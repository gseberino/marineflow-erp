-- Prova: o número da OS sem "OS " repetido no banco (migration 20261012101000).
--
--   N1 os fios da agenda (erp_open_loop_facts): "OS-9xxxxx — aberta" e "Materiais da OS-9xxxxx a receber";
--      nenhum título com "OS OS-" ou "OS ORÇ-"
--   N2 registrar_confirmacao_do_cliente: o "sim" do cliente confirma e o aviso do sino começa com o número
--      como vem ("OS-9xxxxx, …"), nunca "OS OS-"
--   N3 a view segue security_invoker e sem select para anon; o registro da confirmação só pelo sistema
--
-- ═══ COMO RODAR ═══ (só com OK nomeado; também roda no ensaio PGlite da bancada: rodar-numero-da-os.mjs)
--
--   supabase db query --linked -f supabase/tests/numero_da_os_sem_prefixo_repetido.sql --output json
--
-- Seguro em produção: cliente, barco e OS de teste (número OS-9xxxxx livre, criada já no status do teste:
-- nenhum gatilho de mudança de status roda), uma compra de teste ligada a ela, um admin de teste (o aviso
-- do sino tem destino também no ensaio) e telefone aleatório; termina em ROLLBACK. Nenhuma mensagem sai:
-- registrar_confirmacao_do_cliente só marca a OS e grava o aviso do sino.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- ── helpers da transação (somem no rollback) ────────────────────────────────────────────────
create function pg_temp._letras(n integer) returns text language sql volatile as $$
  select translate(substr(md5(random()::text || clock_timestamp()::text), 1, n), '0123456789', 'ghijklmnop')
$$;

-- OS de teste com cliente e barco próprios, já no status pedido; número OS-9xxxxx livre
create function pg_temp._os(p_status text, p_whatsapp text default null, p_agendada_em timestamptz default null,
                            p_pedido_em timestamptz default null)
returns uuid language plpgsql as $$
declare
  v_cli uuid;
  v_ves uuid;
  v_os uuid;
  v_num integer := 900000 + floor(random() * 99000)::integer;
begin
  while exists (select 1 from public.service_orders where service_order_number = 'OS-' || v_num) loop
    v_num := v_num + 1;
  end loop;
  insert into public.clients (type, name, whatsapp) values ('individual', 'Cliente Teste OS ' || pg_temp._letras(6), p_whatsapp)
  returning id into v_cli;
  insert into public.vessels (client_id, name) values (v_cli, 'Navio' || pg_temp._letras(8)) returning id into v_ves;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, invoicing_status,
                                     grand_total, operational_cost_total, labor_cost_total, travel_cost_total,
                                     scheduled_start_at, client_confirmation_requested_at)
  values ('OS-' || v_num, v_cli, v_ves, p_status, 'not_invoiced', 0, 0, 0, 0, p_agendada_em, p_pedido_em)
  returning id into v_os;
  return v_os;
end $$;

-- ═══ N1 os fios da agenda ═══════════════════════════════════════════════════════════════════
do $$
declare
  v_os uuid := pg_temp._os('open');
  v_num text;
  v_po uuid;
  v_titulo text;
  v_materiais text;
  v_ruins integer;
begin
  select service_order_number into v_num from public.service_orders where id = v_os;
  insert into public.purchase_orders (po_number, status, service_order_id, expected_date)
  values ('PO-TESTE-' || upper(pg_temp._letras(10)), 'sent', v_os, current_date + 3)
  returning id into v_po;
  insert into public.purchase_order_items (purchase_order_id, description, quantity, received_qty)
  values (v_po, 'Peça de teste', 2, 0);
  select title into v_titulo from public.erp_open_loop_facts where loop_key = 'so:' || v_os;
  select title into v_materiais from public.erp_open_loop_facts where loop_key = 'so-parts:' || v_os;
  select count(*) into v_ruins from public.erp_open_loop_facts where title ~ 'OS (OS|ORÇ)-';
  insert into _resultado values ('N1 fios da agenda: o número da OS como vem ("OS-9xxxxx — aberta", "Materiais da OS-9xxxxx a receber")',
    v_titulo = v_num || ' — aberta' and v_materiais = 'Materiais da ' || v_num || ' a receber' and v_ruins = 0,
    'titulo=' || coalesce(v_titulo, 'null') || ' materiais=' || coalesce(v_materiais, 'null') || ' com_os_repetido=' || v_ruins);
