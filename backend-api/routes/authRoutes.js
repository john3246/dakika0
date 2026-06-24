const express = require('express');
const router = express.Router();
const authController = require('../controllers/authController');
const { authenticateToken } = require('../middleware/auth');

// Unified Registration route
router.post('/register', authController.register);

// Login route
router.post('/login', authController.login);

// Protected profile route
router.get('/me', authenticateToken, authController.getMe);

module.exports = router;
