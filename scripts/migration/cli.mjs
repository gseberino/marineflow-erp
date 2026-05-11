import { createClient } from '@supabase/supabase-js';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const expectedTables = [
  'app_settings', 'app_users', 'clients', 'suppliers', 'marinas', 'vessels',
  'product_categories', 'financial_categories', 'payment_condition_presets',
  'products', 'services', 'supplier_product_mappings',
  'product_price_history', 'price_update_suggestions', 'inventory_movements',
  'service_orders', 'service_order_parts', 'service_order_services',
  'service_order_technicians', 'agenda_tasks',
  'external_quote_leads', 'external_quotes', 'external_quote_parts', 'external_quote_services',
  'purchase_orders', 'purchase_order_items',
  'fiscal_notes', 'fiscal_note_items',
  'collections', 'payables', 'audit_log',
];

const duplicateKeyRules = {
  clients: ['email', 'cpf_cnpj', 'cnpj_cpf'],
  suppliers: ['email', 'cnpj_cpf', 'cpf_cnpj'],
  services: ['name', 'service_name'],
  products: ['name', 'product_name'],
};

const foreignKeys = [
  { table: 'service_orders', column: 'client_id', references: 'clients' },
  { table: 'service_orders', column: 'vessel_id', references: 'vessels' },
  { table: 'service_order_parts', column: 'service_order_id', references: 'service_orders' },
  { table: 'service_order_services', column: 'service_order_id', references: 'service_orders' },
  { table: 'service_order_technicians', column: 'service_order_id', references: 'service_orders' },
  { table: 'external_quotes', column: 'lead_id', references: 'external_quote_leads' },
];

const tableIdentityKeys = {
  app_settings: ['key'],
};

const ignoredCompareFields = new Set([
  'created_at',
  'updated_at',
  'inserted_at',
  'deleted_at',
  'synced_at',
  'createdAt',
  'updatedAt',
]);

export function resolveDryRunSupabaseConfig(env = process.env) {
  const url =
    env.VITE_SUPABASE_URL?.trim() ||
    env.SUPABASE_URL?.trim() ||
    null;

  const key =
    env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() ||
    env.SUPABASE_ANON_KEY?.trim() ||
    env.SUPABASE_PUBLISHABLE_KEY?.trim() ||
    null;

  if (!url || !key) {
    return null;
  }

  const source = [
    env.VITE_SUPABASE_URL?.trim() ? 'VITE_SUPABASE_URL' : 'SUPABASE_URL',
    env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim()
      ? 'VITE_SUPABASE_PUBLISHABLE_KEY'
      : env.SUPABASE_ANON_KEY?.trim()
        ? 'SUPABASE_ANON_KEY'
        : 'SUPABASE_PUBLISHABLE_KEY',
  ].join(' / ');

  return { url, key, source };
}

export function resolveMigrationEnv(env = process.env, envPath = null) {
  if (!envPath) {
    return {
      env,
      envPath: null,
      envStatus: 'not-provided',
    };
  }

  const resolvedPath = resolve(envPath);
  if (!existsSync(resolvedPath)) {
    return {
      env,
      envPath: resolvedPath,
      envStatus: 'missing',
    };
  }

  const fileEnv = parseEnvFile(readFileSync(resolvedPath, 'utf8'));
  return {
    env: { ...fileEnv, ...env },
    envPath: resolvedPath,
    envStatus: 'loaded',
  };
}

