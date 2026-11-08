-- Retorno rápido ao cliente, F1 (sobe no pacote F0b-1 de ter 10/11/2026): a configuração do retorno e
-- a identificação nova do webhook.
--
-- 1. retorno_config: UMA linha (como agenda_config) com o modo geral, a lista fechada dos tipos que
--    podem sair ligados, as janelas de resposta (K3), os momentos do dono e a hora que cada um sustenta
--    (B.4.1), a carência adaptativa (K2), os tetos (B.6, J.10), o relógio (E.4) e os interruptores
--    (J.11). Nasce em SOMBRA e com todos os tipos desligados: o retorno só registra "eu teria mandado".
--    - "urgente" e "acorde" ficam fora da lista: só entram com o acorde real (leva própria, que alarga
--      o check). Ligar é sempre por grupo (E.6): recibo sem adiamento e fim do dia deixaria a promessa
--      vencer calada; coleta sem o recibo de número novo, e cadastro provisório sem a coleta, também
--      não ligam — os checks do grupo barram no banco, não na memória de quem liga.
--    - clientes_parceiros já nasce com a MP MOTOR HOMES e a Fortroendehus (Förtro), cadastradas como
--      clientes: ficam fora do recibo e do lote de vínculos até o recibo de parceiro (F4) — dúvida 1,
--      recomendado sim. Sem FK, de propósito: num banco sem esses cadastros a lista só não casa nada.
--    - identificacao_nova (F0b-1) nasce falsa: liga em 11/11, com o OK do dono, depois do portão da
--      sombra do quem_sombra (F0b).
--    Esta é a ÚNICA linha de dado da migration. Só o service_role muda a linha; o painel só lê
--    (admin e financeiro).
--
-- 2. _retorno_cfg(): a linha, para as funções do retorno. Linha ausente devolve nulo, e quem chama trata
--    (cfg).id nulo como "desligado" (falha fecha).
--
-- 3. retorno_identificar(fone): F0b-1, o que o webhook usa no lugar do ILIKE + maybeSingle de hoje
--    (que acha 4 dos 22 números de cliente). Desligada (ou sem a linha): {"nova": false}, e o webhook
--    segue o caminho de hoje. Ligada: o papel de quem_escreve (F0b) e o client_id SÓ quando o papel é
--    "cliente" — ambíguo, equipe, fornecedor e número novo devolvem client_id nulo: o número de dois
--    clientes nunca ganha o cadastro de um deles. Erro de quem_escreve SOBE (nunca vira "não
--    identificado" calado), e o webhook cai no ILIKE.
--
-- Reverter (depois das migrations seguintes da F1): drop function public.retorno_identificar(text),
-- public._retorno_cfg(); drop table public.retorno_config. Sem deploy: update public.retorno_config set
-- identificacao_nova = false (a identificação volta ao ILIKE) ou modo = 'desligado' (o retorno para).

create table if not exists public.retorno_config (
  id boolean primary key default true check (id),
  -- modo geral: 'desligado' = nada roda nem registra; 'sombra' = registra "eu teria mandado";
  -- 'ligado' = manda os tipos de tipos_ligados que passarem em _retorno_modo_efetivo (os outros seguem em sombra)
  modo text not null default 'sombra' check (modo in ('desligado', 'sombra', 'ligado')),
  -- lista fechada (molde agenda_config.cliente_tipos_ligados); TODOS desligados = sombra.
  -- 'urgente' e 'acorde' não entram: só ligam com o acorde real (leva própria, que alarga este check).
  tipos_ligados text[] not null default '{}' check (tipos_ligados <@ array[
    'recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'coleta_numero_novo',
    'saudacao_numero_novo', 'adiamento', 'fim_do_dia', 'parar', 'cadastro_provisorio']::text[]),
  -- K3: resposta a quem escreveu, todo dia, das 07:00 às 21:59 (fim exclusivo)
  cliente_resposta_direta_inicio time not null default '07:00',
  cliente_resposta_direta_fim    time not null default '22:00',
  -- K3: fora da janela, o recibo sai às 08:00 (domingo e feriado 09:00), espalhado em 30 min
  manha_recibo       time not null default '08:00',
  manha_recibo_folga time not null default '09:00',
  manha_espalhar interval not null default '30 minutes',
  -- resposta atrasada (adiamento, fim do dia): seg–sex 08:00–19:59, sáb 08:00–12:59, nunca dom/feriado
  atrasada_inicio     time not null default '08:00',
  atrasada_fim        time not null default '20:00',
  atrasada_sabado_fim time not null default '13:00',
  -- B.4.1: os momentos do dono e a hora que cada um sustenta
  ponto_manha      time not null default '07:30',
  ponto_meio_dia   time not null default '12:30',
  ponto_fechamento time not null default '17:30',
  promessa_manha      time not null default '10:00',
  promessa_meio_dia   time not null default '14:00',
  promessa_fechamento time not null default '19:00',
  meio_dia_ligado boolean not null default false,   -- K5 = ligado, mas o meio-dia só existe na F2
  corte_meio_dia time not null default '11:00',     -- antes disto, promete o meio-dia (se ligado)
  corte_tarde    time not null default '15:30',     -- a partir disto, promete a manhã seguinte
  -- B.4.1: calibração aprovada pelo dono e alongamento automático (P3, P6.2 passo 13).
  -- {"<faixa>": {"dias": 0|1, "hora": "HH:MM"}}; só alonga (nunca encurta); '{}' = a tabela do P3.
  promessa_faixa jsonb not null default '{}' check (jsonb_typeof(promessa_faixa) = 'object'),
  alongar_janela       interval not null default '30 days',
  alongar_minimo_casos smallint not null default 20 check (alongar_minimo_casos >= 5),
  alongar_meta         numeric(3,2) not null default 0.80 check (alongar_meta between 0.5 and 0.99),
  -- K2: carência adaptativa (B.8)
  carencia_min            smallint not null default 2  check (carencia_min between 1 and 30),
  carencia_dono_ativo_min smallint not null default 10 check (carencia_dono_ativo_min between 1 and 60),
  dono_ativo_janela_min   smallint not null default 15 check (dono_ativo_janela_min between 1 and 60),
  lote_linhas_por_min     smallint not null default 10 check (lote_linhas_por_min >= 3),
  lote_janela_min         smallint not null default 3  check (lote_janela_min between 1 and 15),
  saudacao_espera_min     smallint not null default 10 check (saudacao_espera_min between 1 and 60),
  audio_espera_min        smallint not null default 3  check (audio_espera_min between 0 and 15),
  audio_reavaliar_max     interval not null default '24 hours',   -- B.2: a transcrição reavalia por 24 h
  robo_resposta_s         smallint not null default 5  check (robo_resposta_s between 1 and 30),  -- B.2: "< 5 s"
  -- tetos (B.6, J.10)
  respostas_dia_max      smallint not null default 40 check (respostas_dia_max between 0 and 200),
  recibo_intervalo       interval not null default '12 hours',
  coleta_max             smallint not null default 2 check (coleta_max between 0 and 2),   -- mensagens no 1º contato
  saudacao_intervalo     interval not null default '30 days',
  apresentacao_intervalo interval not null default '30 days',   -- K4
  volta_min           interval not null default '10 minutes',
  volta_max           interval not null default '24 hours',
  volta_por_volta_max smallint not null default 10,
  espaco_min_s smallint not null default 30,
  espaco_max_s smallint not null default 90,
  proximo_envio_em timestamptz,
  -- relógio (E.4)
  adiamento_antes     interval not null default '30 minutes',
  acorde_antes        interval not null default '60 minutes',
  insistencia_apos    interval not null default '60 minutes',
  caso_fecha_silencio interval not null default '4 hours',
  -- (08/11/2026, cartão F1-10 do dono: "fica na lista até eu resolver") nulo = o caso nunca fecha por idade; só por
  -- conteúdo, silêncio ou nada. Um número de 1 a 10 volta à regra antiga (fecha depois de N dias úteis sem recebida).
  expira_dias_uteis   smallint default null check (expira_dias_uteis is null or expira_dias_uteis between 1 and 10),
  incerta_conferir_ate interval not null default '30 minutes',
  conteudo_min_caracteres smallint not null default 15,
  -- interruptores (J.11)
  so_reativo boolean not null default false,
  so_reativo_motivo text check (so_reativo_motivo in ('conexao', 'erros')),
  so_reativo_desde timestamptz,
  erros_seguidos smallint not null default 0,
  fora_ate date,                  -- "fora até <dia>": o 1º dia em que o dono volta a responder
  segura_recibos boolean not null default false,
  segura_tudo_ate timestamptz,
  fila_modo text not null default 'conta' check (fila_modo in ('conta', 'trava')),
  identificacao_nova boolean not null default false,   -- F0b-1: liga em 11/11 com OK
  -- F0b-8: vigia de silêncio de entrada
  silencio_modo text not null default 'sombra' check (silencio_modo in ('desligado', 'sombra')),
  silencio_inicio time not null default '09:00',
  silencio_fim    time not null default '18:00',
  silencio_horas  interval not null default '3 hours',
  -- cliente que também é parceiro (MP, Förtro): sem recibo e sem vínculo pelo lote até a F4
  clientes_parceiros uuid[] not null default '{}',
  cadastro_arquivar_apos interval not null default '30 days',
  coleta_retencao interval not null default '180 days',     -- J.12: coleta não convertida
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid references public.app_users(id) on delete set null,
  constraint retorno_config_janela check (cliente_resposta_direta_inicio < cliente_resposta_direta_fim),
  constraint retorno_config_atrasada check (atrasada_inicio < atrasada_sabado_fim and atrasada_sabado_fim <= atrasada_fim),
  constraint retorno_config_pontos check (ponto_manha < promessa_manha and promessa_manha <= corte_meio_dia
                                          and ponto_meio_dia < promessa_meio_dia and ponto_fechamento < promessa_fechamento
                                          and corte_meio_dia < corte_tarde and corte_tarde <= ponto_fechamento),
  constraint retorno_config_espaco check (espaco_min_s between 5 and espaco_max_s),
  constraint retorno_config_silencio check (silencio_inicio < silencio_fim),
  constraint retorno_config_so_reativo check (so_reativo = (so_reativo_motivo is not null)
                                              and so_reativo = (so_reativo_desde is not null)),
  -- o grupo do caso liga junto (E.6): recibo sem adiamento e fim do dia deixaria a promessa vencer calada
  constraint retorno_config_grupo_recibo check (
    not (tipos_ligados && array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo']::text[])
    or tipos_ligados @> array['adiamento', 'fim_do_dia']::text[]),
  constraint retorno_config_grupo_coleta check (
    not ('coleta_numero_novo' = any (tipos_ligados)) or 'recibo_numero_novo' = any (tipos_ligados)),
  constraint retorno_config_grupo_cadastro check (
    not ('cadastro_provisorio' = any (tipos_ligados)) or 'coleta_numero_novo' = any (tipos_ligados))
);

comment on table public.retorno_config is 'Retorno F1: configuração e interruptores do retorno rápido (uma linha). Só o service_role muda.';
comment on column public.retorno_config.tipos_ligados is
  'Retorno F1: os tipos que podem sair ligados com modo = ''ligado'' (lista fechada; vazia = tudo em sombra). Liga por grupo: os checks retorno_config_grupo_* barram o recibo sem adiamento e fim do dia, a coleta sem o recibo de número novo e o cadastro provisório sem a coleta.';
comment on column public.retorno_config.clientes_parceiros is
  'Retorno F1: clientes que também são parceiros (MP, Förtro): sem recibo e fora do lote de vínculos até a F4. Sem FK, de propósito.';
comment on column public.retorno_config.identificacao_nova is
  'Retorno F0b-1: true = o webhook identifica pelo retorno_identificar (quem_escreve); false = o ILIKE de hoje.';

-- Dúvida 1 (recomendado: sim): MP MOTOR HOMES e Fortroendehus (Förtro) ficam fora do recibo e do lote até a F4.
-- Se o dono disser não: update public.retorno_config set clientes_parceiros = '{}';
insert into public.retorno_config (id, clientes_parceiros)
values (true, array['ad4fea63-50af-45a3-b5ea-8724e63a5cb0', '0ca417b8-711b-481c-9d3d-5b9c629cd99a']::uuid[])
on conflict (id) do nothing;

-- Leitura só no painel de admin e financeiro (molde agenda_cliente_mensagens); escrita só o service_role.
alter table public.retorno_config enable row level security;

drop policy if exists retorno_config_leitura on public.retorno_config;
create policy retorno_config_leitura on public.retorno_config
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));

