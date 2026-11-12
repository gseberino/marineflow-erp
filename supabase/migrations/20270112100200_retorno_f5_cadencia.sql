-- Retorno rápido ao cliente, F5 (P3): a cadência do orçamento enviado (K7) e o vigia do orçamento. Nada liga aqui.
--
-- 1. _orcamento_dia_util_mais e _orcamento_dia_util_antes: o n-ésimo dia útil da agenda depois de um dia e o último dia
--    útil antes dele (agenda_somar_du, a mesma régua da agenda: seg a sex, sem feriado e sem ausência do dono).
-- 2. _orcamento_calendario (K7): lembrete em cadencia_lembrete_du dias úteis depois do envio, véspera no último dia útil
--    antes do vencimento e encerramento cadencia_encerra_du dia útil depois dele, cada passo com o prazo (ate) até o qual
--    espera o *sim <PIN>*. A véspera no dia do envio (ou antes) sai; o lembrete depois da validade, ou no dia da véspera
--    (ou depois), sai. O encerramento nunca sai.
-- 3. _orcamento_inelegivel: o primeiro motivo para não acompanhar (nulo = pode). O telefone de quem_escreve é o inteiro
--    do cadastro que casa com a chave do envio, nunca a chave (com os 8 dígitos o DDD sai nulo).
-- 4. orcamento_acompanhar (C-ACOMP): cria o acompanhamento e os passos do calendário, idempotente.
-- 5. _orcamento_refazer: o reenvio ao cliente com a validade de pé refaz o acompanhamento parado por dono_falou ou
--    validade_mudou; o passo já enviado nunca volta; o aviso da véspera (avisado_em, aviso_fila) é zerado.
-- 6. _orcamento_parar_motivo (C-PARAR): status_mudou, validade_mudou, parar/opt_out, encerrou, cliente_escreveu (qualquer
--    mensagem, contada da hora do envio de verdade), dono_falou (depois da carência), segurado. Só o id da mensagem sai.
-- 7. _orcamento_agendar_passo: a saída do passo em retorno_saidas (emissor orcamento, classe comercial), na próxima hora
--    comercial até o prazo, com a versão v na dedupe_key (o passo refeito ou remarcado nunca esbarra na chave UNIQUE).
-- 8. orcamento_vigia: a rodada de 5 em 5 minutos, com trava (pg_try_advisory_xact_lock). Detecção do aparelho, novos e
--    refeitos, parar, o dia (sombra, cartão ou sozinho só com o aviso da véspera entregue), fim do prazo, encerramento que
--    não saiu, aceites (as funções da P6, dentro de begin … exception when undefined_function) e os efeitos que faltaram
--    (a função da P5, idem). Cada bloco no seu begin … exception: erro nunca trava a fila.
--
-- Sem dado: só funções. Tudo nasce desligado (retorno_config.orcamento_modo = 'desligado': os blocos 2 a 6 não rodam; o
-- cron é da P13). Reverter: drop das funções desta migration (nenhuma outra migration as chama antes da P5).

-- ── 1. Os dias úteis ────────────────────────────────────────────────────────────────────────────────────────────────────

create or replace function public._orcamento_dia_util_mais(p_dia date, p_n integer)
returns date
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_dia is null or p_n is null then
    return null;
  end if;
  if p_n < 1 then
    raise exception using errcode = '22023', message = '_orcamento_dia_util_mais: n tem de ser 1 ou mais';
  end if;
  return public.agenda_somar_du(p_dia, p_n);
end;
$$;

comment on function public._orcamento_dia_util_mais(date, integer) is
  'Retorno F5 (P3.1): o n-ésimo dia útil da agenda (agenda_dia_util) depois de p_dia, por agenda_somar_du. n menor que 1: 22023.';

revoke all on function public._orcamento_dia_util_mais(date, integer) from public, anon, authenticated;

create or replace function public._orcamento_dia_util_antes(p_dia date)
returns date
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_dia is null then
    return null;
  end if;
  return public.agenda_somar_du(p_dia, -1);
end;
$$;

comment on function public._orcamento_dia_util_antes(date) is
  'Retorno F5 (P3.1): o último dia útil da agenda (agenda_dia_util) antes de p_dia, por agenda_somar_du.';

revoke all on function public._orcamento_dia_util_antes(date) from public, anon, authenticated;

-- ── 2. O calendário (K7) ────────────────────────────────────────────────────────────────────────────────────────────────

-- d0 = o dia de Brasília do envio; V = a validade (vale até V, inclusive). Prazo (ate): lembrete até o dia útil anterior
-- ao passo seguinte (sem dia útil entre os dois, o próprio dia); véspera só no dia ("vale até amanhã" mudaria de um dia
-- para o outro); encerramento até 2 dias úteis depois dele.
create or replace function public._orcamento_calendario(p_enviado timestamptz, p_validade date)
returns table (passo text, tipo text, dia date, ate date)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_d0 date;
  v_lembrete date;
  v_vespera date;
  v_encerramento date;
begin
  if p_enviado is null or p_validade is null then
    return;
  end if;
  v_d0 := (p_enviado at time zone c_fuso)::date;
  v_lembrete := public._orcamento_dia_util_mais(v_d0, coalesce(v_cfg.cadencia_lembrete_du, 2)::integer);
  v_vespera := public._orcamento_dia_util_antes(p_validade);
  v_encerramento := public._orcamento_dia_util_mais(p_validade, coalesce(v_cfg.cadencia_encerra_du, 1)::integer);

  -- Nesta ordem: a véspera no dia do envio ou antes sai; o lembrete depois da validade sai; o lembrete no dia da véspera
  -- que ficou, ou depois dela, sai (fica só a véspera). O encerramento nunca sai.
  if v_vespera <= v_d0 then
    v_vespera := null;
  end if;
  if v_lembrete > p_validade then
    v_lembrete := null;
  end if;
  if v_lembrete is not null and v_vespera is not null and v_lembrete >= v_vespera then
    v_lembrete := null;
  end if;

  if v_lembrete is not null then
    passo := 'lembrete';
    tipo := 'orc_lembrete';
    dia := v_lembrete;
    ate := greatest(v_lembrete, public._orcamento_dia_util_antes(coalesce(v_vespera, v_encerramento)));
    return next;
  end if;
  if v_vespera is not null then
    passo := 'vespera';
    tipo := 'orc_vespera';
    dia := v_vespera;
    ate := v_vespera;
    return next;
  end if;
  passo := 'encerramento';
  tipo := 'orc_encerramento';
  dia := v_encerramento;
  ate := public._orcamento_dia_util_mais(v_encerramento, 2);
  return next;
