CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enum for verification status
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

-- Drop old tables and types if we are resetting the schema
DROP TABLE IF EXISTS tracking_logs CASCADE;
DROP TABLE IF EXISTS order_reviews CASCADE;
DROP TABLE IF EXISTS ratings CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS courier_profiles CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TYPE IF EXISTS user_role CASCADE;
DROP TYPE IF EXISTS vehicle_type CASCADE;

CREATE TABLE users (
    id                UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
    name              VARCHAR(255)    NOT NULL,
    email             VARCHAR(255)    UNIQUE NOT NULL,
    phone             VARCHAR(50)     UNIQUE NOT NULL,
    password_hash     TEXT            NOT NULL,
    
    -- New unified fields
    courier_status    verification_status NOT NULL DEFAULT 'unverified',
    id_document_url   TEXT,
    selfie_url        TEXT,
    is_fully_verified BOOLEAN         NOT NULL DEFAULT FALSE,
    
    -- NIDA & Vehicle Verification
    nida_number       VARCHAR(20)     UNIQUE,
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
    
    created_at        TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE orders (
    id                  UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id         UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    courier_id          UUID            REFERENCES users(id) ON DELETE SET NULL,
    status              order_status    NOT NULL DEFAULT 'PENDING',
    pickup_address      TEXT            NOT NULL,
    pickup_latitude     DOUBLE PRECISION NOT NULL,
    pickup_longitude    DOUBLE PRECISION NOT NULL,
    dropoff_address     TEXT            NOT NULL,
    dropoff_latitude    DOUBLE PRECISION NOT NULL,
    dropoff_longitude   DOUBLE PRECISION NOT NULL,
    item_type           VARCHAR(100)    NOT NULL,
    item_description    TEXT,
    package_weight_kg   NUMERIC(6, 2)   CHECK (package_weight_kg > 0),
    
    -- Pricing
    estimated_price     NUMERIC(10, 2)  NOT NULL CHECK (estimated_price >= 0),
    suggested_price     NUMERIC(10, 2)  CHECK (suggested_price >= 0),
    
    cancel_reason       TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    accepted_at         TIMESTAMPTZ,
    picked_up_at        TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ
);

CREATE TABLE tracking_logs (
    id              BIGSERIAL       PRIMARY KEY,
    order_id        UUID            NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    latitude        DOUBLE PRECISION NOT NULL,
    longitude       DOUBLE PRECISION NOT NULL,
    recorded_at     TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- Two-way rating system
CREATE TABLE ratings (
    rating_id       UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id        UUID            NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    reviewer_id     UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reviewee_id     UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rating_type     VARCHAR(20)     NOT NULL CHECK (rating_type IN ('sender', 'courier')),
    score           SMALLINT        NOT NULL CHECK (score >= 1 AND score <= 5),
    comment         TEXT,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_rating_per_order UNIQUE (order_id, reviewer_id, reviewee_id)
);

CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_phone ON users (phone);
CREATE INDEX idx_users_is_verified ON users (is_fully_verified) WHERE is_fully_verified = TRUE;

-- Geospatial indexing for user location
CREATE INDEX idx_users_location ON users (current_latitude, current_longitude);

CREATE INDEX idx_orders_customer_id ON orders (customer_id);
CREATE INDEX idx_orders_courier_id ON orders (courier_id);
CREATE INDEX idx_orders_status ON orders (status);

CREATE INDEX idx_tracking_logs_order_id ON tracking_logs (order_id);

CREATE OR REPLACE FUNCTION fn_touch_updated_at() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- Two-way rating recomputation
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

CREATE TRIGGER trg_recompute_ratings AFTER INSERT OR DELETE ON ratings FOR EACH ROW EXECUTE FUNCTION fn_recompute_ratings();
