-- Agenda de Produção, Fase 5 ("Mensagens ao cliente"), correção C1 da revisão: a resposta do cliente, o botão "Pedir
-- confirmação" e o envio. Fontes: scratchpad agenda-pesquisa/revisao-fase5-correcao.md (itens 2, 5, 9, 10, 11, 13, 14, 16,
-- 17, 18, 19, 20 e 21), revisao-fase5-regressao.md (A1, M1 e B1) e decisoes-correcao-fase5.md (seção C1). Depende de
-- 20261028100000 a 100600.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (1 coluna nova em agenda_config; 4 funções novas, 1 gatilho novo; 9 funções recriadas)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/c1f5/montar-migration.mjs: as partes escritas à mão
-- e os corpos das funções recriadas copiados da definição MAIS NOVA de cada uma (conferido com grep em 27/10), com cada
-- troca "-- CORREÇÃO FASE 5:" conferida (fora dos blocos nenhuma linha muda, menos as 8 linhas declaradas de
-- _pedir_confirmacao: o now() que vira p_agora e o nome da função):
--   _agenda_cliente_revalidar, _agenda_cliente_enfileirar ← 20261028100200 (P2)
--   pedir_confirmacao_do_agendamento                    ← 20261028100200 (P2): o corpo vai para _pedir_confirmacao
--   _agenda_cliente_confirmar, _agenda_cliente_decidir  ← 20261028100300 (P3)
--   agenda_resposta_do_cliente, _agenda_cliente_data_da_resposta ← 20261028100400 (P4)
--
-- POR QUE: a revisão achou o "sim" de um cliente engolido pela agenda (A1: o pedido do botão antigo nunca fica confirmado),
-- o PARAR prometido no pós-serviço que só vale nas 72 h da mensagem, o botão que diz "registrado: sai amanhã" e de manhã a
-- mensagem é recusada calada (M1), o "dia 31" que vira 31/12 e remarca para janeiro, e o teste do botão que depende do
-- relógio (B1).
--
-- O QUE MUDA:
--   1. agenda_resposta_do_cliente: (A1 = item 11) a agenda só toma a resposta quando a última mensagem que a HBR mandou
--      àquele número é a dela — outra depois dela (o botão antigo: client_confirmation_requested_at mais novo; o dono ou
--      outra rotina falando com o cliente: whatsapp_messages outbound que não é o eco da agenda) = {consumiu:false,
--      motivo:'outra_conversa'} e os leitores de antes seguem; (item 2) o PARAR (e os outros opt-outs) vale para qualquer
--      cliente com mensagem da agenda ENVIADA nos últimos 30 dias, mesmo fora da validade, já respondida ou com o número
--      ambíguo; (item 16) o acesso com negação ("não sei", "não tenho", "ainda não") vai ao dono e não marca acesso_ok_em;
--      (item 17) falta/remarcar com um número de dia que o banco não entendeu ("volto dia 20") vai ao dono; (item 9) o dia
--      pedido (ou o fim do recusado) mais de cliente_pedido_max_du dias úteis depois do combinado vai ao dono, sem replano.
--   2. _agenda_cliente_data_da_resposta (item 9): "dia N" sem mês só vale no mês de hoje (N de hoje em diante) ou no
--      seguinte (N antes de hoje); o dia que não existe nesse mês ("dia 31" em novembro) = null (vai ao dono).
--   3. O botão "Pedir confirmação" (itens 5, 19 e 21; M1 e B1): pedir_confirmacao_do_agendamento vira a casca e chama
--      _pedir_confirmacao(p_os, p_autor, p_agora) com now() — a interna (sem grant) é a que o teste chama com a hora fixa.
--      Pela agenda: no clique, o opt-out, a conversa (d10), o telefone e o teto do dia em que a mensagem sairia viram o
--      erro na hora (dentro ou fora do horário); a confirmação do mesmo dia que a agenda já tem não fica "já está com a
--      agenda": esperando o dono, o clique a APROVA; já mandada, diz quando; indo sair sozinha, diz quando; recusada, uma 2ª
--      pelo botão (chave <dia>:botao). O caminho antigo (a mensagem ao cliente em teste ou a confirmação fora das ondas)
--      recusa fora do horário de mensagens ao cliente ("Fora do horário de mensagens ao cliente: peça amanhã a partir das
--      08:00."); com modo_cliente desligado, como em 30/09.
--   4. O aviso de "não saiu" (item 5c / M1): o gatilho novo trg_agenda_cliente_recusada abre a pergunta cliente_resposta
--      (chave cliente_resposta:nao_saiu:<mensagem>, 7 dias) quando uma mensagem em ligado que o DONO mandou mandar (o botão,
--      a preparada e aprovada, a da rodada aprovada pelo *manda cliente*) é recusada depois — na fila, no passo fila, na
--      trava da fila ou na saída (o worker). A recusa na hora da decisão (_agenda_cliente_decidir) já vai no texto da
--      resposta e não repete; a segurada não avisa.
--   5. _agenda_cliente_revalidar (item 13): o d10 (sem conversa no último ano) também na revalidação, e por isso no gatilho
--      da fila e no agenda_cliente_pode_sair.
--   6. _agenda_cliente_enfileirar (item 14): o choque de intervalo remarca a hora (_agenda_cliente_quando) em vez de recusar
--      para sempre; passou da validade = vencida. Só a trava da fila recusa por intervalo. O sem_conversa/sem_telefone que a
--      trava da fila devolve (item 13) vira o motivo da recusa.
--   7. _agenda_cliente_confirmar (item 20): o M1 do dia D não é registrado quando o botão antigo já pediu a confirmação
--      desse D (dentro de cliente_resposta_validade, sem resposta) ou o cliente já confirmou o D.
--   8. agenda_config.cliente_pedido_max_du (10 dias úteis; o DEFAULT é o único lugar do número).
--
-- O QUE NÃO MUDA: o corpus do leitor de hoje (classificarResposta) e o "PARAR" sozinho, que só o leitor do cliente
-- (classificarRespostaDoCliente) reconhece; os textos ao cliente; a rodada fora do passo confirmar; registrar_confirmacao_do_
-- cliente; com modo_cliente desligado, nada é lido, nada é registrado e o botão faz o que fazia em 30/09.
--
-- DINHEIRO: nada aqui cria, muda ou liga pagamento, cobrança ou orçamento.
--
-- DECISÕES (anotadas em notas-fase5.md, parte C1):
--   · A1: "outra conversa" = (a) um pedido do botão antigo (client_confirmation_requested_at de qualquer OS do cliente)
--     depois da mensagem da agenda, que não é o da própria agenda (o M1 pelo botão grava o pedido com a hora do envio); ou
--     (b) uma mensagem outbound ao número (8 dígitos) depois dela que não é o eco da agenda (o texto de uma mensagem dela ao
--     cliente, ou o id da linha agenda-cliente na fila). Em teste também: a sombra não registra o que não leria.
--   · O PARAR fora da mensagem que espera resposta marca o opt-out de todos os clientes do número que receberam mensagem da
--     agenda nos últimos 30 dias e cancela as vivas deles; a resposta é registrada (efeito opt_out) ligada à última mensagem
--     enviada, que não muda de estado.
--   · O teto do dia pedido também vale para o fim do dia recusado ("vou viajar até 20/12"): tirar semanas do plano é a mesma
--     remarcação longe.
--   · O aviso de "não saiu" vale para toda mensagem APROVADA pelo dono (origem botao, dono ou a da rodada que ele aprovou),
--     não só a do botão: o dono decidiu mandar e não pode ficar sem saber.
--   · O item 20 também pula o M1 quando o cliente já confirmou aquele dia (client_confirmed_for): seria pedir de novo o que
--     ele já disse.
--   · O agenda_data_dita do dono (o rascunho mostra a data antes do *grava*) e o do detector do fornecedor (a previsão entra
--     no "o que mudou" com *desfaz*, e o atraso longo vira pergunta crítica antes de chegar ao cliente) NÃO mudam: lá o "dia
--     31" que vira 31/12 aparece ao dono antes de ir a um terceiro. A correção é só da resposta do cliente.
--
-- ORDEM DE LIGAR: depois de 20261028100000 a 100600; ANTES do deploy do whatsapp-webhook novo (a revisão fora do !doCliente).
-- Sem esta migration, o webhook novo segue igual (a RPC da resposta e o botão têm os mesmos nomes).
--
-- PROVA: supabase/tests/agenda_fase5_correcao_resposta.sql (C1a–C1z) e os ajustes em agenda_fase5_envio.sql (E4f, E9d–E9f,
-- E9z) e agenda_fase5_base.sql (B1). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; depois de 20261028100000 a 100600):
--   npx supabase db query --linked -f supabase/migrations/20261028100700_agenda_fase5_correcao_resposta.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261028100700', 'agenda_fase5_correcao_resposta');"
--
-- DESFAZER: reaplicar as definições de 20261028100200 (revalidar, enfileirar, pedir_confirmacao_do_agendamento), 100300
-- (confirmar, decidir) e 100400 (agenda_resposta_do_cliente, data_da_resposta); drop trigger trg_agenda_cliente_recusada;
-- as funções novas e a coluna ficam (sem quem as chame, nada muda).
--
-- IDEMPOTENTE: add column if not exists, CHECK por nome em do $$, create or replace function, drop trigger if exists +
-- create, revoke/grant e comment.

