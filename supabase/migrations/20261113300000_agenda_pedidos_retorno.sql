-- Agenda de Produção: os pedidos A-1, A-3 e A-5 da F5 do retorno rápido (spec da F5, seção 9.2; R-3 e D-13). Só funções: nenhuma tabela muda (nenhum
-- ALTER TABLE), nenhum dado, cron, edge ou tela. Não tem modo: vale ao entrar, mas só age quando existir saída do retorno de verdade (enviada).
-- Roteiro: agenda-pesquisa/fila-do-dono/agenda-a1a3-publicar.md. Prova: supabase/tests/agenda_pedidos_retorno.sql (begin/rollback, na bancada) e
-- supabase/tests/agenda_pedidos_retorno_pos_deploy.sql (só leitura, em produção depois de aplicar).
--
-- A-1. A agenda conta a saída do orçamento (retorno_saidas, emissor orcamento) enviada hoje a este cliente como "já falou com ele hoje": a mensagem da
--      agenda espera o dia seguinte. O enfileirar (a 1ª trava), depois do teto, remarca enviar_em pela regra única (_agenda_cliente_quando), como a
--      conversa viva já faz, e devolve {motivo orcamento_hoje, enviar_em}: não recusa nem vence.
-- A-3. Depois do "Fechado" da F5 (orc_fechado: "O Gustavo te passa a data por aqui"), a confirmação (confirmar) espera o dia útil da agenda seguinte ao
--      envio do "Fechado" (agenda_somar_du: sem sábado, domingo, feriado nem recesso): {motivo orcamento_fechado, enviar_em}.
--      Quando a hora nova passa da validade da mensagem (valida_ate não muda: a confirmação e a véspera valem só no dia delas), ela não tem como esperar
--      e vale como o teto do dia que já existe (teto_dia): o aviso de atraso ou de mudança no dia vira a pergunta crítica ao dono (d13, "Recomendo você
--      ligar"), e o resto fica recusado (o dono que aprovou fica sabendo, como em toda recusa de mensagem aprovada). O gatilho da fila (a 2ª trava) ganha
--      a mesma regra, para o enfileirar e o gatilho não divergirem.
-- A-5. O teto do dia a todos (teto_total, cliente_total_dia_max) soma as iniciadas do retorno que já saíram hoje (classe aviso, resumo_parceiro e
--      comercial), contadas como o canal do retorno conta as dele: o teto do número vale nos dois sentidos. Entra em _agenda_cliente_no_periodo (o
--      total, p_cliente null), a conta única que o enfileirar, o gatilho da fila e o botão (_pedir_confirmacao) usam: os três contam igual.
--
-- "Mesmo cliente" e "hoje" espelham a F5 no sentido inverso (20270112100400_retorno_f5_canal.sql, _orcamento_checar_antes): o client_id, e o dia de
-- Brasília da hora do envio (ou da decisão), com a saída enviada, incerta ou enviando.
-- Sem a tabela retorno_saidas (a bancada da agenda deixa as migrations do retorno de fora), as 2 novas devolvem null e 0: a agenda fica como antes.
--
-- AS RECRIADAS partem do corpo VIGENTE em produção (q0.sh a1a3_md5, 13/11): o montador (agenda-pesquisa/a1a3/montar.mjs) copia a definição mais nova
-- do repo, confere o md5 do corpo (sem CR) e do comment contra o de produção e recusa se diferir; tirados os blocos "-- PEDIDO A-x (F5): … fim", cada
-- uma é a origem byte a byte. O create or replace mantém dono, ACL e defaults; as portas de antes são reafirmadas no fim.
--   _agenda_cliente_enfileirar   20261028100800:1197  39c92c146c43d1a24dcdb42afaea14b7
--   _agenda_fila_do_cliente      20261028100200:1051  6e462b7407bf84237607f2ab7b11df1b
--   _agenda_cliente_no_periodo   20261028100200:305   d99e071a323385c9b46f468b7a93eaff
-- Nenhuma migration da F5 (20270112100000–100900) nem a 20261113200000 recria estas 3.
--
-- DESFAZER: agenda-pesquisa/a1a3/volta-a1a3.sql (numa transação: as 3 voltam ao corpo e ao comment de antes, as 2 novas saem). A mensagem que já foi
-- remarcada segue registrada com a hora nova.
-- Sem begin/commit: o aplicar.sh roda numa transação e falha inteiro. IDEMPOTENTE: só create or replace, revoke e comment.

-- ── 1. As saídas do orçamento a este cliente: quando a mensagem da agenda pode sair (PEDIDO A-1 e A-3 da F5) ─────────────────────────────
-- Nova, interna (invoker, sem grant: quem chama é o enfileirar e o gatilho da fila, os dois definer). Sem a tabela do retorno (a bancada da agenda
-- deixa as migrations do retorno de fora), devolve null: a agenda fica como antes.
create or replace function public._agenda_cliente_orcamento_espera(p_cliente uuid, p_tipo text, p_dia date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_ini  timestamptz;
  v_fim  timestamptz;
  v_dia  date;
  v_mot  text;
  v_df   date;
  v_du   date;
begin
  if p_cliente is null or p_dia is null or p_agora is null then
    return null;
  end if;
  -- a bancada da agenda não tem as tabelas do retorno; em produção a tabela existe sempre
  if to_regclass('public.retorno_saidas') is null then
    return null;
  end if;
  v_ini := p_dia::timestamp at time zone c_fuso;
  v_fim := (p_dia + 1)::timestamp at time zone c_fuso;
  -- A-1: uma saída do orçamento (emissor orcamento: lembrete, véspera, encerramento, "Fechado", dados da nota) já foi a este cliente neste dia,
  -- até agora. "Foi" e "neste dia" como a F5 conta a comercial do dia (_orcamento_checar_antes): enviada, incerta ou enviando, pela hora do
  -- envio (ou da decisão), no dia de Brasília; o mesmo cliente pelo client_id, como a F5 olha a agenda. A mensagem da agenda espera o dia seguinte.
  if exists (select 1 from public.retorno_saidas s
              where s.client_id = p_cliente and s.emissor = 'orcamento'
                and s.estado in ('enviada', 'incerta', 'enviando')
                and coalesce(s.enviada_em, s.decidida_em) >= v_ini and coalesce(s.enviada_em, s.decidida_em) < v_fim
                and coalesce(s.enviada_em, s.decidida_em) <= p_agora) then
    v_dia := p_dia + 1;
    v_mot := 'orcamento_hoje';
  end if;
  -- A-3: a confirmação depois do "Fechado" (orc_fechado, "O Gustavo te passa a data por aqui") espera o dia útil da agenda seguinte ao dia
  -- do envio dele (agenda_somar_du(dia, 1): sem sábado, salvo sabado_util, domingo, feriado nem recesso). O "Fechado" mais recente decide.
  if p_tipo = 'confirmar' then
    select max((coalesce(s.enviada_em, s.decidida_em) at time zone c_fuso)::date) into v_df
      from public.retorno_saidas s
     where s.client_id = p_cliente and s.emissor = 'orcamento' and s.tipo = 'orc_fechado'
       and s.estado in ('enviada', 'incerta', 'enviando')
       and coalesce(s.enviada_em, s.decidida_em) < v_fim
       and coalesce(s.enviada_em, s.decidida_em) <= p_agora;
    if v_df is not null then
      v_du := public.agenda_somar_du(v_df, 1);
      if v_du > p_dia and v_du >= coalesce(v_dia, v_du) then
        v_dia := v_du;
        v_mot := 'orcamento_fechado';
      end if;
    end if;
  end if;
  if v_dia is null then
    return null;
  end if;
  return jsonb_build_object('dia', v_dia, 'motivo', v_mot);
end;
$function$;

comment on function public._agenda_cliente_orcamento_espera(uuid, text, date, timestamptz) is
  'Agenda de Produção (pedidos A-1 e A-3 da F5 do retorno): o 1º dia em que a mensagem da agenda a este cliente, marcada para p_dia, pode sair por causa das saídas do orçamento (retorno_saidas, emissor orcamento), ou null. A-1: uma saída do orçamento ao cliente (client_id) enviada, incerta ou enviando, com a hora do envio (ou da decisão) em p_dia de Brasília até p_agora = {dia: p_dia + 1, motivo: orcamento_hoje}. A-3: a confirmação (p_tipo confirmar) com o "Fechado" (orc_fechado) mais recente enviado até p_dia = {dia: o dia útil seguinte ao dele (agenda_somar_du(dia, 1)), motivo: orcamento_fechado}, se ainda não chegou. Sem retorno_saidas (a bancada da agenda), null. STABLE, invoker, sem grant: _agenda_cliente_enfileirar (remarca a mensagem) e _agenda_fila_do_cliente (recusa a linha) a chamam.';

-- ── 2. As iniciadas do retorno no dia (PEDIDO A-5 da F5) ───────────────────────────────────────────────────────────────────────────────
-- Nova, interna. Conta como o canal do retorno conta as iniciadas no teto dele (canal_pode_enviar, iniciadas_dia_max): classe aviso,
-- resumo_parceiro ou comercial, enviada, incerta ou enviando, pela hora da decisão, nos dias de Brasília [p_de, p_ate]. Sem a tabela, 0.
create or replace function public._agenda_cliente_retorno_no_periodo(p_de date, p_ate date)
 returns integer
 language plpgsql
 stable
 set search_path to 'public'
as $function$
begin
  if p_de is null or p_ate is null then
    return 0;
  end if;
  -- a bancada da agenda não tem as tabelas do retorno; em produção a tabela existe sempre
  if to_regclass('public.retorno_saidas') is null then
    return 0;
  end if;
  return (select count(*)::int
            from public.retorno_saidas s
           where s.classe in ('aviso', 'resumo_parceiro', 'comercial')
             and s.estado in ('enviada', 'incerta', 'enviando')
             and s.decidida_em >= (p_de::timestamp at time zone 'America/Sao_Paulo')
             and s.decidida_em < ((p_ate + 1)::timestamp at time zone 'America/Sao_Paulo'));
end;
$function$;

comment on function public._agenda_cliente_retorno_no_periodo(date, date) is
  'Agenda de Produção (pedido A-5 da F5 do retorno): quantas iniciadas do retorno (retorno_saidas de classe aviso, resumo_parceiro ou comercial, enviada, incerta ou enviando) foram decididas nos dias de Brasília [p_de, p_ate] — a mesma conta do teto das iniciadas no canal do retorno (canal_pode_enviar). Sem retorno_saidas (a bancada da agenda), 0. STABLE, invoker, sem grant: _agenda_cliente_no_periodo a soma no total do dia a todos (o teto_total).';

-- ── 3. O enfileirar (a 1ª trava): a espera pela saída do orçamento (PEDIDO A-1 e A-3) ─────────────────────────────────────────────────
-- O corpo de 20261028100800:1197 (md5 sem CR 39c92c146c43d1a24dcdb42afaea14b7, o de produção em 13/11) + só os 2 blocos "-- PEDIDO A-1 e A-3 (F5):".
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
  'Agenda de Produção (Fase 5, P2): a 1ª trava — a decisão do envio de uma mensagem ao cliente registrada (ou esperando o dono), na ordem: modo_cliente fora de ligado ou a mensagem em teste = fica (modo); o tipo fora de cliente_tipos_ligados = fica (tipo_em_teste); aprovação pedida/crítica = aguardando_dono; segurada/vencida, ou a validade passada = recusada; d19 a conversa viva (mensagem do cliente ou ao cliente nos últimos cliente_conversa_viva_min) = espera o próximo tique (enviar_em pelo _agenda_cliente_quando; passou da validade = vencida); opt_out; sem_conversa (d10); a revalidação (_agenda_cliente_revalidar); domingo/feriado/janela; o teto (teto_dia, teto_semana na semana ISO, teto_total; d13: o aviso de atraso ou de mudança no dia que não cabe vira a pergunta crítica cliente_aviso e espera o dono); o intervalo (outra agenda-cliente pendente ou saindo a menos de cliente_intervalo_min_s); sem_telefone (_agenda_cliente_telefone; wa_test_mode = o número de teste). Senão whatsapp_send_queue (source agenda-cliente, source_ref_id = a mensagem, o texto e a chave dela, priority 5, scheduled_for = enviar_em, max_attempts = as tentativas de +5 min que cabem na janela) e enfileirada; o 23514 da trava da fila vira recusada com o motivo do detail. Idempotente. Sem grant. CORREÇÃO FASE 5 (C1): o choque de intervalo remarca enviar_em (_agenda_cliente_quando; passou da validade = vencida) e devolve {estado registrada, motivo intervalo, enviar_em} em vez de recusar (item 14); o sem_conversa/sem_telefone da trava da fila vira o motivo (item 13). CORREÇÃO FASE 5 (C2, item 3a): a livre ou aprovada com o dia de enviar_em já passado e ainda válida ganha enviar_em = _agenda_cliente_quando(agora) e segue (depois do próximo tique: {estado registrada, motivo remarcada}); passou da validade = vencida. PEDIDO A-1 e A-3 (F5): depois do teto, a saída do orçamento a este cliente (_agenda_cliente_orcamento_espera): A-1, uma já foi no dia da mensagem = ela espera o dia seguinte; A-3, a confirmação antes do dia útil seguinte ao "Fechado" = espera esse dia útil. enviar_em = _agenda_cliente_quando(o início desse dia) e devolve {estado de antes, motivo orcamento_hoje | orcamento_fechado, enviar_em}: não recusa nem vence. Se a hora nova passa de valida_ate (a validade da mensagem não muda), vale como o teto do dia (teto_dia): o aviso de atraso ou de mudança no dia vira a pergunta crítica cliente_aviso (d13, contando a mensagem do orçamento na semana) e o resto fica recusado.';

-- ── 4. O gatilho da fila (a 2ª trava): a mesma regra (PEDIDO A-1 e A-3) ──────────────────────────────────────────────────────────────
-- O corpo de 20261028100200:1051 (md5 sem CR 6e462b7407bf84237607f2ab7b11df1b, o de produção em 13/11) + só o bloco "-- PEDIDO A-1 e A-3 (F5):". Os 2 gatilhos
-- (trg_agenda_fila_do_cliente e trg_agenda_fila_do_cliente_linha) não mudam: o create or replace troca só o corpo.
create or replace function public._agenda_fila_do_cliente()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  m       public.agenda_cliente_mensagens%rowtype;
  v_local timestamp;
  v_dia   date;
  v_seg   date;
  v_fora  text;
  v_teste boolean;
  v_num   text;
begin
  if tg_op = 'UPDATE' then
    if old.source is distinct from new.source or old.message is distinct from new.message
       or old.phone_normalized is distinct from new.phone_normalized or old.source_ref_id is distinct from new.source_ref_id
       or old.dedupe_key is distinct from new.dedupe_key then
      raise exception 'A linha da fila do cliente não muda de texto, telefone, origem nem chave.' using errcode = '42501';
    end if;
    -- a nova tentativa que o worker marca (+5 min) fora da janela da mensagem, com o modo ou o tipo fora de ligado, ou que
    -- a revalidação recusa, não sai: falha, a hora volta à de antes e a mensagem fica recusada com o motivo
    if new.status = 'pending' and new.scheduled_for is distinct from old.scheduled_for then
      select x.* into m from public.agenda_cliente_mensagens x where x.id = new.source_ref_id;
      v_fora := case
        when not found then 'janela'
        when cf.modo_cliente <> 'ligado' then 'modo'
        when not (m.tipo = any (cf.cliente_tipos_ligados)) then 'tipo_em_teste'
        else coalesce(public._agenda_cliente_fora_da_janela(m.enviar_em, new.scheduled_for),
                      public._agenda_cliente_revalidar(m.id, greatest(now(), new.scheduled_for))) end;
      if v_fora is not null then
        new.status := 'failed';
        new.failed_reason := 'agenda-cliente: a nova tentativa não sai (' || v_fora || ')';
        new.scheduled_for := old.scheduled_for;
        update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = v_fora
         where id = new.source_ref_id and estado = 'enfileirada';
      end if;
    end if;
    return new;
  end if;
  select x.* into m from public.agenda_cliente_mensagens x where x.id = new.source_ref_id;
  if not found or m.modo <> 'ligado' or cf.modo_cliente <> 'ligado' or not (m.tipo = any (cf.cliente_tipos_ligados)) then
    raise exception 'A fila do cliente só aceita a mensagem registrada pela agenda com modo_cliente ligado e o tipo ligado.'
      using errcode = '42501';
  end if;
  -- só a que o _agenda_cliente_enfileirar está decidindo agora (a recusada nunca entra; a enfileirada não entra de novo)
  if m.estado not in ('registrada', 'aguardando_dono') then
    raise exception 'A fila do cliente só aceita a mensagem que a agenda acabou de decidir mandar (esta está %).', m.estado
      using errcode = '42501';
  end if;
  if m.aprovacao not in ('livre', 'aprovada') then
    raise exception 'A fila do cliente só aceita a mensagem livre ou aprovada pelo dono (esta está %).', m.aprovacao
      using errcode = '42501';
  end if;
  if new.dedupe_key is distinct from m.dedupe_key then
    raise exception 'A fila do cliente só aceita a mensagem com a chave dela.' using errcode = '42501';
  end if;
  if new.message is distinct from m.texto then
    raise exception 'A fila do cliente só aceita o texto registrado (nunca mensagem livre).' using errcode = '42501';
  end if;
  -- o telefone: o do cliente da mensagem (nunca o do dono, da equipe nem de quem recebe diária) ou, com wa_test_mode, o de
  -- teste
  v_teste := coalesce((select x.value::text from public.app_settings x where x.key = 'wa_test_mode'), 'false') in ('true', '"true"');
  v_num := case when v_teste
                then nullif(regexp_replace(coalesce((select x.value::text from public.app_settings x where x.key = 'wa_test_number'), ''),
                                           '\D', '', 'g'), '')
                else public._agenda_cliente_telefone(m.client_id) end;
  if v_num is null or new.phone_normalized is distinct from v_num then
    raise exception 'A fila do cliente só aceita o telefone do cliente da mensagem.' using errcode = '42501';
  end if;
  v_local := new.scheduled_for at time zone 'America/Sao_Paulo';
  -- cada tentativa (+5 min) dentro da janela da mensagem, pela regra única; o motivo vai no detail (quem enfileira recusa
  -- a mensagem com ele)
  select t.f into v_fora
    from (select public._agenda_cliente_fora_da_janela(m.enviar_em, new.scheduled_for + make_interval(mins => 5 * k)) as f
            from generate_series(0, greatest(coalesce(new.max_attempts, 3) - 1, 0)) k) t
   where t.f is not null
   limit 1;
  if v_fora is not null then
    raise exception 'Mensagem ao cliente fora da janela (de segunda a sexta de % a %, sábado até %; nunca domingo nem feriado): %.',
      to_char(cf.cliente_janela_inicio, 'HH24:MI'), to_char(cf.cliente_janela_fim, 'HH24:MI'),
      to_char(cf.cliente_sabado_fim, 'HH24:MI'), to_char(v_local, 'DD/MM HH24:MI')
      using errcode = '23514', detail = v_fora;
  end if;
  v_dia := v_local::date;
  v_seg := date_trunc('week', v_dia)::date;
  v_fora := case
    when public._agenda_cliente_no_periodo(m.client_id, v_dia, v_dia, m.id) >= cf.cliente_dia_max then 'teto_dia'
    when public._agenda_cliente_no_periodo(m.client_id, v_seg, v_seg + 6, m.id) >= cf.cliente_semana_max then 'teto_semana'
    when public._agenda_cliente_no_periodo(null, v_dia, v_dia, m.id) >= cf.cliente_total_dia_max then 'teto_total' end;
  if v_fora is not null then
    raise exception 'Teto de mensagens ao cliente (% por dia e % por semana a cada cliente, % no dia a todos): não entra mais nenhuma.',
      cf.cliente_dia_max, cf.cliente_semana_max, cf.cliente_total_dia_max using errcode = '23514', detail = v_fora;
  end if;
  -- PEDIDO A-1 e A-3 (F5): a mesma regra do enfileirar na 2ª trava (_agenda_cliente_orcamento_espera no dia da linha): no dia em que uma
  -- saída do orçamento já foi a este cliente (ou a confirmação antes do dia útil seguinte ao "Fechado"), a linha não entra (o teto do dia).
  -- O enfileirar remarca antes de chegar aqui; isto só pega um caminho novo que não passe por ele.
  if public._agenda_cliente_orcamento_espera(m.client_id, m.tipo, v_dia, greatest(now(), new.scheduled_for)) is not null then
    raise exception 'O cliente já recebeu hoje a mensagem do orçamento (ou a confirmação espera o dia útil seguinte ao "Fechado"): não entra mais nenhuma hoje.'
      using errcode = '23514', detail = 'teto_dia';
  end if;
  -- PEDIDO A-1 e A-3 (F5): fim
  if exists (select 1 from public.whatsapp_send_queue q
              where q.source = 'agenda-cliente' and q.status in ('pending', 'sending') and q.id is distinct from new.id
                and q.source_ref_id is distinct from m.id
                and q.scheduled_for > new.scheduled_for - make_interval(secs => cf.cliente_intervalo_min_s)
                and q.scheduled_for < new.scheduled_for + make_interval(secs => cf.cliente_intervalo_min_s)) then
    raise exception 'Mensagem ao cliente perto demais de outra (no mínimo % s entre uma e outra).', cf.cliente_intervalo_min_s
      using errcode = '23514', detail = 'intervalo';
  end if;
  v_fora := public._agenda_cliente_revalidar(m.id, greatest(now(), new.scheduled_for));
  if v_fora is not null then
    raise exception 'A mensagem ao cliente não vale mais (%): não entra na fila.', v_fora using errcode = '23514', detail = v_fora;
  end if;
  return new;
end;
$function$;

comment on function public._agenda_fila_do_cliente() is
  'Agenda de Produção (Fase 5, P2): a 2ª trava — gatilho de whatsapp_send_queue só para source agenda-cliente. INSERT: recusa (42501) a linha sem a mensagem registrada/esperando o dono em ligado (modo_cliente ligado e o tipo em cliente_tipos_ligados), sem a aprovação livre ou aprovada, com chave ou texto diferentes dos dela, ou com telefone que não é o do cliente dela (_agenda_cliente_telefone; com wa_test_mode, o número de teste); recusa (23514, o motivo no detail) a linha com alguma tentativa fora da janela (janela, domingo, feriado), acima do teto (teto_dia, teto_semana, teto_total), a menos de cliente_intervalo_min_s de outra agenda-cliente pendente ou saindo (intervalo), ou que a revalidação recusa (o motivo dela). UPDATE: a linha não muda de texto, telefone, origem, ref nem chave (42501); a nova tentativa pendente fora da janela, com o modo ou o tipo fora de ligado, ou que a revalidação recusa vira failed, volta à hora de antes e a mensagem enfileirada fica recusada com o motivo. PEDIDO A-1 e A-3 (F5): a mesma regra do enfileirar (_agenda_cliente_orcamento_espera no dia da linha, até greatest(now(), scheduled_for)) recusa a linha com 23514, detail teto_dia; o enfileirar remarca antes de chegar aqui.';

-- ── 5. A conta do teto: o total do dia a todos soma as iniciadas do retorno (PEDIDO A-5) ─────────────────────────────────────────────
-- O corpo de 20261028100200:305 (md5 sem CR d99e071a323385c9b46f468b7a93eaff, o de produção em 13/11) + só o bloco "-- PEDIDO A-5 (F5):". O enfileirar, o gatilho
-- da fila e o botão (_pedir_confirmacao) contam o teto_total por ela: os três passam a contar igual sem mudar nenhum deles por isso.
create or replace function public._agenda_cliente_no_periodo(p_cliente uuid, p_de date, p_ate date, p_exceto uuid)
 returns integer
 language sql
 stable
 set search_path to 'public'
as $function$
  select count(*)::int
         -- PEDIDO A-5 (F5): no total do dia a todos (p_cliente null: o teto_total do enfileirar, do gatilho da fila e do botão), também as
         -- iniciadas do retorno que já saíram, contadas como o canal do retorno conta (_agenda_cliente_retorno_no_periodo)
         + case when p_cliente is null then public._agenda_cliente_retorno_no_periodo(p_de, p_ate) else 0 end
         -- PEDIDO A-5 (F5): fim
    from public.agenda_cliente_mensagens m
   where m.modo = 'ligado' and m.id is distinct from p_exceto
     and (p_cliente is null or m.client_id = p_cliente)
     and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')
     and (m.enviar_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate;
$function$;

comment on function public._agenda_cliente_no_periodo(uuid, date, date, uuid) is
  'Agenda de Produção (Fase 5, P2): o teto contado num lugar só — as mensagens ao cliente (ou a todos, com p_cliente null) em ligado que entraram na fila (enfileirada, enviada, respondida, sem_resposta), com o dia de envio de Brasília em [p_de, p_ate], sem p_exceto. PEDIDO A-5 (F5): com p_cliente null (o total do dia a todos: o teto_total do enfileirar, do gatilho da fila e do botão), soma as iniciadas do retorno no período (_agenda_cliente_retorno_no_periodo: aviso, resumo_parceiro, comercial já saídas), para o teto do número valer nos dois sentidos. Por cliente, como antes.';

-- ── 6. As portas ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- As 3 recriadas mantêm a porta de antes (só o dono executa: são internas, chamadas por definer); o create or replace já a mantém, aqui ela
-- é reafirmada. As 2 novas são internas: função nova nasce com EXECUTE para PUBLIC e (no Supabase) para anon e authenticated, então o revoke é
-- explícito, e o teste prova que nem anon, nem authenticated, nem service_role executam.
revoke all on function public._agenda_cliente_orcamento_espera(uuid, text, date, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public._agenda_cliente_retorno_no_periodo(date, date) from public, anon, authenticated, service_role;
revoke all on function public._agenda_cliente_enfileirar(uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public._agenda_fila_do_cliente() from public, anon, authenticated, service_role;
revoke all on function public._agenda_cliente_no_periodo(uuid, date, date, uuid) from public, anon, authenticated, service_role;

notify pgrst, 'reload schema';
