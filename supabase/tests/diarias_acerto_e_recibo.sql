-- Prova: acerto de diárias — fecha o período (foto: dias, vales, a pagar), TRAVA os dias até a data,
-- reabre só o último e com motivo, numera o recibo, e guarda o "ok" do freelancer
-- (migration 20261006220000_diarias_acerto_e_recibo).
--
--   supabase db query --linked -f supabase/tests/diarias_acerto_e_recibo.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Cria um freelancer de teste.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_dono uuid;
  v_hoje date := public._hoje_brt();
  v_fav uuid;
  r jsonb;
  a1 jsonb;
  a2 jsonb;
  v_n integer;
  v_dia uuid;
begin
  select id into v_dono from public.app_users where role = 'admin' and active order by created_at limit 1;
  r := public.cadastrar_freelancer('Teste Acerto ' || lpad((floor(random() * 1000000))::int::text, 6, '0'),
                                   100, v_hoje - 10, null, null, null, '(47) 98888-7777', null, false, v_dono);
  v_fav := (r ->> 'favorecido_id')::uuid;
  update public.payees set phone = '5547988887777' where id = v_fav;

  perform public.registrar_diaria(v_fav, v_hoje - 10, 'inteiro', null, null, null, null, null, 'painel', v_dono);
  perform public.registrar_diaria(v_fav, v_hoje - 9, 'inteiro', null, null, null, null, null, 'painel', v_dono);
  perform public.registrar_diaria(v_fav, v_hoje - 8, 'meio', null, null, null, null, null, 'painel', v_dono);
  -- Um vale (adiantamento) no meio do período.
  insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, data_exata, favorecido_id, categoria, descricao, status, criada_por)
  values ('debit', 60, v_hoje - 9, true, v_fav, 'Diárias de freelancers', 'Vale', 'aguardando', v_dono);

  -- T1. Simular não grava e mostra o que o acerto vai ser.
  r := public.fechar_acerto_diarias(v_fav, v_hoje - 8, true, null);
  select count(*) into v_n from public.acertos_diarias where favorecido_id = v_fav;
  insert into _resultado values ('T01 simular',
    v_n = 0 and (r ->> 'trabalhado')::numeric = 250 and (r ->> 'pago_no_periodo')::numeric = 60
      and (r ->> 'valor_do_acerto')::numeric = 190 and jsonb_array_length(r -> 'vales') = 1
      and (r ->> 'de')::date = v_hoje - 10,
    r ->> 'resumo');

  -- T2. Fechar: foto do período e número de recibo.
  a1 := public.fechar_acerto_diarias(v_fav, v_hoje - 8, false, v_dono);
  insert into _resultado values ('T02 fechar',
    (a1 ->> 'numero')::int > 0 and (a1 ->> 'valor_do_acerto')::numeric = 190 and a1 ->> 'message' like 'Acerto nº%travados%'
      and a1 ->> 'message' like '%2,5 diária(s)%',
    a1 ->> 'message');

  -- T3. Dia travado: não entra, não muda, não sai. Dia depois do acerto entra.
  begin
    perform public.registrar_diaria(v_fav, v_hoje - 9, 'meio', null, null, null, null, null, 'painel', v_dono);
    insert into _resultado values ('T03a mudar dia travado', false, 'mudou');
  exception when others then
    insert into _resultado values ('T03a mudar dia travado', sqlerrm like '%está no acerto nº%', sqlerrm);
  end;
  select ws.id into v_dia from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
   where wp.payee_id = v_fav and ws.data = v_hoje - 10;
  begin
    perform public.apagar_diaria(v_dia, v_dono);
    insert into _resultado values ('T03b apagar dia travado', false, 'apagou');
  exception when others then
    insert into _resultado values ('T03b apagar dia travado', sqlerrm like '%está no acerto nº%', sqlerrm);
  end;
  r := public.registrar_diaria(v_fav, v_hoje - 5, 'inteiro', null, null, null, null, null, 'painel', v_dono);
  insert into _resultado values ('T03c dia depois do acerto entra', r ->> 'acao' = 'criado', r ->> 'message');

  -- T4. Segundo acerto começa no dia seguinte ao primeiro; o número sobe; o saldo anterior é o que ficou.
  a2 := public.fechar_acerto_diarias(v_fav, v_hoje - 5, false, v_dono);
  insert into _resultado values ('T04 segundo acerto',
    (a2 ->> 'numero')::int = (a1 ->> 'numero')::int + 1 and (a2 ->> 'de')::date = v_hoje - 7
      and (select saldo_anterior from public.acertos_diarias where numero = (a2 ->> 'numero')::int) = 190
      and (a2 ->> 'valor_do_acerto')::numeric = 290,
    a2 ->> 'message');

  -- T5. Nada a fechar de novo até a mesma data.
  begin
    perform public.fechar_acerto_diarias(v_fav, v_hoje - 5, false, v_dono);
    insert into _resultado values ('T05 nada a fechar', false, 'fechou de novo');
  exception when others then
    insert into _resultado values ('T05 nada a fechar', sqlerrm like 'Nada a fechar%', sqlerrm);
  end;

  -- T6. Reabrir: só o último, e com motivo.
  begin
    perform public.reabrir_acerto_diarias((select id from public.acertos_diarias where numero = (a1 ->> 'numero')::int), 'teste', v_dono);
    insert into _resultado values ('T06a reabrir o antigo', false, 'reabriu');
  exception when others then
    insert into _resultado values ('T06a reabrir o antigo', sqlerrm like 'Só o último acerto%', sqlerrm);
  end;
  begin
    perform public.reabrir_acerto_diarias((select id from public.acertos_diarias where numero = (a2 ->> 'numero')::int), '  ', v_dono);
    insert into _resultado values ('T06b sem motivo', false, 'reabriu sem motivo');
  exception when others then
    insert into _resultado values ('T06b sem motivo', sqlerrm like '%motivo%', sqlerrm);
  end;
  r := public.reabrir_acerto_diarias((select id from public.acertos_diarias where numero = (a2 ->> 'numero')::int), 'dia errado', v_dono);
  r := public.registrar_diaria(v_fav, v_hoje - 5, 'meio', null, null, null, null, null, 'painel', v_dono);
  insert into _resultado values ('T06c reaberto destrava', r ->> 'acao' = 'atualizado', r ->> 'message');

  -- T7. Conferência: "ok" do número a quem foi mandado vira conferido; "não" e outro número não.
  update public.acertos_diarias set enviado_ao_freelancer_em = now(), telefone_enviado = '5547988887777'
   where numero = (a1 ->> 'numero')::int;
  r := public.registrar_conferencia_do_freelancer('5547911112222', 'ok', null);
  insert into _resultado values ('T07a outro numero nao confere', not (r ->> 'conferiu')::boolean, r::text);
  r := public.registrar_conferencia_do_freelancer('5547988887777', 'não está certo', null);
  insert into _resultado values ('T07b discordar nao confere', not (r ->> 'conferiu')::boolean, r::text);
  r := public.registrar_conferencia_do_freelancer('+55 (47) 98888-7777', 'ok', null);
  insert into _resultado values ('T07c ok confere',
    (r ->> 'conferiu')::boolean and (select conferido_texto from public.acertos_diarias where numero = (a1 ->> 'numero')::int) = 'ok',
    r::text);

  -- T8. Quem pode.
  insert into _resultado values ('T08 permissoes',
    not has_function_privilege('anon', 'public.fechar_acerto_diarias(uuid, date, boolean, uuid)', 'execute')
      and not has_function_privilege('anon', 'public.reabrir_acerto_diarias(uuid, text, uuid)', 'execute')
      and not has_function_privilege('authenticated', 'public.registrar_conferencia_do_freelancer(text, text, uuid)', 'execute')
      and not has_table_privilege('anon', 'public.acertos_diarias', 'select')
      and not has_table_privilege('authenticated', 'public.acertos_diarias', 'insert'),
    'anon fora; tabela só leitura para logado');
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
