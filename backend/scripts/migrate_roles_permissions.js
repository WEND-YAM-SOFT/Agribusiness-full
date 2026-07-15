const path = require('path');
const dotenv = require('dotenv');

dotenv.config({ path: path.join(__dirname, '..', '.env') });

const { getAdminClient } = require('../services/supabase');
const { normalizeRole, getRolePermissions } = require('../config/permissions');

function parseArgs() {
  const args = process.argv.slice(2);
  const opts = {
    dryRun: false,
    fallbackRole: 'technicien',
    syncAuthMetadata: true,
  };

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg === '--dry-run') {
      opts.dryRun = true;
      continue;
    }
    if (arg === '--fallback-role') {
      opts.fallbackRole = normalizeRole(args[i + 1] || 'technicien');
      i += 1;
      continue;
    }
    if (arg === '--no-sync-auth-metadata') {
      opts.syncAuthMetadata = false;
      continue;
    }
  }

  return opts;
}

function inferRole(oldRole, fallbackRole) {
  const raw = (oldRole || '').toString().trim().toLowerCase();
  const normalized = normalizeRole(raw);

  if (normalized !== 'utilisateur') return normalized;
  if (!raw || raw === 'utilisateur' || raw === 'user') return 'utilisateur';
  return fallbackRole;
}

async function updateProfileCompat(client, profileId, payload) {
  const withPermissions = await client
    .from('profiles')
    .update(payload)
    .eq('id', profileId)
    .select('id')
    .single();

  if (!withPermissions.error) return withPermissions;

  const message = (withPermissions.error.message || '').toString();
  if (message.includes("Could not find the 'permissions' column")) {
    const fallbackPayload = { ...payload };
    delete fallbackPayload.permissions;
    return client
      .from('profiles')
      .update(fallbackPayload)
      .eq('id', profileId)
      .select('id')
      .single();
  }

  return withPermissions;
}

async function syncAuthUserMetadata(client, userId, role, permissions) {
  const current = await client.auth.admin.getUserById(userId);
  if (current.error || !current.data?.user) return current;

  const metadata = current.data.user.user_metadata || {};
  return client.auth.admin.updateUserById(userId, {
    user_metadata: {
      ...metadata,
      role,
      permissions,
    },
  });
}

async function main() {
  const opts = parseArgs();
  const client = getAdminClient();

  const profilesRes = await client.from('profiles').select('id,role,permissions');
  if (profilesRes.error) {
    throw new Error(`profiles read failed: ${profilesRes.error.message}`);
  }

  const profiles = profilesRes.data || [];
  let changed = 0;
  let unchanged = 0;
  let authSynced = 0;
  let failed = 0;

  console.log(opts.dryRun ? 'Mode dry-run.' : 'Mode apply.');
  console.log(`Fallback role: ${opts.fallbackRole}`);
  console.log(`Sync auth metadata: ${opts.syncAuthMetadata ? 'yes' : 'no'}`);

  for (const profile of profiles) {
    const nextRole = inferRole(profile.role, opts.fallbackRole);
    const nextPermissions = getRolePermissions(nextRole);
    const currentPermissions = Array.isArray(profile.permissions) ? profile.permissions : [];

    const sameRole = (profile.role || '') === nextRole;
    const samePermissions = JSON.stringify(currentPermissions) === JSON.stringify(nextPermissions);

    if (sameRole && samePermissions) {
      unchanged += 1;
      continue;
    }

    changed += 1;
    console.log(`[MIGRATE] ${profile.id} ${profile.role || '(vide)'} -> ${nextRole}`);

    if (opts.dryRun) continue;

    const updateRes = await updateProfileCompat(client, profile.id, {
      role: nextRole,
      permissions: nextPermissions,
    });

    if (updateRes.error) {
      failed += 1;
      console.error(`[ERROR] profile ${profile.id}: ${updateRes.error.message}`);
      continue;
    }

    if (opts.syncAuthMetadata) {
      const syncRes = await syncAuthUserMetadata(client, profile.id, nextRole, nextPermissions);
      if (syncRes.error) {
        failed += 1;
        console.error(`[ERROR] auth ${profile.id}: ${syncRes.error.message}`);
      } else {
        authSynced += 1;
      }
    }
  }

  console.log('--- Summary ---');
  console.log(`Profiles total: ${profiles.length}`);
  console.log(`Changed: ${changed}`);
  console.log(`Unchanged: ${unchanged}`);
  console.log(`Auth synced: ${authSynced}`);
  console.log(`Failures: ${failed}`);

  if (failed > 0) {
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error('Migration failed:', err.message);
  process.exit(1);
});
