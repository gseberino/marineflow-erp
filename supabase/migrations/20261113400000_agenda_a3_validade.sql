-- Agenda de Produção: o conserto da validade do pedido A-3 da F5 (pedido da sessão do retorno, 14/11). Só funções: nenhuma tabela muda (nenhum
-- ALTER TABLE, nenhum CHECK; o que impedia a validade de mudar é só o gatilho agenda_cliente_mensagens_so_muda), nenhum dado, cron, edge ou tela.
-- Roteiro: agenda-pesquisa/fila-do-dono/agenda-a3-validade-publicar.md. Prova: supabase/tests/agenda_a3_validade.sql (begin/rollback, na bancada) e
-- supabase/tests/agenda_a3_validade_pos_deploy.sql (só leitura, em produção depois de aplicar).
--
-- O problema: o "Fechado" da F5 promete "O Gustavo te passa a data por aqui", e o A-3 (20261113300000) empurra a confirmação para o dia útil
-- seguinte; como a confirmação vale só no dia dela, a hora nova passava da validade e ela caía ("não saiu, recomendo ligar") justamente no caso
-- mais comum (o cliente aceita e a agenda marca no mesmo dia).
-- O conserto:
--   (1) a confirmação empurrada pelo "Fechado" (motivo orcamento_fechado) e a véspera empurrada pela saída do orçamento do dia (A-1,
--       orcamento_hoje) levam a validade junto, pela mesma distância (os dias entre o dia de envio de antes e o novo);
--   (2) a validade nova nunca passa do início do dia de que a mensagem fala (dia_alvo); e a confirmação, a véspera e o acesso nunca são
--       empurrados para esse dia ou depois: aí não esperam e valem como o teto do dia, como hoje (a confirmação que pergunta "podemos começar
--       <dia>?" não sai no dia do serviço);
--   (3) a revalidação da hora nova continua mandando (o status, a data, o material, a data dita, o texto: a véspera que dizia "Amanhã" fica
--       desatualizada no dia novo e cai; a confirmação fala o dia por extenso e não muda);
--   (4) a guarda da tabela (_agenda_cliente_mensagens_so_muda) aceita o avanço da validade só por este caminho: com agenda.cliente_validade_avanca
--       ligado nesta transação (o enfileirar liga só em volta desse UPDATE), a mensagem esperando, em ligado, confirmar ou vespera, e só a hora e a
--       validade mudando, as duas para a frente. Fora disso, o mesmo erro de antes.
--
-- AS RECRIADAS partem do corpo VIGENTE em produção (q0.sh a3v_md5, 14/11): o montador (agenda-pesquisa/a3v/montar.mjs) confere o md5 do corpo (sem CR)
-- e do comment e recusa se diferir; tirados os blocos "-- PEDIDO A-3, VALIDADE (F5): … fim", cada uma é a origem byte a byte.
--   _agenda_cliente_mensagens_so_muda   20261028100000:315   89bdf01e9f6f759236c9c5dc92578f30
--   _agenda_cliente_enfileirar          20261113300000:131   38775240c466381c78714aea11fa8d71   (os 2 blocos novos ficam dentro dos do A-1/A-3)
--
-- DESFAZER: agenda-pesquisa/a3v/volta-a3v.sql (numa transação: as 2 voltam ao corpo e ao comment de antes). A mensagem que já teve a validade
-- empurrada segue com ela.
-- Sem begin/commit: o aplicar.sh roda numa transação e falha inteiro. IDEMPOTENTE: só create or replace, revoke/grant e comment.

-- ── 1. A guarda da tabela: a validade avança só por este caminho ───────────────────────────────────────────────────────────────────────
-- O corpo de 20261028100000:315 (md5 sem CR 89bdf01e9f6f759236c9c5dc92578f30, o de produção em 14/11) + só o bloco "-- PEDIDO A-3, VALIDADE (F5):". O gatilho
-- (agenda_cliente_mensagens_so_muda, BEFORE UPDATE) não muda: o create or replace troca só o corpo.
create or replace function public._agenda_cliente_mensagens_so_muda()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  -- PEDIDO A-3, VALIDADE (F5): a validade só avança por um caminho, o do enfileirar quando empurra a confirmação depois do "Fechado" ou a
  -- véspera depois do orçamento do dia (ele liga agenda.cliente_validade_avanca nesta transação): a mensagem esperando (registrada ou
  -- esperando o dono), em ligado, confirmar ou vespera; só a hora e a validade mudam (e o modelo, que é gerado e chega nulo no BEFORE UPDATE),
  -- as duas para a frente, com a hora dentro da validade nova.
  -- Fora disso, a validade continua não mudando (o mesmo erro de antes).
  if new.valida_ate is distinct from old.valida_ate then
    if coalesce(current_setting('agenda.cliente_validade_avanca', true), '') <> 'on'
       or old.estado not in ('registrada', 'aguardando_dono') or old.modo <> 'ligado' or old.tipo not in ('confirmar', 'vespera')
       or new.valida_ate < old.valida_ate or new.enviar_em <= old.enviar_em or new.enviar_em > new.valida_ate
       or not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new), array['enviar_em', 'valida_ate', 'modelo'], '{}') then
      raise exception 'A mensagem ao cliente registrada não muda: só o estado, a aprovação, a fila, o envio e a resposta.';
    end if;
    return new;
  end if;
  -- PEDIDO A-3, VALIDADE (F5): fim
  if not public._agenda_so_mudou(to_jsonb(old), to_jsonb(new),
           array['estado', 'recusa_motivo', 'fila_id', 'aprovacao', 'pergunta_id', 'aprovada_em', 'aprovada_por',
                 'enviada_em', 'resposta_id', 'acao_id', 'enviar_em', 'modelo'],
           array['aprovada_por', 'acao_id']) then
    raise exception 'A mensagem ao cliente registrada não muda: só o estado, a aprovação, a fila, o envio e a resposta.';
  end if;
  -- A hora só muda enquanto a mensagem espera (d19: a conversa viva empurra para o próximo tique).
  if new.enviar_em is distinct from old.enviar_em and old.estado not in ('registrada', 'aguardando_dono') then
    raise exception 'A hora da mensagem ao cliente só muda enquanto ela espera (registrada ou esperando o dono).';
  end if;
  return new;
