const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const Utilisateur = require('../models/Utilisateur');
const PasswordResetToken = require('../models/PasswordResetToken');
const AuditLog = require('../models/AuditLog');
const { authenticate } = require('../middleware/auth');
const { sendPasswordResetEmail } = require('../services/email_service');

function signToken(user) {
  return jwt.sign(
    { id: user._id, role: user.role },
    process.env.JWT_SECRET || 'dev_secret_change_me',
    { expiresIn: '8h' }
  );
}

function normalizeRole(role) {
  return role === 'admin' ? 'admin' : 'utilisateur';
}

async function ensureInitialAdmin() {
  const hasAdmin = await Utilisateur.findOne({ role: 'admin' });
  if (hasAdmin) return;

  const existingDefault = await Utilisateur.findOne({ email: 'admin@agribusiness.local' });
  if (existingDefault) {
    existingDefault.role = 'admin';
    existingDefault.actif = true;
    existingDefault.mustChangePassword = true;
    await existingDefault.save();
    return;
  }

  await Utilisateur.create({
    nom: 'Administrateur',
    prenom: 'Principal',
    email: 'admin@agribusiness.local',
    motDePasse: 'Admin@123',
    role: 'admin',
    mustChangePassword: true,
    actif: true
  });
}

// Inscription
router.post('/inscription', async (req, res) => {
  try {
    await ensureInitialAdmin();

    const existant = await Utilisateur.findOne({ email: req.body.email });
    if (existant) {
      return res.status(400).json({ message: 'Cet email est déjà utilisé' });
    }

    const utilisateur = new Utilisateur({
      nom: req.body.nom,
      prenom: req.body.prenom || '',
      email: req.body.email,
      motDePasse: req.body.motDePasse,
      role: normalizeRole(req.body.role),
      permissions: req.body.permissions,
      telephone: req.body.telephone
    });

    await utilisateur.save();
    const token = signToken(utilisateur);

    res.status(201).json({
      token,
      utilisateur: utilisateur.toPublicJson()
    });
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Connexion
router.post('/connexion', async (req, res) => {
  try {
    await ensureInitialAdmin();

    const utilisateur = await Utilisateur.findOne({ email: req.body.email });
    if (!utilisateur) {
      return res.status(401).json({ message: 'Email ou mot de passe incorrect' });
    }

    const motDePasseValide = await utilisateur.verifierMotDePasse(req.body.motDePasse);
    if (!motDePasseValide) {
      return res.status(401).json({ message: 'Email ou mot de passe incorrect' });
    }

    if (!utilisateur.actif) {
      return res.status(403).json({ message: 'Compte désactivé' });
    }

    if (!['admin', 'utilisateur'].includes(utilisateur.role)) {
      utilisateur.role = 'utilisateur';
    }

    utilisateur.derniereConnexionAt = new Date();
    await utilisateur.save();

    const token = signToken(utilisateur);

    await AuditLog.create({
      userId: utilisateur._id,
      userEmail: utilisateur.email,
      action: 'auth.login',
      targetType: 'Utilisateur',
      targetId: utilisateur._id,
      metadata: {},
      ip: req.ip || ''
    });

    res.json({
      token,
      utilisateur: utilisateur.toPublicJson(),
      sessionTimeoutMinutes: 30
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Obtenir le profil
router.get('/profil', authenticate, async (req, res) => {
  try {
    const utilisateur = await Utilisateur.findById(req.user._id).select('-motDePasse');
    if (!utilisateur) return res.status(404).json({ message: 'Utilisateur non trouvé' });

    res.json(utilisateur.toPublicJson());
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

router.put('/profil', authenticate, async (req, res) => {
  try {
    const utilisateur = await Utilisateur.findById(req.user._id);
    if (!utilisateur) return res.status(404).json({ message: 'Utilisateur non trouvé' });

    const { nom, prenom, email, telephone } = req.body;

    if (email && email !== utilisateur.email) {
      const exists = await Utilisateur.findOne({ email, _id: { $ne: utilisateur._id } });
      if (exists) return res.status(400).json({ message: 'Cet email existe déjà' });
      utilisateur.email = email;
    }

    if (nom !== undefined) utilisateur.nom = nom;
    if (prenom !== undefined) utilisateur.prenom = prenom;
    if (telephone !== undefined) utilisateur.telephone = telephone;

    await utilisateur.save();

    await AuditLog.create({
      userId: utilisateur._id,
      userEmail: utilisateur.email,
      action: 'auth.profile_update',
      targetType: 'Utilisateur',
      targetId: utilisateur._id,
      metadata: {},
      ip: req.ip || ''
    });

    res.json(utilisateur.toPublicJson());
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.put('/mot-de-passe', authenticate, async (req, res) => {
  try {
    const { motDePasseActuel, nouveauMotDePasse } = req.body;
    const utilisateur = await Utilisateur.findById(req.user._id);
    if (!utilisateur) return res.status(404).json({ message: 'Utilisateur non trouvé' });

    const ok = await utilisateur.verifierMotDePasse(motDePasseActuel || '');
    if (!ok) return res.status(400).json({ message: 'Mot de passe actuel incorrect' });

    utilisateur.motDePasse = nouveauMotDePasse;
    utilisateur.mustChangePassword = false;
    await utilisateur.save();

    await AuditLog.create({
      userId: utilisateur._id,
      userEmail: utilisateur.email,
      action: 'auth.change_password',
      targetType: 'Utilisateur',
      targetId: utilisateur._id,
      metadata: {},
      ip: req.ip || ''
    });

    res.json({ message: 'Mot de passe mis à jour' });
  } catch (err) {
    const status = err.message && err.message.toLowerCase().includes('service email') ? 503 : 400;
    res.status(status).json({ message: err.message });
  }
});

router.post('/mot-de-passe/oublie', async (req, res) => {
  try {
    const email = (req.body.email || '').trim().toLowerCase();
    const user = await Utilisateur.findOne({ email });
    if (!user) {
      return res.json({
        message: 'Si cet email existe, un email de réinitialisation a été envoyé.'
      });
    }

    await PasswordResetToken.deleteMany({ userId: user._id, usedAt: null });

    const rawToken = crypto.randomBytes(24).toString('hex');
    const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
    const expiresAt = new Date(Date.now() + 30 * 60 * 1000);

    await PasswordResetToken.create({ userId: user._id, tokenHash, expiresAt });

    await AuditLog.create({
      userId: user._id,
      userEmail: user.email,
      action: 'auth.request_password_reset',
      targetType: 'Utilisateur',
      targetId: user._id,
      metadata: {},
      ip: req.ip || ''
    });

    await sendPasswordResetEmail({
      to: user.email,
      userName: `${user.prenom || ''} ${user.nom || ''}`.trim() || user.email,
      token: rawToken,
      expiresMinutes: 30
    });

    res.json({
      message: 'Un email de réinitialisation a été envoyé.'
    });
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.post('/mot-de-passe/reinitialiser', async (req, res) => {
  try {
    const { token, nouveauMotDePasse } = req.body;
    const tokenHash = crypto.createHash('sha256').update(token || '').digest('hex');

    const reset = await PasswordResetToken.findOne({
      tokenHash,
      usedAt: null,
      expiresAt: { $gt: new Date() }
    });

    if (!reset) return res.status(400).json({ message: 'Token invalide ou expiré' });

    const user = await Utilisateur.findById(reset.userId);
    if (!user) return res.status(404).json({ message: 'Utilisateur non trouvé' });

    user.motDePasse = nouveauMotDePasse;
    user.mustChangePassword = false;
    await user.save();

    reset.usedAt = new Date();
    await reset.save();

    await AuditLog.create({
      userId: user._id,
      userEmail: user.email,
      action: 'auth.reset_password',
      targetType: 'Utilisateur',
      targetId: user._id,
      metadata: {},
      ip: req.ip || ''
    });

    res.json({ message: 'Mot de passe réinitialisé avec succès' });
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.post('/deconnexion', authenticate, async (req, res) => {
  await AuditLog.create({
    userId: req.user._id,
    userEmail: req.user.email,
    action: 'auth.logout',
    targetType: 'Utilisateur',
    targetId: req.user._id,
    metadata: {},
    ip: req.ip || ''
  });
  res.json({ message: 'Déconnecté' });
});

module.exports = router;