-- ── 1. O parâmetro novo ─────────────────────────────────────────────────────────────────────────────────

alter table public.agenda_config
  add column if not exists cliente_pedido_max_du smallint not null default 10;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.agenda_config'::regclass and conname = 'agenda_config_cliente_pedido_max_du_check') then
    alter table public.agenda_config
      add constraint agenda_config_cliente_pedido_max_du_check check (cliente_pedido_max_du between 1 and 30);
  end if;
end
$$;

comment on column public.agenda_config.cliente_pedido_max_du is
  'Resposta do cliente: o dia que ele pede (ou o fim do que ele recusa) mais de N dias úteis depois do dia combinado não remarca sozinho — vai ao dono.';

-- ── 2. As funções novas ─────────────────────────────────────────────────────────────────────────────────

-- O motivo da recusa de uma mensagem ao cliente como o dono lê, depois de "não saiu: …". Sem nome nem pronome (o dono
-- sabe de quem é pela frase de antes); os números saem de agenda_config.
create or replace function public._agenda_cliente_motivo_texto(p_motivo text)
 returns text
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf public.agenda_config := public._agenda_cfg();
begin
  return case
    when p_motivo = 'sem_conversa'
      then format('o cliente não escreveu para a HBR nos últimos %s dias, e mensagem automática a quem não escreve arrisca o número',
                  cf.cliente_conversa_dias)
    when p_motivo = 'sem_telefone' then 'o cadastro do cliente está sem telefone válido (ou o número é de alguém da HBR)'
    when p_motivo = 'opt_out' then 'o cliente pediu para não receber WhatsApp'
    when p_motivo in ('teto_dia', 'teto_semana')
      then format('o cliente já recebeu as mensagens que cabem (no máximo %s por dia e %s por semana)', cf.cliente_dia_max,
                  cf.cliente_semana_max)
    when p_motivo = 'teto_total' then format('a agenda já mandou as %s mensagens do dia aos clientes', cf.cliente_total_dia_max)
    -- o motivo mesmo_tipo_<horas> (a lista fechada de recusa_motivo); as horas vêm de cliente_mesmo_tipo_horas
    when left(p_motivo, 10) = 'mesmo_tipo'
      then format('o cliente já recebeu uma mensagem do mesmo tipo nas últimas %s horas', cf.cliente_mesmo_tipo_horas)
    when p_motivo = 'material' then 'o material ainda não está todo na mão, e a data não é firme'
    when p_motivo in ('status', 'data_mudou', 'desatualizada') then 'a OS mudou antes de a mensagem sair'
    when p_motivo = 'passou_da_data' then 'a data que o cliente ouviu já passou'
    when p_motivo in ('domingo', 'feriado', 'janela', 'vencida')
      then 'passou da hora de a mensagem servir sem ela sair (o horário de mensagens ao cliente acabou)'
    when p_motivo = 'intervalo' then 'outra mensagem a cliente estava saindo na mesma hora'
    when p_motivo in ('modo', 'tipo_em_teste') then 'as mensagens ao cliente voltaram para teste'
    when p_motivo = 'texto' then 'o texto da mensagem não fecha'
    else coalesce(p_motivo, 'sem motivo') end;
end;
$function$;

comment on function public._agenda_cliente_motivo_texto(text) is
  'Agenda de Produção (Fase 5, correção C1): o motivo da recusa de uma mensagem ao cliente (recusa_motivo) como o dono lê, depois de "não saiu: …" — "o cliente não escreveu para a HBR nos últimos 365 dias…", "o cliente já recebeu as mensagens que cabem (no máximo 1 por dia e 3 por semana)", "a OS mudou antes de a mensagem sair"… Os números vêm de agenda_config. Interna (sem grant).';

-- (A1 = item 11) Depois de p_desde (a hora em que a mensagem da agenda saiu), a HBR falou com esse número por outro caminho?
-- (a) o botão antigo pediu a confirmação de alguma OS desses clientes depois (client_confirmation_requested_at), e não é o
-- pedido que a própria agenda gravou ao mandar o M1 pelo botão (a mesma hora do envio); (b) uma mensagem outbound ao número
-- (8 últimos dígitos) que não é o eco da agenda (o texto de uma mensagem dela a esses clientes, ou o id da linha
-- agenda-cliente da fila). true = a resposta que chega agora não é à agenda.
create or replace function public._agenda_cliente_outra_conversa(p_clientes uuid[], p_phone text, p_desde timestamptz,
                                                                 p_agora timestamptz)
 returns boolean
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  select p_desde is not null and (
    exists (select 1 from public.service_orders s
             where s.client_id = any (p_clientes)
               and s.client_confirmation_requested_at > p_desde and s.client_confirmation_requested_at <= p_agora
               and not exists (select 1 from public.agenda_cliente_mensagens x
                                where x.service_order_id = s.id and x.origem = 'botao'
                                  and x.enviada_em = s.client_confirmation_requested_at))
    or exists (select 1 from public.whatsapp_messages w
                where w.direction = 'outbound'
                  and public._agenda_chave_telefone(p_phone) is not null
                  and public._agenda_chave_telefone(w.phone_normalized) = public._agenda_chave_telefone(p_phone)
                  and w.occurred_at > p_desde and w.occurred_at <= p_agora
                  and not exists (select 1 from public.agenda_cliente_mensagens x
                                   where x.client_id = any (p_clientes) and x.enviada_em is not null
                                     and btrim(x.texto) = btrim(coalesce(w.body, '')))
                  and not exists (select 1 from public.whatsapp_send_queue q
                                   where q.source = 'agenda-cliente' and q.zapi_message_id is not null
                                     and q.zapi_message_id = w.wa_message_id)));
$function$;

comment on function public._agenda_cliente_outra_conversa(uuid[], text, timestamptz, timestamptz) is
  'Agenda de Produção (Fase 5, correção C1, A1): depois de p_desde (a saída da mensagem da agenda), a HBR falou com esse número por outro caminho — o botão antigo pediu a confirmação de alguma OS desses clientes (client_confirmation_requested_at; o pedido que o M1 pelo botão grava na hora do envio não conta), ou saiu uma mensagem outbound ao número (8 últimos dígitos) que não é o eco da agenda (o texto de uma mensagem dela, ou o id da linha agenda-cliente)? true = a resposta não é à agenda (agenda_resposta_do_cliente devolve consumiu false e os leitores de antes seguem). Interna (sem grant).';

-- (item 5c / M1) A mensagem que o dono mandou mandar (aprovada: o botão, a preparada e aprovada, a da rodada aprovada pelo
-- *manda cliente*) e que foi recusada DEPOIS (o passo fila, a trava da fila, a saída pelo worker) não fica calada: abre a
-- pergunta cliente_resposta ao dono, uma por mensagem, que some em 7 dias. A recusa na hora da decisão já vai no texto da
-- resposta (agenda.cliente_recusa_na_hora ligado por _agenda_cliente_decidir); a segurada não chega aqui (o WHEN). Nunca
-- lança: o erro vai a app_error_logs (agenda / cliente:nao_saiu).
create or replace function public._agenda_cliente_avisar_recusa()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  c_validade constant interval := interval '7 days';   -- spec §3.2: a cliente_resposta some em 7 dias
  v_agora timestamptz := now();
  v_nome  text;
  v_dia   date;
  v_o_que text;
  v_txt   text;