export function compareDryRunComparison({ backup, liveByTable, blockedTables, analysis }) {
  const blockedTableNames = new Set(blockedTables.map((entry) => entry.table));
  const tablesCompared = analysis.tablesFound.filter(
    (table) => !blockedTableNames.has(table) && Array.isArray(liveByTable[table]),
  );

  const counts = {};
  const liveOnlyByTable = {};
  const conflicts = [];
  const schemaErrors = [];

  const liveDataset = {};
  for (const table of tablesCompared) {
    liveDataset[table] = liveByTable[table] ?? [];
  }

  const liveDuplicateSummary = analyzeDatasetForComparison(liveDataset);

  for (const table of tablesCompared) {
    const backupRows = backup[table] ?? [];
    const liveRows = liveByTable[table] ?? [];
    const liveByIdentity = indexRowsByIdentity(table, liveRows);
    const liveIdentities = new Set(liveByIdentity.keys());

    let create = 0;
    let update = 0;
    let ignore = 0;

    for (const row of backupRows) {
      const identity = getRowIdentity(table, row);
      if (!identity) {
        schemaErrors.push({
          table,
          error: 'Backup row missing identity field.',
        });
        continue;
      }

      const liveRow = liveByIdentity.get(identity);
      if (!liveRow) {
        create += 1;
        continue;
      }

      liveIdentities.delete(identity);
      if (rowsEquivalent(row, liveRow)) {
        ignore += 1;
      } else {
        update += 1;
        conflicts.push({
          table,
          type: 'row_changed',
          id: identity,
        });
      }
    }

    const backupDuplicates = summarizeDuplicateRows(table, backupRows);
    const liveDuplicates = summarizeDuplicateRows(table, liveRows);
    if (backupDuplicates.length || liveDuplicates.length) {
      conflicts.push(
        ...backupDuplicates.map((entry) => ({ ...entry, source: 'backup' })),
        ...liveDuplicates.map((entry) => ({ ...entry, source: 'live' })),
      );
    }

    counts[table] = {
      backup: backupRows.length,
      live: liveRows.length,
      create,
      update,
      ignore,
    };
    liveOnlyByTable[table] = liveIdentities.size;
  }

  const recommendation = buildRecommendation({
    blockedTables,
    counts,
    analysis,
    liveDuplicateSummary,
    liveOnlyByTable,
  });

  return {
    tablesCompared,
    counts,
    blockedTables,
    conflicts,
    schemaErrors,
    duplicateSummary: {
      backup: analysis.duplicateSummary,
      live: liveDuplicateSummary,
    },
    missingReferences: analysis.missingReferences,
    missingExpectedTables: analysis.missingExpectedTables,
    liveOnlyByTable,
    recommendation,
  };
}

export async function runDryRun(backupPath, env = process.env) {
  const backup = readBackup(backupPath);
  const analysis = analyzeBackup(backup, backupPath);
  const config = resolveDryRunSupabaseConfig(env);

  if (!config) {
    const missing = listMissingDryRunEnvVars(env);
    return {
      mode: 'dry-run',
      offlineOnly: true,
      missingEnvVars: missing,
      reports: null,
      analysis,
    };
  }

  const client = createClient(config.url, config.key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const liveByTable = {};
  const blockedTables = [];
  const schemaErrors = [];

  for (const table of analysis.tablesFound) {
    const { data, error } = await client.from(table).select('*');
    if (error) {
      const classification = classifyReadOnlyError(error.message ?? String(error));
      const entry = {
        table,
        error: error.message ?? 'Unknown read-only error',
      };
      if (classification === 'blocked') {
        blockedTables.push(entry);
      } else {
        schemaErrors.push(entry);
      }
      continue;
    }

    liveByTable[table] = Array.isArray(data) ? data : [];
  }

  const comparison = compareDryRunComparison({
    backup,
    liveByTable,
    blockedTables,
    analysis,
  });

  const reports = writeDryRunReports({
    backupPath,
    analysis,
    comparison,
    source: config.source,
  });

  return {
    mode: 'dry-run',
    offlineOnly: false,
    source: config.source,
    blockedTables: comparison.blockedTables,
    schemaErrors: [...schemaErrors, ...comparison.schemaErrors],
    duplicateSummary: comparison.duplicateSummary,
    missingReferences: comparison.missingReferences,
    missingExpectedTables: comparison.missingExpectedTables,
    tablesCompared: comparison.tablesCompared,
    counts: comparison.counts,
    conflicts: comparison.conflicts,
    recommendation: comparison.recommendation,
    reports,
  };
}

function isMainModule() {
  return process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url));
}

