-- Agenda: ficha paga, parte B (18/11/2026) — sobre a 20270125100000 (F2)
-- Plano: D:/IA-HBR/agenda-pesquisa/via-os129-1711/plano/F2b/RESUMO.md. Respostas do dono (18/11 ~06:00, cartão da F2):
--   "já começou" = "Só antes de começar": a ficha de OS paga fica segurada só se a OS ainda não começou; depois, pago é adiantamento.
--   "concluída" = "Nunca mandar": OS concluída ou faturada com dia ainda marcado na agenda: a ficha nunca sai, e o dono é avisado.
--   "mande antes da baixa" = "Continua valendo" (como está).
--
-- O que muda:
--   1. _agenda_os_comecou(os, dia), nova: há EVIDÊNCIA de serviço feito na OS antes do dia? Em andamento; check-in antes do dia; um dia
--      da OS antes com resultado cumprido ou parcial (o "como foi", o dono, a diária lançada); a confirmação da manhã de um dia antes
--      respondida "sim" por quem estava na OS; diária aprovada ou paga na OS num dia antes; horas apontadas ou passo da execução iniciado
--      antes. O dia só PLANEJADO na agenda e o "sem registro" da vigia nunca contam (o plano errado de um serviço já feito os gera:
--      o caso OS-00129, revisão do coordenador de 18/11).
--   2. _agenda_ficha_os_pagas (da F2): só a OS paga por inteiro E que ainda não começou. Ela é lida pela liberada, pela pergunta e pela
--      ficha das 19:30: a OS paga que já começou volta à regra de antes (a ficha sai; dentro da janela, a pergunta de sempre).
--   3. _agenda_ficha_os_concluidas(pessoa, dia), nova: as OS concluídas ou faturadas entre as alocações vigentes da pessoa no dia — de
--      QUALQUER alocação (não só a da estimativa): OS concluída não tem serviço a fazer, seja qual for a origem do dia.
--   4. _agenda_ficha_liberada: a pessoa (não o dono) com OS concluída ou faturada no dia nunca tem a ficha (nem a confirmação da manhã,
--      nem a ficha que iria no "como foi"), com ou sem o *mande*.
--   5. _agenda_gestor_fichas: a pergunta da OS paga diz "já está PAGA e ainda não começou: o serviço ainda vai ser feito?"; quem tem OS
--      concluída ou faturada no dia não ganha pergunta (a ficha não sairia de todo jeito); a OS paga e já começada não abre o passo fora
--      da janela.
--   6. _agenda_rotina_ficha: a ficha presa por OS concluída ou faturada diz "Não mandei a ficha de qui 05/11 a Roberto (OS-00074 Lenine):
--      a OS já está concluída. Fale com Roberto." (por = concluida); a pergunta aberta fecha com o motivo dela. No dia misto, o parêntese
--      do aviso (concluída ou paga) cita TODAS as OS do dia, e o porquê nomeia a OS ("a OS-00074 já está paga por inteiro e …").
--   7. _agenda_saude_comunicacao (C4 da revisão da F2): a curta da ficha paga ("… eu seguro a ficha. Para mandar, me diga *mande*.")
--      conta como a do gestor no bloco_grande, como a "Para segurar, me diga.".
-- Toda mudança é ACRÉSCIMO, em blocos "-- FICHA PAGA B: (…) … -- FICHA PAGA B: fim": tirados os blocos B, cada função recriada é a da
-- F2 (ou, na saúde, a de produção), byte a byte (conferir-acrescimo-b.mjs). Os testes de cópia tiram os blocos "-- FICHA PAGA:" e
-- "-- FICHA PAGA B:" (pg_temp.sem_ficha_paga); o bloco B da saúde fica dentro do bloco "-- PRAZO NO BLOCO:", que eles já tiram.
--
-- DESFAZER: D:/IA-HBR/agenda-pesquisa/via-os129-1711/plano/F2b/desfazer.sql (as definições da F2 e a saúde de produção).