begin
  if coalesce(current_setting('agenda.cliente_recusa_na_hora', true), '') = 'on' then
    return null;
  end if;
  begin
    select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name)) into v_nome
      from public.clients cl where cl.id = new.client_id;
    v_dia := coalesce((new.base ->> 'dia_alvo')::date, new.dia_alvo);
    v_o_que := public._agenda_cliente_o_que(new.tipo, v_dia);
    v_txt := format('%s que você %s para %s não saiu: %s. Recomendo ligar.',
                    upper(left(v_o_que, 1)) || substr(v_o_que, 2),
                    case new.origem when 'botao' then 'pediu pelo botão' when 'dono' then 'pediu' else 'aprovou' end,
                    coalesce(v_nome, 'o cliente'), public._agenda_cliente_motivo_texto(new.recusa_motivo));
    perform public._agenda_cliente_perguntar('cliente_resposta', 'cliente_resposta:nao_saiu:' || new.id, new.service_order_id,
                                             v_dia,
                                             case when new.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou',
                                                                    'nova_data', 'mudanca_no_dia') then v_dia end,
                                             v_txt, 'ligado', v_agora, v_agora + c_validade);
  exception when others then
    perform public.log_app_error('db', 'agenda: o aviso de mensagem ao cliente que não saiu falhou: ' || sqlerrm, 'agenda',
                                 'cliente:nao_saiu', 'error', jsonb_build_object('mensagem', new.id, 'sqlstate', sqlstate));
  end;
  return null;
end;
$function$;

comment on function public._agenda_cliente_avisar_recusa() is
  'Agenda de Produção (Fase 5, correção C1, item 5c / M1): gatilho AFTER UPDATE OF estado de agenda_cliente_mensagens — a mensagem em ligado APROVADA pelo dono (aprovacao aprovada: o botão, a preparada pelo dono e aprovada, a da rodada aprovada pelo *manda cliente*) que vira recusada (menos segurada) abre a pergunta cliente_resposta:nao_saiu:<mensagem> ("A confirmação de qua 04/11 que você pediu pelo botão para Flávio não saiu: o cliente não escreveu para a HBR nos últimos 365 dias… Recomendo ligar."), 7 dias. Com agenda.cliente_recusa_na_hora = on (a decisão do dono que já responde o motivo) não abre. Nunca lança (app_error_logs, agenda / cliente:nao_saiu).';

drop trigger if exists trg_agenda_cliente_recusada on public.agenda_cliente_mensagens;
create trigger trg_agenda_cliente_recusada after update of estado on public.agenda_cliente_mensagens
  for each row when (new.estado = 'recusada' and old.estado is distinct from 'recusada' and new.modo = 'ligado'
                     and new.aprovacao = 'aprovada' and new.recusa_motivo is distinct from 'segurada')
  execute function public._agenda_cliente_avisar_recusa();

-- ── 3. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- CORREÇÃO FASE 5:") ──
-- Fora dos blocos nenhuma linha muda (o C1z do teste confere), menos _pedir_confirmacao: o corpo de
-- pedir_confirmacao_do_agendamento (20261028100200) com o nome novo, o p_agora no lugar do now() e o dia de hoje contado de
-- p_agora (as 8 linhas declaradas no montador e no C1z/E9z). Quem recriar de novo qualquer uma delas copia DESTA migration.

-- _agenda_cliente_revalidar
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
  -- CORREÇÃO FASE 5: (item 13) 1b. o d10 também na revalidação — e por isso no gatilho da fila (as duas travas) e no
  -- agenda_cliente_pode_sair (o worker): a quem não escreveu para a HBR em cliente_conversa_dias a mensagem não sai, por
  -- qualquer caminho. Sem telefone válido, o motivo verdadeiro é o telefone (como no enfileirar).
  if not public._agenda_cliente_conversou(m.client_id, p_agora) then
    return case when public._agenda_cliente_telefone(m.client_id) is null then 'sem_telefone' else 'sem_conversa' end;
  end if;
  -- CORREÇÃO FASE 5: fim
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
  'Agenda de Produção (Fase 5, P2): a mensagem ao cliente ainda vale em p_agora? null = sai; senão, na ordem: opt_out (_agenda_cliente_sem_mensagem); status (OS cancelada/rascunho; confirmar, véspera, acesso, material chegou, nova data e mudança no dia com a OS aguardando peça, aguardando o cliente ou concluída; andamento fora de in_progress; pronto e lembrete fora de completed ou já entregue; pós-serviço fora de completed; aviso de atraso com a OS concluída); data_mudou (o próximo dia do plano — sem plano no registro, o dia agendado da OS — ≠ base.dia_alvo; no andamento e no atraso da execução, o último dia ≠ base.fim); material (data firme com algum crítico fora de A, os_prontidao); passou_da_data (aviso de atraso com o prometido_ate antes de hoje); mesmo_tipo_24h (outra do mesmo tipo a ele enviada nas últimas cliente_mesmo_tipo_horas); desatualizada (_agenda_cliente_texto com os dados do registro, a 1ª mensagem de base e o dia do envio de agora ≠ o texto registrado, ou o modelo que não fecha mais). STABLE, definer, sem grant (o pode_sair do worker e as travas a chamam). CORREÇÃO FASE 5 (C1, item 13): depois do opt_out, sem_conversa (o d10: _agenda_cliente_conversou em p_agora; sem telefone válido, sem_telefone) — vale também no gatilho da fila e no pode_sair.';

-- _agenda_cliente_enfileirar
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
  'Agenda de Produção (Fase 5, P2): a 1ª trava — a decisão do envio de uma mensagem ao cliente registrada (ou esperando o dono), na ordem: modo_cliente fora de ligado ou a mensagem em teste = fica (modo); o tipo fora de cliente_tipos_ligados = fica (tipo_em_teste); aprovação pedida/crítica = aguardando_dono; segurada/vencida, ou a validade passada = recusada; d19 a conversa viva (mensagem do cliente ou ao cliente nos últimos cliente_conversa_viva_min) = espera o próximo tique (enviar_em pelo _agenda_cliente_quando; passou da validade = vencida); opt_out; sem_conversa (d10); a revalidação (_agenda_cliente_revalidar); domingo/feriado/janela; o teto (teto_dia, teto_semana na semana ISO, teto_total; d13: o aviso de atraso ou de mudança no dia que não cabe vira a pergunta crítica cliente_aviso e espera o dono); o intervalo (outra agenda-cliente pendente ou saindo a menos de cliente_intervalo_min_s); sem_telefone (_agenda_cliente_telefone; wa_test_mode = o número de teste). Senão whatsapp_send_queue (source agenda-cliente, source_ref_id = a mensagem, o texto e a chave dela, priority 5, scheduled_for = enviar_em, max_attempts = as tentativas de +5 min que cabem na janela) e enfileirada; o 23514 da trava da fila vira recusada com o motivo do detail. Idempotente. Sem grant. CORREÇÃO FASE 5 (C1): o choque de intervalo remarca enviar_em (_agenda_cliente_quando; passou da validade = vencida) e devolve {estado registrada, motivo intervalo, enviar_em} em vez de recusar (item 14); o sem_conversa/sem_telefone da trava da fila vira o motivo (item 13).';

