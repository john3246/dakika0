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
      ADD COLUMN IF NOT EXISTS package_weight_kg NUMERIC(10, 2);
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
