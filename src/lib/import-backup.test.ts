import { describe, expect, test, vi } from 'vitest';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { assertImportAllowed, importBackup } from '../../scripts/migration/import-backup.js';

describe('assertImportAllowed', () => {
  test('blocks when CONFIRM_IMPORT is missing', () => {
    expect(() =>
      assertImportAllowed({
        backupPath: 'backup.json',
        env: {},
      }),
    ).toThrow(/CONFIRM_IMPORT/);
  });

  test('blocks when project ref is forbidden', () => {
    expect(() =>
      assertImportAllowed({
        backupPath: 'backup.json',
        env: {
          CONFIRM_IMPORT: 'true',
          SUPABASE_URL: 'https://vmareepfbgocyleknrgg.supabase.co',
        },
      }),
    ).toThrow(/not allowed/i);
  });

  test('blocks when project ref is not staging', () => {
    expect(() =>
      assertImportAllowed({
        backupPath: 'backup.json',
        env: {
          CONFIRM_IMPORT: 'true',
          SUPABASE_URL: 'https://other-project.supabase.co',
        },
      }),
    ).toThrow(/Target project must be okurngvcodmljjicopdp/i);
  });
});