revoke all on table public.retorno_config from public, anon, authenticated;
grant select on table public.retorno_config to authenticated;
grant all on table public.retorno_config to service_role;

create or replace function public._retorno_cfg() returns public.retorno_config
  language sql stable security definer set search_path = public
  as $$ select c from public.retorno_config c where c.id $$;

comment on function public._retorno_cfg() is
  'Retorno F1: a linha de retorno_config; ausente = nulo, e quem chama trata (cfg).id nulo como desligado.';

revoke all on function public._retorno_cfg() from public, anon, authenticated;

create or replace function public.retorno_identificar(p_fone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_cfg public.retorno_config := public._retorno_cfg();
  q jsonb;
begin
  -- Desligada ou sem a linha: o webhook segue o ILIKE de hoje.
  if v_cfg.id is null or not v_cfg.identificacao_nova then
    return jsonb_build_object('nova', false);
  end if;

  -- Erro aqui sobe de propósito: o webhook trata a exceção caindo no caminho de hoje.
  q := public.quem_escreve(p_fone);

  -- Só o papel "cliente" (1 cadastro ativo, mesmo DDD) dá client_id. Ambíguo nunca escolhe.
  return jsonb_build_object(
    'nova', true,
    'papel', q ->> 'papel',
    'client_id', case when q ->> 'papel' = 'cliente' then (q ->> 'cliente_id')::uuid end,
    'clientes', case when jsonb_typeof(q -> 'clientes') = 'array' then q -> 'clientes' else '[]'::jsonb end);
end;
$$;

comment on function public.retorno_identificar(text) is
  'Retorno F0b-1: {"nova": false} com a identificação nova desligada; ligada, {"nova": true, papel, client_id (só no papel cliente), clientes} pelo quem_escreve. Erro sobe (o webhook cai no ILIKE).';

revoke all on function public.retorno_identificar(text) from public, anon, authenticated;
grant execute on function public.retorno_identificar(text) to service_role;
