-- Agenda de Produção — pacote 1 do assistente, A2 (26/11/2026): os 2 consertos que o A2 pediu (achados A e B da construção do 20270301120300).
--
-- Por quê:
--   · B (vale com qualquer chave): o "ok" puro ao "como foi hoje?" num dia que não é o último do plano abria a pergunta "O Roberto disse que
--     terminou o Vanderlei (OS-00069), mas o plano tinha mais 2 dias…". O leitor (agenda_resposta_da_equipe) grava terminou = true por padrão
--     no "ok" ("tudo como o previsto"), e _agenda_rotina_conclusao, no ramo do plano com mais dias, não distinguia o "ok" do "terminei". Em
--     produção nenhum "como foi" foi respondido até 26/11 (latente: aparece no 1º "ok" a um "como foi" numa OS de vários dias).
--   · A (só com equipe_silencio_acao = 'manter'): o acorde do silêncio que manteve o dia disputava a cota acordes_dia_max (1 por dia) com os
--     outros acordes da rotina: gastava a cota (o "não vou" das 10h refazia a agenda e o acorde dele não saía no dia) e era cortado por ela
--     (um acorde antes das 9h impedia o "Mantive o dia dele"). A decisão do dono é manter E avisá-lo.
--
-- O que muda: só 2 funções, recriadas dos corpos em vigor, mais blocos "-- P1 AGENDA: … -- P1 AGENDA: fim" (tirados os blocos e devolvidas as
-- linhas "--antes:", o corpo é o de antes, byte a byte, sem CR):
--   · _agenda_rotina_conclusao (do 20270301120200, o de produção desde 26/11: md5 de pg_get_functiondef 77bad502…): 1 bloco. No ramo do plano
--     com mais dias, a mensagem de leitura tipo ok não abre pergunta (continue). A leitura de tipo ok é o "ok" puro por construção:
--     _agenda_ler_resposta_da_equipe só devolve tipo ok com terminou nulo; "ok, terminei", "terminei", "acabei", "ok, mas não terminei" são
--     tipo turnos (o terminou dito). É o mesmo critério do texto do A3 no último dia ("respondeu *ok*"). Por que aqui e não no leitor: o
--     leitor tem 46 mil letras, é security definer, e o terminou = true do "ok" é o que o último dia (A3) e a diária leem; aqui só a pergunta
--     muda. Seguem iguais: o "ok, terminei"/"terminei" fora do último dia (a pergunta de sempre), o último dia (A3: com
--     equipe_terminei_conclui = false a pergunta "respondeu *ok*"; com true, conclui), a diária e os meios-dias.
--   · agenda_rotina_rodar (o de produção guardado em 24/11/2026 e conferido em 26/11/2026: md5 f28a8dd2…, com o CR; sem CR 6f214ede…, o de
--     20261026100300): 2 blocos, só na cota dos acordes. A ação equipe de motivo silencio_manteve não conta na cota do dia e o acorde dela não
--     é cortado por ela; os outros acordes, como antes (a cota, a ordem, só com a vigia ligada e a ação executada). Sem 'manter' não existe
--     ação silencio_manteve: nada muda.
--
-- Nada mais muda: nenhuma tabela, coluna, CHECK, índice, modo, teto, cron ou edge function; o leitor fica como está; nenhuma mensagem nova.
-- Portas: create or replace não mexe na ACL nem no dono (agenda_rotina_rodar: security definer, só service_role; _agenda_rotina_conclusao:
-- invoker, ninguém de fora).
-- LIMITE (fora daqui): a vigia (agenda_vigiar) e a rodada do cliente contam a cota do dia do jeito de antes; o acorde do silêncio contado
-- ainda gasta a cota delas.
-- DESFAZER: reaplicar os corpos de antes (D:/IA-HBR/Trabalho/avaliacao-assistente-20261124/pacote1/agenda-lote2/a2/voltar.sql, que também
-- desfaz o 20270301120300). Não há chave: o B vale sempre; o A só tem efeito com 'manter' (equipe_silencio_acao = 'tirar' o apaga).
-- IDEMPOTENTE: create or replace; o comentário só ganha o trecho uma vez.

