-- Agenda de Produção, Fase 7, etapa 7a ("ele marca sozinho"), pacote P6: a medição contra a estimativa — a OS que o gestor
-- marcou pela estimativa do orçamento passa a ser medida (o que levou de verdade × os dias que ele usou), com o fator dela à
-- parte, sem tocar no fator que o aprendizado usa.
-- Spec: scratchpad agenda-pesquisa/spec-fase7a.md (§R, §0 item 7, §1 "Medição", §3.1, §5.6, §8.4 M1–M6); nomes:
-- fase7-registro.md §1 (agenda_medidas_os.dias_fonte + orcamento, fator_orcamento, dp_no_inicio, dp_reais;
-- os_planejamento.dias_no_inicio_fonte + orcamento, dp_no_inicio) e §2 (a cadeia de _agenda_aprender_congelar e agenda_medir_os:
-- o 7e P2 copia DESTA migration). Depende da 20261031100000 (7a P1: as colunas e as listas) e da 20261031100100 (7a P2:
-- _agenda_gestor_estimativa).
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (3 funções recriadas; nenhuma nova; nenhuma tabela, coluna, lista, dado, cron ou tela muda)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7a/p6/montar-migration.mjs: as recriadas são o corpo
-- da definição MAIS NOVA (conferido a cada montagem em supabase/migrations, também nas 20261030* do lote e nas 20261031* do P1 ao
-- P5): _agenda_dias_no_inicio e _agenda_aprender_congelar de 20261029100100 (as únicas), agenda_medir_os de 20261029100900 (a
-- correção C1 da Fase 6). As mudanças estão só nos blocos "-- FASE 7: … -- FASE 7: fim"; fora deles nenhuma linha muda (o M6 de
-- supabase/tests/agenda_fase7a_medicao.sql confere).
--
-- POR QUE: a Fase 6 só mede contra os dias que o dono disse; a sugestão do banco não vale (dias_sugeridos). Com o gestor marcando
-- firme pela estimativa do orçamento (D7-1), a maior parte das OS deixaria de ser medida, e o 7e (o viés da estimativa) não teria
-- amostra. Ao mesmo tempo, o fator de campo aprendido está LIGADO em produção: ele não pode passar a ler a OS por estimativa (o
-- fator é "quanto o serviço passa do que o dono combinou", não "quanto passa da conta do orçamento").
--
-- O QUE MUDA:
--   1. _agenda_dias_no_inicio (o 4º passo, atrás do portão _agenda_gestor_regra('estimativa') com o modo marcar ligado de
--      verdade): sem dias ditos no dia do check-in, os que o gestor usou — a estimativa do orçamento naquele dia
--      (_agenda_gestor_estimativa, a mesma conta da fonte 'orcamento' de agenda_meios_da_os) → {dias, fonte: 'orcamento', em, dp:
--      as diárias-pessoa da estimativa, origem: 'estimativa'}, também na OS sem linha de planejamento. Em sombra (e dentro da
--      simulação da sombra), *gestor, só propor* ou sem a regra: nulo, como antes.
--   2. _agenda_aprender_congelar (o mesmo portão): congela também a fonte 'orcamento' (a estimativa do 4º passo e os dias que o
--      gestor gravou pelo prazo), uma vez, com dp_no_inicio (as diárias-pessoa estimadas; nulas nos dias gravados). A linha de
--      os_planejamento nasce se faltar (os dias de agora continuam nulos).
--   3. agenda_medir_os (sem portão; ver "correções"): dias_fonte 'orcamento' não é dias_sugeridos — a medida vale com os outros
--      critérios de sempre (concluída, check-in, conferência completa, diária ligada ou só o dono); fator := nulo e
--      fator_orcamento := os meios-dias reais ÷ (dias × 2) (o _agenda_aprender_fator, que lê fator, continua só com os dias do
--      dono: não é recriado); dp_no_inicio (o congelado ou o do 4º passo) e dp_reais (as diárias ligadas + os meios-dias de turno
--      do dono ÷ 2). O R$ por diária aprendido (_agenda_aprender_mo, que lê toda medida válida com diarista) passa a contar a OS
--      por estimativa: é o que ele mede.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7a_medicao.sql; registradas em notas-fase77a.md, P6):
--   · O 4º passo usa _agenda_gestor_estimativa no dia do check-in, não agenda_meios_da_os: é a mesma decisão (a fonte 'orcamento'
--     de agenda_meios_da_os sai dela) e ela já devolve as diárias-pessoa (dp), que agenda_meios_da_os não devolve.
--   · O portão do 4º passo e do congelar é a regra estimativa COM o modo marcar ligado (fora da simulação da sombra): a variável
--     agenda.gestor = 'sombra' liga as regras para simular o plano, nunca para gravar uma medida.
--   · O congelar cria a linha de os_planejamento que falta: o motor marca pela estimativa sem criar a linha (só a cria para a
--     sugestão aceita), e sem ela não há onde congelar.
--   · agenda_medir_os não tem portão: o dado 'orcamento' só existe se o gestor marcou pela estimativa (o congelado ou os dias
--     gravados pelo prazo); com o portão, desligar o gestor depois faria a definição de antes dar fator a essa OS, e o fator
--     aprendido (ligado) a leria. dp_no_inicio e dp_reais só na medida por estimativa: as medidas de antes não mudam de versão.
--   · A UPDATE da medida com as 3 colunas novas é repetida no bloco (a instrução de antes não ganha coluna sem mudar a linha); a de
--     antes continua para toda medida que nunca foi por estimativa.
--
-- O QUE NÃO MUDA: nenhuma tabela, coluna, lista, dado, cron, tela ou função de borda. A diária ligada à OS já nasce pela
-- conferência do dia quando há compromisso (_agenda_diaria_do_dia, 20261026100300): nada novo nela (o M5 prova com o Lenine). Com
-- o portão falso e sem medida por estimativa, as três saem como antes, byte a byte (o M7 confere com as definições de antes).
--
-- ORDEM DE LIGAR: depois de 20261031100400 (P5). Aplicar sozinha não muda nada (o portão é falso até o *ligar* do roteiro da §10
-- da spec; a regra sai sozinha tirando estimativa de marcar_regras).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7a_medicao.sql (begin/rollback; M0 a M7). Na bancada:
-- node scripts/bancada-agenda/rodar.mjs --ate 20261031100500
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261031100500_agenda_fase7a_medicao.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261031100500', 'agenda_fase7a_medicao');"
--
-- DESFAZER: sem migration, o portão (spec §10) para o 4º passo e o congelar; a medida por estimativa que já foi gravada fica (é
-- fato). Para tirar o código: recriar _agenda_dias_no_inicio e _agenda_aprender_congelar com o corpo de 20261029100100 e
-- agenda_medir_os com o de 20261029100900 (a cópia sem os blocos "-- FASE 7:") — antes disso, nenhuma OS por estimativa pode
-- ter medida (a definição de antes daria fator a ela).
--
-- IDEMPOTENTE: create or replace function, revoke e comment.

