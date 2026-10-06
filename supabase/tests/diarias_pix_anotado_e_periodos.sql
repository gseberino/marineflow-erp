-- Prova: Pix anotado aparece na conta corrente e desconta até virar lançamento (e nunca em dobro);
-- atalhos de período por pessoa ("em aberto", "desde o último pagamento", 15 dias, semana)
-- (migration 20261006200000_diarias_pix_anotado_e_periodos).
--
-- ═══ COMO RODAR ═══
--
--   supabase db query --linked -f supabase/tests/diarias_pix_anotado_e_periodos.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Cria um freelancer de teste com sufixo aleatório.
-- A tabela final tem de mostrar ok = true em todas as linhas.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_dono uuid;
  v_hoje date := public._hoje_brt();
  v_fav uuid;
  r jsonb;
  c jsonb;
  v_tx_livre uuid;
  v_tx_lancada uuid;
  v_an uuid;
  v_n integer;
begin
  select id into v_dono from public.app_users where role = 'admin' and active order by created_at limit 1;
  r := public.cadastrar_freelancer('Teste Período ' || lpad((floor(random() * 1000000))::int::text, 6, '0'),
                                   150, v_hoje - 10, null, null, null, null, null, false, v_dono);
  v_fav := (r ->> 'favorecido_id')::uuid;

  -- Dias: d-10 e d-9 inteiros (150 cada), d-5 inteiro. Pagamentos ANOTADOS: 300 em d-9, 50 em d-5.
  perform public.registrar_diaria(v_fav, v_hoje - 10, 'inteiro', null, null, null, null, null, 'painel', v_dono);
  perform public.registrar_diaria(v_fav, v_hoje - 9, 'inteiro', null, null, null, null, null, 'painel', v_dono);
  perform public.registrar_diaria(v_fav, v_hoje - 5, 'inteiro', null, null, null, null, null, 'painel', v_dono);
  insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, data_exata, favorecido_id, categoria, descricao, status, criada_por)
  values ('debit', 300, v_hoje - 9, true, v_fav, 'Diárias de freelancers', 'Pix acerto', 'aguardando', v_dono),
         ('debit', 50, v_hoje - 5, true, v_fav, 'Diárias de freelancers', 'Adiantamento', 'aguardando', v_dono);

  -- T1. A anotação aparece como pagamento "aguardando o banco" e desconta.
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T01 anotado aparece e desconta',
    (c ->> 'pago')::numeric = 350 and (c ->> 'saldo_final')::numeric = 100
      and (c ->> 'pago_aguardando_banco')::numeric = 350
      and (select count(*) from jsonb_array_elements(c -> 'linhas') x
            where x ->> 'tipo' = 'pagamento' and (x ->> 'aguardando')::boolean
              and x ->> 'conta' = 'Anotado — aguardando o banco') = 2,
    format('pago=%s saldo=%s', c ->> 'pago', c ->> 'saldo_final'));

  -- T2. Cancelada não conta.
  update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now() where favorecido_id = v_fav and valor = 50;
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T02 cancelada nao conta', (c ->> 'saldo_final')::numeric = 150, c ->> 'saldo_final');
  update public.anotacoes_do_extrato set status = 'aguardando', cancelada_em = null where favorecido_id = v_fav and valor = 50;

  -- T3. Casada com uma linha do banco SEM lançamento: continua contando; casada com linha que JÁ
  --     virou lançamento: sai (o lançamento é que conta) — nunca os dois.
  select t.id into v_tx_livre from public.bank_transactions t
   where t.transaction_type = 'debit'
     and not exists (select 1 from public.payables p where p.bank_transaction_id = t.id and p.status <> 'cancelled')
     and not exists (select 1 from public.finance_review_queue q where q.bank_transaction_id = t.id and q.status = 'rejected')
   limit 1;
  select p.bank_transaction_id into v_tx_lancada from public.payables p
   where p.bank_transaction_id is not null and p.status <> 'cancelled' limit 1;
  select id into v_an from public.anotacoes_do_extrato where favorecido_id = v_fav and valor = 300;
  update public.anotacoes_do_extrato set status = 'aplicada', bank_transaction_id = v_tx_livre, aplicada_em = now() where id = v_an;
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T03a casada sem lancamento conta', (c ->> 'pago')::numeric = 350, c ->> 'pago');
  update public.anotacoes_do_extrato set bank_transaction_id = v_tx_lancada where id = v_an;
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T03b casada com lancamento sai', (c ->> 'pago')::numeric = 50, c ->> 'pago');
  update public.anotacoes_do_extrato set status = 'aguardando', bank_transaction_id = null, aplicada_em = null where id = v_an;

  -- T4. Em aberto: o saldo zerou no Pix de 300 em d-9 → começa em d-8; antes do período, saldo 0.
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono, 'em_aberto');
  insert into _resultado values ('T04 em aberto',
    (c ->> 'de')::date = v_hoje - 8 and (c ->> 'saldo_anterior')::numeric = 0
      and jsonb_array_length(c -> 'linhas') = 2 and (c ->> 'saldo_final')::numeric = 100,
    format('de=%s anterior=%s linhas=%s', c ->> 'de', c ->> 'saldo_anterior', jsonb_array_length(c -> 'linhas')));

  -- T5. Desde o último pagamento (50 em d-5) → começa em d-4; o saldo anterior já o desconta.
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono, 'desde_ultimo_pagamento');
  insert into _resultado values ('T05 desde ultimo pagamento',
    (c ->> 'de')::date = v_hoje - 4 and (c ->> 'saldo_anterior')::numeric = 100 and jsonb_array_length(c -> 'linhas') = 0,
    format('de=%s anterior=%s', c ->> 'de', c ->> 'saldo_anterior'));

  -- T6. 15 dias e semana atual: até hoje; a semana começa na segunda.
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono, 'ultimos_15_dias');
  r := public.conta_corrente_freelancer(v_fav, null, null, v_dono, 'semana_atual');
  insert into _resultado values ('T06 15 dias e semana',
    (c ->> 'ate')::date = v_hoje and (r ->> 'ate')::date = v_hoje
      and extract(isodow from (r ->> 'de')::date) = 1 and (r ->> 'de')::date > v_hoje - 7,
    format('15d de=%s · semana de=%s', c ->> 'de', r ->> 'de'));

  -- T7. Atalho manda sobre De/Até; De/Até sozinhos continuam como antes.
  c := public.conta_corrente_freelancer(v_fav, v_hoje - 10, v_hoje - 9, v_dono);
  insert into _resultado values ('T07 de/ate livres',
    (c ->> 'trabalhado')::numeric = 300 and (c ->> 'pago')::numeric = 300 and (c ->> 'saldo_final')::numeric = 0,
    format('trab=%s pago=%s', c ->> 'trabalhado', c ->> 'pago'));

  -- T8. Resumo com atalho: cada pessoa com o período dela.
  r := public.resumo_freelancers(null, null, v_dono, 'em_aberto');
  insert into _resultado values ('T08 resumo por pessoa',
    exists (select 1 from jsonb_array_elements(r -> 'pessoas') x
             where (x ->> 'id')::uuid = v_fav and (x ->> 'de')::date = v_hoje - 8
               and (x ->> 'pago_aguardando_banco')::numeric = 50),
    'em aberto do freelancer de teste');

  -- T9. Atalho desconhecido é recusado.
  begin
    perform public.conta_corrente_freelancer(v_fav, null, null, v_dono, 'quinzena');
    insert into _resultado values ('T09 atalho invalido', false, 'aceitou');
  exception when others then
    insert into _resultado values ('T09 atalho invalido', sqlerrm like 'Período desconhecido%', sqlerrm);
  end;

  -- T10. Quem pode: anon não; assinatura velha não existe mais (sem ambiguidade de chamada).
  select count(*) into v_n from pg_proc where proname = 'conta_corrente_freelancer' and pronamespace = 'public'::regnamespace;
  insert into _resultado values ('T10 permissoes',
    v_n = 1
      and not has_function_privilege('anon', 'public.conta_corrente_freelancer(uuid, date, date, uuid, text)', 'execute')
      and not has_function_privilege('anon', 'public.resumo_freelancers(date, date, uuid, text)', 'execute')
      and not has_function_privilege('authenticated', 'public._periodo_do_atalho(uuid, text)', 'execute')
      and not has_function_privilege('authenticated', 'public._conta_corrente_linhas(uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.conta_corrente_freelancer(uuid, date, date, uuid, text)', 'execute'),
    format('%s versão(ões)', v_n));
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
