import { importGuardMessage } from './migration-config';

export function assertImportAllowed() {
  if (process.env.CONFIRM_IMPORT !== 'true') {
    throw new Error(importGuardMessage);
  }
}

export function importBackup() {
  assertImportAllowed();
  throw new Error('Import implementation intentionally left disabled until remote-write approval.');
}
