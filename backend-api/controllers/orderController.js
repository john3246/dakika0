const db = require('../db');
const wsManager = require('../websocket');
const crypto = require('crypto');

// Helper to convert DB rows to camelCase
const toCamel = (row) => {
  if (!row) return null;
  return Object.fromEntries(
    Object.entries(row).map(([k, v]) => [
      k.replace(/_([a-z])/g, (_, c) => c.toUpperCase()),
      v,
    ])
  );
};

// Pricing Engine (Haversine Formula)
const calculateDistanceKm = (lat1, lon1, lat2, lon2) => {
  const R = 6371; // Radius of the Earth in km
  const dLat = (lat2 - lat1) * (Math.PI / 180);
  const dLon = (lon2 - lon1) * (Math.PI / 180);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * (Math.PI / 180)) * Math.cos(lat2 * (Math.PI / 180)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
};

exports.createOrder = async (req, res) => {
  const creatorId = req.user.id;
  const {
    pickupAddress, pickupLat, pickupLng,
    dropoffAddress, dropoffLat, dropoffLng,
    itemType, itemDescription, packageWeightKg
  } = req.body;

  if (!pickupAddress || !dropoffAddress || pickupLat == null || pickupLng == null || dropoffLat == null || dropoffLng == null) {
    return res.status(400).json({ error: 'Bad Request', message: 'Missing required location fields' });
  }

  const distanceKm = calculateDistanceKm(pickupLat, pickupLng, dropoffLat, dropoffLng);
  const totalPrice = Math.round(distanceKm * 500 * 100) / 100;

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    const orderId = crypto.randomUUID();
    const qrCodeSecureString = crypto.randomBytes(32).toString('hex');

    const result = await client.query(
      `INSERT INTO orders
         (id, creator_id, pickup_address, pickup_latitude, pickup_longitude,
          dropoff_address, dropoff_latitude, dropoff_longitude,
          distance_km, total_price, qr_code_secure_string, status,
          item_type, item_description, package_weight_kg)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'pending', $12, $13, $14)
       RETURNING *`,
      [
        orderId, creatorId, pickupAddress, pickupLat, pickupLng,
        dropoffAddress, dropoffLat, dropoffLng,
        distanceKm, totalPrice, qrCodeSecureString,
        itemType, itemDescription, packageWeightKg
      ]
    );

    await client.query('COMMIT');

    const order = result.rows[0];
    const camelOrder = toCamel(order);

    wsManager.broadcastOrderEvent(camelOrder, 'order_created');

    res.status(201).json({ message: 'Order created', order: camelOrder });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('createOrder error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  } finally {
    client.release();
  }
};

exports.getBroadcasts = async (req, res) => {
  const courierId = req.user.id;
  try {
    const userRes = await db.query(
      'SELECT is_verified FROM courier_profiles WHERE user_id = $1',
      [courierId]
    );
    const isVerified = userRes.rows[0]?.is_verified;
    if (!isVerified) {
      return res.status(403).json({ error: 'Forbidden', message: 'Profile verification required to view broadcasts.' });
    }

    const result = await db.query(
      `SELECT o.*, u.name AS creator_name, u.sender_rating
       FROM orders o
       JOIN users u ON u.id = o.creator_id
       WHERE o.status = 'pending'
       ORDER BY o.created_at DESC`
    );
    res.json({ orders: result.rows.map(toCamel) });
  } catch (err) {
    console.error('getBroadcasts error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

exports.acceptOrder = async (req, res) => {
  const orderId = req.body.orderId || req.body.id;
  const courierId = req.user.id;

  if (!orderId) {
    return res.status(400).json({ error: 'Bad Request', message: 'Order ID is required' });
  }

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    const profileRes = await client.query(
      'SELECT is_verified FROM courier_profiles WHERE user_id = $1',
      [courierId]
    );
    const isVerified = profileRes.rows[0]?.is_verified;
    if (!isVerified) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'Forbidden', message: 'Only verified couriers can accept orders' });
    }

    const orderRes = await client.query(
      'SELECT * FROM orders WHERE id = $1 FOR UPDATE',
      [orderId]
    );
    if (orderRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
    }

    const order = orderRes.rows[0];

    if (order.creator_id === courierId) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Bad Request', message: 'You cannot accept your own order' });
    }

    if (order.courier_id !== null || order.status !== 'pending') {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Conflict', message: 'Order has already been accepted' });
    }

    const updateRes = await client.query(
      `UPDATE orders 
       SET status = 'accepted', courier_id = $1, updated_at = NOW() 
       WHERE id = $2 
       RETURNING *`,
      [courierId, orderId]
    );

    await client.query('COMMIT');

    const updatedOrder = toCamel(updateRes.rows[0]);
    wsManager.broadcastOrderEvent(updatedOrder, 'order_accepted');

    res.json({ message: 'Order accepted successfully', order: updatedOrder });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('acceptOrder error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  } finally {
    client.release();
  }
};

