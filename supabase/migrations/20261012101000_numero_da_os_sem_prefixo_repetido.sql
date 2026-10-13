-- O número da OS sem "OS " repetido no banco (12/10/2026 — spec-observacao-atomica-prefixo.md, C).
--
-- service_order_number já traz o prefixo ("OS-00060", "ORÇ-00112": os 113 de produção, conferidos em
-- 12/10/2026). Dois pontos do banco ainda punham "OS " na frente dele:
--   · a view erp_open_loop_facts (os fios da agenda): "OS OS-00060 — aberta" e "Materiais da OS OS-00060
--     a receber". refresh_entity_open_loops() copia o título da view para entity_open_loops só nos fios
--     ABERTOS: a primeira rodada da task-automations depois desta migration reescreve esses títulos (é a
--     cópia viva da view, não correção de dado antigo; os fios resolvidos ficam como estão);
--   · registrar_confirmacao_do_cliente (o aviso do sino quando o cliente responde SIM): "OS OS-00060,
--     12/10 às 09h00 — respondeu…". A casca passa a search_path vazio: o corpo já qualifica tudo com
--     public. e o resto é do pg_catalog.
-- O número vai como vem: "OS-00060" já diz OS e "ORÇ-00112" já diz orçamento. Dado antigo NÃO é corrigido
-- (os recebíveis, as tarefas e os avisos que já saíram ficam como estão).
--
-- A view segue security_invoker (o create or replace troca as opções pelas que vierem: sem o "with" ela
-- voltaria a rodar com os direitos da dona) e sem select para anon; as colunas não mudam de nome nem de
-- tipo. Não escreve dados. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. Os fios da agenda: o número da OS como vem
-- ---------------------------------------------------------------------------------------------
-- corpo de 20260727193904 IGUAL + "with (security_invoker = on)" + os 2 títulos sem o "OS " na frente do número
create or replace view public.erp_open_loop_facts with (security_invoker = on) as
SELECT
  'client'::text AS entity_type,
  so.client_id   AS entity_id,
  'so:' || so.id::text AS loop_key,
  'service_order'::text AS kind,
  (so.service_order_number || ' — ' || CASE so.status
      WHEN 'open'           THEN 'aberta'
      WHEN 'approved'       THEN 'aprovada, a agendar'
      WHEN 'scheduled'      THEN 'agendada'
      WHEN 'in_progress'    THEN 'em execução'
      WHEN 'awaiting_parts' THEN 'aguardando peças'
      ELSE so.status END)::text AS title,
  left(coalesce(so.problem_description, ''), 180)::text AS detail,
  'service_orders'::text AS ref_table,
  so.id AS ref_id,
  so.id AS service_order_id,
  so.scheduled_start_at AS due_at,
  (CASE WHEN so.status = 'awaiting_parts' THEN 'high' ELSE 'normal' END)::text AS priority
FROM public.service_orders so
WHERE so.client_id IS NOT NULL
  AND so.status IN ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts')

UNION ALL

SELECT
  'client'::text,
  so.client_id,
  'so-parts:' || so.id::text,
  'delivery'::text,
  ('Materiais da ' || so.service_order_number || ' a receber')::text,
  (count(DISTINCT poi.id)::text || ' item(ns) pendente(s): ' ||
   left(string_agg(DISTINCT coalesce(poi.description, 'item'), ', '), 150))::text,
  'purchase_orders'::text,
  (array_agg(po.id ORDER BY po.expected_date NULLS LAST, po.id))[1],
  so.id,
  min((po.expected_date::timestamp AT TIME ZONE 'America/Sao_Paulo')),
  (CASE WHEN min(po.expected_date) < current_date THEN 'high' ELSE 'normal' END)::text
FROM public.purchase_orders po
JOIN public.service_orders so ON so.id = po.service_order_id
JOIN public.purchase_order_items poi ON poi.purchase_order_id = po.id
WHERE so.client_id IS NOT NULL
  AND po.received_date IS NULL
  AND coalesce(po.status, '') NOT IN ('cancelled', 'canceled', 'received')
  AND coalesce(poi.received_qty, 0) < poi.quantity
GROUP BY so.id, so.client_id, so.service_order_number

UNION ALL

