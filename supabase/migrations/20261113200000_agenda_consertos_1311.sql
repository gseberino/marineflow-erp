-- Agenda de Produção: consertos de 13/11/2026. Só funções e 1 tabela NOVA: nenhuma tabela existente muda (nenhum ALTER TABLE), nenhum dado, cron ou tela.
-- Roteiro: agenda-pesquisa/fila-do-dono/consertos-1311-publicar.md; notas: notas-fase7g.md, seção "Consertos 13/11". Prova: supabase/tests/agenda_consertos_1311.sql
-- (begin/rollback, na bancada) e supabase/tests/agenda_consertos_1311_pos_deploy.sql (só leitura, em produção depois de aplicar).
--
-- (a) A mensagem ao cliente não caía quando o plano caía. Nelson, OS-00112: em 11/11 10:37 a vigia marcou a OS (awaiting_parts → scheduled) e a rodada preparou
--     o M3 (material_chegou), que ficou esperando o dono (*manda cliente*); às 22:00 a vigia desmarcou (20 alocações canceladas, scheduled → awaiting_parts:
--     entraram 5 peças novas na OS às 21:49) e a mensagem seguiu esperando, pedindo *manda cliente* de algo que já não era verdade, até vencer (12/11 22:00).
--     A revalidação da hora de sair a recusaria (status), mas o pedido falso ficava na fila do dono. Nenhum caminho que derruba o plano olhava as mensagens: a
--     vigia (desmarcar, cancelar, status), o *desfaz*, a tela, o assistente e o motor mudam alocações e status pela porta, e só a hora de sair revalidava.
--     O conserto: _agenda_cliente_premissa (nova) é o pedaço da revalidação que é do PLANO e do estado da OS (o status; o dia de que a mensagem fala ou o fim;
--     a semana fora da faixa dita; o M11 com a OS já atendida), e o passo fila (_agenda_cliente_fila, que roda em todo tique e em qualquer modo, depois da vigia
--     no mesmo tique) ganha o (5): a mensagem em ligado ainda não enviada cuja premissa caiu fica recusada com o motivo (status, data_mudou, desatualizada), e a
--     pergunta dela sai da fila do dono (descartada). Vale para todos os tipos cuja premissa depende do plano. Em teste (sombra), nada muda.
-- (b) O fechamento contava como mostrada a linha da agenda que só tinha ido para a FILA (secretario-tarde.ts: r.enviado = enfileirado). Agora as linhas ficam
--     guardadas com o id da linha da fila da tarde (agenda_fechamento_guardar, nova; a tabela agenda_fechamento_fila, nova) e só contam (a pergunta mostrada,
--     o prazo veto_ate, a ação contada) quando a fila diz sent, na hora em que saiu: _agenda_fechamento_conferir (nova), chamada pelo motor de 15 min dentro de
--     agenda_aviso_conferir (recriada, o passo (4)). A linha da fila que falhou, sumiu ou não saiu em 1 dia cai, e as perguntas e as ações voltam no próximo
--     fechamento. agenda_fechamento_registrar não muda. O TS (ai-daily-briefing) muda junto: chama agenda_fechamento_guardar com o id da fila.
-- (c) NOVO-agenda-296: _agenda_porque_da_os dizia "marcado pelo gestor" / "marcado por você" na chave quem_texto de uma OS só reservada. Agora "reservado …".
-- (d) Pedido A-2 da F5 do retorno: _agenda_rotulo_os diz "foi recusado" (era "foi recusado (ou venceu)").
--
-- AS RECRIADAS partem do corpo VIGENTE em produção (q0.sh, 13/11): o montador (agenda-pesquisa/c1311/montar.mjs) copia a definição mais nova do repo, confere o
-- md5 do corpo (sem CR) e do comment contra o de produção e recusa se diferir; tirados os blocos "-- CONSERTO 13/11 (a|b):" (e, em (c) e (d), a linha marcada
-- de volta), cada uma é a origem byte a byte. O create or replace mantém dono, ACL e defaults; as portas de antes são reafirmadas no fim.
--   _agenda_cliente_fila      20261028100800:921  24775239340211340eb435c32bbab9b3
--   agenda_aviso_conferir     20261030100300:556  9cae4565a4d09039c4e692ea56b51e55
--   _agenda_porque_da_os      20261112100200:431  b25261435b91ff328b9fa85ad58b73e5
--   _agenda_rotulo_os         20261024160400:171  c5bd3e8e361e4b545d82bf8ab784c5cf
-- A F5 do retorno (20270112100000–100900) não recria nenhuma destas nem cria as novas (conferido em session/retorno-f5, 2bab9f1b): vale com e sem a F5.
--
-- DESFAZER: agenda-pesquisa/consertos-1311/volta-consertos-1311.sql (numa transação: confere o que a fila já mandou, as 4 recriadas voltam ao corpo e ao
-- comment de antes, agenda_fechamento_guardar passa a registrar NA HORA, como antes do conserto, e _agenda_cliente_premissa sai; a tabela e
-- _agenda_fechamento_conferir ficam como rastro). Mensagem que caiu não volta (ela não sairia: a revalidação a recusaria na hora).
-- Sem begin/commit: o aplicar.sh roda numa transação e falha inteiro. IDEMPOTENTE: create or replace, if not exists, drop … if exists, revoke/grant e comment.
-- ── 1. (a) A premissa do plano da mensagem ao cliente ───────────────────────────────────────────────────────────────────────────────────
-- O pedaço de _agenda_cliente_revalidar que é do PLANO e do estado da OS, com as mesmas regras, copiadas do corpo vigente (20261109101200:982, md5
-- c16166497a20198f48c6ef634ab8f403, o de produção em 13/11): o passo 2 (o status), o status do M11 (_agenda_cliente_ja_atendida), a semana (o status e o
-- plano fora da semana dita) e o passo 3 (o dia de que a mensagem fala, o fim). Fica de fora o que não é do plano nem da OS: o opt-out, a conversa (d10), o
-- telefone, o modo e o tipo em teste, o material da data firme (d09), o "passou da data" do atraso, o mesmo tipo em 24 h, o prometido da semana que mudou e o
-- texto. Por isso o que ela recusa a revalidação também recusa (a regra é a mesma, e a revalidação devolve não nulo se qualquer passo dela falha), e a
-- mensagem que ela derruba nunca sairia; a conversa que falta (o caso mais comum fora do plano) não esconde o plano que caiu.
create or replace function public._agenda_cliente_premissa(p_msg uuid, p_agora timestamptz)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  m           public.agenda_cliente_mensagens%rowtype;
  so          record;
  v_hoje      date := (p_agora at time zone 'America/Sao_Paulo')::date;
  v_plano     jsonb;
  v_agora_dia date;
