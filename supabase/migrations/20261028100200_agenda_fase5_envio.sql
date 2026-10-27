-- Agenda de Produção, Fase 5 ("Mensagens ao cliente"), pacote P2: o envio — a janela do cliente (segunda a sexta 08–19,
-- sábado até 13, nunca domingo nem feriado), a hora com o intervalo de 30 a 60 s entre uma e outra, o teto (1 por dia e 3
-- por semana a cada cliente; o total do dia), a origem agenda-cliente na fila com as três travas (o enfileirar, o gatilho
-- da fila e o worker), a revalidação na saída (também pelo worker, por RPC), o gatilho do envio que grava o que foi dito
-- ao cliente (prometido_*) e o D9 (o botão antigo de pedir a confirmação e o "sim" a ele sem exigir status = 'scheduled').
-- Spec: scratchpad agenda-pesquisa/spec-fase5.md (§3.1, §3.2, §5.2, §6.2, §6.3, d10–d13, d17, d19). Decisões do dono 23/10
-- (janela seg–sex 8–19 e sáb 8–13, nunca domingo; no máximo 1 por dia e 3 por semana por cliente; nos 3 primeiros dias de
-- cada tipo a mensagem passa pelo dono). Depende de 20261028100000 (as tabelas e os parâmetros) e 100100 (os textos, o
-- contexto, o telefone e o prometido).
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (21 funções novas, 2 recriadas, 3 gatilhos novos na fila; nenhuma tabela, nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f5p2/montar-migration.mjs: as partes escritas à mão
-- e os corpos de pedir_confirmacao_do_agendamento (20260930130000) e registrar_confirmacao_do_cliente (20261012101000, a
-- mais nova) copiados, com cada troca "-- FASE 5:" conferida (fora dos blocos, só as 3 linhas listadas no montador).
--
-- POR QUE: é mensagem a TERCEIRO, e o terceiro é o cliente: a lição de setembro (os técnicos receberam alerta à meia-noite)
-- vale inteira. Nada sai sem passar por quatro portões, na ordem: o modo e o tipo ligados; a aprovação (os primeiros dias de
-- cada tipo, ou a pergunta crítica); as regras do canal (opt-out, telefone, conversa, janela, feriado, teto, intervalo); e a
-- revalidação na saída. Cada portão grava o motivo da recusa; a mensagem nunca é apagada.
--
-- O QUE MUDA:
--   1. A janela (a regra única das três travas): _agenda_cliente_dia_de_janela, _agenda_cliente_fora_da_janela (domingo,
--      feriado, janela), _agenda_cliente_fim_da_janela (a "válida até" dos modelos) e _agenda_cliente_quando (a hora: o 1º
--      instante de janela, longe de outra agenda-cliente marcada pelo intervalo determinístico da mensagem; d12).
--   2. O cliente: _agenda_cliente_conversou (uma mensagem DELE em cliente_conversa_dias; d10), _agenda_cliente_sem_mensagem
--      (o opt-out: clients.opt_out_whatsapp, o cadastro inativo, whatsapp_blocked_numbers) e _agenda_cliente_no_periodo (o
--      teto contado num lugar só).
--   3. A revalidação: _agenda_cliente_revalidar (opt_out, status, data_mudou, material, passou_da_data, mesmo_tipo_24h,
--      desatualizada) e agenda_cliente_pode_sair (só service_role: o worker pergunta antes de mandar).
--   4. O registro: _agenda_cliente_registrar (o texto do banco, o proibido, o modo da linha, a chave, a hora, a aprovação —
--      crítica, pedida pelo dono, pedida nos primeiros dias do tipo, aprovada pelo botão ou livre — e as perguntas
--      cliente_aprovar e cliente_aviso), _agenda_cliente_tipo_liberado (d11) e os textos ao dono (§6.2, §6.3).
--   5. A 1ª trava, _agenda_cliente_enfileirar (a conversa viva d19, o teto que vira pergunta crítica d13), e a 2ª, o gatilho
--      trg_agenda_fila_do_cliente em whatsapp_send_queue SÓ para source agenda-cliente (INSERT e a nova tentativa). A 3ª é o
--      worker (_shared/agenda/janela-da-fila.ts e whatsapp-queue-worker/enviar.ts: a janela do cliente, 1 linha de cliente
--      por lote e o agenda_cliente_pode_sair).
--   6. O envio: o gatilho trg_agenda_cliente_enviada (AFTER UPDATE OF status, só agenda-cliente e agenda-confirmacao, quando
--      vira sent): a mensagem enviada, o prometido_* (a de agora e a do botão antigo), a ação que conta no fechamento.
--   7. O passo "fila", _agenda_cliente_fila (a rodada do P3 o chama SEMPRE, até com tudo desligado): a fila velha, a que a
--      revalidação recusa, o que é hora de mandar e a que venceu sem o dono.
--   8. D9: pedir_confirmacao_do_agendamento e registrar_confirmacao_do_cliente recriadas — com o plano ligado, vale o dia do
--      plano em qualquer status ativo (nunca aguardando peça ou o cliente); com modo_cliente ligado e a confirmação ligada, o
--      botão registra pela agenda; o "sim" fixa as alocações do dia (cliente_confirmou).
--
-- O QUE NÃO MUDA: a fila das outras origens (os gatilhos novos só olham source agenda-cliente e, o do envio, também
-- agenda-confirmacao; os de produção ficam iguais); o worker manda as outras origens como sempre (provado em
-- whatsapp-queue-worker/enviar_test.ts); com modo_cliente desligado (a linha nasce assim) nada é registrado e nada sai, e o
-- botão antigo faz o que fazia (com o plano desligado, igual a 30/09).
--
-- DINHEIRO: nada aqui cria, muda ou liga pagamento, cobrança ou orçamento. A mensagem ao cliente nunca leva valor,
-- pagamento, desconto, número de OS ou link (_agenda_cliente_texto_proibido: o registro recusa com 22023).
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase5_envio.sql e anotadas em notas-fase5.md):
--   · O "envio" do texto é o dia da hora calculada (_agenda_cliente_quando), não o que o passo passar: o "Amanhã" do M2/M4
--     é sempre contado do dia em que a mensagem sai. A revalidação recalcula com esse dia; se a hora mudou de dia (a conversa
--     viva), o texto de agora é outro e a mensagem fica desatualizada.
--   · base.dia_alvo é o dia que o TEXTO diz (p_dados.dia, senão o próximo dia do plano); sem plano no registro (o botão com
--     modo_proposta desligado), a comparação do data_mudou é com o dia agendado da OS (base.referencia = agendada).
--   · Nos tipos de fim (o andamento e o atraso da execução), o data_mudou compara o último dia do plano com base.fim.
--   · O aviso de atraso com a OS concluída é recusado por status (a spec não listava).
--   · Sem conversa E sem telefone válido (o Lenine, sem número; o dono cadastrado como cliente), o motivo é sem_telefone (a
--     spec §8.2 espera assim): ninguém "conversa" sem número.
--   · O texto ao dono do aviso que não cabe diz "1 mensagem"/"N mensagens"; o dito e a faixa na forma curta do dono
--     ("qui 05/11 → qui 12 e sex 13/11").
--   · valida_ate nula = o fim da janela do dia do envio; a que já nasce depois da validade fica recusada/vencida.
--   · d19 (conversa viva) mora no enfileirar: a mensagem ganha a hora do próximo tique; valida_ate não muda (o gatilho do
--     P1 não deixa), então a que passaria da validade fica recusada/vencida em vez de ir à manhã seguinte.
--   · d13: o aviso (pode_atrasar, mudanca_no_dia) que bate no teto não é recusado — vira a pergunta crítica cliente_aviso
--     (motivo teto) e a mensagem espera o dono (aprovacao critica); com a opção 2 e o teto ainda cheio, aí é recusada.
--   · O gatilho da 2ª trava, ao falhar a nova tentativa, também recusa a mensagem enfileirada (com o motivo): sem isso ela
--     ficaria "enfileirada" para sempre.
--   · O botão antigo pela agenda só com 'confirmar' em cliente_tipos_ligados (senão a mensagem seria só em teste e o dono
--     acharia que pediu); o pedido de confirmação da OS (client_confirmation_requested_at) conta de quando a mensagem SAI
--     (o gatilho do envio), não do clique.
--   · O prometido do botão antigo (agenda-confirmacao) é o do dia confirmado pelo plano (_agenda_cliente_dia_a_confirmar),
--     senão o scheduled_start_at (o espelho fica no 1º dia, que já passou numa OS em andamento).
--   · A validade do pedido de confirmação (as 72 h de 30/09) passa a ser agenda_config.cliente_resposta_validade (o mesmo
--     DEFAULT de 72 h): o literal sairia na varredura de parâmetros.
--   · O "sim" do botão antigo fixa as alocações sem *desfaz* (a transição fixada → publicada não existe na porta; o P4 é
--     quem fixa com *desfaz* pela resposta da agenda).
--   · As funções novas ganharam parâmetros com padrão (p_agora no enfileirar e no pode_sair, p_exceto no quando, p_autor
--     no registrar): as chamadas da spec continuam valendo.
--
-- ORDEM DE LIGAR: depois de 20261028100000 e 100100; ANTES do deploy do whatsapp-queue-worker (a 3ª trava chama
-- agenda_cliente_pode_sair; sem a função, a linha agenda-cliente não sai — o lado seguro) e da rodada do P3. Com
-- modo_cliente desligado, nada é gravado e nada sai.
--
-- PROVA: supabase/tests/agenda_fase5_envio.sql (E0–E11). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; depois de 20261028100000 e 100100):
--   npx supabase db query --linked -f supabase/migrations/20261028100200_agenda_fase5_envio.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261028100200', 'agenda_fase5_envio');"
--
-- IDEMPOTENTE: create or replace function, drop trigger if exists + create, revoke/grant e comment.

-- ── 1. A janela do cliente (a regra única das três travas) ──────────────────────────────────────────────

-- Dia em que a mensagem ao cliente pode sair: segunda a sábado sem feriado (o sábado tem fim próprio); domingo nunca.
-- Não olha recesso: o recesso é da HBR (a véspera de uma OS dentro dele não existe).
create or replace function public._agenda_cliente_dia_de_janela(p_dia date)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select p_dia is not null and extract(isodow from p_dia) <> 7 and public.agenda_feriado(p_dia) is null;
$function$;

comment on function public._agenda_cliente_dia_de_janela(date) is
  'Agenda de Produção (Fase 5, P2): o dia pode ter mensagem ao cliente? Segunda a sábado sem feriado (agenda_feriado); domingo nunca. Não olha o recesso da HBR.';

-- A janela de UMA tentativa de envio ao cliente — a regra única: o enfileirar (a 1ª tentativa e quantas cabem), o gatilho
-- da fila (o INSERT e a nova tentativa), o passo "fila", o pode_sair do worker e a saúde leem daqui; o worker confere o
-- mesmo na hora (_shared/agenda/janela-da-fila.ts). null = pode sair; senão o motivo: domingo; feriado; janela (outro dia
-- que não o da hora marcada, ou fora de [cliente_janela_inicio, cliente_janela_fim) de segunda a sexta, ou de
-- [cliente_janela_inicio, cliente_sabado_fim) no sábado, em Brasília).
create or replace function public._agenda_cliente_fora_da_janela(p_marcada timestamptz, p_quando timestamptz)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf    public.agenda_config := public._agenda_cfg();
  v_q   timestamp := p_quando at time zone 'America/Sao_Paulo';
  v_fim time;
