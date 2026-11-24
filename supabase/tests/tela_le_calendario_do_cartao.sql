-- Prova: a tela lê o calendário das faturas do cartão — só administrador e financeiro, só cinco colunas, e ninguém além
-- do servidor grava (migration 20270227100000_tela_le_calendario_do_cartao).
--
-- ═══ COMO RODAR ═══
--
--   npx supabase@2.111.0 db query --linked -f <caminho completo>/supabase/tests/tela_le_calendario_do_cartao.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Grava uma fatura de teste só dentro da transação (código com sufixo
-- aleatório), ligada a uma conexão bancária que já existe. A tabela final tem de mostrar ok = true em todas as linhas.
--
-- ANTES de a migration estar aplicada: rodar o ensaio (a migration + este corpo na mesma transação).
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
grant all on _resultado to authenticated, anon;
create temp table _ctx on commit drop as
  select (select id from public.bank_connections order by created_at limit 1) as conexao,
         'teste-' || substr(md5(random()::text), 1, 10) as sufixo,
         (select id from public.app_users where role in ('admin', 'financial') and active order by created_at limit 1) as financeiro,
         (select id from public.app_users where role not in ('admin', 'financial') and active order by created_at limit 1) as outro;
grant select on _ctx to authenticated, anon;

insert into public.cartao_faturas_do_banco (bill_id, bank_connection_id, provider_account_id, vencimento, fechamento, total, minimo, pago, dados)
select 'fatura-' || sufixo, conexao, sufixo, date '2026-11-25', date '2026-11-19', 1320.61, 198.09, 0, '{"id":"cru"}'::jsonb from _ctx;

-- T1. Uma policy só, de leitura, para authenticated; cartao_posicoes continua sem nenhuma ---------------------------
insert into _resultado
select 'T1 uma policy de SELECT para authenticated nas faturas; nenhuma no retrato',
       (select count(*) = 1 and bool_and(cmd = 'SELECT' and roles = '{authenticated}'::name[] and qual like '%is_admin_or_financial%')
          from pg_policies where schemaname = 'public' and tablename = 'cartao_faturas_do_banco')
   and (select count(*) = 0 from pg_policies where schemaname = 'public' and tablename = 'cartao_posicoes'),
       (select string_agg(tablename || ':' || policyname || ':' || cmd || ':' || roles::text, ' | ')
          from pg_policies where schemaname = 'public' and tablename in ('cartao_faturas_do_banco', 'cartao_posicoes'));

-- T2. authenticated lê exatamente as cinco colunas; as outras e a tabela inteira, não -------------------------------
insert into _resultado
select 'T2 authenticated: SELECT só nas cinco colunas',
       (select bool_and(has_column_privilege('authenticated', 'public.cartao_faturas_do_banco', a.attname, 'select')
                        = (a.attname in ('bill_id', 'bank_connection_id', 'fechamento', 'vencimento', 'total')))
          from pg_attribute a
         where a.attrelid = 'public.cartao_faturas_do_banco'::regclass and a.attnum > 0 and not a.attisdropped)
   and not has_table_privilege('authenticated', 'public.cartao_faturas_do_banco', 'select'),
       (select string_agg(a.attname, ', ' order by a.attnum) from pg_attribute a
         where a.attrelid = 'public.cartao_faturas_do_banco'::regclass and a.attnum > 0 and not a.attisdropped
           and has_column_privilege('authenticated', 'public.cartao_faturas_do_banco', a.attname, 'select'));

-- T3. authenticated não grava (nem na tabela, nem em coluna); anon não tem nada -------------------------------------
insert into _resultado
select 'T3 authenticated não grava; anon sem nenhum privilégio (tabela e colunas)',
       not exists (
         select 1 from unnest(array['insert', 'update', 'delete', 'truncate', 'references', 'trigger']) priv
          where has_table_privilege('authenticated', 'public.cartao_faturas_do_banco', priv))
   and not exists (
         select 1 from pg_attribute a, unnest(array['insert', 'update', 'references']) priv
          where a.attrelid = 'public.cartao_faturas_do_banco'::regclass and a.attnum > 0 and not a.attisdropped
            and has_column_privilege('authenticated', 'public.cartao_faturas_do_banco', a.attname, priv))
   and not exists (
         select 1 from unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) priv
          where has_table_privilege('anon', 'public.cartao_faturas_do_banco', priv))
   and not exists (
         select 1 from pg_attribute a, unnest(array['select', 'insert', 'update', 'references']) priv
          where a.attrelid = 'public.cartao_faturas_do_banco'::regclass and a.attnum > 0 and not a.attisdropped
            and has_column_privilege('anon', 'public.cartao_faturas_do_banco', a.attname, priv)),
       'privilégios conferidos um a um';

-- T4. O retrato (cartao_posicoes) segue fechado: anon e authenticated sem nada -------------------------------------
insert into _resultado
select 'T4 cartao_posicoes: anon e authenticated sem privilégio',
       not exists (
         select 1 from unnest(array['anon', 'authenticated']) papel, unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) priv
          where has_table_privilege(papel, 'public.cartao_posicoes', priv))
   and not exists (
         select 1 from pg_attribute a, unnest(array['anon', 'authenticated']) papel, unnest(array['select', 'insert', 'update', 'references']) priv
          where a.attrelid = 'public.cartao_posicoes'::regclass and a.attnum > 0 and not a.attisdropped
            and has_column_privilege(papel, 'public.cartao_posicoes', a.attname, priv)),
       'privilégios conferidos um a um';

