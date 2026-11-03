-- Retorno rápido ao cliente, F1 (P7, sobe em seg 16/11/2026): a fila (whatsapp_send_queue) em modo "conta".
--
-- Por que é delicado (R1-04, defeito 41): a fila já tem 5 gatilhos BEFORE INSERT — 4 da agenda, que
-- recusam com raise exception, e o de idempotência — e, desde a F0a, o do "Cliente Final"
-- (trg_whatsapp_send_queue_cliente_final). Um gatilho novo que recusasse sem lista de exceções
-- derrubaria a 7a e o Secretário (ai_monitor, ai_briefing…), que gravam na fila o dia inteiro.
--
-- Por isso o gatilho é AFTER INSERT: vê a linha como ficou depois de todos os BEFORE (inclusive a
-- cancelada pela F0a) e não pode mudar nem recusar nada. Cada linha nova da fila vira uma linha em
-- retorno_saidas (emissor 'fila', tipo 'fila', estado 'contada', modo 'sombra', dedupe_key
-- 'fila:<id da fila>'), para dois usos:
-- - os tetos do retorno (B.6, J.10) contam também o que a fila mandou ao número;
-- - medir o que o modo 'trava' recusaria (recusaria = true, motivo 'recusaria_fila'): linha AUTOMÁTICA
--   a cliente, cliente ambíguo ou número novo (quem_escreve, F0b), de fonte fora da lista fechada.
--   Nunca recusaria: agenda-* (a agenda é dona das linhas dela), o que alguém pediu (manual, ai_agent,
--   on-my-way, quote_request, revisao-plano, ai_followup_mission) e o que vai à equipe, a fornecedor
--   ou a número sem chave.
--   A lista NÃO é a da F0a, de propósito: lá ela decide o que o opt-out cancela; aqui, o que a trava
--   recusaria. revisao-plano (enviar_lembrete_de_revisao, 20261007150000_planos_de_manutencao.sql: só
--   grava na fila depois do "sim" de admin ou financeiro, e confere o opt-out sozinha) e
--   ai_followup_mission (followup_send_touch, _shared/ai/tools/followups.ts: o toque que o dono aprovou,
--   guardado na fila até o horário comercial; a ferramenta está em NEVER_AUTONOMOUS) são pedidos do dono
--   e só entram nesta lista. Se a Fase 3 do "IA acompanha" tirar o followup_send_touch de
--   NEVER_AUTONOMOUS, a ai_followup_mission sai daqui.
--
-- fila_modo = 'trava' NÃO muda nada nesta leva: fica só registrado em dados.fila_modo. A trava vem
-- depois de 1 semana em "conta" sem recusa falsa (G.0: 24/11), com OK nomeado. A lista fechada foi
-- conferida contra as fontes reais de 120 dias (refeita em 01/11: as 10 do levantamento e a me_acorde,
-- 1 linha) e contra as fontes do código que não apareceram nesses 120 dias: on-my-way, quote_request,
-- revisao-plano e ai_followup_mission (pedidos, na lista); agenda-cliente, agenda-confirmacao,
-- agenda-equipe, agenda-fornecedor e agenda-r10 (agenda-*); task-reminder, agenda e whatsapp_voltou (à
-- equipe). Só ai_followup (o cron 7, pausado; 11 de 11 a número de fora da equipe) cai em recusaria.
-- A semana do G.0 pode passar sem nenhuma fonte rara: o teste prova cada uma. O "sem recusa falsa" se
-- mede com:
--   select fila_source, count(*) from public.retorno_saidas where emissor = 'fila' and recusaria group by 1;
--
-- Erro nunca trava a fila: qualquer exceção dentro do gatilho (configuração, quem_escreve, o insert)
-- é engolida e vai ao app_error_logs (context 'retorno', action 'fila_conta', nível warn); a linha da
-- fila segue gravada. Espera também não trava: a função roda com lock_timeout = 1s. O gatilho roda na
-- transação de quem grava na fila (agenda, Secretário, ai-business-monitor) e, sem limite, esperaria a
-- trava de retorno_saidas (a migration de uma leva seguinte, um índice não concorrente, a bancada com o
-- tmp_falha) ou a linha do app_error_logs do mesmo erro (o upsert do log_app_error a segura até o
-- commit de quem gravou antes). Com o limite, a espera vira 55P03, que o "exception when others" do
-- gatilho e o do log_app_error engolem: a linha da fila segue, sem ser contada (no máximo ~1 s por
-- trava esperada). modo = 'desligado', sem a linha de configuração ou telefone de grupo (@): não conta
-- nada.
--
-- Criar o gatilho pega ShareRowExclusive em whatsapp_send_queue por um instante (no deploy; na bancada,
-- até o rollback: P15).
-- Sem dado: nenhuma linha existente muda; conta só as linhas da fila gravadas daqui em diante.
-- Reverter: drop trigger if exists trg_whatsapp_send_queue_retorno_conta on public.whatsapp_send_queue;
-- drop function if exists public._fila_retorno_conta(); as linhas contadas podem ficar (ou
-- delete from public.retorno_saidas where emissor = 'fila'). Sem deploy: update public.retorno_config
-- set modo = 'desligado' (para o retorno inteiro, inclusive a contagem).

