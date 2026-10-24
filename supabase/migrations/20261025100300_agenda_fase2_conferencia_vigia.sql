-- Agenda de Produção, Fase 2 ("O gestor de agenda"), pacote P3: a conferência do dia, a vigia de 15 min, a saúde e o
-- que foi contado ao dono no fechamento e no acorde.
-- Spec: scratchpad agenda-pesquisa/spec-fase2.md (§7; §3.1, §3.2, §3.3 d6–d10, d19–d21, d23). Decisões 23/10 (Autonomia).
-- Depende de 20261025100000 (tabelas), 100100 (porta e espelho), 100200 (o motor) e da Fase 1 inteira.
--
-- ═══ DDL — OK NOMEADO ═══ (só funções novas; nenhuma tabela, nenhum gatilho, nenhum dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: o motor (100200) sabe propor, aplicar e desfazer, mas ninguém o chama. Aqui entram os olhos e a rotina do
-- gestor: a conferência do dia (o dono diz *dia feito*, *dia não cliente*, *choveu*; o banco marca o resultado, o início
-- da OS pela porta e replaneja na hora), a vigia que roda a cada 15 min dentro do task-automations (publica a semana na
-- quinta às 16:30, replaneja quando algo muda, promove e solta reservas, pergunta o que só o dono sabe e manda o acorde
-- da perda de hoje ou amanhã) e a agenda_saude, a consulta que prova "ação crítica sem decisão = 0".
--
-- O QUE MUDA:
--   1. Conferência do dia: agenda_registrar_dia (resultado e motivo por meio-dia, idempotente; cumprido/parcial → porta
--      em andamento com o check-in na hora do 1º turno; parcial/não → agenda_replanejar na mesma transação; fecha a
--      pergunta da conferência), agenda_conferir_dia (o dia: o dito, a conferência aberta mais recente ou hoje),
--      agenda_choveu, agenda_desfazer_dito (a palavra *desfaz*) e agenda_replanejar (em ligado aplica o que não é
--      crítico; em sombra grava a proposta e as ações que faria, com executada = false).
--   2. agenda_vigiar(p_hoje, p_agora): 15 passos, cada um no seu bloco begin/exception (o que falha vai para
--      app_error_logs, contexto 'agenda', e os outros rodam), e uma linha em agenda_vigia_rodadas por tique. Os passos
--      de 2 a 7 seguem modo_proposta; os de 8 a 14, modo_vigia; limpeza e poda, os dois. Devolve os acordes (só com a
--      vigia ligada e a ação executada; no máximo acordes_dia_max por dia, a perda mais cedo primeiro).
--   3. agenda_saude(p_hoje, p_agora): modos, vigia, contagens do dia, críticas (sem_decisao e pela_regra_sem_decisao
--      têm de ser 0), perguntas, propostas, plano, invariantes e fechamento.
--   4. agenda_fechamento_registrar (o que o fechamento mostrou) e agenda_acorde_registrado (o acorde que saiu).
--   Auxiliares: _agenda_motivo_dito/_texto/_ajuda (o motivo LCI pelas palavras do dono), _agenda_dia_ref, _agenda_quem
--   (quem foi, com "você"), _agenda_propor_e_aplicar e _agenda_acoes_da_sombra (o motor pela vigia e pela conferência),
--   _agenda_classe_agora, _agenda_vigia_perguntar, _agenda_criticidade_da_acao e os 15 passos _agenda_vigia_*.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase2_conferencia_vigia.sql):
--   · agenda_replanejar ganha p_autor (no fim, opcional): sem login, a porta só deixa motor e vigia mudarem status sem
--     autor; o replano da conferência pode tirar a OS da agenda e precisa dizer quem pediu.
--   · agenda_registrar_dia ganha p_canal (no fim): a pergunta da conferência é respondida por whatsapp/painel/tela, e o
--     p_via do resultado é outra lista (dia_feito/conversa/tela). agenda_fechamento_registrar e agenda_acorde_registrado
--     ganham p_agora (no fim, default now()), para o teste não depender do relógio.
--   · cumprido e parcial só marcam o meio-dia que já começou: "dia feito" às 11 h deixa a tarde para depois. "Não
--     cumprido" vale para o dia inteiro (o cliente desmarcou de manhã cedo).
--   · A pergunta da conferência nasce quando o ÚLTIMO meio-dia do dia começou, não o primeiro: com o primeiro, o "dia
--     feito" das 10 h do dia seguinte (sem dia dito) cairia no dia que mal começou, e não no de ontem (d19).
--   · Reserva: promover é agenda_propor('os') sem "fixar" — o motor já deixa a OS usar a própria reserva e a cancela como
--     promovida (ação promover_reserva); "fixar" marcaria o meio-dia como pedido do dono (origem dono) e o texto diria
--     "você pediu outro dia". Soltar cancela a reserva vencida direto (ação soltar_reserva, com desfazer): pelo motor ela
--     seria recolocada mais adiante e a ação viraria "mover". O passo 3 deixa a reserva vencida para o passo 4.
--   · "Ficou pronta" (passo 5) = entrou na classe 2 desde a rodada anterior (a lista vai em
--     agenda_vigia_rodadas.contagens.material.prontas); a 1ª rodada só anota. Sem isso, toda OS pronta que não coube
--     seria reproposta a cada 15 min.
--   · A vigia não refaz, na mesma versão do plano e na mesma hora, a proposta que já tentou para a mesma OS (o motor é
--     determinístico: daria o mesmo); em sombra, não refaz a OS que já está numa proposta aberta em sombra. Sem isso, um
--     caso travado gravaria 96 propostas por dia.
--   · Em sombra nada vigente é tocado: o "sem registro" e a porta do material só agem com modo_proposta ligado; o
--     replano em sombra só grava a proposta e as ações que faria.
--   · agenda_saude reconfere a regra do que é crítico ação por ação (_agenda_criticidade_da_acao): a mesma regra de
--     _agenda_criticidade, com o "segundo atraso" contado só pelas ações ANTES da conferida — a função do motor, chamada
--     depois do fato, veria a própria ação e acusaria o 1º atraso como o segundo. erros_24h conta pela hora do banco
--     (app_error_logs.last_seen_at é now()). leu_o_plano_hoje lê resumo_tarde quando a tabela existe (null sem ela).
--   · O "pouco serviço na fila" da quinta (passo 14) fica na rodada (contagens.backlog.texto): o fechamento (P5) lê de lá;
--     a proposta publicada não muda depois de gravada.
--   · Os textos novos não põem artigo antes do nome do cliente (o banco não sabe se é "o" ou "a"): "Anotado, hoje
--     (ter 03/11): Antônio (OS-00201) feito, com você, Roberto e João." O P5 fixa as amostras do §13 sobre isto.
--
-- O QUE NÃO MUDA: nenhuma tabela, nenhum gatilho, nenhuma função das fases anteriores. Com os modos em 'desligado'
-- (produção hoje) a vigia devolve {rodou: false} e não grava nada; em 'sombra', só propostas, perguntas e ações com
-- executada = false — nada muda para ninguém.
--
-- ORDEM DE LIGAR: depois de 20261025100200 (o motor); antes de publicar o task-automations que chama agenda_vigiar.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase2_conferencia_vigia.sql (begin/rollback; a conferência, cada
-- passo da vigia com um caso positivo e um negativo, a falha forçada, a quinta das 16:29 e das 16:30, a sombra, o
-- acorde, a saúde zerada e enxergando a crítica forçada, as portas). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261025100300
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261025100300_agenda_fase2_conferencia_vigia.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261025100300', 'agenda_fase2_conferencia_vigia');"
--
-- IDEMPOTENTE: só create or replace function, revoke/grant e comment.

-- ── 0. Auxiliares de texto ─────────────────────────────────────────────────────────────────────────────