begin
  if p_msg is null or p_agora is null then
    raise exception '_agenda_cliente_premissa: sem a mensagem ou a hora.' using errcode = '22004';
  end if;
  select * into m from public.agenda_cliente_mensagens where id = p_msg;
  if not found then
    return null;
  end if;
  -- o status da OS (o passo 2 de _agenda_cliente_revalidar; a faturada vale como concluída)
  select o.status, o.delivered_at, o.scheduled_start_at, o.scheduled_end_at into so
    from public.service_orders o where o.id = m.service_order_id;
  if found and so.status = 'invoiced' then
    so.status := 'completed';
  end if;
  if not found or so.status in ('cancelled', 'draft')
     or (m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
         and so.status in ('awaiting_parts', 'awaiting_client', 'completed'))
     or (m.tipo = 'andamento' and so.status <> 'in_progress')
     or (m.tipo in ('pronto', 'pronto_lembrete') and (so.status <> 'completed' or so.delivered_at is not null))
     or (m.tipo = 'pos_servico' and so.status <> 'completed')
     or (m.tipo = 'pode_atrasar' and so.status = 'completed') then
    return 'status';
  end if;
  -- o M11 (onde fica): a OS já atendida
  if m.tipo = 'onde_fica' and public._agenda_cliente_ja_atendida(m.service_order_id) is not null then
    return 'status';
  end if;
  -- a semana prevista (M12): a OS começada, esperando peça ou cliente, ou concluída; o 1º ou o último dia do plano de agora fora da semana dita
  if m.tipo = 'semana' then
    if so.status in ('awaiting_parts', 'awaiting_client', 'in_progress', 'completed') then
      return 'status';
    end if;
    v_plano := public._agenda_plano_da_os(m.service_order_id, v_hoje);
    if m.faixa_de is null or m.faixa_ate is null or (v_plano ->> 'proximo_dia') is null or (v_plano ->> 'ultimo_dia') is null
       or (v_plano ->> 'proximo_dia')::date not between m.faixa_de and m.faixa_ate
       or (v_plano ->> 'ultimo_dia')::date not between m.faixa_de and m.faixa_ate then
      return 'desatualizada';
    end if;
  end if;
  -- o dia de que a mensagem fala (o próximo dia do plano; sem plano no registro, o dia agendado da OS) e, nos tipos de fim, o último dia (o passo 3)
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
  if m.tipo = 'pode_atrasar' and m.variante = 'remarcado' and m.base #>> '{dados,forma}' = 'fim'
     and (v_plano ->> 'ultimo_dia')::date is distinct from (m.base ->> 'fim')::date then
    return 'data_mudou';
  end if;
  return null;
end;
$function$;

comment on function public._agenda_cliente_premissa(uuid, timestamptz) is
  'Agenda de Produção (consertos de 13/11, (a)): a premissa de PLANO de uma mensagem ao cliente ainda vale em p_agora? null = vale (ou a mensagem não existe); senão o motivo, com as regras de _agenda_cliente_revalidar que são do plano e do estado da OS: status (o passo 2; o M11 com a OS já atendida; a semana com a OS começada, esperando peça ou cliente, ou concluída), desatualizada (a semana: o 1º ou o último dia do plano de agora fora da semana dita) e data_mudou (o passo 3: o dia de que a mensagem fala ou o fim mudou). Fora: opt-out, conversa, telefone, modo, tipo em teste, material, passou da data, mesmo tipo em 24 h, o prometido da semana que mudou e o texto (a revalidação da hora de sair continua cuidando deles). O que ela recusa, a revalidação também recusa. STABLE, invoker, sem grant (o passo fila a chama).';

