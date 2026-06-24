const express = require('express');
const router = express.Router();
const adminController = require('../controllers/adminController');
const { authenticateToken, requireAdmin, requireSuperAdmin } = require('../middleware/auth');

router.use(authenticateToken);
router.use(requireAdmin);

router.get('/stats', adminController.getStats);
router.get('/users', adminController.getUsers);
router.get('/couriers', adminController.getCouriers);
router.put('/users/:id/role', requireSuperAdmin, adminController.updateUserRole);
router.put('/users/:id/active', adminController.toggleUserActive);
router.put('/users/:id/verify', adminController.verifyCourier);
router.put('/couriers/:id/verify', adminController.verifyCourier);
router.get('/orders', adminController.getOrders);
router.put('/orders/:id/cancel', adminController.cancelOrder);

module.exports = router;
