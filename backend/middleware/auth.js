const jwt = require('jsonwebtoken');
const Utilisateur = require('../models/Utilisateur');

function extractToken(req) {
  const auth = req.headers.authorization || '';
  if (!auth.startsWith('Bearer ')) return null;
  return auth.slice(7);
}

async function authenticate(req, res, next) {
  try {
    const token = extractToken(req);
    if (!token) return res.status(401).json({ message: 'Authentification requise' });

    const payload = jwt.verify(token, process.env.JWT_SECRET || 'dev_secret_change_me');
    const user = await Utilisateur.findById(payload.id).select('-motDePasse');

    if (!user || !user.actif) {
      return res.status(401).json({ message: 'Session invalide' });
    }

    req.user = user;
    next();
  } catch (err) {
    res.status(401).json({ message: 'Token invalide ou expiré' });
  }
}

function requireRole(roles) {
  const allowed = Array.isArray(roles) ? roles : [roles];
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ message: 'Authentification requise' });
    if (!allowed.includes(req.user.role)) {
      return res.status(403).json({ message: 'Accès interdit' });
    }
    next();
  };
}

function requirePermission(permission) {
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ message: 'Authentification requise' });
    if (req.user.role === 'admin') return next();

    const permissions = Array.isArray(req.user.permissions) ? req.user.permissions : [];
    if (!permissions.includes(permission)) {
      return res.status(403).json({ message: 'Permission insuffisante' });
    }
    next();
  };
}

module.exports = {
  authenticate,
  requireRole,
  requirePermission
};