function parseMigrationArgs(argv) {
  let command = null;
  let backupPath = null;
  let envPath = null;

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];

    if (!command) {
      command = token;
      continue;
    }

    if (token === '--env') {
      const next = argv[index + 1];
      if (!next || next.startsWith('-')) {
        fail('Missing value for --env.');
      }
      envPath = next;
      index += 1;
      continue;
    }

    if (token.startsWith('--env=')) {
      envPath = token.slice('--env='.length);
      if (!envPath) {
        fail('Missing value for --env.');
      }
      continue;
    }

    if (token.startsWith('-')) {
      fail(`Unknown option: ${token}`);
    }

    if (!backupPath) {
      backupPath = token;
      continue;
    }

    fail(`Unexpected argument: ${token}`);
  }

  return { command, backupPath, envPath };
}

function parseEnvFile(content) {
  const values = {};

  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) {
      continue;
    }

    const equalsIndex = line.indexOf('=');
    if (equalsIndex === -1) {
      continue;
    }

    const key = line.slice(0, equalsIndex).trim();
    if (!key) {
      continue;
    }

    let value = line.slice(equalsIndex + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }

    values[key] = value;
  }

  return values;
}

async function main() {
  const { command, backupPath, envPath } = parseMigrationArgs(process.argv.slice(2));

  if (!command || !['analyze', 'dry-run', 'validate', 'import'].includes(command)) {
    fail('Usage: npm run migration:<analyze|dry-run|validate|import> -- <backup.json>');
  }

  if (command === 'import') {
    fail('Import is intentionally blocked. Do not write data without explicit remote-write approval.');
  }

  if (!backupPath) {
    fail('Backup path is required.');
  }

  const runtimeEnv = resolveMigrationEnv(process.env, envPath);
  if (runtimeEnv.envStatus === 'missing') {
    console.error(`Env file not found: ${runtimeEnv.envPath}`);
  }

  if (command === 'dry-run') {
    const result = await runDryRun(backupPath, runtimeEnv.env);
    console.log(JSON.stringify(result, null, 2));
    return;
  }

  const backup = readBackup(backupPath);
  const analysis = analyzeBackup(backup, backupPath);

  if (command === 'validate') {
    const summary = {
      mode: 'validate',
      passed: analysis.missingReferences.total === 0,
      missingReferences: analysis.missingReferences,
    };
    console.log(JSON.stringify(summary, null, 2));
    process.exit(analysis.missingReferences.total === 0 ? 0 : 1);
  }

  const reportPaths = writeAnalyzeReports(analysis);
  console.log(JSON.stringify({
    mode: 'analyze',
    tablesFound: analysis.tablesFound,
    tableCounts: analysis.tableCounts,
    duplicateSummary: analysis.duplicateSummary,
    missingReferences: analysis.missingReferences,
    missingExpectedTables: analysis.missingExpectedTables,
    reports: reportPaths,
  }, null, 2));
}

function readBackup(path) {
  const parsed = JSON.parse(readFileSync(path, 'utf8'));
  if (!parsed || typeof parsed !== 'object' || !('_meta' in parsed)) {
    fail('Invalid backup: missing _meta.');
  }

  for (const [table, rows] of Object.entries(parsed)) {
    if (table !== '_meta' && !Array.isArray(rows)) {
      fail(`Invalid backup: table ${table} is not an array.`);
    }
  }

  return parsed;
}