-- ── 2. (a) O passo fila: (5) o plano caiu ─────────────────────────────────────────────────────────────────────────────────────────────
-- O corpo de 20261028100800:921 (md5 sem CR 24775239340211340eb435c32bbab9b3, o de produção em 13/11) + só os blocos "-- CONSERTO 13/11 (a):".
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
  -- CORREÇÃO FASE 5: (item 3) as que o provedor não entregou
  n_entrega int := 0;
  -- CORREÇÃO FASE 5: fim
  -- CONSERTO 13/11 (a): a premissa de plano de cada mensagem que ainda não saiu, e quantas caíram
  v_c13_mot  text;
  n_c13_caiu int := 0;
  -- CONSERTO 13/11 (a): fim
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
  -- CORREÇÃO FASE 5: (item 3) a linha que o provedor não entregou (o worker desistiu depois das tentativas: failed) não
  -- deixa a mensagem "enfileirada" para sempre (o gatilho do envio só olha sent): fica recusada com o motivo entrega — a
  -- aprovada pelo dono avisa pelo gatilho do "não saiu" (C1); o aviso de atraso, pelo passo atraso
  for r in
    select m.id from public.agenda_cliente_mensagens m
      join public.whatsapp_send_queue q on q.source = 'agenda-cliente' and q.source_ref_id = m.id
     where m.estado = 'enfileirada' and q.status = 'failed'
     order by m.enviar_em, m.id
  loop
    update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = 'entrega'
     where id = r.id and estado = 'enfileirada';
    if found then n_entrega := n_entrega + 1; end if;
  end loop;
  -- CORREÇÃO FASE 5: fim
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
  -- CONSERTO 13/11 (a): (5) o plano caiu: a mensagem em ligado que ainda não saiu (registrada ou esperando o dono, também a aprovada que espera a hora) cuja
  -- premissa de plano não vale mais (_agenda_cliente_premissa: a vigia desmarcou, as alocações foram canceladas ou mudaram de dia, a OS saiu do estado que a
  -- mensagem supõe — por qualquer caminho: a vigia, o *desfaz*, a tela, o assistente, o motor) cai agora, com o motivo, e a pergunta dela (cliente_aprovar ou
  -- cliente_aviso) sai da fila do dono (_agenda_cliente_cancelar: recusada e a pergunta descartada). Antes ela esperava a hora de sair (a revalidação a recusava)
  -- ou vencia, e o fechamento e o aviso pediam *manda cliente* de uma mensagem que já não era verdade (Nelson, OS-00112, 11/11). Depois do (3) e do (4): a que é
  -- hora de mandar passa pelo enfileirar (que revalida inteiro) e a vencida vence como antes. Em teste (sombra), nada.
  for r in
    select m.id from public.agenda_cliente_mensagens m
     where m.modo = 'ligado' and m.estado in ('registrada', 'aguardando_dono')
     order by m.enviar_em, m.id
  loop
    v_c13_mot := public._agenda_cliente_premissa(r.id, p_agora);
    continue when v_c13_mot is null;
    if public._agenda_cliente_cancelar(r.id, v_c13_mot,
         case v_c13_mot when 'status' then 'o plano caiu: a OS não está mais como a mensagem ao cliente supunha, e ela não sai'
                        when 'data_mudou' then 'o plano caiu: o dia de que a mensagem ao cliente falava mudou, e ela não sai'
                        else 'o plano caiu: o plano saiu da semana que a mensagem ao cliente dizia, e ela não sai' end) then
      n_c13_caiu := n_c13_caiu + 1;
    end if;
  end loop;
  -- CONSERTO 13/11 (a): fim
  -- CONSERTO 13/11 (a): a contagem plano_caiu só quando alguma caiu (sem ela, a chave não existe: o de antes, byte a byte)
  if n_c13_caiu > 0 then
    return jsonb_build_object('canceladas', n_modo + n_jan + n_reval, 'pelo_modo', n_modo, 'pela_janela', n_jan,
                              'revalidadas', n_reval, 'enfileiradas', n_fila, 'esperando', n_espera, 'recusadas', n_recus,
                              'vencidas', n_venc, 'entrega', n_entrega, 'plano_caiu', n_c13_caiu);
  end if;
  -- CONSERTO 13/11 (a): fim
  -- CORREÇÃO FASE 5: (item 3) a entrega que falhou nas contagens
  return jsonb_build_object('canceladas', n_modo + n_jan + n_reval, 'pelo_modo', n_modo, 'pela_janela', n_jan,
                            'revalidadas', n_reval, 'enfileiradas', n_fila, 'esperando', n_espera, 'recusadas', n_recus,
                            'vencidas', n_venc, 'entrega', n_entrega);
  -- CORREÇÃO FASE 5: fim
  return jsonb_build_object('canceladas', n_modo + n_jan + n_reval, 'pelo_modo', n_modo, 'pela_janela', n_jan,
                            'revalidadas', n_reval, 'enfileiradas', n_fila, 'esperando', n_espera, 'recusadas', n_recus,
                            'vencidas', n_venc);
end;
$function$;

comment on function public._agenda_cliente_fila(date, timestamptz) is
  'Agenda de Produção (Fase 5, P2), passo do cliente "fila" (roda sempre, até com tudo desligado; a rodada do P3 o chama antes de tudo): (1) a linha agenda-cliente pendente sem a mensagem, com modo_cliente ou o tipo fora de ligado, ou que já devia ter saído e agora está fora da janela dela, vira failed e a mensagem fica recusada (janela, modo, tipo_em_teste); (2) a pendente que a revalidação recusa vira failed/recusada com o motivo; (3) em ligado, a registrada (ou esperando o dono e já aprovada) livre ou aprovada com enviar_em até o próximo tique vai a _agenda_cliente_enfileirar; (4) a registrada ou esperando o dono que passou de valida_ate fica recusada/vencida (a pedida ou crítica com a aprovação vencida e a pergunta vencida). {canceladas, pelo_modo, pela_janela, revalidadas, enfileiradas, esperando, recusadas, vencidas}. CORREÇÃO FASE 5 (C2, item 3): antes do (3), a enfileirada cuja linha da fila o provedor não entregou (failed) fica recusada com o motivo entrega; a contagem entrega. CONSERTO 13/11 (a): (5), depois do (3) e do (4), a mensagem em ligado que ainda não saiu (registrada ou esperando o dono, também a aprovada esperando a hora) cuja premissa de plano não vale mais (_agenda_cliente_premissa: status, data_mudou, desatualizada na semana) cai com o motivo, e a pergunta dela sai da fila do dono (_agenda_cliente_cancelar: recusada, a pergunta descartada); a contagem plano_caiu só quando alguma caiu. Em teste (sombra), nada.';

-- ── 3. (b) O fechamento só conta como mostrado o que a fila MANDOU ──────────────────────────────────────────────────────────────────────
-- O Secretário (ai-daily-briefing, secretario-tarde.ts) grava e enfileira a tarde numa transação (resumo_tarde_registrar) e chamava agenda_fechamento_registrar
-- logo depois: "enviado" ali quer dizer "foi para a fila". Com o WhatsApp fora, a pergunta contava como mostrada (mostrada_vezes, mostrada_em) e o prazo
-- (veto_ate) corria sem o dono ter lido; a ação ficava contada e não voltava. Agora as linhas do fechamento ficam GUARDADAS com o id da linha da fila da tarde
-- (secretario_tarde:<dia>:<telefone>) e só contam quando a fila diz 'sent', na hora em que saiu (sent_at) — o mesmo padrão do guardado da voz ligada (P4.5) e do
-- aviso do gestor (agenda_aviso_conferir). A linha da fila que falhou, sumiu ou não saiu em 1 dia não conta: as perguntas e as ações voltam no próximo
-- fechamento, como hoje quando o registro falha. agenda_fechamento_registrar não muda: quem conta é ela, chamada com p_agora = sent_at.

