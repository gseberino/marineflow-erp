-- Prova das respostas do dono de 20/11/2026 sobre o "Enviar extrato" e as cobranças:
--   migrations 20270212110000_extrato_conta_como_cobranca e 20270212120000_cobrancas_so_admin_financeiro
--   (depois da 20270212100000_fechar_juntas_cobranca_junto).
--
--   A1  extrato SEM saldo (comprovante de quitação) não é cobrança: a tela nem chama a função; e se só contas pagas
--       chegassem nela, nada se cria nem se registra
--   B1  extrato COM saldo (p_os nulo = o cliente inteiro): cria a cobrança da conta de OS sem nenhuma e da conta
--       avulsa (sem OS), não cria para a conta cuja OS tem a "Total" sem conta, e registra o envio nas três
--       (whatsapp_sent com a nota do extrato, 'sent', last_auto_sent_at de hoje); a nota da criada diz "Enviar extrato"
--   B2  o que a regra "1 por dia" lê passa a ver o extrato: o plano de inadimplência (último last_auto_sent_at das
--       cobranças do cliente = hoje) e o lote (cada cobrança das contas com last_auto_sent_at de hoje)
--   B3  o mesmo extrato de novo: nenhuma cobrança nova
--   B4  conta de outro titular no extrato: recusa e nada é gravado (tudo ou nada)
--   B5  cadastro genérico no extrato: recusa ("não entra em cobrança.")
--   B6  o Cobrar juntas segue igual (p_os preenchido): conta fora das OS escolhidas continua recusada
--   C1  a função: técnico e vendedor recusados (42501); financeiro passa
--   C2  RLS de collections como TÉCNICO logado: lê, mas não cria (42501), não altera nem apaga (0 linhas)
--   C3  RLS como FINANCEIRO e ADMINISTRADOR logados: criam, alteram e apagam
--   C4  anon: sem privilégio nenhum na tabela (42501); as 4 policies são TO authenticated
--
-- ═══ COMO RODAR ═══ (DEPOIS das migrations aplicadas; a partir do repositório principal, que é o linkado)
--
--   npx supabase@2.111.0 db query --linked -f supabase/tests/extrato_cobranca_e_rls_cobrancas.sql --output json
--
-- Ensaio ANTES de aplicar: um arquivo "begin; <as 3 migrations> <este corpo sem o begin> rollback;".
-- Seguro em produção: usuários, clientes, barcos, OS e contas de teste criados aqui; nada é enviado. ROLLBACK no fim.
-- A tabela final tem de mostrar ok = true em todas as linhas.
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
  values (v_id, 'Teste extrato (' || p_role || ')', 'teste-extrato-' || v_id || '@teste.invalido', p_role, true);
  return v_id;
end $$;

create function pg_temp._cliente(p_generico boolean default false) returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.clients (type, name, generico, phone, whatsapp)
  values ('individual', 'Cliente Teste Extrato ' || pg_temp._letras(6), p_generico, '(48) 3333-0000', '(48) 99999-0000')
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

create function pg_temp._os(p_cli uuid) returns uuid language plpgsql as $$
declare
  v_ves uuid;
  v_os uuid;
