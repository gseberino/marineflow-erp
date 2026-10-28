-- Prova: anotação à mão e Pix do banco pelo CPF contam uma vez só
-- (migration 20261028150000_diarias_anotacao_e_banco_pelo_cpf).
--
--   supabase db query --linked -f supabase/tests/diarias_anotacao_e_banco_pelo_cpf.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Cria um freelancer de teste com CPF fictício.
-- O caso real: o João tinha Pix anotados e o banco trazia os mesmos para um CPF que faltava no cadastro.
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
  v_an uuid;
  c jsonb;
begin
  select id into v_dono from public.app_users where role = 'admin' and active order by created_at limit 1;
  insert into public.payees (name, kind, active, conta_corrente_desde)
  values ('Freelancer CPF ' || substr(md5(random()::text), 1, 6), 'diarista', true, v_hoje - 20)
  returning id into v_fav;
  insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria, vigencia_inicio)
  values (v_fav, 'freelancer', 'diaria', 200, v_hoje - 20) returning id into v_perfil;
  insert into public.work_shifts (work_profile_id, data, tipo, fracao, valor_diaria)
  values (v_perfil, v_hoje - 15, 'diaria', 1, 200), (v_perfil, v_hoje - 14, 'diaria', 1, 200);
  insert into public.bank_connections (provider, external_id, label, account_kind)
  values ('manual', 'teste-cpf-' || gen_random_uuid(), 'Conta Teste CPF', 'bank') returning id into v_conta;

  -- P1. Sem CPF no cadastro: a anotação conta e o Pix do banco (para o CPF que falta) não entra.
  insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, data_exata, favorecido_id, categoria, descricao, status, criada_por)
  values ('debit', 100, v_hoje - 5, true, v_fav, 'Diárias de freelancers', 'Pagamento anotado', 'aguardando', v_dono)
  returning id into v_an;
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, bank_connection_id,
                                        counterparty_document)
  values (v_hoje - 5, 'PIX ENVIADO TESTE CPF', 100, 'debit', 'bank', v_conta, v_cpf) returning id into v_tx;
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('P1 sem CPF conta a anotacao',
    (c ->> 'saldo_final')::numeric = 300 and (c ->> 'pago_aguardando_banco')::numeric = 100,
    format('saldo=%s aguardando=%s', c ->> 'saldo_final', c ->> 'pago_aguardando_banco'));

  -- P2. Com o CPF preenchido, o mesmo Pix conta UMA vez — pela anotação, que passa a dizer "No banco".
  update public.payees set document = v_cpf where id = v_fav;
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('P2 com CPF conta uma vez',
    (c ->> 'saldo_final')::numeric = 300 and (c ->> 'pago_falta_aprovar')::numeric = 100
      and (c ->> 'pago_aguardando_banco')::numeric = 0,
    format('saldo=%s falta_aprovar=%s aguardando=%s', c ->> 'saldo_final', c ->> 'pago_falta_aprovar', c ->> 'pago_aguardando_banco'));

  -- P3. Pix do banco sem anotação parecida continua descontando.
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, bank_connection_id,
                                        counterparty_document)
  values (v_hoje - 4, 'PIX SEM ANOTACAO', 30, 'debit', 'bank', v_conta, v_cpf);
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('P3 pix sem anotacao desconta',
    (c ->> 'saldo_final')::numeric = 270, format('saldo=%s', c ->> 'saldo_final'));

  -- P4. Um para um: duas anotações de 50 e um Pix de 50 — uma casa, a outra segue aguardando.
  insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, data_exata, favorecido_id, categoria, descricao, status, criada_por)
  values ('debit', 50, v_hoje - 3, true, v_fav, 'Diárias de freelancers', 'Vale 1', 'aguardando', v_dono),
         ('debit', 50, v_hoje - 3, true, v_fav, 'Diárias de freelancers', 'Vale 2', 'aguardando', v_dono);
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, bank_connection_id,
                                        counterparty_document)
  values (v_hoje - 3, 'PIX VALE', 50, 'debit', 'bank', v_conta, v_cpf);
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('P4 um para um',
    (c ->> 'saldo_final')::numeric = 170 and (c ->> 'pago_aguardando_banco')::numeric = 50,
    format('saldo=%s aguardando=%s', c ->> 'saldo_final', c ->> 'pago_aguardando_banco'));

  -- P5. Longe na data (mais de 3 dias) não casa: os dois contam.
  insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, data_exata, favorecido_id, categoria, descricao, status, criada_por)
  values ('debit', 80, v_hoje - 1, true, v_fav, 'Diárias de freelancers', 'Vale longe', 'aguardando', v_dono);
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, bank_connection_id,
                                        counterparty_document)
  values (v_hoje - 12, 'PIX LONGE', 80, 'debit', 'bank', v_conta, v_cpf);
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('P5 longe na data nao casa',
    (c ->> 'saldo_final')::numeric = 10, format('saldo=%s', c ->> 'saldo_final'));

  -- P6. Quando o motor liga a anotação à linha, nada muda.
  update public.anotacoes_do_extrato set status = 'aplicada', bank_transaction_id = v_tx, aplicada_em = now() where id = v_an;
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('P6 ligada pelo motor igual',
    (c ->> 'saldo_final')::numeric = 10, format('saldo=%s', c ->> 'saldo_final'));
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