-- ── As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 7:") ──────────────────────────
-- Fora dos blocos nenhuma linha muda (o M6 de supabase/tests/agenda_fase7a_medicao.sql confere). Quem recriar de novo qualquer
-- uma delas copia DESTA migration (fase7-registro.md §2: _agenda_aprender_congelar e agenda_medir_os no 7e P2).

-- _agenda_dias_no_inicio (de 20261029100100_agenda_fase6_medicao.sql)
create or replace function public._agenda_dias_no_inicio(p_os uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  pl      public.os_planejamento;
  v_ci    date;
  v_dias  numeric;
  v_fonte text;
  v_desfez boolean := false;
  v_disse  boolean := false;
  e       jsonb;
  -- FASE 7: (7a P6) a estimativa do gestor no dia do check-in (o 4º passo)
  v_est   jsonb;
  -- FASE 7: fim
begin
  select (so.check_in_at at time zone 'America/Sao_Paulo')::date into v_ci from public.service_orders so where so.id = p_os;
  select * into pl from public.os_planejamento where service_order_id = p_os;
  if pl.dias_no_inicio is not null then
    return jsonb_build_object('dias', pl.dias_no_inicio, 'fonte', pl.dias_no_inicio_fonte, 'em', pl.dias_no_inicio_em,
                              'origem', 'coluna');
  end if;
  -- FASE 7: (7a P6, regra estimativa; D7-1) o 4º passo: sem dias ditos no dia do check-in, os que o gestor usou — a estimativa
  -- do orçamento no dia do check-in (_agenda_gestor_estimativa: a mesma conta da fonte 'orcamento' de agenda_meios_da_os), com
  -- as diárias-pessoa dela (dp). Só com o gestor ligado de verdade (a regra estimativa e o modo marcar ligado, fora da simulação
  -- da sombra): em sombra nada é marcado pela estimativa, e nada é congelado nem medido contra ela. Vale para a OS sem linha de
  -- planejamento (aqui) e para a de dias nulos no dia do check-in (o histórico, abaixo); a OS com dias ditos agora não tem
  -- estimativa (o motivo 'dito').
  if v_ci is not null and pl.dias is null
     and public._agenda_gestor_regra('estimativa') and public._agenda_gestor_modo('marcar') = 'ligado' then
    v_est := public._agenda_gestor_estimativa(p_os, v_ci);
    v_est := case when coalesce((v_est ->> 'usa')::boolean, false)
                  then jsonb_build_object('dias', (v_est ->> 'dias')::numeric, 'fonte', 'orcamento', 'em', v_ci,
                                          'dp', (v_est ->> 'dp')::numeric, 'origem', 'estimativa') end;
  end if;
  if v_est is not null and pl.service_order_id is null then
    return v_est;
  end if;
  -- FASE 7: fim
  if v_ci is null or pl.service_order_id is null then
    return null;
  end if;
  -- O estado do dia do check-in: o de agora, desfazendo (do mais novo ao mais velho) o que o planejar mudou DEPOIS dele.
  v_dias := pl.dias;
  v_fonte := pl.estimativa_fonte;
  for e in select x from jsonb_array_elements(pl.historico) with ordinality t(x, o) order by o desc loop
    continue when coalesce(e ->> 'em', '') !~ '^\d{4}-\d{2}-\d{2}';
    if left(e ->> 'em', 10)::date > v_ci then
      if coalesce(e -> 'antes', '{}'::jsonb) ? 'dias' then
        v_dias := (e #>> '{antes,dias}')::numeric;
        v_desfez := true;
      end if;
      if coalesce(e -> 'antes', '{}'::jsonb) ? 'estimativa_fonte' then
        v_fonte := e #>> '{antes,estimativa_fonte}';
      end if;
    elsif coalesce(e -> 'depois', '{}'::jsonb) ? 'dias' then
      v_disse := true;
    end if;
  end loop;
  -- FASE 7: (7a P6) sem dias no dia do check-in (o de agora, desfeito o que mudou depois, é nulo): a estimativa do gestor, se ele
  -- a usava
  if v_dias is null and v_est is not null then
    return v_est;
  end if;
  -- FASE 7: fim
  if v_dias is null or v_fonte is null then
    return null;
  end if;
  if v_desfez or v_disse then
    return jsonb_build_object('dias', v_dias, 'fonte', v_fonte, 'em', v_ci, 'origem', 'historico');
  end if;
  -- Sem rastro no histórico (o dono disse antes do histórico existir, ou por outro caminho): os dias de agora, se foram
  -- ditos até o dia do check-in.
  if pl.estimativa_em is not null and (pl.estimativa_em at time zone 'America/Sao_Paulo')::date <= v_ci then
    return jsonb_build_object('dias', v_dias, 'fonte', v_fonte, 'em', v_ci, 'origem', 'atual');
  end if;
  return null;
end;
$function$;

comment on function public._agenda_dias_no_inicio(uuid) is
  'Agenda de Produção (Fase 6): os dias que o dono disse (ou aceitou) até o dia do check-in — {dias, fonte, em, origem}: a coluna os_planejamento.dias_no_inicio (origem coluna); senão o estado do dia do check-in reconstruído do histórico do planejar, desfazendo o que mudou depois (historico); senão os dias de agora, se estimativa_em ≤ o check-in (atual); senão nulo. A sugestão do banco nunca entra (estimativa_fonte só é dono ou aceita). FASE 7 (7a P6, D7-1): o 4º passo, só com o gestor ligado de verdade (o portão _agenda_gestor_regra(''estimativa'') e _agenda_gestor_modo(''marcar'') = ''ligado'', fora da simulação da sombra): sem dias no dia do check-in (também na OS sem linha de planejamento), os que o gestor usou — a estimativa do orçamento naquele dia (_agenda_gestor_estimativa usa) → {dias, fonte: orcamento, em: o check-in, dp: as diárias-pessoa da estimativa, origem: estimativa}. A OS com dias ditos agora não tem estimativa. Os dias que o gestor GRAVOU pelo prazo (estimativa_fonte orcamento) saem pelos passos de antes, com a fonte orcamento e sem dp. Sem o portão, nulo, como antes.';

-- _agenda_aprender_congelar (de 20261029100100_agenda_fase6_medicao.sql)
create or replace function public._agenda_aprender_congelar(p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c   public.agenda_config := public._agenda_cfg();
  r   record;
  v   jsonb;
  n_c int := 0;
  n_s int := 0;
  -- FASE 7: (7a P6) a fonte orcamento só com o gestor ligado de verdade (a regra estimativa e o modo marcar ligado, fora da
  -- simulação da sombra)
  v_gestor boolean := public._agenda_gestor_regra('estimativa') and public._agenda_gestor_modo('marcar') = 'ligado';
  -- FASE 7: fim
begin
  if p_hoje is null then
    raise exception 'Falta o dia (p_hoje).' using errcode = '22023';
  end if;
  for r in
    select so.id as os, pl.service_order_id as tem_plano, pl.dias_no_inicio
      from public.service_orders so
      left join public.os_planejamento pl on pl.service_order_id = so.id
     where so.check_in_at is not null and so.merged_into_id is null
       and (so.check_in_at at time zone 'America/Sao_Paulo')::date between p_hoje - c.aprender_janela_dias and p_hoje
       and pl.dias_no_inicio is null
     order by so.check_in_at, so.id
  loop
    v := case when r.tem_plano is not null then public._agenda_dias_no_inicio(r.os) end;
    -- FASE 7: (7a P6) a fonte orcamento — a estimativa que o gestor usou (o 4º passo de _agenda_dias_no_inicio, também na OS sem
    -- linha de planejamento) ou os dias que ele gravou quando a pergunta com prazo venceu — congela uma vez, com as
    -- diárias-pessoa estimadas (dp_no_inicio; nulas nos dias gravados). A linha de planejamento nasce se faltar (os dias de
    -- agora continuam nulos: só os do início). Só com o gestor ligado de verdade; sem ele, a fonte orcamento não congela, como
    -- antes.
    if v_gestor then
      if r.tem_plano is null then
        v := public._agenda_dias_no_inicio(r.os);
      end if;
      if v ->> 'fonte' = 'orcamento' then
        insert into public.os_planejamento as x (service_order_id, dias_no_inicio, dias_no_inicio_fonte, dias_no_inicio_em,
                                                 dp_no_inicio)
        values (r.os, (v ->> 'dias')::numeric, 'orcamento', (v ->> 'em')::date, (v ->> 'dp')::numeric)
        on conflict (service_order_id) do update
          set dias_no_inicio = excluded.dias_no_inicio, dias_no_inicio_fonte = excluded.dias_no_inicio_fonte,
              dias_no_inicio_em = excluded.dias_no_inicio_em, dp_no_inicio = excluded.dp_no_inicio
          where x.dias_no_inicio is null;
        n_c := n_c + 1;
        continue;
      end if;
    end if;
    -- FASE 7: fim
    if v is null or coalesce(v ->> 'fonte', '') not in ('dono', 'aceita') then
      n_s := n_s + 1;
      continue;
    end if;
    update public.os_planejamento
       set dias_no_inicio = (v ->> 'dias')::numeric, dias_no_inicio_fonte = v ->> 'fonte',
           dias_no_inicio_em = (v ->> 'em')::date
     where service_order_id = r.os and dias_no_inicio is null;
    n_c := n_c + 1;
  end loop;
  return jsonb_build_object('congeladas', n_c, 'sem_dias', n_s);
end;
$function$;

comment on function public._agenda_aprender_congelar(date) is
  'Agenda de Produção (Fase 6): a rodada do aprendizado congela, uma vez, os dias ditos no início — toda OS com check-in até p_hoje (na janela aprender_janela_dias) e sem os_planejamento.dias_no_inicio recebe o de _agenda_dias_no_inicio (só fonte dono ou aceita; a sugestão do banco nunca). {congeladas, sem_dias}. Definer, sem grant a ninguém. FASE 7 (7a P6): com o gestor ligado de verdade (a regra estimativa e o modo marcar ligado, fora da simulação da sombra), congela também a fonte orcamento — a estimativa que o gestor usou no dia do check-in (o 4º passo de _agenda_dias_no_inicio, também na OS sem linha de planejamento) e os dias que ele gravou pelo prazo —, uma vez, com dp_no_inicio (as diárias-pessoa estimadas; nulas nos dias gravados); a linha de os_planejamento nasce se faltar (os dias de agora continuam nulos). Conta em congeladas. Sem o portão, a fonte orcamento não congela (sem_dias), como antes.';

-- agenda_medir_os (de 20261029100900_agenda_fase6_correcao_calculo.sql)
create or replace function public.agenda_medir_os(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  so      public.service_orders;
  pl      public.os_planejamento;
  m0      public.agenda_medidas_os;
  m       public.agenda_medidas_os;
  v_concl boolean;
  v_cls   jsonb;
  v_d     jsonb;
  v_sug   jsonb;
  v_dono  uuid := public._agenda_dono();
  v_aloc  int;
  v_doaloc int;
  v_meios numeric;
  v_novo  jsonb;
  v_velho jsonb;
  v_antes jsonb := '{}'::jsonb;
  v_depois jsonb := '{}'::jsonb;
  v_hist  jsonb;
  k       text;
  -- CORREÇÃO FASE 6: (C1) itens 4 e 9: o dia da conclusão pela porta e o fim da faixa do aviso sem a folga
  v_fim   date;
  v_plano date;
  -- CORREÇÃO FASE 6: fim
  -- FASE 7: (7a P6) os meios-dias de turno do dono na OS por estimativa (para as diárias-pessoa reais)
  v_dono_meios numeric;
  -- FASE 7: fim
begin
  if p_os is null or p_hoje is null then
    raise exception 'Falta a OS ou o dia.' using errcode = '22023';
  end if;
  select * into so from public.service_orders where id = p_os;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'nao_achei');
  end if;
  select * into m0 from public.agenda_medidas_os where service_order_id = p_os for update;
  v_concl := so.status in ('completed', 'invoiced') and so.merged_into_id is null;
  if not v_concl and m0.service_order_id is null then
    return jsonb_build_object('ok', true, 'medida', false, 'motivo', 'nao_concluida');
  end if;
  select * into pl from public.os_planejamento where service_order_id = p_os;
  v_sug := public.os_duracao_sugerida(p_os);

  m.service_order_id := p_os;
  v_cls := public._agenda_classe_de_campo(p_os);
  m.classe_bem := v_cls ->> 'bem';
  m.classe_sistema := v_cls ->> 'sistema';
  m.concluida_em := case when v_concl then (coalesce(so.check_out_at, so.updated_at) at time zone 'America/Sao_Paulo')::date
                         else m0.concluida_em end;
  -- CORREÇÃO FASE 6: (C1) item 9: a conclusão é o check-out, senão o 1º instante em que a porta deixou a OS concluída
  -- (_agenda_concluida_em); nunca a última edição (faturar, pagar ou entregar a moveriam). Sem nenhum dos dois, a medida não
  -- vale (sem_fim, abaixo) e a data fica a que já estava medida (senão a da última edição, só para a linha ter onde ficar):
  -- tocar a OS não move a conclusão.
  if v_concl then
    v_fim := public._agenda_concluida_em(p_os);
    m.concluida_em := coalesce(v_fim, m0.concluida_em, m.concluida_em);
  end if;
  -- CORREÇÃO FASE 6: fim
  m.entregue_em := (so.delivered_at at time zone 'America/Sao_Paulo')::date;

  -- Os dias: os ditos até o check-in; senão a duração sugerida (a medida não vale).
  v_d := case when pl.dias_no_inicio is not null
              then jsonb_build_object('dias', pl.dias_no_inicio, 'fonte', pl.dias_no_inicio_fonte)
              else public._agenda_dias_no_inicio(p_os) end;
  if v_d is null and not coalesce((v_sug ->> 'sem_base')::boolean, true) and (v_sug ->> 'sugerida') is not null then
    v_d := jsonb_build_object('dias', (v_sug ->> 'sugerida')::numeric, 'fonte', 'sugerida');
  end if;
  m.dias_no_inicio := (v_d ->> 'dias')::numeric;
  m.dias_fonte := v_d ->> 'fonte';
  m.meios_planejados := (m.dias_no_inicio * 2)::smallint;

  -- Os meios-dias que aconteceram: (dia, turno) distintos das alocações vigentes não reserva da presença "turno" até a
  -- conclusão (cumprido 1, parcial meio, o resto 0; o melhor das pessoas daquele meio-dia).
  select coalesce(sum(x.valor), 0) into v_meios
    from (select a.dia, a.turno,
                 max(case a.resultado when 'cumprido' then 1 when 'parcial' then 0.5 else 0 end) as valor
            from public.agenda_alocacoes a
           where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
             and a.presenca = 'turno' and a.dia <= m.concluida_em
           group by a.dia, a.turno) x;
  select count(*)::int,
         count(*) filter (where a.payee_id = v_dono)::int,
         count(*) filter (where a.presenca = 'turno' and (a.resultado is null or a.resultado = 'sem_registro'))::smallint
    into v_aloc, v_doaloc, m.meios_sem_registro
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
     and a.dia <= m.concluida_em;
  m.so_o_dono := v_aloc > 0 and v_aloc = v_doaloc;

  -- As diárias ligadas à OS em dia sem alocação dela (a fração daquele dia na OS: 1 = 2 meios, meia = 1).
  select coalesce(sum(greatest(1, round(x.f * 2))), 0)::smallint into m.meios_fora_do_plano
    from (select ws.data, max(ws.fracao / (select count(*) from public.work_shift_os w2 where w2.shift_id = ws.id)) as f
            from public.work_shift_os wo
            join public.work_shifts ws on ws.id = wo.shift_id
            join public.work_profiles wp on wp.id = ws.work_profile_id
            join public.payees p on p.id = wp.payee_id
           where wo.service_order_id = p_os and ws.fracao > 0 and wp.modo_pagamento = 'diaria'
             and p.kind is distinct from 'socio' and ws.data <= m.concluida_em
             and not exists (select 1 from public.agenda_alocacoes a
                              where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                                and a.dia = ws.data)
           group by ws.data) x;
  m.meios_cumpridos := v_meios + m.meios_fora_do_plano;
  select coalesce(sum(v.dias), 0) into m.diarias_ligadas from public.v_dias_por_os_e_pessoa v where v.service_order_id = p_os;
  m.mo := (v_sug ->> 'mo')::numeric;

  m.motivo := case
    when not v_concl then 'reaberta'
    when so.check_in_at is null then 'sem_inicio'
    when m.dias_no_inicio is null then 'sem_dias_no_inicio'
    when m.dias_fonte = 'sugerida' then 'dias_sugeridos'
    when v_aloc = 0 and m.diarias_ligadas = 0 then 'sem_plano'
    when m.meios_sem_registro > 0 then 'conferencia_incompleta'
    when m.diarias_ligadas = 0 and not m.so_o_dono then 'sem_diaria'
  end;
  -- CORREÇÃO FASE 6: (C1) item 9: sem o dia da conclusão, a medida não vale (sem_fim) — depois do sem check-in (a OS que nem
  -- começou diz isso primeiro), antes do resto
  if v_concl and v_fim is null and m.motivo is distinct from 'sem_inicio' then
    m.motivo := 'sem_fim';
  end if;
  -- CORREÇÃO FASE 6: fim
  m.valida := m.motivo is null;
  m.fator := case when m.valida and m.meios_planejados > 0
                  then least(round(m.meios_cumpridos / m.meios_planejados, 2), 99) end;
  -- FASE 7: (7a P6) a medida contra a estimativa do gestor (dias_fonte orcamento) vale como as outras (concluída, com check-in,
  -- a conferência completa, a diária ligada ou só o dono), mas o fator dela fica à parte, em fator_orcamento: o aprendizado do
  -- fator (que lê fator) continua só com os dias do dono. Sem portão: o dado orcamento só existe se o gestor marcou pela
  -- estimativa, e tratá-lo sempre assim protege o fator aprendido (ligado em produção) quando o gestor é desligado depois. As
  -- diárias-pessoa: as estimadas no check-in (dp_no_inicio, congeladas com os dias) e as reais (dp_reais: as diárias ligadas +
  -- os meios-dias de turno do dono ÷ 2; cumprido 1, parcial meio).
  if m.dias_fonte = 'orcamento' then
    m.fator_orcamento := m.fator;
    m.fator := null;
    m.dp_no_inicio := coalesce(pl.dp_no_inicio, (v_d ->> 'dp')::numeric);
    select coalesce(sum(case a.resultado when 'cumprido' then 1 when 'parcial' then 0.5 else 0 end), 0) into v_dono_meios
      from public.agenda_alocacoes a
     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       and a.presenca = 'turno' and a.payee_id = v_dono and a.dia <= m.concluida_em;
    m.dp_reais := round(m.diarias_ligadas + v_dono_meios / 2, 2);
  end if;
  -- FASE 7: fim

  -- O cliente: a 1ª promessa contra a conclusão; os avisos de atraso que saíram e o fim da faixa do último.
  m.prometido_primeiro_ate := coalesce(pl.prometido_primeiro_ate, pl.prometido_original_ate);
  m.atraso_cliente_du := public.agenda_du_entre(m.prometido_primeiro_ate, m.concluida_em);
  select count(*)::smallint into m.avisos_enviados
    from public.agenda_cliente_mensagens x
   where x.service_order_id = p_os and x.tipo in ('pode_atrasar', 'nova_data') and x.modo = 'ligado' and x.enviada_em is not null;
  select coalesce(x.faixa_ate, case when x.variante is distinct from 'peca_sem_data' then x.dia_alvo end) into m.aviso_faixa_ate
    from public.agenda_cliente_mensagens x
   where x.service_order_id = p_os and x.tipo = 'pode_atrasar' and x.modo = 'ligado' and x.enviada_em is not null
     and coalesce(x.faixa_ate, case when x.variante is distinct from 'peca_sem_data' then x.dia_alvo end) is not null
   order by x.enviada_em desc, x.id desc
   limit 1;
  -- CORREÇÃO FASE 6: (C1) item 4: o fim da faixa do último aviso SEM a folga do aprendizado (base.dados.faixa_ate_plano, que o
  -- registro grava quando a folga estava em uso); a mensagem de antes da correção não tem, e vale o faixa_ate dela. Assim a
  -- folga mede o erro do PLANO, não o dela mesma.
  select (x.base #>> '{dados,faixa_ate_plano}')::date into v_plano
    from public.agenda_cliente_mensagens x
   where x.service_order_id = p_os and x.tipo = 'pode_atrasar' and x.modo = 'ligado' and x.enviada_em is not null
     and coalesce(x.faixa_ate, case when x.variante is distinct from 'peca_sem_data' then x.dia_alvo end) is not null
   order by x.enviada_em desc, x.id desc
   limit 1;
  m.aviso_faixa_ate := coalesce(v_plano, m.aviso_faixa_ate);
  -- CORREÇÃO FASE 6: fim
  m.aviso_estouro_du := public.agenda_du_entre(m.aviso_faixa_ate, m.concluida_em);

  -- Grava só quando muda.
  m.medida_em := now();
  v_novo := to_jsonb(m) - array['medida_em', 'versao', 'historico'];
  if m0.service_order_id is null then
    m.versao := 1;
    m.historico := '[]'::jsonb;
    insert into public.agenda_medidas_os select (m).*;
    return jsonb_build_object('ok', true, 'medida', true, 'nova', true, 'mudou', true, 'versao', 1, 'valida', m.valida,
                              'motivo', m.motivo, 'fator', m.fator, 'chave', v_cls ->> 'chave');
  end if;
  v_velho := to_jsonb(m0) - array['medida_em', 'versao', 'historico'];
  if v_novo = v_velho then
    return jsonb_build_object('ok', true, 'medida', true, 'nova', false, 'mudou', false, 'versao', m0.versao, 'valida', m0.valida,
                              'motivo', m0.motivo, 'fator', m0.fator, 'chave', v_cls ->> 'chave');
  end if;
  for k in select key from jsonb_each(v_novo) loop
    if v_novo -> k is distinct from v_velho -> k then
      v_antes := v_antes || jsonb_build_object(k, v_velho -> k);
      v_depois := v_depois || jsonb_build_object(k, v_novo -> k);
    end if;
  end loop;
  v_hist := m0.historico || jsonb_build_array(jsonb_build_object('em', p_hoje, 'versao', m0.versao,
                                                                  'antes', v_antes, 'depois', v_depois));
  if jsonb_array_length(v_hist) > 20 then
    select jsonb_agg(x order by o) into v_hist
      from jsonb_array_elements(v_hist) with ordinality t(x, o) where o > jsonb_array_length(v_hist) - 20;
  end if;
  -- FASE 7: (7a P6) a medida por estimativa (ou que era) grava também fator_orcamento, dp_no_inicio e dp_reais: a mesma
  -- instrução de baixo com as 3 colunas (a de baixo continua para as outras, byte a byte)
  if m.dias_fonte = 'orcamento' or m0.dias_fonte = 'orcamento'
     or coalesce(m0.fator_orcamento, m0.dp_no_inicio, m0.dp_reais) is not null then
    update public.agenda_medidas_os
       set classe_bem = m.classe_bem, classe_sistema = m.classe_sistema, concluida_em = m.concluida_em,
           entregue_em = m.entregue_em, dias_no_inicio = m.dias_no_inicio, dias_fonte = m.dias_fonte,
           meios_planejados = m.meios_planejados, meios_cumpridos = m.meios_cumpridos,
           meios_fora_do_plano = m.meios_fora_do_plano, meios_sem_registro = m.meios_sem_registro,
           diarias_ligadas = m.diarias_ligadas, so_o_dono = m.so_o_dono, mo = m.mo, fator = m.fator, valida = m.valida,
           motivo = m.motivo, prometido_primeiro_ate = m.prometido_primeiro_ate, atraso_cliente_du = m.atraso_cliente_du,
           avisos_enviados = m.avisos_enviados, aviso_faixa_ate = m.aviso_faixa_ate, aviso_estouro_du = m.aviso_estouro_du,
           fator_orcamento = m.fator_orcamento, dp_no_inicio = m.dp_no_inicio, dp_reais = m.dp_reais,
           medida_em = m.medida_em, versao = m0.versao + 1, historico = v_hist
     where service_order_id = p_os;
    return jsonb_build_object('ok', true, 'medida', true, 'nova', false, 'mudou', true, 'versao', m0.versao + 1,
                              'valida', m.valida, 'motivo', m.motivo, 'fator', m.fator, 'chave', v_cls ->> 'chave');
  end if;
  -- FASE 7: fim
  update public.agenda_medidas_os
     set classe_bem = m.classe_bem, classe_sistema = m.classe_sistema, concluida_em = m.concluida_em,
         entregue_em = m.entregue_em, dias_no_inicio = m.dias_no_inicio, dias_fonte = m.dias_fonte,
         meios_planejados = m.meios_planejados, meios_cumpridos = m.meios_cumpridos,
         meios_fora_do_plano = m.meios_fora_do_plano, meios_sem_registro = m.meios_sem_registro,
         diarias_ligadas = m.diarias_ligadas, so_o_dono = m.so_o_dono, mo = m.mo, fator = m.fator, valida = m.valida,
         motivo = m.motivo, prometido_primeiro_ate = m.prometido_primeiro_ate, atraso_cliente_du = m.atraso_cliente_du,
         avisos_enviados = m.avisos_enviados, aviso_faixa_ate = m.aviso_faixa_ate, aviso_estouro_du = m.aviso_estouro_du,
         medida_em = m.medida_em, versao = m0.versao + 1, historico = v_hist
   where service_order_id = p_os;
  return jsonb_build_object('ok', true, 'medida', true, 'nova', false, 'mudou', true, 'versao', m0.versao + 1,
                            'valida', m.valida, 'motivo', m.motivo, 'fator', m.fator, 'chave', v_cls ->> 'chave');
end;
$function$;

comment on function public.agenda_medir_os(uuid, date) is
  'Agenda de Produção (Fase 6): a medida da OS concluída (spec-fase6 §3.1, itens 5 e 6) em agenda_medidas_os — a classe, os dias ditos no início (senão a sugerida: não vale), os meios-dias planejados e os que aconteceram, as diárias ligadas, se é só do dono, a mão de obra, o fator (só a válida), o motivo da inválida, a 1ª promessa ao cliente contra a conclusão e o último aviso de atraso. Grava só quando muda (versao + 1 e o que mudou no histórico). A OS que voltou de concluída fica inválida (reaberta). Definer, sem grant a ninguém. CORREÇÃO FASE 6 (C1): (item 9) a conclusão é o check-out, senão o 1º instante em que a porta deixou a OS concluída (_agenda_concluida_em); sem nenhum dos dois, motivo sem_fim (não vale) e a data fica a já medida; (item 4) o fim da faixa do último aviso é o base.dados.faixa_ate_plano (sem a folga do aprendizado), quando a mensagem o tem. FASE 7 (7a P6, sem portão): a medida contra a estimativa do gestor (dias_fonte orcamento: os dias congelados ou os de _agenda_dias_no_inicio) não é dias_sugeridos — vale com os critérios de sempre; o fator dela fica à parte (fator := nulo; fator_orcamento := os meios-dias reais ÷ (dias × 2), só na válida), e o aprendizado do fator, que lê fator, continua só com os dias do dono; dp_no_inicio (o congelado, senão o do 4º passo) e dp_reais (as diárias ligadas + os meios-dias de turno do dono ÷ 2) só na medida por estimativa. O R$ por diária aprendido passa a contar a OS por estimativa válida com diarista. As outras medidas, byte a byte as de antes.';

-- ── Portas ─────────────────────────────────────────────────────────────────────────────────────────────────────
-- As recriadas mantêm as portas de antes (create or replace não muda a ACL; repetidas aqui para a migration valer sozinha): as
-- três são internas da rodada do aprendizado (agenda_aprender, definer) — sem grant a ninguém, nem service_role. Nunca anon.
revoke all on function
  public._agenda_dias_no_inicio(uuid),
  public._agenda_aprender_congelar(date),
  public.agenda_medir_os(uuid, date)
  from public, anon, authenticated, service_role;
