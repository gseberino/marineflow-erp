## Phase 1 — Foundation (This session)
1. **Enable Lovable Cloud** — Real database, auth, RLS for persistence
2. **i18n Architecture** — Build translation system with pt-BR/en, language selector in Settings
3. **Multi-currency Foundation** — Currency types, exchange rate entity, settings UI, historical value preservation in types

## Phase 2 — Database & Core Modules
4. **Database Schema** — Create all tables (clients, vessels, marinas, products, service_orders, etc.) with proper relations and currency fields
5. **CRUD Operations** — Connect all list/detail/form pages to real Supabase queries
6. **Dashboard** — Replace fake metrics with real database queries, honest empty states

## Phase 3 — Service Orders & Field Operations
7. **Service Order Wizard** — Real creation flow with client→vessel→marina linkage
8. **Travel Calculator** — Real calculation from settings + marina coordinates
9. **Mobile Technician View** — Simplified mobile-first SO execution interface
10. **Time Tracking & Parts** — Real labor/parts tracking with inventory deduction

## Phase 4 — Financial & Reports
11. **Financial Module** — Real receivables/payables/invoices linked to service orders
12. **Reports** — Real aggregation queries with filters
13. **Inventory** — Real stock movements and traceability

## Phase 5 — Auth & Permissions
14. **User Roles** — Admin/Technician/Financial with RLS-based access control
15. **Permission-shaped UI** — Hide/show actions based on actual role

### Approach
- Start with Phase 1 (i18n + Cloud enable) since i18n touches every file and Cloud is needed for everything else
- Each phase builds on the previous
- Will proceed iteratively across multiple messages given the scope