begin
  if p_quando is null or p_marcada is null then
    return 'janela';
  end if;
  if extract(isodow from v_q) = 7 then
    return 'domingo';
  end if;
  if public.agenda_feriado(v_q::date) is not null then
    return 'feriado';
  end if;
  if v_q::date <> (p_marcada at time zone 'America/Sao_Paulo')::date then
    return 'janela';
  end if;
  v_fim := case when extract(isodow from v_q) = 6 then cf.cliente_sabado_fim else cf.cliente_janela_fim end;
  if v_q::time >= cf.cliente_janela_inicio and v_q::time < v_fim then
    return null;
  end if;
  return 'janela';
end;
$function$;

comment on function public._agenda_cliente_fora_da_janela(timestamptz, timestamptz) is
  'Agenda de Produção (Fase 5, P2): a janela de uma tentativa de envio ao cliente, a regra única do banco (o worker tem a mesma em _shared/agenda/janela-da-fila.ts) — null = pode sair; ''domingo''; ''feriado'' (agenda_feriado); ''janela'' (outro dia que não o da hora marcada, em Brasília, ou fora de [cliente_janela_inicio, cliente_janela_fim) de segunda a sexta e de [cliente_janela_inicio, cliente_sabado_fim) no sábado).';

-- O fim da janela do n-ésimo dia de janela a partir de p_dia (0 = o próprio p_dia, se é dia de janela; senão o próximo):
-- a "válida até" dos modelos (§6.1: o fim da janela do dia do envio = 0; do dia seguinte = 1; do 2º dia de janela = 1; do
-- 3º = 2). Lança 54000 sem dia de janela em 31 dias.
create or replace function public._agenda_cliente_fim_da_janela(p_dia date, p_dias_de_janela integer default 0)
 returns timestamptz
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf  public.agenda_config := public._agenda_cfg();
  v_d date := p_dia;
  v_n int := 0;
  v_i int := 0;
begin
  if p_dia is null then
    return null;
  end if;
  loop
    if public._agenda_cliente_dia_de_janela(v_d) then
      exit when v_n >= greatest(coalesce(p_dias_de_janela, 0), 0);
      v_n := v_n + 1;
    end if;
    v_d := v_d + 1;
    v_i := v_i + 1;
    if v_i > 31 then
      raise exception '_agenda_cliente_fim_da_janela: nenhum dia de janela em 31 dias a partir de %', p_dia using errcode = '54000';
    end if;
  end loop;
  return (v_d + case when extract(isodow from v_d) = 6 then cf.cliente_sabado_fim else cf.cliente_janela_fim end)
         at time zone 'America/Sao_Paulo';
end;
$function$;

comment on function public._agenda_cliente_fim_da_janela(date, integer) is
  'Agenda de Produção (Fase 5, P2): o fim da janela (cliente_janela_fim; no sábado cliente_sabado_fim) do n-ésimo dia de janela a partir de p_dia — 0 = o próprio dia (se não é dia de janela, o próximo); 1 = o dia de janela seguinte. A "válida até" dos modelos (spec §6.1). Lança 54000 sem dia de janela em 31 dias.';

-- A hora em que a mensagem sai: o 1º instante >= greatest(p_alvo, p_agora) dentro da janela de um dia de janela; depois,
-- longe de toda outra agenda-cliente marcada (a fila pendente ou saindo; a mensagem registrada ou esperando o dono, em
-- ligado), com o intervalo desta mensagem: cliente_intervalo_min_s + (p_msg_hash mod (max − min + 1)) segundos depois da
-- outra (d12: determinístico, de 30 a 60 s com o DEFAULT). Se isso passa do fim da janela, vai ao próximo dia de janela.
-- p_exceto = a própria mensagem (quando ela é remarcada). Lança 54000 sem dia de janela em 31 dias.
create or replace function public._agenda_cliente_quando(p_msg_hash integer, p_alvo timestamptz, p_agora timestamptz,
                                                         p_exceto uuid default null)
 returns timestamptz
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_faixa int := cf.cliente_intervalo_max_s - cf.cliente_intervalo_min_s + 1;
  v_passo int := cf.cliente_intervalo_min_s + ((coalesce(p_msg_hash, 0) % v_faixa) + v_faixa) % v_faixa;
  v_perto interval := make_interval(secs => cf.cliente_intervalo_min_s);
  v_t     timestamptz := greatest(p_alvo, p_agora);
  v_ini   date;
  v_l     timestamp;
  v_d     date;
  v_fim   time;
  v_outra timestamptz;
begin
  if v_t is null then
    return null;
  end if;
  v_ini := (v_t at time zone 'America/Sao_Paulo')::date;
  loop
    v_l := v_t at time zone 'America/Sao_Paulo';
    v_d := v_l::date;
    if v_d > v_ini + 31 then
      raise exception '_agenda_cliente_quando: nenhum dia de janela em 31 dias a partir de %', v_ini using errcode = '54000';
    end if;
    v_fim := case when extract(isodow from v_d) = 6 then cf.cliente_sabado_fim else cf.cliente_janela_fim end;
    -- fora de um dia de janela, ou depois do fim: o início da janela do próximo dia de janela
    if not public._agenda_cliente_dia_de_janela(v_d) or v_l::time >= v_fim then
      v_d := v_d + 1;
      while not public._agenda_cliente_dia_de_janela(v_d) loop
        v_d := v_d + 1;
        if v_d > v_ini + 31 then
          raise exception '_agenda_cliente_quando: nenhum dia de janela em 31 dias a partir de %', v_ini using errcode = '54000';
        end if;
      end loop;
      v_t := (v_d + cf.cliente_janela_inicio) at time zone 'America/Sao_Paulo';
      continue;
    end if;
    if v_l::time < cf.cliente_janela_inicio then
      v_t := (v_d + cf.cliente_janela_inicio) at time zone 'America/Sao_Paulo';
    end if;
    -- o intervalo: outra agenda-cliente marcada a menos de cliente_intervalo_min_s (a trava da fila recusa isso) empurra
    -- esta para depois da mais tarde delas, com o passo desta mensagem
    select max(s.em) into v_outra
      from (select q.scheduled_for as em from public.whatsapp_send_queue q
             where q.source = 'agenda-cliente' and q.status in ('pending', 'sending')
               and q.source_ref_id is distinct from p_exceto
            union all
            select m.enviar_em from public.agenda_cliente_mensagens m
             where m.modo = 'ligado' and m.estado in ('registrada', 'aguardando_dono') and m.id is distinct from p_exceto) s
     where s.em > v_t - v_perto and s.em < v_t + v_perto;
    exit when v_outra is null;
    v_t := v_outra + make_interval(secs => v_passo);
  end loop;
  return v_t;
end;
$function$;

comment on function public._agenda_cliente_quando(integer, timestamptz, timestamptz, uuid) is
  'Agenda de Produção (Fase 5, P2): a hora de envio de uma mensagem ao cliente — o 1º instante >= greatest(p_alvo, p_agora) dentro da janela (cliente_janela_inicio até cliente_janela_fim; sábado até cliente_sabado_fim) de um dia de janela (_agenda_cliente_dia_de_janela: sem domingo nem feriado); se outra agenda-cliente está marcada a menos de cliente_intervalo_min_s (a fila pending/sending; a mensagem registrada ou esperando o dono em ligado; menos p_exceto), vai para depois da mais tarde delas + cliente_intervalo_min_s + (p_msg_hash mod (max − min + 1)) segundos (d12, determinístico); o que passa do fim da janela vai ao próximo dia de janela. Lança 54000 sem dia de janela em 31 dias.';

-- ── 2. O cliente da mensagem: a conversa, o opt-out e o teto ────────────────────────────────────────────

-- O cliente conversou com a HBR? Uma mensagem DELE (recebida, o WhatsApp ou o telefone pelos 8 últimos dígitos) nos
-- cliente_conversa_dias antes de p_ate. 0 = sem exigência (d10). O que a HBR (ou a agenda) mandou não conta.
create or replace function public._agenda_cliente_conversou(p_cliente uuid, p_ate timestamptz)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select (public._agenda_cfg()).cliente_conversa_dias = 0
      or exists (select 1
                   from public.clients c
                   join public.whatsapp_messages w
                     on public._agenda_chave_telefone(w.phone_normalized)
                        in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone))
                  where c.id = p_cliente and w.direction = 'inbound'
                    and w.occurred_at <= p_ate
                    and w.occurred_at > p_ate - make_interval(days => (public._agenda_cfg()).cliente_conversa_dias));
$function$;

comment on function public._agenda_cliente_conversou(uuid, timestamptz) is
  'Agenda de Produção (Fase 5, P2): o cliente mandou alguma mensagem (recebida, o WhatsApp ou o telefone do cadastro pelos 8 últimos dígitos) nos agenda_config.cliente_conversa_dias antes de p_ate? 0 dias = sempre true (d10). O que a HBR ou a agenda mandou não conta.';

-- O cliente não quer (ou não pode) receber: clients.opt_out_whatsapp, o cadastro inativo, ou o número em
-- whatsapp_blocked_numbers (o WhatsApp ou o telefone, pelos 8 últimos dígitos).
create or replace function public._agenda_cliente_sem_mensagem(p_cliente uuid)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce((select coalesce(c.opt_out_whatsapp, false) or not coalesce(c.active, true)
                      or exists (select 1 from public.whatsapp_blocked_numbers b
                                  where public._agenda_chave_telefone(b.phone_normalized)
                                        in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone)))
                     from public.clients c where c.id = p_cliente), true);
$function$;

comment on function public._agenda_cliente_sem_mensagem(uuid) is
  'Agenda de Produção (Fase 5, P2): o opt-out do cliente — clients.opt_out_whatsapp, o cadastro inativo ou o número (WhatsApp ou telefone, 8 últimos dígitos) em whatsapp_blocked_numbers. Cliente que não existe = true.';

-- Quantas mensagens ao cliente (ou a todos: p_cliente null) em ligado ENTRARAM na fila (enfileirada, enviada, respondida,
-- sem_resposta) com o dia de envio (Brasília) em [p_de, p_ate], sem p_exceto: a contagem única do teto (o enfileirar e o
-- gatilho da fila contam igual). A recusada (nunca saiu) e a em teste não contam.
create or replace function public._agenda_cliente_no_periodo(p_cliente uuid, p_de date, p_ate date, p_exceto uuid)
 returns integer
 language sql
 stable
 set search_path to 'public'
as $function$
  select count(*)::int
    from public.agenda_cliente_mensagens m
   where m.modo = 'ligado' and m.id is distinct from p_exceto
     and (p_cliente is null or m.client_id = p_cliente)
     and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')
     and (m.enviar_em at time zone 'America/Sao_Paulo')::date between p_de and p_ate;
$function$;

comment on function public._agenda_cliente_no_periodo(uuid, date, date, uuid) is
  'Agenda de Produção (Fase 5, P2): o teto contado num lugar só — as mensagens ao cliente (ou a todos, com p_cliente null) em ligado que entraram na fila (enfileirada, enviada, respondida, sem_resposta), com o dia de envio de Brasília em [p_de, p_ate], sem p_exceto.';

-- ── 3. O dia que o botão antigo confirma (D9) ───────────────────────────────────────────────────────────

-- O início do dia que a confirmação do cliente vale: com o plano ligado (modo_proposta), o 1º meio-dia vigente do
-- próximo dia do plano, da OS aberta, aprovada, agendada ou em andamento; senão (como antes) o scheduled_start_at da OS
-- agendada. null quando não há, ou quando já começou há mais de 2 horas (a regra de 30/09).
create or replace function public._agenda_cliente_dia_a_confirmar(p_os uuid, p_agora timestamptz)
 returns timestamptz
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  so    record;
  v_dia date;
  v_ini timestamptz;
