const express = require('express');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { authenticate, requirePermission } = require('../middleware/auth');
const { sendPasswordResetEmail } = require('../services/email_service');
const { getAdminClient, mapRole, mergeFullName, toPublicUser, logAudit } = require('../services/supabase');

const router = express.Router();

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

function signToken(user) {
  return jwt.sign(
    { id: user.id, role: user.role },
    process.env.JWT_SECRET || 'dev_secret_change_me',
    { expiresIn: '8h' }
  );
}

async function getOrCreateDefaultCompanyId(client) {
  const { data: existing, error: readError } = await client
    .from('entreprises')
    .select('id')
    .limit(1)
    .maybeSingle();
  if (readError) throw new Error(readError.message);
  if (existing?.id) return existing.id;

  const { data: created, error: createError } = await client
    .from('entreprises')
    .insert({ nom: 'Entreprise principale' })
    .select('id')
    .single();
  if (createError) throw new Error(createError.message);
  return created.id;
}

async function getProfile(client, userId) {
  const { data, error } = await client
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

async function ensureInitialAdmin() {
  const client = getAdminClient();
  const { data: hasAdmin, error: adminReadError } = await client
    .from('profiles')
    .select('id')
    .eq('role', 'admin')
    .limit(1)
    .maybeSingle();

  if (adminReadError) throw new Error(adminReadError.message);
  if (hasAdmin?.id) return;

  const defaultEmail = 'admin@agribusiness.local';
  const defaultPassword = 'Admin@123';
  const companyId = await getOrCreateDefaultCompanyId(client);

  const { data: users } = await client.auth.admin.listUsers({ page: 1, perPage: 1000 });
  const existing = (users?.users || []).find((u) => (u.email || '').toLowerCase() === defaultEmail);

  let userId = existing?.id;
  if (!userId) {
    const created = await client.auth.admin.createUser({
      email: defaultEmail,
      password: defaultPassword,
      email_confirm: true,
      user_metadata: {
        nom: 'Administrateur',
        prenom: 'Principal',
        telephone: '',
        permissions: [],
        actif: true,
        mustChangePassword: true,
      },
    });
    if (created.error) throw new Error(created.error.message);
    userId = created.data.user.id;
  }

  const { error: profileError } = await client.from('profiles').upsert({
    id: userId,
    company_id: companyId,
    role: 'admin',
    full_name: 'Administrateur Principal',
  });
  if (profileError) throw new Error(profileError.message);
}

async function buildPublicUser(client, authUser, profile) {
  const metadata = authUser?.user_metadata || {};
  const combined = {
    ...profile,
    email: authUser?.email || '',
    telephone: metadata.telephone || '',
    permissions: Array.isArray(metadata.permissions) ? metadata.permissions : [],
    actif: metadata.actif !== false,
    must_change_password: metadata.mustChangePassword === true,
    derniere_connexion_at: metadata.derniereConnexionAt || null,
  };
  return toPublicUser(combined, authUser?.email || '');
}

router.post('/inscription', authenticate, requirePermission('users.manage'), async (req, res) => {
  try {
    try {
      await ensureInitialAdmin();
    } catch (bootstrapError) {
      // Do not block signup if bootstrap admin creation fails in production env.
      console.warn('ensureInitialAdmin failed during inscription:', bootstrapError.message);
    }
    const client = getAdminClient();

    const email = (req.body.email || '').trim().toLowerCase();
    const password = req.body.motDePasse || '';
    const telephone = normalizeInternationalPhone(req.body.telephone || '');
    if (!email || !password) {
      return res.status(400).json({ message: 'Email et mot de passe requis' });
    }
    if (req.body.telephone !== undefined && req.body.telephone !== '' && !telephone) {
      return res.status(400).json({ message: 'Téléphone invalide. Format attendu: +221 77 12 34 56' });
    }

    const companyId = req.body.company_id || (await getOrCreateDefaultCompanyId(client));

    const created = await client.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        nom: req.body.nom || '',
        prenom: req.body.prenom || '',
        telephone,
        permissions: Array.isArray(req.body.permissions) ? req.body.permissions : [],
        actif: true,
        mustChangePassword: false,
      },
    });

    if (created.error) {
      return res.status(400).json({ message: created.error.message });
    }

    const role = mapRole(req.body.role);
    const fullName = mergeFullName(req.body.nom || '', req.body.prenom || '');
    const { error: profileError } = await client.from('profiles').upsert({
      id: created.data.user.id,
      company_id: companyId,
      role,
      full_name: fullName || email,
    });
    if (profileError) {
      return res.status(400).json({ message: profileError.message });
    }

    const publicUser = await buildPublicUser(client, created.data.user, {
      id: created.data.user.id,
      role,
      full_name: fullName,
    });

    const token = signToken(publicUser);
    return res.status(201).json({ token, utilisateur: publicUser });
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.post('/connexion', async (req, res) => {
  try {
    try {
      await ensureInitialAdmin();
    } catch (bootstrapError) {
      // Existing users must still be able to log in even if bootstrap helper fails.
      console.warn('ensureInitialAdmin failed during connexion:', bootstrapError.message);
    }
    const client = getAdminClient();

    const email = (req.body.email || '').trim().toLowerCase();
    const motDePasse = req.body.motDePasse || '';

    const login = await client.auth.signInWithPassword({ email, password: motDePasse });
    if (login.error || !login.data?.user) {
      return res.status(401).json({ message: 'Email ou mot de passe incorrect' });
    }

    let profile = await getProfile(client, login.data.user.id);
    if (!profile) {
      const companyId = await getOrCreateDefaultCompanyId(client);
      const fullName = mergeFullName(
        login.data.user.user_metadata?.nom || '',
        login.data.user.user_metadata?.prenom || ''
      );
      const inserted = await client
        .from('profiles')
        .insert({
          id: login.data.user.id,
          company_id: companyId,
          role: 'utilisateur',
          full_name: fullName || email,
        })
        .select('*')
        .single();

      if (inserted.error) {
        return res.status(400).json({ message: inserted.error.message });
      }
      profile = inserted.data;
    }

    // Auto-heal legacy profiles: ensure company_id exists and role is normalized.
    if (!profile.company_id) {
      const companyId = await getOrCreateDefaultCompanyId(client);
      const normalizedRole = mapRole(profile.role);
      const patched = await client
        .from('profiles')
        .update({ company_id: companyId, role: normalizedRole })
        .eq('id', login.data.user.id)
        .select('*')
        .single();

      if (patched.error) {
        return res.status(400).json({ message: patched.error.message });
      }
      profile = patched.data;
    }

    const metadata = login.data.user.user_metadata || {};
    if (metadata.actif === false) {
      return res.status(403).json({ message: 'Compte désactivé' });
    }

    await client.auth.admin.updateUserById(login.data.user.id, {
      user_metadata: {
        ...metadata,
        derniereConnexionAt: new Date().toISOString(),
      },
    });

    const publicUser = await buildPublicUser(client, {
      ...login.data.user,
      user_metadata: {
        ...metadata,
        derniereConnexionAt: new Date().toISOString(),
      },
    }, profile);

    const token = signToken(publicUser);

    await logAudit(client, {
      userId: publicUser.id,
      userEmail: publicUser.email,
      action: 'auth.login',
      targetType: 'Utilisateur',
      targetId: publicUser.id,
      metadata: {},
      ip: '',
    });

    return res.json({
      token,
      utilisateur: publicUser,
      sessionTimeoutMinutes: 30,
    });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.get('/profil', authenticate, async (req, res) => {
  try {
    const client = getAdminClient();
    const userData = await client.auth.admin.getUserById(req.user.id || req.user._id);
    if (userData.error || !userData.data?.user) {
      return res.status(404).json({ message: 'Utilisateur non trouvé' });
    }
    const profile = await getProfile(client, userData.data.user.id);
    if (!profile) return res.status(404).json({ message: 'Utilisateur non trouvé' });

    const publicUser = await buildPublicUser(client, userData.data.user, profile);
    return res.json(publicUser);
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
});

router.put('/profil', authenticate, async (req, res) => {
  try {
    const client = getAdminClient();
    const userId = req.user.id || req.user._id;

    const userData = await client.auth.admin.getUserById(userId);
    if (userData.error || !userData.data?.user) {
      return res.status(404).json({ message: 'Utilisateur non trouvé' });
    }

    const authUser = userData.data.user;
    const email = (req.body.email || authUser.email || '').trim().toLowerCase();
    const nom = (req.body.nom || authUser.user_metadata?.nom || '').trim();
    const prenom = (req.body.prenom || authUser.user_metadata?.prenom || '').trim();
    const telephone = req.body.telephone !== undefined
      ? normalizeInternationalPhone(req.body.telephone)
      : (authUser.user_metadata?.telephone || '').trim();
    if (req.body.telephone !== undefined && !telephone) {
      return res.status(400).json({ message: 'Téléphone invalide. Format attendu: +221 77 12 34 56' });
    }

    const updatedAuth = await client.auth.admin.updateUserById(userId, {
      email,
      user_metadata: {
        ...(authUser.user_metadata || {}),
        nom,
        prenom,
        telephone,
      },
    });

    if (updatedAuth.error) {
      return res.status(400).json({ message: updatedAuth.error.message });
    }

    const profile = await getProfile(client, userId);
    if (!profile) return res.status(404).json({ message: 'Utilisateur non trouvé' });

    const { error: profileError } = await client
      .from('profiles')
      .update({ full_name: mergeFullName(nom, prenom) || email })
      .eq('id', userId);
    if (profileError) return res.status(400).json({ message: profileError.message });

    await logAudit(client, {
      userId,
      userEmail: email,
      action: 'auth.profile_update',
      targetType: 'Utilisateur',
      targetId: userId,
      metadata: {},
      ip: '',
    });

    const refreshedProfile = await getProfile(client, userId);
    const publicUser = await buildPublicUser(client, updatedAuth.data.user, refreshedProfile);
    return res.json(publicUser);
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.put('/mot-de-passe', authenticate, async (req, res) => {
  try {
    const client = getAdminClient();
    const userId = req.user.id || req.user._id;
    const { motDePasseActuel, nouveauMotDePasse } = req.body;

    const userData = await client.auth.admin.getUserById(userId);
    if (userData.error || !userData.data?.user) {
      return res.status(404).json({ message: 'Utilisateur non trouvé' });
    }

    const email = userData.data.user.email;
    const verify = await client.auth.signInWithPassword({
      email,
      password: motDePasseActuel || '',
    });
    if (verify.error) {
      return res.status(400).json({ message: 'Mot de passe actuel incorrect' });
    }

    const updated = await client.auth.admin.updateUserById(userId, {
      password: nouveauMotDePasse,
      user_metadata: {
        ...(userData.data.user.user_metadata || {}),
        mustChangePassword: false,
      },
    });
    if (updated.error) {
      return res.status(400).json({ message: updated.error.message });
    }

    await logAudit(client, {
      userId,
      userEmail: email,
      action: 'auth.change_password',
      targetType: 'Utilisateur',
      targetId: userId,
      metadata: {},
      ip: '',
    });

    return res.json({ message: 'Mot de passe mis à jour' });
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.post('/mot-de-passe/oublie', async (req, res) => {
  try {
    const client = getAdminClient();
    const email = (req.body.email || '').trim().toLowerCase();
    const users = await client.auth.admin.listUsers({ page: 1, perPage: 1000 });
    const user = (users.data?.users || []).find((u) => (u.email || '').toLowerCase() === email);

    if (!user) {
      return res.json({
        message: 'Si cet email existe, un email de réinitialisation a été envoyé.',
      });
    }

    await client.from('password_reset_tokens').delete().eq('user_id', user.id).is('used_at', null);

    const rawToken = crypto.randomBytes(24).toString('hex');
    const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
    const expiresAt = new Date(Date.now() + 30 * 60 * 1000).toISOString();

    const inserted = await client.from('password_reset_tokens').insert({
      user_id: user.id,
      token_hash: tokenHash,
      expires_at: expiresAt,
    });
    if (inserted.error) return res.status(400).json({ message: inserted.error.message });

    await logAudit(client, {
      userId: user.id,
      userEmail: user.email,
      action: 'auth.request_password_reset',
      targetType: 'Utilisateur',
      targetId: user.id,
      metadata: {},
      ip: '',
    });

    await sendPasswordResetEmail({
      to: user.email,
      userName: mergeFullName(user.user_metadata?.prenom || '', user.user_metadata?.nom || '') || user.email,
      token: rawToken,
      expiresMinutes: 30,
    });

    return res.json({ message: 'Un email de réinitialisation a été envoyé.' });
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.post('/mot-de-passe/reinitialiser', async (req, res) => {
  try {
    const client = getAdminClient();
    const { token, nouveauMotDePasse } = req.body;
    const tokenHash = crypto.createHash('sha256').update(token || '').digest('hex');

    const lookup = await client
      .from('password_reset_tokens')
      .select('*')
      .eq('token_hash', tokenHash)
      .is('used_at', null)
      .gt('expires_at', new Date().toISOString())
      .maybeSingle();

    if (lookup.error) return res.status(400).json({ message: lookup.error.message });
    if (!lookup.data) return res.status(400).json({ message: 'Token invalide ou expiré' });

    const updateUser = await client.auth.admin.updateUserById(lookup.data.user_id, {
      password: nouveauMotDePasse,
    });
    if (updateUser.error) return res.status(400).json({ message: updateUser.error.message });

    const markUsed = await client
      .from('password_reset_tokens')
      .update({ used_at: new Date().toISOString() })
      .eq('id', lookup.data.id);
    if (markUsed.error) return res.status(400).json({ message: markUsed.error.message });

    await logAudit(client, {
      userId: lookup.data.user_id,
      userEmail: updateUser.data.user?.email || '',
      action: 'auth.reset_password',
      targetType: 'Utilisateur',
      targetId: lookup.data.user_id,
      metadata: {},
      ip: '',
    });

    return res.json({ message: 'Mot de passe réinitialisé avec succès' });
  } catch (err) {
    return res.status(400).json({ message: err.message });
  }
});

router.post('/deconnexion', authenticate, async (req, res) => {
  const client = getAdminClient();
  await logAudit(client, {
    userId: req.user.id || req.user._id,
    userEmail: req.user.email,
    action: 'auth.logout',
    targetType: 'Utilisateur',
    targetId: req.user.id || req.user._id,
    metadata: {},
    ip: '',
  });
  return res.json({ message: 'Déconnecté' });
});

module.exports = router;