exports.pickupOrder = async (req, res) => {
  const { orderId, qrCodeSecureString } = req.body;
  const courierId = req.user.id;

  if (!orderId || !qrCodeSecureString) {
    return res.status(400).json({ error: 'Bad Request', message: 'Order ID and QR code string are required' });
  }

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    const orderRes = await client.query(
      'SELECT * FROM orders WHERE id = $1 FOR UPDATE',
      [orderId]
    );
    if (orderRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
    }

    const order = orderRes.rows[0];

    if (order.courier_id !== courierId) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'Forbidden', message: 'Access denied: You are not the assigned courier for this order' });
    }

    if (order.status !== 'accepted') {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Conflict', message: 'Order must be in accepted status' });
    }

    if (qrCodeSecureString !== order.qr_code_secure_string) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Bad Request', message: 'Invalid QR code: Proof of Pickup failed' });
    }

    // Calculate handoff_estimated_time assuming 30 km/h speed
    const distanceKm = parseFloat(order.distance_km);
    const hoursToDeliver = distanceKm / 30;
    const msToDeliver = hoursToDeliver * 60 * 60 * 1000;
    const estimatedTime = new Date(Date.now() + msToDeliver);

    const updateRes = await client.query(
      `UPDATE orders 
       SET status = 'picked_up', handoff_estimated_time = $1, updated_at = NOW() 
       WHERE id = $2 
       RETURNING *`,
      [estimatedTime, orderId]
    );

    await client.query('COMMIT');

    const updatedOrder = toCamel(updateRes.rows[0]);
    wsManager.broadcastOrderEvent(updatedOrder, 'order_picked_up');

    res.json({ message: 'Order picked up successfully', order: updatedOrder });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('pickupOrder error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  } finally {
    client.release();
  }
};

exports.completeOrder = async (req, res) => {
  const { orderId, qrCodeSecureString } = req.body;
  const courierId = req.user.id;

  if (!orderId || !qrCodeSecureString) {
    return res.status(400).json({ error: 'Bad Request', message: 'Order ID and QR code string are required' });
  }

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    const orderRes = await client.query(
      'SELECT * FROM orders WHERE id = $1 FOR UPDATE',
      [orderId]
    );
    if (orderRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
    }

    const order = orderRes.rows[0];

    if (order.courier_id !== courierId) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'Forbidden', message: 'Access denied: You are not the assigned courier for this order' });
    }

    if (order.status !== 'picked_up') {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Conflict', message: 'Order must be in picked_up status' });
    }

    if (qrCodeSecureString !== order.qr_code_secure_string) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Bad Request', message: 'Invalid QR Code: Proof of Delivery failed' });
    }

    const updateRes = await client.query(
      `UPDATE orders 
       SET status = 'delivered', updated_at = NOW() 
       WHERE id = $1 
       RETURNING *`,
      [orderId]
    );

    await client.query('COMMIT');

    const updatedOrder = toCamel(updateRes.rows[0]);
    wsManager.broadcastOrderEvent(updatedOrder, 'order_delivered');

    res.json({ message: 'Order completed and delivered successfully', order: updatedOrder });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('completeOrder error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  } finally {
    client.release();
  }
};

