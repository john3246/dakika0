const express = require('express');
const { getProfile, updateProfile, uploadDocument, upgradeCourier } = require('../controllers/profileController');
const { authenticateToken } = require('../middleware/auth');
const upload = require('../middleware/upload');

const router = express.Router();

// Fetch current user's profile
router.get('/me', authenticateToken, getProfile);

// Update current user's profile
router.put('/update', authenticateToken, updateProfile);

// Upload document or profile image
// Example: POST /upload-document?type=profile OR /upload-document?type=document
router.post('/upload-document', authenticateToken, upload.single('document'), uploadDocument);
// Upgrade to courier (verification)
router.post('/upgrade-courier', authenticateToken, upgradeCourier);

module.exports = router;
