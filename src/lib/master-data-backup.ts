export const IMPORT_BLOCK_REASON =
  'Importacao pela interface foi bloqueada. Use os scripts auditaveis em scripts/migration antes de alterar dados.';

type BackupValidationResult =
  | { ok: true; reason: null }
  | { ok: false; reason: 'missing_meta' | 'invalid_table_shape' };

export function validateBackupPayload(payload: unknown): BackupValidationResult {
  if (!payload || typeof payload !== 'object' || !('_meta' in payload)) {
    return { ok: false, reason: 'missing_meta' };
  }

  for (const [table, rows] of Object.entries(payload)) {
    if (table === '_meta') {
      continue;
    }

    if (!Array.isArray(rows)) {
      return { ok: false, reason: 'invalid_table_shape' };
    }
  }

  return { ok: true, reason: null };
}

export function collectBackupTableNames(payload: Record<string, unknown>): string[] {
  return Object.keys(payload)
    .filter((table) => table !== '_meta')
    .sort((left, right) => left.localeCompare(right));
}

export function createImportBlockedError(): Error {
  return new Error(IMPORT_BLOCK_REASON);
}