function analyzeBackup(backup, backupPath) {
  const tablesFound = Object.keys(backup).filter((table) => table !== '_meta').sort();
  const tableCounts = Object.fromEntries(tablesFound.map((table) => [table, backup[table].length]));
  const duplicateIds = {};
  const duplicateKeys = {};

  for (const table of tablesFound) {
    const rows = backup[table];
    const idGroups = countGroups(rows.map((row) => normalizeValue(row.id)));
    const duplicateIdGroups = [...idGroups.values()].filter((count) => count > 1).length;
    if (duplicateIdGroups > 0) {
      duplicateIds[table] = duplicateIdGroups;
    }

    for (const key of duplicateKeyRules[table] ?? []) {
      const keyGroups = countGroups(rows.map((row) => normalizeValue(row[key])));
      const count = [...keyGroups.values()].filter((valueCount) => valueCount > 1).length;
      if (count > 0) {
        duplicateKeys[`${table}.${key}`] = count;
      }
    }
  }

  const missingReferencesByRule = {};
  let missingReferenceTotal = 0;

  for (const rule of foreignKeys) {
    const referenceIds = new Set((backup[rule.references] ?? []).map((row) => normalizeValue(row.id)).filter(Boolean));
    const missing = (backup[rule.table] ?? []).filter((row) => {
      const value = normalizeValue(row[rule.column]);
      return value && !referenceIds.has(value);
    }).length;

    if (missing > 0) {
      const ruleKey = `${rule.table}.${rule.column}->${rule.references}.id`;
      missingReferencesByRule[ruleKey] = missing;
      missingReferenceTotal += missing;
    }
  }

  return {
    generatedAt: new Date().toISOString(),
    sourceFile: basename(backupPath),
    tablesFound,
    tableCounts,
    duplicateSummary: {
      duplicateIdGroupsByTable: duplicateIds,
      duplicateKeyGroups: duplicateKeys,
    },
    missingReferences: {
      total: missingReferenceTotal,
      byRule: missingReferencesByRule,
    },
    missingExpectedTables: expectedTables.filter((table) => !tablesFound.includes(table)),
  };
}

