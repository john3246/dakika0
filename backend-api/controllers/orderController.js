const db = require('../db');
const wsManager = require('../websocket');
const crypto = require('crypto');
// firebase-admin is initialized globally in server.js — just require it here.
const admin = require('firebase-admin');

// ─── Shared helpers ───────────────────────────────────────────────────────────

/** Convert a DB snake_case row to camelCase, stripping password_hash. */
const toCamel = (row) => {
  if (!row) return null;
  return Object.fromEntries(
    Object.entries(row)
      .filter(([k]) => k !== 'password_hash')
      .map(([k, v]) => [k.replace(/_([a-z])/g, (_, c) => c.toUpperCase()), v])
  );
};

/** Haversine distance in km between two lat/lng pairs. */
const calculateDistanceKm = (lat1, lon1, lat2, lon2) => {
  const R = 6371;
  const dLat = (lat2 - lat1) * (Math.PI / 180);
  const dLon = (lon2 - lon1) * (Math.PI / 180);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * (Math.PI / 180)) *
      Math.cos(lat2 * (Math.PI / 180)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
};

/**
 * Attempt to send a push notification to the given device token.
 * This is intentionally fire-and-forget: any failure is swallowed so it
 * never prevents the HTTP response from being sent.
 *
 * Replace the body of this function with your real FCM / APNs / Expo call
 * once you wire up a push provider.  The safe outer try/catch is the only
 * contract this helper must honour.
 */
async function sendPushNotification(deviceToken, title, body) {
  try {
    // ── Debug: confirm the token is reaching the notification step ──
    console.log('[Push Notification Setup] Target Token:', deviceToken);

    const message = {
      notification: {
        title: title,
        body: body,
      },
      token: deviceToken,
    };
    const response = await admin.messaging().send(message);
    console.log('[Push] Successfully sent message:', response);
  } catch (error) {
    console.error('[Push] sendPushNotification failed locally:', error);
  }
}

// ─── notifyOrderCreator ──────────────────────────────────────────────────────
// Convenience wrapper: looks up the order creator's device_token and fires an
// FCM push notification reporting the new order status.
// Always wraps in try/catch — a missed notification must never block a response.
async function notifyOrderCreator(orderId, newStatus) {
  try {
    const res = await db.query(
      `SELECT u.device_token, u.name
       FROM orders o
       JOIN users u ON u.id = o.creator_id
       WHERE o.id = $1`,
      [orderId]
    );
    const row = res.rows[0];
    if (!row?.device_token) {
      console.log(`[Push] notifyOrderCreator: no device_token for order ${orderId}`);
      return;
    }
    const statusLabel = newStatus.charAt(0) + newStatus.slice(1).toLowerCase().replace('_', ' ');
    await sendPushNotification(
      row.device_token,
      'Delivery Update 🚚',
      `Your order status has changed to: ${statusLabel}`
    );
  } catch (err) {
    console.error('[Push] notifyOrderCreator failed (non-fatal):', err.message);
  }
}

