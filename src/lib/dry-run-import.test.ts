import { describe, expect, test } from 'vitest';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import {
  compareDryRunComparison,
  resolveMigrationEnv,
  resolveDryRunSupabaseConfig,
} from '../../scripts/migration/cli.mjs';

describe('resolveDryRunSupabaseConfig', () => {
  test('prefers Vite public env vars and falls back to public anon vars', () => {
    const config = resolveDryRunSupabaseConfig({
      VITE_SUPABASE_URL: 'https://vite.example.supabase.co',
      VITE_SUPABASE_PUBLISHABLE_KEY: 'vite-public-key',
      SUPABASE_URL: 'https://fallback.example.supabase.co',
      SUPABASE_ANON_KEY: 'fallback-anon-key',
    });

    expect(config).toEqual({
      url: 'https://vite.example.supabase.co',
      key: 'vite-public-key',
      source: 'VITE_SUPABASE_URL / VITE_SUPABASE_PUBLISHABLE_KEY',
    });
  });
});

describe('resolveMigrationEnv', () => {
  test('loads env values from a staging env file when present', () => {
    const dir = mkdtempSync(join(tmpdir(), 'marineflow-staging-env-'));
    const envPath = join(dir, '.env.staging.local');

    writeFileSync(
      envPath,
      [
        'VITE_SUPABASE_URL=https://file.example.supabase.co',
        'VITE_SUPABASE_PUBLISHABLE_KEY=file-public-key',
        'SUPABASE_URL=https://file.example.supabase.co',
        'SUPABASE_ANON_KEY=file-anon-key',
        'APP_PUBLIC_URL=http://localhost:5173',
      ].join('\n'),
    );

    const resolved = resolveMigrationEnv({}, envPath);

    expect(resolved.envStatus).toBe('loaded');
    expect(resolveDryRunSupabaseConfig(resolved.env)).toEqual({
      url: 'https://file.example.supabase.co',
      key: 'file-public-key',
      source: 'VITE_SUPABASE_URL / VITE_SUPABASE_PUBLISHABLE_KEY',
    });

    rmSync(dir, { recursive: true, force: true });
  });

  test('keeps process env values ahead of the local staging env file', () => {
    const dir = mkdtempSync(join(tmpdir(), 'marineflow-staging-env-'));
    const envPath = join(dir, '.env.staging.local');

    writeFileSync(
      envPath,
      [
        'VITE_SUPABASE_URL=https://file.example.supabase.co',
        'VITE_SUPABASE_PUBLISHABLE_KEY=file-public-key',
      ].join('\n'),
    );

    const resolved = resolveMigrationEnv(
      {
        VITE_SUPABASE_URL: 'https://process.example.supabase.co',
        VITE_SUPABASE_PUBLISHABLE_KEY: 'process-public-key',
      },
      envPath,
    );

    expect(resolveDryRunSupabaseConfig(resolved.env)).toEqual({
      url: 'https://process.example.supabase.co',
      key: 'process-public-key',
      source: 'VITE_SUPABASE_URL / VITE_SUPABASE_PUBLISHABLE_KEY',
    });

    rmSync(dir, { recursive: true, force: true });
  });

  test('reports missing when the staging env file does not exist', () => {
    const dir = mkdtempSync(join(tmpdir(), 'marineflow-staging-env-'));
    const envPath = join(dir, '.env.staging.local');

    const resolved = resolveMigrationEnv(
      {
        VITE_SUPABASE_URL: 'https://process.example.supabase.co',
        VITE_SUPABASE_PUBLISHABLE_KEY: 'process-public-key',
      },
      envPath,
    );

    expect(resolved.envStatus).toBe('missing');
    expect(resolveDryRunSupabaseConfig(resolved.env)).toEqual({
      url: 'https://process.example.supabase.co',
      key: 'process-public-key',
      source: 'VITE_SUPABASE_URL / VITE_SUPABASE_PUBLISHABLE_KEY',
    });

    rmSync(dir, { recursive: true, force: true });
  });
});

describe('compareDryRunComparison', () => {
  test('classifies create, update, ignore and blocked tables from read-only data', () => {
    const report = compareDryRunComparison({
      backup: {
        clients: [
          { id: 'c1', name: 'Ana', updated_at: '2026-05-10T10:00:00Z' },
          { id: 'c2', name: 'Bea' },
        ],
      },
      liveByTable: {
        clients: [
          { id: 'c1', name: 'Ana', updated_at: '2026-05-11T10:00:00Z' },
          { id: 'c2', name: 'Beatriz' },
        ],
      },
      blockedTables: [
        {
          table: 'services',
          error: 'RLS denied select',
        },
      ],
      analysis: {
        tablesFound: ['clients'],
        tableCounts: { clients: 2 },
        duplicateSummary: {
          duplicateIdGroupsByTable: {},
          duplicateKeyGroups: {},
        },
        missingReferences: {
          total: 0,
          byRule: {},
        },
        missingExpectedTables: [],
      },
    });

    expect(report.tablesCompared).toEqual(['clients']);
    expect(report.counts.clients).toEqual({
      backup: 2,
      live: 2,
      create: 0,
      update: 1,
      ignore: 1,
    });
    expect(report.blockedTables).toEqual([
      {
        table: 'services',
        error: 'RLS denied select',
      },
    ]);
  });
});
