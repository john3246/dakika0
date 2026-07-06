const db = require('../db');
const wsManager = require('../websocket');

// ─── Shared helper ────────────────────────────────────────────────────────────

/** Convert a DB snake_case row to camelCase, always stripping password_hash. */
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

// ─── GET /api/admin/metrics ───────────────────────────────────────────────────
//
// FIX #3 — ADMIN METRICS ENDPOINT
//
// Aggregates cross-platform analytics to populate the responsive admin
// dashboard.  All counts are returned as proper JS integers, not strings.
//
//   • Total Deliveries grouped by Status
//   • Count of Active Couriers (courier_status = 'verified' AND is_active)
//   • Pending Verification queues (couriers awaiting admin approval)
//   • Revenue aggregates (sum of total_price on delivered orders)
// ─────────────────────────────────────────────────────────────────────────────
exports.getMetrics = async (req, res) => {
  try {
    const [
      totalUsersRes,
      activeCouriersRes,
      pendingVerificationsRes,
      ordersByStatusRes,
      revenueRes,
    ] = await Promise.all([
      // Total registered users
      db.query('SELECT COUNT(*)::int AS count FROM users'),

      // Active, verified couriers currently operational
      db.query(
        `SELECT COUNT(*)::int AS count
         FROM   users
         WHERE  role = 'COURIER'
           AND  courier_status = 'verified'
           AND  is_active = true`
      ),

      // Couriers waiting for admin approval
      db.query(
        `SELECT COUNT(*)::int AS count
         FROM   users u
         JOIN   courier_profiles cp ON u.id = cp.user_id
         WHERE  cp.is_verified = false
           AND  u.role = 'COURIER'`
      ),

      // Delivery totals broken down by status
      db.query(
        `SELECT status, COUNT(*)::int AS count
         FROM   orders
         GROUP  BY status`
      ),

      // Platform revenue (delivered orders only)
      db.query(
        `SELECT COALESCE(SUM(total_price), 0) AS total
         FROM   orders
         WHERE  status = 'delivered'`
      ),
    ]);

    // Build a status → count map with safe defaults
    const deliveriesByStatus = {
      pending: 0,
      accepted: 0,
      pickedUp: 0,
      delivered: 0,
      cancelled: 0,
    };
    ordersByStatusRes.rows.forEach((r) => {
      const camelStatus = r.status.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
      deliveriesByStatus[camelStatus] = r.count;
    });

    const totalOrders = Object.values(deliveriesByStatus).reduce((a, b) => a + b, 0);

    res.json({
      totalUsers: totalUsersRes.rows[0].count,
      activeCouriers: activeCouriersRes.rows[0].count,
      pendingVerifications: pendingVerificationsRes.rows[0].count,
      totalOrders,
      deliveriesByStatus,
      totalRevenue: parseFloat(revenueRes.rows[0].total),
    });
  } catch (error) {
    console.error('Admin getMetrics error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

// ─── Legacy alias — kept so existing /api/admin/stats route still works ──────
exports.getStats = exports.getMetrics;

// ─── GET /api/admin/users ─────────────────────────────────────────────────────

exports.getUsers = async (req, res) => {
  try {
    const result = await db.query('SELECT * FROM users ORDER BY created_at DESC');
    res.json({ users: result.rows.map(mapToCamelCase) });
  } catch (error) {
    console.error('Admin getUsers error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

// ─── GET /api/admin/users/:id ─────────────────────────────────────────────────
//
// FIX #3 — VIEW SINGLE USER (with profile image URL)
// ─────────────────────────────────────────────────────────────────────────────
exports.getUserById = async (req, res) => {
  const { id } = req.params;
  try {
    const result = await db.query('SELECT * FROM users WHERE id = $1', [id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Not Found', message: 'User not found' });
    }
    res.json({ user: mapToCamelCase(result.rows[0]) });
  } catch (error) {
    console.error('Admin getUserById error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

// ─── PUT /api/admin/users/:id ─────────────────────────────────────────────────
//
// FIX #3 — UPDATE USER (credentials, role, active flag in one call)
//
// Accepts any subset of: { name, email, phone, role, isActive }
// The admin cannot accidentally update their own account via this endpoint.
// ─────────────────────────────────────────────────────────────────────────────
exports.updateUser = async (req, res) => {
  const { id } = req.params;

  if (id === req.user.id) {
    return res.status(400).json({
      error: 'Bad Request',
      message: 'You cannot modify your own account through this endpoint',
    });
  }

  const { name, email, phone, role, isActive } = req.body;

  // Build a dynamic SET clause from only the fields actually provided
  const setClauses = [];
  const params = [];
  let paramIndex = 1;

  if (name !== undefined) {
    setClauses.push(`name = $${paramIndex++}`);
    params.push(name);
  }
  if (email !== undefined) {
    setClauses.push(`email = $${paramIndex++}`);
    params.push(email);
  }
  if (phone !== undefined) {
    setClauses.push(`phone = $${paramIndex++}`);
    params.push(phone);
  }
  if (role !== undefined) {
    const uppercaseRole = (role || '').toUpperCase();
    if (!['ADMIN', 'CUSTOMER', 'COURIER'].includes(uppercaseRole)) {
      return res.status(400).json({ error: 'Bad Request', message: 'Invalid role' });
    }
    setClauses.push(`role = $${paramIndex++}`);
    params.push(uppercaseRole);
  }
  if (isActive !== undefined) {
    setClauses.push(`is_active = $${paramIndex++}`);
    params.push(Boolean(isActive));
  }

  if (setClauses.length === 0) {
    return res
      .status(400)
      .json({ error: 'Bad Request', message: 'No updatable fields were provided' });
  }

  setClauses.push(`updated_at = NOW()`);
  params.push(id); // last param is the WHERE id

  try {
    const result = await db.query(
      `UPDATE users SET ${setClauses.join(', ')} WHERE id = $${paramIndex} RETURNING *`,
      params
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Not Found', message: 'User not found' });
    }
    res.json({ message: 'User updated successfully', user: mapToCamelCase(result.rows[0]) });
  } catch (error) {
    if (error.code === '23505') {
      return res
        .status(409)
        .json({ error: 'Conflict', message: 'Email or phone already in use by another account' });
    }
    console.error('Admin updateUser error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

// ─── DELETE /api/admin/users/:id ─────────────────────────────────────────────
//
// FIX #3 — DROP FRAUDULENT ACCOUNTS
//
// Hard-deletes the user row.  The admin cannot delete their own account.
// ─────────────────────────────────────────────────────────────────────────────
exports.deleteUser = async (req, res) => {
  const { id } = req.params;

  if (id === req.user.id) {
    return res.status(400).json({
      error: 'Bad Request',
      message: 'You cannot delete your own account',
    });
  }

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    // Delete dependent courier profile first (FK constraint)
    await client.query('DELETE FROM courier_profiles WHERE user_id = $1', [id]);

    const result = await client.query(
      'DELETE FROM users WHERE id = $1 RETURNING id, name, email',
      [id]
    );

    if (result.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Not Found', message: 'User not found' });
    }

    await client.query('COMMIT');
    res.json({
      message: 'User account permanently deleted',
      deleted: result.rows[0],
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Admin deleteUser error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  } finally {
    client.release();
  }
};

// ─── GET /api/admin/couriers ──────────────────────────────────────────────────

exports.getCouriers = async (req, res) => {
  try {
    const result = await db.query(
      `SELECT u.id, u.name, u.email, u.phone, u.created_at, u.role, u.is_active,
              u.vehicle_type, u.vehicle_registration_number, u.nida_number,
              u.nida_document_url, u.selfie_url, u.courier_status, u.profile_image_url,
              cp.is_verified
       FROM   users u
       JOIN   courier_profiles cp ON u.id = cp.user_id
       ORDER  BY u.created_at DESC`
    );
    res.json({ couriers: result.rows.map(mapToCamelCase) });
  } catch (error) {
    console.error('Admin getCouriers error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

// ─── PUT /api/admin/users/:id/role ────────────────────────────────────────────

exports.updateUserRole = async (req, res) => {
  const { id } = req.params;
  const { role } = req.body;

  if (id === req.user.id) {
    return res.status(400).json({ error: 'Bad Request', message: 'You cannot change your own role' });
  }

  const uppercaseRole = (role || '').toUpperCase();
  if (!['ADMIN', 'CUSTOMER', 'COURIER'].includes(uppercaseRole)) {
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

// ─── PUT /api/admin/users/:id/active ─────────────────────────────────────────

exports.toggleUserActive = async (req, res) => {
  const { id } = req.params;
  const { isActive } = req.body;

  if (id === req.user.id) {
    return res
      .status(400)
      .json({ error: 'Bad Request', message: 'You cannot deactivate yourself' });
  }

  try {
    const result = await db.query(
      'UPDATE users SET is_active = $1, updated_at = NOW() WHERE id = $2 RETURNING *',
      [Boolean(isActive), id]
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

// ─── PUT /api/admin/couriers/:id/verify ──────────────────────────────────────

exports.verifyCourier = async (req, res) => {
  const { id } = req.params;
  const { status, approve } = req.body;

  let finalStatus = status;
  if (approve !== undefined) {
    finalStatus = approve ? 'verified' : 'unverified';
  }

  if (finalStatus !== 'verified' && finalStatus !== 'unverified') {
    return res
      .status(400)
      .json({ error: 'Bad Request', message: 'Invalid verification status' });
  }

  const isVerified = finalStatus === 'verified';

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    await client.query(
      `UPDATE courier_profiles SET is_verified = $1 WHERE user_id = $2`,
      [isVerified, id]
    );

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
      user: mapToCamelCase(userResult.rows[0]),
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Admin verifyCourier error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  } finally {
    client.release();
  }
};

// ─── GET /api/admin/orders ────────────────────────────────────────────────────

exports.getOrders = async (req, res) => {
  try {
    const result = await db.query(
      `SELECT o.*,
              c.name  AS creator_name,  c.phone  AS creator_phone,
              co.name AS courier_name,  co.phone AS courier_phone
       FROM   orders o
       LEFT JOIN users c  ON o.creator_id = c.id
       LEFT JOIN users co ON o.courier_id = co.id
       ORDER  BY o.created_at DESC`
    );
    res.json({ orders: result.rows.map(mapToCamelCase) });
  } catch (error) {
    console.error('Admin getOrders error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

// ─── PUT /api/admin/orders/:id/cancel ────────────────────────────────────────

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
    wsManager.broadcastOrderEvent(camelOrder, 'order_cancelled');
    res.json({ message: 'Order cancelled successfully', order: camelOrder });
  } catch (error) {
    console.error('Admin cancelOrder error:', error);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};