-- A tabela: uma linha por fechamento enfileirado (a linha da fila, única). Nunca apagada (_agenda_registro_nao_apaga); só as funções escrevem.
create table if not exists public.agenda_fechamento_fila (
  id           uuid primary key default gen_random_uuid(),
  dia          date not null,
  fila_id      uuid not null unique,
  via          text not null default 'fechamento' check (via in ('fechamento')),
  linhas       jsonb not null check (jsonb_typeof(linhas) = 'array'),
  estado       text not null default 'esperando' check (estado in ('esperando', 'registrada', 'caiu')),
  motivo       text check (motivo in ('fila_falhou', 'fila_sumiu', 'nao_saiu', 'erro')),
  enviada_em   timestamptz,
  resultado    jsonb,
  criada_em    timestamptz not null default now(),
  resolvida_em timestamptz,
  constraint fechamento_fila_caiu_coerente      check ((estado = 'caiu') = (motivo is not null)),
  constraint fechamento_fila_registrada_coerente check ((estado = 'registrada') = (enviada_em is not null)),
  constraint fechamento_fila_resolvida_coerente  check ((estado = 'esperando') = (resolvida_em is null))
);

comment on table public.agenda_fechamento_fila is
  'Agenda de Produção (consertos de 13/11, (b)): as linhas da agenda que o fechamento das 17:30 levou, guardadas com o id da linha da fila da tarde. Só contam como mostradas (agenda_fechamento_registrar, com p_agora = sent_at) quando a fila diz sent; a linha da fila que falhou, sumiu ou não saiu em 1 dia cai, e as perguntas e as ações voltam no próximo fechamento. Escrita só por agenda_fechamento_guardar e _agenda_fechamento_conferir; nunca apagada. Só o administrador e o financeiro leem.';

drop trigger if exists agenda_fechamento_fila_nao_apaga on public.agenda_fechamento_fila;
create trigger agenda_fechamento_fila_nao_apaga before delete on public.agenda_fechamento_fila
  for each row execute function public._agenda_registro_nao_apaga();

alter table public.agenda_fechamento_fila enable row level security;
drop policy if exists agenda_fechamento_fila_leitura on public.agenda_fechamento_fila;
create policy agenda_fechamento_fila_leitura on public.agenda_fechamento_fila
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));
revoke all on table public.agenda_fechamento_fila from public, anon, authenticated;
grant select on table public.agenda_fechamento_fila to authenticated;
grant all on table public.agenda_fechamento_fila to service_role;

-- A conferência: a linha esperando cuja fila mandou conta agora (na hora em que saiu); a que a fila desistiu, sumiu ou não saiu em 1 dia cai.
create or replace function public._agenda_fechamento_conferir(p_agora timestamptz, p_id uuid default null)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c_espera constant interval := interval '1 day';   -- a fila para de tentar às 19:30 (tentativasAte): em 1 dia ela mandou ou desistiu
  r      record;
  v_r    jsonb;
  v_saiu timestamptz;
  v_est  text;
  v_msg  text;
  n_reg  int := 0;
  n_caiu int := 0;
  n_perg int := 0;
  n_acao int := 0;
begin
  if p_agora is null then
    raise exception '_agenda_fechamento_conferir: sem a hora.' using errcode = '22004';
  end if;
  for r in
    select f.id, f.dia, f.via, f.linhas, f.criada_em, q.id as q_id, q.status as q_status, q.sent_at
      from public.agenda_fechamento_fila f
      left join public.whatsapp_send_queue q on q.id = f.fila_id
     where f.estado = 'esperando' and (p_id is null or f.id = p_id)
     order by f.criada_em, f.id
       for update of f
  loop
    if r.q_status = 'sent' then
      v_saiu := coalesce(r.sent_at, p_agora);
      -- cada fechamento no seu bloco: o que não conta (uma linha que não fecha) cai com o motivo erro e vai a app_error_logs uma vez, sem
      -- derrubar os outros nem voltar a cada tique
      begin
        v_r := public.agenda_fechamento_registrar(r.dia, r.linhas, r.via, v_saiu);
        update public.agenda_fechamento_fila
           set estado = 'registrada', enviada_em = v_saiu, resolvida_em = p_agora, resultado = v_r
         where id = r.id and estado = 'esperando';
        n_reg := n_reg + 1;
        n_perg := n_perg + coalesce((v_r ->> 'perguntas')::int, 0);
        n_acao := n_acao + coalesce((v_r ->> 'acoes')::int, 0);
      exception when others then
        get stacked diagnostics v_est = returned_sqlstate, v_msg = message_text;
        update public.agenda_fechamento_fila
           set estado = 'caiu', motivo = 'erro', resolvida_em = p_agora, resultado = jsonb_build_object('sqlstate', v_est, 'erro', left(v_msg, 300))
         where id = r.id and estado = 'esperando';
        perform public.log_app_error('db', 'agenda: o fechamento que a fila mandou não contou: ' || v_msg, 'agenda', 'fechamento:conferir', 'error',
                                     jsonb_build_object('sqlstate', v_est, 'fechamento', r.id, 'dia', r.dia));
        n_caiu := n_caiu + 1;
      end;
    elsif r.q_id is null or r.q_status in ('failed', 'cancelled') or r.criada_em < p_agora - c_espera then
      update public.agenda_fechamento_fila
         set estado = 'caiu', resolvida_em = p_agora,
             motivo = case when r.q_id is null then 'fila_sumiu' when r.q_status in ('failed', 'cancelled') then 'fila_falhou' else 'nao_saiu' end
       where id = r.id and estado = 'esperando';
      n_caiu := n_caiu + 1;
    end if;
  end loop;
  return jsonb_build_object('registradas', n_reg, 'caidas', n_caiu, 'perguntas', n_perg, 'acoes', n_acao);
end;
$function$;

comment on function public._agenda_fechamento_conferir(timestamptz, uuid) is
  'Agenda de Produção (consertos de 13/11, (b)): o que a fila fez com os fechamentos guardados (agenda_fechamento_fila esperando; p_id = só aquele). A fila mandou (sent): agenda_fechamento_registrar com as linhas guardadas e p_agora = sent_at (a pergunta mostrada na hora em que saiu, o prazo escrito no texto, a ação contada), e a linha fica registrada. A fila desistiu (failed, cancelled), a linha dela sumiu ou não saiu em 1 dia: cai (fila_falhou, fila_sumiu, nao_saiu) e nada conta (volta no próximo fechamento). O que não conta por erro (uma linha que não fecha) cai com erro, uma vez, e vai a app_error_logs (agenda / fechamento:conferir). Pendente: espera. {registradas, caidas, perguntas, acoes}. Invoker, sem grant: agenda_aviso_conferir (o motor de 15 min) e agenda_fechamento_guardar a chamam.';

