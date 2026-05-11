# Migration Scripts

This directory is the local-only entrypoint for Marineflow backup recovery work.

Rules:
- Do not run write operations against Supabase without explicit approval.
- Always run `analyze-backup` and `dry-run-import` before any import attempt.
- Keep reports in a local ignored directory such as `reports/`.
- Do not re-enable browser-driven import flows from the production UI.

Suggested order:
1. `analyze-backup.ts`
2. `dry-run-import.ts`
3. `validate-import.ts`
4. `import-backup.ts` only with explicit confirmation and backup
