const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const db = require('../db');

// ─── Register ────────────────────────────────────────────────────────────────

exports.register = async (req, res) => {
  const {
    name,
    email,
    phone,
    password,
    role = 'CUSTOMER',
    vehicleType,
    vehicleRegistrationNumber,
    nidaNumber,
  } = req.body;

  if (!name || !email || !phone || !password || !role) {
    return res.status(400).json({
      error: 'Bad Request',
      message: 'Name, email, phone, password and role are required',
    });
  }

  const uppercaseRole = role.toUpperCase();
  if (uppercaseRole !== 'CUSTOMER' && uppercaseRole !== 'COURIER') {
    return res.status(400).json({ error: 'Bad Request', message: 'Invalid role provided' });
  }

  if (uppercaseRole === 'COURIER' && (!vehicleType || !vehicleRegistrationNumber)) {
    return res.status(400).json({
      error: 'Bad Request',
      message: 'Couriers must provide vehicle type and registration number',
    });
  }

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    const passwordHash = await bcrypt.hash(password, 10);

    const insertUserQuery = `
      INSERT INTO users 
      (name, email, phone, password_hash, role, courier_status, vehicle_type, vehicle_registration_number, nida_number) 
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) 
      RETURNING id, name, email, phone, courier_status, is_fully_verified, role, is_active, created_at,
                vehicle_type, vehicle_registration_number, nida_number
    `;
    const insertUserParams = [
      name,
      email,
      phone,
      passwordHash,
      uppercaseRole,
      'unverified', // all registrations start unverified
      vehicleType || null,
      vehicleRegistrationNumber || null,
      nidaNumber || null,
    ];

    const userRes = await client.query(insertUserQuery, insertUserParams);
    const user = userRes.rows[0];

    if (uppercaseRole === 'COURIER') {
      const insertProfileQuery = `
        INSERT INTO courier_profiles (user_id, is_verified)
        VALUES ($1, false)
      `;
      await client.query(insertProfileQuery, [user.id]);
    }

    await client.query('COMMIT');

    res.status(201).json({
      message: 'User registered successfully',
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        phone: user.phone,
        courierStatus: user.courier_status,
        isFullyVerified: user.is_fully_verified,
        role: user.role,
        isActive: user.is_active,
        createdAt: user.created_at,
        vehicleType: user.vehicle_type,
        vehicleRegistrationNumber: user.vehicle_registration_number,
        nidaNumber: user.nida_number,
      },
    });
  } catch (error) {
    await client.query('ROLLBACK');
    if (error.code === '23505') {
      return res.status(409).json({
        error: 'Conflict',
        message: 'Email, phone or registration number already exists',
      });
    }
    console.error('Registration error:', error);
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Internal server error during registration',
    });
  } finally {
    client.release();
  }
};

// ─── Login ───────────────────────────────────────────────────────────────────

/**
 * FIX #1 — 7-DAY SESSION LIFESPAN
 *
 * Changed expiresIn from '1d' to '7d' so the Flutter mobile app can remain
 * authenticated across multiple days without forcing the user to log in again.
 * The app only leaves the authenticated state when the user explicitly taps
 * sign-out (which discards the token on the client side) or the 7-day window
 * lapses naturally.
 */
exports.login = async (req, res) => {
  const { email, phone, password } = req.body;

  if (!password || (!email && !phone)) {
    return res.status(400).json({
      error: 'Bad Request',
      message: 'Email/phone and password are required',
    });
  }

  try {
    let query, params;
    if (email) {
      query = 'SELECT * FROM users WHERE email = $1';
      params = [email];
    } else {
      query = 'SELECT * FROM users WHERE phone = $1';
      params = [phone];
    }

    const result = await db.query(query, params);
    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Unauthorized', message: 'Invalid credentials' });
    }

    const user = result.rows[0];
    const isMatch = await bcrypt.compare(password, user.password_hash);
    if (!isMatch) {
      return res.status(401).json({ error: 'Unauthorized', message: 'Invalid credentials' });
    }

    if (!user.is_active) {
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Account deactivated. Please contact support.',
      });
    }

    // Fetch live verification status from courier_profiles for COURIER users
    let isVerified = user.is_fully_verified;
    if (user.role === 'COURIER') {
      const profileRes = await db.query(
        'SELECT is_verified FROM courier_profiles WHERE user_id = $1',
        [user.id]
      );
      if (profileRes.rows.length > 0) {
        isVerified = profileRes.rows[0].is_verified;
      }
    }

    // ── CRITICAL CHANGE: 7-day expiration so Flutter stays authenticated ──
    const tokenPayload = { id: user.id, role: user.role };
    const accessToken = jwt.sign(tokenPayload, process.env.JWT_SECRET, { expiresIn: '7d' });

    res.json({
      message: 'Login successful',
      accessToken,
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        phone: user.phone,
        courierStatus: user.courier_status,
        isFullyVerified: isVerified,
        role: user.role,
        isActive: user.is_active,
        profileImageUrl: user.profile_image_url || null,
        senderRating: parseFloat(user.sender_rating || 5.0),
        courierRating: parseFloat(user.courier_rating || 5.0),
        createdAt: user.created_at,
        nidaNumber: user.nida_number || null,
        nidaDocumentUrl: user.nida_document_url || null,
        selfieUrl: user.selfie_url || null,
        vehicleType: user.vehicle_type || null,
        vehicleRegistrationNumber: user.vehicle_registration_number || null,
      },
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Internal server error during login',
    });
  }
};

// ─── Get Current Authenticated User ──────────────────────────────────────────

exports.getMe = async (req, res) => {
  try {
    const userId = req.user.id;
    const result = await db.query('SELECT * FROM users WHERE id = $1', [userId]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Not Found', message: 'User not found' });
    }

    const user = result.rows[0];

    if (!user.is_active) {
      return res.status(403).json({ error: 'Forbidden', message: 'Account deactivated' });
    }

    let isVerified = user.is_fully_verified;
    if (user.role === 'COURIER') {
      const profileRes = await db.query(
        'SELECT is_verified FROM courier_profiles WHERE user_id = $1',
        [user.id]
      );
      if (profileRes.rows.length > 0) {
        isVerified = profileRes.rows[0].is_verified;
      }
    }

    res.json({
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        phone: user.phone,
        courierStatus: user.courier_status,
        isFullyVerified: isVerified,
        role: user.role,
        isActive: user.is_active,
        profileImageUrl: user.profile_image_url || null,
        senderRating: parseFloat(user.sender_rating || 5.0),
        courierRating: parseFloat(user.courier_rating || 5.0),
        createdAt: user.created_at,
        nidaNumber: user.nida_number || null,
        nidaDocumentUrl: user.nida_document_url || null,
        selfieUrl: user.selfie_url || null,
        vehicleType: user.vehicle_type || null,
        vehicleRegistrationNumber: user.vehicle_registration_number || null,
      },
    });
  } catch (error) {
    console.error('getMe error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};
