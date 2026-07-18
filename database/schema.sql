# Database Schema - SIM Card Transaction Monitor

## PostgreSQL Schema

```sql
-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    national_id VARCHAR(50),
    profile_image_url TEXT,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted')),
    is_admin BOOLEAN DEFAULT FALSE,
    trial_end_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

-- SIM Cards table
CREATE TABLE sim_cards (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    phone_number VARCHAR(20) NOT NULL,
    provider VARCHAR(50) NOT NULL CHECK (provider IN ('Airtel', 'Zamtel', 'MTN')),
    owner_name VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    UNIQUE(user_id, phone_number)
);

-- Withdrawal Limits table
CREATE TABLE withdrawal_limits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sim_card_id UUID NOT NULL REFERENCES sim_cards(id) ON DELETE CASCADE,
    daily_limit DECIMAL(15, 2) NOT NULL DEFAULT 5000.00,
    monthly_limit DECIMAL(15, 2) NOT NULL DEFAULT 50000.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(sim_card_id)
);

-- Transactions table
CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sim_card_id UUID NOT NULL REFERENCES sim_cards(id) ON DELETE CASCADE,
    amount DECIMAL(15, 2) NOT NULL,
    transaction_type VARCHAR(50) NOT NULL CHECK (transaction_type IN ('withdrawal', 'topup', 'transfer', 'payment', 'other')),
    description TEXT,
    transaction_date DATE NOT NULL,
    transaction_time TIME,
    balance_before DECIMAL(15, 2),
    balance_after DECIMAL(15, 2),
    requires_authorization BOOLEAN DEFAULT FALSE,
    authorization_status VARCHAR(20) DEFAULT 'none' CHECK (authorization_status IN ('none', 'pending', 'approved', 'rejected')),
    status VARCHAR(20) DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_sim_card_date (sim_card_id, transaction_date DESC),
    INDEX idx_requires_auth (requires_authorization, authorization_status)
);

-- Authorizations table
CREATE TABLE authorizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    sim_card_id UUID NOT NULL REFERENCES sim_cards(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    authorization_phone VARCHAR(20) NOT NULL,
    otp_code VARCHAR(10),
    otp_attempts INT DEFAULT 0,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    approved_at TIMESTAMP,
    approved_by UUID REFERENCES users(id),
    INDEX idx_status_expires (status, expires_at)
);

-- Subscriptions table
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sim_card_id UUID NOT NULL REFERENCES sim_cards(id) ON DELETE CASCADE,
    subscription_type VARCHAR(50) DEFAULT 'standard' CHECK (subscription_type IN ('trial', 'standard', 'premium')),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    is_trial BOOLEAN DEFAULT FALSE,
    amount DECIMAL(15, 2) NOT NULL DEFAULT 15.00,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'expired', 'cancelled', 'suspended')),
    auto_renew BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_end_date (user_id, end_date),
    INDEX idx_status_sim_card (status, sim_card_id)
);

-- Payments table
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount DECIMAL(15, 2) NOT NULL,
    payment_method VARCHAR(50) NOT NULL CHECK (payment_method IN ('mobile_money', 'bank_transfer', 'airtel_money', 'mtn_money')),
    provider VARCHAR(50),
    transaction_reference VARCHAR(255) UNIQUE,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'cancelled')),
    payment_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_status (user_id, status),
    INDEX idx_payment_date (payment_date DESC)
);

-- Admin Settings table
CREATE TABLE admin_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    admin_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    payment_account_type VARCHAR(50) NOT NULL CHECK (payment_account_type IN ('mobile_money', 'bank')),
    payment_account_number VARCHAR(50) NOT NULL,
    payment_provider VARCHAR(50),
    auto_response_enabled BOOLEAN DEFAULT FALSE,
    auto_response_message TEXT,
    trial_days INT DEFAULT 7,
    subscription_amount DECIMAL(15, 2) DEFAULT 15.00,
    max_failed_otp_attempts INT DEFAULT 3,
    otp_expiry_minutes INT DEFAULT 10,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(admin_user_id)
);

-- SMS Logs table (for auditing)
CREATE TABLE sms_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    phone_number VARCHAR(20) NOT NULL,
    message TEXT NOT NULL,
    sms_type VARCHAR(50) NOT NULL CHECK (sms_type IN ('otp', 'authorization', 'payment_confirmation', 'subscription_reminder', 'other')),
    status VARCHAR(20) DEFAULT 'sent' CHECK (status IN ('sent', 'failed', 'pending')),
    external_id VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_date (user_id, created_at DESC)
);

-- Audit Logs table
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(255) NOT NULL,
    entity_type VARCHAR(50),
    entity_id UUID,
    changes JSONB,
    ip_address VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_date (user_id, created_at DESC),
    INDEX idx_entity (entity_type, entity_id)
);

-- Create Indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_users_trial ON users(trial_end_date);
CREATE INDEX idx_sim_cards_user ON sim_cards(user_id);
CREATE INDEX idx_sim_cards_phone ON sim_cards(phone_number);
CREATE INDEX idx_transactions_sim_card ON transactions(sim_card_id);
CREATE INDEX idx_authorizations_user ON authorizations(user_id);
CREATE INDEX idx_subscriptions_user ON subscriptions(user_id);
CREATE INDEX idx_payments_user ON payments(user_id);

-- Create Views
CREATE VIEW user_active_subscriptions AS
SELECT 
    u.id as user_id,
    u.email,
    u.phone,
    COUNT(s.id) as active_sim_cards,
    SUM(s.amount) as total_monthly_cost
FROM users u
LEFT JOIN subscriptions s ON u.id = s.user_id AND s.status = 'active'
LEFT JOIN sim_cards sc ON s.sim_card_id = sc.id AND sc.is_active = TRUE
WHERE u.status = 'active' AND u.deleted_at IS NULL
GROUP BY u.id;

CREATE VIEW pending_authorizations AS
SELECT 
    a.id,
    a.transaction_id,
    t.amount,
    s.phone_number,
    u.email,
    u.phone,
    a.authorization_phone,
    a.created_at,
    a.expires_at
FROM authorizations a
JOIN transactions t ON a.transaction_id = t.id
JOIN sim_cards s ON a.sim_card_id = s.id
JOIN users u ON a.user_id = u.id
WHERE a.status = 'pending' AND a.expires_at > CURRENT_TIMESTAMP;

CREATE VIEW subscription_expiring_soon AS
SELECT 
    s.id as subscription_id,
    u.id as user_id,
    u.email,
    u.phone,
    s.sim_card_id,
    s.end_date,
    (s.end_date - CURRENT_DATE) as days_until_expiry
FROM subscriptions s
JOIN users u ON s.user_id = u.id
WHERE s.status = 'active' 
AND s.end_date <= (CURRENT_DATE + INTERVAL '3 days')
AND s.end_date > CURRENT_DATE;

-- Triggers for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sim_cards_updated_at BEFORE UPDATE ON sim_cards
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_transactions_updated_at BEFORE UPDATE ON transactions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscriptions_updated_at BEFORE UPDATE ON subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_payments_updated_at BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

## Key Constraints & Relationships

### User Management
- Each user can have multiple SIM cards
- Email and phone must be unique per user
- Trial period stored with user record

### SIM Card Management
- SIM cards linked to users
- One withdrawal limit per SIM card
- Provider must be one of three: Airtel, Zamtel, MTN

### Transactions
- Transactions linked to SIM cards
- Automatic authorization check based on limits
- Status tracking for audit trail

### Authorization System
- Authorization requests created when transaction exceeds limit
- OTP sent to designated phone number
- Tracks approval/rejection with timestamps
- Auto-expires after configured time

### Subscription Lifecycle
1. User registers → Trial subscription created (7 days)
2. Trial ends → Status becomes 'expired'
3. User pays → New subscription created with status 'active'
4. Subscription expires → Status becomes 'expired'
5. Auto-renew enabled → New subscription auto-created

### Payment Tracking
- Links to subscriptions for lifecycle tracking
- Reference stored for reconciliation
- Multiple payment methods supported

## Security Considerations

1. **Sensitive Data**
   - Passwords never stored in plain text (hashed)
   - OTP codes hashed before storage
   - API keys/secrets stored in environment variables

2. **Audit Trail**
   - All significant actions logged in audit_logs
   - SIM card transactions immutable after creation
   - Authorization decisions tracked with user info

3. **Data Retention**
   - Soft deletes using deleted_at column
   - SMS logs kept for 90 days
   - Audit logs kept for 1 year

## Performance Optimization

1. **Indexes on**
   - Foreign keys
   - Frequently searched fields (email, phone)
   - Date ranges for reporting

2. **Composite Indexes**
   - (sim_card_id, transaction_date) for transaction queries
   - (user_id, end_date) for subscription lookups

3. **Views for Common Queries**
   - Pending authorizations
   - Expiring subscriptions
   - Active user subscriptions

## Database Maintenance

### Regular Tasks
- Analyze table statistics monthly
- Vacuum tables weekly
- Archive old SMS logs quarterly
- Review and optimize slow queries

### Backup Strategy
- Daily full backups
- Weekly differential backups
- Test restore procedures monthly
