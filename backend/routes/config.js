const express = require('express');
const AppConfig = require('../models/AppConfig');
const AuditLog = require('../models/AuditLog');
const { authenticate, requireRole } = require('../middleware/auth');

const router = express.Router();

router.use(authenticate, requireRole('admin'));

async function ensureConfig() {
  let config = await AppConfig.findOne({ key: 'main' });
  if (!config) {
    config = await AppConfig.create({ key: 'main' });
  }
  return config;
}

router.get('/', async (req, res) => {
  try {
    const config = await ensureConfig();
    res.json(config);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

router.put('/', async (req, res) => {
  try {
    const config = await ensureConfig();

    const allowedFields = [
      'nomApplication',
      'devise',
      'langue',
      'sessionTimeoutMinutes',
      'theme',
      'notificationsEmail',
      'referencesTheoriques',
      'notes'
    ];

    for (const field of allowedFields) {
      if (req.body[field] !== undefined) {
        config[field] = req.body[field];
      }
    }

    await config.save();

    await AuditLog.create({
      userId: req.user._id,
      userEmail: req.user.email,
      action: 'config.update',
      targetType: 'AppConfig',
      targetId: config._id,
      metadata: { updatedFields: Object.keys(req.body || {}) },
      ip: req.ip || ''
    });

    res.json(config);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

router.get('/audit', async (req, res) => {
  try {
    const logs = await AuditLog.find().sort({ createdAt: -1 }).limit(300);
    res.json(logs);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

router.delete('/audit', async (req, res) => {
  try {
    await AuditLog.deleteMany({});
    await AuditLog.create({
      userId: req.user._id,
      userEmail: req.user.email,
      action: 'audit.clear',
      targetType: 'AuditLog',
      metadata: { cleared: true },
      ip: req.ip || ''
    });
    res.json({ message: 'Audit effacé' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

module.exports = router;
