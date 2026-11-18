-- Agenda: ficha paga, parte B (18/11/2026) — sobre a 20270125100000 (F2, aplicada em 18/11 09:40)
-- Plano: D:/IA-HBR/agenda-pesquisa/via-os129-1711/plano/F2b/RESUMO.md. Respostas do dono:
--   (cartão da F2, 18/11 ~06:00) "já começou" = "Só antes de começar": a ficha de OS paga fica segurada só se a OS ainda não começou;
--     "concluída" = "Nunca mandar": OS concluída ou faturada com dia ainda marcado na agenda: a ficha nunca sai, e o dono é avisado;
--     "mande antes da baixa" = "Continua valendo" (como está).
--   (cartão da revisão da F2b, 18/11 11:45) P1: o check-in sozinho NÃO prova que começou — só prova de trabalho do técnico; P2: "o que tem
--     pra amanhã?" com a ficha segurada responde "Vou ver com <dono> e te falo." e pergunta ao dono; P3: a OS cancelada entra no "nunca";
--     P4: o check-in da reabertura não conta (coberta pela P1).
--
-- O que muda:
--   1. _agenda_os_comecou(os, dia), nova: há PROVA DE TRABALHO do técnico na OS antes do dia? Um dia da OS antes com resultado cumprido ou
--      parcial (o "como foi", o dono, a diária lançada); a confirmação da manhã de um dia antes respondida "sim" sem divergência, de quem
--      estava na OS num turno que confirmou; diária aprovada ou paga na OS; horas apontadas; passo da execução iniciado. NUNCA contam: o dia
--      só PLANEJADO, o "sem registro" da vigia, o check-in e o "em andamento" (a porta os grava também na reabertura da OS).
--   2. _agenda_ficha_os_pagas (da F2): só a OS paga por inteiro E que ainda não começou. Ela é lida pela liberada, pela pergunta e pela
--      ficha das 19:30: a OS paga que já começou volta à regra de antes (a ficha sai; dentro da janela, a pergunta de sempre).
--   3. _agenda_ficha_os_concluidas(pessoa, dia), nova: as OS concluídas, faturadas ou canceladas entre as alocações vigentes da pessoa no
--      dia — de QUALQUER alocação (não só a da estimativa): OS encerrada não tem serviço a fazer, seja qual for a origem do dia.
--      _agenda_ficha_os_concluidas_texto(os[]), nova: "concluída", "faturada", "cancelada" (ou os que houver, por " ou "; plural).
--   4. _agenda_ficha_liberada: a pessoa (não o dono) com OS concluída, faturada ou cancelada no dia nunca tem a ficha (nem a confirmação da
--      manhã, nem a ficha que iria no "como foi"), com ou sem o *mande*.
--   5. _agenda_gestor_fichas: a pergunta da OS paga diz "já está PAGA e ainda não começou: o serviço ainda vai ser feito?"; quem tem OS
--      encerrada no dia não ganha pergunta (a ficha não sairia de todo jeito); a OS paga e já começada não abre o passo fora da janela.
--   6. _agenda_rotina_ficha: a ficha presa por OS encerrada diz "Não mandei a ficha de qui 05/11 a Roberto (OS-00074 Lenine): a OS já está
--      concluída. Fale com Roberto." ("faturada", "cancelada"; por = concluida); a pergunta aberta fecha com o motivo dela. No dia misto, o
--      parêntese do aviso (encerrada ou paga) cita TODAS as OS do dia, e o porquê nomeia a OS ("a OS-00074 já está paga por inteiro e …").
--   7. _agenda_saude_comunicacao (C4 da revisão da F2): a curta da ficha paga ("… eu seguro a ficha. Para mandar, me diga *mande*.")
--      conta como a do gestor no bloco_grande, como a "Para segurar, me diga.".
--   8. agenda_resposta_da_equipe (P2): "o que tem pra amanhã?" com a mensagem à equipe ligada e a ficha desse dia segurada
--      (_agenda_ficha_liberada falso) responde "Vou ver com Gustavo e te falo." (o nome curto do dono) e abre a pergunta equipe_resposta ao
--      dono, com quem perguntou e por que a ficha está segurada.
--   9. _agenda_gestor_decidir (correção da revisão): o *mande* da ficha de quem tem OS encerrada no dia responde "A OS-00074 já está
--      concluída: a ficha não sai." (antes: "Combinado: mando a ficha", e a ficha não saía).
-- Toda mudança nas recriadas é ACRÉSCIMO, em blocos "-- FICHA PAGA B: (…) … -- FICHA PAGA B: fim": tirados os blocos B, cada uma é a de
-- produção (a da F2, a saúde, a resposta da equipe, o decidir), byte a byte (conferir-acrescimo-b.mjs). Os testes de cópia tiram os blocos
-- "-- FICHA PAGA:" e "-- FICHA PAGA B:"; o bloco B da saúde fica dentro do bloco "-- PRAZO NO BLOCO:", que eles já tiram.
--
-- DESFAZER: D:/IA-HBR/agenda-pesquisa/via-os129-1711/plano/F2b/desfazer.sql (as definições da F2 e as de produção).

-- ── 1. A OS que já começou, as OS concluídas, faturadas ou canceladas da pessoa no dia, e o nome do estado delas ──────────
create or replace function public._agenda_os_comecou(p_os uuid, p_dia date)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  -- Só PROVA DE TRABALHO do técnico antes do dia conta (respostas do dono de 18/11, P1 e P4). O dia só planejado na agenda (vigente,
  -- passado ou não, sem resultado), o "sem registro" que a vigia marca no dia que passou, o check-in e o "em andamento" (a porta os
  -- grava ao abrir e ao REABRIR a OS, sem data de serviço) NUNCA contam: o plano errado de um serviço já feito gera esses dias (o caso
  -- OS-00129), e a reabertura grava check-in (OS-00104 e OS-00134, 16/11).
  select coalesce((
    select -- (1) um dia da OS antes deste com o serviço feito, no todo ou em parte: o "como foi" respondido, o dono (conversa, tela,
           --     dia feito) ou a diária lançada que marca o dia
           exists (select 1 from public.agenda_alocacoes a
                    where a.service_order_id = so.id and a.estado in ('publicada', 'fixada') and a.dia < p_dia
                      and a.resultado in ('cumprido', 'parcial'))
           -- (2) a confirmação da manhã de um dia antes deste respondida "sim" SEM divergência (como _agenda_resposta_da_equipe a lê: ok ou
           --     presença; turnos com ok iguais aos do plano, ou "meio" com um turno só no plano), de quem tinha, nesse dia, alocação vigente
           --     NESSA OS num turno que confirmou (os turnos ditos; sem eles, ou com "meio", os do plano)
           or exists (select 1 from public.agenda_equipe_mensagens m
                       cross join lateral (
                         select array(select distinct b.turno from public.agenda_alocacoes b
                                       where b.payee_id = m.payee_id and b.dia = m.dia and b.estado in ('publicada', 'fixada')
                                         and b.tipo <> 'reserva' order by 1) as plano,
                                case when jsonb_typeof(m.leitura -> 'turnos') = 'array'
                                     then array(select x from jsonb_array_elements_text(m.leitura -> 'turnos') x order by 1) end as ditos) t
                       where m.tipo = 'confirmar' and m.modo = 'ligado' and m.estado = 'respondida' and m.dia < p_dia
                         and (m.leitura ->> 'tipo' in ('ok', 'presenca')
                              or (m.leitura ->> 'tipo' = 'turnos' and coalesce((m.leitura ->> 'ok')::boolean, false)
                                  and (t.ditos is null or t.ditos = t.plano or (t.ditos = array['meio'] and cardinality(t.plano) = 1))))
                         and exists (select 1 from public.agenda_alocacoes a
                                      where a.payee_id = m.payee_id and a.dia = m.dia and a.service_order_id = so.id
                                        and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                                        and a.turno = any (case when t.ditos is null or t.ditos = array['meio'] then t.plano else t.ditos end)))
           -- (3) a diária lançada (trabalho normal ou diária, aprovada ou paga, não zero; falta, folga, atestado e feriado não) nessa
           --     OS num dia antes deste
           or exists (select 1 from public.work_shifts ws
                       where ws.data < p_dia and ws.status in ('aprovado', 'pago') and ws.tipo in ('normal', 'diaria')
                         and coalesce(ws.fracao, 1) > 0
                         and (ws.service_order_id = so.id
                              or exists (select 1 from public.work_shift_os wo where wo.shift_id = ws.id and wo.service_order_id = so.id)))
           -- (4) horas apontadas na OS antes deste dia
           or exists (select 1 from public.time_entries t
                       where t.service_order_id = so.id and (t.started_at at time zone 'America/Sao_Paulo')::date < p_dia)
           -- (5) um passo da execução da OS iniciado antes deste dia
           or exists (select 1 from public.service_order_steps s
                       where s.service_order_id = so.id and (s.started_at at time zone 'America/Sao_Paulo')::date < p_dia)
      from public.service_orders so
     where so.id = p_os), false);
$function$;

comment on function public._agenda_os_comecou(uuid, date) is
  'Agenda de Produção (ficha paga B, 18/11/2026, 20270126100000; respostas do dono "Só antes de começar" e, às 11:45, P1 e P4): há PROVA DE TRABALHO do técnico na OS antes de p_dia? (1) um dia da OS antes do dia com resultado cumprido ou parcial (o "como foi", o dono, a diária lançada); (2) a confirmação da manhã de um dia antes respondida "sim" sem divergência (ok, presença; turnos com ok iguais aos do plano, ou "meio" com um turno só) por quem tinha alocação vigente nessa OS num turno que confirmou; (3) trabalho normal ou diária aprovada ou paga, não zero, nessa OS (work_shifts.service_order_id ou work_shift_os) num dia antes; (4) horas apontadas (time_entries) antes do dia; (5) passo da execução iniciado (service_order_steps) antes do dia. NUNCA contam: o dia só planejado na agenda, o sem_registro da vigia, o check-in e o "em andamento" (gravados também na reabertura da OS). Sem a OS = false. STABLE, invoker (lê com a RLS de quem pergunta); authenticated e service_role.';

create or replace function public._agenda_ficha_os_concluidas(p_payee uuid, p_dia date)
 returns uuid[]
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(array_agg(x.os order by x.ini, x.os), '{}'::uuid[])
    from (select a.service_order_id as os, min(lower(a.periodo)) as ini
            from public.agenda_alocacoes a
            join public.service_orders so on so.id = a.service_order_id
           where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
             and so.status in ('completed', 'invoiced', 'cancelled')
           group by a.service_order_id) x;
$function$;

comment on function public._agenda_ficha_os_concluidas(uuid, date) is
  'Agenda de Produção (ficha paga B, 18/11/2026, 20270126100000; respostas do dono "Nunca mandar" e, às 11:45, P3): as OS concluídas, faturadas ou canceladas entre as alocações vigentes da pessoa no dia (publicada ou fixada, sem reserva), de QUALQUER origem do dia (não só a estimativa: OS encerrada não tem serviço a fazer), na ordem do dia. Nenhuma = {}. STABLE, invoker; authenticated e service_role.';

create or replace function public._agenda_ficha_os_concluidas_texto(p_os uuid[])
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select case when cardinality(p_os) > 1 then replace(replace(replace(x.t, 'concluída', 'concluídas'), 'faturada', 'faturadas'), 'cancelada', 'canceladas')
              else x.t end
    from (select string_agg(e.palavra, ' ou ' order by e.ordem) as t
            from (values ('completed', 'concluída', 1), ('invoiced', 'faturada', 2), ('cancelled', 'cancelada', 3)) e(status, palavra, ordem)
           where exists (select 1 from public.service_orders so where so.id = any (p_os) and so.status = e.status)) x;
$function$;

comment on function public._agenda_ficha_os_concluidas_texto(uuid[]) is
  'Agenda de Produção (ficha paga B, 18/11/2026, 20270126100000): o estado das OS encerradas, para o porquê da ficha que não sai — "concluída", "faturada", "cancelada" ou os que houver juntos por " ou " (nessa ordem), no plural com mais de uma OS ("concluídas ou canceladas"). Nenhuma OS encerrada = null. STABLE, invoker; authenticated e service_role.';

-- ── 2. As OS pagas da pessoa no dia: só a que ainda não começou ─────────────────────────────────────────
-- _agenda_ficha_os_pagas (de 20270125100000 (F2); md5 do corpo de antes 9b51d37226c72ec40dca7758460e6995 sem CR)
create or replace function public._agenda_ficha_os_pagas(p_payee uuid, p_dia date)
 returns uuid[]
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(array_agg(x.os order by x.ini, x.os), '{}'::uuid[])
    from (select a.service_order_id as os, min(lower(a.periodo)) as ini
            from public.agenda_alocacoes a
           where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
             and a.duracao_fonte = 'orcamento'
           group by a.service_order_id) x
   -- FICHA PAGA B: (18/11/2026) só a OS paga que ainda não começou (resposta "Só antes de começar"; _agenda_os_comecou): depois de
   -- começar, pago é adiantamento e a ficha sai
   join lateral (select not public._agenda_os_comecou(x.os, p_dia) as nao_comecou) nc on nc.nao_comecou
   -- FICHA PAGA B: fim
   where public._agenda_os_paga_por_inteiro(x.os);
$function$;

comment on function public._agenda_ficha_os_pagas(uuid, date) is
  'Agenda de Produção (ficha paga, 18/11/2026, 20270125100000): as OS pagas por inteiro (_agenda_os_paga_por_inteiro) entre as da alocação vigente da pessoa no dia pela estimativa (publicada ou fixada, sem reserva, duracao_fonte orcamento — a da proteção da ficha), na ordem do dia. Nenhuma = {}. STABLE, invoker; authenticated e service_role. FICHA PAGA B (18/11/2026, 20270126100000; resposta do dono "Só antes de começar"): só a OS paga por inteiro que ainda não começou (_agenda_os_comecou(os, p_dia)): depois de começar, pago é adiantamento e a ficha sai.';

-- ── 3. A ficha liberada ─────────────────────────────────────────────────────────────────────────────────
-- _agenda_ficha_liberada (de 20270125100000 (F2); md5 do corpo de antes 46b2eaa697100267c9c66888738dc2fd sem CR)
create or replace function public._agenda_ficha_liberada(p_payee uuid, p_dia date, p_agora timestamptz)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_payee is null or p_dia is null or p_agora is null then true
    -- FICHA PAGA B: (18/11/2026) a pessoa (não o dono) com OS concluída, faturada ou cancelada no dia (qualquer alocação vigente,
    -- _agenda_ficha_os_concluidas) nunca tem a ficha, nem com o *mande* do dono (respostas "Nunca mandar" e P3)
    when p_payee is distinct from public._agenda_dono(null)
         and cardinality(public._agenda_ficha_os_concluidas(p_payee, p_dia)) > 0 then false
    -- FICHA PAGA B: fim
    -- FICHA PAGA: (18/11/2026) a pessoa (não o dono) com OS paga por inteiro no dia, pela estimativa, só tem a ficha com o *mande* do
    -- DONO de verdade: a pergunta respondida com a 1 por um canal dele (nunca o prazo). O silêncio nunca solta. Dentro e fora da
    -- janela de veto, com ou sem o ligar do gestor.
    when p_payee is distinct from public._agenda_dono(null)
         and cardinality(public._agenda_ficha_os_pagas(p_payee, p_dia)) > 0 then
      exists (select 1 from public.agenda_perguntas q
               where q.chave = format('ficha_estimativa:%s:%s', p_payee, p_dia) and q.modo = 'ligado'
                 and q.estado = 'respondida' and q.opcao_escolhida = 1 and q.respondida_via is distinct from 'prazo'
                 and q.respondida_em <= p_agora)
    -- FICHA PAGA: fim
    when cf.marcar_sozinho_desde is null then true
    when p_dia < (cf.marcar_sozinho_desde at time zone 'America/Sao_Paulo')::date
      or p_dia >= (cf.marcar_sozinho_desde at time zone 'America/Sao_Paulo')::date + cf.ficha_veto_dias then true
    when p_payee is not distinct from public._agenda_dono(null) then true
    when not exists (select 1 from public.agenda_alocacoes a
                      where a.payee_id = p_payee and a.dia = p_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                        and a.duracao_fonte = 'orcamento') then true
    else exists (select 1 from public.agenda_perguntas q
                  where q.chave = format('ficha_estimativa:%s:%s', p_payee, p_dia) and q.modo = 'ligado'
                    and q.mostrada_vezes > 0 and q.mostrada_em <= p_agora and q.opcao_escolhida is distinct from 2)
  end
    from public.agenda_config cf
   where cf.id;
$function$;

comment on function public._agenda_ficha_liberada(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7a, P11; AG7-15): a ficha (e a confirmação da manhã) da pessoa no dia pode sair? true fora da janela de veto (marcar_sozinho_desde nulo, ou p_dia fora de [o dia do ligar, + ficha_veto_dias)), para o dono e para o dia sem alocação vigente da pessoa com duracao_fonte orcamento; senão só com a pergunta ficha_estimativa:<pessoa>:<dia> de verdade (modo ligado) mostrada ao dono até p_agora e não segurada (opcao_escolhida distinta de 2). Lida por _agenda_rotina_ficha, _agenda_rotina_como_foi e _agenda_rotina_confirmar (recriadas pelo P11). STABLE, invoker; authenticated e service_role. FICHA PAGA (18/11/2026, 20270125100000; o caso OS-00129): a pessoa (não o dono) com OS paga por inteiro no dia pela estimativa (_agenda_ficha_os_pagas) só tem a ficha, a confirmação da manhã e a ficha do "como foi" com o *mande* do dono de verdade — a pergunta ficha_estimativa:<pessoa>:<dia> de verdade respondida com a 1 por um canal do dono (respondida_via distinta de prazo) até p_agora; o silêncio nunca solta; vale dentro e fora da janela e sem o ligar do gestor. Sem OS paga, o de antes. FICHA PAGA B (18/11/2026, 20270126100000; respostas do dono "Nunca mandar" e P3): a pessoa (não o dono) com OS concluída, faturada ou cancelada no dia, em qualquer alocação vigente (_agenda_ficha_os_concluidas), nunca tem a ficha, a confirmação da manhã nem a ficha do "como foi", com ou sem o *mande*. A OS paga só segura antes de começar (_agenda_ficha_os_pagas).';

