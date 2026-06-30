const db = require('../db');

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

exports.getStats = async (req, res) => {
  try {
    const usersCount = await db.query('SELECT COUNT(*) FROM users');
    const couriersCount = await db.query("SELECT COUNT(*) FROM users WHERE courier_status = 'verified'");
    const pendingVerifications = await db.query(
      "SELECT COUNT(*) FROM users u JOIN courier_profiles cp ON u.id = cp.user_id WHERE cp.is_verified = false"
    );
    const ordersCount = await db.query('SELECT COUNT(*) FROM orders');
    const completedOrders = await db.query("SELECT COUNT(*) FROM orders WHERE status = 'delivered'");
    const activeOrders = await db.query("SELECT COUNT(*) FROM orders WHERE status IN ('accepted', 'picked_up')");
    
    const revenueResult = await db.query("SELECT SUM(total_price) as total FROM orders WHERE status = 'delivered'");
    const revenue = parseFloat(revenueResult.rows[0].total || 0);

    res.json({
      totalUsers: parseInt(usersCount.rows[0].count),
      totalCouriers: parseInt(couriersCount.rows[0].count),
      pendingVerifications: parseInt(pendingVerifications.rows[0].count),
      totalOrders: parseInt(ordersCount.rows[0].count),
      completedOrders: parseInt(completedOrders.rows[0].count),
      activeOrders: parseInt(activeOrders.rows[0].count),
      totalRevenue: revenue
    });
  } catch (error) {
    console.error('Admin stats error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

exports.getUsers = async (req, res) => {
  try {
    const result = await db.query('SELECT * FROM users ORDER BY created_at DESC');
    const users = result.rows.map(mapToCamelCase);
    res.json({ users });
  } catch (error) {
    console.error('Admin getUsers error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

exports.getCouriers = async (req, res) => {
  try {
    const result = await db.query(`
      SELECT u.id, u.name, u.email, u.phone, u.created_at, u.role, u.is_active, u.vehicle_type, u.vehicle_registration_number, u.nida_number, u.nida_document_url, u.selfie_url, u.courier_status,
             cp.is_verified
      FROM users u
      JOIN courier_profiles cp ON u.id = cp.user_id
      ORDER BY u.created_at DESC
    `);
    const couriers = result.rows.map(mapToCamelCase);
    res.json({ couriers });
  } catch (error) {
    console.error('Admin getCouriers error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

exports.updateUserRole = async (req, res) => {
  const { id } = req.params;
  const { role } = req.body;

  if (id === req.user.id) {
    return res.status(400).json({ error: 'Bad Request', message: 'You cannot change your own role' });
  }

  const uppercaseRole = (role || '').toUpperCase();
  if (uppercaseRole !== 'ADMIN' && uppercaseRole !== 'CUSTOMER' && uppercaseRole !== 'COURIER') {
    return res.status(400).json({ error: 'Bad Request', message: 'Invalid role' });
  }

  try {
    const result = await db.query(
      'UPDATE users SET role = $1, updated_at = NOW() WHERE id = $2 RETURNING *',
      [uppercaseRole, id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Not Found', message: 'User not found' });
    }
    res.json({ message: 'User role updated successfully', user: mapToCamelCase(result.rows[0]) });
  } catch (error) {
    console.error('Admin updateUserRole error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

exports.toggleUserActive = async (req, res) => {
  const { id } = req.params;
  const { isActive } = req.body;

  if (id === req.user.id) {
    return res.status(400).json({ error: 'Bad Request', message: 'You cannot deactivate yourself' });
  }

  try {
    const result = await db.query(
      'UPDATE users SET is_active = $1, updated_at = NOW() WHERE id = $2 RETURNING *',
      [isActive, id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Not Found', message: 'User not found' });
    }
    res.json({ message: 'User status updated successfully', user: mapToCamelCase(result.rows[0]) });
  } catch (error) {
    console.error('Admin toggleUserActive error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

exports.verifyCourier = async (req, res) => {
  const { id } = req.params;
  const { status, approve } = req.body;

  let finalStatus = status;
  if (approve !== undefined) {
    finalStatus = approve ? 'verified' : 'unverified';
  }

  if (finalStatus !== 'verified' && finalStatus !== 'unverified') {
    return res.status(400).json({ error: 'Bad Request', message: 'Invalid verification status' });
  }

  const isVerified = finalStatus === 'verified';

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    // Update courier_profiles
    await client.query(
      `UPDATE courier_profiles 
       SET is_verified = $1 
       WHERE user_id = $2`,
      [isVerified, id]
    );

    // Update users
    const finalRole = isVerified ? 'COURIER' : 'CUSTOMER';
    const userResult = await client.query(
      `UPDATE users 
       SET courier_status = $1, is_fully_verified = $2, role = $3, updated_at = NOW() 
       WHERE id = $4 
       RETURNING *`,
      [finalStatus, isVerified, finalRole, id]
    );

    if (userResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Not Found', message: 'Courier not found' });
    }

    await client.query('COMMIT');
    res.json({ 
      message: 'Courier verification updated successfully', 
      user: mapToCamelCase(userResult.rows[0]) 
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Admin verifyCourier error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  } finally {
    client.release();
  }
};

exports.getOrders = async (req, res) => {
  try {
    const result = await db.query(`
      SELECT o.*, 
             c.name as creator_name, c.phone as creator_phone,
             co.name as courier_name, co.phone as courier_phone
      FROM orders o
      LEFT JOIN users c ON o.creator_id = c.id
      LEFT JOIN users co ON o.courier_id = co.id
      ORDER BY o.created_at DESC
    `);
    const orders = result.rows.map(mapToCamelCase);
    res.json({ orders });
  } catch (error) {
    console.error('Admin getOrders error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

exports.cancelOrder = async (req, res) => {
  const { id } = req.params;
  try {
    const result = await db.query(
      `UPDATE orders SET status = 'cancelled', updated_at = NOW() WHERE id = $1 RETURNING *`,
      [id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
    }
    const camelOrder = mapToCamelCase(result.rows[0]);
    const wsManager = require('../websocket');
    wsManager.broadcastOrderEvent(camelOrder, 'order_cancelled');
    res.json({ message: 'Order cancelled successfully', order: camelOrder });
  } catch (error) {
    console.error('Admin cancelOrder error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};
