-- Prova: "Cobrar juntas" cria a cobrança junto com o envio (migration 20270212100000_fechar_juntas_cobranca_junto).
--
--   C1  duas OS sem cobrança nenhuma (o caso da MP): cria uma cobrança por conta, ligada à conta, com o SALDO, o
--       vencimento da conta, o contato do cadastro, o modelo padrão e a régua desligada; registra o envio nas duas
--       (whatsapp_sent com a nota, 'sent', last_auto_sent_at)
--   C2  o mesmo envio de novo (lembrete do dia seguinte): não cria outra; registra nas mesmas
--   C3  conta que já tem cobrança aberta: não cria; registra na que existe
--   C4  OS com cobrança aberta SEM conta (a "Total" da aprovação): não cria para a conta dessa OS; registra nela
--   C5  conta paga (ou sem saldo) na lista: não cria cobrança para ela
--   C6  cobrança cancelada antiga não conta: cria a nova
--   C7  conta de OUTRO titular junto: recusa e NADA é gravado (nem a cobrança da conta certa) — tudo ou nada
--   C8  conta fora das OS escolhidas: recusa
--   C9  cadastro genérico: recusa
--   C10 sem login (sem auth.uid() e sem p_autor) e vendedor externo: recusa 42501
--   C11 o que o plano de inadimplência lê (collections.last_auto_sent_at por cliente) passa a ter o envio de hoje
--   R1  dado real: as 2 contas da MP MOTOR HOMES (OS-00045, OS-00046) ganham 2 cobranças (R$ 1.650 e R$ 20) — e
--       tudo volta no ROLLBACK
--   P1  privilégios: anon fora, logado e service role dentro, security definer com search_path vazio
--
-- ═══ COMO RODAR ═══ (DEPOIS da migration aplicada; a partir do repositório principal, que é o linkado)
--
--   npx supabase@2.111.0 db query --linked -f supabase/tests/fechar_juntas_cobranca_junto.sql --output json
--
-- Seguro em produção: usuários, clientes, barcos, OS e contas de teste criados aqui; nada é enviado (a função só
-- grava no banco). O R1 chama a função com as contas reais da MP dentro da transação. Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- ── helpers da transação (somem no rollback) ────────────────────────────────────────────────
create function pg_temp._letras(n integer) returns text language sql volatile as $$
  select translate(substr(md5(random()::text || clock_timestamp()::text), 1, n), '0123456789', 'ghijklmnop')
$$;

create function pg_temp._se(p_ok boolean, p_nome text) returns text language sql immutable as $$
  select case when coalesce(p_ok, false) then null else p_nome end
$$;

create function pg_temp._usuario(p_role text) returns uuid language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_id, 'Teste cobrar juntas (' || p_role || ')', 'teste-cobrar-juntas-' || v_id || '@teste.invalido', p_role, true);
  return v_id;
end $$;

create function pg_temp._cliente(p_generico boolean default false) returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.clients (type, name, generico, phone, whatsapp)
  values ('individual', 'Cliente Teste Cobrar Juntas ' || pg_temp._letras(6), p_generico, '(48) 3333-0000', '(48) 99999-0000')
  returning id into v_id;
  return v_id;
end $$;

create function pg_temp._numero_livre() returns text language plpgsql as $$
declare
  v_num integer := 900000 + floor(random() * 99000)::integer;
begin
  while exists (select 1 from public.service_orders where service_order_number = 'OS-' || v_num) loop
    v_num := v_num + 1;
  end loop;
  return 'OS-' || v_num;
end $$;

create function pg_temp._os(p_cli uuid, p_status text default 'invoiced') returns uuid language plpgsql as $$
declare
  v_ves uuid;
  v_os uuid;
begin
  insert into public.vessels (client_id, name) values (p_cli, 'Barco' || pg_temp._letras(8)) returning id into v_ves;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, converted_to_os_at, created_at)
  values (pg_temp._numero_livre(), p_cli, v_ves, p_status, 'approved', now(), clock_timestamp())
  returning id into v_os;
  return v_os;
end $$;

create function pg_temp._conta(p_cli uuid, p_os uuid, p_valor numeric, p_pago numeric default 0,
                               p_venc date default date '2026-07-22') returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, paid_amount,
                                  balance_amount, status)
  values (p_cli, p_os, 'Teste cobrar juntas: saldo', least(current_date, p_venc), p_venc, p_valor, p_pago, p_valor - p_pago,
          case when p_pago >= p_valor then 'paid' when p_pago > 0 then 'partially_paid' else 'pending' end)
  returning id into v_id;
  return v_id;
