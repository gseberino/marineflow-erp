import { analyzeBackupFile } from './analyze-backup';

export function validateImport(path: string) {
  const report = analyzeBackupFile(path);

  return {
    passed: report.missingReferences.length === 0,
    report,
  };
}
