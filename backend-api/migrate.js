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
      ADD COLUMN IF NOT EXISTS role VARCHAR(20) NOT NULL DEFAULT 'user',
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
      DROP TABLE IF EXISTS orders CASCADE;
      CREATE TABLE orders (
        id UUID PRIMARY KEY,
        creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        courier_id UUID REFERENCES users(id) ON DELETE SET NULL,
        status VARCHAR(20) DEFAULT 'pending',
        pickup_latitude NUMERIC,
        pickup_longitude NUMERIC,
        dropoff_latitude NUMERIC,
        dropoff_longitude NUMERIC,
        pickup_address TEXT,
        dropoff_address TEXT,
        distance_km NUMERIC,
        total_price NUMERIC,
        qr_code_secure_string TEXT UNIQUE,
        handoff_estimated_time TIMESTAMP,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
    `);

    await db.query(`
      CREATE TABLE IF NOT EXISTS courier_profiles (
        user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        is_verified BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
    console.log('Migration successful: Columns and constraints added/verified.');

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
  } catch (error) {
    console.error('Migration failed:', error.message);
  }
  process.exit(0);
}

migrate();
