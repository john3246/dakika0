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

const BASE_FEE = 2.00;
const PER_KM_RATE = 0.50;

exports.createOrder = async (req, res) => {
  const customerId = req.user.id;
  const {
    pickupAddress, pickupLat, pickupLng,
    dropoffAddress, dropoffLat, dropoffLng,
    itemDescription, estimatedPrice,
    receiverName, receiverPhone, receiverNationalId
  } = req.body;

  if (!pickupAddress || !dropoffAddress || !receiverName || !receiverPhone) {
    return res.status(400).json({ error: 'Bad Request', message: 'Missing required fields' });
  }

  // Pricing Engine (Fallback Calculation if not passed)
  let finalEstimatedPrice = parseFloat(estimatedPrice);
  if (!finalEstimatedPrice && pickupLat && pickupLng && dropoffLat && dropoffLng) {
    const distance = calculateDistanceKm(pickupLat, pickupLng, dropoffLat, dropoffLng);
    finalEstimatedPrice = BASE_FEE + (distance * PER_KM_RATE);
    finalEstimatedPrice = Math.round(finalEstimatedPrice * 100) / 100;
  }
  if (!finalEstimatedPrice) {
    finalEstimatedPrice = BASE_FEE;
  }

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    // Generate secure random UUID
    const orderId = crypto.randomUUID();
    // Generate secure random 6-digit OTP
    const verificationOtp = crypto.randomInt(100000, 999999).toString();
    // Build QR code payload: Order UUID, Sender ID, Receiver Phone
    const qrCodePayload = `orderId:${orderId}|senderId:${customerId}|receiverPhone:${receiverPhone}`;
    // Expiration set exactly 2 minutes into the future
    const broadcastExpiresAt = new Date(Date.now() + 2 * 60 * 1000);

    const result = await client.query(
      `INSERT INTO orders
         (id, customer_id, pickup_address, pickup_latitude, pickup_longitude,
          dropoff_address, dropoff_latitude, dropoff_longitude,
          item_type, item_description, estimated_price,
          receiver_name, receiver_phone, receiver_national_id, qr_code_payload, verification_otp, broadcast_expires_at, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, 'PENDING')
       RETURNING *`,
      [
        orderId, customerId, pickupAddress, pickupLat || 0, pickupLng || 0,
        dropoffAddress, dropoffLat || 0, dropoffLng || 0,
        'Package', itemDescription || null, finalEstimatedPrice,
        receiverName, receiverPhone, receiverNationalId || null,
        qrCodePayload, verificationOtp, broadcastExpiresAt
      ]
    );

    await client.query('COMMIT');

    const order = result.rows[0];
    const camelOrder = toCamel(order);

    // Print generated OTP simulating SMS delivery
    console.log(`[SMS Simulation] To ${receiverPhone} - Verification OTP for Order ${orderId}: ${verificationOtp}`);

    // Broadcast creation
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
    // Check if courier is fully verified in courier_profiles
    const userRes = await db.query(
      'SELECT is_verified FROM courier_profiles WHERE user_id = $1',
      [courierId]
    );
    const isVerified = userRes.rows[0]?.is_verified;
    if (!isVerified) {
      return res.status(403).json({ error: 'Forbidden', message: 'Profile verification required to view broadcasts.' });
    }

    const result = await db.query(
      `SELECT o.*, u.name AS customer_name, u.sender_rating
       FROM orders o
       JOIN users u ON u.id = o.customer_id
       WHERE o.status = 'PENDING' AND o.broadcast_expires_at > NOW()
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

    // Check if courier is fully verified
    const profileRes = await client.query(
      'SELECT is_verified FROM courier_profiles WHERE user_id = $1',
      [courierId]
    );
    const isVerified = profileRes.rows[0]?.is_verified;
    if (!isVerified) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'Forbidden', message: 'Only verified couriers can accept orders' });
    }

    // Fetch order with row-level lock
    const orderRes = await client.query(
      'SELECT * FROM orders WHERE id = $1 FOR UPDATE',
      [orderId]
    );
    if (orderRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
    }

    const order = orderRes.rows[0];

    // Expiry check
    if (new Date() > new Date(order.broadcast_expires_at)) {
      await client.query('ROLLBACK');
      return res.status(410).json({ error: 'Gone', message: 'Order broadcast has expired. Cannot accept.' });
    }

    // Availability check
    if (order.courier_id !== null || order.status !== 'PENDING') {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Conflict', message: 'Order has already been accepted' });
    }

    // Update order
    const updateRes = await client.query(
      `UPDATE orders 
       SET status = 'ACCEPTED', courier_id = $1, accepted_at = NOW() 
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
  const { orderId, scannedQrPayload } = req.body;
  const courierId = req.user.id;

  if (!orderId || !scannedQrPayload) {
    return res.status(400).json({ error: 'Bad Request', message: 'Order ID and scanned QR payload are required' });
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

    if (order.status !== 'ACCEPTED') {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Conflict', message: 'Order must be in ACCEPTED status' });
    }

    // Compare scannedQrPayload
    if (scannedQrPayload !== order.qr_code_payload) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Bad Request', message: 'Invalid QR code payload: Proof of Pickup failed' });
    }

    const updateRes = await client.query(
      `UPDATE orders 
       SET status = 'PICKED_UP', picked_up_at = NOW() 
       WHERE id = $1 
       RETURNING *`,
      [orderId]
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
  const { orderId, inputtedOtp } = req.body;
  const courierId = req.user.id;

  if (!orderId || !inputtedOtp) {
    return res.status(400).json({ error: 'Bad Request', message: 'Order ID and inputted OTP are required' });
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

    if (order.status !== 'PICKED_UP') {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Conflict', message: 'Order must be in PICKED_UP status' });
    }

    // Compare OTP
    if (inputtedOtp !== order.verification_otp) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Bad Request', message: 'Invalid OTP code: Proof of Delivery failed' });
    }

    const updateRes = await client.query(
      `UPDATE orders 
       SET status = 'DELIVERED', completed_at = NOW() 
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
  const statusList = rawStatus ? rawStatus.split(',').map((s) => s.trim().toUpperCase()) : null;

  try {
    let query = `
      SELECT o.*, 
             cu.name AS customer_name,
             co.name AS courier_name
      FROM orders o
      JOIN users cu ON cu.id = o.customer_id
      LEFT JOIN users co ON co.id = o.courier_id
      WHERE (o.customer_id = $1 OR o.courier_id = $1)
    `;
    const params = [userId];

    if (statusList) {
      query += ` AND o.status = ANY($2::order_status[])`;
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
      `SELECT o.*, u.name AS customer_name, u.sender_rating
       FROM orders o
       JOIN users u ON u.id = o.customer_id
       WHERE o.status = 'PENDING'
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
      `SELECT o.*, u.name AS customer_name, u.sender_rating
       FROM orders o
       JOIN users u ON u.id = o.customer_id
       WHERE o.status IN ('PENDING', 'ACCEPTED')
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
         cust.name AS customer_name, cust.phone AS customer_phone, cust.sender_rating AS customer_rating,
         cour.name AS courier_name, cour.phone AS courier_phone, cour.courier_rating, cour.is_fully_verified AS courier_is_verified,
         cour.current_latitude AS courier_latitude, cour.current_longitude AS courier_longitude
       FROM orders o
       JOIN users cust ON cust.id = o.customer_id
       LEFT JOIN users cour ON cour.id = o.courier_id
       WHERE o.id = $1`,
      [id]
    );

    if (result.rows.length === 0) return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
    const order = result.rows[0];

    if (order.customer_id !== userId && order.courier_id !== userId && order.status !== 'PENDING') {
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
  const { status, cancelReason, qrPayload, otp } = req.body;
  const userId = req.user.id;

  const VALID_STATUSES = ['ACCEPTED', 'PICKED_UP', 'DELIVERED', 'CANCELLED'];
  if (!VALID_STATUSES.includes(status)) {
    return res.status(400).json({ error: 'Bad Request', message: `Invalid status.` });
  }

  try {
    const userRes = await db.query('SELECT is_fully_verified FROM users WHERE id = $1', [userId]);
    const isVerified = userRes.rows[0]?.is_fully_verified;

    const { rows } = await db.query('SELECT * FROM orders WHERE id = $1', [id]);
    if (rows.length === 0) return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
    const order = rows[0];

    if (status === 'ACCEPTED') {
      if (order.status !== 'PENDING') return res.status(409).json({ error: 'Conflict', message: 'Order is no longer available' });
      if (!isVerified) return res.status(403).json({ error: 'Forbidden', message: 'Only verified users can accept orders' });
      if (order.customer_id === userId) {
        return res.status(400).json({ error: 'Bad Request', message: 'You cannot accept your own order' });
      }
      if (new Date() > new Date(order.broadcast_expires_at)) {
        return res.status(403).json({ error: 'Forbidden', message: 'Order broadcast has expired. Cannot accept anymore.' });
      }
    }
    if (status === 'PICKED_UP' || status === 'DELIVERED') {
      if (order.courier_id !== userId) return res.status(403).json({ error: 'Forbidden', message: 'Not your assigned order' });
      if (status === 'PICKED_UP' && order.status !== 'ACCEPTED') return res.status(409).json({ error: 'Conflict', message: 'Must be ACCEPTED first' });
      if (status === 'DELIVERED' && order.status !== 'PICKED_UP') return res.status(409).json({ error: 'Conflict', message: 'Must be PICKED_UP first' });
      
      if (status === 'PICKED_UP') {
        if (!qrPayload || qrPayload !== order.qr_code_payload) {
          return res.status(400).json({ error: 'Bad Request', message: 'Invalid Sender QR Code. Proof of Pickup failed.' });
        }
      }
      
      if (status === 'DELIVERED') {
        if (!otp && !qrPayload) {
          return res.status(400).json({ error: 'Bad Request', message: 'Must provide either OTP or Receiver QR Code for Proof of Delivery.' });
        }
        if (otp && otp !== order.verification_otp) {
          return res.status(400).json({ error: 'Bad Request', message: 'Invalid Receiver OTP. Proof of Delivery failed.' });
        }
        if (qrPayload && qrPayload !== order.qr_code_payload + '-receiver') {
           return res.status(400).json({ error: 'Bad Request', message: 'Invalid Receiver QR Code. Proof of Delivery failed.' });
        }
      }
    }

    let updateQuery, updateParams;
    const now = new Date();

    if (status === 'ACCEPTED') {
      updateQuery = `UPDATE orders SET status='ACCEPTED', courier_id=$1, accepted_at=$2 WHERE id=$3 RETURNING *`;
      updateParams = [userId, now, id];
    } else if (status === 'PICKED_UP') {
      updateQuery = `UPDATE orders SET status='PICKED_UP', picked_up_at=$1 WHERE id=$2 RETURNING *`;
      updateParams = [now, id];
    } else if (status === 'DELIVERED') {
      updateQuery = `UPDATE orders SET status='DELIVERED', completed_at=$1 WHERE id=$2 RETURNING *`;
      updateParams = [now, id];
    } else {
      updateQuery = `UPDATE orders SET status='CANCELLED', cancel_reason=$1 WHERE id=$2 RETURNING *`;
      updateParams = [cancelReason ?? null, id];
    }

    const updated = await db.query(updateQuery, updateParams);
    const camelOrder = toCamel(updated.rows[0]);

    wsManager.broadcastOrderEvent(camelOrder, 'order_' + status.toLowerCase());

    res.json({ message: `Order ${status.toLowerCase()}`, order: camelOrder });
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
       WHERE customer_id = $1 OR courier_id = $1
       GROUP BY status`,
      [userId]
    );

    const stats = { PENDING: 0, ACCEPTED: 0, PICKED_UP: 0, DELIVERED: 0, CANCELLED: 0 };
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

    if (order.status !== 'DELIVERED') {
      return res.status(400).json({ error: 'Bad Request', message: 'Can only rate delivered orders' });
    }

    let targetUserId, ratingColumn;
    if (order.customer_id === userId) {
      targetUserId = order.courier_id;
      ratingColumn = 'courier_rating';
    } else if (order.courier_id === userId) {
      targetUserId = order.customer_id;
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