-- _pedir_confirmacao
create or replace function public._pedir_confirmacao(p_os uuid, p_autor uuid, p_agora timestamptz)
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
  -- CORREÇÃO FASE 5: a conferência no clique (item 5a / M1), a mensagem que a agenda já tem (item 5b) e a janela do caminho
  -- antigo (item 19)
  v_cli   uuid;
  v_dia_q date;
  v_chave text;
  v_ja    public.agenda_cliente_mensagens%rowtype;
  v_sai_em timestamptz;
  v_dia_e date;
  v_seg   date;
  v_pre   text;
  v_d     jsonb;
  v_prox  date;
  -- CORREÇÃO FASE 5: fim
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
  v_hoje := (p_agora at time zone 'America/Sao_Paulo')::date;
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
  if v_os.scheduled_start_at < p_agora then
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
    -- CORREÇÃO FASE 5: (item 5 / M1) antes de registrar. (b) A confirmação deste dia que a agenda já tem — a de um clique
    -- antes (a chave <dia>:botao) ou a da rodada — não responde "já está com a agenda": já mandada, diz quando; na fila ou
    -- indo sair sozinha, diz quando sai; esperando o dono (pedida), o clique a APROVA; recusada, o clique registra uma 2ª pelo
    -- botão (a chave <dia>:botao), se o motivo já não vale; a 2ª pelo botão também recusada diz o porquê. (a) O que não
    -- depende da hora — o opt-out, a conversa (d10), o telefone e o teto do dia em que a mensagem sairia — vira o erro do
    -- clique com os mesmos textos da recusa abaixo, dentro ou fora do horário de mensagens (fora dele, a mensagem sairia na
    -- manhã seguinte e o enfileirar a recusaria calado).
    select so.client_id into v_cli from public.service_orders so where so.id = p_os;
    v_dia_q := (v_os.scheduled_start_at at time zone 'America/Sao_Paulo')::date;
    v_chave := format('agenda-cliente:confirmar:%s:%s', p_os, v_dia_q);
    select m.* into v_ja from public.agenda_cliente_mensagens m where m.dedupe_key = v_chave || ':botao';
    if v_ja.id is null then
      select m.* into v_ja from public.agenda_cliente_mensagens m where m.dedupe_key = v_chave;
    end if;
    if v_ja.id is not null and v_ja.estado in ('enviada', 'respondida', 'sem_resposta') then
      return jsonb_build_object('ok', true, 'agenda', true, 'teste', v_teste, 'id', v_ja.id, 'nada_feito', true,
        'message', format('Já mandei a confirmação de %s para %s (%s às %s).', public._dia_curto(v_dia_q), v_quem,
                          public._dia_curto((v_ja.enviada_em at time zone 'America/Sao_Paulo')::date),
                          to_char(v_ja.enviada_em at time zone 'America/Sao_Paulo', 'HH24:MI')));
    end if;
    if v_ja.id is not null and v_ja.estado = 'enfileirada' then
      return jsonb_build_object('ok', true, 'agenda', true, 'teste', v_teste, 'id', v_ja.id, 'nada_feito', true,
        'message', format('A confirmação de %s para %s já está na fila: sai agora.', public._dia_curto(v_dia_q), v_quem));
    end if;
    if v_ja.id is not null and v_ja.estado in ('registrada', 'aguardando_dono') and v_ja.aprovacao in ('livre', 'aprovada') then
      return jsonb_build_object('ok', true, 'agenda', true, 'teste', v_teste, 'id', v_ja.id, 'nada_feito', true,
        'message', format('A confirmação de %s para %s já vai sair sozinha: sai %s.', public._dia_curto(v_dia_q), v_quem,
                          public._agenda_cliente_quando_texto(v_ja.enviar_em, p_agora)));
    end if;
    if v_ja.id is not null and v_ja.estado = 'recusada' and v_ja.dedupe_key = v_chave || ':botao' then
      raise exception '%', format('A confirmação de %s já foi pedida pelo botão e não saiu: %s. Confirme com %s por telefone.',
                                  public._dia_curto(v_dia_q), public._agenda_cliente_motivo_texto(v_ja.recusa_motivo), v_quem);
    end if;
    if v_ja.id is not null and v_ja.estado = 'recusada' then
      -- a da rodada recusada (segurada, vencida, a OS que mudou…): o clique do dono pede de novo, pelo botão
      v_dados := v_dados || jsonb_build_object('chave', v_dia_q || ':botao');
      v_chave := v_chave || ':botao';
    end if;
    v_sai_em := case when v_ja.id is not null and v_ja.estado = 'aguardando_dono' then greatest(v_ja.enviar_em, p_agora)
                     else public._agenda_cliente_quando(hashtext(v_chave), p_agora, p_agora) end;
    v_dia_e := (v_sai_em at time zone 'America/Sao_Paulo')::date;
    v_seg := date_trunc('week', v_dia_e)::date;
    v_pre := case
      when public._agenda_cliente_sem_mensagem(v_cli) then 'opt_out'
      when not public._agenda_cliente_conversou(v_cli, v_sai_em)
        then case when public._agenda_cliente_telefone(v_cli) is null then 'sem_telefone' else 'sem_conversa' end
      when public._agenda_cliente_telefone(v_cli) is null then 'sem_telefone'
      when public._agenda_cliente_no_periodo(v_cli, v_dia_e, v_dia_e, v_ja.id) >= v_cf.cliente_dia_max then 'teto_dia'
      when public._agenda_cliente_no_periodo(v_cli, v_seg, v_seg + 6, v_ja.id) >= v_cf.cliente_semana_max then 'teto_semana'
      when public._agenda_cliente_no_periodo(null, v_dia_e, v_dia_e, v_ja.id) >= v_cf.cliente_total_dia_max then 'teto_total'
    end;
    if v_pre is null and v_ja.id is not null and v_ja.estado = 'aguardando_dono' then
      if v_ja.aprovacao <> 'pedida' or v_ja.pergunta_id is null then
        raise exception '%', format('A confirmação de %s para %s espera a sua decisão na conversa (opção 1, 2 ou 3).',
                                    public._dia_curto(v_dia_q), v_quem);
      end if;
      -- esperando o dono: o clique é o *manda cliente* dela (a janela, o teto e a revalidação continuam valendo)
      v_d := public._agenda_cliente_decidir(v_ja.pergunta_id, 1::smallint, v_autor, 'tela', 'Pedir confirmação (o botão)', p_agora);
      if not coalesce((v_d ->> 'ok')::boolean, false) or v_d ->> 'estado' = 'recusada' then
        raise exception '%', coalesce(v_d ->> 'texto', 'Não deu para aprovar a confirmação agora.');
      end if;
      return jsonb_build_object('ok', true, 'agenda', true, 'teste', v_teste, 'id', v_ja.id, 'aprovou', true,
                                'mensagem', v_ja.texto, 'enviar_em', v_ja.enviar_em, 'message', v_d ->> 'texto');
    end if;
    if v_pre is not null then
      v_r := jsonb_build_object('criada', true, 'estado', 'recusada', 'motivo', v_pre);
    else
    -- CORREÇÃO FASE 5: fim
    begin
      v_r := public._agenda_cliente_registrar('confirmar', null, p_os,
               (v_os.scheduled_start_at at time zone 'America/Sao_Paulo')::date, v_dados, p_agora, null, 'botao', null, p_agora,
               v_autor);
    exception when sqlstate '22023' then
      raise exception 'Não deu para montar a mensagem ao cliente: %', sqlerrm;
    end;
    -- CORREÇÃO FASE 5: o fim do "senão" da conferência no clique
    end if;
    -- CORREÇÃO FASE 5: fim
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
                      v_quem, public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora), v_quem)
        when (v_r ->> 'enviar_em')::timestamptz <= p_agora + interval '15 minutes'
          then case when v_teste then 'Mensagem na fila (modo de teste: vai para o número de teste).'
                    else format('Pedido de confirmação na fila para %s. Quando ele responder SIM, a OS fica confirmada.', v_quem) end
        else format('Pedido de confirmação a %s registrado: sai %s (fora do horário de mensagens agora).', v_quem,
                    public._agenda_cliente_quando_texto((v_r ->> 'enviar_em')::timestamptz, p_agora)) end);
  end if;
  -- FASE 5: fim

  -- CORREÇÃO FASE 5: (item 19) o caminho antigo (a mensagem ao cliente em teste, ou a confirmação ainda fora das ondas)
  -- também só sai no horário de mensagens ao cliente — a mesma regra das três travas da agenda: fora dele, o clique dá o
  -- erro e nada vai à fila. Com modo_cliente desligado (antes da Fase 5), como em 30/09.
  if v_cf.modo_cliente <> 'desligado' and public._agenda_cliente_fora_da_janela(p_agora, p_agora) is not null then
    v_prox := (public._agenda_cliente_quando(0, p_agora, p_agora) at time zone 'America/Sao_Paulo')::date;
    raise exception '%', format('Fora do horário de mensagens ao cliente: peça %s a partir das %s.',
                                case when v_prox = v_hoje then 'hoje' when v_prox = v_hoje + 1 then 'amanhã'
                                     else public._dia_curto(v_prox) end,
                                to_char(v_cf.cliente_janela_inicio, 'HH24:MI'));
  end if;
  -- CORREÇÃO FASE 5: fim
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
     set client_confirmation_requested_at = p_agora, client_confirmed_at = null, client_confirmed_for = null
   where id = v_os.id;

  return jsonb_build_object('ok', true, 'teste', v_teste, 'mensagem', v_msg,
    'message', case when v_teste then 'Mensagem na fila (modo de teste: vai para o número de teste).'
                    else 'Pedido de confirmação enviado a ' || coalesce(v_os.cliente, 'o cliente') || '. Quando ele responder SIM, a OS fica confirmada.' end);
