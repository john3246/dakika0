const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const pool = require('./db');
require('dotenv').config();
const path = require('path');
const http = require('http');
const wsManager = require('./websocket');

// ─── Firebase Admin: initialize ONCE globally before any route controllers load ─
// Controllers simply require('firebase-admin') and call admin.messaging() —
// the shared app instance created here will be reused automatically.
// ─── Firebase Admin: initialize ONCE globally before any route controllers load ─
const { initializeApp, getApps } = require('firebase-admin/app');
const { cert } = require('firebase-admin/app');

if (!getApps().length) {
  let serviceAccount;

  // Use Render's environment variable if available, otherwise fall back to local file
  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    try {
      serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    } catch (e) {
      console.error('[Firebase] Failed to parse FIREBASE_SERVICE_ACCOUNT env var:', e);
    }
  } else {
    serviceAccount = require('./firebase-key.json');
  }

  if (serviceAccount) {
    initializeApp({
      credential: cert(serviceAccount),
      projectId: 'dakika0',
    });
    console.log('[Firebase] Admin SDK initialized successfully.');
  } else {
    console.error('[Firebase] Critical: No service account credentials found.');
  }
}
// ──────────────────────────────────────────────────────────────────────────────
// ──────────────────────────────────────────────────────────────────────────────

const authRoutes = require('./routes/authRoutes');
const profileRoutes = require('./routes/profileRoutes');
const orderRoutes = require('./routes/orderRoutes');
const adminRoutes = require('./routes/adminRoutes');

const app = express();
app.set('trust proxy', 1);
const server = http.createServer(app);

// Security Middleware
app.use(helmet());
app.use(helmet.crossOriginResourcePolicy({ policy: "cross-origin" })); // Allow images to be loaded by Flutter

// Rate limiting (max 100 requests per 15 min window)
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: 'Too many requests from this IP, please try again after 15 minutes',
});
app.use('/api', limiter);

// CORS configuration for Flutter / Web
const corsOptions = {
  origin: process.env.NODE_ENV === 'production' 
    ? ['https://your-production-app.com'] // Update this if you have a web frontend. Mobile apps usually bypass CORS.
    : '*',
  optionsSuccessStatus: 200,
};
app.use(cors(corsOptions));
app.use(express.json());
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));
app.use('/admin', express.static(path.join(__dirname, 'public/admin')));

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/profile', profileRoutes);
app.use('/api/orders', orderRoutes);
app.use('/api/admin', adminRoutes);

// Global Error Handler
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Something went wrong!' });
});

async function testDBConnection() {
  try {
    const client = await pool.getClient();
    await client.query('SELECT NOW()');
    console.log('Database connection successful!');
    client.release();
  } catch (err) {
    console.error('Database connection error:', err);
    process.exit(1);
  }
}
testDBConnection();

// Initialize WebSocket
wsManager.initWebSocket(server);

// Start Server
const PORT = process.env.PORT || 5000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});