end;
$function$;

comment on function public._agenda_cliente_mensagens_so_muda() is
  'Agenda de Produção (Fase 5): gatilho BEFORE UPDATE de agenda_cliente_mensagens — só estado, recusa_motivo, fila_id, aprovacao, pergunta_id, aprovada_*, enviada_em, resposta_id, acao_id e enviar_em mudam (este só enquanto a mensagem está registrada ou esperando o dono); o texto, o tipo, o cliente, a OS, o modo, a chave e a base ficam como foram. PEDIDO A-3, VALIDADE (F5): valida_ate muda só com agenda.cliente_validade_avanca = on (o enfileirar, nesse UPDATE), com a mensagem esperando (registrada ou esperando o dono), em ligado, confirmar ou vespera, e só enviar_em e valida_ate mudando, as duas para a frente, com a hora dentro da validade nova. Fora disso, o mesmo erro de antes.';

-- ── 2. O enfileirar: a validade junto com a hora, e nunca o dia do serviço ───────────────────────────────────────────────────────────────
-- O corpo de 20261113300000:131 (md5 sem CR 38775240c466381c78714aea11fa8d71, o de produção em 14/11, o do A-1/A-3) + só os 2 blocos "-- PEDIDO A-3, VALIDADE (F5):",
-- ambos DENTRO dos blocos "-- PEDIDO A-1 e A-3 (F5):" (tirados estes, sobra a de 20261028100800, como antes).
create or replace function public._agenda_cliente_enfileirar(p_msg uuid, p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_tique constant interval := interval '15 minutes';   -- o tique do motor (task-automations a cada 15 min)
  m       public.agenda_cliente_mensagens%rowtype;
  v_q     timestamptz;
  v_dia   date;
  v_seg   date;
  v_fone  text;
  v_teste boolean;
  v_tent  int;
  v_fila  uuid;
  v_motivo text;
  v_det   text;
  v_novo  timestamptz;
  v_perg  uuid;
  v_n     int;
  -- PEDIDO A-1 e A-3 (F5): o dia em que a mensagem pode sair por causa das saídas do orçamento a este cliente
  v_a13   jsonb;
  -- PEDIDO A-3, VALIDADE (F5): o dia de que a mensagem fala e a validade empurrada junto com a hora
  v_alvo   date;
  v_valida timestamptz;
  -- PEDIDO A-3, VALIDADE (F5): fim
  -- PEDIDO A-1 e A-3 (F5): fim
begin
  -- o teto é contado e a linha entra numa vez só, mesmo com dois tiques ao mesmo tempo
  perform pg_advisory_xact_lock(hashtext('agenda_cliente_fila'));
  select * into m from public.agenda_cliente_mensagens where id = p_msg for update;
  if not found then
    raise exception 'Não encontrei essa mensagem ao cliente.' using errcode = 'P0002';
  end if;
  -- já decidida (o tique seguinte não refaz)
  if m.estado not in ('registrada', 'aguardando_dono') then
    return jsonb_build_object('estado', m.estado, 'motivo', m.recusa_motivo, 'fila_id', m.fila_id);
  end if;
  -- 1. o modo e o tipo: em teste (ou com o modo fora de ligado) fica como está
  if m.modo <> 'ligado' or cf.modo_cliente <> 'ligado' then
    return jsonb_build_object('estado', m.estado, 'motivo', 'modo');
  end if;
  if not (m.tipo = any (cf.cliente_tipos_ligados)) then
    return jsonb_build_object('estado', m.estado, 'motivo', 'tipo_em_teste');
  end if;
  -- 2. a aprovação: esperando o dono fica esperando; segurada ou vencida não sai
  if m.aprovacao in ('pedida', 'critica') then
    if m.estado <> 'aguardando_dono' then
      update public.agenda_cliente_mensagens set estado = 'aguardando_dono' where id = m.id;
    end if;
    return jsonb_build_object('estado', 'aguardando_dono', 'motivo', 'aprovacao', 'pergunta_id', m.pergunta_id);
  end if;
  v_motivo := case when m.aprovacao in ('segurada', 'vencida') then m.aprovacao
                   when greatest(m.enviar_em, p_agora) > m.valida_ate then 'vencida' end;
  -- d19: o cliente (ou o dono com ele) conversando agora — a mensagem espera o próximo tique (não é recusada); se a janela
  -- do dia acabar, a próxima hora de janela, se ainda valer
  if v_motivo is null and cf.cliente_conversa_viva_min > 0
     and exists (select 1 from public.clients c
                   join public.whatsapp_messages w
                     on public._agenda_chave_telefone(w.phone_normalized)
                        in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone))
                  where c.id = m.client_id and w.occurred_at <= p_agora
                    and w.occurred_at > p_agora - make_interval(mins => cf.cliente_conversa_viva_min)) then
    v_novo := public._agenda_cliente_quando(hashtext(m.dedupe_key), p_agora + c_tique, p_agora, m.id);
    if v_novo > m.valida_ate then
      v_motivo := 'vencida';
    else
      update public.agenda_cliente_mensagens set enviar_em = v_novo where id = m.id;
      return jsonb_build_object('estado', m.estado, 'motivo', 'conversa_viva', 'enviar_em', v_novo);
    end if;
  end if;

  -- CORREÇÃO FASE 5: (item 3a) a mensagem livre ou aprovada cujo DIA marcado já passou (o dono aprovou depois do dia, a
  -- conversa viva a empurrou) e que ainda vale (valida_ate) não é recusada por "janela" ("outro dia que não o da hora
  -- marcada"): ganha a próxima hora possível a partir de agora (a regra única, _agenda_cliente_quando) e segue — a
  -- revalidação de agora decide (o texto com "Amanhã" fica desatualizado, que é o certo). Passou da validade = vencida;
  -- a hora nova depois do próximo tique fica registrada (o passo fila a manda na hora).
  if v_motivo is null and m.aprovacao in ('livre', 'aprovada')
     and (m.enviar_em at time zone 'America/Sao_Paulo')::date < (p_agora at time zone 'America/Sao_Paulo')::date then
    v_novo := public._agenda_cliente_quando(hashtext(m.dedupe_key), p_agora, p_agora, m.id);
    if v_novo > m.valida_ate then
      v_motivo := 'vencida';
    else
      update public.agenda_cliente_mensagens set enviar_em = v_novo where id = m.id;
      m.enviar_em := v_novo;
      if v_novo > p_agora + c_tique then
        return jsonb_build_object('estado', m.estado, 'motivo', 'remarcada', 'enviar_em', v_novo);
      end if;
    end if;
  end if;
  -- CORREÇÃO FASE 5: fim
  v_q := greatest(m.enviar_em, p_agora);
  v_dia := (m.enviar_em at time zone 'America/Sao_Paulo')::date;
  if v_motivo is null then
    v_motivo := case
      -- 3. o cliente pediu para não receber
      when public._agenda_cliente_sem_mensagem(m.client_id) then 'opt_out'
      -- 4. só a quem já escreveu para a HBR (d10); sem telefone válido nenhum (ou o número é de alguém da HBR), o motivo
      -- verdadeiro é o telefone (o Lenine: sem número, ninguém "conversou")
      when not public._agenda_cliente_conversou(m.client_id, v_q)
        then case when public._agenda_cliente_telefone(m.client_id) is null then 'sem_telefone' else 'sem_conversa' end
      -- 5. a revalidação (o status, a data, o material, a data dita, o mesmo tipo, o texto)
      else public._agenda_cliente_revalidar(m.id, p_agora)
    end;
  end if;
  -- 6. domingo, feriado, a janela (a regra única): no dia marcado, agora ou na hora marcada
  if v_motivo is null then
    v_motivo := public._agenda_cliente_fora_da_janela(m.enviar_em, v_q);
  end if;
  -- 7. o teto: por cliente no dia e na semana ISO, e o total do dia (contados como o gatilho da fila conta)
  if v_motivo is null then
    v_seg := date_trunc('week', v_dia)::date;
    v_n := public._agenda_cliente_no_periodo(m.client_id, v_seg, v_seg + 6, m.id);
    v_motivo := case
      when public._agenda_cliente_no_periodo(m.client_id, v_dia, v_dia, m.id) >= cf.cliente_dia_max then 'teto_dia'
      when v_n >= cf.cliente_semana_max then 'teto_semana'
      when public._agenda_cliente_no_periodo(null, v_dia, v_dia, m.id) >= cf.cliente_total_dia_max then 'teto_total' end;
    -- PEDIDO A-1 e A-3 (F5): a saída do orçamento a este cliente (_agenda_cliente_orcamento_espera). A-1: uma já foi no dia da mensagem = a
    -- mensagem espera o dia seguinte; A-3: a confirmação antes do dia útil seguinte ao "Fechado" = espera esse dia útil. Remarca enviar_em
    -- pela regra única (_agenda_cliente_quando) e devolve sem recusar (o passo fila a manda na hora nova). Se a hora nova passa da validade
    -- (que não muda), a mensagem não pode esperar: vale como o teto do dia (teto_dia), e o aviso de atraso ou de mudança no dia vira a
    -- pergunta crítica ao dono logo abaixo (d13), contando a mensagem do orçamento na semana.
    if v_motivo is null then
      v_a13 := public._agenda_cliente_orcamento_espera(m.client_id, m.tipo, v_dia, p_agora);
      if v_a13 is not null then
        v_novo := public._agenda_cliente_quando(hashtext(m.dedupe_key),
                    ((v_a13 ->> 'dia')::date)::timestamp at time zone 'America/Sao_Paulo', p_agora, m.id);
        -- PEDIDO A-3, VALIDADE (F5): a confirmação, a véspera e o acesso falam do início do serviço (dia_alvo) e nunca são empurrados para o dia
        -- dele ou depois: aí não esperam (valem como o teto do dia, logo abaixo). A confirmação empurrada pelo "Fechado" (A-3) e a véspera
        -- empurrada pela saída do orçamento do dia (A-1) levam a validade junto, pela mesma distância (os dias entre o dia de envio de antes e o
        -- novo), nunca além do início do dia_alvo; a guarda da tabela (_agenda_cliente_mensagens_so_muda) só aceita esse avanço com
        -- agenda.cliente_validade_avanca ligado nesta transação. A revalidação da hora nova continua mandando (o status, a data, o material, o
        -- texto: a véspera que dizia "Amanhã" fica desatualizada e cai).
        v_alvo := coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo);
        if m.tipo in ('confirmar', 'vespera', 'acesso') and v_alvo is not null
           and (v_novo at time zone 'America/Sao_Paulo')::date >= v_alvo then
          v_novo := 'infinity'::timestamptz;   -- passa do dia de que ela fala: não espera
        elsif v_novo > m.valida_ate and v_alvo is not null
              and ((m.tipo = 'confirmar' and v_a13 ->> 'motivo' = 'orcamento_fechado')
                   or (m.tipo = 'vespera' and v_a13 ->> 'motivo' = 'orcamento_hoje')) then
          v_valida := least(m.valida_ate + ((v_novo at time zone 'America/Sao_Paulo')::date - v_dia) * interval '1 day',
                            v_alvo::timestamp at time zone 'America/Sao_Paulo');
          if v_novo <= v_valida then
            perform set_config('agenda.cliente_validade_avanca', 'on', true);
            update public.agenda_cliente_mensagens set enviar_em = v_novo, valida_ate = v_valida where id = m.id;
            perform set_config('agenda.cliente_validade_avanca', '', true);
            return jsonb_build_object('estado', m.estado, 'motivo', v_a13 ->> 'motivo', 'enviar_em', v_novo, 'valida_ate', v_valida);
          end if;
        end if;
        -- PEDIDO A-3, VALIDADE (F5): fim
        if v_novo <= m.valida_ate then
          update public.agenda_cliente_mensagens set enviar_em = v_novo where id = m.id;
          return jsonb_build_object('estado', m.estado, 'motivo', v_a13 ->> 'motivo', 'enviar_em', v_novo);
        end if;
        v_motivo := 'teto_dia';
        v_n := v_n + 1;
      end if;
    end if;
    -- PEDIDO A-1 e A-3 (F5): fim
    -- d13: o aviso que não cabe no teto não fica mudo — vira pergunta crítica ao dono (recomenda ligar); a mensagem espera
    -- a decisão (a opção 2 passa de novo pelo canal: com o teto cheio, não sai)
    if v_motivo is not null and m.tipo in ('pode_atrasar', 'mudanca_no_dia') and m.aprovacao <> 'aprovada' then
      v_perg := public._agenda_cliente_perguntar('cliente_aviso',
                  format('cliente_aviso:%s:%s', m.service_order_id, coalesce(m.dia_alvo, v_dia)), m.service_order_id,
                  coalesce(m.dia_alvo, v_dia), v_dia,
                  public._agenda_cliente_texto_do_aviso('teto', m.tipo, m.service_order_id,
                    coalesce(m.base -> 'dados', '{}'::jsonb) || jsonb_build_object('mensagens_na_semana', v_n),
                    (p_agora at time zone 'America/Sao_Paulo')::date),
                  'ligado', p_agora, m.valida_ate);
      update public.agenda_cliente_mensagens
         set aprovacao = 'critica', pergunta_id = v_perg, estado = 'aguardando_dono'
       where id = m.id;
      return jsonb_build_object('estado', 'aguardando_dono', 'motivo', v_motivo, 'pergunta_id', v_perg);
    end if;
  end if;
  -- CORREÇÃO FASE 5: (item 14) o choque de intervalo REMARCA a hora (o próximo instante longe das outras, pela regra única
  -- _agenda_cliente_quando) em vez de recusar para sempre — a outra marcada pode ser uma nova tentativa (+5 min) que caiu
  -- perto, e a chave desta não volta. A que passaria da validade vence. Fica registrada: o passo fila a enfileira na hora
  -- nova. Só a trava da fila recusa por intervalo (o 8, abaixo, fica como defesa e já não acha nada).
  if v_motivo is null
     and exists (select 1 from public.whatsapp_send_queue q
                  where q.source = 'agenda-cliente' and q.status in ('pending', 'sending')
                    and q.source_ref_id is distinct from m.id
                    and q.scheduled_for > m.enviar_em - make_interval(secs => cf.cliente_intervalo_min_s)
                    and q.scheduled_for < m.enviar_em + make_interval(secs => cf.cliente_intervalo_min_s)) then
    v_novo := public._agenda_cliente_quando(hashtext(m.dedupe_key), m.enviar_em, p_agora, m.id);
    if v_novo > m.valida_ate then
      v_motivo := 'vencida';
    else
      update public.agenda_cliente_mensagens set enviar_em = v_novo where id = m.id;
      return jsonb_build_object('estado', m.estado, 'motivo', 'intervalo', 'enviar_em', v_novo);
    end if;
  end if;
  -- CORREÇÃO FASE 5: fim
  -- 8. o intervalo: outra linha agenda-cliente pendente ou saindo a menos de cliente_intervalo_min_s
  if v_motivo is null
     and exists (select 1 from public.whatsapp_send_queue q
                  where q.source = 'agenda-cliente' and q.status in ('pending', 'sending')
                    and q.source_ref_id is distinct from m.id
                    and q.scheduled_for > m.enviar_em - make_interval(secs => cf.cliente_intervalo_min_s)
                    and q.scheduled_for < m.enviar_em + make_interval(secs => cf.cliente_intervalo_min_s)) then
    v_motivo := 'intervalo';
  end if;
  -- 9. o telefone dele (nunca o do dono, da equipe nem de quem recebe diária); o modo de teste do WhatsApp vai para o
  -- número de teste (o mesmo desvio da equipe, do fornecedor e de pedir_confirmacao_do_agendamento); sem ele, nada sai
  if v_motivo is null then
    v_fone := public._agenda_cliente_telefone(m.client_id);
    v_teste := coalesce((select x.value::text from public.app_settings x where x.key = 'wa_test_mode'), 'false') in ('true', '"true"');
    if v_fone is not null and v_teste then
      v_fone := nullif(regexp_replace(coalesce((select x.value::text from public.app_settings x where x.key = 'wa_test_number'), ''),
                                      '\D', '', 'g'), '');
    end if;
    if length(coalesce(v_fone, '')) < 12 then
      v_motivo := 'sem_telefone';
    end if;
  end if;
  if v_motivo is not null then
    update public.agenda_cliente_mensagens
       set estado = 'recusada', recusa_motivo = v_motivo,
           aprovacao = case when m.aprovacao in ('pedida', 'critica') and v_motivo = 'vencida' then 'vencida' else aprovacao end
     where id = m.id;
    return jsonb_build_object('estado', 'recusada', 'motivo', v_motivo);
  end if;

  -- 10. a fila: as tentativas (+5 min) que cabem na janela da mensagem, contadas de agora (a regra única; a 1ª já cabe)
  v_tent := greatest(1, (select count(*)::int from generate_series(0, 2) k
                          where public._agenda_cliente_fora_da_janela(m.enviar_em, v_q + make_interval(mins => 5 * k)) is null));
  -- a trava da fila (o gatilho) recusa com 23514 o que passaria da janela, do teto, do intervalo ou da revalidação: aqui
  -- isso vira a recusa da mensagem com o motivo, sem desfazer o que veio antes na mesma transação
  begin
    insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, priority, scheduled_for,
                                            max_attempts, dedupe_key)
    values (v_fone, m.texto, 'agenda-cliente', m.id, 5, m.enviar_em, v_tent, m.dedupe_key)
    on conflict do nothing
    returning id into v_fila;
  exception when sqlstate '23514' then
    get stacked diagnostics v_det = pg_exception_detail;
    v_motivo := case when v_det in ('janela', 'domingo', 'feriado', 'teto_dia', 'teto_semana', 'teto_total', 'intervalo',
                                    'opt_out', 'status', 'data_mudou', 'material', 'passou_da_data', 'mesmo_tipo_24h',
                                    'desatualizada') then v_det else 'janela' end;
    -- CORREÇÃO FASE 5: (item 13) a revalidação da trava da fila também diz sem_conversa / sem_telefone (o d10)
    if v_det in ('sem_conversa', 'sem_telefone') then
      v_motivo := v_det;
    end if;
    -- CORREÇÃO FASE 5: fim
    update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = v_motivo where id = m.id;
    return jsonb_build_object('estado', 'recusada', 'motivo', v_motivo, 'pela_fila', true);
  end;
  if v_fila is null then
    -- a mesma chave já estava na fila (o gatilho de idempotência de produção devolve nada): é a mesma mensagem
    select q.id into v_fila from public.whatsapp_send_queue q where q.dedupe_key = m.dedupe_key;
  end if;
  update public.agenda_cliente_mensagens set estado = 'enfileirada', fila_id = v_fila where id = m.id;
  return jsonb_build_object('estado', 'enfileirada', 'fila_id', v_fila, 'teste', v_teste, 'tentativas', v_tent,
                            'enviar_em', m.enviar_em);