-- ── 1. A OS que já começou e as OS concluídas ou faturadas da pessoa no dia ───────────────────────────
create or replace function public._agenda_os_comecou(p_os uuid, p_dia date)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  -- Só EVIDÊNCIA de serviço feito conta. O dia só planejado na agenda (vigente, passado ou não, sem resultado) e o "sem registro" que a
  -- vigia marca no dia que passou NUNCA contam: o plano errado de um serviço já feito gera esses dias (o caso OS-00129).
  select coalesce((
    select -- (1) em andamento: o início registrado na OS
           so.status = 'in_progress'
           -- (2) o check-in (a chegada: a porta da OS ao passar para em andamento, ou a via do técnico lançada) antes do dia
           or (so.check_in_at at time zone 'America/Sao_Paulo')::date < p_dia
           -- (3) um dia da OS antes deste com o serviço feito, no todo ou em parte: o "como foi" respondido, o dono (conversa, tela,
           --     dia feito) ou a diária lançada que marca o dia
           or exists (select 1 from public.agenda_alocacoes a
                       where a.service_order_id = so.id and a.dia < p_dia and a.resultado in ('cumprido', 'parcial'))
           -- (4) a confirmação da manhã de um dia antes deste respondida "sim" por quem estava nessa OS no dia
           or exists (select 1 from public.agenda_equipe_mensagens m
                       where m.tipo = 'confirmar' and m.modo = 'ligado' and m.estado = 'respondida' and m.dia < p_dia
                         and (m.leitura ->> 'tipo' in ('ok', 'presenca')
                              or (m.leitura ->> 'tipo' = 'turnos' and coalesce((m.leitura ->> 'ok')::boolean, false)))
                         and exists (select 1 from public.agenda_alocacoes a
                                      where a.payee_id = m.payee_id and a.dia = m.dia and a.service_order_id = so.id
                                        and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'))
           -- (5) a diária lançada (trabalho normal ou diária, aprovada ou paga, não zero; falta, folga, atestado e feriado não) nessa
           --     OS num dia antes deste
           or exists (select 1 from public.work_shifts ws
                       where ws.data < p_dia and ws.status in ('aprovado', 'pago') and ws.tipo in ('normal', 'diaria')
                         and coalesce(ws.fracao, 1) > 0
                         and (ws.service_order_id = so.id
                              or exists (select 1 from public.work_shift_os wo where wo.shift_id = ws.id and wo.service_order_id = so.id)))
           -- (6) horas apontadas na OS ou um passo da execução iniciado antes deste dia
           or exists (select 1 from public.time_entries t
                       where t.service_order_id = so.id and (t.started_at at time zone 'America/Sao_Paulo')::date < p_dia)
           or exists (select 1 from public.service_order_steps s
                       where s.service_order_id = so.id and (s.started_at at time zone 'America/Sao_Paulo')::date < p_dia)
      from public.service_orders so
     where so.id = p_os), false);
$function$;

comment on function public._agenda_os_comecou(uuid, date) is
  'Agenda de Produção (ficha paga B, 18/11/2026, 20270126100000; resposta do dono "Só antes de começar"): há EVIDÊNCIA de serviço feito na OS antes de p_dia? (1) em andamento (in_progress); (2) check-in antes do dia; (3) um dia da OS antes do dia com resultado cumprido ou parcial (o "como foi", o dono, a diária lançada); (4) a confirmação da manhã de um dia antes respondida "sim" (ok, presença, turnos com ok) por quem estava nessa OS no dia; (5) trabalho normal ou diária aprovada ou paga, não zero, nessa OS (work_shifts.service_order_id ou work_shift_os) num dia antes; (6) horas apontadas (time_entries) ou passo da execução iniciado (service_order_steps) antes do dia. O dia só planejado na agenda e o sem_registro da vigia NUNCA contam. Sem a OS = false. STABLE, invoker (lê com a RLS de quem pergunta); authenticated e service_role.';

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
             and so.status in ('completed', 'invoiced')
           group by a.service_order_id) x;
$function$;

comment on function public._agenda_ficha_os_concluidas(uuid, date) is
  'Agenda de Produção (ficha paga B, 18/11/2026, 20270126100000; resposta do dono "Nunca mandar"): as OS concluídas ou faturadas entre as alocações vigentes da pessoa no dia (publicada ou fixada, sem reserva), de QUALQUER origem do dia (não só a estimativa: OS concluída não tem serviço a fazer), na ordem do dia. Nenhuma = {}. STABLE, invoker; authenticated e service_role.';

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
    -- FICHA PAGA B: (18/11/2026) a pessoa (não o dono) com OS concluída ou faturada no dia (qualquer alocação vigente,
    -- _agenda_ficha_os_concluidas) nunca tem a ficha, nem com o *mande* do dono (resposta "Nunca mandar")
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
  'Agenda de Produção (Fase 7a, P11; AG7-15): a ficha (e a confirmação da manhã) da pessoa no dia pode sair? true fora da janela de veto (marcar_sozinho_desde nulo, ou p_dia fora de [o dia do ligar, + ficha_veto_dias)), para o dono e para o dia sem alocação vigente da pessoa com duracao_fonte orcamento; senão só com a pergunta ficha_estimativa:<pessoa>:<dia> de verdade (modo ligado) mostrada ao dono até p_agora e não segurada (opcao_escolhida distinta de 2). Lida por _agenda_rotina_ficha, _agenda_rotina_como_foi e _agenda_rotina_confirmar (recriadas pelo P11). STABLE, invoker; authenticated e service_role. FICHA PAGA (18/11/2026, 20270125100000; o caso OS-00129): a pessoa (não o dono) com OS paga por inteiro no dia pela estimativa (_agenda_ficha_os_pagas) só tem a ficha, a confirmação da manhã e a ficha do "como foi" com o *mande* do dono de verdade — a pergunta ficha_estimativa:<pessoa>:<dia> de verdade respondida com a 1 por um canal do dono (respondida_via distinta de prazo) até p_agora; o silêncio nunca solta; vale dentro e fora da janela e sem o ligar do gestor. Sem OS paga, o de antes. FICHA PAGA B (18/11/2026, 20270126100000; resposta do dono "Nunca mandar"): a pessoa (não o dono) com OS concluída ou faturada no dia, em qualquer alocação vigente (_agenda_ficha_os_concluidas), nunca tem a ficha, a confirmação da manhã nem a ficha do "como foi", com ou sem o *mande*. A OS paga só segura antes de começar (_agenda_ficha_os_pagas).';

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
       -- FICHA PAGA B: (18/11/2026) quem tem OS concluída ou faturada no dia não ganha pergunta: a ficha nunca sai, nem com o *mande*
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
  'Agenda de Produção (Fase 7a, P11; AG7-15, spec §5.11 e §6.3): o passo diário fichas da rodada do gestor — com o ligar do gestor (marcar_sozinho_desde) e o próximo dia útil dentro das ficha_veto_dias a partir dele, para cada pessoa da rotina (_agenda_contatos_com_plano, sem o dono) com alocação vigente nesse dia de duracao_fonte orcamento e sem a ficha do dia já decidida, a pergunta ficha_estimativa (chave ficha_estimativa:<pessoa>:<dia>; veto_ate = hoje às equipe_hora_ficha; opções 1 Mande / 2 Segure; recomendação e padrão 1): "Hoje às 19:30 a ficha de amanhã vai para Roberto: Lenine, ter 03/11 o dia todo — dia 1 de 6, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele." (o dia que não é amanhã pelo nome: "a ficha de terça"). O modo é o de _agenda_modo_da_pergunta(''ficha_estimativa'') — o das mensagens à equipe; desligado, fora da janela, depois da hora da ficha ou fora de dia útil = {pulado}. {dia, prazo, modo, perguntas, novas, pessoas [{pessoa, nome, pergunta_id, texto}]}. Invoker, sem grant. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; a ficha prometida a quem não tem telefone): só pergunta a ficha de quem tem para onde ela ir (_agenda_equipe_tem_telefone, a régua de _agenda_equipe_registrar): sem telefone, nenhuma pergunta — a ficha fica segurada às 19:30 e o aviso diz "não tem telefone no cadastro. Fale com Alex.". FICHA PAGA (18/11/2026, 20270125100000; o caso OS-00129): toda pergunta leva o número da OS ("Alex: OS-00129 Fulano, qua 18/11 o dia todo — dia 1 de 1"). Com OS paga por inteiro (_agenda_ficha_os_pagas): "… pela minha estimativa. A OS-00129 já está PAGA por inteiro: o serviço ainda vai ser feito? Sem resposta até 19:30, eu seguro a ficha. 1) Mande; 2) Segure a ficha: eu não mando e você fala com ele (recomendo).", recomendação e padrão 2; fora da janela e sem o ligar do gestor, só pergunta a quem tem OS paga (sem nenhuma, os pulos de antes). A aberta que nasceu antes de a OS ficar paga (padrão 1, sem resposta) fica resolvida ("a OS ficou paga por inteiro depois desta pergunta: perguntei de novo, avisando") e nasce a nova, com o insert do gravador. FICHA PAGA B (18/11/2026, 20270126100000): a pergunta da OS paga diz "A OS-00129 já está PAGA e ainda não começou: o serviço ainda vai ser feito?" (só a OS paga que ainda não começou pergunta e abre o passo fora da janela); quem tem OS concluída ou faturada no dia não ganha pergunta: a ficha não sai de todo jeito.';

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
  -- FICHA PAGA B: (18/11/2026) as OS concluídas ou faturadas da pessoa no dia, todas as OS do dia e o porquê
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
        -- FICHA PAGA B: (18/11/2026) as OS concluídas ou faturadas (qualquer alocação) e TODAS as OS da pessoa no dia, para o aviso
        v_fc_os := public._agenda_ficha_os_concluidas(v_p, v_d);
        v_fb_os := array(select a.service_order_id from public.agenda_alocacoes a
                          where a.payee_id = v_p and a.dia = v_d and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                          group by a.service_order_id order by min(lower(a.periodo)), a.service_order_id);
        v_fb_cli := public._agenda_lista(array(
                      select concat_ws(' ', so.service_order_number, public._agenda_nome_curto(cl.name))
                        from unnest(v_fb_os) with ordinality u(os, o)
                        join public.service_orders so on so.id = u.os left join public.clients cl on cl.id = so.client_id
                       order by u.o), null);
        v_fb_txt := (select case when bool_and(so.status = 'invoiced') then 'faturada'
                                 when bool_and(so.status = 'completed') then 'concluída'
                                 else 'concluída ou faturada' end
                       from public.service_orders so where so.id = any (v_fc_os));
        if cardinality(v_fc_os) > 1 then
          v_fb_txt := replace(replace(v_fb_txt, 'concluída', 'concluídas'), 'faturada', 'faturadas');
        end if;
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
          -- FICHA PAGA B: (18/11/2026) OS concluída ou faturada: a ficha nunca sai ("Não mandei a ficha de qui 05/11 a Roberto (OS-00074
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
          -- FICHA PAGA B: (fecha o "se a OS está concluída ou paga")
          end if;
          -- FICHA PAGA B: fim
          update public.agenda_equipe_mensagens set acao_id = v_f11_a where id = v_f11_m;
        end if;
        -- FICHA PAGA B: (18/11/2026) a pergunta aberta de quem tem OS concluída ou faturada fecha com o motivo dela
        if cardinality(v_fc_os) > 0 then
          update public.agenda_perguntas
             set estado = 'resolvida', resolvida_motivo = 'a OS já estava concluída ou faturada: a ficha não saiu'
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
  'Agenda de Produção (Fase 3, P4): a ficha da véspera (equipe_hora_ficha num dia útil) para o próximo dia útil — não vai a quem já recebeu a ficha desse dia nem a quem recebeu o "como foi hoje?" levando a ficha; o texto de agenda_equipe_ficha, pelo _agenda_equipe_registrar. FASE 7 (7a P11, spec §3.2 "Equipe" e §5.11; AG7-15): com a mensagem de verdade, a ficha que _agenda_ficha_liberada não solta (na janela de veto do ligar, um dia da pessoa marcado pela estimativa sem a pergunta ficha_estimativa mostrada, ou segurada com a 2) fica registrada como recusada (veto) — nada vai à fila nem conta no teto — e, se o dono não soube, a ação equipe da vigia conta no que mudou ("Não mandei a ficha de ter 03/11 a Roberto (Lenine): o dia é pela minha estimativa e você não viu a pergunta antes das 19:30. Fale com Roberto."); a pergunta do dia fecha (resolvida). Fora disso, a de antes, byte a byte. CORREÇÃO 2 DA 7a (a 2ª revisão da etapa; a ficha prometida a quem não tem telefone): a ficha segurada de quem não tem telefone diz o porquê ("Não mandei a ficha de qui 05/11 a Alex (Lenine): o dia é pela minha estimativa e Alex não tem telefone no cadastro. Fale com Alex.", por = sem_telefone); e a pergunta da ficha que fechou "ela foi como eu disse" com a ficha recusada no registro ganha o motivo verdadeiro ("… mas ela não saiu (sem telefone no cadastro)"). FASE 7f (P5): com o convite ligado de verdade, quem tem o convite de amanhã sem o SIM não recebe a ficha (AG7-23); com o previsto ligado de verdade e a equipe ligada, a ficha leva a mudança da semana ("Na semana: sai …; entra …") e, na quinta, o previsto da semana que vem, numa mensagem só, e grava em dias o que a pessoa passa a ter ouvido. Fora disso, a de antes, byte a byte. FICHA PAGA (18/11/2026, 20270125100000): a ficha presa por OS paga por inteiro (_agenda_ficha_liberada) diz o porquê ao dono — "Não mandei a ficha de qua 18/11 a Alex (OS-00129 Fulano): a OS já está paga por inteiro e <porquê>. Fale com Alex.": sem pergunta, "e não consegui te perguntar antes das 19:30" (por = paga_sem_pergunta); pergunta não mostrada, "e você não viu a pergunta" (paga_nao_vista); mostrada sem resposta, "e você não disse *mande*" (paga). Sem telefone, o de antes. A pergunta aberta fecha com o motivo dela ("a OS estava paga por inteiro e você não viu a pergunta | não disse mande: a ficha não saiu"). Fora disso, byte a byte. FICHA PAGA B (18/11/2026, 20270126100000): a ficha presa por OS concluída ou faturada, em qualquer alocação do dia: "Não mandei a ficha de qui 05/11 a Roberto (OS-00074 Lenine): a OS já está concluída. Fale com Roberto." (por = concluida; "faturada", ou "concluída ou faturada", pelo status); a pergunta aberta fecha com "a OS já estava concluída ou faturada: a ficha não saiu". No dia misto, o parêntese cita TODAS as OS do dia e o porquê nomeia a concluída ou a paga ("a OS-00074 já está concluída"). A concluída vence a paga.';

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

-- ── 7. Portas ───────────────────────────────────────────────────────────────────────────────────────────
-- As 2 leituras novas como a _agenda_ficha_os_pagas da F2: authenticated e service_role, nunca anon. As 5 recriadas mantêm as
-- portas de antes (create or replace não as muda).
revoke all on function public._agenda_os_comecou(uuid, date), public._agenda_ficha_os_concluidas(uuid, date) from public, anon;
grant execute on function public._agenda_os_comecou(uuid, date), public._agenda_ficha_os_concluidas(uuid, date) to authenticated, service_role;
