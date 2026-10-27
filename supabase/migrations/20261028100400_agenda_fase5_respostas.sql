-- Agenda de Produção, Fase 5 ("Mensagens ao cliente"), pacote P4: a resposta do cliente — o que ele escreve depois de uma
-- mensagem da agenda (o SIM, "pode ser sexta?", "não dá pra amanhã", "a chave fica com o marinheiro", "PARAR", o áudio, a
-- reclamação, a pergunta) é lido sem IA, decidido pelo banco e registrado; o que a agenda não trata vai ao dono. Nada
-- responde ao cliente.
-- Spec: scratchpad agenda-pesquisa/spec-fase5.md (§0 item 7, §3.1, §3.2, §5.4, §6.2, §6.3, d8, d9, d18). Decisões do dono
-- 23/10 (o gestor remaneja quando o cliente pede outra data; o crítico sempre pergunta; o áudio nunca confirma). Depende de
-- 20261028100000 (as tabelas), 100100 (os textos), 100200 (o envio, a pergunta da mensagem) e 100300 (o cancelar, o
-- acorde e o "não respondeu").
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (9 funções novas, 1 recriada; nenhuma tabela, nenhum gatilho, nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f5p4/montar-migration.mjs: as partes escritas à mão
-- e o corpo de agenda_desfazer copiado de 20261027100400 (a definição mais nova), com cada bloco "-- FASE 5:" conferido
-- (fora dos blocos nenhuma linha muda).
--
-- POR QUE: a mensagem a TERCEIRO tem resposta, e hoje ninguém lê (NOVO-agenda-41: o leitor nunca leu nada; 0 de 9 linhas de
-- ai_comms_log com reply_intent). O "sim" curto de 30/09 só vale para o botão antigo; o "não dá terça" fica na conversa e a
-- equipe vai mesmo assim.
--
-- O QUE MUDA:
--   1. agenda_resposta_do_cliente (nova; só service_role; o whatsapp-webhook chama, depois da resposta da equipe e antes
--      da confirmação de 30/09 e da conferência do recibo — "o ok tem um dono só"): quem é (o cliente com OS na carteira ou
--      concluída há até 30 dias; nunca o dono, a equipe ou quem recebe diária), a que mensagem responde (a última da agenda
--      mandada a ele, dos tipos que esperam resposta, dentro de cliente_resposta_validade e ainda sem resposta; sem ela, não
--      lê), e o efeito. desligado = nada; sombra = só registra a resposta (efeito sombra, com a intenção) e devolve consumiu
--      false (os fluxos de hoje seguem iguais).
--   2. Os efeitos (sem grant): _agenda_cliente_confirmar_dia (o SIM fixa o dia e grava client_confirmed_*),
--      _agenda_cliente_pedido_de_dia (o "não antes de", o bem indisponível e o replano) e _agenda_cliente_anotar_acesso (uma
--      linha nova em site_access), cada um com a ação e o *desfaz*; e o opt-out (as vivas recusadas, calado).
--   3. agenda_desfazer recriada (blocos -- FASE 5:): a ação da resposta do cliente vai a _agenda_desfazer_cliente; a
--      mensagem enviada não se desmanda; o replano do pedido desfeito direto também tira o pedido.
--   4. Auxiliares: _agenda_clientes_do_telefone, _agenda_cliente_a_mensagem (leitura), _agenda_cliente_data_da_resposta e
--      _agenda_cliente_restaurar_pedido.
--
-- MEDIDO EM PRODUÇÃO (27/10, só contagens, f5p4/m5p4_01_numeros.sql): 11 clientes com OS na carteira ou concluída há até
-- 30 dias, 8 com número; nenhum número de dois clientes e nenhum que seja do dono, da equipe ou de quem recebe diária; nenhuma
-- OS ativa com o campo de acesso preenchido (o NOVO-agenda-38 continua).
--
-- O QUE NÃO MUDA: registrar_confirmacao_do_cliente (o P2; com a agenda consumindo, o webhook não a chama), a rodada (P3), o
-- envio e as travas (P2), o motor (a criticidade da Fase 2 vale: o remarcar do que o cliente confirmou para mais de 2 dias
-- úteis vira a pergunta crítica do motor; a mensagem do dia novo sai pela rodada, na hora dela).
--
-- DINHEIRO: nada aqui cria, muda ou liga pagamento, cobrança ou orçamento. Preço, desconto, parcela e pagamento ditos pelo
-- cliente vão ao dono (negociação), sem resposta.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase5_respostas.sql e anotadas em notas-fase5.md):
--   · O SIM ao aviso de atraso REMARCADO (M6 remarcado: "precisou passar para quinta (12/11) … Pode ser? Responda SIM")
--     confirma o dia novo como o M1 (a spec punha todo pode_atrasar em ciência); o SIM ao M6 peça/execução é ciência.
--   · O pedido de dia só vale nas mensagens que propõem um dia (M1, M2, M4, M3, M7, M10 e o M6 remarcado) e com
--     modo_proposta ligado; no "ficou pronto", no pós-serviço e no aviso de atraso por peça vai ao dono. O dia pedido que é
--     hoje, já passou, é o mesmo combinado ou é ANTES dele vai ao dono (o "não antes de" não adiantaria nada).
--   · O dia recusado é o que o cliente disse ("não posso quarta" tira a quarta, não o dia da mensagem; "vou viajar até
--     sexta" tira de hoje a sexta; "essa semana" tira do dia combinado ao domingo); sem dia dito, o dia da mensagem. O dia
--     recusado que não é dia do serviço ("não dá amanhã" num sábado, com o serviço na terça) vai ao dono: não adivinho.
--   · O acorde vale para o pedido de dia (data também, não só remarcar e falta) quando o dia combinado é hoje ou o próximo
--     dia útil (a spec: "≤ amanhã"; no sábado, a terça depois de Finados ainda é "amanhã" para a equipe); o acorde é a
--     própria ação do pedido (depois.acorde), como o "não vou" da equipe.
--   · Duas OS esperando OU dois clientes no número = ambígua (vai ao dono, a mensagem não fica respondida).
--   · Uma resposta por mensagem da agenda: a que já foi respondida não lê a 2ª ("obrigado" depois do SIM não vira pergunta).
--   · O efeito que falha (o replano que lança) não derruba o webhook: a resposta vai ao dono e o erro a app_error_logs
--     (action cliente:resposta).
--
-- ORDEM DE LIGAR: depois de 20261028100000 a 100300; ANTES do deploy do whatsapp-webhook (sem a função, o webhook segue como
-- hoje: a RPC ausente devolve false sem registro). Com modo_cliente desligado (a linha nasce assim) nada é lido.
--
-- PROVA: supabase/tests/agenda_fase5_respostas.sql (A0–A12). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; depois de 20261028100000 a 100300):
--   npx supabase db query --linked -f supabase/migrations/20261028100400_agenda_fase5_respostas.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261028100400', 'agenda_fase5_respostas');"
--
-- DESFAZER: reaplicar agenda_desfazer de 20261027100400; as funções novas ficam (sem o webhook novo, ninguém as chama).
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. Quem escreveu e o que ele disse ──────────────────────────────────────────────────────────────────