SELECT
  'client'::text,
  q.client_id,
  'quote:' || q.id::text,
  'quote'::text,
  ('Orçamento ' || coalesce(q.quote_number, '') || ' aguardando resposta do cliente')::text,
  left(coalesce(q.problem_description, ''), 180)::text,
  'external_quotes'::text,
  q.id,
  NULL::uuid,
  (q.quote_validity_date::timestamp AT TIME ZONE 'America/Sao_Paulo'),
  'normal'::text
FROM public.external_quotes q
WHERE q.client_id IS NOT NULL
  AND q.status IN ('pending_approval', 'pending_product')

UNION ALL

SELECT
  'client'::text,
  r.client_id,
  'ar:' || r.id::text,
  'receivable'::text,
  ((CASE WHEN r.due_date < current_date THEN 'Título VENCIDO ' ELSE 'Título a vencer ' END)
   || 'R$ ' || translate(to_char(coalesce(r.balance_amount, r.amount), 'FM999G999G990D00'), ',.', '.,'))::text,
  left(coalesce(r.description, ''), 180)::text,
  'receivables'::text,
  r.id,
  r.service_order_id,
  (r.due_date::timestamp AT TIME ZONE 'America/Sao_Paulo'),
  (CASE WHEN r.due_date < current_date THEN 'urgent' ELSE 'high' END)::text
FROM public.receivables r
WHERE r.client_id IS NOT NULL
  AND r.status = 'pending'
  AND r.due_date <= current_date + 15
  AND coalesce(r.balance_amount, r.amount) > 0

UNION ALL

SELECT
  'supplier'::text,
  po.supplier_id,
  'po:' || po.id::text,
  'purchase_order'::text,
  ('Compra ' || coalesce(po.po_number, '') || ' aguardando entrega')::text,
  left(coalesce(po.notes, ''), 180)::text,
  'purchase_orders'::text,
  po.id,
  po.service_order_id,
  (po.expected_date::timestamp AT TIME ZONE 'America/Sao_Paulo'),
  (CASE WHEN po.expected_date < current_date THEN 'high' ELSE 'normal' END)::text
FROM public.purchase_orders po
WHERE po.supplier_id IS NOT NULL
  AND po.received_date IS NULL
  AND coalesce(po.status, '') NOT IN ('cancelled', 'canceled', 'received')

UNION ALL

SELECT
  'supplier'::text,
  p.supplier_id,
  'ap:' || p.id::text,
  'payable'::text,
  ((CASE WHEN p.due_date < current_date THEN 'Pagamento VENCIDO ' ELSE 'Pagamento a vencer ' END)
   || 'R$ ' || translate(to_char(coalesce(p.balance_amount, p.amount), 'FM999G999G990D00'), ',.', '.,'))::text,
  left(coalesce(p.description, ''), 180)::text,
  'payables'::text,
  p.id,
  p.linked_service_order_id,
  (p.due_date::timestamp AT TIME ZONE 'America/Sao_Paulo'),
  (CASE WHEN p.due_date < current_date THEN 'urgent' ELSE 'high' END)::text
FROM public.payables p
WHERE p.supplier_id IS NOT NULL
  AND p.status = 'pending'
  AND p.due_date <= current_date + 15
  AND coalesce(p.balance_amount, p.amount) > 0;

revoke all on public.erp_open_loop_facts from anon;

comment on view public.erp_open_loop_facts is
  'Os fatos dos fios em aberto (OS, materiais a receber, orçamento, títulos, compras, pagamentos). O número da OS vai como vem: ele já traz o prefixo (OS-00060, ORÇ-00112).';

