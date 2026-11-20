-- Prova: "Saiu da equipe" (migration 20270210100000_freelancer_saida_da_equipe).
--
--   supabase db query --linked -f supabase/tests/freelancer_saida_da_equipe.sql --output json
--
-- Seguro em produção: a transação inteira termina em ROLLBACK. Cria um freelancer de teste (nome com
-- sufixo aleatório) e, no fim, um prestador sem diária; não toca em ninguém de verdade.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_dono uuid;
  v_hoje date := public._hoje_brt();
  v_sufixo text := lpad((floor(random() * 1000000))::int::text, 6, '0');
  v_fav uuid;
  v_outro uuid;
  r jsonb;
  s jsonb;
  v_fim date;
  v_n int;
  v_pessoa jsonb;
begin
  select id into v_dono from public.app_users where role = 'admin' and active order by created_at limit 1;
  if v_dono is null then
    insert into _resultado values ('setup', false, 'sem admin ativo');
    return;
  end if;
  r := public.cadastrar_freelancer('Teste Saida ' || v_sufixo, 100, v_hoje - 20, null, null, null, null, null, false, v_dono);
  v_fav := (r ->> 'favorecido_id')::uuid;
  perform public.registrar_diaria(v_fav, v_hoje - 10, 'inteiro', null, null, null, null, null, 'painel', v_dono);
  perform public.registrar_diaria(v_fav, v_hoje - 9, 'meio', null, null, null, null, null, 'painel', v_dono);
  perform public.registrar_diaria(v_fav, v_hoje - 5, 'inteiro', null, null, null, null, null, 'painel', v_dono);

  -- S1. Simular não grava e diz o que vai acontecer, com o saldo.
  r := public.registrar_saida_da_equipe(v_fav, v_hoje - 5, true, null);
  select vigencia_fim into v_fim from public.work_profiles where payee_id = v_fav;
  insert into _resultado values ('S1 simular nao grava',
    v_fim is null and r ->> 'acao' = 'saiu' and (r ->> 'simulado')::boolean
      and r ->> 'message' like '%sai da equipe: último dia%' and r ->> 'message' like '%R$ 250,00 a receber%',
    r ->> 'message');

  -- S2. Gravar sem dizer quem: recusa.
  begin
    perform public.registrar_saida_da_equipe(v_fav, v_hoje - 5, false, null);
    insert into _resultado values ('S2 sem autor recusa', false, 'gravou');
  exception when others then
    insert into _resultado values ('S2 sem autor recusa', sqlerrm like 'Diga quem está registrando a saída%', sqlerrm);
  end;

  -- S3. Último dia antes de um dia já lançado: recusa e diz qual.
  begin
    perform public.registrar_saida_da_equipe(v_fav, v_hoje - 8, false, v_dono);
    insert into _resultado values ('S3 dia lancado depois recusa', false, 'gravou');
  exception when others then
    insert into _resultado values ('S3 dia lancado depois recusa',
      sqlerrm like 'Há 1 dia(s) de % lançado(s) depois de %' and sqlerrm like '%' || to_char(v_hoje - 5, 'DD/MM') || '%', sqlerrm);
  end;

  -- S4. Futuro e antes do começo da diária: recusa.
  begin
    perform public.registrar_saida_da_equipe(v_fav, v_hoje + 1, false, v_dono);
    insert into _resultado values ('S4a futuro recusa', false, 'gravou');
  exception when others then
    insert into _resultado values ('S4a futuro recusa', sqlerrm like 'Último dia no futuro%', sqlerrm);
  end;
  begin
    perform public.registrar_saida_da_equipe(v_fav, v_hoje - 30, false, v_dono);
    insert into _resultado values ('S4b antes do comeco recusa', false, 'gravou');
  exception when others then
    insert into _resultado values ('S4b antes do comeco recusa', sqlerrm like 'O último dia % é antes do começo da diária%', sqlerrm);
  end;

  -- S5. A saída grava o fim da vigência; o cadastro continua ativo.
  r := public.registrar_saida_da_equipe(v_fav, v_hoje - 5, false, v_dono);
  select vigencia_fim into v_fim from public.work_profiles where payee_id = v_fav;
  insert into _resultado values ('S5 saida grava',
    v_fim = v_hoje - 5 and r ->> 'acao' = 'saiu' and r ->> 'message' like '%saiu da equipe%'
      and (select active from public.payees where id = v_fav) and public._saida_da_equipe(v_fav) = v_hoje - 5,
    r ->> 'message');

  -- S6. Depois do último dia nenhum dia entra (com a mensagem certa); antes dele, entra (dia esquecido).
  begin
    perform public.registrar_diaria(v_fav, v_hoje - 4, 'inteiro', null, null, null, null, null, 'painel', v_dono);
    insert into _resultado values ('S6a dia depois da saida recusa', false, 'gravou');
  exception when others then
    insert into _resultado values ('S6a dia depois da saida recusa',
      sqlerrm like '% saiu da equipe (último dia ' || to_char(v_hoje - 5, 'DD/MM/YYYY') || ')%', sqlerrm);
  end;
  r := public.registrar_diaria(v_fav, v_hoje - 6, 'inteiro', null, null, null, null, null, 'painel', v_dono);
  insert into _resultado values ('S6b dia antes da saida entra', r ->> 'acao' = 'criado', r ->> 'message');
  begin
    perform public.registrar_diarias_em_lote(v_fav, jsonb_build_array(jsonb_build_object('data', v_hoje - 3, 'jornada', 'inteiro')), 'agente', v_dono);
    insert into _resultado values ('S6c lote depois da saida recusa', false, 'gravou');
  exception when others then
    insert into _resultado values ('S6c lote depois da saida recusa', sqlerrm like '%saiu da equipe%', sqlerrm);
  end;

  -- S7. O resumo continua mostrando a dívida, com saiu_em; e ela entra no "a pagar a todos".
  s := public.resumo_freelancers(null, null, v_dono, null);
  select x into v_pessoa from jsonb_array_elements(s -> 'pessoas') x where x ->> 'id' = v_fav::text;
  insert into _resultado values ('S7 resumo mostra quem saiu com o saldo',
    v_pessoa is not null and (v_pessoa ->> 'saiu_em')::date = v_hoje - 5 and (v_pessoa ->> 'ativo')::boolean
      and (v_pessoa ->> 'saldo_final')::numeric = 350 and (v_pessoa ->> 'ultimo_dia_trabalhado')::date = v_hoje - 5
      and (s ->> 'deve')::numeric >= 350,
    coalesce(v_pessoa::text, 'nao apareceu'));

  -- S8. Mudar a data e repetir a mesma.
  r := public.registrar_saida_da_equipe(v_fav, v_hoje - 5, false, v_dono);
  insert into _resultado values ('S8a mesma data nada muda', r ->> 'acao' = 'sem_mudanca', r ->> 'message');
  r := public.registrar_saida_da_equipe(v_fav, v_hoje - 2, false, v_dono);
  select vigencia_fim into v_fim from public.work_profiles where payee_id = v_fav;
  insert into _resultado values ('S8b outra data muda', r ->> 'acao' = 'mudou_a_data' and v_fim = v_hoje - 2, r ->> 'message');

  -- S9. Adiantado (Roberto: "cobrar / descontar se ele voltar"): a saída não zera; a frase diz adiantado.
  update public.payees set saldo_anterior = -1000 where id = v_fav;
  r := public.registrar_saida_da_equipe(v_fav, v_hoje - 2, true, null);
  s := public.resumo_freelancers(null, null, v_dono, null);
  select x into v_pessoa from jsonb_array_elements(s -> 'pessoas') x where x ->> 'id' = v_fav::text;
  insert into _resultado values ('S9 adiantado fica registrado',
    r ->> 'message' like '%R$ 650,00 adiantado (ele deve dias)%' and (v_pessoa ->> 'saldo_final')::numeric = -650
      and (s ->> 'adiantado')::numeric >= 650,
    r ->> 'message');

  -- S10. Desativado nos favorecidos COM saldo continua no resumo; zerado sai (como antes).
  update public.payees set active = false where id = v_fav;
  s := public.resumo_freelancers(null, null, v_dono, null);
  select x into v_pessoa from jsonb_array_elements(s -> 'pessoas') x where x ->> 'id' = v_fav::text;
  insert into _resultado values ('S10a desativado com saldo aparece',
    v_pessoa is not null and not (v_pessoa ->> 'ativo')::boolean, coalesce(v_pessoa::text, 'nao apareceu'));
  update public.payees set saldo_anterior = -350 where id = v_fav;   -- 350 trabalhado − 350 = zero
  s := public.resumo_freelancers(null, null, v_dono, null);
  select count(*) into v_n from jsonb_array_elements(s -> 'pessoas') x where x ->> 'id' = v_fav::text;
  insert into _resultado values ('S10b desativado zerado sai', v_n = 0, null);

  -- S11. Voltar: com o cadastro desativado, recusa (a saída não reativa nada); reativado, volta e o dia entra.
  begin
    perform public.desfazer_saida_da_equipe(v_fav, false, v_dono);
    insert into _resultado values ('S11a volta com desativado recusa', false, 'gravou');
  exception when others then
    insert into _resultado values ('S11a volta com desativado recusa', sqlerrm like '%desativado nos favorecidos%', sqlerrm);
  end;
  update public.payees set active = true where id = v_fav;
  r := public.desfazer_saida_da_equipe(v_fav, true, null);
  select vigencia_fim into v_fim from public.work_profiles where payee_id = v_fav;
  insert into _resultado values ('S11b simular a volta nao grava', v_fim = v_hoje - 2 and r ->> 'message' like '%volta para a equipe%', r ->> 'message');
  r := public.desfazer_saida_da_equipe(v_fav, false, v_dono);
  select vigencia_fim into v_fim from public.work_profiles where payee_id = v_fav;
  s := public.registrar_diaria(v_fav, v_hoje - 1, 'inteiro', null, null, null, null, null, 'painel', v_dono);
  insert into _resultado values ('S11c voltou e o dia entra',
    v_fim is null and r ->> 'message' like '%voltou para a equipe%' and s ->> 'acao' = 'criado'
      and public._saida_da_equipe(v_fav) is null,
    r ->> 'message');
  begin
    perform public.desfazer_saida_da_equipe(v_fav, false, v_dono);
    insert into _resultado values ('S11d volta sem saida recusa', false, 'gravou');
  exception when others then
    insert into _resultado values ('S11d volta sem saida recusa', sqlerrm like '%não saiu da equipe%', sqlerrm);
  end;

  -- S12. Quem não tem diária (prestador por serviço) não tem saída da equipe.
  insert into public.payees (name, kind, active) values ('Prestador Teste ' || v_sufixo, 'prestador', true) returning id into v_outro;
  begin
    perform public.registrar_saida_da_equipe(v_outro, v_hoje - 1, true, null);
    insert into _resultado values ('S12 sem diaria recusa', false, 'simulou');
  exception when others then
    insert into _resultado values ('S12 sem diaria recusa', sqlerrm like '%não recebe por diária%', sqlerrm);
  end;

  -- S13. Quem pode: as duas funções abertas só a quem entra; as internas, nem isso.
  insert into _resultado values ('S13 permissoes',
    not has_function_privilege('anon', 'public.registrar_saida_da_equipe(uuid, date, boolean, uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.registrar_saida_da_equipe(uuid, date, boolean, uuid)', 'execute')
      and not has_function_privilege('anon', 'public.desfazer_saida_da_equipe(uuid, boolean, uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.desfazer_saida_da_equipe(uuid, boolean, uuid)', 'execute')
      and not has_function_privilege('anon', 'public._saida_da_equipe(uuid)', 'execute')
      and not has_function_privilege('authenticated', 'public._saida_da_equipe(uuid)', 'execute')
      and not has_function_privilege('anon', 'public._frase_do_saldo_da_saida(numeric, boolean)', 'execute'),
    null);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