-- O motivo dito pelo dono → o código LCI de agenda_alocacoes.motivo. null = não entendi.
create or replace function public._agenda_motivo_dito(p_motivo text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  with w as (select public._agenda_normal(p_motivo) as v)
  select case
    when w.v = '' then null
    when replace(w.v, ' ', '_') in ('material', 'cliente_ou_bem', 'equipe_faltou', 'trabalho_anterior', 'informacao', 'clima',
                                    'estimativa', 'imprevisto_tecnico', 'urgencia_outra_os', 'esqueci', 'concluida_antes')
      then replace(w.v, ' ', '_')
    when w.v in ('peca', 'pecas', 'falta peca', 'falta de peca', 'faltou peca', 'faltou material', 'falta material') then 'material'
    when w.v in ('cliente', 'bem', 'barco', 'lancha', 'motorhome', 'cliente nao liberou', 'cliente desmarcou', 'cliente cancelou')
      then 'cliente_ou_bem'
    when w.v in ('equipe', 'faltou', 'faltou gente', 'nao veio', 'ninguem veio', 'falta de gente') then 'equipe_faltou'
    when w.v in ('anterior', 'servico anterior', 'outro servico atrasou') then 'trabalho_anterior'
    when w.v in ('info', 'falta informacao', 'faltou informacao') then 'informacao'
    when w.v in ('chuva', 'choveu', 'tempo', 'vento', 'mau tempo') then 'clima'
    when w.v in ('demorou', 'demorou mais') then 'estimativa'
    when w.v in ('imprevisto', 'problema', 'defeito') then 'imprevisto_tecnico'
    when w.v in ('urgencia', 'urgente', 'outra os', 'emergencia') then 'urgencia_outra_os'
    when w.v in ('esquecimento') then 'esqueci'
    when w.v in ('terminou antes', 'acabou antes', 'concluiu antes') then 'concluida_antes'
  end
  from w;
$function$;

comment on function public._agenda_motivo_dito(text) is
  'Agenda de Produção (Fase 2, P3): o motivo de um dia que não foi como no plano, pelas palavras do dono ("cliente", "chuva", "equipe", "imprevisto"…) ou pelo código, → o código LCI (material, cliente_ou_bem, equipe_faltou, trabalho_anterior, informacao, clima, estimativa, imprevisto_tecnico, urgencia_outra_os, esqueci, concluida_antes). null = não entendi.';

-- O código LCI em uma palavra para o dono.
create or replace function public._agenda_motivo_texto(p_codigo text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_codigo
    when 'material' then 'material'
    when 'cliente_ou_bem' then 'cliente'
    when 'equipe_faltou' then 'equipe'
    when 'trabalho_anterior' then 'trabalho anterior'
    when 'informacao' then 'informação'
    when 'clima' then 'chuva'
    when 'estimativa' then 'estimativa'
    when 'imprevisto_tecnico' then 'imprevisto'
    when 'urgencia_outra_os' then 'urgência em outra OS'
    when 'esqueci' then 'esqueci'
    when 'concluida_antes' then 'terminou antes'
    else p_codigo end;
$function$;

comment on function public._agenda_motivo_texto(text) is 'Agenda de Produção (Fase 2, P3): o motivo LCI em uma palavra ("cliente", "chuva", "imprevisto").';

-- O que dizer quando falta o motivo (ou não deu para entender).
create or replace function public._agenda_ajuda_do_motivo(p_resultado text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when p_resultado = 'parcial'
    then 'Me diga o motivo junto: *dia parcial imprevisto* (ou material, cliente, equipe, clima, anterior, informação, estimativa, urgência, esqueci).'
    else 'Me diga o motivo junto: *dia não cliente* (ou material, equipe, clima, imprevisto, anterior, informação, estimativa, urgência, esqueci).' end;
$function$;

comment on function public._agenda_ajuda_do_motivo(text) is 'Agenda de Produção (Fase 2, P3): a frase que pede o motivo do dia parcial ou não cumprido, com as palavras que valem.';

-- "hoje (ter 03/11)", "ontem (seg 02/11)", "na sex 30/10", "no sáb 31/10".
create or replace function public._agenda_dia_ref(p_dia date, p_hoje date)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when p_dia = p_hoje then 'hoje (' || public._dia_curto(p_dia) || ')'
              when p_dia = p_hoje - 1 then 'ontem (' || public._dia_curto(p_dia) || ')'
              when extract(isodow from p_dia) in (6, 7) then 'no ' || public._dia_curto(p_dia)
              else 'na ' || public._dia_curto(p_dia) end;
$function$;

comment on function public._agenda_dia_ref(date, date) is 'Agenda de Produção (Fase 2, P3): o dia numa frase — "hoje (ter 03/11)", "ontem (seg 02/11)", "na sex 30/10", "no sáb 31/10".';

-- Quem estava no plano de uma OS num dia: "você, Roberto e João" (o dono é "você" e vem primeiro).
create or replace function public._agenda_quem(p_os uuid, p_dia date, p_ids uuid[] default null)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  with q as (
    select a.payee_id, py.kind = 'socio' and a.payee_id is not distinct from public._agenda_dono(null) as eh_dono,
           public._agenda_nome_curto(py.name) as nome, min(lower(a.periodo)) as ini
      from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
     where a.service_order_id = p_os and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       and (p_ids is null or a.id = any (p_ids))
     group by a.payee_id, py.kind, py.name
  )
  select public._agenda_lista(array(select case when q.eh_dono then 'você' else q.nome end
                                      from q order by q.eh_dono desc, q.ini, q.nome, q.payee_id), null)
    from (select 1) x;
$function$;

comment on function public._agenda_quem(uuid, date, uuid[]) is 'Agenda de Produção (Fase 2, P3): quem estava no plano de uma OS num dia ("você, Roberto e João"), o dono primeiro e como "você"; p_ids recorta as alocações.';

-- ── 1. O motor pela vigia e pela conferência ───────────────────────────────────────────────────────────

-- As ações que o motor faria, em sombra (executada = false): uma por OS da proposta, como o agenda_aplicar faria, sem
-- tocar em alocação, status nem data.
create or replace function public._agenda_acoes_da_sombra(p_proposta uuid, p_origem text, p_autor uuid, p_hoje date,
                                                          p_agora timestamptz)
 returns uuid[]
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_p    public.agenda_propostas%rowtype;
  v_sel  jsonb;
  v_os   uuid;
  v_ncri int;
  v_ncan int;
  v_tipo text;
  v_txt  text;
  v_id   uuid;
  v_ids  uuid[] := '{}';
begin
  select * into v_p from public.agenda_propostas where id = p_proposta;
  if not found then
    raise exception 'Não encontrei essa proposta.' using errcode = 'P0002';
  end if;
  v_sel := public._agenda_itens_escolhidos(v_p.itens, null, null);
  for v_os in select distinct (e ->> 'os')::uuid from jsonb_array_elements(v_sel) e order by 1 loop
    select count(*) filter (where e ->> 'op' = 'criar'), count(*) filter (where e ->> 'op' = 'cancelar')
      into v_ncri, v_ncan
      from jsonb_array_elements(v_sel) e where (e ->> 'os')::uuid = v_os;
    v_tipo := case
      when v_p.escopo = 'semana' and v_ncri > 0 then 'publicar'
      when v_ncri > 0 and v_ncan > 0
           and not exists (select 1 from jsonb_array_elements(v_sel) e
                            where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar' and e ->> 'motivo' <> 'promovida') then 'promover_reserva'
      when v_ncri > 0 and v_ncan > 0 then 'mover'
      when v_ncri > 0 then 'criar'
      when not exists (select 1 from jsonb_array_elements(v_sel) e
                        where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar' and e ->> 'motivo' <> 'condicao_vencida') then 'soltar_reserva'
      else 'cancelar' end;
    v_txt := regexp_replace(coalesce((select string_agg(rtrim(e ->> 'texto', '.'), '; ' order by e ->> 'op' = 'cancelar', e ->> 'de')
                                        from jsonb_array_elements(v_sel) e where (e ->> 'os')::uuid = v_os), 'mudança') || '.', '\.\.$', '.');
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, proposta_id, critica,
                                     versao_antes, alocacoes_criadas, alocacoes_canceladas, status_antes, atraso_du, antes, depois,
                                     texto, motivo, autor)
    values (clock_timestamp(), p_hoje, false, p_origem, v_tipo, v_os, array[v_os], p_proposta, false, v_p.versao_base,
            array(select (x ->> 'alocacao_id')::uuid from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                   where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar' and x ->> 'alocacao_id' is not null),
            array(select (x ->> 'alocacao_id')::uuid from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                   where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar' and x ->> 'alocacao_id' is not null),
            (select so.status from public.service_orders so where so.id = v_os),
            (select max((e ->> 'atraso_du')::int) from jsonb_array_elements(v_sel) e where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar'),
            jsonb_build_object('alocacoes', (select coalesce(jsonb_agg(x order by x ->> 'dia', x ->> 'turno'), '[]'::jsonb)
                                               from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                                              where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar'),
                               'fim', (select min(e ->> 'fim_antes') from jsonb_array_elements(v_sel) e
                                        where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar')),
            jsonb_build_object('alocacoes', (select coalesce(jsonb_agg(x order by x ->> 'dia', x ->> 'turno'), '[]'::jsonb)
                                               from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                                              where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar'),
                               'fim', (select max(e ->> 'fim_depois') from jsonb_array_elements(v_sel) e
                                        where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar')),
            left(v_txt, 400),
            left((select string_agg(distinct e ->> 'motivo', ', ') from jsonb_array_elements(v_sel) e
                   where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar'), 200),
            p_autor)
    returning id into v_id;
    v_ids := v_ids || v_id;
  end loop;
  return v_ids;
end;
$function$;

comment on function public._agenda_acoes_da_sombra(uuid, text, uuid, date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): em sombra, o que o agenda_aplicar faria com uma proposta — uma linha em agenda_acoes por OS (executada = false; tipo e texto como o aplicar; os itens críticos ficam de fora), sem tocar em alocação, status nem data. Devolve os ids.';

-- Propõe e aplica (em ligado) ou grava o que faria (em sombra). O caminho único da vigia e da conferência até o motor.
create or replace function public._agenda_propor_e_aplicar(p_escopo text, p_os uuid[], p_origem text, p_autor uuid,
                                                           p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_por  text;
  v_p    jsonb;
  v_a    jsonb;
  v_ids  uuid[];
begin
  if p_origem is null or p_origem not in ('motor', 'vigia', 'conferencia', 'dono') then
    raise exception 'Origem desconhecida para replanejar: "%".', coalesce(p_origem, '') using errcode = '22023';
  end if;
  if cf.modo_proposta = 'desligado' then
    return jsonb_build_object('ok', false, 'modo', 'desligado', 'texto', 'A agenda automática está desligada: não mudo nada.');
  end if;
  -- quem "criou" a proposta: a conferência é o dono dizendo o que aconteceu
  v_por := case p_origem when 'conferencia' then 'dono' when 'dono' then 'dono' when 'vigia' then 'vigia' else 'motor' end;
  v_p := public.agenda_propor(p_escopo, null, null, p_os, '{}'::jsonb, true, v_por, p_autor, p_hoje, p_agora);
  if not coalesce((v_p ->> 'ok')::boolean, false) then
    return v_p || jsonb_build_object('modo', cf.modo_proposta);
  end if;
  if cf.modo_proposta = 'ligado' then
    v_a := public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, p_origem, p_autor, null, p_hoje, p_agora);
    if not coalesce((v_a ->> 'ok')::boolean, false) then
      -- a proposta recém-calculada não aplicou: nunca deveria acontecer (o motor valida antes de sair). Fica consultável.
      perform public.log_app_error('db', 'agenda: a proposta da ' || p_origem || ' não aplicou: ' || coalesce(v_a ->> 'texto', '?'),
                                   'agenda', p_origem || ':aplicar', 'warn',
                                   jsonb_build_object('proposta', v_p ->> 'proposta_id', 'violacoes', v_a -> 'violacoes',
                                                      'p_hoje', p_hoje, 'p_agora', p_agora));
    end if;
    return jsonb_build_object('ok', coalesce((v_a ->> 'ok')::boolean, false), 'modo', 'ligado', 'simulacao', false,
                              'proposta_id', v_p ->> 'proposta_id', 'texto', v_a ->> 'texto',
                              'acoes', coalesce(v_a -> 'acoes', '[]'::jsonb),
                              'publicadas', coalesce((v_a ->> 'publicadas')::int, 0), 'canceladas', coalesce((v_a ->> 'canceladas')::int, 0),
                              'perguntas', coalesce(v_p -> 'perguntas', '[]'::jsonb), 'fora', coalesce(v_p -> 'fora', '[]'::jsonb));
  end if;
  v_ids := public._agenda_acoes_da_sombra((v_p ->> 'proposta_id')::uuid, p_origem, p_autor, p_hoje, p_agora);
  return jsonb_build_object('ok', true, 'modo', cf.modo_proposta, 'simulacao', true, 'proposta_id', v_p ->> 'proposta_id',
                            'texto', case when cardinality(v_ids) = 0 then 'Em teste (nada foi mudado): eu não mudaria nada.'
                                          else 'Em teste (nada foi mudado): eu teria feito assim — '
                                               || (select string_agg(a.texto, ' ' order by a.criada_em, a.id)
                                                     from public.agenda_acoes a where a.id = any (v_ids)) end,
                            'acoes', to_jsonb(v_ids), 'publicadas', 0, 'canceladas', 0,
                            'perguntas', coalesce(v_p -> 'perguntas', '[]'::jsonb), 'fora', coalesce(v_p -> 'fora', '[]'::jsonb));
end;
$function$;

comment on function public._agenda_propor_e_aplicar(text, uuid[], text, uuid, date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): agenda_propor(persistir) + — em ligado — agenda_aplicar dos itens não críticos (o que não aplicou vai para app_error_logs, warn) ou — em sombra — _agenda_acoes_da_sombra (executada = false). Origens: motor, vigia, conferencia (a proposta fica criada_por dono), dono. {ok, modo, simulacao, proposta_id, texto, acoes, publicadas, canceladas, perguntas, fora}.';

create or replace function public.agenda_replanejar(p_os uuid[], p_motivo text default null, p_origem text default 'vigia',
                                                    p_hoje date default public._hoje_brt(), p_agora timestamptz default now(),
                                                    p_autor uuid default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_r     jsonb;
  v_perg  text;
begin
  if coalesce(cardinality(p_os), 0) = 0 then
    raise exception 'Diga que OS replanejar.' using errcode = '22023';
  end if;
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora para replanejar.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  v_r := public._agenda_propor_e_aplicar('replano', array(select distinct x from unnest(p_os) x order by 1), p_origem, p_autor,
                                         p_hoje, p_agora);
  -- a decisão que ficou com o dono vai junto, com as palavras da pergunta
  select string_agg(q ->> 'texto', ' ' order by q ->> 'chave') into v_perg
    from jsonb_array_elements(coalesce(v_r -> 'perguntas', '[]'::jsonb)) q;
  return v_r || jsonb_build_object('motivo', p_motivo,
    'texto', coalesce(v_r ->> 'texto', '') || coalesce(' Preciso de você: ' || v_perg, ''));
end;
$function$;

comment on function public.agenda_replanejar(uuid[], text, text, date, timestamptz, uuid) is
  'Agenda de Produção (Fase 2, P3): replaneja as OS de p_os pelo motor (agenda_propor replano, persistido). Em ligado aplica o que não é crítico (o cancelamento do que não pode mais acontecer entra; o novo encaixe crítico vira pergunta e o texto a traz); em sombra a proposta fica aberta em modo sombra e as ações que faria entram com executada = false. Origens: vigia, motor, conferencia, dono; p_autor (quem pediu) vale para a porta quando o replano vem do dono. Só service_role.';

-- ── 2. A conferência do dia ────────────────────────────────────────────────────────────────────────────

create or replace function public.agenda_registrar_dia(p_autor uuid, p_dia date, p_resultado text, p_motivo text default null,
                                                       p_os uuid default null, p_pessoas uuid[] default null,
                                                       p_via text default 'dia_feito', p_trecho text default null,
                                                       p_hoje date default public._hoje_brt(), p_agora timestamptz default now(),
                                                       p_canal text default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_autor   uuid;
  v_motivo  text;
  v_alvo    uuid[];
  v_mudou   uuid[];
  v_oss     uuid[];
  v_antes   jsonb;
  v_os      uuid;
  v_mov     uuid[] := '{}';
  v_and     text[] := '{}';
  v_partes  text[] := '{}';
  v_acoes   uuid[] := '{}';
  v_acao    uuid;
  v_check   timestamptz;
  v_porta   jsonb;
  v_rep     jsonb;
  v_txt     text;
  v_ref     text;
  v_resp    text;
  v_estado  text;
  v_msg     text;
begin
  v_autor := public._autor_da_agenda(p_autor);
  if p_resultado is null or p_resultado not in ('cumprido', 'parcial', 'nao_cumprido') then
    raise exception 'Resultado desconhecido: "%" (cumprido, parcial ou nao_cumprido).', coalesce(p_resultado, '') using errcode = '22023';
  end if;
  if p_via is null or p_via not in ('dia_feito', 'conversa', 'tela') then
    raise exception 'Caminho desconhecido para anotar o dia: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  if p_dia is null or p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia, a data de hoje ou a hora.' using errcode = '22023';
  end if;
  v_motivo := public._agenda_motivo_dito(p_motivo);
  if p_resultado in ('parcial', 'nao_cumprido') and v_motivo is null then
    return jsonb_build_object('ok', false, 'mudou', false, 'pede', 'motivo', 'texto', public._agenda_ajuda_do_motivo(p_resultado));
  end if;
  if p_dia > p_hoje then
    return jsonb_build_object('ok', false, 'mudou', false,
      'texto', public._agenda_maiuscula(public._dia_curto(p_dia)) || ' ainda não chegou: não dá para dizer como foi.');
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  v_ref := public._agenda_dia_ref(p_dia, p_hoje);
  v_resp := case when p_via = 'tela' then 'tela' when p_canal in ('whatsapp', 'painel', 'tela') then p_canal else 'whatsapp' end;

  -- O alvo: os meio-dias vigentes (sem reserva) do dia; cumprido e parcial só o que já começou.
  v_alvo := array(select a.id from public.agenda_alocacoes a
                   where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = p_dia
                     and (p_os is null or a.service_order_id = p_os)
                     and (p_pessoas is null or a.payee_id = any (p_pessoas))
                     and (p_resultado = 'nao_cumprido' or lower(a.periodo) <= p_agora)
                   order by a.service_order_id, a.turno = 'tarde', a.payee_id, a.id);
  if cardinality(v_alvo) = 0 then
    return jsonb_build_object('ok', false, 'mudou', false, 'dia', p_dia,
      'texto', case
        when exists (select 1 from public.agenda_alocacoes a
                      where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = p_dia
                        and (p_os is null or a.service_order_id = p_os) and (p_pessoas is null or a.payee_id = any (p_pessoas)))
          then format('Ainda não começou nada do plano %s.', v_ref)
        when p_os is not null then format('%s não estava no plano %s.', public._agenda_rotulo_da_os(p_os), v_ref)
        else format('Não tinha nada do plano %s.', v_ref) end);
  end if;

  -- Como estava (para a ação) e o que muda (o mesmo resultado de novo não muda nada).
  select coalesce(jsonb_object_agg(q.os, q.alocs), '{}'::jsonb) into v_antes
    from (select a.service_order_id::text as os,
                 jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'payee_id', a.payee_id, 'dia', a.dia, 'turno', a.turno,
                                              'presenca', a.presenca, 'resultado', a.resultado, 'motivo', a.motivo)
                           order by a.turno = 'tarde', a.payee_id, a.id) as alocs
            from public.agenda_alocacoes a where a.id = any (v_alvo) group by a.service_order_id) q;
  with mud as (
    update public.agenda_alocacoes a
       set resultado = p_resultado, motivo = v_motivo, resultado_em = p_agora, resultado_via = p_via,
           resultado_por = v_autor, resultado_trecho = left(nullif(btrim(coalesce(p_trecho, '')), ''), 300)
     where a.id = any (v_alvo) and (a.resultado is distinct from p_resultado or a.motivo is distinct from v_motivo)
     returning a.id, a.service_order_id)
  select coalesce(array_agg(m.id order by m.id), '{}'::uuid[]),
         coalesce(array_agg(distinct m.service_order_id), '{}'::uuid[])
    into v_mudou, v_oss
    from mud m;

  if cardinality(v_mudou) = 0 then
    return jsonb_build_object('ok', true, 'mudou', false, 'dia', p_dia,
      'texto', format('Já estava anotado %s: %s %s.', v_ref,
                      public._agenda_lista(array(select public._agenda_rotulo_da_os(x)
                                                   from unnest((select array_agg(distinct a.service_order_id)
                                                                  from public.agenda_alocacoes a where a.id = any (v_alvo))) x
                                                  order by 1), null),
                      case p_resultado when 'cumprido' then 'feito'
                                       when 'parcial' then 'em parte (' || public._agenda_motivo_texto(v_motivo) || ')'
                                       else 'não andou (' || public._agenda_motivo_texto(v_motivo) || ')' end));
  end if;

  -- Por OS: a ação (resultado), o início pela porta e o espelho.
  for v_os in select x from unnest(v_oss) x
               order by (select so.service_order_number from public.service_orders so where so.id = x) collate "C", x loop
    v_txt := format('%s, %s: %s.', public._agenda_rotulo_da_os(v_os), public._dia_curto(p_dia),
                    case p_resultado when 'cumprido' then 'feito'
                                     when 'parcial' then 'andou em parte (' || public._agenda_motivo_texto(v_motivo) || ')'
                                     else 'não andou (' || public._agenda_motivo_texto(v_motivo) || ')' end);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto,
                                     motivo, autor)
    values (clock_timestamp(), p_hoje, true, 'conferencia', 'resultado', v_os, array[v_os],
            jsonb_build_object('alocacoes', coalesce(v_antes -> v_os::text, '[]'::jsonb)),
            jsonb_build_object('resultado', p_resultado, 'motivo', v_motivo, 'via', p_via, 'dia', p_dia,
                               'alocacoes', to_jsonb(array(select a.id from public.agenda_alocacoes a
                                                            where a.id = any (v_mudou) and a.service_order_id = v_os order by a.id))),
            left(v_txt, 400), v_motivo, v_autor)
    returning id into v_acao;
    v_acoes := v_acoes || v_acao;

    if p_resultado in ('cumprido', 'parcial')
       and (select so.status from public.service_orders so where so.id = v_os)
           in ('open', 'approved', 'scheduled', 'awaiting_parts', 'awaiting_client') then
      -- o início é a hora do 1º meio-dia dela no dia (o banco deriva; ninguém grava hora dita)
      select min(lower(a.periodo)) into v_check
        from public.agenda_alocacoes a
       where a.service_order_id = v_os and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva';
      v_porta := public.os_transicionar_status(v_os, 'in_progress', 'conferencia', null, v_autor, v_check, p_hoje, p_agora);
      if coalesce((v_porta ->> 'mudou')::boolean, false) then
        v_and := v_and || public._agenda_nome_curto((select cl.name from public.service_orders so
                                                      join public.clients cl on cl.id = so.client_id where so.id = v_os));
      end if;
    end if;
    perform public._agenda_espelhar_datas(v_os, p_hoje);
    if p_resultado in ('parcial', 'nao_cumprido') then
      v_mov := v_mov || v_os;
    end if;
    v_partes := v_partes || case
      when p_resultado = 'cumprido' then format('%s feito, com %s', public._agenda_rotulo_da_os(v_os), public._agenda_quem(v_os, p_dia, v_alvo))
      when p_resultado = 'parcial' then format('%s andou em parte (%s)', public._agenda_rotulo_da_os(v_os), public._agenda_motivo_texto(v_motivo))
      when v_motivo = 'clima' then coalesce(public._agenda_nome_curto((select cl.name from public.service_orders so
                                                                         join public.clients cl on cl.id = so.client_id where so.id = v_os)),
                                            public._agenda_rotulo_da_os(v_os))
      else public._agenda_rotulo_da_os(v_os) end;
  end loop;

  -- A conferência do dia fica respondida quando nada do que começou ficou sem resultado.
  update public.agenda_perguntas q
     set estado = 'respondida', respondida_em = p_agora, respondida_por = v_autor, respondida_via = v_resp,
         resposta = left(nullif(btrim(coalesce(p_trecho, '')), ''), 500)
   where q.tipo = 'conferencia' and q.dia = p_dia and q.estado = 'aberta'
     and not exists (select 1 from public.agenda_alocacoes a
                      where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = p_dia
                        and a.resultado is null and lower(a.periodo) <= p_agora);

  -- Parcial e não cumprido: replaneja na mesma transação. Se o motor falhar, o resultado fica e a vigia tenta de novo.
  if cardinality(v_mov) > 0 then
    begin
      v_rep := public.agenda_replanejar(v_mov, v_motivo, 'conferencia', p_hoje, p_agora, v_autor);
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      perform public.log_app_error('db', 'agenda: replanejar depois da conferência falhou: ' || v_msg, 'agenda',
                                   'conferencia:replanejar', 'error',
                                   jsonb_build_object('os', to_jsonb(v_mov), 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
      v_rep := jsonb_build_object('ok', false, 'texto', 'Não consegui replanejar agora; eu tento de novo daqui a pouco.');
    end;
  end if;

  v_txt := case
    when p_resultado = 'nao_cumprido' and v_motivo = 'clima'
      then format('Anotado, %s: não deu por causa da chuva (%s).', v_ref, public._agenda_lista(v_partes, null))
    when p_resultado = 'nao_cumprido'
      then format('Anotado, %s: %s não andou (%s).', v_ref, public._agenda_lista(v_partes, null), public._agenda_motivo_texto(v_motivo))
    else format('Anotado, %s: %s.', v_ref, array_to_string(v_partes, '; ')) end
    || case when cardinality(v_and) = 1 then ' ' || v_and[1] || ' agora está em andamento.'
            when cardinality(v_and) > 1 then ' ' || public._agenda_lista(v_and, null) || ' agora estão em andamento.'
            else '' end
    || case when v_rep is null then ''
            when coalesce((v_rep ->> 'ok')::boolean, false) and v_rep ->> 'texto' like 'Nada a mudar na agenda.%'
              then ' O resto do plano fica como está.' || coalesce(nullif(substr(v_rep ->> 'texto', length('Nada a mudar na agenda.') + 1), ''), '')
            when coalesce((v_rep ->> 'ok')::boolean, false)
              then ' Replanejei: ' || regexp_replace(coalesce(v_rep ->> 'texto', ''), '^Mudei: ', '')
            else ' ' || coalesce(v_rep ->> 'texto', '') end;
  return jsonb_build_object('ok', true, 'mudou', true, 'dia', p_dia, 'texto', v_txt, 'alocacoes', cardinality(v_mudou),
                            'acoes', to_jsonb(v_acoes), 'replano', v_rep);
end;
$function$;

comment on function public.agenda_registrar_dia(uuid, date, text, text, uuid, uuid[], text, text, date, timestamptz, text) is
  'Agenda de Produção (Fase 2, P3): o que aconteceu num dia do plano — resultado (cumprido, parcial, nao_cumprido) e o motivo LCI (obrigatório para parcial e não; sem ele, a frase que pede, nada muda) nas alocações vigentes sem reserva do dia (p_os/p_pessoas recortam; cumprido e parcial só o que já começou). Idempotente: o mesmo resultado de novo não muda nada; outro corrige (vai ao histórico). Uma ação resultado por OS (origem conferencia, sem desfazer). cumprido/parcial numa OS que não começou → porta em andamento com o check-in na hora do 1º meio-dia dela no dia; parcial/não → agenda_replanejar na mesma transação (se o motor falhar, o resultado fica, o erro vai para app_error_logs e a vigia tenta de novo); a pergunta conferencia do dia fica respondida. Não cria diária. Admin pelo _autor_da_agenda.';

create or replace function public.agenda_conferir_dia(p_autor uuid, p_resultado text, p_motivo text default null,
                                                      p_quando text default null, p_canal text default 'whatsapp',
                                                      p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_autor uuid := public._autor_da_agenda(p_autor);
  v_d     jsonb;
  v_dia   date;
begin
  if p_resultado is null or p_resultado not in ('cumprido', 'parcial', 'nao_cumprido') then
    raise exception 'Resultado desconhecido: "%" (cumprido, parcial ou nao_cumprido).', coalesce(p_resultado, '') using errcode = '22023';
  end if;
  cf := public._agenda_cfg();
  if cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('ok', false, 'mudou', false, 'texto', 'Ainda não tenho plano publicado: a agenda automática está em teste.');
  end if;
  if p_resultado in ('parcial', 'nao_cumprido') and public._agenda_motivo_dito(p_motivo) is null then
    return jsonb_build_object('ok', false, 'mudou', false, 'pede', 'motivo', 'texto', public._agenda_ajuda_do_motivo(p_resultado));
  end if;
  if nullif(btrim(coalesce(p_quando, '')), '') is not null then
    begin
      v_d := public.agenda_data_dita(p_quando, p_hoje, 'passado');
    exception when sqlstate '22007' then
      return jsonb_build_object('ok', false, 'mudou', false, 'texto', sqlerrm);
    end;
    if (v_d ->> 'de') is distinct from (v_d ->> 'ate') then
      return jsonb_build_object('ok', false, 'mudou', false, 'texto', 'Diga um dia só (por exemplo "ontem" ou "segunda").');
    end if;
    v_dia := (v_d ->> 'de')::date;
  else
    -- sem dia dito: a conferência aberta mais recente; sem ela, hoje se algum meio-dia já começou (d19)
    select q.dia into v_dia from public.agenda_perguntas q
     where q.tipo = 'conferencia' and q.estado = 'aberta' and q.dia <= p_hoje
     order by q.dia desc, q.criada_em desc, q.id desc limit 1;
    if v_dia is null then
      if exists (select 1 from public.agenda_alocacoes a
                  where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = p_hoje and lower(a.periodo) <= p_agora) then
        v_dia := p_hoje;
      else
        return jsonb_build_object('ok', false, 'mudou', false, 'texto', 'Hoje ainda não começou nada do plano.');
      end if;
    end if;
  end if;
  return public.agenda_registrar_dia(v_autor, v_dia, p_resultado, p_motivo, null, null, 'dia_feito', null, p_hoje, p_agora, p_canal);
end;
$function$;

comment on function public.agenda_conferir_dia(uuid, text, text, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a entrada das palavras *dia feito*, *dia parcial <motivo>*, *dia não <motivo>* — o dia é o dito (p_quando, agenda_data_dita passado: "ontem", "segunda", "dd/mm"), senão a conferência aberta mais recente (d19), senão hoje se algum meio-dia já começou ("Hoje ainda não começou nada do plano."). Fora de modo_proposta ligado: "Ainda não tenho plano publicado: a agenda automática está em teste." (nada muda). Chama agenda_registrar_dia com todas as alocações do dia. Admin pelo _autor_da_agenda.';

create or replace function public.agenda_choveu(p_autor uuid, p_quando text default null, p_canal text default 'whatsapp',
                                                p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language sql
 volatile
 security definer
 set search_path to 'public'
as $function$
  select public.agenda_conferir_dia(p_autor, 'nao_cumprido', 'clima', p_quando, p_canal, p_hoje, p_agora);
$function$;

comment on function public.agenda_choveu(uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a palavra *choveu* — agenda_conferir_dia(nao_cumprido, clima) sobre todo o plano do dia (o dito, a conferência aberta ou hoje), com o replano de cada OS.';

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
begin
  v_ref := public.agenda_acao_desfazivel(p_alvo, p_hoje, p_agora);
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
  return jsonb_build_object('ok', true, 'mudou', true, 'acoes', v_ref -> 'acao_ids',
    'texto', case when cardinality(v_txts) = 1 then v_txts[1]
                  else format('Desfiz a publicação da semana (%s): %s', public._agenda_plural(cardinality(v_txts), 'mudança', 'mudanças'),
                              array_to_string(v_txts, ' ')) end);
end;
$function$;

comment on function public.agenda_desfazer_dito(uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a palavra *desfaz* (+ o nome, o número ou "semana") — agenda_acao_desfazivel (ambíguo ou nada: a frase pronta, nada muda) + agenda_desfazer(via dono) de cada ação; "semana" é tudo ou nada. Executa direto: é a ordem exata do dono. Admin pelo _autor_da_agenda.';

-- ── 3. A vigia: auxiliares ─────────────────────────────────────────────────────────────────────────────

-- A classe da OS agora, com a prontidão junto: {classe, motivo, condicao_tipo, condicoes, texto, pront}.
create or replace function public._agenda_classe_agora(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_pront jsonb := public.os_prontidao(p_os, p_hoje);
begin
  return public._agenda_classe_da_os(v_pront, public.agenda_meios_da_os(p_os, p_hoje), p_hoje,
           exists (select 1 from public.agenda_alocacoes a
                    where a.service_order_id = p_os and a.estado = 'fixada' and a.tipo <> 'reserva' and a.dia >= p_hoje
                      and a.resultado is null), false)
         || jsonb_build_object('pront', v_pront);
end;
$function$;

comment on function public._agenda_classe_agora(uuid, date) is 'Agenda de Produção (Fase 2, P3): _agenda_classe_da_os da OS em p_hoje (com o meio-dia fixado que ela tem), com a prontidão em pront.';

-- Uma pergunta da vigia (de fato, nunca crítica). p_uma_vez: a mesma chave nunca volta (em qualquer estado); senão só
-- não abre duas vezes. true = gravou.
create or replace function public._agenda_vigia_perguntar(p_tipo text, p_chave text, p_os uuid, p_os_material uuid, p_dia date,
                                                          p_perda date, p_texto text, p_modo text, p_agora timestamptz,
                                                          p_uma_vez boolean default true, p_os_ids uuid[] default null)
 returns boolean
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_id uuid;
begin
  if p_modo not in ('sombra', 'ligado') then
    return false;
  end if;
  if exists (select 1 from public.agenda_perguntas q
              where q.chave = left(p_chave, 200) and q.modo = p_modo and (p_uma_vez or q.estado = 'aberta')) then
    return false;
  end if;
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, os_material_id, dia, perda_em, texto, modo, criada_em)
  values (p_tipo, left(p_chave, 200), p_os, coalesce(p_os_ids, case when p_os is null then '{}'::uuid[] else array[p_os] end),
          case when p_os_material is not null and exists (select 1 from public.os_material m where m.id = p_os_material)
               then p_os_material end,
          p_dia, p_perda, left(public._agenda_corta(p_texto, 600), 600), p_modo, p_agora)
  on conflict (chave, modo) where estado = 'aberta' do nothing
  returning id into v_id;
  return v_id is not null;
end;
$function$;

comment on function public._agenda_vigia_perguntar(text, text, uuid, uuid, date, date, text, text, timestamptz, boolean, uuid[]) is
  'Agenda de Produção (Fase 2, P3): grava uma pergunta de fato da vigia (conferencia, chegou, parada, estouro, duracao, material_conferir, padrao_do_dono) no modo da vigia. p_uma_vez = a chave nunca volta, em estado nenhum; senão só não abre duas vezes. true = gravou.';

-- A vigia já tentou esta OS, nesta versão do plano e nesta hora? (o motor é determinístico: daria o mesmo) Em sombra,
-- basta a OS estar numa proposta aberta em sombra.
create or replace function public._agenda_vigia_ja_tentou(p_os uuid, p_agora timestamptz)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  with c as (select cf.modo_proposta as modo, cf.versao_plano as versao from public.agenda_config cf where cf.id)
  select exists (
    select 1 from public.agenda_propostas p, c
     where p_os = any (p.os_alvo) and p.modo = c.modo
       and ((c.modo = 'ligado' and p.criada_por = 'vigia' and p.escopo in ('os', 'replano') and p.versao_base = c.versao
             and p.criada_em > p_agora - interval '1 hour')
            or (c.modo = 'sombra' and p.estado = 'aberta')));
$function$;

comment on function public._agenda_vigia_ja_tentou(uuid, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a vigia não refaz o que acabou de tentar — em ligado, proposta da vigia (os/replano) com a OS na mesma versão do plano na última hora; em sombra, a OS já numa proposta aberta em sombra.';

-- O texto do acorde de uma ação: "Mudei a agenda de amanhã: <a ação>. *desfaz <nome>* volta como estava."
create or replace function public._agenda_texto_do_acorde(p_acao uuid, p_perda date, p_hoje date)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select format('Mudei a agenda de %s: %s', case when p_perda = p_hoje then 'hoje' when p_perda = p_hoje + 1 then 'amanhã'
                                                 else public._dia_curto(p_perda) end, a.texto)
         || case when a.desfazivel_ate is not null
                 then format(' *desfaz %s* volta como estava.',
                             coalesce(public._agenda_nome_curto(cl.name), so.service_order_number, 'isso'))
                 else '' end
    from public.agenda_acoes a
    left join public.service_orders so on so.id = a.service_order_id
    left join public.clients cl on cl.id = so.client_id
   where a.id = p_acao;
$function$;

comment on function public._agenda_texto_do_acorde(uuid, date, date) is 'Agenda de Produção (Fase 2, P3): o acorde de uma mudança feita sozinha — "Mudei a agenda de amanhã: <a frase da ação> *desfaz Vanderlei* volta como estava."';

-- ── 4. Os 15 passos da vigia (cada um devolve as contagens; a vigia os chama um a um, cada um no seu bloco) ─────

-- 1. Limpeza (os dois modos): propostas abertas de outra versão do plano (obsoleta) ou vencidas (expirada), com as
-- alocações de proposta delas; perguntas vencidas ou cuja condição sumiu (resolvida, com o fato).
create or replace function public._agenda_vigia_limpeza(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_obs   int := 0;
  v_exp   int := 0;
  v_venc  int := 0;
  v_res   int := 0;
  r       record;
  v_pront jsonb;
  v_cache jsonb := '{}'::jsonb;
  v_item  jsonb;
  v_mot   text;
  v_dono_padrao boolean;
begin
  for r in select p.id, p.versao_base, p.expira_em, p.modo from public.agenda_propostas p
            where p.estado = 'aberta' order by p.criada_em, p.id loop
    if r.modo = 'ligado' and r.versao_base < cf.versao_plano then
      update public.agenda_propostas set estado = 'obsoleta', motivo_fim = 'a agenda mudou' where id = r.id;
      v_obs := v_obs + 1;
    elsif r.expira_em < p_agora then
      update public.agenda_propostas set estado = 'expirada', motivo_fim = 'passou da validade' where id = r.id;
      v_exp := v_exp + 1;
    else
      continue;
    end if;
    delete from public.agenda_alocacoes where proposta_id = r.id and estado = 'proposta';
  end loop;

  update public.agenda_perguntas q set estado = 'vencida'
   where q.estado = 'aberta' and q.expira_em is not null and q.expira_em < p_agora;
  get diagnostics v_venc = row_count;

  v_dono_padrao := exists (select 1 from public.agenda_disponibilidade d
                            where d.payee_id = public._agenda_dono(null) and d.substituida_em is null
                              and d.dias_semana is not null and d.situacao = 'disponivel');
  for r in select q.* from public.agenda_perguntas q where q.estado = 'aberta' order by q.criada_em, q.id loop
    v_mot := null;
    if r.tipo = 'conferencia' then
      if not exists (select 1 from public.agenda_alocacoes a
                      where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = r.dia and a.resultado is null) then
        v_mot := case
          when not exists (select 1 from public.agenda_alocacoes a
                            where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = r.dia) then 'o dia saiu do plano'
          when not exists (select 1 from public.agenda_alocacoes a
                            where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = r.dia
                              and a.resultado is distinct from 'sem_registro') then 'o dia ficou sem registro'
          else 'o dia já está anotado' end;
      end if;
    elsif r.tipo = 'padrao_do_dono' then
      if v_dono_padrao then v_mot := 'você disse os dias em que fica em campo'; end if;
    elsif r.service_order_id is not null then
      v_pront := v_cache -> r.service_order_id::text;
      if v_pront is null then
        v_pront := public.os_prontidao(r.service_order_id, p_hoje);
        v_cache := v_cache || jsonb_build_object(r.service_order_id::text, v_pront);
      end if;
      if v_pront ->> 'estado' in ('concluida', 'fora_da_carteira') then
        v_mot := 'a OS saiu da carteira';
      elsif r.tipo = 'chegou' then
        select e into v_item from jsonb_array_elements(coalesce(v_pront #> '{material,itens}', '[]'::jsonb)) e
         where coalesce(e ->> 'id', e ->> 'linha') = split_part(r.chave, ':', 2) limit 1;
        if v_item is null then
          v_mot := 'a peça saiu da OS';
        elsif v_item ->> 'situacao' = 'na_mao' then
          v_mot := format('"%s" chegou', v_item ->> 'curto');
        elsif not coalesce((v_item ->> 'atrasado')::boolean, false) or (v_item ->> 'data') is distinct from split_part(r.chave, ':', 3) then
          v_mot := 'a previsão mudou';
        end if;
      elsif r.tipo = 'parada' then
        if v_pront ->> 'estado' <> 'parada' then v_mot := 'a OS voltou a andar'; end if;
      elsif r.tipo = 'estouro' then
        if v_pront ->> 'status' <> 'in_progress' then
          v_mot := 'a OS não está mais em andamento';
        elsif (public.agenda_meios_da_os(r.service_order_id, p_hoje) ->> 'total') is distinct from split_part(r.chave, ':', 3) then
          v_mot := 'o combinado mudou';
        end if;
      elsif r.tipo = 'duracao' then
        if exists (select 1 from public.os_planejamento pl
                    where pl.service_order_id = r.service_order_id and pl.dias is not null
                      and pl.estimativa_fonte in ('dono', 'aceita')) then
          v_mot := 'você disse os dias';
        end if;
      elsif r.tipo = 'material_conferir' then
        if (v_pront #>> '{material,estado}') is distinct from 'nao_conferido' then v_mot := 'o material foi conferido'; end if;
      end if;
    end if;
    if v_mot is not null then
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = left(v_mot, 200) where id = r.id;
      v_res := v_res + 1;
    end if;
  end loop;
  return jsonb_build_object('obsoletas', v_obs, 'expiradas', v_exp, 'vencidas', v_venc, 'resolvidas', v_res);
end;
$function$;

-- 2. Sem registro (proposta, só em ligado): o meio-dia que passou sem_registro_du dias úteis sem resultado.
create or replace function public._agenda_vigia_sem_registro(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf    public.agenda_config := public._agenda_cfg();
  v_lim date;
  v_n   int;
begin
  if cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('n', 0, 'pulado', 'nada vigente muda fora de ligado');
  end if;
  v_lim := public.agenda_somar_du(p_hoje, -cf.sem_registro_du);
  update public.agenda_alocacoes a
     set resultado = 'sem_registro', resultado_via = 'sistema', resultado_em = p_agora
   where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.resultado is null and a.dia <= v_lim;
  get diagnostics v_n = row_count;
  return jsonb_build_object('n', v_n, 'ate', v_lim);
end;
$function$;

-- 3. Violações (proposta): a etapa da estabilidade do motor sobre todo o vigente de hoje em diante; o que não pode mais
-- acontecer é replanejado na hora, e a perda de hoje ou do próximo dia útil vira acorde (vigia ligada).
create or replace function public._agenda_vigia_violacoes(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_cong   date := public.agenda_somar_du(p_hoje, cf.congelamento_du);
  v_escopo uuid[];
  v_cart   uuid[];
  v_info   jsonb := '{}'::jsonb;
  v_os     uuid;
  v_canc   jsonb;
  v_afet   uuid[];
  v_r      jsonb;
  v_acordes jsonb := '[]'::jsonb;
  r        record;
  v_acao   uuid;
begin
  v_escopo := array(select distinct a.service_order_id from public.agenda_alocacoes a
                     where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null order by 1);
  if cardinality(v_escopo) = 0 then
    return jsonb_build_object('os', 0, 'violadas', 0);
  end if;
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k);
  foreach v_os in array v_escopo loop
    v_info := v_info || jsonb_build_object(v_os::text, jsonb_build_object('pront', public.os_prontidao(v_os, p_hoje),
                                                                          'meios', public.agenda_meios_da_os(v_os, p_hoje)));
  end loop;
  v_canc := public._agenda_violacoes(v_escopo, v_cart, false, v_info, p_hoje, v_cong);
  -- a reserva vencida é do passo 4 (soltar)
  v_afet := array(select distinct (c ->> 'os')::uuid from jsonb_array_elements(v_canc) c
                   where (c ->> 'violada')::boolean and c ->> 'motivo' <> 'condicao_vencida' order by 1);
  v_afet := array(select x from unnest(v_afet) x where not public._agenda_vigia_ja_tentou(x, p_agora) order by 1);
  if cardinality(v_afet) = 0 then
    return jsonb_build_object('os', cardinality(v_escopo), 'violadas', 0);
  end if;
  v_r := public.agenda_replanejar(v_afet,
           (select string_agg(distinct c ->> 'motivo', ', ') from jsonb_array_elements(v_canc) c
             where (c ->> 'violada')::boolean and (c ->> 'os')::uuid = any (v_afet)),
           'vigia', p_hoje, p_agora, null);
  if cf.modo_proposta = 'ligado' and cf.modo_vigia = 'ligado' then
    for r in select (c ->> 'os')::uuid as os, min((c ->> 'dia')::date) as perda
               from jsonb_array_elements(v_canc) c
              where (c ->> 'violada')::boolean and c ->> 'motivo' <> 'condicao_vencida' and (c ->> 'dia')::date <= v_cong
                and (c ->> 'os')::uuid = any (v_afet)
              group by 1 order by 2, 1 loop
      v_acao := null;
      select a.id into v_acao from public.agenda_acoes a
       where a.id in (select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'acoes', '[]'::jsonb)) x)
         and a.service_order_id = r.os and a.executada
       order by a.criada_em, a.id limit 1;
      if v_acao is not null then
        -- o novo encaixe que ficou com o dono vai junto: é a decisão que a perda de amanhã pede
        v_acordes := v_acordes || jsonb_build_object('chave', 'agenda:' || v_acao, 'assunto', 'os:' || r.os, 'acao_id', v_acao,
                       'os', r.os, 'perda_em', r.perda,
                       'texto', public._agenda_texto_do_acorde(v_acao, r.perda, p_hoje)
                                || coalesce(' Preciso de você: ' || (select string_agg(q ->> 'texto', ' ' order by q ->> 'chave')
                                                                       from jsonb_array_elements(coalesce(v_r -> 'perguntas', '[]'::jsonb)) q
                                                                      where (q ->> 'service_order_id')::uuid = r.os), ''));
      end if;
    end loop;
  end if;
  return jsonb_build_object('os', cardinality(v_escopo), 'violadas', cardinality(v_afet), 'modo', v_r ->> 'modo',
                            'acoes', jsonb_array_length(coalesce(v_r -> 'acoes', '[]'::jsonb)),
                            'perguntas', jsonb_array_length(coalesce(v_r -> 'perguntas', '[]'::jsonb)),
                            'texto', v_r ->> 'texto', 'acordes', v_acordes);
end;
$function$;

-- 4. Reservas (proposta): a reserva condicionada cuja condição se cumpriu (a OS virou classe 1 ou 2) é promovida pelo
-- motor (que usa a própria reserva e a cancela como promovida); a que venceu (condicao_ate < hoje) sem a condição é
-- solta (a OS volta à fila).
create or replace function public._agenda_vigia_reservas(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  r       record;
  v_cl    jsonb;
  v_prom  uuid[] := '{}';
  v_sol   int := 0;
  v_r     jsonb;
  v_va    bigint;
  v_lig   boolean := cf.modo_proposta = 'ligado';
begin
  for r in select a.service_order_id as os, array_agg(a.id order by a.dia, a.turno = 'tarde', a.payee_id, a.id) as ids,
                  min(a.dia) as de, max(a.dia) as ate, min(a.condicao_ate) as cond_ate,
                  (array_agg(a.condicao order by a.dia, a.turno = 'tarde', a.id))[1] as condicao,
                  bool_or(a.estado = 'fixada') as tem_fixada,
                  jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'payee_id', a.payee_id, 'dia', a.dia, 'turno', a.turno,
                                               'presenca', a.presenca, 'estado', a.estado, 'fixado_por', a.fixado_por)
                            order by a.dia, a.turno = 'tarde', a.payee_id, a.id) as alocs
             from public.agenda_alocacoes a
            where a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.reserva_de = 'condicionada'
              and a.dia >= p_hoje and a.resultado is null
            group by a.service_order_id order by 1 loop
    v_cl := public._agenda_classe_agora(r.os, p_hoje);
    if (v_cl ->> 'classe')::int in (1, 2) then
      if not public._agenda_vigia_ja_tentou(r.os, p_agora) then
        v_prom := v_prom || r.os;
      end if;
    elsif r.cond_ate < p_hoje then
      continue when not v_lig and exists (select 1 from public.agenda_acoes x
                                           where x.service_order_id = r.os and x.tipo = 'soltar_reserva' and not x.executada
                                             and x.dia = p_hoje);
      v_va := (public._agenda_cfg()).versao_plano;
      if v_lig then
        if r.tem_fixada then perform set_config('agenda.mexe_fixado', 'on', true); end if;
        update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'condicao_vencida'
         where id = any (r.ids) and estado in ('publicada', 'fixada');
        perform set_config('agenda.mexe_fixado', 'off', true);
      end if;
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, versao_antes, versao_depois,
                                       alocacoes_canceladas, antes, depois, texto, motivo, desfazivel_ate)
      values (clock_timestamp(), p_hoje, v_lig, 'vigia', 'soltar_reserva', r.os, array[r.os], v_va,
              case when v_lig then (public._agenda_cfg()).versao_plano end,
              case when v_lig then r.ids else '{}'::uuid[] end,
              jsonb_build_object('alocacoes', r.alocs, 'condicao', r.condicao, 'condicao_ate', r.cond_ate),
              '{}'::jsonb,
              left(format('%s: soltei a reserva de %s — a condição venceu em %s.', public._agenda_rotulo_da_os(r.os),
                          public._agenda_dias_texto(array(select (x ->> 'dia')::date from jsonb_array_elements(r.alocs) x)),
                          public._dia_curto(r.cond_ate)), 400),
              'condicao_vencida', case when v_lig then p_agora + cf.desfazer_validade end);
      v_sol := v_sol + 1;
    end if;
  end loop;
  if cardinality(v_prom) > 0 then
    v_r := public._agenda_propor_e_aplicar('os', v_prom, 'vigia', null, p_hoje, p_agora);
  end if;
  return jsonb_build_object('promovidas', cardinality(v_prom), 'soltas', v_sol, 'texto', v_r ->> 'texto');
end;
$function$;

-- 5. Material completo (proposta): a OS com dia no plano que ainda está aguardando peças e já tem tudo na mão vai para
-- agendada pela porta; a OS que ficou pronta (entrou na classe 2 desde a rodada anterior) e não tem plano é encaixada.
create or replace function public._agenda_vigia_material(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf       public.agenda_config := public._agenda_cfg();
  r        record;
  v_cl     jsonb;
  v_prontas uuid[] := '{}';
  v_antes  jsonb;
  v_tem    boolean;
  v_novas  uuid[] := '{}';
  v_ag     int := 0;
  v_porta  jsonb;
  v_r      jsonb;
begin
  for r in select k.service_order_id as os, k.status from public.os_carteira(p_hoje) k order by k.numero collate "C", k.service_order_id loop
    v_cl := public._agenda_classe_agora(r.os, p_hoje);
    continue when (v_cl ->> 'classe')::int is distinct from 2;
    v_prontas := v_prontas || r.os;
    if cf.modo_proposta = 'ligado' and r.status = 'awaiting_parts' and public._agenda_os_tem_dia(r.os, p_hoje)
       and (v_cl #>> '{pront,material,estado}') = 'completo' then
      v_porta := public.os_transicionar_status(r.os, 'scheduled', 'vigia', null, null, null, p_hoje, p_agora);
      if coalesce((v_porta ->> 'mudou')::boolean, false) then v_ag := v_ag + 1; end if;
    end if;
  end loop;
  -- a lista da rodada anterior (a última que a anotou)
  select x.contagens #> '{material,prontas}' into v_antes
    from public.agenda_vigia_rodadas x
   where x.contagens -> 'material' ? 'prontas'
   order by x.p_agora desc, x.rodou_em desc, x.id desc limit 1;
  v_tem := v_antes is not null;
  if v_tem then
    v_novas := array(select o from unnest(v_prontas) o
                      where not exists (select 1 from jsonb_array_elements_text(v_antes) y where y::uuid = o)
                        and not public._agenda_os_tem_dia(o, p_hoje)
                        and not exists (select 1 from public.agenda_alocacoes a
                                         where a.service_order_id = o and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva'
                                           and a.dia >= p_hoje)
                        and not public._agenda_vigia_ja_tentou(o, p_agora)
                      order by o);
    if cardinality(v_novas) > 0 then
      v_r := public._agenda_propor_e_aplicar('os', v_novas, 'vigia', null, p_hoje, p_agora);
    end if;
  end if;
  return jsonb_build_object('prontas', to_jsonb(v_prontas), 'agendadas', v_ag, 'encaixadas', cardinality(v_novas),
                            'primeira_rodada', not v_tem, 'texto', v_r ->> 'texto');
end;
$function$;

-- 6. Dia não cumprido (proposta, só em ligado): o meio-dia parcial ou não cumprido gravado pela tela ou pela conversa
-- depois do último replano da OS (a conferência já replaneja na hora; isto é a rede).
create or replace function public._agenda_vigia_dia_nao_cumprido(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf    public.agenda_config := public._agenda_cfg();
  v_oss uuid[];
  v_r   jsonb;
begin
  if cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('os', 0, 'pulado', 'nada vigente muda fora de ligado');
  end if;
  v_oss := array(
    select distinct a.service_order_id from public.agenda_alocacoes a
     where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.resultado in ('parcial', 'nao_cumprido')
       and a.dia between p_hoje - 7 and p_hoje
       and not exists (select 1 from public.agenda_propostas p
                        where p.escopo in ('replano', 'os') and a.service_order_id = any (p.os_alvo)
                          and p.criada_em >= coalesce(a.resultado_em, '-infinity'::timestamptz))
     order by 1);
  v_oss := array(select x from unnest(v_oss) x where not public._agenda_vigia_ja_tentou(x, p_agora) order by 1);
  if cardinality(v_oss) = 0 then
    return jsonb_build_object('os', 0);
  end if;
  v_r := public.agenda_replanejar(v_oss, 'dia não cumprido', 'vigia', p_hoje, p_agora, null);
  return jsonb_build_object('os', cardinality(v_oss), 'texto', v_r ->> 'texto');
end;
$function$;

-- 7. A publicação da semana (proposta): no dia_do_plano, no 1º tique depois de hora_do_plano, uma vez só por semana e
-- modo. Em ligado publica os não críticos; em sombra a proposta fica aberta e as ações que faria entram com
-- executada = false.
create or replace function public._agenda_vigia_publicacao(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf    public.agenda_config := public._agenda_cfg();
  v_seg date := p_hoje - (extract(isodow from p_hoje)::int - 1);
  v_de  date;
  v_ate date;
  v_r   jsonb;
begin
  if extract(isodow from p_hoje)::int <> cf.dia_do_plano then
    return jsonb_build_object('publicou', false, 'motivo', 'não é o dia do plano');
  end if;
  if (p_agora at time zone 'America/Sao_Paulo')::time < cf.hora_do_plano then
    return jsonb_build_object('publicou', false, 'motivo', 'antes da hora do plano');
  end if;
  -- o mesmo período que agenda_propor('semana') calcula
  v_de := public.agenda_somar_du(v_seg + 7, 0);
  v_ate := v_seg + 7 + 5;
  if exists (select 1 from public.agenda_propostas p
              where p.escopo = 'semana' and p.criada_por = 'vigia' and p.modo = cf.modo_proposta
                and p.periodo = daterange(v_de, v_ate, '[]')) then
    return jsonb_build_object('publicou', false, 'motivo', 'a semana já saiu');
  end if;
  v_r := public._agenda_propor_e_aplicar('semana', null, 'vigia', null, p_hoje, p_agora);
  return jsonb_build_object('publicou', coalesce((v_r ->> 'ok')::boolean, false) and v_r ->> 'modo' = 'ligado',
                            'modo', v_r ->> 'modo', 'proposta_id', v_r ->> 'proposta_id', 'de', v_de, 'ate', v_ate,
                            'publicadas', coalesce((v_r ->> 'publicadas')::int, 0),
                            'acoes', jsonb_array_length(coalesce(v_r -> 'acoes', '[]'::jsonb)),
                            'perguntas', jsonb_array_length(coalesce(v_r -> 'perguntas', '[]'::jsonb)),
                            'texto', v_r ->> 'texto');
end;
$function$;

-- 8. Conferência (vigia): o dia tem plano (sem reserva) e o último meio-dia dele já começou → "Foi isso?". Uma por dia.
create or replace function public._agenda_vigia_conferencia(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_ult  timestamptz;
  v_txt  text;
  v_oss  uuid[];
  v_dono uuid := public._agenda_dono(null);
begin
  if cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('criada', false, 'motivo', 'sem plano publicado');
  end if;
  select max(lower(a.periodo)) into v_ult from public.agenda_alocacoes a
   where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = p_hoje;
  if v_ult is null then
    return jsonb_build_object('criada', false, 'motivo', 'hoje não tem plano');
  end if;
  if v_ult > p_agora then
    return jsonb_build_object('criada', false, 'motivo', 'o último meio-dia de hoje ainda não começou');
  end if;
  if not exists (select 1 from public.agenda_alocacoes a
                  where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = p_hoje and a.resultado is null) then
    return jsonb_build_object('criada', false, 'motivo', 'o dia já está anotado');
  end if;
  v_oss := array(select distinct a.service_order_id from public.agenda_alocacoes a
                  where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = p_hoje);
  select 'Agenda de hoje: ' || string_agg(q.txt, '; ' order by q.ini, q.numero collate "C")
         || '. Foi isso? Responda *dia feito* ou conte o que mudou.'
    into v_txt
    from (select public._agenda_rotulo_da_os(a.service_order_id) || ' — '
                 || public._agenda_pessoas_texto(jsonb_agg(jsonb_build_object('payee_id', a.payee_id,
                                                   'nome', public._agenda_nome_curto(py.name), 'dia', a.dia, 'turno', a.turno,
                                                   'presenca', a.presenca)), v_dono) as txt,
                 min(lower(a.periodo)) as ini, min(so.service_order_number) as numero
            from public.agenda_alocacoes a
            join public.payees py on py.id = a.payee_id
            join public.service_orders so on so.id = a.service_order_id
           where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = p_hoje
           group by a.service_order_id) q;
  return jsonb_build_object('criada', public._agenda_vigia_perguntar('conferencia', 'conferencia:' || p_hoje, null, null, p_hoje, p_hoje,
                                                                     v_txt, cf.modo_vigia, p_agora, true, v_oss));
end;
$function$;

-- 9. Chegou? (vigia): item crítico com a previsão vencida e sem chegada (ou comprado sem previsão, vencido pela classe
-- do fornecedor). Uma vez por previsão.
create or replace function public._agenda_vigia_chegou(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf    public.agenda_config := public._agenda_cfg();
  r     record;
  v_p   jsonb;
  e     jsonb;
  v_n   int := 0;
  v_ref text;
begin
  for r in select k.service_order_id as os from public.os_carteira(p_hoje) k order by k.numero collate "C", k.service_order_id loop
    v_p := public.os_prontidao(r.os, p_hoje);
    for e in select x from jsonb_array_elements(coalesce(v_p #> '{material,itens}', '[]'::jsonb)) with ordinality t(x, o)
              where coalesce((x ->> 'critico')::boolean, true) and coalesce((x ->> 'atrasado')::boolean, false) order by o loop
      v_ref := coalesce(e ->> 'id', e ->> 'linha');
      continue when v_ref is null or e ->> 'data' is null;
      if public._agenda_vigia_perguntar('chegou', format('chegou:%s:%s', v_ref, e ->> 'data'), r.os, (e ->> 'id')::uuid, null,
           (v_p #>> '{plano,proximo_dia}')::date,
           format('%s: "%s" tinha previsão para %s. Chegou?', public._agenda_rotulo_da_os(r.os), e ->> 'curto',
                  public._dia_curto((e ->> 'data')::date)),
           cf.modo_vigia, p_agora) then
        v_n := v_n + 1;
      end if;
    end loop;
  end loop;
  return jsonb_build_object('criadas', v_n);
end;
$function$;

-- 10. Parada? (vigia): em andamento, sem evidência há parada_du dias úteis e sem dia no plano (substitui a R2).
create or replace function public._agenda_vigia_parada(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf  public.agenda_config := public._agenda_cfg();
  r   record;
  v_p jsonb;
  v_n int := 0;
begin
  for r in select k.service_order_id as os from public.os_carteira(p_hoje) k
            where k.status = 'in_progress' order by k.numero collate "C", k.service_order_id loop
    v_p := public.os_prontidao(r.os, p_hoje);
    continue when v_p ->> 'estado' is distinct from 'parada';
    -- (a evidência é a diária, o dia feito ou o início: o texto da Fase 1, "sem diária", só fala da diária)
    if public._agenda_vigia_perguntar('parada', format('parada:%s:%s', r.os, coalesce(v_p ->> 'ultima_evidencia', 'nunca')), r.os, null,
         null, null,
         case when v_p ->> 'ultima_evidencia' is null
              then format('%s está em andamento e não tem nada anotado. Parou?', public._agenda_rotulo_da_os(r.os))
              else format('%s está em andamento e não andou desde %s. Parou?', public._agenda_rotulo_da_os(r.os),
                          public._dia_curto((v_p ->> 'ultima_evidencia')::date)) end,
         cf.modo_vigia, p_agora) then
      v_n := v_n + 1;
    end if;
  end loop;
  return jsonb_build_object('criadas', v_n);
end;
$function$;

-- 11. Estouro (vigia): a OS já teve mais meios-dias feitos que estouro_fator × o combinado → "o que falta?".
create or replace function public._agenda_vigia_estouro(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf  public.agenda_config := public._agenda_cfg();
  r   record;
  v_m jsonb;
  v_n int := 0;
  v_c numeric;
  v_t numeric;
begin
  for r in select k.service_order_id as os from public.os_carteira(p_hoje) k
            where k.status = 'in_progress' order by k.numero collate "C", k.service_order_id loop
    v_m := public.agenda_meios_da_os(r.os, p_hoje);
    continue when v_m ->> 'fonte' not in ('dono', 'aceita') or (v_m ->> 'total') is null;
    v_c := coalesce((v_m ->> 'cumpridos')::numeric, 0);
    v_t := (v_m ->> 'total')::numeric;
    continue when v_t <= 0 or v_c <= cf.estouro_fator * v_t;
    if public._agenda_vigia_perguntar('estouro', format('estouro:%s:%s', r.os, v_m ->> 'total'), r.os, null, null, null,
         format('%s já teve %s de serviço e o combinado era %s. O que falta?', public._agenda_rotulo_da_os(r.os),
                public._agenda_dias(round(v_c) / 2), public._agenda_dias(v_t / 2)),
         cf.modo_vigia, p_agora) then
      v_n := v_n + 1;
    end if;
  end loop;
  return jsonb_build_object('criadas', v_n);
end;
$function$;

-- 12. Duração e material (vigia): a OS que só tem reserva porque os dias são só sugeridos ou o material não foi
-- conferido, com a reserva caindo nas próximas 2 semanas → "quantos dias?" / "tem peça a comprar?". Uma por OS.
create or replace function public._agenda_vigia_duracao_material(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf    public.agenda_config := public._agenda_cfg();
  r     record;
  v_cl  jsonb;
  v_tipo text;
  v_d   int := 0;
  v_m   int := 0;
begin
  -- a reserva vigente (ligado) ou a da proposta aberta em sombra (o que a sombra perguntaria)
  for r in select a.service_order_id as os, min(a.dia) as de, min(a.condicao_ate) as ate
             from public.agenda_alocacoes a
             left join public.agenda_propostas p on p.id = a.proposta_id
            where a.tipo = 'reserva' and a.reserva_de = 'condicionada' and a.dia between p_hoje and p_hoje + 14
              and (a.estado in ('publicada', 'fixada')
                   or (a.estado = 'proposta' and cf.modo_proposta = 'sombra' and p.estado = 'aberta' and p.modo = 'sombra'))
            group by a.service_order_id order by 2, 1 loop
    v_cl := public._agenda_classe_agora(r.os, p_hoje);
    continue when (v_cl ->> 'classe')::int is distinct from 3;
    v_tipo := case when v_cl -> 'condicoes' ? 'conferir_material' then 'material_conferir'
                   when v_cl -> 'condicoes' ? 'duracao' then 'duracao' end;
    continue when v_tipo is null;
    if public._agenda_vigia_perguntar(v_tipo, v_tipo || ':' || r.os, r.os, null, null, r.ate,
         case v_tipo
           when 'duracao' then format('Quantos dias leva %s, e com quem? Guardei lugar a partir de %s; preciso saber até %s.',
                                      public._agenda_rotulo_da_os(r.os), public._dia_curto(r.de), public._dia_curto(r.ate))
           else format('%s tem peça a comprar? Guardei lugar a partir de %s; preciso saber até %s.',
                       public._agenda_rotulo_da_os(r.os), public._dia_curto(r.de), public._dia_curto(r.ate)) end,
         cf.modo_vigia, p_agora, false) then
      if v_tipo = 'duracao' then v_d := v_d + 1; else v_m := v_m + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('duracao', v_d, 'material_conferir', v_m);
end;
$function$;

-- 13. Dono sem padrão (vigia): alguma OS ficou fora porque falta o dono dizer os dias em campo → uma pergunta por semana.
create or replace function public._agenda_vigia_padrao_do_dono(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_fora jsonb;
  v_oss  uuid[];
  v_seg  date := p_hoje - (extract(isodow from p_hoje)::int - 1);
begin
  if exists (select 1 from public.agenda_disponibilidade d
              where d.payee_id = public._agenda_dono(null) and d.substituida_em is null
                and d.dias_semana is not null and d.situacao = 'disponivel') then
    return jsonb_build_object('criada', false, 'motivo', 'você tem padrão');
  end if;
  select p.fora into v_fora from public.agenda_propostas p
   where p.modo = cf.modo_proposta and p.criada_em > p_agora - interval '7 days'
   order by p.criada_em desc, p.id desc limit 1;
  v_oss := array(select distinct (f ->> 'os')::uuid from jsonb_array_elements(coalesce(v_fora, '[]'::jsonb)) f
                  where f ->> 'motivo' = 'padrao_do_dono' and f ->> 'os' is not null order by 1);
  if cardinality(v_oss) = 0 then
    return jsonb_build_object('criada', false, 'motivo', 'nada ficou fora por isso');
  end if;
  return jsonb_build_object('criada', public._agenda_vigia_perguntar('padrao_do_dono', 'padrao_do_dono:' || v_seg, null, null, null, null,
    format('Para marcar %s, preciso saber em que dias você fica em campo. Quais dias da semana você vai?',
           public._agenda_lista(array(select public._agenda_rotulo_da_os(x) from unnest(v_oss) x order by 1), 3)),
    cf.modo_vigia, p_agora, true, v_oss));
end;
$function$;

-- 14. Pouco serviço pronto na fila (vigia, só no dia do plano): o serviço da classe 2 sem plano + o que já está
-- publicado depois da semana que sai < backlog_minimo_semanas × a capacidade comprometível → a frase vai na rodada (o
-- fechamento da quinta a usa na linha da semana). Não pergunta.
create or replace function public._agenda_vigia_backlog(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_seg  date := p_hoje - (extract(isodow from p_hoje)::int - 1);
  v_fim  date;
  v_fila numeric := 0;
  v_pub  numeric;
  v_dias numeric;
  v_comp numeric;
  v_abaixo boolean;
  r      record;
  v_cl   jsonb;
begin
  -- (depois da hora do plano: é a fila que sobra depois da semana publicada)
  if extract(isodow from p_hoje)::int <> cf.dia_do_plano or (p_agora at time zone 'America/Sao_Paulo')::time < cf.hora_do_plano then
    return jsonb_build_object('calculado', false);
  end if;
  v_fim := v_seg + 7 + 5;
  for r in select k.service_order_id as os from public.os_carteira(p_hoje) k order by 1 loop
    continue when public._agenda_os_tem_dia(r.os, p_hoje);
    v_cl := public._agenda_classe_agora(r.os, p_hoje);
    continue when (v_cl ->> 'classe')::int is distinct from 2;
    v_fila := v_fila + coalesce((public.agenda_meios_da_os(r.os, p_hoje) ->> 'restantes')::numeric, 0);
  end loop;
  select count(*) into v_pub
    from (select distinct a.service_order_id, a.dia, a.turno from public.agenda_alocacoes a
           where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia > v_fim and a.resultado is null) q;
  v_dias := round((v_fila + v_pub)) / 2;
  v_comp := coalesce((public.agenda_capacidade_semanal(p_hoje) ->> 'comprometivel')::numeric, 0);
  v_abaixo := v_dias < cf.backlog_minimo_semanas * v_comp;
  return jsonb_build_object('calculado', true, 'dias', v_dias, 'comprometivel', v_comp, 'minimo', cf.backlog_minimo_semanas * v_comp,
                            'abaixo', v_abaixo,
                            'texto', case when not v_abaixo then null
                                          when v_dias <= 0 then 'Depois desta semana, não tem serviço pronto na fila.'
                                          else format('Depois desta semana, só tem %s de serviço pronto na fila.', public._agenda_dias(v_dias)) end);
end;
$function$;

-- 15. Poda (os dois modos): as rodadas de mais de 60 dias saem.
create or replace function public._agenda_vigia_poda(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  v_n int;
begin
  delete from public.agenda_vigia_rodadas x where x.p_agora < p_agora - interval '60 days';
  get diagnostics v_n = row_count;
  return jsonb_build_object('apagadas', v_n);
end;
$function$;

comment on function public._agenda_vigia_limpeza(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 1: propostas abertas de outra versão do plano (obsoleta, só ligado) ou vencidas (expirada), com as alocações de proposta; perguntas vencidas; perguntas cuja condição sumiu (resolvida, com o fato: chegou, voltou a andar, saiu da carteira, o dia está anotado…).';
comment on function public._agenda_vigia_sem_registro(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 2 (só ligado): meio-dia vigente sem resultado há sem_registro_du dias úteis → sem_registro (via sistema).';
comment on function public._agenda_vigia_violacoes(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 3: _agenda_violacoes sobre o vigente de hoje em diante (menos a reserva vencida, que é do passo 4) → agenda_replanejar (vigia); a perda de hoje ou do próximo dia útil vira acorde (vigia ligada, ação executada).';
comment on function public._agenda_vigia_reservas(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 4: reserva condicionada com a condição cumprida (classe 1 ou 2) → o motor a promove (promover_reserva); vencida sem a condição → solta (soltar_reserva, com desfazer; em sombra só a ação que faria).';
comment on function public._agenda_vigia_material(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 5: com dia no plano, aguardando peças e o material completo → agendada pela porta (via vigia, só ligado); a OS que entrou na classe 2 desde a rodada anterior, sem plano e sem reserva → encaixada (agenda_propor os + aplicar). Anota a lista de prontas na rodada.';
comment on function public._agenda_vigia_dia_nao_cumprido(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 6 (só ligado): meio-dia parcial ou não cumprido dos últimos 7 dias gravado depois do último replano da OS → agenda_replanejar.';
comment on function public._agenda_vigia_publicacao(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 7: no dia_do_plano, a partir de hora_do_plano, a semana seguinte uma vez só (por período e modo): ligado publica os não críticos; sombra grava a proposta e as ações que faria.';
comment on function public._agenda_vigia_conferencia(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 8 (com plano publicado): o último meio-dia de hoje começou e falta resultado → pergunta conferencia:<hoje> ("Agenda de hoje: … Foi isso? Responda *dia feito* ou conte o que mudou."). Uma por dia.';
comment on function public._agenda_vigia_chegou(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 9: item crítico atrasado (a previsão passou sem chegada) → pergunta chegou:<item>:<previsão>, uma vez por previsão.';
comment on function public._agenda_vigia_parada(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 10: os_prontidao parada (em andamento, sem evidência há parada_du dias úteis, sem dia no plano) → pergunta parada:<os>:<última evidência>. Substitui a R2.';
comment on function public._agenda_vigia_estouro(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 11: em andamento com os dias ditos e os meios-dias feitos acima de estouro_fator × o combinado → pergunta estouro:<os>:<total> ("o que falta?").';
comment on function public._agenda_vigia_duracao_material(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 12: reserva condicionada nas próximas 2 semanas (vigente, ou da proposta aberta em sombra) de OS na classe 3 por material não conferido ou dias só sugeridos → pergunta material_conferir:<os> / duracao:<os>, uma por OS.';
comment on function public._agenda_vigia_padrao_do_dono(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 13: o dono sem padrão e alguma OS fora por isso na última proposta → pergunta padrao_do_dono:<segunda>, uma por semana.';
comment on function public._agenda_vigia_backlog(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 14 (dia do plano, depois da hora do plano): o serviço pronto sem plano + o publicado depois da semana que sai, em dias, contra backlog_minimo_semanas × a capacidade comprometível; abaixo → a frase para a linha da semana (fica na rodada).';
comment on function public._agenda_vigia_poda(date, timestamptz) is 'Agenda de Produção (Fase 2, P3), vigia passo 15: apaga as rodadas da vigia de mais de 60 dias.';

-- ── 5. A vigia ─────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.agenda_vigiar(p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_passos      constant text[] := array['limpeza', 'sem_registro', 'violacoes', 'reservas', 'material', 'dia_nao_cumprido',
                                         'publicacao', 'conferencia', 'chegou', 'parada', 'estouro', 'duracao_material',
                                         'padrao_do_dono', 'backlog', 'poda'];
  c_da_proposta constant text[] := array['sem_registro', 'violacoes', 'reservas', 'material', 'dia_nao_cumprido', 'publicacao'];
  c_da_vigia    constant text[] := array['conferencia', 'chegou', 'parada', 'estouro', 'duracao_material', 'padrao_do_dono',
                                         'backlog'];
  cf        public.agenda_config;
  v_t0      timestamptz := clock_timestamp();
  v_passo   text;
  v_r       jsonb;
  v_cont    jsonb := '{}'::jsonb;
  v_erros   int := 0;
  v_falhas  jsonb := '[]'::jsonb;
  v_acordes jsonb := '[]'::jsonb;
  v_estado  text;
  v_msg     text;
  v_cota    int;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da vigia.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  cf := public._agenda_cfg();
  if cf.modo_proposta = 'desligado' and cf.modo_vigia = 'desligado' then
    return jsonb_build_object('rodou', false, 'modos', jsonb_build_object('proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
                              'acordes', '[]'::jsonb);
  end if;

  foreach v_passo in array c_passos loop
    continue when v_passo = any (c_da_proposta) and cf.modo_proposta = 'desligado';
    continue when v_passo = any (c_da_vigia) and cf.modo_vigia = 'desligado';
    begin
      execute format('select public.%I($1, $2)', '_agenda_vigia_' || v_passo) into v_r using p_hoje, p_agora;
      v_acordes := v_acordes || coalesce(v_r -> 'acordes', '[]'::jsonb);
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb) - 'acordes');
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('vigia da agenda, passo %s: %s', v_passo, v_msg), 'agenda', 'vigia:' || v_passo,
                                   'error', jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje,
                                                               'p_agora', p_agora));
    end;
  end loop;

  -- Os acordes: só com a vigia ligada e a ação executada; no máximo acordes_dia_max por dia; a perda mais cedo primeiro.
  if cf.modo_vigia = 'ligado' and jsonb_array_length(v_acordes) > 0 then
    v_cota := greatest(cf.acordes_dia_max - (select count(*)::int from public.agenda_acoes a
                                              where a.dia = p_hoje and a.contada_via = 'acorde'), 0);
    select coalesce(jsonb_agg(q.e order by q.ord), '[]'::jsonb) into v_acordes
      from (select e, row_number() over (order by (e ->> 'perda_em')::date nulls last, e ->> 'chave') as ord
              from jsonb_array_elements(v_acordes) e
             where exists (select 1 from public.agenda_acoes a where a.id = (e ->> 'acao_id')::uuid and a.executada)) q
     where q.ord <= v_cota;
  else
    v_acordes := '[]'::jsonb;
  end if;

  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
          v_cont || jsonb_build_object('acordes', jsonb_array_length(v_acordes), 'falhas', v_falhas),
          least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int));

  return jsonb_build_object('rodou', true, 'modos', jsonb_build_object('proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
                            'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas, 'acordes', v_acordes);
end;
$function$;

comment on function public.agenda_vigiar(date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a vigia de 15 min (chamada pelo task-automations). Os dois modos desligados = {rodou: false}. Passos, cada um no seu bloco (o que falha vai para app_error_logs, context agenda, action vigia:<passo>, e os outros rodam): 1 limpeza; 2 sem registro; 3 violações → replano e acorde; 4 reservas (promove/solta); 5 material completo (porta/encaixe); 6 dia não cumprido; 7 publicação da semana (dia_do_plano, hora_do_plano, uma vez); 8 conferência; 9 chegou?; 10 parada? (substitui a R2); 11 estouro; 12 duração/material; 13 dono sem padrão; 14 pouco serviço na fila; 15 poda. 2 a 7 seguem modo_proposta; 8 a 14, modo_vigia. Uma linha em agenda_vigia_rodadas por tique. {rodou, modos, contagens, erros, falhas, acordes:[{chave agenda:<acao>, assunto os:<os>, texto, acao_id, os, perda_em}]} — acorde só com a vigia ligada e a ação executada, até acordes_dia_max por dia. Só service_role.';

-- ── 6. A saúde ─────────────────────────────────────────────────────────────────────────────────────────

-- A regra do que é crítico (a mesma de _agenda_criticidade), reconferida sobre uma ação já executada: o "segundo
-- atraso" conta só as ações da OS ANTES desta (a função do motor, depois do fato, veria a própria ação).
create or replace function public._agenda_criticidade_da_acao(p_acao uuid)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf        public.agenda_config := public._agenda_cfg();
  a         public.agenda_acoes%rowtype;
  v_fim_a   date;
  v_fim_d   date;
  v_ini_a   date;
  v_ini_d   date;
  v_precisa date;
  v_conf    date;
begin
  select * into a from public.agenda_acoes where id = p_acao;
  if not found or a.service_order_id is null then
    return null;
  end if;
  v_fim_a := (a.antes ->> 'fim')::date;
  v_fim_d := (a.depois ->> 'fim')::date;
  v_ini_a := (select min((x ->> 'dia')::date) from jsonb_array_elements(coalesce(a.antes -> 'alocacoes', '[]'::jsonb)) x);
  v_ini_d := (select min((x ->> 'dia')::date) from jsonb_array_elements(coalesce(a.depois -> 'alocacoes', '[]'::jsonb)) x);
  select pl.precisa_ate into v_precisa from public.os_planejamento pl where pl.service_order_id = a.service_order_id;
  -- 1. a data que o cliente precisa
  if v_precisa is not null and v_fim_d > v_precisa and (v_fim_a is null or v_fim_a <= v_precisa) then
    return 'nao_cabe';
  end if;
  -- 2. o fim publicado andou
  if v_fim_a is not null and v_fim_d > v_fim_a then
    if v_fim_d - v_fim_a >= cf.atraso_longo_dias then
      return 'atraso_longo';
    end if;
    if exists (select 1 from public.agenda_acoes b
                where b.service_order_id = a.service_order_id and b.id <> a.id and b.executada and coalesce(b.atraso_du, 0) > 0
                  and b.criada_em < a.criada_em and (b.desfeita_em is null or b.desfeita_em > a.criada_em)) then
      return 'segundo_atraso';
    end if;
    select (so.client_confirmed_for at time zone 'America/Sao_Paulo')::date into v_conf
      from public.service_orders so where so.id = a.service_order_id;
    if v_ini_a is not null and v_ini_d is not null and v_conf = v_ini_a
       and public.agenda_du_entre(v_ini_a, v_ini_d) > cf.remarcar_confirmado_du then
      return 'remarcar_confirmado';
    end if;
  end if;
  -- 3. saiu um meio-dia fixado pelo dono sem ter ficado impossível (a pessoa ou a OS)
  if exists (select 1 from public.agenda_alocacoes x
              where x.id = any (a.alocacoes_canceladas) and x.fixado_por = 'dono'
                and x.cancelada_motivo is distinct from 'pessoa' and x.cancelada_motivo is distinct from 'os_saiu') then
    return 'fixada_pelo_dono';
  end if;
  return null;
end;
$function$;

comment on function public._agenda_criticidade_da_acao(uuid) is
  'Agenda de Produção (Fase 2, P3): a regra única do que é crítico (_agenda_criticidade) reconferida sobre uma ação executada — nao_cabe, atraso_longo, segundo_atraso (só pelas ações da OS anteriores a esta e não desfeitas até ela), remarcar_confirmado, fixada_pelo_dono (meio-dia fixado pelo dono cancelado sem a pessoa ou a OS ter saído). Para a agenda_saude.';

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
begin
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k);

  select max(x.p_agora) as ultima, max(x.rodou_em) as rodou_em,
         count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24,
         (array_agg(x.erros order by x.p_agora desc, x.rodou_em desc))[1] as erros_ult
    into v_ult from public.agenda_vigia_rodadas x;
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

  return jsonb_build_object(
    'ok', v_sem = 0 and (v_regra ->> 'n')::int = 0 and v_choques = 0,
    'modos', jsonb_build_object('leitura', cf.modo_leitura, 'proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
    'vigia', v_vig, 'hoje', v_hoje, 'criticas', v_crit, 'perguntas', v_perg, 'propostas', v_prop, 'plano', v_plano,
    'invariantes', v_inv, 'fechamento', v_fech);
end;
$function$;

comment on function public.agenda_saude(date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a conferência depois de cada deploy e o painel da sombra — {ok, modos, vigia (última rodada, rodou nas últimas 2 h, erros em 24 h no app_error_logs context agenda, rodadas em 24 h), hoje (publicar, criar, mover, cancelar, promover, soltar, status, resultado, desfeitas, sombra), criticas (abertas, respondidas em 7 dias, sem_decisao e pela_regra_sem_decisao — têm de ser 0), perguntas (abertas por tipo, mostradas hoje), propostas, plano (vigentes futuras, OS programadas, reservas, sem registro em 7 dias), invariantes (vigente de OS fora da carteira, espelho divergente em ligado, choques = 0), fechamento (leu o plano hoje: resumo_tarde.detalhe.agenda; linhas mostradas)}. Leitura (invoker): authenticated (a RLS do admin vale) e service_role.';

-- ── 7. O que foi contado ao dono ───────────────────────────────────────────────────────────────────────

create or replace function public.agenda_fechamento_registrar(p_hoje date, p_linhas jsonb, p_via text default 'fechamento',
                                                              p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  e      jsonb;
  v_perg int := 0;
  v_acao int := 0;
  v_n    int;
begin
  if p_via is null or p_via not in ('fechamento', 'acorde', 'conversa') then
    raise exception 'Por onde foi mostrado: "%" (fechamento, acorde ou conversa).', coalesce(p_via, '') using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_linhas, '[]'::jsonb)) <> 'array' then
    raise exception 'As linhas mostradas vêm numa lista.' using errcode = '22023';
  end if;
  for e in select x from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) x loop
    if e ->> 'pergunta_id' is not null then
      update public.agenda_perguntas q
         set mostrada_vezes = least(q.mostrada_vezes + 1, 50), mostrada_em = p_agora, mostrada_via = p_via
       where q.id = (e ->> 'pergunta_id')::uuid and q.estado = 'aberta';
      get diagnostics v_n = row_count;
      v_perg := v_perg + v_n;
    end if;
    if jsonb_typeof(e -> 'acao_ids') = 'array' then
      update public.agenda_acoes a set contada_em = p_agora, contada_via = p_via
       where a.id in (select y::uuid from jsonb_array_elements_text(e -> 'acao_ids') y) and a.contada_em is null;
      get diagnostics v_n = row_count;
      v_acao := v_acao + v_n;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'perguntas', v_perg, 'acoes', v_acao);
end;
$function$;

comment on function public.agenda_fechamento_registrar(date, jsonb, text, timestamptz) is
  'Agenda de Produção (Fase 2, P3): o que o fechamento (ou a conversa) mostrou da agenda — para cada linha {pergunta_id?, acao_ids?}: a pergunta aberta ganha mostrada_vezes + 1, mostrada_em e mostrada_via; as ações ainda não contadas ganham contada_em/contada_via. Chamada pelo secretário quando o fechamento saiu com as linhas da agenda em ligado. Só service_role.';

create or replace function public.agenda_acorde_registrado(p_acao uuid, p_aviso uuid default null, p_enviado boolean default true,
                                                           p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_n int := 0;
begin
  if p_acao is null then
    raise exception 'Diga a ação do acorde.' using errcode = '22023';
  end if;
  if coalesce(p_enviado, false) then
    update public.agenda_acoes a set contada_em = p_agora, contada_via = 'acorde'
     where a.id = p_acao and a.executada and a.contada_em is null;
    get diagnostics v_n = row_count;
  end if;
  return jsonb_build_object('ok', true, 'marcada', v_n = 1, 'aviso', p_aviso);
end;
$function$;

comment on function public.agenda_acorde_registrado(uuid, uuid, boolean, timestamptz) is
  'Agenda de Produção (Fase 2, P3): o acorde de uma ação saiu (o portão acordou e a fila aceitou, ou a voz não está ligada e foi direto) → a ação fica contada_via = acorde (entra na conta de acordes_dia_max do dia). Não enviado = nada muda (o fechamento conta). Só service_role.';

-- ── Portas ─────────────────────────────────────────────────────────────────────────────────────────────
-- As leituras e os textos: authenticated (o painel) e service_role, nunca anon.
revoke all on function
  public._agenda_motivo_dito(text), public._agenda_motivo_texto(text), public._agenda_ajuda_do_motivo(text),
  public._agenda_dia_ref(date, date), public._agenda_quem(uuid, date, uuid[]), public._agenda_classe_agora(uuid, date),
  public._agenda_texto_do_acorde(uuid, date, date), public._agenda_criticidade_da_acao(uuid), public.agenda_saude(date, timestamptz)
  from public, anon;
grant execute on function
  public._agenda_motivo_dito(text), public._agenda_motivo_texto(text), public._agenda_ajuda_do_motivo(text),
  public._agenda_dia_ref(date, date), public._agenda_quem(uuid, date, uuid[]), public._agenda_classe_agora(uuid, date),
  public._agenda_texto_do_acorde(uuid, date, date), public._agenda_criticidade_da_acao(uuid), public.agenda_saude(date, timestamptz)
  to authenticated, service_role;

-- As palavras do dono: o painel (authenticated, com o administrador conferido dentro) e o WhatsApp (service_role).
revoke all on function
  public.agenda_registrar_dia(uuid, date, text, text, uuid, uuid[], text, text, date, timestamptz, text),
  public.agenda_conferir_dia(uuid, text, text, text, text, date, timestamptz),
  public.agenda_choveu(uuid, text, text, date, timestamptz),
  public.agenda_desfazer_dito(uuid, text, text, date, timestamptz)
  from public, anon;
grant execute on function
  public.agenda_registrar_dia(uuid, date, text, text, uuid, uuid[], text, text, date, timestamptz, text),
  public.agenda_conferir_dia(uuid, text, text, text, text, date, timestamptz),
  public.agenda_choveu(uuid, text, text, date, timestamptz),
  public.agenda_desfazer_dito(uuid, text, text, date, timestamptz)
  to authenticated, service_role;

-- O que age sozinho: só service_role (o task-automations e o secretário).
revoke all on function
  public.agenda_replanejar(uuid[], text, text, date, timestamptz, uuid), public.agenda_vigiar(date, timestamptz),
  public.agenda_fechamento_registrar(date, jsonb, text, timestamptz), public.agenda_acorde_registrado(uuid, uuid, boolean, timestamptz)
  from public, anon, authenticated;
grant execute on function
  public.agenda_replanejar(uuid[], text, text, date, timestamptz, uuid), public.agenda_vigiar(date, timestamptz),
  public.agenda_fechamento_registrar(date, jsonb, text, timestamptz), public.agenda_acorde_registrado(uuid, uuid, boolean, timestamptz)
  to service_role;

-- As peças de dentro da vigia e da conferência: ninguém de fora (só as funções security definer acima as chamam).
revoke all on function
  public._agenda_acoes_da_sombra(uuid, text, uuid, date, timestamptz),
  public._agenda_propor_e_aplicar(text, uuid[], text, uuid, date, timestamptz),
  public._agenda_vigia_perguntar(text, text, uuid, uuid, date, date, text, text, timestamptz, boolean, uuid[]),
  public._agenda_vigia_ja_tentou(uuid, timestamptz),
  public._agenda_vigia_limpeza(date, timestamptz), public._agenda_vigia_sem_registro(date, timestamptz),
  public._agenda_vigia_violacoes(date, timestamptz), public._agenda_vigia_reservas(date, timestamptz),
  public._agenda_vigia_material(date, timestamptz), public._agenda_vigia_dia_nao_cumprido(date, timestamptz),
  public._agenda_vigia_publicacao(date, timestamptz), public._agenda_vigia_conferencia(date, timestamptz),
  public._agenda_vigia_chegou(date, timestamptz), public._agenda_vigia_parada(date, timestamptz),
  public._agenda_vigia_estouro(date, timestamptz), public._agenda_vigia_duracao_material(date, timestamptz),
  public._agenda_vigia_padrao_do_dono(date, timestamptz), public._agenda_vigia_backlog(date, timestamptz),
  public._agenda_vigia_poda(date, timestamptz)
  from public, anon, authenticated, service_role;
