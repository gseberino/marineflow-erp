-- Prova: o boleto lido no e-mail vira conta a pagar (migration 20270221100000_contas_a_pagar_do_email).
--
-- ═══ COMO RODAR ═══
--
--   npx supabase@2.111.0 db query --linked -f supabase/tests/contas_a_pagar_do_email.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Cria um fornecedor, e-mails, contas e uma saída de banco de teste só
-- dentro da transação (valores com centavos improváveis). A tabela final tem de mostrar ok = true em todas as linhas.
--
-- ANTES de a migration estar aplicada: rodar o ensaio (a migration + este corpo na mesma transação), como está em
-- D:/IA-HBR/Trabalho/o-que-vence/ensaio.sh.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_hoje  date := public._hoje_brt();
  v_conta uuid;
  v_forn  uuid;
  v_cnpj  text := '99' || lpad((floor(random() * 1000000000000))::bigint::text, 12, '0');
  v_cat   text;
  v_e1 uuid; v_e2 uuid; v_e3 uuid; v_e4 uuid; v_e5 uuid; v_e6 uuid; v_e7 uuid;
  v_p  uuid;
  v_tx uuid;
  v_bc uuid;
  r    jsonb;
  n    int;
  -- linhas de teste: 47 dígitos, prefixo 999 (banco que não existe)
  l1 text := '999' || lpad((floor(random() * 1e15))::bigint::text, 44, '1');
  l2 text := '999' || lpad((floor(random() * 1e15))::bigint::text, 44, '2');
  l3 text := '999' || lpad((floor(random() * 1e15))::bigint::text, 44, '3');
  l4 text := '999' || lpad((floor(random() * 1e15))::bigint::text, 44, '4');
  l5 text := '999' || lpad((floor(random() * 1e15))::bigint::text, 44, '5');
  l6 text := '999' || lpad((floor(random() * 1e15))::bigint::text, 44, '6');
  l7 text := '999' || lpad((floor(random() * 1e15))::bigint::text, 44, '7');