-- ── 4. A pergunta da ficha ──────────────────────────────────────────────────────────────────────────────
-- _agenda_gestor_fichas (de 20270125100000 (F2); md5 do corpo de antes 61b60204be07e8d91a93df3f3485731c sem CR)
create or replace function public._agenda_gestor_fichas(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config;
  v_modo  text;
  v_desde date;
  v_d     date;
  v_ate   timestamptz;
  v_hora  text;
  v_quando text;
  v_dono  uuid := public._agenda_dono(null);
  p       record;
  v_os    uuid;
  v_partes text[];
  v_txt   text;
  v_id    uuid;
  v_novas int := 0;
  v_lista jsonb := '[]'::jsonb;
  v_ops   jsonb;
  -- FICHA PAGA: (18/11/2026) a OS paga por inteiro
  v_janela boolean;
  v_pagas  boolean;
  v_fp_os  uuid[];
  v_fp_rot text;
  v_fp_q   public.agenda_perguntas%rowtype;
  -- FICHA PAGA: fim
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_fichas: sem o dia ou a hora' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_modo := coalesce(public._agenda_modo_da_pergunta('ficha_estimativa', null), 'desligado');
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'as mensagens à equipe estão desligadas');
  end if;
  -- FICHA PAGA: (18/11/2026) a ficha de OS paga por inteiro pergunta dentro e fora da janela e sem o ligar do gestor: alguém (não o
  -- dono) com OS paga no próximo dia útil, pela estimativa. Sem ninguém assim, os pulos de antes.
  v_d := public.agenda_somar_du(p_hoje, 1);
  v_pagas := exists (select 1 from public.agenda_alocacoes a
                      where a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.duracao_fonte = 'orcamento'
                        and a.payee_id is distinct from v_dono and public._agenda_os_paga_por_inteiro(a.service_order_id));
  -- FICHA PAGA B: (18/11/2026) só a OS paga que ainda não começou abre o passo fora da janela
  v_pagas := v_pagas and exists (select 1 from public.agenda_alocacoes a
                                  where a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.duracao_fonte = 'orcamento'
                                    and a.payee_id is distinct from v_dono
                                    and cardinality(public._agenda_ficha_os_pagas(a.payee_id, v_d)) > 0);
  -- FICHA PAGA B: fim
  if not v_pagas then
  -- FICHA PAGA: fim
  if cf.marcar_sozinho_desde is null then
    return jsonb_build_object('pulado', true, 'motivo', 'o gestor ainda não marca sozinho: sem janela da ficha');
  end if;
  -- FICHA PAGA: (fecha o "se ninguém tem OS paga")
  end if;
  -- FICHA PAGA: fim
  if not public.agenda_dia_util(p_hoje) then
    return jsonb_build_object('pulado', true, 'motivo', 'não é dia útil');
  end if;
  v_desde := (cf.marcar_sozinho_desde at time zone 'America/Sao_Paulo')::date;
  v_d := public.agenda_somar_du(p_hoje, 1);
  -- FICHA PAGA: (18/11/2026) a janela; fora dela (e sem o ligar do gestor), só a OS paga
  v_janela := v_desde is not null and v_d >= v_desde and v_d < v_desde + cf.ficha_veto_dias;
  if not v_pagas then
  -- FICHA PAGA: fim
  if v_d < v_desde or v_d >= v_desde + cf.ficha_veto_dias then
    return jsonb_build_object('pulado', true, 'motivo', 'fora da janela da ficha', 'dia', v_d);
  end if;
  -- FICHA PAGA: (fecha o "se ninguém tem OS paga")
  end if;
  -- FICHA PAGA: fim
  v_ate := (p_hoje + cf.equipe_hora_ficha) at time zone 'America/Sao_Paulo';
  if p_agora >= v_ate then
    return jsonb_build_object('pulado', true, 'motivo', 'já passou a hora da ficha', 'dia', v_d);
  end if;
  v_hora := to_char(cf.equipe_hora_ficha, 'HH24:MI');
  v_quando := case when v_d = p_hoje + 1 then 'amanhã'
                   else (array['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'])[extract(isodow from v_d)::int] end;
  v_ops := jsonb_build_array(
    jsonb_build_object('n', 1, 'texto', 'Mande', 'efeito', jsonb_build_object('mandar', true)),
    jsonb_build_object('n', 2, 'texto', 'Segure a ficha: eu não mando e você fala com ele', 'efeito', jsonb_build_object('segurar', true)));

  for p in
    select c.payee_id, public._agenda_nome_curto(py.name) as nome
      from public._agenda_contatos_com_plano(v_d) c(payee_id)
      join public.payees py on py.id = c.payee_id
     where c.payee_id is distinct from v_dono
       and exists (select 1 from public.agenda_alocacoes a
                    where a.payee_id = c.payee_id and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      and a.duracao_fonte = 'orcamento')
       -- FASE 7: (7a correção 2, a ficha prometida a quem não tem telefone) só quem tem para onde a ficha ir: sem telefone ela não sai
       -- de jeito nenhum, e a pergunta prometia "Hoje às 19:30 a ficha de amanhã vai para Alex" (e às 19:30 a fechava "ela foi como
       -- eu disse"). A ficha de quem não tem telefone fica segurada e diz o porquê (_agenda_rotina_ficha): o dono avisa de boca.
       and public._agenda_equipe_tem_telefone(c.payee_id)
       -- FASE 7: fim
       -- FICHA PAGA: (18/11/2026) fora da janela, só quem tem OS paga no dia
       and (v_janela or cardinality(public._agenda_ficha_os_pagas(c.payee_id, v_d)) > 0)
       -- FICHA PAGA: fim
       -- FICHA PAGA B: (18/11/2026) quem tem OS concluída, faturada ou cancelada no dia não ganha pergunta: a ficha nunca sai, nem com o *mande*
       and cardinality(public._agenda_ficha_os_concluidas(c.payee_id, v_d)) = 0
       -- FICHA PAGA B: fim
       -- a ficha desse dia já foi decidida (registrada, ou de carona no "como foi hoje?"): não há o que perguntar
       and not exists (select 1 from public.agenda_equipe_mensagens m
                        where m.payee_id = c.payee_id and m.modo = 'ligado'
                          and ((m.tipo = 'ficha' and m.dia = v_d) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_d)))
     order by 2, 1
  loop
    -- o que a ficha diz desse dia pela estimativa: cada OS dele no dia, o turno e que dia é do plano dela
    select array_agg(format('%s, %s %s — dia %s de %s', o.cliente, public._dia_curto(v_d),
                            case when o.m and o.t then 'o dia todo' when o.m then 'de manhã' else 'à tarde' end, o.k, o.n)
                     order by o.ini, o.os),
           (array_agg(o.os order by o.ini, o.os))[1]
      into v_partes, v_os
      from (select a.service_order_id as os, min(lower(a.periodo)) as ini,
                   bool_or(a.turno = 'manha') as m, bool_or(a.turno = 'tarde') as t,
                   coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as cliente,
                   (select count(distinct b.dia) from public.agenda_alocacoes b
                     where b.service_order_id = a.service_order_id and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva'
                       and b.presenca = 'turno' and b.dia <= v_d) as k,
                   (select count(distinct b.dia) from public.agenda_alocacoes b
                     where b.service_order_id = a.service_order_id and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva'
                       and b.presenca = 'turno') as n
              from public.agenda_alocacoes a
              join public.service_orders so on so.id = a.service_order_id
              left join public.clients cl on cl.id = so.client_id
             where a.payee_id = p.payee_id and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
               and a.duracao_fonte = 'orcamento'
             group by a.service_order_id, cl.name, so.service_order_number) o;
    -- FICHA PAGA: (18/11/2026) o número da OS na frente do nome ("OS-00129 Fulano, qua 18/11 o dia todo — dia 1 de 1"): as mesmas
    -- partes, de novo, com o número
    select array_agg(format('%s, %s %s — dia %s de %s', concat_ws(' ', o.numero, o.cliente), public._dia_curto(v_d),
                            case when o.m and o.t then 'o dia todo' when o.m then 'de manhã' else 'à tarde' end, o.k, o.n)
                     order by o.ini, o.os)
      into v_partes
      from (select a.service_order_id as os, min(lower(a.periodo)) as ini,
                   bool_or(a.turno = 'manha') as m, bool_or(a.turno = 'tarde') as t,
                   so.service_order_number as numero, public._agenda_nome_curto(cl.name) as cliente,
                   (select count(distinct b.dia) from public.agenda_alocacoes b
                     where b.service_order_id = a.service_order_id and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva'
                       and b.presenca = 'turno' and b.dia <= v_d) as k,
                   (select count(distinct b.dia) from public.agenda_alocacoes b
                     where b.service_order_id = a.service_order_id and b.estado in ('publicada', 'fixada') and b.tipo <> 'reserva'
                       and b.presenca = 'turno') as n
              from public.agenda_alocacoes a
              join public.service_orders so on so.id = a.service_order_id
              left join public.clients cl on cl.id = so.client_id
             where a.payee_id = p.payee_id and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
               and a.duracao_fonte = 'orcamento'
             group by a.service_order_id, cl.name, so.service_order_number) o;
    -- FICHA PAGA: fim
    -- FICHA PAGA: (18/11/2026) com OS paga por inteiro, o aviso e a recomendação e o padrão na 2 (Segure): sem resposta, eu seguro.
    -- A aberta que nasceu antes de a OS ficar paga (padrão 1, sem resposta) não muda o que pergunta (o gatilho recusa): fica
    -- resolvida e nasce a nova, com o mesmo insert do gravador (_agenda_gestor_perguntar não devolve a mesma chave fechada).
    v_fp_os := public._agenda_ficha_os_pagas(p.payee_id, v_d);
    v_id := null;
    if cardinality(v_fp_os) > 0 then
      v_fp_rot := public._agenda_lista(array(select so.service_order_number from unnest(v_fp_os) with ordinality u(os, o)
                                              join public.service_orders so on so.id = u.os order by u.o), null);
      v_txt := format('Hoje às %s a ficha de %s vai para %s: %s, pela minha estimativa.', v_hora, v_quando, p.nome,
                      array_to_string(v_partes, '; '))
               || case when cardinality(v_fp_os) = 1
                       then format(' A %s já está PAGA por inteiro: o serviço ainda vai ser feito?', v_fp_rot)
                       else format(' As %s já estão PAGAS por inteiro: os serviços ainda vão ser feitos?', v_fp_rot) end
               || format(' Sem resposta até %s, eu seguro a ficha.', v_hora)
               || ' 1) Mande; 2) Segure a ficha: eu não mando e você fala com ele (recomendo).';
      -- FICHA PAGA B: (18/11/2026) só a OS paga que ainda não começou segura: o aviso diz isso
      v_txt := replace(replace(v_txt, ' já está PAGA por inteiro: o serviço ainda vai ser feito?',
                                      ' já está PAGA e ainda não começou: o serviço ainda vai ser feito?'),
                       ' já estão PAGAS por inteiro: os serviços ainda vão ser feitos?',
                       ' já estão PAGAS e ainda não começaram: os serviços ainda vão ser feitos?');
      -- FICHA PAGA B: fim
      select q.* into v_fp_q from public.agenda_perguntas q
       where q.chave = format('ficha_estimativa:%s:%s', p.payee_id, v_d) and q.modo = v_modo and q.estado = 'aberta';
      if v_fp_q.id is not null and v_fp_q.opcao_padrao is distinct from 2 and v_fp_q.opcao_escolhida is null then
        update public.agenda_perguntas
           set estado = 'resolvida', resolvida_motivo = 'a OS ficou paga por inteiro depois desta pergunta: perguntei de novo, avisando'
         where id = v_fp_q.id;
        insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, recomendacao, modo,
                                             criada_em, expira_em, veto_ate, opcao_padrao)
        values ('ficha_estimativa', v_fp_q.chave, v_os, case when v_os is null then '{}'::uuid[] else array[v_os] end,
                (v_ate at time zone 'America/Sao_Paulo')::date, left(public._agenda_corta(v_txt, 600), 600), v_ops, 2::smallint,
                v_modo, p_agora, v_ate + cf.desfazer_validade, v_ate, 2::smallint)
        returning id into v_id;
      end if;
      if v_id is null then
        v_id := public._agenda_gestor_perguntar('ficha_estimativa', format('ficha_estimativa:%s:%s', p.payee_id, v_d), v_os, v_txt,
                                                v_ops, 2::smallint, v_ate, 2::smallint, v_modo, p_agora);
      end if;
    else
    -- FICHA PAGA: fim
    v_txt := format('Hoje às %s a ficha de %s vai para %s: %s, pela minha estimativa.', v_hora, v_quando, p.nome,
                    array_to_string(v_partes, '; '))
             || ' 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele.';
    v_id := public._agenda_gestor_perguntar('ficha_estimativa', format('ficha_estimativa:%s:%s', p.payee_id, v_d), v_os, v_txt,
                                            v_ops, 1::smallint, v_ate, 1::smallint, v_modo, p_agora);
    -- FICHA PAGA: (fecha o "se tem OS paga")
    end if;
    -- FICHA PAGA: fim
    if v_id is not null and exists (select 1 from public.agenda_perguntas q where q.id = v_id and q.criada_em = p_agora) then
      v_novas := v_novas + 1;
    end if;
    v_lista := v_lista || jsonb_build_object('pessoa', p.payee_id, 'nome', p.nome, 'pergunta_id', v_id, 'texto', v_txt);
  end loop;
  return jsonb_build_object('dia', v_d, 'prazo', v_ate, 'modo', v_modo, 'perguntas', jsonb_array_length(v_lista),
                            'novas', v_novas, 'pessoas', v_lista);
end;
$function$;

comment on function public._agenda_gestor_fichas(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P11; AG7-15, spec §5.11 e §6.3): o passo diário fichas da rodada do gestor — com o ligar do gestor (marcar_sozinho_desde) e o próximo dia útil dentro das ficha_veto_dias a partir dele, para cada pessoa da rotina (_agenda_contatos_com_plano, sem o dono) com alocação vigente nesse dia de duracao_fonte orcamento e sem a ficha do dia já decidida, a pergunta ficha_estimativa (chave ficha_estimativa:<pessoa>:<dia>; veto_ate = hoje às equipe_hora_ficha; opções 1 Mande / 2 Segure; recomendação e padrão 1): "Hoje às 19:30 a ficha de amanhã vai para Roberto: Lenine, ter 03/11 o dia todo — dia 1 de 6, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele." (o dia que não é amanhã pelo nome: "a ficha de terça"). O modo é o de _agenda_modo_da_pergunta(''ficha_estimativa'') — o das mensagens à equipe; desligado, fora da janela, depois da hora da ficha ou fora de dia útil = {pulado}. {dia, prazo, modo, perguntas, novas, pessoas [{pessoa, nome, pergunta_id, texto}]}. Invoker, sem grant. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; a ficha prometida a quem não tem telefone): só pergunta a ficha de quem tem para onde ela ir (_agenda_equipe_tem_telefone, a régua de _agenda_equipe_registrar): sem telefone, nenhuma pergunta — a ficha fica segurada às 19:30 e o aviso diz "não tem telefone no cadastro. Fale com Alex.". FICHA PAGA (18/11/2026, 20270125100000; o caso OS-00129): toda pergunta leva o número da OS ("Alex: OS-00129 Fulano, qua 18/11 o dia todo — dia 1 de 1"). Com OS paga por inteiro (_agenda_ficha_os_pagas): "… pela minha estimativa. A OS-00129 já está PAGA por inteiro: o serviço ainda vai ser feito? Sem resposta até 19:30, eu seguro a ficha. 1) Mande; 2) Segure a ficha: eu não mando e você fala com ele (recomendo).", recomendação e padrão 2; fora da janela e sem o ligar do gestor, só pergunta a quem tem OS paga (sem nenhuma, os pulos de antes). A aberta que nasceu antes de a OS ficar paga (padrão 1, sem resposta) fica resolvida ("a OS ficou paga por inteiro depois desta pergunta: perguntei de novo, avisando") e nasce a nova, com o insert do gravador. FICHA PAGA B (18/11/2026, 20270126100000): a pergunta da OS paga diz "A OS-00129 já está PAGA e ainda não começou: o serviço ainda vai ser feito?" (só a OS paga que ainda não começou pergunta e abre o passo fora da janela); quem tem OS concluída, faturada ou cancelada no dia não ganha pergunta: a ficha não sai de todo jeito.';

