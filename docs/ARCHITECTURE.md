# SIM Card Transaction Monitor - Architecture Design

## System Overview

The SIM Card Transaction Monitor is a three-tier application designed to provide secure transaction monitoring, authorization controls, and subscription management for SIM card agents in Zambia.

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Mobile App                        │
│  (User Auth, SIM Card Mgmt, Transaction Upload/View)        │
└──────────────────────┬──────────────────────────────────────┘
                       │ REST API / HTTPS
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                   Node.js Backend (Express)                  │
│  ┌──────────────┬──────────────┬──────────────────────────┐ │
│  │ Auth Routes  │ User Routes  │ Transaction Routes       │ │
│  ├──────────────┼──────────────┼──────────────────────────┤ │
│  │ SIM Routes   │ Payment      │ Authorization Routes     │ │
│  │ Subscription │ Routes       │ Admin Routes             │ │
│  └──────────────┴──────────────┴──────────────────────────┘ │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           Middleware Layer                           │  │
│  │  (JWT Auth, Error Handling, Logging, Validation)    │  │
│  └──────────────────────────────────────────────────────┘  │
└──────────────────────┬──────────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
    PostgreSQL    SMS Gateway    Payment Gateway
    Database    (Twilio/Africast)  (Pesapal/Flutterwave)
```

## Architecture Layers

### 1. **Presentation Layer (Flutter)**
- User interfaces for authentication, SIM management, transactions
- Local state management using Provider
- Secure storage of JWT tokens
- Real-time notifications

### 2. **API Layer (Node.js/Express)**
- RESTful API endpoints
- JWT-based authentication
- Request validation and sanitization
- Error handling and logging
- Rate limiting and security middleware

### 3. **Business Logic Layer**
- User management
- Subscription lifecycle (free trial, payment, renewal)
- Transaction processing
- Authorization workflows
- Payment processing

### 4. **Data Access Layer**
- PostgreSQL database queries
- Connection pooling
- Database migrations
- Caching layer (Redis optional)

### 5. **External Services**
- SMS Gateway (Twilio/Africastalking)
- Payment Gateway (Pesapal/Flutterwave)
- Telecom APIs (future integration)

## Database Design

### Core Entities

```
users
├── id (PK)
├── email
├── phone
├── password_hash
├── full_name
├── created_at
├── trial_end_date
└── status

sim_cards
├── id (PK)
├── user_id (FK)
├── phone_number
├── provider (Airtel/Zamtel/MTN)
├── is_active
├── created_at
└── deleted_at

transactions
├── id (PK)
├── sim_card_id (FK)
├── amount
├── type (withdrawal/topup/other)
├── date
├── description
├── requires_auth
└── status

withdrawal_limits
├── id (PK)
├── sim_card_id (FK)
├── daily_limit
├── monthly_limit
└── updated_at

authorizations
├── id (PK)
├── transaction_id (FK)
├── user_id (FK)
├── auth_phone
├── otp_code
├── status (pending/approved/rejected)
├── created_at
└── expires_at

subscriptions
├── id (PK)
├── user_id (FK)
├── sim_card_id (FK)
├── start_date
├── end_date
├── is_trial
├── amount (K15)
├── status
└── auto_renew

payments
├── id (PK)
├── subscription_id (FK)
├── amount
├── method (mobile_money/bank)
├── provider (Airtel Money/MTN Money/Bank)
├── transaction_ref
├── status
└── created_at

admin_settings
├── id (PK)
├── payment_account (mobile/bank)
├── auto_response_enabled
├── auto_response_message
└── updated_at
```

## Authentication Flow

```
1. User Registration
   ├─ Validate email & phone
   ├─ Hash password (bcrypt)
   ├─ Create user record
   ├─ Start 7-day trial
   └─ Return JWT token

2. User Login
   ├─ Validate credentials
   ├─ Check trial/subscription status
   ├─ Generate JWT token (24h expiry)
   └─ Return token + user data

3. Token Refresh
   ├─ Validate refresh token
   └─ Issue new access token
```

## Authorization Flow (Transaction Exceeding Limit)

```
1. Transaction Upload
   ├─ Validate amount vs withdrawal_limit
   ├─ If exceeds → Create authorization request
   │  ├─ Generate OTP code
   │  ├─ Send SMS to auth_phone
   │  ├─ Store in authorizations table
   │  └─ Mark transaction as pending_auth
   └─ If within limit → Mark as approved

2. SMS Notification
   ├─ Send SMS: "OTP: XXXXX to approve transaction of K{amount}"
   └─ OTP valid for 10 minutes

3. User Authorization
   ├─ Enter OTP in app
   ├─ Validate OTP & expiry
   ├─ Update authorization status
   ├─ Mark transaction as approved
   └─ Send confirmation SMS
```

## Subscription & Payment Flow

```
1. Registration
   ├─ 7-day free trial starts
   └─ No payment required