begin
  insert into public.vessels (client_id, name) values (p_cli, 'Barco' || pg_temp._letras(8)) returning id into v_ves;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, converted_to_os_at, created_at)
  values (pg_temp._numero_livre(), p_cli, v_ves, 'invoiced', 'approved', now(), clock_timestamp())
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
  values (p_cli, p_os, 'Teste extrato: conta', least(current_date, p_venc), p_venc, p_valor, p_pago, p_valor - p_pago,
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

-- Uma consulta como um papel (e um login): o texto que volta ou "erro <sqlstate>: <mensagem>".
create function pg_temp._como(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_papel)::text
         else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- ═══ A1, B1–B3 ══════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_fin uuid := pg_temp._usuario('financial');
  v_cli uuid := pg_temp._cliente();
  a uuid; b uuid;
  ca uuid; cb uuid; cavulsa uuid; cpaga uuid;
  k_total uuid;
  r jsonb;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_falhas text;
begin
  a := pg_temp._os(v_cli);
  b := pg_temp._os(v_cli);
  ca := pg_temp._conta(v_cli, a, 1650);                -- OS sem cobrança nenhuma
  cb := pg_temp._conta(v_cli, b, 300);                 -- OS com a "Total" sem conta
  cavulsa := pg_temp._conta(v_cli, null, 80);          -- conta avulsa, sem OS
  cpaga := pg_temp._conta(v_cli, a, 500, 500);         -- o sinal pago
  insert into public.collections (service_order_id, receivable_id, client_id, amount, due_date, status, description)
  values (b, null, v_cli, 300, current_date, 'pending', 'Total') returning id into k_total;

  -- A1 só contas pagas: nada se cria nem se registra (a tela nem chama a função no comprovante de quitação)
  r := public.cobrar_juntas_registrar_envio(v_cli, array[cpaga], null, null, v_fin);
  insert into _resultado values ('A1 extrato sem saldo (quitação): nenhuma cobrança criada nem registrada',
    (r ->> 'criadas')::int = 0 and (r ->> 'registradas')::int = 0
    and not exists (select 1 from public.collections k where k.client_id = v_cli and k.last_auto_sent_at is not null),
    r::text);

  -- B1 extrato com saldo: p_os nulo
  r := public.cobrar_juntas_registrar_envio(v_cli, array[ca, cb, cavulsa], null, null, v_fin);
  v_falhas := concat_ws(', ',
    pg_temp._se((r ->> 'criadas')::int = 2 and (r ->> 'registradas')::int = 3, 'contagens ' || r::text),
    pg_temp._se(exists (select 1 from public.collections k where k.receivable_id = ca and k.service_order_id = a
                         and k.amount = 1650 and k.status = 'sent' and k.created_by = v_fin
                         and k.notes like 'Criada junto com o envio do "Enviar extrato" em %'), 'cobrança da conta da OS A'),
    pg_temp._se(exists (select 1 from public.collections k where k.receivable_id = cavulsa and k.service_order_id is null
                         and k.amount = 80 and k.status = 'sent'), 'cobrança da conta avulsa'),
    pg_temp._se(not exists (select 1 from public.collections k where k.receivable_id = cb), 'criou para a conta da OS com Total'),
    pg_temp._se(exists (select 1 from public.collections k where k.id = k_total and k.status = 'sent'
                         and (k.last_auto_sent_at at time zone 'America/Sao_Paulo')::date = v_hoje), 'registro na Total da OS B'),
    pg_temp._se((select count(*) from public.collection_contacts x join public.collections k on k.id = x.collection_id
                  where k.client_id = v_cli and x.contact_type = 'whatsapp_sent'
                    and x.notes = 'Extrato do cliente com saldo (Enviar extrato)' and x.created_by = v_fin) = 3, 'contatos whatsapp_sent'));
  insert into _resultado values ('B1 extrato com saldo: cria a da conta de OS e a da avulsa, respeita a Total da OS e registra nas três',
    v_falhas = '', case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas end);

  -- B2 a regra "1 por dia": plano de inadimplência (por cliente) e lote (por cobrança)
  insert into _resultado values ('B2 o plano de inadimplência e o lote veem o extrato como a cobrança de hoje',
    (select (max(k.last_auto_sent_at) at time zone 'America/Sao_Paulo')::date from public.collections k
      where k.client_id = v_cli and k.last_auto_sent_at is not null) = v_hoje
    and not exists (select 1 from public.collections k
                     where (k.receivable_id in (ca, cb, cavulsa) or k.id = k_total)
                       and k.status <> 'cancelled'
                       and (k.last_auto_sent_at is null or (k.last_auto_sent_at at time zone 'America/Sao_Paulo')::date <> v_hoje)),
    'ok');

  -- B3 de novo: não duplica
  r := public.cobrar_juntas_registrar_envio(v_cli, array[ca, cb, cavulsa], null, null, v_fin);
  insert into _resultado values ('B3 o mesmo extrato de novo: nenhuma cobrança nova',
    (r ->> 'criadas')::int = 0 and (r ->> 'registradas')::int = 3
    and (select count(*) from public.collections k where k.client_id = v_cli) = 3,
    r::text);
exception when others then
  insert into _resultado values ('A1/B1–B3 extrato', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ B4–B6, C1 recusas da função ═════════════════════════════════════════════════════════════
do $$
declare
  v_adm uuid := pg_temp._usuario('admin');
  v_fin uuid := pg_temp._usuario('financial');
  v_tec uuid := pg_temp._usuario('technician');
  v_ven uuid := pg_temp._usuario('seller');
  v_cli uuid := pg_temp._cliente();
  v_outro uuid := pg_temp._cliente();
  v_gen uuid := pg_temp._cliente(true);
  a uuid; b uuid; g uuid;
  ca uuid; c_outro uuid; cg uuid; cb uuid;
  e text;
  r jsonb;
begin
  a := pg_temp._os(v_cli);
  b := pg_temp._os(v_cli);
  ca := pg_temp._conta(v_cli, a, 400);
  cb := pg_temp._conta(v_cli, b, 70);
  c_outro := pg_temp._conta(v_outro, a, 250);  -- conta da OS do cliente, em nome de OUTRO cadastro

  -- B4 tudo ou nada no extrato
  e := pg_temp._erro_sql(format('select public.cobrar_juntas_registrar_envio(%L::uuid, array[%L, %L]::uuid[], null, null, %L::uuid)',
                                v_cli, ca, c_outro, v_adm));
  insert into _resultado values ('B4 extrato com conta de outro titular: recusa e nada é gravado',
    e like '22023 Estas contas não são deste cliente: %'
    and not exists (select 1 from public.collections k where k.receivable_id in (ca, c_outro)),
    coalesce(e, 'GRAVOU'));

  -- B5 genérico no extrato
  g := pg_temp._os(v_gen);
  cg := pg_temp._conta(v_gen, g, 100);
  e := pg_temp._erro_sql(format('select public.cobrar_juntas_registrar_envio(%L::uuid, array[%L]::uuid[], null, null, %L::uuid)',
                                v_gen, cg, v_adm));
  insert into _resultado values ('B5 extrato de cadastro genérico: recusa',
    e like '22023 O cadastro % é genérico, sem CPF/CNPJ: não entra em cobrança.'
    and not exists (select 1 from public.collections k where k.receivable_id = cg),
    coalesce(e, 'GRAVOU'));

  -- B6 o Cobrar juntas (p_os preenchido) continua exigindo as OS escolhidas
  e := pg_temp._erro_sql(format('select public.cobrar_juntas_registrar_envio(%L::uuid, array[%L, %L]::uuid[], array[%L]::uuid[], null, %L::uuid)',
                                v_cli, ca, cb, a, v_adm));
  insert into _resultado values ('B6 Cobrar juntas: conta de OS que não foi escolhida continua recusada',
    e like '22023 Estas contas não são deste cliente ou de uma das OS escolhidas: %', coalesce(e, 'GRAVOU'));

  -- C1 a função: técnico e vendedor fora; financeiro dentro
  e := pg_temp._erro_sql(format('select public.cobrar_juntas_registrar_envio(%L::uuid, array[%L]::uuid[], null, null, %L::uuid)',
                                v_cli, ca, v_tec));
  insert into _resultado values ('C1a técnico chama a função: recusa 42501, nada gravado',
    e = '42501 Seu cargo não mexe em cobranças.' and not exists (select 1 from public.collections k where k.receivable_id = ca),
    coalesce(e, 'GRAVOU'));
  e := pg_temp._erro_sql(format('select public.cobrar_juntas_registrar_envio(%L::uuid, array[%L]::uuid[], null, null, %L::uuid)',
                                v_cli, ca, v_ven));
  insert into _resultado values ('C1b vendedor chama a função: recusa 42501', e = '42501 Seu cargo não mexe em cobranças.', coalesce(e, 'GRAVOU'));
  -- o técnico logado (auth.uid() dele, sem p_autor), como a tela chamaria
  e := pg_temp._como(v_tec, 'authenticated',
         format('select public.cobrar_juntas_registrar_envio(%L::uuid, array[%L]::uuid[], null, null, null)::text', v_cli, ca));
  insert into _resultado values ('C1c técnico LOGADO chama a RPC: recusa 42501',
    e = 'erro 42501: Seu cargo não mexe em cobranças.', coalesce(e, 'GRAVOU'));
  r := public.cobrar_juntas_registrar_envio(v_cli, array[ca], null, null, v_fin);
  insert into _resultado values ('C1d financeiro chama a função: cria e registra',
    (r ->> 'criadas')::int = 1 and (r ->> 'registradas')::int = 1, r::text);
exception when others then
  insert into _resultado values ('B4–B6/C1 recusas', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ C2–C4 RLS de collections, com o papel e o login de cada um ═════════════════════════════
do $$
declare
  v_adm uuid := pg_temp._usuario('admin');
  v_fin uuid := pg_temp._usuario('financial');
  v_tec uuid := pg_temp._usuario('technician');
  v_cli uuid := pg_temp._cliente();
  v_os uuid := pg_temp._os(v_cli);
  k uuid;
  v_ins text;
  e1 text; e2 text; e3 text; e4 text;
begin
  insert into public.collections (service_order_id, client_id, amount, due_date, status, description)
  values (v_os, v_cli, 500, current_date, 'pending', 'Teste RLS') returning id into k;
  v_ins := format($q$insert into public.collections (service_order_id, client_id, amount, due_date, status, description)
                    values (%L, %L, 10, current_date, 'pending', 'Criada na tela') returning 'criou'$q$, v_os, v_cli);

  -- C2 técnico
  e1 := pg_temp._como(v_tec, 'authenticated', format('select count(*)::text from public.collections where id = %L', k));
  e2 := pg_temp._como(v_tec, 'authenticated', v_ins);
  e3 := pg_temp._como(v_tec, 'authenticated',
          format($q$with x as (update public.collections set status = 'paid' where id = %L returning 1) select count(*)::text from x$q$, k));
  e4 := pg_temp._como(v_tec, 'authenticated',
          format($q$with x as (delete from public.collections where id = %L returning 1) select count(*)::text from x$q$, k));
  insert into _resultado values ('C2 técnico logado: lê, mas não cria (42501), não altera nem apaga (0 linhas)',
    e1 = '1' and e2 like 'erro 42501: new row violates row-level security policy%' and e3 = '0' and e4 = '0'
    and exists (select 1 from public.collections c where c.id = k and c.status = 'pending'),
    concat_ws(' | ', e1, e2, e3, e4));

  -- C3 financeiro e administrador
  e1 := pg_temp._como(v_fin, 'authenticated', v_ins);
  e2 := pg_temp._como(v_fin, 'authenticated',
          format($q$with x as (update public.collections set status = 'sent' where id = %L returning 1) select count(*)::text from x$q$, k));
  e3 := pg_temp._como(v_adm, 'authenticated', v_ins);
  e4 := pg_temp._como(v_adm, 'authenticated',
          format($q$with x as (delete from public.collections where id = %L returning 1) select count(*)::text from x$q$, k));
  insert into _resultado values ('C3 financeiro e administrador logados: criam, alteram e apagam',
    e1 = 'criou' and e2 = '1' and e3 = 'criou' and e4 = '1',
    concat_ws(' | ', e1, e2, e3, e4));

  -- C4 anon
  e1 := pg_temp._como(null, 'anon', 'select count(*)::text from public.collections');
  e2 := pg_temp._como(null, 'anon', v_ins);
  insert into _resultado values ('C4 anon: sem privilégio (42501) para ler nem criar; as 4 policies são TO authenticated',
    e1 like 'erro 42501:%' and e2 like 'erro 42501:%'
    and (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = 'collections') = 4
    and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'collections'
                     and p.roles <> array['authenticated']::name[]),
    concat_ws(' | ', e1, e2));
exception when others then
  insert into _resultado values ('C2–C4 RLS', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