-- ── 5. A ficha das 19:30 ────────────────────────────────────────────────────────────────────────────────
-- _agenda_rotina_ficha (de 20270125100000 (F2); md5 do corpo de antes c0f0f48b02e4a7b80888d3112fa7cc40 sem CR)
create or replace function public._agenda_rotina_ficha(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_local timestamp := p_agora at time zone 'America/Sao_Paulo';
  v_modo  text := public._agenda_modo_da_equipe();
  v_d     date;
  v_p     uuid;
  v_f     jsonb;
  v_r     jsonb;
  v_cont  jsonb := '{}'::jsonb;
  -- FASE 7: (7a P11) a ficha de um dia pela estimativa, na janela de veto
  v_f11_q   public.agenda_perguntas%rowtype;
  v_f11_m   uuid;
  v_f11_a   uuid;
  v_f11_os  uuid[];
  v_f11_cli text;
  v_f11_nom text;
  v_f72_fecha boolean := false;  -- (7a correção 2) a pergunta da ficha fecha depois do registro, com o que houve
  -- FICHA PAGA: (18/11/2026) as OS pagas por inteiro da pessoa no dia (_agenda_ficha_os_pagas)
  v_fp_os   uuid[];
  -- FICHA PAGA: fim
  -- FICHA PAGA B: (18/11/2026) as OS concluídas, faturadas ou canceladas da pessoa no dia, todas as OS do dia e o porquê
  v_fc_os   uuid[];
  v_fb_os   uuid[];
  v_fb_cli  text;
  v_fb_txt  text;
  -- FICHA PAGA B: fim
  -- FASE 7: fim
  -- FASE 7f: (7f P5) o previsto e a mudança junto da ficha
  v_7f_s    jsonb;
  v_7f_prev boolean;
  v_7f_mud  boolean;
  v_7f_txt  text;
  v_7f_dias date[];
  -- FASE 7f: fim
begin
  if v_local::time < cf.equipe_hora_ficha or not public.agenda_dia_util(p_hoje) then
    return jsonb_build_object('fichas', 0);
  end if;
  v_d := public.agenda_somar_du(p_hoje, 1);
  for v_p in select x from public._agenda_contatos_com_plano(v_d) x loop
    continue when exists (select 1 from public.agenda_equipe_mensagens m
                           where m.payee_id = v_p and m.modo = v_modo
                             and ((m.tipo = 'ficha' and m.dia = v_d) or (m.tipo = 'como_foi' and m.leva_ficha_de = v_d)));
    -- FASE 7f: (7f P5, §5.5 (1), AG7-23 "Sim, só vira dia dele com o sim") quem tem o convite de amanhã enviado e ainda sem o SIM não recebe a ficha:
    -- o dia ainda não é dele. Só com o convite ligado de verdade (com o freio, o de antes: a ficha sai).
    continue when public._agenda_fala_modo('convite') = 'ligado'
                  and exists (select 1 from public.agenda_equipe_mensagens m
                               where m.payee_id = v_p and m.tipo = 'convite' and m.dia = v_d and m.modo = 'ligado'
                                 and m.estado in ('enfileirada', 'sem_resposta', 'respondida')
                                 and m.leitura ->> 'convite' is distinct from 'sim');
    -- FASE 7f: fim
    v_f := public.agenda_equipe_ficha(v_p, v_d, p_hoje);
    continue when not coalesce((v_f ->> 'tem_plano')::boolean, false);
    -- FASE 7: (7a P11, spec §3.2 "Equipe" e §5.11; AG7-15) nas primeiras ficha_veto_dias a partir do ligar do gestor, a ficha de
    -- um dia marcado pela estimativa (a alocação da pessoa no dia com duracao_fonte orcamento) só sai com a pergunta
    -- ficha_estimativa daquele dia mostrada ao dono e não segurada (_agenda_ficha_liberada). Senão ela fica registrada como
    -- recusada (veto): nada vai à fila nem conta no teto da pessoa. Se o dono não soube (não viu a pergunta a tempo, ou ela nem
    -- nasceu), o que mudou conta para ele (a ação equipe da vigia: o fechamento e o *o que mudou* do dia seguinte). A pergunta do
    -- dia fecha aqui: a hora da ficha chegou. Só com a mensagem de verdade (em teste nada sai de todo jeito).
    if v_modo = 'ligado' then
      v_f11_q := null;
      select q.* into v_f11_q from public.agenda_perguntas q
       where q.chave = format('ficha_estimativa:%s:%s', v_p, v_d) and q.modo = 'ligado'
       order by q.criada_em desc, q.id desc limit 1;
      if not public._agenda_ficha_liberada(v_p, v_d, p_agora) then
        insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, recusa_motivo, dedupe_key,
                                                    criada_em)
        values (v_p, v_d, 'ficha', 'ligado', left(v_f ->> 'texto_ficha', 600), p_agora, 'recusada', 'veto',
                format('agenda-equipe:ficha:%s:%s', v_p, v_d), p_agora)
        returning id into v_f11_m;
        -- FICHA PAGA: (18/11/2026) a ficha presa por OS paga por inteiro diz o porquê ao dono (por = paga)
        v_fp_os := public._agenda_ficha_os_pagas(v_p, v_d);
        -- FICHA PAGA: fim
        -- FICHA PAGA B: (18/11/2026) as OS concluídas, faturadas ou canceladas (qualquer alocação) e TODAS as OS da pessoa no dia, para o aviso
        v_fc_os := public._agenda_ficha_os_concluidas(v_p, v_d);
        v_fb_os := array(select a.service_order_id from public.agenda_alocacoes a
                          where a.payee_id = v_p and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                          group by a.service_order_id order by min(lower(a.periodo)), a.service_order_id);
        v_fb_cli := public._agenda_lista(array(
                      select concat_ws(' ', so.service_order_number, public._agenda_nome_curto(cl.name))
                        from unnest(v_fb_os) with ordinality u(os, o)
                        join public.service_orders so on so.id = u.os left join public.clients cl on cl.id = so.client_id
                       order by u.o), null);
        -- "concluída", "faturada", "cancelada" (ou os que houver, por " ou "), no plural com mais de uma
        v_fb_txt := public._agenda_ficha_os_concluidas_texto(v_fc_os);
        -- FICHA PAGA B: fim
        if v_f11_q.id is null or v_f11_q.opcao_escolhida is distinct from 2 then
          v_f11_os := array(select a.service_order_id from public.agenda_alocacoes a
                             where a.payee_id = v_p and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                               and a.duracao_fonte = 'orcamento'
                             group by a.service_order_id order by min(lower(a.periodo)), a.service_order_id);
          v_f11_cli := public._agenda_lista(array(
                         select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)
                           from unnest(v_f11_os) with ordinality u(os, o)
                           join public.service_orders so on so.id = u.os left join public.clients cl on cl.id = so.client_id
                          order by u.o), null);
          v_f11_nom := (select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_p);
          -- FICHA PAGA B: (18/11/2026) OS concluída, faturada ou cancelada: a ficha nunca sai ("Não mandei a ficha de qui 05/11 a Roberto (OS-00074
          -- Lenine): a OS já está concluída. Fale com Roberto.", por concluida). E a OS paga (o porquê da F2) com o dia misto: TODAS as OS do
          -- dia no parêntese e a paga nomeada no porquê. O ramo da OS paga da F2, logo abaixo, fica sem uso (mantido para a cópia sem os
          -- blocos B ser a da F2).
          if cardinality(v_fc_os) > 0 then
            insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
            values (clock_timestamp(), p_hoje, true, 'vigia', 'equipe', v_fb_os[1], v_fb_os, v_p,
                    jsonb_build_object('motivo', 'ficha_segurada', 'dia', v_d, 'mensagem', v_f11_m, 'pergunta', v_f11_q.id, 'por', 'concluida'),
                    left(format('Não mandei a ficha de %s a %s (%s): %s. Fale com %s.',
                                public._dia_curto(v_d), v_f11_nom, v_fb_cli,
                                -- todas as OS do dia concluídas: "a OS" / "as OS"; o dia misto nomeia as concluídas ("a OS-00074 já está …")
                                case when cardinality(v_fb_os) <= cardinality(v_fc_os)
                                       then case when cardinality(v_fc_os) = 1 then 'a OS já está ' else 'as OS já estão ' end || v_fb_txt
                                     else case when cardinality(v_fc_os) = 1 then 'a ' else 'as ' end
                                          || public._agenda_lista(array(select so.service_order_number from unnest(v_fc_os) with ordinality u(os, o)
                                                                         join public.service_orders so on so.id = u.os order by u.o), null)
                                          || case when cardinality(v_fc_os) = 1 then ' já está ' else ' já estão ' end || v_fb_txt end,
                                v_f11_nom), 400))
            returning id into v_f11_a;
          elsif cardinality(v_fp_os) > 0 and not (v_f11_q.id is null and not public._agenda_equipe_tem_telefone(v_p)) then
            insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
            values (clock_timestamp(), p_hoje, true, 'vigia', 'equipe', v_fb_os[1], v_fb_os, v_p,
                    jsonb_build_object('motivo', 'ficha_segurada', 'dia', v_d, 'mensagem', v_f11_m, 'pergunta', v_f11_q.id,
                                       'por', case when v_f11_q.id is null then 'paga_sem_pergunta'
                                                   when coalesce(v_f11_q.mostrada_vezes, 0) = 0 then 'paga_nao_vista'
                                                   else 'paga' end),
                    left(format('Não mandei a ficha de %s a %s (%s): %s %s. Fale com %s.',
                                public._dia_curto(v_d), v_f11_nom, v_fb_cli,
                                -- todas as OS do dia pagas: o texto da F2; o dia misto nomeia as pagas ("a OS-00129 já está paga por inteiro")
                                case when cardinality(v_fb_os) <= cardinality(v_fp_os)
                                       then case when cardinality(v_fp_os) = 1 then 'a OS já está paga por inteiro' else 'as OS já estão pagas por inteiro' end
                                     else case when cardinality(v_fp_os) = 1 then 'a ' else 'as ' end
                                          || public._agenda_lista(array(select so.service_order_number from unnest(v_fp_os) with ordinality u(os, o)
                                                                         join public.service_orders so on so.id = u.os order by u.o), null)
                                          || case when cardinality(v_fp_os) = 1 then ' já está paga por inteiro' else ' já estão pagas por inteiro' end end,
                                case when v_f11_q.id is null
                                       then 'e não consegui te perguntar antes das ' || to_char(cf.equipe_hora_ficha, 'HH24:MI')
                                     when coalesce(v_f11_q.mostrada_vezes, 0) = 0 then 'e você não viu a pergunta'
                                     else 'e você não disse *mande*' end,
                                v_f11_nom), 400))
            returning id into v_f11_a;
          else
          -- FICHA PAGA B: fim
          -- FICHA PAGA: (18/11/2026) a ficha presa por OS paga por inteiro: o porquê é esse ("Não mandei a ficha de qua 18/11 a Alex
          -- (OS-00129 Fulano): a OS já está paga por inteiro e <porquê>. Fale com Alex."), dito pelo que houve com a pergunta: sem pergunta,
          -- "e não consegui te perguntar antes das 19:30" (por paga_sem_pergunta); não mostrada, "e você não viu a pergunta" (paga_nao_vista);
          -- mostrada e sem resposta, "e você não disse *mande*" (paga). O texto é o do insert: a ação não muda depois de gravada (o gatilho
          -- _agenda_acoes_so_desfaz). Sem telefone, o de antes (ela não sairia de todo jeito).
          if cardinality(v_fp_os) > 0 and not (v_f11_q.id is null and not public._agenda_equipe_tem_telefone(v_p)) then
            insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
            values (clock_timestamp(), p_hoje, true, 'vigia', 'equipe', v_f11_os[1], v_f11_os, v_p,
                    jsonb_build_object('motivo', 'ficha_segurada', 'dia', v_d, 'mensagem', v_f11_m, 'pergunta', v_f11_q.id,
                                       'por', case when v_f11_q.id is null then 'paga_sem_pergunta'
                                                   when coalesce(v_f11_q.mostrada_vezes, 0) = 0 then 'paga_nao_vista'
                                                   else 'paga' end),
                    left(format('Não mandei a ficha de %s a %s (%s): %s %s. Fale com %s.',
                                public._dia_curto(v_d), v_f11_nom,
                                public._agenda_lista(array(
                                  select concat_ws(' ', so.service_order_number, public._agenda_nome_curto(cl.name))
                                    from unnest(v_fp_os) with ordinality u(os, o)
                                    join public.service_orders so on so.id = u.os left join public.clients cl on cl.id = so.client_id
                                   order by u.o), null),
                                case when cardinality(v_fp_os) = 1 then 'a OS já está paga por inteiro'
                                     else 'as OS já estão pagas por inteiro' end,
                                case when v_f11_q.id is null
                                       then 'e não consegui te perguntar antes das ' || to_char(cf.equipe_hora_ficha, 'HH24:MI')
                                     when coalesce(v_f11_q.mostrada_vezes, 0) = 0 then 'e você não viu a pergunta'
                                     else 'e você não disse *mande*' end,
                                v_f11_nom), 400))
            returning id into v_f11_a;
          else
          -- FICHA PAGA: fim
          insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
          values (clock_timestamp(), p_hoje, true, 'vigia', 'equipe', v_f11_os[1], v_f11_os, v_p,
                  jsonb_build_object('motivo', 'ficha_segurada', 'dia', v_d, 'mensagem', v_f11_m, 'pergunta', v_f11_q.id,
                                     -- (7a correção 2) quem não tem telefone não ganha a pergunta: o porquê é esse
                                     'por', case when v_f11_q.id is null and not public._agenda_equipe_tem_telefone(v_p) then 'sem_telefone'
                                                 when v_f11_q.id is null then 'sem_pergunta' else 'nao_vista' end),
                  left(format('Não mandei a ficha de %s a %s (%s): o dia é pela minha estimativa e %s. Fale com %s.',
                              public._dia_curto(v_d), v_f11_nom, v_f11_cli,
                              -- (7a correção 2) sem telefone no cadastro: o gestor não pergunta a ficha (ela não sairia), e o
                              -- dono fica sabendo que tem de avisar de boca
                              case when v_f11_q.id is null and not public._agenda_equipe_tem_telefone(v_p)
                                     then format('%s não tem telefone no cadastro', v_f11_nom)
                                   when v_f11_q.id is null then 'não consegui te perguntar antes'
                                   else 'você não viu a pergunta antes das ' || to_char(cf.equipe_hora_ficha, 'HH24:MI') end,
                              v_f11_nom), 400))
          returning id into v_f11_a;
          -- FICHA PAGA: (fecha o "se a OS está paga")
          end if;
          -- FICHA PAGA: fim
          -- FICHA PAGA B: (fecha o "se a OS está encerrada ou paga")
          end if;
          -- FICHA PAGA B: fim
          update public.agenda_equipe_mensagens set acao_id = v_f11_a where id = v_f11_m;
        end if;
        -- FICHA PAGA B: (18/11/2026) a pergunta aberta de quem tem OS concluída, faturada ou cancelada fecha com o motivo dela
        if cardinality(v_fc_os) > 0 then
          update public.agenda_perguntas
             set estado = 'resolvida', resolvida_motivo = 'a OS já estava concluída, faturada ou cancelada: a ficha não saiu'
           where chave = format('ficha_estimativa:%s:%s', v_p, v_d) and modo = 'ligado' and estado = 'aberta';
        end if;
        -- FICHA PAGA B: fim
        -- FICHA PAGA: (18/11/2026) a pergunta da OS paga fecha com o motivo dela (o update de baixo não acha mais a aberta)
        if cardinality(v_fp_os) > 0 then
          update public.agenda_perguntas
             set estado = 'resolvida',
                 resolvida_motivo = case when coalesce(v_f11_q.mostrada_vezes, 0) = 0
                                         then 'a OS estava paga por inteiro e você não viu a pergunta: a ficha não saiu'
                                         else 'a OS estava paga por inteiro e você não disse mande: a ficha não saiu' end
           where chave = format('ficha_estimativa:%s:%s', v_p, v_d) and modo = 'ligado' and estado = 'aberta';
        end if;
        -- FICHA PAGA: fim
        update public.agenda_perguntas
           set estado = 'resolvida', resolvida_motivo = 'na hora da ficha você não tinha visto a pergunta: a ficha não saiu'
         where chave = format('ficha_estimativa:%s:%s', v_p, v_d) and modo = 'ligado' and estado = 'aberta';
        v_cont := v_cont || jsonb_build_object('recusada', coalesce((v_cont ->> 'recusada')::int, 0) + 1);
        continue;
      end if;
      -- (7a correção 2) a pergunta fecha logo abaixo, depois do registro: antes ela fechava aqui "ela foi como eu disse" e o
      -- registro recusava em seguida (sem telefone, teto, janela) — o dono lia que a ficha tinha ido
      v_f72_fecha := true;
    end if;
    -- FASE 7: fim
    -- FASE 7f: (7f P5, §5.5 (2) e (3), §6.4, R8.5-17) com o previsto ligado de verdade (o freio = teste) e a equipe ligada, a ficha leva o que a
    -- semana da pessoa tem a dizer, numa mensagem só: a mudança dos dias que ela já ouviu ("Na semana: sai …; entra …") e, na quinta, o previsto da
    -- semana que vem. A ficha grava em dias o que a pessoa passa a ter ouvido. Sem nada a dizer, ou passando de 600 letras, a ficha de antes (e os
    -- passos previsto e mudancas_equipe da rodada comunicar mandam o que ficou de fora, sozinho). Fora disso, byte a byte a de antes.
    v_7f_txt := null;
    v_7f_dias := null;
    if v_modo = 'ligado' and public._agenda_fala_modo('previsto') = 'ligado' then
      v_7f_s := public._agenda_equipe_semana_da_pessoa(v_p, p_hoje, p_agora);
      v_7f_prev := jsonb_array_length(coalesce(v_7f_s -> 'previsto', '[]'::jsonb)) > 0
                   and not exists (select 1 from public.agenda_equipe_mensagens m
                                    where m.payee_id = v_p and m.tipo = 'previsto' and m.dia = (v_7f_s ->> 'seg')::date and m.modo = 'ligado');
      v_7f_mud := jsonb_typeof(v_7f_s -> 'mudanca') = 'object'
                  and not exists (select 1 from public.agenda_equipe_mensagens m
                                   where m.dedupe_key = format('agenda-equipe:mudanca:%s:%s:19h', v_p, p_hoje));
      if v_7f_prev or v_7f_mud then
        v_7f_txt := case when v_7f_mud then v_7f_s ->> 'texto_mudanca_junto' else '' end
                    || case when v_7f_prev then v_7f_s ->> 'texto_previsto_junto' else '' end;
        v_7f_dias := array(select x::date from jsonb_array_elements_text(v_7f_s -> case when v_7f_prev and v_7f_mud then 'estado_ambos'
                                                                                   when v_7f_prev then 'estado_previsto'
                                                                                   else 'estado_mudanca' end) x order by 1);
        if char_length(coalesce(v_f ->> 'texto_ficha', '')) + char_length(v_7f_txt) > 600 then
          v_7f_txt := null;
          v_7f_dias := null;
        end if;
      end if;
    end if;
    if v_7f_txt is not null then
      v_r := public._agenda_equipe_registrar(v_p, v_d, 'ficha', (v_f ->> 'texto_ficha') || v_7f_txt, p_agora, null, null, v_7f_dias);
    else
    -- FASE 7f: fim
    v_r := public._agenda_equipe_registrar(v_p, v_d, 'ficha', v_f ->> 'texto_ficha', p_agora);
    -- FASE 7f: (7f P5) o fim do if de cima
    end if;
    -- FASE 7f: fim
    -- FASE 7: (7a correção 2, a ficha prometida a quem não tem telefone) a pergunta da ficha liberada fecha com o que aconteceu
    -- no registro: enfileirada = "ela foi como eu disse"; recusada (o teto, a janela, o telefone que sumiu) = o porquê
    if v_f72_fecha then
      update public.agenda_perguntas
         set estado = 'resolvida',
             resolvida_motivo = case when v_r ->> 'estado' = 'recusada'
                                     then format('na hora da ficha você não a segurou, mas ela não saiu (%s)',
                                                 case v_r ->> 'motivo' when 'sem_telefone' then 'sem telefone no cadastro'
                                                                       when 'teto' then 'o limite de mensagens do dia'
                                                                       when 'janela' then 'fora do horário de mandar'
                                                                       when 'parou' then 'a pessoa não recebe mais a rotina'
                                                                       else coalesce(v_r ->> 'motivo', 'recusada') end)
                                     else 'na hora da ficha você não a segurou: ela foi como eu disse' end
       where chave = format('ficha_estimativa:%s:%s', v_p, v_d) and modo = 'ligado' and estado = 'aberta';
      v_f72_fecha := false;
    end if;
    -- FASE 7: fim
    v_cont := v_cont || jsonb_build_object(coalesce(v_r ->> 'estado', 'nada'),
                                           coalesce((v_cont ->> coalesce(v_r ->> 'estado', 'nada'))::int, 0) + 1);
  end loop;
  return jsonb_build_object('dia', v_d, 'por_estado', v_cont);
end;
$function$;

comment on function public._agenda_rotina_ficha(date, timestamptz) is
  'Agenda de Produção (Fase 3, P4): a ficha da véspera (equipe_hora_ficha num dia útil) para o próximo dia útil — não vai a quem já recebeu a ficha desse dia nem a quem recebeu o "como foi hoje?" levando a ficha; o texto de agenda_equipe_ficha, pelo _agenda_equipe_registrar. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11; AG7-15): com a mensagem de verdade, a ficha que _agenda_ficha_liberada não solta (na janela de veto do ligar, um dia da pessoa marcado pela estimativa sem a pergunta ficha_estimativa mostrada, ou segurada com a 2) fica registrada como recusada (veto) — nada vai à fila nem conta no teto — e, se o dono não soube, a ação equipe da vigia conta no que mudou ("Não mandei a ficha de ter 03/11 a Roberto (Lenine): o dia é pela minha estimativa e você não viu a pergunta antes das 19:30. Fale com Roberto."); a pergunta do dia fecha (resolvida). Fora disso, a de antes, byte a byte. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; a ficha prometida a quem não tem telefone): a ficha segurada de quem não tem telefone diz o porquê ("Não mandei a ficha de qui 05/11 a Alex (Lenine): o dia é pela minha estimativa e Alex não tem telefone no cadastro. Fale com Alex.", por = sem_telefone); e a pergunta da ficha que fechou "ela foi como eu disse" com a ficha recusada no registro ganha o motivo verdadeiro ("… mas ela não saiu (sem telefone no cadastro)"). FASE 7f (P5): com o convite ligado de verdade, quem tem o convite de amanhã sem o SIM não recebe a ficha (AG7-23); com o previsto ligado de verdade e a equipe ligada, a ficha leva a mudança da semana ("Na semana: sai …; entra …") e, na quinta, o previsto da semana que vem, numa mensagem só, e grava em dias o que a pessoa passa a ter ouvido. Fora disso, a de antes, byte a byte. FICHA PAGA (18/11/2026, 20270125100000): a ficha presa por OS paga por inteiro (_agenda_ficha_liberada) diz o porquê ao dono — "Não mandei a ficha de qua 18/11 a Alex (OS-00129 Fulano): a OS já está paga por inteiro e <porquê>. Fale com Alex.": sem pergunta, "e não consegui te perguntar antes das 19:30" (por = paga_sem_pergunta); pergunta não mostrada, "e você não viu a pergunta" (paga_nao_vista); mostrada sem resposta, "e você não disse *mande*" (paga). Sem telefone, o de antes. A pergunta aberta fecha com o motivo dela ("a OS estava paga por inteiro e você não viu a pergunta | não disse mande: a ficha não saiu"). Fora disso, byte a byte. FICHA PAGA B (18/11/2026, 20270126100000): a ficha presa por OS concluída, faturada ou cancelada, em qualquer alocação do dia: "Não mandei a ficha de qui 05/11 a Roberto (OS-00074 Lenine): a OS já está concluída. Fale com Roberto." (por = concluida; "faturada", "cancelada" ou os que houver por " ou ", pelo status: _agenda_ficha_os_concluidas_texto); a pergunta aberta fecha com "a OS já estava concluída, faturada ou cancelada: a ficha não saiu". No dia misto, o parêntese cita TODAS as OS do dia e o porquê nomeia a concluída ou a paga ("a OS-00074 já está concluída"). A concluída vence a paga.';

-- ── 6. A saúde da comunicação (C4) ──────────────────────────────────────────────────────────────────────
-- _agenda_saude_comunicacao (de 20270122100000 (produção em 18/11); md5 do corpo de antes 00926f7360872e00e572b5dd5fce6a6c sem CR)
create or replace function public._agenda_saude_comunicacao(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_semana  constant int := 7;    -- estrutural: os números "na semana" (§11)
  c_quinze  constant int := 14;   -- estrutural: "desfeitas em 2 semanas" (§11, parar)
  c_lotes   constant int := 2;    -- estrutural: o alvo de §11 é 2 lotes (o fechamento e a quinta) mais acordes_dia_max
  -- estrutural: a lista do CHECK agenda_config_veto_tipos_check (20261109100000), o que nunca vence pelo prazo; o V3 confere que é a mesma
  c_nunca   constant text[] := array['diaria', 'diaria_ligar', 'nfe_vincular', 'pix_material', 'concluir', 'entrega', 'cliente_aprovar', 'cliente_aviso',
                                     'cliente_resposta', 'aprendizado', 'conferencia', 'remarcar_confirmado', 'compre_ate', 'sinal', 'tarefa', 'local',
                                     'combinar', 'acesso', 'dia_prometido', 'dia_avisado'];
  cf        public.agenda_config;
  v_uid     uuid := auth.uid();
  v_papel   text;
  v_modos   jsonb;
  v_algum   boolean;
  v_ult     timestamptz;
  v_rod24   int;
  v_abertas int;
  v_acima   int;
  v_bloco   jsonb := '{}'::jsonb;
  v_bgrande int := 0;
  v_z       jsonb;
  v_n       jsonb := '{}'::jsonb;
begin
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'A saúde da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then
      v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') then
      raise exception 'A saúde da agenda é com o administrador ou o financeiro.' using errcode = '42501';
    end if;
  end if;
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_saude_comunicacao: sem o dia de hoje ou a hora' using errcode = '22004';
  end if;
  cf := public._agenda_cfg();
  v_modos := jsonb_build_object('bloco', cf.modo_bloco_agenda, 'lote', cf.modo_lote_dono, 'veto', cf.modo_veto, 'previsto', cf.modo_equipe_previsto,
                                'convite', cf.modo_equipe_convite, 'camadas', cf.modo_cliente_camadas);
  v_algum := exists (select 1 from jsonb_each_text(v_modos) m where m.value <> 'desligado');
  select max(r.p_agora), count(*) filter (where r.p_agora > p_agora - interval '1 day' and r.p_agora <= p_agora)
    into v_ult, v_rod24
    from public.agenda_vigia_rodadas r
   where r.rotina = 'comunicar' and r.p_agora <= p_agora;
  -- as que contam no teto, como _agenda_comunicar_teto: ligadas, sem conferencia, que valem
  select count(*)::int into v_abertas from public.agenda_perguntas x
   where x.estado = 'aberta' and x.modo = 'ligado' and x.tipo <> 'conferencia' and (x.expira_em is null or x.expira_em > p_agora);
  v_acima := greatest(v_abertas - cf.perguntas_abertas_max, 0);

  -- o bloco nos fechamentos dos últimos 7 dias, pelo detalhe de resumo_tarde (P3): em sombra, bloco_seria (o texto que sairia com ele ligado); ligado, bloco_mostrou e o texto que saiu.
  -- No mínimo o bloco é o veredito e a 1ª decisão (com o "e mais N"): acima de texto_max com qualquer outra linha, ele ainda podia ceder, e isso é o bloco_grande.
  -- A tabela é a do Secretário (20261015210000); um resumo_tarde sem as colunas que o bloco lê (o da bancada da Fase 2 tem só dia, telefone e detalhe) conta como sem a tabela.
  if to_regclass('public.resumo_tarde') is not null
     and (select count(*) from pg_attribute a where a.attrelid = to_regclass('public.resumo_tarde') and a.attnum > 0 and not a.attisdropped
             and a.attname in ('dia', 'turno', 'detalhe', 'criado_em')) = 4 then
    execute $q$
      select coalesce(jsonb_build_object(
               'em_sombra', count(*) filter (where t.detalhe -> 'agenda' ? 'bloco_seria'),
               'seria_dentro', count(*) filter (where (t.detalhe #>> '{agenda,bloco_seria,caracteres}')::int <= $3),
               'seria_acima', count(*) filter (where (t.detalhe #>> '{agenda,bloco_seria,caracteres}')::int > $3),
               'seria_dentro_por_turno', coalesce((select jsonb_object_agg(z.turno, z.n) from (
                   select u.turno, count(*) as n from public.resumo_tarde u
                    where u.dia between $1 and $2 and (u.detalhe #>> '{agenda,bloco_seria,caracteres}')::int <= $3 group by u.turno) z), '{}'::jsonb),
               'ligado', count(*) filter (where t.detalhe -> 'agenda' ? 'bloco_mostrou'),
               'ligado_acima', count(*) filter (where t.detalhe -> 'agenda' ? 'bloco_mostrou' and (t.detalhe ->> 'caracteres')::int > $3),
               'ultimo', (select jsonb_build_object('dia', u.dia, 'turno', u.turno, 'modo', u.detalhe #>> '{agenda,bloco_diria,modo}',
                                                    'caracteres', coalesce((u.detalhe #>> '{agenda,bloco_seria,caracteres}')::int, (u.detalhe ->> 'caracteres')::int))
                            from public.resumo_tarde u
                           where u.dia between $1 and $2 and u.detalhe -> 'agenda' ? 'bloco_diria'
                           order by u.dia desc, u.criado_em desc limit 1)), '{}'::jsonb),
             count(*) filter (where t.detalhe -> 'agenda' ? 'bloco_mostrou' and (t.detalhe ->> 'caracteres')::int > $3
                                and ((select count(*) from jsonb_array_elements(t.detalhe #> '{agenda,bloco_mostrou}') l where l ->> 'parte' not in ('veredito', 'decisao')) > 0
                                     or (select count(*) from jsonb_array_elements(t.detalhe #> '{agenda,bloco_mostrou}') l where l ->> 'parte' = 'decisao') > 2))::int
        from public.resumo_tarde t
       where t.dia between $1 and $2 and t.detalhe -> 'agenda' ? 'bloco_diria'
    $q$ into v_bloco, v_bgrande using p_hoje - c_semana + 1, p_hoje, cf.texto_max;
    -- PRAZO NO BLOCO: (17/11/2026, 20270122100000; revisão da F1) o mínimo do bloco com a linha das perguntas do gestor. Com ela no bloco, as que nunca saem são a 1ª
    -- decisão, a do gestor e a do cliente (2A): no mínimo ele pode ter 3 decisões, e acima de texto_max já não tem o que ceder — isso não é bloco grande. A conta de cima
    -- vale, com a tolerância "as fixas + 1": no nivel_min só ficam as que nunca saem — o "(e mais N)" sai nele (o corte dele é o nivel_min; o "com o e mais N" do
    -- comentário de cima não vale para o mínimo) — e o +1 é o nível logo acima, que ainda tem o "(e mais N)". Antes, 1 fixa: 2. Com a do gestor no fechamento, +1
    -- quando a 1ª é uma crítica (sempre numerada, "Decisão N:"; sem crítica, a 1ª é a do gestor) e +1 com a do cliente à vista. (revisão 3) As marcas presas às linhas
    -- certas, com os espaços juntados como o Secretário os junta (blocoDaAgenda e linhasDaAgenda, secretario-tarde-coleta.ts):
    --   a do gestor: a (m) ligada de perda 76 está em linhas_diria e uma decisão à vista é a forma inteira dela ('· ' e o texto sem o "Agenda: ", igual) ou a curta.
    --   linhas_diria não grava a curta; _agenda_linhas_do_fechamento a monta das mesmas perguntas: com a ficha em 1º, ela começa pelo trecho do texto da ficha antes de
    --   " 1) Mande" (o mesmo começo da inteira) e " Para segurar, me diga."; sem a ficha, a 1ª tem prazo (perda 76: a ordem é ficha, prazo, sem prazo) e a curta começa
    --   por "Sem resposta até <dia hora>, conto: ". Nenhuma linha da ordem nem a do cliente começa assim (as 4 da ordem saem numeradas);
    --   a do cliente (v_cli, fixa): a linha cliente ligada de linhas_diria, escrita como o bloco a escreve ('· ' e _agenda_corta do texto sem a mensagem, 220), é igual
    --   a uma decisão à vista — uma cliente_aprovar da ordem ("Mensagem para …", que pode sair) não casa.
    -- Sem a do gestor à vista, a tolerância é a de antes (2) e a conta sai a mesma, também nos fechamentos de antes de aplicar (a janela de 7 dias ainda os lê).
    execute $q$
      select count(*) filter (where t.detalhe -> 'agenda' ? 'bloco_mostrou' and (t.detalhe ->> 'caracteres')::int > $3
                                and ((select count(*) from jsonb_array_elements(t.detalhe #> '{agenda,bloco_mostrou}') l where l ->> 'parte' not in ('veredito', 'decisao')) > 0
                                     or (select count(*) from jsonb_array_elements(t.detalhe #> '{agenda,bloco_mostrou}') l where l ->> 'parte' = 'decisao')
                                        > 2 + case when exists (select 1
                                                                  from jsonb_array_elements(t.detalhe #> '{agenda,bloco_mostrou}') l,
                                                                       jsonb_array_elements(case when jsonb_typeof(t.detalhe #> '{agenda,linhas_diria}') = 'array'
                                                                                                 then t.detalhe #> '{agenda,linhas_diria}' else '[]'::jsonb end) x,
                                                                       lateral (select btrim(regexp_replace(l ->> 'texto', '\s+', ' ', 'g')) as v,
                                                                                       '· ' || regexp_replace(btrim(regexp_replace(x ->> 'texto', '\s+', ' ', 'g')), '^Agenda: ', '') as i) z
                                                                 where l ->> 'parte' = 'decisao' and x ->> 'tipo' = 'pergunta' and x ->> 'perda' = '76' and x ->> 'modo' = 'ligado'
                                                                   and (z.v = z.i
                                                                        or starts_with(z.v, split_part(z.i, ' 1) Mande', 1) || ' Para segurar, me diga.')
                                                                        -- FICHA PAGA B: (18/11/2026, 20270126100000; C4 da revisão da F2) a curta da ficha de OS paga
                                                                        -- termina com "Para mandar, me diga *mande*." (a 20270125100000 a escreve assim)
                                                                        or starts_with(z.v, split_part(z.i, ' 1) Mande', 1) || ' Para mandar, me diga *mande*.')
                                                                        -- FICHA PAGA B: fim
                                                                        or z.v ~ '^· Sem resposta até [^,]+, conto: '))
                                                    then coalesce((select case when l ->> 'texto' ~ '^· Decisão [0-9]+: ' then 1 else 0 end
                                                                     from jsonb_array_elements(t.detalhe #> '{agenda,bloco_mostrou}') with ordinality u(l, o)
                                                                    where l ->> 'parte' = 'decisao' order by o limit 1), 0)
                                                         + case when exists (select 1
                                                                               from jsonb_array_elements(t.detalhe #> '{agenda,bloco_mostrou}') l,
                                                                                    jsonb_array_elements(case when jsonb_typeof(t.detalhe #> '{agenda,linhas_diria}') = 'array'
                                                                                                              then t.detalhe #> '{agenda,linhas_diria}' else '[]'::jsonb end) x
                                                                              where l ->> 'parte' = 'decisao' and x ->> 'tipo' = 'cliente' and x ->> 'modo' = 'ligado'
                                                                                and btrim(regexp_replace(l ->> 'texto', '\s+', ' ', 'g'))
                                                                                    = btrim(regexp_replace('· ' || public._agenda_corta(regexp_replace(x ->> 'texto',
                                                                                        ': ".*"( \(\*agenda clientes\* mostra inteira\))?\. \*manda', '. *manda'), 220), '\s+', ' ', 'g')))
                                                                then 1 else 0 end
                                                    else 0 end))::int
        from public.resumo_tarde t
       where t.dia between $1 and $2 and t.detalhe -> 'agenda' ? 'bloco_diria'
    $q$ into v_bgrande using p_hoje - c_semana + 1, p_hoje, cf.texto_max;
    -- PRAZO NO BLOCO: fim
  end if;

  v_z := jsonb_build_object(
    'assumida_sem_prazo_mostrado', (select count(*) from public.agenda_perguntas q
                                     where q.assumida_por = 'prazo'
                                       and not coalesce(q.veto_ate is not null and q.mostrada_vezes > 0 and q.mostrada_em < q.veto_ate, false)),
    'assumida_que_esperava', (select count(*) from public.agenda_perguntas q where q.assumida_por is not null and q.veto_espera is not null),
    'assumida_tipo_proibido', (select count(*) from public.agenda_perguntas q where q.assumida_por is not null and q.tipo = any (c_nunca)),
    'teto_passou_sem_motivo', case when v_acima = 0 or public._agenda_fala_modo('veto') <> 'ligado' then 0 else
       least(v_acima, (select count(*)::int from public.agenda_perguntas x
                        where x.estado = 'aberta' and x.modo = 'ligado' and x.tipo <> 'conferencia' and (x.expira_em is null or x.expira_em > p_agora)
                          and x.padrao_efeito = 'nada' and x.opcao_escolhida is null and x.criada_em < v_ult
                          and public._agenda_pergunta_espera(x, p_hoje) is null)) end,
    'bloco_grande', coalesce(v_bgrande, 0),
    'excecao_acima_do_teto', greatest(- public._agenda_lote_cota(p_hoje), 0));
  -- FASE 7f: (7f P9, §11 aceites 6 e 7; NOVO-agenda-131 e 138) os zeros da equipe e do cliente, que entram no zeros_ok (e por ele no ok de agenda_saude). Só o que
  -- a 7f manda de verdade (ligado): em teste nada conta. Hoje 0 em produção (sql/wf7f9_zeros, dom 08/11). A equipe: o previsto, a mudança e o convite fora da janela
  -- ou no domingo; o dia com mais que equipe_proativas_dia_max mensagens de quem recebeu alguma da 7f; a ficha do dia com convite sem o SIM antes dela (AG7-23); mais
  -- de uma mudança das 19:30 por pessoa e dia. O cliente: o dia exato (o M1 e o M3 marcados pela estimativa) antes de cliente_dia_exato_du dias úteis do dia, ao
  -- cliente que ouviu a semana daquele dia; a semana que mudou enviada sem o *manda cliente*; a semana como dia ouvido (firme)
  v_z := v_z || jsonb_build_object(
    'equipe_fora_da_janela', (select count(*) from public.agenda_equipe_mensagens e
                               where e.tipo in ('previsto', 'mudanca', 'convite') and e.modo = 'ligado' and e.estado in ('enfileirada', 'respondida', 'sem_resposta')
                                 and (extract(isodow from e.enviar_em at time zone 'America/Sao_Paulo') = 7
                                      or (e.enviar_em at time zone 'America/Sao_Paulo')::time < cf.equipe_janela_inicio
                                      or (e.enviar_em at time zone 'America/Sao_Paulo')::time > cf.equipe_janela_fim)),
    'equipe_acima_do_teto', (select count(*) from (select e.payee_id from public.agenda_equipe_mensagens e
                                                    where e.modo = 'ligado' and e.tipo <> 'resposta' and e.estado in ('enfileirada', 'respondida', 'sem_resposta')
                                                    group by e.payee_id, (e.enviar_em at time zone 'America/Sao_Paulo')::date
                                                   having count(*) > cf.equipe_proativas_dia_max and bool_or(e.tipo in ('previsto', 'mudanca', 'convite'))) g),
    'ficha_sem_sim', (select count(*) from public.agenda_equipe_mensagens f
                       where f.tipo = 'ficha' and f.modo = 'ligado' and f.estado in ('enfileirada', 'respondida', 'sem_resposta')
                         and exists (select 1 from public.agenda_equipe_mensagens c
                                      where c.tipo = 'convite' and c.modo = 'ligado' and c.payee_id = f.payee_id and c.dia = f.dia and c.estado <> 'recusada'
                                        and c.criada_em <= f.enviar_em
                                        and not coalesce(c.leitura ->> 'convite' = 'sim' and c.resposta_em <= f.enviar_em, false))),
    'mudanca_19h_repetida', (select count(*) from (select 1 from public.agenda_equipe_mensagens e
                                                    where e.tipo = 'mudanca' and e.modo = 'ligado' and e.dedupe_key like '%:19h' and e.estado <> 'recusada'
                                                    group by e.payee_id, (e.enviar_em at time zone 'America/Sao_Paulo')::date having count(*) > 1) g),
    'dia_exato_cedo', (select count(*) from public.agenda_cliente_mensagens m
                        where m.tipo in ('confirmar', 'material_chegou') and m.modo = 'ligado' and m.enviada_em is not null and m.dia_alvo is not null
                          and coalesce((m.base #>> '{dados,por_estimativa}')::boolean, false)
                          and exists (select 1 from public.agenda_cliente_mensagens s
                                       where s.service_order_id = m.service_order_id and s.tipo = 'semana' and s.modo = 'ligado' and s.enviada_em is not null
                                         and s.enviada_em < m.enviada_em and m.dia_alvo between s.faixa_de and s.faixa_ate)
                          and (m.enviada_em at time zone 'America/Sao_Paulo')::date < public.agenda_somar_du(m.dia_alvo, - cf.cliente_dia_exato_du)),
    'promessa_mudou_sem_dono', (select count(*) from public.agenda_cliente_mensagens m
                                 where m.tipo = 'semana' and m.variante = 'mudou' and m.enviada_em is not null and m.aprovacao is distinct from 'aprovada'),
    'semana_como_dia_ouvido', (select count(*) from public.agenda_cliente_mensagens m where m.tipo = 'semana' and m.prometido_tipo = 'firme')
                              + (select count(*) from public.os_planejamento p join public.agenda_cliente_mensagens m on m.id = p.prometido_mensagem_id
                                  where m.tipo = 'semana' and p.prometido_tipo = 'firme'));
  -- FASE 7f: fim

  if v_algum then
    v_n := jsonb_build_object(
      'perguntas', (select jsonb_build_object(
                             'abertas', v_abertas, 'teto', cf.perguntas_abertas_max, 'acima_do_teto', v_acima,
                             'com_prazo', count(*) filter (where q.estado = 'aberta' and q.veto_ate is not null and q.veto_espera is null),
                             'esperam_voce', count(*) filter (where q.estado = 'aberta' and q.veto_espera = 'dono'),
                             'respondidas_semana', count(*) filter (where q.estado = 'respondida' and q.assumida_por is null
                                                                     and q.respondida_em > p_agora - make_interval(days => c_semana)),
                             'assumidas_prazo_semana', count(*) filter (where q.assumida_por = 'prazo' and q.assumida_em > p_agora - make_interval(days => c_semana)),
                             'assumidas_teto_semana', count(*) filter (where q.assumida_por = 'teto' and q.assumida_em > p_agora - make_interval(days => c_semana)),
                             'teria_semana', count(*) filter (where q.veto_teria_em > p_agora - make_interval(days => c_semana)))
                      from public.agenda_perguntas q where q.modo = 'ligado')
                   || jsonb_build_object(
                        'idade_media_du', (select round(avg((select count(*) from generate_series((x.criada_em at time zone 'America/Sao_Paulo')::date + 1, p_hoje, interval '1 day') d
                                                              where public.agenda_dia_util(d::date)))::numeric, 1)
                                             from public.agenda_perguntas x
                                            where x.estado = 'aberta' and x.modo = 'ligado' and x.tipo <> 'conferencia' and (x.expira_em is null or x.expira_em > p_agora)),
                        'complacencia', (select jsonb_build_object('assumidas', count(*),
                                                                   'desfeitas', count(*) filter (where exists (select 1 from public.agenda_acoes a
                                                                                                                where a.pergunta_id = q.id and a.desfeita_em is not null)))
                                           from public.agenda_perguntas q
                                          where q.assumida_por = 'prazo' and q.assumida_em > p_agora - make_interval(days => c_quinze))),
      'excecoes', jsonb_build_object(
        'hoje', (select count(*) from public.agenda_dono_avisos v where v.dia = p_hoje and v.fila_id is not null and v.dedupe_key like 'agenda-dono:excecao:%'),
        'cota_livre', greatest(public._agenda_lote_cota(p_hoje), 0),
        'acima_da_cota_hoje', (select count(distinct x) from public.agenda_vigia_rodadas r
                                 cross join lateral jsonb_array_elements_text(coalesce(r.contagens #> '{lote_guardaria,acima_da_cota_ids}', '[]'::jsonb)) x
                                where r.rotina = 'comunicar' and r.p_hoje = p_hoje),
        'em_sombra_hoje', (select jsonb_build_object('avisos', count(*),
                                                     'levaria', coalesce(sum((r.contagens #>> '{lote_guardaria,levaria,acoes}')::int), 0),
                                                     'guardaria', coalesce(sum((r.contagens #>> '{lote_guardaria,guardaria,acoes}')::int), 0),
                                                     'guardaria_perguntas', coalesce(sum((r.contagens #>> '{lote_guardaria,guardaria,perguntas}')::int), 0),
                                                     'acima_da_cota', coalesce(sum((r.contagens #>> '{lote_guardaria,acima_da_cota}')::int), 0))
                             from public.agenda_vigia_rodadas r
                            where r.rotina = 'comunicar' and r.p_hoje = p_hoje and r.contagens #> '{lote_guardaria,aviso}' is not null)),
      'quinta', jsonb_build_object(
        'saiu', (select jsonb_build_object('dia', v.dia, 'estado', v.estado, 'enviada_em', v.enviada_em,
                                           'mudancas', cardinality(v.acao_ids), 'perguntas', cardinality(v.pergunta_ids))
                   from public.agenda_dono_avisos v
                  where v.dedupe_key like 'agenda-dono:semana:%' and v.dia between p_hoje - c_semana + 1 and p_hoje
                  order by v.dia desc limit 1),
        'diria', (select jsonb_build_object('dia', r.p_hoje, 'caracteres', (r.contagens #>> '{quinta,quinta_diria,caracteres}')::int,
                                            'cabe', (r.contagens #>> '{quinta,quinta_diria,cabe}')::boolean, 'motivo', r.contagens #>> '{quinta,quinta_diria,motivo}',
                                            'mudancas', (r.contagens #>> '{quinta,quinta_diria,mudancas}')::int, 'perguntas', (r.contagens #>> '{quinta,quinta_diria,perguntas}')::int)
                    from public.agenda_vigia_rodadas r
                   where r.rotina = 'comunicar' and r.p_hoje between p_hoje - c_semana + 1 and p_hoje and r.contagens #> '{quinta,quinta_diria}' is not null
                   order by r.p_agora desc limit 1)),
      'bloco', v_bloco,
      'mensagens_hoje', (select jsonb_build_object('fechamento', count(*) filter (where f.source = 'ai_briefing_tarde'),
                                                   'aviso', count(*) filter (where f.source = 'agenda-dono'),
                                                   'acorde', count(*) filter (where f.source = 'agenda'),
                                                   'alvo', c_lotes + cf.acordes_dia_max)
                           from public.whatsapp_send_queue f
                          where f.source in ('ai_briefing_tarde', 'agenda-dono', 'agenda') and f.status not in ('failed', 'cancelled')
                            and f.created_at >= (p_hoje::timestamp at time zone 'America/Sao_Paulo')
                            and f.created_at < ((p_hoje + 1)::timestamp at time zone 'America/Sao_Paulo')));
  end if;

  -- FASE 7f: (7f P9, §11 "Métricas": equipe e cliente, por semana) os números, como os de antes, só com o modo deles fora de desligado. Em teste conta o que foi
  -- registrado (em_teste); de verdade, o que saiu e o que voltou. Só contagens
  if cf.modo_equipe_previsto <> 'desligado' or cf.modo_equipe_convite <> 'desligado' then
    v_n := v_n || jsonb_build_object('equipe', (
      select jsonb_build_object(
               'previstos', count(*) filter (where e.tipo = 'previsto' and e.modo = 'ligado' and e.estado <> 'recusada'),
               'mudancas', count(*) filter (where e.tipo = 'mudanca' and e.modo = 'ligado' and e.estado <> 'recusada'),
               'mudancas_19h', count(*) filter (where e.tipo = 'mudanca' and e.modo = 'ligado' and e.estado <> 'recusada' and e.dedupe_key like '%:19h'),
               'convites', count(*) filter (where e.tipo = 'convite' and e.modo = 'ligado' and e.estado <> 'recusada'),
               'convites_sim', count(*) filter (where e.tipo = 'convite' and e.modo = 'ligado' and e.leitura ->> 'convite' = 'sim'),
               'convites_nao', count(*) filter (where e.tipo = 'convite' and e.modo = 'ligado' and e.leitura ->> 'convite' = 'nao'),
               'convites_sem_resposta', count(*) filter (where e.tipo = 'convite' and e.modo = 'ligado' and e.estado = 'sem_resposta'),
               'recusadas', count(*) filter (where e.modo = 'ligado' and e.estado = 'recusada'),
               'em_teste', count(*) filter (where e.modo = 'sombra'),
               'nao_depois_de_mudanca', (select count(*) from public.agenda_disponibilidade d
                                          where d.origem = 'diarista' and d.situacao = 'indisponivel' and d.substituida_em is null
                                            and d.criado_em > p_agora - make_interval(days => c_semana)
                                            and exists (select 1 from public.agenda_equipe_mensagens x
                                                         where x.payee_id = d.payee_id and x.tipo in ('mudanca', 'convite') and x.modo = 'ligado'
                                                           and x.estado <> 'recusada' and x.criada_em < d.criado_em
                                                           and (d.periodo @> x.dia or exists (select 1 from unnest(coalesce(x.dias, '{}'::date[])) u(dia) where d.periodo @> u.dia)))))
        from public.agenda_equipe_mensagens e
       where e.tipo in ('previsto', 'mudanca', 'convite') and e.criada_em > p_agora - make_interval(days => c_semana)));
  end if;
  if cf.modo_cliente_camadas <> 'desligado' then
    v_n := v_n || jsonb_build_object('cliente', (
      select jsonb_build_object(
               'semanas', jsonb_build_object(
                 'registradas', count(*) filter (where m.tipo = 'semana' and m.variante is distinct from 'mudou' and m.modo = 'ligado'),
                 'enviadas', count(*) filter (where m.tipo = 'semana' and m.variante is distinct from 'mudou' and m.modo = 'ligado' and m.enviada_em is not null),
                 'seguradas', count(*) filter (where m.tipo = 'semana' and m.variante is distinct from 'mudou' and m.aprovacao = 'segurada'),
                 'vencidas', count(*) filter (where m.tipo = 'semana' and m.variante is distinct from 'mudou' and m.aprovacao = 'vencida'),
                 'em_teste', count(*) filter (where m.tipo = 'semana' and m.variante is distinct from 'mudou' and m.modo = 'sombra')),
               'semana_mudou', jsonb_build_object(
                 'registradas', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.modo = 'ligado'),
                 'mandadas', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.aprovacao = 'aprovada'),
                 'seguradas', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.aprovacao = 'segurada'),
                 'vencidas', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.aprovacao = 'vencida'),
                 'enviadas', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.enviada_em is not null),
                 'em_teste', count(*) filter (where m.tipo = 'semana' and m.variante = 'mudou' and m.modo = 'sombra')),
               'mudancas_ao_cliente', count(*) filter (where m.modo = 'ligado' and m.enviada_em is not null
                                                         and (m.tipo in ('pode_atrasar', 'nova_data', 'mudanca_no_dia') or (m.tipo = 'semana' and m.variante = 'mudou'))))
        from public.agenda_cliente_mensagens m
       where m.criada_em > p_agora - make_interval(days => c_semana)));
  end if;
  -- FASE 7f: fim
  return jsonb_build_object(
    'modos', v_modos, 'freio', cf.gestor_so_propor,
    'ultima_rodada', v_ult, 'rodadas_24h', coalesce(v_rod24, 0),
    'erros_24h', (select count(*) from public.app_error_logs e
                   where e.context = 'agenda' and e.action like 'comunicar:%' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'falhas_lote_guardaria_24h', (select count(*) from public.app_error_logs e
                                   where e.context = 'agenda' and e.action = 'comunicar:lote_guardaria' and e.last_seen_at >= least(p_agora, now()) - interval '1 day'),
    'zeros_ok', not exists (select 1 from jsonb_each(v_z) z where (z.value)::text <> '0'),
    'numeros', v_n) || v_z;
end;
$function$;

comment on function public._agenda_saude_comunicacao(date, timestamptz) is
  'Agenda de Produção (Fase 7f, P7; §11, R8.5-27, R8.5-29, R8.6): a saúde da comunicação — {modos (os 6, crus), freio, ultima_rodada e rodadas_24h (rotina comunicar), erros_24h (comunicar:%), falhas_lote_guardaria_24h, zeros_ok, numeros} e os zeros: assumida_sem_prazo_mostrado, assumida_que_esperava, assumida_tipo_proibido, teto_passou_sem_motivo, bloco_grande, excecao_acima_do_teto. numeros só com algum modo fora de desligado: perguntas (abertas, teto, com prazo, esperam você, respondidas, assumidas por prazo e por teto, teria, idade média em dias úteis, complacência de 2 semanas), excecoes (hoje, cota livre, os ids distintos acima da cota; em sombra o que o lote levaria e guardaria), quinta (a que saiu; em sombra a que diria), bloco (resumo_tarde de 7 dias), mensagens_hoje por origem (aviso = agenda-dono, acorde = agenda; só contagens). A porta de _agenda_saude_local: administrador, financeiro ou service_role; o resto 42501. FASE 7f (P9): os zeros da equipe (equipe_fora_da_janela, equipe_acima_do_teto, ficha_sem_sim, mudanca_19h_repetida; aceite 6) e do cliente (dia_exato_cedo, promessa_mudou_sem_dono, semana_como_dia_ouvido; aceite 7), só do que a 7f manda de verdade, no zeros_ok; numeros.equipe (com o previsto ou o convite fora de desligado: previstos, mudanças, convites com SIM, NÃO e sem resposta, recusadas, em teste, "não vou" depois de mudança ou convite, na semana) e numeros.cliente (com as camadas fora de desligado: as semanas registradas, enviadas, seguradas, vencidas e em teste, a semana que mudou mandada, segurada, vencida e enviada, e as mudanças que chegaram ao cliente, na semana). PRAZO NO BLOCO (17/11/2026, 20270122100000; plano perguntas-com-prazo-1711, F1, revisão): bloco_grande não conta o fechamento que está no mínimo do bloco com a linha das perguntas do gestor: no mínimo ficam a 1ª decisão, a do gestor e a do cliente. A tolerância é as fixas + 1 (no nivel_min só ficam as decisões que nunca saem, sem o "(e mais N)"; o +1 é o nível logo acima, com ele): a de antes, 2 (a 1ª e mais 1), ganha +1 com a 1ª numerada (uma crítica antes da do gestor) e +1 com a do cliente à vista. A do gestor está no fechamento quando a (m) ligada de perda 76 está em detalhe.agenda.linhas_diria e uma decisão à vista é a forma inteira dela (o texto sem o "Agenda: ", com os espaços juntados) ou a curta (que começa pelo trecho da ficha antes de " 1) Mande" e " Para segurar, me diga.", ou por "Sem resposta até …, conto: "); a do cliente, quando a linha cliente ligada de linhas_diria, escrita como o bloco a escreve (_agenda_corta, 220), é igual a uma decisão à vista (uma cliente_aprovar da ordem não conta). Sem a do gestor à vista, a conta de antes. FICHA PAGA B (18/11/2026, 20270126100000; C4 da revisão da F2): no bloco_grande, a curta da ficha de OS paga ("… eu seguro a ficha. Para mandar, me diga *mande*.", da 20270125100000) conta como a do gestor, como a "Para segurar, me diga.".';

-- ── 7. A resposta da equipe: "o que tem pra amanhã?" com a ficha segurada (P2) ──────────────────────────
-- agenda_resposta_da_equipe (de 20261109101000 (produção em 18/11); md5 do corpo de antes f572cd9e2068d952b3c862be24c9d46a sem CR)
create or replace function public.agenda_resposta_da_equipe(p_phone text, p_body text, p_message_id text,
                                                            p_recebida_em timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_hoje   date := (p_recebida_em at time zone 'America/Sao_Paulo')::date;
  v_hora   time := (p_recebida_em at time zone 'America/Sao_Paulo')::time;
  v_ids    uuid[];
  v_payee  uuid;
  v_nome   text;
  v_l      jsonb;
  v_tipo   text;
  m        public.agenda_equipe_mensagens%rowtype;
  v_recibo timestamptz;
  v_trecho text := left(btrim(coalesce(p_body, '')), 500);
  v_wa     text := nullif(btrim(coalesce(p_message_id, '')), '');
  v_dia    date;
  v_f      jsonb;
  v_r      jsonb;
  v_os     uuid[];
  v_disp   uuid;
  v_rep    jsonb;
  v_acao   uuid;
  v_plano  text[];
  v_ditos  text[];
  v_conf   text[];
  v_term   boolean;
  v_ent    boolean;
  v_estado text;
  v_msg    text;
  v_resp   text;
  v_div    boolean;
  -- FASE 7b: (7b P3, §5.2; A1, A3) a pergunta dos dias da semana: a mensagem aberta dela, a leitura, a gravação e a resposta
  v_7b_mq   public.agenda_equipe_mensagens%rowtype;
  v_7b_vd   jsonb;
  v_7b_g    jsonb;
  v_7b_resp text;
  v_7b_ult  boolean;
  v_7b_sem  text;
  v_7b_dias smallint[];
  v_7b_sab  boolean;
  -- FASE 7b: fim
  -- FASE 7c: (7c P8) as etapas no "como foi"
  v_p8_dp    jsonb;
  v_p8_lista jsonb;
  v_p8_lt    jsonb;
  v_p8_its   jsonb;
  v_p8_parc  jsonb := '{}'::jsonb;
  v_p8_conf  text[];
  v_p8_os    text;
  v_p8_tu    text[];
  -- FASE 7c: fim
  -- FASE 7f: (7f P5) o convite, o previsto e a mudança
  v_7f_cv    public.agenda_equipe_mensagens%rowtype;
  v_7f_x     uuid;
  v_7f_plano text[];
  v_7f_sim   boolean;
  v_7f_resp  text;
  -- FASE 7f: fim
  -- FICHA PAGA B: (18/11/2026) a pergunta "o que tem" com a ficha segurada
  v_fb_resp text;
  v_fb_os   uuid[];
  v_fb_pg   uuid[];
  -- FICHA PAGA B: fim
begin
  if v_trecho = '' or p_recebida_em is null then
    return jsonb_build_object('consumiu', false);
  end if;
  -- desligado: nada lê (o webhook segue como sempre)
  if cf.modo_equipe = 'desligado' then
    return jsonb_build_object('consumiu', false, 'modo', 'desligado');
  end if;
  v_ids := public._agenda_payees_do_telefone(p_phone, v_hoje);
  if cardinality(v_ids) > 1 then
    perform public.log_app_error('db', 'agenda: o telefone de uma mensagem é de mais de uma pessoa da equipe; não li a resposta',
                                 'agenda', 'equipe:telefone', 'warn', jsonb_build_object('payees', to_jsonb(v_ids)));
    return jsonb_build_object('consumiu', false, 'motivo', 'ambiguo');
  end if;
  if cardinality(v_ids) = 0 then
    return jsonb_build_object('consumiu', false);
  end if;
  v_payee := v_ids[1];
  v_nome := (select public._agenda_nome_curto(p.name) from public.payees p where p.id = v_payee);
  -- a mesma mensagem dele de novo: nada muda
  if v_wa is not null and exists (select 1 from public.agenda_equipe_mensagens x
                                   where x.payee_id = v_payee and (x.resposta_wa_id = v_wa or x.responde_wa_id = v_wa)) then
    return jsonb_build_object('consumiu', exists (select 1 from public.agenda_equipe_mensagens x
                                                   where x.payee_id = v_payee and x.modo = 'ligado'
                                                     and (x.resposta_wa_id = v_wa or x.responde_wa_id = v_wa)),
                              'repetida', true);
  end if;

  -- FASE 7b: (7b P3, §5.2 item 1) a pergunta dos dias da semana aberta — ligada, enfileirada, mandada antes desta mensagem e com o
  -- prazo da semana por vir (a quinta que planeja a semana, hora_do_plano − equipe_dias_fechar_antes) — e a leitura dela, sem IA. Só
  -- com a pergunta dos dias ligada (modo_dias): em teste ela nunca sai, e nada daqui muda.
  if cf.modo_dias = 'ligado' then
    select * into v_7b_mq from public.agenda_equipe_mensagens x
     where x.payee_id = v_payee and x.tipo = 'dias' and x.modo = 'ligado' and x.estado = 'enfileirada'
       and x.enviar_em <= p_recebida_em
       and p_recebida_em < (((x.dia - 7 + (cf.dia_do_plano - 1)) + cf.hora_do_plano) - cf.equipe_dias_fechar_antes)
                           at time zone 'America/Sao_Paulo'
     order by x.enviar_em desc, x.criada_em desc limit 1;
    if v_7b_mq.id is not null then
      v_7b_vd := public._agenda_ler_dias_da_equipe(p_body);
    end if;
  end if;
  -- FASE 7b: fim
  v_l := public._agenda_ler_resposta_da_equipe(p_body);
  v_tipo := v_l ->> 'tipo';
  -- a quem ele responde: a última que o sistema começou (ligado, enfileirada, dentro da validade)
  select * into m from public.agenda_equipe_mensagens x
   where x.payee_id = v_payee and x.tipo <> 'resposta' and x.modo = 'ligado' and x.estado = 'enfileirada'
     -- FASE 7b: (7b P3, §5.2 item 2) a pergunta dos dias da semana não é a mensagem a que ele responde no resto (ela tem o ramo dela)
     and x.tipo <> 'dias'
     -- FASE 7b: fim
     and x.enviar_em <= p_recebida_em and x.enviar_em >= p_recebida_em - cf.equipe_resposta_validade
   order by x.enviar_em desc, x.criada_em desc limit 1;
  -- FASE 7f: (7f P5, §5.5, AG7-23) o convite vale até o prazo dele (a ficha da véspera), não só equipe_resposta_validade: o aberto e mais novo que a
  -- mensagem de cima é a mensagem a que ele responde (a última que o sistema começou, como sempre).
  select * into v_7f_cv from public.agenda_equipe_mensagens x
   where x.payee_id = v_payee and x.tipo = 'convite' and x.modo = 'ligado' and x.estado = 'enfileirada' and x.enviar_em <= p_recebida_em
     and public._agenda_equipe_convite_prazo(x.dia) > p_recebida_em
   order by x.enviar_em desc, x.criada_em desc limit 1;
  if v_7f_cv.id is not null and (m.id is null or v_7f_cv.enviar_em > m.enviar_em) then
    m := v_7f_cv;
  end if;
  -- FASE 7f: fim
  -- o recibo das diárias mandado depois dela: o "ok" é do recibo (NOVO-agenda-17); a pergunta é sempre da agenda
  select max(a.enviado_ao_freelancer_em) into v_recibo
    from public.acertos_diarias a
   where a.favorecido_id = v_payee and a.status = 'fechado' and a.conferido_em is null
     and a.enviado_ao_freelancer_em > p_recebida_em - interval '7 days' and a.enviado_ao_freelancer_em <= p_recebida_em;
  if v_tipo <> 'pergunta' and v_recibo is not null and (m.id is null or v_recibo > m.enviar_em) then
    return jsonb_build_object('consumiu', false, 'motivo', 'recibo');
  end if;
  -- FASE 7b: (7b P3, §5.2 item 3; A1 = NOVO-agenda-52, A3 = NOVO-agenda-54) a resposta à pergunta dos dias da semana, antes da
  -- pergunta, do "não vou" e do "como foi":
  --   · os dias ou "nenhum" (em qualquer ordem: a frase com os dias é sobre a semana) gravam a semana presa — e o padrão de quem tem —
  --     pelo _agenda_equipe_dias_gravar (origem diarista; a exceção do dono no dia vence e volta em conflitos) e respondem
  --     "Anotei: …" (§6.1);
  --   · "igual" (ou "ok") com a pergunta por último: nada gravado, "Anotei: semana de 16/11 igual (de seg a sex). Obrigado!";
  --   · não entendi com a pergunta por último, e a leitura geral não é pergunta, presença nem turnos (o "não vou" junto de um dia da
  --     semana também: "segunda não posso" é sobre a semana, A3): na 1ª vez, "Não entendi os dias da semana de 16/11. …"; na 2ª, a
  --     pergunta equipe_resposta ao dono, e a mensagem fica respondida.
  -- Fora disso, o de antes (a mensagem a que ele responde é a última que o sistema começou, fora a pergunta da semana).
  if v_7b_mq.id is not null then
    v_7b_ult := v_7b_mq.enviar_em > coalesce(m.enviar_em, '-infinity'::timestamptz);
    v_7b_sem := to_char(v_7b_mq.dia, 'DD/MM');
    -- (correção da revisão da 7b, achado 8) a resposta só é da pergunta da semana quando ela é a última mensagem que o sistema
    -- mandou a ele (v_7b_ult), quando a frase fala da semana, ou quando é só a lista dos dias (o formato que a pergunta pede: "seg ter qui",
    -- "nenhum") e a leitura de sempre não a entende. Com a ficha, a confirmação ou o "como foi" mandados depois dela, "não posso", "ok,
    -- sexta tô lá", "sim, todos prontos" e "terminei todos" são a resposta a essas (o caminho de antes) e a pergunta da semana continua
    -- aberta: antes, viravam os dias da semana (e o padrão dele), e a falta de amanhã ficava sem replano.
    if not v_7b_ult and v_7b_vd ->> 'tipo' in ('dias', 'nenhum')
       and not (public._agenda_normal(p_body) ~ '\msemana\M')
       and not (v_tipo = 'nao_entendi'
                and btrim(regexp_replace(public._agenda_normal(p_body),
                                         '\m(segunda|terca|quarta|quinta|sexta|sabado|seg|ter|qua|qui|sex|sab|feira|nenhum|nenhuma|dia|dias|e|a|ate|so|somente|apenas|posso|consigo|vou|venho|todos|todo|toda|na|no|nos|de|do|da)s?\M',
                                         '', 'g')) = '') then
      v_7b_vd := v_7b_vd || jsonb_build_object('tipo', 'outra_mensagem');
    end if;
    -- (correção da revisão da 7b: fim)
    if v_7b_vd ->> 'tipo' in ('dias', 'nenhum') then
      v_7b_dias := array(select y::smallint from jsonb_array_elements_text(coalesce(v_7b_vd -> 'dias', '[]'::jsonb)) y);
      v_7b_sab := coalesce((v_7b_vd ->> 'sabado')::boolean, false);
      v_7b_g := public._agenda_equipe_dias_gravar(v_payee, v_7b_mq.dia, v_7b_dias, v_7b_sab, 'diarista', v_trecho, p_recebida_em,
                                                  v_7b_mq.id);
      v_7b_resp := case when cardinality(v_7b_dias) = 0 and not v_7b_sab
                        then format('Anotei: na semana de %s você não pode. Obrigado por avisar!', v_7b_sem)
                        else format('Anotei: na semana de %s você pode %s. Obrigado!', v_7b_sem,
                                    public._agenda_dias_curtos(v_7b_dias, v_7b_sab)) end;
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
             leitura = v_7b_vd || jsonb_build_object('mudou', v_7b_g -> 'mudou', 'padrao_mudou', v_7b_g -> 'padrao_mudou',
                                                     'conflitos', coalesce(v_7b_g -> 'conflitos', '[]'::jsonb))
       where id = v_7b_mq.id;
      v_r := public._agenda_equipe_registrar(v_payee, v_7b_mq.dia, 'resposta', v_7b_resp, p_recebida_em, null,
                                             coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
      return jsonb_build_object('consumiu', true, 'tipo', 'dias', 'leitura', v_7b_vd ->> 'tipo', 'mudou', v_7b_g -> 'mudou',
                                'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_7b_resp end, 'envio', v_r ->> 'estado');
    end if;
    if v_7b_vd ->> 'tipo' = 'igual' and v_7b_ult then
      v_7b_resp := format('Anotei: semana de %s igual (%s). Obrigado!', v_7b_sem,
                          public._agenda_dias_declarados(v_payee, v_7b_mq.dia) ->> 'texto');
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa, leitura = v_7b_vd
       where id = v_7b_mq.id;
      v_r := public._agenda_equipe_registrar(v_payee, v_7b_mq.dia, 'resposta', v_7b_resp, p_recebida_em, null,
                                             coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
      return jsonb_build_object('consumiu', true, 'tipo', 'dias', 'leitura', 'igual',
                                'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_7b_resp end, 'envio', v_r ->> 'estado');
    end if;
    if v_7b_vd ->> 'tipo' = 'nao_entendi' and v_7b_ult
       and (v_tipo not in ('pergunta', 'nao_vou', 'presenca', 'turnos')
            or (v_tipo = 'nao_vou'
                and public._agenda_normal(p_body) ~ '\m(segunda|terca|quarta|quinta|sexta|sabado|seg|ter|qua|qui|sex|sab)s?\M')) then
      if coalesce((v_7b_mq.leitura ->> 'nao_entendi')::int, 0) = 0 then
        v_7b_resp := format('Não entendi os dias da semana de %s. Mande só os dias, assim: seg ter qui (ou "nenhum").', v_7b_sem);
        update public.agenda_equipe_mensagens
           set leitura = coalesce(leitura, '{}'::jsonb)
                         || jsonb_build_object('nao_entendi', 1, 'trecho', v_trecho, 'recebida_em', p_recebida_em)
         where id = v_7b_mq.id;
        v_r := public._agenda_equipe_registrar(v_payee, v_7b_mq.dia, 'resposta', v_7b_resp, p_recebida_em, null,
                                               'dias:' || v_7b_mq.dia);
        return jsonb_build_object('consumiu', true, 'tipo', 'dias', 'leitura', 'nao_entendi', 'vez', 1,
                                  'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_7b_resp end, 'envio', v_r ->> 'estado');
      end if;
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:dias', v_payee, v_7b_mq.dia), v_payee,
        null, v_7b_mq.dia,
        format('%s respondeu "%s" à pergunta dos dias da semana de %s, e eu não entendi. Diga os dias dele (ex.: %s vem seg e ter na semana de %s).',
               v_nome, public._agenda_corta(v_trecho, 120), v_7b_sem, v_nome, v_7b_sem),
        'ligado', p_recebida_em);
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
             leitura = coalesce(v_7b_mq.leitura, '{}'::jsonb) || v_7b_vd || jsonb_build_object('nao_entendi', 2)
       where id = v_7b_mq.id;
      return jsonb_build_object('consumiu', true, 'tipo', 'dias', 'leitura', 'nao_entendi', 'vez', 2, 'resposta', null);
    end if;
  end if;
  -- FASE 7b: fim

  -- ── pergunta: a ficha do publicado, sem valores (em sombra só registra) ──────────────────────────────
  if v_tipo = 'pergunta' then
    v_dia := case when v_l ->> 'dia' = 'amanha' then v_hoje + 1 else v_hoje end;
    -- FICHA PAGA B: (18/11/2026, 20270126100000; P2 do dono) com a mensagem à equipe ligada e a ficha desse dia segurada
    -- (_agenda_ficha_liberada falso: OS paga sem o *mande*, OS concluída, faturada ou cancelada, ou o dia pela estimativa ainda sem a
    -- pergunta mostrada ao dono), a resposta não diz o plano: "Vou ver com Gustavo e te falo." (o nome curto do dono, de _agenda_dono),
    -- e a pergunta equipe_resposta ao dono diz quem perguntou e por que a ficha está segurada. Desligado, em teste ou com a ficha
    -- liberada: o de antes.
    if cf.modo_equipe = 'ligado' and not public._agenda_ficha_liberada(v_payee, v_dia, p_recebida_em) then
      v_fb_resp := format('Vou ver com %s e te falo.',
                          coalesce((select public._agenda_nome_curto(py.name) from public.payees py where py.id = public._agenda_dono(null)),
                                   'o responsável'));
      v_fb_os := public._agenda_ficha_os_concluidas(v_payee, v_dia);
      v_fb_pg := public._agenda_ficha_os_pagas(v_payee, v_dia);
      v_r := public._agenda_equipe_registrar(v_payee, v_dia, 'resposta', v_fb_resp, p_recebida_em, null,
                                             coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
      if v_r ? 'id' then
        update public.agenda_equipe_mensagens
           set leitura = v_l || jsonb_build_object('pergunta', v_trecho, 'recebida_em', p_recebida_em, 'ficha_segurada', true)
         where id = (v_r ->> 'id')::uuid;
      end if;
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:pergunta', v_payee, v_dia), v_payee,
        null, v_dia,
        format('O %s perguntou o que tem %s, e a ficha dele está segurada: %s. Diga a ele o que fazer.', v_nome,
               case when v_dia = v_hoje then 'hoje' else 'amanhã (' || public._dia_curto(v_dia) || ')' end,
               case when cardinality(v_fb_os) > 0
                      then case when cardinality(v_fb_os) = 1 then 'a ' else 'as ' end
                           || public._agenda_lista(array(select so.service_order_number from unnest(v_fb_os) with ordinality u(os, o)
                                                          join public.service_orders so on so.id = u.os order by u.o), null)
                           || case when cardinality(v_fb_os) = 1 then ' já está ' else ' já estão ' end
                           || public._agenda_ficha_os_concluidas_texto(v_fb_os)
                    when cardinality(v_fb_pg) > 0
                      then case when cardinality(v_fb_pg) = 1 then 'a ' else 'as ' end
                           || public._agenda_lista(array(select so.service_order_number from unnest(v_fb_pg) with ordinality u(os, o)
                                                          join public.service_orders so on so.id = u.os order by u.o), null)
                           || case when cardinality(v_fb_pg) = 1 then ' já está paga' else ' já estão pagas' end
                           || ' e você não disse *mande*'
                    else 'o dia é pela minha estimativa e a pergunta da ficha ainda não foi vista (ou você a segurou)' end),
        'ligado', p_recebida_em);
      return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'ficha_segurada', true,
                                'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_fb_resp end,
                                'envio', v_r ->> 'estado');
    end if;
    -- FICHA PAGA B: fim
    v_f := public.agenda_equipe_ficha(v_payee, v_dia, v_hoje);
    v_r := public._agenda_equipe_registrar(v_payee, v_dia, 'resposta', v_f ->> 'texto_resposta', p_recebida_em, null,
                                           coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
    if v_r ? 'id' then
      update public.agenda_equipe_mensagens
         set leitura = v_l || jsonb_build_object('pergunta', v_trecho, 'recebida_em', p_recebida_em)
       where id = (v_r ->> 'id')::uuid;
    end if;
    if not coalesce((v_f ->> 'tem_plano')::boolean, false) and public.agenda_dia_util(v_dia) then
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:pergunta', v_payee, v_dia), v_payee,
        null, v_dia, format('O %s perguntou o que tem %s e ainda não tem plano para ele. Diga a ele o que fazer.', v_nome,
                            case when v_dia = v_hoje then 'hoje' else 'amanhã (' || public._dia_curto(v_dia) || ')' end),
        case when cf.modo_equipe = 'ligado' then 'ligado' else 'sombra' end, p_recebida_em);
    end if;
    return jsonb_build_object('consumiu', cf.modo_equipe = 'ligado', 'tipo', v_tipo,
                              'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_f ->> 'texto_resposta' end,
                              'envio', v_r ->> 'estado');
  end if;

  -- FASE 7f: (7f P5, §5.5, §6.4, AG7-23, E5, E6) antes do "não vou":
  --   · o NÃO ao convite é o "não vou" do dia do convite: o caminho de baixo, com a mensagem tratada como a ficha daquele dia (m.tipo só aqui, na
  --     variável; a linha continua convite). A disponibilidade, o replano, a ação e o "Tá bom, aviso o Gustavo." são os de sempre;
  --   · a ficha que levou a semana (o previsto ou a mudança, dias gravados): "não posso quarta" de outro dia que não o da ficha é dia que a gramática
  --     não conhece: vai ao dono com o trecho, e nada é remanejado (a ficha continua esperando o OK dela).
  if m.id is not null and m.tipo = 'convite' and v_tipo <> 'pergunta'
     and (v_tipo = 'nao_vou' or public._agenda_normal(p_body) ~ '^(nao|n)\M') then
    v_tipo := 'nao_vou';
    v_l := v_l || jsonb_build_object('tipo', 'nao_vou', 'convite', 'nao');
    m.tipo := 'ficha';
  end if;
  if m.id is not null and v_tipo = 'nao_vou' and m.tipo = 'ficha' and m.dias is not null
     and exists (select 1 from unnest(public._agenda_dias_citados(p_body)) d where d <> extract(isodow from m.dia)::int) then
    perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:semana', v_payee, m.dia), v_payee, null, m.dia,
      format('O %s respondeu "%s" à ficha de %s, que levava a semana dele, e eu não mudei nada: diga o que fazer com o dia que ele falou.',
             v_nome, public._agenda_corta(v_trecho, 120), public._dia_curto(m.dia)),
      'ligado', p_recebida_em);
    update public.agenda_equipe_mensagens
       set leitura = coalesce(leitura, '{}'::jsonb) || jsonb_build_object('semana', v_trecho, 'semana_em', p_recebida_em)
     where id = m.id;
    return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'semana', true, 'resposta', null);
  end if;
  -- FASE 7f: fim
  -- ── não vou (à ficha ou à confirmação; sem nada pendente: hoje antes do meio-dia, senão o próximo dia útil) ─
  -- (Revisão C1, item 3) também ao "como foi hoje?": aí o dia é o da ficha que ele levava (senão o próximo dia útil), e o
  -- "como foi" de hoje continua esperando a resposta de hoje (não vira a pergunta da diária de hoje)
  if v_tipo = 'nao_vou' and (m.id is null or m.tipo in ('ficha', 'confirmar', 'como_foi')) then
    -- (antes do fim da manhã, hoje; depois, o próximo dia útil)
    v_dia := case when m.tipo = 'como_foi' then coalesce(m.leva_ficha_de, public.agenda_somar_du(m.dia, 1))
                  else coalesce(m.dia, case when v_hora < cf.manha_fim then v_hoje else public.agenda_somar_du(v_hoje, 1) end) end;
    v_os := array(select distinct a.service_order_id from public.agenda_alocacoes a
                   where a.payee_id = v_payee and a.dia = v_dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                   order by 1);
    if cf.modo_equipe <> 'ligado' then
      -- em sombra nada muda: só o que faria
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
      values (clock_timestamp(), v_hoje, false, 'equipe', 'equipe', v_os[1], v_os, v_payee,
              jsonb_build_object('motivo', 'nao_vou', 'dia', v_dia, 'trecho', v_trecho),
              left(format('Em teste: o %s avisou que não vem %s; eu tiraria ele do plano desse dia.', v_nome,
                          public._agenda_dia_ref(v_dia, v_hoje)), 400));
      return jsonb_build_object('consumiu', false, 'tipo', v_tipo, 'modo', 'sombra');
    end if;
    perform set_config('agenda.hoje', v_hoje::text, true);
    if not exists (select 1 from public.agenda_disponibilidade d
                    where d.payee_id = v_payee and d.substituida_em is null and d.situacao = 'indisponivel'
                      and d.turno is null and d.periodo @> v_dia) then
      insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
      values (v_payee, daterange(v_dia, v_dia, '[]'), 'indisponivel', 'diarista', left('Avisou que não vem: ' || v_trecho, 200),
              left(v_trecho, 300), p_recebida_em)
      returning id into v_disp;
    end if;
    if cf.modo_proposta = 'ligado' and cardinality(v_os) > 0 then
      begin
        -- (C1, NOVO-agenda-27) a falta é evento real: o replano refaz os meios-dias que sobram da OS num bloco só, amanhã
        -- incluído (_agenda_violacoes lê agenda.replano_da_falta); o *desfaz* volta tudo
        perform set_config('agenda.replano_da_falta', 'on', true);
        v_rep := public.agenda_replanejar(v_os, 'equipe_faltou', 'vigia', v_hoje, p_recebida_em, null);
        perform set_config('agenda.replano_da_falta', '', true);
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        perform set_config('agenda.replano_da_falta', '', true);
        perform public.log_app_error('db', 'agenda: replanejar depois do "não vou" da equipe falhou: ' || v_msg, 'agenda',
                                     'equipe:replanejar', 'error',
                                     jsonb_build_object('os', to_jsonb(v_os), 'sqlstate', v_estado, 'payee', v_payee));
      end;
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
    values (clock_timestamp(), v_hoje, true, 'equipe', 'equipe', v_os[1], v_os, v_payee,
            jsonb_build_object('motivo', 'nao_vou', 'dia', v_dia, 'trecho', v_trecho, 'disponibilidade', v_disp,
                               'mensagem', m.id, 'replano_acoes', coalesce(v_rep -> 'acoes', '[]'::jsonb),
                               'acorde', v_dia <= public.agenda_somar_du(v_hoje, cf.congelamento_du)),
            left(format('O %s avisou que não vem %s.', v_nome, public._agenda_dia_da_equipe(v_dia, v_hoje))
                 || coalesce(' ' || nullif(v_rep ->> 'texto', ''), ''), 400))
    returning id into v_acao;
    -- FASE 7f: (7f P5, §5.5 (b), NOVO-agenda-76) quem a troca tirou do dia que já tinha ficha fica sabendo na hora (a mensagem de mudança), antes do
    -- acorde: o "Já avisei" do acorde (_agenda_texto_do_acorde) só sai com ela na fila. O que falhar aqui não derruba o "não vou": registra e segue.
    if public._agenda_fala_modo('previsto') <> 'desligado' then
      begin
        for v_7f_x in select (x #>> '{}')::uuid from jsonb_array_elements(coalesce(v_rep -> 'acoes', '[]'::jsonb)) x loop
          perform public._agenda_equipe_mudanca_na_hora(v_7f_x, v_hoje, p_recebida_em);
        end loop;
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        perform public.log_app_error('db', 'agenda: a mudança na hora depois do "não vou" falhou: ' || v_msg, 'agenda', 'equipe:mudanca', 'error',
                                     jsonb_build_object('payee', v_payee, 'dia', v_dia, 'sqlstate', v_estado));
      end;
    end if;
    -- FASE 7f: fim
    -- (C1, item 3) o "como foi" de hoje não é respondido pelo "não vou" de amanhã: ele segue esperando a resposta de hoje
    if m.id is not null and m.tipo <> 'como_foi' then
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa, leitura = v_l,
             acao_id = v_acao
       where id = m.id;
    end if;
    v_resp := format('Tá bom, aviso %s.', coalesce('o ' || (select public._agenda_nome_curto(p.name) from public.payees p
                                                              where p.id = public._agenda_dono(null)), 'o responsável'));
    v_r := public._agenda_equipe_registrar(v_payee, v_dia, 'resposta', v_resp, p_recebida_em, null,
                                           coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
    return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'acao_id', v_acao, 'dia', v_dia,
                              'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_resp end, 'envio', v_r ->> 'estado');
  end if;

  -- Daqui em diante só a resposta a uma mensagem que o sistema mandou.
  if m.id is null then
    return jsonb_build_object('consumiu', false, 'tipo', v_tipo);
  end if;

  -- FASE 7f: (7f P5, §5.5, §6.4, R8.7, E5, E5b, E6) a resposta ao convite, ao previsto e à mudança:
  --   · ao convite, o SIM (ok, presença, ou os turnos do plano com o ok) confirma: grava ANTES a disponibilidade confirmada no dia (como o ok à ficha)
  --     e a mensagem respondida, e depois responde "Combinado, até <dia>." — acima do teto de respostas do dia a resposta é recusada e o SIM vale;
  --     o que não é SIM nem NÃO vai ao dono com o trecho, e o convite segue esperando o SIM até o prazo (o NÃO é o caminho do "não vou", acima);
  --   · ao previsto e à mudança, o ok é ciência (respondida, nada muda, sem resposta automática); o resto vai ao dono com o trecho, sem remanejar.
  if m.tipo = 'convite' then
    v_7f_plano := array(select distinct a.turno from public.agenda_alocacoes a
                         where a.payee_id = v_payee and a.dia = m.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' order by 1);
    v_7f_sim := v_tipo in ('ok', 'presenca')
                or (v_tipo = 'turnos' and coalesce((v_l ->> 'ok')::boolean, false)
                    and (jsonb_typeof(v_l -> 'turnos') is distinct from 'array'
                         or array(select x from jsonb_array_elements_text(v_l -> 'turnos') x order by 1) = v_7f_plano
                         or (v_l -> 'turnos' = '["meio"]'::jsonb and cardinality(v_7f_plano) = 1)));
    if v_7f_sim then
      if not exists (select 1 from public.agenda_disponibilidade d
                      where d.payee_id = v_payee and d.substituida_em is null and d.situacao = 'confirmada'
                        and d.turno is null and d.periodo @> m.dia) then
        insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
        values (v_payee, daterange(m.dia, m.dia, '[]'), 'confirmada', 'diarista', left('Disse SIM ao convite: ' || v_trecho, 200),
                left(v_trecho, 300), p_recebida_em);
      end if;
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
             leitura = v_l || jsonb_build_object('convite', 'sim')
       where id = m.id;
      v_7f_resp := format('Combinado, até %s.', public._dia_curto(m.dia));
      v_r := public._agenda_equipe_registrar(v_payee, m.dia, 'resposta', v_7f_resp, p_recebida_em, null,
                                             coalesce(v_wa, md5(v_trecho || p_recebida_em::text)));
      return jsonb_build_object('consumiu', true, 'tipo', 'convite', 'leitura', 'sim', 'dia', m.dia,
                                'resposta', case when v_r ->> 'estado' = 'enfileirada' then v_7f_resp end, 'envio', v_r ->> 'estado');
    end if;
    perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:convite', v_payee, m.dia), v_payee, null, m.dia,
      format('O %s respondeu "%s" ao convite de %s, e eu não entendi. Sem o SIM dele até %s, ele sai do dia.', v_nome,
             public._agenda_corta(v_trecho, 120), public._dia_curto(m.dia),
             public._dia_curto((public._agenda_equipe_convite_prazo(m.dia) at time zone 'America/Sao_Paulo')::date) || ' às '
             || to_char(public._agenda_equipe_convite_prazo(m.dia) at time zone 'America/Sao_Paulo', 'HH24:MI')),
      'ligado', p_recebida_em);
    update public.agenda_equipe_mensagens
       set leitura = coalesce(leitura, '{}'::jsonb) || jsonb_build_object('nao_entendi', v_trecho, 'recebida_em', p_recebida_em)
     where id = m.id;
    return jsonb_build_object('consumiu', true, 'tipo', 'convite', 'leitura', 'nao_entendi', 'resposta', null);
  end if;
  if m.tipo in ('previsto', 'mudanca') then
    if v_tipo = 'ok' then
      update public.agenda_equipe_mensagens
         set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
             leitura = v_l || jsonb_build_object('ciencia', true)
       where id = m.id;
      return jsonb_build_object('consumiu', true, 'tipo', m.tipo, 'ciencia', true, 'resposta', null);
    end if;
    perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:%s', v_payee, m.dia, m.tipo), v_payee, null, m.dia,
      format('O %s respondeu "%s" à %s, e eu não mudei nada: diga o que fazer.', v_nome, public._agenda_corta(v_trecho, 120),
             case m.tipo when 'previsto' then 'semana prevista dele' else 'mudança da semana dele' end),
      'ligado', p_recebida_em);
    update public.agenda_equipe_mensagens
       set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
           leitura = v_l || jsonb_build_object('ao_dono', true)
     where id = m.id;
    return jsonb_build_object('consumiu', true, 'tipo', m.tipo, 'ao_dono', true, 'resposta', null);
  end if;
  -- FASE 7f: fim
  -- ── à ficha ou à confirmação ────────────────────────────────────────────────────────────────────────
  if m.tipo in ('ficha', 'confirmar') then
    -- (Revisão C1, item 7) o "ok" com os turnos ditos diferentes do plano ("ok, só de manhã" com o dia todo no plano) não
    -- confirma o dia: vai ao dono, como o não entendido (com o plano no texto)
    v_plano := array(select distinct a.turno from public.agenda_alocacoes a
                      where a.payee_id = v_payee and a.dia = m.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      order by 1);
    v_ditos := case when jsonb_typeof(v_l -> 'turnos') = 'array'
                    then array(select x from jsonb_array_elements_text(v_l -> 'turnos') x order by 1) end;
    v_div := v_tipo = 'turnos' and v_ditos is not null
             and not (v_ditos = v_plano or (v_ditos = array['meio'] and cardinality(v_plano) = 1));
    if not v_div
       and (v_tipo in ('ok', 'presenca') or (v_tipo = 'turnos' and coalesce((v_l ->> 'ok')::boolean, false))) then
      if not exists (select 1 from public.agenda_disponibilidade d
                      where d.payee_id = v_payee and d.substituida_em is null and d.situacao = 'confirmada'
                        and d.turno is null and d.periodo @> m.dia) then
        insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
        values (v_payee, daterange(m.dia, m.dia, '[]'), 'confirmada', 'diarista',
                left(case m.tipo when 'ficha' then 'Confirmou a ficha: ' else 'Confirmou de manhã: ' end || v_trecho, 200),
                left(v_trecho, 300), p_recebida_em);
      end if;
    else
      -- não entendi (ou turnos sem ok): vai ao dono com o trecho, e nada muda (nem remaneja: não é silêncio)
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:%s', v_payee, m.dia, m.tipo), v_payee,
        null, m.dia, format('O %s respondeu "%s" à %s de %s', v_nome, public._agenda_corta(v_trecho, 120),
                            case m.tipo when 'ficha' then 'ficha' else 'confirmação' end, public._dia_curto(m.dia))
                     || case when v_div
                             then ', e o plano é ' || case when v_plano = array['manha', 'tarde'] then 'o dia todo'
                                                           when v_plano = array['manha'] then 'a manhã'
                                                           when v_plano = array['tarde'] then 'a tarde'
                                                           else 'sem nada para ele' end || '.'
                             else '.' end,
        'ligado', p_recebida_em);
    end if;
    update public.agenda_equipe_mensagens
       set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa, leitura = v_l
     where id = m.id;
    return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'resposta', null);
  end if;

  -- ── ao "como foi hoje?" ─────────────────────────────────────────────────────────────────────────────
  v_plano := array(select distinct a.turno from public.agenda_alocacoes a
                    where a.payee_id = v_payee and a.dia = m.dia and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                    order by 1);
  v_ent := true;
  if v_tipo = 'ok' or (v_tipo = 'turnos' and v_l -> 'turnos' = 'null'::jsonb and coalesce((v_l ->> 'ok')::boolean, false)) then
    -- "ok" = tudo como o previsto: os turnos do plano e terminou (salvo "ok, mas não terminei")
    v_ditos := v_plano;
    v_term := coalesce((v_l ->> 'terminou')::boolean, true);
  elsif v_tipo = 'turnos' and jsonb_typeof(v_l -> 'turnos') = 'array' then
    v_ditos := array(select x from jsonb_array_elements_text(v_l -> 'turnos') x order by 1);
    v_term := (v_l ->> 'terminou')::boolean;
  else
    -- não entendi, "terminei" sem o dia, "não vou"/presença fora de hora: a diária vira pergunta (crítica)
    v_ent := false;
    v_ditos := null;
    v_term := (v_l ->> 'terminou')::boolean;
  end if;
  -- FASE 7c: (7c P8, §16.5.3, §16.3.8; AG7-10b) com modo_tarefas ligado, as etapas do que devia ficar pronto hoje (de quem responde, sem
  -- resultado: _agenda_tarefas_da_pessoa) lidas sem IA (_agenda_ler_tarefas_da_resposta); com o "como foi" que não tem mais a lista de
  -- agora (_agenda_tarefas_texto_confere), os números não valem e só as palavras são lidas. A resposta só das etapas, sem turno nem OK,
  -- vale os turnos do plano para a diária só com tarefas_resposta_vale_dia = sempre, ou = tudo e "tudo"/"fiz tudo" — sem virar o tipo ok
  -- (o "fiz tudo" é sobre hoje: não confirma a ficha de amanhã que o "como foi" levava).
  if cf.modo_tarefas = 'ligado' then
    v_p8_dp := public._agenda_tarefas_da_pessoa(v_payee, m.dia, v_hoje);
    v_p8_lista := coalesce(v_p8_dp -> 'pergunta', '[]'::jsonb);
    if jsonb_array_length(v_p8_lista) > 0 then
      v_p8_lt := public._agenda_ler_tarefas_da_resposta(
                   case when public._agenda_tarefas_texto_confere(m.texto, v_p8_lista) then p_body
                        else regexp_replace(coalesce(p_body, ''), '[0-9]+', ' ', 'g') end,
                   v_p8_lista);
      if coalesce((v_p8_lt ->> 'entendeu')::boolean, false) and not v_ent and v_tipo in ('nao_entendi', 'turnos')
         and jsonb_typeof(v_l -> 'turnos') is distinct from 'array' and not coalesce((v_l ->> 'ok')::boolean, false)
         and (cf.tarefas_resposta_vale_dia = 'sempre'
              or (cf.tarefas_resposta_vale_dia = 'tudo' and coalesce((v_p8_lt ->> 'tudo')::boolean, false))) then
        v_ent := true;
        v_ditos := v_plano;
        v_term := coalesce((v_p8_lt ->> 'tudo')::boolean, false);
      end if;
    end if;
  end if;
  -- FASE 7c: fim
  update public.agenda_equipe_mensagens
     set estado = 'respondida', resposta_texto = v_trecho, resposta_em = p_recebida_em, resposta_wa_id = v_wa,
         leitura = v_l || jsonb_build_object('entendeu', v_ent, 'turnos_lidos', to_jsonb(v_ditos), 'turnos_plano', to_jsonb(v_plano),
                                             'terminou', v_term)
   where id = m.id;
  -- FASE 7c: (7c P8, §16.5.3, §16.6.4) a leitura das etapas fica na mensagem (tarefas e a lista perguntada); a entendida grava as feitas
  -- e as pendentes (via equipe, por _agenda_tarefas_registrar: vale sobre a conferência); a que falou de falta sem dizer qual vira a
  -- pergunta equipe_resposta ao dono, e nada muda nas etapas.
  if v_p8_lt is not null then
    update public.agenda_equipe_mensagens
       set leitura = coalesce(leitura, '{}'::jsonb) || jsonb_build_object('tarefas', v_p8_lt, 'lista', v_p8_lista)
     where id = m.id;
    v_p8_its := coalesce(v_p8_dp -> 'itens', '[]'::jsonb);
    if coalesce((v_p8_lt ->> 'entendeu')::boolean, false) then
      perform public._agenda_tarefas_registrar(
        array(select (i ->> 'linha_id')::uuid from jsonb_array_elements(v_p8_its) i
               where (i ->> 'n')::int in (select x::int from jsonb_array_elements_text(v_p8_lt -> 'feitas') x)
                 and i ->> 'linha_id' is not null),
        'feita', 'equipe', v_trecho, m.id, p_recebida_em);
      perform public._agenda_tarefas_registrar(
        array(select (i ->> 'linha_id')::uuid from jsonb_array_elements(v_p8_its) i
               where (i ->> 'n')::int in (select x::int from jsonb_array_elements_text(v_p8_lt -> 'pendentes') x)
                 and i ->> 'linha_id' is not null),
        'pendente', 'equipe', v_trecho, m.id, p_recebida_em);
    elsif coalesce((v_p8_lt ->> 'falou_de_falta')::boolean, false) then
      perform public._agenda_equipe_perguntar('equipe_resposta', format('equipe_resposta:%s:%s:tarefas', v_payee, m.dia), v_payee,
        (v_p8_its -> 0 ->> 'os')::uuid, m.dia,
        format('O %s respondeu "%s" ao "como foi" do %s (%s), e não entendi o que faltou. Me diga qual (ex.: "no %s falta %s").',
               v_nome, public._agenda_corta(v_trecho, 120), v_p8_its -> 0 ->> 'cliente', public._dia_curto(m.dia),
               v_p8_its -> 0 ->> 'cliente',
               lower(left(v_p8_lista -> 0 ->> 'texto', 1)) || substr(v_p8_lista -> 0 ->> 'texto', 2)),
        'ligado', p_recebida_em);
    end if;
  end if;
  -- FASE 7c: fim
  if v_ent then
    v_conf := array(select x from unnest(v_ditos) x where x = any (v_plano) order by 1);
    perform set_config('agenda.hoje', v_hoje::text, true);
    -- FASE 7c: (7c P8, §16.5.3, §16.3.9) com a leitura das etapas entendida: o turno confirmado em que termina uma etapa pendente sai do
    -- cumprido e vai a parcial (o motivo da leitura, senão estimativa), por OS, logo depois do cumprido dos outros; as etapas que terminavam
    -- num turno que ele não confirmou ficam pendentes (via equipe).
    if v_p8_lt is not null then
      v_p8_conf := v_conf;
      v_p8_its := coalesce(v_p8_dp -> 'itens', '[]'::jsonb);
      if coalesce((v_p8_lt ->> 'entendeu')::boolean, false) then
        select coalesce(jsonb_object_agg(z.os, z.tus), '{}'::jsonb) into v_p8_parc
          from (select i ->> 'os' as os, jsonb_agg(distinct d.turno) as tus
                  from jsonb_array_elements(v_p8_its) i
                  join public.os_tarefas_dia d on d.id = (i ->> 'linha_id')::uuid
                 where (i ->> 'n')::int in (select x::int from jsonb_array_elements_text(v_p8_lt -> 'pendentes') x)
                   and d.turno = any (v_conf)
                 group by i ->> 'os') z;
        v_conf := array(select x from unnest(v_conf) x
                         where not exists (select 1 from jsonb_each(v_p8_parc) p, jsonb_array_elements_text(p.value) t where t = x)
                         order by 1);
      end if;
      perform public._agenda_tarefas_registrar(
        array(select d.id from jsonb_array_elements(coalesce(v_p8_dp -> 'pergunta', '[]'::jsonb)) q
                join jsonb_array_elements(v_p8_its) i on (i ->> 'n')::int = (q ->> 'n')::int
                join public.os_tarefas_dia d on d.id = (i ->> 'linha_id')::uuid
               where not (d.turno = any (v_p8_conf))
                 and not (v_ditos = array['meio'] and cardinality(v_plano) = 1)
                 and not (coalesce((v_p8_lt ->> 'entendeu')::boolean, false)
                          and (q ->> 'n')::int in (select x::int from jsonb_array_elements_text(v_p8_lt -> 'feitas') x))),
        'pendente', 'equipe', v_trecho, m.id, p_recebida_em);
    end if;
    -- FASE 7c: fim
    begin
      if cardinality(v_conf) > 0 then
        -- os turnos que ele confirmou viram resultado (via equipe), e a diária é decidida em seguida
        perform set_config('agenda.turnos_equipe', array_to_string(v_conf, ','), true);
        v_r := public.agenda_registrar_dia(null, m.dia, 'cumprido', null, null, array[v_payee], 'equipe', v_trecho, v_hoje,
                                           p_recebida_em, null);
        perform set_config('agenda.turnos_equipe', '', true);
      elsif v_ditos = '{}'::text[] then
        v_r := public.agenda_registrar_dia(null, m.dia, 'nao_cumprido', 'equipe', null, array[v_payee], 'equipe', v_trecho, v_hoje,
                                           p_recebida_em, null);
      end if;
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
      perform set_config('agenda.turnos_equipe', '', true);
      perform public.log_app_error('db', 'agenda: anotar o dia pela resposta da equipe falhou: ' || v_msg, 'agenda',
                                   'equipe:dia', 'error', jsonb_build_object('payee', v_payee, 'dia', m.dia, 'sqlstate', v_estado));
    end;
    -- FASE 7c: (7c P8, §16.5.3) o turno com etapa pendente: parcial, por OS (agenda_registrar_dia via equipe, só os turnos dela)
    for v_p8_os in select k from jsonb_object_keys(v_p8_parc) k order by 1 loop
      begin
        v_p8_tu := array(select x from jsonb_array_elements_text(v_p8_parc -> v_p8_os) x order by 1);
        perform set_config('agenda.turnos_equipe', array_to_string(v_p8_tu, ','), true);
        v_r := public.agenda_registrar_dia(null, m.dia, 'parcial', coalesce(v_p8_lt ->> 'motivo', 'estimativa'), v_p8_os::uuid,
                                           array[v_payee], 'equipe', v_trecho, v_hoje, p_recebida_em, null);
        perform set_config('agenda.turnos_equipe', '', true);
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        perform set_config('agenda.turnos_equipe', '', true);
        perform public.log_app_error('db', 'agenda: anotar o parcial pelas etapas da equipe falhou: ' || v_msg, 'agenda',
                                     'tarefas:parcial', 'error',
                                     jsonb_build_object('payee', v_payee, 'dia', m.dia, 'os', v_p8_os, 'sqlstate', v_estado));
      end;
    end loop;
    -- FASE 7c: fim
    -- o "ok" ao "como foi" que levava a ficha de amanhã confirma amanhã também — (C1, item 3) salvo se ele já disse que
    -- não vem amanhã (o "ok" depois do "amanhã não vou" é sobre hoje)
    if v_tipo = 'ok' and m.leva_ficha_de is not null
       and not exists (select 1 from public.agenda_disponibilidade d
                        where d.payee_id = v_payee and d.substituida_em is null and d.situacao in ('confirmada', 'indisponivel')
                          and d.turno is null and d.periodo @> m.leva_ficha_de) then
      insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, trecho, criado_em)
      values (v_payee, daterange(m.leva_ficha_de, m.leva_ficha_de, '[]'), 'confirmada', 'diarista',
              left('Confirmou a ficha junto do "como foi": ' || v_trecho, 200), left(v_trecho, 300), p_recebida_em);
    end if;
  end if;
  -- a diária do dia (idempotente: o agenda_registrar_dia já a chamou quando anotou)
  begin
    v_r := public._agenda_diaria_do_dia(v_payee, m.dia, 'equipe', v_hoje, p_recebida_em);
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    perform public.log_app_error('db', 'agenda: a diária pela resposta da equipe falhou: ' || v_msg, 'agenda', 'equipe:diaria',
                                 'error', jsonb_build_object('payee', v_payee, 'dia', m.dia, 'sqlstate', v_estado));
  end;
  return jsonb_build_object('consumiu', true, 'tipo', v_tipo, 'entendeu', v_ent, 'resposta', null, 'diaria', v_r ->> 'status');
end;
$function$;

comment on function public.agenda_resposta_da_equipe(text, text, text, timestamptz) is
  'Agenda de Produção (Fase 3, P4): a mensagem do técnico (número que não é login de admin), chamada pelo whatsapp-webhook antes da confirmação do cliente e da conferência do recibo. modo_equipe desligado, telefone de ninguém da equipe (ou de dois) = {consumiu: false}. A mesma mensagem (p_message_id) de novo = nada muda. Lida por _agenda_ler_resposta_da_equipe. Decide a última mensagem que o sistema mandou (ligado, enfileirada, dentro de equipe_resposta_validade); o recibo de diárias mandado depois dela fica com o "ok" (NOVO-agenda-17: consumiu false). pergunta → a ficha do publicado (agenda_equipe_ficha.texto_resposta) como resposta enfileirada (sem plano: a pergunta equipe_resposta ao dono); em sombra só registra (consumiu false). nao_vou → indisponível no dia (agenda_disponibilidade origem diarista), replano (modo_proposta ligado, origem vigia), ação equipe com o acorde para a rotina e "Tá bom, aviso o Gustavo."; em sombra só a ação executada = false. ok/presença à ficha ou à confirmação → confirmada, sem resposta; não entendido → equipe_resposta ao dono, sem remanejo. Ao "como foi hoje?": ok = os turnos do plano e terminou; os turnos ditos viram resultado (agenda_registrar_dia via equipe, só os turnos confirmados) e a diária (_agenda_diaria_do_dia); não entendido = a pergunta crítica da diária. Sem pendente (ok, turnos, presença, não entendi) = consumiu false. {consumiu, tipo, resposta, acao_id}. Só service_role. FASE 7b (P3, §5.2; A1 = NOVO-agenda-52, A2, A3 = NOVO-agenda-54): com modo_dias ligado, a resposta à pergunta dos dias da semana (a mensagem dias ligada, enfileirada, mandada antes e com o prazo da semana por vir) é lida por _agenda_ler_dias_da_equipe ANTES da pergunta, do "não vou" e do "como foi": os dias ou "nenhum" (em qualquer ordem) gravam a semana presa e o padrão de quem tem (_agenda_equipe_dias_gravar, origem diarista; a exceção do dono no dia vence e volta em leitura.conflitos), a mensagem fica respondida e sai "Anotei: na semana de 16/11 você pode seg, ter e qui. Obrigado!" / "… você não pode. Obrigado por avisar!"; "igual"/"ok" com a pergunta por último: nada gravado, "Anotei: semana de 16/11 igual (de seg a sex). Obrigado!"; não entendido com a pergunta por último (e a leitura geral não é pergunta, presença nem turnos; o "não vou" junto de um dia da semana também — "segunda não posso" nunca vira o "não vou" da ficha): 1ª vez "Não entendi os dias da semana de 16/11. Mande só os dias, assim: seg ter qui (ou "nenhum")." (chave agenda-equipe:resposta:<pessoa>:dias:<segunda>), 2ª vez a pergunta equipe_resposta ao dono e a mensagem respondida. {consumiu: true, tipo: dias, leitura, …}. A "última que o sistema começou" do resto não é mais a pergunta da semana. Fora disso, o de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achado 8): com modo_dias ligado, a pergunta da semana aberta só leva a resposta (os dias ou "nenhum") quando é a última mensagem mandada a ele, quando a frase fala da semana ou quando é só a lista dos dias e a leitura de sempre não a entende; com a ficha, a confirmação ou o "como foi" mandados depois, "não posso", "ok, sexta tô lá", "sim, todos prontos" e "terminei todos" seguem o caminho de antes (o "não vou", a confirmação, os turnos) e a pergunta da semana continua aberta. FASE 7c (P8, §16.5.3, §16.3.8; AG7-10b): com modo_tarefas ligado, no "como foi" a lista do que devia ficar pronto (de quem responde, sem resultado) é lida por _agenda_ler_tarefas_da_resposta (com o texto que não tem mais a lista de agora, só as palavras) e gravada na mensagem (tarefas, lista); a entendida grava as feitas e as pendentes via equipe (_agenda_tarefas_registrar), o turno confirmado em que termina uma pendente sai do cumprido e vai a parcial (o motivo da leitura, senão estimativa), por OS, e as etapas de turno não confirmado ficam pendentes; a que falou de falta sem dizer qual vira a pergunta equipe_resposta ao dono ("O Alex respondeu "faltou umas coisas" ao "como foi" do Lenine (qua 04/11), e não entendi o que faltou. Me diga qual (…)."); a resposta só das etapas vale os turnos do plano para a diária com tarefas_resposta_vale_dia sempre, ou tudo e "tudo" (sem virar o tipo ok). Desligado ou em teste: a de antes, byte a byte. FASE 7f (P5): o convite vale até o prazo dele: SIM (ok, presença, os turnos do plano com o ok) grava a disponibilidade confirmada e a mensagem respondida ANTES de responder "Combinado, até <dia>." (acima do teto de respostas a resposta é recusada e o SIM vale); NÃO = o caminho do "não vou" com o dia do convite; o resto vai ao dono e o convite segue esperando. Ao previsto e à mudança, ok = ciência, o resto vai ao dono sem remanejar; à ficha que levou a semana, "não posso quarta" de outro dia vai ao dono. Depois do replano do "não vou", a mudança na hora de quem já tinha a ficha (_agenda_equipe_mudanca_na_hora). FICHA PAGA B (18/11/2026, 20270126100000; P2 do dono, 18/11 11:45): "o que tem pra amanhã?" com a mensagem à equipe ligada e a ficha desse dia segurada (_agenda_ficha_liberada falso) não diz o plano: responde "Vou ver com Gustavo e te falo." (o nome curto do dono) e abre a pergunta equipe_resposta ao dono ("O João perguntou o que tem amanhã (ter 03/11), e a ficha dele está segurada: a OS-00074 já está paga e você não disse *mande*. Diga a ele o que fazer."; ou "… já está concluída" (faturada, cancelada), ou o dia pela estimativa sem a pergunta vista). Com a ficha liberada, desligado ou em teste: o de antes.';

-- ── 8. O *mande* da ficha de OS encerrada (correção da revisão) ─────────────────────────────────────────
-- _agenda_gestor_decidir (de 20261031100900 (produção em 18/11); md5 do corpo de antes ed6693488bfa2c8a7c30583c2c5f0478 sem CR)
create or replace function public._agenda_gestor_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid, p_via text,
                                                         p_trecho text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c_tipos constant text[] := array['situacao', 'estimativa', 'reavaliar', 'reestimar', 'ficha_estimativa', 'onda', 'sabado',
                                   'bem_livre', 'compre_ate', 'sinal'];
  v_prazo boolean := p_via = 'prazo';
  v_q     public.agenda_perguntas%rowtype;
  v_opc   jsonb;
  v_ef    jsonb;
  v_nome  text;
  v_agora jsonb;
  v_mot   text;
  v_ate   text;
  v_txt   text;
  v_acao  uuid;
  -- FASE 7: (7a P8) a onda
  v_f7_ap   text;
  v_f7_pr   public.agenda_propostas%rowtype;
  v_f7_np   jsonb;
  v_f7_oss  uuid[];
  v_f7_r    jsonb;
  -- FASE 7: fim
  -- FASE 7: (7a P9) a revisão diária: reestimar e reavaliar
  v_f9_rq   jsonb;
  v_f9_pl   public.os_planejamento%rowtype;
  v_f9_m    jsonb;
  v_f9_ft   numeric;
  v_f9_aj   jsonb;
  v_f9_dt   text;
  v_f9_ant  jsonb;
  v_f9_dep  jsonb;
  v_f9_cf   public.agenda_config;
  -- FASE 7: fim
  -- FASE 7: (7a P11) a ficha da equipe de um dia pela estimativa
  v_f11_p   uuid;
  v_f11_d   date;
  v_f11_n   text;
  -- FASE 7: fim
  -- FICHA PAGA B: (18/11/2026) as OS encerradas da pessoa no dia da ficha
  v_fb_os   uuid[];
  -- FICHA PAGA B: fim
  -- FASE 7: (7a P12) o sábado de manhã para cumprir o prazo
  v_f12_sab  date;
  v_f12_r    jsonb;
  v_f12_x    record;
  v_f12_pes  text[];
  v_f12_sabs date[];
  -- FASE 7: fim
begin
  if p_via is null or p_via not in ('whatsapp', 'painel', 'tela', 'prazo') then
    raise exception 'Canal desconhecido para a decisão: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_decidir: sem o dia ou a hora' using errcode = '22004';
  end if;
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  select * into v_q from public.agenda_perguntas where id = p_pergunta for update;
  if not found then
    raise exception 'Não encontrei essa pergunta.' using errcode = 'P0002';
  end if;
  if not (v_q.tipo = any (c_tipos)) then
    raise exception '_agenda_gestor_decidir: a pergunta "%" não é do gestor da agenda', v_q.tipo using errcode = '22023';
  end if;
  if v_q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  if v_q.modo <> 'ligado' or coalesce(public._agenda_modo_da_pergunta(v_q.tipo, v_q.chave), 'desligado') <> 'ligado' then
    return jsonb_build_object('ok', false, 'gestor', true,
                              'texto', 'O gestor da agenda está em teste: mostro o que eu faria, mas não mudo nada.');
  end if;
  -- FASE 7: (7a P8, spec §5.8 e §6.3) a onda — 1) faço tudo como montei; 2) mudo só o de hoje e amanhã (as OS de evento real); 3)
  -- não mudo nada. A conta é refeita agora pelo motor com os parâmetros da proposta da pergunta, só se a agenda não mudou desde
  -- ela (a mesma versão do plano: o motor dá o mesmo); se mudou, a pergunta resolve e a rodada seguinte refaz a conta (e pergunta
  -- de novo se ainda for muita mudança). O que entra vai com a pergunta (a ação crítica, com pergunta_id). Nunca tem prazo.
  if v_q.tipo = 'onda' then
    if v_prazo then
      return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa pergunta não tem prazo: nada mudou.');
    end if;
    select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
    if v_opc is null then
      return jsonb_build_object('ok', false, 'gestor', true,
        'texto', 'Essa opção não existe. As opções são: '
                 || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                       from jsonb_array_elements(v_q.opcoes) o) || '.');
    end if;
    v_f7_ap := v_opc #>> '{efeito,aplicar}';
    if v_f7_ap is null or v_f7_ap not in ('tudo', 'so_evento_real', 'nada') then
      return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não tem o que fazer: nada mudou.');
    end if;
    select * into v_f7_pr from public.agenda_propostas pr where pr.id = v_q.proposta_id;
    if v_f7_ap = 'nada' then
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
      if v_f7_pr.id is not null and v_f7_pr.estado = 'aberta' then
        perform public.agenda_descartar(v_f7_pr.id, p_autor, 'você disse: não mudo nada');
      end if;
      return jsonb_build_object('ok', true, 'gestor', true,
        'texto', 'Combinado: não mudei nada. Me diga o que mudar (*agenda plano* mostra o que está marcado).');
    end if;
    if v_f7_pr.id is null or v_q.versao_base is distinct from (public._agenda_cfg()).versao_plano then
      update public.agenda_perguntas
         set estado = 'resolvida', resolvida_motivo = 'a agenda mudou desde a pergunta: refaço a conta na próxima rodada'
       where id = v_q.id;
      return jsonb_build_object('ok', false, 'gestor', true, 'mudou', true,
        'texto', 'A agenda mudou desde a pergunta: não mudei nada agora. Na próxima rodada eu refaço a conta e, se ainda for muita mudança, te pergunto de novo.');
    end if;
    begin
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
      v_f7_np := public.agenda_propor(v_f7_pr.escopo, (v_f7_pr.parametros ->> 'p_de')::date, (v_f7_pr.parametros ->> 'p_ate')::date,
                   case when jsonb_typeof(v_f7_pr.parametros -> 'p_os') = 'array'
                        then array(select x::uuid from jsonb_array_elements_text(v_f7_pr.parametros -> 'p_os') x) end,
                   coalesce(v_f7_pr.parametros -> 'p_restricoes', '{}'::jsonb), true, 'dono', p_autor, p_hoje, p_agora);
      if not coalesce((v_f7_np ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0098', message = coalesce(v_f7_np ->> 'texto', 'não deu');
      end if;
      v_f7_oss := case when v_f7_ap = 'so_evento_real'
                       then array(select distinct (i ->> 'os')::uuid from jsonb_array_elements(v_f7_np -> 'itens') i
                                   where i ->> 'op' = 'criar' and coalesce((i ->> 'evento_real')::boolean, false) order by 1) end;
      if v_f7_ap = 'so_evento_real' and cardinality(v_f7_oss) = 0 then
        perform public.agenda_descartar((v_f7_np ->> 'proposta_id')::uuid, p_autor, 'nada de hoje e amanhã para mudar');
        return jsonb_build_object('ok', true, 'gestor', true,
                                  'texto', 'Não havia nada de hoje e amanhã para mudar: não mudei nada.');
      end if;
      v_f7_r := public.agenda_aplicar((v_f7_np ->> 'proposta_id')::uuid, v_f7_oss, 'dono', p_autor, v_q.id, p_hoje, p_agora);
      if not coalesce((v_f7_r ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0098', message = coalesce(v_f7_r ->> 'texto', 'não deu');
      end if;
    exception when sqlstate 'P0098' then
      -- nada fica: a pergunta continua aberta
      return jsonb_build_object('ok', false, 'gestor', true,
                                'texto', 'Não consegui fazer o que você escolheu: ' || sqlerrm || ' Nada mudou.');
    end;
    return jsonb_build_object('ok', true, 'gestor', true, 'texto', 'Feito: ' || (v_f7_r ->> 'texto'),
                              'acoes', v_f7_r -> 'acoes', 'proposta_id', v_f7_np ->> 'proposta_id');
  end if;
  -- FASE 7: fim
  -- FASE 7: (7a P9, spec §5.9 e §6.3) as perguntas da revisão diária.
  --   reavaliar (sem prazo): 1) "Use *concluiu Rodrigo*."; 2) "Me diga o que mais tem para fazer e quantos dias" — as duas
  --     respondem a pergunta; nada aqui conclui nem marca.
  --   reestimar: só se a pergunta que eu faria agora para a OS ainda é esta (a mesma chave: os dias do dono e o mesmo
  --     orçamento); senão ela resolve e nada muda. 1) fico com os dias do dono — o que vale sem resposta até o prazo (nada muda
  --     na agenda); 2) uso a minha conta pelo orçamento: os dias ficam gravados como os do gestor, com o sim do dono
  --     (estimativa_fonte orcamento, como a opção 1 das perguntas do P4; o histórico e a ação estimar, desfazível) e a
  --     agenda acompanha na hora — sobrando meio-dia, o corte dos últimos (_agenda_gestor_reestimar, do
  --     dono); faltando, o encaixe do que falta (_agenda_propor_e_aplicar, do dono).
  if v_q.tipo in ('reestimar', 'reavaliar') then
    select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
    if v_opc is null then
      return jsonb_build_object('ok', false, 'gestor', true,
        'texto', 'Essa opção não existe. As opções são: '
                 || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                       from jsonb_array_elements(v_q.opcoes) o) || '.');
    end if;
    if v_prazo and v_q.opcao_escolhida is not null then
      return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Você já respondeu essa pergunta: o prazo não vale mais.');
    end if;
    v_ef := coalesce(v_opc -> 'efeito', '{}'::jsonb);
    select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) into v_nome
      from public.service_orders so left join public.clients cl on cl.id = so.client_id
     where so.id = v_q.service_order_id;
    if v_q.tipo = 'reavaliar' then
      if v_prazo then
        return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa pergunta não tem prazo: nada mudou.');
      end if;
      if not (v_ef ? 'terminou' or v_ef ? 'dizer') then
        return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não tem o que fazer: nada mudou.');
      end if;
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
      return jsonb_build_object('ok', true, 'gestor', true,
        'texto', case when v_ef ? 'terminou' then format('Use *concluiu %s*.', v_nome)
                      else format('Me diga o que mais tem para fazer e quantos dias (ex.: ''%s 2 dias''): eu marco.', v_nome) end);
    end if;
    -- reestimar: a opção tem de ter o que fazer; depois, a condição de agora
    if not (v_ef ? 'manter' or v_ef ? 'dias') then
      return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não tem o que fazer: nada mudou.');
    end if;
    v_f9_rq :=public._agenda_gestor_perguntas_da_revisao(v_q.service_order_id, p_hoje, p_agora, true) -> 'reestimar';
    if jsonb_typeof(v_f9_rq) is distinct from 'object' or (v_f9_rq ->> 'chave') is distinct from v_q.chave then
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'não precisa mais: mudou o que falta saber'
       where id = v_q.id;
      return jsonb_build_object('ok', false, 'gestor', true, 'sem_condicao', true,
                                'texto', 'Não mudei nada: não precisa mais (mudou o que falta saber).');
    end if;
    select * into v_f9_pl from public.os_planejamento x where x.service_order_id = v_q.service_order_id for update;
    v_f9_dt := case when v_f9_pl.dias >= 2 then 'os ' else '' end || public._agenda_dias(v_f9_pl.dias);
    if v_ef ? 'manter' then
      if v_prazo then
        v_ate := public._dia_curto((v_q.veto_ate at time zone 'America/Sao_Paulo')::date) || ' às '
                 || to_char(v_q.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI');
        update public.agenda_perguntas
           set estado = 'resolvida', opcao_escolhida = p_opcao,
               resolvida_motivo = left(format('sem resposta até %s: fiquei com os dias que você disse', replace(v_ate, ' às ', ' ')), 200)
         where id = v_q.id;
        return jsonb_build_object('ok', true, 'gestor', true, 'os', v_q.service_order_id, 'via', p_via,
          'texto', format('Sem resposta sobre %s até %s: fiquei com %s que você disse.', v_nome, v_ate, v_f9_dt));
      end if;
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
      return jsonb_build_object('ok', true, 'gestor', true, 'os', v_q.service_order_id,
                                'texto', format('Combinado, %s: fico com %s que você disse.', v_nome, v_f9_dt));
    end if;
    if v_prazo then
      return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não vale sem resposta: nada mudou.');
    end if;
    v_f9_cf := public._agenda_cfg();
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = v_q.id;
    v_f9_ant := jsonb_build_object('dias', v_f9_pl.dias, 'estimativa_fonte', v_f9_pl.estimativa_fonte,
                                   'estimativa_em', v_f9_pl.estimativa_em);
    v_f9_dep := jsonb_build_object('dias', (v_ef ->> 'dias')::numeric, 'estimativa_fonte', 'orcamento', 'estimativa_em', p_agora);
    v_txt := format('Combinado, %s: agora conto %s, pela minha conta do orçamento. *desfaz %s* volta.', v_nome,
                    public._agenda_dias((v_ef ->> 'dias')::numeric), v_nome);
    update public.os_planejamento
       set dias = (v_ef ->> 'dias')::numeric, estimativa_fonte = 'orcamento', estimativa_em = p_agora,
           historico = public._os_material_historico(v_f9_pl.historico, jsonb_build_object(
             'em', (p_agora at time zone 'America/Sao_Paulo')::date, 'quando', p_agora, 'autor', p_autor, 'por', 'dono',
             'motivo', 'você escolheu na pergunta reestimar', 'pergunta', v_q.id, 'antes', v_f9_ant, 'depois', v_f9_dep)),
           atualizado_em = p_agora, atualizado_por = p_autor
     where service_order_id = v_q.service_order_id;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, pergunta_id, antes, depois,
                                     texto, motivo, autor, desfazivel_ate)
    values (p_agora, p_hoje, true, 'dono', 'estimar', v_q.service_order_id, array[v_q.service_order_id], v_q.id, v_f9_ant, v_f9_dep,
            left(public._agenda_corta(v_txt, 400), 400), 'você escolheu na pergunta', p_autor, p_agora + v_f9_cf.desfazer_validade)
    returning id into v_acao;
    -- a agenda acompanha: o que sobra sai, o que falta entra
    v_f9_aj := null;
    if public._agenda_os_tem_dia(v_q.service_order_id, p_hoje) then
      v_f9_m := public.agenda_meios_da_os(v_q.service_order_id, p_hoje);
      v_f9_ft := coalesce((v_f9_m ->> 'cumpridos')::numeric, 0) + coalesce((v_f9_m ->> 'vigentes')::numeric, 0);
      if v_f9_ft - (v_f9_m ->> 'total')::numeric >= 1 then
        v_f9_aj := public._agenda_gestor_reestimar(v_q.service_order_id, p_hoje, p_agora, p_autor);
      elsif (v_f9_m ->> 'total')::numeric > v_f9_ft then
        v_f9_aj := public._agenda_propor_e_aplicar('os', array[v_q.service_order_id], 'dono', p_autor, p_hoje, p_agora);
      end if;
    end if;
    return jsonb_build_object('ok', true, 'gestor', true, 'os', v_q.service_order_id, 'acao_id', v_acao, 'dias', v_ef -> 'dias',
                              'texto', concat_ws(' ', v_txt, nullif(v_f9_aj ->> 'texto', '')), 'agenda', v_f9_aj);
  end if;
  -- FASE 7: fim
  -- FASE 7: (7a P11, spec §5.11 e §6.3; AG7-15) a ficha da equipe de um dia pela estimativa, na janela de veto do ligar:
  --   1) Mande — fica respondida e a ficha sai na hora dela (_agenda_ficha_liberada);
  --   2) Segure — fica respondida; a ficha e a confirmação da manhã desse dia não saem (a rotina as registra como recusadas: veto)
  --      e o dono fala com a pessoa. A 2 nunca vale sem resposta.
  --   Sem resposta até o prazo (a hora da ficha), com a pergunta mostrada antes (o passo vetos), vale a 1: fica resolvida.
  if v_q.tipo = 'ficha_estimativa' then
    select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
    if v_opc is null then
      return jsonb_build_object('ok', false, 'gestor', true,
        'texto', 'Essa opção não existe. As opções são: '
                 || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                       from jsonb_array_elements(v_q.opcoes) o) || '.');
    end if;
    v_ef := coalesce(v_opc -> 'efeito', '{}'::jsonb);
    if not (v_ef ? 'mandar' or v_ef ? 'segurar') then
      return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não tem o que fazer: nada mudou.');
    end if;
    v_f11_p := nullif(split_part(v_q.chave, ':', 2), '')::uuid;
    v_f11_d := nullif(split_part(v_q.chave, ':', 3), '')::date;
    v_f11_n := coalesce((select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_f11_p), 'a pessoa');
    if v_prazo then
      if not (v_ef ? 'mandar') then
        return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não vale sem resposta: nada mudou.');
      end if;
      v_ate := public._dia_curto((v_q.veto_ate at time zone 'America/Sao_Paulo')::date) || ' às '
               || to_char(v_q.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI');
      update public.agenda_perguntas
         set estado = 'resolvida',
             resolvida_motivo = left(format('sem resposta até %s: a ficha vai como eu disse', replace(v_ate, ' às ', ' ')), 200)
       where id = v_q.id;
      return jsonb_build_object('ok', true, 'gestor', true, 'via', p_via, 'pessoa', v_f11_p, 'dia', v_f11_d,
        'texto', format('Sem resposta até %s: a ficha de %s vai para %s como eu disse.', v_ate, public._dia_curto(v_f11_d), v_f11_n));
    end if;
    -- quem responde viu a pergunta: sem a conta de mostrada (respondeu pela conversa ou pela tela), ela passa a contar agora — a
    -- ficha (_agenda_ficha_liberada) e o zero ficha_estimativa_sem_veto da saúde leem a mostrada
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via,
           mostrada_vezes = greatest(mostrada_vezes, 1), mostrada_em = coalesce(mostrada_em, p_agora),
           mostrada_via = coalesce(mostrada_via, 'conversa')
     where id = v_q.id;
    -- FICHA PAGA B: (18/11/2026, 20270126100000; correção da revisão da F2b) o *mande* de quem tem OS concluída, faturada ou cancelada no
    -- dia fica gravado, mas a ficha não sai (_agenda_ficha_liberada): a resposta diz isso, e não "Combinado: mando a ficha".
    v_fb_os := case when v_ef ? 'mandar' and v_f11_p is distinct from public._agenda_dono(null)
                    then public._agenda_ficha_os_concluidas(v_f11_p, v_f11_d) else '{}'::uuid[] end;
    if cardinality(v_fb_os) > 0 then
      return jsonb_build_object('ok', true, 'gestor', true, 'pessoa', v_f11_p, 'dia', v_f11_d, 'encerrada', true,
        'texto', format('%s %s %s %s: a ficha não sai.', case when cardinality(v_fb_os) = 1 then 'A' else 'As' end,
                        public._agenda_lista(array(select so.service_order_number from unnest(v_fb_os) with ordinality u(os, o)
                                                    join public.service_orders so on so.id = u.os order by u.o), null),
                        case when cardinality(v_fb_os) = 1 then 'já está' else 'já estão' end,
                        public._agenda_ficha_os_concluidas_texto(v_fb_os)));
    end if;
    -- FICHA PAGA B: fim
    return jsonb_build_object('ok', true, 'gestor', true, 'pessoa', v_f11_p, 'dia', v_f11_d,
      'texto', case when v_ef ? 'mandar'
                    then format('Combinado: mando a ficha de %s para %s.', public._dia_curto(v_f11_d), v_f11_n)
                    else format('Combinado: não mando a ficha de %s para %s, nem a confirmação da manhã. Fale com %s.',
                                public._dia_curto(v_f11_d), v_f11_n, v_f11_n) end);
  end if;
  -- FASE 7: fim
  -- FASE 7: (7a P12, spec §5.12 e §6.3; AG7-08) o sábado (crítica, sem prazo; a pergunta é do passo sabado):
  --   1) Use o sábado — a variável agenda.sabado só nesta transação (a manhã de sábado de quem tem o padrão de sábado vira útil
  --      no motor, _agenda_contexto do P5, e o validador a aceita) e o replano da OS, de origem dono (agenda_replanejar, "sábado
  --      autorizado"); a variável desliga logo depois. A manhã de sábado que entrou no plano fica dita na disponibilidade da
  --      pessoa (a exceção "vem" daquele sábado, origem dono: o sábado combinado — sem ela a grade diria "sábado só quando vocês
  --      combinam" e a vigia tiraria o dia como "quem ia não está mais livre"), e o texto lembra de combinar com quem vai (a
  --      ficha da equipe só sai para dia útil). O sábado que já começou não vale mais: a pergunta resolve e nada muda.
  --   2) Não use — respondida; nada muda (o atraso, se houver, é a crítica de sempre do motor).
  if v_q.tipo = 'sabado' then
    if v_prazo then
      return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa pergunta não tem prazo: nada mudou.');
    end if;
    select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
    if v_opc is null then
      return jsonb_build_object('ok', false, 'gestor', true,
        'texto', 'Essa opção não existe. As opções são: '
                 || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                       from jsonb_array_elements(v_q.opcoes) o) || '.');
    end if;
    v_ef := coalesce(v_opc -> 'efeito', '{}'::jsonb);
    if not (v_ef ? 'sabado' or v_ef ? 'nao_usar') then
      return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não tem o que fazer: nada mudou.');
    end if;
    select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) into v_nome
      from public.service_orders so left join public.clients cl on cl.id = so.client_id
     where so.id = v_q.service_order_id;
    if v_ef ? 'nao_usar' then
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
      return jsonb_build_object('ok', true, 'gestor', true, 'os', v_q.service_order_id,
        'texto', format('Combinado: não uso o sábado para %s.', v_nome)
                 || case when v_ef ->> 'fim' is not null
                         then format(' O serviço termina %s.', public._dia_curto((v_ef ->> 'fim')::date)) else '' end);
    end if;
    v_f12_sabs := array(select x::date from jsonb_array_elements_text(coalesce(v_ef -> 'sabados', '[]'::jsonb)) x order by 1);
    v_f12_sab := v_f12_sabs[1];
    if v_f12_sab is null or lower(public.agenda_periodo(v_f12_sab, 'manha')) <= p_agora then
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'o sábado já passou: nada mudou'
       where id = v_q.id;
      return jsonb_build_object('ok', false, 'gestor', true, 'sem_condicao', true,
        'texto', format('O sábado %s já passou: não mudei nada.', coalesce(to_char(v_f12_sab, 'DD/MM'), '')));
    end if;
    begin
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
      perform set_config('agenda.sabado', 'on', true);
      v_f12_r := public.agenda_replanejar(array[v_q.service_order_id], 'sábado autorizado', 'dono', p_hoje, p_agora, p_autor);
      perform set_config('agenda.sabado', '', true);
      if not coalesce((v_f12_r ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0098', message = coalesce(v_f12_r ->> 'texto', 'não deu.');
      end if;
    exception when sqlstate 'P0098' then
      -- nada fica (nem a pergunta respondida nem a variável: a subtransação volta tudo)
      perform set_config('agenda.sabado', '', true);
      return jsonb_build_object('ok', false, 'gestor', true,
                                'texto', 'Não consegui usar o sábado: ' || sqlerrm || ' Nada mudou.');
    end;
    -- a manhã de sábado que entrou fica dita na disponibilidade de quem vai (a exceção "vem" daquele sábado, de manhã)
    v_f12_pes := '{}';
    v_f12_sabs := '{}';
    for v_f12_x in
      select a.payee_id, a.dia, public._agenda_nome_curto(py.name) as nome
        from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
       where a.service_order_id = v_q.service_order_id and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
         and a.presenca = 'turno' and a.turno = 'manha' and extract(isodow from a.dia) = 6 and a.dia >= p_hoje
         and a.resultado is null
       group by a.payee_id, a.dia, py.name
       order by a.dia, 3, a.payee_id
    loop
      if not exists (select 1 from public.agenda_disponibilidade d
                      where d.payee_id = v_f12_x.payee_id and d.substituida_em is null and d.periodo @> v_f12_x.dia
                        and d.situacao in ('disponivel', 'confirmada') and (d.turno is null or d.turno = 'manha')) then
        insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, trecho, criado_por)
        values (v_f12_x.payee_id, daterange(v_f12_x.dia, v_f12_x.dia, '[]'), 'manha', 'disponivel', 'dono',
                left(format('sábado de manhã para %s: você autorizou', public._agenda_rotulo_da_os(v_q.service_order_id)), 200),
                left(p_trecho, 300), p_autor);
      end if;
      if not (v_f12_x.nome = any (v_f12_pes)) then v_f12_pes := v_f12_pes || v_f12_x.nome; end if;
      if not (v_f12_x.dia = any (v_f12_sabs)) then v_f12_sabs := v_f12_sabs || v_f12_x.dia; end if;
    end loop;
    if cardinality(v_f12_sabs) = 0 then
      return jsonb_build_object('ok', true, 'gestor', true, 'os', v_q.service_order_id, 'agenda', v_f12_r,
        'texto', 'Refiz a conta com o sábado liberado, mas ele não entrou: ' || coalesce(nullif(v_f12_r ->> 'texto', ''), 'nada mudou.'));
    end if;
    return jsonb_build_object('ok', true, 'gestor', true, 'os', v_q.service_order_id, 'agenda', v_f12_r,
      'sabados', to_jsonb(v_f12_sabs),
      'texto', format('Combinado: uso %s de manhã para %s.', case when cardinality(v_f12_sabs) = 1
                                                                  then 'o sábado ' || to_char(v_f12_sabs[1], 'DD/MM')
                                                                  else 'os sábados ' || public._agenda_lista(array(
                                                                         select to_char(x, 'DD/MM') from unnest(v_f12_sabs) x order by x))
                                                             end, v_nome)
               || coalesce(' ' || nullif(v_f12_r ->> 'texto', ''), '')
               || format(' Combine o sábado com %s: a ficha da equipe só sai para dia útil.', public._agenda_lista(v_f12_pes)));
  end if;
  -- FASE 7: fim
  if v_q.tipo not in ('situacao', 'estimativa') then
    return jsonb_build_object('ok', false, 'gestor', true,
      'texto', case when jsonb_array_length(v_q.opcoes) = 0 then 'Essa pergunta não tem opções: me responda com as suas palavras.'
                    else 'Ainda não sei decidir essa pergunta: nada mudou.' end);
  end if;
  select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
  if v_opc is null then
    return jsonb_build_object('ok', false, 'gestor', true,
      'texto', 'Essa opção não existe. As opções são: '
               || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                     from jsonb_array_elements(v_q.opcoes) o) || '.');
  end if;
  if v_prazo and v_q.opcao_escolhida is not null then
    return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Você já respondeu essa pergunta: o prazo não vale mais.');
  end if;
  v_ef := coalesce(v_opc -> 'efeito', '{}'::jsonb);
  select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) into v_nome
    from public.service_orders so left join public.clients cl on cl.id = so.client_id
   where so.id = v_q.service_order_id;

  if v_ef ? 'dias' then
    -- a condição ainda vale: a pergunta que o gestor faria agora para a OS é esta (o mesmo motivo, os dias ainda não ditos)
    v_agora := public._agenda_gestor_perguntas_da_os(v_q.service_order_id, p_hoje, p_agora, true);
    if (v_agora ->> 'chave') is distinct from v_q.chave then
      v_mot := case when exists (select 1 from public.os_planejamento pl
                                  where pl.service_order_id = v_q.service_order_id and pl.dias is not null)
                    then 'você já disse os dias' else 'não precisa mais: mudou o que falta saber' end;
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = left(v_mot, 200) where id = v_q.id;
      return jsonb_build_object('ok', false, 'gestor', true, 'sem_condicao', true,
                                'texto', format('Não mudei nada: %s.', v_mot));
    end if;
    v_ate := public._dia_curto((v_q.veto_ate at time zone 'America/Sao_Paulo')::date) || ' às '
             || to_char(v_q.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI');
    if v_prazo then
      v_txt := format('Sem resposta sobre %s até %s: %s. *desfaz %s* volta.', v_nome, v_ate, v_ef ->> 'feito', v_nome);
      update public.agenda_perguntas
         set estado = 'resolvida', opcao_escolhida = p_opcao,
             resolvida_motivo = left(format('sem resposta até %s: ficou como eu disse', replace(v_ate, ' às ', ' ')), 200)
       where id = v_q.id;
    else
      v_txt := format('Combinado, %s: %s. *desfaz %s* volta.', v_nome, v_ef ->> 'feito', v_nome);
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
    end if;
    v_acao := public._agenda_gestor_gravar_dias(v_q.service_order_id, (v_ef ->> 'dias')::numeric, v_txt, v_q.id, p_agora);
    if v_acao is null then
      -- (não acontece: a condição acima já viu os dias do dono; se acontecer, nada fica — nem a pergunta respondida)
      raise exception '_agenda_gestor_decidir: os dias do dono já estão gravados' using errcode = 'P0001';
    end if;
    return jsonb_build_object('ok', true, 'gestor', true, 'texto', v_txt, 'acao_id', v_acao, 'os', v_q.service_order_id,
                              'dias', v_ef -> 'dias', 'via', p_via);
  end if;

  if v_prazo then
    -- (a opção que vale sem resposta é sempre a dos dias; outra não se aplica sozinha)
    return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não vale sem resposta: nada mudou.');
  end if;
  if v_ef ? 'dizer' then
    update public.agenda_perguntas set opcao_escolhida = p_opcao, resposta = left(p_trecho, 500) where id = v_q.id;
    return jsonb_build_object('ok', true, 'gestor', true, 'aberta', true,
                              'texto', format('Me diga os dias (ex.: ''%s 3 dias'').', v_nome));
  end if;
  if v_ef ? 'terminou' or v_ef ? 'nao_fazer' then
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = v_q.id;
    return jsonb_build_object('ok', true, 'gestor', true,
      'texto', case when v_ef ? 'terminou' then format('Use *concluiu %s*.', v_nome)
                    else format('Combinado: não marco %s. Para tirar o serviço da carteira, cancele a OS.', v_nome) end);
  end if;
  return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não tem o que fazer: nada mudou.');
end;
$function$;

comment on function public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 7a, P4): o despacho das perguntas do gestor (situacao, estimativa, reavaliar, reestimar, ficha_estimativa, onda, sabado, bem_livre, compre_ate, sinal), chamado por agenda_decidir (o dono) e por _agenda_gestor_vetos (p_via prazo). Só situacao e estimativa decidem aqui (os outros tipos: "não tem opções" ou "ainda não sei decidir", até os pacotes P8, P9, P11 e P12 recriarem ESTA função). Opção com efeito dias: se a pergunta que o gestor faria agora para a OS ainda é esta, grava os dias (_agenda_gestor_gravar_dias; a pergunta respondida pelo dono, ou resolvida "sem resposta até sex 30/10 18:00: ficou como eu disse"); senão resolve a pergunta e nada muda. dizer: fica aberta com a escolha (o prazo não vale mais), "Me diga os dias (ex.: ''Nelson 3 dias'')."; terminou: "Use *concluiu Nelson*."; nao_fazer: "não marco". Só com a pergunta e o modo de quem a fez ligados. Trava agenda_plano. {ok, gestor true, texto, acao_id?, aberta?, sem_condicao?}. Security definer, sem grant a ninguém. FASE 7 (7a P8, spec §5.8): a onda — com a agenda na mesma versão do plano da pergunta, a conta é refeita pelo motor com os parâmetros da proposta dela (agenda_propor persistido, criada_por dono) e aplicada com a pergunta (ações críticas): 1 tudo ("Feito: …"); 2 só as OS de evento real, o de hoje e amanhã (sem nenhuma: "Não havia nada de hoje e amanhã para mudar: não mudei nada."); 3 nada (a proposta descartada; "Combinado: não mudei nada. …"). Com a agenda mudada desde a pergunta, a pergunta resolve e nada muda ("A agenda mudou desde a pergunta: …"). Falhou = nada fica, a pergunta continua aberta. Sem prazo (via prazo: "Essa pergunta não tem prazo"). O P9 e o P12 recriam esta função copiando DESTA migration. FASE 7 (7a P9, spec §5.9 e §6.3): reavaliar (sem prazo) — 1 "Use *concluiu Rodrigo*."; 2 "Me diga o que mais tem para fazer e quantos dias (ex.: ''Rodrigo 2 dias''): eu marco." (as duas respondem); reestimar — só com a condição de agora (a pergunta que a revisão faria para a OS é a mesma: _agenda_gestor_perguntas_da_revisao seco; senão resolve e nada muda): 1 fico com os dias do dono (o prazo: "Sem resposta sobre Nelson até sex 30/10 às 18:00: fiquei com os 4 dias que você disse."; o dono: "Combinado, Nelson: fico com os 4 dias que você disse."); 2 os dias da conta ficam gravados com o sim do dono (estimativa_fonte orcamento, como a opção 1 das perguntas do P4; o histórico e a ação estimar, desfazível) e a agenda acompanha na hora (o corte dos últimos meios-dias do dono, _agenda_gestor_reestimar; ou o encaixe do que falta, _agenda_propor_e_aplicar de origem dono). O P12 recria esta função copiando DESTA migration. FASE 7 (7a P11, spec §5.11 e §6.3; AG7-15): a ficha_estimativa — 1) Mande: respondida ("Combinado: mando a ficha de ter 03/11 para Roberto."), a ficha sai na hora dela; 2) Segure: respondida ("Combinado: não mando a ficha de ter 03/11 para Roberto, nem a confirmação da manhã. Fale com Roberto."), a ficha e a confirmação desse dia ficam recusadas (veto); sem resposta até o prazo (via prazo, o passo vetos), vale a 1 e a pergunta fica resolvida ("sem resposta até sex 30/10 19:30: a ficha vai como eu disse"); a 2 nunca vale sem resposta. FASE 7 (7a P12, spec §5.12 e §6.3; AG7-08): o sábado (crítica, sem prazo) — 1) Use o sábado: a variável agenda.sabado só na transação (a manhã de sábado de quem tem o padrão no motor e no validador) e agenda_replanejar(a OS, "sábado autorizado", dono); a manhã de sábado que entrou fica dita na disponibilidade de quem vai (a exceção "vem" daquele sábado, origem dono) e o texto lembra de combinar ("… Combine o sábado com Roberto: a ficha da equipe só sai para dia útil."); o sábado que já começou resolve a pergunta e nada muda; falhou = nada fica; 2) Não use: respondida, nada muda ("Combinado: não uso o sábado para Nelson. O serviço termina ter 17/11."). Sem prazo (via prazo: "Essa pergunta não tem prazo"). Quem recriar esta função depois copia DESTA migration. FICHA PAGA B (18/11/2026, 20270126100000; correção da revisão da F2b): o *mande* (a 1 da ficha_estimativa) de quem tem OS concluída, faturada ou cancelada no dia fica gravado, mas a resposta é "A OS-00074 já está concluída: a ficha não sai." (a ficha não sai: _agenda_ficha_liberada), e não "Combinado: mando a ficha". O dono e quem não tem OS encerrada: o de antes.';

-- ── 9. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- As 3 leituras novas como a _agenda_ficha_os_pagas da F2: authenticated e service_role, nunca anon. As 7 recriadas mantêm as
-- portas de antes (create or replace não as muda).
revoke all on function public._agenda_os_comecou(uuid, date), public._agenda_ficha_os_concluidas(uuid, date),
                       public._agenda_ficha_os_concluidas_texto(uuid[]) from public, anon;
grant execute on function public._agenda_os_comecou(uuid, date), public._agenda_ficha_os_concluidas(uuid, date),
                          public._agenda_ficha_os_concluidas_texto(uuid[]) to authenticated, service_role;
