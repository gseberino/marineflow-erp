-- Retorno rápido ao cliente, F4 (P14): medidas, fechamento das 17:30, retenção e o cron. Nada liga aqui.
--
-- 1. parceiro_resumo_fechamento(p_agora): as linhas do parceiro no fechamento das 17:30 (C-FECH-P, P11.2), só contagens e a
--    sigla do parceiro; nunca nome de cliente nem telefone. O fechamento PEDE, não abre: a linha diz *parceiro*, e quem abre
--    o cartão é o dono. Com parceiro_modo = 'desligado', nenhuma linha.
-- 2. parceiro_retencao_rodada(p_agora): a retenção (tabela de P14.1). Chamada pelo parceiro_vigia às 04:00, em qualquer modo
--    (o passo já existe na P7, guardado por to_regprocedure). Passada a parceiro_retencao (180 dias): painel sem linhas,
--    cartão e item sem texto, saída ao parceiro com '[expirado]', pedido sem nome, veículo e número; o cadastro provisório
--    nascido pela MP sem OS fora de rascunho ou cancelada vira 'Cliente pela MP (expirado)', inativo e sem telefone, e a
--    unidade dele 'Veículo (expirado)', inativa. A linha fica, sem dado pessoal. os_interessados e parceiro_vetos não expiram.
-- 3. retorno_f4_medidas: a foto do portão (8.5) e da operação, security_invoker, só para o service_role. Os "0 esperados" leem
--    só o que foi gravado no envio (dados.visibilidade, dados.interessado_ids) e aviso_em; saída expirada (dados = '{}') não
--    conta. Só saída real (modo ligado, enviada ou incerta).
-- 4. O cron retorno-minuto ganha "select public.parceiro_vigia(now());" depois do vigia do retorno (cron.alter_job). Nasce
--    quase no-op: com parceiro_modo = 'desligado', o vigia só relê o veto, fecha cartão vencido e roda a retenção às 04:00.
--
-- A queda das aberturas sobre cliente final não tem coluna aqui (dúvida 12): o indicador indireto é a contagem por semana de
-- retorno_medidas_blocos com cat = 'parceiro_mp' e abertura verdadeiro, lida direto da visão materializada da F0b.
--
-- Reverter sem deploy: update public.retorno_config set parceiro_modo = 'desligado'. O passo do cron fica (o vigia volta a
-- quase no-op). Tirar o passo: cron.alter_job com o comando de 20261123100900_retorno_f2_vigia.sql.

-- ── 1. O fechamento das 17:30 (C-FECH-P) ─────────────────────────────────────────────────────────────────────────────────