-- A guarda: o Secretário chama depois de gravar e enfileirar a tarde (r.novo && r.enviado), com o id da linha da fila da tarde. Se a fila já mandou (o worker
-- foi mais rápido), conta na hora; senão fica esperando a conferência do motor.
create or replace function public.agenda_fechamento_guardar(p_hoje date, p_linhas jsonb, p_fila uuid, p_via text default 'fechamento',
                                                            p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  q    record;
  v_id uuid;
  v_r  jsonb;
begin
  if p_hoje is null or p_fila is null or p_agora is null then
    raise exception 'agenda_fechamento_guardar: sem o dia, a linha da fila ou a hora.' using errcode = '22004';
  end if;
  if p_via is null or p_via <> 'fechamento' then
    raise exception 'Por onde foi mostrado: "%" (só o fechamento espera a fila).', coalesce(p_via, '') using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_linhas, '[]'::jsonb)) <> 'array' then
    raise exception 'As linhas mostradas vêm numa lista.' using errcode = '22023';
  end if;
  select f.id, f.status into q from public.whatsapp_send_queue f where f.id = p_fila;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sem_fila', 'perguntas', 0, 'acoes', 0);
  end if;
  insert into public.agenda_fechamento_fila (dia, fila_id, via, linhas, criada_em)
  values (p_hoje, p_fila, p_via, coalesce(p_linhas, '[]'::jsonb), p_agora)
  on conflict (fila_id) do nothing
  returning id into v_id;
  if v_id is null then
    return jsonb_build_object('ok', true, 'estado', 'ja_existe', 'perguntas', 0, 'acoes', 0);
  end if;
  if q.status = 'sent' then
    v_r := public._agenda_fechamento_conferir(p_agora, v_id);
    return jsonb_build_object('ok', true, 'estado', 'registrada', 'id', v_id,
                              'perguntas', coalesce((v_r ->> 'perguntas')::int, 0), 'acoes', coalesce((v_r ->> 'acoes')::int, 0));
  end if;
  return jsonb_build_object('ok', true, 'estado', 'esperando', 'id', v_id, 'perguntas', 0, 'acoes', 0);
end;
$function$;

comment on function public.agenda_fechamento_guardar(date, jsonb, uuid, text, timestamptz) is
  'Agenda de Produção (consertos de 13/11, (b)): as linhas da agenda que o fechamento levou ({pergunta_id, acao_ids, pergunta_ids?, veto_ate?, veto_diria?}, as de agenda_fechamento_registrar), guardadas com o id da linha da fila da tarde (agenda_fechamento_fila). Só contam como mostradas quando a fila diz sent (_agenda_fechamento_conferir; o motor de 15 min confere em agenda_aviso_conferir); se a fila já mandou, contam agora, na hora em que saiu. A mesma linha da fila 2x = ja_existe (nada conta de novo). Sem a linha da fila = {ok:false, motivo:sem_fila} (nada guardado). {ok, estado: esperando|registrada|ja_existe, id, perguntas, acoes}. Só o fechamento (p_via). Definer, só o service_role.';

