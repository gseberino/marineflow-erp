-- NOVO-006 / NOVO-008 / NOVO-020 — o técnico deixa de LER valores da OS e dos itens.
--
-- Retrabalho da view rejeitada em 11/08 (spec em audit/retrabalho/README-view-tecnico.md):
--   · sem invoicing_status e payment_status (decisão (b) do dono, 11/08). Não fez falta:
--     o bloqueio de edição do formulário usa `status` ('invoiced'/'cancelled'), que fica;
--   · views IRMÃS para os itens (NOVO-008): service_order_parts e service_order_services
--     têm preço/custo/desconto por linha — fechar só a tabela-mãe deixava a soma à vista;
--   · o frontend passa a ter SELECT próprio para o técnico (colunas nomeadas, sem embed de
--     payment_condition_presets, que derrubaria a consulta com PGRST200 — NOVO-020a) e o
--     Salvar do técnico deixa de reenviar campo de valor (NOVO-020b).
--
-- POR QUE VIEWS E NÃO REVOKE DE COLUNA: `REVOKE SELECT (coluna)` não omite a coluna — recusa a
-- consulta inteira (42501), e o frontend pede `*` em toda parte (NOVO-006).
--
-- COLUNAS LISTADAS UMA A UMA, DE PROPÓSITO: coluna de valor criada no futuro não entra
-- sozinha. O preço é o oposto — coluna operacional nova também não aparece até alguém
-- acrescentar. É a falha para o lado seguro.
--
-- CRITÉRIO DO QUE FICOU DE FORA: valor monetário, percentual de precificação/comissão,
-- forma/condição de pagamento e `share_token` (abre o link público, que mostra valores).
--
-- security_invoker=on nas três: a RLS das tabelas base continua valendo — a view restringe
-- COLUNA, nunca LINHA. Sem isso a view rodaria como postgres e viraria buraco na RLS.

-- ── 1. A ordem ───────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.service_orders_tecnico
WITH (security_invoker = on) AS
SELECT
  id,
  service_order_number,
  client_id,
  vessel_id,
  marina_id,
  requested_by_name,
  requested_by_contact_id,
  scheduled_start_at,
  scheduled_end_at,
  check_in_at,
  check_out_at,
  status,
  quote_status,
  priority,
  service_type,
  problem_description,
  initial_findings,
  diagnosis,
  solution_applied,
  technician_notes,
  internal_notes,
  extra_notes,
  customer_visible_report,
  estimated_hours,
  labor_hours_total,
  travel_distance_km,
  technician_count_for_travel,
  travel_hours,
  travel_type,
  is_travel_billable,
  currency,
  client_signature_url,
  signed_at,
  signed_by_name,
  signed_document_hash,
  requires_resignature,
  resignature_requested_at,
  photos,
  survey_id,
  estimate_confidence,
  customer_po_number,
  customer_buyer_name,
  quote_validity_days,
  quote_validity_date,
  converted_to_os_at,
  cancelled_at,
  cancellation_reason,
  reopened_at,
  reopen_reason,
  reminder_sent_at,
  created_by,
  created_at,
  updated_at
FROM public.service_orders;

COMMENT ON VIEW public.service_orders_tecnico IS
  'OS sem nenhuma coluna de valor nem de situação financeira, para o cargo técnico (NOVO-006/020). '
  'security_invoker=on: a RLS de service_orders continua valendo — restringe COLUNA, nunca LINHA. '
  'Colunas listadas uma a uma de propósito: coluna de valor nova não entra sozinha.';

REVOKE ALL ON public.service_orders_tecnico FROM PUBLIC;
REVOKE ALL ON public.service_orders_tecnico FROM anon;
GRANT SELECT ON public.service_orders_tecnico TO authenticated;
GRANT SELECT ON public.service_orders_tecnico TO service_role;

-- ── 2. As peças (sem custo, preço, total e desconto por linha) ───────────────
CREATE OR REPLACE VIEW public.service_order_parts_tecnico
WITH (security_invoker = on) AS
SELECT
  id,
  service_order_id,
  service_order_service_id,
  product_id,
  quantity,
  serial_number,
  notes,
  source,
  warranty_days,
  warranty_months,
  warranty_expires_at,
  created_at,
  updated_at
FROM public.service_order_parts;

COMMENT ON VIEW public.service_order_parts_tecnico IS
  'Peças da OS sem unit_cost/unit_sale/line_total/desconto (NOVO-008). security_invoker=on.';

REVOKE ALL ON public.service_order_parts_tecnico FROM PUBLIC;
REVOKE ALL ON public.service_order_parts_tecnico FROM anon;
GRANT SELECT ON public.service_order_parts_tecnico TO authenticated;
GRANT SELECT ON public.service_order_parts_tecnico TO service_role;

-- ── 3. Os serviços (sem preço unitário, total e desconto por linha) ──────────
CREATE OR REPLACE VIEW public.service_order_services_tecnico
WITH (security_invoker = on) AS
SELECT
  id,
  service_order_id,
  service_id,
  name_snapshot,
  description_snapshot,
  billing_unit_snapshot,
  quantity,
  notes,
  technician_user_id,
  started_at,
  finished_at,
  elapsed_minutes,
  service_system,
  service_verb,
  fiscal_verb,
  warranty_days,
  warranty_months,
  warranty_expires_at,
  created_at,
  updated_at
FROM public.service_order_services;

COMMENT ON VIEW public.service_order_services_tecnico IS
  'Serviços da OS sem unit_price/line_total/desconto (NOVO-008). security_invoker=on.';

REVOKE ALL ON public.service_order_services_tecnico FROM PUBLIC;
REVOKE ALL ON public.service_order_services_tecnico FROM anon;
GRANT SELECT ON public.service_order_services_tecnico TO authenticated;
GRANT SELECT ON public.service_order_services_tecnico TO service_role;

-- Auto-registro da versão do arquivo (regra 1 do CLAUDE.md).
insert into supabase_migrations.schema_migrations (version, name)
values ('20260910120000', 'views_tecnico_sem_valores')
on conflict (version) do nothing;

-- ── Verificação depois de aplicar (não é parte da migration) ─────────────────
-- 1. Nenhuma coluna de valor sobreviveu nas três views:
--      SELECT table_name, column_name FROM information_schema.columns
--       WHERE table_schema='public' AND table_name LIKE '%_tecnico'
--         AND column_name ~ 'cost|total|amount|price|fee|rate|discount|commission|payment|share_token|invoicing';
--      -- esperado: 0 linhas
-- 2. Anônimo não lê:  SELECT has_table_privilege('anon','public.service_orders_tecnico','SELECT');  -- false
-- 3. security_invoker: SELECT relname, reloptions FROM pg_class WHERE relname LIKE '%_tecnico';
-- 4. PostgREST enxerga os relacionamentos a partir das views (só o ambiente real responde):
--      GET /rest/v1/service_orders_tecnico?select=id,clients(name),service_order_parts_tecnico(id)&limit=1
--      com apikey anon: resposta 42501/permission (embed resolvido) é sucesso; PGRST200 é falha.