2. Trial End
   ├─ Notify user 1 day before
   ├─ Offer subscription (K15/month per SIM)
   └─ Mark as trial_ended

3. Payment Processing
   ├─ User selects payment method
   ├─ Mobile Money: Generate payment link
   ├─ Bank: Display account details
   ├─ Verify payment
   ├─ Create subscription record
   ├─ Grant access
   └─ Send confirmation SMS

4. Auto-Renewal
   ├─ Check subscription expiry daily
   ├─ Send renewal reminder 3 days before
   ├─ Auto-renew if payment method on file
   └─ Suspend access if renewal fails
```

## Security Measures

### 1. Authentication
- JWT with 24-hour expiry
- Refresh tokens stored securely
- Bcrypt password hashing

### 2. Data Protection
- HTTPS/TLS for all communications
- Sensitive data encryption at rest
- PII not logged

### 3. API Security
- Rate limiting (100 req/min per user)
- CORS configuration
- SQL injection prevention (parameterized queries)
- XSS protection

### 4. Authorization
- Role-based access control (RBAC)
- User: Can only see own data
- Admin: Full access to dashboard

### 5. OTP Security
- 6-digit OTP generated
- 10-minute expiry
- Max 3 attempts before lock

## Deployment Architecture

```
┌──────────────────────────────────────────┐
│         GitHub Actions CI/CD             │
│    ┌─────────────────────────────────┐  │
│    │ Automated Testing & Build       │  │
│    │ Docker Image Creation           │  │
│    │ Push to Registry                │  │
│    └─────────────────────────────────┘  │
└────────────────┬─────────────────────────┘
                 ▼
        ┌────────────────────┐
        │  Docker Registry   │
        │  (DockerHub/ECR)   │
        └────────────────┬───┘
                         ▼
    ┌────────────────────────────────┐
    │    Production Environment      │
    │  (AWS/DigitalOcean/Railway)    │
    │  ┌──────────────────────────┐  │
    │  │ Backend API Container    │  │
    │  │ PostgreSQL Container     │  │
    │  │ Redis Cache (optional)   │  │
    │  └──────────────────────────┘  │
    └────────────────────────────────┘
```

## API Endpoints Summary

### Authentication
- `POST /api/auth/register` - Register new user
- `POST /api/auth/login` - Login user
- `POST /api/auth/refresh` - Refresh JWT token
- `POST /api/auth/logout` - Logout user

### User Management
- `GET /api/users/profile` - Get user profile
- `PUT /api/users/profile` - Update profile
- `POST /api/users/verify-phone` - Verify phone number

### SIM Card Management
- `POST /api/simcards` - Add new SIM card
- `GET /api/simcards` - List user's SIM cards
- `DELETE /api/simcards/:id` - Delete SIM card
- `PUT /api/simcards/:id/limit` - Set withdrawal limit

### Transactions
- `POST /api/transactions/upload` - Upload transactions
- `GET /api/transactions` - Get transactions (filtered)
- `GET /api/transactions/:id` - Get transaction details
- `GET /api/transactions/simcard/:simcardId` - Get SIM transactions

### Authorization
- `POST /api/authorizations/request` - Request authorization
- `POST /api/authorizations/:id/approve` - Approve with OTP
- `GET /api/authorizations/pending` - Get pending authorizations

### Subscriptions
- `GET /api/subscriptions` - Get subscription status
- `POST /api/subscriptions/payment` - Process payment
- `GET /api/subscriptions/history` - Payment history

### Admin
- `GET /api/admin/users` - List all users
- `GET /api/admin/users/:id` - User details
- `GET /api/admin/subscriptions` - Subscription records
- `PUT /api/admin/settings` - Update app settings
- `GET /api/admin/dashboard` - Dashboard metrics

## Performance Considerations

1. **Database Indexing**
   - Index on `user_id`, `sim_card_id`
   - Index on transaction dates
   - Composite indexes for common queries

2. **Caching**
   - Cache user session data
   - Cache subscription status (5-minute TTL)
   - Cache frequently accessed settings

3. **Pagination**
   - Implement cursor-based pagination
   - Default limit: 20 items, max: 100

4. **Query Optimization**
   - Use JOINs efficiently
   - Limit N+1 queries
   - Profile slow queries

## Monitoring & Logging

1. **Application Logging**
   - Log all API requests/responses
   - Log authentication attempts
   - Log payment transactions

2. **Error Tracking**
   - Sentry for exception tracking
   - Alert on critical errors

3. **Performance Monitoring**
   - Monitor API response times
   - Track database query performance
   - Alert on high CPU/memory usage

## Future Enhancements

1. Real-time transaction sync via Telecom APIs
2. Machine learning for fraud detection
3. Advanced reporting and analytics
4. Multi-language support
5. Two-factor authentication
6. WhatsApp notifications
7. Mobile money auto-debit for subscriptions
