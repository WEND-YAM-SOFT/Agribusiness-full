const express = require('express');
const crypto = require('crypto');
const { authenticate, requireRole } = require('../middleware/auth');
const { getAdminClient, mapRole, mergeFullName, toPublicUser, logAudit } = require('../services/supabase');

const router = express.Router();

router.use(authenticate, requireRole('admin'));

async function getOrCreateDefaultCompanyId(client) {
  const { data: existing } = await client.from('entreprises').select('id').limit(1).maybeSingle();
  if (existing?.id) return existing.id;
  const created = await client.from('entreprises').insert({ nom: 'Entreprise principale' }).select('id').single();
  if (created.error) throw new Error(created.error.message);
  return created.data.id;
}

function toPublic(profile, authUser) {
  const metadata = authUser?.user_metadata || {};
  return toPublicUser({
    ...profile,
    email: authUser?.email || '',
    telephone: metadata.telephone || '',
    permissions: Array.isArray(metadata.permissions) ? metadata.permissions : [],
    actif: metadata.actif !== false,
    must_change_password: metadata.mustChangePassword === true,
    derniere_connexion_at: metadata.derniereConnexionAt || null,
  }, authUser?.email || '');
}

function normalizeInternationalPhone(value) {
  const input = String(value || '').trim();
  if (!input) return '';

  const match = input.match(/^\+(\d{1,4})\s*(.*)$/);
  if (!match) return null;

  const countryCode = `+${match[1]}`;
  const localDigits = (match[2] || '').replace(/\D/g, '');
  if (localDigits.length < 6) return null;

  const grouped = localDigits.match(/.{1,2}/g) || [];
  return `${countryCode} ${grouped.join(' ')}`.trim();
}