end $$;

create function pg_temp._erro_sql(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;

create function pg_temp._abertas(p_conta uuid) returns integer language sql stable as $$
  select count(*)::integer from public.collections k
   where k.receivable_id = p_conta and k.status in ('pending', 'sent', 'viewed', 'overdue', 'disputed')
$$;

-- ═══ C1–C6, C11 ══════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_adm uuid := pg_temp._usuario('admin');
  v_cli uuid := pg_temp._cliente();
  a uuid; b uuid; c uuid; d uuid;
  ca uuid; cb uuid; cc uuid; cd uuid; cpaga uuid; cvelha uuid;
  k_existente uuid; k_da_os uuid; k_cancelada uuid;
  r jsonb;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_falhas text;
  v_modelo text;
begin
  select t.send_method into v_modelo from public.collection_templates t order by t.is_default desc nulls last, t.name limit 1;

  -- C1 duas OS sem cobrança nenhuma (MP: 1.650 vencida + 20 de saldo de uma conta de 520 com 500 pagos)
  a := pg_temp._os(v_cli);
  b := pg_temp._os(v_cli);
  ca := pg_temp._conta(v_cli, a, 1650);
  cb := pg_temp._conta(v_cli, b, 520, 500);
  r := public.cobrar_juntas_registrar_envio(v_cli, array[ca, cb], array[a, b], 'Nota de teste', v_adm);
  v_falhas := concat_ws(', ',
    pg_temp._se((r ->> 'criadas')::int = 2 and (r ->> 'registradas')::int = 2, 'contagens ' || r::text),
    pg_temp._se(exists (select 1 from public.collections k where k.receivable_id = ca and k.service_order_id = a and k.client_id = v_cli
                         and k.amount = 1650 and k.due_date = date '2026-07-22' and k.status = 'sent'
                         and (k.last_auto_sent_at at time zone 'America/Sao_Paulo')::date = v_hoje
                         and k.auto_rule_enabled = false and k.contact_whatsapp = '(48) 99999-0000' and k.phone = '(48) 3333-0000'
                         and k.contact_name like 'Cliente Teste Cobrar Juntas %' and k.created_by = v_adm
                         and k.send_method = coalesce(v_modelo, 'text_link') and k.standalone_amount is null
                         and k.notes like 'Criada junto com o envio do "Cobrar juntas" em %'), 'cobrança da OS A'),
    pg_temp._se(exists (select 1 from public.collections k where k.receivable_id = cb and k.amount = 20 and k.status = 'sent'), 'cobrança da OS B com o SALDO (20)'),
    pg_temp._se((select count(*) from public.collection_contacts x join public.collections k on k.id = x.collection_id
                  where k.receivable_id in (ca, cb) and x.contact_type = 'whatsapp_sent' and x.notes = 'Nota de teste'
                    and x.created_by = v_adm) = 2, 'contato whatsapp_sent'));
  insert into _resultado values ('C1 duas OS sem cobrança: cria uma por conta (saldo, vencimento, contato) e registra o envio',
    v_falhas = '', case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas end);

  -- C2 de novo: não duplica
  r := public.cobrar_juntas_registrar_envio(v_cli, array[ca, cb], array[a, b], null, v_adm);
  insert into _resultado values ('C2 o mesmo envio de novo: nenhuma cobrança nova, registra nas mesmas',
    (r ->> 'criadas')::int = 0 and (r ->> 'registradas')::int = 2 and pg_temp._abertas(ca) = 1 and pg_temp._abertas(cb) = 1
    and (select count(*) from public.collection_contacts x join public.collections k on k.id = x.collection_id
          where k.receivable_id = ca and x.notes = 'Cobrar juntas (várias OS numa mensagem)') = 1,
    r::text);

  -- C3 conta que já tem cobrança aberta (criada pela tela, valor diferente): não cria; registra nela
  c := pg_temp._os(v_cli);
  cc := pg_temp._conta(v_cli, c, 800);
  insert into public.collections (service_order_id, receivable_id, client_id, amount, due_date, status)
  values (c, cc, v_cli, 750, current_date + 5, 'viewed') returning id into k_existente;
  r := public.cobrar_juntas_registrar_envio(v_cli, array[ca, cc], array[a, c], null, v_adm);
  insert into _resultado values ('C3 conta com cobrança aberta: não cria outra e registra na que existe',
    (r ->> 'criadas')::int = 0 and pg_temp._abertas(cc) = 1
    and exists (select 1 from public.collections k where k.id = k_existente and k.status = 'sent' and k.amount = 750
                 and k.last_auto_sent_at is not null),
    r::text);

  -- C4 OS com cobrança aberta SEM conta (a "Total" que generate-collections cria na aprovação)
  d := pg_temp._os(v_cli);
  cd := pg_temp._conta(v_cli, d, 300);
  insert into public.collections (service_order_id, receivable_id, client_id, amount, due_date, status, description)
  values (d, null, v_cli, 300, current_date, 'pending', 'Total') returning id into k_da_os;
  r := public.cobrar_juntas_registrar_envio(v_cli, array[ca, cd], array[a, d], null, v_adm);
  insert into _resultado values ('C4 OS com cobrança sem conta: não cria para a conta da OS e registra na da OS',
    (r ->> 'criadas')::int = 0 and pg_temp._abertas(cd) = 0
    and exists (select 1 from public.collections k where k.id = k_da_os and k.status = 'sent' and k.last_auto_sent_at is not null),
    r::text);

  -- C5 conta paga na lista: não cria
  cpaga := pg_temp._conta(v_cli, a, 100, 100);
  r := public.cobrar_juntas_registrar_envio(v_cli, array[ca, cpaga], array[a], null, v_adm);
  insert into _resultado values ('C5 conta paga na lista: nenhuma cobrança para ela',
    (r ->> 'criadas')::int = 0 and not exists (select 1 from public.collections k where k.receivable_id = cpaga),
    r::text);

  -- C6 cobrança cancelada antiga não conta: cria a nova
  cvelha := pg_temp._conta(v_cli, b, 90);
  insert into public.collections (service_order_id, receivable_id, client_id, amount, due_date, status)
  values (b, cvelha, v_cli, 90, current_date, 'cancelled') returning id into k_cancelada;
  r := public.cobrar_juntas_registrar_envio(v_cli, array[cb, cvelha], array[b], null, v_adm);
  insert into _resultado values ('C6 só cobrança cancelada: cria a nova e deixa a cancelada como estava',
    (r ->> 'criadas')::int = 1 and pg_temp._abertas(cvelha) = 1
    and exists (select 1 from public.collections k where k.id = k_cancelada and k.status = 'cancelled' and k.last_auto_sent_at is null),
    r::text);

  -- C11 o plano de inadimplência lê last_auto_sent_at por cliente (financial.ts, get_delinquency_plan)
  insert into _resultado values ('C11 o plano de inadimplência passa a ver o envio de hoje deste cliente',
    exists (select 1 from public.collections k where k.client_id = v_cli and k.last_auto_sent_at is not null
             and (k.last_auto_sent_at at time zone 'America/Sao_Paulo')::date = v_hoje),
    'ok');
exception when others then
  insert into _resultado values ('C1–C6 cria e registra', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ C7–C10 recusas ════════════════════════════════════════════════════════════════════════
do $$
declare
  v_adm uuid := pg_temp._usuario('admin');
  v_ext uuid := pg_temp._usuario('external_seller');
  v_cli uuid := pg_temp._cliente();
  v_outro uuid := pg_temp._cliente();
  v_gen uuid := pg_temp._cliente(true);
  a uuid; b uuid; g uuid;
  ca uuid; cb uuid; cg uuid; c_fora uuid;
  e text;
begin
  a := pg_temp._os(v_cli);
  b := pg_temp._os(v_cli);
  ca := pg_temp._conta(v_cli, a, 400);
  -- a conta da OS B em nome de OUTRO cadastro (o pagador)
  cb := pg_temp._conta(v_outro, b, 250);

  -- C7 tudo ou nada: a recusa não deixa nem a cobrança da conta certa
  e := pg_temp._erro_sql(format('select public.cobrar_juntas_registrar_envio(%L::uuid, array[%L, %L]::uuid[], array[%L, %L]::uuid[], null, %L::uuid)',
                                v_cli, ca, cb, a, b, v_adm));
  insert into _resultado values ('C7 conta de outro titular: recusa e nada é gravado (nem a da conta certa)',
    e like '22023 Estas contas não são deste cliente ou de uma das OS escolhidas: %'
    and not exists (select 1 from public.collections k where k.receivable_id in (ca, cb)),
    coalesce(e, 'GRAVOU'));

  -- C8 conta fora das OS escolhidas
  c_fora := pg_temp._conta(v_cli, b, 70);
  e := pg_temp._erro_sql(format('select public.cobrar_juntas_registrar_envio(%L::uuid, array[%L, %L]::uuid[], array[%L]::uuid[], null, %L::uuid)',
                                v_cli, ca, c_fora, a, v_adm));
  insert into _resultado values ('C8 conta de OS que não foi escolhida: recusa',
    e like '22023 Estas contas não são deste cliente %' and not exists (select 1 from public.collections k where k.receivable_id in (ca, c_fora)),
    coalesce(e, 'GRAVOU'));

  -- C9 genérico
  g := pg_temp._os(v_gen);
  cg := pg_temp._conta(v_gen, g, 100);
  e := pg_temp._erro_sql(format('select public.cobrar_juntas_registrar_envio(%L::uuid, array[%L]::uuid[], array[%L]::uuid[], null, %L::uuid)',
                                v_gen, cg, g, v_adm));
  insert into _resultado values ('C9 cadastro genérico: recusa',
    e like '22023 O cadastro % é genérico, sem CPF/CNPJ: não entra em cobrança conjunta.'
    and not exists (select 1 from public.collections k where k.receivable_id = cg),
    coalesce(e, 'GRAVOU'));

  -- C10 sem login e vendedor externo
  e := pg_temp._erro_sql(format('select public.cobrar_juntas_registrar_envio(%L::uuid, array[%L]::uuid[], array[%L]::uuid[], null, null)',
                                v_cli, ca, a));
  insert into _resultado values ('C10a sem login: recusa 42501', e = '42501 Faça login para registrar a cobrança.', coalesce(e, 'GRAVOU'));
  e := pg_temp._erro_sql(format('select public.cobrar_juntas_registrar_envio(%L::uuid, array[%L]::uuid[], array[%L]::uuid[], null, %L::uuid)',
                                v_cli, ca, a, v_ext));
  insert into _resultado values ('C10b vendedor externo: recusa 42501',
    e = '42501 Seu cargo não mexe em cobranças.' and not exists (select 1 from public.collections k where k.receivable_id = ca),
    coalesce(e, 'GRAVOU'));
exception when others then
  insert into _resultado values ('C7–C10 recusas', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ R1 dado real: MP MOTOR HOMES ═══════════════════════════════════════════════════════════
do $$
declare
  v_adm uuid := pg_temp._usuario('admin');
  v_cli uuid;
  v_contas uuid[];
  v_os uuid[];
  v_antes integer;
  r jsonb;
begin
  select c.id into v_cli from public.clients c where c.name = 'MP MOTOR HOMES' limit 1;
  select array_agg(x.id order by so.service_order_number), array_agg(distinct x.service_order_id)
    into v_contas, v_os
    from public.receivables x join public.service_orders so on so.id = x.service_order_id
   where x.client_id = v_cli and so.service_order_number in ('OS-00045', 'OS-00046')
     and x.status not in ('paid', 'cancelled');
  select count(*) into v_antes from public.collections k where k.receivable_id = any(v_contas);
  r := public.cobrar_juntas_registrar_envio(v_cli, v_contas, v_os, 'Ensaio (rollback)', v_adm);
  insert into _resultado values ('R1 dado real: a MP (OS-00045 + OS-00046) ganha 2 cobranças, R$ 1.650 e R$ 20 (volta no rollback)',
    cardinality(v_contas) = 2 and v_antes = 0 and (r ->> 'criadas')::int = 2
    and (select array_agg(k.amount order by k.amount) from public.collections k where k.receivable_id = any(v_contas)) = array[20.00, 1650.00]::numeric[],
    format('contas %s, antes %s, %s', cardinality(v_contas), v_antes, r));
exception when others then
  insert into _resultado values ('R1 dado real: MP', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ P privilégios ═══════════════════════════════════════════════════════════════════════════
do $$
declare
  v_f constant text := 'public.cobrar_juntas_registrar_envio(uuid, uuid[], uuid[], text, uuid)';
  v_falhas text;
begin
  v_falhas := concat_ws(', ',
    pg_temp._se(not has_function_privilege('anon', v_f, 'execute'), 'anon executa'),
    pg_temp._se(has_function_privilege('authenticated', v_f, 'execute'), 'logado sem acesso'),
    pg_temp._se(has_function_privilege('service_role', v_f, 'execute'), 'service role sem acesso'),
    pg_temp._se((select p.prosecdef and p.proconfig @> array['search_path=""'] from pg_proc p where p.oid = v_f::regprocedure),
                'security definer + search_path'));
  insert into _resultado values ('P1 privilégios: anon fora, logado e service role dentro, search_path vazio',
    v_falhas = '', case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas end);
exception when others then
  insert into _resultado values ('P1 privilégios', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