end;
$$;

comment on function public._pedir_confirmacao(uuid, uuid, timestamptz) is
  'O botão "Pedir confirmação" (Fase 5, correção C1): o corpo de pedir_confirmacao_do_agendamento (20261028100200) com a hora em p_agora (a casca passa now(); o teste, a hora fixa). Pela agenda (modo_cliente ligado e confirmar nas ondas): a confirmação do mesmo dia que a agenda já tem não fica "já está com a agenda" — mandada ("Já mandei a confirmação de qua 04/11 para Flávio (sex 30/10 às 10:00)."), na fila ou indo sair sozinha (diz quando), esperando o dono (o clique a aprova pelo _agenda_cliente_decidir), recusada (uma 2ª pelo botão, chave <dia>:botao; a 2ª recusada diz o porquê); no clique, o opt-out, a conversa (d10), o telefone e o teto do dia do envio viram o erro com o texto da recusa, dentro ou fora do horário. O caminho antigo, com modo_cliente fora de desligado, recusa fora do horário de mensagens ao cliente ("Fora do horário de mensagens ao cliente: peça amanhã a partir das 08:00."). Interna (sem grant): só a casca a chama.';

-- pedir_confirmacao_do_agendamento
create or replace function public.pedir_confirmacao_do_agendamento(p_os uuid, p_autor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  -- CORREÇÃO FASE 5: (item 21 / B1) a casca do botão: o corpo (20261028100200) mora em _pedir_confirmacao, que recebe a
  -- hora — aqui o relógio; no teste, a hora fixa (de dia e de noite). A porta e o cargo conferido não mudam.
  return public._pedir_confirmacao(p_os, p_autor, now());
  -- CORREÇÃO FASE 5: fim
end;
$$;

comment on function public.pedir_confirmacao_do_agendamento(uuid, uuid) is
  'O botão "Pedir confirmação" (30/09/2026): manda ao cliente o pedido de SIM. Fase 5 (P2, D9): com modo_proposta ligado, vale o próximo dia vigente do plano (de amanhã em diante) com a OS aberta, aprovada, agendada ou em andamento — aguardando peça ou o cliente recusa —; fora de ligado, a regra de 30/09 (agendada e no futuro). Com modo_cliente ligado e confirmar em cliente_tipos_ligados, registra o M1 pela agenda (_agenda_cliente_registrar origem botao, já aprovado; janela, feriado, teto, intervalo e revalidação) e diz quando sai; a recusa vira o erro com o motivo. Fora disso, como antes (origem agenda-confirmacao). CORREÇÃO FASE 5 (C1): a casca — o corpo mora em _pedir_confirmacao(p_os, p_autor, now()).';

-- _agenda_cliente_confirmar
create or replace function public._agenda_cliente_confirmar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_perto constant interval := interval '2 days';   -- spec §5.3: "não sai se o M1 saiu há menos de 2 dias corridos"
  r       record;
  x       jsonb;
  v_d     date;
  v_m1    timestamptz;
  v_vesp  date;
  v_alvo_v timestamptz;
  v_tipo  text;
  v_r     jsonb;
  n_m1    int := 0;
  n_vesp  int := 0;
  n_unico int := 0;
  n_pula  int := 0;
begin
  for r in
    select k.service_order_id as os
      from public.os_carteira(p_hoje) k
     where k.status not in ('awaiting_parts', 'awaiting_client', 'in_progress')
     order by k.numero collate "C", k.service_order_id
  loop
    x := public._agenda_plano_da_os(r.os, p_hoje);
    v_d := (x ->> 'proximo_dia')::date;
    continue when v_d is null or v_d <= p_hoje;
    -- ainda não começou: nenhum dia antes do próximo (cumprido, parcial ou sem registro)
    continue when coalesce((x ->> 'inicio')::date, v_d) < v_d;
    continue when public.os_prontidao(r.os, p_hoje) #>> '{material,estado}' is distinct from 'completo';
    x := public._agenda_cliente_contexto(r.os, p_hoje);
    v_vesp := public._agenda_cliente_vespera(v_d);
    continue when v_vesp is null or v_vesp < p_hoje;
    v_alvo_v := public._agenda_cliente_toque(v_vesp);
    v_m1 := public._agenda_cliente_toque(public.agenda_somar_du(v_d, -cf.cliente_confirmar_du));
    if v_m1 < p_agora then
      v_m1 := public._agenda_cliente_proximo_toque(p_agora);
    end if;
    -- CORREÇÃO FASE 5: (item 20) o botão antigo já pediu a confirmação deste D (dentro de cliente_resposta_validade, sem
    -- resposta, e o dia que ele confirma é o D), ou o cliente já confirmou o D: o M1 (e o toque único da confirmação) não
    -- sai — seria a 2ª confirmação do mesmo dia. A véspera segue a regra dela.
    if exists (select 1 from public.service_orders so
                where so.id = r.os
                  and ((so.client_confirmation_requested_at > p_agora - cf.cliente_resposta_validade
                        and so.client_confirmation_requested_at <= p_agora and so.client_confirmed_at is null
                        and (public._agenda_cliente_dia_a_confirmar(r.os, p_agora) at time zone 'America/Sao_Paulo')::date = v_d)
                       or (so.client_confirmed_for at time zone 'America/Sao_Paulo')::date = v_d)) then
      v_m1 := null;
    end if;
    -- CORREÇÃO FASE 5: fim
    -- a mensagem que já propôs este D (o material chegou M3, a nova data M7, a mudança no dia M10, o aviso remarcado)
    -- substitui a confirmação; a véspera só sai se ela saiu há c_perto ou mais (abaixo)
    if exists (select 1 from public.agenda_cliente_mensagens m
                where m.service_order_id = r.os
                  and (m.tipo in ('material_chegou', 'nova_data', 'mudanca_no_dia')
                       or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado'))
                  and coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) = v_d and m.estado <> 'recusada') then
      if exists (select 1 from public.agenda_cliente_mensagens m
                  where m.service_order_id = r.os
                    and (m.tipo in ('material_chegou', 'nova_data', 'mudanca_no_dia')
                         or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado'))
                    and coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) = v_d and m.estado <> 'recusada'
                    and (m.enviada_em is null or m.enviada_em > v_alvo_v - c_perto)) then
        n_pula := n_pula + 1;
        continue;
      end if;
      v_m1 := null;
    end if;

    if v_m1 is not null and (v_m1 at time zone 'America/Sao_Paulo')::date >= v_vesp then
      -- um toque só, na véspera (que também não sai se a confirmação saiu há menos de c_perto)
      if public._agenda_cliente_ja_registra(v_vesp, p_hoje, p_agora) then
        if exists (select 1 from public.agenda_cliente_mensagens m
                    where m.service_order_id = r.os and m.tipo in ('confirmar', 'material_chegou', 'nova_data')
                      and m.enviada_em is not null and m.enviada_em > v_alvo_v - c_perto) then
          n_pula := n_pula + 1;
          continue;
        end if;
        v_tipo := case when coalesce((x ->> 'acesso_conhecido')::boolean, false) then 'confirmar' else 'acesso' end;
        v_r := public._agenda_cliente_registrar(v_tipo, case when v_tipo = 'confirmar' then 'unico' end, r.os, v_d,
                 '{}'::jsonb, v_alvo_v, public._agenda_cliente_fim_da_janela(v_vesp, 0), 'rodada', null, p_agora);
        if coalesce((v_r ->> 'criada')::boolean, false) then n_unico := n_unico + 1; end if;
      end if;
      continue;
    end if;
    -- a confirmação (D-3)
    if v_m1 is not null and public._agenda_cliente_ja_registra((v_m1 at time zone 'America/Sao_Paulo')::date, p_hoje, p_agora) then
      v_r := public._agenda_cliente_registrar('confirmar', null, r.os, v_d, '{}'::jsonb, v_m1,
               public._agenda_cliente_fim_da_janela((v_m1 at time zone 'America/Sao_Paulo')::date, 0), 'rodada', null, p_agora);
      if coalesce((v_r ->> 'criada')::boolean, false) then n_m1 := n_m1 + 1; end if;
    end if;
    -- a véspera (D-1)
    if public._agenda_cliente_ja_registra(v_vesp, p_hoje, p_agora) then
      if exists (select 1 from public.agenda_cliente_mensagens m
                  where m.service_order_id = r.os and m.tipo in ('confirmar', 'material_chegou', 'nova_data')
                    and m.enviada_em is not null and m.enviada_em > v_alvo_v - c_perto) then
        n_pula := n_pula + 1;
        continue;
      end if;
      v_tipo := case when coalesce((x ->> 'acesso_conhecido')::boolean, false) then 'vespera' else 'acesso' end;
      v_r := public._agenda_cliente_registrar(v_tipo, null, r.os, v_d, '{}'::jsonb, v_alvo_v,
               public._agenda_cliente_fim_da_janela(v_vesp, 0), 'rodada', null, p_agora);
      if coalesce((v_r ->> 'criada')::boolean, false) then n_vesp := n_vesp + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('confirmar', n_m1, 'vespera', n_vesp, 'unico', n_unico, 'vespera_pulada', n_pula);
end;
$function$;

comment on function public._agenda_cliente_confirmar(date, timestamptz) is
  'Agenda de Produção (Fase 5, P3): o passo confirmar da rodada do cliente — a confirmação (M1) em D − cliente_confirmar_du dias úteis, a véspera (M2) ou o acesso (M4) no último dia de janela antes de D, ou um toque só; o M3/M7/M10/M6 remarcado do mesmo D substitui o M1. CORREÇÃO FASE 5 (C1, item 20): o M1 do D não sai quando o botão antigo já pediu a confirmação desse D (client_confirmation_requested_at dentro de cliente_resposta_validade, sem resposta, com _agenda_cliente_dia_a_confirmar no D) ou o cliente já confirmou o D (client_confirmed_for). Interna (sem grant).';

-- _agenda_cliente_decidir
create or replace function public._agenda_cliente_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid default null,
                                                          p_via text default 'whatsapp', p_trecho text default null,
                                                          p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  c_tique constant interval := interval '15 minutes';   -- o tique do motor
  q      public.agenda_perguntas%rowtype;
  m      public.agenda_cliente_mensagens%rowtype;
  v_aut  uuid := (select u.id from public.app_users u where u.id = p_autor);
  v_nome text;
  v_manda boolean;
  v_r    jsonb;
  v_txt  text;
  v_acao uuid;
begin
  select * into q from public.agenda_perguntas where id = p_pergunta for update;
  if not found then
    raise exception 'Não encontrei essa pergunta.' using errcode = 'P0002';
  end if;
  if q.tipo not in ('cliente_aprovar', 'cliente_aviso') then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta não é de mensagem ao cliente.');
  end if;
  if q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  if q.modo <> 'ligado' or cf.modo_cliente <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'As mensagens ao cliente estão em teste: nada sai ainda.');
  end if;
  if p_via is null or p_via not in ('whatsapp', 'painel', 'tela') then
    raise exception 'Canal desconhecido para a decisão: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  if p_opcao is null or (q.tipo = 'cliente_aprovar' and p_opcao not in (1, 2))
     or (q.tipo = 'cliente_aviso' and p_opcao not in (1, 2, 3)) then
    return jsonb_build_object('ok', false,
      'texto', case when q.tipo = 'cliente_aprovar' then 'Essa opção não existe. As opções são: 1) manda; 2) segura.'
                    else 'Essa opção não existe. As opções são: 1) Você liga e eu não mando nada; 2) Eu mando o aviso escrito agora; 3) Não aviso agora.' end);
  end if;
  v_manda := (q.tipo = 'cliente_aprovar' and p_opcao = 1) or (q.tipo = 'cliente_aviso' and p_opcao = 2);
  select * into m from public.agenda_cliente_mensagens where pergunta_id = q.id order by criada_em desc, id limit 1 for update;
  v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                        from public.service_orders so join public.clients cl on cl.id = so.client_id
                       where so.id = coalesce(m.service_order_id, q.service_order_id)), 'cliente');

  -- a mensagem já não espera (venceu, a revalidação tirou): a pergunta sai sem decisão, nada muda
  if m.id is not null and m.estado not in ('registrada', 'aguardando_dono') then
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'a mensagem ao cliente já não estava esperando'
     where id = q.id;
    return jsonb_build_object('ok', false, 'mensagem_id', m.id,
      'texto', format('A mensagem do %s já não está esperando (%s): nada mudou.', v_nome,
                      coalesce(m.recusa_motivo, m.estado)));
  end if;

  update public.agenda_perguntas
     set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
         respondida_por = v_aut, respondida_via = p_via
   where id = q.id;

  if m.id is null then
    -- a pergunta sem mensagem (a data dita que já passou): não há aviso escrito que ainda sirva
    v_txt := case when v_manda
                  then format('Não há aviso escrito para mandar ao %s: a data que ele ouviu já passou e o aviso chegaria depois dela. Recomendo você ligar.', v_nome)
                  when p_opcao = 1 then format('Combinado: você liga para o %s; eu não mando nada.', v_nome)
                  else format('Combinado: não aviso o %s agora.', v_nome) end;
  elsif v_manda then
    update public.agenda_cliente_mensagens
       set aprovacao = 'aprovada', aprovada_em = p_agora, aprovada_por = v_aut
     where id = m.id;
    if m.enviar_em <= p_agora + c_tique then
      -- CORREÇÃO FASE 5: (item 5c) a recusa na hora da decisão já vai no texto da resposta (abaixo): o aviso de "não saiu"
      -- (_agenda_cliente_avisar_recusa) não a repete
      perform set_config('agenda.cliente_recusa_na_hora', 'on', true);
      -- CORREÇÃO FASE 5: fim
      v_r := public._agenda_cliente_enfileirar(m.id, p_agora);
      -- CORREÇÃO FASE 5: a recusa que vier depois (o passo fila, a trava, o worker) avisa
      perform set_config('agenda.cliente_recusa_na_hora', '', true);
      -- CORREÇÃO FASE 5: fim
    end if;
    v_txt := case
      when v_r is null then format('Mando ao %s %s.', v_nome, public._agenda_cliente_quando_texto(m.enviar_em, p_agora))
      when v_r ->> 'estado' = 'enfileirada' then format('Mando ao %s agora.', v_nome)
      when v_r ->> 'estado' = 'recusada' then
        format('Não mandei ao %s: %s.', v_nome, case
          when v_r ->> 'motivo' in ('teto_dia', 'teto_semana') then format('ele já recebeu as mensagens que cabem (no máximo %s por dia e %s por semana); recomendo ligar', cf.cliente_dia_max, cf.cliente_semana_max)
          when v_r ->> 'motivo' = 'teto_total' then 'as mensagens de hoje aos clientes já acabaram; sai na próxima vez que couber'
          when v_r ->> 'motivo' = 'opt_out' then 'ele pediu para não receber mensagens'
          when v_r ->> 'motivo' in ('sem_telefone', 'sem_conversa') then 'não tenho como mandar a ele (telefone ou conversa)'
          when v_r ->> 'motivo' in ('vencida', 'passou_da_data') then 'passou da hora de a mensagem servir'
          when v_r ->> 'motivo' in ('janela', 'domingo', 'feriado') then 'fora do horário de mensagens'
          else 'a OS mudou desde a mensagem (' || coalesce(v_r ->> 'motivo', 'sem motivo') || ')' end)
      else format('Mando ao %s %s.', v_nome, public._agenda_cliente_quando_texto(
                    coalesce((v_r ->> 'enviar_em')::timestamptz, m.enviar_em), p_agora)) end;
  else
    update public.agenda_cliente_mensagens
       set aprovacao = 'segurada', aprovada_em = p_agora, aprovada_por = v_aut, estado = 'recusada', recusa_motivo = 'segurada'
     where id = m.id;
    v_txt := case when q.tipo = 'cliente_aviso' and p_opcao = 1
                  then format('Combinado: você liga para o %s; eu não mando nada.', v_nome)
                  when q.tipo = 'cliente_aviso' then format('Combinado: não aviso o %s agora.', v_nome)
                  else format('Segurei a mensagem do %s: ela não sai.', v_nome) end;
  end if;

  -- a decisão crítica fica na trilha (a ação crítica com a pergunta respondida)
  if q.tipo = 'cliente_aviso' then
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, pergunta_id, critica,
                                     antes, depois, texto, autor)
    values (clock_timestamp(), (p_agora at time zone 'America/Sao_Paulo')::date, true, 'dono', 'cliente',
            coalesce(m.service_order_id, q.service_order_id), array[coalesce(m.service_order_id, q.service_order_id)],
            q.id, true, '{}'::jsonb,
            jsonb_build_object('mensagem_id', m.id, 'opcao', p_opcao, 'manda', v_manda),
            public._agenda_corta(v_txt, 400), v_aut)
    returning id into v_acao;
  end if;
  return jsonb_build_object('ok', true, 'texto', v_txt, 'mensagem_id', m.id, 'manda', v_manda, 'acao_id', v_acao,
                            'estado', coalesce(v_r ->> 'estado', (select x.estado from public.agenda_cliente_mensagens x where x.id = m.id)),
                            'fila_id', v_r ->> 'fila_id');
