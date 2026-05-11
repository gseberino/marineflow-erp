import { readFileSync } from 'node:fs';
import { collectBackupTableNames, validateBackupPayload } from '../../src/lib/master-data-backup';

export function dryRunImport(path: string) {
  const raw = JSON.parse(readFileSync(path, 'utf8'));
  const validation = validateBackupPayload(raw);
  if (!validation.ok) {
    throw new Error(`Invalid backup payload: ${validation.reason}`);
  }

  return {
    tables: collectBackupTableNames(raw),
    writePlanned: false,
    nextStep: 'Review conflicts and approvals before any write path.',
  };
}
