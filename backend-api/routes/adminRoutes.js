const express = require('express');
const router = express.Router();
const adminController = require('../controllers/adminController');
const { authenticateToken, requireAdmin, requireSuperAdmin } = require('../middleware/auth');

// All routes require a valid JWT and at least ADMIN privileges
router.use(authenticateToken);
router.use(requireAdmin);

// Analytics & Metrics
router.get('/metrics', adminController.getMetrics);
router.get('/stats', adminController.getStats); // compatibility alias

// User Management (List & Single)
router.get('/users', adminController.getUsers);
router.get('/users/:id', adminController.getUserById);

// Super Admin restricted CRUD controls
router.put('/users/:id', requireSuperAdmin, adminController.updateUser);
router.delete('/users/:id', requireSuperAdmin, adminController.deleteUser);

// Courier & Operational Verification
router.get('/couriers', adminController.getCouriers);
router.put('/users/:id/verify', adminController.verifyCourier);
router.put('/couriers/:id/verify', adminController.verifyCourier);

// Legacy granular PUT toggles
router.put('/users/:id/role', requireSuperAdmin, adminController.updateUserRole);
router.put('/users/:id/active', adminController.toggleUserActive);

// Order Management
router.get('/orders', adminController.getOrders);
router.put('/orders/:id/cancel', adminController.cancelOrder);

module.exports = router;