-- Os clientes de um telefone (os 8 últimos dígitos do WhatsApp ou do telefone do cadastro) que têm OS na carteira (aberta,
-- aprovada, agendada, em andamento, aguardando peça ou o cliente) ou concluída nos últimos 30 dias (spec §5.4). O número do
-- dono, da equipe ou de quem recebe diária (app_users, payees) nunca é cliente: nenhum (NOVO-agenda-42).
create or replace function public._agenda_clientes_do_telefone(p_phone text, p_agora timestamptz)
 returns uuid[]
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(array_agg(c.id order by c.id), '{}'::uuid[])
    from public.clients c
   where public._agenda_chave_telefone(p_phone) is not null
     and public._agenda_chave_telefone(p_phone) in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone))
     and not exists (
       select 1 from (
         select public._agenda_chave_telefone(u.phone_normalized) as k from public.app_users u
         union select public._agenda_chave_telefone(u.phone) from public.app_users u
         union select public._agenda_chave_telefone(p.phone) from public.payees p
       ) i where i.k = public._agenda_chave_telefone(p_phone))
     and exists (
       select 1 from public.service_orders so
        where so.client_id = c.id
          and (so.status in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client')
               or (so.status in ('completed', 'invoiced')
                   and coalesce(so.delivered_at, so.check_out_at) > p_agora - interval '30 days')));
$function$;

comment on function public._agenda_clientes_do_telefone(text, timestamptz) is
  'Agenda de Produção (Fase 5, P4): os clientes de um telefone (8 últimos dígitos de clients.whatsapp ou clients.phone) com OS na carteira ou concluída nos últimos 30 dias. O número do dono, da equipe ou de quem recebe diária (app_users.phone/phone_normalized, payees.phone) nunca é cliente (vazio). Interna (sem grant).';

-- A mensagem da agenda como o dono lê numa frase ("à confirmação de ter 03/11", "ao aviso de atraso", "ao \"ficou pronto\"").
create or replace function public._agenda_cliente_a_mensagem(p_tipo text, p_variante text, p_dia date)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case p_tipo
    when 'confirmar' then 'à confirmação' || coalesce(' de ' || public._dia_curto(p_dia), '')
    when 'vespera' then 'ao aviso da véspera' || coalesce(' (' || public._dia_curto(p_dia) || ')', '')
    when 'acesso' then 'à pergunta do acesso' || coalesce(' (' || public._dia_curto(p_dia) || ')', '')
    when 'material_chegou' then 'ao aviso de que o material chegou' || coalesce(' (começo ' || public._dia_curto(p_dia) || ')', '')
    when 'nova_data' then 'à nova data' || coalesce(' (' || public._dia_curto(p_dia) || ')', '')
    when 'mudanca_no_dia' then 'à mudança do dia' || coalesce(' (novo dia: ' || public._dia_curto(p_dia) || ')', '')
    when 'pode_atrasar' then case when p_variante = 'remarcado'
                                  then 'à mudança de data' || coalesce(' (' || public._dia_curto(p_dia) || ')', '')
                                  else 'ao aviso de atraso' end
    when 'pronto' then 'ao "ficou pronto"'
    when 'pronto_lembrete' then 'ao lembrete da entrega'
    when 'pos_servico' then 'à mensagem de pós-serviço'
    when 'andamento' then 'ao andamento do serviço'
    else 'à mensagem da agenda' end;
$function$;

comment on function public._agenda_cliente_a_mensagem(text, text, date) is
  'Agenda de Produção (Fase 5, P4): a mensagem ao cliente numa frase do dono, depois de "respondeu …" — "à confirmação de ter 03/11", "ao aviso da véspera (ter 03/11)", "ao aviso de atraso", "à mudança de data (qui 12/11)" (o M6 remarcado), "ao \"ficou pronto\"".';

-- A data que o cliente disse, pelo banco (agenda_data_dita, com o dia da mensagem em Brasília; o LLM e o TS nunca
-- calculam): {de, ate}. "essa semana" (só no dia recusado) = do dia combinado ao domingo da mesma semana, nunca antes de
-- hoje. null = não entendeu.
create or replace function public._agenda_cliente_data_da_resposta(p_expressao text, p_hoje date, p_dia date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v jsonb;
  v_ini date;
begin
  if nullif(btrim(coalesce(p_expressao, '')), '') is null then
    return null;
  end if;
  if public._agenda_normal(p_expressao) in ('essa semana', 'esta semana', 'nessa semana', 'nesta semana') then
    v_ini := date_trunc('week', coalesce(p_dia, p_hoje))::date;
    return jsonb_build_object('de', greatest(coalesce(p_dia, p_hoje), p_hoje), 'ate', greatest(v_ini + 6, p_hoje));
  end if;
  begin
    v := public.agenda_data_dita(p_expressao, p_hoje, 'futuro');
  exception when others then
    return null;
  end;
  if v ->> 'de' is null then
    return null;
  end if;
  return jsonb_build_object('de', (v ->> 'de')::date, 'ate', coalesce((v ->> 'ate')::date, (v ->> 'de')::date));
end;
$function$;

comment on function public._agenda_cliente_data_da_resposta(text, date, date) is
  'Agenda de Produção (Fase 5, P4): a expressão de data da resposta do cliente ("sexta", "dia 04/11", "até sexta", "semana que vem") vira {de, ate} pelo banco (agenda_data_dita, futuro, com o dia da mensagem). "essa semana" (o dia recusado) = do dia combinado (p_dia) ao domingo da mesma semana, nunca antes de hoje. null = não entendeu. Interna (sem grant).';

-- ── 2. Os efeitos (cada um com a ação e o *desfaz*; chamados só pela resposta do cliente) ───────────────

-- O SIM à mensagem que propôs o dia (M1, M3, M7, M10 e o M6 remarcado): o client_confirmed_* (= o início do 1º meio-dia
-- do dia) e as alocações publicadas do dia fixadas (cliente_confirmou), com a ação fixar origem cliente e o *desfaz*.
-- O dia que saiu do plano não confirma nada: {ok: false, o_que}.
create or replace function public._agenda_cliente_confirmar_dia(p_msg uuid, p_resposta uuid, p_trecho text, p_hoje date,
                                                                p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  m      public.agenda_cliente_mensagens%rowtype;
  v_dia  date;
  v_ini  timestamptz;
  v_so   record;
  v_fix  uuid[];
  v_nome text;
  v_acao uuid;
  v_txt  text;
begin
  select * into m from public.agenda_cliente_mensagens where id = p_msg;
  v_dia := coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  select min(lower(a.periodo)) into v_ini
    from public.agenda_alocacoes a
   where a.service_order_id = m.service_order_id and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva';
  if v_ini is null then
    return jsonb_build_object('ok', false, 'o_que',
      format('confirmou, mas esse dia (%s) não está mais no plano: confira', coalesce(public._dia_curto(v_dia), 'sem dia')));
  end if;
  select so.client_confirmed_at, so.client_confirmed_for, cl.name, cl.display_name into v_so
    from public.service_orders so join public.clients cl on cl.id = so.client_id
   where so.id = m.service_order_id for update of so;
  v_nome := coalesce(public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(v_so.display_name, '')), ''), v_so.name)), 'cliente');
  with x as (
    update public.agenda_alocacoes a set estado = 'fixada', fixado_por = 'cliente_confirmou'
     where a.service_order_id = m.service_order_id and a.dia = v_dia and a.estado = 'publicada' and a.tipo <> 'reserva'
    returning a.id)
  select coalesce(array_agg(x.id order by x.id), '{}'::uuid[]) into v_fix from x;
  update public.service_orders set client_confirmed_at = p_agora, client_confirmed_for = v_ini where id = m.service_order_id;
  v_txt := format('O %s confirmou %s.', v_nome, public._dia_curto(v_dia));
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto,
                                   motivo, desfazivel_ate)
  values (clock_timestamp(), p_hoje, true, 'cliente', 'fixar', m.service_order_id, array[m.service_order_id],
          jsonb_build_object('alocacoes', to_jsonb(v_fix), 'estado', 'publicada',
                             'client_confirmed_at', v_so.client_confirmed_at, 'client_confirmed_for', v_so.client_confirmed_for),
          jsonb_build_object('efeito', 'confirmou', 'resposta_id', p_resposta, 'mensagem_id', m.id, 'dia', v_dia,
                             'alocacoes', to_jsonb(v_fix), 'estado', 'fixada', 'fixado_por', 'cliente_confirmou',
                             'client_confirmed_at', p_agora, 'client_confirmed_for', v_ini, 'trecho', public._agenda_corta(p_trecho, 200)),
          v_txt, 'o cliente confirmou', p_agora + cf.desfazer_validade)
  returning id into v_acao;
  -- o sino, como o "sim" do botão de 30/09
  insert into public.app_notifications (user_id, type, title, body, navigate_to)
  select u.id, 'agendamento_confirmado', v_nome || ' confirmou o atendimento',
         public._dia_curto(v_dia) || ' — respondeu "' || left(btrim(coalesce(p_trecho, '')), 40) || '" pelo WhatsApp.',
         '/v2/service-orders/' || m.service_order_id
    from public.app_users u where u.role = 'admin' and u.active;
  return jsonb_build_object('ok', true, 'acao_id', v_acao, 'texto', v_txt, 'fixadas', cardinality(v_fix));
