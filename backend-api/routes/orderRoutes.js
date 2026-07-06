const express = require('express');
const router = express.Router();
const { authenticateToken, requireRole } = require('../middleware/auth');
const {
  createOrder,
  getBroadcasts,
  acceptOrder,
  pickupOrder,
  completeOrder,
  getOrders,
  getMyOrders,
  getAvailableOrders,
  getOrderById,
  updateOrderStatus,
  getMyStats,
  getNearbyOrders,
  rateOrder,
} = require('../controllers/orderController');

// All routes require a valid JWT
router.use(authenticateToken);

// Dynamic lifecycle routes
router.post('/create', requireRole('CUSTOMER'), createOrder);
router.get('/broadcasts', requireRole('COURIER'), getBroadcasts);
router.post('/accept', requireRole('COURIER'), acceptOrder);
router.post('/pickup', requireRole('COURIER'), pickupOrder);
router.post('/complete', requireRole('COURIER'), completeOrder);

// Standard/Compatibility routes
router.post('/', requireRole('CUSTOMER'), createOrder);

// Data visibility endpoints
router.get('/', getOrders);
router.get('/history', getOrders);
router.get('/mine', getMyOrders);

router.get('/stats', getMyStats);
router.get('/available', getAvailableOrders);
router.get('/nearby', getNearbyOrders);
router.get('/:id', getOrderById);
router.patch('/:id/status', updateOrderStatus);
router.post('/:id/rate', rateOrder);

module.exports = router;