end;
$$;

comment on function public._orcamento_calendario(timestamptz, date) is
  'Retorno F5 (P3.1, K7): os passos do acompanhamento {passo, tipo, dia, ate}. Lembrete = cadencia_lembrete_du dias úteis depois do dia (Brasília) do envio, até o dia útil anterior ao passo seguinte; véspera = o último dia útil antes da validade, só no dia; encerramento = cadencia_encerra_du dia útil depois da validade, até 2 dias úteis depois. Véspera no dia do envio ou antes: sai. Lembrete depois da validade ou no dia da véspera (ou depois): sai.';

revoke all on function public._orcamento_calendario(timestamptz, date) from public, anon, authenticated;

-- ── 3. Quem não é acompanhado ───────────────────────────────────────────────────────────────────────────────────────────

-- O primeiro motivo, na ordem da spec, ou nulo. 'sem_envio' (a mais da spec): a ordem sem orcamento_enviado_em, ou com ele
-- depois de p_agora (ninguém olha o futuro). 'equipe' vem por último: o número da equipe não conta como compartilhado.
create or replace function public._orcamento_inelegivel(p_os uuid, p_agora timestamptz)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_so record;
  v_fone text;
  v_q jsonb;
  v_papel text;
begin
  select so.id, so.client_id, so.status, so.quote_status, so.converted_to_os_at, so.merged_into_id, so.orcamento_enviado_em,
         so.orcamento_enviado_via, so.orcamento_enviado_chave, so.quote_validity_date, so.origem_parceiro_id,
         c.generico, c.whatsapp, c.phone
    into v_so
    from public.service_orders so
    left join public.clients c on c.id = so.client_id
   where so.id = p_os;
  if not found or v_so.status is distinct from 'draft' or v_so.converted_to_os_at is not null or v_so.merged_into_id is not null then
    return 'nao_e_orcamento';
  end if;
  if (v_so.quote_status in ('sent', 'awaiting_approval')) is not true then
    return 'funil';
  end if;
  if v_so.orcamento_enviado_via = 'historico' then
    return 'historico';
  end if;
  if v_so.orcamento_enviado_em is null or v_so.orcamento_enviado_em > v_agora then
    return 'sem_envio';
  end if;
  if v_so.quote_validity_date is null then
    return 'sem_validade';
  end if;
  if v_so.quote_validity_date < (v_so.orcamento_enviado_em at time zone c_fuso)::date + 2 then
    return 'validade_curta';
  end if;
  if coalesce(v_so.generico, false) then
    return 'cliente_final';
  end if;
  if v_so.client_id = any (coalesce(v_cfg.clientes_parceiros, '{}'::uuid[]))
     or (v_so.origem_parceiro_id is not null
         and exists (select 1 from public.parceiros pa where pa.id = v_so.origem_parceiro_id)) then
    return 'parceiro_cliente';
  end if;
  -- A marcação à mão não tem chave; e a chave do envio tem de ser de um número do cadastro (antes de qualquer insert:
  -- orcamento_acompanhamentos.chave é NOT NULL).
  if v_so.orcamento_enviado_chave is null
     or (v_so.orcamento_enviado_chave in (public._agenda_chave_telefone(v_so.whatsapp), public._agenda_chave_telefone(v_so.phone))) is not true then
    return 'destino';
  end if;
  -- O telefone inteiro do cadastro (o mesmo que _orcamento_agendar_passo grava): quem_escreve tira dele a chave e o DDD.
  v_fone := (case when public._agenda_chave_telefone(v_so.whatsapp) = v_so.orcamento_enviado_chave then v_so.whatsapp
                  else v_so.phone end);
  v_q := public.quem_escreve(v_fone);
  v_papel := v_q ->> 'papel';
  if v_papel is distinct from 'equipe'
     and (v_papel is distinct from 'cliente'
          or nullif(v_q ->> 'cliente_id', '')::uuid is distinct from v_so.client_id
          or exists (select 1 from public.parceiro_numeros n
                      where n.chave = v_so.orcamento_enviado_chave and n.situacao <> 'recusado')) then
    return 'numero_compartilhado';
  end if;
  -- Só fala com quem já escreveu.
  if not exists (select 1 from public.whatsapp_messages w
                  where w.direction = 'inbound'
                    and public._agenda_chave_telefone(w.phone_normalized) = v_so.orcamento_enviado_chave
                    and w.occurred_at > v_agora - coalesce(v_cfg.cadencia_conversa, interval '365 days')
                    and w.occurred_at <= v_agora) then
    return 'sem_conversa';
  end if;
  if public.canal_bloqueado(v_fone) is not null then
    return 'opt_out';
  end if;
  if v_papel = 'equipe' then
    return 'equipe';
  end if;
  return null;
end;
$$;

comment on function public._orcamento_inelegivel(uuid, timestamptz) is
  'Retorno F5 (P3.1): o primeiro motivo para não acompanhar o orçamento, ou nulo: nao_e_orcamento, funil, historico, sem_envio (sem orcamento_enviado_em ou com ele depois de p_agora), sem_validade, validade_curta (menos de 2 dias depois do envio), cliente_final, parceiro_cliente, destino (sem chave ou chave fora do cadastro), numero_compartilhado (quem_escreve do telefone inteiro do cadastro não dá este cliente sozinho, ou número de parceiro), sem_conversa (nenhuma recebida em cadencia_conversa), opt_out (canal_bloqueado), equipe.';

revoke all on function public._orcamento_inelegivel(uuid, timestamptz) from public, anon, authenticated;

-- ── 4. Acompanhar (C-ACOMP) ─────────────────────────────────────────────────────────────────────────────────────────────

