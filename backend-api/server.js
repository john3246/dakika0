const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const pool = require('./db');
require('dotenv').config();
const path = require('path');
const http = require('http');
const wsManager = require('./websocket');

const authRoutes = require('./routes/authRoutes');
const profileRoutes = require('./routes/profileRoutes');
const orderRoutes = require('./routes/orderRoutes');
const adminRoutes = require('./routes/adminRoutes');

const app = express();
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
const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});
