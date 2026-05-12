import { readFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { basename, join } from 'node:path';

// Replicating needed config to avoid TS imports
const blockedProjectRefs = [
  'vmareepfbgocyleknrgg',
  'zssewfqhmrlagqbfqsmb',
];

const importGuardMessage = 'Set CONFIRM_IMPORT=true only after backup confirmation, dry-run approval, and explicit authorization.';

function extractSupabaseProjectRef(input) {
  if (!input) return null;
  const value = input.trim();
  const refMatch = value.match(/[a-z0-9]{20,}/i);
  return refMatch ? refMatch[0] : null;
}

function isBlockedSupabaseProjectRef(input) {
  const ref = extractSupabaseProjectRef(input);
  return Boolean(ref && blockedProjectRefs.includes(ref));
}

function isProbablyProductionContext(env = process.env) {
  const nodeEnv = env.NODE_ENV?.toLowerCase();
  if (nodeEnv === 'production') return true;
  const appUrl = env.APP_PUBLIC_URL?.trim().toLowerCase() ?? '';
  if (!appUrl) return false;
  if (appUrl.includes('localhost') || appUrl.includes('127.0.0.1')) return false;
  return appUrl.includes('vercel.app') || appUrl.includes('lovable.app') || appUrl.includes('production');
}

const TABLE_ORDER = [
  'app_settings',
  'app_users',
  'financial_categories',
  'product_categories',
  'payment_condition_presets',
  'marinas',
  'clients', // BEFORE vessels
  'vessels',
  'suppliers',
  'products',
  'services',
  'supplier_product_mappings',
  'product_price_history',
  'price_update_suggestions',
  'service_orders',
  'service_order_parts',
  'service_order_services',
  'service_order_technicians',
  'agenda_tasks',
  'external_quote_leads',
  'external_quotes',
  'external_quote_parts',
  'external_quote_services',
  'purchase_orders',
  'purchase_order_items',
  'fiscal_notes',
  'fiscal_note_items',
  'inventory_movements',
  'collections',
  'payables',
  'audit_log',
];

const TABLE_IDENTITY_KEYS = {
  app_settings: 'key',
  product_categories: 'name', // Use name to handle seed data conflicts
  service_order_technicians: 'service_order_id,user_id', // Composite PK
};

export function assertImportAllowed(options = {}) {
  const env = options.env ?? process.env;

  if (env.CONFIRM_IMPORT !== 'true') {
    throw new Error(importGuardMessage);
  }

  if (!options.backupPath) {
    throw new Error('Backup path is required before import.');
  }

  if (isProbablyProductionContext(env)) {
    throw new Error('Import blocked: environment looks like production.');
  }

  const url = env.VITE_SUPABASE_URL ?? env.SUPABASE_URL;
  if (!url) {
    throw new Error('SUPABASE_URL is missing.');
  }

  if (isBlockedSupabaseProjectRef(url)) {
    throw new Error(
      `Import blocked: project ref is not allowed (${blockedProjectRefs.join(', ')}).`,
    );
  }

  if (!url.includes('okurngvcodmljjicopdp')) {
    throw new Error('Import blocked: Target project must be okurngvcodmljjicopdp.');
  }
}

async function importTable(supabase, table, rows) {
  const onConflict = TABLE_IDENTITY_KEYS[table] || 'id';
  const BATCH_SIZE = 50;
  let created = 0;
  let errors = 0;

  for (let i = 0; i < rows.length; i += BATCH_SIZE) {
    const batch = rows.slice(i, i + BATCH_SIZE);
    
    // For tables with composite PK, we need to ensure the columns exist in batch
    const { error } = await supabase
      .from(table)
      .upsert(batch, { onConflict, ignoreDuplicates: false });

    if (error) {
      console.error(`Error importing batch for table ${table}:`, error.message);
      errors += batch.length;
    } else {
      created += batch.length;
    }
  }

  return { created, errors };
}

export async function importBackup(options = {}) {
  assertImportAllowed(options);

  const env = options.env ?? process.env;
  const backupPath = options.backupPath;
  const url = env.VITE_SUPABASE_URL ?? env.SUPABASE_URL;
  const key = env.SUPABASE_SERVICE_ROLE_KEY || env.VITE_SUPABASE_PUBLISHABLE_KEY || env.SUPABASE_ANON_KEY;

  console.log(`Starting import to ${url}...`);
  console.log(`Key present: ${!!key}, Type: ${typeof key}, Length: ${key?.length}`);

  const backup = JSON.parse(readFileSync(backupPath, 'utf8'));
  const supabase = createClient(url, key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const tablesInBackup = Object.keys(backup).filter(t => t !== '_meta');
  const tablesToProcess = TABLE_ORDER.filter(t => tablesInBackup.includes(t));
  
  const remainingTables = tablesInBackup.filter(t => !TABLE_ORDER.includes(t));
  tablesToProcess.push(...remainingTables);

  const results = {};

  for (const table of tablesToProcess) {
    const rows = backup[table];
    if (!rows || rows.length === 0) continue;

    console.log(`Importing ${rows.length} rows into ${table}...`);
    const { created, errors } = await importTable(supabase, table, rows);
    results[table] = { created, errors };
  }

  const report = {
    generatedAt: new Date().toISOString(),
    sourceFile: basename(backupPath),
    targetUrl: url,
    results,
  };

  const reportsDir = 'reports';
  if (!existsSync(reportsDir)) mkdirSync(reportsDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const reportPath = join(reportsDir, `import-report-${stamp}.json`);
  writeFileSync(reportPath, JSON.stringify(report, null, 2));

  console.log(`Import complete. Report saved to ${reportPath}`);
  return report;
}
