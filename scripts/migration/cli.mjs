import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';

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

const [command, backupPath] = process.argv.slice(2);

if (!command || !['analyze', 'dry-run', 'validate', 'import'].includes(command)) {
  fail('Usage: npm run migration:<analyze|dry-run|validate|import> -- <backup.json>');
}

if (command === 'import') {
  fail('Import is intentionally blocked. Do not write data without explicit remote-write approval.');
}

if (!backupPath) {
  fail('Backup path is required.');
}

const backup = readBackup(backupPath);
const report = analyzeBackup(backup, backupPath);

if (command === 'dry-run') {
  writeSummary({
    mode: 'dry-run',
    writePlanned: false,
    tables: report.tablesFound,
    missingExpectedTables: report.missingExpectedTables,
  });
  process.exit(0);
}

if (command === 'validate') {
  writeSummary({
    mode: 'validate',
    passed: report.missingReferences.total === 0,
    missingReferences: report.missingReferences,
  });
  process.exit(report.missingReferences.total === 0 ? 0 : 1);
}

const reportPaths = writeReports(report);
writeSummary({
  mode: 'analyze',
  tablesFound: report.tablesFound,
  tableCounts: report.tableCounts,
  duplicateSummary: report.duplicates,
  missingReferences: report.missingReferences,
  missingExpectedTables: report.missingExpectedTables,
  reports: reportPaths,
});

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
    duplicates: {
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

function writeReports(report) {
  const reportsDir = 'reports';
  mkdirSync(reportsDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const jsonPath = join(reportsDir, `migration-analysis-${stamp}.json`);
  const mdPath = join(reportsDir, `migration-analysis-${stamp}.md`);

  writeFileSync(jsonPath, `${JSON.stringify(report, null, 2)}\n`);
  writeFileSync(mdPath, renderMarkdown(report));

  return { json: jsonPath, markdown: mdPath };
}

function renderMarkdown(report) {
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
    `- duplicate id groups: ${sumObject(report.duplicates.duplicateIdGroupsByTable)}`,
    `- duplicate key groups: ${sumObject(report.duplicates.duplicateKeyGroups)}`,
    '',
    '## Missing References',
    `- total: ${report.missingReferences.total}`,
    '',
    '## Missing Expected Tables',
    ...(report.missingExpectedTables.length ? report.missingExpectedTables.map((table) => `- ${table}`) : ['- none']),
    '',
  ].join('\n');
}

function countGroups(values) {
  const counts = new Map();
  for (const value of values) {
    if (!value) continue;
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }
  return counts;
}

function normalizeValue(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function sumObject(object) {
  return Object.values(object).reduce((sum, count) => sum + count, 0);
}

function writeSummary(summary) {
  console.log(JSON.stringify(summary, null, 2));
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