end;
$function$;

comment on function public._agenda_cliente_confirmar_dia(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 5, P4): o SIM do cliente à mensagem que propôs o dia (o dia_alvo da base) — client_confirmed_at = agora e client_confirmed_for = o início do 1º meio-dia vigente do dia; as alocações publicadas do dia viram fixada (cliente_confirmou); a ação fixar (origem cliente, antes/depois, desfazivel_ate = agora + desfazer_validade) "O Flávio confirmou ter 03/11." e o sino dos administradores. Sem meio-dia vigente no dia: {ok: false, o_que} e nada muda. Interna (sem grant).';

-- O pedido de dia do cliente (data, remarcar, falta): o "não antes de" (o dia pedido; o maior dos dois, se o dono já tinha
-- posto um) e o bem indisponível (os dias recusados), com o histórico, e o replano pela vigia (a criticidade da Fase 2
-- vale: o remarcar do que ele confirmou para mais de 2 dias úteis vira a pergunta do motor). A ação cliente (origem
-- cliente) guarda o antes, o que entrou e as ações do replano, com o *desfaz*; o dia recusado que é hoje ou o próximo dia
-- útil vai ao dono por acorde (a mesma ação).
create or replace function public._agenda_cliente_pedido_de_dia(p_msg uuid, p_resposta uuid, p_tirar daterange, p_nao_antes date,
                                                                p_pedido text, p_trecho text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  m        public.agenda_cliente_mensagens%rowtype;
  p        public.os_planejamento%rowtype;
  v_os     uuid;
  v_dia    date;
  v_nome   text;
  v_add    datemultirange;
  v_tirado datemultirange;
  v_nao    date;
  v_motivo text;
  v_rep    jsonb;
  v_novo   date;
  v_crit   boolean;
  v_acorde boolean;
  v_txt    text;
  v_acao   uuid;
begin
  select * into m from public.agenda_cliente_mensagens where id = p_msg;
  v_os := m.service_order_id;
  v_dia := coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo);
  v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                        from public.clients cl where cl.id = m.client_id), 'cliente');
  insert into public.os_planejamento (service_order_id) values (v_os) on conflict (service_order_id) do nothing;
  select * into p from public.os_planejamento where service_order_id = v_os for update;
  v_add := case when p_tirar is null or isempty(p_tirar) then '{}'::datemultirange else datemultirange(p_tirar) end;
  v_tirado := v_add - p.bem_indisponivel;
  v_nao := case when p_nao_antes is not null and (p.nao_antes_de is null or p_nao_antes > p.nao_antes_de) then p_nao_antes
                else p.nao_antes_de end;
  v_motivo := case when v_nao is distinct from p.nao_antes_de then 'o cliente pediu' else p.nao_antes_motivo end;
  update public.os_planejamento
     set bem_indisponivel = p.bem_indisponivel + v_add, nao_antes_de = v_nao, nao_antes_motivo = v_motivo,
         historico = public._os_material_historico(p.historico, jsonb_build_object(
           'em', p_hoje, 'autor', null, 'trecho', public._agenda_corta(p_trecho, 500),
           'antes', jsonb_build_object('bem_indisponivel', p.bem_indisponivel::text, 'nao_antes_de', p.nao_antes_de),
           'depois', jsonb_build_object('bem_indisponivel', (p.bem_indisponivel + v_add)::text, 'nao_antes_de', v_nao))),
         atualizado_em = p_agora
   where service_order_id = v_os;
  v_rep := public.agenda_replanejar(array[v_os], 'o cliente pediu outro dia', 'vigia', p_hoje, p_agora, null);
  v_novo := (public._agenda_plano_da_os(v_os, p_hoje) ->> 'proximo_dia')::date;
  v_crit := jsonb_array_length(coalesce(v_rep -> 'perguntas', '[]'::jsonb)) > 0;
  -- "O Flávio pediu sex 06/11: remarquei para seg 09/11, o 1º dia que coube." / "O Flávio pediu outro dia (ter 03/11 não
  -- dá): tirei o dia e remarquei para qui 05/11." / "…: tirei o dia; a decisão ficou com você." (spec §6.3)
  v_txt := p_pedido || ': '
           || case when p_nao_antes is not null
                   then case when not v_crit and v_novo is not null
                             then 'remarquei para ' || public._dia_curto(v_novo)
                                  || case when v_novo > p_nao_antes then ', o 1º dia que coube' else '' end || '.'
                             else 'anotei; a decisão ficou com você.' end
                   else case when not v_crit and v_novo is not null
                             then 'tirei o dia e remarquei para ' || public._dia_curto(v_novo) || '.'
                             else 'tirei o dia; a decisão ficou com você.' end end
           || format(' *desfaz %s* volta como estava.', v_nome);
  -- o dia que a equipe esperava ir é hoje ou o próximo dia útil: o dono fica sabendo na hora (acorde)
  v_acorde := v_dia is not null and v_dia <= public.agenda_somar_du(p_hoje, 1);
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto,
                                   motivo, desfazivel_ate)
  values (clock_timestamp(), p_hoje, true, 'cliente', 'cliente', v_os, array[v_os],
          jsonb_build_object('bem_indisponivel', p.bem_indisponivel::text, 'nao_antes_de', p.nao_antes_de,
                             'nao_antes_motivo', p.nao_antes_motivo),
          jsonb_build_object('efeito', 'replanejou', 'resposta_id', p_resposta, 'mensagem_id', m.id, 'dia', v_dia,
                             'tirado', v_tirado::text, 'nao_antes_de', v_nao, 'nao_antes_motivo', v_motivo,
                             'replano_acoes', coalesce(v_rep -> 'acoes', '[]'::jsonb), 'critica', v_crit, 'novo_dia', v_novo,
                             'acorde', v_acorde, 'acorde_chave', 'cliente_resposta:' || p_resposta, 'perda_em', v_dia),
          public._agenda_corta(v_txt, 400), 'o cliente pediu outro dia', p_agora + cf.desfazer_validade)
  returning id into v_acao;
  return jsonb_build_object('ok', true, 'acao_id', v_acao, 'texto', public._agenda_corta(v_txt, 400), 'novo_dia', v_novo,
                            'critica', v_crit, 'acorde', v_acorde, 'replano', v_rep -> 'texto');
end;
$function$;

comment on function public._agenda_cliente_pedido_de_dia(uuid, uuid, daterange, date, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 5, P4): o pedido de dia do cliente — os_planejamento.bem_indisponivel + p_tirar (os dias recusados), nao_antes_de = p_nao_antes (o maior dos dois; motivo "o cliente pediu"), o histórico, e agenda_replanejar (vigia; a criticidade da Fase 2 vale). A ação cliente (origem cliente; antes = o planejamento, depois = {efeito replanejou, tirado, nao_antes_de, replano_acoes, critica, novo_dia, acorde}) "O Flávio pediu outro dia (ter 03/11 não dá): tirei o dia e remarquei para qui 05/11. *desfaz Flávio* volta como estava.", com desfazivel_ate; o dia combinado em até 1 dia útil = acorde (depois.acorde). Interna (sem grant).';