begin
  select o.status, o.scheduled_start_at into so from public.service_orders o where o.id = p_os;
  if not found then
    return null;
  end if;
  if (public._agenda_cfg()).modo_proposta = 'ligado' then
    if so.status not in ('open', 'approved', 'scheduled', 'in_progress') then
      return null;
    end if;
    v_dia := (public._agenda_plano_da_os(p_os, (p_agora at time zone 'America/Sao_Paulo')::date) ->> 'proximo_dia')::date;
    select min(lower(a.periodo)) into v_ini
      from public.agenda_alocacoes a
     where a.service_order_id = p_os and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva';
  elsif so.status = 'scheduled' then
    v_ini := so.scheduled_start_at;
  end if;
  if v_ini is null or v_ini <= p_agora - interval '2 hours' then
    return null;
  end if;
  return v_ini;
end;
$function$;

comment on function public._agenda_cliente_dia_a_confirmar(uuid, timestamptz) is
  'Agenda de Produção (Fase 5, P2, D9): o início do dia que a confirmação do cliente vale — com modo_proposta ligado, o 1º meio-dia vigente (sem reserva) do próximo dia do plano (_agenda_plano_da_os), para a OS em open, approved, scheduled ou in_progress (nunca aguardando peça/cliente); fora de ligado, como antes, o scheduled_start_at da OS agendada. null sem dia, ou quando ele começou há mais de 2 horas.';

-- ── 4. Os textos ao dono (a pergunta e o que mudou sozinho) ─────────────────────────────────────────────