CREATE OR REPLACE FUNCTION public._agenda_rotina_conclusao(p_hoje date, p_agora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  m       record;
  v_os    uuid[];
  v_x     uuid;
  v_st    text;
  v_fut   date[];
  v_rest  numeric;
  v_r     jsonb;
  v_acao  uuid;
  v_nome  text;
  v_cli   text;
  v_conc  int := 0;
  v_perg  int := 0;
  -- FASE 7c: (7c P8) as etapas pendentes ditas da OS
  v_p8_pend text[];
  -- FASE 7c: fim
  -- TERMINOU: (23/11/2026) o "terminou ou falta dia?" do dono
  v_term     jsonb;
  v_term_est text;
  v_term_msg text;
  -- TERMINOU: fim
  -- P1 AGENDA: (A3, 24/11/2026) o número da OS no texto da pergunta ao dono
  v_num      text;
  -- P1 AGENDA: fim
begin
  for m in
    select x.* from public.agenda_equipe_mensagens x
     where x.tipo = 'como_foi' and x.modo = 'ligado' and x.dia = p_hoje and x.acao_id is null
       and coalesce((x.leitura ->> 'terminou')::boolean, false)
     order by x.resposta_em, x.id
  loop
    v_os := array(select distinct a.service_order_id from public.agenda_alocacoes a
                   where a.payee_id = m.payee_id and a.dia = p_hoje and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva');
    continue when cardinality(v_os) <> 1;
    v_x := v_os[1];
    -- P1 AGENDA: (A3, 25/11/2026, revisão) a mensagem que já virou a pergunta terminou:<os> de hoje deste técnico (o ramo novo, abaixo) não é
    -- relida: ela fica sem acao_id e o laço a pegaria em todo tique do dia. Sem isto, depois do *falta dia* do dono no mesmo dia (o motor
    -- encaixa dia novo) o tique seguinte abria a pergunta do "dia sobrando", que contradiz o dono, não vence e segura a pergunta geral; e
    -- virar a chave para true no mesmo dia concluía a OS da pergunta já feita ao dono. A pergunta geral (sem payee_id) não conta aqui.
    continue when exists (select 1 from public.agenda_perguntas q
                           where q.chave = 'terminou:' || v_x and q.payee_id = m.payee_id
                             and q.criada_em >= (p_hoje::timestamp at time zone 'America/Sao_Paulo'));
    -- P1 AGENDA: fim
    select so.status into v_st from public.service_orders so where so.id = v_x;
    continue when v_st not in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client');
    v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = m.payee_id);
    v_cli := (select public._agenda_nome_curto(cl.name) from public.service_orders so join public.clients cl on cl.id = so.client_id
               where so.id = v_x);
    v_fut := array(select distinct a.dia from public.agenda_alocacoes a
                    where a.service_order_id = v_x and a.dia > p_hoje and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                    order by 1);
    v_rest := (public.agenda_meios_da_os(v_x, p_hoje + 1) ->> 'restantes')::numeric;
    -- FASE 7c: (7c P8, §16.3.9 (c), §16.6.6; AG7-10d; R5.2-3, R5.10-11) com modo_tarefas ligado e tarefas_concluir_sem_pendente, o
    -- "terminei" no último dia não conclui a OS que tem etapa pendente DITA (uma etapa viva cuja última linha com resultado é pendente: pela
    -- equipe, pela conferência ou pelo dono); vira a pergunta concluir com o que falta. A sem registro e a etapa sem linha não seguram. O
    -- *concluiu* do dono conclui como hoje.
    if cardinality(v_fut) = 0 and v_rest = 0 and cf.modo_tarefas = 'ligado' and cf.tarefas_concluir_sem_pendente then
      v_p8_pend := array(select t.texto from public.os_tarefas t
                          where t.service_order_id = v_x and t.estado = 'viva'
                            and (select d.resultado from public.os_tarefas_dia d
                                  where d.tarefa_id = t.id and d.estado = 'planejada' and d.termina and d.resultado is not null
                                  order by d.dia desc, d.turno = 'tarde' desc, d.resultado_em desc limit 1) = 'pendente'
                          order by t.ordem, t.id);
      if cardinality(v_p8_pend) > 0 then
        if public._agenda_equipe_perguntar('concluir', format('concluir:%s:%s', v_x, p_hoje), m.payee_id, v_x, p_hoje,
             format('O %s disse que terminou o %s, mas não concluí: ainda falta %s. *concluiu %s* fecha a OS mesmo assim.', v_nome,
                    coalesce(v_cli, public._agenda_rotulo_da_os(v_x)),
                    public._agenda_lista(array(select '"' || x || '"' from unnest(v_p8_pend) with ordinality u(x, o) order by o), 3),
                    coalesce(v_cli, (select so.service_order_number from public.service_orders so where so.id = v_x))),
             'ligado', p_agora) then
          v_perg := v_perg + 1;
        end if;
        continue;
      end if;
    end if;
    -- FASE 7c: fim
    if cardinality(v_fut) = 0 and v_rest = 0 then
      -- P1 AGENDA: (A3, 24/11/2026; agenda_config.equipe_terminei_conclui) com a chave em false (o padrão) e o motor ligado, o "terminei" (ou
      -- o "ok") do técnico no último dia do plano não conclui a OS em nome da equipe: vira a pergunta "terminou ou falta dia?" ao dono, na
      -- chave de _agenda_terminou_rodar (terminou:<os>), a que a manhã das 07:30 mostra, *concluiu <alvo>* conclui e *falta dia <alvo>* fecha.
      -- Uma por dia: a de hoje, aberta ou já fechada, não nasce de novo. O texto diz o que ele disse: o "ok" puro (leitura de tipo ok, em que
      -- o "terminou" é só o padrão do leitor) é "respondeu *ok*", e não "disse que terminou". Com a chave em true, o de antes.
      if not cf.equipe_terminei_conclui and cf.modo_proposta = 'ligado' then
        continue when exists (select 1 from public.agenda_perguntas q
                               where q.chave = 'terminou:' || v_x
                                 and q.criada_em >= (p_hoje::timestamp at time zone 'America/Sao_Paulo'));
        v_num := (select so.service_order_number from public.service_orders so where so.id = v_x);
        if public._agenda_equipe_perguntar('concluir', 'terminou:' || v_x, m.payee_id, v_x, p_hoje,
             case when m.leitura ->> 'tipo' = 'ok'
                  then format('O %s respondeu *ok* ao "como foi hoje?" no último dia da %s (%s). Responda *concluiu %s* para fechar, ou *falta dia %s* se ainda tem serviço.',
                              v_nome, v_num, coalesce(v_cli, v_num), v_num, v_num)
                  else format('O %s disse em %s que terminou a %s (%s). Responda *concluiu %s* para fechar, ou *falta dia %s* se ainda tem serviço.',
                              v_nome, public._dia_curto(p_hoje), v_num, coalesce(v_cli, v_num), v_num, v_num) end,
             'ligado', p_agora) then
          v_perg := v_perg + 1;
        end if;
        continue;
      end if;
      -- P1 AGENDA: fim
      if cf.modo_proposta = 'ligado' then
        v_r := public.os_registrar_marco(v_x, 'conclusao', 'equipe', null, null,
                                         left(format('O %s disse que terminou: "%s"', v_nome, m.resposta_texto), 200), p_hoje, p_agora);
        if coalesce((v_r ->> 'ok')::boolean, false) and v_r ->> 'acao_id' is not null then
          update public.agenda_equipe_mensagens set acao_id = (v_r ->> 'acao_id')::uuid where id = m.id;
          v_conc := v_conc + 1;
        else
          -- a porta recusou (o período fechado, o levantamento…): a pergunta, com a frase dela
          perform public._agenda_equipe_perguntar('concluir', format('concluir:%s:%s', v_x, p_hoje), m.payee_id, v_x, p_hoje,
            format('O %s disse que terminou o %s, mas não concluí: %s', v_nome, public._agenda_rotulo_da_os(v_x),
                   coalesce(v_r ->> 'texto', 'a porta recusou.')), 'ligado', p_agora);
          v_perg := v_perg + 1;
        end if;
      else
        insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
        values (clock_timestamp(), p_hoje, false, 'equipe', 'concluir', v_x, array[v_x], m.payee_id,
                jsonb_build_object('mensagem', m.id),
                left(format('Em teste: concluiria o %s (o %s disse que terminou e era o último dia do plano).',
                            public._agenda_rotulo_da_os(v_x), v_nome), 400))
        returning id into v_acao;
        update public.agenda_equipe_mensagens set acao_id = v_acao where id = m.id;
        v_conc := v_conc + 1;
      end if;
    else
      -- P1 AGENDA: (A2, 26/11/2026, conserto B) o "ok" puro ao "como foi hoje?" (a leitura de tipo ok: _agenda_ler_resposta_da_equipe só
      -- devolve tipo ok com terminou nulo, e é agenda_resposta_da_equipe que grava terminou = true por padrão) num dia que NÃO é o último do
      -- plano é "tudo como o previsto": o plano segue e não há o que perguntar. Sem isto nascia "O Roberto disse que terminou o Vanderlei
      -- (OS-00069), mas o plano tinha mais 2 dias…" sem ele ter dito. Vale com qualquer chave. Seguem com a pergunta o "ok, terminei", o
      -- "terminei", o "acabei" (tipo turnos, o terminou dito); o último dia é o de cima (A3); a diária e os meios-dias são do leitor (nada muda).
      continue when m.leitura ->> 'tipo' = 'ok';
      -- P1 AGENDA: fim
      if public._agenda_equipe_perguntar('concluir', format('concluir:%s:%s', v_x, p_hoje), m.payee_id, v_x, p_hoje,
           format('O %s disse que terminou o %s, mas o plano tinha mais %s. *concluiu %s* fecha a OS.', v_nome,
                  public._agenda_rotulo_da_os(v_x),
                  case when cardinality(v_fut) > 0
                       then public._agenda_plural(cardinality(v_fut), 'dia', 'dias') || ' (' || public._agenda_dias_texto(v_fut) || ')'
                       else 'serviço do que você disse' end,
                  coalesce(v_cli, (select so.service_order_number from public.service_orders so where so.id = v_x))),
           'ligado', p_agora) then
        v_perg := v_perg + 1;
      end if;
    end if;
  end loop;
  -- TERMINOU: (23/11/2026, NOVO-testes-01, opção A do dono) a OS em execução com o plano cumprido e sem dia futuro ganha a pergunta
  -- "A OS-X terminou ou falta dia?" (_agenda_terminou_rodar; também fecha a que não vale mais). Num bloco próprio: o erro dela vai para
  -- app_error_logs (rotina:terminou) e não desfaz as conclusões da equipe deste passo. A linha de antes, em "--antes:".
  begin
    v_term := public._agenda_terminou_rodar(p_hoje, p_agora);
  exception when others then
    get stacked diagnostics v_term_est = returned_sqlstate, v_term_msg = message_text;
    perform public.log_app_error('db', 'rotina da agenda, terminou ou falta dia: ' || v_term_msg, 'agenda', 'rotina:terminou', 'error',
                                 jsonb_build_object('sqlstate', v_term_est, 'p_hoje', p_hoje, 'p_agora', p_agora));
    v_term := jsonb_build_object('erro', left(v_term_msg, 200));
  end;
--antes:  return jsonb_build_object('concluidas', v_conc, 'perguntas', v_perg);
  return jsonb_build_object('concluidas', v_conc, 'perguntas', v_perg, 'terminou', v_term);
  -- TERMINOU: fim
end;
$function$;

CREATE OR REPLACE FUNCTION public.agenda_rotina_rodar(p_hoje date, p_agora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_variable
declare
  c_passos      constant text[] := array['ficha', 'confirmar', 'silencio', 'como_foi', 'sem_resposta',
                                         'acordes_da_equipe', 'diarias', 'resultado_pela_diaria', 'conclusao', 'entrega'];
  c_da_equipe   constant text[] := array['ficha', 'confirmar', 'silencio', 'como_foi', 'sem_resposta', 'acordes_da_equipe'];
  c_do_dia_util constant text[] := array['ficha', 'confirmar', 'silencio', 'como_foi'];
  cf        public.agenda_config;
  v_t0      timestamptz := clock_timestamp();
  v_passo   text;
  v_r       jsonb;
  v_cont    jsonb := '{}'::jsonb;
  v_erros   int := 0;
  v_falhas  jsonb := '[]'::jsonb;
  v_acordes jsonb := '[]'::jsonb;
  v_cota    int;
  v_estado  text;
  v_msg     text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora da rotina.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  cf := public._agenda_cfg();
  -- A fila velha roda SEMPRE, em qualquer modo (até desligado): o que não saiu na janela, ou ficou na fila quando o dono
  -- desligou a equipe, não sai mais. Só mexe em linha source agenda-equipe; não grava a rodada.
  begin
    v_cont := jsonb_build_object('fila', public._agenda_rotina_fila(p_hoje, p_agora));
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    v_erros := v_erros + 1;
    v_falhas := v_falhas || jsonb_build_object('passo', 'fila', 'sqlstate', v_estado, 'erro', left(v_msg, 300));
    perform public.log_app_error('db', 'rotina da agenda, passo fila: ' || v_msg, 'agenda', 'rotina:fila', 'error',
                                 jsonb_build_object('passo', 'fila', 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
  end;
  if cf.modo_equipe = 'desligado' and cf.modo_diaria = 'desligado' then
    return jsonb_build_object('rodou', false, 'modos', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
                              'acordes', '[]'::jsonb, 'fila', v_cont -> 'fila');
  end if;

  foreach v_passo in array c_passos loop
    continue when v_passo = any (c_da_equipe) and cf.modo_equipe = 'desligado';
    -- domingo: nada à equipe
    continue when v_passo = any (c_do_dia_util) and extract(isodow from p_hoje) = 7;
    continue when v_passo = 'diarias' and cf.modo_diaria = 'desligado';
    continue when v_passo = 'resultado_pela_diaria' and cf.modo_proposta <> 'ligado';
    continue when v_passo = 'conclusao' and (cf.modo_equipe <> 'ligado' or cf.modo_proposta = 'desligado');
    continue when v_passo = 'entrega' and cf.modo_vigia = 'desligado';
    begin
      execute format('select public.%I($1, $2)', '_agenda_rotina_' || v_passo) into v_r using p_hoje, p_agora;
      v_acordes := v_acordes || coalesce(v_r -> 'acordes', '[]'::jsonb);
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb) - 'acordes');
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('rotina da agenda, passo %s: %s', v_passo, v_msg), 'agenda', 'rotina:' || v_passo,
                                   'error', jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje,
                                                               'p_agora', p_agora));
    end;
  end loop;

  -- Os acordes: como os da vigia — só com a vigia ligada e a ação executada, na cota acordes_dia_max do dia.
  if cf.modo_vigia = 'ligado' and jsonb_array_length(v_acordes) > 0 then
    v_cota := greatest(cf.acordes_dia_max - (select count(*)::int from public.agenda_acoes a
    -- P1 AGENDA: (A2, 26/11/2026, conserto A) o acorde do silêncio que manteve o dia (a ação equipe silencio_manteve, que só nasce com
    -- agenda_config.equipe_silencio_acao = 'manter') não gasta a cota do dia: o acorde do "não vou" das 10h sai no mesmo dia
--antes:                                              where a.dia = p_hoje and a.contada_via = 'acorde'), 0);
                                              where a.dia = p_hoje and a.contada_via = 'acorde'
                                                and a.depois ->> 'motivo' is distinct from 'silencio_manteve'), 0);
    -- P1 AGENDA: fim
    -- P1 AGENDA: (A2, 26/11/2026, conserto A) e não é cortado por ela: um acorde que saiu antes das 9h não impede o "Mantive o dia dele"
    -- (a decisão do dono é avisá-lo). Os outros acordes, na cota de sempre e na ordem de sempre (a perda mais cedo primeiro); o do
    -- silêncio vem à frente. Continua: só com a vigia ligada e a ação executada.