begin
  select id into v_conta from public.email_accounts order by created_at limit 1;
  select name into v_cat from public.financial_categories where type = 'payable' and active order by name limit 1;
  insert into public.suppliers (name, cnpj_cpf) values ('FORNECEDOR DE TESTE DO BOLETO', v_cnpj) returning id into v_forn;
  -- histórico do fornecedor: dá a categoria
  insert into public.payables (supplier_id, supplier_name, expense_category, description, issue_date, due_date, amount, status, paid_amount, balance_amount, origin)
  values (v_forn, 'FORNECEDOR DE TESTE DO BOLETO', v_cat, 'histórico de teste', v_hoje - 200, v_hoje - 200, 11.11, 'paid', 11.11, 0, 'manual');

  -- T1: sem fornecedor, vence em 10 dias → cria, sem fornecedor, com o nome do remetente
  insert into public.email_messages (account_id, dedup_key, from_name, from_address, subject, received_at, has_attachments, dados_extraidos)
  values (v_conta, 'teste-boleto-1-' || l1, 'Boletos TESTE', 'boleto@teste.invalid', 'Seu boleto de teste', now(), true,
          jsonb_build_object('nfes', '[]'::jsonb, 'boletos', jsonb_build_array(
            jsonb_build_object('linha', l1, 'valor', 4321.07, 'vencimento', to_char(v_hoje + 10, 'YYYY-MM-DD'), 'origem', 'pdf'))))
  returning id into v_e1;
  r := public.contas_a_pagar_do_email(v_e1, v_hoje);
  select count(*) into n from public.payables
   where boleto_linha = l1 and status = 'pending' and origin = 'boleto' and supplier_id is null and supplier_name = 'Boletos TESTE'
     and amount = 4321.07 and balance_amount = 4321.07 and due_date = v_hoje + 10 and email_message_id = v_e1 and expense_category is null;
  insert into _resultado values ('T1 boleto sem fornecedor vira conta a pagar', (r ->> 'criadas')::int = 1 and n = 1, r::text);

  -- T2: o mesmo boleto em outro e-mail (lembrete) → nada novo
  insert into public.email_messages (account_id, dedup_key, from_name, from_address, subject, received_at, has_attachments, dados_extraidos)
  values (v_conta, 'teste-boleto-2-' || l1, 'Boletos TESTE', 'boleto@teste.invalid', 'Lembrete: seu boleto vence', now(), true,
          jsonb_build_object('boletos', jsonb_build_array(
            jsonb_build_object('linha', l1, 'valor', 4321.07, 'vencimento', to_char(v_hoje + 10, 'YYYY-MM-DD'), 'origem', 'texto'))))
  returning id into v_e2;
  r := public.contas_a_pagar_do_email(v_e2, v_hoje);
  select count(*) into n from public.payables where boleto_linha = l1;
  insert into _resultado values ('T2 o lembrete do mesmo boleto não duplica', (r ->> 'ja_existiam')::int = 1 and (r ->> 'criadas')::int = 0 and n = 1, r::text);

  -- T3: cancelada pelo dono → o próximo lembrete NÃO recria
  update public.payables set status = 'cancelled' where boleto_linha = l1;
  r := public.contas_a_pagar_do_email(v_e2, v_hoje);
  select count(*) into n from public.payables where boleto_linha = l1;
  insert into _resultado values ('T3 conta cancelada não renasce', (r ->> 'ja_existiam')::int = 1 and n = 1, r::text);

  -- T4: e-mail com NF-e do fornecedor (CNPJ) e parcela da nota já lançada → LIGA a linha, não cria
  insert into public.payables (supplier_id, supplier_name, description, issue_date, due_date, amount, status, paid_amount, balance_amount, origin)
  values (v_forn, 'FORNECEDOR DE TESTE DO BOLETO', 'NF-e de teste (parcela 1/2)', v_hoje - 5, v_hoje + 20, 987.63, 'pending', 0, 987.63, 'manual')
  returning id into v_p;
  insert into public.email_messages (account_id, dedup_key, from_name, from_address, subject, received_at, has_attachments, dados_extraidos)
  values (v_conta, 'teste-boleto-4-' || l2, 'NF-e TESTE', 'nfe@teste.invalid', 'Nota e boleto de teste', now(), true,
          jsonb_build_object(
            'nfes', jsonb_build_array(jsonb_build_object('chave', repeat('9', 44), 'emitente_cnpj', v_cnpj, 'para_empresa', true)),
            'boletos', jsonb_build_array(
              jsonb_build_object('linha', l2, 'valor', 987.63, 'vencimento', to_char(v_hoje + 21, 'YYYY-MM-DD'), 'origem', 'pdf'),
              jsonb_build_object('linha', l3, 'valor', 555.49, 'vencimento', to_char(v_hoje + 51, 'YYYY-MM-DD'), 'origem', 'pdf'))))
  returning id into v_e3;
  r := public.contas_a_pagar_do_email(v_e3, v_hoje);
  select count(*) into n from public.payables where id = v_p and boleto_linha = l2 and email_message_id = v_e3 and status = 'pending';
  insert into _resultado values ('T4 boleto da parcela já lançada é ligado a ela', (r ->> 'ligadas')::int = 1 and n = 1, r::text);

  -- T5: a outra parcela (sem conta) nasce COM o fornecedor (pelo CNPJ da nota) e a categoria dele
  select count(*) into n from public.payables
   where boleto_linha = l3 and supplier_id = v_forn and supplier_name = 'FORNECEDOR DE TESTE DO BOLETO'
     and expense_category = v_cat and status = 'pending' and origin = 'boleto';
  insert into _resultado values ('T5 fornecedor pelo CNPJ da nota + categoria do histórico', (r ->> 'criadas')::int = 1 and n = 1, r::text);

  -- T6: boleto já pago no banco (saída por boleto, mesmo valor, ainda sem lançamento) → parece pago, não cria
  select id into v_bc from public.bank_connections where provider <> 'caixa' order by created_at limit 1;
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, payment_method, bank_ref_id, bank_connection_id)
  values (v_hoje - 1, 'Pagamento Boleto BCO TESTE', 333.17, 'debit', 'BOLETO', 'teste-boleto-' || l4, v_bc)
  returning id into v_tx;
  insert into public.email_messages (account_id, dedup_key, from_name, from_address, subject, received_at, has_attachments, dados_extraidos)
  values (v_conta, 'teste-boleto-6-' || l4, 'Boletos TESTE', 'boleto@teste.invalid', 'Boleto já pago', now(), true,
          jsonb_build_object('boletos', jsonb_build_array(
            jsonb_build_object('linha', l4, 'valor', 333.17, 'vencimento', to_char(v_hoje, 'YYYY-MM-DD'), 'origem', 'pdf'))))
  returning id into v_e4;
  r := public.contas_a_pagar_do_email(v_e4, v_hoje);
  select count(*) into n from public.payables where boleto_linha = l4;
  insert into _resultado values ('T6 saída por boleto no banco = parece pago, não cria', (r ->> 'parecem_pagas')::int = 1 and n = 0, r::text);

  -- T7: a mesma saída já lançada pelo Extrato → a linha é ligada à despesa paga
  insert into public.payables (supplier_name, description, issue_date, due_date, amount, status, paid_amount, balance_amount, origin, bank_transaction_id)
  values ('BCO TESTE', 'Pagamento Boleto BCO TESTE', v_hoje - 1, v_hoje - 1, 333.17, 'paid', 333.17, 0, 'bank_reconciliation', v_tx)
  returning id into v_p;
  r := public.contas_a_pagar_do_email(v_e4, v_hoje);
  select count(*) into n from public.payables where id = v_p and boleto_linha = l4 and status = 'paid';
  insert into _resultado values ('T7 despesa já lançada pelo Extrato recebe a linha', (r ->> 'ligadas')::int = 1 and n = 1, r::text);

  -- T8: vencido há 30 dias, sem conta e sem saída → histórico, não cria
  insert into public.email_messages (account_id, dedup_key, from_name, from_address, subject, received_at, has_attachments, dados_extraidos)
  values (v_conta, 'teste-boleto-8-' || l5, 'Boletos TESTE', 'boleto@teste.invalid', 'Boleto antigo', now() - interval '40 days', true,
          jsonb_build_object('boletos', jsonb_build_array(
            jsonb_build_object('linha', l5, 'valor', 777.31, 'vencimento', to_char(v_hoje - 30, 'YYYY-MM-DD'), 'origem', 'pdf'))))
  returning id into v_e5;
  r := public.contas_a_pagar_do_email(v_e5, v_hoje);
  select count(*) into n from public.payables where boleto_linha = l5;
  insert into _resultado values ('T8 boleto vencido há 30 dias não vira conta', (r ->> 'antigas')::int = 1 and n = 0, r::text);

  -- T9: vencimento incerto, sem vencimento, sem valor e linha curta → ignorados
  insert into public.email_messages (account_id, dedup_key, from_name, from_address, subject, received_at, has_attachments, dados_extraidos)
  values (v_conta, 'teste-boleto-9-' || l6, 'Boletos TESTE', 'boleto@teste.invalid', 'Boletos incompletos', now(), true,
          jsonb_build_object('boletos', jsonb_build_array(
            jsonb_build_object('linha', l6, 'valor', 10.01, 'vencimento', to_char(v_hoje + 3, 'YYYY-MM-DD'), 'vencimento_incerto', true, 'origem', 'pdf'),
            jsonb_build_object('linha', l6, 'valor', 10.01, 'vencimento', null, 'origem', 'pdf'),
            jsonb_build_object('linha', l6, 'valor', null, 'vencimento', to_char(v_hoje + 3, 'YYYY-MM-DD'), 'origem', 'pdf'),
            jsonb_build_object('linha', '12345', 'valor', 10.01, 'vencimento', to_char(v_hoje + 3, 'YYYY-MM-DD'), 'origem', 'pdf'))))
  returning id into v_e6;
  r := public.contas_a_pagar_do_email(v_e6, v_hoje);
  select count(*) into n from public.payables where boleto_linha = l6;
  insert into _resultado values ('T9 boleto incompleto ou incerto é ignorado', (r ->> 'ignoradas')::int = 4 and n = 0, r::text);

  -- T10: venceu ontem (dentro dos 5 dias) → cria, já vencida
  insert into public.email_messages (account_id, dedup_key, from_name, from_address, subject, received_at, has_attachments, dados_extraidos)
  values (v_conta, 'teste-boleto-10-' || l7, null, 'cobranca@teste.invalid', null, now() - interval '3 days', true,
          jsonb_build_object('boletos', jsonb_build_array(
            jsonb_build_object('linha', l7, 'valor', 88.03, 'vencimento', to_char(v_hoje - 1, 'YYYY-MM-DD'), 'origem', 'texto'))))
  returning id into v_e7;
  r := public.contas_a_pagar_do_email(v_e7, v_hoje);
  select count(*) into n from public.payables
   where boleto_linha = l7 and due_date = v_hoje - 1 and issue_date = v_hoje - 3 and supplier_name = 'cobranca@teste.invalid'
     and description like 'Boleto — %';
  insert into _resultado values ('T10 venceu ontem: cria (sem assunto nem nome, usa o endereço)', (r ->> 'criadas')::int = 1 and n = 1, r::text);

  -- T11: e-mail sem boletos e e-mail sem dados → zeros, sem erro
  update public.email_messages set dados_extraidos = '{}'::jsonb where id = v_e6;
  r := public.contas_a_pagar_do_email(v_e6, v_hoje);
  insert into _resultado values ('T11 e-mail sem boleto devolve zeros', (r ->> 'criadas')::int = 0 and (r ->> 'ignoradas')::int = 0, r::text);

  -- T12: chave desligada → pulado
  insert into public.app_settings (key, value) values ('boleto_email_modo', 'desligado')
    on conflict (key) do update set value = excluded.value;
  r := public.contas_a_pagar_do_email(v_e1, v_hoje);
  insert into _resultado values ('T12 chave boleto_email_modo = desligado pula', coalesce((r ->> 'pulado')::boolean, false), r::text);
  delete from public.app_settings where key = 'boleto_email_modo';

  -- T13: e-mail que não existe → erro com código
  begin
    r := public.contas_a_pagar_do_email(gen_random_uuid(), v_hoje);
    insert into _resultado values ('T13 e-mail inexistente dá erro', false, r::text);
  exception when others then
    insert into _resultado values ('T13 e-mail inexistente dá erro', sqlstate = 'P0002', sqlstate || ': ' || sqlerrm);
  end;