-- O tipo como o dono lê: "confirmação", "véspera", "aviso de atraso"…
create or replace function public._agenda_cliente_tipo_texto(p_tipo text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_tipo
    when 'confirmar' then 'confirmação'
    when 'vespera' then 'véspera'
    when 'acesso' then 'véspera, com a pergunta do acesso'
    when 'material_chegou' then 'o material chegou'
    when 'andamento' then 'andamento'
    when 'pode_atrasar' then 'aviso de atraso'
    when 'nova_data' then 'nova data'
    when 'pronto' then 'ficou pronto'
    when 'pronto_lembrete' then 'lembrete da entrega'
    when 'pos_servico' then 'pós-serviço'
    when 'mudanca_no_dia' then 'mudança no dia'
  end;
$function$;

comment on function public._agenda_cliente_tipo_texto(text) is
  'Agenda de Produção (Fase 5, P2): o tipo da mensagem ao cliente como o dono lê ("confirmação", "véspera", "aviso de atraso", "ficou pronto"…).';

-- Quando sai, como o dono lê: "agora", "hoje às 10:00", "amanhã às 09:00", "sáb 31/10 às 09:00".
create or replace function public._agenda_cliente_quando_texto(p_quando timestamptz, p_agora timestamptz)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_quando is null then null
    when p_quando <= p_agora then 'agora'
    when (p_quando at time zone 'America/Sao_Paulo')::date = (p_agora at time zone 'America/Sao_Paulo')::date
      then 'hoje às ' || to_char(p_quando at time zone 'America/Sao_Paulo', 'HH24:MI')
    when (p_quando at time zone 'America/Sao_Paulo')::date = (p_agora at time zone 'America/Sao_Paulo')::date + 1
      then 'amanhã às ' || to_char(p_quando at time zone 'America/Sao_Paulo', 'HH24:MI')
    else public._dia_curto((p_quando at time zone 'America/Sao_Paulo')::date) || ' às '
         || to_char(p_quando at time zone 'America/Sao_Paulo', 'HH24:MI') end;
$function$;

comment on function public._agenda_cliente_quando_texto(timestamptz, timestamptz) is
  'Agenda de Produção (Fase 5, P2): quando a mensagem sai, como o dono lê — "agora", "hoje às 10:00", "amanhã às 09:00", "sáb 31/10 às 09:00" (Brasília).';

-- O que a mensagem diz, como o dono lê (a ação do envio e a da sombra): "a confirmação de ter 03/11", "o aviso de que pode
-- atrasar", "que o serviço ficou pronto"…
create or replace function public._agenda_cliente_o_que(p_tipo text, p_dia date)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case p_tipo
    when 'confirmar' then 'a confirmação' || coalesce(' de ' || public._dia_curto(p_dia), '')
    when 'vespera' then 'o aviso da véspera' || coalesce(' de ' || public._dia_curto(p_dia), '')
    when 'acesso' then 'a véspera com a pergunta do acesso' || coalesce(' (' || public._dia_curto(p_dia) || ')', '')
    when 'material_chegou' then 'que o material chegou' || coalesce(' (começo ' || public._dia_curto(p_dia) || ')', '')
    when 'andamento' then 'o andamento do serviço'
    when 'pode_atrasar' then 'o aviso de que pode atrasar'
    when 'nova_data' then 'a nova data' || coalesce(': ' || public._dia_curto(p_dia), '')
    when 'pronto' then 'que o serviço ficou pronto'
    when 'pronto_lembrete' then 'o lembrete para combinar a entrega'
    when 'pos_servico' then 'a mensagem de pós-serviço'
    when 'mudanca_no_dia' then 'a mudança do dia' || coalesce(' (novo dia: ' || public._dia_curto(p_dia) || ')', '')
  end;
$function$;

comment on function public._agenda_cliente_o_que(text, date) is
  'Agenda de Produção (Fase 5, P2): o que a mensagem ao cliente diz, como o dono lê na linha do que mudou sozinho ("Mandei ao Nelson a confirmação de qui 05/11.").';

-- O texto da pergunta crítica cliente_aviso (spec §6.2) — p_motivo: segundo_atraso, atraso_longo, passou, teto. O que o
-- cliente ouviu (dito_de/dito_ate, dia_dito, senão o prometido) e a faixa nova (faixa_de/faixa_ate, senão o dia) vêm de
-- p_dados; atraso_dias (atraso longo) e, no teto, as mensagens da semana.
create or replace function public._agenda_cliente_texto_do_aviso(p_motivo text, p_tipo text, p_os uuid, p_dados jsonb,
                                                                 p_hoje date)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  x       jsonb := public._agenda_cliente_contexto(p_os, p_hoje);
  d       jsonb := coalesce(p_dados, '{}'::jsonb);
  v_nome  text := coalesce(x ->> 'nome', 'cliente');
  v_serv  text := x ->> 'servico';
  v_de    date;
  v_ate   date;
  v_fde   date;
  v_fate  date;
  v_dito  text;
  v_faixa text;
  v_opc   constant text := ' 1) Você liga e eu não mando nada (recomendo); 2) Eu mando o aviso escrito; 3) Não aviso agora.';
begin
  if d ? 'dito_de' or d ? 'dito_ate' then
    v_de := (d ->> 'dito_de')::date; v_ate := (d ->> 'dito_ate')::date;
  elsif d ? 'dia_dito' then
    v_de := (d ->> 'dia_dito')::date; v_ate := v_de;
  else
    v_de := (x #>> '{prometido,de}')::date; v_ate := (x #>> '{prometido,ate}')::date;
  end if;
  v_fde := coalesce((d ->> 'faixa_de')::date, (d ->> 'dia')::date, (x ->> 'dia')::date);
  v_fate := coalesce((d ->> 'faixa_ate')::date, v_fde);
  v_dito := case when coalesce(v_de, v_ate) is null then 'a data dita'
                 else public._agenda_faixa_texto(coalesce(v_de, v_ate), 'manha', coalesce(v_ate, v_de), 'tarde') end;
  v_faixa := case when v_fde is null then 'sem data' else public._agenda_faixa_texto(v_fde, 'manha', v_fate, 'tarde') end;
  v_serv := upper(left(v_serv, 1)) || substr(v_serv, 2);
  return left(case p_motivo
    when 'segundo_atraso' then format('%s do %s vai atrasar de novo (%s → %s). É o 2º atraso: recomendo você ligar.%s',
                                      v_serv, v_nome, v_dito, v_faixa, v_opc)
    when 'atraso_longo' then format('%s do %s vai atrasar %s dias (%s → %s): recomendo você ligar.%s',
                                    v_serv, v_nome, coalesce(d ->> 'atraso_dias', '?'), v_dito, v_faixa, v_opc)
    when 'passou' then format('A data que o %s ouviu (%s) passou sem aviso. Recomendo você ligar hoje.%s', v_nome, v_dito, v_opc)
    else format('%s do %s não cabe: ele já recebeu %s esta semana. Recomendo você ligar.%s',
                case when p_tipo = 'mudanca_no_dia' then 'O aviso da mudança no dia' else 'O aviso de atraso' end, v_nome,
                case when (d ->> 'mensagens_na_semana') = '1' then '1 mensagem'
                     else coalesce(d ->> 'mensagens_na_semana', 'as') || ' mensagens' end, v_opc)
  end, 600);
end;
$function$;

comment on function public._agenda_cliente_texto_do_aviso(text, text, uuid, jsonb, date) is
  'Agenda de Produção (Fase 5, P2): o texto da pergunta crítica cliente_aviso (spec §6.2) — segundo_atraso ("… vai atrasar de novo (qui 05/11 → qui 12 a sex 13/11). É o 2º atraso: recomendo você ligar."), atraso_longo, passou e teto, sempre com as 3 opções (1 recomendada). O dito e a faixa na forma do dono (_agenda_faixa_texto).';

-- Abre a pergunta da mensagem e devolve o id (a pergunta nasce ANTES da mensagem: o CHECK cliente_critica_pergunta vale no
-- INSERT). cliente_aprovar:<mensagem> (a aprovação dos primeiros dias, ou a preparada pelo dono) ou
-- cliente_aviso:<os>:<dia> (crítica, 3 opções, recomendação 1). A mesma chave aberta = a mesma pergunta.
create or replace function public._agenda_cliente_perguntar(p_tipo_pergunta text, p_chave text, p_os uuid, p_dia date,
                                                            p_perda date, p_texto text, p_modo text, p_agora timestamptz,
                                                            p_expira timestamptz)
 returns uuid
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_id uuid;
begin
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, recomendacao,
                                       recomendacao_texto, modo, criada_em, expira_em)
  values (p_tipo_pergunta, left(p_chave, 200), p_os, array[p_os], p_dia, p_perda, left(public._agenda_corta(p_texto, 600), 600),
          case when p_tipo_pergunta = 'cliente_aviso' then jsonb_build_array(
                 jsonb_build_object('n', 1, 'texto', 'Você liga e eu não mando nada', 'efeito', jsonb_build_object('mensagem', 'segura')),
                 jsonb_build_object('n', 2, 'texto', 'Eu mando o aviso escrito agora', 'efeito', jsonb_build_object('mensagem', 'manda')),
                 jsonb_build_object('n', 3, 'texto', 'Não aviso agora', 'efeito', jsonb_build_object('mensagem', 'segura')))
               else '[]'::jsonb end,
          case when p_tipo_pergunta = 'cliente_aviso' then 1 end,
          case when p_tipo_pergunta = 'cliente_aviso' then 'Recomendo você ligar: um aviso escrito agora pesa mais do que uma ligação.' end,
          p_modo, p_agora, p_expira)
  on conflict (chave, modo) where estado = 'aberta' do nothing
  returning id into v_id;
  if v_id is null then
    select q.id into v_id from public.agenda_perguntas q where q.chave = left(p_chave, 200) and q.modo = p_modo and q.estado = 'aberta';
  end if;
  return v_id;
end;
$function$;

comment on function public._agenda_cliente_perguntar(text, text, uuid, date, date, text, text, timestamptz, timestamptz) is
  'Agenda de Produção (Fase 5, P2): abre a pergunta de uma mensagem ao cliente e devolve o id — cliente_aprovar (sem opções: *manda cliente* / *segura cliente*) ou cliente_aviso (crítica: 1 você liga e eu não mando nada, recomendada; 2 eu mando o aviso escrito; 3 não aviso agora). A mesma chave aberta devolve a pergunta que já estava. Interna (sem grant).';

-- ── 5. A revalidação (na saída, e também pelo worker) ───────────────────────────────────────────────────

-- Uma mensagem registrada ainda vale AGORA? null = sai; senão o motivo, nesta ordem (spec §5.2): opt_out, status,
-- data_mudou, material, passou_da_data, mesmo_tipo_24h, desatualizada. O texto é recalculado com os dados do registro e
-- com a 1ª mensagem e o dia do envio que ele guardou em base (a assinatura e o "Amanhã" não mudam de sentido de um dia
-- para o outro); se a hora de envio mudou de dia, o texto de agora é outro e a mensagem está desatualizada.
create or replace function public._agenda_cliente_revalidar(p_msg uuid, p_agora timestamptz default now())
 returns text
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  m      public.agenda_cliente_mensagens%rowtype;
  so     record;
  v_hoje date := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_plano jsonb;
  v_agora_dia date;
  v_nivel text;
  v_txt  text;
  v_dados jsonb;
begin
  select * into m from public.agenda_cliente_mensagens where id = p_msg;
  if not found then
    return 'desatualizada';
  end if;
  -- 1. o cliente pediu para não receber (ou o cadastro saiu)
  if public._agenda_cliente_sem_mensagem(m.client_id) then
    return 'opt_out';
  end if;
  -- 2. o status da OS
  select o.status, o.delivered_at, o.scheduled_start_at, o.scheduled_end_at into so
    from public.service_orders o where o.id = m.service_order_id;
  if not found or so.status in ('cancelled', 'draft')
     or (m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
         and so.status in ('awaiting_parts', 'awaiting_client', 'completed'))
     or (m.tipo = 'andamento' and so.status <> 'in_progress')
     or (m.tipo in ('pronto', 'pronto_lembrete') and (so.status <> 'completed' or so.delivered_at is not null))
     or (m.tipo = 'pos_servico' and so.status <> 'completed')
     or (m.tipo = 'pode_atrasar' and so.status = 'completed') then
    return 'status';
  end if;
  -- 3. a data: o dia de que a mensagem fala (o próximo dia do plano; sem plano no registro, o dia agendado da OS) e, nos
  -- tipos de fim (o andamento e o atraso da execução), o último dia
  v_plano := public._agenda_plano_da_os(m.service_order_id, v_hoje);
  if m.base ? 'dia_alvo'
     and (m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
          or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado')) then
    v_agora_dia := case when m.base ->> 'referencia' = 'agendada'
                        then (so.scheduled_start_at at time zone 'America/Sao_Paulo')::date
                        else (v_plano ->> 'proximo_dia')::date end;
    if v_agora_dia is distinct from (m.base ->> 'dia_alvo')::date then
      return 'data_mudou';
    end if;
  end if;
  if m.base ? 'fim' and m.base ->> 'referencia' = 'plano'
     and (m.tipo = 'andamento' or (m.tipo = 'pode_atrasar' and m.variante = 'execucao'))
     and (v_plano ->> 'ultimo_dia')::date is distinct from (m.base ->> 'fim')::date then
    return 'data_mudou';
  end if;
  -- 4. a data firme sem todo o material crítico na mão (d09): o pior nível dos críticos fora de A
  if m.prometido_tipo = 'firme' then
    v_nivel := public.os_prontidao(m.service_order_id, v_hoje) #>> '{material,confianca}';
    if v_nivel is not null and v_nivel <> 'A' then
      return 'material';
    end if;
  end if;
  -- 5. o aviso de atraso depois da data que o cliente ouviu (não sai: vira pergunta crítica na rodada)
  if m.tipo = 'pode_atrasar'
     and exists (select 1 from public.os_planejamento p
                  where p.service_order_id = m.service_order_id and p.prometido_ate < v_hoje) then
    return 'passou_da_data';
  end if;
  -- 6. o mesmo tipo a este cliente nas últimas cliente_mesmo_tipo_horas
  if exists (select 1 from public.agenda_cliente_mensagens x
              where x.client_id = m.client_id and x.tipo = m.tipo and x.id <> m.id and x.enviada_em is not null
                and x.enviada_em > p_agora - make_interval(hours => cf.cliente_mesmo_tipo_horas)) then
    return 'mesmo_tipo_24h';
  end if;
  -- 7. o texto de agora (os mesmos dados, a mesma 1ª mensagem, o dia do envio de agora) ≠ o registrado
  v_dados := coalesce(m.base -> 'dados', '{}'::jsonb)
             || jsonb_build_object('primeira', coalesce((m.base ->> 'primeira')::boolean, false),
                                   'envio', (m.enviar_em at time zone 'America/Sao_Paulo')::date);
  begin
    v_txt := public._agenda_cliente_texto(m.tipo, m.variante, m.service_order_id, v_dados, v_hoje);
  exception when others then
    return 'desatualizada';
  end;
  if v_txt is distinct from m.texto then
    return 'desatualizada';
  end if;
  return null;
end;
$function$;

comment on function public._agenda_cliente_revalidar(uuid, timestamptz) is
  'Agenda de Produção (Fase 5, P2): a mensagem ao cliente ainda vale em p_agora? null = sai; senão, na ordem: opt_out (_agenda_cliente_sem_mensagem); status (OS cancelada/rascunho; confirmar, véspera, acesso, material chegou, nova data e mudança no dia com a OS aguardando peça, aguardando o cliente ou concluída; andamento fora de in_progress; pronto e lembrete fora de completed ou já entregue; pós-serviço fora de completed; aviso de atraso com a OS concluída); data_mudou (o próximo dia do plano — sem plano no registro, o dia agendado da OS — ≠ base.dia_alvo; no andamento e no atraso da execução, o último dia ≠ base.fim); material (data firme com algum crítico fora de A, os_prontidao); passou_da_data (aviso de atraso com o prometido_ate antes de hoje); mesmo_tipo_24h (outra do mesmo tipo a ele enviada nas últimas cliente_mesmo_tipo_horas); desatualizada (_agenda_cliente_texto com os dados do registro, a 1ª mensagem de base e o dia do envio de agora ≠ o texto registrado, ou o modelo que não fecha mais). STABLE, definer, sem grant (o pode_sair do worker e as travas a chamam).';

-- A pergunta do worker antes de mandar uma linha agenda-cliente (a 3ª trava): {pode, motivo}. Recusa com o modo ou o tipo
-- fora de ligado, a validade vencida, a janela de agora e a revalidação. Erro na leitura = {pode: false, motivo: janela}.
create or replace function public.agenda_cliente_pode_sair(p_fila uuid, p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf  public.agenda_config;
  q   record;
  m   public.agenda_cliente_mensagens%rowtype;
  v   text;
begin
  cf := public._agenda_cfg();
  select x.source, x.source_ref_id, x.message into q from public.whatsapp_send_queue x where x.id = p_fila;
  if not found or q.source is distinct from 'agenda-cliente' then
    return jsonb_build_object('pode', false, 'motivo', 'janela', 'erro', 'a linha da fila não é de mensagem ao cliente');
  end if;
  select * into m from public.agenda_cliente_mensagens where id = q.source_ref_id;
  if not found then
    return jsonb_build_object('pode', false, 'motivo', 'janela', 'erro', 'a linha da fila não tem a mensagem registrada');
  end if;
  if cf.modo_cliente <> 'ligado' or m.modo <> 'ligado' then
    return jsonb_build_object('pode', false, 'motivo', 'modo');
  end if;
  if not (m.tipo = any (cf.cliente_tipos_ligados)) then
    return jsonb_build_object('pode', false, 'motivo', 'tipo_em_teste');
  end if;
  if m.valida_ate < p_agora then
    return jsonb_build_object('pode', false, 'motivo', 'vencida');
  end if;
  v := public._agenda_cliente_fora_da_janela(m.enviar_em, p_agora);
  if v is not null then
    return jsonb_build_object('pode', false, 'motivo', v);
  end if;
  v := public._agenda_cliente_revalidar(m.id, p_agora);
  if v is not null then
    return jsonb_build_object('pode', false, 'motivo', v);
  end if;
  if q.message is distinct from m.texto then
    return jsonb_build_object('pode', false, 'motivo', 'desatualizada');
  end if;
  return jsonb_build_object('pode', true, 'motivo', null);
exception when others then
  return jsonb_build_object('pode', false, 'motivo', 'janela', 'erro', sqlerrm);
end;
$function$;

comment on function public.agenda_cliente_pode_sair(uuid, timestamptz) is
  'Agenda de Produção (Fase 5, P2): a 3ª trava, chamada pelo whatsapp-queue-worker antes de mandar uma linha agenda-cliente — {pode, motivo}. Não sai: modo_cliente (ou a mensagem) fora de ligado (modo); o tipo fora de cliente_tipos_ligados (tipo_em_teste); valida_ate vencida (vencida); a janela de agora (_agenda_cliente_fora_da_janela: domingo, feriado, janela); a revalidação (_agenda_cliente_revalidar); o texto da fila ≠ o registrado (desatualizada). Linha que não é de cliente, sem a mensagem ou erro na leitura = {pode: false, motivo: janela}. Só service_role.';

-- O tipo já está liberado (sai sem o dono)? Somou cliente_aprovacao_dias dias DISTINTOS (Brasília) com mensagem daquele
-- tipo aprovada pelo dono, da rodada e em ligado (d11). A preparada pelo dono e o "segura" não contam. 0 = liberado.
create or replace function public._agenda_cliente_tipo_liberado(p_tipo text)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select (public._agenda_cfg()).cliente_aprovacao_dias = 0
      or (select count(distinct (m.aprovada_em at time zone 'America/Sao_Paulo')::date)
            from public.agenda_cliente_mensagens m
           where m.tipo = p_tipo and m.aprovacao = 'aprovada' and m.origem = 'rodada' and m.modo = 'ligado')
         >= (public._agenda_cfg()).cliente_aprovacao_dias;
$function$;

comment on function public._agenda_cliente_tipo_liberado(text) is
  'Agenda de Produção (Fase 5, P2): o tipo de mensagem ao cliente já sai sozinho? Somou agenda_config.cliente_aprovacao_dias dias distintos (Brasília, aprovada_em) com mensagem dele aprovada pelo dono (aprovacao aprovada, origem rodada, modo ligado) — d11. A preparada pelo dono e a segurada não contam. cliente_aprovacao_dias = 0: sempre liberado.';

-- ── 6. O registro e a 1ª trava (o enfileirar) ───────────────────────────────────────────────────────────

-- Uma mensagem registrada: decide se vai à fila (e marca enfileirada), espera (sombra, o dono, a conversa viva) ou é
-- recusada (o motivo). A ordem é a da spec (§5.2). A janela vale para TODA tentativa: o max_attempts é cortado para a última
-- (+5 min cada) não passar do fim; o gatilho da fila confere tudo de novo no INSERT.
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
  'Agenda de Produção (Fase 5, P2): a 1ª trava — a decisão do envio de uma mensagem ao cliente registrada (ou esperando o dono), na ordem: modo_cliente fora de ligado ou a mensagem em teste = fica (modo); o tipo fora de cliente_tipos_ligados = fica (tipo_em_teste); aprovação pedida/crítica = aguardando_dono; segurada/vencida, ou a validade passada = recusada; d19 a conversa viva (mensagem do cliente ou ao cliente nos últimos cliente_conversa_viva_min) = espera o próximo tique (enviar_em pelo _agenda_cliente_quando; passou da validade = vencida); opt_out; sem_conversa (d10); a revalidação (_agenda_cliente_revalidar); domingo/feriado/janela; o teto (teto_dia, teto_semana na semana ISO, teto_total; d13: o aviso de atraso ou de mudança no dia que não cabe vira a pergunta crítica cliente_aviso e espera o dono); o intervalo (outra agenda-cliente pendente ou saindo a menos de cliente_intervalo_min_s); sem_telefone (_agenda_cliente_telefone; wa_test_mode = o número de teste). Senão whatsapp_send_queue (source agenda-cliente, source_ref_id = a mensagem, o texto e a chave dela, priority 5, scheduled_for = enviar_em, max_attempts = as tentativas de +5 min que cabem na janela) e enfileirada; o 23514 da trava da fila vira recusada com o motivo do detail. Idempotente. Sem grant.';

-- Registra a mensagem-modelo no modo de agora (sombra: a chave termina em :sombra) e decide o envio. Desligado = nada.
create or replace function public._agenda_cliente_registrar(p_tipo text, p_variante text, p_os uuid, p_dia_alvo date,
                                                            p_dados jsonb, p_alvo timestamptz, p_valida_ate timestamptz,
                                                            p_origem text, p_critica text default null,
                                                            p_agora timestamptz default now(), p_autor uuid default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_tique constant interval := interval '15 minutes';   -- o tique do motor: o que sai até o próximo entra na fila agora
  v_hoje  date := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_dados jsonb := coalesce(p_dados, '{}'::jsonb) - 'primeira' - 'envio' - 'chave' - 'prometido_tipo';
  x       jsonb;
  v_cli   uuid;
  v_modo  text;
  v_chave text;
  v_id    uuid := gen_random_uuid();
  v_ja    uuid;
  v_enviar timestamptz;
  v_valida timestamptz;
  v_prim  boolean;
  v_var   text := nullif(btrim(coalesce(p_variante, '')), '');
  v_txt   text;
  v_proib text;
  v_prom  text;
  v_aprov text;
  v_estado text := 'registrada';
  v_recusa text;
  v_perg  uuid;
  v_base  jsonb;
  v_r     jsonb;
  v_acao  uuid;
  v_aut   uuid;
begin
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('criada', false, 'modo', 'desligado');
  end if;
  if p_origem is null or p_origem not in ('rodada', 'dono', 'botao') then
    raise exception 'A mensagem ao cliente vem da rodada, do dono ou do botão (veio %).', coalesce(p_origem, 'nada') using errcode = '22023';
  end if;
  if p_critica is not null and p_critica not in ('segundo_atraso', 'atraso_longo', 'passou', 'teto') then
    raise exception 'Motivo de aviso crítico desconhecido: %.', p_critica using errcode = '22023';
  end if;
  if p_alvo is null then
    raise exception 'A mensagem ao cliente veio sem a hora.' using errcode = '22023';
  end if;
  select so.client_id into v_cli from public.service_orders so where so.id = p_os;
  if v_cli is null then
    raise exception 'A mensagem ao cliente veio sem a OS (ou a OS sem cliente).' using errcode = '22023';
  end if;
  x := public._agenda_cliente_contexto(p_os, v_hoje);

  -- o modo da linha: ligado só com modo_cliente ligado E o tipo na lista das ondas; senão em teste (a chave com :sombra)
  v_modo := case when cf.modo_cliente = 'ligado' and p_tipo = any (cf.cliente_tipos_ligados) then 'ligado' else 'sombra' end;
  v_chave := format('agenda-cliente:%s:%s:%s', p_tipo, p_os,
                    coalesce(nullif(btrim(p_dados ->> 'chave'), ''), p_dia_alvo::text,
                             to_char(p_alvo at time zone 'America/Sao_Paulo', 'YYYY-MM-DD')))
             || case when v_modo = 'sombra' then ':sombra' else '' end;
  select m.id into v_ja from public.agenda_cliente_mensagens m where m.dedupe_key = v_chave;
  if v_ja is not null then
    return jsonb_build_object('criada', false, 'modo', v_modo, 'motivo', 'ja_existe', 'id', v_ja);
  end if;

  -- a hora (a janela, o feriado, o intervalo) e o texto contado do dia em que ele SAI (o "Amanhã"), com a assinatura só na
  -- 1ª mensagem; o registro guarda os dois (a revalidação recalcula com eles)
  v_enviar := public._agenda_cliente_quando(hashtext(v_chave), p_alvo, p_agora);
  v_prim := coalesce((p_dados ->> 'primeira')::boolean, (x ->> 'primeira')::boolean, false);
  if p_tipo = 'confirmar' and v_var is null then
    v_var := case when v_prim then 'primeira' else 'seguinte' end;
  end if;
  v_txt := public._agenda_cliente_texto(p_tipo, v_var, p_os,
             v_dados || jsonb_build_object('primeira', v_prim, 'envio', (v_enviar at time zone 'America/Sao_Paulo')::date), v_hoje);
  v_proib := public._agenda_cliente_texto_proibido(v_txt);
  if v_proib is not null then
    raise exception 'A mensagem ao cliente não pode levar % (o texto: "%").', v_proib, left(v_txt, 120) using errcode = '22023';
  end if;
  -- o que a mensagem DIZ de data (vira o prometido quando sai): firme nos modelos com dia; faixa no atraso da peça e da
  -- execução (condicional, se o passo disser); nada no andamento, no pronto e no pós-serviço
  v_prom := coalesce(nullif(btrim(p_dados ->> 'prometido_tipo'), ''),
                     case when p_tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
                               or (p_tipo = 'pode_atrasar' and v_var = 'remarcado') then 'firme'
                          when p_tipo = 'pode_atrasar' then 'faixa' end);
  if v_prom is not null and v_prom not in ('condicional', 'faixa', 'firme') then
    raise exception 'O que a mensagem diz de data é condicional, faixa ou firme (veio %).', v_prom using errcode = '22023';
  end if;
  v_valida := coalesce(p_valida_ate, public._agenda_cliente_fim_da_janela((v_enviar at time zone 'America/Sao_Paulo')::date, 0));
  v_base := jsonb_build_object(
    'status', x ->> 'status',
    'dia_alvo', coalesce((p_dados ->> 'dia')::date, (x ->> 'dia')::date, p_dia_alvo),
    'fim', coalesce((p_dados ->> 'fim')::date, (x ->> 'fim')::date),
    'nivel', x ->> 'nivel_material',
    'prometido_ate', x #>> '{prometido,ate}',
    'primeira', v_prim,
    'envio', (v_enviar at time zone 'America/Sao_Paulo')::date,
    'referencia', case when x -> 'plano' is null or jsonb_typeof(x -> 'plano') = 'null' then 'agendada' else 'plano' end,
    'dados', v_dados);

  -- a aprovação (em ligado): a crítica pergunta (cliente_aviso); a do dono e a do tipo ainda não liberado pedem *manda
  -- cliente* (cliente_aprovar); a do botão já foi aprovada pelo clique; o resto sai sozinho. Em teste, sempre livre.
  if v_enviar > v_valida then
    v_aprov := 'livre';
    v_estado := 'recusada';
    v_recusa := 'vencida';
  elsif v_modo = 'sombra' then
    v_aprov := 'livre';
  elsif p_critica is not null then
    v_aprov := 'critica';
    v_estado := 'aguardando_dono';
    v_perg := public._agenda_cliente_perguntar('cliente_aviso',
                format('cliente_aviso:%s:%s', p_os, coalesce(p_dia_alvo, (v_enviar at time zone 'America/Sao_Paulo')::date)),
                p_os, p_dia_alvo, (v_enviar at time zone 'America/Sao_Paulo')::date,
                public._agenda_cliente_texto_do_aviso(p_critica, p_tipo, p_os, p_dados, v_hoje), 'ligado', p_agora, v_valida);
  elsif p_origem = 'botao' then
    v_aprov := 'aprovada';
    v_aut := (select u.id from public.app_users u where u.id = p_autor);
  elsif p_origem = 'dono' or not public._agenda_cliente_tipo_liberado(p_tipo) then
    v_aprov := 'pedida';
    v_estado := 'aguardando_dono';
    v_perg := public._agenda_cliente_perguntar('cliente_aprovar', 'cliente_aprovar:' || v_id, p_os, p_dia_alvo,
                (v_enviar at time zone 'America/Sao_Paulo')::date,
                case when p_origem = 'dono'
                     then format('Pronto para o %s, sai %s: "%s". Para mandar: *manda cliente %s*.', x ->> 'nome',
                                 public._agenda_cliente_quando_texto(v_enviar, p_agora), v_txt, x ->> 'nome')
                     else format('Mensagem para o %s (%s), sai %s: "%s". *manda cliente %s* ou *segura cliente %s*.', x ->> 'nome',
                                 public._agenda_cliente_tipo_texto(p_tipo), public._agenda_cliente_quando_texto(v_enviar, p_agora),
                                 v_txt, x ->> 'nome', x ->> 'nome') end,
                'ligado', p_agora, v_valida);
  else
    v_aprov := 'livre';
  end if;

  insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, variante, origem, dia_alvo, faixa_de,
                                               faixa_ate, prometido_tipo, modo, texto, base, enviar_em, valida_ate, aprovacao,
                                               pergunta_id, aprovada_em, aprovada_por, estado, recusa_motivo, dedupe_key,
                                               criada_em)
  values (v_id, v_cli, p_os, p_tipo, v_var, p_origem, p_dia_alvo, (p_dados ->> 'faixa_de')::date,
          (p_dados ->> 'faixa_ate')::date, v_prom, v_modo, v_txt, v_base, v_enviar, v_valida, v_aprov, v_perg,
          case when v_aprov = 'aprovada' then p_agora end, v_aut, v_estado, v_recusa, v_chave, p_agora);

  -- em teste: o que a agenda teria mandado (a linha do que mudou sozinho, sem executar)
  if v_modo = 'sombra' then
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
    values (clock_timestamp(), v_hoje, false, 'vigia', 'cliente', p_os, array[p_os], '{}'::jsonb,
            jsonb_build_object('mensagem_id', v_id, 'tipo', p_tipo, 'enviar_em', v_enviar),
            left(format('Em teste: eu teria mandado ao %s %s (sairia %s).', x ->> 'nome',
                        public._agenda_cliente_o_que(p_tipo, coalesce((v_base ->> 'dia_alvo')::date, p_dia_alvo)),
                        public._agenda_cliente_quando_texto(v_enviar, p_agora)), 400))
    returning id into v_acao;
    update public.agenda_cliente_mensagens set acao_id = v_acao where id = v_id;
  end if;

  -- o que sai até o próximo tique entra na fila agora; o de depois fica registrado e o passo "fila" o enfileira na hora
  if v_modo = 'ligado' and v_estado = 'registrada' and v_aprov in ('livre', 'aprovada') and v_enviar <= p_agora + c_tique then
    v_r := public._agenda_cliente_enfileirar(v_id, p_agora);
  end if;
  return jsonb_build_object('criada', true, 'id', v_id, 'modo', v_modo, 'estado', v_estado, 'motivo', v_recusa,
                            'aprovacao', v_aprov, 'pergunta_id', v_perg, 'enviar_em', v_enviar, 'valida_ate', v_valida,
                            'texto', v_txt)
         || coalesce(v_r, '{}'::jsonb);
end;
$function$;

comment on function public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamptz, timestamptz, text, text, timestamptz, uuid) is
  'Agenda de Produção (Fase 5, P2): grava a mensagem-modelo ao cliente e decide o envio — desligado = nada; o texto é o do banco (_agenda_cliente_texto, contado do dia do envio, com a assinatura só na 1ª mensagem; o proibido = 22023); o modo da linha: ligado só com modo_cliente ligado E o tipo em cliente_tipos_ligados, senão sombra (chave com :sombra, a ação "Em teste: eu teria mandado…"); a chave agenda-cliente:<tipo>:<os>:<p_dados.chave | dia_alvo | o dia do alvo> (uma só: a 2ª devolve ja_existe); enviar_em pelo _agenda_cliente_quando; valida_ate = p_valida_ate, senão o fim da janela do dia do envio (passou dela = recusada/vencida); a aprovação em ligado: p_critica (segundo_atraso, atraso_longo, passou, teto) = critica + pergunta cliente_aviso; origem dono ou tipo ainda não liberado = pedida + pergunta cliente_aprovar; botão = aprovada (aprovada_por = p_autor); senão livre. base guarda {status, dia_alvo, fim, nivel, prometido_ate, primeira, envio, referencia, dados} para a revalidação. A livre/aprovada que sai até o próximo tique vai a _agenda_cliente_enfileirar. p_dados: os do modelo (dia, fim, janela, n, faixa_de/ate, peca_de/ate, dito_de/ate, dia_dito, quando, n_feitos), primeira, prometido_tipo, chave (o sufixo da chave no lugar do dia: o lembrete e o andamento semanal), atraso_dias (o aviso crítico). Sem grant.';

-- ── 7. A 2ª trava: o gatilho da fila, só para source agenda-cliente ─────────────────────────────────────

-- Nada com source agenda-cliente entra na fila sem a mensagem registrada em ligado (com o tipo ligado e a aprovação livre ou
-- aprovada), com outra chave, outro texto ou outro telefone, com alguma tentativa fora da janela, acima do teto, perto
-- demais de outra (o intervalo) ou que a revalidação recusa; e a linha que entrou não muda de texto, telefone, origem nem
-- chave. É o que garante que um caminho novo (ou um defeito) não manda ao cliente uma mensagem livre, à noite, de novo ou
-- ao telefone errado. A revalidação é feita na hora em que a linha sai (greatest(now(), scheduled_for)).
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
  'Agenda de Produção (Fase 5, P2): a 2ª trava — gatilho de whatsapp_send_queue só para source agenda-cliente. INSERT: recusa (42501) a linha sem a mensagem registrada/esperando o dono em ligado (modo_cliente ligado e o tipo em cliente_tipos_ligados), sem a aprovação livre ou aprovada, com chave ou texto diferentes dos dela, ou com telefone que não é o do cliente dela (_agenda_cliente_telefone; com wa_test_mode, o número de teste); recusa (23514, o motivo no detail) a linha com alguma tentativa fora da janela (janela, domingo, feriado), acima do teto (teto_dia, teto_semana, teto_total), a menos de cliente_intervalo_min_s de outra agenda-cliente pendente ou saindo (intervalo), ou que a revalidação recusa (o motivo dela). UPDATE: a linha não muda de texto, telefone, origem, ref nem chave (42501); a nova tentativa pendente fora da janela, com o modo ou o tipo fora de ligado, ou que a revalidação recusa vira failed, volta à hora de antes e a mensagem enfileirada fica recusada com o motivo.';

drop trigger if exists trg_agenda_fila_do_cliente on public.whatsapp_send_queue;
create trigger trg_agenda_fila_do_cliente before insert on public.whatsapp_send_queue
  for each row when (new.source = 'agenda-cliente') execute function public._agenda_fila_do_cliente();
drop trigger if exists trg_agenda_fila_do_cliente_linha on public.whatsapp_send_queue;
create trigger trg_agenda_fila_do_cliente_linha
  before update of scheduled_for, message, phone_normalized, source, source_ref_id, dedupe_key on public.whatsapp_send_queue
  for each row when (old.source = 'agenda-cliente' or new.source = 'agenda-cliente')
  execute function public._agenda_fila_do_cliente();

-- ── 8. O envio: a mensagem enviada, o que foi dito e o que conta no fechamento ──────────────────────────

-- O 1º gatilho de "depois" em whatsapp_send_queue: só as duas origens, só quando a linha vira 'sent'. Nunca lança (o erro
-- vai a app_error_logs, context agenda, action cliente:enviada): o worker não pode cair por causa dele.
create or replace function public._agenda_cliente_enviada()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  m      public.agenda_cliente_mensagens%rowtype;
  v_em   timestamptz := coalesce(new.sent_at, now());
  v_nome text;
  v_acao uuid;
  v_ini  timestamptz;
  v_ok   boolean := false;
  v_passo text;
begin
  -- Três passos, cada um no seu bloco: o que falha vai ao log e os outros seguem (a mensagem enviada nunca deixa de ficar
  -- enviada porque o prometido ou a ação falharam).
  if new.source = 'agenda-cliente' then
    begin
      v_passo := 'a mensagem';
      select * into m from public.agenda_cliente_mensagens where id = new.source_ref_id for update;
      if found and m.estado not in ('enviada', 'respondida', 'sem_resposta') then
        -- a verdade é o envio: até a que o passo da fila tinha recusado no meio tempo (a corrida com o worker) fica enviada
        update public.agenda_cliente_mensagens
           set estado = 'enviada', enviada_em = v_em, recusa_motivo = null, fila_id = coalesce(fila_id, new.id)
         where id = m.id;
        v_ok := true;
      end if;
    exception when others then
      perform public.log_app_error('db', format('mensagem ao cliente, o envio (%s): %s', v_passo, sqlerrm), 'agenda',
                                   'cliente:enviada', 'error',
                                   jsonb_build_object('fila', new.id, 'ref', new.source_ref_id, 'sqlstate', sqlstate));
    end;
    if v_ok and m.prometido_tipo is not null then
      begin
        v_passo := 'o prometido';
        perform public._agenda_cliente_prometer(m.id, v_em);
      exception when others then
        perform public.log_app_error('db', format('mensagem ao cliente, o envio (%s): %s', v_passo, sqlerrm), 'agenda',
                                     'cliente:enviada', 'error',
                                     jsonb_build_object('fila', new.id, 'ref', new.source_ref_id, 'sqlstate', sqlstate));
      end;
    end if;
    if v_ok then
      begin
        v_passo := 'a ação';
        select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) into v_nome
          from public.clients cl where cl.id = m.client_id;
        insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
        values (clock_timestamp(), (v_em at time zone 'America/Sao_Paulo')::date, true, 'vigia', 'cliente',
                m.service_order_id, array[m.service_order_id], '{}'::jsonb,
                jsonb_build_object('mensagem_id', m.id, 'tipo', m.tipo, 'fila_id', new.id, 'enviada_em', v_em),
                left(format('Mandei ao %s %s.', coalesce(v_nome, 'cliente'),
                            public._agenda_cliente_o_que(m.tipo, coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo))), 400))
        returning id into v_acao;
        update public.agenda_cliente_mensagens set acao_id = v_acao where id = m.id;
        -- o botão antigo pela agenda (D9): o pedido de confirmação conta de quando a mensagem SAIU
        if m.origem = 'botao' and m.tipo = 'confirmar' then
          update public.service_orders
             set client_confirmation_requested_at = v_em, client_confirmed_at = null, client_confirmed_for = null
           where id = m.service_order_id;
        end if;
      exception when others then
        perform public.log_app_error('db', format('mensagem ao cliente, o envio (%s): %s', v_passo, sqlerrm), 'agenda',
                                     'cliente:enviada', 'error',
                                     jsonb_build_object('fila', new.id, 'ref', new.source_ref_id, 'sqlstate', sqlstate));
      end;
    end if;
  elsif new.source_ref_id is not null then
    -- D9: o botão antigo (agenda-confirmacao) também é data dita ao cliente
    begin
      v_passo := 'o prometido do botão';
      v_ini := coalesce(public._agenda_cliente_dia_a_confirmar(new.source_ref_id, v_em),
                        (select so.scheduled_start_at from public.service_orders so where so.id = new.source_ref_id));
      if v_ini is not null then
        perform public._agenda_cliente_prometer_confirmacao(new.source_ref_id, v_ini, v_em);
      end if;
    exception when others then
      perform public.log_app_error('db', format('mensagem ao cliente, o envio (%s): %s', v_passo, sqlerrm), 'agenda',
                                   'cliente:enviada', 'error',
                                   jsonb_build_object('fila', new.id, 'ref', new.source_ref_id, 'sqlstate', sqlstate));
    end;
  end if;
  return null;