end;
$function$;

comment on function public._agenda_cliente_decidir(uuid, smallint, uuid, text, text, timestamptz) is
  'Agenda de Produção (Fase 5, P3): a decisão do dono sobre a mensagem ao cliente (pergunta aberta, em ligado, com modo_cliente ligado; senão "As mensagens ao cliente estão em teste: nada sai ainda."). cliente_aprovar: 1 = aprovada (aprovada_em/por; à fila se é a hora — a janela, o teto e a revalidação continuam —, senão o passo fila manda no tique certo: "Mando ao Nelson amanhã às 09:00."), 2 = segurada (recusada/segurada: "Segurei a mensagem do Flávio: ela não sai."). cliente_aviso (crítica): 1 = você liga e nada sai, 2 = manda pelo canal (teto cheio = não sai e o texto diz), 3 = não aviso agora; a ação crítica (tipo cliente, origem dono) fica na trilha; a pergunta sem mensagem (a data dita que já passou) não manda nada. A mensagem que já não espera fecha a pergunta (resolvida) sem mudar nada. Chamada por agenda_decidir (e pelo *manda cliente* / *segura cliente* do P5). Interna (sem grant). CORREÇÃO FASE 5 (C1): a recusa na hora (o enfileirar dentro da decisão) já vai no texto; agenda.cliente_recusa_na_hora fica ligado só durante essa chamada, para o aviso de "não saiu" (trg_agenda_cliente_recusada) não repetir.';

