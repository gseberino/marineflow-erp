import { describe, expect, test, vi } from 'vitest';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { assertImportAllowed, importBackup } from '../../scripts/migration/import-backup.ts';

describe('assertImportAllowed', () => {
  test('blocks when CONFIRM_IMPORT is missing', () => {
    expect(() =>
      assertImportAllowed({
        backupPath: 'backup.json',
        dryRunReportPath: 'report.json',
        env: {},
      }),
    ).toThrow(/CONFIRM_IMPORT/);
  });

  test('blocks when dry-run report is missing', () => {
    expect(() =>
      assertImportAllowed({
        backupPath: 'backup.json',
        dryRunReportPath: 'missing-report.json',
        env: { CONFIRM_IMPORT: 'true' },
      }),
    ).toThrow(/dry-run report/i);
  });

  test('blocks when project ref is forbidden', () => {
    const dir = mkdtempSync(join(tmpdir(), 'marineflow-import-guard-'));
    const reportPath = join(dir, 'report.json');
    writeFileSync(reportPath, '{}', 'utf8');

    expect(() =>
      assertImportAllowed({
        backupPath: 'backup.json',
        dryRunReportPath: reportPath,
        env: {
          CONFIRM_IMPORT: 'true',
          SUPABASE_URL: 'https://vmareepfbgocyleknrgg.supabase.co',
        },
      }),
    ).toThrow(/not allowed/i);

    rmSync(dir, { recursive: true, force: true });
  });

  test('blocks service_role unless explicitly allowed', () => {
    const dir = mkdtempSync(join(tmpdir(), 'marineflow-import-guard-'));
    const reportPath = join(dir, 'report.json');
    writeFileSync(reportPath, '{}', 'utf8');

    expect(() =>
      assertImportAllowed({
        backupPath: 'backup.json',
        dryRunReportPath: reportPath,
        env: {
          CONFIRM_IMPORT: 'true',
          SUPABASE_URL: 'https://staging-example.supabase.co',
          SUPABASE_SERVICE_ROLE_KEY: 'secret',
        },
      }),
    ).toThrow(/service_role/i);

    rmSync(dir, { recursive: true, force: true });
  });

  test('importBackup remains disabled even when the guard passes', () => {
    const dir = mkdtempSync(join(tmpdir(), 'marineflow-import-guard-'));
    const reportPath = join(dir, 'report.json');
    writeFileSync(reportPath, '{}', 'utf8');

    expect(() =>
      importBackup({
        backupPath: 'backup.json',
        dryRunReportPath: reportPath,
        env: {
          CONFIRM_IMPORT: 'true',
          SUPABASE_URL: 'https://staging-example.supabase.co',
        },
      }),
    ).toThrow(/intentionally left disabled/i);

    rmSync(dir, { recursive: true, force: true });
  });
});
