-- Agenda de Produção, Fase 5 ("Mensagens ao cliente"), pacote P3: a rodada do cliente — agenda_cliente_vigiar (a cada
-- 15 min, pelo task-automations, depois da vigia e antes das regras), os passos que decidem QUAL mensagem-modelo vai a
-- QUEM e QUANDO (a confirmação D-3, a véspera D-1 às 09:00 ou o acesso, um toque só, o material chegou e a nova data, o
-- aviso de atraso, a mudança no dia, o andamento, o "ficou pronto" e o lembrete, o pós-serviço, o "não respondeu"), o
-- risco da data dita, a decisão do dono (a aprovação dos 3 primeiros dias de cada tipo e as críticas) e a saúde.
-- Spec: scratchpad agenda-pesquisa/spec-fase5.md (§3.1, §3.2, §5.3, §6.1, §6.2, d5, d13, d17, d19–d21). Decisões do dono
-- 23/10 (o gestor manda sozinho as mensagens-modelo; os 3 primeiros dias de cada tipo passam pelo dono; o crítico sempre
-- pergunta). Depende de 20261028100000 (as tabelas), 100100 (os textos, o contexto) e 100200 (o registro, as travas, o
-- passo "fila").
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (20 funções novas, 2 recriadas; nenhuma tabela, nenhum gatilho, nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f5p3/montar-migration.mjs: as partes escritas à mão
-- e os corpos de agenda_decidir (20261026100300) e agenda_saude (20261027100500) copiados, com cada bloco "-- FASE 5:"
-- conferido (fora dos blocos nenhuma linha muda).
--
-- POR QUE: é mensagem a TERCEIRO (o cliente). A rodada só decide o quê e quando; o texto é do banco
-- (_agenda_cliente_texto) e todo envio passa pelo _agenda_cliente_registrar e pelas três travas do P2 (o modo e o tipo, a
-- aprovação, o canal, a revalidação). Nada aqui escreve na fila.
--
-- O QUE MUDA:
--   1. agenda_cliente_vigiar (nova; só service_role): antes de tudo, em qualquer modo, o passo "fila" do P2; desligado =
--      {rodou: false}. Os passos, cada um no seu bloco (o que falha vai a app_error_logs, context agenda, action
--      cliente:<passo>, e os outros rodam): material, mudanca_no_dia, confirmar, atraso, andamento, pronto, pos_servico,
--      sem_resposta. Uma linha em agenda_vigia_rodadas (rotina cliente). Os acordes (a ação ainda não contada) só com a
--      vigia ligada, na cota acordes_dia_max.
--   2. Os passos (_agenda_cliente_<passo>, sem grant) e as horas (_agenda_cliente_toque, _proximo_toque, _dia_seguinte,
--      _vespera, _ultimo_fim, _ja_registra): a de amanhã é registrada a partir de cliente_hora_preparo (entra no
--      fechamento); a de hoje, no tique em que aparece.
--   3. _agenda_cliente_risco: a data que o cliente ouviu (prometido_*) ainda vale? (material: a peça + folga + os dias da
--      OS, faixa ou condicional; execução: o fim do plano, o estouro; replano: o plano publicado com o material na mão).
--   4. _agenda_cliente_decidir: a resposta do dono (cliente_aprovar 1 manda / 2 segura; cliente_aviso 1 você liga / 2 manda
--      / 3 não avisa). agenda_decidir recriada despacha os dois tipos para ela.
--   5. agenda_saude recriada com o bloco cliente: os zeros obrigatórios (entram no ok) e as métricas.
--   6. As auxiliares: _agenda_cliente_cancelar (tira do caminho o aviso que ficou velho), _agenda_cliente_acorde (a ação
--      do acorde), _agenda_cliente_ouviu (o cliente ouviu esse dia?).
--
-- O QUE NÃO MUDA: o registro, as travas, a fila e o worker (P2); a vigia, a rotina e o material (a rodada roda depois
-- deles e só lê o plano); o motor decide o crítico do plano (remarcar o que o cliente confirmou, o atraso longo, o 2º
-- atraso: a mensagem só lê o plano vigente, que só muda com a decisão). Com modo_cliente desligado (a linha nasce assim)
-- só o passo "fila" roda (e não acha nada).
--
-- DINHEIRO: nada aqui cria, muda ou liga pagamento, cobrança ou orçamento.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase5_rodada.sql e anotadas em notas-fase5.md):
--   · Os passos "material" e "mudanca_no_dia" rodam ANTES do "confirmar" (a spec os lista depois): a mensagem que já propôs o
--     dia D (o M3/M7, o M10, o aviso remarcado) substitui o M1 do mesmo D, e a véspera dele só sai se ela saiu há 2 dias ou
--     mais — no tique em que a peça chega (ou em que choveu) os dois passos veriam a OS.
--   · O atraso longo do aviso conta em DIAS ÚTEIS entre o prometido_ate e o fim novo (agenda_du_entre >= atraso_longo_dias):
--     em dias corridos, o caso base da spec (o Nelson: ouviu qui 05/11, a peça em qua 11/11, a faixa nova qui 12 a sex 13/11
--     = 8 corridos) já seria crítico, e a spec o espera como aviso comum (e a previsão em 20/11 como crítico). O texto ao dono
--     ("vai atrasar N dias") continua em dias corridos.
--   · A faixa da peça: [chegada + folga_material_du, chegada + folga_material_du + dias − 1] dias úteis (o 1º dia útil depois
--     da chegada até o fim do serviço: 12 e 13/11 para o Nelson, 2 dias); "a peça" = a chegada mais tarde dos críticos que
--     têm data; o tipo é faixa só com o pior nível dos críticos em A ou B (senão condicional, d09). Sem nenhuma data, não há
--     o que dizer (sem_data): conta e espera (a vigia já pede a previsão ao dono).
--   · A data dita que já passou (ou o aviso que só sairia depois dela) abre a pergunta crítica cliente_aviso SEM mensagem
--     (uma vez por data): o aviso escrito chegaria depois da data e a revalidação o recusaria (passou_da_data). A opção 2
--     nela diz que não há aviso que ainda sirva.
--   · O aviso vivo que não bate mais com o risco de agora (a peça mudou de novo, chegou, a data passou) é tirado do caminho
--     (recusada/desatualizada, a linha da fila que não saiu falha, a pergunta é descartada): a revalidação não recalcula a
--     faixa e o aviso velho sairia.
--   · A mudança no dia é lida nas alocações (o meio-dia daquele dia cancelado hoje ou não cumprido hoje, e o dia que não
--     voltou ao plano), não no tipo da ação: assim o *choveu* (resultado não cumprido + replano) e o replano da vigia valem
--     igual. O dia inteiro tem de ter saído (a troca de manhã para tarde no mesmo dia não manda M10).
--   · O acorde é uma ação tipo cliente executada (depois.acorde = true), uma por chave: o envio dos acordes só manda ação
--     executada (o molde da rotina).
--   · O pós-serviço sai entre o toque e o toque + 2 h de segunda a sexta (a spec: 09:00–11:00); o que passou dessa hora vai
--     ao próximo dia útil de janela; não sai mais depois do 3º dia de janela a contar do dia certo.
--   · O "não respondeu" (sem_resposta) abre cliente_resposta com a chave cliente_resposta:sem_resposta:<mensagem> (a spec só
--     define a chave da resposta, P4) e expira em 7 dias.
--   · _agenda_cliente_decidir ganhou p_via e p_trecho (a resposta do dono fica registrada como nas outras perguntas).
--
-- ORDEM DE LIGAR: depois de 20261028100000, 100100 e 100200; ANTES do deploy do task-automations (o passo chama
-- agenda_cliente_vigiar; sem a função, o passo só anota que ela não existe). Com modo_cliente desligado nada é registrado.
--
-- PROVA: supabase/tests/agenda_fase5_rodada.sql (R0–R12). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; depois de 20261028100000, 100100 e 100200):
--   npx supabase db query --linked -f supabase/migrations/20261028100300_agenda_fase5_rodada.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261028100300', 'agenda_fase5_rodada');"
--
-- DESFAZER: reaplicar agenda_decidir de 20261026100300 e agenda_saude de 20261027100500; as funções novas ficam (sem a
-- rodada, ninguém as chama).
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── 1. As horas da rodada (o toque, a véspera, o "registra a de amanhã") ────────────────────────────────

-- O toque (cliente_hora_toque, 09:00) do 1º dia de janela a partir de p_dia (o próprio, se é de janela). Lança 54000 sem
-- dia de janela em 31 dias.
create or replace function public._agenda_cliente_toque(p_dia date)
 returns timestamptz
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_d date := p_dia;
begin
  if p_dia is null then
    return null;
  end if;
  while not public._agenda_cliente_dia_de_janela(v_d) loop
    v_d := v_d + 1;
    if v_d > p_dia + 31 then
      raise exception '_agenda_cliente_toque: nenhum dia de janela em 31 dias a partir de %', p_dia using errcode = '54000';
    end if;
  end loop;
  return (v_d + (public._agenda_cfg()).cliente_hora_toque) at time zone 'America/Sao_Paulo';
end;
$function$;

comment on function public._agenda_cliente_toque(date) is
  'Agenda de Produção (Fase 5, P3): o toque (agenda_config.cliente_hora_toque) do 1º dia de janela do cliente a partir de p_dia (segunda a sábado sem feriado). Lança 54000 sem dia de janela em 31 dias.';

-- A "próxima manhã de janela": o 1º toque DEPOIS de p_agora (hoje, se ainda não deu a hora do toque e hoje é de janela).
create or replace function public._agenda_cliente_proximo_toque(p_agora timestamptz)
 returns timestamptz
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_t timestamptz := public._agenda_cliente_toque((p_agora at time zone 'America/Sao_Paulo')::date);
begin
  if v_t <= p_agora then
    v_t := public._agenda_cliente_toque((p_agora at time zone 'America/Sao_Paulo')::date + 1);
  end if;
  return v_t;
end;
$function$;

comment on function public._agenda_cliente_proximo_toque(timestamptz) is
  'Agenda de Produção (Fase 5, P3): a próxima manhã de janela do cliente — o 1º toque (cliente_hora_toque) depois de p_agora.';

-- O dia de janela seguinte a p_dia (estritamente depois). Lança 54000 sem dia de janela em 31 dias.
create or replace function public._agenda_cliente_dia_seguinte(p_dia date)
 returns date
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_d date := p_dia + 1;
begin
  if p_dia is null then
    return null;
  end if;
  while not public._agenda_cliente_dia_de_janela(v_d) loop
    v_d := v_d + 1;
    if v_d > p_dia + 31 then
      raise exception '_agenda_cliente_dia_seguinte: nenhum dia de janela em 31 dias depois de %', p_dia using errcode = '54000';
    end if;
  end loop;
  return v_d;
end;
$function$;

comment on function public._agenda_cliente_dia_seguinte(date) is
  'Agenda de Produção (Fase 5, P3): o dia de janela do cliente seguinte a p_dia (estritamente depois; pula domingo e feriado). Lança 54000 sem dia de janela em 31 dias.';

-- A véspera de um dia: o ÚLTIMO dia de janela antes dele (o sábado conta: a véspera de ter 03/11, com Finados na segunda,
-- é sáb 31/10). null sem dia de janela nos 31 dias antes.
create or replace function public._agenda_cliente_vespera(p_dia date)
 returns date
 language sql
 stable
 set search_path to 'public'
as $function$
  select max(g::date) from generate_series(p_dia - 31, p_dia - 1, interval '1 day') g
   where public._agenda_cliente_dia_de_janela(g::date);
$function$;

comment on function public._agenda_cliente_vespera(date) is
  'Agenda de Produção (Fase 5, P3): a véspera de um dia para o cliente — o último dia de janela antes dele (segunda a sábado sem feriado; o sábado conta). null sem dia de janela nos 31 dias antes.';