end;
$function$;

comment on function public._agenda_cliente_enviada() is
  'Agenda de Produção (Fase 5, P2): gatilho AFTER UPDATE OF status de whatsapp_send_queue, só para source agenda-cliente e agenda-confirmacao, quando a linha vira sent — agenda-cliente: a mensagem fica enviada (enviada_em = sent_at), a que diz data vira o prometido da OS (_agenda_cliente_prometer), e a ação tipo cliente (origem vigia, executada, sem desfazer: "Mandei ao Nelson a confirmação de qui 05/11.") conta no fechamento; a do botão (origem botao) marca o pedido de confirmação da OS; agenda-confirmacao (o botão antigo, D9): o prometido firme do dia confirmado (_agenda_cliente_dia_a_confirmar, senão scheduled_start_at). Nunca lança: o erro vai a app_error_logs (agenda / cliente:enviada).';

drop trigger if exists trg_agenda_cliente_enviada on public.whatsapp_send_queue;
create trigger trg_agenda_cliente_enviada after update of status on public.whatsapp_send_queue
  for each row when (new.source in ('agenda-cliente', 'agenda-confirmacao') and new.status = 'sent'
                     and old.status is distinct from 'sent')
  execute function public._agenda_cliente_enviada();

-- ── 9. O passo "fila" (roda SEMPRE, até com tudo desligado) ─────────────────────────────────────────────