-- O acesso dito pelo cliente: uma linha nova no fim de service_orders.site_access ("Cliente (31/10): …", até 300; o que
-- havia fica igual) e os_planejamento.acesso_ok_em, com a ação cliente e o *desfaz* (que só volta se ninguém mexeu depois).
create or replace function public._agenda_cliente_anotar_acesso(p_msg uuid, p_resposta uuid, p_trecho text, p_hoje date,
                                                                p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  m       public.agenda_cliente_mensagens%rowtype;
  v_antes text;
  v_dep   text;
  v_linha text;
  v_ok    timestamptz;
  v_nome  text;
  v_txt   text;
  v_acao  uuid;
begin
  select * into m from public.agenda_cliente_mensagens where id = p_msg;
  v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                        from public.clients cl where cl.id = m.client_id), 'cliente');
  select so.site_access into v_antes from public.service_orders so where so.id = m.service_order_id for update;
  v_linha := format('Cliente (%s): %s', to_char(p_hoje, 'DD/MM'), left(btrim(coalesce(p_trecho, '')), 300));
  v_dep := case when coalesce(v_antes, '') = '' then v_linha else v_antes || E'\n' || v_linha end;
  update public.service_orders set site_access = v_dep where id = m.service_order_id;
  insert into public.os_planejamento (service_order_id) values (m.service_order_id) on conflict (service_order_id) do nothing;
  select pl.acesso_ok_em into v_ok from public.os_planejamento pl where pl.service_order_id = m.service_order_id for update;
  update public.os_planejamento set acesso_ok_em = p_agora, atualizado_em = p_agora where service_order_id = m.service_order_id;
  v_txt := format('Anotei o acesso que o %s disse: "%s".', v_nome, public._agenda_corta(btrim(coalesce(p_trecho, '')), 200));
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto,
                                   motivo, desfazivel_ate)
  values (clock_timestamp(), p_hoje, true, 'cliente', 'cliente', m.service_order_id, array[m.service_order_id],
          jsonb_build_object('site_access', v_antes, 'acesso_ok_em', v_ok),
          jsonb_build_object('efeito', 'anotou_acesso', 'resposta_id', p_resposta, 'mensagem_id', m.id,
                             'site_access', v_dep, 'acesso_ok_em', p_agora, 'linha', v_linha),
          public._agenda_corta(v_txt, 400), 'o cliente disse o acesso', p_agora + cf.desfazer_validade)
  returning id into v_acao;
  return jsonb_build_object('ok', true, 'acao_id', v_acao, 'texto', public._agenda_corta(v_txt, 400));
end;
$function$;

comment on function public._agenda_cliente_anotar_acesso(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 5, P4): o acesso dito pelo cliente — uma linha nova no fim de service_orders.site_access ("Cliente (31/10): <até 300>"; o que havia fica igual, byte a byte), os_planejamento.acesso_ok_em = agora (a véspera deixa de perguntar por cliente_acesso_validade_dias) e a ação cliente (origem cliente; antes/depois do campo) "Anotei o acesso que o Flávio disse: …", com desfazivel_ate. O gatilho das datas não se mexe (site_access não é data). Interna (sem grant).';

-- Volta o pedido de dia do cliente (a ação cliente "replanejou"): o bem indisponível perde só o que a ação pôs; o "não
-- antes de" volta ao de antes se ainda é o que ela pôs. true = mudou algo.
create or replace function public._agenda_cliente_restaurar_pedido(p_acao uuid, p_agora timestamptz)
 returns boolean
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_a   public.agenda_acoes%rowtype;
  p     public.os_planejamento%rowtype;
  v_bem datemultirange;
  v_nao date;
  v_mot text;
begin
  select * into v_a from public.agenda_acoes where id = p_acao;
  select * into p from public.os_planejamento where service_order_id = v_a.service_order_id for update;
  if not found then
    return false;
  end if;
  v_bem := p.bem_indisponivel - coalesce(nullif(v_a.depois ->> 'tirado', '')::datemultirange, '{}'::datemultirange);
  if p.nao_antes_de is not distinct from (v_a.depois ->> 'nao_antes_de')::date then
    v_nao := (v_a.antes ->> 'nao_antes_de')::date;
    v_mot := v_a.antes ->> 'nao_antes_motivo';
  else
    v_nao := p.nao_antes_de;
    v_mot := p.nao_antes_motivo;
  end if;
  if v_bem = p.bem_indisponivel and v_nao is not distinct from p.nao_antes_de then
    return false;
  end if;
  update public.os_planejamento
     set bem_indisponivel = v_bem, nao_antes_de = v_nao, nao_antes_motivo = v_mot,
         historico = public._os_material_historico(p.historico, jsonb_build_object(
           'em', (p_agora at time zone 'America/Sao_Paulo')::date, 'autor', null, 'trecho', 'desfeito o pedido do cliente',
           'antes', jsonb_build_object('bem_indisponivel', p.bem_indisponivel::text, 'nao_antes_de', p.nao_antes_de),
           'depois', jsonb_build_object('bem_indisponivel', v_bem::text, 'nao_antes_de', v_nao))),
         atualizado_em = p_agora
   where service_order_id = v_a.service_order_id;
  return true;
end;
$function$;

comment on function public._agenda_cliente_restaurar_pedido(uuid, timestamptz) is
  'Agenda de Produção (Fase 5, P4): volta o pedido de dia do cliente de uma ação cliente (efeito replanejou) — o bem indisponível perde só os dias que ela pôs (depois.tirado) e o "não antes de" volta ao de antes se ainda é o dela; o histórico ganha a linha. true = mudou algo. Interna (sem grant).';

