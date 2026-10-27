-- Prova: só o que é diária abate a conta do freelancer (migration 20261027150000_diarias_so_categoria_diarias).
--
-- ═══ COMO RODAR ═══
--
--   supabase db query --linked -f supabase/tests/diarias_so_categoria_diarias.sql --output json
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
  c jsonb;
begin
  select id into v_dono from public.app_users where role = 'admin' and active order by created_at limit 1;
  insert into public.payees (name, kind, active, conta_corrente_desde, document)
  values ('Freelancer Categoria ' || substr(md5(random()::text), 1, 6), 'diarista', true, v_hoje - 20, v_cpf)
  returning id into v_fav;
  insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria, vigencia_inicio)
  values (v_fav, 'freelancer', 'diaria', 200, v_hoje - 20) returning id into v_perfil;
  insert into public.work_shifts (work_profile_id, data, tipo, fracao, valor_diaria)
  values (v_perfil, v_hoje - 15, 'diaria', 1, 200), (v_perfil, v_hoje - 14, 'diaria', 1, 200);
  insert into public.bank_connections (provider, external_id, label, account_kind)
  values ('manual', 'teste-categoria-' || gen_random_uuid(), 'Conta Teste Categoria', 'bank') returning id into v_conta;

  -- T01. Diária e sem categoria abatem; alimentação e peças não.
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               payee_id, origin)
  values ('Pix diária', v_hoje - 13, v_hoje - 13, 100, 100, 0, 'paid', 'Diárias de freelancers', v_fav, 'bank_reconciliation'),
         ('Pix sem categoria', v_hoje - 12, v_hoje - 12, 30, 30, 0, 'paid', null, v_fav, 'bank_reconciliation'),
         ('Pix almoço', v_hoje - 12, v_hoje - 12, 63, 63, 0, 'paid', 'Alimentação de campo', v_fav, 'bank_reconciliation'),
         ('Pix peças', v_hoje - 11, v_hoje - 11, 70, 70, 0, 'paid', 'Peças e materiais', v_fav, 'bank_reconciliation');
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T01 so diaria e sem categoria abatem',
    (c ->> 'saldo_final')::numeric = 270 and (c ->> 'pago')::numeric = 130
      and not exists (select 1 from jsonb_array_elements(c -> 'linhas') x where x ->> 'categoria' in ('Alimentação de campo', 'Peças e materiais')),
    format('saldo=%s pago=%s', c ->> 'saldo_final', c ->> 'pago'));

  -- T02. Anotação de outra categoria não abate; de diária, sim.
  insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, data_exata, favorecido_id, categoria, descricao, status, criada_por)
  values ('debit', 40, v_hoje - 6, true, v_fav, 'Alimentação de campo', 'Lanche', 'aguardando', v_dono),
         ('debit', 50, v_hoje - 6, true, v_fav, 'Diárias de freelancers', 'Vale', 'aguardando', v_dono);
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T02 anotacao de outra categoria nao abate',
    (c ->> 'saldo_final')::numeric = 220 and (c ->> 'pago_aguardando_banco')::numeric = 50,
    format('saldo=%s aguardando=%s', c ->> 'saldo_final', c ->> 'pago_aguardando_banco'));

  -- T03. Lançamento de outra categoria não "cobre" anotação solta de diária do mesmo valor.
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               payee_id, origin)
  values ('Pix 50 peças', v_hoje - 5, v_hoje - 5, 50, 50, 0, 'paid', 'Peças e materiais', v_fav, 'bank_reconciliation');
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T03 outra categoria nao cobre anotacao',
    (c ->> 'saldo_final')::numeric = 220 and (c ->> 'pago_aguardando_banco')::numeric = 50,
    format('saldo=%s aguardando=%s', c ->> 'saldo_final', c ->> 'pago_aguardando_banco'));

  -- T04. Pix do banco pelo CPF, ainda sem categoria, continua descontando.
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, bank_connection_id,
                                        counterparty_document)
  values (v_hoje - 4, 'PIX TESTE CATEGORIA', 20, 'debit', 'bank', v_conta, v_cpf);
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T04 fila sem categoria desconta',
    (c ->> 'saldo_final')::numeric = 200 and (c ->> 'pago_falta_aprovar')::numeric = 20,
    format('saldo=%s falta_aprovar=%s', c ->> 'saldo_final', c ->> 'pago_falta_aprovar'));

  -- T05. A função auxiliar não fica aberta a quem chega pela API.
  insert into _resultado values ('T05 permissoes',
    not has_function_privilege('anon', 'public._abate_diarias(text)', 'execute')
      and not has_function_privilege('authenticated', 'public._abate_diarias(text)', 'execute')
      and public._abate_diarias(null) and public._abate_diarias('Diárias de freelancers')
      and not public._abate_diarias('Comissões'),
    null);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