-- A fila velha e o que é hora de mandar. (1) A linha pendente com o modo ou o tipo fora de ligado, ou que já devia ter saído
-- e agora está fora da janela dela, vira failed e a mensagem fica recusada (modo / tipo_em_teste / janela). (2) A pendente
-- que a revalidação recusa (a OS mudou antes de a mensagem sair) vira failed/recusada com o motivo. (3) A registrada (ou a
-- aprovada que esperava o dono) em ligado, livre ou aprovada, com a hora até o próximo tique, vai ao enfileirar. (4) A que
-- passou da validade sem sair vence: a esperando o dono fica com a aprovação vencida e a pergunta dela vencida.
create or replace function public._agenda_cliente_fila(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_tique constant interval := interval '15 minutes';   -- o tique do motor
  r       record;
  v_mot   text;
  v_res   jsonb;
  n_modo  int := 0;
  n_jan   int := 0;
  n_reval int := 0;
  n_fila  int := 0;
  n_espera int := 0;
  n_recus int := 0;
  n_venc  int := 0;
begin
  -- (1) e (2): as linhas pendentes
  for r in
    select q.id, q.scheduled_for, m.id as msg, m.tipo, m.enviar_em
      from public.whatsapp_send_queue q
      left join public.agenda_cliente_mensagens m on m.id = q.source_ref_id
     where q.source = 'agenda-cliente' and q.status = 'pending'
     order by q.scheduled_for, q.id
  loop
    v_mot := case
      when r.msg is null then 'janela'
      when cf.modo_cliente <> 'ligado' then 'modo'
      when not (r.tipo = any (cf.cliente_tipos_ligados)) then 'tipo_em_teste'
      when r.scheduled_for <= p_agora and public._agenda_cliente_fora_da_janela(r.enviar_em, p_agora) is not null then 'janela'
    end;
    if v_mot is not null then
      if v_mot = 'janela' then n_jan := n_jan + 1; else n_modo := n_modo + 1; end if;
    else
      v_mot := public._agenda_cliente_revalidar(r.msg, p_agora);
      if v_mot is not null then
        n_reval := n_reval + 1;
      end if;
    end if;
    if v_mot is not null then
      update public.whatsapp_send_queue
         set status = 'failed', failed_reason = 'agenda-cliente: não saiu (' || v_mot || ')'
       where id = r.id and status = 'pending';
      update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = v_mot
       where id = r.msg and estado = 'enfileirada';
    end if;
  end loop;
  -- (3) o que é hora de mandar
  if cf.modo_cliente = 'ligado' then
    for r in
      select m.id from public.agenda_cliente_mensagens m
       where m.modo = 'ligado' and m.aprovacao in ('livre', 'aprovada')
         and m.estado in ('registrada', 'aguardando_dono') and m.enviar_em <= p_agora + c_tique
       order by m.enviar_em, m.id
    loop
      v_res := public._agenda_cliente_enfileirar(r.id, p_agora);
      case v_res ->> 'estado'
        when 'enfileirada' then n_fila := n_fila + 1;
        when 'recusada' then n_recus := n_recus + 1;
        else n_espera := n_espera + 1;
      end case;
    end loop;
  end if;
  -- (4) a validade: a que não saiu a tempo vence (a esperando o dono, com a pergunta)
  for r in
    select m.id, m.aprovacao, m.pergunta_id from public.agenda_cliente_mensagens m
     where m.modo = 'ligado' and m.estado in ('registrada', 'aguardando_dono') and m.valida_ate < p_agora
     order by m.enviar_em, m.id
  loop
    update public.agenda_cliente_mensagens
       set estado = 'recusada', recusa_motivo = 'vencida',
           aprovacao = case when r.aprovacao in ('pedida', 'critica') then 'vencida' else aprovacao end
     where id = r.id;
    if r.aprovacao in ('pedida', 'critica') and r.pergunta_id is not null then
      update public.agenda_perguntas
         set estado = 'vencida', resolvida_motivo = 'a mensagem ao cliente venceu sem a resposta do dono'
       where id = r.pergunta_id and estado = 'aberta';
    end if;
    n_venc := n_venc + 1;
  end loop;
  return jsonb_build_object('canceladas', n_modo + n_jan + n_reval, 'pelo_modo', n_modo, 'pela_janela', n_jan,
                            'revalidadas', n_reval, 'enfileiradas', n_fila, 'esperando', n_espera, 'recusadas', n_recus,
                            'vencidas', n_venc);
end;
$function$;

comment on function public._agenda_cliente_fila(date, timestamptz) is
  'Agenda de Produção (Fase 5, P2), passo do cliente "fila" (roda sempre, até com tudo desligado; a rodada do P3 o chama antes de tudo): (1) a linha agenda-cliente pendente sem a mensagem, com modo_cliente ou o tipo fora de ligado, ou que já devia ter saído e agora está fora da janela dela, vira failed e a mensagem fica recusada (janela, modo, tipo_em_teste); (2) a pendente que a revalidação recusa vira failed/recusada com o motivo; (3) em ligado, a registrada (ou esperando o dono e já aprovada) livre ou aprovada com enviar_em até o próximo tique vai a _agenda_cliente_enfileirar; (4) a registrada ou esperando o dono que passou de valida_ate fica recusada/vencida (a pedida ou crítica com a aprovação vencida e a pergunta vencida). {canceladas, pelo_modo, pela_janela, revalidadas, enfileiradas, esperando, recusadas, vencidas}.';

-- ── 10. D9: o botão antigo e o "sim" ao pedido de confirmação ───────────────────────────────────────────
-- Corpos copiados das definições MAIS NOVAS (pedir_confirmacao_do_agendamento: 20260930130000;
-- registrar_confirmacao_do_cliente: 20261012101000, com a casca de search_path vazio); as mudanças estão marcadas
-- "-- FASE 5:" e, no registrar, fora dos blocos só as 3 linhas da regra do plano e da validade (2 delas nas duas
-- consultas). A casca (security definer, search_path) não muda.

create or replace function public.pedir_confirmacao_do_agendamento(p_os uuid, p_autor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := coalesce(auth.uid(), p_autor);
  v_os record;
  v_fone text;
  v_teste boolean;
  v_fone_teste text;
  v_destino text;
  v_nome text;
  v_quando text;
  v_msg text;
  -- FASE 5: o plano (D9) e a mensagem pela agenda
  v_cf public.agenda_config;
  v_hoje date;
  v_dia date;
  v_fim date;
  v_r jsonb;
  v_motivo text;
  v_quem text;
  v_dados jsonb;
  -- FASE 5: fim
begin
  if v_autor is not null and not exists (
    select 1 from public.app_users u where u.id = v_autor and u.active and u.role in ('admin', 'financial', 'seller')) then
    raise exception 'Sem permissão para falar com o cliente pelo WhatsApp.' using errcode = '42501';
  end if;

  select s.id, s.service_order_number, s.status, s.scheduled_start_at,
         c.name as cliente, c.phone, c.whatsapp, c.opt_out_whatsapp, v.name as barco
    into v_os
    from public.service_orders s
    left join public.clients c on c.id = s.client_id
    left join public.vessels v on v.id = s.vessel_id
   where s.id = p_os;
  if v_os.id is null then raise exception 'OS não encontrada.'; end if;
  -- FASE 5: D9 — com o plano ligado (modo_proposta), vale o próximo dia vigente do plano, de amanhã em diante, com a OS
  -- aberta, aprovada, agendada ou em andamento (o espelho scheduled_* fica para trás numa OS em andamento); aguardando peça
  -- ou o cliente, não. Sem o plano ligado, a regra de 30/09 (agendada e no futuro).
  v_cf := public._agenda_cfg();
  v_hoje := public._hoje_brt();
  if v_cf.modo_proposta = 'ligado' then
    if v_os.status in ('awaiting_parts', 'awaiting_client') then
      raise exception 'A OS espera peça (ou o cliente): confirmar o dia agora seria prometer o que não depende de nós.';
    end if;
    v_dia := (public._agenda_plano_da_os(p_os, v_hoje) ->> 'proximo_dia')::date;
    if v_os.status not in ('open', 'approved', 'scheduled', 'in_progress') or v_dia is null or v_dia <= v_hoje then
      raise exception 'A OS % não tem dia marcado no plano de amanhã em diante.', v_os.service_order_number;
    end if;
    v_os.scheduled_start_at := (select min(lower(a.periodo)) from public.agenda_alocacoes a
                                 where a.service_order_id = p_os and a.dia = v_dia and a.estado in ('publicada', 'fixada')
                                   and a.tipo <> 'reserva');
  else
  -- FASE 5: fim
  if v_os.status <> 'scheduled' or v_os.scheduled_start_at is null then
    raise exception 'A OS % não está agendada.', v_os.service_order_number;
  end if;
  if v_os.scheduled_start_at < now() then
    raise exception 'O atendimento da OS % já passou.', v_os.service_order_number;
  end if;
  -- FASE 5: o fim do "senão" (a regra de 30/09)
  end if;
  -- FASE 5: fim
  if coalesce(v_os.opt_out_whatsapp, false) then
    raise exception 'Este cliente pediu para não receber WhatsApp: confirme por telefone.';
  end if;
  v_fone := regexp_replace(coalesce(nullif(v_os.whatsapp, ''), v_os.phone, ''), '\D', '', 'g');
  if length(v_fone) < 10 then raise exception 'Cliente sem telefone cadastrado.'; end if;
  if length(v_fone) in (10, 11) then v_fone := '55' || v_fone; end if;

  v_teste := coalesce((select value::text from public.app_settings where key = 'wa_test_mode'), 'false') in ('true', '"true"');
  v_fone_teste := regexp_replace(coalesce((select value::text from public.app_settings where key = 'wa_test_number'), ''), '\D', '', 'g');
  if v_teste and v_fone_teste = '' then raise exception 'Modo de teste ligado sem número de teste configurado.'; end if;
  v_destino := case when v_teste then v_fone_teste else v_fone end;
  -- FASE 5: com modo_cliente ligado e a confirmação ligada (cliente_tipos_ligados), a mensagem é a da agenda — o M1 pelo
  -- botão, já aprovado (o dono clicou) — e passa pela janela, pelo feriado, pelo teto, pelo intervalo e pela revalidação:
  -- sai na hora que a janela deixa, e o pedido de confirmação conta de quando ela SAI (o gatilho do envio). Fora disso (o
  -- modo em teste, ou a confirmação ainda não ligada), como antes.
  if v_cf.modo_cliente = 'ligado' and 'confirmar' = any (v_cf.cliente_tipos_ligados) then
    v_quem := coalesce(public._agenda_nome_curto(v_os.cliente), 'o cliente');
    v_dados := '{}'::jsonb;
    if v_cf.modo_proposta <> 'ligado' then
      -- sem o plano, o dia, o turno e os dias de trabalho saem do agendamento da OS
      v_dia := (v_os.scheduled_start_at at time zone 'America/Sao_Paulo')::date;
      v_fim := greatest(v_dia, coalesce((select (so.scheduled_end_at at time zone 'America/Sao_Paulo')::date
                                           from public.service_orders so where so.id = p_os), v_dia));
      v_dados := jsonb_build_object('dia', v_dia, 'fim', v_fim,
        'janela', case when (v_os.scheduled_start_at at time zone 'America/Sao_Paulo')::time < v_cf.tarde_inicio
                       then 'manha' else 'tarde' end,
        'n', greatest(1, (select count(*)::int from generate_series(v_dia, v_fim, interval '1 day') g
                           where public.agenda_dia_util(g::date))));
    end if;
    begin
      v_r := public._agenda_cliente_registrar('confirmar', null, p_os,
               (v_os.scheduled_start_at at time zone 'America/Sao_Paulo')::date, v_dados, now(), null, 'botao', null, now(),
               v_autor);
    exception when sqlstate '22023' then
      raise exception 'Não deu para montar a mensagem ao cliente: %', sqlerrm;
    end;
    if not coalesce((v_r ->> 'criada')::boolean, false) then
      return jsonb_build_object('ok', true, 'agenda', true, 'teste', v_teste, 'id', v_r ->> 'id',
        'message', format('A confirmação de %s com %s já está com a agenda.', public._dia_curto(
                            (v_os.scheduled_start_at at time zone 'America/Sao_Paulo')::date), v_quem));
    end if;
    v_motivo := v_r ->> 'motivo';
    if v_r ->> 'estado' = 'recusada' then
      raise exception '%', case
        when v_motivo = 'sem_conversa' then format('%s não escreveu para a HBR nos últimos %s dias: mensagem automática a quem não escreve arrisca o número. Confirme por telefone.',
                                                    v_quem, v_cf.cliente_conversa_dias)
        when v_motivo in ('teto_dia', 'teto_semana') then format('%s já recebeu as mensagens que cabem (no máximo %s por dia e %s por semana): confirme por telefone.',
                                                                  v_quem, v_cf.cliente_dia_max, v_cf.cliente_semana_max)
        when v_motivo = 'teto_total' then format('A agenda já mandou as %s mensagens de hoje aos clientes: confirme por telefone.',
                                                 v_cf.cliente_total_dia_max)
        when v_motivo = 'material' then format('O material da OS %s ainda não está todo na mão: a data ainda não é firme para confirmar.',
                                               v_os.service_order_number)
        when v_motivo = 'mesmo_tipo_24h' then format('%s já recebeu uma confirmação nas últimas %s horas.', v_quem,
                                                     v_cf.cliente_mesmo_tipo_horas)
        when v_motivo = 'opt_out' then 'Este cliente pediu para não receber WhatsApp: confirme por telefone.'
        when v_motivo = 'sem_telefone' then 'Cliente sem telefone válido para a mensagem (ou o número é de alguém da HBR).'
        when v_motivo in ('status', 'data_mudou', 'desatualizada')
          then format('A OS %s mudou enquanto eu montava a mensagem: confira o plano e peça de novo.', v_os.service_order_number)
        else format('Não deu para pedir a confirmação agora (%s).', coalesce(v_motivo, v_r ->> 'estado')) end;
    end if;
    return jsonb_build_object('ok', true, 'agenda', true, 'teste', v_teste, 'mensagem', v_r ->> 'texto', 'id', v_r ->> 'id',
      'enviar_em', v_r ->> 'enviar_em',
      'message', case
        when v_motivo = 'conversa_viva'
          then format('Pedido de confirmação a %s registrado: sai %s (%s está conversando agora; espero a conversa acabar).',
                      v_quem, public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, now()), v_quem)
        when (v_r ->> 'enviar_em')::timestamptz <= now() + interval '15 minutes'
          then case when v_teste then 'Mensagem na fila (modo de teste: vai para o número de teste).'
                    else format('Pedido de confirmação na fila para %s. Quando ele responder SIM, a OS fica confirmada.', v_quem) end
        else format('Pedido de confirmação a %s registrado: sai %s (fora do horário de mensagens agora).', v_quem,
                    public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, now())) end);
  end if;
  -- FASE 5: fim

  v_nome := coalesce(nullif(split_part(btrim(coalesce(v_os.cliente, '')), ' ', 1), ''), '');
  v_quando := (array['domingo','segunda','terça','quarta','quinta','sexta','sábado'])[extract(dow from v_os.scheduled_start_at at time zone 'America/Sao_Paulo')::int + 1]
    || ' (' || to_char(v_os.scheduled_start_at at time zone 'America/Sao_Paulo', 'DD/MM') || ') às '
    || to_char(v_os.scheduled_start_at at time zone 'America/Sao_Paulo', 'HH24"h"MI');
  v_msg := 'Olá' || case when v_nome <> '' then ', ' || initcap(v_nome) else '' end || '! Aqui é da HBR Marine. '
    || 'Confirmando o atendimento' || coalesce(' no ' || nullif(v_os.barco, ''), '') || ' ' || v_quando || '. '
    || 'Pode responder SIM para confirmar? Se precisar remarcar, é só avisar por aqui. 👍';

  insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, priority)
  values (v_destino, v_msg, 'agenda-confirmacao', v_os.id, 3);

  update public.service_orders
     set client_confirmation_requested_at = now(), client_confirmed_at = null, client_confirmed_for = null
   where id = v_os.id;

  return jsonb_build_object('ok', true, 'teste', v_teste, 'mensagem', v_msg,
    'message', case when v_teste then 'Mensagem na fila (modo de teste: vai para o número de teste).'
                    else 'Pedido de confirmação enviado a ' || coalesce(v_os.cliente, 'o cliente') || '. Quando ele responder SIM, a OS fica confirmada.' end);