--antes:    select coalesce(jsonb_agg(q.e order by q.ord), '[]'::jsonb) into v_acordes
--antes:      from (select e, row_number() over (order by (e ->> 'perda_em')::date nulls last, e ->> 'chave') as ord
--antes:              from jsonb_array_elements(v_acordes) e
--antes:             where exists (select 1 from public.agenda_acoes a where a.id = (e ->> 'acao_id')::uuid and a.executada)) q
--antes:     where q.ord <= v_cota;
    select coalesce(jsonb_agg(q.e order by q.fora_da_cota desc, q.ord), '[]'::jsonb) into v_acordes
      from (select e, x.fora_da_cota,
                   row_number() over (partition by x.fora_da_cota order by (e ->> 'perda_em')::date nulls last, e ->> 'chave') as ord
              from jsonb_array_elements(v_acordes) e
             cross join lateral (select exists (select 1 from public.agenda_acoes s
                                                 where s.id = (e ->> 'acao_id')::uuid and s.depois ->> 'motivo' = 'silencio_manteve')
                                        as fora_da_cota) x
             where exists (select 1 from public.agenda_acoes a where a.id = (e ->> 'acao_id')::uuid and a.executada)) q
     where q.ord <= v_cota or q.fora_da_cota;
    -- P1 AGENDA: fim
  else
    v_acordes := '[]'::jsonb;
  end if;

  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                           rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
          v_cont || jsonb_build_object('acordes', jsonb_array_length(v_acordes), 'falhas', v_falhas),
          least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int),
          'rotina', cf.modo_equipe, cf.modo_diaria);

  return jsonb_build_object('rodou', true,
                            'modos', jsonb_build_object('proposta', cf.modo_proposta, 'vigia', cf.modo_vigia,
                                                        'equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
                            'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas, 'acordes', v_acordes);
end;
$function$;

-- ── Os comentários das recriadas (o de antes + o que mudou; uma vez só) ──────────────────────────────────────────────────────────────
do $c$
declare
  c_c constant text := 'public._agenda_rotina_conclusao(date,timestamptz)';
  c_r constant text := 'public.agenda_rotina_rodar(date,timestamptz)';
begin
  if coalesce(obj_description(to_regprocedure(c_c), 'pg_proc'), '') not like '%P1 AGENDA (A2, conserto B%' then
    execute format('comment on function %s is %L', c_c, ltrim(coalesce(obj_description(to_regprocedure(c_c), 'pg_proc'), '')
      || ' P1 AGENDA (A2, conserto B, 26/11/2026, 20270301120310): o "ok" puro ao "como foi hoje?" (leitura tipo ok) num dia que não é o último do plano não abre a pergunta "disse que terminou… mas o plano tinha mais N dias"; o "terminei" dito, sim, como antes.'));
  end if;
  if coalesce(obj_description(to_regprocedure(c_r), 'pg_proc'), '') not like '%P1 AGENDA (A2, conserto A%' then
    execute format('comment on function %s is %L', c_r, ltrim(coalesce(obj_description(to_regprocedure(c_r), 'pg_proc'), '')
      || ' P1 AGENDA (A2, conserto A, 26/11/2026, 20270301120310): o acorde da ação equipe silencio_manteve (só com equipe_silencio_acao = ''manter'') fica fora da cota acordes_dia_max: não a gasta e não é cortado por ela.'));
  end if;
end
$c$;

insert into supabase_migrations.schema_migrations (version, name) values ('20270301120310','agenda_p1_silencio_consertos');