-- _agenda_cliente_data_da_resposta
create or replace function public._agenda_cliente_data_da_resposta(p_expressao text, p_hoje date, p_dia date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v jsonb;
  v_ini date;
  -- CORREÇÃO FASE 5: (item 9) o "dia N" sem mês
  v_s   text;
  v_num int;
  v_nat date;
  v_seg date;
  -- CORREÇÃO FASE 5: fim
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
  -- CORREÇÃO FASE 5: (item 9) o "dia N" sem mês (com ou sem o dia da semana) do cliente só vale no mês de hoje (N de hoje em
  -- diante) ou no seguinte (N antes de hoje): o N que não existe nesse mês ("dia 31" dito em novembro) ou que o
  -- agenda_data_dita levou para mais longe (31/12) = não entendi (vai ao dono). O mês dito ("dia 3/12") vale como dito.
  v_s := public._agenda_preparar_data(p_expressao);
  if v_s !~ '/' then
    v_num := coalesce((regexp_match(v_s, '\mdia (\d{1,2})\M'))[1],
                      (regexp_match(v_s, '^(?:(?:o|no|na|em|pro|pra|para|a) )?(\d{1,2})$'))[1],
                      (regexp_match(v_s, '\m(?:segunda|terca|quarta|quinta|sexta|sabado|domingo) (\d{1,2})$'))[1])::int;
    if v_num is not null then
      v_seg := (date_trunc('month', p_hoje) + interval '1 month')::date;
      v_nat := case when v_num >= extract(day from p_hoje)::int
                    then public._agenda_data_valida(extract(year from p_hoje)::int, extract(month from p_hoje)::int, v_num)
                    else public._agenda_data_valida(extract(year from v_seg)::int, extract(month from v_seg)::int, v_num) end;
      if v_nat is null or v_nat is distinct from (v ->> 'de')::date then
        return null;
      end if;
    end if;
  end if;
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('de', (v ->> 'de')::date, 'ate', coalesce((v ->> 'ate')::date, (v ->> 'de')::date));
end;
$function$;

comment on function public._agenda_cliente_data_da_resposta(text, date, date) is
  'Agenda de Produção (Fase 5, P4): a expressão de data da resposta do cliente ("sexta", "dia 04/11", "até sexta", "semana que vem") vira {de, ate} pelo banco (agenda_data_dita, futuro, com o dia da mensagem). "essa semana" (o dia recusado) = do dia combinado (p_dia) ao domingo da mesma semana, nunca antes de hoje. null = não entendeu. Interna (sem grant). CORREÇÃO FASE 5 (C1, item 9): o "dia N" sem mês só vale no mês de hoje (N de hoje em diante) ou no seguinte (N antes de hoje); o dia que não existe nesse mês ("dia 31" em novembro) ou que iria mais longe = null.';

-- agenda_resposta_do_cliente
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
  -- CORREÇÃO FASE 5: a outra conversa (A1) e o PARAR que vale sempre (item 2)
  c_opt_out_dias constant interval := interval '30 days';   -- decisão da correção C1: o PARAR de quem recebeu da agenda em 30 dias
  v_outra   boolean := false;
  v_opt_cli uuid[];
  v_opt_msg uuid;
  v_opt_os  uuid;
  v_c       uuid;
  -- CORREÇÃO FASE 5: fim
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
  -- CORREÇÃO FASE 5: (A1 = item 11) a resposta só é da agenda quando a última mensagem que a HBR mandou a esse número é a
  -- dela: o botão antigo (o pedido de 30/09) ou o dono (ou outra rotina) falando com o cliente depois dela = a resposta é
  -- dessa outra conversa — devolve consumiu false (abaixo) e os leitores de antes (o "sim" de 30/09, a revisão) seguem.
  if m.id is not null then
    v_outra := public._agenda_cliente_outra_conversa(v_cli, p_phone, coalesce(m.enviada_em, m.enviar_em), p_agora);
  end if;
  -- (item 2) o PARAR (e os outros opt-outs) vale SEMPRE para quem recebeu mensagem da agenda nos últimos c_opt_out_dias —
  -- fora da validade, depois de outra resposta, com o número de dois clientes ou depois de outra conversa: o pós-serviço
  -- promete "é só responder PARAR". Marca o opt-out de cada cliente do número que recebeu, cancela as vivas dele, grava a
  -- resposta (efeito opt_out) e a ação; nada responde ao cliente.
  if v_modo = 'ligado' and v_tipo = 'text' and p_intencao = 'opt_out' and not public._e_concordancia(p_body)
     and (m.id is null or v_outra or v_n > 1 or cardinality(v_cli) > 1) then
    select coalesce(array_agg(distinct x.client_id), '{}'::uuid[]) into v_opt_cli
      from public.agenda_cliente_mensagens x
     where x.client_id = any (v_cli) and x.modo = 'ligado' and x.enviada_em is not null
       and x.enviada_em <= p_agora and x.enviada_em > p_agora - c_opt_out_dias;
    if cardinality(v_opt_cli) > 0 then
      select x.id, x.service_order_id into v_opt_msg, v_opt_os
        from public.agenda_cliente_mensagens x
       where x.client_id = any (v_opt_cli) and x.modo = 'ligado' and x.enviada_em is not null and x.enviada_em <= p_agora
       order by x.enviada_em desc, x.id limit 1;
      insert into public.agenda_cliente_respostas (id, client_id, service_order_id, mensagem_id, whatsapp_message_id, recebida_em,
                                                   tipo_msg, texto, intencao, expressao, data_dita, efeito, modo)
      values (v_rid, v_opt_cli[1], v_opt_os, v_opt_msg, p_message_id, p_agora, v_tipo, v_trecho, 'opt_out', null, null,
              'opt_out', 'ligado')
      on conflict (whatsapp_message_id) do nothing;
      if not found then
        return jsonb_build_object('consumiu', true, 'repetida', true);
      end if;
      foreach v_c in array v_opt_cli loop
        update public.clients set opt_out_whatsapp = true where id = v_c and not coalesce(opt_out_whatsapp, false);
        for v_id in select x.id from public.agenda_cliente_mensagens x
                     where x.client_id = v_c and x.estado in ('registrada', 'aguardando_dono', 'enfileirada')
                     order by x.enviar_em, x.id loop
          if public._agenda_cliente_cancelar(v_id, 'opt_out', 'O cliente pediu para não receber mensagens.') then
            v_k := v_k + 1;
          end if;
        end loop;
      end loop;
      v_nome := coalesce((select public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(cl.display_name, '')), ''), cl.name))
                            from public.clients cl where cl.id = v_opt_cli[1]), 'cliente');
      v_texto := format('O %s pediu para não receber mais mensagens: não mando mais nada a ele.', v_nome);
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto, motivo)
      values (clock_timestamp(), v_hoje, true, 'cliente', 'cliente', v_opt_os, array[v_opt_os], '{}'::jsonb,
              jsonb_build_object('efeito', 'opt_out', 'resposta_id', v_rid, 'mensagem_id', v_opt_msg, 'canceladas', v_k,
                                 'clientes', to_jsonb(v_opt_cli), 'fora_da_mensagem', true),
              v_texto, 'o cliente pediu para parar')
      returning id into v_acao;
      update public.agenda_cliente_respostas set acao_id = v_acao where id = v_rid;
      return jsonb_build_object('consumiu', true, 'modo', 'ligado', 'efeito', 'opt_out', 'intencao', 'opt_out', 'texto', v_texto,
                                'resposta_id', v_rid, 'mensagem_id', v_opt_msg, 'acao_id', v_acao, 'pergunta_id', null);
    end if;
  end if;
  -- CORREÇÃO FASE 5: fim
  if m.id is null then
    return jsonb_build_object('consumiu', false, 'motivo', 'sem_mensagem');
  end if;
  -- CORREÇÃO FASE 5: (A1) a outra conversa depois da mensagem da agenda: não é resposta a ela (em teste também: a sombra
  -- não registra o que a agenda não leria)
  if v_outra then
    return jsonb_build_object('consumiu', false, 'modo', v_modo, 'motivo', 'outra_conversa', 'mensagem_id', m.id);
  end if;
  -- CORREÇÃO FASE 5: fim

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
      -- CORREÇÃO FASE 5: (item 9) o dia pedido longe demais do combinado (mais de cliente_pedido_max_du dias úteis) não
      -- remarca sozinho: é o dono que vê
      elsif public.agenda_du_entre(coalesce(v_dia, v_hoje), v_de) > cf.cliente_pedido_max_du then
        v_efeito := 'ao_dono';
        v_o_que := format('pediu %s, mais de %s dias úteis depois do combinado: remarque você', public._dia_curto(v_de),
                          cf.cliente_pedido_max_du);
      -- CORREÇÃO FASE 5: fim
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
    -- CORREÇÃO FASE 5: (item 17) falta/remarcar com um número de dia que o banco não entendeu ("tô viajando, volto dia 20",
    -- "só depois de 20/11"): tirar só o dia combinado remarcaria para quando ele ainda está fora — vai ao dono
    elsif v_int in ('remarcar', 'falta') and v_data is null
          and public._agenda_preparar_data(coalesce(v_trecho, '')) ~ '(\mdia \d{1,2}\M|\m\d{1,2}/\d{1,2})' then
      v_efeito := 'ao_dono';
      v_o_que := 'falou de outro dia, que eu não entendi';
    -- CORREÇÃO FASE 5: fim
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
      -- CORREÇÃO FASE 5: (item 9) tirar dias até longe demais do combinado ("vou viajar até 20/12") também não remarca sozinho
      elsif public.agenda_du_entre(coalesce(v_dia, v_hoje), v_ate) > cf.cliente_pedido_max_du then
        v_efeito := 'ao_dono';
        v_o_que := format('disse que não dá até %s, mais de %s dias úteis depois do combinado: remarque você',
                          public._dia_curto(v_ate), cf.cliente_pedido_max_du);
      -- CORREÇÃO FASE 5: fim
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
    -- CORREÇÃO FASE 5: (item 16) o acesso com negação ("não sei onde vai estar a chave", "não tenho a chave", "ainda não
    -- sei") não é acesso dito: não vai para o campo da OS nem desliga a pergunta do acesso — vai ao dono
    elsif v_int = 'acesso' and public._agenda_normal(coalesce(v_trecho, '')) ~ '\m(nao sei|nao tenho|ainda nao)\M' then
      v_efeito := 'ao_dono';
      v_o_que := 'falou do acesso, mas ainda não sabe (ou não tem) a chave';
    -- CORREÇÃO FASE 5: fim
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
  'Agenda de Produção (Fase 5, P4): a mensagem do cliente que chega pelo WhatsApp (o webhook chama depois da equipe e antes da confirmação de 30/09 e da conferência do recibo: o "ok" tem um dono só). modo_cliente desligado, número de ninguém (ou do dono, da equipe, de quem recebe diária), a mesma mensagem de novo ou sem mensagem da agenda esperando resposta (a última dos tipos que esperam, enviada dentro de cliente_resposta_validade e ainda sem resposta; em teste, a que teria saído) = consumiu false. Em teste: registra a resposta (efeito sombra, com a intenção) e consumiu false. Ligado, a 1ª que vale: duas OS ou dois clientes no número = ambígua (ao dono); áudio e mídia ao dono (o áudio NUNCA confirma); o SIM curto (_e_concordancia) confirma o M1/M3/M7/M10 e o M6 remarcado (_agenda_cliente_confirmar_dia: fixa o dia, com *desfaz*), registra a véspera e o acesso, é ciência no aviso de atraso, vai ao dono no "ficou pronto" e não faz nada no pós-serviço; opt-out = as vivas recusadas (opt_out) e o cadastro marcado, calado; reclamação (na hora, por acorde), negociação, acordo e pergunta ao dono; o dia pedido (data) e o recusado (remarcar, falta) — só nas mensagens que propõem um dia e com modo_proposta ligado — viram o "não antes de" e o bem indisponível com o replano (_agenda_cliente_pedido_de_dia, com *desfaz*; o dia combinado em até 1 dia útil = acorde); o dia passado, de hoje, o mesmo ou mais cedo que o combinado vai ao dono; o acesso dito vai para o campo da OS (_agenda_cliente_anotar_acesso, com *desfaz*); o resto ao dono. Ao dono = a pergunta cliente_resposta:<resposta> (some em 7 dias). A mensagem fica respondida (resposta_id) e a pergunta do "não respondeu" dela se resolve. O efeito que falha vai ao dono e a app_error_logs (cliente:resposta). {consumiu, modo, efeito, intencao, texto, resposta_id, mensagem_id, acao_id, pergunta_id}. Só service_role. CORREÇÃO FASE 5 (C1): (A1) a resposta só é da agenda quando a última mensagem da HBR ao número é a dela — o botão antigo ou outra mensagem outbound depois dela (_agenda_cliente_outra_conversa) = {consumiu:false, motivo:outra_conversa}, em teste também; (item 2) o opt-out vale para quem recebeu mensagem da agenda em 30 dias, mesmo sem mensagem esperando, depois de outra conversa ou com o número ambíguo (efeito opt_out, consumiu true); (item 16) o acesso com negação vai ao dono; (item 17) falta/remarcar com um número de dia não entendido vai ao dono; (item 9) o dia pedido ou o fim do recusado a mais de cliente_pedido_max_du dias úteis do combinado vai ao dono.';

-- ── 4. Portas ───────────────────────────────────────────────────────────────────────────────────────────

-- As novas: internas (security definer, search_path fixo) — ninguém de fora, nem o service_role. Só outra função as chama
-- (a resposta do cliente, o botão, o gatilho).
revoke all on function
  public._agenda_cliente_motivo_texto(text),
  public._agenda_cliente_outra_conversa(uuid[], text, timestamptz, timestamptz),
  public._agenda_cliente_avisar_recusa(),
  public._pedir_confirmacao(uuid, uuid, timestamptz)
  from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas delas (create or replace não muda a ACL; repetidas para a migration se bastar):
revoke all on function
  public._agenda_cliente_revalidar(uuid, timestamptz), public._agenda_cliente_enfileirar(uuid, timestamptz),
  public._agenda_cliente_confirmar(date, timestamptz),
  public._agenda_cliente_decidir(uuid, smallint, uuid, text, text, timestamptz),
  public._agenda_cliente_data_da_resposta(text, date, date)
  from public, anon, authenticated, service_role;
-- o botão: authenticated (o cargo é conferido dentro) e service_role
revoke all on function public.pedir_confirmacao_do_agendamento(uuid, uuid) from public, anon;
grant execute on function public.pedir_confirmacao_do_agendamento(uuid, uuid) to authenticated, service_role;
-- a resposta do cliente: só o webhook (service_role)
revoke all on function public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.agenda_resposta_do_cliente(text, text, uuid, text, text, text, timestamptz) to service_role;
