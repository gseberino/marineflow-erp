-- Coluna morta service_orders.photos (Diário de Bordo, item "Banco · coluna morta").
--
-- Medição em 19/09/2026: 103 OS, todas com photos = [] (nada escreve nela desde que as
-- fotos passaram a viver em service_order_photos.public_url, ver NOVO-lev-17). A página
-- pública da OS ainda lia a coluna para uma galeria que nunca aparecia; esse trecho saiu
-- do código em 19/09. A view do técnico (service_orders_tecnico) lista a coluna, e view
-- não aceita "tirar coluna" com CREATE OR REPLACE: é preciso derrubar e recriar.
--
-- Por que está na fila do dono: DROP VIEW + DROP COLUMN. Rodar no SQL Editor do Supabase
-- (projeto okurngvcodmljjicopdp) ou com:
--   npx supabase db query --linked -f <este arquivo>
-- Depois, no repo: mover este arquivo para supabase/migrations/, tirar `photos` de
-- src/integrations/supabase/types.ts (blocos service_orders e service_orders_tecnico) e da
-- lista de colunas esperadas em src/lib/service-orders-source.test.ts (linha ~177).

begin;

drop view if exists public.service_orders_tecnico;

create view public.service_orders_tecnico
with (security_invoker = on) as
select id, service_order_number, client_id, vessel_id, marina_id, requested_by_name,
       requested_by_contact_id, scheduled_start_at, scheduled_end_at, check_in_at, check_out_at,
       status, quote_status, priority, service_type, problem_description, initial_findings,
       diagnosis, solution_applied, technician_notes, internal_notes, extra_notes,
       customer_visible_report, estimated_hours, labor_hours_total, travel_distance_km,
       technician_count_for_travel, travel_hours, travel_type, is_travel_billable, currency,
       client_signature_url, signed_at, signed_by_name, signed_document_hash, requires_resignature,
       resignature_requested_at, survey_id, estimate_confidence, customer_po_number,
       customer_buyer_name, quote_validity_days, quote_validity_date, converted_to_os_at,
       cancelled_at, cancellation_reason, reopened_at, reopen_reason, reminder_sent_at,
       created_by, created_at, updated_at
from public.service_orders;

-- Mesmos acessos de antes: o técnico lê pela view; anon não.
grant select on public.service_orders_tecnico to authenticated;
revoke all on public.service_orders_tecnico from anon;

alter table public.service_orders drop column if exists photos;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260919140000', 'apagar_coluna_morta_photos')
on conflict do nothing;

commit;