-- O *desfaz* do que a resposta do cliente mudou (a ação com depois.resposta_id): a confirmação (as alocações que ela fixou
-- voltam a publicada, como estavam — cancela-se a fixada e cria-se a publicada igual, o rastro fica — e o client_confirmed_*
-- volta, se ninguém confirmou de novo), o pedido de dia (o planejamento volta e o replano é desfeito; o que não volta é
-- replanejado) e o acesso (o campo volta, só se ainda é o que ela escreveu: "O acesso da OS mudou depois; confira na
-- tela."). O opt-out não se desfaz. Chamada só por agenda_desfazer (o plano já travado).
create or replace function public._agenda_desfazer_cliente(p_acao uuid, p_autor uuid, p_via text, p_hoje date,
                                                           p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_a     public.agenda_acoes%rowtype;
  v_os    uuid;
  v_nome  text;
  v_ef    text;
  v_x     record;
  v_id    uuid;
  v_novas uuid[] := '{}';
  v_canc  uuid[] := '{}';
  v_r     jsonb;
  v_falha boolean := false;
  v_n     int := 0;
  v_sa    text;
  v_novo  date;
  v_txt   text;
  v_acao  uuid;
begin
  select * into v_a from public.agenda_acoes where id = p_acao;
  v_os := v_a.service_order_id;
  v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                        from public.service_orders so join public.clients cl on cl.id = so.client_id where so.id = v_os), 'cliente');
  v_ef := v_a.depois ->> 'efeito';
  if v_ef = 'opt_out' then
    return jsonb_build_object('ok', false,
      'texto', format('O pedido do %s para não receber mensagens não se desfaz por aqui: só ele pode pedir para voltar.', v_nome));
  end if;
  if v_ef is null or v_ef not in ('confirmou', 'replanejou', 'anotou_acesso') or v_a.desfazivel_ate is null then
    return jsonb_build_object('ok', false, 'texto', 'Essa resposta do cliente não mudou nada para desfazer.');
  end if;
  if p_agora > v_a.desfazivel_ate then
    return jsonb_build_object('ok', false,
      'texto', format('Não dá mais para desfazer o %s: passou o prazo. Se quiser mudar, me diga o dia.', v_nome));
  end if;

  if v_ef = 'confirmou' then
    if exists (select 1 from public.agenda_alocacoes a
                where a.id in (select x::uuid from jsonb_array_elements_text(coalesce(v_a.depois -> 'alocacoes', '[]'::jsonb)) x)
                  and a.estado = 'fixada' and (lower(a.periodo) <= p_agora or a.resultado is not null)) then
      return jsonb_build_object('ok', false,
        'texto', format('Não dá para desfazer: já começou o dia que o %s confirmou.', v_nome));
    end if;
    for v_x in select a.* from public.agenda_alocacoes a
                where a.id in (select x::uuid from jsonb_array_elements_text(coalesce(v_a.depois -> 'alocacoes', '[]'::jsonb)) x)
                  and a.estado = 'fixada' and a.fixado_por = 'cliente_confirmou'
                order by a.dia, a.turno = 'tarde', a.payee_id, a.id loop
      perform set_config('agenda.mexe_fixado', 'on', true);
      update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where id = v_x.id;
      perform set_config('agenda.mexe_fixado', 'off', true);
      insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, substitui_id,
                                           fixado_por, reserva_de, condicao, condicao_tipo, condicao_ate, motivos)
      values (v_x.service_order_id, v_x.payee_id, v_x.dia, v_x.turno, v_x.presenca, v_x.tipo, 'publicada', v_x.origem, v_x.id,
              null, v_x.reserva_de, v_x.condicao, v_x.condicao_tipo, v_x.condicao_ate, v_x.motivos)
      returning id into v_id;
      v_novas := v_novas || v_id;
      v_canc := v_canc || v_x.id;
    end loop;
    update public.service_orders
       set client_confirmed_at = (v_a.antes ->> 'client_confirmed_at')::timestamptz,
           client_confirmed_for = (v_a.antes ->> 'client_confirmed_for')::timestamptz
     where id = v_os and client_confirmed_for is not distinct from (v_a.depois ->> 'client_confirmed_for')::timestamptz;
    v_txt := format('Desfeito: a confirmação do %s (%s) sai; o dia continua no plano, sem fixar.', v_nome,
                    coalesce(public._dia_curto((v_a.depois ->> 'dia')::date), 'o dia'));
  elsif v_ef = 'replanejou' then
    perform public._agenda_cliente_restaurar_pedido(v_a.id, p_agora);
    -- o replano que o pedido causou volta (cada ação dele, pelo desfazer de sempre); o que não voltar é replanejado
    perform set_config('agenda.desfazer_cliente', 'on', true);
    for v_id in select x::uuid from jsonb_array_elements_text(coalesce(v_a.depois -> 'replano_acoes', '[]'::jsonb)) x loop
      if exists (select 1 from public.agenda_acoes e where e.id = v_id and e.executada and e.desfeita_em is null) then
        v_r := public.agenda_desfazer(v_id, p_autor, p_via, p_hoje, p_agora);
        if coalesce((v_r ->> 'ok')::boolean, false) then
          v_n := v_n + 1;
        else
          v_falha := true;
        end if;
      end if;
    end loop;
    perform set_config('agenda.desfazer_cliente', '', true);
    if v_falha or v_n = 0 then
      perform public.agenda_replanejar(array[v_os], 'desfeito o pedido do cliente', 'vigia', p_hoje, p_agora, p_autor);
    end if;
    v_novo := (public._agenda_plano_da_os(v_os, p_hoje) ->> 'proximo_dia')::date;
    v_txt := format('Desfeito: o pedido do %s sai; %s.', v_nome,
                    case when v_novo is not null then 'o serviço fica para ' || public._dia_curto(v_novo)
                         else 'o serviço fica sem dia no plano por enquanto' end);
  else
    select so.site_access into v_sa from public.service_orders so where so.id = v_os for update;
    if v_sa is distinct from (v_a.depois ->> 'site_access') then
      return jsonb_build_object('ok', false, 'texto', 'O acesso da OS mudou depois; confira na tela.');
    end if;
    update public.service_orders set site_access = v_a.antes ->> 'site_access' where id = v_os;
    update public.os_planejamento set acesso_ok_em = (v_a.antes ->> 'acesso_ok_em')::timestamptz, atualizado_em = p_agora
     where service_order_id = v_os and acesso_ok_em is not distinct from (v_a.depois ->> 'acesso_ok_em')::timestamptz;
    v_txt := format('Desfeito: o acesso que o %s disse saiu da OS.', v_nome);
  end if;

  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, critica, versao_depois,
                                   alocacoes_criadas, alocacoes_canceladas, antes, depois, texto, autor, desfaz_a)
  values (clock_timestamp(), p_hoje, true, case when p_via in ('motor', 'vigia') then p_via else 'dono' end, 'desfazer', v_os,
          v_a.os_ids, false, (public._agenda_cfg()).versao_plano, v_novas, v_canc,
          jsonb_build_object('acao', v_a.id), jsonb_build_object('alocacoes', to_jsonb(v_novas), 'efeito', v_ef),
          public._agenda_corta(v_txt, 400), p_autor, v_a.id)
  returning id into v_acao;
  update public.agenda_alocacoes set acao_id = v_acao where id = any (v_novas);
  update public.agenda_acoes set desfeita_em = p_agora, desfeita_por = p_autor, desfeita_pela = v_acao where id = v_a.id;
  return jsonb_build_object('ok', true, 'texto', public._agenda_corta(v_txt, 400), 'acao_id', v_acao,
                            'recriadas', to_jsonb(v_novas), 'canceladas', to_jsonb(v_canc));
end;
$function$;

comment on function public._agenda_desfazer_cliente(uuid, uuid, text, date, timestamptz) is
  'Agenda de Produção (Fase 5, P4): o *desfaz* do que a resposta do cliente mudou (ação com depois.resposta_id; agenda_desfazer a chama, com o plano travado). confirmou: as alocações que ela fixou (ainda fixadas por cliente_confirmou e sem começar) voltam a publicada — cancela-se a fixada (agenda.mexe_fixado) e cria-se a publicada igual (substitui_id) — e client_confirmed_* volta ao antes se ainda é o dela. replanejou: o planejamento volta (_agenda_cliente_restaurar_pedido), as ações do replano são desfeitas (agenda_desfazer, com agenda.desfazer_cliente ligado para o bloco do fim não repetir) e, se alguma não voltar, a OS é replanejada. anotou_acesso: site_access e acesso_ok_em voltam, só se o campo ainda é o que ela escreveu ("O acesso da OS mudou depois; confira na tela."). opt_out e o que não mudou nada: recusa. A ação desfazer (desfaz_a) e desfeita_* na original. Interna (sem grant).';

-- ── 3. A resposta do cliente (o webhook chama; a agenda decide) ─────────────────────────────────────────