exception when others then
  insert into _resultado values ('N1 fios da agenda: o número da OS como vem ("OS-9xxxxx — aberta", "Materiais da OS-9xxxxx a receber")',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ N2 o aviso do sino quando o cliente confirma ═══════════════════════════════════════════
do $$
declare
  v_admin uuid := gen_random_uuid();
  v_fone text := '55479' || lpad((floor(random() * 100000000))::bigint::text, 8, '0');
  v_os uuid;
  v_num text;
  r jsonb;
  v_avisos integer;
  v_certos integer;
  v_corpo text;
begin
  -- um admin ativo de teste: o aviso do sino vai a todos os admins (no ensaio, só a ele)
  insert into public.app_users (id, full_name, email, role, active, created_at)
  values (v_admin, 'Admin de teste OS', 'teste-os-' || v_admin || '@teste.invalido', 'admin', true, now() - interval '30 years');
  v_os := pg_temp._os('scheduled', v_fone, now() + interval '1 day', now() - interval '1 hour');
  select service_order_number into v_num from public.service_orders where id = v_os;
  r := public.registrar_confirmacao_do_cliente(v_fone, 'sim', null);
  select count(*), count(*) filter (where body like v_num || ', %' and body not like 'OS OS-%' and body not like 'OS ORÇ-%'),
         min(body) filter (where user_id = v_admin)
    into v_avisos, v_certos, v_corpo
    from public.app_notifications
   where type = 'agendamento_confirmado' and navigate_to = '/v2/service-orders/' || v_os;
  insert into _resultado values ('N2 o "sim" do cliente confirma e o aviso do sino começa com o número como vem ("OS-9xxxxx, …")',
    coalesce((r->>'confirmou')::boolean, false) and r->>'os' = v_num and v_avisos >= 1 and v_certos = v_avisos
    and v_corpo like v_num || ', %',
    'confirmou=' || coalesce(r->>'confirmou', '-') || ' avisos=' || v_avisos || ' certos=' || v_certos
    || ' corpo=' || coalesce(left(v_corpo, 60), 'null'));
exception when others then
  insert into _resultado values ('N2 o "sim" do cliente confirma e o aviso do sino começa com o número como vem ("OS-9xxxxx, …")',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ N3 as portas ═══════════════════════════════════════════════════════════════════════════
do $$
declare
  v_f text := 'public.registrar_confirmacao_do_cliente(text, text, uuid)';
  v_opcoes text[];
begin
  select c.reloptions into v_opcoes from pg_class c where c.oid = 'public.erp_open_loop_facts'::regclass;
  insert into _resultado values ('N3 a view segue security_invoker e fechada ao anon; a confirmação só pelo sistema',
    (v_opcoes @> array['security_invoker=on'] or v_opcoes @> array['security_invoker=true'])
    and not has_table_privilege('anon', 'public.erp_open_loop_facts', 'select')
    and not has_function_privilege('anon', v_f, 'execute') and not has_function_privilege('authenticated', v_f, 'execute')
    and has_function_privilege('service_role', v_f, 'execute'),
    'opcoes=' || coalesce(array_to_string(v_opcoes, ','), 'null')
    || ' anon_select=' || has_table_privilege('anon', 'public.erp_open_loop_facts', 'select'));
exception when others then
  insert into _resultado values ('N3 a view segue security_invoker e fechada ao anon; a confirmação só pelo sistema',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