-- T5. Administrador ou financeiro, pela tela: lê a fatura, com as cinco colunas --------------------------------------
do $t5$
declare v_quem uuid := (select financeiro from _ctx); v_n int; v_total numeric; v_msg text;
begin
  if v_quem is null then
    insert into _resultado values ('T5 administrador/financeiro lê as cinco colunas', true, 'PULADO: sem administrador nem financeiro ativo');
    return;
  end if;
  begin
    perform set_config('request.jwt.claim.sub', v_quem::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_quem, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(*), max(f.total) into v_n, v_total
      from (select bill_id, bank_connection_id, fechamento, vencimento, total from public.cartao_faturas_do_banco) f, _ctx
     where f.bill_id = 'fatura-' || _ctx.sufixo and f.fechamento = date '2026-11-19' and f.vencimento = date '2026-11-25'
       and f.bank_connection_id = _ctx.conexao;
    reset role;
  exception when others then
    v_msg := sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('T5 administrador/financeiro lê as cinco colunas', v_msg is null and v_n = 1 and v_total = 1320.61,
    coalesce(v_msg, format('linhas %s total %s', v_n, v_total)));
end
$t5$;

-- T6. O mesmo usuário NÃO lê o conteúdo cru do banco, nem a tabela inteira (erro, nunca nulo calado) -----------------
do $t6$
declare v_quem uuid := (select financeiro from _ctx); v_cru boolean := false; v_tudo boolean := false; v_msg text := '';
begin
  if v_quem is null then
    insert into _resultado values ('T6 conteúdo cru e "todas as colunas" recusados para a tela', true, 'PULADO: sem administrador nem financeiro ativo');
    return;
  end if;
  perform set_config('request.jwt.claim.sub', v_quem::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_quem, 'role', 'authenticated')::text, true);
  begin
    set local role authenticated;
    perform dados from public.cartao_faturas_do_banco limit 1;
    v_msg := v_msg || 'leu dados; ';
  exception when insufficient_privilege then v_cru := true;
  end;
  reset role;
  begin
    set local role authenticated;
    perform * from public.cartao_faturas_do_banco limit 1;
    v_msg := v_msg || 'leu todas as colunas; ';
  exception when insufficient_privilege then v_tudo := true;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('T6 conteúdo cru e "todas as colunas" recusados para a tela', v_cru and v_tudo, coalesce(nullif(v_msg, ''), 'permission denied nos dois'));
end
$t6$;

-- T7. Quem não é administrador nem financeiro (e quem está sem login) não vê fatura nenhuma --------------------------
do $t7$
-- Sem usuário ativo de outro cargo para testar, vale um login que não está em app_users: a regra responde igual (não é
-- administrador nem financeiro ativo).
declare v_quem uuid := coalesce((select outro from _ctx), gen_random_uuid()); v_n_outro int; v_n_sem_login int; v_msg text;
begin
  begin
    perform set_config('request.jwt.claim.sub', v_quem::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_quem, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(*) into v_n_outro from (select bill_id from public.cartao_faturas_do_banco) f;
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    set local role authenticated;
    select count(*) into v_n_sem_login from (select bill_id from public.cartao_faturas_do_banco) f;
    reset role;
  exception when others then
    v_msg := sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('T7 outro cargo e sem login: zero faturas', v_msg is null and v_n_outro = 0 and v_n_sem_login = 0,
    coalesce(v_msg, format('outro cargo %s, sem login %s', v_n_outro, v_n_sem_login)));
end
$t7$;

-- T8. anon: a leitura é recusada, não devolve vazio calado ---------------------------------------------------------
do $t8$
declare v_ok boolean := false; v_msg text := 'leu sem erro';
begin
  begin
    set local role anon;
    perform bill_id from public.cartao_faturas_do_banco limit 1;
  exception when insufficient_privilege then
    v_ok := true; v_msg := 'permission denied';
  end;
  reset role;
  insert into _resultado values ('T8 anon não lê as faturas', v_ok, v_msg);
end
$t8$;

-- T9. Administrador/financeiro pela tela não grava nem apaga ------------------------------------------------------
do $t9$
declare v_quem uuid := (select financeiro from _ctx); v_upd boolean := false; v_del boolean := false; v_ins boolean := false;
begin
  if v_quem is null then
    insert into _resultado values ('T9 pela tela ninguém grava', true, 'PULADO: sem administrador nem financeiro ativo');
    return;
  end if;
  perform set_config('request.jwt.claim.sub', v_quem::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_quem, 'role', 'authenticated')::text, true);
  begin
    set local role authenticated;
    update public.cartao_faturas_do_banco set total = 0 where bill_id = (select 'fatura-' || sufixo from _ctx);
  exception when insufficient_privilege then v_upd := true;
  end;
  reset role;
  begin
    set local role authenticated;
    delete from public.cartao_faturas_do_banco where bill_id = (select 'fatura-' || sufixo from _ctx);
  exception when insufficient_privilege then v_del := true;
  end;
  reset role;
  begin
    set local role authenticated;
    insert into public.cartao_faturas_do_banco (bill_id, bank_connection_id, provider_account_id)
    select 'intrusa-' || sufixo, conexao, sufixo from _ctx;
  exception when insufficient_privilege then v_ins := true;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('T9 pela tela ninguém grava', v_upd and v_del and v_ins,
    format('update recusado %s, delete recusado %s, insert recusado %s', v_upd, v_del, v_ins));
end
$t9$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