// ─── createOrder ─────────────────────────────────────────────────────────────
//
// FIX #4 — REORDER CREATION CRASH
//
// Root cause: any unhandled exception thrown after the DB COMMIT (e.g. inside
// the push-notification call) would propagate uncaught and kill the response
// loop, leaving the HTTP connection hanging.  The Flutter app timed out and
// showed 'failed to contact server'.
//
// Fix: wrap the ENTIRE pipeline in a single outer try/catch, including the
// notification step.  The notification itself is wrapped in an *inner*
// try/catch so that a null device_token or a transient FCM error can never
// prevent the 201 response from reaching the client.
// ─────────────────────────────────────────────────────────────────────────────
exports.createOrder = async (req, res) => {
  const creatorId = req.user.id;
  const {
    pickupAddress,
    pickupLat,
    pickupLng,
    dropoffAddress,
    dropoffLat,
    dropoffLng,
    itemType,
    itemDescription,
    packageWeightKg,
    suggestedPrice,
  } = req.body;

  if (
    !pickupAddress ||
    !dropoffAddress ||
    pickupLat == null ||
    pickupLng == null ||
    dropoffLat == null ||
    dropoffLng == null
  ) {
    return res
      .status(400)
      .json({ error: 'Bad Request', message: 'Missing required location fields' });
  }

  const distanceKm = calculateDistanceKm(pickupLat, pickupLng, dropoffLat, dropoffLng);
  const totalPrice = Math.round(distanceKm * 500 * 100) / 100;

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    const orderId = crypto.randomUUID();

    // Build the QR payload string safely — no external calls, no risk of null refs.
    const qrCodeSecureString = crypto.randomBytes(32).toString('hex');
    const qrPayload = `ORDER:${orderId}|TOKEN:${qrCodeSecureString}`;

    const result = await client.query(
      `INSERT INTO orders
         (id, creator_id, pickup_address, pickup_latitude, pickup_longitude,
          dropoff_address, dropoff_latitude, dropoff_longitude,
          distance_km, total_price, qr_code_secure_string, status,
          item_type, item_description, package_weight_kg, suggested_price)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'pending', $12, $13, $14, $15)
       RETURNING *`,
      [
        orderId,
        creatorId,
        pickupAddress,
        pickupLat,
        pickupLng,
        dropoffAddress,
        dropoffLat,
        dropoffLng,
        distanceKm,
        totalPrice,
        qrCodeSecureString,
        itemType || null,
        itemDescription || null,
        packageWeightKg || null,
        suggestedPrice || null,
      ]
    );

    await client.query('COMMIT');

    const newOrder = toCamel(result.rows[0]);
    // Augment the camelCase order with the full QR payload string for the client
    newOrder.qrPayload = qrPayload;

    // Broadcast the new order to connected WebSocket listeners (e.g. courier dashboards)
    wsManager.broadcastOrderEvent(newOrder, 'order_created');

    // ── Inner try/catch: notification failure must NEVER crash the response ──
    try {
      const userRes = await db.query('SELECT device_token FROM users WHERE id = $1', [creatorId]);
      const deviceToken = userRes.rows[0]?.device_token ?? null;

      if (deviceToken) {
        await sendPushNotification(
          deviceToken,
          'Order Created! 🚀',
          `Your delivery from ${pickupAddress} to ${dropoffAddress} is now live.`
        );
      } else {
        console.log(`[Push] Skipped — user ${creatorId} has no device_token registered.`);
      }
    } catch (notifError) {
      // Log the failure but do NOT re-throw — the order is already committed.
      console.error('[Push] sendPushNotification failed (non-fatal):', notifError.message);
    }

    // Always finish the HTTP lifecycle cleanly.
    return res.status(201).json({ success: true, order: newOrder });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('createOrder error:', err);
    return res
      .status(500)
      .json({ error: 'Internal Server Error', message: 'Internal server error' });
  } finally {
    client.release();
  }
};

// ─── getBroadcasts ────────────────────────────────────────────────────────────

exports.getBroadcasts = async (req, res) => {
  const courierId = req.user.id;
  try {
    const userRes = await db.query(
      'SELECT is_verified FROM courier_profiles WHERE user_id = $1',
      [courierId]
    );
    const isVerified = userRes.rows[0]?.is_verified;
    if (!isVerified) {
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Profile verification required to view broadcasts.',
      });
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

// ─── acceptOrder ─────────────────────────────────────────────────────────────

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
      return res
        .status(403)
        .json({ error: 'Forbidden', message: 'Only verified couriers can accept orders' });
    }

    const orderRes = await client.query('SELECT * FROM orders WHERE id = $1 FOR UPDATE', [
      orderId,
    ]);
    if (orderRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
    }

    const order = orderRes.rows[0];

    if (order.creator_id === courierId) {
      await client.query('ROLLBACK');
      return res
        .status(400)
        .json({ error: 'Bad Request', message: 'You cannot accept your own order' });
    }

    if (order.courier_id !== null || order.status !== 'pending') {
      await client.query('ROLLBACK');
      return res
        .status(409)
        .json({ error: 'Conflict', message: 'Order has already been accepted' });
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

    // ── Notify the sender their order has been accepted ──
    notifyOrderCreator(orderId, 'ACCEPTED');

    res.json({ message: 'Order accepted successfully', order: updatedOrder });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('acceptOrder error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  } finally {
    client.release();
  }
};

