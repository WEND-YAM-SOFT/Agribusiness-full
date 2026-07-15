const express = require('express');
const { authenticate, requireRole } = require('../middleware/auth');
const { getAdminClient, logAudit } = require('../services/supabase');

const router = express.Router();

router.use(authenticate, requireRole('admin'));

const DEFAULT_REFERENCES = {
  poulet_chair: { dureeJours: 42, poidsFinalG: 2500, consoTotaleKgParTete: 4.2, courbeTheorique: [] },
  poule_pondeuse: { dureeJours: 140, poidsFinalG: 1800, consoTotaleKgParTete: 14.0, courbeTheorique: [] },
  dinde: { dureeJours: 90, poidsFinalG: 7000, consoTotaleKgParTete: 18.0, courbeTheorique: [] },
  canard: { dureeJours: 50, poidsFinalG: 3200, consoTotaleKgParTete: 6.0, courbeTheorique: [] },
  autre: { dureeJours: 45, poidsFinalG: 2500, consoTotaleKgParTete: 5.0, courbeTheorique: [] },
};

function defaultConfig() {
  return {
    key: 'main',
    nomApplication: 'AgriBusiness',
    devise: 'FCFA',
    langue: 'fr',
    sessionTimeoutMinutes: 30,
    theme: 'light',
    notificationsEmail: false,
    referencesTheoriques: DEFAULT_REFERENCES,
    notes: '',
  };
}

async function ensureConfig(client) {
  const current = await client.from('app_config').select('*').eq('key', 'main').maybeSingle();
  if (current.error) throw new Error(current.error.message);
  if (current.data) return current.data;

  const created = await client.from('app_config').insert(defaultConfig()).select('*').single();
  if (created.error) throw new Error(created.error.message);
  return created.data;
}

router.get('/', async (req, res) => {
  try {
    const client = getAdminClient();
    const config = await ensureConfig(client);
    return res.json(config);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.put('/', async (req, res) => {
  try {
    const client = getAdminClient();
    const existing = await ensureConfig(client);

    const allowedFields = [
      'nomApplication',
      'devise',
      'langue',
      'sessionTimeoutMinutes',
      'theme',
      'notificationsEmail',
      'referencesTheoriques',
      'notes',
    ];

    const updates = {};
    for (const field of allowedFields) {
      if (req.body[field] !== undefined) updates[field] = req.body[field];
    }

    const saved = await client
      .from('app_config')
      .update(updates)
      .eq('key', existing.key)
      .select('*')
      .single();

    if (saved.error) return res.status(400).json({ message: saved.error.message });

    await logAudit(client, {
      userId: req.user.id || req.user._id,
      userEmail: req.user.email,
      action: 'config.update',
      targetType: 'AppConfig',
      targetId: existing.key,
      metadata: { updatedFields: Object.keys(req.body || {}) },
      ip: '',
    });

    return res.json(saved.data);
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.get('/audit', async (req, res) => {
  try {
    const client = getAdminClient();
    const logs = await client
      .from('audit_logs')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(300);
    if (logs.error) return res.status(500).json({ message: logs.error.message });

    const rows = logs.data || [];
    const userIds = [...new Set(rows.map((r) => (r.user_id || '').toString()).filter(Boolean))];

    let profileById = new Map();
    if (userIds.length) {
      const profiles = await client
        .from('profiles')
        .select('id,full_name')
        .in('id', userIds);
      if (!profiles.error) {
        profileById = new Map((profiles.data || []).map((p) => [String(p.id), (p.full_name || '').toString().trim()]));
      }
    }

    const mapped = rows.map((row) => {
      const userId = (row.user_id || '').toString();
      const userEmail = (row.user_email || '').toString();
      const actorName = (profileById.get(userId) || '').toString().trim();
      return {
        id: row.id,
        userId,
        userEmail,
        action: row.action || '',
        targetType: row.target_type || '',
        targetId: row.target_id || null,
        metadata: row.metadata || {},
        ip: row.ip || '',
        createdAt: row.created_at || null,
        actor: actorName || userEmail || userId || 'Système',
      };
    });

    return res.json(mapped);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.delete('/audit', async (req, res) => {
  try {
    const client = getAdminClient();
    const cleared = await client.from('audit_logs').delete().neq('id', '00000000-0000-0000-0000-000000000000');
    if (cleared.error) return res.status(500).json({ message: cleared.error.message });

    await logAudit(client, {
      userId: req.user.id || req.user._id,
      userEmail: req.user.email,
      action: 'audit.clear',
      targetType: 'AuditLog',
      targetId: null,
      metadata: { cleared: true },
      ip: '',
    });

    return res.json({ message: 'Audit effacé' });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

module.exports = router;
