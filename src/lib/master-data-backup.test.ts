import {
  IMPORT_BLOCK_REASON,
  collectBackupTableNames,
  createImportBlockedError,
  validateBackupPayload,
} from './master-data-backup';

describe('validateBackupPayload', () => {
  test('accepts backup payload with metadata and array tables', () => {
    const payload = {
      _meta: [{ version: '1.1', date: '2026-05-10T13:11:29.382Z' }],
      clients: [{ id: '1' }],
      suppliers: [],
    };

    expect(validateBackupPayload(payload)).toEqual({
      ok: true,
      reason: null,
    });
  });

  test('rejects payload without metadata', () => {
    expect(validateBackupPayload({ clients: [] })).toEqual({
      ok: false,
      reason: 'missing_meta',
    });
  });

  test('rejects payload when a table is not an array', () => {
    expect(
      validateBackupPayload({
        _meta: [{ version: '1.1', date: '2026-05-10T13:11:29.382Z' }],
        clients: { id: '1' },
      }),
    ).toEqual({
      ok: false,
      reason: 'invalid_table_shape',
    });
  });
});

describe('collectBackupTableNames', () => {
  test('returns only data tables sorted alphabetically', () => {
    const payload = {
      suppliers: [],
      _meta: [{ version: '1.1', date: '2026-05-10T13:11:29.382Z' }],
      clients: [],
    };

    expect(collectBackupTableNames(payload)).toEqual(['clients', 'suppliers']);
  });
});

describe('import protection', () => {
  test('exposes a stable user-facing reason for blocking UI import', () => {
    expect(IMPORT_BLOCK_REASON).toContain('scripts/migration');
    expect(createImportBlockedError().message).toBe(IMPORT_BLOCK_REASON);
  });
});
