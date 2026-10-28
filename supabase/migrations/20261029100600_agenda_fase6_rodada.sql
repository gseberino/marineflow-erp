-- Agenda de Produção, Fase 6 ("Aprendizado"), pacote P6: a rodada do aprendizado, a decisão do dono, o *desfaz aprendizado*,
-- a saúde, a revisão da carga pelo plano cumprido e os gatilhos de um planejador mais forte.
-- Spec: scratchpad agenda-pesquisa/spec-fase6.md (§3.1 itens 9, 10 e 12, §3.2, §5.6, §5.9, §6.2, §6.3, §8.3 R1–R8, §10, §11).
-- Depende de 20261029100500.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (6 funções novas; 5 recriadas; nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f6p6/montar-migration.mjs (as partes escritas à mão
-- f6p6/parte-0-cabeca.sql, parte-1-novas.sql e parte-9-portas.sql + as 5 recriadas, cada uma com o corpo da definição MAIS
-- NOVA, conferida com grep a cada montagem: fora dos blocos "-- FASE 6:" nenhuma linha muda). Edite o montador, nunca este .sql.
--
-- POR QUE: os pacotes P1 a P5 mediram e calcularam, mas nada os chamava. Este pacote liga tudo: uma rodada por dia mede as OS
-- concluídas (em qualquer modo, até desligado) e, fora de desligado, recalcula cada valor aprendido pelo gravador único; o dono
-- decide as trocas grandes pelas perguntas de sempre e desfaz o que entrou sozinho com *desfaz aprendizado*; a saúde mostra os
-- zeros do aprendizado. E traz os dois itens que só perguntam: a carga de cada pessoa pelo plano cumprido (a 1ª escrita de
-- parâmetro feita por função — só pela opção 1 da pergunta, com *desfaz*) e os gatilhos de um planejador mais forte (um aviso
-- só, uma vez).
--
-- O QUE MUDA:
--   1. agenda_aprender(hoje, agora) (definer, só service_role; o passo TS do P8 a chama a cada tique): uma vez por dia, no 1º
--      tique a partir de aprender_hora (antes = {rodou: false, cedo}; o 2º do dia = {rodou: false, ja_rodou}). Os passos, cada
--      um no seu bloco (o que falha vai a app_error_logs, context agenda, action aprender:<passo>, e os outros seguem):
--        (1) SEMPRE, em qualquer modo: congelar (os dias ditos no início) e medir (as OS concluídas);
--        (2) com modo_aprendizado fora de desligado: fator, mo, presenca, fornecedor, capacidade, cliente;
--        (3) com o modo fora de desligado E no dia_do_plano: revisao e solver.
--      Grava uma linha em agenda_vigia_rodadas (rotina aprender; contagens com o modo, a lista, cada passo e as falhas) e
--      devolve {rodou, modo, ligados, semanal, contagens, erros, falhas}. Nada de mensagem a ninguém.
--   2. _agenda_aprender_revisao(hoje, agora): o plano cumprido (agenda_ppc) das revisao_semanas semanas completas antes de hoje;
--      ppc_baixo_semanas seguidas (a partir da última) abaixo de ppc_baixo → item carga, chave todas, calculado =
--      least(carga_max, carga_ppc_baixo); ppc_alto_semanas seguidas acima de ppc_alto → greatest(carga_max, carga_ppc_alto);
--      senão carga_max. Pelo gravador (padrão = carga_max): a carga nunca entra sozinha, sempre pergunta (com revisao ligado).
--   3. _agenda_aprender_solver(hoje, agora): os 4 gatilhos da semana completa anterior (OS ativas > solver_os_ativas; pessoas
--      no plano > solver_pessoas; presenças curtas do dono por dia útil > solver_curtas_dia; planos sugeridos descartados ÷
--      (aplicados + descartados) > solver_descarte_pct; a habilidade escassa não é medível), guardados semana a semana na
--      amostra. calculado = 1 quando as solver_semanas semanas seguidas mais novas têm ≥ solver_gatilhos_min gatilhos, senão 0;
--      n = as semanas seguidas medidas. Pergunta UMA VEZ (com revisao ligado): depois da 1ª pergunta, o passo nunca mais deixa
--      o gravador perguntar.
--   4. _agenda_aprendizado_decidir (definer, sem grant; agenda_decidir a chama): a resposta à pergunta "aprendizado".
--      1 = o medido passa a valer (em_uso; a carga também muda agenda_config.carga_max) e uma ação crítica "aprendizado"
--      (origem dono, desfazível por desfazer_validade; o planejador mais forte só anota, sem ação); 2 = trava (travado_valor =
--      o medido; o que vale continua); 3 = volta ao padrão (em_uso nulo) E trava, com a ação desfazível.
--   5. _agenda_desfazer_aprendizado (definer, sem grant; agenda_desfazer a chama): volta o em_uso de antes (nulo = o padrão) e
--      trava a chave por aprender_trava_dias (travado_valor = o medido recusado); a da carga volta carga_max (só se ainda é o
--      que a decisão gravou). A ação desfazer e o desfeita_* na original.
--   6. _agenda_aprendizado_carga(de, para, autor, agora) (definer, sem grant): o ÚNICO caminho que escreve parâmetro —
--      update agenda_config set carga_max = para where carga_max = de. Só _agenda_aprendizado_decidir (opção 1 da pergunta da
--      carga) e _agenda_desfazer_aprendizado (o *desfaz* daquela ação) a chamam; o montador e o R4 de
--      supabase/tests/agenda_fase6_rodada.sql provam que nenhuma outra função escreve em agenda_config (só o versao_plano do
--      gatilho das alocações, da Fase 2).
--   7. Recriadas (o corpo da definição mais nova + blocos "-- FASE 6:"):
--      · agenda_decidir (de 20261028100300): o tipo aprendizado vai a _agenda_aprendizado_decidir;
--      · agenda_desfazer (de 20261028100400): o tipo aprendizado vai a _agenda_desfazer_aprendizado;
--      · agenda_desfazer_dito (de 20261025100300): o alvo "aprendizado" = o último lote de ações "aprendizado" desfazíveis (as
--        do mesmo instante: o que a mesma rodada ou a mesma decisão mudou), tudo ou nada;
--      · agenda_saude (de 20261028100300): o bloco aprendizado (os zeros entram no ok, como os das Fases 4 e 5);
--      · _agenda_aprendizado_texto (de 20261029100500): os textos da carga e do planejador mais forte (spec §6.2/§6.3).
--
-- DESVIOS DA SPEC (provados em supabase/tests/agenda_fase6_rodada.sql):
--   · Os passos recebem p_agora (como P2 a P5); a revisão e o solver só rodam no dia_do_plano pela rodada (chamados direto,
--     rodam em qualquer dia: os testes os chamam assim).
--   · A opção 3 também trava a chave (a nota do P1): com o modo ligado, o medido ≠ padrão voltaria a perguntar no dia seguinte.
--   · As opções 1 e 3 geram a ação crítica desfazível (não só a da carga); a 2 não muda nada e não gera ação.
--   · *desfaz aprendizado* desfaz o último LOTE (as ações aprendizado desfazíveis do mesmo instante), não uma ação só: a rodada
--     grava várias no mesmo p_agora (o fator muda 4 chaves de uma vez) e "a última" seria um sorteio. Tudo ou nada.
--   · A carga recomendada nunca anda contra o sinal: o plano pouco cumprido nunca sobe a carga (least) e o muito cumprido nunca
--     a baixa (greatest).
--   · O solver: "pessoas na grade" = as pessoas com meio-dia vigente (não reserva) na semana; a semana medida é a completa
--     anterior a hoje; as OS ativas são as da carteira de hoje (a carteira de antes não se reconstrói). A habilidade escassa
--     fica "nao_medivel" no detalhe.
--   · A saúde: rodada_atrasada só conta depois da 1ª rodada (antes do passo TS do P8 não há rodada nenhuma);
--     em_uso_fora_de_ligado olha o que a ÚLTIMA rodada gravou contra o modo e a lista DELA (logo depois de o dono desligar, as
--     linhas ainda em uso até a rodada seguinte não acusam: o leitor _agenda_aprendido já devolve nulo na hora);
--     troca_grande_sem_pergunta olha as ações "aprendizado" da vigia em 7 dias contra os limites de hoje. Os erros de
--     aprender:% em 24 h aparecem, mas não reprovam (como erros_24h das outras rodadas).
--
-- O QUE NÃO MUDA: nenhuma mensagem nova a terceiros (o montador recusa escrita em fila de mensagem); nenhum parâmetro muda
-- sozinho (a carga só pela opção 1, com *desfaz*); o que já está publicado (o aprendido vale da próxima proposta em diante). Com
-- o modo fora de ligado, nada do que o motor, a vigia, a prontidão e a rodada do cliente leem muda (o R1 compara antes e
-- depois da rodada). Os textos e as decisões de antes de agenda_decidir, agenda_desfazer, agenda_desfazer_dito e
-- agenda_saude ficam como estavam (o R8 confere as cópias).
--
-- ORDEM DE LIGAR: depois de 20261029100500; antes de 20261029100700. Aplicar sozinha não muda nada para ninguém: nada chama a
-- rodada até o passo TS do P8 (task-automations/agenda-aprender.ts) ser publicado; a decisão e o *desfaz* só alcançam as
-- perguntas e as ações "aprendizado", que só a rodada cria.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase6_rodada.sql (a fixture-fase6 só na bancada; as portas e as cópias em
-- qualquer lugar). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261029100600
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261029100600_agenda_fase6_rodada.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261029100600', 'agenda_fase6_rodada');"
--
-- DESFAZER: reaplicar, em ordem, as definições de 20261025100300 (agenda_desfazer_dito), 20261028100300 (agenda_decidir e
-- agenda_saude), 20261028100400 (agenda_desfazer) e 20261029100500 (_agenda_aprendizado_texto); as novas podem ficar (ninguém de
-- antes as chama). A carga que o dono aceitou pela pergunta volta pelo *desfaz* ou por update agenda_config set carga_max = <o
-- valor de antes> (está em agenda_acoes.antes.carga_max da ação).
--
-- IDEMPOTENTE: create or replace function; revoke/grant.

-- ── 1. A revisão da carga pelo plano cumprido ───────────────────────────────────────────────────────────
-- O plano cumprido (agenda_ppc: os dias de serviço publicados antes do dia e conferidos) das revisao_semanas semanas
-- completas antes de hoje, a mais nova primeiro. As seguidas a partir da mais nova: abaixo de ppc_baixo por
-- ppc_baixo_semanas → recomenda carga_ppc_baixo (nunca acima da de hoje); acima de ppc_alto por ppc_alto_semanas → recomenda
-- carga_ppc_alto (nunca abaixo da de hoje); senão a de hoje. A semana sem nada conferido corta a sequência. Escreve só pelo
-- gravador (item carga, chave todas, padrão = carga_max): a carga nunca entra sozinha (_agenda_aprendizado_troca_cabe), e a
-- troca só acontece pela opção 1 da pergunta (_agenda_aprendizado_decidir).
create or replace function public._agenda_aprender_revisao(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c         public.agenda_config := public._agenda_cfg();
  v_seg     date;
  v_s       date;
  v_p       numeric;
  v_sem     jsonb := '[]'::jsonb;
  v_amos    jsonb := '[]'::jsonb;
  v_n       int := 0;
  v_baixo   int := 0;
  v_alto    int := 0;
  v_rec     int := 0;
  v_segue_b boolean := true;
  v_segue_a boolean := true;
  v_segue_r boolean := true;
  v_gat     text;
  v_k       int;
  v_calc    numeric;
  v_most    jsonb;
  v_r       jsonb;
  k         int;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1);
  for k in 1 .. c.revisao_semanas loop
    v_s := v_seg - 7 * k;
    v_p := (public.agenda_ppc(v_s, p_hoje) ->> 'ppc')::numeric;
    v_sem := v_sem || jsonb_build_array(jsonb_build_object('semana', v_s, 'ppc', v_p));
    if v_p is not null then
      v_n := v_n + 1;
      v_amos := v_amos || jsonb_build_array(jsonb_build_object('semana', v_s, 'ppc', v_p));
    end if;
    v_segue_b := v_segue_b and v_p is not null and v_p < c.ppc_baixo;
    if v_segue_b then v_baixo := v_baixo + 1; end if;
    v_segue_a := v_segue_a and v_p is not null and v_p > c.ppc_alto;
    if v_segue_a then v_alto := v_alto + 1; end if;
    v_segue_r := v_segue_r and v_p is not null;
    if v_segue_r then v_rec := v_rec + 1; end if;
  end loop;

  if v_baixo >= c.ppc_baixo_semanas then
    v_gat := 'baixo';
    v_k := v_baixo;
    v_calc := least(c.carga_max, c.carga_ppc_baixo);
  elsif v_alto >= c.ppc_alto_semanas then
    v_gat := 'alto';
    v_k := v_alto;
    v_calc := greatest(c.carga_max, c.carga_ppc_alto);
  else
    v_k := least(v_rec, c.ppc_baixo_semanas);
    v_calc := case when v_n > 0 then c.carga_max end;
  end if;
  -- as semanas que o texto diz, da mais antiga para a mais nova
  select coalesce(jsonb_agg(e -> 'ppc' order by o desc), '[]'::jsonb) into v_most
    from jsonb_array_elements(v_sem) with ordinality t(e, o) where o <= v_k;

  v_r := public._agenda_aprendizado_gravar('carga', 'todas', 'todas', v_calc, v_n, v_amos, c.carga_max,
           jsonb_build_object('semanas', v_sem, 'medidas', v_n, 'baixo_seguidas', v_baixo, 'alto_seguidas', v_alto,
                              'gatilho', v_gat, 'mostrar', v_most, 'meta', c.ppc_meta, 'ppc_baixo', c.ppc_baixo,
                              'ppc_alto', c.ppc_alto),
           p_agora);
  return v_r || jsonb_build_object('gatilho', v_gat, 'semanas', v_n);
end;
$function$;

comment on function public._agenda_aprender_revisao(date, timestamptz) is
  'Agenda de Produção (Fase 6, P6): a revisão da carga de cada pessoa pelo plano cumprido (spec-fase6 §5.6, §3.3 d7) — agenda_ppc das revisao_semanas semanas completas antes de hoje; ppc_baixo_semanas seguidas abaixo de ppc_baixo → item carga = least(carga_max, carga_ppc_baixo); ppc_alto_semanas seguidas acima de ppc_alto → greatest(carga_max, carga_ppc_alto); senão carga_max. Pelo gravador (padrão carga_max): sempre pergunta, nunca entra sozinha; a carga só muda pela opção 1 da pergunta. Só no dia_do_plano pela rodada. Sem grant a ninguém.';

-- ── 2. Os gatilhos de um planejador mais forte ──────────────────────────────────────────────────────────
-- A semana completa anterior a hoje: as OS ativas (a carteira de hoje), as pessoas com meio-dia vigente (não reserva) no
-- plano, as presenças curtas do dono (abrir e fechar) por dia útil e os planos sugeridos que o dono descartou ÷ (aplicados +
-- descartados), em ligado. A habilidade escassa não é medível (não há cadastro de habilidade). Cada semana fica na amostra
-- (a mais nova primeiro); calculado = 1 quando as solver_semanas semanas seguidas mais novas têm ≥ solver_gatilhos_min
-- gatilhos, senão 0. Pergunta UMA VEZ: depois da 1ª pergunta desta chave, o passo passa ao gravador o valor que o deixa onde
-- está (a pergunta aberta continua; respondida, nunca volta).
create or replace function public._agenda_aprender_solver(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c          public.agenda_config := public._agenda_cfg();
  c_gatilhos constant text[] := array['os_ativas', 'pessoas', 'curtas_dia', 'descarte'];
  v_dono     uuid := public._agenda_dono(null);
  v_w        date;
  v_du       int;
  v_os       int;
  v_pes      int;
  v_curtas   numeric;
  v_apl      int;
  v_desc     int;
  v_dpct     numeric;
  v_valem    text[] := '{}';
  v_nova     jsonb;
  r0         public.agenda_aprendizado;
  v_am       jsonb;
  v_cad      int := 0;
  v_seg      int := 0;
  v_calc     numeric;
  v_ja       boolean;
  v_resp     smallint;
  v_quando   date;
  e          jsonb;
  o          int;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  v_w := p_hoje - (extract(isodow from p_hoje)::int - 1) - 7;
  select count(*)::int into v_du
    from generate_series(v_w, v_w + 6, interval '1 day') g where public.agenda_dia_util(g::date);
  select count(*)::int into v_os from public.os_carteira(p_hoje);
  select count(distinct a.payee_id)::int into v_pes
    from public.agenda_alocacoes a
   where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia between v_w and v_w + 6;
  select case when v_du > 0 then round(count(*)::numeric / v_du, 1) end into v_curtas
    from public.agenda_alocacoes a
   where a.payee_id = v_dono and a.presenca <> 'turno' and a.estado in ('publicada', 'fixada')
     and a.dia between v_w and v_w + 6;
  select count(*) filter (where p.estado = 'aplicada')::int, count(*) filter (where p.estado = 'descartada')::int
    into v_apl, v_desc
    from public.agenda_propostas p
   where p.modo = 'ligado' and p.estado in ('aplicada', 'descartada')
     and (p.decidida_em at time zone 'America/Sao_Paulo')::date between v_w and v_w + 6;
  v_dpct := case when v_apl + v_desc > 0 then round(v_desc::numeric / (v_apl + v_desc), 2) end;
  if v_os > c.solver_os_ativas then v_valem := v_valem || 'os_ativas'::text; end if;
  if v_pes > c.solver_pessoas then v_valem := v_valem || 'pessoas'::text; end if;
  if v_curtas > c.solver_curtas_dia then v_valem := v_valem || 'curtas_dia'::text; end if;
  if v_dpct > c.solver_descarte_pct then v_valem := v_valem || 'descarte'::text; end if;
  v_nova := jsonb_build_object('semana', v_w, 'os_ativas', v_os, 'pessoas', v_pes, 'curtas_dia', v_curtas,
                               'descarte_pct', v_dpct, 'aplicados', v_apl, 'descartados', v_desc,
                               'valem', to_jsonb(v_valem), 'n_valem', cardinality(v_valem));

  -- a amostra: esta semana no lugar dela, as de antes como estavam (as de depois saem), a mais nova primeiro
  select * into r0 from public.agenda_aprendizado a where a.item = 'solver' and a.chave = 'gatilhos';
  select coalesce(jsonb_agg(t.x order by t.s desc), '[]'::jsonb) into v_am
    from (select u.x, u.s
            from (select v_nova as x, v_w as s
                  union all
                  select y, (y ->> 'semana')::date from jsonb_array_elements(coalesce(r0.amostra, '[]'::jsonb)) y
                   where (y ->> 'semana')::date < v_w) u
           order by u.s desc
           limit greatest(c.solver_semanas, c.revisao_semanas)) t;
  -- as semanas seguidas medidas (sem buraco) e, delas, as seguidas com gatilhos bastantes
  for o in 0 .. jsonb_array_length(v_am) - 1 loop
    e := v_am -> o;
    exit when (e ->> 'semana')::date <> v_w - 7 * o;
    v_cad := v_cad + 1;
    if v_seg = o and (e ->> 'n_valem')::int >= c.solver_gatilhos_min then
      v_seg := v_seg + 1;
    end if;
  end loop;
  v_calc := case when v_seg >= c.solver_semanas then 1 else 0 end;

  -- uma vez: depois da 1ª pergunta, o valor que deixa a linha onde está
  select q.opcao_escolhida, q.dia into v_resp, v_quando
    from public.agenda_perguntas q
   where q.tipo = 'aprendizado' and q.chave = 'aprendizado:solver:gatilhos'
   order by q.criada_em desc, q.id desc limit 1;
  v_ja := found;
  if v_ja then
    v_calc := case when r0.estado = 'pergunta'
                        and exists (select 1 from public.agenda_perguntas q where q.id = r0.pergunta_id and q.estado = 'aberta')
                   then r0.calculado
                   else coalesce(r0.em_uso, 0) end;
  end if;

  return public._agenda_aprendizado_gravar('solver', 'gatilhos', 'geral', v_calc, v_cad, v_am, 0,
           v_nova || jsonb_build_object('semanas_seguidas', v_seg, 'semanas_medidas', v_cad, 'total', cardinality(c_gatilhos),
                                        'habilidade', 'nao_medivel', 'perguntado', v_ja, 'perguntado_em', v_quando,
                                        'resposta', v_resp,
                                        'limites', jsonb_build_object('os_ativas', c.solver_os_ativas, 'pessoas', c.solver_pessoas,
                                                                      'curtas_dia', c.solver_curtas_dia,
                                                                      'descarte', c.solver_descarte_pct)),
           p_agora);
end;
$function$;

comment on function public._agenda_aprender_solver(date, timestamptz) is
  'Agenda de Produção (Fase 6, P6): os gatilhos de um planejador mais forte (spec-fase6 §5.6) na semana completa anterior a hoje — OS ativas (a carteira de hoje) > solver_os_ativas; pessoas com meio-dia vigente na semana > solver_pessoas; presenças curtas do dono por dia útil > solver_curtas_dia; planos sugeridos descartados ÷ (aplicados + descartados), em ligado, > solver_descarte_pct; a habilidade escassa é nao_medivel. Cada semana na amostra; calculado 1 quando as solver_semanas seguidas mais novas têm ≥ solver_gatilhos_min, senão 0 (n = as semanas seguidas medidas). Pergunta UMA vez (com revisao ligado): depois da 1ª pergunta, nunca mais. Só no dia_do_plano pela rodada. Sem grant a ninguém.';

-- ── 3. A única escrita de parâmetro feita por função ────────────────────────────────────────────────────
-- A carga de cada pessoa no plano (agenda_config.carga_max), só se ela ainda é a de antes (p_de). Quem chama: a opção 1 da
-- pergunta da carga (_agenda_aprendizado_decidir) e o *desfaz* da ação dela (_agenda_desfazer_aprendizado). Mais ninguém (o
-- montador e o R4 de agenda_fase6_rodada.sql conferem); sem grant a ninguém.
create or replace function public._agenda_aprendizado_carga(p_de numeric, p_para numeric, p_autor uuid, p_agora timestamptz)
 returns boolean
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
begin
  if p_de is null or p_para is null or p_agora is null then
    raise exception 'Falta a carga de antes, a nova ou a hora.' using errcode = '22023';
  end if;
  update public.agenda_config set carga_max = p_para, atualizado_em = p_agora, atualizado_por = p_autor
   where id and carga_max = p_de;
  return found;
end;
$function$;

comment on function public._agenda_aprendizado_carga(numeric, numeric, uuid, timestamptz) is
  'Agenda de Produção (Fase 6, P6): a ÚNICA escrita de parâmetro feita por função — agenda_config.carga_max de p_de para p_para (só se ainda é p_de; devolve se mudou). Só a opção 1 da pergunta da carga (_agenda_aprendizado_decidir) e o *desfaz* daquela ação (_agenda_desfazer_aprendizado) a chamam. Definer, sem grant a ninguém.';

-- ── 4. A decisão do dono sobre uma pergunta do aprendizado ─────────────────────────────────────────────
-- 1 = passa a valer o medido (a carga também muda carga_max) e fica a ação crítica com *desfaz* (o planejador mais forte só
-- anota: nada muda na agenda); 2 = fico com o de agora (trava: travado_valor = o medido, até aprender_trava_dias); 3 = volto ao
-- padrão (em_uso nulo) e trava, com a ação crítica e o *desfaz*. Só com a pergunta aberta, a linha ainda nela e o item ligado
-- (modo_aprendizado ligado e na lista). agenda_decidir a chama (o canal e a trava do plano são dela).
create or replace function public._agenda_aprendizado_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid, p_via text,
                                                              p_trecho text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_q      public.agenda_perguntas%rowtype;
  r0       public.agenda_aprendizado;
  r        public.agenda_aprendizado;
  v_opc    jsonb;
  v_efet   numeric;
  v_carga  numeric;
  v_d      jsonb;
  v_txt    text;
  v_acao   uuid;
  v_antes  jsonb := '{}'::jsonb;
  v_depois jsonb := '{}'::jsonb;
  v_hist   jsonb;
  k        text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  select * into v_q from public.agenda_perguntas where id = p_pergunta for update;
  if not found or v_q.tipo <> 'aprendizado' then
    raise exception 'Não encontrei essa pergunta do aprendizado.' using errcode = 'P0002';
  end if;
  if v_q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  select * into r0 from public.agenda_aprendizado a where a.pergunta_id = v_q.id for update;
  if not found or r0.estado <> 'pergunta' then
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'O medido mudou: a pergunta não vale mais.'
     where id = v_q.id and estado = 'aberta';
    return jsonb_build_object('ok', false,
      'texto', 'Essa pergunta não vale mais: o medido mudou desde ela. Se precisar, pergunto de novo.');
  end if;
  if cf.modo_aprendizado <> 'ligado' or not (public._agenda_aprendizado_da_lista(r0.item) = any (cf.aprendizado_ligados)) then
    return jsonb_build_object('ok', false,
      'texto', 'O aprendizado está em teste: não mudo nada agora. Quando ele estiver ligado, eu pergunto de novo.');
  end if;
  select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
  if v_opc is null then
    return jsonb_build_object('ok', false,
      'texto', 'Essa opção não existe. As opções são: '
               || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                     from jsonb_array_elements(v_q.opcoes) o) || '.');
  end if;

  update public.agenda_perguntas
     set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
         respondida_por = p_autor, respondida_via = p_via
   where id = v_q.id;

  r := r0;
  v_efet := coalesce(r0.em_uso, r0.padrao);
  if p_opcao = 1 then
    r.em_uso := r0.calculado;
    r.estado := 'em_uso';
    r.em_uso_desde := p_agora;
    r.travado_ate := null;
    r.travado_valor := null;
    if r0.item = 'carga' then
      -- a carga de todos muda no parâmetro (o motor lê carga_max), e o *desfaz* a volta
      v_carga := cf.carga_max;
      v_efet := v_carga;
      if not public._agenda_aprendizado_carga(v_carga, r0.calculado, p_autor, p_agora) then
        raise exception 'A carga mudou enquanto eu decidia.' using errcode = '40001';
      end if;
    end if;
  elsif p_opcao = 2 then
    r.estado := 'travado';
    r.travado_ate := p_hoje + cf.aprender_trava_dias;
    r.travado_valor := r0.calculado;
  else
    r.em_uso := null;
    r.em_uso_desde := null;
    r.estado := 'travado';
    r.travado_ate := p_hoje + cf.aprender_trava_dias;
    r.travado_valor := r0.calculado;
  end if;

  v_d := jsonb_build_object('chave', r0.chave, 'calculado', r0.calculado, 'em_uso', r.em_uso, 'efetivo', v_efet,
                            'padrao', r0.padrao, 'volta', r0.padrao, 'n', r0.n, 'n_min', r0.n_min,
                            'desde', (r.em_uso_desde at time zone 'America/Sao_Paulo')::date, 'travado_ate', r.travado_ate,
                            'trava_dias', cf.aprender_trava_dias, 'detalhe', r0.detalhe);
  v_txt := case p_opcao
             when 1 then public._agenda_aprendizado_texto(r0.item, 'acao', v_d)
             when 2 then public._agenda_aprendizado_texto(r0.item, 'fico', v_d)
             else regexp_replace(public._agenda_aprendizado_texto(r0.item, 'desfeito', v_d), '^Desfeito: ', 'Combinado: ') end;
  -- a linha do foco: na trava pela opção 3, o que vale é o padrão
  r.texto := left(public._agenda_corta(public._agenda_aprendizado_texto(r0.item, 'foco_' || r.estado,
                    v_d || case when p_opcao = 3 then jsonb_build_object('efetivo', r0.padrao) else '{}'::jsonb end), 400), 400);

  -- a ação crítica, com *desfaz* (a 1 e a 3 mudam o que vale; a 2 não muda nada; o planejador mais forte só anota)
  if p_opcao in (1, 3) and r0.item <> 'solver' then
    insert into public.agenda_acoes (dia, executada, origem, tipo, critica, pergunta_id, texto, antes, depois, desfazivel_ate,
                                     autor, criada_em)
    values (p_hoje, true, 'dono', 'aprendizado', true, v_q.id, left(public._agenda_corta(v_txt, 400), 400),
            jsonb_build_object('item', r0.item, 'chave', r0.chave, 'nivel', r0.nivel, 'em_uso', r0.em_uso, 'valor', v_efet,
                               'estado', r0.estado)
              || case when v_carga is not null then jsonb_build_object('carga_max', v_carga) else '{}'::jsonb end,
            jsonb_build_object('item', r0.item, 'chave', r0.chave, 'nivel', r0.nivel, 'em_uso', r.em_uso, 'n', r0.n,
                               'opcao', p_opcao)
              || case when v_carga is not null then jsonb_build_object('carga_max', r0.calculado) else '{}'::jsonb end,
            p_agora + cf.desfazer_validade, p_autor, p_agora)
    returning id into v_acao;
    r.acao_id := v_acao;
  end if;

  -- o histórico: em uso, estado e calculado, quando mudam (os 20 mais novos)
  foreach k in array array['em_uso', 'estado', 'calculado'] loop
    if to_jsonb(r0) -> k is distinct from to_jsonb(r) -> k then
      v_antes := v_antes || jsonb_build_object(k, to_jsonb(r0) -> k);
      v_depois := v_depois || jsonb_build_object(k, to_jsonb(r) -> k);
    end if;
  end loop;
  v_hist := r0.historico;
  if v_antes <> '{}'::jsonb then
    v_hist := v_hist || jsonb_build_array(jsonb_build_object('em', p_agora, 'antes', v_antes, 'depois', v_depois,
                                                             'decisao', p_opcao));
    if jsonb_array_length(v_hist) > 20 then
      select jsonb_agg(x order by o) into v_hist
        from jsonb_array_elements(v_hist) with ordinality t(x, o) where o > jsonb_array_length(v_hist) - 20;
    end if;
  end if;
  update public.agenda_aprendizado
     set em_uso = r.em_uso, estado = r.estado, em_uso_desde = r.em_uso_desde, travado_ate = r.travado_ate,
         travado_valor = r.travado_valor, texto = r.texto, acao_id = r.acao_id, historico = v_hist
   where id = r0.id;

  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'item', r0.item, 'chave', r0.chave,
                            'estado', r.estado, 'em_uso', r.em_uso);
