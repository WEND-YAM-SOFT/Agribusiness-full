const express = require('express');
const crypto = require('crypto');
const Utilisateur = require('../models/Utilisateur');
const AuditLog = require('../models/AuditLog');
const { authenticate, requireRole } = require('../middleware/auth');

const router = express.Router();

router.use(authenticate, requireRole('admin'));

function normalizeRole(role) {
  return role === 'admin' ? 'admin' : 'utilisateur';
}

async function logAudit(req, action, targetType, targetId, metadata = {}) {
  await AuditLog.create({
    userId: req.user?._id || null,
    userEmail: req.user?.email || '',
    action,
    targetType,
    targetId: targetId || null,
    metadata,
    ip: req.ip || ''
  });
}

router.get('/', async (req, res) => {
  try {
    const users = await Utilisateur.find().sort({ createdAt: -1 });
    res.json(users.map((u) => u.toPublicJson()));
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

router.post('/', async (req, res) => {
  try {
    const { nom, prenom, email, telephone, role, permissions, motDePasseTemporaire } = req.body;
    const exists = await Utilisateur.findOne({ email });
    if (exists) return res.status(400).json({ message: 'Cet email existe déjà' });

    const tempPassword = motDePasseTemporaire || crypto.randomBytes(5).toString('hex');

    const user = await Utilisateur.create({
      nom,
      prenom: prenom || '',
      email,
      telephone: telephone || '',
      role: normalizeRole(role),
      permissions: Array.isArray(permissions) ? permissions : undefined,
      motDePasse: tempPassword,
      mustChangePassword: true,
      actif: true
    });

    await logAudit(req, 'user.create', 'Utilisateur', user._id, { email: user.email, role: user.role });

    res.status(201).json({
      utilisateur: user.toPublicJson(),
      motDePasseTemporaire: tempPassword
    });
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const user = await Utilisateur.findById(req.params.id);
    if (!user) return res.status(404).json({ message: 'Utilisateur non trouvé' });

    const { nom, prenom, email, telephone, role, permissions, actif } = req.body;

    if (email && email !== user.email) {
      const exists = await Utilisateur.findOne({ email, _id: { $ne: user._id } });
      if (exists) return res.status(400).json({ message: 'Cet email existe déjà' });
      user.email = email;
    }

    if (nom !== undefined) user.nom = nom;
    if (prenom !== undefined) user.prenom = prenom;
    if (telephone !== undefined) user.telephone = telephone;
    if (actif !== undefined) user.actif = Boolean(actif);
    if (role !== undefined) user.role = normalizeRole(role);
    if (Array.isArray(permissions)) user.permissions = permissions;

    await user.save();

    await logAudit(req, 'user.update', 'Utilisateur', user._id, {
      email: user.email,
      role: user.role,
      actif: user.actif
    });

    res.json(user.toPublicJson());
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.put('/:id/activer', async (req, res) => {
  try {
    const user = await Utilisateur.findById(req.params.id);
    if (!user) return res.status(404).json({ message: 'Utilisateur non trouvé' });

    user.actif = true;
    await user.save();

    await logAudit(req, 'user.activate', 'Utilisateur', user._id, { email: user.email });

    res.json(user.toPublicJson());
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.put('/:id/desactiver', async (req, res) => {
  try {
    const user = await Utilisateur.findById(req.params.id);
    if (!user) return res.status(404).json({ message: 'Utilisateur non trouvé' });

    if (String(user._id) === String(req.user._id)) {
      return res.status(400).json({ message: 'Vous ne pouvez pas désactiver votre propre compte' });
    }

    user.actif = false;
    await user.save();

    await logAudit(req, 'user.deactivate', 'Utilisateur', user._id, { email: user.email });

    res.json(user.toPublicJson());
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.put('/:id/reset-password', async (req, res) => {
  try {
    const user = await Utilisateur.findById(req.params.id);
    if (!user) return res.status(404).json({ message: 'Utilisateur non trouvé' });

    const tempPassword = req.body.motDePasseTemporaire || crypto.randomBytes(5).toString('hex');
    user.motDePasse = tempPassword;
    user.mustChangePassword = true;
    await user.save();

    await logAudit(req, 'user.reset_password', 'Utilisateur', user._id, { email: user.email });

    res.json({
      message: 'Mot de passe réinitialisé',
      motDePasseTemporaire: tempPassword
    });
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const user = await Utilisateur.findById(req.params.id);
    if (!user) return res.status(404).json({ message: 'Utilisateur non trouvé' });

    if (String(user._id) === String(req.user._id)) {
      return res.status(400).json({ message: 'Suppression de votre compte impossible' });
    }

    await user.deleteOne();

    await logAudit(req, 'user.delete', 'Utilisateur', user._id, { email: user.email });

    res.json({ message: 'Utilisateur supprimé' });
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

module.exports = router;
