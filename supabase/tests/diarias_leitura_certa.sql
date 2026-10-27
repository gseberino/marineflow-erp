-- Prova: a conta corrente das diárias lê certo o que já aconteceu
-- (migration 20261027120000_diarias_leitura_certa).
--
-- ═══ COMO RODAR ═══
--
--   supabase db query --linked -f supabase/tests/diarias_leitura_certa.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Cria um freelancer de teste com CPF fictício.
-- A tabela final tem de mostrar ok = true em todas as linhas.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_hoje date := public._hoje_brt();
  v_dono uuid;
  v_fav uuid;
  v_perfil uuid;
  v_conta uuid;
  v_cpf text := '999' || lpad((floor(random() * 100000000))::int::text, 8, '0');
  v_tx uuid;
  v_tx2 uuid;
  v_an uuid;
  v_dis text;
  c jsonb;
  v_n integer;
begin
  select id into v_dono from public.app_users where role = 'admin' and active order by created_at limit 1;
  insert into public.payees (name, kind, active, conta_corrente_desde, document)
  values ('Freelancer Leitura ' || substr(md5(random()::text), 1, 6), 'diarista', true, v_hoje - 20, v_cpf)
  returning id into v_fav;
  insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria, vigencia_inicio)
  values (v_fav, 'freelancer', 'diaria', 200, v_hoje - 20) returning id into v_perfil;
  insert into public.work_shifts (work_profile_id, data, tipo, fracao, valor_diaria)
  values (v_perfil, v_hoje - 15, 'diaria', 1, 200), (v_perfil, v_hoje - 14, 'diaria', 1, 200);
  insert into public.bank_connections (provider, external_id, label, account_kind)
  values ('manual', 'teste-leitura-' || gen_random_uuid(), 'Conta Teste Leitura', 'bank') returning id into v_conta;

  -- T01. Pagamento sem divisão não ganha "(inclui reembolso … R$ 0,00)".
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               payee_id, origin)
  values ('Pix diária teste', v_hoje - 13, v_hoje - 13, 100, 100, 0, 'paid', 'Diárias de freelancers', v_fav, 'bank_reconciliation');
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T01 sem sufixo de reembolso vazio',
    not exists (select 1 from jsonb_array_elements(c -> 'linhas') x where x ->> 'descricao' like '%inclui reembolso%')
      and (c ->> 'saldo_final')::numeric = 300,
    format('saldo=%s', c ->> 'saldo_final'));

  -- T02. Pix do banco para o CPF dele, sem lançamento: desconta, "No banco — falta aprovar na fila".
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, bank_connection_id,
                                        counterparty_document)
  values (v_hoje - 10, 'PIX ENVIADO TESTE LEITURA', 120, 'debit', 'bank', v_conta,
          substr(v_cpf, 1, 3) || '.' || substr(v_cpf, 4, 3) || '.' || substr(v_cpf, 7, 3) || '-' || substr(v_cpf, 10, 2))
  returning id into v_tx;
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T02 linha do banco pelo CPF desconta',
    (c ->> 'saldo_final')::numeric = 180 and (c ->> 'pago_falta_aprovar')::numeric = 120
      and (c ->> 'pago_aguardando_banco')::numeric = 0
      and (select count(*) from jsonb_array_elements(c -> 'linhas') x
            where x ->> 'conta' = 'No banco — falta aprovar na fila' and (x ->> 'aguardando')::boolean) = 1,
    format('saldo=%s falta_aprovar=%s', c ->> 'saldo_final', c ->> 'pago_falta_aprovar'));

  -- T03. Aprovada (virou lançamento): conta uma vez só, pela linha do lançamento.
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               payee_id, bank_transaction_id, origin)
  values ('Pix aprovado teste', v_hoje - 10, v_hoje - 10, 120, 120, 0, 'paid', 'Diárias de freelancers', v_fav, v_tx, 'bank_reconciliation');
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T03 aprovada conta uma vez',
    (c ->> 'saldo_final')::numeric = 180 and (c ->> 'pago_falta_aprovar')::numeric = 0,
    format('saldo=%s', c ->> 'saldo_final'));

  -- T04. Linha dispensada do extrato não conta; de outro CPF não entra.
  select dismissed_kind into v_dis from public.bank_transactions where dismissed_kind is not null limit 1;
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, bank_connection_id,
                                        counterparty_document, dismissed_kind)
  values (v_hoje - 9, 'PIX DISPENSADO TESTE', 70, 'debit', 'bank', v_conta, v_cpf, v_dis),
         (v_hoje - 9, 'PIX OUTRA PESSOA TESTE', 80, 'debit', 'bank', v_conta, '99800000000', null);
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T04 dispensada e outro CPF fora',
    (c ->> 'saldo_final')::numeric = 180, format('saldo=%s dispensa=%s', c ->> 'saldo_final', coalesce(v_dis, '(nenhuma no banco)')));

  -- T05. Anotação casada com linha ainda sem lançamento: uma linha só, "No banco — falta aprovar".
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, bank_connection_id,
                                        counterparty_document)
  values (v_hoje - 8, 'PIX ANOTADO TESTE', 50, 'debit', 'bank', v_conta, v_cpf) returning id into v_tx2;
  insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, data_exata, favorecido_id, categoria, descricao, status,
                                          bank_transaction_id, aplicada_em, criada_por)
  values ('debit', 50, v_hoje - 8, true, v_fav, 'Diárias de freelancers', 'Vale anotado', 'aplicada', v_tx2, now(), v_dono);
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T05 anotada e no banco conta uma vez',
    (c ->> 'saldo_final')::numeric = 130 and (c ->> 'pago_falta_aprovar')::numeric = 50
      and (c ->> 'pago_aguardando_banco')::numeric = 0,
    format('saldo=%s falta_aprovar=%s aguardando=%s', c ->> 'saldo_final', c ->> 'pago_falta_aprovar', c ->> 'pago_aguardando_banco'));

  -- T06. Anotação que nunca casou (nome/CPF diferentes) conta enquanto não há lançamento…
  insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, data_exata, favorecido_id, categoria, descricao, status, criada_por)
  values ('debit', 40, v_hoje - 6, true, v_fav, 'Diárias de freelancers', 'Vale solto 1', 'aguardando', v_dono),
         ('debit', 40, v_hoje - 6, true, v_fav, 'Diárias de freelancers', 'Vale solto 2', 'aguardando', v_dono);
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T06a soltas contam',
    (c ->> 'saldo_final')::numeric = 50 and (c ->> 'pago_aguardando_banco')::numeric = 80,
    format('saldo=%s aguardando=%s', c ->> 'saldo_final', c ->> 'pago_aguardando_banco'));
  -- … e quando o dono aprova a linha do banco (lançamento de mesmo valor, 1 dia depois), sai UMA delas.
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               payee_id, origin)
  values ('Pix aprovado na fila (sem CPF)', v_hoje - 5, v_hoje - 5, 40, 40, 0, 'paid', 'Diárias de freelancers', v_fav, 'bank_reconciliation');
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T06b lancamento cobre uma anotacao so',
    (c ->> 'saldo_final')::numeric = 50 and (c ->> 'pago_aguardando_banco')::numeric = 40,
    format('saldo=%s aguardando=%s', c ->> 'saldo_final', c ->> 'pago_aguardando_banco'));
  -- Lançamento de valor diferente ou longe na data não cobre nada.
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               payee_id, origin)
  values ('Pix outro valor', v_hoje - 6, v_hoje - 6, 45, 45, 0, 'paid', 'Diárias de freelancers', v_fav, 'bank_reconciliation'),
         ('Pix longe na data', v_hoje - 1, v_hoje - 1, 40, 40, 0, 'paid', 'Diárias de freelancers', v_fav, 'bank_reconciliation');
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T06c valor ou data diferente nao cobre',
    (c ->> 'saldo_final')::numeric = -35 and (c ->> 'pago_aguardando_banco')::numeric = 40,
    format('saldo=%s aguardando=%s', c ->> 'saldo_final', c ->> 'pago_aguardando_banco'));

  -- T07. O resumo traz a chave nova por pessoa.
  c := public.resumo_freelancers(null, null, v_dono);
  insert into _resultado values ('T07 resumo com falta_aprovar',
    exists (select 1 from jsonb_array_elements(c -> 'pessoas') x
             where (x ->> 'id')::uuid = v_fav and (x ->> 'pago_falta_aprovar')::numeric = 50),
    'pessoa de teste no resumo');

  -- T08. Permissões continuam as de antes (create or replace mantém).
  insert into _resultado values ('T08 permissoes',
    not has_function_privilege('anon', 'public.conta_corrente_freelancer(uuid, date, date, uuid, text)', 'execute')
      and not has_function_privilege('anon', 'public.resumo_freelancers(date, date, uuid, text)', 'execute')
      and not has_function_privilege('authenticated', 'public._conta_corrente_linhas(uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.conta_corrente_freelancer(uuid, date, date, uuid, text)', 'execute'),
    null);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