-- ── 4. (b) A conferência do aviso do gestor confere também o fechamento ──────────────────────────────────────────────────────────────
-- O corpo de 20261030100300:556 (md5 sem CR 9cae4565a4d09039c4e692ea56b51e55, o de produção em 13/11) + só os blocos "-- CONSERTO 13/11 (b):". O motor de 15 min
-- (task-automations, agenda-aviso.ts) a chama em todo tique, em qualquer modo, e lê só enviados, recusados e devolvidas: nenhum TS muda por isto.
create or replace function public.agenda_aviso_conferir(p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  r       record;
  v_lig   boolean;
  v_mot   text;
  v_saiu  timestamptz;
  v_env   int := 0;
  v_rec   int := 0;
  v_dev   int := 0;
  v_n     int;
  -- CONSERTO 13/11 (b): o fechamento que a fila mandou
  v_c13_fech jsonb;
  v_c13_est  text;
  v_c13_msg  text;
  -- CONSERTO 13/11 (b): fim
begin
  if p_agora is null then
    raise exception 'agenda_aviso_conferir: sem a hora' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext('agenda_dono_aviso'));
  v_lig := public._agenda_aviso_ligado();

  -- (1) a fila velha: a linha que ainda espera e não sai mais (a janela dela passou, é domingo, ou o aviso desligou) falha,
  -- e o aviso fica recusado com o motivo
  for r in select q.id as fila_id, q.scheduled_for, v.id
             from public.agenda_dono_avisos v
             join public.whatsapp_send_queue q on q.id = v.fila_id
            where v.estado = 'enfileirada' and q.source = 'agenda-dono' and q.status = 'pending' and q.scheduled_for <= p_agora
            order by v.criada_em, v.id loop
    v_mot := case when not v_lig then 'modo' else public._agenda_aviso_fora_da_janela(r.scheduled_for, p_agora) end;
    continue when v_mot is null;
    update public.whatsapp_send_queue
       set status = 'failed', processing_started_at = null,
           failed_reason = 'agenda-dono: ' || case v_mot when 'modo' then 'o aviso do gestor saiu de ligado'
                                                         when 'domingo' then 'domingo, não sai'
                                                         else 'não saiu dentro da janela' end
     where id = r.fila_id;
    update public.agenda_dono_avisos set estado = 'recusada', recusa_motivo = v_mot where id = r.id and estado = 'enfileirada';
  end loop;

  -- (2) o que a fila mandou: a ação conta na hora em que saiu, o prazo do *desfaz* começa ali (nunca menos do que já era) e a
  -- pergunta conta como mostrada; o que a fila desistiu (ou a linha sumiu) fica recusado
  for r in select v.*, q.status as fila_status, q.sent_at
             from public.agenda_dono_avisos v
             left join public.whatsapp_send_queue q on q.id = v.fila_id
            where v.estado = 'enfileirada'
            order by v.criada_em, v.id loop
    if r.fila_status = 'sent' then
      v_saiu := coalesce(r.sent_at, p_agora);
      update public.agenda_acoes a
         set contada_em = v_saiu,
             desfazivel_ate = case when a.desfazivel_ate is not null and a.desfeita_em is null
                                   then greatest(a.desfazivel_ate, v_saiu + cf.desfazer_validade) else a.desfazivel_ate end
       where a.id = any (r.acao_ids) and a.contada_via = 'aviso';
      update public.agenda_perguntas q
         set mostrada_vezes = least(q.mostrada_vezes + 1, 50), mostrada_em = v_saiu, mostrada_via = 'aviso'
       where q.id = any (r.pergunta_ids) and q.estado = 'aberta';
      update public.agenda_dono_avisos set estado = 'enviada', enviada_em = v_saiu where id = r.id;
      v_env := v_env + 1;
    elsif r.fila_status is null or r.fila_status = 'failed' then
      update public.agenda_dono_avisos set estado = 'recusada', recusa_motivo = 'fila' where id = r.id;
    end if;
  end loop;

  -- (3) o que não saiu (recusado aqui, pelo worker na hora de mandar ou pela trava): as ações voltam a "por contar" — só as
  -- que este aviso marcou (a mesma hora) — e vão no próximo aviso ou no fechamento
  for r in select v.* from public.agenda_dono_avisos v
            where v.estado = 'recusada' and v.devolvida_em is null
            order by v.criada_em, v.id loop
    update public.agenda_acoes a set contada_em = null, contada_via = null
     where a.id = any (r.acao_ids) and a.contada_via = 'aviso' and a.contada_em = r.enviar_em;
    get diagnostics v_n = row_count;
    update public.agenda_dono_avisos set devolvida_em = p_agora where id = r.id;
    v_rec := v_rec + 1;
    v_dev := v_dev + v_n;
  end loop;

  -- CONSERTO 13/11 (b): (4) o fechamento que a fila mandou: as linhas da agenda guardadas com a linha da fila da tarde (agenda_fechamento_guardar) contam agora,
  -- na hora em que a tarde saiu; a que a fila desistiu, sumiu ou não saiu em 1 dia cai e volta no próximo fechamento (_agenda_fechamento_conferir). O erro dela
  -- não derruba o aviso: vai a app_error_logs (agenda / fechamento:conferir) e a conferência tenta de novo no próximo tique. A chave fechamento só quando houve
  -- (sem ela, o de antes, byte a byte).
  begin
    v_c13_fech := public._agenda_fechamento_conferir(p_agora);
  exception when others then
    get stacked diagnostics v_c13_est = returned_sqlstate, v_c13_msg = message_text;
    perform public.log_app_error('db', 'agenda: o fechamento que a fila mandou não foi conferido: ' || v_c13_msg, 'agenda', 'fechamento:conferir', 'error',
                                 jsonb_build_object('sqlstate', v_c13_est, 'p_agora', p_agora));
    v_c13_fech := null;
  end;
  if coalesce((v_c13_fech ->> 'registradas')::int, 0) + coalesce((v_c13_fech ->> 'caidas')::int, 0) > 0 then
    return jsonb_build_object('enviados', v_env, 'recusados', v_rec, 'devolvidas', v_dev, 'fechamento', v_c13_fech);
  end if;
  -- CONSERTO 13/11 (b): fim
  return jsonb_build_object('enviados', v_env, 'recusados', v_rec, 'devolvidas', v_dev);
end;
$function$;

comment on function public.agenda_aviso_conferir(timestamptz) is
  'Agenda de Produção (correção de 29/10, P4): o que a fila fez com os avisos do gestor. (1) A linha agenda-dono pendente que não sai mais (a janela dela passou, domingo, ou o aviso desligado) vira falha e o aviso fica recusado (janela, domingo, modo). (2) A que saiu (sent): as ações contadas na hora do envio (sent_at), o desfazivel_ate de cada uma = o maior entre o de antes e sent_at + desfazer_validade (o prazo do *desfaz* a partir de quando o dono soube), as perguntas abertas mostradas (+1, mostrada_em, mostrada_via aviso), o aviso enviado; a que a fila desistiu (ou sumiu) = recusada/fila. (3) O aviso recusado (aqui, pelo worker ou pela trava) devolve as ações que marcou (contada_* nulos) uma vez (devolvida_em). {enviados, recusados, devolvidas}. Definer, só o service_role. CONSERTO 13/11 (b): (4) o fechamento que a fila mandou (_agenda_fechamento_conferir): as linhas da agenda guardadas com a linha da fila da tarde contam na hora em que a tarde saiu (sent_at); a que a fila desistiu ou que não saiu em 1 dia cai e volta no próximo fechamento. O erro dela vai a app_error_logs (agenda / fechamento:conferir) sem derrubar o aviso. A chave fechamento {registradas, caidas, perguntas, acoes} só quando houve.';

