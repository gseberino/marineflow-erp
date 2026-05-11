import { readFileSync } from 'node:fs';
import { analyzeBackupDataset } from '../../src/lib/migration-report';
import { validateBackupPayload } from '../../src/lib/master-data-backup';
import { duplicateKeyRules, foreignKeyRules } from './migration-config';

export function analyzeBackupFile(path: string) {
  const raw = JSON.parse(readFileSync(path, 'utf8'));
  const validation = validateBackupPayload(raw);
  if (!validation.ok) {
    throw new Error(`Invalid backup payload: ${validation.reason}`);
  }

  return analyzeBackupDataset(raw, {
    duplicateKeyRules,
    foreignKeys: foreignKeyRules,
  });
}
