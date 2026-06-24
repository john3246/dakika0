const ws = require('ws');
const jwt = require('jsonwebtoken');
const db = require('./db');

// Map of userId -> Set of WebSocket connections (supporting multiple devices/tabs per user)
const clients = new Map();

// Helper to calculate distance
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

// Initialize WebSocket server
function initWebSocket(server) {
  const wss = new ws.Server({ noServer: true });

  server.on('upgrade', (request, socket, head) => {
    const url = new URL(request.url, `http://${request.headers.host}`);
    const token = url.searchParams.get('token');

    if (!token) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }

    jwt.verify(token, process.env.JWT_SECRET, async (err, decoded) => {
      if (err) {
        socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
        socket.destroy();
        return;
      }

      try {
        const result = await db.query(
          'SELECT id, name, email, role, is_active, courier_status, is_fully_verified FROM users WHERE id = $1',
          [decoded.id]
        );

        if (result.rows.length === 0 || !result.rows[0].is_active) {
          socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
          socket.destroy();
          return;
        }

        const user = result.rows[0];
        wss.handleUpgrade(request, socket, head, (wsConnection) => {
          wsConnection.user = user;
          wss.emit('connection', wsConnection, request);
        });
      } catch (dbError) {
        console.error('WS upgrade DB error:', dbError);
        socket.write('HTTP/1.1 500 Internal Server Error\r\n\r\n');
        socket.destroy();
      }
    });
  });

  wss.on('connection', (socket) => {
    const user = socket.user;
    console.log(`[WS] User connected: ${user.name} (${user.role})`);

    // Add to active clients map
    if (!clients.has(user.id)) {
      clients.set(user.id, new Set());
    }
    clients.get(user.id).add(socket);

    // If super_admin or admin, send initial list of active couriers
    if (user.role && user.role.toUpperCase() === 'ADMIN') {
      sendActiveCouriers(socket);
    }

    socket.on('message', async (messageData) => {
      try {
        const data = JSON.parse(messageData);
        switch (data.type) {
          case 'location_update':
            await handleLocationUpdate(user.id, data.latitude, data.longitude);
            break;
          default:
            console.log(`[WS] Unknown message type: ${data.type}`);
        }
      } catch (error) {
        console.error('[WS] Error handling message:', error);
      }
    });

    socket.on('close', () => {
      console.log(`[WS] User disconnected: ${user.name}`);
      const userSockets = clients.get(user.id);
      if (userSockets) {
        userSockets.delete(socket);
        if (userSockets.size === 0) {
          clients.delete(user.id);
        }
      }
      // Broadcast disconnect to admins
      broadcastToAdmins({
        type: 'courier_offline',
        userId: user.id
      });
    });
  });

  console.log('WebSocket Server Initialized successfully.');
}

// Handle location update from client
async function handleLocationUpdate(userId, lat, lng) {
  if (lat == null || lng == null) return;

  try {
    // 1. Update in Postgres
    const result = await db.query(
      `UPDATE users 
       SET current_latitude = $1, current_longitude = $2, updated_at = NOW() 
       WHERE id = $3 
       RETURNING id, name, role, courier_status, is_fully_verified, current_latitude, current_longitude`,
      [lat, lng, userId]
    );

    const user = result.rows[0];
    if (!user) return;

    // 2. Broadcast to admins (for dashboard tracking)
    broadcastToAdmins({
      type: 'courier_location_update',
      courier: {
        id: user.id,
        name: user.name,
        role: user.role,
        isFullyVerified: user.is_fully_verified,
        currentLatitude: user.current_latitude,
        currentLongitude: user.current_longitude
      }
    });

    // 3. Broadcast to order senders if courier is tracking/active on their order
    // Find active orders where this user is the courier
    const activeOrders = await db.query(
      `SELECT id, customer_id FROM orders WHERE courier_id = $1 AND status IN ('ACCEPTED', 'PICKED_UP')`,
      [userId]
    );

    for (const order of activeOrders.rows) {
      sendToUser(order.customer_id, {
        type: 'delivery_location_update',
        orderId: order.id,
        latitude: lat,
        longitude: lng
      });
    }

  } catch (error) {
    console.error('Error handling location update:', error);
  }
}

// Send active couriers locations to a newly connected admin
async function sendActiveCouriers(socket) {
  try {
    const result = await db.query(
      `SELECT id, name, courier_status, is_fully_verified, current_latitude, current_longitude 
       FROM users 
       WHERE (current_latitude IS NOT NULL AND current_longitude IS NOT NULL) 
         AND (role = 'COURIER' OR is_fully_verified = TRUE)`
    );

    socket.send(JSON.stringify({
      type: 'active_couriers',
      couriers: result.rows.map(row => ({
        id: row.id,
        name: row.name,
        courierStatus: row.courier_status,
        isFullyVerified: row.is_fully_verified,
        currentLatitude: row.current_latitude,
        currentLongitude: row.current_longitude
      }))
    }));
  } catch (error) {
    console.error('Error sending active couriers:', error);
  }
}

// Broadcast order event notifications
function broadcastOrderEvent(order, eventType) {
  // EventTypes: 'order_created', 'order_accepted', 'order_picked_up', 'order_delivered', 'order_cancelled'
  const payload = {
    type: 'order_event',
    eventType,
    order
  };

  // 1. Send to Admins
  broadcastToAdmins(payload);

  // 2. Send to specific customer and courier if assigned
  if (order.customerId) {
    sendToUser(order.customerId, payload);
  }
  if (order.courierId) {
    sendToUser(order.courierId, payload);
  }

  // 3. For new order creation, broadcast to all nearby verified couriers (within 10km)
  if (eventType === 'order_created' && order.pickupLatitude && order.pickupLongitude) {
    db.query(
      `SELECT id, name, current_latitude, current_longitude 
       FROM users 
       WHERE is_fully_verified = TRUE AND current_latitude IS NOT NULL`
    ).then(res => {
      res.rows.forEach(courier => {
        // Exclude the customer who created the order from receiving notifications/accepting
        if (courier.id === order.customerId) return;

        const distance = calculateDistanceKm(
          order.pickupLatitude,
          order.pickupLongitude,
          courier.current_latitude,
          courier.current_longitude
        );

        if (distance <= 10.0) {
          sendToUser(courier.id, {
            type: 'order_broadcast',
            order
          });
          console.log(`[WS Broadcast] Order broadcast sent to nearby courier: ${courier.name}`);
        }
      });
    }).catch(err => console.error('Error broadcasting new order to nearby couriers:', err));
  }
}

// Helper: Send data to all socket connections of a specific user
function sendToUser(userId, data) {
  const userSockets = clients.get(userId);
  if (userSockets) {
    const payload = JSON.stringify(data);
    userSockets.forEach(socket => {
      if (socket.readyState === ws.OPEN) {
        socket.send(payload);
      }
    });
  }
}

// Helper: Send data to all active Admin / Super Admin connections
function broadcastToAdmins(data) {
  const payload = JSON.stringify(data);
  for (const [userId, userSockets] of clients.entries()) {
    userSockets.forEach(socket => {
      if (socket.user && socket.user.role && socket.user.role.toUpperCase() === 'ADMIN') {
        if (socket.readyState === ws.OPEN) {
          socket.send(payload);
        }
      }
    });
  }
}

module.exports = {
  initWebSocket,
  broadcastOrderEvent,
  sendToUser,
  broadcastToAdmins
};
