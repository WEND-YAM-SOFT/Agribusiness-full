const path = require('path');
const dotenv = require('dotenv');

dotenv.config({ path: path.join(__dirname, '..', '.env') });

const { getAdminClient } = require('../services/supabase');

function parseArgs() {
  const args = process.argv.slice(2);
  return {
    apply: args.includes('--apply'),
    cleanupAuthOrphans: args.includes('--cleanup-auth-orphans'),
  };
}

function isSchemaMissingError(error) {
  const message = (error?.message || '').toString().toLowerCase();
  return message.includes('does not exist')
    || message.includes('schema cache')
    || message.includes('could not find the');
}

function isNotFoundError(error) {
  const message = (error?.message || '').toString().toLowerCase();
  return message.includes('not found');
}

async function getAllAuthUsers(client) {
  const users = [];
  let page = 1;
  const perPage = 1000;

  while (true) {
    const res = await client.auth.admin.listUsers({ page, perPage });
    if (res.error) throw new Error(`auth listUsers failed: ${res.error.message}`);

    const chunk = res.data?.users || [];
    users.push(...chunk);
    if (chunk.length < perPage) break;
    page += 1;
  }

  return users;
}

async function safeDeleteByUserIds(client, table, userIds, userIdColumn) {
  if (!userIds.length) return { deleted: 0, skipped: false };
  const res = await client.from(table).delete().in(userIdColumn, userIds);
  if (!res.error) return { deleted: userIds.length, skipped: false };
  if (isSchemaMissingError(res.error)) return { deleted: 0, skipped: true };
  throw new Error(`${table} cleanup failed: ${res.error.message}`);
}

async function safeDetachAudit(client, userIds) {
  if (!userIds.length) return { detached: 0, skipped: false };
  const res = await client.from('audit_logs').update({ user_id: null }).in('user_id', userIds);
  if (!res.error) return { detached: userIds.length, skipped: false };
  if (isSchemaMissingError(res.error)) return { detached: 0, skipped: true };
  throw new Error(`audit_logs detach failed: ${res.error.message}`);
}

async function main() {
  const opts = parseArgs();
  const client = getAdminClient();

  const authUsers = await getAllAuthUsers(client);
  const authIds = new Set(authUsers.map((u) => u.id));

  const profilesRes = await client.from('profiles').select('id,full_name,role');
  if (profilesRes.error) throw new Error(`profiles read failed: ${profilesRes.error.message}`);
  const profiles = profilesRes.data || [];

  const orphanProfiles = profiles.filter((p) => !authIds.has(p.id));

  const profileIds = new Set(profiles.map((p) => p.id));
  const authWithoutProfile = authUsers.filter((u) => !profileIds.has(u.id));

  console.log(opts.apply ? 'Mode apply.' : 'Mode dry-run.');
  console.log(`Auth users: ${authUsers.length}`);
  console.log(`Profiles: ${profiles.length}`);
  console.log(`Orphan profiles (without auth user): ${orphanProfiles.length}`);
  console.log(`Auth users without profile: ${authWithoutProfile.length}`);

  if (authWithoutProfile.length) {
    console.log('Auth users without profile (potential stale accounts):');
    authWithoutProfile.forEach((u) => {
      const nom = (u.user_metadata?.nom || '').toString().trim();
      const prenom = (u.user_metadata?.prenom || '').toString().trim();
      const fullName = `${prenom} ${nom}`.trim();
      console.log(`- ${u.id} | ${u.email || ''}${fullName ? ` | ${fullName}` : ''}`);
    });
  }

  if (!orphanProfiles.length) {
    console.log('No orphan profile cleanup needed.');
  } else {
    console.log('Orphan profile IDs:');
    orphanProfiles.forEach((p) => {
      console.log(`- ${p.id} | ${(p.full_name || '').toString()} | role=${(p.role || '').toString()}`);
    });
  }

  if (!opts.apply) {
    console.log('Dry-run complete. Re-run with --apply to clean SQL leftovers.');
    console.log('Add --cleanup-auth-orphans to also delete auth users without profile.');
    return;
  }

  const orphanIds = orphanProfiles.map((p) => p.id);

  let tokenCleanup = { deleted: 0, skipped: false };
  let auditCleanup = { detached: 0, skipped: false };

  if (orphanIds.length) {
    tokenCleanup = await safeDeleteByUserIds(client, 'password_reset_tokens', orphanIds, 'user_id');
    auditCleanup = await safeDetachAudit(client, orphanIds);

    const deleteProfilesRes = await client.from('profiles').delete().in('id', orphanIds);
    if (deleteProfilesRes.error) throw new Error(`profiles delete failed: ${deleteProfilesRes.error.message}`);
  }

  let deletedAuthOrphans = 0;
  if (opts.cleanupAuthOrphans && authWithoutProfile.length) {
    for (const user of authWithoutProfile) {
      const deleted = await client.auth.admin.deleteUser(user.id);
      if (deleted.error && !isNotFoundError(deleted.error)) {
        throw new Error(`auth orphan delete failed (${user.id}): ${deleted.error.message}`);
      }
      deletedAuthOrphans += 1;
    }
  }

  console.log('Cleanup done:');
  console.log(`- password_reset_tokens cleaned: ${tokenCleanup.deleted}${tokenCleanup.skipped ? ' (table/column missing, skipped)' : ''}`);
  console.log(`- audit_logs user_id detached: ${auditCleanup.detached}${auditCleanup.skipped ? ' (table/column missing, skipped)' : ''}`);
  console.log(`- orphan profiles deleted: ${orphanIds.length}`);
  console.log(`- auth users without profile deleted: ${deletedAuthOrphans}`);
}

main().catch((err) => {
  console.error('Reconcile failed:', err.message);
  process.exit(1);
});
