-- Agenda de Produção — pacote 1 do assistente, A3 (24/11/2026): o "terminei" (e o "ok") do técnico no último dia vira pergunta ao dono.
--
-- Por quê (NOVO-agenda-p1-03; especificação: D:/IA-HBR/Trabalho/avaliacao-assistente-20261124/pacote1/spec-agenda.md, seção A3): no último dia do
-- plano, com o motor ligado, _agenda_rotina_conclusao concluía a OS em nome da equipe (os_registrar_marco via equipe) quando a leitura da resposta ao
-- "como foi hoje?" dizia "terminou". E o "ok" puro vale "terminou" no leitor (agenda_resposta_da_equipe: coalesce(terminou, true)): um "ok" no último
-- dia concluía a OS sem ninguém dizer que terminou. Concluir faz o saldo "na entrega" vencer e prepara o aviso de "pronto" ao cliente.
--
-- O que muda: só _agenda_rotina_conclusao, recriada do corpo em vigor (20270223100000, igual ao de produção guardado em 24/11/2026 17:46: md5 de
-- pg_get_functiondef a9bfdfa9…) mais 3 blocos "-- P1 AGENDA: … -- P1 AGENDA: fim" (a variável v_num, a mensagem já perguntada que não é relida
-- e o ramo novo). Tirados os blocos, o corpo é o de antes, byte a byte.
--   · agenda_config.equipe_terminei_conclui = false (o padrão; 20270301120000) e modo_proposta ligado: nada conclui pela palavra do técnico. Nasce a
--     pergunta tipo concluir, chave terminou:<os> (a de _agenda_terminou_rodar), em ligado, com o técnico em payee_id e dia = hoje; uma por dia:
--       "terminei": O Alex disse em qua 02/12 que terminou a OS-00131 (Fernando). Responda *concluiu OS-00131* para fechar, ou *falta dia OS-00131* se ainda tem serviço.
--       "ok" puro:  O Alex respondeu *ok* ao "como foi hoje?" no último dia da OS-00131 (Fernando). Responda *concluiu OS-00131* para fechar, ou *falta dia OS-00131* se ainda tem serviço.
--   · A mensagem que já virou essa pergunta não é relida no resto do dia (nem com a chave virada para true no meio do dia: a OS não conclui
--     pela mensagem já perguntada; nem depois do *falta dia* do dono: o "dia sobrando" não nasce dela).
--   · equipe_terminei_conclui = true: o de antes (conclui pela porta, via equipe).
--   · Não mudam: modo_proposta em sombra (só a ação "Em teste: concluiria…"), a etapa pendente dita (7c P8), o dia sobrando no plano e a porta que
--     recusa (as três perguntas concluir:<os>:<dia> de antes).
--
-- LIMITE CONHECIDO (decisão de desenho pendente; nada aqui o resolve): no fim do mesmo passo roda _agenda_terminou_rodar, que fecha toda pergunta
-- concluir de chave terminou:% cuja OS tenha meio-dia publicado ou fixado de hoje em diante sem resultado ("a OS voltou a ter dia no plano"). A
-- resposta do técnico só dá resultado aos meios-dias DELE que já começaram: o meio-dia do dono (o fechamento da presença "abre e fecha", o padrão da
-- casa), o de outra pessoa ou a tarde que ainda não começou ficam sem resultado, e a pergunta nova é fechada no mesmo passo, sem ser mostrada. Nesse
-- caso a OS continua em andamento e não conclui; no dia seguinte _agenda_terminou_rodar abre a pergunta geral ("A OS-X terminou ou falta dia?") e a
-- manhã das 07:30 a mostra. O "terminei" seco (sem turno: o leitor não anota o dia) deixa a OS agendada: a pergunta é fechada no mesmo passo ("a OS
-- não está mais em andamento") e a geral não nasce (ela exige a OS em andamento). A pergunta com o que o técnico disse só sobrevive quando nenhum
-- meio-dia de hoje da OS ficou sem resultado e a OS está em andamento. Em todos os casos a OS não conclui. Consertar pede mexer em
-- _agenda_terminou_rodar (a chave terminou:<os>:equipe não escapa: o filtro dela é like 'terminou:%'; e agenda_falta_dia_dito só fecha a chave
-- exata): fora deste lote. supabase/tests/agenda_p1_terminei.sql prova os dois lados (S1 a S6).
--
-- Nada mais muda: nenhuma tabela, coluna, CHECK, modo, cron ou edge function; o leitor (_agenda_ler_resposta_da_equipe) fica como está; nenhuma
-- mensagem nova ao técnico nem ao cliente. Portas: create or replace não mexe na ACL nem no dono (invoker, search_path = public, ninguém de fora
-- executa: as de 20261026100300).
-- DESFAZER: reaplicar o corpo de 20270223100000 (a função _agenda_rotina_conclusao), ou
-- update public.agenda_config set equipe_terminei_conclui = true where id.

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

-- ── O comentário da recriada (o de antes + o que mudou; uma vez só) ───────────────────────────────────────────────────────────────────
do $c$
declare
  c_f constant text := 'public._agenda_rotina_conclusao(date,timestamptz)';
begin
  if coalesce(obj_description(to_regprocedure(c_f), 'pg_proc'), '') not like '%P1 AGENDA (A3, 24/11/2026%' then
    execute format('comment on function %s is %L', c_f, coalesce(obj_description(to_regprocedure(c_f), 'pg_proc'), '')
      || ' P1 AGENDA (A3, 24/11/2026, 20270301120200): com agenda_config.equipe_terminei_conclui = false (o padrão) e modo_proposta ligado, o "terminei" (ou o "ok") do técnico no último dia do plano não conclui a OS: vira a pergunta concluir de chave terminou:<os> ao dono ("O Alex disse em qua 02/12 que terminou a OS-00131 (Fernando). Responda *concluiu OS-00131* para fechar, ou *falta dia OS-00131* se ainda tem serviço."; com o "ok" puro, "O Alex respondeu *ok* ao "como foi hoje?" no último dia da OS-00131 (Fernando). …"), uma por dia. Com true, o de antes (conclui pela porta, via equipe).');
  end if;
end
$c$;

insert into supabase_migrations.schema_migrations (version, name) values ('20270301120200','agenda_p1_terminei_pergunta');