create or replace function public._fila_retorno_conta()
returns trigger
language plpgsql
security definer
set search_path = public
set lock_timeout = '1s'
as $$
declare
  v_cfg public.retorno_config;
  v_q jsonb;
  v_fonte text := coalesce(new.source, 'manual');
  v_recusaria boolean := false;
begin
  begin
    v_cfg := public._retorno_cfg();
    -- Sem a linha (falha fecha), desligado ou grupo: não conta.
    if v_cfg.id is null or v_cfg.modo = 'desligado' or coalesce(new.phone_normalized, '') ~ '@' then
      return null;
    end if;
    v_q := public.quem_escreve(new.phone_normalized);
    -- Recusaria em 'trava': linha AUTOMÁTICA a cliente ou lead, de fonte fora da lista fechada.
    -- Nunca: agenda-*, o que alguém pediu (manual, ai_agent, on-my-way, quote_request, e o que o dono aprova
    -- antes de ir à fila: revisao-plano, ai_followup_mission) e o que vai à equipe.
    v_recusaria := v_q ->> 'papel' in ('cliente', 'cliente_ambiguo', 'novo')
                   and v_fonte not like 'agenda-%'
                   and v_fonte not in ('manual', 'ai_agent', 'on-my-way', 'quote_request', 'revisao-plano',
                                       'ai_followup_mission');
    insert into public.retorno_saidas (emissor, fila_id, fila_source, tipo, chave, phone_normalized, modo, estado,
                                       motivo, recusaria, enviar_em, decidida_em, dados, dedupe_key)
    values ('fila', new.id, v_fonte, 'fila', coalesce(public._agenda_chave_telefone(new.phone_normalized), '00000000'),
            new.phone_normalized, 'sombra', 'contada', case when v_recusaria then 'recusaria_fila' end, v_recusaria,
            new.scheduled_for, now(),
            jsonb_build_object('papel', v_q ->> 'papel', 'status', new.status, 'fila_modo', v_cfg.fila_modo),
            'fila:' || new.id)
    on conflict (dedupe_key) do nothing;
  exception when others then
    -- Nunca derruba a gravação da fila: registra e segue.
    begin
      perform public.log_app_error('db', 'retorno, fila em conta: ' || sqlerrm, 'retorno', 'fila_conta', 'warn',
                                   jsonb_build_object('fila', new.id, 'sqlstate', sqlstate));
    exception when others then
      null;
    end;
  end;
  return null;
end;
$$;

comment on function public._fila_retorno_conta() is
  'Retorno F1 (P7): conta cada linha nova da fila em retorno_saidas (emissor fila, estado contada) e marca recusaria (o que a trava recusaria). Nunca recusa nem muda a linha; erro, ou trava esperada além de 1 s (lock_timeout), vai ao app_error_logs (retorno/fila_conta).';

revoke all on function public._fila_retorno_conta() from public, anon, authenticated;

drop trigger if exists trg_whatsapp_send_queue_retorno_conta on public.whatsapp_send_queue;
create trigger trg_whatsapp_send_queue_retorno_conta
  after insert on public.whatsapp_send_queue
  for each row execute function public._fila_retorno_conta();

comment on trigger trg_whatsapp_send_queue_retorno_conta on public.whatsapp_send_queue is
  'Retorno F1 (P7): AFTER INSERT, só conta (modo conta); nunca recusa. Reverter sem deploy: retorno_config.modo = desligado.';
