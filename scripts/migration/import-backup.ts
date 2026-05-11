import { existsSync } from 'node:fs';
import {
  blockedProjectRefs,
  importGuardMessage,
  isBlockedSupabaseProjectRef,
  isProbablyProductionContext,
} from './migration-config';

export type ImportBackupOptions = {
  backupPath?: string;
  dryRunReportPath?: string;
  env?: Record<string, string | undefined>;
  allowServiceRole?: boolean;
};

export function assertImportAllowed(options: ImportBackupOptions = {}) {
  const env = options.env ?? process.env;

  if (env.CONFIRM_IMPORT !== 'true') {
    throw new Error(importGuardMessage);
  }

  if (!options.backupPath) {
    throw new Error('Backup path is required before import.');
  }

  if (!options.dryRunReportPath || !existsSync(options.dryRunReportPath)) {
    throw new Error('A verified dry-run report is required before import.');
  }

  if (isProbablyProductionContext(env)) {
    throw new Error('Import blocked: environment looks like production.');
  }

  const projectRef = env.VITE_SUPABASE_URL ?? env.SUPABASE_URL;
  if (isBlockedSupabaseProjectRef(projectRef)) {
    throw new Error(
      `Import blocked: project ref is not allowed (${blockedProjectRefs.join(', ')}).`,
    );
  }

  if (env.SUPABASE_SERVICE_ROLE_KEY?.trim() && !options.allowServiceRole) {
    throw new Error('Import blocked: service_role is not permitted in this phase.');
  }
}

export function importBackup(options: ImportBackupOptions = {}) {
  assertImportAllowed(options);
  throw new Error('Import implementation intentionally left disabled until remote-write approval.');
}
