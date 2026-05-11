import { beforeEach, describe, expect, test, vi } from 'vitest';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const { fromMock, createClientMock } = vi.hoisted(() => ({
  fromMock: vi.fn(),
  createClientMock: vi.fn(() => ({
    from: vi.fn(),
  })),
}));

vi.mock('@supabase/supabase-js', () => ({
  createClient: createClientMock,
}));

import { resolveMigrationEnv, runStagingReadiness, runValidateStagingSchema } from '../../scripts/migration/cli.mjs';

beforeEach(() => {
  fromMock.mockReset();
  createClientMock.mockClear();
  createClientMock.mockImplementation(() => ({
    from: fromMock,
  }));
});

describe('runStagingReadiness', () => {
  test('resolveMigrationEnv reports missing when the env file does not exist', () => {
    const result = resolveMigrationEnv(
      { VITE_SUPABASE_URL: 'https://process-example.supabase.co' },
      'C:\\temp\\definitely-missing.env',
    );

    expect(result.envStatus).toBe('missing');
    expect(result.env.VITE_SUPABASE_URL).toBe('https://process-example.supabase.co');
  });

  test('resolveMigrationEnv loads .env.staging.local without overriding process env', () => {
    const dir = mkdtempSync(join(tmpdir(), 'marineflow-staging-env-'));
    const envPath = join(dir, '.env.staging.local');
    writeFileSync(
      envPath,
      [
        'VITE_SUPABASE_URL=https://file-example.supabase.co',
        'VITE_SUPABASE_PUBLISHABLE_KEY=file-key',
        'SUPABASE_URL=https://file-example.supabase.co',
        'SUPABASE_ANON_KEY=file-anon',
      ].join('\n'),
      'utf8',
    );

    const result = resolveMigrationEnv(
      {
        VITE_SUPABASE_URL: 'https://process-example.supabase.co',
        VITE_SUPABASE_PUBLISHABLE_KEY: 'process-key',
        SUPABASE_URL: 'https://process-example.supabase.co',
        SUPABASE_ANON_KEY: 'process-anon',
      },
      envPath,
    );

    expect(result.envStatus).toBe('loaded');
    expect(result.env.VITE_SUPABASE_URL).toBe('https://process-example.supabase.co');
    expect(result.env.VITE_SUPABASE_PUBLISHABLE_KEY).toBe('process-key');
    expect(result.env.SUPABASE_URL).toBe('https://process-example.supabase.co');
    expect(result.env.SUPABASE_ANON_KEY).toBe('process-anon');

    rmSync(dir, { recursive: true, force: true });
  });

  test('reports not_configured when no env vars are present', async () => {
    const report = await runStagingReadiness({
      env: {},
      envStatus: 'not-provided',
      envPath: null,
    });

    expect(report.status).toBe('not_configured');
    expect(report.missingEnvVars).toEqual(
      expect.arrayContaining(['VITE_SUPABASE_URL', 'SUPABASE_URL']),
    );
    expect(report.tableChecks).toHaveLength(5);
  });

  test('reports ready_for_schema_validation when all probe tables are empty and readable', async () => {
    fromMock.mockImplementation(() => ({
      select: vi.fn().mockResolvedValue({ data: null, error: null, count: 0 }),
    }));

    const report = await runStagingReadiness({
      env: {
        VITE_SUPABASE_URL: 'https://staging-example.supabase.co',
        VITE_SUPABASE_PUBLISHABLE_KEY: 'public-key',
      },
      envStatus: 'loaded',
      envPath: 'C:\\temp\\.env.staging.local',
    });

    expect(report.status).toBe('ready_for_schema_validation');
    expect(report.sameProjectGuess).toBe('unknown');
    expect(report.tableChecks.every((entry) => entry.status === 'readable')).toBe(true);
  });

  test('reports blocked_by_rls_or_permissions when every probe table is blocked', async () => {
    fromMock.mockImplementation(() => ({
      select: vi.fn().mockResolvedValue({
        data: null,
        error: { message: 'row-level security policy blocked select' },
        count: null,
      }),
    }));

    const report = await runStagingReadiness({
      env: {
        VITE_SUPABASE_URL: 'https://staging-example.supabase.co',
        VITE_SUPABASE_PUBLISHABLE_KEY: 'public-key',
      },
      envStatus: 'loaded',
      envPath: 'C:\\temp\\.env.staging.local',
      mode: 'validate-staging-schema',
    });

    expect(report.status).toBe('blocked_by_rls_or_permissions');
    expect(report.tableChecks.every((entry) => entry.status === 'blocked/read not available')).toBe(true);
  });

  test('reports possibly_not_empty when a readable table has rows', async () => {
    fromMock.mockImplementation((table: string) => ({
      select: vi.fn().mockResolvedValue({
        data: null,
        error: null,
        count: table === 'clients' ? 12 : 0,
      }),
    }));

    const report = await runStagingReadiness({
      env: {
        VITE_SUPABASE_URL: 'https://staging-example.supabase.co',
        VITE_SUPABASE_PUBLISHABLE_KEY: 'public-key',
      },
      envStatus: 'loaded',
      envPath: 'C:\\temp\\.env.staging.local',
    });

    expect(report.status).toBe('possibly_not_empty');
    expect(report.tableChecks.find((entry) => entry.table === 'clients')?.count).toBe(12);
  });

  test('validate staging schema stays read-only and reports limitations', async () => {
    fromMock.mockImplementation(() => ({
      select: vi.fn().mockResolvedValue({ data: null, error: null, count: 0 }),
    }));

    const report = await runValidateStagingSchema({
      env: {
        VITE_SUPABASE_URL: 'https://staging-example.supabase.co',
        VITE_SUPABASE_PUBLISHABLE_KEY: 'public-key',
      },
      envStatus: 'loaded',
      envPath: 'C:\\temp\\.env.staging.local',
    });

    expect(report.mode).toBe('validate-staging-schema');
    expect(report.validationScope).toBe('read-only placeholder');
    expect(report.limitations).toEqual(
      expect.arrayContaining([
        expect.stringMatching(/Does not inspect schema columns/i),
        expect.stringMatching(/public read checks/i),
      ]),
    );
  });
});