end;
$function$;

comment on function public._agenda_cliente_enfileirar(uuid, timestamptz) is
  'Agenda de Produção (Fase 5, P2): a 1ª trava — a decisão do envio de uma mensagem ao cliente registrada (ou esperando o dono), na ordem: modo_cliente fora de ligado ou a mensagem em teste = fica (modo); o tipo fora de cliente_tipos_ligados = fica (tipo_em_teste); aprovação pedida/crítica = aguardando_dono; segurada/vencida, ou a validade passada = recusada; d19 a conversa viva (mensagem do cliente ou ao cliente nos últimos cliente_conversa_viva_min) = espera o próximo tique (enviar_em pelo _agenda_cliente_quando; passou da validade = vencida); opt_out; sem_conversa (d10); a revalidação (_agenda_cliente_revalidar); domingo/feriado/janela; o teto (teto_dia, teto_semana na semana ISO, teto_total; d13: o aviso de atraso ou de mudança no dia que não cabe vira a pergunta crítica cliente_aviso e espera o dono); o intervalo (outra agenda-cliente pendente ou saindo a menos de cliente_intervalo_min_s); sem_telefone (_agenda_cliente_telefone; wa_test_mode = o número de teste). Senão whatsapp_send_queue (source agenda-cliente, source_ref_id = a mensagem, o texto e a chave dela, priority 5, scheduled_for = enviar_em, max_attempts = as tentativas de +5 min que cabem na janela) e enfileirada; o 23514 da trava da fila vira recusada com o motivo do detail. Idempotente. Sem grant. CORREÇÃO FASE 5 (C1): o choque de intervalo remarca enviar_em (_agenda_cliente_quando; passou da validade = vencida) e devolve {estado registrada, motivo intervalo, enviar_em} em vez de recusar (item 14); o sem_conversa/sem_telefone da trava da fila vira o motivo (item 13). CORREÇÃO FASE 5 (C2, item 3a): a livre ou aprovada com o dia de enviar_em já passado e ainda válida ganha enviar_em = _agenda_cliente_quando(agora) e segue (depois do próximo tique: {estado registrada, motivo remarcada}); passou da validade = vencida. PEDIDO A-1 e A-3 (F5): depois do teto, a saída do orçamento a este cliente (_agenda_cliente_orcamento_espera): A-1, uma já foi no dia da mensagem = ela espera o dia seguinte; A-3, a confirmação antes do dia útil seguinte ao "Fechado" = espera esse dia útil. enviar_em = _agenda_cliente_quando(o início desse dia) e devolve {estado de antes, motivo orcamento_hoje | orcamento_fechado, enviar_em}: não recusa nem vence. Se a hora nova passa de valida_ate (a validade da mensagem não muda), vale como o teto do dia (teto_dia): o aviso de atraso ou de mudança no dia vira a pergunta crítica cliente_aviso (d13, contando a mensagem do orçamento na semana) e o resto fica recusado. PEDIDO A-3, VALIDADE (F5): a confirmação, a véspera e o acesso nunca são empurrados (A-1/A-3) para o dia de que falam (dia_alvo) ou depois: aí valem como o teto do dia. A confirmação empurrada pelo "Fechado" (motivo orcamento_fechado) e a véspera empurrada pela saída do orçamento do dia (orcamento_hoje) que passariam da validade levam a validade junto, pela mesma distância em dias, nunca além do início do dia_alvo (agenda.cliente_validade_avanca ligado só nesse UPDATE) e devolvem {estado de antes, motivo, enviar_em, valida_ate}. A revalidação da hora nova continua mandando.';

-- ── 3. As portas (as de antes, reafirmadas: o create or replace já as mantém) ──────────────────────────────────────────────────────────
revoke all on function public._agenda_cliente_mensagens_so_muda() from public, anon, authenticated;
grant execute on function public._agenda_cliente_mensagens_so_muda() to service_role;
revoke all on function public._agenda_cliente_enfileirar(uuid, timestamptz) from public, anon, authenticated, service_role;

notify pgrst, 'reload schema';
