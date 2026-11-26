-- Agenda de Produção — pacote 1 do assistente, A2 (decisão do dono de 24/11/2026): o silêncio das 9h mantém o dia, avisa o dono e pede de
-- novo ao técnico.
--
-- Por quê (especificação: D:/IA-HBR/Trabalho/avaliacao-assistente-20261124/pacote1/spec-agenda.md, seção A2; críticas de risco e de
-- viabilidade, seção 4): quando o técnico não responde até as 9h à confirmação das 07:45, _agenda_rotina_silencio TIRA o dia dele do plano
-- (indisponível no dia, replano da falta e o acorde ao dono). Aconteceu em 18/11, 24/11 e 26/11/2026, sem que ninguém soubesse se a mensagem
-- chegou. O dono decidiu em 24/11: "manter o dia marcado e avisá-lo, E avisar o técnico de novo pedindo confirmação".
--
-- O que muda: só 2 funções, recriadas dos corpos em vigor (os de produção guardados em 24/11/2026 e conferidos em 26/11/2026: md5 de
-- pg_get_functiondef 10c8d3f9… e 4ebd1575…, com o CR que o arquivo aplicado levou; sem CR, iguais aos de 20261026100300 e 20261109101000), mais
-- blocos "-- P1 AGENDA: … -- P1 AGENDA: fim". Tirados os blocos, cada corpo é o de antes, byte a byte (sem CR).
--   · _agenda_rotina_silencio: 2 blocos (as variáveis e o ramo novo). Com agenda_config.equipe_silencio_acao = 'manter', para a confirmação de
--     hoje que saiu e ficou sem resposta até equipe_silencio_ate, sem mensagem dele depois do envio, e com dia dele no plano de hoje:
--       - nada tira o dia: nenhuma disponibilidade, nenhum replano; a confirmação continua 'enfileirada' (o "ok" ou o "não vou" que vier
--         depois ainda é a resposta a ela; depois do "como foi" das 17:00, a resposta é a ele);
--       - o 2º pedido ao técnico: uma mensagem tipo 'resposta' (não é tipo novo: o leitor agenda_resposta_da_equipe não a escolhe como a
--         mensagem a que ele responde, e ela conta no teto de respostas, não no de proativas), chave agenda-equipe:resposta:<pessoa>:reconfirmar:<dia>
--         (no máximo 1 por pessoa e dia, em TODO dia de silêncio), com o texto da confirmação sem o "Bom dia, <nome>.":
--           "Alex, ainda não vi sua resposta de hoje cedo. Hoje é Fernando de manhã e de tarde. Tá confirmado? Responda *ok* se vem ou *não vou* se não der."
--         A ficha do dia segurada (_agenda_ficha_liberada falso: a mesma regra da confirmação da manhã) não pede de novo;
--       - a ação equipe de motivo silencio_manteve, com acorde, uma por pessoa e dia, com o texto ao dono (duas variantes):
--           "O Alex não respondeu à confirmação de hoje até as 9h (não sei se a mensagem chegou). Mantive o dia dele: Fernando (OS-00131). Pedi de novo a ele. Se ele não for, me avise que eu refaço a agenda."
--           "… Mantive o dia dele: Fernando (OS-00131). Não consegui pedir de novo. Se ele não for, me avise que eu refaço a agenda."  (teto,
--            janela, sem telefone, parou, ficha segurada; o erro do registro vai para app_error_logs)
--     Sem dia dele no plano de hoje (o dono ou o motor já o tiraram depois das 07:45), nada: não há dia a manter.
--   · _agenda_rotina_acordes_da_equipe: 1 bloco. O acorde da ação silencio_manteve é a frase da ação, inteira (não há replano a contar; sem
--     isto, o acorde diria "O Alex avisou que não vem hoje. A agenda automática não está ligada: reveja o dia dele.").
--   · Com equipe_silencio_acao = 'tirar' (o padrão, de 20270301120000), tudo como antes.
--
-- Nada mais muda: nenhuma tabela, coluna, CHECK, índice, tipo de mensagem, teto, gatilho da fila, modo, cron ou edge function; o leitor
-- agenda_resposta_da_equipe fica como está. Portas: create or replace não mexe na ACL nem no dono (as duas são invoker, search_path = public e
-- ninguém de fora executa: as de 20261026100300; quem chama é agenda_rotina_rodar, security definer, só service_role).
-- LIGAR (só com o OK nomeado do dono, "OK ligar o silêncio que mantém o dia", e só com o A3 no ar: com o dia mantido o "como foi" passa a sair,
-- e o "ok" dele no último dia fecharia a OS): update public.agenda_config set equipe_silencio_acao = 'manter' where id;
-- DESFAZER: update public.agenda_config set equipe_silencio_acao = 'tirar' where id; ou reaplicar os corpos de antes
-- (D:/IA-HBR/Trabalho/avaliacao-assistente-20261124/pacote1/agenda-lote2/a2/voltar.sql).
-- IDEMPOTENTE: create or replace; o comentário só ganha o trecho do A2 uma vez.