create or replace function public.orcamento_acompanhar(p_os uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_motivo text;
  v_so record;
  v_id uuid;
  v_passos jsonb;
begin
  v_motivo := public._orcamento_inelegivel(p_os, v_agora);
  if v_motivo is not null then
    return jsonb_build_object('ok', false, 'motivo', v_motivo);
  end if;
  select so.id, so.client_id, so.orcamento_enviado_em, so.orcamento_enviado_chave, so.quote_validity_date
    into v_so from public.service_orders so where so.id = p_os;

  insert into public.orcamento_acompanhamentos (service_order_id, client_id, chave, enviado_em, validade_ate, modo)
  values (v_so.id, v_so.client_id, v_so.orcamento_enviado_chave, v_so.orcamento_enviado_em, v_so.quote_validity_date,
          (case when v_cfg.orcamento_modo = 'ligado' then 'ligado' else 'sombra' end))
  on conflict (service_order_id) do nothing
  returning id into v_id;
  if v_id is null then
    -- Já acompanhado: os passos são os de quando nasceu (ou do refazer), nunca um 2º calendário.
    select a.id into v_id from public.orcamento_acompanhamentos a where a.service_order_id = p_os;
  else
    insert into public.orcamento_passos (acompanhamento_id, passo, tipo, dia, ate)
    select v_id, c.passo, c.tipo, c.dia, c.ate
      from public._orcamento_calendario(v_so.orcamento_enviado_em, v_so.quote_validity_date) c
    on conflict (acompanhamento_id, passo) do nothing;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('passo', p.passo, 'dia', p.dia, 'ate', p.ate) order by p.dia, p.passo), '[]'::jsonb)
    into v_passos
    from public.orcamento_passos p
   where p.acompanhamento_id = v_id;
  return jsonb_build_object('ok', true, 'acompanhamento_id', v_id, 'passos', v_passos);
end;
$$;

comment on function public.orcamento_acompanhar(uuid, timestamptz) is
  'Retorno F5 (P3.1, C-ACOMP): o orçamento elegível (_orcamento_inelegivel nulo) ganha o acompanhamento (modo ligado só com orcamento_modo ligado; enviado_em, validade_ate e chave do 1º envio ao cliente) e os passos de _orcamento_calendario em previsto. Idempotente (on conflict). {ok: true, acompanhamento_id, passos: [{passo, dia, ate}]} ou {ok: false, motivo}, sem gravar nada.';

revoke all on function public.orcamento_acompanhar(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.orcamento_acompanhar(uuid, timestamptz) to service_role;

-- ── 5. O reenvio com a validade de pé refaz o acompanhamento ────────────────────────────────────────────────────────────

-- Só parado por dono_falou ou validade_mudou (nunca por cliente_escreveu, encerrou, parar, opt_out ou segurado: o K7 para
-- com qualquer resposta), com um envio ao cliente na mesma chave depois de enviado_em + cadencia_dono_carencia, até p_agora,
-- e a validade de agora pelo menos 2 dias depois dele (o reenvio não renova a data: D13). Os passos ainda não enviados
-- (previsto, pulado, cancelado) voltam a previsto no calendário novo, sem o aviso da véspera antiga; o enviado não volta.
create or replace function public._orcamento_refazer(p_acomp uuid, p_envio uuid, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_a public.orcamento_acompanhamentos;
  v_e public.orcamento_envios;
  v_so record;
  v_c record;
  v_n integer := 0;
  v_passos jsonb;
begin
  select * into v_a from public.orcamento_acompanhamentos a where a.id = p_acomp for update;
  if not found or v_a.estado is distinct from 'parado' or (v_a.parou_por in ('dono_falou', 'validade_mudou')) is not true then
    return jsonb_build_object('ok', false, 'motivo', 'estado');
  end if;
  select * into v_e from public.orcamento_envios e where e.id = p_envio;
  if not found or v_e.service_order_id is distinct from v_a.service_order_id or not v_e.ao_cliente
     or v_e.chave is distinct from v_a.chave
     or v_e.em <= v_a.enviado_em + coalesce(v_cfg.cadencia_dono_carencia, interval '2 hours')
     or v_e.em > v_agora then
    return jsonb_build_object('ok', false, 'motivo', 'envio');
  end if;
  select so.status, so.converted_to_os_at, so.merged_into_id, so.quote_status, so.quote_validity_date
    into v_so from public.service_orders so where so.id = v_a.service_order_id;
  if not found or v_so.status is distinct from 'draft' or v_so.converted_to_os_at is not null or v_so.merged_into_id is not null
     or (v_so.quote_status in ('sent', 'awaiting_approval')) is not true then
    return jsonb_build_object('ok', false, 'motivo', 'status');
  end if;
  -- Data vencida no reenvio, ou a menos de 2 dias dele: nada se refaz.
  if v_so.quote_validity_date is null or v_so.quote_validity_date < (v_e.em at time zone c_fuso)::date + 2 then
    return jsonb_build_object('ok', false, 'motivo', 'validade');
  end if;

  update public.orcamento_acompanhamentos a
     set enviado_em = v_e.em, validade_ate = v_so.quote_validity_date, estado = 'ativo', parou_por = null, parou_em = null,
         parou_msg_id = null, desfecho_proposto = null, refeito_em = v_agora, atualizado_em = now()
   where a.id = p_acomp and a.estado = 'parado';
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'estado');
  end if;

  for v_c in select c.passo, c.tipo, c.dia, c.ate from public._orcamento_calendario(v_e.em, v_so.quote_validity_date) c loop
    update public.orcamento_passos p
       set dia = v_c.dia, ate = v_c.ate, estado = 'previsto', motivo = null, saida_id = null, avisado_em = null,
           aviso_fila = null, texto_aprovado = null, aprovado_em = null, aprovado_por = null
     where p.acompanhamento_id = p_acomp and p.passo = v_c.passo and p.estado in ('previsto', 'pulado', 'cancelado');
    if found then
      v_n := v_n + 1;
    elsif not exists (select 1 from public.orcamento_passos p where p.acompanhamento_id = p_acomp and p.passo = v_c.passo) then
      -- O passo que o calendário antigo tinha tirado (o lembrete na véspera) e o novo põe.
      insert into public.orcamento_passos (acompanhamento_id, passo, tipo, dia, ate)
      values (p_acomp, v_c.passo, v_c.tipo, v_c.dia, v_c.ate)
      on conflict (acompanhamento_id, passo) do nothing;
      v_n := v_n + 1;
    end if;
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object('passo', p.passo, 'dia', p.dia, 'ate', p.ate, 'estado', p.estado)
                            order by p.dia, p.passo), '[]'::jsonb)
    into v_passos
    from public.orcamento_passos p
   where p.acompanhamento_id = p_acomp;
  return jsonb_build_object('ok', true, 'acompanhamento_id', p_acomp, 'refeitos', v_n, 'passos', v_passos);
end;
$$;

