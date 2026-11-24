-- Prova: as duas tabelas do retrato do cartão existem, só o servidor grava (das faturas, administrador e financeiro leem
-- cinco colunas desde 20270227100000), e regravar uma fatura não perde a data em que ela apareceu (migration
-- 20270225100000_posicao_do_cartao).
--
-- ═══ COMO RODAR ═══
--
--   npx supabase@2.111.0 db query --linked -f <caminho completo>/supabase/tests/posicao_do_cartao.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Grava linhas de teste só dentro da transação (códigos com sufixo aleatório),
-- ligadas a uma conexão bancária que já existe. A tabela final tem de mostrar ok = true em todas as linhas.
--
-- ANTES de a migration estar aplicada: rodar o ensaio (a migration + este corpo na mesma transação).
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ctx on commit drop as
  select (select id from public.bank_connections order by created_at limit 1) as conexao,
         'teste-' || substr(md5(random()::text), 1, 10) as sufixo;

-- C1. As tabelas existem, com RLS ligada e sem policy (fechadas a tudo que não é o servidor) ------------------------
-- Desde 20270227100000 as faturas têm UMA policy, só de leitura (administrador e financeiro leem cinco colunas para a
-- previsão de caixa da tela; a prova dela é tela_le_calendario_do_cartao.sql). Qualquer outra policy reprova aqui.
insert into _resultado
select 'C1 tabelas com RLS ligada e sem policy (fora a de leitura das faturas pela tela)',
       (select count(*) = 2 from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname in ('cartao_posicoes', 'cartao_faturas_do_banco') and c.relkind = 'r' and c.relrowsecurity)
   and (select count(*) = 0 from pg_policies where schemaname = 'public' and tablename in ('cartao_posicoes', 'cartao_faturas_do_banco')
           and not (tablename = 'cartao_faturas_do_banco' and cmd = 'SELECT' and roles = '{authenticated}'::name[])),
       (select string_agg(c.relname || ':' || c.relrowsecurity, ', ') from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname in ('cartao_posicoes', 'cartao_faturas_do_banco'));

-- C2. anon e authenticated não têm NENHUM privilégio, de tabela nem de coluna; service_role lê e grava ---------------
-- Única exceção (20270227100000): authenticated lê cinco colunas das faturas, para a previsão de caixa da tela.
insert into _resultado
select 'C2 ' || t || ': anon e authenticated sem privilégio (fora a leitura de cinco colunas das faturas), service_role com',
       not exists (
         select 1 from unnest(array['anon', 'authenticated']) papel, unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) priv
          where has_table_privilege(papel, 'public.' || t, priv))
   and not exists (
         select 1 from pg_attribute a, unnest(array['anon', 'authenticated']) papel, unnest(array['select', 'insert', 'update', 'references']) priv
          where a.attrelid = ('public.' || t)::regclass and a.attnum > 0 and not a.attisdropped
            and has_column_privilege(papel, 'public.' || t, a.attname, priv)
            and not (t = 'cartao_faturas_do_banco' and papel = 'authenticated' and priv = 'select'
                     and a.attname in ('bill_id', 'bank_connection_id', 'fechamento', 'vencimento', 'total')))
   and has_table_privilege('service_role', 'public.' || t, 'select')
   and has_table_privilege('service_role', 'public.' || t, 'insert')
   and has_table_privilege('service_role', 'public.' || t, 'update'),
       (select string_agg(papel || ':' || priv, ', ') from unnest(array['anon', 'authenticated']) papel,
               unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) priv
         where has_table_privilege(papel, 'public.' || t, priv))
  from unnest(array['cartao_posicoes', 'cartao_faturas_do_banco']) t;

-- C3. Como usuário comum (authenticated) a leitura é recusada, não devolve vazio calado ------------------------------
do $$
declare v_ok boolean := false; v_msg text := 'leu sem erro';
begin
  begin
    set local role authenticated;
    perform count(*) from public.cartao_posicoes;
  exception when insufficient_privilege then
    v_ok := true; v_msg := 'permission denied';
  end;
  reset role;
  insert into _resultado values ('C3 authenticated não lê cartao_posicoes', v_ok, v_msg);
end $$;

-- C4. O retrato: uma linha por sincronização, e a mais nova de cada conta sai pelo índice --------------------------
insert into public.cartao_posicoes (bank_connection_id, provider_account_id, nome, final, saldo_informado, vencimento, minimo, limite,
                                    limite_disponivel, situacao, dados, faturas_lidas, faturas_vistas, provedor_atualizado_em, lido_em)
select conexao, sufixo, 'Cartão de teste', '0000', 100.00, date '2026-12-21', 15.00, 1000.00, 900.00, 'ACTIVE',
       '{"balanceDueDate":"2026-12-21"}'::jsonb, 2,
       '[{"bill_id":"a","vencimento":"2026-11-21","total":500,"pago":0,"pagamentos":0},{"bill_id":"b","vencimento":"2026-12-21","total":100,"pago":null,"pagamentos":null}]'::jsonb,
       now() - interval '20 hours', now() - interval '9 hours'
  from _ctx;
insert into public.cartao_posicoes (bank_connection_id, provider_account_id, saldo_informado, vencimento, faturas_erro)
select conexao, sufixo, 60.50, date '2026-12-21', 'Pluggy /bills respondeu 404' from _ctx;