create or replace function public.agenda_resposta_do_cliente(p_phone text, p_body text, p_message_id uuid, p_tipo_msg text,
                                                             p_intencao text, p_expressao text,
                                                             p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf        public.agenda_config := public._agenda_cfg();
  c_pergunta_dias constant interval := interval '7 days';   -- spec §3.2: a cliente_resposta some em 7 dias
  -- os tipos que esperam resposta (spec §5.4); os que propõem um dia (o pedido de outro dia só vale neles)
  c_esperam constant text[] := array['confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia',
                                     'pode_atrasar', 'pronto', 'pronto_lembrete', 'pos_servico'];
  c_do_dia  constant text[] := array['confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia'];
  v_hoje    date;
  v_modo    text;
  v_tipo    text;
  v_trecho  text;
  v_cli     uuid[];
  m         public.agenda_cliente_mensagens%rowtype;
  v_n       int;
  v_r       public.agenda_cliente_respostas%rowtype;
  v_rid     uuid := gen_random_uuid();
  v_int     text;
  v_expr    text;
  v_data    jsonb;
  v_nome    text;
  v_dia     date;
  v_ref     text;
  v_do_dia  boolean;
  v_efeito  text;
  v_o_que   text;
  v_texto   text;
  v_x       jsonb;
  v_acao    uuid;
  v_perg    uuid;
  v_acorde  boolean := false;
  v_de      date;
  v_ate     date;
  v_id      uuid;
  v_k       int := 0;
  v_estado  text;
  v_msg     text;
begin
  if p_agora is null then
    return jsonb_build_object('consumiu', false);
  end if;
  -- desligado: nada lê (o webhook segue como sempre)
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('consumiu', false, 'modo', 'desligado');
  end if;
  v_tipo := case when p_tipo_msg in ('text', 'audio', 'image', 'document', 'video') then p_tipo_msg else 'outro' end;
  v_trecho := nullif(left(btrim(coalesce(p_body, '')), 500), '');
  if v_tipo = 'text' and v_trecho is null then
    return jsonb_build_object('consumiu', false);
  end if;
  v_hoje := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_modo := case when cf.modo_cliente = 'ligado' then 'ligado' else 'sombra' end;

  -- quem é (o dono, a equipe e quem recebe diária nunca são cliente)
  v_cli := public._agenda_clientes_do_telefone(p_phone, p_agora);
  if cardinality(v_cli) = 0 then
    return jsonb_build_object('consumiu', false);
  end if;
  -- a mesma mensagem dele de novo: nada muda
  if p_message_id is not null then
    select * into v_r from public.agenda_cliente_respostas r where r.whatsapp_message_id = p_message_id;
    if found then
      return jsonb_build_object('consumiu', v_r.modo = 'ligado', 'efeito', v_r.efeito, 'repetida', true, 'resposta_id', v_r.id);
    end if;
  end if;

  -- a que mensagem ele responde: a última da agenda mandada a ele (em teste, a que teria saído), dos tipos que esperam
  -- resposta, dentro de cliente_resposta_validade, ainda sem resposta. Sem ela, a agenda não lê: é conversa.
  select count(distinct x.service_order_id)::int into v_n
    from public.agenda_cliente_mensagens x
   where x.client_id = any (v_cli) and x.tipo = any (c_esperam)
     and ((x.modo = 'ligado' and x.estado in ('enviada', 'sem_resposta')
           and x.enviada_em <= p_agora and x.enviada_em > p_agora - cf.cliente_resposta_validade)
          or (v_modo = 'sombra' and x.modo = 'sombra' and x.estado = 'registrada'
              and x.enviar_em <= p_agora and x.enviar_em > p_agora - cf.cliente_resposta_validade));
  select x.* into m
    from public.agenda_cliente_mensagens x
   where x.client_id = any (v_cli) and x.tipo = any (c_esperam)
     and ((x.modo = 'ligado' and x.estado in ('enviada', 'sem_resposta')
           and x.enviada_em <= p_agora and x.enviada_em > p_agora - cf.cliente_resposta_validade)
          or (v_modo = 'sombra' and x.modo = 'sombra' and x.estado = 'registrada'
              and x.enviar_em <= p_agora and x.enviar_em > p_agora - cf.cliente_resposta_validade))
   order by coalesce(x.enviada_em, x.enviar_em) desc, x.criada_em desc, x.id
   limit 1;
  if m.id is null then
    return jsonb_build_object('consumiu', false, 'motivo', 'sem_mensagem');
  end if;

  -- a intenção: o áudio e a mídia antes de tudo (nunca confirmam); o SIM curto pela regra única de 30/09; o resto como o
  -- leitor do webhook classificou (sem IA)
  v_int := case when v_tipo = 'audio' then 'audio'
                when v_tipo <> 'text' then 'outro'
                when public._e_concordancia(p_body) then 'confirma'
                when p_intencao in ('remarcar', 'falta', 'data', 'acesso', 'opt_out', 'disputa', 'negociacao', 'pergunta',
                                    'acordo', 'outro') then p_intencao
                else 'outro' end;
  v_expr := case when v_int in ('data', 'remarcar', 'falta') then nullif(left(btrim(coalesce(p_expressao, '')), 60), '') end;
  v_dia := coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo);
  v_data := case when v_expr is not null then public._agenda_cliente_data_da_resposta(v_expr, v_hoje, v_dia) end;
  v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                        from public.clients cl where cl.id = m.client_id), 'cliente');
  v_ref := public._agenda_cliente_a_mensagem(m.tipo, m.variante, v_dia);
  v_do_dia := m.tipo = any (c_do_dia) or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado');

  -- em teste: só registra o que faria (a intenção); nada muda e os fluxos de hoje seguem iguais
  if v_modo = 'sombra' then
    insert into public.agenda_cliente_respostas (id, client_id, service_order_id, mensagem_id, whatsapp_message_id, recebida_em,
                                                 tipo_msg, texto, intencao, expressao, data_dita, efeito, modo)
    values (v_rid, m.client_id, m.service_order_id, m.id, p_message_id, p_agora, v_tipo, v_trecho, v_int, v_expr,
            (v_data ->> 'de')::date, 'sombra', 'sombra')
    on conflict (whatsapp_message_id) do nothing;
    return jsonb_build_object('consumiu', false, 'modo', 'sombra', 'efeito', 'sombra', 'intencao', v_int, 'resposta_id', v_rid);
  end if;

  -- ligado: a resposta fica registrada primeiro (uma por mensagem do WhatsApp); o efeito vem depois
  insert into public.agenda_cliente_respostas (id, client_id, service_order_id, mensagem_id, whatsapp_message_id, recebida_em,
                                               tipo_msg, texto, intencao, expressao, data_dita, efeito, modo)
  values (v_rid, m.client_id, m.service_order_id, case when v_n > 1 or cardinality(v_cli) > 1 then null else m.id end,
          p_message_id, p_agora, v_tipo, v_trecho, v_int, v_expr, (v_data ->> 'de')::date, 'nada', 'ligado')
  on conflict (whatsapp_message_id) do nothing;
  if not found then
    return jsonb_build_object('consumiu', true, 'repetida', true);
  end if;
  perform set_config('agenda.hoje', v_hoje::text, true);

  begin
    if v_n > 1 or cardinality(v_cli) > 1 then
      -- duas OS (ou dois clientes no número) esperando: não adivinha
      v_efeito := 'ambigua';
      v_texto := format('Chegou "%s" do número do %s, mas %s: não sei a qual mensagem é. Não respondi nada; é com você.',
                        public._agenda_corta(coalesce(v_trecho, 'uma mensagem que não é texto'), 120), v_nome,
                        case when cardinality(v_cli) > 1 then format('o número é de %s clientes', cardinality(v_cli))
                             else format('há %s serviços esperando resposta dele', v_n) end);
    elsif v_int = 'audio' then
      -- o áudio NUNCA confirma: vai ao dono
      v_efeito := 'ao_dono';
      v_texto := format('O %s respondeu por áudio %s; a transcrição está na conversa. Não respondi nada; é com você.', v_nome, v_ref);
    elsif v_tipo <> 'text' then
      v_efeito := 'ao_dono';
      v_texto := format('O %s respondeu com %s %s. Não respondi nada; é com você.', v_nome,
                        case v_tipo when 'image' then 'uma foto' when 'video' then 'um vídeo' when 'document' then 'um documento'
                                    else 'uma mensagem que não é texto' end, v_ref);
    elsif v_int = 'confirma' then
      if m.tipo in ('confirmar', 'material_chegou', 'nova_data', 'mudanca_no_dia')
         or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado') then
        -- (decisão do P4) o SIM ao aviso remarcado confirma o dia novo, como o M1: o texto dele pede "Responda SIM"
        v_x := public._agenda_cliente_confirmar_dia(m.id, v_rid, v_trecho, v_hoje, p_agora);
        if coalesce((v_x ->> 'ok')::boolean, false) then
          v_efeito := 'confirmou';
          v_acao := (v_x ->> 'acao_id')::uuid;
          v_texto := v_x ->> 'texto';
        else
          v_efeito := 'ao_dono';
          v_o_que := v_x ->> 'o_que';
        end if;
      elsif m.tipo in ('vespera', 'acesso') then
        v_efeito := 'confirmou';   -- só registra (o client_confirmed_* é do SIM ao M1/M3/M7/M10)
      elsif m.tipo = 'pode_atrasar' then
        v_efeito := 'ciencia';
      elsif m.tipo in ('pronto', 'pronto_lembrete') then
        v_efeito := 'ao_dono';
        v_o_que := 'combine a entrega com ele';
      else
        v_efeito := 'nada';
      end if;
    elsif v_int = 'opt_out' then
      -- honrado calado (d8): nada mais sai a ele; o dono fica sabendo pela ação
      update public.clients set opt_out_whatsapp = true where id = m.client_id and not coalesce(opt_out_whatsapp, false);
      for v_id in select x.id from public.agenda_cliente_mensagens x
                   where x.client_id = m.client_id and x.estado in ('registrada', 'aguardando_dono', 'enfileirada')
                   order by x.enviar_em, x.id loop
        if public._agenda_cliente_cancelar(v_id, 'opt_out', 'O cliente pediu para não receber mensagens.') then
          v_k := v_k + 1;
        end if;
      end loop;
      v_efeito := 'opt_out';
      v_texto := format('O %s pediu para não receber mais mensagens: não mando mais nada a ele.', v_nome);
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto, motivo)
      values (clock_timestamp(), v_hoje, true, 'cliente', 'cliente', m.service_order_id, array[m.service_order_id], '{}'::jsonb,
              jsonb_build_object('efeito', 'opt_out', 'resposta_id', v_rid, 'mensagem_id', m.id, 'canceladas', v_k),
              v_texto, 'o cliente pediu para parar')
      returning id into v_acao;
    elsif v_int in ('disputa', 'negociacao', 'acordo', 'pergunta') then
      v_efeito := 'ao_dono';
      v_acorde := v_int = 'disputa';   -- a reclamação vai na hora
      v_o_que := case v_int when 'disputa' then 'parece reclamação'
                            when 'negociacao' then 'é sobre preço ou pagamento'
                            when 'acordo' then 'parece que concorda, mas não é um SIM claro'
                            else 'é uma pergunta' end;
    elsif v_int in ('data', 'remarcar', 'falta') and not v_do_dia then
      v_efeito := 'ao_dono';
      v_o_que := case when m.tipo in ('pronto', 'pronto_lembrete') then 'falou de dia: combine a entrega com ele'
                      else 'falou de outro dia' end;
    elsif v_int in ('data', 'remarcar', 'falta') and cf.modo_proposta <> 'ligado' then
      v_efeito := 'ao_dono';
      v_o_que := 'pediu outro dia, mas a agenda automática não está ligada: remarque você';
    elsif v_int = 'data' then
      v_de := (v_data ->> 'de')::date;
      v_ate := (v_data ->> 'ate')::date;
      if v_de is null then
        v_efeito := 'ao_dono';
        v_o_que := 'não entendi o dia que ele pediu';
      elsif v_de <= v_hoje then
        v_efeito := 'ao_dono';
        v_o_que := 'o dia que ele pediu já passou ou é hoje';
      elsif v_dia is not null and v_de = v_dia then
        v_efeito := 'ao_dono';
        v_o_que := 'falou do mesmo dia combinado';
      elsif v_dia is not null and v_de < v_dia then
        -- (decisão do P4) mais cedo que o combinado: o "não antes de" não adianta nada; é o dono que vê se dá
        v_efeito := 'ao_dono';
        v_o_que := format('pediu um dia antes do combinado (%s)', public._dia_curto(v_de));
      else
        v_x := public._agenda_cliente_pedido_de_dia(m.id, v_rid,
                 case when v_dia is not null then daterange(v_dia, v_dia, '[]') end, v_de,
                 format('O %s pediu %s', v_nome,
                        case when v_ate > v_de then 'a partir de ' || public._dia_curto(v_de) else public._dia_curto(v_de) end),
                 v_trecho, v_hoje, p_agora);
        v_efeito := 'replanejou';
        v_acao := (v_x ->> 'acao_id')::uuid;
        v_texto := v_x ->> 'texto';
      end if;
    elsif v_int in ('remarcar', 'falta') then
      -- o dia recusado: o que ele disse (convertido pelo banco), senão o dia da mensagem
      v_de := (v_data ->> 'de')::date;
      v_ate := (v_data ->> 'ate')::date;
      if v_de is null or v_ate < v_hoje then
        v_de := v_dia;
        v_ate := v_dia;
      end if;
      v_de := greatest(v_de, v_hoje);
      if v_de is null or v_ate < v_de then
        v_efeito := 'ao_dono';
        v_o_que := 'pediu outro dia';
      elsif not (v_dia between v_de and v_ate)
            and not exists (select 1 from public.agenda_alocacoes a
                             where a.service_order_id = m.service_order_id and a.estado in ('publicada', 'fixada')
                               and a.tipo <> 'reserva' and a.dia between v_de and v_ate) then
        -- (decisão do P4) o dia recusado não é dia do serviço ("não dá amanhã" no sábado, com o serviço na terça): não
        -- adivinho de qual dia ele fala
        v_efeito := 'ao_dono';
        v_o_que := format('disse que não dá %s, mas não é dia do serviço',
                          case when v_ate > v_de then public._dia_curto(v_de) || ' a ' || public._dia_curto(v_ate)
                               else public._dia_curto(v_de) end);
      else
        v_x := public._agenda_cliente_pedido_de_dia(m.id, v_rid, daterange(v_de, v_ate, '[]'), null,
                 format('O %s pediu outro dia (%s não dá)', v_nome,
                        case when v_ate > v_de then public._dia_curto(v_de) || ' a ' || public._dia_curto(v_ate)
                             else public._dia_curto(v_de) end),
                 v_trecho, v_hoje, p_agora);
        v_efeito := 'replanejou';
        v_acao := (v_x ->> 'acao_id')::uuid;
        v_texto := v_x ->> 'texto';
      end if;
    elsif v_int = 'acesso' and (v_do_dia or m.tipo = 'pode_atrasar') then
      v_x := public._agenda_cliente_anotar_acesso(m.id, v_rid, v_trecho, v_hoje, p_agora);
      v_efeito := 'anotou_acesso';
      v_acao := (v_x ->> 'acao_id')::uuid;
      v_texto := v_x ->> 'texto';
    else
      v_efeito := 'ao_dono';
      v_o_que := case when v_int = 'acesso' then 'falou do acesso' else 'não entendi o que ele quer' end;
    end if;
  exception when others then
    -- o efeito que falha não derruba o webhook: a resposta vai ao dono e o erro fica consultável
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    perform public.log_app_error('db', 'agenda: a resposta do cliente falhou: ' || v_msg, 'agenda', 'cliente:resposta', 'error',
                                 jsonb_build_object('mensagem', m.id, 'resposta', v_rid, 'intencao', v_int, 'sqlstate', v_estado));
    v_efeito := 'ao_dono';
    v_acao := null;
    v_acorde := false;
    v_o_que := 'não consegui ler a resposta sozinho';
    v_texto := null;
  end;

  -- ao dono: a pergunta cliente_resposta (sem opções; some em 7 dias), e o acorde na hora quando é reclamação
  if v_efeito in ('ao_dono', 'ambigua') then
    v_texto := coalesce(v_texto, format('O %s respondeu "%s" %s: %s. Não respondi nada; é com você.', v_nome,
                                        public._agenda_corta(coalesce(v_trecho, ''), 120), v_ref, v_o_que));
    v_perg := public._agenda_cliente_perguntar('cliente_resposta', 'cliente_resposta:' || v_rid, m.service_order_id, v_dia,
                                               case when v_do_dia then v_dia end, v_texto, 'ligado', p_agora,
                                               p_agora + c_pergunta_dias);
    if v_acorde then
      v_acao := public._agenda_cliente_acorde(m.service_order_id, 'cliente_resposta:' || v_rid, v_texto, v_hoje, v_hoje, v_perg);
    end if;
  end if;

  -- a mensagem respondida (antes das 48 h o "não respondeu" não a pega; depois, a pergunta dele se resolve)
  if v_efeito <> 'ambigua' then
    update public.agenda_cliente_mensagens set estado = 'respondida', resposta_id = v_rid
     where id = m.id and estado in ('enviada', 'sem_resposta');
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = left(format('O %s respondeu.', v_nome), 200)
     where chave = 'cliente_resposta:sem_resposta:' || m.id and estado = 'aberta';
  end if;
  update public.agenda_cliente_respostas
     set efeito = v_efeito, acao_id = v_acao, pergunta_id = v_perg, data_dita = coalesce((v_data ->> 'de')::date, data_dita)
   where id = v_rid;
  return jsonb_build_object('consumiu', true, 'modo', 'ligado', 'efeito', v_efeito, 'intencao', v_int, 'texto', v_texto,
                            'resposta_id', v_rid, 'mensagem_id', m.id, 'acao_id', v_acao, 'pergunta_id', v_perg);
