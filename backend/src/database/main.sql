CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enums
DO $$ BEGIN
    CREATE TYPE app_role AS ENUM ('customer', 'rider', 'admin', 'support');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE verification_status AS ENUM ('unverified', 'pending', 'verified');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE order_status AS ENUM (
        'PENDING',
        'ACCEPTED',
        'PICKED_UP',
        'DELIVERED',
        'CANCELLED'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 1. Users Table (Merged)
CREATE TABLE IF NOT EXISTS users (
    id                UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    name              VARCHAR(255)    NOT NULL,
    email             VARCHAR(255)    UNIQUE NOT NULL,
    phone             VARCHAR(50)     UNIQUE NOT NULL,
    password_hash     TEXT            NOT NULL,
    
    -- Role & Verification Status
    role              VARCHAR(20)     NOT NULL DEFAULT 'CUSTOMER' CHECK (role IN ('CUSTOMER', 'COURIER', 'ADMIN', 'SUPPORT')),
    courier_status    verification_status NOT NULL DEFAULT 'unverified',
    id_document_url   TEXT,
    selfie_url        TEXT,
    is_fully_verified BOOLEAN         NOT NULL DEFAULT FALSE,
    
    -- NIDA & Vehicle Verification
    nida_number       VARCHAR(20)     UNIQUE,
    nida_document_url TEXT,
    vehicle_type      VARCHAR(20)     CHECK (vehicle_type IN ('car', 'bike')),
    vehicle_registration_number VARCHAR(30) UNIQUE,
    
    profile_image_url TEXT,
    device_token      TEXT,
    
    -- Geospatial
    current_latitude  DOUBLE PRECISION,
    current_longitude DOUBLE PRECISION,
    
    -- Ratings
    sender_rating     NUMERIC(3, 2)   NOT NULL DEFAULT 5.00 CHECK (sender_rating >= 1.00 AND sender_rating <= 5.00),
    courier_rating    NUMERIC(3, 2)   NOT NULL DEFAULT 5.00 CHECK (courier_rating >= 1.00 AND courier_rating <= 5.00),
    
    -- Additional fields from main.sql
    status            VARCHAR(20)     DEFAULT 'active' CHECK (status IN ('active','suspended','deleted','pending_verification')),
    email_verified    BOOLEAN         DEFAULT FALSE,
    phone_verified    BOOLEAN         DEFAULT FALSE,
    is_active         BOOLEAN         NOT NULL DEFAULT TRUE,
    last_login        TIMESTAMP,
    
    created_at        TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    
    CONSTRAINT users_contact_check CHECK (phone IS NOT NULL OR email IS NOT NULL)
);

-- 2. User Profiles Table (from main.sql)
CREATE TABLE IF NOT EXISTS user_profiles (
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

-- 3. KYC Records Table (from main.sql)
CREATE TABLE IF NOT EXISTS kyc_records (
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

-- 4. KYC Documents Table (from main.sql)
CREATE TABLE IF NOT EXISTS kyc_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,

    doc_type VARCHAR(50),
    file_url TEXT NOT NULL,
    file_hash TEXT,

    status VARCHAR(20) DEFAULT 'pending',
    uploaded_at TIMESTAMP DEFAULT now()
);

-- 5. Login Attempts Table (from main.sql)
CREATE TABLE IF NOT EXISTS login_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone VARCHAR(20),
    ip_address INET,
    success BOOLEAN,
    attempted_at TIMESTAMP DEFAULT now()
);

-- 6. Refresh Tokens Table (from main.sql)
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,

    token_hash TEXT NOT NULL,
    user_agent TEXT,
    ip_address INET,

    expires_at TIMESTAMP NOT NULL,
    revoked BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP DEFAULT now()
);

-- 7. Addresses Table (from main.sql)
CREATE TABLE IF NOT EXISTS addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),

    label VARCHAR(50),
    address TEXT,

    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,

    is_default BOOLEAN DEFAULT FALSE
);

-- 8. Courier Profiles (from schema.sql / migrate.js)
CREATE TABLE IF NOT EXISTS courier_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 9. Orders Table (from schema.sql / migrate.js, including suggested_price)
CREATE TABLE IF NOT EXISTS orders (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id         UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    courier_id          UUID            REFERENCES users(id) ON DELETE SET NULL,
    status              VARCHAR(20)     NOT NULL DEFAULT 'pending',
    
    pickup_address      TEXT            NOT NULL,
    pickup_latitude     DOUBLE PRECISION NOT NULL,
    pickup_longitude    DOUBLE PRECISION NOT NULL,
    
    dropoff_address     TEXT            NOT NULL,
    dropoff_latitude    DOUBLE PRECISION NOT NULL,
    dropoff_longitude   DOUBLE PRECISION NOT NULL,
    
    distance_km         NUMERIC(10, 2)  NOT NULL,
    total_price         NUMERIC(10, 2)  NOT NULL,
    qr_code_secure_string VARCHAR(255)  UNIQUE NOT NULL,
    handoff_estimated_time TIMESTAMP,
    
    item_type           VARCHAR(255)    NOT NULL DEFAULT 'Package',
    item_description    TEXT,
    package_weight_kg   NUMERIC(10, 2)  CHECK (package_weight_kg > 0),
    suggested_price     NUMERIC(10, 2)  CHECK (suggested_price >= 0),
    
    cancel_reason       TEXT,
    created_at          TIMESTAMP       NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP       NOT NULL DEFAULT NOW(),
    accepted_at         TIMESTAMP,
    picked_up_at        TIMESTAMP,
    completed_at        TIMESTAMP
);