CREATE OR REPLACE FUNCTION public._agenda_rotina_silencio(p_hoje date, p_agora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  m       record;
  v_os    uuid[];
  v_disp  uuid;
  v_rep   jsonb;
  v_nome  text;
  v_hora  text := to_char(cf.equipe_silencio_ate, 'FMHH24') || 'h'
                  || case when extract(minute from cf.equipe_silencio_ate) = 0 then '' else to_char(cf.equipe_silencio_ate, 'MI') end;
  v_n     int := 0;
  v_estado text;
  v_msg   text;
  -- P1 AGENDA: (A2, 26/11/2026) o silêncio que mantém o dia: o texto do 2º pedido e o que houve com ele
  v_pedido text;
  v_r2_id  uuid;
  v_r2_est text;
  v_r2_mot text;
  -- P1 AGENDA: fim
begin
  -- (a falta pelo silêncio só vale na manhã: depois do fim dela, o dia já é do "como foi hoje?")
  if cf.modo_equipe <> 'ligado' or v_local::time < cf.equipe_silencio_ate or v_local::time >= cf.manha_fim then
    return jsonb_build_object('silencio', 0);
  end if;
  for m in
    select x.*, p.phone from public.agenda_equipe_mensagens x
      join public.whatsapp_send_queue q on q.id = x.fila_id
      join public.payees p on p.id = x.payee_id
     where x.tipo = 'confirmar' and x.dia = p_hoje and x.modo = 'ligado' and x.estado = 'enfileirada' and x.resposta_em is null
       and q.status = 'sent' and q.sent_at <= p_agora - interval '30 minutes'
     order by x.enviar_em, x.id
  loop
    -- qualquer mensagem dele depois do envio: não é silêncio (o dono vê o trecho, se não foi entendido)
    continue when exists (select 1 from public.whatsapp_messages w
                           where w.direction = 'inbound' and w.created_at > m.enviar_em and w.created_at <= p_agora
                             and length(regexp_replace(coalesce(m.phone, ''), '\D', '', 'g')) >= 8
                             and right(regexp_replace(coalesce(w.phone_normalized, ''), '\D', '', 'g'), 8)
                                 = right(regexp_replace(m.phone, '\D', '', 'g'), 8));
    -- P1 AGENDA: (A2, decisão do dono de 24/11/2026; agenda_config.equipe_silencio_acao) com 'manter', o silêncio não tira o dia: avisa o dono
    -- (o acorde, pela ação silencio_manteve) e pede de novo ao técnico, no máximo uma vez por pessoa e dia (a resposta de chave
    -- reconfirmar:<dia>), em todo dia de silêncio. A confirmação fica 'enfileirada': o "ok" ou o "não vou" que vier depois ainda é a resposta a
    -- ela (agenda_resposta_da_equipe responde à última que o sistema começou, e o 2º pedido é tipo 'resposta', que o leitor não escolhe); depois
    -- do "como foi" das 17:00, a resposta é a ele. A ficha do dia segurada (_agenda_ficha_liberada, a regra da confirmação da manhã) não pede
    -- de novo. Sem dia dele no plano de hoje (o dono ou o motor já o tiraram), nada: não há dia a manter. Nada aqui decide por "ele leu": o
    -- sistema não sabe se a mensagem chegou. Com 'tirar' (o padrão), o de antes.
    if cf.equipe_silencio_acao = 'manter' then
      continue when exists (select 1 from public.agenda_acoes e
                             where e.tipo = 'equipe' and e.payee_id = m.payee_id and e.dia = p_hoje
                               and e.depois ->> 'motivo' = 'silencio_manteve');
      v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = m.payee_id);
      v_os := array(select distinct a.service_order_id from public.agenda_alocacoes a
                     where a.payee_id = m.payee_id and a.dia = p_hoje and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                     order by 1);
      continue when cardinality(v_os) = 0;
      v_r2_id := null;
      v_r2_est := null;
      v_r2_mot := null;
      if not public._agenda_ficha_liberada(m.payee_id, p_hoje, p_agora) then
        v_r2_mot := 'ficha_segurada';
      else
        v_pedido := regexp_replace(coalesce(public.agenda_equipe_ficha(m.payee_id, p_hoje, p_hoje) ->> 'texto_confirmar', ''),
                                   '^Bom dia, [^.]*\.\s*', '');
        if v_pedido = '' then
          v_r2_mot := 'sem_plano';
        else
          -- o erro do 2º pedido não segura o aviso ao dono: vai para app_error_logs e o texto diz "Não consegui pedir de novo."
          begin
            perform public._agenda_equipe_registrar(m.payee_id, p_hoje, 'resposta',
                      format('%s, ainda não vi sua resposta de hoje cedo. %s Responda *ok* se vem ou *não vou* se não der.', v_nome, v_pedido),
                      p_agora, null, 'reconfirmar:' || p_hoje::text);
            select r.id, r.estado, r.recusa_motivo into v_r2_id, v_r2_est, v_r2_mot from public.agenda_equipe_mensagens r
             where r.dedupe_key = format('agenda-equipe:resposta:%s:reconfirmar:%s', m.payee_id, p_hoje);
          exception when others then
            get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
            v_r2_id := null;
            v_r2_est := null;
            v_r2_mot := 'erro';
            perform public.log_app_error('db', 'agenda: o 2º pedido do silêncio à equipe falhou: ' || v_msg, 'agenda',
                                         'rotina:silencio', 'error', jsonb_build_object('payee', m.payee_id, 'dia', p_hoje, 'sqlstate', v_estado));
          end;
        end if;
      end if;
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
      values (clock_timestamp(), p_hoje, true, 'equipe', 'equipe', v_os[1], v_os, m.payee_id,
              jsonb_build_object('motivo', 'silencio_manteve', 'dia', p_hoje, 'mensagem', m.id, 'acorde', true,
                                 'segundo_pedido', v_r2_id, 'segundo_pedido_estado', coalesce(v_r2_est, 'nao_pedi'),
                                 'segundo_pedido_motivo', v_r2_mot),
              left(format('O %s não respondeu à confirmação de hoje até as %s (não sei se a mensagem chegou). Mantive o dia dele: %s. %s Se ele não for, me avise que eu refaço a agenda.',
                          v_nome, v_hora,
                          public._agenda_lista(array(select public._agenda_rotulo_da_os(u.x) from unnest(v_os) with ordinality u(x, o)
                                                      order by u.o), null),
                          case when v_r2_est = 'enfileirada' then 'Pedi de novo a ele.' else 'Não consegui pedir de novo.' end), 400));
      v_n := v_n + 1;
      continue;
    end if;
    -- P1 AGENDA: fim
    v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = m.payee_id);
    v_os := array(select distinct a.service_order_id from public.agenda_alocacoes a
                   where a.payee_id = m.payee_id and a.dia = p_hoje and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                   order by 1);
    v_disp := null;
    v_rep := null;
    if not exists (select 1 from public.agenda_disponibilidade d
                    where d.payee_id = m.payee_id and d.substituida_em is null and d.situacao = 'indisponivel'
                      and d.turno is null and d.periodo @> p_hoje) then
      insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_em)
      values (m.payee_id, daterange(p_hoje, p_hoje, '[]'), 'indisponivel', 'agente',
              'Sem resposta à confirmação até ' || to_char(cf.equipe_silencio_ate, 'HH24:MI'), p_agora)
      returning id into v_disp;
    end if;
    if cf.modo_proposta = 'ligado' and cardinality(v_os) > 0 then
      begin
        -- (C1, NOVO-agenda-27) a falta é evento real: o resto da OS volta num bloco só, amanhã incluído
        perform set_config('agenda.replano_da_falta', 'on', true);
        v_rep := public.agenda_replanejar(v_os, 'equipe_faltou', 'vigia', p_hoje, p_agora, null);
        perform set_config('agenda.replano_da_falta', '', true);
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        perform set_config('agenda.replano_da_falta', '', true);
        perform public.log_app_error('db', 'agenda: replanejar pelo silêncio da equipe falhou: ' || v_msg, 'agenda',
                                     'rotina:silencio', 'error', jsonb_build_object('os', to_jsonb(v_os), 'sqlstate', v_estado));
      end;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
    values (clock_timestamp(), p_hoje, true, 'equipe', 'equipe', v_os[1], v_os, m.payee_id,
            jsonb_build_object('motivo', 'silencio', 'dia', p_hoje, 'disponibilidade', v_disp, 'mensagem', m.id,
                               'replano_acoes', coalesce(v_rep -> 'acoes', '[]'::jsonb), 'acorde', true),
            left(format('O %s não respondeu à confirmação de hoje até as %s.', v_nome, v_hora)
                 || coalesce(' ' || nullif(v_rep ->> 'texto', ''), ''), 400));
    update public.agenda_equipe_mensagens set estado = 'sem_resposta' where id = m.id;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('silencio', v_n);
