import { runValidateStagingSchema } from './cli.mjs';

export type ValidateStagingSchemaOptions = Parameters<typeof runValidateStagingSchema>[0];

export async function validateStagingSchema(options: ValidateStagingSchemaOptions) {
  return runValidateStagingSchema(options);
}

// Runtime lives in scripts/migration/cli.mjs for now.
