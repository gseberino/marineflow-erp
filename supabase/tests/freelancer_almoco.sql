-- Prova: "Trouxe o almoço" (migration 20270210110000_freelancer_almoco).
--
--   supabase db query --linked -f supabase/tests/freelancer_almoco.sql --output json
--
-- Seguro em produção: a transação inteira termina em ROLLBACK. Cria um freelancer de teste (nome com
-- sufixo aleatório). O valor do almoço é o da configuração (diarias_valor_almoco): o teste lê a chave
-- e confere contra ela — não supõe R$ 20.
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
  v_alm numeric := public._valor_do_almoco();
  r jsonb;
  w record;
  c jsonb;
  v_n int;
begin
  select id into v_dono from public.app_users where role = 'admin' and active order by created_at limit 1;
  if v_dono is null or v_alm is null then
    insert into _resultado values ('setup', false, 'sem admin ativo ou sem diarias_valor_almoco');
    return;
  end if;
  r := public.cadastrar_freelancer('Teste Almoco ' || v_sufixo, 100, v_hoje - 20, null, null, null, null, null, false, v_dono);
  v_fav := (r ->> 'favorecido_id')::uuid;

  -- A0. A configuração existe e vale R$ 20 (o que o dono disse).
  insert into _resultado values ('A0 valor do almoco configurado', v_alm = 20, v_alm::text);

  -- A1. A caixa: o almoço entra no extra e o motivo é escrito sozinho.
  r := public.registrar_diaria(v_fav, v_hoje - 10, 'inteiro', null, null, null, null, null, 'painel', v_dono, true);
  select ws.* into w from public.work_shifts ws where ws.id = (r ->> 'diaria_id')::uuid;
  insert into _resultado values ('A1 almoco com motivo sozinho',
    w.almoco = v_alm and w.extras = v_alm and w.observacao = 'Alimentação (trouxe o almoço)' and w.valor_dia = 100 + v_alm
      and r ->> 'message' like '%(com almoço R$ 20,00)%',
    r ->> 'message');

  -- A2. Com observação dita: o motivo vai na frente, a observação continua.
  r := public.registrar_diaria(v_fav, v_hoje - 9, 'inteiro', null, 'barco do Rodrigo', 30, null, null, 'painel', v_dono, true);
  select ws.* into w from public.work_shifts ws where ws.id = (r ->> 'diaria_id')::uuid;
  insert into _resultado values ('A2 almoco mais outros extras e a observacao',
    w.almoco = v_alm and w.extras = 30 + v_alm and w.observacao = 'Alimentação (trouxe o almoço); barco do Rodrigo',
    w.observacao || ' · ' || w.extras);

  -- A3. Corrigir só a jornada (sem dizer almoço nem extras): almoço, extras e observação ficam.
  r := public.registrar_diaria(v_fav, v_hoje - 9, 'meio', null, null, null, null, null, 'painel', v_dono, null);
  select ws.* into w from public.work_shifts ws where ws.id = (r ->> 'diaria_id')::uuid;
  insert into _resultado values ('A3 corrigir a jornada mantem o almoco',
    w.fracao = 0.5 and w.almoco = v_alm and w.extras = 30 + v_alm and w.observacao = 'Alimentação (trouxe o almoço); barco do Rodrigo',
    w.observacao || ' · ' || w.extras);

  -- A4. Marcar de novo não soma outro almoço.
  r := public.registrar_diaria(v_fav, v_hoje - 9, 'meio', null, null, null, null, null, 'painel', v_dono, true);
  select ws.* into w from public.work_shifts ws where ws.id = (r ->> 'diaria_id')::uuid;
  insert into _resultado values ('A4 marcar de novo nao duplica',
    w.almoco = v_alm and w.extras = 30 + v_alm and w.observacao = 'Alimentação (trouxe o almoço); barco do Rodrigo', w.extras::text);

  -- A5. Tirar o almoço: sai o valor e sai o motivo; o resto fica.
  r := public.registrar_diaria(v_fav, v_hoje - 9, 'meio', null, null, null, null, null, 'painel', v_dono, false);
  select ws.* into w from public.work_shifts ws where ws.id = (r ->> 'diaria_id')::uuid;
  insert into _resultado values ('A5 tirar o almoco',
    w.almoco = 0 and w.extras = 30 and w.observacao = 'barco do Rodrigo', coalesce(w.observacao, '∅') || ' · ' || w.extras);

  -- A6. Quem não diz almoço (caminho antigo): extras é o TOTAL do dia — o almoço fica dentro se couber.
  r := public.registrar_diaria(v_fav, v_hoje - 10, 'inteiro', null, null, 50, null, null, 'painel', v_dono);
  select ws.* into w from public.work_shifts ws where ws.id = (r ->> 'diaria_id')::uuid;
  insert into _resultado values ('A6a total antigo inclui o almoco',
    w.almoco = v_alm and w.extras = 50 and w.observacao = 'Alimentação (trouxe o almoço)', w.extras::text);
  r := public.registrar_diaria(v_fav, v_hoje - 10, 'inteiro', null, null, 10, null, null, 'painel', v_dono);
  select ws.* into w from public.work_shifts ws where ws.id = (r ->> 'diaria_id')::uuid;
  insert into _resultado values ('A6b total menor que o almoco tira o almoco',
    w.almoco = 0 and w.extras = 10 and w.observacao is null, coalesce(w.observacao, '∅') || ' · ' || w.extras);

  -- A7. O lote aceita almoco por dia.
  r := public.registrar_diarias_em_lote(v_fav, jsonb_build_array(
         jsonb_build_object('data', v_hoje - 8, 'jornada', 'inteiro', 'almoco', true),
         jsonb_build_object('data', v_hoje - 7, 'jornada', 'inteiro')), 'agente', v_dono);
  select count(*) into v_n from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
   where wp.payee_id = v_fav and ws.data in (v_hoje - 8, v_hoje - 7) and ws.almoco = case when ws.data = v_hoje - 8 then v_alm else 0 end;
  insert into _resultado values ('A7 lote com almoco', v_n = 2, r::text);

  -- A8. O recibo não trava: nenhum dia com adicional fica sem motivo (a mesma regra de fechar_acerto_diarias).
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  select count(*) into v_n from jsonb_array_elements(c -> 'linhas') l
   where l ->> 'tipo' = 'dia' and coalesce((l ->> 'extras')::numeric, 0) > 0
     and nullif(btrim(coalesce(l ->> 'observacao', '')), '') is null;
  -- o dia de A6b (extra de 10 sem motivo, dito à mão) é o único que trava — de propósito: não é almoço
  insert into _resultado values ('A8 almoco nao trava o recibo', v_n = 1, v_n::text);

  -- A9. A conta corrente manda o almoço de cada dia (a tela de correção marca a caixa).
  select count(*) into v_n from jsonb_array_elements(c -> 'linhas') l
   where l ->> 'tipo' = 'dia' and (l ->> 'data')::date = v_hoje - 8 and (l ->> 'almoco')::numeric = v_alm;
  insert into _resultado values ('A9 conta corrente traz o almoco', v_n = 1, null);

  -- A10. Apagar devolve o almoço; o Desfazer recoloca igual.
  r := public.apagar_diaria((select ws.id from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
                              where wp.payee_id = v_fav and ws.data = v_hoje - 8), v_dono);
  insert into _resultado values ('A10 apagar devolve o almoco', (r -> 'apagado' ->> 'almoco')::numeric = v_alm, r ->> 'apagado');

  -- A11. Dia sem trabalho não tem almoço.
  begin
    perform public.registrar_diaria(v_fav, v_hoje - 6, 'faltou', null, null, null, null, null, 'painel', v_dono, true);
    insert into _resultado values ('A11 falta sem almoco', false, 'gravou');
  exception when others then
    insert into _resultado values ('A11 falta sem almoco', sqlerrm like 'Almoço é de quem trabalhou%', sqlerrm);
  end;

  -- A12. Sem a configuração, o banco recusa (não há valor escondido no código).
  delete from public.app_settings where key = 'diarias_valor_almoco';
  begin
    perform public.registrar_diaria(v_fav, v_hoje - 5, 'inteiro', null, null, null, null, null, 'painel', v_dono, true);
    insert into _resultado values ('A12 sem configuracao recusa', false, 'gravou');
  exception when others then
    insert into _resultado values ('A12 sem configuracao recusa', sqlerrm like 'O valor do almoço não está configurado%', sqlerrm);
  end;

  -- A13. Quem pode: a assinatura nova aberta só a quem entra; a antiga não existe mais; as internas fechadas.
  insert into _resultado values ('A13 permissoes',
    not has_function_privilege('anon', 'public.registrar_diaria(uuid, date, text, uuid[], text, numeric, numeric, numeric, text, uuid, boolean)', 'execute')
      and has_function_privilege('authenticated', 'public.registrar_diaria(uuid, date, text, uuid[], text, numeric, numeric, numeric, text, uuid, boolean)', 'execute')
      and to_regprocedure('public.registrar_diaria(uuid, date, text, uuid[], text, numeric, numeric, numeric, text, uuid)') is null
      and not has_function_privilege('authenticated', 'public._valor_do_almoco()', 'execute')
      and not has_function_privilege('anon', 'public._observacao_com_almoco(text, boolean)', 'execute'),
    null);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