-- O fim da janela do ÚLTIMO dia de janela até p_dia (o próprio, se é de janela): o limite do aviso de atraso ("nunca
-- depois da data dita").
create or replace function public._agenda_cliente_ultimo_fim(p_dia date)
 returns timestamptz
 language sql
 stable
 set search_path to 'public'
as $function$
  select public._agenda_cliente_fim_da_janela(d, 0)
    from (select max(g::date) as d from generate_series(p_dia - 31, p_dia, interval '1 day') g
           where public._agenda_cliente_dia_de_janela(g::date)) x
   where x.d is not null;
$function$;

comment on function public._agenda_cliente_ultimo_fim(date) is
  'Agenda de Produção (Fase 5, P3): o fim da janela do último dia de janela do cliente até p_dia (o próprio, se é de janela) — o limite do aviso de atraso (nunca depois da data dita). null sem dia de janela nos 31 dias antes.';

-- A mensagem que SAI no dia p_dia já se registra agora? Sim quando o dia é hoje (ou já passou) ou quando é o próximo dia de
-- janela e já deu a hora do preparo (cliente_hora_preparo, 17:00): a de amanhã entra no fechamento da véspera.
create or replace function public._agenda_cliente_ja_registra(p_dia date, p_hoje date, p_agora timestamptz)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select p_dia is not null
     and (p_dia <= p_hoje
          or (p_dia <= public._agenda_cliente_dia_seguinte(p_hoje)
              and (p_agora at time zone 'America/Sao_Paulo')::time >= (public._agenda_cfg()).cliente_hora_preparo));
$function$;

comment on function public._agenda_cliente_ja_registra(date, date, timestamptz) is
  'Agenda de Produção (Fase 5, P3): a mensagem ao cliente que sai no dia p_dia já é registrada agora? Sim com o dia hoje (ou passado), ou com o dia sendo o próximo dia de janela e a hora de Brasília >= cliente_hora_preparo (a de amanhã entra no fechamento da véspera).';

-- ── 2. O risco do que foi dito ao cliente ───────────────────────────────────────────────────────────────

-- A data que o cliente ouviu (os_planejamento.prometido_*) ainda vale? Só existe com prometido_ate (senão null) e com a OS
-- ativa. {risco, causa, tipo, variante, faixa_de, faixa_ate, fim_novo, peca, dito_de, dito_ate, atraso_dias, atraso_du,
-- passou, sem_data, segundo}:
--   · material (algum crítico fora de A): a data de agora é a da peça (a chegada mais tarde dos críticos que têm data) +
--     folga_material_du dias úteis, mais os dias da OS — faixa [chegada + folga, chegada + folga + dias − 1]; tipo
--     'faixa' com o pior nível dos críticos em A/B, senão 'condicional' (d09); sem nenhuma data = sem_data;
--   · execucao (em andamento): o fim do plano, ou amanhã quando os meios-dias feitos passaram de estouro_fator × o
--     combinado; faixa [fim, fim + 1 dia útil];
--   · replano (o plano publicado, com o material todo na mão): o último dia do plano; firme (o M6 'remarcado').
-- risco = a data de agora (o fim novo) depois do prometido_ate. passou = o prometido_ate já ficou para trás (o teste
-- prova que nunca há risco com a data vencida sem passou). segundo = já houve aviso de atraso ou nova data enviados nesta
-- OS, ou o prometido de agora passou do original.
create or replace function public._agenda_cliente_risco(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  p       public.os_planejamento%rowtype;
  v_status text;
  v_plano jsonb;
  v_pront jsonb;
  v_crit  jsonb;
  v_m     jsonb;
  v_conf  text;
  v_peca  date;
  v_n     int;
  v_causa text;
  v_tipo  text;
  v_var   text;
  v_de    date;
  v_ate   date;
  v_novo  date;
  v_est   boolean := false;
begin
  select * into p from public.os_planejamento where service_order_id = p_os;
  if not found or p.prometido_ate is null then
    return null;
  end if;
  select so.status into v_status from public.service_orders so where so.id = p_os;
  if v_status is null
     or v_status not in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client') then
    return null;
  end if;
  v_plano := public._agenda_plano_da_os(p_os, p_hoje);
  v_pront := public.os_prontidao(p_os, p_hoje);
  select coalesce(jsonb_agg(e), '[]'::jsonb) into v_crit
    from jsonb_array_elements(coalesce(v_pront #> '{material,itens}', '[]'::jsonb)) e
   where coalesce((e ->> 'critico')::boolean, false) and e ->> 'nivel' <> 'A';

  if jsonb_array_length(v_crit) > 0 then
    v_causa := 'material';
    v_var := 'peca';
    v_conf := v_pront #>> '{material,confianca}';
    v_tipo := case when v_conf in ('A', 'B') then 'faixa' else 'condicional' end;
    select max((e ->> 'data')::date) into v_peca from jsonb_array_elements(v_crit) e where e ->> 'data' is not null;
    v_n := greatest(1, ceil(coalesce((v_pront #>> '{duracao,dias}')::numeric, (v_plano ->> 'dias')::numeric, 1))::int);
    if v_peca is not null then
      v_de := public.agenda_somar_du(v_peca, cf.folga_material_du);
      v_ate := public.agenda_somar_du(v_peca, cf.folga_material_du + v_n - 1);
      v_novo := v_ate;
    end if;
  elsif v_status = 'in_progress' then
    v_causa := 'execucao';
    v_var := 'execucao';
    v_tipo := 'faixa';
    v_m := public.agenda_meios_da_os(p_os, p_hoje);
    v_est := coalesce(v_m ->> 'fonte' in ('dono', 'aceita'), false) and coalesce((v_m ->> 'total')::numeric, 0) > 0
             and coalesce((v_m ->> 'cumpridos')::numeric, 0) > cf.estouro_fator * (v_m ->> 'total')::numeric;
    v_novo := greatest(coalesce((v_plano ->> 'ultimo_dia')::date, p_hoje),
                       case when v_est then public.agenda_somar_du(p_hoje, 1) end);
    v_de := v_novo;
    v_ate := public.agenda_somar_du(v_novo, 1);
  elsif (v_plano ->> 'proximo_dia') is not null and (v_plano ->> 'ultimo_dia') is not null then
    v_causa := 'replano';
    v_var := 'remarcado';
    v_tipo := 'firme';
    v_de := (v_plano ->> 'proximo_dia')::date;
    v_ate := (v_plano ->> 'ultimo_dia')::date;
    v_novo := v_ate;
  end if;

  return jsonb_build_object(
    'risco', coalesce(v_novo > p.prometido_ate, v_causa = 'material' and v_novo is null),
    'causa', v_causa, 'tipo', v_tipo, 'variante', v_var,
    'faixa_de', v_de, 'faixa_ate', v_ate, 'fim_novo', v_novo, 'peca', v_peca, 'estouro', v_est,
    'dito_de', coalesce(p.prometido_de, p.prometido_ate), 'dito_ate', p.prometido_ate,
    'atraso_dias', v_novo - p.prometido_ate, 'atraso_du', public.agenda_du_entre(p.prometido_ate, v_novo),
    'passou', p.prometido_ate < p_hoje,
    'sem_data', v_causa = 'material' and v_novo is null,
    'segundo', coalesce(p.prometido_original_ate < p.prometido_ate, false)
               or exists (select 1 from public.agenda_cliente_mensagens m
                           where m.service_order_id = p_os and m.tipo in ('pode_atrasar', 'nova_data')
                             and m.enviada_em is not null));
end;
$function$;

comment on function public._agenda_cliente_risco(uuid, date) is
  'Agenda de Produção (Fase 5, P3): a data que o cliente ouviu (os_planejamento.prometido_*) ainda vale? null sem prometido_ate ou com a OS fora das ativas. {risco, causa (material: algum crítico fora de A — a chegada mais tarde dos críticos com data + folga_material_du dias úteis + os dias da OS, tipo faixa com o pior nível em A/B, senão condicional, sem data = sem_data; execucao: em andamento, o fim do plano, ou amanhã com o estouro; replano: o plano publicado com o material na mão, firme), tipo, variante (peca, execucao, remarcado), faixa_de, faixa_ate, fim_novo, peca, dito_de, dito_ate, atraso_dias (corridos), atraso_du (dias úteis), passou (prometido_ate antes de p_hoje), sem_data, segundo (já houve aviso de atraso ou nova data enviados, ou o prometido de agora passou do original)}. risco = o fim novo depois do prometido_ate.';

-- ── 3. Auxiliares dos passos ────────────────────────────────────────────────────────────────────────────

-- Tira uma mensagem viva (registrada, esperando o dono ou na fila ainda sem sair) do caminho: recusada com o motivo, a
-- linha da fila que ainda não saiu fica failed, a pergunta dela (aberta) é descartada. A que já saiu não muda.
create or replace function public._agenda_cliente_cancelar(p_msg uuid, p_motivo text, p_texto text)
 returns boolean
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  m public.agenda_cliente_mensagens%rowtype;
begin
  select * into m from public.agenda_cliente_mensagens where id = p_msg for update;
  if not found or m.estado not in ('registrada', 'aguardando_dono', 'enfileirada') then
    return false;
  end if;
  if m.estado = 'enfileirada' then
    update public.whatsapp_send_queue
       set status = 'failed', failed_reason = left('agenda-cliente: não saiu (' || p_motivo || ')', 200)
     where source = 'agenda-cliente' and source_ref_id = m.id and status = 'pending';
    if not found then
      -- já está saindo (ou saiu): a verdade é o envio
      return false;
    end if;
  end if;
  update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = p_motivo where id = m.id;
  if m.pergunta_id is not null then
    update public.agenda_perguntas set estado = 'descartada', resolvida_motivo = left(p_texto, 200)
     where id = m.pergunta_id and estado = 'aberta';
  end if;
  return true;
end;
$function$;

comment on function public._agenda_cliente_cancelar(uuid, text, text) is
  'Agenda de Produção (Fase 5, P3): tira do caminho uma mensagem ao cliente viva (registrada, esperando o dono, ou enfileirada com a linha da fila ainda pending) — recusada com o motivo, a linha da fila failed, a pergunta aberta dela descartada com p_texto. A que já está saindo ou saiu não muda (false). Interna (sem grant).';

-- A ação de acorde de uma mensagem ao cliente (o aviso crítico que perde em até 1 dia útil, a mudança no dia sem decisão):
-- tipo cliente, origem vigia, executada (o acorde só sai de ação executada), uma por chave. A rodada devolve as que ainda
-- não foram contadas.
create or replace function public._agenda_cliente_acorde(p_os uuid, p_chave text, p_texto text, p_perda date, p_hoje date,
                                                         p_pergunta uuid default null)
 returns uuid
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  v_id uuid;
begin
  select a.id into v_id from public.agenda_acoes a
   where a.tipo = 'cliente' and a.depois ->> 'acorde_chave' = p_chave;
  if v_id is not null then
    return null;
  end if;
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
  values (clock_timestamp(), p_hoje, true, 'vigia', 'cliente', p_os, array[p_os], '{}'::jsonb,
          jsonb_build_object('acorde', true, 'acorde_chave', p_chave, 'perda_em', p_perda, 'pergunta_id', p_pergunta),
          public._agenda_corta(p_texto, 400))
  returning id into v_id;
  return v_id;
end;
$function$;

comment on function public._agenda_cliente_acorde(uuid, text, text, date, date, uuid) is
  'Agenda de Produção (Fase 5, P3): a ação que leva um acorde da mensagem ao cliente ao dono (tipo cliente, origem vigia, executada, depois {acorde, acorde_chave, perda_em, pergunta_id}), uma por chave (a 2ª devolve null). A rodada devolve as não contadas. Interna (sem grant).';

-- O que o cliente OUVIU para um dia (a mensagem com data enviada — em teste, a que teria saído — ou o "sim" do botão).
create or replace function public._agenda_cliente_ouviu(p_os uuid, p_dia date, p_agora timestamptz)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select exists (select 1 from public.agenda_cliente_mensagens m
                  where m.service_order_id = p_os
                    and (m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')
                         or (m.tipo = 'pode_atrasar' and m.variante = 'remarcado'))
                    and coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) = p_dia
                    and (m.enviada_em is not null
                         or (m.modo = 'sombra' and m.enviar_em <= p_agora and m.estado = 'registrada')))
      or exists (select 1 from public.service_orders so
                  where so.id = p_os and (so.client_confirmed_for at time zone 'America/Sao_Paulo')::date = p_dia);
$function$;

comment on function public._agenda_cliente_ouviu(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 5, P3): o cliente ouviu esse dia? Uma mensagem com data firme (confirmar, véspera, acesso, material chegou, nova data, mudança no dia, aviso remarcado) enviada para ele — em teste, a que teria saído até p_agora —, ou client_confirmed_for nesse dia.';

-- ── 4. Os passos da rodada (cada um devolve as contagens; o que falha vai a app_error_logs pela rodada) ──

-- Passo "material": a OS cujo material crítico ficou todo na mão há pouco (uma linha crítica chegou nos últimos
-- c_recente_du dias úteis) e que estava esperando por ele (o aviso de atraso enviado, o prometido condicional ou em faixa, ou
-- a OS que saiu de "aguardando peças" nesses dias), com o próximo dia no plano: nova data (M7) se o aviso de atraso foi
-- enviado; senão o material chegou (M3). Não sai se o cliente já ouviu esse dia. Sai na hora (a janela empurra).
create or replace function public._agenda_cliente_material(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c_recente_du constant int := 5;     -- spec §5.3: "ficou com todo crítico A há ≤ 5 du"
  r      record;
  v_pront jsonb;
  v_dia  date;
  v_tipo text;
  v_r    jsonb;
  n_reg  int := 0;
  n_ja   int := 0;
begin
  for r in
    select k.service_order_id as os, k.status, p.prometido_tipo
      from public.os_carteira(p_hoje) k
      left join public.os_planejamento p on p.service_order_id = k.service_order_id
     where k.status not in ('awaiting_parts', 'awaiting_client', 'in_progress')
       and exists (select 1 from public.os_material om
                    where om.service_order_id = k.service_order_id and om.critico and om.situacao = 'na_mao'
                      and om.chegou_em >= public.agenda_somar_du(p_hoje, -c_recente_du))
     order by k.numero collate "C", k.service_order_id
  loop
    v_pront := public.os_prontidao(r.os, p_hoje);
    continue when v_pront #>> '{material,estado}' is distinct from 'completo';
    v_dia := (public._agenda_plano_da_os(r.os, p_hoje) ->> 'proximo_dia')::date;
    continue when v_dia is null or v_dia <= p_hoje;
    -- estava esperando pelo material? (o prometido nulo não pode deixar a condição nula: aí o continue não pularia)
    continue when not (
      coalesce(r.prometido_tipo in ('condicional', 'faixa'), false)
      or exists (select 1 from public.agenda_cliente_mensagens m
                  where m.service_order_id = r.os and m.tipo = 'pode_atrasar' and m.enviada_em is not null)
      or exists (select 1 from public.agenda_acoes a
                  where a.service_order_id = r.os and a.tipo = 'status' and a.executada and a.desfeita_em is null
                    and a.status_antes = 'awaiting_parts' and a.dia >= public.agenda_somar_du(p_hoje, -c_recente_du)));
    -- o cliente já ouviu esse dia (a confirmação, a véspera): não repete
    if public._agenda_cliente_ouviu(r.os, v_dia, p_agora) then
      n_ja := n_ja + 1;
      continue;
    end if;
    v_tipo := case when exists (select 1 from public.agenda_cliente_mensagens m
                                 where m.service_order_id = r.os and m.tipo = 'pode_atrasar' and m.enviada_em is not null)
                   then 'nova_data' else 'material_chegou' end;
    v_r := public._agenda_cliente_registrar(v_tipo, null, r.os, v_dia, '{}'::jsonb, p_agora,
             public._agenda_cliente_fim_da_janela((public._agenda_cliente_quando(0, p_agora, p_agora) at time zone 'America/Sao_Paulo')::date, 1),
             'rodada', null, p_agora);
    if coalesce((v_r ->> 'criada')::boolean, false) then n_reg := n_reg + 1; end if;
  end loop;
  return jsonb_build_object('registradas', n_reg, 'ja_ouviu', n_ja);
end;
$function$;

-- Passo "confirmar": a OS da carteira com o próximo dia D no plano, que ainda não começou, com o material todo na mão e
-- fora de "aguardando": a confirmação (M1) às cliente_hora_toque de D − cliente_confirmar_du dias úteis (passado → a
-- próxima manhã de janela) e a véspera às cliente_hora_toque do último dia de janela antes de D — acesso (M4) quando o
-- acesso é desconhecido, senão véspera (M2). Se o dia da confirmação não é antes do da véspera, sai um toque só nesse dia:
-- o acesso (M4) com o acesso desconhecido (decisão do coordenador: o acesso vale mais que a confirmação), senão a
-- confirmação 'unico'. A véspera não sai se a confirmação (ou o material chegou, a nova data) saiu há menos de 2 dias
-- corridos. O M3/M7 do mesmo D substitui o M1. Cada uma é registrada no dia em que sai, ou na véspera a partir de
-- cliente_hora_preparo (entra no fechamento).
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

-- Passo "atraso": a data que o cliente ouviu e que não vai se cumprir (_agenda_cliente_risco). O aviso (M6) é registrado
-- no 1º tique a partir de cliente_hora_preparo do dia (sai na manhã seguinte, depois do fechamento) ou na hora, quando o
-- prometido vence em até cliente_atraso_na_hora_du dias úteis. Nunca depois da data: se a hora possível passa do fim da
-- janela do último dia de janela até o prometido_ate, ou se ele já passou, NÃO sai e abre a pergunta crítica
-- cliente_aviso (passou: "recomendo ligar hoje"). O 2º atraso e o atraso de atraso_longo_dias dias úteis ou mais saem
-- como pergunta crítica (a mensagem espera o dono). O aviso vivo que não bate mais com o risco de agora (a peça mudou de
-- novo, chegou) é tirado do caminho (desatualizada).
create or replace function public._agenda_cliente_atraso(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_modo  text := case when cf.modo_cliente = 'ligado' then 'ligado' else 'sombra' end;
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  r       record;
  m       record;
  x       jsonb;
  v_urg   boolean;
  v_alvo  timestamptz;
  v_lim   timestamptz;
  v_crit  text;
  v_dados jsonb;
  v_r     jsonb;
  v_chave text;
  v_perg  uuid;
  v_ctx   jsonb;
  n_reg   int := 0;
  n_crit  int := 0;
  n_pass  int := 0;
  n_esp   int := 0;
  n_semd  int := 0;
  n_canc  int := 0;
begin
  for r in
    select k.service_order_id as os, p.prometido_ate
      from public.os_carteira(p_hoje) k
      join public.os_planejamento p on p.service_order_id = k.service_order_id
     where p.prometido_ate is not null
     order by k.numero collate "C", k.service_order_id
  loop
    x := public._agenda_cliente_risco(r.os, p_hoje);
    -- o aviso vivo que não é mais o de agora sai do caminho
    for m in
      select a.id, a.dia_alvo from public.agenda_cliente_mensagens a
       where a.service_order_id = r.os and a.tipo = 'pode_atrasar' and a.estado in ('registrada', 'aguardando_dono', 'enfileirada')
    loop
      if x is null or not coalesce((x ->> 'risco')::boolean, false) or coalesce((x ->> 'passou')::boolean, false)
         or m.dia_alvo is distinct from (x ->> 'faixa_de')::date then
        if public._agenda_cliente_cancelar(m.id, 'desatualizada', 'o risco de atraso mudou antes de a mensagem sair') then
          n_canc := n_canc + 1;
        end if;
      end if;
    end loop;
    continue when x is null or not coalesce((x ->> 'risco')::boolean, false);
    v_lim := public._agenda_cliente_ultimo_fim(r.prometido_ate);
    v_urg := public.agenda_du_entre(p_hoje, r.prometido_ate) <= cf.cliente_atraso_na_hora_du;
    v_alvo := case when v_urg then p_agora else public._agenda_cliente_toque(public._agenda_cliente_dia_seguinte(p_hoje)) end;
    -- a data dita já passou, ou o aviso só sairia depois dela: não sai; o dono liga (pergunta crítica, uma vez)
    if coalesce((x ->> 'passou')::boolean, false) or v_lim is null
       or public._agenda_cliente_quando(0, v_alvo, p_agora) > v_lim then
      v_chave := format('cliente_aviso:%s:%s', r.os, r.prometido_ate);
      if not exists (select 1 from public.agenda_perguntas q where q.chave = v_chave and q.modo = v_modo) then
        v_perg := public._agenda_cliente_perguntar('cliente_aviso', v_chave, r.os, r.prometido_ate, p_hoje,
                    public._agenda_cliente_texto_do_aviso('passou', 'pode_atrasar', r.os, x, p_hoje), v_modo, p_agora,
                    public._agenda_cliente_fim_da_janela(p_hoje, 1));
        n_pass := n_pass + 1;
        if v_modo = 'ligado' then
          v_ctx := public._agenda_cliente_contexto(r.os, p_hoje);
          perform public._agenda_cliente_acorde(r.os, v_chave,
            format('A data que o %s ouviu (%s) passou sem aviso: recomendo você ligar hoje. A decisão está nas perguntas da agenda (1, 2 ou 3).',
                   coalesce(v_ctx ->> 'nome', 'cliente'), public._dia_curto(r.prometido_ate)),
            p_hoje, p_hoje, v_perg);
        end if;
      end if;
      continue;
    end if;
    if coalesce((x ->> 'sem_data')::boolean, false) then
      -- sem nenhuma previsão da peça não há o que dizer (a vigia já pede a previsão ao dono)
      n_semd := n_semd + 1;
      continue;
    end if;
    -- sem urgência, espera o fechamento do dia (o 1º tique a partir de cliente_hora_preparo)
    if not v_urg and v_local::time < cf.cliente_hora_preparo then
      n_esp := n_esp + 1;
      continue;
    end if;
    v_crit := case when coalesce((x ->> 'segundo')::boolean, false) then 'segundo_atraso'
                   when (x ->> 'atraso_du')::int >= cf.atraso_longo_dias then 'atraso_longo' end;
    v_dados := jsonb_build_object('faixa_de', x -> 'faixa_de', 'faixa_ate', x -> 'faixa_ate', 'prometido_tipo', x -> 'tipo',
                                  'dito_de', x -> 'dito_de', 'dito_ate', x -> 'dito_ate', 'atraso_dias', x -> 'atraso_dias')
               || case when x ->> 'variante' = 'peca' then jsonb_build_object('peca_de', x -> 'peca', 'peca_ate', x -> 'peca')
                       else '{}'::jsonb end;
    v_r := public._agenda_cliente_registrar('pode_atrasar', x ->> 'variante', r.os, (x ->> 'faixa_de')::date, v_dados,
             v_alvo, v_lim, 'rodada', v_crit, p_agora);
    if coalesce((v_r ->> 'criada')::boolean, false) then
      n_reg := n_reg + 1;
      if v_r ->> 'aprovacao' = 'critica' then
        n_crit := n_crit + 1;
        -- a crítica que perde em até 1 dia útil acorda o dono
        if v_r ->> 'modo' = 'ligado' and r.prometido_ate <= public.agenda_somar_du(p_hoje, 1) then
          v_ctx := public._agenda_cliente_contexto(r.os, p_hoje);
          perform public._agenda_cliente_acorde(r.os, 'cliente_aviso:' || (v_r ->> 'id'),
            format('O aviso de atraso do %s precisa de você hoje (%s → %s): recomendo ligar. A decisão está nas perguntas da agenda (1, 2 ou 3).',
                   coalesce(v_ctx ->> 'nome', 'cliente'), public._dia_curto(r.prometido_ate),
                   public._agenda_faixa_texto((x ->> 'faixa_de')::date, 'manha', (x ->> 'faixa_ate')::date, 'tarde')),
            r.prometido_ate, p_hoje, (v_r ->> 'pergunta_id')::uuid);
        end if;
      end if;
    end if;
  end loop;
  return jsonb_build_object('registradas', n_reg, 'criticas', n_crit, 'passou', n_pass, 'esperando_fechamento', n_esp,
                            'sem_data', n_semd, 'desatualizadas', n_canc);
end;
$function$;

-- Passo "mudanca_no_dia": o dia de HOJE ou AMANHÃ que o cliente ouviu (_agenda_cliente_ouviu) e que saiu do plano hoje —
-- o meio-dia dele cancelado hoje ou dado como não cumprido hoje, sem ser a pedido do cliente (cancelada_motivo cliente,
-- motivo cliente_ou_bem) — e não voltou. A nova data é o próximo dia do plano de agora: M10 (variante pelo motivo: clima,
-- equipe — falta ou a pessoa —, senão geral), uma por dia perdido. Sem próximo dia (a decisão está com o dono), nada ao
-- cliente: o acorde ao dono ("recomendo ligar").
create or replace function public._agenda_cliente_mudanca_no_dia(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  r      record;
  v_novo date;
  v_env  date;
  v_var  text;
  v_r    jsonb;
  v_ctx  jsonb;
  n_reg  int := 0;
  n_sem  int := 0;
  n_tarde int := 0;
begin
  for r in
    select x.os, x.dia,
           bool_or(x.motivo = 'clima' or x.cancelada_motivo = 'clima') as clima,
           bool_or(x.motivo = 'equipe_faltou' or x.cancelada_motivo = 'pessoa') as equipe
      from (select a.service_order_id as os, a.dia, a.motivo, a.cancelada_motivo
              from public.agenda_alocacoes a
             where a.dia in (p_hoje, p_hoje + 1) and a.tipo <> 'reserva'
               and ((a.estado = 'cancelada' and (a.cancelada_em at time zone 'America/Sao_Paulo')::date = p_hoje
                     and coalesce(a.cancelada_motivo, '') not in ('cliente', 'desfeito', 'os_saiu'))
                    or (a.resultado = 'nao_cumprido' and (a.resultado_em at time zone 'America/Sao_Paulo')::date = p_hoje
                        and coalesce(a.motivo, '') <> 'cliente_ou_bem'))) x
     where not exists (select 1 from public.agenda_alocacoes v
                        where v.service_order_id = x.os and v.dia = x.dia and v.estado in ('publicada', 'fixada')
                          and v.tipo <> 'reserva' and v.resultado is distinct from 'nao_cumprido')
       and public._agenda_cliente_ouviu(x.os, x.dia, p_agora)
     group by x.os, x.dia
     order by x.dia, x.os
  loop
    -- o dia que a mensagem diz é contado de quando ela sai: o dia perdido já passou do envio possível = tarde demais
    v_env := (public._agenda_cliente_quando(0, p_agora, p_agora) at time zone 'America/Sao_Paulo')::date;
    if r.dia < v_env then
      n_tarde := n_tarde + 1;
      continue;
    end if;
    v_novo := (public._agenda_plano_da_os(r.os, p_hoje) ->> 'proximo_dia')::date;
    if v_novo is null or v_novo <= r.dia then
      -- a decisão está com o dono (pergunta crítica do motor, ou a OS fora do plano): nada ao cliente; o acorde
      n_sem := n_sem + 1;
      if cf.modo_cliente = 'ligado' then
        v_ctx := public._agenda_cliente_contexto(r.os, p_hoje);
        perform public._agenda_cliente_acorde(r.os, format('mudanca_no_dia:%s:%s', r.os, r.dia),
          format('O %s esperava a equipe %s: a decisão está com você; recomendo ligar.',
                 coalesce(v_ctx ->> 'nome', 'cliente'), case when r.dia = p_hoje then 'hoje' else 'amanhã' end),
          r.dia, p_hoje);
      end if;
      continue;
    end if;
    v_var := case when r.clima then 'clima' when r.equipe then 'equipe' else 'geral' end;
    v_r := public._agenda_cliente_registrar('mudanca_no_dia', v_var, r.os, v_novo,
             jsonb_build_object('quando', case when r.dia = v_env then 'hoje' else 'amanhã' end, 'chave', r.dia::text),
             p_agora, public._agenda_cliente_fim_da_janela(v_env, 0), 'rodada', null, p_agora);
    if coalesce((v_r ->> 'criada')::boolean, false) then n_reg := n_reg + 1; end if;
  end loop;
  return jsonb_build_object('registradas', n_reg, 'sem_decisao', n_sem, 'tarde_demais', n_tarde);
end;
$function$;

-- Passo "andamento": (a) o 1º dia feito (cumprido ou parcial) de uma OS de 2 dias ou mais — às c_hora_tarde do mesmo dia
-- ("começamos hoje") ou na manhã seguinte ("começamos ontem"); (b) o semanal (chave = a semana ISO) da OS em andamento de
-- mais de cliente_andamento_min_du dias, a cada cliente_andamento_intervalo_dias. Nunca quando o fim planejado mudou desde
-- a data dita (aí é o aviso de atraso ou a nova data).
create or replace function public._agenda_cliente_andamento(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_hora_tarde constant time := '18:00';    -- spec §5.3: "às 18:00 do mesmo dia (dentro da janela)"
  r       record;
  x       jsonb;
  v_ini   date;
  v_alvo  timestamptz;
  v_env   date;
  v_ult   timestamptz;
  v_r     jsonb;
  n_ini   int := 0;
  n_sem   int := 0;
begin
  for r in
    select k.service_order_id as os, k.status, p.prometido_ate
      from public.os_carteira(p_hoje) k
      left join public.os_planejamento p on p.service_order_id = k.service_order_id
     where k.status = 'in_progress'
     order by k.numero collate "C", k.service_order_id
  loop
    x := public._agenda_plano_da_os(r.os, p_hoje);
    continue when x is null or (x ->> 'dias')::int < 2;
    -- o fim planejado mudou desde a data dita: é o aviso de atraso (M6/M7), não o andamento
    continue when r.prometido_ate is not null and (x ->> 'ultimo_dia')::date is distinct from r.prometido_ate;
    -- (a) o 1º dia feito
    select min(a.dia) into v_ini from public.agenda_alocacoes a
     where a.service_order_id = r.os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
       and a.resultado in ('cumprido', 'parcial');
    if v_ini is not null and v_ini >= p_hoje - 1 and v_ini <= p_hoje then
      v_alvo := case when v_ini = p_hoje then greatest(p_agora, (p_hoje + c_hora_tarde) at time zone 'America/Sao_Paulo')
                     else greatest(p_agora, public._agenda_cliente_toque(p_hoje)) end;
      v_env := (public._agenda_cliente_quando(0, v_alvo, p_agora) at time zone 'America/Sao_Paulo')::date;
      if v_env in (v_ini, v_ini + 1) then
        v_r := public._agenda_cliente_registrar('andamento', 'primeiro_dia', r.os, v_ini,
                 jsonb_build_object('quando', case when v_env = v_ini then 'hoje' else 'ontem' end, 'chave', 'inicio'),
                 v_alvo, public._agenda_cliente_fim_da_janela(v_ini, 1), 'rodada', null, p_agora);
        if coalesce((v_r ->> 'criada')::boolean, false) then n_ini := n_ini + 1; end if;
      end if;
    end if;
    -- (b) o semanal
    if (x ->> 'dias')::int > cf.cliente_andamento_min_du and v_ini is not null and v_ini < p_hoje then
      select max(m.enviada_em) into v_ult from public.agenda_cliente_mensagens m
       where m.service_order_id = r.os and m.tipo = 'andamento' and m.enviada_em is not null;
      if coalesce((v_ult at time zone 'America/Sao_Paulo')::date, v_ini) + cf.cliente_andamento_intervalo_dias <= p_hoje then
        v_r := public._agenda_cliente_registrar('andamento', 'semanal', r.os, (x ->> 'ultimo_dia')::date,
                 jsonb_build_object('n_feitos', floor(coalesce((x ->> 'meios_cumpridos')::numeric, 0))::int,
                                    'chave', to_char(p_hoje, 'IYYY-"S"IW')),
                 greatest(p_agora, public._agenda_cliente_toque(p_hoje)), public._agenda_cliente_fim_da_janela(p_hoje, 1),
                 'rodada', null, p_agora);
        if coalesce((v_r ->> 'criada')::boolean, false) then n_sem := n_sem + 1; end if;
      end if;
    end if;
  end loop;
  return jsonb_build_object('primeiro_dia', n_ini, 'semanal', n_sem);
end;
$function$;

-- Passo "pronto": a OS concluída (completed) sem entrega, concluída hoje ou ontem — o "ficou pronto" (M8) na hora (até o
-- fim da janela; senão na manhã seguinte), válido até o fim do 2º dia de janela. O lembrete (M8), uma vez,
-- cliente_pronto_lembrete_dias dias depois do "ficou pronto" enviado, sem resposta e ainda sem entrega (no toque do 1º dia de
-- janela a partir daí).
create or replace function public._agenda_cliente_pronto(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  r      record;
  v_dia  date;
  v_alvo timestamptz;
  v_r    jsonb;
  n_pr   int := 0;
  n_lem  int := 0;
begin
  for r in
    select so.id as os, (so.check_out_at at time zone 'America/Sao_Paulo')::date as concluida
      from public.service_orders so
     where so.status = 'completed' and so.delivered_at is null and so.merged_into_id is null
       and so.check_out_at is not null and so.check_out_at <= p_agora
       and (so.check_out_at at time zone 'America/Sao_Paulo')::date between p_hoje - 1 and p_hoje
     order by so.service_order_number collate "C", so.id
  loop
    v_r := public._agenda_cliente_registrar('pronto', null, r.os, r.concluida, '{}'::jsonb, p_agora,
             public._agenda_cliente_fim_da_janela(r.concluida, 1), 'rodada', null, p_agora);
    if coalesce((v_r ->> 'criada')::boolean, false) then n_pr := n_pr + 1; end if;
  end loop;
  for r in
    select m.service_order_id as os, (m.enviada_em at time zone 'America/Sao_Paulo')::date as enviada
      from public.agenda_cliente_mensagens m
      join public.service_orders so on so.id = m.service_order_id
     where m.tipo = 'pronto' and m.estado = 'enviada' and m.resposta_id is null
       and so.status = 'completed' and so.delivered_at is null
       and not exists (select 1 from public.agenda_cliente_mensagens l
                        where l.service_order_id = m.service_order_id and l.tipo = 'pronto_lembrete')
     order by m.enviada_em, m.id
  loop
    v_alvo := public._agenda_cliente_toque(r.enviada + cf.cliente_pronto_lembrete_dias);
    v_dia := (v_alvo at time zone 'America/Sao_Paulo')::date;
    continue when not public._agenda_cliente_ja_registra(v_dia, p_hoje, p_agora);
    if v_alvo < p_agora then
      v_alvo := greatest(p_agora, public._agenda_cliente_toque(p_hoje));
    end if;
    v_r := public._agenda_cliente_registrar('pronto_lembrete', null, r.os, null, jsonb_build_object('chave', '2'), v_alvo,
             public._agenda_cliente_fim_da_janela((v_alvo at time zone 'America/Sao_Paulo')::date, 1), 'rodada', null, p_agora);
    if coalesce((v_r ->> 'criada')::boolean, false) then n_lem := n_lem + 1; end if;
  end loop;
  return jsonb_build_object('pronto', n_pr, 'lembrete', n_lem);
end;
$function$;

-- Passo "pos_servico": cliente_pos_dias depois da entrega (ou da conclusão, quando não houve entrega em cliente_pos_dias), de
-- segunda a sexta (dia de janela), entre o toque e c_janela_pos depois dele; o que passou da hora vai ao próximo dia útil
-- de janela. Uma por OS (chave pos). Válido até o fim do 3º dia de janela; o que já passou disso a contar do dia certo não
-- sai mais. Não sai com uma pergunta cliente_resposta aberta do cliente nem com mensagem dele nos últimos c_quieto.
create or replace function public._agenda_cliente_pos_servico(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_janela_pos constant interval := interval '2 hours';   -- spec §5.3: "entre 09:00 e 11:00 de seg–sex"
  c_quieto     constant interval := interval '3 days';    -- spec §5.3: "nem com mensagem dele nos últimos 3 dias"
  r       record;
  v_alvo  date;
  v_d     date;
  v_t     timestamptz;
  v_r     jsonb;
  n_reg   int := 0;
  n_esp   int := 0;
begin
  for r in
    select so.id as os, so.client_id,
           coalesce((so.delivered_at at time zone 'America/Sao_Paulo')::date,
                    case when (so.check_out_at at time zone 'America/Sao_Paulo')::date + cf.cliente_pos_dias <= p_hoje
                         then (so.check_out_at at time zone 'America/Sao_Paulo')::date end) as base
      from public.service_orders so
     where so.status = 'completed' and so.merged_into_id is null and so.check_out_at is not null
       and (so.check_out_at at time zone 'America/Sao_Paulo')::date >= p_hoje - 62
       and not exists (select 1 from public.agenda_cliente_mensagens m
                        where m.service_order_id = so.id and m.tipo = 'pos_servico')
     order by so.service_order_number collate "C", so.id
  loop
    continue when r.base is null;
    v_alvo := r.base + cf.cliente_pos_dias;
    continue when v_alvo > p_hoje;
    -- o dia certo: o 1º dia de janela de segunda a sexta a partir de base + cliente_pos_dias; passou do 3º dia de janela
    -- dele, não sai mais
    v_d := v_alvo;
    while not (public._agenda_cliente_dia_de_janela(v_d) and extract(isodow from v_d) <= 5) loop
      v_d := v_d + 1;
    end loop;
    continue when public._agenda_cliente_fim_da_janela(v_d, 2) < p_agora;
    -- o cliente conversando (mensagem dele nos últimos dias) ou com uma resposta esperando o dono: agora não
    if exists (select 1 from public.agenda_perguntas q
                where q.tipo = 'cliente_resposta' and q.estado = 'aberta'
                  and q.service_order_id in (select x.id from public.service_orders x where x.client_id = r.client_id))
       or exists (select 1 from public.clients c
                    join public.whatsapp_messages w
                      on public._agenda_chave_telefone(w.phone_normalized)
                         in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone))
                   where c.id = r.client_id and w.direction = 'inbound' and w.occurred_at <= p_agora
                     and w.occurred_at > p_agora - c_quieto) then
      n_esp := n_esp + 1;
      continue;
    end if;
    -- a hora: hoje, se é segunda a sexta de janela e ainda está entre o toque e o toque + c_janela_pos; senão o toque do
    -- próximo dia útil de janela
    v_d := greatest(v_d, p_hoje);
    loop
      v_t := (v_d + cf.cliente_hora_toque) at time zone 'America/Sao_Paulo';
      exit when public._agenda_cliente_dia_de_janela(v_d) and extract(isodow from v_d) <= 5 and v_t + c_janela_pos > p_agora;
      v_d := v_d + 1;
      if v_d > p_hoje + 31 then
        raise exception '_agenda_cliente_pos_servico: nenhum dia útil de janela em 31 dias' using errcode = '54000';
      end if;
    end loop;
    v_r := public._agenda_cliente_registrar('pos_servico', null, r.os, null, jsonb_build_object('chave', 'pos'),
             greatest(v_t, p_agora), public._agenda_cliente_fim_da_janela(v_d, 2), 'rodada', null, p_agora);
    if coalesce((v_r ->> 'criada')::boolean, false) then n_reg := n_reg + 1; end if;
  end loop;
  return jsonb_build_object('registradas', n_reg, 'esperando_o_cliente', n_esp);
end;
$function$;

-- Passo "sem_resposta": a confirmação, o material chegou, a nova data e a mudança no dia enviados há mais de
-- cliente_sem_resposta_horas sem resposta ficam sem_resposta, com a pergunta cliente_resposta ao dono ("O Nelson não
-- respondeu a confirmação de qui 05/11.") — sem reenviar. A pergunta some em c_resposta_dias.
create or replace function public._agenda_cliente_sem_resposta(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_resposta_dias constant interval := interval '7 days';   -- spec §3.2: "some ... em 7 dias"
  v_modo  text := case when cf.modo_cliente = 'ligado' then 'ligado' else 'sombra' end;
  r       record;
  v_dia   date;
  n       int := 0;
begin
  for r in
    select m.id, m.service_order_id as os, m.tipo, m.dia_alvo, m.base, cl.name, cl.display_name
      from public.agenda_cliente_mensagens m
      join public.clients cl on cl.id = m.client_id
     where m.modo = 'ligado' and m.estado = 'enviada' and m.resposta_id is null
       and m.tipo in ('confirmar', 'material_chegou', 'nova_data', 'mudanca_no_dia')
       and m.enviada_em < p_agora - make_interval(hours => cf.cliente_sem_resposta_horas)
     order by m.enviada_em, m.id
  loop
    update public.agenda_cliente_mensagens set estado = 'sem_resposta' where id = r.id and estado = 'enviada';
    v_dia := coalesce((r.base ->> 'dia_alvo')::date, r.dia_alvo);
    perform public._agenda_cliente_perguntar('cliente_resposta', 'cliente_resposta:sem_resposta:' || r.id, r.os, v_dia, null,
      format('O %s não respondeu %s.',
             coalesce(public._agenda_nome_curto(coalesce(nullif(btrim(coalesce(r.display_name, '')), ''), r.name)), 'cliente'),
             case r.tipo
               when 'confirmar' then 'a confirmação' || coalesce(' de ' || public._dia_curto(v_dia), '')
               when 'material_chegou' then 'o aviso de que o material chegou' || coalesce(' (' || public._dia_curto(v_dia) || ')', '')
               when 'nova_data' then 'a nova data' || coalesce(' (' || public._dia_curto(v_dia) || ')', '')
               else 'a mudança do dia' || coalesce(' (' || public._dia_curto(v_dia) || ')', '') end),
      v_modo, p_agora, p_agora + c_resposta_dias);
    n := n + 1;
  end loop;
  return jsonb_build_object('sem_resposta', n);
end;
$function$;

-- ── 5. A rodada ─────────────────────────────────────────────────────────────────────────────────────────

-- A rodada do cliente, a cada 15 min, pelo task-automations (depois da vigia, antes das regras). Antes de tudo, em
-- qualquer modo, o passo "fila" (_agenda_cliente_fila). modo_cliente desligado = {rodou: false} e nada mais. Os passos,
-- cada um no seu bloco (o que falha vai a app_error_logs, context agenda, action cliente:<passo>, e os outros rodam), na
-- ordem: material e mudanca_no_dia (antes da confirmação: o M3/M7 e o M10 que propõem o dia D substituem o M1 e a véspera
-- do mesmo D), confirmar, atraso, andamento, pronto, pos_servico, sem_resposta. Uma linha em agenda_vigia_rodadas (rotina cliente). Os acordes (as ações
-- de acorde ainda não contadas de hoje e de ontem) só com a vigia ligada, na cota acordes_dia_max do dia, como os da rotina.
create or replace function public.agenda_cliente_vigiar(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_passos  constant text[] := array['material', 'mudanca_no_dia', 'confirmar', 'atraso', 'andamento', 'pronto',
                                     'pos_servico', 'sem_resposta'];
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
    raise exception 'Faltam o dia e a hora da rodada do cliente.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  cf := public._agenda_cfg();
  -- A fila do cliente roda SEMPRE, em qualquer modo (até desligado): o que ficou fora da janela, com o modo ou o tipo fora
  -- de ligado, ou que a revalidação recusa, não sai; o que é hora de mandar vai à fila; o que venceu sem o dono vence.
  begin
    v_cont := jsonb_build_object('fila', public._agenda_cliente_fila(p_hoje, p_agora));
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    v_erros := v_erros + 1;
    v_falhas := v_falhas || jsonb_build_object('passo', 'fila', 'sqlstate', v_estado, 'erro', left(v_msg, 300));
    perform public.log_app_error('db', 'mensagem ao cliente, passo fila: ' || v_msg, 'agenda', 'cliente:fila', 'error',
                                 jsonb_build_object('passo', 'fila', 'sqlstate', v_estado, 'p_hoje', p_hoje, 'p_agora', p_agora));
  end;
  if cf.modo_cliente = 'desligado' then
    return jsonb_build_object('rodou', false, 'modo', cf.modo_cliente, 'fila', v_cont -> 'fila', 'erros', v_erros,
                              'falhas', v_falhas, 'acordes', '[]'::jsonb);
  end if;

  foreach v_passo in array c_passos loop
    begin
      execute format('select public.%I($1, $2)', '_agenda_cliente_' || v_passo) into v_r using p_hoje, p_agora;
      v_cont := v_cont || jsonb_build_object(v_passo, coalesce(v_r, '{}'::jsonb));
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      v_erros := v_erros + 1;
      v_falhas := v_falhas || jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'erro', left(v_msg, 300));
      perform public.log_app_error('db', format('mensagem ao cliente, passo %s: %s', v_passo, v_msg), 'agenda',
                                   'cliente:' || v_passo, 'error',
                                   jsonb_build_object('passo', v_passo, 'sqlstate', v_estado, 'p_hoje', p_hoje,
                                                      'p_agora', p_agora));
    end;
  end loop;

  -- Os acordes: como os da rotina — só com a vigia ligada e a ação executada, na cota acordes_dia_max do dia.
  if cf.modo_vigia = 'ligado' then
    v_cota := greatest(cf.acordes_dia_max - (select count(*)::int from public.agenda_acoes a
                                              where a.dia = p_hoje and a.contada_via = 'acorde'), 0);
    select coalesce(jsonb_agg(q.e order by q.ord), '[]'::jsonb) into v_acordes
      from (select jsonb_build_object('chave', 'agenda:' || a.id, 'assunto', 'cliente:' || a.service_order_id,
                                      'acao_id', a.id, 'os', a.service_order_id, 'perda_em', a.depois ->> 'perda_em',
                                      'texto', a.texto) as e,
                   row_number() over (order by (a.depois ->> 'perda_em')::date nulls last, a.criada_em, a.id) as ord
              from public.agenda_acoes a
             where a.tipo = 'cliente' and a.executada and a.contada_em is null
               and coalesce((a.depois ->> 'acorde')::boolean, false) and a.dia >= p_hoje - 1) q
     where q.ord <= v_cota;
  end if;

  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms,
                                           rotina, modo_equipe, modo_diaria)
  values (clock_timestamp(), p_hoje, p_agora, cf.modo_proposta, cf.modo_vigia,
          v_cont || jsonb_build_object('modo_cliente', cf.modo_cliente, 'tipos_ligados', to_jsonb(cf.cliente_tipos_ligados),
                                       'acordes', jsonb_array_length(v_acordes), 'falhas', v_falhas),
          least(v_erros, 32767), greatest(0, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int),
          'cliente', cf.modo_equipe, cf.modo_diaria);

  return jsonb_build_object('rodou', true, 'modo', cf.modo_cliente, 'tipos_ligados', to_jsonb(cf.cliente_tipos_ligados),
                            'contagens', v_cont, 'erros', v_erros, 'falhas', v_falhas, 'acordes', v_acordes);
end;
$function$;

comment on function public.agenda_cliente_vigiar(date, timestamptz) is
  'Agenda de Produção (Fase 5, P3): a rodada da mensagem ao cliente, a cada 15 min, pelo task-automations (depois da vigia, antes das regras). Antes de tudo, em qualquer modo, o passo fila (_agenda_cliente_fila). modo_cliente desligado = {rodou: false}. Passos, cada um no seu bloco (o que falha vai para app_error_logs, context agenda, action cliente:<passo>, e os outros rodam): material (o material chegou M3 / a nova data M7), mudanca_no_dia (M10, ou o acorde sem decisão), confirmar (a confirmação M1 em D − cliente_confirmar_du dias úteis, a véspera M2 ou o acesso M4 no último dia de janela antes de D, ou um toque só), atraso (o aviso M6 no 1º tique a partir de cliente_hora_preparo, ou na hora com o prometido a até cliente_atraso_na_hora_du dias úteis; nunca depois da data: cliente_aviso passou; 2º atraso e atraso longo = pergunta crítica), andamento (M5), pronto (M8 e o lembrete), pos_servico (M9), sem_resposta (a pergunta cliente_resposta). Tudo pelo _agenda_cliente_registrar (o modo, a aprovação dos primeiros dias, as travas). Uma linha em agenda_vigia_rodadas (rotina = cliente). {rodou, modo, tipos_ligados, contagens, erros, falhas, acordes} — os acordes só com a vigia ligada, na cota acordes_dia_max. Só service_role.';

-- ── 6. A decisão do dono sobre uma mensagem ao cliente ──────────────────────────────────────────────────

-- cliente_aprovar: 1 manda (aprovada; vai à fila se é a hora, senão o passo fila manda no tique certo — a janela, o teto e a
-- revalidação continuam valendo), 2 segura (não sai). cliente_aviso (crítica): 1 você liga e eu não mando nada, 2 eu mando
-- o aviso escrito (pelo canal: com o teto cheio, não sai, e o texto diz), 3 não aviso agora. Só com a pergunta aberta, em
-- ligado e com modo_cliente ligado. A pergunta fica respondida (a opção, as palavras, quem e por onde).
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
      v_r := public._agenda_cliente_enfileirar(m.id, p_agora);
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
  'Agenda de Produção (Fase 5, P3): a decisão do dono sobre a mensagem ao cliente (pergunta aberta, em ligado, com modo_cliente ligado; senão "As mensagens ao cliente estão em teste: nada sai ainda."). cliente_aprovar: 1 = aprovada (aprovada_em/por; à fila se é a hora — a janela, o teto e a revalidação continuam —, senão o passo fila manda no tique certo: "Mando ao Nelson amanhã às 09:00."), 2 = segurada (recusada/segurada: "Segurei a mensagem do Flávio: ela não sai."). cliente_aviso (crítica): 1 = você liga e nada sai, 2 = manda pelo canal (teto cheio = não sai e o texto diz), 3 = não aviso agora; a ação crítica (tipo cliente, origem dono) fica na trilha; a pergunta sem mensagem (a data dita que já passou) não manda nada. A mensagem que já não espera fecha a pergunta (resolvida) sem mudar nada. Chamada por agenda_decidir (e pelo *manda cliente* / *segura cliente* do P5). Interna (sem grant).';

-- ── 7. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 5:") ─────────
-- agenda_decidir: corpo de 20261026100300 (a mais nova); agenda_saude: corpo de 20261027100500 (a mais nova, com os blocos
-- das Fases 3 e 4). Fora dos blocos "-- FASE 5:" nenhuma linha muda (o R12 confere). A casca não muda.

create or replace function public.agenda_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid default null,
                                                 p_via text default 'whatsapp', p_trecho text default null,
                                                 p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config;
  v_q    public.agenda_perguntas%rowtype;
  v_opc  jsonb;
  v_rest jsonb;
  v_sim  jsonb;
  v_mud  text;
  v_r    jsonb;
  v_ap   jsonb;
begin
  if p_via is null or p_via not in ('whatsapp', 'painel', 'tela') then
    raise exception 'Canal desconhecido para a decisão: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  select * into v_q from public.agenda_perguntas where id = p_pergunta for update;
  if not found then
    raise exception 'Não encontrei essa pergunta.' using errcode = 'P0002';
  end if;
  -- FASE 3: a diária (a pergunta crítica que diverge e a de ligar a OS) tem o efeito dela e o modo dela (modo_diaria):
  -- _agenda_decidir_diaria (20261026100300).
  if v_q.tipo in ('diaria', 'diaria_ligar') then
    return public._agenda_decidir_diaria(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_hoje, p_agora);
  end if;
  -- FASE 3: fim
  -- FASE 5: a mensagem ao cliente (cliente_aprovar, a aprovação dos primeiros dias, e cliente_aviso, a crítica do aviso de
  -- atraso) tem o efeito dela e o modo dela (modo_cliente): _agenda_cliente_decidir (20261028100300).
  if v_q.tipo in ('cliente_aprovar', 'cliente_aviso') then
    return public._agenda_cliente_decidir(v_q.id, p_opcao, p_autor, p_via, p_trecho, p_agora);
  end if;
  -- FASE 5: fim
  if not v_q.critica then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta não é de decisão.');
  end if;
  if v_q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  if v_q.modo <> 'ligado' or cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.');
  end if;
  select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
  if v_opc is null then
    return jsonb_build_object('ok', false,
      'texto', 'Essa opção não existe. As opções são: '
               || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                     from jsonb_array_elements(v_q.opcoes) o) || '.');
  end if;
  v_rest := coalesce(v_opc #> '{efeito,restricoes}', '{}'::jsonb);

  -- A agenda mudou desde a pergunta: o efeito da opção é refeito agora; se não termina como a opção dizia, a pergunta
  -- volta com os dias de agora (nada é executado).
  if v_q.versao_base is distinct from cf.versao_plano and jsonb_typeof(v_opc -> 'espera') = 'object'
     and v_opc -> 'espera' <> '{}'::jsonb then
    v_sim := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest, false, 'dono', p_autor, p_hoje, p_agora);
    select string_agg(format('%s termina %s (antes eu disse %s)', public._agenda_rotulo_da_os(e.key::uuid),
                             coalesce(public._dia_curto(x.fim), 'sem encaixe'), public._dia_curto((e.value #>> '{}')::date)), '; ')
      into v_mud
      from jsonb_each(v_opc -> 'espera') e
      left join lateral (select max((i ->> 'fim_depois')::date) as fim from jsonb_array_elements(v_sim -> 'itens') i
                          where i ->> 'op' = 'criar' and i ->> 'os' = e.key and i ->> 'tipo' <> 'reserva') x on true
     where x.fim is distinct from (e.value #>> '{}')::date;
    if v_mud is not null then
      return jsonb_build_object('ok', false, 'mudou', true,
        'texto', 'A agenda mudou desde a pergunta: ' || v_mud || '. Me responda de novo com os dias de agora.');
    end if;
  end if;

  begin
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = p_pergunta;
    v_r := public.agenda_propor('replano', null, null, v_q.os_ids, v_rest || jsonb_build_object('decisao', p_pergunta),
                                true, 'dono', p_autor, p_hoje, p_agora);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_r ->> 'texto', 'não deu');
    end if;
    v_ap := public.agenda_aplicar((v_r ->> 'proposta_id')::uuid, null, 'dono', p_autor, p_pergunta, p_hoje, p_agora);
    if not coalesce((v_ap ->> 'ok')::boolean, false) then
      raise exception using errcode = 'P0098', message = coalesce(v_ap ->> 'texto', 'não deu');
    end if;
  exception when sqlstate 'P0098' then
    -- nada fica: a pergunta continua aberta
    return jsonb_build_object('ok', false, 'texto', 'Não consegui fazer o que você escolheu: ' || sqlerrm || ' Nada mudou.');
  end;
  return jsonb_build_object('ok', true, 'texto', 'Feito: ' || (v_ap ->> 'texto'), 'acoes', v_ap -> 'acoes',
                            'proposta_id', v_r ->> 'proposta_id');
end;
$function$;

comment on function public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): a resposta do dono a uma pergunta crítica aberta (só em ligado). Opção que não existe = recusa, nada marcado. Se a agenda mudou desde a pergunta, o efeito da opção é refeito agora e, se não termina como a opção dizia (espera), devolve a pergunta com os dias de agora sem executar. Senão: a pergunta fica respondida (opcao_escolhida, resposta = as palavras do dono, respondida_*) e o efeito é executado — agenda_propor(replano, as OS da pergunta, as restrições da opção + decisao) e agenda_aplicar com p_pergunta (toda ação sai critica = true com pergunta_id). Falhou = nada fica, a pergunta continua aberta. Canais: whatsapp, painel, tela. Fase 3: diaria e diaria_ligar vão a _agenda_decidir_diaria (o lançamento, a correção pelo registrar_diaria ou a ligação às OS, com modo_diaria ligado). Fase 5 (P3): cliente_aprovar e cliente_aviso vão a _agenda_cliente_decidir (manda ou segura a mensagem ao cliente; com modo_cliente ligado).';

create or replace function public.agenda_saude(p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf        public.agenda_config := public._agenda_cfg();
  v_cart    uuid[];
  v_ult     record;
  v_vig     jsonb;
  v_hoje    jsonb;
  v_crit    jsonb;
  v_perg    jsonb;
  v_prop    jsonb;
  v_plano   jsonb;
  v_inv     jsonb;
  v_fech    jsonb;
  v_sem     int;
  v_regra   jsonb;
  v_leu     boolean;
  v_choques int;
  -- FASE 3
  v_rot     jsonb;
  v_eq      jsonb;
  v_dia     jsonb;
  v_conc    jsonb;
  v_marcos  jsonb;
  v_com     jsonb;
  v_teto    int;
  v_janela  int;
  v_semconf int;
  v_sobre   int;
  v_semrec  int;
  v_pay     int;
  -- FASE 4: o material e a mensagem ao fornecedor
  v_mrod    jsonb;
  v_rem     jsonb;
  v_mperg   jsonb;
  v_semdono int;
  v_semorig int;
  v_prec    jsonb;
  v_det     jsonb;
  v_fsombra int;
  v_ffora   int;
  v_fteto   int;
  v_fproib  int;
  v_forn    jsonb;
  v_cob     jsonb;
  v_med     numeric;
  v_zeros4  boolean;
  v_mat     jsonb;
  -- FASE 4: fim
  -- FASE 5: a mensagem ao cliente
  v_crod    jsonb;
  v_cmsg    jsonb;
  v_caprov  jsonb;
  v_cjan    int;
  v_cdom    int;
  v_cteto   int;
  v_cint    int;
  v_cproib  int;
  v_csombra int;
  v_csemap  int;
  v_ccrit   int;
  v_cvesp   int;
  v_cdepois int;
  v_caudio  int;
  v_cmet    jsonb;
  v_zeros5  boolean;
  v_cli     jsonb;
  -- FASE 5: fim
begin
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k);

  select max(x.p_agora) as ultima, max(x.rodou_em) as rodou_em,
         count(*) filter (where x.p_agora > p_agora - interval '1 day' and x.p_agora <= p_agora) as n24,
         (array_agg(x.erros order by x.p_agora desc, x.rodou_em desc))[1] as erros_ult
    into v_ult from public.agenda_vigia_rodadas x
   -- FASE 3: a rotina da equipe grava na mesma tabela (rotina = 'rotina'); a vigia é só a dela.
   where x.rotina = 'vigia';
  v_vig := jsonb_build_object(
    'ultima_rodada', v_ult.ultima, 'rodou_em', v_ult.rodou_em,
    'rodou_nas_ultimas_2h', coalesce(v_ult.ultima > p_agora - interval '2 hours', false),
    'rodadas_24h', coalesce(v_ult.n24, 0), 'erros_ultima_rodada', coalesce(v_ult.erros_ult, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'));

  select jsonb_build_object(
           'publicar', count(*) filter (where a.executada and a.tipo = 'publicar'),
           'criar', count(*) filter (where a.executada and a.tipo = 'criar'),
           'mover', count(*) filter (where a.executada and a.tipo = 'mover'),
           'cancelar', count(*) filter (where a.executada and a.tipo = 'cancelar'),
           'promover', count(*) filter (where a.executada and a.tipo = 'promover_reserva'),
           'soltar', count(*) filter (where a.executada and a.tipo = 'soltar_reserva'),
           'status', count(*) filter (where a.executada and a.tipo = 'status'),
           'resultado', count(*) filter (where a.executada and a.tipo = 'resultado'),
           'desfeitas', count(*) filter (where a.executada and a.tipo = 'desfazer'),
           'sombra', count(*) filter (where not a.executada))
    into v_hoje from public.agenda_acoes a where a.dia = p_hoje;

  -- A prova: nenhuma ação crítica executada sem a decisão registrada (o gatilho impede; isto confere).
  select count(*) into v_sem
    from public.agenda_acoes a left join public.agenda_perguntas q on q.id = a.pergunta_id
   where a.executada and a.critica and (q.id is null or q.estado <> 'respondida' or q.opcao_escolhida is null);
  -- E o erro de classificação: ação autônoma executada como não crítica que a regra diz crítica.
  select jsonb_build_object('n', count(*), 'acoes', coalesce(jsonb_agg(a.id order by a.criada_em, a.id), '[]'::jsonb)) into v_regra
    from public.agenda_acoes a
   where a.executada and not a.critica and a.origem in ('motor', 'vigia', 'conferencia')
     and a.tipo in ('publicar', 'criar', 'mover', 'cancelar', 'promover_reserva', 'soltar_reserva')
     and public._agenda_criticidade_da_acao(a.id) is not null;
  v_crit := jsonb_build_object(
    'abertas', (select count(*) from public.agenda_perguntas q where q.critica and q.estado = 'aberta'),
    'respondidas_7d', (select count(*) from public.agenda_perguntas q
                        where q.critica and q.estado = 'respondida' and q.respondida_em > p_agora - interval '7 days'),
    'sem_decisao', v_sem, 'pela_regra_sem_decisao', (v_regra ->> 'n')::int, 'pela_regra_acoes', v_regra -> 'acoes');

  v_perg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q where q.estado = 'aberta' group by q.tipo) t), '{}'::jsonb),
    'abertas_sombra', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.modo = 'sombra'),
    'mostradas_hoje', (select count(*) from public.agenda_perguntas q
                        where (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  select jsonb_build_object(
           'abertas', count(*) filter (where p.estado = 'aberta'),
           'obsoletas_7d', count(*) filter (where p.estado = 'obsoleta' and p.criada_em > p_agora - interval '7 days'),
           'aplicadas_7d', count(*) filter (where p.estado = 'aplicada' and p.criada_em > p_agora - interval '7 days'),
           'sombra_7d', count(*) filter (where p.modo = 'sombra' and p.criada_em > p_agora - interval '7 days'))
    into v_prop from public.agenda_propostas p;

  select jsonb_build_object(
           'alocacoes_vigentes_futuras', count(*) filter (where a.dia >= p_hoje and a.resultado is null),
           'os_programadas', count(distinct a.service_order_id) filter (where a.dia >= p_hoje and a.resultado is null and a.tipo <> 'reserva'),
           'reservas', count(*) filter (where a.dia >= p_hoje and a.tipo = 'reserva'),
           'sem_registro_7d', count(*) filter (where a.resultado = 'sem_registro' and a.dia > p_hoje - 7))
    into v_plano from public.agenda_alocacoes a where a.estado in ('publicada', 'fixada');

  select count(*) into v_choques
    from public.agenda_alocacoes a join public.agenda_alocacoes b
      on b.payee_id = a.payee_id and b.id > a.id and b.periodo && a.periodo
   where a.estado in ('publicada', 'fixada') and b.estado in ('publicada', 'fixada');
  v_inv := jsonb_build_object(
    'vigente_de_os_fora_da_carteira', (select count(distinct a.service_order_id) from public.agenda_alocacoes a
                                        where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
                                          and not (a.service_order_id = any (v_cart))),
    'espelho_divergente', case when cf.modo_proposta <> 'ligado' then 0 else (
       select count(*) from public.service_orders so
        cross join lateral (select min(lower(a.periodo)) as ini, max(upper(a.periodo)) as fim from public.agenda_alocacoes a
                             where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                               and a.resultado is distinct from 'nao_cumprido') m
        where so.id = any (v_cart)
          and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = so.id)
          and (so.scheduled_start_at is distinct from m.ini or so.scheduled_end_at is distinct from m.fim)) end,
    'choques', v_choques);

  if to_regclass('public.resumo_tarde') is not null then
    execute $q$select exists (select 1 from public.resumo_tarde t
                               where t.dia = $1 and jsonb_typeof(t.detalhe -> 'agenda') = 'object'
                                 and (t.detalhe -> 'agenda' ? 'linhas_diria' or t.detalhe -> 'agenda' ? 'linhas'))$q$
      into v_leu using p_hoje;
  end if;
  v_fech := jsonb_build_object(
    'leu_o_plano_hoje', v_leu,
    'linhas_mostradas', (select count(*) from public.agenda_acoes a
                          where a.contada_via = 'fechamento' and (a.contada_em at time zone 'America/Sao_Paulo')::date = p_hoje)
                        + (select count(*) from public.agenda_perguntas q
                            where q.mostrada_via = 'fechamento' and (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje));

  -- FASE 3: a rotina, a equipe, as diárias, a conclusão, os marcos e a comissão. Os "0 obrigatórios": acima do teto, fora
  -- da janela, diária sem confirmação, turno sobrescrito pela agenda, conclusão sem cobrança quando devia, pagamento de
  -- comissão de técnico.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'rotina:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_rot from public.agenda_vigia_rodadas x where x.rotina = 'rotina';
  select count(*) into v_teto
    from (select m.payee_id, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia, m.tipo = 'resposta' as resp, count(*) as n
            from public.agenda_equipe_mensagens m
           where m.modo = 'ligado' and m.estado in ('enfileirada', 'respondida', 'sem_resposta')
           group by 1, 2, 3) t
   where t.n > case when t.resp then cf.equipe_respostas_dia_max else cf.equipe_proativas_dia_max end;
  -- (revisão C1) pela regra única da janela (_agenda_equipe_fora_da_janela): a resposta direta tem a dela
  select count(*) into v_janela
    from public.whatsapp_send_queue q
    left join public.agenda_equipe_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-equipe'
     and (x.id is null
          or public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.scheduled_for) is not null
          -- o que SAIU fora da janela (o worker atrasado): também conta
          or (q.sent_at is not null and public._agenda_equipe_fora_da_janela(x.tipo, x.enviar_em, q.sent_at) is not null));
  v_eq := jsonb_build_object(
    'mensagens_hoje_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select m.tipo, count(*) as n from public.agenda_equipe_mensagens m
         where (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.tipo) t), '{}'::jsonb),
    'recusadas_hoje_por_motivo', coalesce((select jsonb_object_agg(t.recusa_motivo, t.n) from (
        select m.recusa_motivo, count(*) as n from public.agenda_equipe_mensagens m
         where m.estado = 'recusada' and (m.enviar_em at time zone 'America/Sao_Paulo')::date = p_hoje group by m.recusa_motivo) t), '{}'::jsonb),
    'acima_do_teto', v_teto, 'fora_da_janela', v_janela);
  select count(*) into v_semconf
    from public.agenda_acoes a
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono' and a.desfeita_em is null
     and coalesce(public._agenda_confirmacao_do_dia(a.payee_id, (a.depois ->> 'dia')::date) ->> 'estado', '') <> 'confirmada';
  select count(*) into v_sobre
    from public.agenda_acoes a left join public.work_shifts ws on ws.id = a.work_shift_id
   where a.tipo = 'diaria' and a.executada and not a.critica and a.origem <> 'dono'
     and (coalesce(jsonb_typeof(a.antes -> 'turno'), 'null') <> 'null' or (ws.id is not null and ws.origem <> 'agente'));
  v_dia := jsonb_build_object(
    -- (o dia de quem agiu: a.dia é o p_hoje dele; criada_em é o relógio do banco)
    'lancadas_7d', (select count(*) from public.agenda_acoes a
                     where a.tipo = 'diaria' and a.executada and a.origem <> 'dono' and a.dia > p_hoje - 7),
    'sombra_7d', (select count(*) from public.agenda_acoes a
                   where a.tipo = 'diaria' and not a.executada and a.dia > p_hoje - 7),
    'perguntas_abertas', (select count(*) from public.agenda_perguntas q where q.tipo in ('diaria', 'diaria_ligar') and q.estado = 'aberta'),
    'sem_confirmacao', v_semconf, 'sobrescreveu_turno', v_sobre);
  -- a conclusão pela porta sem cobrança viva quando a regra da condição dá parcelas ou título (a releitura é só service_role)
  if has_function_privilege('public._os_recebiveis_da_conclusao(uuid, date)', 'execute') then
    select count(*) into v_semrec
      from (select distinct so.id, so.check_out_at
              from public.agenda_acoes a join public.service_orders so on so.id = a.service_order_id
             where a.tipo = 'concluir' and a.executada and a.desfeita_em is null and so.status in ('completed', 'invoiced')
               and so.check_out_at is not null
               and not exists (select 1 from public.receivables r where r.service_order_id = so.id and r.status <> 'cancelled')) t
     where public._os_recebiveis_da_conclusao(t.id, (t.check_out_at at time zone 'America/Sao_Paulo')::date) ->> 'motivo'
           in ('parcelas', 'titulo_unico');
  end if;
  v_conc := jsonb_build_object(
    'pela_agenda_7d', (select count(*) from public.agenda_acoes a
                        where a.tipo = 'concluir' and a.executada and a.origem in ('equipe', 'dono')
                          and a.dia > p_hoje - 7),
    'desfeitas_7d', (select count(*) from public.agenda_acoes a
                      where a.tipo = 'concluir' and a.desfeita_em > p_agora - interval '7 days'),
    'sem_recebivel_quando_devia', v_semrec);
  select jsonb_build_object(
           'concluidas_30d', count(*),
           'entregues_em_ate_5du', count(*) filter (where so.delivered_at is not null
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date,
                                        (so.delivered_at at time zone 'America/Sao_Paulo')::date) <= cf.entrega_aviso_du),
           'sem_entrega_ha_mais_de_5du', count(*) filter (where so.delivered_at is null and so.status = 'completed'
             and public.agenda_du_entre((so.check_out_at at time zone 'America/Sao_Paulo')::date, p_hoje) > cf.entrega_aviso_du))
    into v_marcos
    from public.service_orders so
   where so.check_out_at > p_agora - interval '30 days'
     and exists (select 1 from public.agenda_acoes a
                  where a.service_order_id = so.id and a.tipo = 'concluir' and a.executada and a.desfeita_em is null);
  select count(*) into v_pay
    from public.payables pa
   where pa.origin = 'commission' and pa.created_at > p_agora - interval '7 days'
     and pa.payee_id in (select w.payee_id from public.work_profiles w where w.modo_pagamento = 'diaria' and w.payee_id is not null);
  v_com := jsonb_build_object('pagamento', (select c.pagamento from public.comissao_config c where c.id),
                              'payables_de_comissao_tecnico_7d', v_pay);
  -- FASE 3: fim
  -- FASE 4: o material (a nota, o Pix, o detector, o cadastro) e a mensagem ao fornecedor. Os "0 obrigatórios": linha
  -- ligada a nota ou Pix sem a palavra do dono (vinculo_sem_resposta_do_dono), previsão sem o original guardado, e na
  -- mensagem ao fornecedor: nada na fila em sombra (ou sem a mensagem registrada), nada saindo ou que saiu fora da janela,
  -- nada acima do teto, nada com valor, pagamento, OS, link ou o nome do cliente.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'material:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_mrod from public.agenda_vigia_rodadas x where x.rotina = 'material';
  select jsonb_build_object(
           'a_caminho', count(*) filter (where r.estado = 'a_caminho'),
           'sem_resposta', count(*) filter (where r.vinculo = 'sem_resposta' and r.estado <> 'descartada'),
           'ligadas_7d', count(*) filter (where r.vinculo = 'ligada' and r.respondida_em > p_agora - interval '7 days'),
           'sem_servico_7d', count(*) filter (where r.vinculo = 'sem_servico' and r.respondida_em > p_agora - interval '7 days'),
           'chegaram_7d', count(*) filter (where r.estado = 'chegou' and r.chegou_em > p_hoje - 7))
    into v_rem from public.material_remessas r;
  v_mperg := jsonb_build_object(
    'abertas_por_tipo', coalesce((select jsonb_object_agg(t.tipo, t.n) from (
        select q.tipo, count(*) as n from public.agenda_perguntas q
         where q.estado = 'aberta'
           and q.tipo in ('nfe_vincular', 'pix_material', 'previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo')
         group by q.tipo) t), '{}'::jsonb),
    -- o teto do Pix (pix_perguntas_semana_max por semana ISO, no total), no modo de agora
    'pix_na_semana', (select count(*) from public.agenda_perguntas q
                       where q.tipo = 'pix_material'
                         and q.modo = case when cf.modo_material = 'ligado' then 'ligado' else 'sombra' end
                         and (q.criada_em at time zone 'America/Sao_Paulo')::date
                             between date_trunc('week', p_hoje)::date and date_trunc('week', p_hoje)::date + 6));
  -- a linha que a agenda ligou a uma nota ou a um Pix tem de ter a palavra do dono (ou a compra que ele já ligou)
  select count(*) into v_semdono
    from public.os_material m
   where (m.remessa_id is not null or m.fonte in ('nfe', 'pix'))
     and coalesce(m.evidencia ->> 'vinculo_por', '') not in ('dono', 'compra_ligada');
  select count(*) into v_semorig from public.os_material m where m.previsao_ate is not null and m.previsao_original is null;
  -- a precisão do detector é do administrador e do financeiro (para outro login ela lançaria 42501)
  if (select auth.uid()) is null or public.is_admin_or_financial((select auth.uid())) then
    v_prec := public.agenda_detector_precisao(p_hoje - 13, p_hoje);
  end if;
  v_det := jsonb_build_object(
    'sinais_14d', v_prec -> 'sinais', 'julgados_14d', v_prec -> 'julgados', 'certos_14d', v_prec -> 'certos',
    'precisao_14d', v_prec -> 'precisao', 'pronto_para_ligar', coalesce((v_prec ->> 'pronto_para_ligar')::boolean, false),
    'aplicados_7d', (select count(*) from public.material_sinais s where s.estado = 'aplicado' and s.dia > p_hoje - 7),
    'desfeitos_7d', (select count(*) from public.material_sinais s join public.agenda_acoes a on a.id = s.acao_id
                      where a.desfeita_em > p_agora - interval '7 days'));
  -- a mensagem ao fornecedor: o que entrou na fila sem a mensagem registrada em ligado (nada sai em sombra)
  select count(*) into v_fsombra
    from public.whatsapp_send_queue q
    left join public.agenda_fornecedor_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-fornecedor' and (x.id is null or x.modo <> 'ligado');
  v_fsombra := v_fsombra + (select count(*) from public.agenda_fornecedor_mensagens x
                             where x.modo <> 'ligado' and (x.fila_id is not null or x.estado = 'enfileirada'));
  -- o que está na fila, saindo ou saiu fora da janela da mensagem (pela regra única); o que falhou não saiu
  select count(*) into v_ffora
    from public.whatsapp_send_queue q
    join public.agenda_fornecedor_mensagens x on x.id = q.source_ref_id
   where q.source = 'agenda-fornecedor'
     and ((q.status in ('pending', 'sending', 'sent')
           and public._agenda_fornecedor_fora_da_janela(x.enviar_em, q.scheduled_for) is not null)
          or (q.sent_at is not null and public._agenda_fornecedor_fora_da_janela(x.enviar_em, q.sent_at) is not null));
  -- acima do teto: o que entrou na fila (ligado), por fornecedor no dia e na semana ISO, e no dia a todos
  with ent as (
    select x.fornecedor_id as f, (x.enviar_em at time zone 'America/Sao_Paulo')::date as dia
      from public.agenda_fornecedor_mensagens x
     where x.modo = 'ligado'
       and (x.fila_id is not null
            or exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-fornecedor' and q.source_ref_id = x.id))
  )
  select (select count(*) from (select e.f, e.dia from ent e group by 1, 2 having count(*) > cf.fornecedor_dia_max) a)
       + (select count(*) from (select e.f, date_trunc('week', e.dia) from ent e group by 1, 2
                                 having count(*) > cf.fornecedor_semana_max) b)
       + (select count(*) from (select e.dia from ent e group by 1 having count(*) > cf.fornecedor_total_dia_max) t)
    into v_fteto;
  select count(*) into v_fproib
    from public.agenda_fornecedor_mensagens x
   where public._agenda_fornecedor_texto_proibido(x.texto, x.service_order_id) is not null;
  select jsonb_build_object(
           'registradas_7d', count(*),
           'enfileiradas_7d', count(*) filter (where x.estado = 'enfileirada'),
           'em_teste_7d', count(*) filter (where x.modo = 'sombra'),
           'recusadas_7d_por_motivo', coalesce((
             select jsonb_object_agg(t.recusa_motivo, t.n) from (
               select y.recusa_motivo, count(*) as n from public.agenda_fornecedor_mensagens y
                where y.estado = 'recusada' and (y.enviar_em at time zone 'America/Sao_Paulo')::date > p_hoje - 7
                group by y.recusa_motivo) t), '{}'::jsonb))
    into v_forn
    from public.agenda_fornecedor_mensagens x
   where (x.enviar_em at time zone 'America/Sao_Paulo')::date > p_hoje - 7;
  -- a cobertura: os itens críticos das OS que começam nas próximas material_inicio_dias, e quantos têm data (nível A a D)
  select jsonb_build_object(
           'itens_criticos_proximos', count(*),
           'com_previsao', count(*) filter (where e ->> 'nivel' <> 'E'),
           'pct', case when count(*) > 0 then round(100 * (count(*) filter (where e ->> 'nivel' <> 'E'))::numeric / count(*)) end)
    into v_cob
    from (select k.id from unnest(v_cart) k(id)
           where public._agenda_inicio_previsto(k.id, p_hoje) between p_hoje and p_hoje + cf.material_inicio_dias) o
    cross join lateral jsonb_array_elements(coalesce(public.os_prontidao(o.id, p_hoje) #> '{material,itens}', '[]'::jsonb)) e
   where coalesce((e ->> 'critico')::boolean, false);
  -- a espera: a mediana dos dias corridos da aprovação (a régua de os_carteira) até a 1ª compra (o dia dito ou o da OC),
  -- das OS aprovadas nos últimos 90 dias que já compraram
  select percentile_cont(0.5) within group (order by t.d) into v_med
    from (select min(coalesce(m.comprado_em, (po.created_at at time zone 'America/Sao_Paulo')::date))
                 - (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date as d
            from public.service_orders so
            join public.os_material m on m.service_order_id = so.id
            left join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
            left join public.purchase_orders po on po.id = poi.purchase_order_id and po.status <> 'cancelled'
           where so.merged_into_id is null and so.status <> 'cancelled'
             and (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date
                 between p_hoje - 90 and p_hoje
           group by so.id
          having min(coalesce(m.comprado_em, (po.created_at at time zone 'America/Sao_Paulo')::date)) is not null) t;
  v_zeros4 := v_semdono = 0 and v_semorig = 0 and v_fsombra = 0 and v_ffora = 0 and v_fteto = 0 and v_fproib = 0;
  v_mat := jsonb_build_object(
    'modos', jsonb_build_object('material', cf.modo_material, 'detector', cf.modo_detector, 'fornecedor', cf.modo_fornecedor),
    'ultima_rodada', v_mrod -> 'ultima_rodada', 'rodou_nas_ultimas_2h', v_mrod -> 'rodou_nas_ultimas_2h',
    'erros_24h', v_mrod -> 'erros_24h',
    'remessas', v_rem, 'perguntas', v_mperg,
    'vinculo_sem_resposta_do_dono', v_semdono, 'previsao_sem_original', v_semorig,
    'detector', v_det,
    'fornecedor', v_forn || jsonb_build_object('na_fila_em_sombra', v_fsombra, 'fora_da_janela', v_ffora,
                                               'acima_do_teto', v_fteto, 'com_valor_ou_cliente', v_fproib),
    'cobertura', v_cob,
    'espera', jsonb_build_object('mediana_ate_comprar_90d', v_med));
  -- FASE 4: fim
  -- FASE 5: a mensagem ao cliente — o modo, as ondas e os tipos liberados, a rodada, as mensagens e a aprovação em 7 dias.
  -- Os "0 obrigatórios" (entram no ok pelo v_zeros4, para o ok ficar igual linha a linha): nada fora da janela (nem o que
  -- saiu fora dela), nada em feriado ou domingo, nada acima do teto, nada a menos do intervalo de outra, nada com texto
  -- proibido, nada na fila em teste, nada enviado sem a aprovação dos primeiros dias, nada crítico enviado sem a opção 2,
  -- nenhuma véspera com a OS aguardando peça, nenhum aviso de atraso depois da data dita, nenhum áudio que confirmou. As
  -- métricas não reprovam.
  select jsonb_build_object('ultima_rodada', max(x.p_agora),
                            'rodou_nas_ultimas_2h', coalesce(max(x.p_agora) > p_agora - interval '2 hours', false),
                            'erros_24h', (select count(*) from public.app_error_logs e
                                           where e.context = 'agenda' and e.action like 'cliente:%'
                                             and e.last_seen_at >= least(p_agora, now()) - interval '1 day'))
    into v_crod from public.agenda_vigia_rodadas x where x.rotina = 'cliente';
  select coalesce(jsonb_object_agg(t.tipo, jsonb_build_object('registradas', t.reg, 'aguardando', t.agu, 'enviadas', t.env,
                                                              'recusadas_por_motivo', t.rec)), '{}'::jsonb)
    into v_cmsg
    from (select m.tipo, count(*) as reg, count(*) filter (where m.estado = 'aguardando_dono') as agu,
                 count(*) filter (where m.enviada_em is not null) as env,
                 coalesce((select jsonb_object_agg(y.recusa_motivo, y.n)
                             from (select z.recusa_motivo, count(*) as n from public.agenda_cliente_mensagens z
                                    where z.tipo = m.tipo and z.estado = 'recusada' and z.criada_em > p_agora - interval '7 days'
                                    group by z.recusa_motivo) y), '{}'::jsonb) as rec
            from public.agenda_cliente_mensagens m
           where m.criada_em > p_agora - interval '7 days'
           group by m.tipo) t;
  select jsonb_build_object(
           'pedidas_abertas', count(*) filter (where m.estado = 'aguardando_dono' and m.aprovacao in ('pedida', 'critica')),
           'vencidas_7d', count(*) filter (where m.aprovacao = 'vencida' and m.criada_em > p_agora - interval '7 days'),
           'aprovadas_7d', count(*) filter (where m.aprovacao = 'aprovada' and m.aprovada_em > p_agora - interval '7 days'),
           'seguradas_7d', count(*) filter (where m.aprovacao = 'segurada' and m.aprovada_em > p_agora - interval '7 days'))
    into v_caprov from public.agenda_cliente_mensagens m where m.modo = 'ligado';
  -- a janela (a regra única): o que está na fila, saindo ou saiu fora da janela da mensagem; o feriado e o domingo à parte
  select count(*) filter (where t.f is not null), count(*) filter (where t.f in ('feriado', 'domingo'))
    into v_cjan, v_cdom
    from (select coalesce(case when q.status in ('pending', 'sending', 'sent')
                               then public._agenda_cliente_fora_da_janela(x.enviar_em, q.scheduled_for) end,
                          case when q.sent_at is not null then public._agenda_cliente_fora_da_janela(x.enviar_em, q.sent_at) end) as f
            from public.whatsapp_send_queue q
            join public.agenda_cliente_mensagens x on x.id = q.source_ref_id
           where q.source = 'agenda-cliente') t;
  -- o teto: o que entrou na fila (ligado), por cliente no dia e na semana ISO, e no dia a todos
  with ent as (
    select m.client_id as c, (m.enviar_em at time zone 'America/Sao_Paulo')::date as dia
      from public.agenda_cliente_mensagens m
     where m.modo = 'ligado' and m.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')
  )
  select (select count(*) from (select e.c, e.dia from ent e group by 1, 2 having count(*) > cf.cliente_dia_max) a)
       + (select count(*) from (select e.c, date_trunc('week', e.dia) from ent e group by 1, 2
                                 having count(*) > cf.cliente_semana_max) b)
       + (select count(*) from (select e.dia from ent e group by 1 having count(*) > cf.cliente_total_dia_max) t)
    into v_cteto;
  -- o intervalo: duas linhas agenda-cliente (na fila, saindo ou saídas) a menos de cliente_intervalo_min_s uma da outra
  select count(*) into v_cint
    from public.whatsapp_send_queue a
    join public.whatsapp_send_queue b
      on b.source = 'agenda-cliente' and b.id > a.id and b.status in ('pending', 'sending', 'sent')
     and abs(extract(epoch from coalesce(b.sent_at, b.scheduled_for) - coalesce(a.sent_at, a.scheduled_for)))
         < cf.cliente_intervalo_min_s
   where a.source = 'agenda-cliente' and a.status in ('pending', 'sending', 'sent');
  select count(*) into v_cproib
    from public.agenda_cliente_mensagens m where public._agenda_cliente_texto_proibido(m.texto) is not null;
  -- em teste nada entra na fila (nem linha da fila sem a mensagem registrada em ligado)
  select (select count(*) from public.whatsapp_send_queue q
            left join public.agenda_cliente_mensagens x on x.id = q.source_ref_id
           where q.source = 'agenda-cliente' and (x.id is null or x.modo <> 'ligado'))
       + (select count(*) from public.agenda_cliente_mensagens x
           where x.modo <> 'ligado' and (x.fila_id is not null or x.enviada_em is not null
                                         or x.estado in ('enfileirada', 'enviada', 'respondida', 'sem_resposta')))
    into v_csombra;
  -- enviada sem a aprovação do dono quando o tipo ainda não somava os dias aprovados (ou a preparada pelo dono)
  select count(*) into v_csemap
    from public.agenda_cliente_mensagens m
   where m.modo = 'ligado' and m.enviada_em is not null and m.aprovacao <> 'aprovada'
     and (m.origem <> 'rodada'
          or (cf.cliente_aprovacao_dias > 0
              and (select count(distinct (y.aprovada_em at time zone 'America/Sao_Paulo')::date)
                     from public.agenda_cliente_mensagens y
                    where y.tipo = m.tipo and y.aprovacao = 'aprovada' and y.origem = 'rodada' and y.modo = 'ligado'
                      and y.aprovada_em < m.criada_em) < cf.cliente_aprovacao_dias));
  -- a crítica enviada sem a decisão "2) eu mando o aviso escrito"
  select count(*) into v_ccrit
    from public.agenda_cliente_mensagens m
    left join public.agenda_perguntas q on q.id = m.pergunta_id
   where m.enviada_em is not null
     and (m.aprovacao = 'critica'
          or (q.tipo = 'cliente_aviso' and not (q.estado = 'respondida' and q.opcao_escolhida = 2)));
  -- a véspera (M2/M4) enviada com a OS aguardando peça (no registro, ou pela última mudança de status antes do envio)
  select count(*) into v_cvesp
    from public.agenda_cliente_mensagens m
   where m.tipo in ('vespera', 'acesso') and m.enviada_em is not null
     and (m.base ->> 'status' = 'awaiting_parts'
          or (select a.status_depois from public.agenda_acoes a
               where a.service_order_id = m.service_order_id and a.tipo = 'status' and a.executada
                 and a.criada_em <= m.enviada_em
               order by a.criada_em desc, a.id desc limit 1) = 'awaiting_parts');
  -- o aviso de atraso enviado depois da data que o cliente ouviu
  select count(*) into v_cdepois
    from public.agenda_cliente_mensagens m
   where m.tipo = 'pode_atrasar' and m.enviada_em is not null and m.base ? 'prometido_ate'
     and (m.enviada_em at time zone 'America/Sao_Paulo')::date > (m.base ->> 'prometido_ate')::date;
  select count(*) into v_caudio
    from public.agenda_cliente_respostas r where r.tipo_msg = 'audio' and r.efeito = 'confirmou';
  -- as métricas (para depois; nenhuma reprova)
  select jsonb_build_object(
    'm6_antes_da_data_pct_90d', (
      select case when count(*) > 0 then round(100 * (count(*) filter (
               where (m.enviada_em at time zone 'America/Sao_Paulo')::date <= (m.base ->> 'prometido_ate')::date))::numeric
               / count(*)) end
        from public.agenda_cliente_mensagens m
       where m.tipo = 'pode_atrasar' and m.enviada_em > p_agora - interval '90 days' and m.base ? 'prometido_ate'),
    'aprovadas_sem_segurar_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where m.aprovacao = 'aprovada'))::numeric / count(*)) end
        from public.agenda_cliente_mensagens m
       where m.modo = 'ligado' and m.aprovacao in ('aprovada', 'segurada') and m.aprovada_em > p_agora - interval '30 days'),
    'resposta_24h_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where r.recebida_em <= m.enviada_em + interval '1 day'))::numeric
               / count(*)) end
        from public.agenda_cliente_mensagens m
        left join public.agenda_cliente_respostas r on r.id = m.resposta_id
       where m.modo = 'ligado' and m.enviada_em > p_agora - interval '30 days'
         and m.tipo in ('confirmar', 'vespera', 'acesso', 'material_chegou', 'nova_data', 'mudanca_no_dia')),
    'sim_automatico_pct', (
      select case when count(*) > 0 then round(100 * (count(*) filter (where r.efeito = 'confirmou'))::numeric / count(*)) end
        from public.agenda_cliente_respostas r
       where r.modo = 'ligado' and r.recebida_em > p_agora - interval '30 days' and r.intencao = 'confirma'),
    'opt_outs_30d', (select count(*) from public.agenda_cliente_respostas r
                      where r.intencao = 'opt_out' and r.recebida_em > p_agora - interval '30 days'),
    'falhas_de_entrega_30d', (select count(*) from public.whatsapp_send_queue q
                               where q.source = 'agenda-cliente' and q.status = 'failed'
                                 and q.created_at > p_agora - interval '30 days'),
    'idas_perdidas_por_acesso_90d', (
      select jsonb_build_object('com_aviso', count(*) filter (where t.avisado), 'sem_aviso', count(*) filter (where not t.avisado))
        from (select distinct a.service_order_id, a.dia,
                     exists (select 1 from public.agenda_cliente_mensagens m
                              where m.service_order_id = a.service_order_id and m.tipo in ('vespera', 'acesso')
                                and m.enviada_em is not null and coalesce((m.base ->> 'dia_alvo')::date, m.dia_alvo) = a.dia) as avisado
                from public.agenda_alocacoes a
               where a.resultado = 'nao_cumprido' and a.motivo = 'cliente_ou_bem' and a.dia > p_hoje - 90 and a.dia <= p_hoje) t))
    into v_cmet;
  v_zeros5 := v_cjan = 0 and v_cdom = 0 and v_cteto = 0 and v_cint = 0 and v_cproib = 0 and v_csombra = 0 and v_csemap = 0
              and v_ccrit = 0 and v_cvesp = 0 and v_cdepois = 0 and v_caudio = 0;
  v_zeros4 := v_zeros4 and v_zeros5;
  v_cli := jsonb_build_object(
    'modo', cf.modo_cliente, 'tipos_ligados', to_jsonb(cf.cliente_tipos_ligados),
    'tipos_liberados', to_jsonb(array(select t from unnest(array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento',
                                                                  'pode_atrasar', 'nova_data', 'pronto', 'pronto_lembrete',
                                                                  'pos_servico', 'mudanca_no_dia']) t
                                       where public._agenda_cliente_tipo_liberado(t))),
    'ultima_rodada', v_crod -> 'ultima_rodada', 'rodou_nas_ultimas_2h', v_crod -> 'rodou_nas_ultimas_2h',
    'erros_24h', v_crod -> 'erros_24h',
    'mensagens_7d', jsonb_build_object('por_tipo', v_cmsg),
    'aprovacao', v_caprov,
    'fora_da_janela', v_cjan, 'em_feriado_ou_domingo', v_cdom, 'acima_do_teto', v_cteto, 'intervalo_curto', v_cint,
    'com_texto_proibido', v_cproib, 'na_fila_em_sombra', v_csombra, 'sem_aprovacao_no_periodo', v_csemap,
    'critica_sem_decisao', v_ccrit, 'vespera_com_os_aguardando_peca', v_cvesp, 'aviso_depois_da_data', v_cdepois,
    'audio_que_confirmou', v_caudio,
    'metricas', v_cmet);
  -- FASE 5: fim
  return jsonb_build_object(
    -- FASE 3: os zeros obrigatórios da execução entram no ok.
    'ok', v_sem = 0 and (v_regra ->> 'n')::int = 0 and v_choques = 0
          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0
          -- FASE 4: os zeros obrigatórios do material e da mensagem ao fornecedor entram no ok.
          and v_zeros4,
          -- FASE 4: fim
    'modos', jsonb_build_object('leitura', cf.modo_leitura, 'proposta', cf.modo_proposta, 'vigia', cf.modo_vigia),
    'vigia', v_vig, 'hoje', v_hoje, 'criticas', v_crit, 'perguntas', v_perg, 'propostas', v_prop, 'plano', v_plano,
    'invariantes', v_inv, 'fechamento', v_fech,
    -- FASE 3
    'rotina', v_rot, 'equipe', v_eq, 'diarias', v_dia, 'conclusao', v_conc, 'marcos', v_marcos, 'comissao', v_com,
    'modos_fase3', jsonb_build_object('equipe', cf.modo_equipe, 'diaria', cf.modo_diaria),
    -- FASE 5: a mensagem ao cliente
    'cliente', v_cli,
    -- FASE 5: fim
    -- FASE 4: o material
    'material', v_mat);
    -- FASE 4: fim
end;
$function$;

comment on function public.agenda_saude(date, timestamptz) is
  'Agenda de Produção (Fase 2, P3): a conferência depois de cada deploy e o painel da sombra — {ok, modos, vigia (última rodada, rodou nas últimas 2 h, erros em 24 h no app_error_logs context agenda, rodadas em 24 h), hoje (publicar, criar, mover, cancelar, promover, soltar, status, resultado, desfeitas, sombra), criticas (abertas, respondidas em 7 dias, sem_decisao e pela_regra_sem_decisao — têm de ser 0), perguntas (abertas por tipo, mostradas hoje), propostas, plano (vigentes futuras, OS programadas, reservas, sem registro em 7 dias), invariantes (vigente de OS fora da carteira, espelho divergente em ligado, choques = 0), fechamento (leu o plano hoje: resumo_tarde.detalhe.agenda; linhas mostradas)}. Leitura (invoker): authenticated (a RLS do admin vale) e service_role. Fase 3: a vigia lê só as rodadas dela (rotina = vigia); blocos rotina (última rodada, rodou nas últimas 2 h, erros 24 h), equipe (mensagens e recusas de hoje; acima_do_teto e fora_da_janela — também o que saiu fora dela — têm de ser 0), diarias (lançadas e em teste em 7 dias, perguntas abertas; sem_confirmacao e sobrescreveu_turno têm de ser 0), conclusao (pela agenda e desfeitas em 7 dias; sem_recebivel_quando_devia = 0, só para quem lê a releitura), marcos (N4), comissao (pagamento desligado; payables de comissão de técnico em 7 dias = 0) e modos_fase3; o ok inclui esses zeros. Fase 4 (P5): o bloco material — modos (material, detector, fornecedor), a rodada do material (rotina = material: última, rodou nas últimas 2 h, erros 24 h em material:%), remessas (a caminho, sem resposta, ligadas/sem serviço/chegaram em 7 dias), perguntas (as abertas da Fase 4 por tipo; pix_na_semana), detector (agenda_detector_precisao dos últimos 14 dias — só para administrador/financeiro ou sem login —, aplicados e desfeitos em 7 dias), fornecedor (registradas, enfileiradas, em teste e recusadas por motivo em 7 dias), cobertura (itens críticos das OS que começam nas próximas material_inicio_dias e quantos têm data, nível A–D), espera (mediana da aprovação à 1ª compra, OS aprovadas em 90 dias); os zeros obrigatórios entram no ok: vinculo_sem_resposta_do_dono, previsao_sem_original e, do fornecedor, na_fila_em_sombra, fora_da_janela, acima_do_teto e com_valor_ou_cliente. Fase 5 (P3): o bloco cliente — modo, tipos_ligados, tipos_liberados (somaram cliente_aprovacao_dias dias aprovados), a rodada do cliente (rotina = cliente: última, rodou nas últimas 2 h, erros 24 h em cliente:%), mensagens_7d por tipo (registradas, aguardando, enviadas, recusadas por motivo), aprovacao (pedidas abertas, vencidas, aprovadas e seguradas em 7 dias) e as métricas (M6 antes da data, aprovadas sem segurar, resposta em 1 dia, SIM automático, opt-outs, falhas de entrega, idas perdidas por acesso com e sem véspera); os zeros obrigatórios entram no ok: fora_da_janela, em_feriado_ou_domingo, acima_do_teto, intervalo_curto, com_texto_proibido, na_fila_em_sombra, sem_aprovacao_no_periodo, critica_sem_decisao, vespera_com_os_aguardando_peca, aviso_depois_da_data e audio_que_confirmou.';

-- ── 8. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- A rodada do cliente: só service_role (o task-automations). Nunca anon, nunca authenticated.
revoke all on function public.agenda_cliente_vigiar(date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_cliente_vigiar(date, timestamptz) to service_role;

-- Os passos, a decisão e as auxiliares que escrevem: ninguém de fora (nem o service_role). Só a rodada (security definer)
-- e agenda_decidir os chamam: o ÚNICO caminho até a fila agenda-cliente continua sendo a agenda.
revoke all on function
  public._agenda_cliente_material(date, timestamptz), public._agenda_cliente_confirmar(date, timestamptz),
  public._agenda_cliente_atraso(date, timestamptz), public._agenda_cliente_mudanca_no_dia(date, timestamptz),
  public._agenda_cliente_andamento(date, timestamptz), public._agenda_cliente_pronto(date, timestamptz),
  public._agenda_cliente_pos_servico(date, timestamptz), public._agenda_cliente_sem_resposta(date, timestamptz),
  public._agenda_cliente_decidir(uuid, smallint, uuid, text, text, timestamptz),
  public._agenda_cliente_cancelar(uuid, text, text), public._agenda_cliente_acorde(uuid, text, text, date, date, uuid)
  from public, anon, authenticated, service_role;

-- As leituras (STABLE, invoker): authenticated (o foco e a tela do P5/P6, com a RLS de quem lê) e service_role; nunca anon.
revoke all on function
  public._agenda_cliente_toque(date), public._agenda_cliente_proximo_toque(timestamptz),
  public._agenda_cliente_dia_seguinte(date), public._agenda_cliente_vespera(date), public._agenda_cliente_ultimo_fim(date),
  public._agenda_cliente_ja_registra(date, date, timestamptz), public._agenda_cliente_risco(uuid, date),
  public._agenda_cliente_ouviu(uuid, date, timestamptz)
  from public, anon;
grant execute on function
  public._agenda_cliente_toque(date), public._agenda_cliente_proximo_toque(timestamptz),
  public._agenda_cliente_dia_seguinte(date), public._agenda_cliente_vespera(date), public._agenda_cliente_ultimo_fim(date),
  public._agenda_cliente_ja_registra(date, date, timestamptz), public._agenda_cliente_risco(uuid, date),
  public._agenda_cliente_ouviu(uuid, date, timestamptz)
  to authenticated, service_role;

-- As recriadas mantêm as portas delas (create or replace não muda a ACL; repetidas aqui para a migration se bastar):
revoke all on function public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz) to service_role;
revoke all on function public.agenda_saude(date, timestamptz) from public, anon;
grant execute on function public.agenda_saude(date, timestamptz) to authenticated, service_role;