-- ── 5. (c) O porquê de uma OS: quem_texto da reserva (NOVO-agenda-296) ────────────────────────────────────────────────────────────────
-- O corpo de 20261112100200:431 (md5 sem CR b25261435b91ff328b9fa85ad58b73e5, o de produção em 13/11) com 1 linha trocada, marcada "-- CONSERTO 13/11 (c)": na
-- reserva, quem_texto diz "reservado pelo gestor" / "reservado por você" (o texto longo já dizia "reservei" / "você reservou"; a tela e o cartão já escreviam assim
-- pelo estado). A marcada não muda.
create or replace function public._agenda_porque_da_os(p_os uuid, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  c_max   constant int := 600;   -- estrutural: o teto do porquê de uma OS (§6.2)
  v_uid   uuid := auth.uid();
  v_papel text;
  so      record;
  v_rot   text;
  v_tipo  text;
  a       public.agenda_alocacoes;
  ac      public.agenda_acoes;
  v_alocs jsonb;
  v_dias  date[];
  v_pess  text;
  v_quem  text;
  v_f     jsonb;
  v_m     jsonb;
  v_sup   jsonb;
  v_crit  text;
  v_deg   text;
  v_mot   text;
  v_perg  text;
  v_txt   text;
begin
  -- Quem vê: com login, só admin/financeiro; sem login, só o service_role, ou quem chama de dentro, sem JWT (molde de agenda_perguntas_em_ordem)
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'O porquê da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'O porquê da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_porque_da_os: sem a OS, o dia ou a hora.' using errcode = '22004';
  end if;
  select s.id, s.status into so from public.service_orders s where s.id = p_os;
  if not found then
    raise exception 'Não encontrei esse serviço.' using errcode = 'P0002';
  end if;
  v_rot := public._agenda_rotulo_da_os(p_os);

  if not exists (select 1 from public.os_carteira(p_hoje) k where k.service_order_id = p_os) then
    return jsonb_build_object('estado', 'fora_da_carteira', 'quem', null, 'quem_texto', null, 'fonte', null, 'fonte_texto', null, 'suposicoes', '[]'::jsonb,
                              'criterio_texto', null, 'degrau_texto', null, 'zona', null, 'motivo_fora', null,
                              'texto', format('Essa OS não está mais na carteira (%s).', public._agenda_status_texto(so.status)));
  end if;

  -- o bloco vigente de hoje em diante: o compromisso; sem ele, a reserva
  select case when bool_or(x.tipo <> 'reserva') then 'compromisso' when count(*) > 0 then 'reserva' end into v_tipo
    from public.agenda_alocacoes x
   where x.service_order_id = p_os and x.estado in ('publicada', 'fixada') and x.dia >= p_hoje;

  if v_tipo is null then
    v_mot := nullif(btrim(public._agenda_classe_agora(p_os, p_hoje) ->> 'texto'), '');
    v_perg := (select e ->> 'linha' from jsonb_array_elements(public.agenda_perguntas_em_ordem(p_hoje, p_agora)) e
                where e ->> 'os' = p_os::text and nullif(btrim(e ->> 'linha'), '') is not null
                order by (e ->> 'ordem')::int limit 1);
    return jsonb_build_object('estado', 'fora', 'quem', null, 'quem_texto', null, 'fonte', null, 'fonte_texto', null, 'suposicoes', '[]'::jsonb,
                              'criterio_texto', null, 'degrau_texto', null, 'zona', null, 'motivo_fora', v_mot,
                              'texto', public._agenda_corta(v_rot || ' ficou de fora' || coalesce(': ' || v_mot, '') || '.' || coalesce(' ' || v_perg, ''), c_max));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('payee_id', x.payee_id, 'nome', public._agenda_nome_curto(py.name), 'dia', x.dia, 'turno', x.turno,
                                               'presenca', x.presenca) order by x.dia, x.turno = 'tarde', py.name, x.id), '[]'::jsonb),
         array_agg(distinct x.dia)
    into v_alocs, v_dias
    from public.agenda_alocacoes x join public.payees py on py.id = x.payee_id
   where x.service_order_id = p_os and x.estado in ('publicada', 'fixada') and x.dia >= p_hoje and (x.tipo = 'reserva') = (v_tipo = 'reserva');
  select x.* into a from public.agenda_alocacoes x
   where x.service_order_id = p_os and x.estado in ('publicada', 'fixada') and x.dia >= p_hoje and (x.tipo = 'reserva') = (v_tipo = 'reserva')
   order by x.presenca <> 'turno', x.dia, x.turno = 'tarde', x.payee_id is not distinct from public._agenda_dono(null), x.id
   limit 1;
  select c.* into ac from public.agenda_acoes c where c.id = a.acao_id;
  v_quem := public._agenda_quem_marcou(ac.origem, a.origem);
  v_pess := public._agenda_gestor_pessoas(v_alocs);
  v_txt := v_rot || ': '
           || case when v_tipo = 'reserva' then case when v_quem = 'dono' then 'você reservou ' else 'reservei ' end
                   when v_quem = 'dono' then 'você marcou ' else 'marquei ' end
           || public._agenda_dias_texto(v_dias) || ' com ' || v_pess
           || case when v_tipo = 'reserva' and nullif(btrim(a.condicao), '') is not null then ', ' || btrim(a.condicao) else '' end || '.';

  if a.suposicoes is null then
    -- de antes do porquê (§6.2): a duração é a de hoje, e o texto diz que é de hoje
    v_m := public.agenda_meios_da_os(p_os, p_hoje);
    v_f := jsonb_build_object('fonte', v_m ->> 'fonte',
                              'texto', public._agenda_duracao_fonte_texto(v_m ->> 'fonte', (v_m ->> 'dias')::numeric, null, v_m ->> 'texto_vies'));
    v_txt := v_txt || ' Essa marcação é de antes de eu guardar o porquê' || coalesce('; a duração de hoje: ' || (v_f ->> 'texto'), '') || '.';
    v_sup := '[]'::jsonb;
  else
    v_f := public._agenda_porque_fonte(a.id, p_hoje);
    v_sup := coalesce((select jsonb_agg(jsonb_build_object('codigo', z.c, 'texto', z.t) order by z.o)
                         from (select s ->> 'codigo' as c, public._agenda_suposicao_texto(s ->> 'codigo', s -> 'detalhe') as t, u.o
                                 from jsonb_array_elements(a.suposicoes) with ordinality u(s, o)) z
                        where z.t is not null), '[]'::jsonb);
    v_crit := public._agenda_criterio_texto(a.criterio);
    v_deg := public._agenda_degrau_texto(coalesce(ac.degrau, a.degrau));
    v_txt := v_txt
             || coalesce(' Duração: ' || (v_f ->> 'texto') || '.', '')
             || case when v_quem = 'gestor' and jsonb_array_length(v_sup) > 0
                     then ' Contei: ' || (select string_agg(e ->> 'texto', '; ' order by o) from jsonb_array_elements(v_sup) with ordinality t(e, o)) || '.'
                     else '' end
             || case when v_quem = 'gestor' and v_crit is not null
                     then format(' %s: %s.', (select public._agenda_nome_curto(py.name) from public.payees py where py.id = a.payee_id), v_crit)
                     else '' end
             || coalesce(' Última mudança: ' || v_deg || '.', '')
             || case when v_quem = 'gestor' then ' Se algo estiver errado, me diga o certo.' else '' end;
  end if;
  return jsonb_build_object('estado', case when v_tipo = 'reserva' then 'reservada' else 'marcada' end,
                            'quem', v_quem, 'quem_texto', case when v_tipo = 'reserva' and v_quem = 'dono' then 'reservado por você' when v_tipo = 'reserva' then 'reservado pelo gestor' when v_quem = 'dono' then 'marcado por você' else 'marcado pelo gestor' end,  -- CONSERTO 13/11 (c): NOVO-agenda-296, a reserva não é marcação (R9.12-9)
                            'fonte', v_f ->> 'fonte', 'fonte_texto', v_f ->> 'texto', 'suposicoes', v_sup,
                            'criterio_texto', v_crit, 'degrau_texto', v_deg, 'zona', ac.zona, 'motivo_fora', null,
                            'texto', public._agenda_corta(v_txt, c_max));