// ─── pickupOrder ─────────────────────────────────────────────────────────────

exports.pickupOrder = async (req, res) => {
  const { orderId, qrCodeSecureString } = req.body;
  const courierId = req.user.id;

  if (!orderId || !qrCodeSecureString) {
    return res
      .status(400)
      .json({ error: 'Bad Request', message: 'Order ID and QR code string are required' });
  }

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    const orderRes = await client.query('SELECT * FROM orders WHERE id = $1 FOR UPDATE', [
      orderId,
    ]);
    if (orderRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
    }

    const order = orderRes.rows[0];

    if (order.courier_id !== courierId) {
      await client.query('ROLLBACK');
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Access denied: You are not the assigned courier for this order',
      });
    }

    if (order.status !== 'accepted') {
      await client.query('ROLLBACK');
      return res
        .status(409)
        .json({ error: 'Conflict', message: 'Order must be in accepted status' });
    }

    if (qrCodeSecureString !== order.qr_code_secure_string) {
      await client.query('ROLLBACK');
      return res
        .status(400)
        .json({ error: 'Bad Request', message: 'Invalid QR code: Proof of Pickup failed' });
    }

    // Estimate delivery time assuming 30 km/h average speed
    const distanceKm = parseFloat(order.distance_km);
    const estimatedTime = new Date(Date.now() + (distanceKm / 30) * 3_600_000);

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

    // ── Notify the sender their package has been picked up ──
    notifyOrderCreator(orderId, 'PICKED_UP');

    res.json({ message: 'Order picked up successfully', order: updatedOrder });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('pickupOrder error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  } finally {
    client.release();
  }
};

// ─── completeOrder ────────────────────────────────────────────────────────────

exports.completeOrder = async (req, res) => {
  const { orderId, qrCodeSecureString } = req.body;
  const courierId = req.user.id;

  if (!orderId || !qrCodeSecureString) {
    return res
      .status(400)
      .json({ error: 'Bad Request', message: 'Order ID and QR code string are required' });
  }

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    const orderRes = await client.query('SELECT * FROM orders WHERE id = $1 FOR UPDATE', [
      orderId,
    ]);
    if (orderRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
    }

    const order = orderRes.rows[0];

    if (order.courier_id !== courierId) {
      await client.query('ROLLBACK');
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Access denied: You are not the assigned courier for this order',
      });
    }

    if (order.status !== 'picked_up') {
      await client.query('ROLLBACK');
      return res
        .status(409)
        .json({ error: 'Conflict', message: 'Order must be in picked_up status' });
    }

    if (qrCodeSecureString !== order.qr_code_secure_string) {
      await client.query('ROLLBACK');
      return res
        .status(400)
        .json({ error: 'Bad Request', message: 'Invalid QR Code: Proof of Delivery failed' });
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

    // ── Notify the sender their package has been delivered ──
    notifyOrderCreator(orderId, 'DELIVERED');

    res.json({ message: 'Order completed and delivered successfully', order: updatedOrder });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('completeOrder error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  } finally {
    client.release();
  }
};

