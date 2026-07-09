const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = process.env.SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

function ensureSupabaseEnv() {
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required');
  }
}

function getAdminClient() {
  ensureSupabaseEnv();
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

function mapRole(role) {
  const value = (role || '').toString().toLowerCase().trim();
  if (value === 'admin' || value === 'owner' || value === 'administrateur') return 'admin';
  if (value === 'viewer') return 'viewer';
  return 'agent';
}

function toAppRole(dbRole) {
  const value = (dbRole || '').toString().toLowerCase().trim();
  return value === 'admin' || value === 'owner' || value === 'administrateur'
    ? 'admin'
    : 'utilisateur';
}

function splitFullName(fullName = '') {
  const value = (fullName || '').trim();
  if (!value) return { nom: '', prenom: '' };
  const parts = value.split(/\s+/);
  const nom = parts.shift() || '';
  const prenom = parts.join(' ');
  return { nom, prenom };
}

function mergeFullName(nom = '', prenom = '') {
  return [nom, prenom].filter(Boolean).join(' ').trim();
}

function toPublicUser(profile, emailOverride) {
  const { nom, prenom } = splitFullName(profile.full_name || '');
  return {
    id: profile.id,
    nom,
    prenom,
    email: emailOverride || profile.email || '',
    telephone: profile.telephone || '',
    role: toAppRole(profile.role),
    permissions: Array.isArray(profile.permissions) ? profile.permissions : [],
    actif: profile.actif !== false,
    mustChangePassword: profile.must_change_password !== false,
    derniereConnexionAt: profile.derniere_connexion_at || null,
    createdAt: profile.created_at || null,
    updatedAt: profile.updated_at || null,
  };
}

async function logAudit(client, payload) {
  const row = {
    user_id: payload.userId || null,
    user_email: payload.userEmail || '',
    action: payload.action,
    target_type: payload.targetType || '',
    target_id: payload.targetId || null,
    metadata: payload.metadata || {},
    ip: payload.ip || '',
  };
  await client.from('audit_logs').insert(row);
}

module.exports = {
  getAdminClient,
  mapRole,
  toAppRole,
  mergeFullName,
  toPublicUser,
  logAudit,
};