-- 10. Parcels Table (from main.sql)
CREATE TABLE IF NOT EXISTS parcels (
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

-- 11. Parcel Assignments (from main.sql)
CREATE TABLE IF NOT EXISTS parcel_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    parcel_id UUID UNIQUE REFERENCES parcels(id) ON DELETE CASCADE,
    rider_id UUID REFERENCES users(id),

    assigned_by UUID REFERENCES users(id),

    assigned_at TIMESTAMP DEFAULT now(),
    accepted_at TIMESTAMP,
    completed_at TIMESTAMP
);

-- 12. Parcel Tracking (from main.sql)
CREATE TABLE IF NOT EXISTS parcel_tracking (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    parcel_id UUID REFERENCES parcels(id),

    status VARCHAR(50),

    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    accuracy_meters INT,

    recorded_by UUID REFERENCES users(id),

    recorded_at TIMESTAMP DEFAULT now()
);

-- 13. Tracking Logs (from schema.sql)
CREATE TABLE IF NOT EXISTS tracking_logs (
    id              BIGSERIAL       PRIMARY KEY,
    order_id        UUID            NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    latitude        DOUBLE PRECISION NOT NULL,
    longitude       DOUBLE PRECISION NOT NULL,
    recorded_at     TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- 14. Rider Profiles (from main.sql)
CREATE TABLE IF NOT EXISTS rider_profiles (
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

-- 15. Wallets Table (from main.sql)
CREATE TABLE IF NOT EXISTS wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE REFERENCES users(id),

    balance NUMERIC(12,2) DEFAULT 0 CHECK (balance >= 0),
    currency VARCHAR(10) DEFAULT 'TZS',

    updated_at TIMESTAMP DEFAULT now()
);

-- 16. Wallet Ledger (from main.sql)
CREATE TABLE IF NOT EXISTS wallet_ledger (
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

-- 17. Ratings Table (Merged two-way ratings)
CREATE TABLE IF NOT EXISTS ratings (
    rating_id       UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id        UUID            REFERENCES orders(id) ON DELETE CASCADE,
    parcel_id       UUID            REFERENCES parcels(id) ON DELETE CASCADE,
    reviewer_id     UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reviewee_id     UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rating_type     VARCHAR(20)     NOT NULL CHECK (rating_type IN ('sender', 'courier')),
    score           SMALLINT        NOT NULL CHECK (score >= 1 AND score <= 5),
    comment         TEXT,
    is_flagged      BOOLEAN         DEFAULT FALSE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_rating_per_order UNIQUE (order_id, reviewer_id, reviewee_id)
);

-- 18. Notifications (from main.sql)
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),

    title TEXT,
    body TEXT,

    is_read BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP DEFAULT now()
);

-- 19. Audit Logs (from main.sql)
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID,
    action TEXT,
    entity TEXT,
    entity_id UUID,

    ip_address INET,
    metadata JSONB,

    created_at TIMESTAMP DEFAULT now()
);

-- Indices
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
CREATE INDEX IF NOT EXISTS idx_users_phone ON users (phone);
CREATE INDEX IF NOT EXISTS idx_users_is_verified ON users (is_fully_verified) WHERE is_fully_verified = TRUE;
CREATE INDEX IF NOT EXISTS idx_users_location ON users (current_latitude, current_longitude);

CREATE INDEX IF NOT EXISTS idx_orders_creator_id ON orders (creator_id);
CREATE INDEX IF NOT EXISTS idx_orders_courier_id ON orders (courier_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);

CREATE INDEX IF NOT EXISTS idx_tracking_logs_order_id ON tracking_logs (order_id);
CREATE INDEX IF NOT EXISTS idx_parcels_status ON parcels(status);
CREATE INDEX IF NOT EXISTS idx_tracking_parcel ON parcel_tracking(parcel_id);
CREATE INDEX IF NOT EXISTS idx_wallet_wallet_id ON wallet_ledger(wallet_id);
CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_ratings_rated_user ON ratings(reviewee_id);

-- Common trigger helper function
CREATE OR REPLACE FUNCTION fn_touch_updated_at() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- Triggers
DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- Recompute ratings logic
CREATE OR REPLACE FUNCTION fn_recompute_ratings() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_reviewee_id UUID;
    v_type        VARCHAR(20);
    v_avg         NUMERIC(3, 2);
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_reviewee_id := OLD.reviewee_id;
        v_type := OLD.rating_type;
    ELSE
        v_reviewee_id := NEW.reviewee_id;
        v_type := NEW.rating_type;
    END IF;

    SELECT COALESCE(AVG(score)::NUMERIC(3,2), 5.00) INTO v_avg 
    FROM ratings 
    WHERE reviewee_id = v_reviewee_id AND rating_type = v_type;

    IF v_type = 'sender' THEN
        UPDATE users SET sender_rating = v_avg, updated_at = NOW() WHERE id = v_reviewee_id;
    ELSIF v_type = 'courier' THEN
        UPDATE users SET courier_rating = v_avg, updated_at = NOW() WHERE id = v_reviewee_id;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_recompute_ratings ON ratings;
CREATE TRIGGER trg_recompute_ratings AFTER INSERT OR DELETE ON ratings FOR EACH ROW EXECUTE FUNCTION fn_recompute_ratings();