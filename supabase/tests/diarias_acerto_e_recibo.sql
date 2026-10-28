-- Prova: o recibo de diárias sai do Pix que zera a conta — foto congelada com hash, travas, dias
-- travados até a data, o próximo recibo começando em zero, reabrir só o último e com motivo, e o
-- "ok" do freelancer (migrations 20261006220000_diarias_acerto_e_recibo e
-- 20261027180000_diarias_recibo_de_servicos).
--
--   supabase db query --linked -f supabase/tests/diarias_acerto_e_recibo.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Cria um freelancer de teste com CPF fictício.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- Um pagamento de diária já lançado (o que a fila vira depois de aprovada).
create function pg_temp._pix(p_fav uuid, p_data date, p_valor numeric) returns uuid language sql as $$
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               payee_id, origin)
  values ('Pix teste recibo', p_data, p_data, p_valor, p_valor, 0, 'paid', 'Diárias de freelancers', p_fav, 'bank_reconciliation')
  returning id;
$$;

do $$
declare
  v_dono uuid;
  v_hoje date := public._hoje_brt();
  v_fav uuid;
  v_cpf text := '999' || lpad((floor(random() * 100000000))::int::text, 8, '0');
  v_conta uuid;
  r jsonb;
  a1 jsonb;
  a2 jsonb;
  v_n integer;
  v_dia uuid;
  v_pix uuid;
  v_ac record;