// ─── getOrders  (replaces getMyOrders) ────────────────────────────────────────
//
// FIX #2 — DATA VISIBILITY POLICIES
//
// Three distinct data access tiers based on req.user.role:
//
//   ADMIN    → every order in the system (no filter)
//   CUSTOMER → only orders where customer_id (creator_id) = req.user.id
//   COURIER  → orders where courier_id = req.user.id  UNION
//               all PENDING orders (so they can discover & claim new jobs)
//
// The optional ?status= query-param filter is honoured for CUSTOMER and
// COURIER tiers.  Admins always receive all statuses.
// ─────────────────────────────────────────────────────────────────────────────
exports.getOrders = async (req, res) => {
  const { id: userId, role } = req.user;
  const rawStatus = req.query.status;
  const statusList = rawStatus ? rawStatus.split(',').map((s) => s.trim().toLowerCase()) : null;

  try {
    let rows;

    if (role === 'ADMIN') {
      // ── ADMIN: unrestricted view of every order ──
      const result = await db.query(
        `SELECT o.*,
                cu.name  AS creator_name,  cu.phone  AS creator_phone,
                co.name  AS courier_name,  co.phone  AS courier_phone
         FROM   orders o
         LEFT JOIN users cu ON cu.id = o.creator_id
         LEFT JOIN users co ON co.id = o.courier_id
         ORDER  BY o.created_at DESC`
      );
      rows = result.rows;
    } else if (role === 'CUSTOMER') {
      // ── CUSTOMER: strictly their own orders ──
      let query = `
        SELECT o.*,
               cu.name AS creator_name,
               co.name AS courier_name
        FROM   orders o
        JOIN   users cu ON cu.id = o.creator_id
        LEFT JOIN users co ON co.id = o.courier_id
        WHERE  o.creator_id = $1
      `;
      const params = [userId];
      if (statusList) {
        query += ` AND o.status = ANY($2::text[])`;
        params.push(statusList);
      }
      query += ` ORDER BY o.created_at DESC`;
      const result = await db.query(query, params);
      rows = result.rows;
    } else {
      // ── COURIER: their assigned orders + all PENDING orders to discover ──
      // Using UNION DISTINCT to avoid duplicate rows when a pending order is
      // also already assigned to this courier (edge-case safety).
      let assignedQuery = `
        SELECT o.*,
               cu.name AS creator_name,
               co.name AS courier_name
        FROM   orders o
        JOIN   users cu ON cu.id = o.creator_id
        LEFT JOIN users co ON co.id = o.courier_id
        WHERE  o.courier_id = $1
      `;
      const assignedParams = [userId];
      if (statusList) {
        assignedQuery += ` AND o.status = ANY($2::text[])`;
        assignedParams.push(statusList);
      }

      const pendingQuery = `
        SELECT o.*,
               cu.name AS creator_name,
               co.name AS courier_name
        FROM   orders o
        JOIN   users cu ON cu.id = o.creator_id
        LEFT JOIN users co ON co.id = o.courier_id
        WHERE  o.status = 'pending'
          AND  o.courier_id IS NULL
      `;

      // Run both in parallel for speed
      const [assignedRes, pendingRes] = await Promise.all([
        db.query(assignedQuery, assignedParams),
        db.query(pendingQuery),
      ]);

      // Merge and de-duplicate by order id
      const seen = new Set();
      rows = [...assignedRes.rows, ...pendingRes.rows].filter((r) => {
        if (seen.has(r.id)) return false;
        seen.add(r.id);
        return true;
      });

      // Sort merged result set by created_at desc
      rows.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    }

    res.json({ orders: rows.map(toCamel) });
  } catch (err) {
    console.error('getOrders error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

// Keep backward-compatible alias used by GET /api/orders/mine
exports.getMyOrders = exports.getOrders;

// ─── getAvailableOrders ───────────────────────────────────────────────────────

exports.getAvailableOrders = async (req, res) => {
  try {
    const userResult = await db.query('SELECT is_fully_verified FROM users WHERE id = $1', [
      req.user.id,
    ]);
    if (!userResult.rows[0]?.is_fully_verified) {
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Profile verification required to view available orders.',
      });
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

// ─── getNearbyOrders ──────────────────────────────────────────────────────────

exports.getNearbyOrders = async (req, res) => {
  const { lat, lng, radiusKm = 10 } = req.query;

  if (!lat || !lng) {
    return res
      .status(400)
      .json({ error: 'Bad Request', message: 'Latitude (lat) and Longitude (lng) are required.' });
  }

  try {
    const userResult = await db.query('SELECT is_fully_verified FROM users WHERE id = $1', [
      req.user.id,
    ]);
    if (!userResult.rows[0]?.is_fully_verified) {
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Profile verification required to view nearby map feed.',
      });
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

    const nearbyOrders = result.rows.filter((row) => {
      if (!row.pickup_latitude || !row.pickup_longitude) return false;
      return calculateDistanceKm(latNum, lngNum, row.pickup_latitude, row.pickup_longitude) <= radiusNum;
    });

    res.json({ orders: nearbyOrders.map(toCamel) });
  } catch (err) {
    console.error('getNearbyOrders error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

// ─── getOrderById ─────────────────────────────────────────────────────────────

exports.getOrderById = async (req, res) => {
  const { id } = req.params;
  const { id: userId, role } = req.user;

  try {
    const result = await db.query(
      `SELECT o.*,
         cust.name   AS creator_name,  cust.phone  AS creator_phone,
         cust.sender_rating            AS creator_rating,
         cour.name   AS courier_name,  cour.phone  AS courier_phone,
         cour.courier_rating,          cour.is_fully_verified AS courier_is_verified,
         cour.current_latitude         AS courier_latitude,
         cour.current_longitude        AS courier_longitude
       FROM orders o
       JOIN  users cust ON cust.id = o.creator_id
       LEFT JOIN users cour ON cour.id = o.courier_id
       WHERE o.id = $1`,
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
    }

    const order = result.rows[0];

    // Admins see everything; customers and couriers only see orders they are party to
    const isParty = order.creator_id === userId || order.courier_id === userId;
    const isPending = order.status === 'pending'; // couriers can browse pending orders
    if (role !== 'ADMIN' && !isParty && !isPending) {
      return res.status(403).json({ error: 'Forbidden', message: 'Access denied' });
    }

    res.json({ order: toCamel(order) });
  } catch (err) {
    console.error('getOrderById error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

// ─── updateOrderStatus ────────────────────────────────────────────────────────

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
    const userRes = await db.query('SELECT is_fully_verified, role FROM users WHERE id = $1', [
      userId,
    ]);
    const user = userRes.rows[0];
    if (!user) return res.status(404).json({ error: 'Not Found', message: 'User not found' });

    // Only ADMINs can force-override order status via this generic endpoint
    if (user.role.toUpperCase() === 'ADMIN') {
      const updated = await db.query(
        `UPDATE orders SET status = $1, updated_at = NOW() WHERE id = $2 RETURNING *`,
        [status, id]
      );
      if (updated.rows.length === 0) {
        return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
      }
      const camelOrder = toCamel(updated.rows[0]);
      wsManager.broadcastOrderEvent(camelOrder, `order_${status}`);
      return res.json({ message: `Order forced to ${status} by admin`, order: camelOrder });
    }

    return res.status(403).json({
      error: 'Forbidden',
      message: 'Please use the specific endpoints (accept, pickup, complete) instead',
    });
  } catch (err) {
    console.error('updateOrderStatus error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

// ─── getMyStats ───────────────────────────────────────────────────────────────

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

    const stats = { pending: 0, accepted: 0, pickedUp: 0, delivered: 0, cancelled: 0 };
    result.rows.forEach((r) => {
      // Normalise DB snake_case keys to camelCase for the stats map
      const key = r.status.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
      stats[key] = r.count;
    });
    res.json({ stats });
  } catch (err) {
    console.error('getMyStats error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

// ─── rateOrder ────────────────────────────────────────────────────────────────

exports.rateOrder = async (req, res) => {
  const { id } = req.params;
  const { rating } = req.body;
  const userId = req.user.id;

  if (rating < 1 || rating > 5) {
    return res
      .status(400)
      .json({ error: 'Bad Request', message: 'Rating must be between 1 and 5' });
  }

  try {
    const { rows } = await db.query('SELECT * FROM orders WHERE id = $1', [id]);
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
    }
    const order = rows[0];

    if (order.status !== 'delivered') {
      return res
        .status(400)
        .json({ error: 'Bad Request', message: 'Can only rate delivered orders' });
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

    if (!targetUserId) {
      return res.status(400).json({ error: 'Bad Request', message: 'Target user not found' });
    }

    await db.query(
      `UPDATE users
       SET ${ratingColumn} = LEAST(5.00, GREATEST(1.00, ((${ratingColumn} * 4) + $1) / 5.0))
       WHERE id = $2`,
      [rating, targetUserId]
    );

    res.json({ message: 'Rating submitted successfully' });
  } catch (err) {
    console.error('rateOrder error:', err);
    res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  }
};

// ─── lockEscrow ───────────────────────────────────────────────────────────────
//
// Called when an order is accepted by a courier.  Verifies the sender has
// sufficient wallet funds, then atomically moves the order's total_price from
// the sender's wallet into the order's escrow_balance column.
//
// POST /api/orders/:id/escrow/lock
// ─────────────────────────────────────────────────────────────────────────────
exports.lockEscrow = async (req, res) => {
  const orderId   = req.params.id;
  const senderId  = req.user.id;

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    // 1. Fetch the order and verify ownership + status
    const orderRes = await client.query(
      'SELECT * FROM orders WHERE id = $1 FOR UPDATE',
      [orderId]
    );
    if (orderRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
    }
    const order = orderRes.rows[0];

    if (order.creator_id !== senderId) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'Forbidden', message: 'Only the order creator can lock escrow' });
    }

    if (order.status !== 'accepted') {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: 'Conflict',
        message: 'Escrow can only be locked on an accepted order',
      });
    }

    if (parseFloat(order.escrow_balance) > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Conflict', message: 'Escrow already locked for this order' });
    }

    const amount = parseFloat(order.total_price);

    // 2. Upsert sender wallet (create with 0 balance if first time)
    await client.query(
      `INSERT INTO wallets (user_id, balance) VALUES ($1, 0)
       ON CONFLICT (user_id) DO NOTHING`,
      [senderId]
    );

    // 3. Check sufficient balance
    const walletRes = await client.query(
      'SELECT balance FROM wallets WHERE user_id = $1 FOR UPDATE',
      [senderId]
    );
    const senderBalance = parseFloat(walletRes.rows[0]?.balance ?? 0);
    if (senderBalance < amount) {
      await client.query('ROLLBACK');
      return res.status(402).json({
        error: 'Payment Required',
        message: `Insufficient wallet balance. Required: TZS ${amount}, Available: TZS ${senderBalance}`,
      });
    }

    // 4. Deduct from sender wallet
    await client.query(
      'UPDATE wallets SET balance = balance - $1, updated_at = NOW() WHERE user_id = $2',
      [amount, senderId]
    );

    // 5. Lock amount into order escrow_balance
    await client.query(
      'UPDATE orders SET escrow_balance = $1, updated_at = NOW() WHERE id = $2',
      [amount, orderId]
    );

    // 6. Log the hold in wallet_ledger
    const senderWalletRes = await client.query('SELECT id FROM wallets WHERE user_id = $1', [senderId]);
    const senderWalletId  = senderWalletRes.rows[0].id;
    const balanceAfter    = senderBalance - amount;

    await client.query(
      `INSERT INTO wallet_ledger
         (wallet_id, transaction_type, amount, reference_type, reference_id, balance_after)
       VALUES ($1, 'hold', $2, 'order', $3, $4)`,
      [senderWalletId, amount, orderId, balanceAfter]
    );

    await client.query('COMMIT');

    console.log(`[Escrow] Locked TZS ${amount} for order ${orderId}`);
    return res.json({
      success: true,
      message: `TZS ${amount} locked in escrow for order ${orderId}`,
      escrowBalance: amount,
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('lockEscrow error:', err);
    return res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  } finally {
    client.release();
  }
};

// ─── releaseEscrowPayment ─────────────────────────────────────────────────────
//
// Atomically releases the escrowed funds to the courier upon verified delivery.
// This is the most financially critical endpoint — every step is inside a single
// DB transaction; any fault triggers ROLLBACK.
//
// Sequence (must succeed entirely or not at all):
//   1. Verify order is in 'delivered' status
//   2. Verify escrow_balance > 0
//   3. Zero the order's escrow_balance
//   4. Upsert courier wallet, credit the payout
//   5. Write immutable wallet_ledger audit row
//   6. COMMIT
//
// POST /api/orders/:id/escrow/release  (ADMIN or COURIER role)
// ─────────────────────────────────────────────────────────────────────────────
exports.releaseEscrowPayment = async (req, res) => {
  const orderId  = req.params.id;
  const callerId = req.user.id;
  const callerRole = req.user.role;

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    // ── Step 1: Fetch and lock the order row ──────────────────────────────────
    const orderRes = await client.query(
      'SELECT * FROM orders WHERE id = $1 FOR UPDATE',
      [orderId]
    );
    if (orderRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Not Found', message: 'Order not found' });
    }
    const order = orderRes.rows[0];

    // Only the assigned courier or an admin may trigger release
    if (callerRole !== 'ADMIN' && order.courier_id !== callerId) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'Forbidden', message: 'Not authorised to release this escrow' });
    }

    // ── Step 2: Delivery must be confirmed ────────────────────────────────────
    if (order.status !== 'delivered') {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: 'Conflict',
        message: `Cannot release escrow: order status is '${order.status}', must be 'delivered'`,
      });
    }

    const escrowAmount = parseFloat(order.escrow_balance ?? 0);
    if (escrowAmount <= 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: 'Conflict',
        message: 'No escrow funds to release for this order',
      });
    }

    const courierId = order.courier_id;

    // ── Step 3: Zero the escrow balance on the order ──────────────────────────
    await client.query(
      'UPDATE orders SET escrow_balance = 0, updated_at = NOW() WHERE id = $1',
      [orderId]
    );

    // ── Step 4: Upsert courier wallet and credit payout ───────────────────────
    await client.query(
      `INSERT INTO wallets (user_id, balance) VALUES ($1, $2)
       ON CONFLICT (user_id) DO UPDATE
         SET balance     = wallets.balance + EXCLUDED.balance,
             updated_at  = NOW()`,
      [courierId, escrowAmount]
    );

    // ── Step 5: Write immutable audit entry to wallet_ledger ──────────────────
    const courierWalletRes = await client.query(
      'SELECT id, balance FROM wallets WHERE user_id = $1',
      [courierId]
    );
    const courierWalletId = courierWalletRes.rows[0].id;
    const balanceAfter    = parseFloat(courierWalletRes.rows[0].balance);

    await client.query(
      `INSERT INTO wallet_ledger
         (wallet_id, transaction_type, amount, reference_type, reference_id, balance_after)
       VALUES ($1, 'credit', $2, 'order', $3, $4)`,
      [courierWalletId, escrowAmount, orderId, balanceAfter]
    );

    // ── Step 6: COMMIT ─────────────────────────────────────────────────────────
    await client.query('COMMIT');

    console.log(`[Escrow] Released TZS ${escrowAmount} to courier ${courierId} for order ${orderId}`);

    // Fire non-blocking push to courier
    try {
      const tokenRes = await db.query('SELECT device_token FROM users WHERE id = $1', [courierId]);
      const token = tokenRes.rows[0]?.device_token;
      if (token) {
        await sendPushNotification(
          token,
          'Payment Received 💰',
          `TZS ${escrowAmount.toLocaleString()} has been credited to your wallet!`
        );
      }
    } catch (_) {}

    return res.json({
      success: true,
      message: `TZS ${escrowAmount} released to courier successfully`,
      courierId,
      amountPaid: escrowAmount,
      newBalance: balanceAfter,
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('releaseEscrowPayment error:', err);
    return res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
  } finally {
    client.release();
  }
};

