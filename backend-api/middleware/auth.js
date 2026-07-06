const jwt = require('jsonwebtoken');
const db = require('../db');

/**
 * Verifies the Bearer JWT in Authorization header.
 * Attaches the live DB user record to req.user on success.
 * Rejects expired, missing, or tampered tokens with the appropriate HTTP status.
 */
function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (token == null) {
    return res.status(401).json({ error: 'Unauthorized', message: 'Unauthorized: No token provided' });
  }

  jwt.verify(token, process.env.JWT_SECRET, async (err, decoded) => {
    if (err) {
      // Distinguish expired tokens (403) from malformed tokens (403) — both are Forbidden
      return res.status(403).json({ error: 'Forbidden', message: 'Forbidden: Invalid or expired token' });
    }

    try {
      const result = await db.query(
        'SELECT id, role, is_active, is_fully_verified, courier_status FROM users WHERE id = $1',
        [decoded.id]
      );

      if (result.rows.length === 0) {
        return res.status(401).json({ error: 'Unauthorized', message: 'User not found' });
      }

      const user = result.rows[0];

      if (!user.is_active) {
        return res.status(403).json({ error: 'Forbidden', message: 'Account deactivated' });
      }

      req.user = user;
      next();
    } catch (dbError) {
      console.error('authenticateToken DB error:', dbError);
      res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
    }
  });
}

/**
 * Middleware factory — allows access only to callers whose role is in the
 * provided list.  Roles are compared case-insensitively.
 * Usage: requireRole('ADMIN', 'COURIER')
 */
function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ error: 'Unauthorized', message: 'Unauthorized' });
    }
    const userRole = (req.user.role || '').toUpperCase();
    const targetRoles = roles.map((r) => r.toUpperCase());
    if (!targetRoles.includes(userRole)) {
      return res.status(403).json({
        error: 'Forbidden',
        message: `Forbidden: Access denied. Role '${userRole}' does not match required roles: [${roles.join(', ')}]`,
      });
    }
    next();
  };
}

/**
 * Middleware — rejects the request when the caller's profile is not fully
 * verified.  Performs a live DB check so the flag is always fresh.
 */
function requireVerified(req, res, next) {
  if (!req.user) {
    return res.status(401).json({ error: 'Unauthorized', message: 'Unauthorized' });
  }

  db.query('SELECT is_fully_verified FROM users WHERE id = $1', [req.user.id])
    .then((result) => {
      if (result.rows.length === 0) {
        return res.status(404).json({ error: 'Not Found', message: 'User not found' });
      }
      if (!result.rows[0].is_fully_verified) {
        return res.status(403).json({ error: 'Forbidden', message: 'Forbidden: Profile verification required' });
      }
      next();
    })
    .catch((err) => {
      console.error('requireVerified error:', err);
      res.status(500).json({ error: 'Internal Server Error', message: 'Internal server error' });
    });
}

/**
 * Middleware — allows access only to users with role ADMIN.
 */
function requireAdmin(req, res, next) {
  if (!req.user) {
    return res.status(401).json({ error: 'Unauthorized', message: 'Unauthorized' });
  }
  const role = (req.user.role || '').toUpperCase();
  if (role !== 'ADMIN') {
    return res.status(403).json({ error: 'Forbidden', message: 'Forbidden: Admin access required' });
  }
  next();
}

/**
 * Middleware — Super-admin gate.
 * Both super-admin and standard admin share the ADMIN role in the users table,
 * so this mirrors requireAdmin for now.  A `is_super_admin` column can be
 * added later without touching the route guards.
 */
function requireSuperAdmin(req, res, next) {
  if (!req.user) {
    return res.status(401).json({ error: 'Unauthorized', message: 'Unauthorized' });
  }
  const role = (req.user.role || '').toUpperCase();
  if (role !== 'ADMIN') {
    return res.status(403).json({ error: 'Forbidden', message: 'Forbidden: Admin access required' });
  }
  next();
}

module.exports = {
  authenticateToken,
  requireRole,
  requireVerified,
  requireAdmin,
  requireSuperAdmin,
};
