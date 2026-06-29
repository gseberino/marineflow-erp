# Staging Readiness
Generated: 2026-05-19T17:03:17.406Z
Status: blocked_by_rls_or_permissions
Env file status: loaded
Env file path: C:\temp\.env.staging.local
Source env: VITE_SUPABASE_URL / VITE_SUPABASE_PUBLISHABLE_KEY
Same project guess: unknown
## Table Checks
- clients: blocked/read not available (row-level security policy blocked select)
- suppliers: blocked/read not available (row-level security policy blocked select)
- service_orders: blocked/read not available (row-level security policy blocked select)
- products: blocked/read not available (row-level security policy blocked select)
- services: blocked/read not available (row-level security policy blocked select)
## Recommendation
- RLS or permissions blocked all probe tables; verify staging access or use a controlled server-side validation path.