-- Retorno rápido ao cliente, F1 (sobe no pacote F0b-1 de ter 10/11/2026): o vigia de silêncio de
-- ENTRADA (F0b-8), em sombra.
--
-- O problema (plano B.9): a sessão "zumbi" da Evolution deixa a ENTRADA parada por dias (buracos de
-- 147 h, 97 h e 94 h) enquanto a SAÍDA funciona — o dono responde pelo celular e não percebe que nada
-- chega. O vigia de hoje (whatsapp-conexao) só enxerga a conexão fora e a saída travada; quando o número
-- fica 10 min fora, ele grava o aviso app_notifications.type = 'whatsapp_caiu' no sino (e
-- 'whatsapp_voltou' na volta), com o estado em whatsapp_conexao_vigia.
--
-- 1. retorno_vigia_silencio(agora): em dia útil, das silencio_inicio + silencio_horas até silencio_fim
--    (09:00 + 3 h até 18:00), procura silencio_horas sem nenhuma recebida de fora da equipe COM saída
--    humana no período. Sem saída humana, os dois lados estão quietos: não é sessão zumbi e não registra.
--    - Pela hora de GRAVAÇÃO (occurred_at), de propósito: a ressincronização grava tarde, e é a gravação
--      que para quando a sessão trava (a hora real da F0b mostraria a mensagem "no lugar certo" e
--      esconderia o buraco).
--    - Equipe = a chave de 8 dígitos de app_users.phone_normalized, app_users.phone e payees.phone, de
--      TODAS as linhas (como a consulta r31): a mensagem da equipe não prova que a entrada funciona para
--      cliente. Grupo ('@') e transmissão (is_broadcast) também não contam.
--    - Saída humana = saida_humana (gatilho da F0b) ou, nas gravadas antes de 06/11, _saida_e_humana()
--      pela origem; a desconhecida não conta.
--    - Só REGISTRA, em retorno_silencios (modo 'sombra'), por 2 semanas, para comparar com os avisos
--      whatsapp_caiu: caiu_avisado diz se o vigia de hoje já tinha avisado. Nunca manda nada.
--    - Ninguém olha o futuro (replay): só lê recebidas, saídas e avisos com hora <= agora, o estado da
--      conexão só se ele começou até agora, e só fecha silêncio detectado até agora.
--    - Fecha os abertos (voltou_em = 1ª recebida de fora da equipe depois de desde) em toda chamada,
--      também fora do horário; com silencio_modo = 'desligado' (ou sem a configuração) não faz nada.
--    - Erro vai ao app_error_logs (log_app_error, que agrupa o repetido) e devolve {"acao": "erro"}: não
--      fica calado no cron.job_run_details, que ninguém lê.
--    - O passo 6 (fechar) roda antes da conferência da janela: o resultado é o mesmo da ordem do P8.1
--      (o silêncio registrado agora nunca volta na mesma chamada, porque desde é a última recebida).
-- 2. retorno_silencios_comparados: cada silêncio com caiu_no_periodo (aviso whatsapp_caiu entre desde −
--    30 min e a volta, ou detectado_em + 6 h) e a duração. Só o service_role lê (security_invoker).
-- 3. Cron 'retorno-silencio': a cada 15 min, seg–sex, 12–21 UTC (09:00–18:45 de Brasília). Pura SQL,
--    sem chamada de edge (o incidente de 17/08 foi consulta pesada repetida; esta lê só o dia, por
--    occurred_at).
--
-- Sem dado: nenhuma linha existente muda; retorno_silencios (P1) começa a receber linhas em sombra.
-- Reverter: select cron.unschedule('retorno-silencio'); drop view public.retorno_silencios_comparados;
-- drop function public.retorno_vigia_silencio(timestamptz). Sem deploy: update public.retorno_config
-- set silencio_modo = 'desligado' (o cron segue rodando e devolve {"acao": "desligado"}).