end;
$$;

create or replace function public.registrar_confirmacao_do_cliente(p_phone text, p_body text, p_message_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_os record;
  v_n int;
  v_quando text;
  -- FASE 5: o dia confirmado e as alocações que ele fixa
  v_dia date;
  v_fix uuid[];
  -- FASE 5: fim
begin
  if length(v_fone) < 8 or not public._e_concordancia(p_body) then
    return jsonb_build_object('confirmou', false);
  end if;

  -- OS agendada, com pedido de confirmação nas últimas 72 h e ainda sem resposta, deste cliente.
  select count(*) into v_n
    from public.service_orders s join public.clients c on c.id = s.client_id
   where public._agenda_cliente_dia_a_confirmar(s.id, now()) is not null
     and s.client_confirmation_requested_at > now() - (public._agenda_cfg()).cliente_resposta_validade
     and s.client_confirmed_at is null
     and right(regexp_replace(coalesce(nullif(c.whatsapp, ''), c.phone, ''), '\D', '', 'g'), 8) = right(v_fone, 8);
  if v_n = 0 then return jsonb_build_object('confirmou', false); end if;

  if v_n > 1 then
    -- Duas OS esperando: "sim" não diz qual. Avisa o dono em vez de adivinhar.
    insert into public.app_notifications (user_id, type, title, body, navigate_to)
    select u.id, 'agendamento_confirmado', 'Cliente respondeu SIM, mas há ' || v_n || ' OS esperando confirmação',
           'Confira com o cliente qual atendimento ele confirmou.', '/agenda'
      from public.app_users u where u.role = 'admin' and u.active;
    return jsonb_build_object('confirmou', false, 'ambigua', v_n);
  end if;

  select s.id, s.service_order_number, public._agenda_cliente_dia_a_confirmar(s.id, now()) as scheduled_start_at, c.name as cliente into v_os
    from public.service_orders s join public.clients c on c.id = s.client_id
   where public._agenda_cliente_dia_a_confirmar(s.id, now()) is not null
     and s.client_confirmation_requested_at > now() - (public._agenda_cfg()).cliente_resposta_validade
     and s.client_confirmed_at is null
     and right(regexp_replace(coalesce(nullif(c.whatsapp, ''), c.phone, ''), '\D', '', 'g'), 8) = right(v_fone, 8);

  update public.service_orders
     set client_confirmed_at = now(), client_confirmed_for = v_os.scheduled_start_at
   where id = v_os.id;
  -- FASE 5: D9 — com o plano ligado, o SIM fixa as alocações publicadas daquele dia (fixado_por cliente_confirmou) e
  -- registra a ação (fixar, origem cliente). Sem *desfaz* por aqui: com modo_cliente fora de desligado, quem lê a resposta
  -- primeiro é a agenda (agenda_resposta_do_cliente, P4), que fixa com *desfaz*; este é o caminho do botão antigo.
  if (public._agenda_cfg()).modo_proposta = 'ligado' then
    v_dia := (v_os.scheduled_start_at at time zone 'America/Sao_Paulo')::date;
    with x as (
      update public.agenda_alocacoes a set estado = 'fixada', fixado_por = 'cliente_confirmou'
       where a.service_order_id = v_os.id and a.dia = v_dia and a.estado = 'publicada' and a.tipo <> 'reserva'
      returning a.id)
    select coalesce(array_agg(x.id), '{}'::uuid[]) into v_fix from x;
    if cardinality(v_fix) > 0 then
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
      values (clock_timestamp(), (now() at time zone 'America/Sao_Paulo')::date, true, 'cliente', 'fixar', v_os.id,
              array[v_os.id], jsonb_build_object('alocacoes', v_fix, 'estado', 'publicada'),
              jsonb_build_object('alocacoes', v_fix, 'estado', 'fixada', 'fixado_por', 'cliente_confirmou'),
              format('O %s confirmou %s.', coalesce(public._agenda_nome_curto(v_os.cliente), 'cliente'), public._dia_curto(v_dia)));
    end if;
  end if;
  -- FASE 5: fim

  v_quando := to_char(v_os.scheduled_start_at at time zone 'America/Sao_Paulo', 'DD/MM "às" HH24"h"MI');
  insert into public.app_notifications (user_id, type, title, body, navigate_to)
  select u.id, 'agendamento_confirmado', coalesce(v_os.cliente, 'Cliente') || ' confirmou o atendimento',
         v_os.service_order_number || ', ' || v_quando || ' — respondeu "' || left(btrim(p_body), 40) || '" pelo WhatsApp.',
         '/v2/service-orders/' || v_os.id
    from public.app_users u where u.role = 'admin' and u.active;

  return jsonb_build_object('confirmou', true, 'os', v_os.service_order_number);
end;
$$;

comment on function public.pedir_confirmacao_do_agendamento(uuid, uuid) is
  'O botão "Pedir confirmação" (30/09/2026): manda ao cliente o pedido de SIM. Fase 5 (P2, D9): com modo_proposta ligado, vale o próximo dia vigente do plano (de amanhã em diante) com a OS aberta, aprovada, agendada ou em andamento — aguardando peça ou o cliente recusa —; fora de ligado, a regra de 30/09 (agendada e no futuro). Com modo_cliente ligado e confirmar em cliente_tipos_ligados, registra o M1 pela agenda (_agenda_cliente_registrar origem botao, já aprovado; janela, feriado, teto, intervalo e revalidação) e diz quando sai; a recusa vira o erro com o motivo. Fora disso, como antes (origem agenda-confirmacao).';
comment on function public.registrar_confirmacao_do_cliente(text, text, uuid) is
  'O "sim" curto do cliente ao pedido de confirmação (30/09/2026; o número da OS sem prefixo repetido, 12/10). Fase 5 (P2, D9): a OS que vale é a de _agenda_cliente_dia_a_confirmar (com o plano ligado, o próximo dia do plano em qualquer status ativo; senão a agendada), o pedido vale cliente_resposta_validade, e com o plano ligado o SIM fixa as alocações publicadas daquele dia (cliente_confirmou) com a ação fixar (origem cliente).';

-- ── 11. Portas ──────────────────────────────────────────────────────────────────────────────────────────

-- As leituras (invoker, STABLE/IMMUTABLE): a janela, a validade, o tipo liberado e os textos ao dono — authenticated (o foco
-- e a tela do P5/P6, com a RLS de quem lê) e service_role; nunca anon.
revoke all on function
  public._agenda_cliente_dia_de_janela(date), public._agenda_cliente_fora_da_janela(timestamptz, timestamptz),
  public._agenda_cliente_fim_da_janela(date, integer), public._agenda_cliente_tipo_liberado(text),
  public._agenda_cliente_tipo_texto(text), public._agenda_cliente_quando_texto(timestamptz, timestamptz),
  public._agenda_cliente_o_que(text, date)
  from public, anon;
grant execute on function
  public._agenda_cliente_dia_de_janela(date), public._agenda_cliente_fora_da_janela(timestamptz, timestamptz),
  public._agenda_cliente_fim_da_janela(date, integer), public._agenda_cliente_tipo_liberado(text),
  public._agenda_cliente_tipo_texto(text), public._agenda_cliente_quando_texto(timestamptz, timestamptz),
  public._agenda_cliente_o_que(text, date)
  to authenticated, service_role;

-- Os passos internos, as travas e os gatilhos: ninguém de fora (nem o service_role). O único caminho até a fila
-- agenda-cliente é a rodada (P3), a resposta (P4), a decisão do dono (P3/P5) e o botão (pedir_confirmacao_do_agendamento).
revoke all on function
  public._agenda_cliente_quando(integer, timestamptz, timestamptz, uuid),
  public._agenda_cliente_conversou(uuid, timestamptz), public._agenda_cliente_sem_mensagem(uuid),
  public._agenda_cliente_no_periodo(uuid, date, date, uuid), public._agenda_cliente_dia_a_confirmar(uuid, timestamptz),
  public._agenda_cliente_texto_do_aviso(text, text, uuid, jsonb, date),
  public._agenda_cliente_perguntar(text, text, uuid, date, date, text, text, timestamptz, timestamptz),
  public._agenda_cliente_revalidar(uuid, timestamptz), public._agenda_cliente_enfileirar(uuid, timestamptz),
  public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamptz, timestamptz, text, text, timestamptz, uuid),
  public._agenda_fila_do_cliente(), public._agenda_cliente_enviada(), public._agenda_cliente_fila(date, timestamptz)
  from public, anon, authenticated, service_role;

-- A 3ª trava (o worker): só service_role.
revoke all on function public.agenda_cliente_pode_sair(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_cliente_pode_sair(uuid, timestamptz) to service_role;

-- D9: as mesmas portas de antes (o botão: authenticated, com o cargo conferido dentro, e service_role; o "sim": só o
-- webhook, service_role).
revoke all on function public.pedir_confirmacao_do_agendamento(uuid, uuid) from public, anon;
grant execute on function public.pedir_confirmacao_do_agendamento(uuid, uuid) to authenticated, service_role;
revoke all on function public.registrar_confirmacao_do_cliente(text, text, uuid) from public, anon, authenticated;
grant execute on function public.registrar_confirmacao_do_cliente(text, text, uuid) to service_role;
