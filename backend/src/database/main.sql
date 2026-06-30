CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE TYPE app_role AS ENUM ('customer', 'rider', 'admin', 'support');
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone VARCHAR(20) UNIQUE,
    email VARCHAR(255) UNIQUE,
    password_hash TEXT NOT NULL,
    role app_role NOT NULL DEFAULT 'customer',

    status VARCHAR(20) DEFAULT 'active'
        CHECK (status IN ('active','suspended','deleted','pending_verification')),

    email_verified BOOLEAN DEFAULT FALSE,
    phone_verified BOOLEAN DEFAULT FALSE,

    last_login TIMESTAMP,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now(),

    CONSTRAINT users_contact_check CHECK (phone IS NOT NULL OR email IS NOT NULL)
);

CREATE TABLE user_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,

    first_name VARCHAR(100),
    last_name VARCHAR(100),
    profile_photo TEXT,
    date_of_birth DATE,
    gender VARCHAR(10),
    language VARCHAR(10) DEFAULT 'sw',

    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);


CREATE TABLE kyc_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,

    nida_number_encrypted TEXT UNIQUE NOT NULL,
    first_name_encrypted TEXT,
    last_name_encrypted TEXT,
    dob_encrypted TEXT,

    verification_status VARCHAR(20) DEFAULT 'pending'
        CHECK (verification_status IN ('pending','verified','rejected')),

    verified_at TIMESTAMP,
    verification_provider VARCHAR(50) DEFAULT 'NIDA',

    raw_response JSONB,

    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

CREATE TABLE kyc_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,

    doc_type VARCHAR(50),
    file_url TEXT NOT NULL,
    file_hash TEXT,

    status VARCHAR(20) DEFAULT 'pending',
    uploaded_at TIMESTAMP DEFAULT now()
);


CREATE TABLE login_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone VARCHAR(20),
    ip_address INET,
    success BOOLEAN,
    attempted_at TIMESTAMP DEFAULT now()
);


CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,

    token_hash TEXT NOT NULL,
    user_agent TEXT,
    ip_address INET,

    expires_at TIMESTAMP NOT NULL,
    revoked BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP DEFAULT now()
);


CREATE TABLE addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),

    label VARCHAR(50),
    address TEXT,

    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,

    is_default BOOLEAN DEFAULT FALSE
);


CREATE TABLE parcels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    sender_id UUID REFERENCES users(id),

    receiver_name TEXT,
    receiver_phone TEXT,

    pickup_address TEXT,
    pickup_lat DOUBLE PRECISION,
    pickup_lng DOUBLE PRECISION,

    dropoff_address TEXT,
    dropoff_lat DOUBLE PRECISION,
    dropoff_lng DOUBLE PRECISION,

    description TEXT,
    declared_value NUMERIC(12,2),

    status VARCHAR(30) DEFAULT 'created'
        CHECK (status IN (
            'created','matched','picked_up',
            'in_transit','delivered','cancelled','failed'
        )),

    is_insured BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);


CREATE TABLE parcel_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    parcel_id UUID UNIQUE REFERENCES parcels(id) ON DELETE CASCADE,
    rider_id UUID REFERENCES users(id),

    assigned_by UUID REFERENCES users(id),

    assigned_at TIMESTAMP DEFAULT now(),
    accepted_at TIMESTAMP,
    completed_at TIMESTAMP
);


CREATE TABLE parcel_tracking (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    parcel_id UUID REFERENCES parcels(id),

    status VARCHAR(50),

    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    accuracy_meters INT,

    recorded_by UUID REFERENCES users(id),

    recorded_at TIMESTAMP DEFAULT now()
);


CREATE TABLE rider_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE REFERENCES users(id),

    nida_number_encrypted TEXT,
    vehicle_type VARCHAR(30),
    plate_number_encrypted TEXT,

    is_online BOOLEAN DEFAULT FALSE,

    current_lat DOUBLE PRECISION,
    current_lng DOUBLE PRECISION,

    trust_score NUMERIC(3,2) DEFAULT 0,

    created_at TIMESTAMP DEFAULT now()
);


CREATE TABLE wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE REFERENCES users(id),

    balance NUMERIC(12,2) DEFAULT 0 CHECK (balance >= 0),
    currency VARCHAR(10) DEFAULT 'TZS',

    updated_at TIMESTAMP DEFAULT now()
);


CREATE TABLE wallet_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    wallet_id UUID REFERENCES wallets(id),

    transaction_type VARCHAR(20)
        CHECK (transaction_type IN ('credit','debit','hold','release')),

    amount NUMERIC(12,2) NOT NULL,

    reference_type VARCHAR(50),
    reference_id UUID,

    provider VARCHAR(30),
    provider_txn_id TEXT,

    balance_after NUMERIC(12,2),

    created_at TIMESTAMP DEFAULT now()
);


CREATE TABLE ratings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    parcel_id UUID REFERENCES parcels(id),

    rater_id UUID REFERENCES users(id),
    rated_user_id UUID REFERENCES users(id),

    score INT CHECK (score BETWEEN 1 AND 5),
    comment TEXT,

    is_flagged BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP DEFAULT now()
);


CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),

    title TEXT,
    body TEXT,

    is_read BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID,
    action TEXT,
    entity TEXT,
    entity_id UUID,

    ip_address INET,
    metadata JSONB,

    created_at TIMESTAMP DEFAULT now()
);

CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_parcels_status ON parcels(status);
CREATE INDEX idx_tracking_parcel ON parcel_tracking(parcel_id);
CREATE INDEX idx_wallet_wallet_id ON wallet_ledger(wallet_id);
CREATE INDEX idx_audit_user ON audit_logs(user_id);
CREATE INDEX idx_ratings_rated_user ON ratings(rated_user_id);