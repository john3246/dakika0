const pool = require('../db');

// Helper to map snake_case DB row to camelCase
const mapToCamelCase = (row) => {
  if (!row) return null;
  const result = {};
  for (const key in row) {
    if (key === 'password_hash') continue;

    const camelKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase());
    result[camelKey] = row[key];
  }
  return result;
};

const getProfile = async (req, res) => {
  try {
    const userId = req.user.id;
    const userResult = await pool.query('SELECT * FROM users WHERE id = $1', [userId]);
    if (userResult.rows.length === 0) {
      return res.status(404).json({ message: 'User not found' });
    }
    res.json({ profile: mapToCamelCase(userResult.rows[0]) });
  } catch (error) {
    console.error('Error fetching profile:', error);
    res.status(500).json({ error: 'Failed to fetch profile' });
  }
};

const updateProfile = async (req, res) => {
  try {
    const userId = req.user.id;
    const { name, phone } = req.body;

    const updates = [];
    const values = [];
    let idx = 1;

    if (name) {
      updates.push(`name = $${idx++}`);
      values.push(name);
    }
    if (phone) {
      updates.push(`phone = $${idx++}`);
      values.push(phone);
    }

    if (updates.length === 0) {
      return res.status(400).json({ message: 'No fields provided to update' });
    }

    values.push(userId);
    const query = `UPDATE users SET ${updates.join(', ')} WHERE id = $${idx} RETURNING *`;
    const result = await pool.query(query, values);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'User not found' });
    }

    res.json({ message: 'Profile updated successfully', profile: mapToCamelCase(result.rows[0]) });
  } catch (error) {
    console.error('Error updating profile:', error);
    res.status(500).json({ error: 'Failed to update profile' });
  }
};

const upgradeCourier = async (req, res) => {
  const userId = req.user.id;
  const { 
    idDocumentUrl, 
    selfieUrl, 
    nidaNumber, 
    vehicleType, 
    vehicleRegistrationNumber 
  } = req.body;

  const client = await pool.getClient();
  try {
    await client.query('BEGIN');

    const result = await client.query(
      `UPDATE users 
       SET 
         courier_status = 'pending', 
         role = 'COURIER',
         is_fully_verified = false,
         id_document_url = COALESCE($1, id_document_url), 
         selfie_url = COALESCE($2, selfie_url),
         nida_number = $3,
         vehicle_type = $4,
         vehicle_registration_number = $5
       WHERE id = $6 RETURNING *`,
      [
        idDocumentUrl || null, 
        selfieUrl || null, 
        nidaNumber || null,
        vehicleType || null,
        vehicleRegistrationNumber || null,
        userId
      ]
    );

    // Upsert into courier_profiles
    await client.query(
      `INSERT INTO courier_profiles (user_id, is_verified)
       VALUES ($1, false)
       ON CONFLICT (user_id) DO UPDATE SET is_verified = false`,
      [userId]
    );

    await client.query('COMMIT');

    res.json({ message: 'Verification successful! You are now a courier.', profile: mapToCamelCase(result.rows[0]) });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error upgrading courier:', error);
    if (error.code === '23505') {
      return res.status(409).json({ error: 'NIDA Number or Vehicle Registration already exists' });
    }
    res.status(500).json({ error: 'Failed to submit verification' });
  } finally {
    client.release();
  }
};

const uploadDocument = async (req, res) => {
  try {
    const userId = req.user.id;
    const file = req.file;
    const uploadType = req.query.type; // 'profile', 'id_document', 'selfie'
    
    if (!file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }

    const fileUrl = `${req.protocol}://${req.get('host')}/uploads/${file.filename}`;

    let column = 'profile_image_url';
    if (uploadType === 'id_document') column = 'id_document_url';
    if (uploadType === 'selfie') column = 'selfie_url';

    await pool.query(`UPDATE users SET ${column} = $1 WHERE id = $2`, [fileUrl, userId]);

    res.json({ message: 'File uploaded successfully', url: fileUrl });
  } catch (error) {
    console.error('Error uploading document:', error);
    res.status(500).json({ error: 'Failed to upload document' });
  }
};

module.exports = {
  getProfile,
  updateProfile,
  upgradeCourier,
  uploadDocument
};