function writeAnalyzeReports(report) {
  const reportsDir = 'reports';
  mkdirSync(reportsDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const jsonPath = join(reportsDir, `migration-analysis-${stamp}.json`);
  const mdPath = join(reportsDir, `migration-analysis-${stamp}.md`);

  writeFileSync(jsonPath, `${JSON.stringify(report, null, 2)}\n`);
  writeFileSync(mdPath, renderAnalyzeMarkdown(report));

  return { json: jsonPath, markdown: mdPath };
}

function writeDryRunReports({ backupPath, analysis, comparison, source }) {
  const reportsDir = 'reports';
  mkdirSync(reportsDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const jsonPath = join(reportsDir, `migration-dry-run-${stamp}.json`);
  const mdPath = join(reportsDir, `migration-dry-run-${stamp}.md`);
  const report = {
    mode: 'dry-run',
    generatedAt: new Date().toISOString(),
    sourceFile: basename(backupPath),
    source,
    tablesFound: analysis.tablesFound,
    tableCounts: analysis.tableCounts,
    duplicateSummary: comparison.duplicateSummary,
    missingReferences: comparison.missingReferences,
    missingExpectedTables: comparison.missingExpectedTables,
    tablesCompared: comparison.tablesCompared,
    counts: comparison.counts,
    blockedTables: comparison.blockedTables,
    conflicts: comparison.conflicts,
    schemaErrors: comparison.schemaErrors,
    recommendation: comparison.recommendation,
  };

  writeFileSync(jsonPath, `${JSON.stringify(report, null, 2)}\n`);
  writeFileSync(mdPath, renderDryRunMarkdown(report));

  return { json: jsonPath, markdown: mdPath };
}

function renderAnalyzeMarkdown(report) {
  return [
    '# Migration Analysis',
    '',
    `Generated: ${report.generatedAt}`,
    `Source file: ${report.sourceFile}`,
    '',
    '## Tables',
    ...Object.entries(report.tableCounts).map(([table, count]) => `- ${table}: ${count}`),
    '',
    '## Duplicate Groups',
    `- duplicate id groups: ${sumObject(report.duplicateSummary.duplicateIdGroupsByTable)}`,
    `- duplicate key groups: ${sumObject(report.duplicateSummary.duplicateKeyGroups)}`,
    '',
    '## Missing References',
    `- total: ${report.missingReferences.total}`,
    '',
    '## Missing Expected Tables',
    ...(report.missingExpectedTables.length ? report.missingExpectedTables.map((table) => `- ${table}`) : ['- none']),
    '',
  ].join('\n');
}

function renderDryRunMarkdown(report) {
  return [
    '# Migration Dry Run',
    '',
    `Generated: ${report.generatedAt}`,
    `Source file: ${report.sourceFile}`,
    `Source env: ${report.source}`,
    '',
    '## Tables Compared',
    ...(report.tablesCompared.length ? report.tablesCompared.map((table) => `- ${table}`) : ['- none']),
    '',
    '## Counts',
    ...Object.entries(report.counts).map(([table, counts]) => `- ${table}: backup ${counts.backup}, live ${counts.live}, create ${counts.create}, update ${counts.update}, ignore ${counts.ignore}`),
    '',
    '## Blocked Tables',
    ...(report.blockedTables.length ? report.blockedTables.map((entry) => `- ${entry.table}: ${entry.error}`) : ['- none']),
    '',
    '## Conflicts',
    ...(report.conflicts.length ? report.conflicts.map((entry) => `- ${entry.table}: ${entry.type}${entry.id ? ` (${entry.id})` : ''}`) : ['- none']),
    '',
    '## Schema Errors',
    ...(report.schemaErrors.length ? report.schemaErrors.map((entry) => `- ${entry.table}: ${entry.error}`) : ['- none']),
    '',
    '## Recommendation',
    `- ${report.recommendation}`,
    '',
  ].join('\n');
}

function summarizeDuplicateRows(table, rows) {
  const summary = [];
  const idGroups = groupValues(rows.map((row) => normalizeValue(row.id)));
  for (const [value, count] of idGroups.entries()) {
    if (value && count > 1) {
      summary.push({ table, kind: 'duplicate_id', value, count });
    }
  }

  for (const key of duplicateKeyRules[table] ?? []) {
    const keyGroups = groupValues(rows.map((row) => normalizeValue(row[key])));
    for (const [value, count] of keyGroups.entries()) {
      if (value && count > 1) {
        summary.push({ table, kind: `duplicate_${key}`, value, count });
      }
    }
  }

  return summary;
}

function analyzeDatasetForComparison(dataset) {
  const duplicateIds = {};
  const duplicateKeys = {};
  const missingReferencesByRule = {};
  let missingReferenceTotal = 0;

  for (const [table, rows] of Object.entries(dataset)) {
    const idGroups = groupValues(rows.map((row) => normalizeValue(row.id)));
    const duplicateIdGroups = [...idGroups.values()].filter((count) => count > 1).length;
    if (duplicateIdGroups > 0) {
      duplicateIds[table] = duplicateIdGroups;
    }

    for (const key of duplicateKeyRules[table] ?? []) {
      const keyGroups = groupValues(rows.map((row) => normalizeValue(row[key])));
      const count = [...keyGroups.values()].filter((valueCount) => valueCount > 1).length;
      if (count > 0) {
        duplicateKeys[`${table}.${key}`] = count;
      }
    }
  }

  for (const rule of foreignKeys) {
    const referenceIds = new Set((dataset[rule.references] ?? []).map((row) => normalizeValue(row.id)).filter(Boolean));
    const missing = (dataset[rule.table] ?? []).filter((row) => {
      const value = normalizeValue(row[rule.column]);
      return value && !referenceIds.has(value);
    }).length;

    if (missing > 0) {
      const ruleKey = `${rule.table}.${rule.column}->${rule.references}.id`;
      missingReferencesByRule[ruleKey] = missing;
      missingReferenceTotal += missing;
    }
  }

  return {
    duplicateSummary: {
      duplicateIdGroupsByTable: duplicateIds,
      duplicateKeyGroups: duplicateKeys,
    },
    missingReferences: {
      total: missingReferenceTotal,
      byRule: missingReferencesByRule,
    },
  };
}

function buildRecommendation({ blockedTables, counts, analysis, liveDuplicateSummary, liveOnlyByTable }) {
  if (blockedTables.length > 0) {
    return 'The public key cannot read every table. Use a secure server-side read-only credential or a dedicated read-only view before importing.';
  }

  const totals = Object.values(counts).reduce(
    (acc, entry) => {
      acc.create += entry.create;
      acc.update += entry.update;
      acc.ignore += entry.ignore;
      return acc;
    },
    { create: 0, update: 0, ignore: 0 },
  );

  const liveOnlyTotal = Object.values(liveOnlyByTable ?? {}).reduce((sum, count) => sum + count, 0);

  if (analysis.missingReferences.total > 0 || totals.create > 0 || totals.update > 0 || liveOnlyTotal > 0) {
    return 'The destination is not cleanly aligned with the backup. Prefer a clean staging database or remove duplicates before importing.';
  }

  if (
    sumObject(analysis.duplicateSummary.duplicateIdGroupsByTable) > 0 ||
    sumObject(analysis.duplicateSummary.duplicateKeyGroups) > 0 ||
    sumObject(liveDuplicateSummary.duplicateSummary.duplicateIdGroupsByTable) > 0 ||
    sumObject(liveDuplicateSummary.duplicateSummary.duplicateKeyGroups) > 0
  ) {
    return 'Duplicate records exist in the backup or destination. Deduplicate before any import.';
  }

  return 'The backup and destination are closely aligned. A clean staging import remains the safest next step.';
}

function indexRowsByIdentity(table, rows) {
  const indexed = new Map();
  for (const row of rows) {
    const identity = getRowIdentity(table, row);
    if (identity) {
      indexed.set(identity, row);
    }
  }
  return indexed;
}

function getRowIdentity(table, row) {
  if (tableIdentityKeys[table]) {
    for (const key of tableIdentityKeys[table]) {
      const value = normalizeValue(row[key]);
      if (value) {
        return value;
      }
    }
  }

  return normalizeValue(row.id);
}

function rowsEquivalent(left, right) {
  return canonicalizeRow(left) === canonicalizeRow(right);
}

function canonicalizeRow(row) {
  return JSON.stringify(stripIgnoredFields(row));
}

function stripIgnoredFields(value) {
  if (Array.isArray(value)) {
    return value.map((entry) => stripIgnoredFields(entry));
  }

  if (!value || typeof value !== 'object') {
    return value;
  }

  const entries = Object.entries(value)
    .filter(([key]) => !ignoredCompareFields.has(key))
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, entry]) => [key, stripIgnoredFields(entry)]);

  return Object.fromEntries(entries);
}