router.get('/', async (req, res) => {
  try {
    const client = getAdminClient();
    const usersPage = await client.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (usersPage.error) return res.status(500).json({ message: usersPage.error.message });

    const ids = (usersPage.data.users || []).map((u) => u.id);
    const profilesResponse = await client.from('profiles').select('*').in('id', ids);
    if (profilesResponse.error) return res.status(500).json({ message: profilesResponse.error.message });

    const profileById = new Map((profilesResponse.data || []).map((p) => [p.id, p]));
    const users = (usersPage.data.users || [])
      .map((u) => {
        const p = profileById.get(u.id);
        if (!p) return null;
        return toPublic(p, u);
      })
      .filter(Boolean)
      .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));

    return res.json(users);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.post('/', async (req, res) => {
  try {
    const client = getAdminClient();
    const companyId = req.body.company_id || (await getOrCreateDefaultCompanyId(client));

    const tempPassword = req.body.motDePasseTemporaire || crypto.randomBytes(5).toString('hex');
    const email = (req.body.email || '').trim().toLowerCase();
    const nom = (req.body.nom || '').trim();
    const prenom = (req.body.prenom || '').trim();
    const role = mapRole(req.body.role);
    const telephone = normalizeInternationalPhone(req.body.telephone || '');

    if (!telephone) {
      return res.status(400).json({ message: 'Téléphone invalide. Format attendu: +221 77 12 34 56' });
    }

    const created = await client.auth.admin.createUser({
      email,
      password: tempPassword,
      email_confirm: true,
      user_metadata: {
        nom,
        prenom,
        telephone,
        permissions: Array.isArray(req.body.permissions) ? req.body.permissions : [],
        actif: true,
        mustChangePassword: true,
      },
    });
    if (created.error) return res.status(400).json({ message: created.error.message });

    const profileInsert = await client.from('profiles').insert({
      id: created.data.user.id,
      company_id: companyId,
      role,
      full_name: mergeFullName(nom, prenom) || email,
    }).select('*').single();
    if (profileInsert.error) {
      // Roll back auth user to avoid a stuck "already registered" email without profile row.
      await client.auth.admin.deleteUser(created.data.user.id);
      return res.status(400).json({ message: profileInsert.error.message });
    }

    await logAudit(client, {
      userId: req.user.id || req.user._id,
      userEmail: req.user.email,
      action: 'user.create',
      targetType: 'Utilisateur',
      targetId: created.data.user.id,
      metadata: { email, role },
      ip: '',
    });

    return res.status(201).json({
      utilisateur: toPublic(profileInsert.data, created.data.user),
      motDePasseTemporaire: tempPassword,
    });
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const client = getAdminClient();
    const userData = await client.auth.admin.getUserById(req.params.id);
    if (userData.error || !userData.data?.user) return res.status(404).json({ message: 'Utilisateur non trouvé' });

    const authUser = userData.data.user;
    const metadata = authUser.user_metadata || {};

    const nom = req.body.nom !== undefined ? String(req.body.nom) : String(metadata.nom || '');
    const prenom = req.body.prenom !== undefined ? String(req.body.prenom) : String(metadata.prenom || '');
    const telephone = req.body.telephone !== undefined
      ? normalizeInternationalPhone(String(req.body.telephone))
      : String(metadata.telephone || '');
    if (req.body.telephone !== undefined && !telephone) {
      return res.status(400).json({ message: 'Téléphone invalide. Format attendu: +221 77 12 34 56' });
    }
    const permissions = Array.isArray(req.body.permissions) ? req.body.permissions : (Array.isArray(metadata.permissions) ? metadata.permissions : []);
    const actif = req.body.actif !== undefined ? Boolean(req.body.actif) : metadata.actif !== false;
    const role = req.body.role !== undefined ? mapRole(req.body.role) : mapRole((await client.from('profiles').select('role').eq('id', req.params.id).single()).data?.role);

    const authUpdate = await client.auth.admin.updateUserById(req.params.id, {
      email: req.body.email ? String(req.body.email).trim().toLowerCase() : authUser.email,
      user_metadata: {
        ...metadata,
        nom,
        prenom,
        telephone,
        permissions,
        actif,
      },
    });
    if (authUpdate.error) return res.status(400).json({ message: authUpdate.error.message });

    const profileUpdate = await client
      .from('profiles')
      .update({ role, full_name: mergeFullName(nom, prenom) || authUpdate.data.user.email })
      .eq('id', req.params.id)
      .select('*')
      .single();
    if (profileUpdate.error) return res.status(400).json({ message: profileUpdate.error.message });

    await logAudit(client, {
      userId: req.user.id || req.user._id,
      userEmail: req.user.email,
      action: 'user.update',
      targetType: 'Utilisateur',
      targetId: req.params.id,
      metadata: { email: authUpdate.data.user.email, role, actif },
      ip: '',
    });

    return res.json(toPublic(profileUpdate.data, authUpdate.data.user));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/:id/activer', async (req, res) => {
  try {
    const client = getAdminClient();
    const userData = await client.auth.admin.getUserById(req.params.id);
    if (userData.error || !userData.data?.user) return res.status(404).json({ message: 'Utilisateur non trouvé' });

    const metadata = userData.data.user.user_metadata || {};
    const updated = await client.auth.admin.updateUserById(req.params.id, {
      user_metadata: { ...metadata, actif: true },
    });
    if (updated.error) return res.status(400).json({ message: updated.error.message });

    const profile = await client.from('profiles').select('*').eq('id', req.params.id).single();
    if (profile.error) return res.status(400).json({ message: profile.error.message });

    await logAudit(client, {
      userId: req.user.id || req.user._id,
      userEmail: req.user.email,
      action: 'user.activate',
      targetType: 'Utilisateur',
      targetId: req.params.id,
      metadata: { email: updated.data.user.email },
      ip: '',
    });

    return res.json(toPublic(profile.data, updated.data.user));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/:id/desactiver', async (req, res) => {
  try {
    if (String(req.params.id) === String(req.user.id || req.user._id)) {
      return res.status(400).json({ message: 'Vous ne pouvez pas désactiver votre propre compte' });
    }

    const client = getAdminClient();
    const userData = await client.auth.admin.getUserById(req.params.id);
    if (userData.error || !userData.data?.user) return res.status(404).json({ message: 'Utilisateur non trouvé' });

    const metadata = userData.data.user.user_metadata || {};
    const updated = await client.auth.admin.updateUserById(req.params.id, {
      user_metadata: { ...metadata, actif: false },
    });
    if (updated.error) return res.status(400).json({ message: updated.error.message });

    const profile = await client.from('profiles').select('*').eq('id', req.params.id).single();
    if (profile.error) return res.status(400).json({ message: profile.error.message });

    await logAudit(client, {
      userId: req.user.id || req.user._id,
      userEmail: req.user.email,
      action: 'user.deactivate',
      targetType: 'Utilisateur',
      targetId: req.params.id,
      metadata: { email: updated.data.user.email },
      ip: '',
    });

    return res.json(toPublic(profile.data, updated.data.user));
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/:id/reset-password', async (req, res) => {
  try {
    const client = getAdminClient();
    const userData = await client.auth.admin.getUserById(req.params.id);
    if (userData.error || !userData.data?.user) return res.status(404).json({ message: 'Utilisateur non trouvé' });

    const tempPassword = req.body.motDePasseTemporaire || crypto.randomBytes(5).toString('hex');
    const metadata = userData.data.user.user_metadata || {};

    const updated = await client.auth.admin.updateUserById(req.params.id, {
      password: tempPassword,
      user_metadata: {
        ...metadata,
        mustChangePassword: true,
      },
    });

    if (updated.error) return res.status(400).json({ message: updated.error.message });

    await logAudit(client, {
      userId: req.user.id || req.user._id,
      userEmail: req.user.email,
      action: 'user.reset_password',
      targetType: 'Utilisateur',
      targetId: req.params.id,
      metadata: { email: updated.data.user.email },
      ip: '',
    });

    return res.json({ message: 'Mot de passe réinitialisé', motDePasseTemporaire: tempPassword });
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    if (String(req.params.id) === String(req.user.id || req.user._id)) {
      return res.status(400).json({ message: 'Suppression de votre compte impossible' });
    }

    const client = getAdminClient();
    const userData = await client.auth.admin.getUserById(req.params.id);
    if (userData.error || !userData.data?.user) return res.status(404).json({ message: 'Utilisateur non trouvé' });

    const profile = await client.from('profiles').select('*').eq('id', req.params.id).maybeSingle();
    if (profile.error) return res.status(400).json({ message: profile.error.message });

    const deletedProfile = await client.from('profiles').delete().eq('id', req.params.id);
    if (deletedProfile.error) return res.status(400).json({ message: deletedProfile.error.message });

    const deleted = await client.auth.admin.deleteUser(req.params.id);
    if (deleted.error) {
      if (profile.data) {
        await client.from('profiles').upsert(profile.data);
      }
      return res.status(400).json({ message: deleted.error.message });
    }

    await logAudit(client, {
      userId: req.user.id || req.user._id,
      userEmail: req.user.email,
      action: 'user.delete',
      targetType: 'Utilisateur',
      targetId: req.params.id,
      metadata: { email: userData.data.user.email },
      ip: '',
    });

    return res.json({ message: 'Utilisateur supprimé' });
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

module.exports = router;