end;
$function$;

comment on function public._agenda_aprendizado_decidir(uuid, smallint, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 6, P6): a resposta do dono à pergunta crítica aprendizado (spec-fase6 §3.2, §5.6) — só com a pergunta aberta, a linha de agenda_aprendizado nela e o item ligado (modo_aprendizado ligado e na lista; senão "O aprendizado está em teste"). 1 = o medido passa a valer (em_uso; na carga, agenda_config.carga_max muda por _agenda_aprendizado_carga) e a ação crítica aprendizado (origem dono, desfazível por desfazer_validade; o planejador mais forte só anota, sem ação); 2 = trava (travado_valor = o medido; o que vale continua); 3 = volta ao padrão (em_uso nulo) e trava, com a ação. A pergunta fica respondida. Chamada por agenda_decidir. Definer, sem grant.';

-- ── 5. O *desfaz* do que o aprendizado mudou ────────────────────────────────────────────────────────────
-- A ação aprendizado (a que entrou sozinha pelo gravador ou a da decisão 1/3): o em_uso de antes volta (nulo = o padrão) e a
-- chave fica travada por aprender_trava_dias (travado_valor = o medido recusado), para a rodada seguinte não trocar de novo;
-- a da carga volta carga_max, só se ainda é a que a decisão gravou. Só se a linha ainda está como a ação a deixou.
create or replace function public._agenda_desfazer_aprendizado(p_acao uuid, p_autor uuid, p_via text, p_hoje date,
                                                               p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_a      public.agenda_acoes%rowtype;
  r0       public.agenda_aprendizado;
  r        public.agenda_aprendizado;
  v_volta  numeric;
  v_d      jsonb;
  v_txt    text;
  v_acao   uuid;
  v_antes  jsonb := '{}'::jsonb;
  v_depois jsonb := '{}'::jsonb;
  v_hist   jsonb;
  k        text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Falta o dia (p_hoje) ou a hora (p_agora).' using errcode = '22023';
  end if;
  select * into v_a from public.agenda_acoes where id = p_acao for update;
  if not found or v_a.tipo <> 'aprendizado' then
    raise exception 'Não encontrei essa mudança do aprendizado.' using errcode = 'P0002';
  end if;
  if not v_a.executada then
    return jsonb_build_object('ok', false, 'texto', 'Isso foi só o teste do aprendizado: nada mudou para desfazer.');
  end if;
  if v_a.desfeita_em is not null then
    return jsonb_build_object('ok', false, 'texto', 'Isso já foi desfeito.');
  end if;
  if v_a.desfazivel_ate is null or p_agora > v_a.desfazivel_ate then
    return jsonb_build_object('ok', false, 'texto', 'Não dá mais para desfazer esse aprendizado: passou o prazo.');
  end if;
  select * into r0 from public.agenda_aprendizado a
   where a.item = v_a.antes ->> 'item' and a.chave = v_a.antes ->> 'chave' for update;
  if not found or r0.em_uso is distinct from (v_a.depois ->> 'em_uso')::numeric then
    return jsonb_build_object('ok', false, 'texto', 'Esse aprendizado já mudou depois dessa mudança: não há o que desfazer nela.');
  end if;
  if v_a.depois ? 'carga_max' then
    if not public._agenda_aprendizado_carga((v_a.depois ->> 'carga_max')::numeric, (v_a.antes ->> 'carga_max')::numeric,
                                            p_autor, p_agora) then
      return jsonb_build_object('ok', false,
        'texto', format('A parte da semana de cada pessoa mudou depois (hoje %s): não há o que desfazer nessa mudança.',
                        public._agenda_aprendizado_valor('carga', cf.carga_max)));
    end if;
  end if;

  r := r0;
  r.em_uso := (v_a.antes ->> 'em_uso')::numeric;
  r.em_uso_desde := case when r.em_uso is not null then p_agora end;
  r.estado := 'travado';
  r.travado_ate := p_hoje + cf.aprender_trava_dias;
  r.travado_valor := coalesce(r0.calculado, (v_a.depois ->> 'em_uso')::numeric);
  v_volta := coalesce((v_a.antes ->> 'carga_max')::numeric, r.em_uso, r0.padrao);
  v_d := jsonb_build_object('chave', r0.chave, 'calculado', r0.calculado, 'em_uso', r.em_uso, 'efetivo', v_volta,
                            'padrao', r0.padrao, 'volta', v_volta, 'n', r0.n, 'n_min', r0.n_min,
                            'desde', (r.em_uso_desde at time zone 'America/Sao_Paulo')::date, 'travado_ate', r.travado_ate,
                            'trava_dias', cf.aprender_trava_dias, 'detalhe', r0.detalhe);
  v_txt := public._agenda_aprendizado_texto(r0.item, 'desfeito', v_d);
  r.texto := left(public._agenda_corta(public._agenda_aprendizado_texto(r0.item, 'foco_travado', v_d), 400), 400);

  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, critica, antes, depois, texto, autor, desfaz_a)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', false,
          jsonb_build_object('acao', v_a.id),
          jsonb_build_object('item', r0.item, 'chave', r0.chave, 'em_uso', r.em_uso, 'travado_ate', r.travado_ate)
            || case when v_a.depois ? 'carga_max' then jsonb_build_object('carga_max', v_a.antes -> 'carga_max') else '{}'::jsonb end,
          left(public._agenda_corta(v_txt, 400), 400), p_autor, v_a.id)
  returning id into v_acao;
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_a.id;

  foreach k in array array['em_uso', 'estado', 'calculado'] loop
    if to_jsonb(r0) -> k is distinct from to_jsonb(r) -> k then
      v_antes := v_antes || jsonb_build_object(k, to_jsonb(r0) -> k);
      v_depois := v_depois || jsonb_build_object(k, to_jsonb(r) -> k);
    end if;
  end loop;
  v_hist := r0.historico;
  if v_antes <> '{}'::jsonb then
    v_hist := v_hist || jsonb_build_array(jsonb_build_object('em', p_agora, 'antes', v_antes, 'depois', v_depois,
                                                             'desfeita', v_a.id));
    if jsonb_array_length(v_hist) > 20 then
      select jsonb_agg(x order by o) into v_hist
        from jsonb_array_elements(v_hist) with ordinality t(x, o) where o > jsonb_array_length(v_hist) - 20;
    end if;
  end if;
  update public.agenda_aprendizado
     set em_uso = r.em_uso, estado = r.estado, em_uso_desde = r.em_uso_desde, travado_ate = r.travado_ate,
         travado_valor = r.travado_valor, texto = r.texto, historico = v_hist
   where id = r0.id;

  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'item', r0.item, 'chave', r0.chave,
                            'em_uso', r.em_uso, 'travado_ate', r.travado_ate);
end;
$function$;

comment on function public._agenda_desfazer_aprendizado(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 6, P6): o *desfaz* da ação aprendizado (spec-fase6 §5.6) — a que entrou sozinha (origem vigia) ou a da decisão 1/3 (origem dono): o em_uso de antes volta (nulo = o padrão) e a chave fica travada por aprender_trava_dias (travado_valor = o medido recusado); a da carga volta agenda_config.carga_max (só se ainda é a que a decisão gravou). Só dentro de desfazivel_ate e com a linha ainda como a ação a deixou. A ação desfazer (desfaz_a) e desfeita_* na original. Chamada por agenda_desfazer. Definer, sem grant.';

