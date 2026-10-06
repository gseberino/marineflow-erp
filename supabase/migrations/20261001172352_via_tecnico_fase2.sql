-- Via do técnico, fase 2 (01/10/2026)
--
-- O que o escritório escreve para o técnico e o que volta do papel. Avaliação de 01/10: a via
-- não tinha onde dizer "até onde ir", "onde fica e como entrar" nem "este serviço é só para
-- levantar". Só acréscimos; nada é apagado nem renomeado.
--
-- Atenção (achado de 01/10, não resolvido aqui): o portal do cliente lê service_orders e
-- vessels com select('*') como anon. Estas colunas, como as notas internas que já existem,
-- chegam ao navegador do cliente pelo link /view/ — não aparecem na tela, mas estão na rede.

-- ── OS: instrução ao técnico e local/acesso do serviço ─────────────────────────────────────
alter table public.service_orders add column if not exists technician_instructions text;
alter table public.service_orders add column if not exists site_access text;

comment on column public.service_orders.technician_instructions is
  'Instrução do escritório ao técnico: ressalvas, o que não fazer, o que pedir aprovação. Sai só na via do técnico.';
comment on column public.service_orders.site_access is
  'Onde o serviço acontece e como entrar (endereço, vaga, chave, portaria, horário). Preenchido a partir do veículo; sai na via do técnico.';

-- ── Linha de serviço: instrução e situação na via (antes de sair e na volta do papel) ─────────
alter table public.service_order_services add column if not exists technician_instructions text;
alter table public.service_order_services add column if not exists field_status text not null default 'a_fazer';
alter table public.service_order_services add column if not exists field_status_note text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'service_order_services_field_status_check'
  ) then
    alter table public.service_order_services
      add constraint service_order_services_field_status_check
      check (field_status in ('a_fazer', 'so_levantar', 'aguarda_peca', 'feito', 'parcial', 'nao_feito'));
  end if;
end $$;

comment on column public.service_order_services.technician_instructions is
  'Instrução ao técnico para este serviço. Sai no cartão do serviço na via do técnico.';
comment on column public.service_order_services.field_status is
  'Situação na via: a_fazer | so_levantar (medir/fotografar, não executar) | aguarda_peca | feito | parcial | nao_feito. Os três últimos vêm do papel, pela tela Lançar a via.';
comment on column public.service_order_services.field_status_note is
  'Motivo do parcial/não feito, ou observação da situação.';

-- ── Veículo: local e acesso padrão; tipo sem "Lancha" automático ──────────────────────────
alter table public.vessels add column if not exists access_notes text;
comment on column public.vessels.access_notes is
  'Local e acesso padrão do veículo (marina/vaga, endereço de guarda, chave, portaria). Sugerido em cada OS nova.';

-- O padrão 'Lancha' transformava em lancha todo veículo criado sem escolher o tipo
-- (HOMEBUS, uma Hilux e um Iveco estavam assim em 01/10). Sem padrão, quem cria escolhe.
alter table public.vessels alter column asset_type drop default;

-- ── Visões do técnico: as colunas novas entram no fim (mesma ordem das existentes) ─────────
create or replace view public.service_orders_tecnico with (security_invoker = on) as
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
  created_by, created_at, updated_at,
  technician_instructions, site_access
from public.service_orders;

create or replace view public.service_order_services_tecnico with (security_invoker = on) as
select id, service_order_id, service_id, name_snapshot, description_snapshot,
  billing_unit_snapshot, quantity, notes, technician_user_id, started_at, finished_at,
  elapsed_minutes, service_system, service_verb, fiscal_verb, warranty_days, warranty_months,
  warranty_expires_at, created_at, updated_at,
  technician_instructions, field_status, field_status_note
from public.service_order_services;

-- Registro com a versão do ARQUIVO, para um db push futuro não reexecutar.
insert into supabase_migrations.schema_migrations (version, name)
values ('20261001172352', 'via_tecnico_fase2')
on conflict (version) do nothing;