create or replace function public.retorno_vigia_silencio(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_cfg public.retorno_config := public._retorno_cfg();
  v_local timestamp;
  v_dia date;
  v_inicio_local timestamp;
  v_inicio timestamptz;
  v_equipe text[];
  v_desde timestamptz;
  v_saidas int := 0;
  v_voltaram int := 0;
  v_estado text;
  v_caiu boolean;
begin
  -- 1. Sem a configuração ou desligado: nada roda (falha fecha).
  if v_cfg.id is null or v_cfg.silencio_modo is distinct from 'sombra' then
    return jsonb_build_object('acao', 'desligado');
  end if;

  begin
    p_agora := coalesce(p_agora, now());
    v_local := p_agora at time zone 'America/Sao_Paulo';
    v_dia := v_local::date;
    v_inicio_local := v_dia + v_cfg.silencio_inicio;
    v_inicio := v_inicio_local at time zone 'America/Sao_Paulo';

    -- 3. Equipe: a chave de todas as linhas (ativas ou não), como a consulta r31.
    select coalesce(array_agg(distinct e.k), '{}') into v_equipe
      from (select public._agenda_chave_telefone(u.phone_normalized) as k from public.app_users u
            union all
            select public._agenda_chave_telefone(u.phone) from public.app_users u
            union all
            select public._agenda_chave_telefone(p.phone) from public.payees p) e
     where e.k is not null;

    -- 6. Fecha os abertos: a 1ª recebida de fora da equipe depois de desde (até agora). Roda em toda
    --    chamada ligada, também fora do horário, para a volta de um buraco longo ser vista no dia seguinte.
    update public.retorno_silencios s
       set voltou_em = v.voltou
      from (select s2.id,
                   (select min(m.occurred_at)
                      from public.whatsapp_messages m
                     where m.direction = 'inbound'
                       and m.occurred_at > s2.desde and m.occurred_at <= p_agora
                       and m.phone_normalized !~ '@' and not coalesce(m.is_broadcast, false)
                       and not (coalesce(public._agenda_chave_telefone(m.phone_normalized), '') = any (v_equipe))) as voltou
              from public.retorno_silencios s2
             where s2.voltou_em is null and s2.detectado_em <= p_agora) v
     where v.id = s.id and v.voltou is not null;
    get diagnostics v_voltaram = row_count;

    -- 2. Fora do dia útil ou da janela [silencio_inicio + silencio_horas, silencio_fim]: só o passo 6.
    --    A janela é conferida em timestamp (time + interval daria a volta na meia-noite).
    if not coalesce(public.agenda_dia_util(v_dia), false)
       or v_cfg.silencio_horas <= interval '0'
       or v_local < v_inicio_local + v_cfg.silencio_horas
       or v_local > v_dia + v_cfg.silencio_fim then
      return jsonb_build_object('acao', 'fora', 'voltaram', v_voltaram);
    end if;

    -- 4. A última recebida de fora da equipe no dia (pela hora de gravação), nunca antes de silencio_inicio.
    select greatest(v_inicio, max(m.occurred_at)) into v_desde
      from public.whatsapp_messages m
     where m.direction = 'inbound'
       and m.occurred_at >= v_inicio and m.occurred_at <= p_agora
       and m.phone_normalized !~ '@' and not coalesce(m.is_broadcast, false)
       and not (coalesce(public._agenda_chave_telefone(m.phone_normalized), '') = any (v_equipe));

    -- 5. Saídas humanas depois dela (a desconhecida não conta: coalesce dá nulo e o where descarta).
    select count(*) into v_saidas
      from public.whatsapp_messages m
     where m.direction = 'outbound'
       and m.occurred_at > v_desde and m.occurred_at <= p_agora
       and coalesce(m.saida_humana, public._saida_e_humana(m.direction, m.raw_payload, m.sent_by));

    if p_agora - v_desde < v_cfg.silencio_horas or v_saidas = 0 then
      -- Entrada viva, ou os dois lados quietos (não é sessão zumbi): nada a registrar.
      return jsonb_build_object('acao', 'normal', 'desde', v_desde, 'saidas_humanas', v_saidas, 'voltaram', v_voltaram);
    end if;

    -- O estado da conexão só vale se começou até agora (no replay, o estado de hoje é o futuro).
    select c.estado into v_estado
      from public.whatsapp_conexao_vigia c
     where c.desde <= p_agora
     order by c.id
     limit 1;
    -- O vigia de hoje já tinha avisado a queda? (aviso gravado entre desde − 30 min e agora)
    select exists (select 1 from public.app_notifications n
                    where n.type = 'whatsapp_caiu'
                      and n.created_at >= v_desde - interval '30 minutes'
                      and n.created_at <= p_agora)
      into v_caiu;

    insert into public.retorno_silencios (dia, desde, detectado_em, saidas_humanas, conexao_estado, caiu_avisado)
    values (v_dia, v_desde, p_agora, least(v_saidas, 32767)::smallint, v_estado, v_caiu)
    on conflict (dia, desde) do nothing;

    return jsonb_build_object('acao', 'silencio', 'desde', v_desde, 'saidas_humanas', v_saidas, 'voltaram', v_voltaram);
  exception when others then
    perform public.log_app_error('db', format('vigia de silêncio de entrada: %s', sqlerrm), 'retorno', 'vigia_silencio',
                                 'error', jsonb_build_object('agora', p_agora, 'sqlstate', sqlstate));
    return jsonb_build_object('acao', 'erro', 'erro', sqlstate);
  end;
end;
$$;

comment on function public.retorno_vigia_silencio(timestamptz) is
  'Retorno F0b-8 (sombra): em dia útil, na janela do silêncio, registra em retorno_silencios as silencio_horas sem recebida de fora da equipe (hora de gravação) com saída humana no período; fecha os abertos na volta. Nunca manda nada. {"acao": "silencio"|"normal"|"fora"|"desligado"|"erro", "desde", "saidas_humanas", "voltaram"}.';

revoke all on function public.retorno_vigia_silencio(timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_vigia_silencio(timestamptz) to service_role;

-- Cada silêncio comparado com o aviso de queda do vigia de hoje, para as 2 semanas de sombra.
drop view if exists public.retorno_silencios_comparados;
create view public.retorno_silencios_comparados with (security_invoker = on) as
select s.id, s.dia, s.desde, s.detectado_em, s.voltou_em, s.saidas_humanas, s.conexao_estado, s.caiu_avisado, s.modo,
       exists (select 1 from public.app_notifications n
                where n.type = 'whatsapp_caiu'
                  and n.created_at >= s.desde - interval '30 minutes'
                  and n.created_at <= coalesce(s.voltou_em, s.detectado_em + interval '6 hours')) as caiu_no_periodo,
       coalesce(s.voltou_em, now()) - s.desde as duracao
  from public.retorno_silencios s;

comment on view public.retorno_silencios_comparados is
  'Retorno F0b-8 (sombra): cada silêncio de entrada com caiu_no_periodo (aviso whatsapp_caiu entre desde − 30 min e a volta, ou detectado_em + 6 h) e a duração. Só o service_role lê.';

-- Só leitura, só o service_role (o padrão do Supabase daria tudo a anon, authenticated e service_role).
revoke all on public.retorno_silencios_comparados from public, anon, authenticated, service_role;
grant select on public.retorno_silencios_comparados to service_role;

-- A cada 15 min, seg–sex, 12–21 UTC (09:00–18:45 de Brasília). Pura SQL, sem chamada de edge.
select cron.unschedule(jobid) from cron.job where jobname = 'retorno-silencio';
select cron.schedule('retorno-silencio', '*/15 12-21 * * 1-5', $c$select public.retorno_vigia_silencio(now())$c$);