end;
$function$;

comment on function public._agenda_porque_da_os(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7g, P3; §5.3, §6.2): o porquê de uma OS — {estado: marcada|reservada|fora|fora_da_carteira, quem, quem_texto, fonte, fonte_texto, suposicoes [{codigo, texto}], criterio_texto, degrau_texto, zona, motivo_fora, texto (≤ 600)}. Marcada e reservada: pelo que foi gravado na 1ª alocação de turno vigente de hoje em diante e na ação que a criou; de antes do porquê, a duração de hoje e o aviso. Fora: o motivo de agora (_agenda_classe_agora) e a pergunta aberta dela (agenda_perguntas_em_ordem). SECURITY DEFINER; com login, só admin/financeiro (42501 para o resto); sem login, o service_role. OS que não existe: P0002. CONSERTO 13/11 (c), NOVO-agenda-296: quem_texto na reserva é "reservado pelo gestor" / "reservado por você" (a reserva não é marcação, R9.12-9); na marcada, "marcado pelo gestor" / "marcado por você".';

-- ── 6. (d) O rótulo do orçamento recusado: "foi recusado" (pedido A-2 da F5 do retorno) ───────────────────────────────────────────────
-- O corpo de 20261024160400:171 (md5 sem CR c5bd3e8e361e4b545d82bf8ab784c5cf, o de produção em 13/11) com 1 linha trocada, marcada "-- CONSERTO 13/11 (d)": a frase
-- de quem está fora da carteira com o orçamento recusado diz "foi recusado" (com a F5, vencer não recusa mais o orçamento). O rótulo curto ("recusado ou
-- vencido") não muda: o pedido é só a frase.
create or replace function public._agenda_rotulo_os(p_status text, p_quote_status text, p_assinado boolean,
                                                    p_juntado_em text, p_frase boolean)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p_juntado_em is not null then
      case when p_status = 'draft' then 'foi juntado ao ' else 'foi juntada à ' end || p_juntado_em
    when p_status = 'draft' then case
      when p_quote_status = 'approved' then case when p_assinado then 'orçamento assinado' else 'orçamento aprovado' end
      when p_quote_status = 'awaiting_deposit' then 'esperando o sinal'
      when p_quote_status in ('sent', 'awaiting_approval') then
        case when p_frase then 'foi enviado e espera a aprovação do cliente' else 'enviado, esperando a aprovação' end
      when p_quote_status = 'rejected' then case when p_frase then 'foi recusado' else 'recusado ou vencido' end  -- CONSERTO 13/11 (d): pedido A-2 da F5, vencer não é recusar
      else case when p_frase then 'ainda é rascunho (não foi enviado ao cliente)' else 'rascunho' end end
    when p_status in ('open', 'approved') then 'aprovada'
    when p_status = 'scheduled' then 'agendada'
    when p_status = 'in_progress' then 'em andamento'
    when p_status = 'awaiting_parts' then 'esperando peças'
    when p_status = 'awaiting_client' then 'esperando o cliente'
    when p_status = 'completed' then case when p_frase then 'já foi concluída' else 'concluída' end
    when p_status = 'invoiced' then case when p_frase then 'já foi faturada' else 'faturada' end
    when p_status = 'cancelled' then 'foi cancelada'
    else coalesce(p_status, '')
  end;
$function$;

comment on function public._agenda_rotulo_os(text, text, boolean, text, boolean) is
  'Agenda de Produção (Fase 1, P3): o status da OS/orçamento em português — rótulo curto (p_frase false) ou a frase de quem está fora da carteira (p_frase true). CONSERTO 13/11 (d), pedido A-2 da F5: a frase do orçamento recusado é "foi recusado" (era "foi recusado (ou venceu)").';

-- ── 7. As portas ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- As novas: a premissa e a conferência são internas (sem grant a ninguém; quem chama é definer ou o passo fila); a guarda, só o service_role (o Secretário).
-- Função nova nasce com EXECUTE para PUBLIC e (no Supabase) para anon e authenticated: o revoke é explícito, e o teste prova que anon não executa.
revoke all on function public._agenda_cliente_premissa(uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public._agenda_fechamento_conferir(timestamptz, uuid) from public, anon, authenticated, service_role;
revoke all on function public.agenda_fechamento_guardar(date, jsonb, uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_fechamento_guardar(date, jsonb, uuid, text, timestamptz) to service_role;
-- As recriadas: as portas de produção em 13/11, reafirmadas (o create or replace já as mantém).
revoke all on function public._agenda_cliente_fila(date, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.agenda_aviso_conferir(timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_aviso_conferir(timestamptz) to service_role;
revoke all on function public._agenda_porque_da_os(uuid, date, timestamptz) from public, anon;
grant execute on function public._agenda_porque_da_os(uuid, date, timestamptz) to authenticated, service_role;
revoke all on function public._agenda_rotulo_os(text, text, boolean, text, boolean) from public, anon;
grant execute on function public._agenda_rotulo_os(text, text, boolean, text, boolean) to authenticated, service_role;

notify pgrst, 'reload schema';
