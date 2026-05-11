import { describe, expect, test } from 'vitest';
import {
  compareDryRunComparison,
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