end;
$function$;

comment on function public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz) is
  'Agenda de Produção (Fase 5, P4): a mensagem do cliente que chega pelo WhatsApp (o webhook chama depois da equipe e antes da confirmação de 30/09 e da conferência do recibo: o "ok" tem um dono só). modo_cliente desligado, número de ninguém (ou do dono, da equipe, de quem recebe diária), a mesma mensagem de novo ou sem mensagem da agenda esperando resposta (a última dos tipos que esperam, enviada dentro de cliente_resposta_validade e ainda sem resposta; em teste, a que teria saído) = consumiu false. Em teste: registra a resposta (efeito sombra, com a intenção) e consumiu false. Ligado, a 1ª que vale: duas OS ou dois clientes no número = ambígua (ao dono); áudio e mídia ao dono (o áudio NUNCA confirma); o SIM curto (_e_concordancia) confirma o M1/M3/M7/M10 e o M6 remarcado (_agenda_cliente_confirmar_dia: fixa o dia, com *desfaz*), registra a véspera e o acesso, é ciência no aviso de atraso, vai ao dono no "ficou pronto" e não faz nada no pós-serviço; opt-out = as vivas recusadas (opt_out) e o cadastro marcado, calado; reclamação (na hora, por acorde), negociação, acordo e pergunta ao dono; o dia pedido (data) e o recusado (remarcar, falta) — só nas mensagens que propõem um dia e com modo_proposta ligado — viram o "não antes de" e o bem indisponível com o replano (_agenda_cliente_pedido_de_dia, com *desfaz*; o dia combinado em até 1 dia útil = acorde); o dia passado, de hoje, o mesmo ou mais cedo que o combinado vai ao dono; o acesso dito vai para o campo da OS (_agenda_cliente_anotar_acesso, com *desfaz*); o resto ao dono. Ao dono = a pergunta cliente_resposta:<resposta> (some em 7 dias). A mensagem fica respondida (resposta_id) e a pergunta do "não respondeu" dela se resolve. O efeito que falha vai ao dono e a app_error_logs (cliente:resposta). {consumiu, modo, efeito, intencao, texto, resposta_id, mensagem_id, acao_id, pergunta_id}. Só service_role.';

