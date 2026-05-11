# Migration Scripts

This directory is the local-only entrypoint for Marineflow backup recovery work.

Rules:
- Do not run write operations against Supabase without explicit approval.
- Always run `analyze-backup` and `dry-run-import` before any import attempt.
- Keep reports in a local ignored directory such as `reports/`.
- Do not re-enable browser-driven import flows from the production UI.
- Use `migration:inventory` to review schema and migration coverage locally when you need a read-only inventory.
- For staging work, copy `.env.staging.example` to `.env.staging.local` and use the `--env .env.staging.local` flag or the `migration:dry-run:staging` / `migration:validate:staging` scripts.
- Use `migration:check-staging` to confirm read-only reachability before schema work.
- Use `migration:validate-staging-schema` only after staging schema exists and is ready for read-only validation.

Suggested order:
1. `analyze-backup.ts`
2. `dry-run-import.ts`
3. `validate-import.ts`
4. `import-backup.ts` only with explicit confirmation and backup