comment on function public._orcamento_refazer(uuid, uuid, timestamptz) is
  'Retorno F5 (P3.1): o reenvio ao cliente (orcamento_envios ao_cliente, mesma chave, depois de enviado_em + cadencia_dono_carencia, até p_agora) com a validade de agora a 2 dias ou mais dele refaz o acompanhamento parado por dono_falou ou validade_mudou: enviado_em = o reenvio, validade_ate = a de agora, ativo; os passos previsto, pulado e cancelado voltam a previsto no calendário novo, com avisado_em e aviso_fila nulos; o enviado não volta. Senão {ok: false, motivo: estado | envio | status | validade}.';

revoke all on function public._orcamento_refazer(uuid, uuid, timestamptz) from public, anon, authenticated;

-- ── 6. Por que parar (C-PARAR) ──────────────────────────────────────────────────────────────────────────────────────────

-- enviado_em é a hora do envio de verdade (no aparelho, a do eco): a resposta mandada entre o PDF e a detecção conta. A
-- mensagem é a do instante: hora real (ou de gravação) depois do envio e até p_agora, gravada até p_agora. O corpo só é lido
-- aqui dentro (encerrou); só o id sai, e o desfecho proposto (fechou_com_outro ou desistiu) no encerrou.
create or replace function public._orcamento_parar_motivo(p_acomp uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_a public.orcamento_acompanhamentos;
  v_so record;
  v_bloq text;
  v_m record;
  v_desde timestamptz;
begin
  select * into v_a from public.orcamento_acompanhamentos a where a.id = p_acomp;
  if not found then
    return null;
  end if;

  -- 1. O orçamento saiu do funil aberto (convertido, agrupado, perdido, cancelado, aprovado).
  select so.status, so.converted_to_os_at, so.merged_into_id, so.quote_status, so.quote_validity_date
    into v_so from public.service_orders so where so.id = v_a.service_order_id;
  if not found or v_so.status is distinct from 'draft' or v_so.converted_to_os_at is not null or v_so.merged_into_id is not null
     or (v_so.quote_status in ('sent', 'awaiting_approval')) is not true then
    return jsonb_build_object('motivo', 'status_mudou', 'msg_id', null, 'em', null);
  end if;

  -- 2. A validade mudou (R19 ou tela): recalcular seria prometer duas vezes; o dono decide.
  if v_so.quote_validity_date is distinct from v_a.validade_ate then
    return jsonb_build_object('motivo', 'validade_mudou', 'msg_id', null, 'em', null);
  end if;

  -- 3. PARAR (o número bloqueado pelo pedido de parar) ou o opt-out do cadastro.
  v_bloq := public.canal_bloqueado(v_a.chave);
  if v_bloq is not null then
    return jsonb_build_object('motivo', (case when v_bloq = 'opt_out' then 'opt_out' else 'parar' end), 'msg_id', null, 'em', null);
  end if;

  -- 4. "Fechei com outro" ou "desisti" depois do envio.
  select w.id, coalesce(w.hora_real, w.occurred_at) as em, w.body
    into v_m
    from public.whatsapp_messages w
   where w.direction = 'inbound'
     and public._agenda_chave_telefone(w.phone_normalized) = v_a.chave
     and w.occurred_at > v_a.enviado_em - interval '1 day'
     and w.occurred_at <= v_agora
     and coalesce(w.hora_real, w.occurred_at) > v_a.enviado_em
     and coalesce(w.hora_real, w.occurred_at) <= v_agora
     and not coalesce(w.is_broadcast, false)
     and public._retorno_encerrou(w.body)
   order by coalesce(w.hora_real, w.occurred_at), w.id
   limit 1;
  if found then
    return jsonb_build_object(
      'motivo', 'encerrou', 'msg_id', v_m.id, 'em', v_m.em,
      'desfecho', (case when public._retorno_busca(v_m.body)
                               ~ '\m(desisti|desistimos|nao (tenho|temos) mais interesse|nao (quero|queremos|vou querer|preciso|precisamos) mais)\M'
                        then 'desistiu' else 'fechou_com_outro' end));
  end if;

  -- 5. Qualquer mensagem do cliente depois do envio, inclusive "ok, obrigado" (K7).
  select w.id, coalesce(w.hora_real, w.occurred_at) as em
    into v_m
    from public.whatsapp_messages w
   where w.direction = 'inbound'
     and public._agenda_chave_telefone(w.phone_normalized) = v_a.chave
     and w.occurred_at > v_a.enviado_em - interval '1 day'
     and w.occurred_at <= v_agora
     and coalesce(w.hora_real, w.occurred_at) > v_a.enviado_em
     and coalesce(w.hora_real, w.occurred_at) <= v_agora
     and not coalesce(w.is_broadcast, false)
   order by coalesce(w.hora_real, w.occurred_at), w.id
   limit 1;
  if found then
    return jsonb_build_object('motivo', 'cliente_escreveu', 'msg_id', v_m.id, 'em', v_m.em);
  end if;

  -- 6. O dono escreveu ao cliente depois da carência (o que ele manda logo depois do PDF é parte do envio). A saída do
  --    próprio retorno (via whatsapp-send com origem de retorno) não é humana (_saida_e_humana).
  v_desde := v_a.enviado_em + coalesce(v_cfg.cadencia_dono_carencia, interval '2 hours');
  select w.id, coalesce(w.hora_real, w.occurred_at) as em
    into v_m
    from public.whatsapp_messages w
   where w.direction = 'outbound'
     and public._agenda_chave_telefone(w.phone_normalized) = v_a.chave
     and w.occurred_at > v_desde - interval '1 day'
     and w.occurred_at <= v_agora
     and coalesce(w.hora_real, w.occurred_at) > v_desde
     and coalesce(w.hora_real, w.occurred_at) <= v_agora
     and coalesce(w.saida_humana, public._saida_e_humana(w.direction, w.raw_payload, w.sent_by))
   order by coalesce(w.hora_real, w.occurred_at), w.id
   limit 1;
  if found then
    return jsonb_build_object('motivo', 'dono_falou', 'msg_id', v_m.id, 'em', v_m.em);
  end if;

  -- 7. Já parado (o segurado só sai com *solta <número>*).
  if v_a.estado = 'parado' then
    return jsonb_build_object('motivo', v_a.parou_por, 'msg_id', v_a.parou_msg_id, 'em', v_a.parou_em);
  end if;
  return null;
end;
$$;

comment on function public._orcamento_parar_motivo(uuid, timestamptz) is
  'Retorno F5 (P3.1, C-PARAR): {motivo, msg_id, em} (e desfecho no encerrou) ou nulo, nesta ordem: status_mudou, validade_mudou, parar/opt_out (canal_bloqueado da chave), encerrou (_retorno_encerrou), cliente_escreveu (qualquer recebida depois do envio de verdade e até p_agora), dono_falou (saída humana depois de enviado_em + cadencia_dono_carencia), o parou_por do acompanhamento já parado (segurado). Só o id da mensagem sai, nunca o texto.';

revoke all on function public._orcamento_parar_motivo(uuid, timestamptz) from public, anon, authenticated;

-- ── 7. A saída do passo ─────────────────────────────────────────────────────────────────────────────────────────────────

-- enviar_em = a próxima hora comercial a partir de greatest(p_agora, dia + cadencia_hora em Brasília) até o prazo do passo:
-- no mesmo dia comercial antes de cadencia_fim, a própria hora (ou agora); depois dele, cadencia_hora do próximo dia
-- comercial (seg a sex, agenda_dia_util). Sem nenhuma até ate: pulado/fora_da_janela, nada inserido. A versão v na chave
-- (1 + as saídas que o passo já teve) deixa o passo refeito ou remarcado nascer de novo sem esbarrar na dedupe_key UNIQUE.
create or replace function public._orcamento_agendar_passo(p_passo uuid, p_agora timestamptz, p_por text)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_p public.orcamento_passos;
  v_a public.orcamento_acompanhamentos;
  v_fone text;
  v_base timestamptz;
  v_dia date;
  v_em timestamptz;
  v_voltas integer := 0;
  v_modo text;
  v_v integer;
  v_dedupe text;
  v_dados jsonb;
  v_id uuid;
begin
  if p_por is null or p_por not in ('sim', 'sozinho', 'sombra') then
    raise exception using errcode = '22023', message = '_orcamento_agendar_passo: por fora da lista (sim, sozinho, sombra)';
  end if;
  select * into v_p from public.orcamento_passos p where p.id = p_passo for update;
  if not found or v_p.estado not in ('previsto', 'aguarda_sim') then
    return null;
  end if;
  select * into v_a from public.orcamento_acompanhamentos a where a.id = v_p.acompanhamento_id;

  -- O número do cadastro que casa com a chave (o mesmo de _orcamento_inelegivel), só dígitos.
  select regexp_replace((case when public._agenda_chave_telefone(c.whatsapp) = v_a.chave then c.whatsapp else c.phone end),
                        '[^0-9]', '', 'g')
    into v_fone
    from public.clients c
   where c.id = v_a.client_id;
  if v_fone is null or public._agenda_chave_telefone(v_fone) is distinct from v_a.chave then
    update public.orcamento_passos p set estado = 'pulado', motivo = 'erro'
     where p.id = p_passo and p.estado in ('previsto', 'aguarda_sim');
    perform public._retorno_log('orcamento_agendar_passo', 'o cadastro não tem mais o número do acompanhamento', 'error',
                                jsonb_build_object('passo_id', p_passo));
    return null;
  end if;

  v_base := greatest(v_agora, (v_p.dia + v_cfg.cadencia_hora) at time zone c_fuso);
  v_dia := (v_base at time zone c_fuso)::date;
  v_em := null;
  while v_dia <= v_p.ate and v_voltas < 60 loop
    v_voltas := v_voltas + 1;
    if extract(isodow from v_dia) <= 5 and coalesce(public.agenda_dia_util(v_dia), false) then
      v_em := greatest(v_base, (v_dia + v_cfg.cadencia_hora) at time zone c_fuso);
      if (v_em at time zone c_fuso)::date = v_dia and (v_em at time zone c_fuso)::time < v_cfg.cadencia_fim then
        exit;
      end if;
      v_em := null;
    end if;
    v_dia := v_dia + 1;
  end loop;
  if v_em is null then
    update public.orcamento_passos p set estado = 'pulado', motivo = 'fora_da_janela'
     where p.id = p_passo and p.estado in ('previsto', 'aguarda_sim');
    return null;
  end if;

  -- Em sombra (o acompanhamento, ou o tipo ainda desligado) a chave ganha ':sombra': a real fica livre para quando ligar.
  v_modo := (case when v_a.modo = 'sombra' or p_por = 'sombra' then 'sombra' else 'ligado' end);
  select count(*)::integer + 1 into v_v
    from public.retorno_saidas s
   where s.emissor = 'orcamento' and s.dados ->> 'passo_id' = p_passo::text;
  v_dedupe := 'orcamento:' || v_a.id || ':' || v_p.passo || ':' || v_v || (case when v_modo = 'sombra' then ':sombra' else '' end);
  v_dados := jsonb_build_object('acompanhamento_id', v_a.id, 'passo_id', v_p.id, 'os_id', v_a.service_order_id, 'por', p_por)
             || (case when p_por = 'sim' then jsonb_build_object('texto_aprovado', v_p.texto_aprovado) else '{}'::jsonb end)
             || (case when p_por = 'sozinho' then jsonb_build_object('sozinho', true) else '{}'::jsonb end);

  insert into public.retorno_saidas (emissor, abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo,
                                     estado, enviar_em, dados, dedupe_key)
  values ('orcamento', null, v_p.tipo, 'retorno_orcamento', 'comercial', v_a.chave, v_fone, v_a.client_id, v_modo,
          'agendada', v_em, v_dados, v_dedupe)
  on conflict (dedupe_key) do nothing
  returning id into v_id;
  if v_id is null then
    update public.orcamento_passos p set estado = 'pulado', motivo = 'erro'
     where p.id = p_passo and p.estado in ('previsto', 'aguarda_sim');
    perform public._retorno_log('orcamento_agendar_passo', 'a chave da saída já existia: ' || v_dedupe, 'error',
                                jsonb_build_object('passo_id', p_passo));
    return null;
  end if;
  update public.orcamento_passos p set estado = 'agendado', saida_id = v_id where p.id = p_passo;
  return v_id;
end;
$$;

comment on function public._orcamento_agendar_passo(uuid, timestamptz, text) is
  'Retorno F5 (P3.1): agenda a saída do passo (previsto ou aguarda_sim) em retorno_saidas: emissor orcamento, abertura nula, tipo do passo, origem retorno_orcamento, classe comercial, o número do cadastro que casa com a chave, modo sombra (acompanhamento em sombra ou p_por = sombra) ou ligado, enviar_em na próxima hora comercial até ate, dados {acompanhamento_id, passo_id, os_id, por, texto_aprovado (sim), sozinho (sozinho)}, dedupe_key orcamento:<acomp>:<passo>:<v>[:sombra]. Sem hora até ate: pulado/fora_da_janela. Chave repetida ou cadastro sem o número: pulado/erro e log. Devolve o id da saída ou nulo.';

revoke all on function public._orcamento_agendar_passo(uuid, timestamptz, text) from public, anon, authenticated;

-- ── 8. O vigia ──────────────────────────────────────────────────────────────────────────────────────────────────────────

create or replace function public.orcamento_vigia(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_cfg public.retorno_config;
  v_r record;
  v_x jsonb;
  v_m jsonb;
  v_motivo text;
  v_cands uuid[];
  v_so record;
  v_fila_ok boolean;
  v_detectar jsonb;
  v_novos integer := 0;
  v_refeitos integer := 0;
  v_parados integer := 0;
  v_sombra integer := 0;
  v_sozinho integer := 0;
  v_cartao integer := 0;
  v_fora integer := 0;
  v_sem_sim integer := 0;
  v_encerrados integer := 0;
  v_aceites integer;
  v_dados integer;
  v_caidos integer := 0;
  v_efeitos integer := 0;
  v_falhas integer := 0;
begin
  -- Uma rodada por vez: a outra pula.
  if not pg_try_advisory_xact_lock(hashtext('orcamento:vigia')) then
    return jsonb_build_object('ok', true, 'pulou', true);
  end if;
  v_cfg := public._retorno_cfg();
  if v_cfg.id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_config');
  end if;

  -- 1. O PDF mandado do aparelho (segue envio_mao_modo).
  begin
    v_detectar := public.orcamento_detectar_envio(v_agora);
  exception when others then
    v_falhas := v_falhas + 1;
    perform public._retorno_log('orcamento_vigia', 'detectar: ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
  end;

  if v_cfg.orcamento_modo is distinct from 'desligado' then
    -- 2. Novos (o 1º envio desde a rodada anterior, fora do histórico) e refeitos (o reenvio com a validade de pé).
    begin
      for v_r in
        select so.id
          from public.service_orders so
         where so.orcamento_enviado_em > v_agora - interval '1 day'
           and so.orcamento_enviado_em <= v_agora
           and so.orcamento_enviado_via is distinct from 'historico'
           and not exists (select 1 from public.orcamento_acompanhamentos a where a.service_order_id = so.id)
         order by so.orcamento_enviado_em, so.id
      loop
        begin
          v_x := public.orcamento_acompanhar(v_r.id, v_agora);
          if coalesce((v_x ->> 'ok')::boolean, false) then
            v_novos := v_novos + 1;
          end if;
        exception when others then
          v_falhas := v_falhas + 1;
          perform public._retorno_log('orcamento_vigia', 'acompanhar: ' || sqlerrm, 'error',
                                      jsonb_build_object('service_order_id', v_r.id, 'sqlstate', sqlstate));
        end;
      end loop;
      for v_r in
        select a.id,
               (select e.id from public.orcamento_envios e
                 where e.service_order_id = a.service_order_id and e.ao_cliente and e.chave = a.chave
                   and e.em > a.enviado_em + coalesce(v_cfg.cadencia_dono_carencia, interval '2 hours')
                   and e.em <= v_agora
                 order by e.em desc, e.id desc
                 limit 1) as envio
          from public.orcamento_acompanhamentos a
         where a.estado = 'parado' and a.parou_por in ('dono_falou', 'validade_mudou')
         order by a.criado_em, a.id
      loop
        continue when v_r.envio is null;
        begin
          v_x := public._orcamento_refazer(v_r.id, v_r.envio, v_agora);
          if coalesce((v_x ->> 'ok')::boolean, false) then
            v_refeitos := v_refeitos + 1;
          end if;
        exception when others then
          v_falhas := v_falhas + 1;
          perform public._retorno_log('orcamento_vigia', 'refazer: ' || sqlerrm, 'error',
                                      jsonb_build_object('acompanhamento_id', v_r.id, 'sqlstate', sqlstate));
        end;
      end loop;
    exception when others then
      v_falhas := v_falhas + 1;
      perform public._retorno_log('orcamento_vigia', 'novos: ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
    end;

    -- 3. Parar: o acompanhamento ativo com motivo para (ou conclui, com o funil fora do aberto); os passos que esperam e as
    --    saídas agendadas dele caem com o motivo da parada (de-para da P5.1).
    begin
      for v_r in select a.id from public.orcamento_acompanhamentos a where a.estado = 'ativo' order by a.criado_em, a.id loop
        begin
          v_m := public._orcamento_parar_motivo(v_r.id, v_agora);
          continue when v_m is null;
          v_motivo := v_m ->> 'motivo';
          update public.orcamento_acompanhamentos a
             set estado = (case when v_motivo = 'status_mudou' then 'concluido' else 'parado' end),
                 parou_por = v_motivo,
                 parou_em = coalesce(nullif(v_m ->> 'em', '')::timestamptz, v_agora),
                 parou_msg_id = nullif(v_m ->> 'msg_id', '')::uuid,
                 desfecho_proposto = (case when v_motivo = 'encerrou' then v_m ->> 'desfecho' end),
                 atualizado_em = now()
           where a.id = v_r.id and a.estado = 'ativo';
          update public.retorno_saidas s
             set estado = 'cancelada', motivo = v_motivo, decidida_em = v_agora, processando_ate = null, atualizada_em = now()
           where s.emissor = 'orcamento' and s.estado = 'agendada' and s.dados ->> 'acompanhamento_id' = v_r.id::text;
          update public.orcamento_passos p
             set estado = 'cancelado'
           where p.acompanhamento_id = v_r.id
             and (p.estado in ('previsto', 'aguarda_sim')
                  or (p.estado = 'agendado'
                      and not exists (select 1 from public.retorno_saidas s
                                       where s.id = p.saida_id
                                         and s.estado in ('preparada', 'enviando', 'sombra', 'enviada', 'incerta'))));
          v_parados := v_parados + 1;
        exception when others then
          v_falhas := v_falhas + 1;
          perform public._retorno_log('orcamento_vigia', 'parar: ' || sqlerrm, 'error',
                                      jsonb_build_object('acompanhamento_id', v_r.id, 'sqlstate', sqlstate));
        end;
      end loop;
    exception when others then
      v_falhas := v_falhas + 1;
      perform public._retorno_log('orcamento_vigia', 'parar: ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
    end;

    -- 4. O dia. O passo previsto com o prazo já passado (o vigia ficou parado) cai fora da janela. Em dia comercial e sem
    --    *segura orcamentos*: sombra (o acompanhamento ou o tipo desligado) → saída em sombra; cartão → aguarda_sim;
    --    sozinho → saída, só com o aviso da véspera entregue (avisado_em e a linha aviso_fila da fila em sent até agora);
    --    sem ele, aguarda_sim (o que sai sozinho sempre teve a chance de ser segurado).
    begin
      update public.orcamento_passos p
         set estado = 'pulado', motivo = 'fora_da_janela'
        from public.orcamento_acompanhamentos a
       where a.id = p.acompanhamento_id and a.estado = 'ativo' and p.estado = 'previsto' and p.ate < v_hoje;
      get diagnostics v_fora = row_count;
      if not coalesce(v_cfg.orcamento_segura, false) and extract(isodow from v_hoje) <= 5
         and coalesce(public.agenda_dia_util(v_hoje), false) then
        for v_r in
          select p.id, p.avisado_em, p.aviso_fila, a.modo, coalesce(t.nivel, 'desligado') as nivel
            from public.orcamento_passos p
            join public.orcamento_acompanhamentos a on a.id = p.acompanhamento_id
            left join public.retorno_modelo_tipos t on t.tipo = p.tipo
           where p.estado = 'previsto' and a.estado = 'ativo' and p.dia <= v_hoje and v_hoje <= p.ate
           order by p.dia, p.id
        loop
          begin
            if v_r.modo = 'sombra' or v_r.nivel = 'desligado' then
              if public._orcamento_agendar_passo(v_r.id, v_agora, 'sombra') is not null then
                v_sombra := v_sombra + 1;
              end if;
            else
              v_fila_ok := v_r.nivel = 'sozinho' and v_r.avisado_em is not null and v_r.avisado_em <= v_agora
                           and v_r.aviso_fila is not null
                           and exists (select 1 from public.whatsapp_send_queue q
                                        where q.id = v_r.aviso_fila and q.status = 'sent' and q.sent_at <= v_agora);
              if v_fila_ok then
                if public._orcamento_agendar_passo(v_r.id, v_agora, 'sozinho') is not null then
                  v_sozinho := v_sozinho + 1;
                end if;
              else
                update public.orcamento_passos p set estado = 'aguarda_sim' where p.id = v_r.id and p.estado = 'previsto';
                v_cartao := v_cartao + 1;
              end if;
            end if;
          exception when others then
            v_falhas := v_falhas + 1;
            perform public._retorno_log('orcamento_vigia', 'dia: ' || sqlerrm, 'error',
                                        jsonb_build_object('passo_id', v_r.id, 'sqlstate', sqlstate));
          end;
        end loop;
      end if;
    exception when others then
      v_falhas := v_falhas + 1;
      perform public._retorno_log('orcamento_vigia', 'dia: ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
    end;

    -- 5. Fim do prazo: o passo à espera do *sim* depois de cadencia_fim do dia ate. Antes disso, continua à espera.
    begin
      update public.orcamento_passos p
         set estado = 'pulado', motivo = 'sem_sim'
        from public.orcamento_acompanhamentos a
       where a.id = p.acompanhamento_id and a.estado = 'ativo' and p.estado = 'aguarda_sim'
         and v_agora > ((p.ate + v_cfg.cadencia_fim) at time zone c_fuso);
      get diagnostics v_sem_sim = row_count;
    exception when others then
      v_falhas := v_falhas + 1;
      perform public._retorno_log('orcamento_vigia', 'prazo: ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
    end;

    -- 6. O encerramento que não saiu (qualquer motivo): encerrado sem mensagem, com "sumiu" proposto. Nunca marca perdido.
    begin
      update public.orcamento_acompanhamentos a
         set estado = 'encerrado', encerramento = 'sem_mensagem', desfecho_proposto = 'sumiu', atualizado_em = now()
       where a.estado = 'ativo'
         and exists (select 1 from public.orcamento_passos p
                      where p.acompanhamento_id = a.id and p.passo = 'encerramento' and p.estado = 'pulado');
      get diagnostics v_encerrados = row_count;
    exception when others then
      v_falhas := v_falhas + 1;
      perform public._retorno_log('orcamento_vigia', 'encerramento: ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
    end;
  end if;

  -- 7. Os aceites (P6; seguem aceite_modo, aceite_audio e dados_nota_ligado) e o aceite que perdeu o objeto.
  begin
    v_aceites := public._orcamento_aceites_detectar(v_agora);
  exception
    when undefined_function then
      v_aceites := null;
    when others then
      v_falhas := v_falhas + 1;
      perform public._retorno_log('orcamento_vigia', 'aceites: ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
  end;
  begin
    v_dados := public._orcamento_dados_detectar(v_agora);
  exception
    when undefined_function then
      v_dados := null;
    when others then
      v_falhas := v_falhas + 1;
      perform public._retorno_log('orcamento_vigia', 'dados: ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
  end;
  begin
    for v_r in
      select a.id, a.estado, a.client_id, a.chave, a.candidatos, a.service_order_id, a.executado_em, a.total_visto,
             coalesce(rm.recebida_em, w.hora_real, w.occurred_at) as recebida
        from public.orcamento_aceites a
        left join public.retorno_mensagens rm on rm.whatsapp_message_id = a.whatsapp_message_id
        left join public.whatsapp_messages w on w.id = a.whatsapp_message_id
       where a.estado in ('detectado', 'duvida', 'agenda') and a.criado_em <= v_agora
       order by a.criado_em, a.id
    loop
      begin
        if v_r.estado = 'detectado' and v_r.executado_em is not null then
          -- A ferramenta está convertendo (*1 B* ou *1 D* com *sim <PIN>*). Só depois de 30 minutos sem volta: convertido
          -- depois do *sim* → sem_sinal sem registro (o "Fechado" não saiu); senão, volta à lista.
          if v_r.executado_em < v_agora - interval '30 minutes' then
            select so.service_order_number, so.converted_to_os_at into v_so
              from public.service_orders so where so.id = v_r.service_order_id;
            if v_so.converted_to_os_at is not null and v_so.converted_to_os_at >= v_r.executado_em then
              update public.orcamento_aceites a
                 set estado = 'sem_sinal', decidido_em = v_r.executado_em,
                     resultado = a.resultado || jsonb_build_object('numero', v_so.service_order_number, 'convertido', true,
                                                                   'saida_nao_saiu', 'sem_registro')
               where a.id = v_r.id and a.estado = 'detectado' and a.executado_em = v_r.executado_em;
              if found then
                v_caidos := v_caidos + 1;
              end if;
            else
              update public.orcamento_aceites a set executado_em = null
               where a.id = v_r.id and a.estado = 'detectado' and a.executado_em = v_r.executado_em;
            end if;
          end if;
          continue;
        end if;

        v_cands := coalesce(public._orcamento_candidatos(v_r.client_id, v_r.chave, v_r.recebida, v_agora), '{}'::uuid[]);
        if (v_r.estado = 'detectado' and (v_r.service_order_id is null or not (v_r.service_order_id = any (v_cands))))
           or (v_r.estado in ('duvida', 'agenda') and not (coalesce(v_r.candidatos, '{}'::uuid[]) && v_cands)) then
          update public.orcamento_aceites a
             set estado = 'caiu',
                 resultado = a.resultado || jsonb_build_object(
                   'motivo', 'sem_candidato',
                   'numeros', (select coalesce(jsonb_agg(so.service_order_number order by so.service_order_number), '[]'::jsonb)
                                 from public.service_orders so where so.id = any (coalesce(v_r.candidatos, '{}'::uuid[]))),
                   'quote_status', (select coalesce(jsonb_agg(so.quote_status order by so.service_order_number), '[]'::jsonb)
                                      from public.service_orders so where so.id = any (coalesce(v_r.candidatos, '{}'::uuid[]))))
           where a.id = v_r.id and a.estado = v_r.estado and a.executado_em is null;
          if found then
            v_caidos := v_caidos + 1;
          end if;
        elsif v_r.estado = 'detectado'
              and exists (select 1 from public.retorno_cartao_itens i
                           where i.aceite_id = v_r.id and i.estado = 'caiu' and i.caiu_motivo = 'orcamento_mudou') then
          -- O item caiu no cartão (o retorno_vigia_cartao, pelo _retorno_item_conferir, que não escreve no aceite).
          update public.orcamento_aceites a
             set estado = 'caiu',
                 resultado = a.resultado || jsonb_build_object(
                   'motivo', 'orcamento_mudou', 'total_antes', v_r.total_visto,
                   'total_agora', (select so.grand_total from public.service_orders so where so.id = v_r.service_order_id))
           where a.id = v_r.id and a.estado = 'detectado' and a.executado_em is null;
          if found then
            v_caidos := v_caidos + 1;
          end if;
        end if;
      exception
        when undefined_function then
          raise;
        when others then
          v_falhas := v_falhas + 1;
          perform public._retorno_log('orcamento_vigia', 'aceite: ' || sqlerrm, 'error',
                                      jsonb_build_object('aceite_id', v_r.id, 'sqlstate', sqlstate));
      end;
    end loop;
  exception
    when undefined_function then
      v_caidos := null;
    when others then
      v_falhas := v_falhas + 1;
      perform public._retorno_log('orcamento_vigia', 'aceites caídos: ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
  end;

  -- 8. Os efeitos que faltaram (a saída que o retorno_vigia da F1 decidiu sozinho): _orcamento_aplicar_efeitos (P5) marca
  --    dados.efeitos_f5 e nunca roda duas vezes na mesma saída.
  begin
    for v_r in
      select s.id
        from public.retorno_saidas s
       where s.emissor = 'orcamento'
         and s.estado in ('sombra', 'enviada', 'incerta', 'recusada', 'cancelada')
         and s.decidida_em <= v_agora
         and not (s.dados ? 'efeitos_f5')
       order by s.decidida_em, s.id
       limit 200
    loop
      begin
        perform public._orcamento_aplicar_efeitos(v_r.id, v_agora);
        v_efeitos := v_efeitos + 1;
      exception
        when undefined_function then
          raise;
        when others then
          v_falhas := v_falhas + 1;
          perform public._retorno_log('orcamento_vigia', 'efeitos: ' || sqlerrm, 'error',
                                      jsonb_build_object('saida_id', v_r.id, 'sqlstate', sqlstate));
      end;
    end loop;
  exception
    when undefined_function then
      v_efeitos := null;
    when others then
      v_falhas := v_falhas + 1;
      perform public._retorno_log('orcamento_vigia', 'efeitos: ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
  end;

  return jsonb_build_object(
    'ok', true, 'modo', v_cfg.orcamento_modo, 'detectar', v_detectar, 'novos', v_novos, 'refeitos', v_refeitos,
    'parados', v_parados, 'dia', jsonb_build_object('sombra', v_sombra, 'sozinho', v_sozinho, 'cartao', v_cartao,
                                                    'fora_da_janela', v_fora),
    'sem_sim', v_sem_sim, 'encerrados', v_encerrados, 'aceites', v_aceites, 'dados', v_dados, 'aceites_caidos', v_caidos,
    'efeitos', v_efeitos, 'falhas', v_falhas);
end;
$$;

comment on function public.orcamento_vigia(timestamptz) is
  'Retorno F5 (P3.1): a rodada do orçamento (cron retorno-orcamento, P13), uma por vez (pg_try_advisory_xact_lock; a outra devolve pulou). 1 detecção do aparelho; com orcamento_modo fora de desligado: 2 novos (orcamento_acompanhar) e refeitos (_orcamento_refazer), 3 parar (_orcamento_parar_motivo: parado, ou concluido no status_mudou; passos e saídas agendadas caem), 4 o dia (sombra, cartão → aguarda_sim, sozinho só com o aviso da véspera em sent na fila; prazo vencido → fora_da_janela), 5 aguarda_sim depois de cadencia_fim do ate → sem_sim, 6 encerramento pulado → encerrado sem_mensagem; sempre: 7 aceites e dados (P6) e o aceite que perdeu o objeto (caiu, ou sem_sinal sem registro 30 min depois do *sim*), 8 efeitos que faltaram (P5). Cada bloco no seu begin … exception; função de onda posterior ausente = bloco pulado (nulo na contagem).';

revoke all on function public.orcamento_vigia(timestamptz) from public, anon, authenticated;
grant execute on function public.orcamento_vigia(timestamptz) to service_role;