-- ---------------------------------------------------------------------------------------------
-- 2. O aviso do sino quando o cliente confirma: o número da OS como vem
-- ---------------------------------------------------------------------------------------------
-- corpo de 20260930130000:109-163 IGUAL + search_path vazio na casca + o aviso sem o "OS " na frente do número
create or replace function public.registrar_confirmacao_do_cliente(p_phone text, p_body text, p_message_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_os record;
  v_n int;
  v_quando text;
begin
  if length(v_fone) < 8 or not public._e_concordancia(p_body) then
    return jsonb_build_object('confirmou', false);
  end if;

  -- OS agendada, com pedido de confirmação nas últimas 72 h e ainda sem resposta, deste cliente.
  select count(*) into v_n
    from public.service_orders s join public.clients c on c.id = s.client_id
   where s.status = 'scheduled' and s.scheduled_start_at > now() - interval '2 hours'
     and s.client_confirmation_requested_at > now() - interval '72 hours'
     and s.client_confirmed_at is null
     and right(regexp_replace(coalesce(nullif(c.whatsapp, ''), c.phone, ''), '\D', '', 'g'), 8) = right(v_fone, 8);
  if v_n = 0 then return jsonb_build_object('confirmou', false); end if;

  if v_n > 1 then
    -- Duas OS esperando: "sim" não diz qual. Avisa o dono em vez de adivinhar.
    insert into public.app_notifications (user_id, type, title, body, navigate_to)
    select u.id, 'agendamento_confirmado', 'Cliente respondeu SIM, mas há ' || v_n || ' OS esperando confirmação',
           'Confira com o cliente qual atendimento ele confirmou.', '/agenda'
      from public.app_users u where u.role = 'admin' and u.active;
    return jsonb_build_object('confirmou', false, 'ambigua', v_n);
  end if;

  select s.id, s.service_order_number, s.scheduled_start_at, c.name as cliente into v_os
    from public.service_orders s join public.clients c on c.id = s.client_id
   where s.status = 'scheduled' and s.scheduled_start_at > now() - interval '2 hours'
     and s.client_confirmation_requested_at > now() - interval '72 hours'
     and s.client_confirmed_at is null
     and right(regexp_replace(coalesce(nullif(c.whatsapp, ''), c.phone, ''), '\D', '', 'g'), 8) = right(v_fone, 8);

  update public.service_orders
     set client_confirmed_at = now(), client_confirmed_for = v_os.scheduled_start_at
   where id = v_os.id;

  v_quando := to_char(v_os.scheduled_start_at at time zone 'America/Sao_Paulo', 'DD/MM "às" HH24"h"MI');
  insert into public.app_notifications (user_id, type, title, body, navigate_to)
  select u.id, 'agendamento_confirmado', coalesce(v_os.cliente, 'Cliente') || ' confirmou o atendimento',
         v_os.service_order_number || ', ' || v_quando || ' — respondeu "' || left(btrim(p_body), 40) || '" pelo WhatsApp.',
         '/v2/service-orders/' || v_os.id
    from public.app_users u where u.role = 'admin' and u.active;

  return jsonb_build_object('confirmou', true, 'os', v_os.service_order_number);
end;
$$;

revoke all on function public.registrar_confirmacao_do_cliente(text, text, uuid) from public, anon, authenticated;
grant execute on function public.registrar_confirmacao_do_cliente(text, text, uuid) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova: o aviso só pelo sistema, a casca nova, nenhum "OS " na frente do número; a view segue
-- security_invoker e fechada ao anon.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text := 'public.registrar_confirmacao_do_cliente(text, text, uuid)';
  v_def text;
  v_view text;
begin
  if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute') then
    raise exception 'o registro da confirmação do cliente ficou exposto para anon/authenticated: %', v_f;
  end if;
  if not has_function_privilege('service_role', v_f, 'execute') then
    raise exception 'o webhook (service_role) não alcança %', v_f;
  end if;
  if not (select p.prosecdef from pg_proc p where p.oid = v_f::regprocedure) then
    raise exception 'registrar_confirmacao_do_cliente deixou de ser security definer';
  end if;
  if not coalesce((select 'search_path=""' = any (p.proconfig) from pg_proc p where p.oid = v_f::regprocedure), false) then
    raise exception 'registrar_confirmacao_do_cliente sem o search_path vazio';
  end if;
  v_def := pg_get_functiondef(v_f::regprocedure);
  if position('''OS '' ||' in v_def) > 0 then
    raise exception 'registrar_confirmacao_do_cliente ainda põe "OS " na frente do número da OS';
  end if;
  if not exists (select 1 from pg_class c
                  where c.oid = 'public.erp_open_loop_facts'::regclass
                    and (c.reloptions @> array['security_invoker=on'] or c.reloptions @> array['security_invoker=true'])) then
    raise exception 'erp_open_loop_facts deixou de ser security_invoker';
  end if;
  if has_table_privilege('anon', 'public.erp_open_loop_facts', 'select') then
    raise exception 'erp_open_loop_facts aberta para anon';
  end if;
  v_view := pg_get_viewdef('public.erp_open_loop_facts'::regclass);
  if position('''OS ''::text ||' in v_view) > 0 or position('Materiais da OS ' in v_view) > 0 then
    raise exception 'erp_open_loop_facts ainda põe "OS " na frente do número da OS';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261012101000', 'numero_da_os_sem_prefixo_repetido')
on conflict do nothing;