-- ── 4. A função recriada (o corpo da definição mais nova; as mudanças marcadas "-- FASE 5:") ────────────
-- agenda_desfazer: corpo de 20261027100400 (a mais nova, com os blocos das Fases 3 e 4). Fora dos blocos "-- FASE 5:"
-- nenhuma linha muda (o A10 confere). A casca não muda.

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
  'Agenda de Produção (Fase 2, P2): desfaz uma ação executada — recusa (nada muda) se foi sombra, já foi desfeita, não é desfazível (pedido do dono pela tela ou aprovação), passou o desfazivel_ate, algum meio-dia criado já começou ou tem resultado, ou recriar o que saiu bateria em quem já está no lugar ("Não dá para desfazer: o Roberto já está no Giancarlo…"). Faz: o que ela criou → cancelada (desfeito); o que ela tirou volta igual (substitui_id, mesmo estado/fixado); o status pela porta (via desfazer; o que começou não regride); o espelho; nova ação tipo desfazer (desfaz_a) e a original ganha desfeita_*. Desfazer uma decisão crítica cria a pergunta de novo ("A decisão sobre o Nelson volta a ficar com você."). Fase 3: concluir e entregar vão a _agenda_desfazer_marco (as cobranças da conclusão, a saída, a comissão de vendedor e a entrega); a diária da agenda a _agenda_desfazer_diaria (apaga o turno que ela criou, com o acerto aberto); desfazer o replano da ausência da equipe tira a ausência do dia (agenda_disponibilidade substituída). Fase 4 (P4): a ação material (a previsão pela mensagem do fornecedor, a chegada pela nota) vai a _agenda_desfazer_material (as linhas voltam se ninguém mexeu nelas depois). Fase 5 (P4): o que a resposta do cliente mudou (a ação fixar/cliente de origem cliente com depois.resposta_id: a confirmação, o pedido de dia, o acesso) vai a _agenda_desfazer_cliente; a outra ação cliente (a mensagem enviada, o acorde, a decisão do aviso) não se desfaz ("Mensagem enviada não se desmanda."); desfazer direto o replano que o pedido de dia causou também tira o pedido (_agenda_cliente_restaurar_pedido) e deixa a ação do cliente desfeita.';

-- ── 5. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- A resposta do cliente: só service_role (o whatsapp-webhook). Nunca anon, nunca authenticated.
revoke all on function public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz) to service_role;

-- Os efeitos, quem é o cliente, a data e o desfazer do cliente: ninguém de fora (nem o service_role). Só a resposta e
-- agenda_desfazer (security definer) os chamam.
revoke all on function
  public._agenda_clientes_do_telefone(text, timestamptz),
  public._agenda_cliente_data_da_resposta(text, date, date),
  public._agenda_cliente_confirmar_dia(uuid, uuid, text, date, timestamptz),
  public._agenda_cliente_pedido_de_dia(uuid, uuid, daterange, date, text, text, date, timestamptz),
  public._agenda_cliente_anotar_acesso(uuid, uuid, text, date, timestamptz),
  public._agenda_cliente_restaurar_pedido(uuid, timestamptz),
  public._agenda_desfazer_cliente(uuid, uuid, text, date, timestamptz)
  from public, anon, authenticated, service_role;

-- O texto da mensagem para o dono (leitura, STABLE, invoker): authenticated (o foco do P5) e
-- service_role; nunca anon.
revoke all on function public._agenda_cliente_a_mensagem(text, text, date) from public, anon;
grant execute on function public._agenda_cliente_a_mensagem(text, text, date) to authenticated, service_role;

-- A recriada mantém a porta dela (create or replace não muda a ACL; repetida aqui para a migration se bastar).
revoke all on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_desfazer(uuid, uuid, text, date, timestamptz) to service_role;
