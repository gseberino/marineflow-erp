type DuplicateKeyRule = Record<string, string[]>;

type ForeignKeyRule = {
  table: string;
  column: string;
  references: string;
};

type BackupRow = Record<string, unknown>;
type BackupDataset = Record<string, BackupRow[]>;

type AnalyzeOptions = {
  duplicateKeyRules?: DuplicateKeyRule;
  foreignKeys?: ForeignKeyRule[];
};

export function analyzeBackupDataset(dataset: BackupDataset, options: AnalyzeOptions = {}) {
  const duplicateKeyRules = options.duplicateKeyRules ?? {};
  const foreignKeys = options.foreignKeys ?? [];

  const tableCounts = Object.fromEntries(
    Object.entries(dataset).map(([table, rows]) => [table, rows.length]),
  );

  const duplicateIds: Array<{ table: string; id: string; count: number }> = [];
  const duplicateKeys: Array<{ table: string; key: string; value: string; count: number }> = [];
  const missingReferences: Array<{
    table: string;
    column: string;
    value: string;
    referencedTable: string;
  }> = [];

  for (const [table, rows] of Object.entries(dataset)) {
    const ids = countValues(rows.map((row) => normalizeValue(row.id)));
    for (const [id, count] of ids.entries()) {
      if (id && count > 1) {
        duplicateIds.push({ table, id, count });
      }
    }

    for (const key of duplicateKeyRules[table] ?? []) {
      const values = countValues(rows.map((row) => normalizeValue(row[key])));
      for (const [value, count] of values.entries()) {
        if (value && count > 1) {
          duplicateKeys.push({ table, key, value, count });
        }
      }
    }
  }

  for (const rule of foreignKeys) {
    const referenceIds = new Set(
      (dataset[rule.references] ?? [])
        .map((row) => normalizeValue(row.id))
        .filter((value): value is string => Boolean(value)),
    );

    for (const row of dataset[rule.table] ?? []) {
      const value = normalizeValue(row[rule.column]);
      if (value && !referenceIds.has(value)) {
        missingReferences.push({
          table: rule.table,
          column: rule.column,
          value,
          referencedTable: rule.references,
        });
      }
    }
  }

  return {
    tableCounts,
    duplicateIds,
    duplicateKeys,
    missingReferences,
  };
}

function normalizeValue(value: unknown): string | null {
  if (typeof value === 'string' && value.trim().length > 0) {
    return value.trim();
  }

  return null;
}

function countValues(values: Array<string | null>): Map<string, number> {
  const counts = new Map<string, number>();

  for (const value of values) {
    if (!value) {
      continue;
    }

    counts.set(value, (counts.get(value) ?? 0) + 1);
  }

  return counts;
}