exports.getMyOrders = async (req, res) => {
  const userId = req.user.id;
  const rawStatus = req.query.status;
  const statusList = rawStatus ? rawStatus.split(',').map((s) => s.trim().toLowerCase()) : null;

  try {
    let query = `
      SELECT o.*, 
             cu.name AS creator_name,
             co.name AS courier_name
      FROM orders o
      JOIN users cu ON cu.id = o.creator_id
      LEFT JOIN users co ON co.id = o.courier_id
      WHERE (o.creator_id = $1 OR o.courier_id = $1)
    `;
    const params = [userId];

    if (statusList) {
      query += ` AND o.status = ANY($2::text[])`;
      params.push(statusList);
    }
    
    query += ` ORDER BY o.created_at DESC`;

    const result = await db.query(query, params);
    res.json({ orders: result.rows.map(toCamel) });
  } catch (err) {
    console.error('getMyOrders error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

exports.getAvailableOrders = async (req, res) => {
  try {
    const userResult = await db.query('SELECT is_fully_verified FROM users WHERE id = $1', [req.user.id]);
    if (!userResult.rows[0]?.is_fully_verified) {
      return res.status(403).json({ error: 'Forbidden', message: 'Profile verification required to view available orders.' });
    }

    const result = await db.query(
      `SELECT o.*, u.name AS creator_name, u.sender_rating
       FROM orders o
       JOIN users u ON u.id = o.creator_id
       WHERE o.status = 'pending'
       ORDER BY o.created_at DESC`
    );
    res.json({ orders: result.rows.map(toCamel) });
  } catch (err) {
    console.error('getAvailableOrders error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

exports.getNearbyOrders = async (req, res) => {
  const { lat, lng, radiusKm = 10 } = req.query;
  
  if (!lat || !lng) {
    return res.status(400).json({ error: 'Bad Request', message: 'Latitude (lat) and Longitude (lng) are required.' });
  }

  try {
    const userResult = await db.query('SELECT is_fully_verified FROM users WHERE id = $1', [req.user.id]);
    if (!userResult.rows[0]?.is_fully_verified) {
      return res.status(403).json({ error: 'Forbidden', message: 'Profile verification required to view nearby map feed.' });
    }

    const result = await db.query(
      `SELECT o.*, u.name AS creator_name, u.sender_rating
       FROM orders o
       JOIN users u ON u.id = o.creator_id
       WHERE o.status IN ('pending', 'accepted')
       ORDER BY o.created_at DESC`
    );

    const latNum = parseFloat(lat);
    const lngNum = parseFloat(lng);
    const radiusNum = parseFloat(radiusKm);

    const nearbyOrders = result.rows.filter(row => {
      if (!row.pickup_latitude || !row.pickup_longitude) return false;
      const dist = calculateDistanceKm(latNum, lngNum, row.pickup_latitude, row.pickup_longitude);
      return dist <= radiusNum;
    });

    res.json({ orders: nearbyOrders.map(toCamel) });
  } catch (err) {
    console.error('getNearbyOrders error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

exports.getOrderById = async (req, res) => {
  const { id } = req.params;
  const userId  = req.user.id;

  try {
    const result = await db.query(
      `SELECT o.*,
         cust.name AS creator_name, cust.phone AS creator_phone, cust.sender_rating AS creator_rating,
         cour.name AS courier_name, cour.phone AS courier_phone, cour.courier_rating, cour.is_fully_verified AS courier_is_verified,
         cour.current_latitude AS courier_latitude, cour.current_longitude AS courier_longitude
       FROM orders o
       JOIN users cust ON cust.id = o.creator_id
       LEFT JOIN users cour ON cour.id = o.courier_id
       WHERE o.id = $1`,
      [id]
    );

    if (result.rows.length === 0) return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
    const order = result.rows[0];

    if (order.creator_id !== userId && order.courier_id !== userId && order.status !== 'pending') {
      return res.status(403).json({ error: 'Forbidden', message: 'Access denied' });
    }

    res.json({ order: toCamel(order) });
  } catch (err) {
    console.error('getOrderById error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

exports.updateOrderStatus = async (req, res) => {
  const { id } = req.params;
  let { status } = req.body;
  status = status ? status.toLowerCase() : null;
  const userId = req.user.id;

  const VALID_STATUSES = ['accepted', 'picked_up', 'delivered', 'cancelled'];
  if (!VALID_STATUSES.includes(status)) {
    return res.status(400).json({ error: 'Bad Request', message: 'Invalid status.' });
  }

  try {
    const userRes = await db.query('SELECT is_fully_verified, role FROM users WHERE id = $1', [userId]);
    const user = userRes.rows[0];
    if (!user) return res.status(404).json({ error: 'Not Found', message: 'User not found' });

    // Allow Admins to arbitrarily update statuses for support purposes
    if (user.role.toUpperCase() === 'ADMIN') {
      const updated = await db.query(`UPDATE orders SET status=$1, updated_at=NOW() WHERE id=$2 RETURNING *`, [status, id]);
      if (updated.rows.length === 0) return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
      const camelOrder = toCamel(updated.rows[0]);
      wsManager.broadcastOrderEvent(camelOrder, 'order_' + status);
      return res.json({ message: `Order forced to ${status} by admin`, order: camelOrder });
    }

    return res.status(403).json({ error: 'Forbidden', message: 'Please use the specific endpoints (accept, pickup, complete) instead' });
  } catch (err) {
    console.error('updateOrderStatus error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

exports.getMyStats = async (req, res) => {
  const userId = req.user.id;
  try {
    const result = await db.query(
      `SELECT status, COUNT(*)::int AS count
       FROM orders
       WHERE creator_id = $1 OR courier_id = $1
       GROUP BY status`,
      [userId]
    );

    const stats = { pending: 0, accepted: 0, picked_up: 0, delivered: 0, cancelled: 0 };
    result.rows.forEach((r) => { stats[r.status] = r.count; });
    res.json({ stats });
  } catch (err) {
    console.error('getMyStats error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

exports.rateOrder = async (req, res) => {
  const { id } = req.params;
  const { rating } = req.body;
  const userId = req.user.id;

  if (rating < 1 || rating > 5) {
    return res.status(400).json({ error: 'Bad Request', message: 'Rating must be between 1 and 5' });
  }

  try {
    const { rows } = await db.query('SELECT * FROM orders WHERE id = $1', [id]);
    if (rows.length === 0) return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
    const order = rows[0];

    if (order.status !== 'delivered') {
      return res.status(400).json({ error: 'Bad Request', message: 'Can only rate delivered orders' });
    }

    let targetUserId, ratingColumn;
    if (order.creator_id === userId) {
      targetUserId = order.courier_id;
      ratingColumn = 'courier_rating';
    } else if (order.courier_id === userId) {
      targetUserId = order.creator_id;
      ratingColumn = 'sender_rating';
    } else {
      return res.status(403).json({ error: 'Forbidden', message: 'Not involved in this order' });
    }

    if (!targetUserId) return res.status(400).json({ error: 'Bad Request', message: 'Target user not found' });

    await db.query(
      `UPDATE users SET ${ratingColumn} = LEAST(5.00, GREATEST(1.00, ((${ratingColumn} * 4) + $1) / 5.0)) WHERE id = $2`,
      [rating, targetUserId]
    );

    res.json({ message: 'Rating submitted successfully' });
  } catch (err) {
    console.error('rateOrder error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};
