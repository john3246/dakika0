const db = require('./db');
const bcrypt = require('bcrypt');

async function migrate() {
  try {
    await db.query(`
      ALTER TABLE users 
      ADD COLUMN IF NOT EXISTS nida_number VARCHAR(20) UNIQUE,
      ADD COLUMN IF NOT EXISTS nida_document_url TEXT,
      ADD COLUMN IF NOT EXISTS vehicle_type VARCHAR(20) CHECK (vehicle_type IN ('car', 'bike')),
      ADD COLUMN IF NOT EXISTS vehicle_registration_number VARCHAR(30) UNIQUE,
      ADD COLUMN IF NOT EXISTS role VARCHAR(20) NOT NULL DEFAULT 'CUSTOMER',
      ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;
    `);

    await db.query(`
      ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
      UPDATE users SET role = 'ADMIN' WHERE role IN ('admin', 'super_admin');
      UPDATE users SET role = 'CUSTOMER' WHERE role IN ('user', 'customer');
      UPDATE users SET role = 'COURIER' WHERE role = 'courier';
      ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('CUSTOMER', 'COURIER', 'ADMIN'));
    `);

    await db.query(`
      CREATE TABLE IF NOT EXISTS orders (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          courier_id UUID REFERENCES users(id) ON DELETE SET NULL,
          status VARCHAR(20) DEFAULT 'pending',
          pickup_latitude NUMERIC(10, 7) NOT NULL,
          pickup_longitude NUMERIC(10, 7) NOT NULL,
          dropoff_latitude NUMERIC(10, 7) NOT NULL,
          dropoff_longitude NUMERIC(10, 7) NOT NULL,
          pickup_address TEXT NOT NULL,
          dropoff_address TEXT NOT NULL,
          distance_km NUMERIC(10, 2) NOT NULL,
          total_price NUMERIC(10, 2) NOT NULL,
          qr_code_secure_string VARCHAR(255) UNIQUE NOT NULL,
          handoff_estimated_time TIMESTAMP,
          item_type VARCHAR(255),
          item_description TEXT,
          package_weight_kg NUMERIC(10, 2),
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
      
      ALTER TABLE orders 
      ADD COLUMN IF NOT EXISTS item_type VARCHAR(255),
      ADD COLUMN IF NOT EXISTS item_description TEXT,
      ADD COLUMN IF NOT EXISTS package_weight_kg NUMERIC(10, 2),
      ADD COLUMN IF NOT EXISTS suggested_price NUMERIC(10, 2) CHECK (suggested_price >= 0),
      ADD COLUMN IF NOT EXISTS escrow_balance NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (escrow_balance >= 0),
      ADD COLUMN IF NOT EXISTS cancel_reason TEXT;
    `);

    // Create all other tables from merged schema if they don't exist
    await db.query(`
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

      CREATE TABLE IF NOT EXISTS kyc_records (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,
          nida_number_encrypted TEXT UNIQUE NOT NULL,
          first_name_encrypted TEXT,
          last_name_encrypted TEXT,
          dob_encrypted TEXT,
          verification_status VARCHAR(20) DEFAULT 'pending' CHECK (verification_status IN ('pending','verified','rejected')),
          verified_at TIMESTAMP,
          verification_provider VARCHAR(50) DEFAULT 'NIDA',
          raw_response JSONB,
          created_at TIMESTAMP DEFAULT now(),
          updated_at TIMESTAMP DEFAULT now()
      );

      CREATE TABLE IF NOT EXISTS kyc_documents (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID REFERENCES users(id) ON DELETE CASCADE,
          doc_type VARCHAR(50),
          file_url TEXT NOT NULL,
          file_hash TEXT,
          status VARCHAR(20) DEFAULT 'pending',
          uploaded_at TIMESTAMP DEFAULT now()
      );

      CREATE TABLE IF NOT EXISTS login_attempts (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          phone VARCHAR(20),
          ip_address INET,
          success BOOLEAN,
          attempted_at TIMESTAMP DEFAULT now()
      );

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

      CREATE TABLE IF NOT EXISTS addresses (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID REFERENCES users(id),
          label VARCHAR(50),
          address TEXT,
          lat DOUBLE PRECISION,
          lng DOUBLE PRECISION,
          is_default BOOLEAN DEFAULT FALSE
      );

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
          status VARCHAR(30) DEFAULT 'created' CHECK (status IN ('created','matched','picked_up','in_transit','delivered','cancelled','failed')),
          is_insured BOOLEAN DEFAULT FALSE,
          created_at TIMESTAMP DEFAULT now(),
          updated_at TIMESTAMP DEFAULT now()
      );

      CREATE TABLE IF NOT EXISTS parcel_assignments (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          parcel_id UUID UNIQUE REFERENCES parcels(id) ON DELETE CASCADE,
          rider_id UUID REFERENCES users(id),
          assigned_by UUID REFERENCES users(id),
          assigned_at TIMESTAMP DEFAULT now(),
          accepted_at TIMESTAMP,
          completed_at TIMESTAMP
      );

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

      CREATE TABLE IF NOT EXISTS wallets (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID UNIQUE REFERENCES users(id),
          balance NUMERIC(12,2) DEFAULT 0 CHECK (balance >= 0),
          currency VARCHAR(10) DEFAULT 'TZS',
          updated_at TIMESTAMP DEFAULT now()
      );

      CREATE TABLE IF NOT EXISTS wallet_ledger (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          wallet_id UUID REFERENCES wallets(id),
          transaction_type VARCHAR(20) CHECK (transaction_type IN ('credit','debit','hold','release')),
          amount NUMERIC(12,2) NOT NULL,
          reference_type VARCHAR(50),
          reference_id UUID,
          provider VARCHAR(30),
          provider_txn_id TEXT,
          balance_after NUMERIC(12,2),
          created_at TIMESTAMP DEFAULT now()
      );

      CREATE TABLE IF NOT EXISTS notifications (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID REFERENCES users(id),
          title TEXT,
          body TEXT,
          is_read BOOLEAN DEFAULT FALSE,
          created_at TIMESTAMP DEFAULT now()
      );

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

      -- Add parcel_id reference to ratings table if it's missing (since ratings was merged)
      ALTER TABLE ratings ADD COLUMN IF NOT EXISTS parcel_id UUID REFERENCES parcels(id) ON DELETE CASCADE;
    `);

    await db.query(`
      CREATE TABLE IF NOT EXISTS courier_profiles (
        user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        is_verified BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);

    console.log('Migration successful: Tables created or verified.');

    const checkAdmin = await db.query("SELECT id FROM users WHERE email = $1", ["admin@dakika0.com"]);
    if (checkAdmin.rows.length === 0) {
      const hash = await bcrypt.hash("admin123", 10);
      await db.query(
        `INSERT INTO users (name, email, phone, password_hash, role, is_active, courier_status, is_fully_verified)
         VALUES ($1, $2, $3, $4, 'ADMIN', true, 'verified', true)`,
        ["System Admin", "admin@dakika0.com", "+255123456789", hash]
      );
      console.log('Admin user seeded: admin@dakika0.com / admin123');
    }

    const checkSuperAdmin = await db.query("SELECT id FROM users WHERE email = $1", ["superadmin@dakika0.com"]);
    if (checkSuperAdmin.rows.length === 0) {
      const hash = await bcrypt.hash("superadmin123", 10);
      await db.query(
        `INSERT INTO users (name, email, phone, password_hash, role, is_active, courier_status, is_fully_verified)
         VALUES ($1, $2, $3, $4, 'ADMIN', true, 'verified', true)`,
        ["Super Admin", "superadmin@dakika0.com", "+255987654321", hash]
      );
      console.log('Super Admin user seeded: superadmin@dakika0.com / superadmin123');
    } else {
      console.log('Super Admin user already exists.');
    }

    process.exit(0);
  } catch (error) {
    console.error('Migration failed:', error.message);
    process.exit(1);
  }
}

migrate();