-- ── 6. A rodada do aprendizado ──────────────────────────────────────────────────────────────────────────
-- Uma vez por dia, no 1º tique a partir de aprender_hora (o passo TS do task-automations a chama a cada tique). Os passos,
-- cada um no seu bloco: o que falha vai a app_error_logs (context agenda, action aprender:<passo>) e os outros seguem — a
-- rodada nunca lança por um passo, e não mexe nas rodadas das Fases 1 a 5 (só grava a linha dela, rotina aprender).
create or replace function public.agenda_aprender(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_medir   constant text[] := array['congelar', 'medir'];
  c_passos  constant text[] := array['fator', 'mo', 'presenca', 'fornecedor', 'capacidade', 'cliente'];
  c_semana  constant text[] := array['revisao', 'solver'];
  cf        public.agenda_config;
  v_t0      timestamptz := clock_timestamp();
  v_semanal boolean;
  v_passo   text;
  v_r       jsonb;
  v_cont    jsonb := '{}'::jsonb;
  v_erros   int := 0;
  v_falhas  jsonb := '[]'::jsonb;
  v_estado  text;
  v_msg     text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rodada do aprendizado.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_aprender'));
  cf := public._agenda_cfg();
  if (p_agora at time zone 'America/Sao_Paulo')::time < cf.aprender_hora then
    return jsonb_build_object('rodou', false, 'cedo', true, 'modo', cf.modo_aprendizado, 'hora', cf.aprender_hora);
  end if;
  if exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.p_hoje = p_hoje) then
    return jsonb_build_object('rodou', false, 'ja_rodou', true, 'modo', cf.modo_aprendizado);
  end if;
  v_semanal := extract(isodow from p_hoje)::int = cf.dia_do_plano;

  -- (1) a medição: sempre, em qualquer modo (só escreve as tabelas da Fase 6); (2) o aprendido: fora de desligado; (3) a
  -- revisão e o planejador mais forte: fora de desligado, no dia do plano
  foreach v_passo in array c_medir
                           || case when cf.modo_aprendizado <> 'desligado' then c_passos else '{}'::text[] end
                           || case when cf.modo_aprendizado <> 'desligado' and v_semanal then c_semana else '{}'::text[] end loop
    begin
      if v_passo = any (c_medir) then
        execute format('select public.%I($1)', '_agenda_aprender_' || v_passo) into v_r using p_hoje;
      else
        execute format('select public.%I($1, $2)', '_agenda_aprender_' || v_passo) into v_r using p_hoje, p_agora;
      end if;
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('aprendizado, passo %s: %s', v_passo, v_msg), 'agenda',
                                   'aprender:' || v_passo, 'error',
                                   jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje,
                                                      'p_agora', p_agora));
    end;
  end loop;

  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                           rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
          v_cont || jsonb_build_object('modo_aprendizado', cf.modo_aprendizado, 'ligados', to_jsonb(cf.aprendizado_ligados),
                                       'semanal', v_semanal, 'falhas', v_falhas),
          least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int),
          'aprender', cf.modo_equipe, cf.modo_diaria);

  return jsonb_build_object('rodou', true, 'modo', cf.modo_aprendizado, 'ligados', to_jsonb(cf.aprendizado_ligados),
                            'semanal', v_semanal, 'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas);
end;
$function$;

comment on function public.agenda_aprender(date, timestamptz) is
  'Agenda de Produção (Fase 6, P6): a rodada diária do aprendizado (spec-fase6 §5.6), pelo task-automations a cada tique — roda uma vez por dia, no 1º tique a partir de aprender_hora (antes = {rodou: false, cedo}; o 2º = {rodou: false, ja_rodou}). Passos, cada um no seu bloco (o que falha vai a app_error_logs, context agenda, action aprender:<passo>, e os outros seguem): (1) sempre, até com modo_aprendizado desligado, congelar e medir; (2) fora de desligado, fator, mo, presenca, fornecedor, capacidade e cliente (pelo gravador: em teste tudo fica sombra e nada é usado); (3) fora de desligado e no dia_do_plano, revisao (a carga pelo plano cumprido) e solver. Uma linha em agenda_vigia_rodadas (rotina aprender). {rodou, modo, ligados, semanal, contagens, erros, falhas}. Nenhuma mensagem. Só service_role.';

-- ── 7. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 6:") ──────────────────
-- Fora dos blocos nenhuma linha muda (o R8 do teste confere). Quem recriar de novo qualquer uma delas copia DESTA migration.

-- agenda_decidir (de 20261028100300_agenda_fase5_rodada.sql)
create or replace function public.agenda_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid default null,
                                                 p_via text default 'whatsapp', p_trecho text default null,
                                                 p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config;
  v_q    public.agenda_perguntas%rowtype;
  v_opc  jsonb;
  v_rest jsonb;
  v_sim  jsonb;
  v_mud  text;
  v_r    jsonb;
  v_ap   jsonb;
begin
  if p_via is null or p_via not in ('whatsapp', 'painel', 'tela') then
    raise exception 'Canal desconhecido para a decisão: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  select * into v_q from public.agenda_perguntas where id = p_pergunta for update;
  if not found then
    raise exception 'Não encontrei essa pergunta.' using errcode = 'P0002';
  end if;
  -- FASE 3: a diária (a pergunta crítica que diverge e a de ligar a OS) tem o efeito dela e o modo dela (modo_diaria):
  -- _agenda_decidir_diaria (20261026100300).
  if v_q.tipo in ('diaria', 'diaria_ligar') then
    return public._agenda_decidir_diaria(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 3: fim
  -- FASE 5: a mensagem ao cliente (cliente_aprovar, a aprovação dos primeiros dias, e cliente_aviso, a crítica do aviso de
  -- atraso) tem o efeito dela e o modo dela (modo_cliente): _agenda_cliente_decidir (20261028100300).
  if v_q.tipo in ('cliente_aprovar', 'cliente_aviso') then
    return public._agenda_cliente_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_agora);
  end if;
  -- FASE 5: fim
  -- FASE 6: (P6) a pergunta do aprendizado (a troca grande de um valor medido, a carga de cada pessoa pelo plano cumprido e
  -- o planejador mais forte) tem o efeito dela e o modo dela (modo_aprendizado e aprendizado_ligados):
  -- _agenda_aprendizado_decidir (20261029100600). A opção 1 da carga é a única escrita de parâmetro (carga_max), com *desfaz*.
  if v_q.tipo = 'aprendizado' then
    return public._agenda_aprendizado_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 6: fim
  if not v_q.critica then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta não é de decisão.');
  end if;
  if v_q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  if v_q.modo <> 'ligado' or cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.');
  end if;
  select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
  if v_opc is null then
    return jsonb_build_object('ok', false,
      'texto', 'Essa opção não existe. As opções são: '
               || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                     from jsonb_array_elements(v_q.opcoes) o) || '.');
  end if;
  v_rest := coalesce(v_opc #> '{efeito,restricoes}', '{}'::jsonb);

  -- A agenda mudou desde a pergunta: o efeito da opção é refeito agora; se não termina como a opção dizia, a pergunta
  -- volta com os dias de agora (nada é executado).
  if v_q.versao_base is distinct from cf.versao_plano and jsonb_typeof(v_opc -> 'espera') = 'object'
     and v_opc -> 'espera' <> '{}'::jsonb then
    v_sim := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest, false, 'dono', p_autor, p_hoje, p_agora);
    select string_agg(format('%s termina %s (antes eu disse %s)', public._agenda_rotulo_da_os(e.key::uuid),
                             coalesce(public._dia_curto(x.fim), 'sem encaixe'), public._dia_curto((e.value #>> '{}')::date)), '; ')
      into v_mud
      from jsonb_each(v_opc -> 'espera') e
      left join lateral (select max((i ->> 'fim_depois')::date) as fim from jsonb_array_elements(v_sim -> 'itens') i
                          where i ->> 'op' = 'criar' and i ->> 'os' = e.key and i ->> 'tipo' <> 'reserva') x on true
     where x.fim is distinct from (e.value #>> '{}')::date;
    if v_mud is not null then
      return jsonb_build_object('ok', false, 'mudou', true,
        'texto', 'A agenda mudou desde a pergunta: ' || v_mud || '. Me responda de novo com os dias de agora.');
    end if;
  end if;

  begin
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = p_pergunta;
    v_r := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest || jsonb_build_object('decisao', p_pergunta),
                                true, 'dono', p_autor, p_hoje, p_agora);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_r ->> 'texto', 'não deu');
    end if;
    v_ap := public.agenda_aplicar((v_r ->> 'proposta_id')::uuid, null, 'dono', p_autor, p_pergunta, p_hoje, p_agora);
    if not coalesce((v_ap ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_ap ->> 'texto', 'não deu');
    end if;
  exception when sqlstate 'P0098' then
    -- nada fica: a pergunta continua aberta
    return jsonb_build_object('ok', false, 'texto', 'Não consegui fazer o que você escolheu: ' || sqlerrm || ' Nada mudou.');
  end;
  return jsonb_build_object('ok', true, 'texto', 'Feito: ' || (v_ap ->> 'texto'), 'acoes', v_ap -> 'acoes',
                            'proposta_id', v_r ->> 'proposta_id');
end;
$function$;

comment on function public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): a resposta do dono a uma pergunta crítica aberta (só em ligado). Opção que não existe = recusa, nada marcado. Se a agenda mudou desde a pergunta, o efeito da opção é refeito agora e, se não termina como a opção dizia (espera), devolve a pergunta com os dias de agora sem executar. Senão: a pergunta fica respondida (opcao_escolhida, resposta = as palavras do dono, respondida_*) e o efeito é executado — agenda_propor(replano, as OS da pergunta, as restrições da opção + decisao) e agenda_aplicar com p_pergunta (toda ação sai critica = true com pergunta_id). Falhou = nada fica, a pergunta continua aberta. Canais: whatsapp, painel, tela. Fase 3: diaria e diaria_ligar vão a _agenda_decidir_diaria (o lançamento, a correção pelo registrar_diaria ou a ligação às OS, com modo_diaria ligado). Fase 5 (P3): cliente_aprovar e cliente_aviso vão a _agenda_cliente_decidir (manda ou segura a mensagem ao cliente; com modo_cliente ligado). Fase 6 (P6): aprendizado vai a _agenda_aprendizado_decidir (1 o medido passa a valer — na carga, agenda_config.carga_max muda —, 2 trava, 3 volta ao padrão e trava; a 1 e a 3 com a ação crítica desfazível; com modo_aprendizado ligado e o item na lista).';

-- agenda_desfazer (de 20261028100400_agenda_fase5_respostas.sql)
create or replace function public.agenda_desfazer(p_acao uuid, p_autor uuid default null, p_via text default 'dono',
                                                  p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_a     public.agenda_acoes%rowtype;
  v_nome  text;
  v_x     record;
  v_novas uuid[] := '{}';
  v_canc  uuid[] := '{}';
  v_id    uuid;
  v_os    uuid;
  v_acao  uuid;
  v_txt   text;
  v_q     public.agenda_perguntas%rowtype;
  v_dias  date[];
begin
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  select * into v_a from public.agenda_acoes where id = p_acao for update;
  if not found then
    raise exception 'Não encontrei essa mudança.' using errcode = 'P0002';
  end if;
  v_os := v_a.service_order_id;
  v_nome := coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                        join public.clients cl on cl.id = so.client_id where so.id = v_os), 'serviço');
  if not v_a.executada then
    return jsonb_build_object('ok', false, 'texto', 'Isso foi só o teste da agenda automática: nada mudou para desfazer.');
  end if;
  if v_a.desfeita_em is not null then
    return jsonb_build_object('ok', false, 'texto', 'Isso já foi desfeito.');
  end if;
  if v_a.tipo = 'desfazer' then
    return jsonb_build_object('ok', false, 'texto', 'Não desfaço um desfazer: me diga o dia que você quer.');
  end if;
  -- FASE 3: a conclusão e a entrega têm o desfazer delas (o status e a saída pela porta, as cobranças da conclusão, a
  -- comissão de vendedor, os vencimentos "na entrega" e a entrega): _agenda_desfazer_marco (20261026100100).
  if v_a.tipo in ('concluir', 'entregar') then
    return public._agenda_desfazer_marco(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 3 (P4): a diária que a agenda lançou: apaga o turno que ela criou, se o acerto está aberto (_agenda_desfazer_diaria).
  if v_a.tipo = 'diaria' then
    return public._agenda_desfazer_diaria(v_a.id, p_autor, p_hoje, p_agora);
  end if;
  -- FASE 3: fim
  -- FASE 4: a mudança do material que o gestor fez sozinho (a previsão pela mensagem do fornecedor, a chegada pela nota
  -- importada): as linhas voltam como estavam, se ninguém mexeu nelas depois (_agenda_desfazer_material, 20261027100400).
  if v_a.tipo = 'material' then
    return public._agenda_desfazer_material(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 4: fim
  -- FASE 5: o que a resposta do cliente mudou (a confirmação, o pedido de dia, o acesso: a ação com depois.resposta_id) tem
  -- o desfazer dela (_agenda_desfazer_cliente, 20261028100400); a mensagem enviada não se desmanda; o acorde e a decisão do
  -- aviso crítico não mudaram nada na agenda.
  if v_a.origem = 'cliente' and v_a.tipo in ('fixar', 'cliente') and v_a.depois ? 'resposta_id' then
    return public._agenda_desfazer_cliente(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  if v_a.tipo = 'cliente' then
    return jsonb_build_object('ok', false,
      'texto', case when v_a.depois ? 'mensagem_id' then 'Mensagem enviada não se desmanda.'
                    else 'Isso foi um aviso para você: nada mudou na agenda para desfazer.' end);
  end if;
  -- FASE 5: fim
  -- FASE 6: (P6) o que o aprendizado mudou (a troca que entrou sozinha e a decisão 1 ou 3 do dono) tem o desfazer dele: o
  -- valor de antes volta e a chave fica travada; a carga volta carga_max (_agenda_desfazer_aprendizado, 20261029100600).
  if v_a.tipo = 'aprendizado' then
    return public._agenda_desfazer_aprendizado(v_a.id, p_autor, p_via, p_hoje, p_agora);
  end if;
  -- FASE 6: fim
  if v_a.desfazivel_ate is null then
    return jsonb_build_object('ok', false, 'texto', 'Essa mudança foi pedida por você: para mudar de novo, me diga o dia.');
  end if;
  if p_agora > v_a.desfazivel_ate then
    return jsonb_build_object('ok', false,
      'texto', case when exists (select 1 from public.agenda_alocacoes a where a.id = any (v_a.alocacoes_criadas)
                                                                       and lower(a.periodo) <= p_agora)
                    then format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.', v_nome)
                    else format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga o dia.', v_nome) end);
  end if;
  if exists (select 1 from public.agenda_alocacoes a
              where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada')
                and (lower(a.periodo) <= p_agora or a.resultado is not null)) then
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: já começou o 1º dia do %s na nova data. Se quiser mudar, me diga o dia.', v_nome));
  end if;
  -- recriar o que saiu não pode bater em quem já está no lugar
  select a.dia, a.turno, py.name as pessoa, cl.name as cliente into v_x
    from public.agenda_alocacoes c
    join public.agenda_alocacoes a on a.payee_id = c.payee_id and a.periodo && c.periodo and a.estado in ('publicada', 'fixada')
                                  and not (a.id = any (v_a.alocacoes_criadas))
    join public.payees py on py.id = a.payee_id
    join public.service_orders so on so.id = a.service_order_id
    left join public.clients cl on cl.id = so.client_id
   where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora
   order by a.dia, a.turno = 'tarde'
   limit 1;
  if found then
    return jsonb_build_object('ok', false,
      'texto', format('Não dá para desfazer: o %s já está no %s %s.', public._agenda_nome_curto(v_x.pessoa),
                      coalesce(public._agenda_nome_curto(v_x.cliente), 'outro serviço'), public._agenda_meio_texto(v_x.dia, v_x.turno)));
  end if;

  -- 1. O que a ação criou sai.
  for v_id in select a.id from public.agenda_alocacoes a
               where a.id = any (v_a.alocacoes_criadas) and a.estado in ('publicada', 'fixada') order by a.dia, a.turno, a.id loop
    if (select estado from public.agenda_alocacoes where id = v_id) = 'fixada' then
      perform set_config('agenda.mexe_fixado', 'on', true);
    end if;
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where id = v_id;
    perform set_config('agenda.mexe_fixado', 'off', true);
    v_canc := v_canc || v_id;
  end loop;
  -- 2. O que ela tirou volta, igual (mesma pessoa, dia, turno e presença), do que ainda não começou.
  for v_x in select c.* from public.agenda_alocacoes c
              where c.id = any (v_a.alocacoes_canceladas) and c.estado = 'cancelada' and lower(c.periodo) > p_agora
              order by c.dia, c.turno = 'tarde', c.payee_id, c.id loop
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, substitui_id,
                                         fixado_por, reserva_de, condicao, condicao_tipo, condicao_ate, motivos)
    values (v_x.service_order_id, v_x.payee_id, v_x.dia, v_x.turno, v_x.presenca, v_x.tipo,
            case when v_x.fixado_por is not null then 'fixada' else 'publicada' end, v_x.origem, v_x.id,
            v_x.fixado_por, v_x.reserva_de, v_x.condicao, v_x.condicao_tipo, v_x.condicao_ate, v_x.motivos)
    returning id into v_id;
    v_novas := v_novas || v_id;
  end loop;
  -- 3. O status volta pela porta (a regra de não regredir o que começou continua valendo) e o espelho acompanha.
  if v_a.tipo = 'status' and v_a.status_antes is not null and v_os is not null then
    perform public.os_transicionar_status(v_os, v_a.status_antes, 'desfazer', null, p_autor, null, p_hoje, p_agora);
  elsif v_os is not null then
    if public._agenda_os_tem_dia(v_os, p_hoje) then
      if (select status from public.service_orders where id = v_os) in ('open', 'approved', 'awaiting_parts') then
        perform public.os_transicionar_status(v_os, 'scheduled', 'desfazer', null, p_autor, null, p_hoje, p_agora);
      end if;
    elsif (select status from public.service_orders where id = v_os) = 'scheduled' then
      perform public.os_transicionar_status(v_os, case when v_a.status_antes in ('open', 'approved', 'awaiting_parts')
                                                       then v_a.status_antes else 'approved' end,
                                            'desfazer', null, p_autor, null, p_hoje, p_agora);
    end if;
    perform public._agenda_espelhar_datas(v_os, p_hoje);
  end if;

  v_dias := array(select a.dia from public.agenda_alocacoes a where a.id = any (v_novas) and a.tipo <> 'reserva');
  v_txt := case when cardinality(v_dias) > 0
                then format('Desfeito: o %s volta para %s, como estava.', public._agenda_rotulo_da_os(v_os), public._agenda_dias_texto(v_dias))
                when cardinality(v_novas) > 0 then format('Desfeito: a reserva do %s volta como estava.', public._agenda_rotulo_da_os(v_os))
                else format('Desfeito: o %s sai da agenda, como estava.', coalesce(public._agenda_rotulo_da_os(v_os), 'serviço')) end;
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, proposta_id, critica,
                                   versao_depois, alocacoes_criadas, alocacoes_canceladas, antes, depois, texto, autor, desfaz_a)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os,
          v_a.os_ids, v_a.proposta_id, false, (public._agenda_cfg()).versao_plano, v_novas, v_canc,
          jsonb_build_object('acao', v_a.id), jsonb_build_object('alocacoes', to_jsonb(v_novas)), left(v_txt, 400), p_autor, v_a.id)
  returning id into v_acao;
  update public.agenda_alocacoes set acao_id = v_acao where id = any (v_novas);
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_a.id;

  -- Desfazer uma decisão crítica não a reabre: a decisão volta ao dono como pergunta nova, do mesmo tipo.
  if v_a.critica and v_a.pergunta_id is not null then
    select * into v_q from public.agenda_perguntas where id = v_a.pergunta_id;
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao,
                                         recomendacao_texto, versao_base, modo, criada_em)
    values (v_q.tipo, left(v_q.chave || ':refeita:' || left(v_acao::text, 8), 200), v_q.service_order_id, v_q.os_ids, v_q.perda_em,
            v_q.texto, v_q.opcoes, v_q.recomendacao, v_q.recomendacao_texto, (public._agenda_cfg()).versao_plano, v_q.modo, p_agora)
    on conflict (chave, modo) where estado = 'aberta' do nothing;
    v_txt := format('Desfeito. A decisão sobre o %s volta a ficar com você.', v_nome);
  end if;
  -- FASE 3: o replano que a ausência da equipe causou ("não vou" ou o silêncio até as 9h): desfazer também tira a ausência
  -- daquele dia (senão a vigia replanejaria de novo no tique seguinte). "Se ele estiver lá, *desfaz Vanderlei*."
  update public.agenda_disponibilidade d set substituida_em = p_agora
   where d.substituida_em is null
     and d.id in (select (e.depois ->> 'disponibilidade')::uuid from public.agenda_acoes e
                   where e.tipo = 'equipe' and e.depois ->> 'disponibilidade' is not null
                     and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text);
  -- FASE 3: fim
  -- FASE 5: o replano que o pedido de dia do cliente causou, desfeito direto (sem a ação do cliente): o pedido sai junto (o
  -- bem indisponível e o "não antes de" voltam; senão a vigia replanejaria de novo no tique seguinte) e a ação do cliente
  -- fica desfeita. Quem desfaz pela ação do cliente (_agenda_desfazer_cliente) liga agenda.desfazer_cliente e faz isso ela.
  if coalesce(current_setting('agenda.desfazer_cliente', true), '') <> 'on' then
    for v_x in select e.id from public.agenda_acoes e
                where e.tipo = 'cliente' and e.origem = 'cliente' and e.executada and e.desfeita_em is null
                  and e.depois ->> 'efeito' = 'replanejou'
                  and coalesce(e.depois -> 'replano_acoes', '[]'::jsonb) ? v_a.id::text loop
      perform public._agenda_cliente_restaurar_pedido(v_x.id, p_agora);
      update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_x.id;
    end loop;
  end if;
  -- FASE 5: fim
  return jsonb_build_object('ok', true, 'texto', v_txt, 'acao_id', v_acao, 'recriadas', to_jsonb(v_novas), 'canceladas', to_jsonb(v_canc));
end;
$function$;

comment on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): desfaz uma ação executada — recusa (nada muda) se foi sombra, já foi desfeita, não é desfazível (pedido do dono pela tela ou aprovação), passou o desfazivel_ate, algum meio-dia criado já começou ou tem resultado, ou recriar o que saiu bateria em quem já está no lugar ("Não dá para desfazer: o Roberto já está no Giancarlo…"). Faz: o que ela criou → cancelada (desfeito); o que ela tirou volta igual (substitui_id, mesmo estado/fixado); o status pela porta (via desfazer; o que começou não regride); o espelho; nova ação tipo desfazer (desfaz_a) e a original ganha desfeita_*. Desfazer uma decisão crítica cria a pergunta de novo ("A decisão sobre o Nelson volta a ficar com você."). Fase 3: concluir e entregar vão a _agenda_desfazer_marco (as cobranças da conclusão, a saída, a comissão de vendedor e a entrega); a diária da agenda a _agenda_desfazer_diaria (apaga o turno que ela criou, com o acerto aberto); desfazer o replano da ausência da equipe tira a ausência do dia (agenda_disponibilidade substituída). Fase 4 (P4): a ação material (a previsão pela mensagem do fornecedor, a chegada pela nota) vai a _agenda_desfazer_material (as linhas voltam se ninguém mexeu nelas depois). Fase 5 (P4): o que a resposta do cliente mudou (a ação fixar/cliente de origem cliente com depois.resposta_id: a confirmação, o pedido de dia, o acesso) vai a _agenda_desfazer_cliente; a outra ação cliente (a mensagem enviada, o acorde, a decisão do aviso) não se desfaz ("Mensagem enviada não se desmanda."); desfazer direto o replano que o pedido de dia causou também tira o pedido (_agenda_cliente_restaurar_pedido) e deixa a ação do cliente desfeita. Fase 6 (P6): a ação aprendizado vai a _agenda_desfazer_aprendizado (o em_uso de antes volta, nulo = o padrão, e a chave fica travada por aprender_trava_dias; a da carga volta carga_max).';

-- agenda_desfazer_dito (de 20261025100300_agenda_fase2_conferencia_vigia.sql)
create or replace function public.agenda_desfazer_dito(p_autor uuid, p_alvo text default null, p_canal text default 'whatsapp',
                                                       p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor uuid := public._autor_da_agenda(p_autor);
  v_ref   jsonb;
  v_id    uuid;
  v_r     jsonb;
  v_txts  text[] := '{}';
  v_falha text;
  -- FASE 6: (P6) o alvo "aprendizado"
  v_aprend boolean := false;
  -- FASE 6: fim
begin
  -- FASE 6: (P6) *desfaz aprendizado* (spec-fase6 §5.6): o último lote de ações aprendizado desfazíveis — as do mesmo
  -- instante (o que a mesma rodada ou a mesma decisão mudou: o fator muda as 4 chaves de uma vez) —, tudo ou nada. Sem
  -- nenhuma, "não tenho". Os outros alvos seguem por agenda_acao_desfazivel, como antes
  if public._agenda_normal(p_alvo) in ('aprendizado', 'o aprendizado') then
    v_aprend := true;
    select jsonb_build_object('status', 'ok',
                              'acao_id', (array_agg(a.id order by a.antes ->> 'item', a.antes ->> 'chave', a.id))[1],
                              'acao_ids', jsonb_agg(a.id order by a.antes ->> 'item', a.antes ->> 'chave', a.id))
      into v_ref
      from public.agenda_acoes a
     where a.tipo = 'aprendizado' and a.executada and a.desfeita_em is null and a.desfazivel_ate >= p_agora
       and a.criada_em = (select max(b.criada_em) from public.agenda_acoes b
                           where b.tipo = 'aprendizado' and b.executada and b.desfeita_em is null and b.desfazivel_ate >= p_agora)
    having count(*) > 0;
    v_ref := coalesce(v_ref, jsonb_build_object('status', 'nenhuma',
                                                'texto', 'Não tenho mudança do aprendizado para desfazer agora.'));
  else
  -- FASE 6: fim
  v_ref := public.agenda_acao_desfazivel(p_alvo, p_hoje, p_agora);
  -- FASE 6: (P6) o fim do "se é o aprendizado"
  end if;
  -- FASE 6: fim
  if v_ref ->> 'status' is distinct from 'ok' then
    return jsonb_build_object('ok', false, 'mudou', false, 'status', v_ref ->> 'status', 'texto', v_ref ->> 'texto',
                              'opcoes', v_ref -> 'opcoes');
  end if;
  -- "desfaz semana" são várias ações: tudo ou nada
  begin
    for v_id in select x::uuid from jsonb_array_elements_text(coalesce(v_ref -> 'acao_ids', jsonb_build_array(v_ref ->> 'acao_id'))) x loop
      v_r := public.agenda_desfazer(v_id, v_autor, 'dono', p_hoje, p_agora);
      if not coalesce((v_r ->> 'ok')::boolean, false) then
        v_falha := v_r ->> 'texto';
        raise exception using errcode = 'P0098', message = 'desfazer recusado';
      end if;
      v_txts := v_txts || (v_r ->> 'texto');
    end loop;
  exception when sqlstate 'P0098' then
    return jsonb_build_object('ok', false, 'mudou', false, 'texto', v_falha);
  end;
  -- FASE 6: (P6) o lote do aprendizado: os "Desfeito: …" um depois do outro (não é a publicação da semana)
  if v_aprend then
    return jsonb_build_object('ok', true, 'mudou', true, 'acoes', v_ref -> 'acao_ids', 'texto', array_to_string(v_txts, ' '));
  end if;
  -- FASE 6: fim
  return jsonb_build_object('ok', true, 'mudou', true, 'acoes', v_ref -> 'acao_ids',
    'texto', case when cardinality(v_txts) = 1 then v_txts[1]
                  else format('Desfiz a publicação da semana (%s): %s', public._agenda_plural(cardinality(v_txts), 'mudança', 'mudanças'),
                              array_to_string(v_txts, ' ')) end);
end;
$function$;

comment on function public.agenda_desfazer_dito(uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a palavra *desfaz* (+ o nome, o número ou "semana") — agenda_acao_desfazivel (ambíguo ou nada: a frase pronta, nada muda) + agenda_desfazer(via dono) de cada ação; "semana" é tudo ou nada. Executa direto: é a ordem exata do dono. Admin pelo _autor_da_agenda. Fase 6 (P6): o alvo "aprendizado" = o último lote de ações aprendizado desfazíveis (as do mesmo instante), tudo ou nada; o texto é o "Desfeito: …" de cada uma.';

-- agenda_saude (de 20261028100300_agenda_fase5_rodada.sql)
create or replace function public.agenda_saude(p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_cart    uuid[];
  v_ult     record;
  v_vig     jsonb;
  v_hoje    jsonb;
  v_crit    jsonb;
  v_perg    jsonb;
  v_prop    jsonb;
  v_plano   jsonb;
  v_inv     jsonb;
  v_fech    jsonb;
  v_sem     int;
  v_regra   jsonb;
  v_leu     boolean;
  v_choques int;
  -- FASE 3
  v_rot     jsonb;
  v_eq      jsonb;
  v_dia     jsonb;
  v_conc    jsonb;
  v_marcos  jsonb;
  v_com     jsonb;
  v_teto    int;
  v_janela  int;
  v_semconf int;
  v_sobre   int;
  v_semrec  int;
  v_pay     int;
  -- FASE 4: o material e a mensagem ao fornecedor
  v_mrod    jsonb;
  v_rem     jsonb;
  v_mperg   jsonb;
  v_semdono int;
  v_semorig int;
  v_prec    jsonb;
  v_det     jsonb;
  v_fsombra int;
  v_ffora   int;
  v_fteto   int;
  v_fproib  int;
  v_forn    jsonb;
  v_cob     jsonb;
  v_med     numeric;
  v_zeros4  boolean;
  v_mat     jsonb;
  -- FASE 4: fim
  -- FASE 5: a mensagem ao cliente
  v_crod    jsonb;
  v_cmsg    jsonb;
  v_caprov  jsonb;
  v_cjan    int;
  v_cdom    int;
  v_cteto   int;
  v_cint    int;
  v_cproib  int;
  v_csombra int;
  v_csemap  int;
  v_ccrit   int;
  v_cvesp   int;
  v_cdepois int;
  v_caudio  int;
  v_cmet    jsonb;
  v_zeros5  boolean;
  v_cli     jsonb;
  -- FASE 5: fim
  -- FASE 6: o aprendizado
  v_arod    record;
  v_apeq    int;
  v_afora   int;
  v_agrande int;
  v_aatras  int;
  v_asemcl  int;
  v_afat    int;
  v_amet    jsonb;
  v_zeros6  boolean;
  v_apr     jsonb;
  -- FASE 6: fim
begin
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k);

  select max(x.p_agora) as ultima, max(x.rodou_em) as rodou_em,
         count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24,
         (array_agg(x.erros order by x.p_agora desc, x.rodou_em desc))[1] as erros_ult
    into v_ult from public.agenda_vigia_rodadas x
   -- FASE 3: a rotina da equipe grava na mesma tabela (rotina = 'rotina'); a vigia é só a dela.
   where x.rotina = 'vigia';
  v_vig := jsonb_build_object(
    'ultima_rodada', v_ult.ultima, 'rodou_em', v_ult.rodou_em,
    'rodou_nas_ultimas_2h', coalesce(v_ult.ultima > p_agora - interval '2 hours', false),
    'rodadas_24h', coalesce(v_ult.n24, 0), 'erros_ultima_rodada', coalesce(v_ult.erros_ult, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'));

  select jsonb_build_object(
           'publicar', count(*) filter (where a.executada and a.tipo = 'publicar'),
           'criar', count(*) filter (where a.executada and a.tipo = 'criar'),
           'mover', count(*) filter (where a.executada and a.tipo = 'mover'),
           'cancelar', count(*) filter (where a.executada and a.tipo = 'cancelar'),
           'promover', count(*) filter (where a.executada and a.tipo = 'promover_reserva'),
           'soltar', count(*) filter (where a.executada and a.tipo = 'soltar_reserva'),
           'status', count(*) filter (where a.executada and a.tipo = 'status'),
           'resultado', count(*) filter (where a.executada and a.tipo = 'resultado'),
           'desfeitas', count(*) filter (where a.executada and a.tipo = 'desfazer'),
           'sombra', count(*) filter (where not a.executada))
    into v_hoje from public.agenda_acoes a where a.dia = p_hoje;

  -- A prova: nenhuma ação crítica executada sem a decisão registrada (o gatilho impede; isto confere).
  select count(*) into v_sem
    from public.agenda_acoes a left join public.agenda_perguntas q on q.id = a.pergunta_id
   where a.executada and a.critica and (q.id is null or q.estado <> 'respondida' or q.opcao_escolhida is null);
  -- E o erro de classificação: ação autônoma executada como não crítica que a regra diz crítica.
  select jsonb_build_object('n', count(*), 'acoes', coalesce(jsonb_agg(a.id order by a.criada_em, a.id), '[]'::jsonb)) into v_regra
    from public.agenda_acoes a
   where a.executada and not a.critica and a.origem in ('motor', 'vigia', 'conferencia')
     and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
     and public._agenda_criticidade_da_acao(a.id) is not null;
  v_crit := jsonb_build_object(
    'abertas', (select count(*) from public.agenda_perguntas q where q.critica and q.estado = 'aberta'),
    'respondidas_7d', (select count(*) from public.agenda_perguntas q
                        where q.critica and q.estado = 'respondida' and q.respondida_em > p_agora - interval '7 days'),
    'sem_decisao', v_sem, 'pela_regra_sem_decisao', (v_regra ->> 'n')::int, 'pela_regra_acoes', v_regra -> 'acoes');

  v_perg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q where q.estado = 'aberta' group by q.tipo) t), '{}'::jsonb),
    'abertas_sombra', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.modo = 'sombra'),
    'mostradas_hoje', (select count(*) from public.agenda_perguntas q
                        where (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  select jsonb_build_object(
           'abertas', count(*) filter (where p.estado = 'aberta'),
           'obsoletas_7d', count(*) filter (where p.estado = 'obsoleta' and p.criada_em > p_agora - interval '7 days'),
           'aplicadas_7d', count(*) filter (where p.estado = 'aplicada' and p.criada_em > p_agora - interval '7 days'),
           'sombra_7d', count(*) filter (where p.modo = 'sombra' and p.criada_em > p_agora - interval '7 days'))
    into v_prop from public.agenda_propostas p;

  select jsonb_build_object(
           'alocacoes_vigentes_futuras', count(*) filter (where a.dia >= p_hoje and a.resultado is null),
           'os_programadas', count(distinct a.service_order_id) filter (where a.dia >= p_hoje and a.resultado is null and a.tipo <> 'reserva'),
           'reservas', count(*) filter (where a.dia >= p_hoje and a.tipo = 'reserva'),
           'sem_registro_7d', count(*) filter (where a.resultado = 'sem_registro' and a.dia > p_hoje - 7))
    into v_plano from public.agenda_alocacoes a where a.estado in ('publicada', 'fixada');

  select count(*) into v_choques
    from public.agenda_alocacoes a join public.agenda_alocacoes b
      on b.payee_id = a.payee_id and b.id > a.id and b.periodo && a.periodo
   where a.estado in ('publicada', 'fixada') and b.estado in ('publicada', 'fixada');
  v_inv := jsonb_build_object(
    'vigente_de_os_fora_da_carteira', (select count(distinct a.service_order_id) from public.agenda_alocacoes a
                                        where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
                                          and not (a.service_order_id = any (v_cart))),
    'espelho_divergente', case when cf.modo_proposta <> 'ligado' then 0 else (
       select count(*) from public.service_orders so
        cross join lateral (select min(lower(a.periodo)) as ini, max(upper(a.periodo)) as fim from public.agenda_alocacoes a
                             where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                               and a.resultado is distinct from 'nao_cumprido') m
        where so.id = any (v_cart)
          and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = so.id)
          and (so.scheduled_start_at is distinct from m.ini or so.scheduled_end_at is distinct from m.fim)) end,
    'choques', v_choques);

  if to_regclass('public.resumo_tarde') is not null then
    execute $q$select exists (select 1 from public.resumo_tarde t
                               where t.dia = $1 and jsonb_typeof(t.detalhe -> 'agenda') = 'object'
                                 and (t.detalhe -> 'agenda' ? 'linhas_diria' or t.detalhe -> 'agenda' ? 'linhas'))$q$
      into v_leu using p_hoje;
  end if;
  v_fech := jsonb_build_object(
    'leu_o_plano_hoje', v_leu,
    'linhas_mostradas', (select count(*) from public.agenda_acoes a
                          where a.contada_via = 'fechamento' and (a.contada_em at time zone 'America/Sao_Paulo')::date = p_hoje)
                        + (select count(*) from public.agenda_perguntas q
                            where q.mostrada_via = 'fechamento' and (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  -- FASE 3: a rotina, a equipe, as diárias, a conclusão, os marcos e a comissão. Os "0 obrigatórios": acima do teto, fora
  -- da janela, diária sem confirmação, turno sobrescrito pela agenda, conclusão sem cobrança quando devia, pagamento de
  -- comissão de técnico.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'rotina:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_rot from public.agenda_vigia_rodadas x where x.rotina = 'rotina';
  select count(*) into v_teto
    from (select m.payee_id, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia, m.tipo = 'resposta' as resp, count(*) as n
            from public.agenda_equipe_mensagens m
           where m.modo = 'ligado' and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
           group by 1, 2, 3) t
   where t.n > case when t.resp then cf.equipe_respostas_dia_max else cf.equipe_proativas_dia_max end;
  -- (revisão C1) pela regra única da janela (_agenda_equipe_fora_da_janela): a resposta direta tem a dela
  select count(*) into v_janela
    from public.whatsapp_send_queue q
    left join public.agenda_equipe_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-equipe'
     and (x.id is null
          or public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.scheduled_for) is not null
          -- o que SAIU fora da janela (o worker atrasado): também conta
          or (q.sent_at is not null and public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.sent_at) is not null));
  v_eq := jsonb_build_object(
    'mensagens_hoje_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select m.tipo, count(*) as n from public.agenda_equipe_mensagens m
         where (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.tipo) t), '{}'::jsonb),
    'recusadas_hoje_por_motivo', coalesce((select jsonb_object_agg(t.recusa_motivo, t.n) from (
        select m.recusa_motivo, count(*) as n from public.agenda_equipe_mensagens m
         where m.estado = 'recusada' and (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.recusa_motivo) t), '{}'::jsonb),
    'acima_do_teto', v_teto, 'fora_da_janela', v_janela);
  select count(*) into v_semconf
    from public.agenda_acoes a
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono' and a.desfeita_em is null
     and coalesce(public._agenda_confirmacao_do_dia(a.payee_id, (a.depois ->> 'dia')::date) ->> 'estado', '') <> 'confirmada';
  select count(*) into v_sobre
    from public.agenda_acoes a left join public.work_shifts ws on ws.id = a.work_shift_id
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono'
     and (coalesce(jsonb_typeof(a.antes -> 'turno'), 'null') <> 'null' or (ws.id is not null and ws.origem <> 'agente'));
  v_dia := jsonb_build_object(
    -- (o dia de quem agiu: a.dia é o p_hoje dele; criada_em é o relógio do banco)
    'lancadas_7d', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'diaria' and a.executada and a.origem <> 'dono' and a.dia > p_hoje - 7),
    'sombra_7d', (select count(*) from public.agenda_acoes a
                   where a.tipo = 'diaria' and not a.executada and a.dia > p_hoje - 7),
    'perguntas_abertas', (select count(*) from public.agenda_perguntas q where q.tipo in ('diaria', 'diaria_ligar') and q.estado = 'aberta'),
    'sem_confirmacao', v_semconf, 'sobrescreveu_turno', v_sobre);
  -- a conclusão pela porta sem cobrança viva quando a regra da condição dá parcelas ou título (a releitura é só service_role)
  if has_function_privilege('public._os_recebiveis_da_conclusao(uuid, date)', 'execute') then
    select count(*) into v_semrec
      from (select distinct so.id, so.check_out_at
              from public.agenda_acoes a join public.service_orders so on so.id = a.service_order_id
             where a.tipo = 'concluir' and a.executada and a.desfeita_em is null and so.status in ('completed', 'invoiced')
               and so.check_out_at is not null
               and not exists (select 1 from public.receivables r where r.service_order_id = so.id and r.status <> 'cancelled')) t
     where public._os_recebiveis_da_conclusao(t.id, (t.check_out_at at time zone 'America/Sao_Paulo')::date) ->> 'motivo'
           in ('parcelas', 'titulo_unico');
  end if;
  v_conc := jsonb_build_object(
    'pela_agenda_7d', (select count(*) from public.agenda_acoes a
                        where a.tipo = 'concluir' and a.executada and a.origem in ('equipe', 'dono')
                          and a.dia > p_hoje - 7),
    'desfeitas_7d', (select count(*) from public.agenda_acoes a
                      where a.tipo = 'concluir' and a.desfeita_em > p_agora - interval '7 days'),
    'sem_recebivel_quando_devia', v_semrec);
  select jsonb_build_object(
           'concluidas_30d', count(*),
           'entregues_em_ate_5du', count(*) filter (where so.delivered_at is not null
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date,
                                        (so.delivered_at at time zone 'America/Sao_Paulo')::date) <= cf.entrega_aviso_du),
           'sem_entrega_ha_mais_de_5du', count(*) filter (where so.delivered_at is null and so.status = 'completed'
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date, p_hoje) > cf.entrega_aviso_du))
    into v_marcos
    from public.service_orders so
   where so.check_out_at > p_agora - interval '30 days'
     and exists (select 1 from public.agenda_acoes a
                  where a.service_order_id = so.id and a.tipo = 'concluir' and a.executada and a.desfeita_em is null);
  select count(*) into v_pay
    from public.payables pa
   where pa.origin = 'commission' and pa.created_at > p_agora - interval '7 days'
     and pa.payee_id in (select w.payee_id from public.work_profiles w where w.modo_pagamento = 'diaria' and w.payee_id is not null);
  v_com := jsonb_build_object('pagamento', (select c.pagamento from public.comissao_config c where c.id),
                              'payables_de_comissao_tecnico_7d', v_pay);
  -- FASE 3: fim
  -- FASE 4: o material (a nota, o Pix, o detector, o cadastro) e a mensagem ao fornecedor. Os "0 obrigatórios": linha
  -- ligada a nota ou Pix sem a palavra do dono (vinculo_sem_resposta_do_dono), previsão sem o original guardado, e na
  -- mensagem ao fornecedor: nada na fila em sombra (ou sem a mensagem registrada), nada saindo ou que saiu fora da janela,
  -- nada acima do teto, nada com valor, pagamento, OS, link ou o nome do cliente.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'material:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_mrod from public.agenda_vigia_rodadas x where x.rotina = 'material';
  select jsonb_build_object(
           'a_caminho', count(*) filter (where r.estado = 'a_caminho'),
           'sem_resposta', count(*) filter (where r.vinculo = 'sem_resposta' and r.estado <> 'descartada'),
           'ligadas_7d', count(*) filter (where r.vinculo = 'ligada' and r.respondida_em > p_agora - interval '7 days'),
           'sem_servico_7d', count(*) filter (where r.vinculo = 'sem_servico' and r.respondida_em > p_agora - interval '7 days'),
           'chegaram_7d', count(*) filter (where r.estado = 'chegou' and r.chegou_em > p_hoje - 7))
    into v_rem from public.material_remessas r;
  v_mperg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q
         where q.estado = 'aberta'
           and q.tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo')
         group by q.tipo) t), '{}'::jsonb),
    -- o teto do Pix (pix_perguntas_semana_max por semana ISO, no total), no modo de agora
    'pix_na_semana', (select count(*) from public.agenda_perguntas q
                       where q.tipo = 'pix_material'
                         and q.modo = case when cf.modo_material = 'ligado' then 'ligado' else 'sombra' end
                         and (q.criada_em at time zone 'America/Sao_Paulo')::date
                             between date_trunc('week', p_hoje)::date and date_trunc('week', p_hoje)::date + 6));
  -- a linha que a agenda ligou a uma nota ou a um Pix tem de ter a palavra do dono (ou a compra que ele já ligou)
  select count(*) into v_semdono
    from public.os_material m
   where (m.remessa_id is not null or m.fonte in ('nfe', 'pix'))
     and coalesce(m.evidencia ->> 'vinculo_por', '') not in ('dono', 'compra_ligada');
  select count(*) into v_semorig from public.os_material m where m.previsao_ate is not null and m.previsao_original is null;
  -- a precisão do detector é do administrador e do financeiro (para outro login ela lançaria 42501)
  if (select auth.uid()) is null or public.is_admin_or_financial((select auth.uid())) then
    v_prec := public.agenda_detector_precisao(p_hoje - 13, p_hoje);
  end if;
  v_det := jsonb_build_object(
    'sinais_14d', v_prec -> 'sinais', 'julgados_14d', v_prec -> 'julgados', 'certos_14d', v_prec -> 'certos',
    'precisao_14d', v_prec -> 'precisao', 'pronto_para_ligar', coalesce((v_prec ->> 'pronto_para_ligar')::boolean, false),
    'aplicados_7d', (select count(*) from public.material_sinais s where s.estado = 'aplicado' and s.dia > p_hoje - 7),
    'desfeitos_7d', (select count(*) from public.material_sinais s join public.agenda_acoes a on a.id = s.acao_id
                      where a.desfeita_em > p_agora - interval '7 days'));
  -- a mensagem ao fornecedor: o que entrou na fila sem a mensagem registrada em ligado (nada sai em sombra)
  select count(*) into v_fsombra
    from public.whatsapp_send_queue q
    left join public.agenda_fornecedor_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-fornecedor' and (x.id is null or x.modo <> 'ligado');
  v_fsombra := v_fsombra + (select count(*) from public.agenda_fornecedor_mensagens x
                             where x.modo <> 'ligado' and (x.fila_id is not null or x.estado = 'enfileirada'));
  -- o que está na fila, saindo ou saiu fora da janela da mensagem (pela regra única); o que falhou não saiu
  select count(*) into v_ffora
    from public.whatsapp_send_queue q
    join public.agenda_fornecedor_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-fornecedor'
     and ((q.status in ('pending', 'sending', 'sent')
           and public._agenda_fornecedor_fora_da_janela(x.enviar_em, q.scheduled_for) is not null)
          or (q.sent_at is not null and public._agenda_fornecedor_fora_da_janela(x.enviar_em, q.sent_at) is not null));
  -- acima do teto: o que entrou na fila (ligado), por fornecedor no dia e na semana ISO, e no dia a todos
  with ent as (
    select x.fornecedor_id as f, (x.enviar_em at time zone 'America/Sao_Paulo')::date as dia
      from public.agenda_fornecedor_mensagens x
     where x.modo = 'ligado'
       and (x.fila_id is not null
            or exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-fornecedor' and q.source_ref_id = x.id))
  )
  select (select count(*) from (select e.f, e.dia from ent e group by 1, 2 having count(*) > cf.fornecedor_dia_max) a)
       + (select count(*) from (select e.f, date_trunc('week', e.dia) from ent e group by 1, 2
                                 having count(*) > cf.fornecedor_semana_max) b)
       + (select count(*) from (select e.dia from ent e group by 1 having count(*) > cf.fornecedor_total_dia_max) t)
    into v_fteto;
  select count(*) into v_fproib
    from public.agenda_fornecedor_mensagens x
   where public._agenda_fornecedor_texto_proibido(x.texto, x.service_order_id) is not null;
  select jsonb_build_object(
           'registradas_7d', count(*),
           'enfileiradas_7d', count(*) filter (where x.estado = 'enfileirada'),
           'em_teste_7d', count(*) filter (where x.modo = 'sombra'),
           'recusadas_7d_por_motivo', coalesce((
             select jsonb_object_agg(t.recusa_motivo, t.n) from (
               select y.recusa_motivo, count(*) as n from public.agenda_fornecedor_mensagens y
                where y.estado = 'recusada' and (y.enviar_em at time zone 'America/Sao_Paulo')::date > p_hoje - 7
                group by y.recusa_motivo) t), '{}'::jsonb))
    into v_forn
    from public.agenda_fornecedor_mensagens x
   where (x.enviar_em at time zone 'America/Sao_Paulo')::date > p_hoje - 7;
  -- a cobertura: os itens críticos das OS que começam nas próximas material_inicio_dias, e quantos têm data (nível A a D)
  select jsonb_build_object(
           'itens_criticos_proximos', count(*),
           'com_previsao', count(*) filter (where e ->> 'nivel' <> 'E'),
           'pct', case when count(*) > 0 then round(100 * (count(*) filter (where e ->> 'nivel' <> 'E'))::numeric / count(*)) end)
    into v_cob
    from (select k.id from unnest(v_cart) k(id)
           where public._agenda_inicio_previsto(k.id, p_hoje) between p_hoje and p_hoje + cf.material_inicio_dias) o
    cross join lateral jsonb_array_elements(coalesce(public.os_prontidao(o.id, p_hoje) #> '{material,itens}', '[]'::jsonb)) e
   where coalesce((e ->> 'critico')::boolean, false);
  -- a espera: a mediana dos dias corridos da aprovação (a régua de os_carteira) até a 1ª compra (o dia dito ou o da OC),
  -- das OS aprovadas nos últimos 90 dias que já compraram
  select percentile_cont(0.5) within group (order by t.d) into v_med
    from (select min(coalesce(m.comprado_em, (po.created_at at time zone 'America/Sao_Paulo')::date))
                 - (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date as d
            from public.service_orders so
            join public.os_material m on m.service_order_id = so.id
            left join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
            left join public.purchase_orders po on po.id = poi.purchase_order_id and po.status <> 'cancelled'
           where so.merged_into_id is null and so.status <> 'cancelled'
             and (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date
                 between p_hoje - 90 and p_hoje
           group by so.id
          having min(coalesce(m.comprado_em, (po.created_at at time zone 'America/Sao_Paulo')::date)) is not null) t;
  v_zeros4 := v_semdono = 0 and v_semorig = 0 and v_fsombra = 0 and v_ffora = 0 and v_fteto = 0 and v_fproib = 0;
  v_mat := jsonb_build_object(
    'modos', jsonb_build_object('material', cf.modo_material, 'detector', cf.modo_detector, 'fornecedor', cf.modo_fornecedor),
    'ultima_rodada', v_mrod -> 'ultima_rodada', 'rodou_nas_ultimas_2h', v_mrod -> 'rodou_nas_ultimas_2h',
    'erros_24h', v_mrod -> 'erros_24h',
    'remessas', v_rem, 'perguntas', v_mperg,
    'vinculo_sem_resposta_do_dono', v_semdono, 'previsao_sem_original', v_semorig,
    'detector', v_det,
    'fornecedor', v_forn || jsonb_build_object('na_fila_em_sombra', v_fsombra, 'fora_da_janela', v_ffora,
                                               'acima_do_teto', v_fteto, 'com_valor_ou_cliente', v_fproib),
    'cobertura', v_cob,
    'espera', jsonb_build_object('mediana_ate_comprar_90d', v_med));
  -- FASE 4: fim
  -- FASE 5: a mensagem ao cliente — o modo, as ondas e os tipos liberados, a rodada, as mensagens e a aprovação em 7 dias.
  -- Os "0 obrigatórios" (entram no ok pelo v_zeros4, para o ok ficar igual linha a linha): nada fora da janela (nem o que
  -- saiu fora dela), nada em feriado ou domingo, nada acima do teto, nada a menos do intervalo de outra, nada com texto
  -- proibido, nada na fila em teste, nada enviado sem a aprovação dos primeiros dias, nada crítico enviado sem a opção 2,
  -- nenhuma véspera com a OS aguardando peça, nenhum aviso de atraso depois da data dita, nenhum áudio que confirmou. As
  -- métricas não reprovam.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'cliente:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_crod from public.agenda_vigia_rodadas x where x.rotina = 'cliente';
  select coalesce(jsonb_object_agg(t.tipo, jsonb_build_object('registradas', t.reg, 'aguardando', t.agu, 'enviadas', t.env,
                                                              'recusadas_por_motivo', t.rec)), '{}'::jsonb)
    into v_cmsg
    from (select m.tipo, count(*) as reg, count(*) filter (where m.estado = 'aguardando_dono') as agu,
                 count(*) filter (where m.enviada_em is not null) as env,
                 coalesce((select jsonb_object_agg(y.recusa_motivo, y.n)
                             from (select z.recusa_motivo, count(*) as n from public.agenda_cliente_mensagens z
                                    where z.tipo = m.tipo and z.estado = 'recusada' and z.criada_em > p_agora - interval '7 days'
                                    group by z.recusa_motivo) y), '{}'::jsonb) as rec
            from public.agenda_cliente_mensagens m
           where m.criada_em > p_agora - interval '7 days'
           group by m.tipo) t;
  select jsonb_build_object(
           'pedidas_abertas', count(*) filter (where m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')),
           'vencidas_7d', count(*) filter (where m.aprovacao = 'vencida' and m.criada_em > p_agora - interval '7 days'),
           'aprovadas_7d', count(*) filter (where m.aprovacao = 'aprovada' and m.aprovada_em > p_agora - interval '7 days'),
           'seguradas_7d', count(*) filter (where m.aprovacao = 'segurada' and m.aprovada_em > p_agora - interval '7 days'))
    into v_caprov from public.agenda_cliente_mensagens m where m.modo = 'ligado';
  -- a janela (a regra única): o que está na fila, saindo ou saiu fora da janela da mensagem; o feriado e o domingo à parte
  select count(*) filter (where t.f is not null), count(*) filter (where t.f in ('feriado', 'domingo'))
    into v_cjan, v_cdom
    from (select coalesce(case when q.status in ('pending', 'sending', 'sent')
                               then public._agenda_cliente_fora_da_janela(x.enviar_em, q.scheduled_for) end,
                          case when q.sent_at is not null then public._agenda_cliente_fora_da_janela(x.enviar_em, q.sent_at) end) as f
            from public.whatsapp_send_queue q
            join public.agenda_cliente_mensagens x on x.id = q.source_ref_id
           where q.source = 'agenda-cliente') t;
  -- o teto: o que entrou na fila (ligado), por cliente no dia e na semana ISO, e no dia a todos
  with ent as (
    select m.client_id as c, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia
      from public.agenda_cliente_mensagens m
     where m.modo = 'ligado' and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')
  )
  select (select count(*) from (select e.c, e.dia from ent e group by 1, 2 having count(*) > cf.cliente_dia_max) a)
       + (select count(*) from (select e.c, date_trunc('week', e.dia) from ent e group by 1, 2
                                 having count(*) > cf.cliente_semana_max) b)
       + (select count(*) from (select e.dia from ent e group by 1 having count(*) > cf.cliente_total_dia_max) t)
    into v_cteto;
  -- o intervalo: duas linhas agenda-cliente (na fila, saindo ou saídas) a menos de cliente_intervalo_min_s uma da outra
  select count(*) into v_cint
    from public.whatsapp_send_queue a
    join public.whatsapp_send_queue b
      on b.source = 'agenda-cliente' and b.id > a.id and b.status in ('pending', 'sending', 'sent')
     and abs(extract(epoch from coalesce(b.sent_at, b.scheduled_for) - coalesce(a.sent_at, a.scheduled_for)))
         < cf.cliente_intervalo_min_s
   where a.source = 'agenda-cliente' and a.status in ('pending', 'sending', 'sent');
  select count(*) into v_cproib
    from public.agenda_cliente_mensagens m where public._agenda_cliente_texto_proibido(m.texto) is not null;
  -- em teste nada entra na fila (nem linha da fila sem a mensagem registrada em ligado)
  select (select count(*) from public.whatsapp_send_queue q
            left join public.agenda_cliente_mensagens x on x.id = q.source_ref_id
           where q.source = 'agenda-cliente' and (x.id is null or x.modo <> 'ligado'))
       + (select count(*) from public.agenda_cliente_mensagens x
           where x.modo <> 'ligado' and (x.fila_id is not null or x.enviada_em is not null
                                         or x.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')))
    into v_csombra;
  -- enviada sem a aprovação do dono quando o tipo ainda não somava os dias aprovados (ou a preparada pelo dono)
  select count(*) into v_csemap
    from public.agenda_cliente_mensagens m
   where m.modo = 'ligado' and m.enviada_em is not null and m.aprovacao <> 'aprovada'
     and (m.origem <> 'rodada'
          or (cf.cliente_aprovacao_dias > 0
              and (select count(distinct (y.aprovada_em at time zone 'America/Sao_Paulo')::date)
                     from public.agenda_cliente_mensagens y
                    where y.tipo = m.tipo and y.aprovacao = 'aprovada' and y.origem = 'rodada' and y.modo = 'ligado'
                      and y.aprovada_em < m.criada_em) < cf.cliente_aprovacao_dias));
  -- a crítica enviada sem a decisão "2) eu mando o aviso escrito"
  select count(*) into v_ccrit
    from public.agenda_cliente_mensagens m
    left join public.agenda_perguntas q on q.id = m.pergunta_id
   where m.enviada_em is not null
     and (m.aprovacao = 'critica'
          or (q.tipo = 'cliente_aviso' and not (q.estado = 'respondida' and q.opcao_escolhida = 2)));
  -- a véspera (M2/M4) enviada com a OS aguardando peça (no registro, ou pela última mudança de status antes do envio)
  select count(*) into v_cvesp
    from public.agenda_cliente_mensagens m
   where m.tipo in ('vespera', 'acesso') and m.enviada_em is not null
     and (m.base ->> 'status' = 'awaiting_parts'
          or (select a.status_depois from public.agenda_acoes a
               where a.service_order_id = m.service_order_id and a.tipo = 'status' and a.executada
                 and a.criada_em <= m.enviada_em
               order by a.criada_em desc, a.id desc limit 1) = 'awaiting_parts');
  -- o aviso de atraso enviado depois da data que o cliente ouviu
  select count(*) into v_cdepois
    from public.agenda_cliente_mensagens m
   where m.tipo = 'pode_atrasar' and m.enviada_em is not null and m.base ? 'prometido_ate'
     and (m.enviada_em at time zone 'America/Sao_Paulo')::date > (m.base ->> 'prometido_ate')::date;
  select count(*) into v_caudio
    from public.agenda_cliente_respostas r where r.tipo_msg = 'audio' and r.efeito = 'confirmou';
  -- as métricas (para depois; nenhuma reprova)
  select jsonb_build_object(
    'm6_antes_da_data_pct_90d', (
      select case when count(*) > 0 then round(100 * (count(*) filter (
               where (m.enviada_em at time zone 'America/Sao_Paulo')::date <= (m.base ->> 'prometido_ate')::date))::numeric
               / count(*)) end
        from public.agenda_cliente_mensagens m
       where m.tipo = 'pode_atrasar' and m.enviada_em > p_agora - interval '90 days' and m.base ? 'prometido_ate'),
    'aprovadas_sem_segurar_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where m.aprovacao = 'aprovada'))::numeric / count(*)) end
        from public.agenda_cliente_mensagens m
       where m.modo = 'ligado' and m.aprovacao in ('aprovada', 'segurada') and m.aprovada_em > p_agora - interval '30 days'),
    'resposta_24h_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where r.recebida_em <= m.enviada_em + interval '1 day'))::numeric
               / count(*)) end
        from public.agenda_cliente_mensagens m
        left join public.agenda_cliente_respostas r on r.id = m.resposta_id
       where m.modo = 'ligado' and m.enviada_em > p_agora - interval '30 days'
         and m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')),
    'sim_automatico_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where r.efeito = 'confirmou'))::numeric / count(*)) end
        from public.agenda_cliente_respostas r
       where r.modo = 'ligado' and r.recebida_em > p_agora - interval '30 days' and r.intencao = 'confirma'),
    'opt_outs_30d', (select count(*) from public.agenda_cliente_respostas r
                      where r.intencao = 'opt_out' and r.recebida_em > p_agora - interval '30 days'),
    'falhas_de_entrega_30d', (select count(*) from public.whatsapp_send_queue q
                               where q.source = 'agenda-cliente' and q.status = 'failed'
                                 and q.created_at > p_agora - interval '30 days'),
    'idas_perdidas_por_acesso_90d', (
      select jsonb_build_object('com_aviso', count(*) filter (where t.avisado), 'sem_aviso', count(*) filter (where not t.avisado))
        from (select distinct a.service_order_id, a.dia,
                     exists (select 1 from public.agenda_cliente_mensagens m
                              where m.service_order_id = a.service_order_id and m.tipo in ('vespera', 'acesso')
                                and m.enviada_em is not null and coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) = a.dia) as avisado
                from public.agenda_alocacoes a
               where a.resultado = 'nao_cumprido' and a.motivo = 'cliente_ou_bem' and a.dia > p_hoje - 90 and a.dia <= p_hoje) t))
    into v_cmet;
  v_zeros5 := v_cjan = 0 and v_cdom = 0 and v_cteto = 0 and v_cint = 0 and v_cproib = 0 and v_csombra = 0 and v_csemap = 0
              and v_ccrit = 0 and v_cvesp = 0 and v_cdepois = 0 and v_caudio = 0;
  v_zeros4 := v_zeros4 and v_zeros5;
  v_cli := jsonb_build_object(
    'modo', cf.modo_cliente, 'tipos_ligados', to_jsonb(cf.cliente_tipos_ligados),
    'tipos_liberados', to_jsonb(array(select t from unnest(array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento',
                                                                  'pode_atrasar', 'nova_data', 'pronto', 'pronto_lembrete',
                                                                  'pos_servico', 'mudanca_no_dia']) t
                                       where public._agenda_cliente_tipo_liberado(t))),
    'ultima_rodada', v_crod -> 'ultima_rodada', 'rodou_nas_ultimas_2h', v_crod -> 'rodou_nas_ultimas_2h',
    'erros_24h', v_crod -> 'erros_24h',
    'mensagens_7d', jsonb_build_object('por_tipo', v_cmsg),
    'aprovacao', v_caprov,
    'fora_da_janela', v_cjan, 'em_feriado_ou_domingo', v_cdom, 'acima_do_teto', v_cteto, 'intervalo_curto', v_cint,
    'com_texto_proibido', v_cproib, 'na_fila_em_sombra', v_csombra, 'sem_aprovacao_no_periodo', v_csemap,
    'critica_sem_decisao', v_ccrit, 'vespera_com_os_aguardando_peca', v_cvesp, 'aviso_depois_da_data', v_cdepois,
    'audio_que_confirmou', v_caudio,
    'metricas', v_cmet);
  -- FASE 5: fim
  -- FASE 6: (P6) o aprendizado (spec-fase6 §11) — o modo, a lista, a rodada, os itens e as métricas. Os "0 obrigatórios"
  -- (entram no ok pelo v_zeros4, como os das Fases 4 e 5): nada em uso com menos medidas que o mínimo; nada que a ÚLTIMA
  -- rodada gravou em uso com o modo dela fora de ligado ou o item fora da lista dela (logo depois de o dono desligar, o leitor
  -- já devolve o padrão; a linha muda na rodada seguinte); nenhuma troca grande que entrou sozinha (as ações da vigia em 7 dias
  -- contra os limites de hoje: a regra de _agenda_aprendizado_troca_cabe, que não tem porta para quem lê a saúde); nenhuma
  -- rodada atrasada (depois da 1ª, nenhuma em 26 h); nenhuma medida sem classe; nenhum fator fora de [fator_min, fator_max].
  -- Os erros de aprender:% em 24 h e as métricas não reprovam.
  select x.p_agora, x.p_hoje, x.contagens into v_arod
    from public.agenda_vigia_rodadas x where x.rotina = 'aprender'
   order by x.p_agora desc, x.rodou_em desc, x.id desc limit 1;
  select count(*) into v_apeq
    from public.agenda_aprendizado a
   where a.estado in ('em_uso', 'pergunta', 'travado') and a.em_uso is not null and a.n < a.n_min;
  select count(*) into v_afora
    from public.agenda_aprendizado a
   where v_arod.p_agora is not null and a.estado = 'em_uso' and a.em_uso is not null and a.calculado_em >= v_arod.p_agora
     and (coalesce(v_arod.contagens ->> 'modo_aprendizado', '') <> 'ligado'
          or not coalesce(v_arod.contagens -> 'ligados' ? public._agenda_aprendizado_da_lista(a.item), false));
  select count(*) into v_agrande
    from public.agenda_acoes a
   where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada and a.criada_em > p_agora - interval '7 days'
     and not coalesce(case a.antes ->> 'item'
           when 'fator' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.fator_troca_max
           when 'mo' then (a.antes ->> 'valor')::numeric > 0
                          and abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                              / (a.antes ->> 'valor')::numeric <= cf.mo_troca_max
           when 'fornecedor_atraso' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                         <= cf.fornecedor_troca_max_du
           when 'fornecedor_prazo' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                        <= cf.fornecedor_troca_max_du
           when 'capacidade_dono' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric)
                                       <= cf.capacidade_troca_max
           when 'aviso_folga' then abs((a.depois ->> 'em_uso')::numeric - (a.antes ->> 'valor')::numeric) <= cf.aviso_troca_max_du
           when 'presenca' then a.antes ->> 'nivel' in ('fina', 'sistema')
         end, false);
  v_aatras := case when v_arod.p_agora is not null and v_arod.p_agora < p_agora - interval '26 hours' then 1 else 0 end;
  select count(*) into v_asemcl from public.agenda_medidas_os m where m.classe_bem is null or m.classe_sistema is null;
  select count(*) into v_afat
    from public.agenda_aprendizado a
   where a.item = 'fator'
     and ((a.calculado is not null and a.calculado not between cf.fator_min and cf.fator_max)
          or (a.em_uso is not null and a.em_uso not between cf.fator_min and cf.fator_max));
  -- as métricas (para depois; nenhuma reprova)
  select jsonb_build_object(
    'itens', coalesce((select jsonb_object_agg(t.item, jsonb_build_object('chaves', t.chaves, 'n_max', t.n_max, 'n_min', t.n_min,
                                                                         'estados', t.estados))
                         from (select a.item, count(*) as chaves, max(a.n) as n_max, max(a.n_min) as n_min,
                                      (select jsonb_object_agg(s.estado, s.n)
                                         from (select b.estado, count(*) as n from public.agenda_aprendizado b
                                                where b.item = a.item group by b.estado) s) as estados
                                 from public.agenda_aprendizado a group by a.item) t), '{}'::jsonb),
    'medidas', (select jsonb_build_object('total', count(*), 'validas', count(*) filter (where m.valida),
                                          'invalidas', coalesce((select jsonb_object_agg(y.motivo, y.n)
                                                                   from (select z.motivo, count(*) as n from public.agenda_medidas_os z
                                                                          where not z.valida
                                                                            and z.concluida_em > p_hoje - cf.aprender_janela_dias
                                                                          group by z.motivo) y), '{}'::jsonb))
                  from public.agenda_medidas_os m where m.concluida_em > p_hoje - cf.aprender_janela_dias),
    'trocas_30d', jsonb_build_object(
      'sozinhas', (select count(*) from public.agenda_acoes a
                    where a.tipo = 'aprendizado' and a.origem = 'vigia' and a.executada and a.criada_em > p_agora - interval '30 days'),
      'perguntas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.criada_em > p_agora - interval '30 days'),
      'decididas', (select count(*) from public.agenda_perguntas q
                     where q.tipo = 'aprendizado' and q.estado = 'respondida' and q.respondida_em > p_agora - interval '30 days'),
      'desfeitas', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - interval '30 days')),
    -- o erro do fator: das OS válidas concluídas depois que o fator da classe delas passou a valer, quantas ficaram dentro dele
    'erro_do_fator', (select case when count(*) > 0 then jsonb_build_object('dentro', count(*) filter (where t.fator <= t.uso),
                                                                           'medidas', count(*),
                                                                           'pct', round(100 * (count(*) filter (where t.fator <= t.uso))::numeric / count(*))) end
                        from (select m.fator, u.em_uso as uso
                                from public.agenda_medidas_os m
                                cross join lateral (
                                  select a.em_uso, a.em_uso_desde from public.agenda_aprendizado a
                                   where a.item = 'fator' and a.estado = 'em_uso'
                                     and a.chave in (m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                     'bem:' || m.classe_bem, 'todas')
                                   order by array_position(array[m.classe_bem || ':' || m.classe_sistema, 'sistema:' || m.classe_sistema,
                                                                 'bem:' || m.classe_bem, 'todas'], a.chave)
                                   limit 1) u
                               where m.valida and m.concluida_em >= (u.em_uso_desde at time zone 'America/Sao_Paulo')::date) t),
    -- a pontualidade com o cliente antes e depois de a folga do aviso valer
    'pontualidade_folga', (select case when f.desde is not null then jsonb_build_object(
                                     'desde', f.desde,
                                     'antes_pct', (select round(100 * avg((m.atraso_cliente_du <= 0)::int)) from public.agenda_medidas_os m
                                                    where m.atraso_cliente_du is not null and m.concluida_em < f.desde),
                                     'depois_pct', (select round(100 * avg((m.atraso_cliente_du <= 0)::int)) from public.agenda_medidas_os m
                                                     where m.atraso_cliente_du is not null and m.concluida_em >= f.desde)) end
                             from (select (min(a.em_uso_desde) at time zone 'America/Sao_Paulo')::date as desde
                                     from public.agenda_aprendizado a where a.item = 'aviso_folga' and a.em_uso is not null) f),
    -- parar (§11): o item que o dono desfez 2 vezes em 4 semanas (recomendar tirá-lo da lista; a decisão é dele)
    'desfeito_2x_em_4_semanas', coalesce((select jsonb_agg(t.item order by t.item)
                                            from (select a.antes ->> 'item' as item from public.agenda_acoes a
                                                   where a.tipo = 'aprendizado' and a.desfeita_em > p_agora - interval '28 days'
                                                   group by 1 having count(distinct a.desfeita_em) >= 2) t), '[]'::jsonb))
    into v_amet;
  v_zeros6 := v_apeq = 0 and v_afora = 0 and v_agrande = 0 and v_aatras = 0 and v_asemcl = 0 and v_afat = 0;
  v_zeros4 := v_zeros4 and v_zeros6;
  v_apr := jsonb_build_object(
    'modo', cf.modo_aprendizado, 'ligados', to_jsonb(cf.aprendizado_ligados),
    'ultima_rodada', v_arod.p_agora,
    'rodou_hoje', exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.p_hoje = p_hoje),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'aprender:%'
                     and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'em_uso_com_amostra_pequena', v_apeq, 'em_uso_fora_de_ligado', v_afora, 'troca_grande_sem_pergunta', v_agrande,
    'rodada_atrasada', v_aatras, 'medida_sem_classe', v_asemcl, 'fator_fora_dos_limites', v_afat,
    'metricas', v_amet);
  -- FASE 6: fim
  return jsonb_build_object(
    -- FASE 3: os zeros obrigatórios da execução entram no ok.
    'ok', v_sem = 0 and (v_regra ->> 'n')::int = 0 and v_choques = 0
          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0
          -- FASE 4: os zeros obrigatórios do material e da mensagem ao fornecedor entram no ok.
          and v_zeros4,
          -- FASE 4: fim
    'modos', jsonb_build_object('leitura', cf.modo_leitura, 'proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
    'vigia', v_vig, 'hoje', v_hoje, 'criticas', v_crit, 'perguntas', v_perg, 'propostas', v_prop, 'plano', v_plano,
    'invariantes', v_inv, 'fechamento', v_fech,
    -- FASE 3
    'rotina', v_rot, 'equipe', v_eq, 'diarias', v_dia, 'conclusao', v_conc, 'marcos', v_marcos, 'comissao', v_com,
    'modos_fase3', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
    -- FASE 5: a mensagem ao cliente
    'cliente', v_cli,
    -- FASE 5: fim
    -- FASE 6: o aprendizado
    'aprendizado', v_apr,
    -- FASE 6: fim
    -- FASE 4: o material
    'material', v_mat);
    -- FASE 4: fim
end;
$function$;

comment on function public.agenda_saude(date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a conferência depois de cada deploy e o painel da sombra — {ok, modos, vigia (última rodada, rodou nas últimas 2 h, erros em 24 h no app_error_logs context agenda, rodadas em 24 h), hoje (publicar, criar, mover, cancelar, promover, soltar, status, resultado, desfeitas, sombra), criticas (abertas, respondidas em 7 dias, sem_decisao e pela_regra_sem_decisao — têm de ser 0), perguntas (abertas por tipo, mostradas hoje), propostas, plano (vigentes futuras, OS programadas, reservas, sem registro em 7 dias), invariantes (vigente de OS fora da carteira, espelho divergente em ligado, choques = 0), fechamento (leu o plano hoje: resumo_tarde.detalhe.agenda; linhas mostradas)}. Leitura (invoker): authenticated (a RLS do admin vale) e service_role. Fase 3: a vigia lê só as rodadas dela (rotina = vigia); blocos rotina (última rodada, rodou nas últimas 2 h, erros 24 h), equipe (mensagens e recusas de hoje; acima_do_teto e fora_da_janela — também o que saiu fora dela — têm de ser 0), diarias (lançadas e em teste em 7 dias, perguntas abertas; sem_confirmacao e sobrescreveu_turno têm de ser 0), conclusao (pela agenda e desfeitas em 7 dias; sem_recebivel_quando_devia = 0, só para quem lê a releitura), marcos (N4), comissao (pagamento desligado; payables de comissão de técnico em 7 dias = 0) e modos_fase3; o ok inclui esses zeros. Fase 4 (P5): o bloco material — modos (material, detector, fornecedor), a rodada do material (rotina = material: última, rodou nas últimas 2 h, erros 24 h em material:%), remessas (a caminho, sem resposta, ligadas/sem serviço/chegaram em 7 dias), perguntas (as abertas da Fase 4 por tipo; pix_na_semana), detector (agenda_detector_precisao dos últimos 14 dias — só para administrador/financeiro ou sem login —, aplicados e desfeitos em 7 dias), fornecedor (registradas, enfileiradas, em teste e recusadas por motivo em 7 dias), cobertura (itens críticos das OS que começam nas próximas material_inicio_dias e quantos têm data, nível A–D), espera (mediana da aprovação à 1ª compra, OS aprovadas em 90 dias); os zeros obrigatórios entram no ok: vinculo_sem_resposta_do_dono, previsao_sem_original e, do fornecedor, na_fila_em_sombra, fora_da_janela, acima_do_teto e com_valor_ou_cliente. Fase 5 (P3): o bloco cliente — modo, tipos_ligados, tipos_liberados (somaram cliente_aprovacao_dias dias aprovados), a rodada do cliente (rotina = cliente: última, rodou nas últimas 2 h, erros 24 h em cliente:%), mensagens_7d por tipo (registradas, aguardando, enviadas, recusadas por motivo), aprovacao (pedidas abertas, vencidas, aprovadas e seguradas em 7 dias) e as métricas (M6 antes da data, aprovadas sem segurar, resposta em 1 dia, SIM automático, opt-outs, falhas de entrega, idas perdidas por acesso com e sem véspera); os zeros obrigatórios entram no ok: fora_da_janela, em_feriado_ou_domingo, acima_do_teto, intervalo_curto, com_texto_proibido, na_fila_em_sombra, sem_aprovacao_no_periodo, critica_sem_decisao, vespera_com_os_aguardando_peca, aviso_depois_da_data e audio_que_confirmou. Fase 6 (P6): a chave aprendizado — o modo, a lista, a última rodada, os erros de aprender:% em 24 h, os 6 zeros (em_uso_com_amostra_pequena, em_uso_fora_de_ligado, troca_grande_sem_pergunta, rodada_atrasada, medida_sem_classe, fator_fora_dos_limites; entram no ok) e as métricas (itens, medidas, trocas em 30 dias, o erro do fator, a pontualidade antes e depois da folga, o item desfeito 2 vezes em 4 semanas).';

-- _agenda_aprendizado_texto (de 20261029100500_agenda_fase6_cliente.sql)
create or replace function public._agenda_aprendizado_texto(p_item text, p_momento text, p_d jsonb)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_nivel  text := public._agenda_classe_texto_do_nivel(p_d ->> 'chave');
  v_calc   text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'calculado')::numeric);
  v_uso    text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'em_uso')::numeric);
  v_efet   text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'efetivo')::numeric);
  v_padrao text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'padrao')::numeric);
  v_volta  text := public._agenda_aprendizado_valor(p_item, (p_d ->> 'volta')::numeric);
  v_n      text := p_d ->> 'n';
  v_nmin   text := p_d ->> 'n_min';
  v_desde  text := public._dia_curto(nullif(p_d ->> 'desde', '')::date);
  v_trava  text := public._dia_curto(nullif(p_d ->> 'travado_ate', '')::date);
  v_dias   text := p_d ->> 'trava_dias';
  v_rotulo text;