insert into _resultado
select 'C4 duas sincronizações = duas linhas; a mais nova é a segunda',
       (select count(*) = 2 from public.cartao_posicoes p, _ctx where p.provider_account_id = _ctx.sufixo)
   and (select p.saldo_informado = 60.50 and p.faturas_lidas is null and p.faturas_erro is not null
          from public.cartao_posicoes p, _ctx where p.provider_account_id = _ctx.sufixo order by p.lido_em desc limit 1),
       (select string_agg(p.saldo_informado::text, ' → ' order by p.lido_em) from public.cartao_posicoes p, _ctx where p.provider_account_id = _ctx.sufixo);

-- C4b. A série das faturas fica no retrato (a tabela das faturas só tem o último estado) e a idade do dado também ----
insert into _resultado
select 'C4b o retrato guarda o estado das faturas da leitura e a hora do provedor; sem lista, os dois ficam nulos',
       (select jsonb_array_length(p.faturas_vistas) = 2 and (p.faturas_vistas -> 0 ->> 'total')::numeric = 500
               and p.faturas_vistas -> 1 -> 'pago' = 'null'::jsonb and p.provedor_atualizado_em < p.lido_em
          from public.cartao_posicoes p, _ctx where p.provider_account_id = _ctx.sufixo order by p.lido_em limit 1)
   and (select p.faturas_vistas is null and p.provedor_atualizado_em is null
          from public.cartao_posicoes p, _ctx where p.provider_account_id = _ctx.sufixo order by p.lido_em desc limit 1),
       (select string_agg(coalesce(jsonb_array_length(p.faturas_vistas)::text, 'nulo'), ' → ' order by p.lido_em)
          from public.cartao_posicoes p, _ctx where p.provider_account_id = _ctx.sufixo);

-- C5. A fatura: regravar pelo código atualiza total e pagamentos e NÃO muda o "visto_em" --------------------------
insert into public.cartao_faturas_do_banco (bill_id, bank_connection_id, provider_account_id, vencimento, total, minimo, pago, encargos, dados, visto_em, lido_em)
select 'fatura-' || sufixo, conexao, sufixo, date '2026-11-21', 500.00, 75.00, 0, 0, '{"id":"x"}'::jsonb,
       now() - interval '3 days', now() - interval '3 days'
  from _ctx;
-- o mesmo que o upsert da sincronização faz: todas as colunas que ela manda, menos visto_em
insert into public.cartao_faturas_do_banco (bill_id, bank_connection_id, provider_account_id, vencimento, total, minimo, pago, encargos, dados, lido_em)
select 'fatura-' || sufixo, conexao, sufixo, date '2026-11-21', 512.30, 75.00, 300.00, 12.30, '{"id":"x","payments":[{"amount":300}]}'::jsonb, now()
  from _ctx
on conflict (bill_id) do update
   set bank_connection_id = excluded.bank_connection_id, provider_account_id = excluded.provider_account_id,
       vencimento = excluded.vencimento, total = excluded.total, minimo = excluded.minimo, pago = excluded.pago,
       encargos = excluded.encargos, dados = excluded.dados, lido_em = excluded.lido_em;

insert into _resultado
select 'C5 regravar a fatura: uma linha, total e pago novos, visto_em de antes',
       (select count(*) = 1 from public.cartao_faturas_do_banco f, _ctx where f.provider_account_id = _ctx.sufixo)
   and f.total = 512.30 and f.pago = 300.00 and f.encargos = 12.30
   and f.visto_em < now() - interval '2 days' and f.lido_em > now() - interval '1 minute',
       format('total %s pago %s visto %s lido %s', f.total, f.pago, f.visto_em::date, f.lido_em::date)
  from public.cartao_faturas_do_banco f, _ctx where f.bill_id = 'fatura-' || _ctx.sufixo;

-- C6. Sem conexão bancária de verdade não grava (não sobra retrato de cartão que não existe) ------------------------
do $$
declare v_ok boolean := false; v_msg text := 'gravou sem conexão';
begin
  begin
    insert into public.cartao_posicoes (bank_connection_id, provider_account_id) values (gen_random_uuid(), 'sem-conexao');
  exception when foreign_key_violation then
    v_ok := true; v_msg := 'recusado pela chave estrangeira';
  end;
  insert into _resultado values ('C6 retrato exige conexão bancária existente', v_ok, v_msg);
end $$;

-- C7. Valor e data que o banco não mandou ficam nulos (a coluna aceita; ninguém vira zero) --------------------------
insert into public.cartao_faturas_do_banco (bill_id, bank_connection_id, provider_account_id)
select 'vazia-' || sufixo, conexao, sufixo from _ctx;
insert into _resultado
select 'C7 fatura só com código: valores e datas nulos',
       f.total is null and f.pago is null and f.vencimento is null and f.minimo is null and f.visto_em is not null,
       format('total %s pago %s venc %s', f.total, f.pago, f.vencimento)
  from public.cartao_faturas_do_banco f, _ctx where f.bill_id = 'vazia-' || _ctx.sufixo;

select teste, ok, detalhe from _resultado order by teste;

rollback;
