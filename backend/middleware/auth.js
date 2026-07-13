const jwt = require('jsonwebtoken');
const { getAdminClient, toAppRole } = require('../services/supabase');

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
    const client = getAdminClient();
    const { data: profile, error } = await client
      .from('profiles')
      .select('*')
      .eq('id', payload.id)
      .maybeSingle();

    if (error) {
      return res.status(401).json({ message: 'Session invalide' });
    }

    if (!profile || profile.actif === false) {
      return res.status(401).json({ message: 'Session invalide' });
    }

    const fullName = (profile.full_name || profile.fullName || '').toString().trim();
    let prenom = (profile.prenom || '').toString().trim();
    let nom = (profile.nom || '').toString().trim();
    if ((!prenom || !nom) && fullName) {
      const parts = fullName.split(/\s+/).filter(Boolean);
      if (parts.length === 1) {
        prenom = prenom || parts[0];
        nom = nom || parts[0];
      } else if (parts.length > 1) {
        prenom = prenom || parts[0];
        nom = nom || parts.slice(1).join(' ');
      }
    }

    req.user = {
      _id: profile.id,
      id: profile.id,
      email: profile.email || '',
      role: toAppRole(profile.role),
      permissions: Array.isArray(profile.permissions) ? profile.permissions : [],
      actif: profile.actif !== false,
      nom,
      prenom,
      nomComplet: fullName,
      fullName,
      telephone: profile.telephone || '',
    };
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
