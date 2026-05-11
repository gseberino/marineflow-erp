import { runStagingReadiness } from './cli.mjs';

export type CheckStagingReadinessOptions = Parameters<typeof runStagingReadiness>[0];

export async function checkStagingReadiness(options: CheckStagingReadinessOptions) {
  return runStagingReadiness(options);
}

// Runtime lives in scripts/migration/cli.mjs for now.