create or replace function public.parceiro_resumo_fechamento(p_agora timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_linhas text[] := '{}'::text[];
  v_total integer;
  v_mudaram integer;
  v_n integer;
  r record;
begin
  if v_cfg.id is null or v_cfg.parceiro_modo = 'desligado' then
    return jsonb_build_object('linhas', '[]'::jsonb);
  end if;

  -- O painel que espera o dono hoje, por parceiro: as linhas que saem e quantas mudaram desde o último painel enviado.
  for r in
    select pa.id as parceiro_id, pa.sigla, pp.linhas
      from public.parceiro_paineis pp
      join public.parceiros pa on pa.id = pp.parceiro_id and pa.ativo
     where pp.dia = v_hoje and pp.estado = 'aguardando'
     order by pa.criado_em, pa.id
  loop
    select count(*) into v_total
      from jsonb_array_elements(r.linhas) l
     where l ->> 'fora_por' is null and coalesce(l ->> 'n', '') ~ '^[0-9]{1,3}$';
    if v_total = 0 then
      continue;
    end if;
    select count(*) into v_mudaram
      from jsonb_array_elements(r.linhas) l
     where l ->> 'fora_por' is null and coalesce(l ->> 'n', '') ~ '^[0-9]{1,3}$'
       and not exists (
         select 1
           from public.parceiro_paineis ant, jsonb_array_elements(ant.linhas) la
          where ant.parceiro_id = r.parceiro_id and ant.estado = 'enviado' and ant.dia < v_hoje
            and ant.dia = (select max(a2.dia) from public.parceiro_paineis a2
                            where a2.parceiro_id = r.parceiro_id and a2.estado = 'enviado' and a2.dia < v_hoje)
            and la ->> 'fora_por' is null
            and la ->> 'service_order_id' is not distinct from l ->> 'service_order_id'
            and la ->> 'estado' is not distinct from l ->> 'estado'
            and la ->> 'desde' is not distinct from l ->> 'desde');
    v_linhas := v_linhas || format('Pátio da %s: %s, %s · *parceiro* para liberar', r.sigla,
      case when v_total = 1 then '1 veículo' else v_total || ' veículos' end,
      case when v_mudaram = 0 then 'nenhum mudou' when v_mudaram = 1 then '1 mudou' else v_mudaram || ' mudaram' end);
  end loop;

  -- NÃO MP de hoje, por parceiro (o veto do cliente; o do dono não entra).
  for r in
    select pa.sigla, count(*)::integer as n
      from public.parceiro_vetos pv
      join public.parceiros pa on pa.id = pv.parceiro_id
     where pv.origem = 'nao_mp' and (pv.em at time zone c_fuso)::date = v_hoje and pv.em <= v_agora
     group by pa.sigla, pa.criado_em, pa.id
     order by pa.criado_em, pa.id
  loop
    v_linhas := v_linhas || format('NÃO %s: %s hoje', upper(r.sigla), case when r.n = 1 then '1 cliente' else r.n || ' clientes' end);
  end loop;

  -- Vínculos confirmados que ainda não têm aviso (nada aparece ao parceiro sem ele).
  select count(*) into v_n
    from public.os_interessados oi
    join public.parceiros pa on pa.id = oi.parceiro_id and pa.ativo
   where oi.situacao = 'confirmado' and oi.papel is distinct from 'anfitria' and oi.aviso_ao_cliente = 'nao_avisado';
  if v_n > 0 then
    v_linhas := v_linhas || format('Vínculos sem aviso: %s', v_n);
  end if;

  -- Respostas ao aviso que podem ser um "não": a OS fica fora até o dono decidir.
  select count(*) into v_n
    from public.os_interessados oi
    join public.parceiros pa on pa.id = oi.parceiro_id and pa.ativo
   where oi.situacao = 'confirmado' and oi.retido_em is not null and oi.retido_em <= v_agora;
  if v_n > 0 then
    v_linhas := v_linhas || format('Respostas ao aviso para decidir: %s · *parceiro*', v_n);
  end if;

  -- Perguntas do parceiro esperando o dono, por parceiro (ficam na lista até *resolvido*, rr-f1-10).
  for r in
    select pa.sigla, count(*)::integer as n
      from public.parceiro_fila f
      join public.parceiros pa on pa.id = f.parceiro_id and pa.ativo
     where f.tipo = 'pergunta' and f.estado in ('espera', 'no_cartao') and f.criado_em <= v_agora
     group by pa.sigla, pa.criado_em, pa.id
     order by pa.criado_em, pa.id
  loop
    v_linhas := v_linhas || format('%s: %s esperando · *parceiro*', r.sigla,
      case when r.n = 1 then '1 pergunta' else r.n || ' perguntas' end);
  end loop;

  return jsonb_build_object('linhas', to_jsonb(v_linhas));
end;
$$;

comment on function public.parceiro_resumo_fechamento(timestamptz) is
  'Retorno F4 (P11.2, C-FECH-P): as linhas do parceiro no fechamento das 17:30, {linhas: [texto]}. Só a sigla e contagens: painel aguardando de hoje (veículos e quantos mudaram desde o último enviado), NÃO de hoje, vínculos sem aviso, respostas ao aviso retidas e perguntas esperando. Nunca nome de cliente nem telefone. Pede, não abre: o cartão só abre com *parceiro*. desligado: lista vazia.';

revoke all on function public.parceiro_resumo_fechamento(timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_resumo_fechamento(timestamptz) to service_role;

-- ── 2. A retenção (P14.1), às 04:00, pelo parceiro_vigia ──────────────────────────────────────────────────────────────────

create or replace function public.parceiro_retencao_rodada(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_limite timestamptz;
  v_r jsonb := '{}'::jsonb;
  v_erros text[] := '{}'::text[];
  v_n integer;
begin
  if v_cfg.id is null then
    return jsonb_build_object('ok', true, 'rodou', false, 'motivo', 'sem_config');
  end if;
  v_limite := v_agora - v_cfg.parceiro_retencao;

  -- Cada passo isolado: erro nunca trava a retenção dos outros.
  begin
    update public.parceiro_paineis pp
       set linhas = '[]'::jsonb
     where pp.criado_em < v_limite and pp.linhas <> '[]'::jsonb;
    get diagnostics v_n = row_count;
    v_r := v_r || jsonb_build_object('paineis', v_n);
  exception when others then
    v_erros := v_erros || 'paineis'::text;
    perform public._retorno_log('parceiro_retencao', 'parceiro_retencao_rodada (paineis): ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
  end;

  begin
    update public.parceiro_cartao_itens i
       set texto_mostrado = null, retrato = '{}'::jsonb, opcoes = '[]'::jsonb
      from public.parceiro_cartoes c
     where c.id = i.cartao_id and c.criado_em < v_limite
       and (i.texto_mostrado is not null or i.retrato <> '{}'::jsonb or i.opcoes <> '[]'::jsonb);
    get diagnostics v_n = row_count;
    v_r := v_r || jsonb_build_object('cartao_itens', v_n);
    -- texto é not null: o marcador fica no lugar
    update public.parceiro_cartoes c
       set texto = '[expirado]', dados = '{}'::jsonb
     where c.criado_em < v_limite and (c.texto is distinct from '[expirado]' or c.dados <> '{}'::jsonb);
    get diagnostics v_n = row_count;
    v_r := v_r || jsonb_build_object('cartoes', v_n);
  exception when others then
    v_erros := v_erros || 'cartoes'::text;
    perform public._retorno_log('parceiro_retencao', 'parceiro_retencao_rodada (cartoes): ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
  end;

  begin
    -- Só saída que já terminou. O check retorno_saidas_texto exige texto nos estados que saem: o marcador fica no lugar.
    update public.retorno_saidas s
       set texto = case when s.texto is null then null else '[expirado]' end, dados = '{}'::jsonb, atualizada_em = now()
     where s.emissor = 'parceiro' and s.criada_em < v_limite
       and s.estado not in ('agendada', 'preparada', 'enviando')
       and (s.texto is distinct from '[expirado]' and s.texto is not null or s.dados <> '{}'::jsonb);
    get diagnostics v_n = row_count;
    v_r := v_r || jsonb_build_object('saidas', v_n);
  exception when others then
    v_erros := v_erros || 'saidas'::text;
    perform public._retorno_log('parceiro_retencao', 'parceiro_retencao_rodada (saidas): ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
  end;

  begin
    -- O provisório nascido pela MP, sem OS fora de rascunho ou cancelada, ativo ou não (o passo 11 do vigia só arquiva quem
    -- não tem OS nenhuma). Com OS de verdade, fica como está: é o registro do serviço.
    update public.clients c
       set active = false, name = 'Cliente pela MP (expirado)', whatsapp = null, phone = null
     where c.provisorio
       and c.name is distinct from 'Cliente pela MP (expirado)'
       and exists (select 1 from public.parceiro_pedidos pp where pp.client_id = c.id and pp.criado_em < v_limite)
       and not exists (select 1 from public.service_orders so
                        where so.client_id = c.id and so.status not in ('draft', 'cancelled'));
    get diagnostics v_n = row_count;
    v_r := v_r || jsonb_build_object('provisorios', v_n);
    update public.vessels v
       set active = false, name = 'Veículo (expirado)'
     where v.client_id in (select c.id from public.clients c where c.provisorio and c.name = 'Cliente pela MP (expirado)')
       and (v.active or v.name is distinct from 'Veículo (expirado)');
    get diagnostics v_n = row_count;
    v_r := v_r || jsonb_build_object('unidades', v_n);
  exception when others then
    v_erros := v_erros || 'provisorios'::text;
    perform public._retorno_log('parceiro_retencao', 'parceiro_retencao_rodada (provisorios): ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
  end;

  begin
    update public.parceiro_pedidos pp
       set primeiro_nome = null, veiculo = null, whatsapp_informado = null, cadastro_simulado = null, atualizado_em = now()
     where pp.criado_em < v_limite
       and (pp.primeiro_nome is not null or pp.veiculo is not null or pp.whatsapp_informado is not null or pp.cadastro_simulado is not null);
    get diagnostics v_n = row_count;
    v_r := v_r || jsonb_build_object('pedidos', v_n);
  exception when others then
    v_erros := v_erros || 'pedidos'::text;
    perform public._retorno_log('parceiro_retencao', 'parceiro_retencao_rodada (pedidos): ' || sqlerrm, 'error', jsonb_build_object('sqlstate', sqlstate));
  end;

  return jsonb_build_object('ok', cardinality(v_erros) = 0, 'rodou', true, 'limite', v_limite, 'passos', v_r, 'erros', to_jsonb(v_erros));
end;
$$;

comment on function public.parceiro_retencao_rodada(timestamptz) is
  'Retorno F4 (P14.1): a retenção do parceiro, chamada pelo parceiro_vigia às 04:00 em qualquer modo. Passada retorno_config.parceiro_retencao: painel sem linhas; item do cartão sem texto, retrato e opções; cartão e saída ao parceiro (já terminada) com [expirado] e dados vazios; pedido sem nome, veículo, número e simulação; provisório nascido pela MP sem OS fora de rascunho ou cancelada anonimizado e inativo, com a unidade. os_interessados e parceiro_vetos não expiram. Cada passo isolado.';

revoke all on function public.parceiro_retencao_rodada(timestamptz) from public, anon, authenticated;
grant execute on function public.parceiro_retencao_rodada(timestamptz) to service_role;

-- ── 3. A medida (8.5) ──────────────────────────────────────────────────────────────────────────────────────────────────

create or replace view public.retorno_f4_medidas with (security_invoker = on) as
with cfg as (
  select c.parceiro_aviso_espera from public.retorno_config c where c.id
),
-- as saídas ao parceiro que citam vínculo, reais e ainda com o que foi gravado no envio
cita as (
  select s.id, coalesce(s.enviada_em, s.decidida_em, s.atualizada_em) as em, coalesce(s.decidida_em, s.enviada_em, s.atualizada_em) as decidida,
         s.dados
    from public.retorno_saidas s
   where s.emissor = 'parceiro' and s.modo = 'ligado' and s.estado in ('enviada', 'incerta')
     and s.dados <> '{}'::jsonb
     and (s.tipo in ('parceiro_painel', 'parceiro_patio', 'parceiro_eco', 'parceiro_repassar')
          or (s.tipo = 'parceiro_recibo' and coalesce(s.dados ->> 'bloco_patio', '') = 'true'))
     and (case when jsonb_typeof(s.dados -> 'interessado_ids') = 'array' then jsonb_array_length(s.dados -> 'interessado_ids') else 0 end) > 0
),
cita_vinculo as (
  select c.id, c.em, c.decidida, c.dados,
         case when x.v ~ '^[0-9a-fA-F-]{36}$' then x.v::uuid end as interessado_id
    from cita c
    cross join lateral jsonb_array_elements_text(case when jsonb_typeof(c.dados -> 'interessado_ids') = 'array'
                                                      then c.dados -> 'interessado_ids' else '[]'::jsonb end) x(v)
),
docs as (
  -- o eco do aparelho (raw_payload ? data e sem via) de documento a número confirmado de parceiro, depois de confirmado;
  -- só a contagem e o casamento do número no nome, nunca o corpo
  select distinct w.id,
         regexp_match(lower(coalesce(w.raw_payload #>> '{data,message,documentMessage,fileName}', '')),
                      '(?:^|[^a-z0-9])(orc|os)-([0-9]{3,8})(?:[^0-9]|$)') is not null as com_numero,
         exists (select 1 from public.parceiro_envios_a_mao e where e.whatsapp_message_id = w.id) as detectado
    from public.whatsapp_messages w
    join public.parceiro_numeros nn
      on nn.chave = public._agenda_chave_telefone(w.phone_normalized) and nn.situacao = 'confirmado'
   where w.direction = 'outbound' and w.message_type = 'document'
     and w.raw_payload ? 'data' and not (w.raw_payload ? 'via')
     and w.occurred_at >= nn.confirmado_em
),
partes as (
  select
    (select count(*) from public.retorno_saidas s
      where s.emissor = 'parceiro' and s.modo = 'ligado' and s.estado in ('enviada', 'incerta')
        and s.tipo not in ('parceiro_aviso_cliente', 'parceiro_nao_mp_ok')
        and s.texto ~* '(r\$|\mpix\M|\mvalor\M[^0-9]{0,15}[0-9])') as saida_com_valor,
    (select count(*) from public.ai_comms_log l
      where l.audiencia = 'parceiro' and l.status = 'sent'
        and coalesce(substring(l.message_preview from 'papel=([a-z]+)'), '') not in ('contratante', 'pagador')) as doc_sem_papel,
    (select count(*) from public.parceiro_envios_a_mao e
      where e.situacao in ('so_registro', 'perguntada')
         or (e.situacao = 'decidida'
             and not exists (select 1 from public.os_interessados oi
                              where oi.service_order_id = e.service_order_id and oi.parceiro_id = e.parceiro_id
                                and oi.situacao = 'confirmado' and oi.papel in ('contratante', 'pagador')))) as doc_a_mao,
    (select count(*) from docs d where not d.com_numero) as doc_sem_numero
)
select
  (select count(*) from public.os_interessados oi
    where oi.situacao = 'confirmado' and oi.papel is distinct from 'anfitria') as vinculos_confirmados,
  (select count(*) from public.os_interessados oi
    where oi.situacao = 'confirmado' and oi.papel is distinct from 'anfitria' and oi.aviso_ao_cliente = 'nao_avisado') as vinculos_sem_aviso,
  (select count(*) from public.os_interessados oi
     join public.clients c on c.id = oi.client_id
    where oi.situacao = 'confirmado' and oi.papel is distinct from 'anfitria' and oi.aviso_ao_cliente = 'nao_avisado'
      and coalesce(btrim(c.whatsapp), '') = '' and coalesce(btrim(c.phone), '') = '') as base_fraca,
  (select count(*) from public.retorno_saidas s
    where s.tipo = 'parceiro_aviso_cliente' and s.modo = 'ligado' and s.estado = 'enviada') as aviso_enviado,
  (select count(*) from public.retorno_saidas s
    where s.tipo = 'parceiro_aviso_cliente' and s.modo = 'ligado' and s.estado = 'incerta') as aviso_incerto,
  (select count(*) from public.parceiro_vetos pv where pv.origem = 'nao_mp') as nao_mp,
  (select count(*) from public.parceiro_paineis pp where pp.estado = 'enviado') as painel_enviados,
  (select count(*) filter (where not u.editado)
     from (select pp.editado from public.parceiro_paineis pp where pp.estado = 'enviado'
            order by pp.dia desc, pp.criado_em desc limit 10) u) as painel_sem_edicao_10,
  (select p.saida_com_valor + p.doc_sem_papel + p.doc_a_mao + p.doc_sem_numero from partes p) as valor_ou_doc_ao_parceiro,
  (select p.doc_sem_numero from partes p) as doc_sem_numero_no_nome,
  (select count(*) from docs d where d.com_numero and not d.detectado) as doc_mao_sem_deteccao,
  (select count(*) from public.retorno_saidas s
    where s.emissor = 'parceiro' and s.estado = 'recusada' and s.motivo = 'validador') as bloqueios_do_validador,
  (select count(distinct cv.id)
     from cita_vinculo cv
     left join public.os_interessados oi on oi.id = cv.interessado_id
    where not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(cv.dados -> 'visibilidade') = 'array'
                                                              then cv.dados -> 'visibilidade' else '[]'::jsonb end) v
                       where v ->> 'interessado_id' = cv.interessado_id::text and v ->> 'visivel' = 'true')
       or (oi.id is not null and (oi.aviso_em is null or oi.aviso_em > cv.em - (select cfg.parceiro_aviso_espera from cfg))))
    as os_sem_aviso_no_painel,
  (select count(distinct cv.id)
     from cita_vinculo cv
     join public.os_interessados oi on oi.id = cv.interessado_id
    where exists (select 1 from public.parceiro_vetos pv
                   where pv.client_id = oi.client_id and pv.parceiro_id = oi.parceiro_id and pv.em < cv.decidida)
       or oi.veto_do_cliente_em < cv.decidida) as veto_ignorado,
  (select count(distinct cv.id)
     from cita_vinculo cv
     join public.os_interessados oi on oi.id = cv.interessado_id
    where oi.papel = 'anfitria') as anfitria_no_painel,
  (select round(100.0 * count(*) filter (where a.insistencias > 0) / nullif(count(*), 0), 1)
     from public.retorno_aberturas a
    where a.papel = 'parceiro' and a.aberta_em >= now() - interval '56 days') as insistencia_mp_pct,
  (select round((select count(*) from public.parceiro_cartao_itens i where i.decidido_em >= now() - interval '7 days')::numeric
                / nullif((select count(*) from generate_series((now() at time zone 'America/Sao_Paulo')::date - 6,
                                                               (now() at time zone 'America/Sao_Paulo')::date, interval '1 day') d
                           where public.agenda_dia_util(d::date)), 0), 2)) as toques_dia,
  (select round(avg(extract(epoch from (s.enviada_em - a.aberta_em)) / 60.0)::numeric, 1)
     from public.retorno_saidas s
     join public.retorno_aberturas a on a.id = s.abertura_id
    where s.tipo = 'parceiro_recibo' and s.modo = 'ligado' and s.estado = 'enviada') as recibo_parceiro_medio_min,
  (select count(*) from public.retorno_saidas s
    where s.tipo = 'parceiro_patio' and s.estado <> 'cancelada') as patio_pedidos,
  (select count(*) from public.retorno_saidas s
    where s.tipo = 'parceiro_eco' and s.modo = 'ligado' and s.estado = 'enviada') as eco_enviados,
  (select coalesce(jsonb_object_agg(f.fora_por, f.n), '{}'::jsonb)
     from (select l ->> 'fora_por' as fora_por, count(*) as n
             from public.parceiro_paineis pp, jsonb_array_elements(pp.linhas) l
            where pp.dia >= (now() at time zone 'America/Sao_Paulo')::date - 7 and l ->> 'fora_por' is not null
            group by 1) f) as linhas_fora_painel;

comment on view public.retorno_f4_medidas is
  'Retorno F4 (P14.1): a foto do portão de saída (8.5) e da operação do parceiro. Os "0 esperados" (valor_ou_doc_ao_parceiro, os_sem_aviso_no_painel, veto_ignorado, anfitria_no_painel) contam só saída real (modo ligado, enviada ou incerta) e leem o que foi gravado no envio; saída expirada (dados = {}) não conta. doc_mao_sem_deteccao fica fora da soma e sem meta. A queda das aberturas sobre cliente final é lida de retorno_medidas_blocos (cat parceiro_mp, abertura).';

revoke all on public.retorno_f4_medidas from public, anon, authenticated;
grant select on public.retorno_f4_medidas to service_role;

-- ── 4. O cron: parceiro_vigia depois do vigia do retorno ─────────────────────────────────────────────────────────────────

-- bancada: pular (início)
do $cron$
declare
  v_job bigint;
  v_cmd text;
  v_ancora text;
  v_n integer;
begin
  if to_regprocedure('public.parceiro_vigia(timestamptz)') is null then
    raise exception 'retorno-minuto: parceiro_vigia(timestamptz) não existe; o passo entra depois dela (20270105100600)';
  end if;
  select j.jobid, j.command into v_job, v_cmd from cron.job j where j.jobname = 'retorno-minuto';
  if v_job is null then
    raise exception 'retorno-minuto: o job não existe (20261116101100 e 20261123100900 sobem antes)';
  end if;
  if position('public.parceiro_vigia(' in v_cmd) > 0 then
    return;   -- já tem o passo
  end if;
  -- Depois do passo do cartão da F2, se houver; senão, logo depois do retorno_vigia. Uma ocorrência só, senão para.
  v_ancora := case when position('select public.retorno_vigia_cartao(now());' in v_cmd) > 0
                   then 'select public.retorno_vigia_cartao(now());' else 'select public.retorno_vigia(now());' end;
  v_n := (char_length(v_cmd) - char_length(replace(v_cmd, v_ancora, ''))) / char_length(v_ancora);
  if v_n is distinct from 1 then
    raise exception 'retorno-minuto: a âncora % aparece % vezes no comando', v_ancora, v_n;
  end if;
  perform cron.alter_job(job_id := v_job, command := replace(v_cmd, v_ancora, v_ancora || E'\n  select public.parceiro_vigia(now());'));
end
$cron$;
-- bancada: pular (fim)