function classifyReadOnlyError(message) {
  const lower = message.toLowerCase();
  if (
    lower.includes('row-level security') ||
    lower.includes('permission denied') ||
    lower.includes('not allowed') ||
    lower.includes('rls')
  ) {
    return 'blocked';
  }

  return 'schema';
}

function listMissingDryRunEnvVars(env = process.env) {
  const missing = [];
  if (!env.VITE_SUPABASE_URL?.trim() && !env.SUPABASE_URL?.trim()) {
    missing.push('VITE_SUPABASE_URL', 'SUPABASE_URL');
  }
  if (
    !env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() &&
    !env.SUPABASE_ANON_KEY?.trim() &&
    !env.SUPABASE_PUBLISHABLE_KEY?.trim()
  ) {
    missing.push('VITE_SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_ANON_KEY', 'SUPABASE_PUBLISHABLE_KEY');
  }
  return missing;
}

function groupValues(values) {
  const counts = new Map();
  for (const value of values) {
    if (!value) continue;
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }
  return counts;
}

function countGroups(values) {
  return groupValues(values);
}

function normalizeValue(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function sumObject(object) {
  return Object.values(object).reduce((sum, count) => sum + count, 0);
}

function fail(message) {
  throw new Error(message);
}

if (isMainModule()) {
  try {
    await main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