end;
$function$;

CREATE OR REPLACE FUNCTION public._agenda_rotina_acordes_da_equipe(p_hoje date, p_agora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  r        record;
  v_rep    uuid;
  v_nome   text;
  v_txt    text;
  v_acordes jsonb := '[]'::jsonb;
begin
  for r in
    select e.* from public.agenda_acoes e
     where e.tipo = 'equipe' and e.executada and e.contada_em is null and coalesce((e.depois ->> 'acorde')::boolean, false)
       and e.dia >= p_hoje - 1
       and (e.depois ->> 'dia')::date between p_hoje and public.agenda_somar_du(p_hoje, cf.congelamento_du)
     order by e.criada_em, e.id
  loop
    -- a mudança que o replano fez (a 1ª executada); o acorde sai uma vez (a mudança ou o aviso contados)
    select a.id into v_rep from public.agenda_acoes a
     where a.id in (select (x #>> '{}')::uuid from jsonb_array_elements(coalesce(r.depois -> 'replano_acoes', '[]'::jsonb)) x)
       and a.executada
     order by a.criada_em, a.id limit 1;
    continue when exists (select 1 from public.agenda_acoes a
                           where a.contada_via = 'acorde'
                             and (a.id = v_rep or a.id in (select (x #>> '{}')::uuid
                                                              from jsonb_array_elements(coalesce(r.depois -> 'replano_acoes', '[]'::jsonb)) x)));
    v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = r.payee_id);
    v_txt := case r.depois ->> 'motivo'
               when 'silencio' then split_part(r.texto, '.', 1) || '.'
               else format('O %s avisou que não vem %s.', v_nome, public._agenda_dia_da_equipe((r.depois ->> 'dia')::date, p_hoje)) end
             || case when v_rep is not null then ' ' || public._agenda_texto_do_acorde(v_rep, (r.depois ->> 'dia')::date, p_hoje)
                     else ' A agenda automática não está ligada: reveja o dia dele.' end;
    -- FASE 7f: (7f P5, §6.3) o convite sem o SIM no prazo (sem_sim) e o dia novo sem tempo de convidar (convite_sem_prazo): a pessoa não "avisou que
    -- não vem". A frase é a da ação (a 1ª, sem o replano); o replano vem do acorde de sempre.
    if r.depois ->> 'motivo' = 'sem_sim' then
      v_txt := split_part(r.texto, '.', 1) || '.'
               || case when v_rep is not null then ' ' || public._agenda_texto_do_acorde(v_rep, (r.depois ->> 'dia')::date, p_hoje)
                       else ' A agenda automática não está ligada: reveja o dia dele.' end;
    elsif r.depois ->> 'motivo' = 'convite_sem_prazo' then
      v_txt := r.texto;
    end if;
    -- FASE 7f: fim
    -- P1 AGENDA: (A2, 26/11/2026) o silêncio que manteve o dia (_agenda_rotina_silencio com equipe_silencio_acao = 'manter'): a frase é a da
    -- ação, inteira (não há replano a contar). O acorde marca a própria ação (acao_id = r.id) e ela não volta no tique seguinte.
    if r.depois ->> 'motivo' = 'silencio_manteve' then
      v_txt := r.texto;
    end if;
    -- P1 AGENDA: fim
    v_acordes := v_acordes || jsonb_build_object('chave', 'agenda:' || coalesce(v_rep, r.id), 'assunto', 'equipe:' || r.payee_id,
                   'acao_id', coalesce(v_rep, r.id), 'os', r.service_order_id, 'perda_em', r.depois ->> 'dia', 'texto', v_txt);
  end loop;
  return jsonb_build_object('acordes_da_equipe', jsonb_array_length(v_acordes), 'acordes', v_acordes);
end;
$function$;

-- ── Os comentários das recriadas (o de antes + o que mudou; uma vez só) ──────────────────────────────────────────────────────────────
do $c$
declare
  c_s constant text := 'public._agenda_rotina_silencio(date,timestamptz)';
  c_a constant text := 'public._agenda_rotina_acordes_da_equipe(date,timestamptz)';
begin
  if coalesce(obj_description(to_regprocedure(c_s), 'pg_proc'), '') not like '%P1 AGENDA (A2, 24/11/2026%' then
    execute format('comment on function %s is %L', c_s, ltrim(coalesce(obj_description(to_regprocedure(c_s), 'pg_proc'), '')
      || ' P1 AGENDA (A2, 24/11/2026, 20270301120300): com agenda_config.equipe_silencio_acao = ''manter'', o silêncio das 9h não tira o dia: nenhuma disponibilidade nem replano, a confirmação continua enfileirada, o 2º pedido ao técnico (tipo resposta, chave agenda-equipe:resposta:<pessoa>:reconfirmar:<dia>, no máximo 1 por pessoa e dia; não sai com a ficha do dia segurada) e a ação equipe silencio_manteve com acorde ("O Alex não respondeu à confirmação de hoje até as 9h (não sei se a mensagem chegou). Mantive o dia dele: Fernando (OS-00131). Pedi de novo a ele. Se ele não for, me avise que eu refaço a agenda."; sem o pedido, "Não consegui pedir de novo."). Sem dia dele no plano de hoje, nada. Com ''tirar'' (o padrão), o de antes.'));
  end if;
  if coalesce(obj_description(to_regprocedure(c_a), 'pg_proc'), '') not like '%P1 AGENDA (A2, 24/11/2026%' then
    execute format('comment on function %s is %L', c_a, ltrim(coalesce(obj_description(to_regprocedure(c_a), 'pg_proc'), '')
      || ' P1 AGENDA (A2, 24/11/2026, 20270301120300): o silêncio que manteve o dia (motivo silencio_manteve) tem a frase da ação, inteira, e marca a própria ação.'));
  end if;
end
$c$;

insert into supabase_migrations.schema_migrations (version, name) values ('20270301120300','agenda_p1_silencio_mantem');