begin
  -- FASE 6: (P2) o R$ por diária (spec-fase6 §6.2 e §6.3): a mão de obra das OS com diária ligada ÷ as diárias ligadas; o
  -- padrão é mo_por_diaria_real, e o valor entra no realista de os_duracao_sugerida ("estimar os dias pelo valor")
  if p_item = 'mo' then
    return case p_momento
      when 'foco_medindo' then format('Valor por diária: %s de %s OS com diária ligada medidas; para estimar os dias pelo valor uso %s (padrão).',
                                      v_n, v_nmin, v_padrao)
      when 'foco_sombra' then format('Em teste: cada diária rendeu %s de mão de obra (%s OS com diária ligada); para estimar os dias pelo valor uso %s (padrão).',
                                     v_calc, v_n, v_padrao)
      when 'foco_em_uso' then format('Cada diária rendeu %s de mão de obra (%s OS com diária ligada): é o que uso para estimar os dias pelo valor desde %s.',
                                     v_uso, v_n, v_desde)
      when 'foco_pergunta' then format('Cada diária rendeu %s de mão de obra (%s OS com diária ligada), e hoje uso %s para estimar os dias pelo valor: a troca espera a sua resposta.',
                                       v_calc, v_n, v_efet)
      when 'foco_travado' then format('Cada diária rendeu %s de mão de obra (%s OS com diária ligada); para estimar os dias pelo valor fico com %s até %s, como você decidiu.',
                                      v_calc, v_n, v_efet, v_trava)
      when 'acao' then format('Cada diária rendeu %s de mão de obra (%s OS): passei a estimar os dias pelo valor com %s (era %s). *desfaz aprendizado* volta.',
                              v_calc, v_n, v_calc, v_efet)
      when 'pergunta' then format('Medi a mão de obra por diária: cada diária rendeu %s (%s OS com diária ligada), e hoje eu uso %s para estimar os dias pelo valor. É uma troca grande.',
                                  v_calc, v_n, v_efet)
      when 'opcao1' then format('Passo a usar %s', v_calc)
      when 'opcao2' then format('Fico com %s', v_efet)
      when 'opcao3' then 'Volto ao padrão'
      when 'desfeito' then format('Desfeito: para estimar os dias pelo valor volto a %s por diária. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                  coalesce(v_volta, v_padrao, 'o padrão'), v_dias)
      when 'fico' then format('Combinado: fico com %s por diária. Volto a perguntar se o medido mudar muito.', v_efet)
    end;
  end if;

  -- (P2) a presença do dono (spec-fase6 §6.2 e §6.3): k = as OS da classe a que ele foi sem estar no plano (detalhe.k) e n
  -- = as OS medidas; 1 = o dia todo, 0 = o abre e fecha (o padrão). Na classe entra sozinha; em todas, sempre pergunta.
  if p_item = 'presenca' and v_nivel is not null then
    declare
      v_foi  text := format('Você foi a %s de %s %s sem estar no plano', coalesce(p_d #>> '{detalhe,k}', '0'), v_n,
                            substr(v_nivel, 4));
      v_onde text := case when p_d ->> 'chave' = 'todas' then 'por padrão' else 'nelas' end;
      v_dia  boolean := coalesce((p_d ->> 'calculado')::numeric, 0) >= 1;
      v_udia boolean := coalesce((p_d ->> 'em_uso')::numeric, 0) >= 1;
      v_edia boolean := coalesce((p_d ->> 'efetivo')::numeric, 0) >= 1;
      v_vdia boolean := coalesce((p_d ->> 'volta')::numeric, 0) >= 1;
    begin
      return case p_momento
        when 'foco_medindo' then format('%s: %s de %s OS medidas para saber se você fica o dia todo; conto com você para abrir e fechar (padrão).',
                                        public._agenda_maiuscula(v_nivel), v_n, v_nmin)
        when 'foco_sombra' then v_foi || case when v_dia then format(': em teste, eu contaria com você o dia todo %s.', v_onde)
                                              else format(': em teste, continuo contando com você só para abrir e fechar %s.', v_onde) end
        when 'foco_em_uso' then v_foi || case when v_udia then format(': conto com você o dia todo %s desde %s.', v_onde, v_desde)
                                              else format(': conto com você só para abrir e fechar %s.', v_onde) end
        when 'foco_pergunta' then v_foi || case when v_dia then ': perguntei se passo a contar com você o dia todo por padrão; espero a sua resposta.'
                                                else ': perguntei se volto a contar com você só para abrir e fechar; espero a sua resposta.' end
        when 'foco_travado' then v_foi || format('; fico com %s até %s, como você decidiu.',
                                                 case when v_edia then 'o dia todo' else 'o abre e fecha' end, v_trava)
        when 'acao' then v_foi || case when v_dia then ': passei a contar com você o dia todo nas próximas dessas OS (as que você não disse como é). *desfaz aprendizado* volta ao abre e fecha.'
                                       else ': voltei a contar com você só para abrir e fechar nas próximas dessas OS (as que você não disse como é). *desfaz aprendizado* volta ao dia todo.' end
        when 'pergunta' then v_foi || case when v_dia then '. Quer que eu conte com você o dia todo por padrão, e não só para abrir e fechar?'
                                           else '. Quer que eu volte a contar com você só para abrir e fechar por padrão?' end
        when 'opcao1' then case when v_dia then 'Sim, o dia todo (recomendo pelo medido)' else 'Sim, só abrir e fechar (recomendo pelo medido)' end
        when 'opcao2' then case when v_dia then 'Não, continuo com o abre e fecha' else 'Não, continuo com o dia todo' end
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: n%s volto a contar com você %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    v_nivel, case when v_vdia then 'o dia todo' else 'só para abrir e fechar' end, v_dias)
        when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.',
                                case when v_edia then 'o dia todo' else 'o abre e fecha' end)
      end;
    end;
  end if;
  -- FASE 6: fim
  -- FASE 6: (P3) o fornecedor (spec-fase6 §6.2 e §6.3): o atraso das entregas (padrão 0: a chegada no dia que o fornecedor
  -- diz) e o prazo da nota (da saída até a chegada; padrão = o prazo de hoje). O nome é o curto do cadastro (detalhe.nome),
  -- sem artigo; detalhe.no_prazo = as entregas no prazo; detalhe.dono = o prazo é o que o dono disse (só mede).
  if p_item in ('fornecedor_atraso', 'fornecedor_prazo') then
    declare
      v_nome  text := coalesce(p_d #>> '{detalhe,nome}', 'O fornecedor');
      v_np    text := coalesce(p_d #>> '{detalhe,no_prazo}', '0');
      v_dono  boolean := coalesce((p_d #>> '{detalhe,dono}')::boolean, false);
      v_cnum  numeric := coalesce((p_d ->> 'calculado')::numeric, 0);
      v_unum  numeric := coalesce((p_d ->> 'em_uso')::numeric, 0);
      v_vnum  numeric := coalesce((p_d ->> 'volta')::numeric, (p_d ->> 'padrao')::numeric, 0);
      -- "a chegada 2 dias úteis depois do que o fornecedor diz" / "a chegada no dia que o fornecedor diz"
      v_ccheg text := case when v_cnum > 0 then format('a chegada %s depois do que o fornecedor diz', v_calc)
                           else 'a chegada no dia que o fornecedor diz' end;
      v_ucheg text := case when v_unum > 0 then format('a chegada %s depois do que o fornecedor diz', v_uso)
                           else 'a chegada no dia que o fornecedor diz' end;
      v_echeg text := case when coalesce((p_d ->> 'efetivo')::numeric, 0) > 0
                           then format('a chegada %s depois do que o fornecedor diz', v_efet)
                           else 'a chegada no dia que o fornecedor diz' end;
      v_vcheg text := case when v_vnum > 0
                           then format('a chegada %s depois do que o fornecedor diz',
                                       public._agenda_aprendizado_valor('fornecedor_atraso', v_vnum))
                           else 'a chegada no dia que o fornecedor diz' end;
    begin
      if p_item = 'fornecedor_atraso' then
        return case p_momento
          when 'foco_medindo' then format('%s: %s de %s entregas medidas.', v_nome, v_n, v_nmin)
          when 'foco_sombra' then format('%s: %s de %s entregas no prazo%s (em teste).', v_nome, v_np, v_n,
                                         case when v_cnum > 0 then '; o atraso chega a ' || v_calc else '' end)
          when 'foco_em_uso' then format('%s: %s de %s entregas no prazo%s: conto %s (desde %s).', v_nome, v_np, v_n,
                                         case when v_unum > 0 then '; o atraso chega a ' || v_uso else '' end, v_ucheg, v_desde)
          when 'foco_pergunta' then format('%s: o atraso chega a %s (%s entregas), e hoje conto %s: a troca espera a sua resposta.',
                                           v_nome, v_calc, v_n, v_echeg)
          when 'foco_travado' then format('%s: o atraso chega a %s (%s entregas); fico com %s até %s, como você decidiu.',
                                          v_nome, v_calc, v_n, v_echeg, v_trava)
          when 'acao' then case when v_cnum > 0
                                then format('%s atrasou até %s em %s entregas: passei a contar %s. *desfaz aprendizado* volta.',
                                            v_nome, v_calc, v_n, v_ccheg)
                                else format('%s voltou a entregar no prazo (%s de %s entregas): passei a contar %s. *desfaz aprendizado* volta.',
                                            v_nome, v_np, v_n, v_ccheg) end
          when 'pergunta' then case when v_cnum > 0
                                    then format('Medi as entregas de %s: o atraso chega a %s (%s entregas), e hoje eu conto %s. É uma troca grande.',
                                                v_nome, v_calc, v_n, v_echeg)
                                    else format('Medi as entregas de %s: %s de %s no prazo, e hoje eu conto %s. É uma troca grande.',
                                                v_nome, v_np, v_n, v_echeg) end
          when 'opcao1' then format('Passo a contar %s', v_ccheg)
          when 'opcao2' then format('Fico com %s', v_echeg)
          when 'opcao3' then 'Volto ao padrão'
          when 'desfeito' then format('Desfeito: para %s volto a contar %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                      v_nome, v_vcheg, v_dias)
          when 'fico' then format('Combinado: para %s fico com %s. Volto a perguntar se o medido mudar muito.', v_nome, v_echeg)
        end;
      end if;
      -- o prazo da nota: da saída (despacho) até a chegada
      return case p_momento
        when 'foco_medindo' then case when v_dono
               then format('%s: você disse %s; medi %s notas da saída até a chegada (vale o que você disse).',
                           v_nome, coalesce(v_padrao, 'o prazo'), v_n)
               else format('%s: %s de %s notas medidas da saída até a chegada; conto %s (padrão).',
                           v_nome, v_n, v_nmin, coalesce(v_padrao, 'o prazo da classe')) end
        when 'foco_sombra' then format('Em teste: %s leva até %s da saída da nota até a chegada (%s notas); hoje conto %s (padrão).',
                                       v_nome, v_calc, v_n, coalesce(v_padrao, 'o prazo da classe'))
        when 'foco_em_uso' then format('%s leva até %s da saída da nota até a chegada (%s notas): é o prazo que uso desde %s.',
                                       v_nome, v_uso, v_n, v_desde)
        when 'foco_pergunta' then format('%s leva até %s da saída da nota até a chegada (%s notas), e hoje conto %s: a troca espera a sua resposta.',
                                         v_nome, v_calc, v_n, coalesce(v_efet, 'o prazo da classe'))
        when 'foco_travado' then format('%s leva até %s da saída da nota até a chegada (%s notas); fico com %s até %s, como você decidiu.',
                                        v_nome, v_calc, v_n, coalesce(v_efet, 'o prazo da classe'), v_trava)
        when 'acao' then format('Medi as notas de %s: da saída até a chegada levam até %s (%s notas). Passei a contar %s no lugar de %s. *desfaz aprendizado* volta.',
                                v_nome, v_calc, v_n, v_calc, coalesce(v_efet, 'o prazo da classe'))
        when 'pergunta' then format('Medi as notas de %s: da saída até a chegada levam até %s (%s notas), e hoje eu conto %s. É uma troca grande.',
                                    v_nome, v_calc, v_n, coalesce(v_efet, 'o prazo da classe'))
        when 'opcao1' then format('Passo a contar %s', v_calc)
        when 'opcao2' then format('Fico com %s', coalesce(v_efet, 'o prazo da classe'))
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: para %s volto a contar %s da saída da nota até a chegada. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    v_nome, coalesce(v_volta, v_padrao, 'o prazo da classe'), v_dias)
        when 'fico' then format('Combinado: para %s fico com %s. Volto a perguntar se o medido mudar muito.',
                                v_nome, coalesce(v_efet, 'o prazo da classe'))
      end;
    end;
  end if;
  -- FASE 6: fim
  -- FASE 6: (P4) a capacidade do dono (spec-fase6 §6.2 e §6.3): quanto dos meios-dias dele marcados no plano ele fez (a
  -- mediana das semanas: detalhe.taxa; "7 de cada 10"), nas últimas detalhe.janela semanas, e a parte da semana dele que o
  -- motor marca (o padrão é carga_max, a de todos). "Seria" no singular só em teste (o spec); "seriam" na pergunta.
  if p_item = 'capacidade_dono' then
    declare
      v_taxa numeric := (p_d #>> '{detalhe,taxa}')::numeric;
      v_dez  text := coalesce(round(v_taxa * 10)::text, '?');
      v_ult  text := case when p_d #>> '{detalhe,janela}' is null then 'Nas últimas semanas'
                          else format('Nas últimas %s semanas', p_d #>> '{detalhe,janela}') end;
      v_sems text := public._agenda_plural(coalesce((p_d ->> 'n')::int, 0), 'semana medida', 'semanas medidas');
    begin
      return case p_momento
        when 'foco_medindo' then format('A sua semana no plano: %s de %s semanas medidas; marco até %s da sua semana (padrão).',
                                        v_n, v_nmin, coalesce(v_padrao, 'a parte de todos'))
        when 'foco_sombra' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano (%s). Hoje marco até %s da sua semana; pelo medido seria %s (em teste).',
                                       v_ult, v_dez, v_sems, coalesce(v_padrao, 'a parte de todos'), v_calc)
        when 'foco_em_uso' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano (%s): marco até %s da sua semana desde %s.',
                                       v_ult, v_dez, v_sems, v_uso, v_desde)
        when 'foco_pergunta' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano (%s). Hoje marco até %s da sua semana; pelo medido seriam %s: a troca espera a sua resposta.',
                                         v_ult, v_dez, v_sems, coalesce(v_efet, v_padrao), v_calc)
        when 'foco_travado' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano (%s). Pelo medido seriam %s; fico com %s da sua semana até %s, como você decidiu.',
                                        v_ult, v_dez, v_sems, v_calc, coalesce(v_efet, v_padrao), v_trava)
        when 'acao' then format('%s você fez %s de cada 10 meios-dias seus do plano: passei a marcar até %s da sua semana (era %s). *desfaz aprendizado* volta.',
                                v_ult, v_dez, v_calc, coalesce(v_efet, v_padrao))
        when 'pergunta' then format('%s você fez %s de cada 10 meios-dias seus marcados no plano. Hoje marco até %s da sua semana; pelo medido seriam %s.',
                                    v_ult, v_dez, coalesce(v_efet, v_padrao), v_calc)
        when 'opcao1' then format('Passo a marcar até %s', v_calc)
        when 'opcao2' then format('Fico com %s', coalesce(v_efet, v_padrao))
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: volto a marcar até %s da sua semana. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    coalesce(v_volta, v_padrao, 'a parte de todos'), v_dias)
        when 'fico' then format('Combinado: fico com %s da sua semana. Volto a perguntar se o medido mudar muito.',
                                coalesce(v_efet, v_padrao))
      end;
    end;
  end if;
  -- FASE 6: fim
  -- FASE 6: (P5) a pontualidade com o cliente (só medida: só a linha do foco) e a folga do aviso de atraso (spec-fase6 §6.2
  -- e §6.3). A pontualidade lê detalhe.no_prazo e detalhe.p80_atraso_du; a folga é a faixa do aviso "com 2 dias úteis a mais"
  -- (0 = a faixa do plano, o padrão)
  if p_item = 'cliente_pontualidade' and p_momento like 'foco_%' then
    if p_momento = 'foco_medindo' then
      return format('Pontualidade: %s de %s OS com a 1ª data dita ao cliente medidas.', v_n, v_nmin);
    end if;
    return format('Pontualidade: %s de %s OS ficaram prontas até o dia dito primeiro ao cliente%s.',
                  coalesce(p_d #>> '{detalhe,no_prazo}', '0'), v_n,
                  case when coalesce((p_d #>> '{detalhe,p80_atraso_du}')::numeric, 0) > 0
                       then '; o atraso chega a ' || public._agenda_aprendizado_valor('aviso_folga', (p_d #>> '{detalhe,p80_atraso_du}')::numeric)
                       else '' end);
  end if;
  if p_item = 'aviso_folga' then
    declare
      v_cn numeric := coalesce((p_d ->> 'calculado')::numeric, 0);
      -- "a faixa com 2 dias úteis a mais" / "a faixa do plano", de cada valor
      v_fc text := case when coalesce((p_d ->> 'calculado')::numeric, 0) > 0 then format('a faixa com %s a mais', v_calc)
                        else 'a faixa do plano' end;
      v_fu text := case when coalesce((p_d ->> 'em_uso')::numeric, 0) > 0 then format('a faixa com %s a mais', v_uso)
                        else 'a faixa do plano' end;
      v_fe text := case when coalesce((p_d ->> 'efetivo')::numeric, (p_d ->> 'padrao')::numeric, 0) > 0
                        then format('a faixa com %s a mais',
                                    public._agenda_aprendizado_valor('aviso_folga', coalesce((p_d ->> 'efetivo')::numeric, (p_d ->> 'padrao')::numeric)))
                        else 'a faixa do plano' end;
      v_fv text := case when coalesce((p_d ->> 'volta')::numeric, (p_d ->> 'padrao')::numeric, 0) > 0
                        then format('a faixa com %s a mais',
                                    public._agenda_aprendizado_valor('aviso_folga', coalesce((p_d ->> 'volta')::numeric, (p_d ->> 'padrao')::numeric)))
                        else 'a faixa do plano' end;
      v_terminou text := case when coalesce((p_d ->> 'calculado')::numeric, 0) > 0
                              then format('o serviço terminou até %s depois do fim que eu disse', v_calc)
                              else 'o serviço terminou dentro da faixa que eu disse' end;
    begin
      return case p_momento
        when 'foco_medindo' then format('Avisos de atraso: %s de %s avisos medidos; dou %s (padrão).', v_n, v_nmin, v_fe)
        when 'foco_sombra' then format('Avisos de atraso: em %s, %s (em teste: eu daria %s).', v_n, v_terminou, v_fc)
        when 'foco_em_uso' then format('Avisos de atraso: em %s, %s: dou %s desde %s.', v_n, v_terminou, v_fu, v_desde)
        when 'foco_pergunta' then format('Avisos de atraso: em %s, %s, e hoje dou %s: a troca espera a sua resposta.',
                                         v_n, v_terminou, v_fe)
        when 'foco_travado' then format('Avisos de atraso: em %s, %s; fico com %s até %s, como você decidiu.',
                                        v_n, v_terminou, v_fe, v_trava)
        when 'acao' then format('Os avisos de atraso erraram para %s (%s avisos): passei a dar %s%s. *desfaz aprendizado* volta.',
                                case when v_cn > coalesce((p_d ->> 'efetivo')::numeric, 0) then 'menos' else 'mais' end,
                                v_n, v_fc,
                                case when coalesce((p_d ->> 'efetivo')::numeric, 0) > 0 then format(' (era %s)', v_fe) else '' end)
        when 'pergunta' then format('Medi os avisos de atraso: em %s, %s, e hoje eu dou %s. É uma troca grande.', v_n, v_terminou, v_fe)
        when 'opcao1' then format('Passo a dar %s', v_fc)
        when 'opcao2' then format('Fico com %s', v_fe)
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: volto a dar %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                    v_fv, v_dias)
        when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.', v_fe)
      end;
    end;
  end if;
  -- FASE 6: fim
  -- FASE 6: (P6) a carga de cada pessoa pelo plano cumprido (a revisão) e os gatilhos de um planejador mais forte (spec-fase6
  -- §6.2 e §6.3). A carga lê detalhe.mostrar (o plano cumprido das semanas que o texto diz, da mais antiga para a mais nova),
  -- detalhe.gatilho (baixo, alto ou nulo), detalhe.meta, detalhe.ppc_baixo e detalhe.ppc_alto; o planejador lê os números
  -- da semana (os_ativas, pessoas, valem, n_valem, total, limites), as semanas seguidas e a resposta da pergunta (uma vez só)
  if p_item = 'carga' then
    declare
      v_pcts  text[] := array(select public._agenda_aprendizado_valor('carga', x::numeric)
                                from jsonb_array_elements_text(coalesce(p_d #> '{detalhe,mostrar}', '[]'::jsonb))
                                     with ordinality t(x, o)
                               order by o);
      v_k     int := cardinality(array(select x from jsonb_array_elements_text(coalesce(p_d #> '{detalhe,mostrar}', '[]'::jsonb)) x));
      v_gat   text := p_d #>> '{detalhe,gatilho}';
      v_meta  text := public._agenda_aprendizado_valor('carga', (p_d #>> '{detalhe,meta}')::numeric);
      v_hoje  text := coalesce(v_efet, v_padrao);
      v_cumpr text;
    begin
      v_cumpr := case when v_k = 0 then 'O plano cumprido ainda não foi medido'
                      when v_k = 1 then format('O plano foi cumprido em %s na última semana (meta %s)', v_pcts[1], v_meta)
                      else format('O plano foi cumprido em %s nas últimas %s semanas (meta %s)', public._agenda_lista(v_pcts, null),
                                  v_k, v_meta) end;
      return case p_momento
        when 'foco_medindo' then format('O plano cumprido: %s de %s semanas medidas; marco até %s da semana de cada pessoa.',
                                        v_n, v_nmin, v_padrao)
        when 'foco_sombra' then v_cumpr || '.'
                                || case when (p_d ->> 'calculado')::numeric is distinct from (p_d ->> 'padrao')::numeric
                                        then format(' Em teste: eu perguntaria se passo a marcar até %s da semana de cada pessoa (hoje %s).',
                                                    v_calc, v_padrao)
                                        else '' end
        when 'foco_em_uso' then format('%s; marco até %s da semana de cada pessoa.', v_cumpr, v_uso)
        when 'foco_pergunta' then format('%s: perguntei se passo a marcar até %s da semana de cada pessoa (hoje %s); espera a sua resposta.',
                                         v_cumpr, v_calc, v_hoje)
        when 'foco_travado' then format('%s; fico com %s até %s, como você decidiu.', v_cumpr, v_hoje, v_trava)
        when 'acao' then format('Passei a marcar até %s da semana de cada pessoa (era %s), como você decidiu. *desfaz aprendizado* volta.',
                                v_calc, v_hoje)
        when 'pergunta' then case v_gat
          when 'alto' then format('O plano foi cumprido acima de %s em %s semanas seguidas: posso estar marcando pouco.',
                                  public._agenda_aprendizado_valor('carga', (p_d #>> '{detalhe,ppc_alto}')::numeric), v_k)
          else format('O plano foi cumprido abaixo de %s em %s semanas seguidas (%s). Recomendo marcar até %s da semana de cada pessoa (hoje %s).',
                      public._agenda_aprendizado_valor('carga', (p_d #>> '{detalhe,ppc_baixo}')::numeric), v_k,
                      array_to_string(v_pcts, ', '), v_calc, v_hoje) end
        when 'opcao1' then format('Passo para %s', v_calc)
        when 'opcao2' then format('Fico com %s', v_hoje)
        when 'opcao3' then 'Volto ao padrão'
        when 'desfeito' then format('Desfeito: volto a marcar até %s da semana de cada pessoa. Não pergunto de novo por %s dias, salvo se o plano cumprido mudar.',
                                    coalesce(v_volta, v_padrao), v_dias)
        when 'fico' then format('Combinado: fico com %s. Volto a perguntar em %s dias se o plano cumprido continuar assim.', v_hoje, v_dias)
      end;
    end;
  end if;
  if p_item = 'solver' then
    declare
      v_valem text[] := array(select x from jsonb_array_elements_text(coalesce(p_d #> '{detalhe,valem}', '[]'::jsonb)) x);
      v_base  text := format('Gatilhos de um planejador mais forte: %s de %s (%s OS ativas, %s pessoas)',
                             coalesce(p_d #>> '{detalhe,n_valem}', '0'), coalesce(p_d #>> '{detalhe,total}', '0'),
                             coalesce(p_d #>> '{detalhe,os_ativas}', '0'), coalesce(p_d #>> '{detalhe,pessoas}', '0'));
      v_resp  text := p_d #>> '{detalhe,resposta}';
      v_ja    boolean := coalesce((p_d #>> '{detalhe,perguntado}')::boolean, false);
      v_lista text;
    begin
      v_lista := public._agenda_lista(array(
        select 'de ' || case g
                 when 'os_ativas' then format('%s OS ativas', p_d #>> '{detalhe,limites,os_ativas}')
                 when 'pessoas' then format('%s pessoas', p_d #>> '{detalhe,limites,pessoas}')
                 when 'curtas_dia' then format('%s idas curtas suas por dia útil',
                                               public._agenda_num((p_d #>> '{detalhe,limites,curtas_dia}')::numeric, 1))
                 when 'descarte' then format('%s%% dos planos que eu sugeri descartados',
                                             round(100 * (p_d #>> '{detalhe,limites,descarte}')::numeric))
               end
          from unnest(v_valem) with ordinality u(g, o) order by o), null);
      return case p_momento
        when 'foco_medindo' then format('%s; medi %s de %s semanas.', v_base, v_n, v_nmin)
        when 'foco_sombra' then v_base || '.'
                                || case when (p_d ->> 'calculado')::numeric >= 1
                                        then ' Em teste: eu avisaria que vale estudar um planejador mais forte.' else '' end
        when 'foco_pergunta' then v_base || '. Perguntei se vale estudar um planejador mais forte; espera a sua resposta.'
        when 'foco_em_uso' then v_base || case when v_resp = '1' then '. Você quis ver isso; nada muda sozinho.'
                                               when v_resp = '2' then '. Você disse "agora não"; não pergunto de novo.'
                                               when v_ja then '. Já perguntei uma vez; não pergunto de novo.'
                                               else '.' end
        when 'foco_travado' then v_base || '. Você disse "agora não"; não pergunto de novo.'
        when 'pergunta' then format('Há %s semanas a agenda passa %s: vale estudar um planejador mais forte. Nada muda sozinho.',
                                    coalesce(p_d #>> '{detalhe,semanas_seguidas}', v_n), v_lista)
        when 'opcao1' then 'Quero ver isso'
        when 'opcao2' then 'Agora não'
        when 'opcao3' then 'Volto ao padrão'
        when 'acao' then 'Combinado: anotei que você quer ver um planejador mais forte. Nada muda sozinho na agenda.'
        when 'fico' then 'Combinado: agora não. Não pergunto de novo.'
        when 'desfeito' then 'Desfeito: volto a só medir os gatilhos de um planejador mais forte.'
      end;
    end;
  end if;
  -- FASE 6: fim
  -- O fator de campo (spec-fase6 §6.2 e §6.3).
  if p_item = 'fator' and v_nivel is not null then
    return case p_momento
      when 'foco_medindo' then format('%s: %s de %s OS medidas; para perguntar o que falta, uso %s o combinado (padrão).',
                                      public._agenda_maiuscula(v_nivel), v_n, v_nmin, v_padrao)
      when 'foco_sombra' then format('Em teste: %s levam até %s o combinado (%s OS); hoje seria %s, e vale %s (padrão).',
                                     v_nivel, v_calc, v_n, v_calc, v_padrao)
      when 'foco_em_uso' then format('%s levam até %s o combinado (%s OS): é o que uso desde %s.',
                                     public._agenda_maiuscula(v_nivel), v_uso, v_n, v_desde)
      when 'foco_pergunta' then format('%s levam até %s o combinado (%s OS), e hoje uso %s: a troca espera a sua resposta.',
                                       public._agenda_maiuscula(v_nivel), v_calc, v_n, v_efet)
      when 'foco_travado' then format('%s levam até %s o combinado (%s OS); fico com %s até %s, como você decidiu.',
                                      public._agenda_maiuscula(v_nivel), v_calc, v_n, v_efet, v_trava)
      when 'acao' then format('Aprendi com as OS concluídas: %s levam até %s o combinado (%s OS). Passei a usar %s no lugar de %s para perguntar o que falta. *desfaz aprendizado* volta.',
                              v_nivel, v_calc, v_n, v_calc, v_efet)
      when 'pergunta' then format('Medi %s: levam até %s o combinado (%s OS), e hoje eu uso %s. É uma troca grande.',
                                  v_nivel, v_calc, v_n, v_efet)
      when 'opcao1' then format('Passo a usar %s', v_calc)
      when 'opcao2' then format('Fico com %s', v_efet)
      when 'opcao3' then 'Volto ao padrão'
      when 'desfeito' then format('Desfeito: %s voltam a %s para perguntar o que falta. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                  v_nivel, v_volta, v_dias)
      when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.', v_efet)
    end;
  end if;

  -- Os outros itens: um texto provisório, sem jargão; o pacote de cada item (P2 a P6) recria esta função com o texto da §6.
  v_rotulo := case p_item
    when 'mo' then 'O valor de mão de obra por diária'
    when 'presenca' then 'A sua presença nas OS'
    when 'fornecedor_atraso' then 'O atraso do fornecedor'
    when 'fornecedor_prazo' then 'O prazo do fornecedor'
    when 'capacidade_dono' then 'A parte da sua semana no plano'
    when 'cliente_pontualidade' then 'A pontualidade com o cliente'
    when 'aviso_folga' then 'A folga do aviso de atraso'
    when 'carga' then 'A parte da semana de cada pessoa no plano'
    when 'solver' then 'Os sinais de um planejador mais forte'
    else 'O que eu medi' end;
  return case p_momento
    when 'foco_medindo' then format('%s: %s de %s medidas; vale %s (padrão).', v_rotulo, v_n, v_nmin, coalesce(v_padrao, 'o de hoje'))
    when 'foco_sombra' then format('Em teste: %s medido é %s (%s medidas); vale %s (padrão).',
                                   lower(left(v_rotulo, 1)) || substr(v_rotulo, 2), v_calc, v_n, coalesce(v_padrao, 'o de hoje'))
    when 'foco_em_uso' then format('%s: uso %s, pelo medido (%s medidas), desde %s.', v_rotulo, v_uso, v_n, v_desde)
    when 'foco_pergunta' then format('%s: o medido é %s (%s medidas), e hoje uso %s: a troca espera a sua resposta.',
                                     v_rotulo, v_calc, v_n, coalesce(v_efet, 'o padrão'))
    when 'foco_travado' then format('%s: o medido é %s (%s medidas); fico com %s até %s, como você decidiu.',
                                    v_rotulo, v_calc, v_n, coalesce(v_efet, 'o padrão'), v_trava)
    when 'acao' then format('Aprendi com o que aconteceu: %s passou a %s (era %s; %s medidas). *desfaz aprendizado* volta.',
                            lower(left(v_rotulo, 1)) || substr(v_rotulo, 2), v_calc, coalesce(v_efet, 'o padrão'), v_n)
    when 'pergunta' then format('Medi %s: %s (%s medidas), e hoje uso %s. É uma troca grande.',
                                lower(left(v_rotulo, 1)) || substr(v_rotulo, 2), v_calc, v_n, coalesce(v_efet, 'o padrão'))
    when 'opcao1' then format('Passo a usar %s', v_calc)
    when 'opcao2' then format('Fico com %s', coalesce(v_efet, 'o de agora'))
    when 'opcao3' then 'Volto ao padrão'
    when 'desfeito' then format('Desfeito: %s volta a %s. Não troco de novo por %s dias, salvo se o medido mudar muito.',
                                lower(left(v_rotulo, 1)) || substr(v_rotulo, 2), coalesce(v_volta, 'o padrão'), v_dias)
    when 'fico' then format('Combinado: fico com %s. Volto a perguntar se o medido mudar muito.', coalesce(v_efet, 'o padrão'))
  end;
end;
$function$;

comment on function public._agenda_aprendizado_texto(text, text, jsonb) is
  'Agenda de Produção (Fase 6): os textos do aprendizado ao dono, do banco — p_momento foco_<estado> (a linha do foco), acao (o que mudou sozinho), pergunta (a troca grande, sem as opções), opcao1/2/3, desfeito e fico. p_d: {chave, calculado, em_uso, efetivo (o que valia antes), padrao, volta, n, n_min, desde, travado_ate, trava_dias}. O fator tem os textos da spec-fase6 §6.2/§6.3; os outros itens, um texto provisório que o pacote de cada um recria (copiar DESTA definição). FASE 6 (P2): o R$ por diária (mo) e a presença do dono têm os textos da spec §6.2/§6.3 (a presença lê detalhe.k, as idas do dono). FASE 6 (P3): o atraso (fornecedor_atraso) e o prazo da nota (fornecedor_prazo) têm os textos da spec §6.2/§6.3 (o nome, as entregas no prazo e o "você disse" vêm do detalhe). FASE 6 (P4): a capacidade do dono (capacidade_dono) tem os textos da spec §6.2/§6.3 ("Nas últimas 8 semanas você fez 7 de cada 10 meios-dias seus marcados no plano …"; a taxa e a janela vêm do detalhe). FASE 6 (P5): a pontualidade com o cliente (cliente_pontualidade: só a linha do foco, "Pontualidade: 5 de 7 OS ficaram prontas até o dia dito primeiro ao cliente; o atraso chega a 2 dias úteis.") e a folga do aviso de atraso (aviso_folga: "a faixa com 2 dias úteis a mais"; 0 = a faixa do plano) têm os textos da spec §6.2/§6.3. FASE 6 (P6): a carga de cada pessoa pelo plano cumprido ("O plano foi cumprido em 52%, 55% e 48% nas últimas 3 semanas (meta 70%)."; a pergunta "abaixo de 60% em 3 semanas seguidas (…). Recomendo marcar até 70% …") e os gatilhos de um planejador mais forte ("Gatilhos de um planejador mais forte: 0 de 4 (9 OS ativas, 4 pessoas)."; a pergunta "Há 4 semanas a agenda passa de 25 OS ativas e de 6 pessoas: …") têm os textos da spec §6.2/§6.3. Todos os itens com o texto da spec.';


-- ── 9. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- A rodada: só service_role (o task-automations). Os passos, a decisão, o *desfaz* e a escrita da carga: sem grant a
-- ninguém, nem service_role (quem chama é a rodada, agenda_decidir e agenda_desfazer, todas definer).
revoke all on function public.agenda_aprender(date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_aprender(date, timestamptz) to service_role;
revoke all on function public._agenda_aprender_revisao(date, timestamptz), public._agenda_aprender_solver(date, timestamptz),
  public._agenda_aprendizado_carga(numeric, numeric, uuid, timestamptz),
  public._agenda_aprendizado_decidir(uuid, smallint, uuid, text, text, date, timestamptz),
  public._agenda_desfazer_aprendizado(uuid, uuid, text, date, timestamptz)
  from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas de antes (create or replace não as muda; repetidas aqui para a migration valer sozinha).
revoke all on function public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz) to service_role;
revoke all on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) to service_role;
revoke all on function public.agenda_desfazer_dito(uuid, text, text, date, timestamptz), public.agenda_saude(date, timestamptz),
  public._agenda_aprendizado_texto(text, text, jsonb)
  from public, anon;
grant execute on function public.agenda_desfazer_dito(uuid, text, text, date, timestamptz), public.agenda_saude(date, timestamptz),
  public._agenda_aprendizado_texto(text, text, jsonb)
  to authenticated, service_role;