begin
  select id into v_dono from public.app_users where role = 'admin' and active order by created_at limit 1;
  r := public.cadastrar_freelancer('Teste Recibo ' || lpad((floor(random() * 1000000))::int::text, 6, '0'),
                                   100, v_hoje - 10, null, null, null, '(47) 98888-7777', null, false, v_dono);
  v_fav := (r ->> 'favorecido_id')::uuid;
  update public.payees set phone = '5547988887777', document = v_cpf, nit = '123.45678.90-1' where id = v_fav;
  insert into public.bank_connections (provider, external_id, label, account_kind)
  values ('manual', 'teste-recibo-' || gen_random_uuid(), 'Conta Teste Recibo', 'bank') returning id into v_conta;

  perform public.registrar_diaria(v_fav, v_hoje - 10, 'inteiro', null, null, null, null, null, 'painel', v_dono);
  perform public.registrar_diaria(v_fav, v_hoje - 9, 'inteiro', null, null, null, null, null, 'painel', v_dono);
  perform public.registrar_diaria(v_fav, v_hoje - 8, 'meio', null, null, null, null, null, 'painel', v_dono);
  perform pg_temp._pix(v_fav, v_hoje - 9, 60);  -- um vale no meio do período

  -- T01. Sem Pix que zere: a simulação diz quanto falta e não grava.
  r := public.fechar_acerto_diarias(v_fav, null, true, null);
  select count(*) into v_n from public.acertos_diarias where favorecido_id = v_fav;
  insert into _resultado values ('T01 sem Pix que zere',
    v_n = 0 and not (r ->> 'ok')::boolean and r -> 'travas' ->> 0 like 'Falta pagar R$ 190,00%'
      and jsonb_array_length(r -> 'candidatos') = 1 and not (r -> 'candidatos' -> 0 ->> 'zera')::boolean,
    r::text);

  -- T02. Com o Pix de 190: escolhe sozinho, mostra a prévia (vale à parte do Pix) e não grava.
  v_pix := pg_temp._pix(v_fav, v_hoje - 7, 190);
  r := public.fechar_acerto_diarias(v_fav, v_hoje - 8, true, null);
  select count(*) into v_n from public.acertos_diarias where favorecido_id = v_fav;
  insert into _resultado values ('T02 simular com o Pix',
    v_n = 0 and (r ->> 'ok')::boolean and (r -> 'pix' ->> 'id')::uuid = v_pix and (r ->> 'trabalhado')::numeric = 250
      and (r ->> 'pago_no_periodo')::numeric = 60 and (r ->> 'valor_do_acerto')::numeric = 190
      and (r ->> 'saldo_final')::numeric = 0 and jsonb_array_length(r -> 'vales') = 1 and (r ->> 'de')::date = v_hoje - 10
      and r ->> 'resumo' like '%2,5 diária(s)%Pix de%R$ 190,00',
    r ->> 'resumo');

  -- T03. Travas: adicional sem motivo e falta de CPF (todas de uma vez, sem gravar).
  update public.work_shifts set extras = 20
   where id = (select ws.id from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
                where wp.payee_id = v_fav and ws.data = v_hoje - 10);
  update public.payees set document = null where id = v_fav;
  r := public.fechar_acerto_diarias(v_fav, v_hoje - 8, true, null, v_pix);
  insert into _resultado values ('T03 travas juntas',
    not (r ->> 'ok')::boolean
      and exists (select 1 from jsonb_array_elements_text(r -> 'travas') t where t like 'Falta o CPF%')
      and exists (select 1 from jsonb_array_elements_text(r -> 'travas') t where t like '%motivo do adicional%')
      and exists (select 1 from jsonb_array_elements_text(r -> 'travas') t where t like '%ainda falta pagar R$ 20,00%'),
    (r -> 'travas')::text);
  begin
    perform public.fechar_acerto_diarias(v_fav, v_hoje - 8, false, v_dono, v_pix);
    insert into _resultado values ('T03b fechar com trava recusa', false, 'fechou');
  exception when others then
    insert into _resultado values ('T03b fechar com trava recusa', sqlerrm like '%Falta o CPF%', sqlerrm);
  end;
  update public.work_shifts set extras = 0
   where id = (select ws.id from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
                where wp.payee_id = v_fav and ws.data = v_hoje - 10);
  update public.payees set document = v_cpf where id = v_fav;

  -- T04. Fechar: número, foto congelada com hash, totais com o Pix à parte.
  a1 := public.fechar_acerto_diarias(v_fav, v_hoje - 8, false, v_dono);
  select * into v_ac from public.acertos_diarias where id = (a1 ->> 'id')::uuid;
  insert into _resultado values ('T04 fechar',
    (a1 ->> 'numero')::int > 0 and (a1 ->> 'valor_do_acerto')::numeric = 190 and a1 ->> 'message' like 'Recibo nº%travados%'
      and v_ac.pix_quitacao_id = v_pix and v_ac.pagos_ate = v_hoje - 7 and v_ac.ate = v_hoje - 8 and v_ac.pago_no_periodo = 60
      and v_ac.hash = encode(sha256(convert_to(v_ac.documento::text, 'UTF8')), 'hex')
      and v_ac.documento -> 'prestador' ->> 'nit' = '123.45678.90-1' and v_ac.documento -> 'empresa' ->> 'cnpj' is not null
      and jsonb_array_length(v_ac.documento -> 'linhas') = 5,
    a1 ->> 'message');

  -- T05. Dia travado: não muda, não sai. Dia depois do acerto entra.
  begin
    perform public.registrar_diaria(v_fav, v_hoje - 9, 'meio', null, null, null, null, null, 'painel', v_dono);
    insert into _resultado values ('T05a mudar dia travado', false, 'mudou');
  exception when others then
    insert into _resultado values ('T05a mudar dia travado', sqlerrm like '%está no acerto nº%', sqlerrm);
  end;
  select ws.id into v_dia from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
   where wp.payee_id = v_fav and ws.data = v_hoje - 10;
  begin
    perform public.apagar_diaria(v_dia, v_dono);
    insert into _resultado values ('T05b apagar dia travado', false, 'apagou');
  exception when others then
    insert into _resultado values ('T05b apagar dia travado', sqlerrm like '%está no acerto nº%', sqlerrm);
  end;
  r := public.registrar_diaria(v_fav, v_hoje - 5, 'inteiro', null, null, null, null, null, 'painel', v_dono);
  insert into _resultado values ('T05c dia depois do acerto entra', r ->> 'acao' = 'criado', r ->> 'message');

  -- T06. Pix na fila (linha do banco pelo CPF) não serve de quitação: aprovar antes.
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, bank_connection_id,
                                        counterparty_document)
  values (v_hoje - 4, 'PIX TESTE RECIBO FILA', 100, 'debit', 'bank', v_conta, v_cpf);
  r := public.fechar_acerto_diarias(v_fav, null, true, null,
         (select (x ->> 'id')::uuid from jsonb_array_elements(public.fechar_acerto_diarias(v_fav, null, true, null) -> 'candidatos') x
           where (x ->> 'aguardando')::boolean limit 1));
  insert into _resultado values ('T06 Pix da fila trava',
    not (r ->> 'ok')::boolean and exists (select 1 from jsonb_array_elements_text(r -> 'travas') t where t like '%está na fila: aprove%'),
    (r -> 'travas')::text);
  delete from public.bank_transactions where description = 'PIX TESTE RECIBO FILA' and bank_connection_id = v_conta;

  -- T07. O segundo recibo começa em zero: dia seguinte ao anterior, saldo anterior 0, o número sobe.
  v_pix := pg_temp._pix(v_fav, v_hoje - 4, 100);
  a2 := public.fechar_acerto_diarias(v_fav, null, false, v_dono);
  select * into v_ac from public.acertos_diarias where id = (a2 ->> 'id')::uuid;
  insert into _resultado values ('T07 segundo recibo começa em zero',
    (a2 ->> 'numero')::int = (a1 ->> 'numero')::int + 1 and v_ac.de = v_hoje - 7 and v_ac.saldo_anterior = 0
      and v_ac.trabalhado = 100 and v_ac.valor_do_acerto = 100 and v_ac.pago_no_periodo = 0,
    a2 ->> 'message');

  -- T08. Nada a quitar de novo.
  begin
    perform public.fechar_acerto_diarias(v_fav, null, false, v_dono);
    insert into _resultado values ('T08 nada a quitar', false, 'fechou de novo');
  exception when others then
    insert into _resultado values ('T08 nada a quitar', sqlerrm like 'Nenhum pagamento depois do último recibo%', sqlerrm);
  end;

  -- T09. Reabrir: só o último, e com motivo.
  begin
    perform public.reabrir_acerto_diarias((select id from public.acertos_diarias where numero = (a1 ->> 'numero')::int), 'teste', v_dono);
    insert into _resultado values ('T09a reabrir o antigo', false, 'reabriu');
  exception when others then
    insert into _resultado values ('T09a reabrir o antigo', sqlerrm like 'Só o último acerto%', sqlerrm);
  end;
  begin
    perform public.reabrir_acerto_diarias((select id from public.acertos_diarias where numero = (a2 ->> 'numero')::int), '  ', v_dono);
    insert into _resultado values ('T09b sem motivo', false, 'reabriu sem motivo');
  exception when others then
    insert into _resultado values ('T09b sem motivo', sqlerrm like '%motivo%', sqlerrm);
  end;
  r := public.reabrir_acerto_diarias((select id from public.acertos_diarias where numero = (a2 ->> 'numero')::int), 'dia errado', v_dono);
  r := public.registrar_diaria(v_fav, v_hoje - 5, 'meio', null, null, null, null, null, 'painel', v_dono);
  insert into _resultado values ('T09c reaberto destrava', r ->> 'acao' = 'atualizado', r ->> 'message');

  -- T10. Conferência: "ok" do número a quem foi mandado vira conferido; "não" e outro número não.
  update public.acertos_diarias set enviado_ao_freelancer_em = now(), telefone_enviado = '5547988887777'
   where numero = (a1 ->> 'numero')::int;
  r := public.registrar_conferencia_do_freelancer('5547911112222', 'ok', null);
  insert into _resultado values ('T10a outro numero nao confere', not (r ->> 'conferiu')::boolean, r::text);
  r := public.registrar_conferencia_do_freelancer('5547988887777', 'não está certo', null);
  insert into _resultado values ('T10b discordar nao confere', not (r ->> 'conferiu')::boolean, r::text);
  r := public.registrar_conferencia_do_freelancer('+55 (47) 98888-7777', 'ok', null);
  insert into _resultado values ('T10c ok confere',
    (r ->> 'conferiu')::boolean and (select conferido_texto from public.acertos_diarias where numero = (a1 ->> 'numero')::int) = 'ok',
    r::text);

  -- T11. Quem pode.
  insert into _resultado values ('T11 permissoes',
    not has_function_privilege('anon', 'public.fechar_acerto_diarias(uuid, date, boolean, uuid, uuid, date)', 'execute')
      and has_function_privilege('authenticated', 'public.fechar_acerto_diarias(uuid, date, boolean, uuid, uuid, date)', 'execute')
      and not has_function_privilege('authenticated', 'public._previa_do_recibo(uuid, date, date, date, uuid)', 'execute')
      and not has_function_privilege('anon', 'public.reabrir_acerto_diarias(uuid, text, uuid)', 'execute')
      and not has_function_privilege('authenticated', 'public.registrar_conferencia_do_freelancer(text, text, uuid)', 'execute')
      and not has_table_privilege('anon', 'public.acertos_diarias', 'select')
      and not has_table_privilege('authenticated', 'public.acertos_diarias', 'insert'),
    'anon fora; tabela só leitura para logado');
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
