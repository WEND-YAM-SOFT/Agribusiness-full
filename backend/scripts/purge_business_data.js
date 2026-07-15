const path = require('path');
const dotenv = require('dotenv');

const { getAdminClient } = require('../services/supabase');

dotenv.config({ path: path.join(__dirname, '..', '.env') });

const CONFIRM_TOKEN = 'PURGE_NOW';

// Keep auth users + profiles + entreprises (identity scope).
const TABLES_TO_PURGE = [
  'alertes',
  'bandes',
  'clients',
  'commandes',
  'crm_interactions',
  'crm_taches',
  'stocks',
  'tresorerie_mouvements',
  'audit_logs',
  'password_reset_tokens',
];

function parseArgs() {
  const args = process.argv.slice(2);
  const result = {
    confirm: '',
    dryRun: false,
    companyId: '',
  };

  for (let i = 0; i < args.length; i += 1) {
    const a = args[i];
    if (a === '--dry-run') {
      result.dryRun = true;
      continue;
    }
    if (a === '--confirm') {
      result.confirm = args[i + 1] || '';
      i += 1;
      continue;
    }
    if (a === '--company-id') {
      result.companyId = args[i + 1] || '';
      i += 1;
      continue;
    }
  }

  return result;
}

async function countRows(client, table, companyId) {
  let query = client.from(table).select('id', { count: 'exact', head: true });
  if (companyId) query = query.eq('company_id', companyId);
  const { count, error } = await query;
  if (error) throw new Error(`${table} (count): ${error.message}`);
  return count || 0;
}

async function purgeTable(client, table, companyId) {
  let query = client.from(table).delete();

  if (companyId) {
    query = query.eq('company_id', companyId);
  } else {
    // Delete all rows while keeping a filter to satisfy PostgREST safe-delete constraints.
    query = query.not('id', 'is', null);
  }

  const { error } = await query;
  if (error) throw new Error(`${table} (delete): ${error.message}`);
}

async function main() {
  const args = parseArgs();

  if (!args.dryRun && args.confirm !== CONFIRM_TOKEN) {
    console.error('Purge bloquee: confirmation manquante.');
    console.error(`Utilise: node scripts/purge_business_data.js --confirm ${CONFIRM_TOKEN}`);
    console.error('Options: --dry-run, --company-id <uuid>');
    process.exit(1);
  }

  const client = getAdminClient();

  console.log(args.dryRun ? 'Mode dry-run (aucune suppression).' : 'Mode purge active.');
  if (args.companyId) {
    console.log(`Scope: company_id = ${args.companyId}`);
  } else {
    console.log('Scope: toutes les entreprises');
  }

  const report = [];
  for (const table of TABLES_TO_PURGE) {
    const before = await countRows(client, table, args.companyId);
    if (!args.dryRun && before > 0) {
      await purgeTable(client, table, args.companyId);
    }
    const after = args.dryRun ? before : await countRows(client, table, args.companyId);
    report.push({ table, before, after, deleted: before - after });
  }

  console.log('--- Rapport purge ---');
  for (const row of report) {
    console.log(`${row.table}: ${row.before} -> ${row.after} (supprime: ${row.deleted})`);
  }

  console.log('Termine. Les utilisateurs auth + profiles + entreprises sont conserves.');
}

main().catch((err) => {
  console.error('Erreur purge:', err.message);
  process.exit(1);
});