end $$;

-- T14–T16: só o serviço executa
insert into _resultado
select 'T14 anon NÃO executa', not has_function_privilege('anon', 'public.contas_a_pagar_do_email(uuid, date)', 'execute'), ''
union all
select 'T15 authenticated NÃO executa', not has_function_privilege('authenticated', 'public.contas_a_pagar_do_email(uuid, date)', 'execute'), ''
union all
select 'T16 service_role executa', has_function_privilege('service_role', 'public.contas_a_pagar_do_email(uuid, date)', 'execute'), '';

-- T17: dois boletos vivos com a mesma linha não cabem
do $$
declare
  l text := '999' || lpad((floor(random() * 1e15))::bigint::text, 44, '8');
begin
  insert into public.payables (supplier_name, description, issue_date, due_date, amount, status, paid_amount, balance_amount, origin, boleto_linha)
  values ('TESTE', 'boleto único 1', current_date, current_date, 1.01, 'pending', 0, 1.01, 'boleto', l);
  begin
    insert into public.payables (supplier_name, description, issue_date, due_date, amount, status, paid_amount, balance_amount, origin, boleto_linha)
    values ('TESTE', 'boleto único 2', current_date, current_date, 1.01, 'pending', 0, 1.01, 'boleto', l);
    insert into _resultado values ('T17 índice: um boleto, uma conta viva', false, 'inseriu duas');
  exception when unique_violation then
    insert into _resultado values ('T17 índice: um boleto, uma conta viva', true, '');
  end;
end $$;

select teste, ok, detalhe from _resultado order by (substring(teste from 'T(\d+)'))::int;

rollback;
