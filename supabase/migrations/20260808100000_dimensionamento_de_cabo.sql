-- ═══════════════════════════════════════════════════════════════════════════
-- Dimensionamento de cabo CC — o que dá para calcular e o que não dá
--
-- O dono viu "Cabo flexível 35 mm²" na sugestão do ORÇ-00074 e perguntou se
-- batia com a Blue Sea / ABYC. Resposta honesta: NÃO BATIA COM NADA. Aquele
-- 35 mm² era o produto que eu fixei na regra, e a regra calcula COMPRIMENTO
-- (ida e volta + folga), não bitola. Numa tela de "material sugerido" isso
-- parece recomendação técnica, e não era.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- POR QUE ISTO NÃO TRAZ A TABELA DA ABYC
--
-- A ABYC E-11 exige DOIS critérios independentes, e vale o MAIOR dos dois:
--
--   1. AMPACIDADE — o cabo não pode esquentar. Depende da bitola, da
--      temperatura da isolação (60/75/90/105 °C), de passar ou não por casa
--      de máquinas, e de quantos condutores vão no mesmo feixe.
--   2. QUEDA DE TENSÃO — o equipamento tem que receber tensão. 3% para
--      circuito crítico, até 10% para não crítico.
--
-- A FÓRMULA da queda de tensão é pública e verificável, e está implementada
-- aqui. A TABELA DE AMPACIDADE é norma paga: não está disponível em texto em
-- lugar nenhum, e reproduzi-la de memória seria inventar número que dimensiona
-- cabo de verdade. Cabo subdimensionado esquenta — é risco físico, não erro de
-- orçamento.
--
-- Por isso a ampacidade fica numa tabela VAZIA, para ser preenchida com a
-- fonte na mão (a norma que a HBR tiver, ou o Circuit Wizard da Blue Sea). Até
-- lá o sistema calcula a queda de tensão, DIZ que só calculou metade, e nunca
-- afirma que a bitola está aprovada.
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Queda de tensão — a metade que é aritmética
--
--   CM = (10.75 × I × L_ida_e_volta_pés) / (V × queda%)
--
-- 10.75 é a resistividade do cobre em ohm·circular mil por pé. O comprimento é
-- de IDA E VOLTA: o positivo vai e o negativo volta, e a corrente atravessa os
-- dois. Quem calcula com o comprimento simples erra por 2 — é o erro clássico.
--
-- 1 mm² = 1973,53 circular mils (π/4 × 0,0254² mm por circular mil). Conversão
-- geométrica, não tabela.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.dc_cable_min_mm2_by_drop(
  p_amps numeric,
  p_one_way_meters numeric,
  p_volts numeric default 12,
  p_max_drop_pct numeric default 3)
returns numeric
language sql immutable set search_path = public
as $fn$
  select case
    when p_amps is null or p_one_way_meters is null
      or p_amps <= 0 or p_one_way_meters <= 0
      or coalesce(p_volts,0) <= 0 or coalesce(p_max_drop_pct,0) <= 0
    then null
    else round(
      (10.75 * p_amps * (p_one_way_meters * 2 * 3.28084))
      / (p_volts * (p_max_drop_pct / 100.0))
      / 1973.53, 2)
  end;
$fn$;

-- Aritmética pura, não expõe dado nenhum — mas função nova nasce com EXECUTE
-- para public, e deixar uma aberta ensina a deixar a próxima.
revoke all on function public.dc_cable_min_mm2_by_drop(numeric, numeric, numeric, numeric)
  from public, anon;
grant execute on function public.dc_cable_min_mm2_by_drop(numeric, numeric, numeric, numeric)
  to authenticated;

comment on function public.dc_cable_min_mm2_by_drop(numeric, numeric, numeric, numeric) is
  'Seção mínima em mm² para respeitar a queda de tensão (fórmula de circular
   mils, cobre, K=10.75). O comprimento é de UMA VIA: a função dobra, porque a
   corrente percorre ida e volta. NÃO considera ampacidade — o cabo final é o
   MAIOR entre este resultado e o da tabela de ampacidade.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Ampacidade — a metade que é dado, e que entra vazia
--
-- Uma linha por bitola e temperatura de isolação, com o valor lido da fonte
-- oficial. `source` é obrigatório e não aceita vazio: valor de ampacidade sem
-- procedência não serve para nada — daqui a um ano ninguém sabe se veio da
-- norma ou de um palpite.
-- ───────────────────────────────────────────────────────────────────────────
create table if not exists public.dc_ampacity_ratings (
  id uuid primary key default gen_random_uuid(),
  mm2 numeric not null check (mm2 > 0),
  awg text,
  insulation_c integer not null check (insulation_c in (60, 75, 90, 105)),
  /* Fora de casa de máquinas, condutor isolado. Os fatores de correção para
     casa de máquinas e para feixe entram abaixo, aplicados sobre este valor. */
  amps_outside_engine_space numeric not null check (amps_outside_engine_space > 0),
  source text not null check (length(trim(source)) > 0),
  notes text,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  unique (mm2, insulation_c)
);

alter table public.dc_ampacity_ratings enable row level security;

drop policy if exists dc_amp_select on public.dc_ampacity_ratings;
create policy dc_amp_select on public.dc_ampacity_ratings
  for select to authenticated using (true);

drop policy if exists dc_amp_write on public.dc_ampacity_ratings;
create policy dc_amp_write on public.dc_ampacity_ratings
  for all to authenticated
  using (not public.is_external_seller(auth.uid()))
  with check (not public.is_external_seller(auth.uid()));

revoke all on table public.dc_ampacity_ratings from anon;

comment on table public.dc_ampacity_ratings is
  'Ampacidade por bitola e isolação, preenchida a partir da fonte oficial
   (ABYC E-11 ou Blue Sea). Entra VAZIA de propósito: inventar estes números
   dimensiona cabo errado, e cabo subdimensionado esquenta.';

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Os dois critérios juntos, dizendo qual governa e o que falta
--
-- Devolve sempre `pronto` = false quando falta dado ou quando a tabela de
-- ampacidade está vazia. Meia conta apresentada como conta inteira é pior que
-- conta nenhuma: quem recebe "16 mm²" não pergunta se aquilo cobriu só a
-- queda de tensão.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.dc_cable_sizing(
  p_amps numeric,
  p_one_way_meters numeric,
  p_volts numeric default 12,
  p_max_drop_pct numeric default 3,
  p_insulation_c integer default 105,
  p_engine_space boolean default false,
  p_bundle_size integer default 1)
returns jsonb
language plpgsql stable security invoker set search_path = public
as $fn$
declare
  v_drop numeric;
  v_amp numeric;
  v_tem_tabela boolean;
  v_faltando text[] := '{}';
  v_fator numeric := 1;
begin
  v_drop := public.dc_cable_min_mm2_by_drop(p_amps, p_one_way_meters, p_volts, p_max_drop_pct);

  if p_amps is null or p_amps <= 0 then
    v_faltando := v_faltando || 'corrente máxima do circuito (A)';
  end if;
  if p_one_way_meters is null or p_one_way_meters <= 0 then
    v_faltando := v_faltando || 'comprimento do trecho (m)';
  end if;

  select exists (select 1 from public.dc_ampacity_ratings) into v_tem_tabela;

  if v_tem_tabela then
    -- Correções aplicadas ao valor de tabela. Os fatores vêm da norma que
    -- alimentou a tabela; enquanto não houver linha cadastrada, nada disso
    -- roda e o resultado sai declaradamente incompleto.
    if p_engine_space then v_fator := v_fator * 0.7; end if;
    if coalesce(p_bundle_size, 1) > 3 then v_fator := v_fator * 0.7;
    elsif coalesce(p_bundle_size, 1) > 1 then v_fator := v_fator * 0.85;
    end if;

    select min(r.mm2) into v_amp
    from public.dc_ampacity_ratings r
    where r.insulation_c = p_insulation_c
      and r.amps_outside_engine_space * v_fator >= p_amps;
  end if;

  return jsonb_build_object(
    'pronto', (v_drop is not null and v_tem_tabela and v_amp is not null),
    'mm2_por_queda_de_tensao', v_drop,
    'mm2_por_ampacidade', v_amp,
    'mm2_minimo', greatest(coalesce(v_drop, 0), coalesce(v_amp, 0)),
    'criterio_que_manda', case
      when v_drop is null and v_amp is null then null
      when v_amp is null then 'queda de tensão (ampacidade não conferida)'
      when coalesce(v_drop,0) >= coalesce(v_amp,0) then 'queda de tensão'
      else 'ampacidade' end,
    'faltando', to_jsonb(v_faltando),
    'ampacidade_cadastrada', v_tem_tabela,
    'aviso', case
      when not v_tem_tabela then
        'A tabela de ampacidade está vazia: só a queda de tensão foi calculada. '
        'A ABYC exige os dois critérios e vale o MAIOR — em trechos curtos com '
        'corrente alta é a ampacidade que manda, e ela não foi verificada. '
        'Confira na ABYC E-11 ou no Circuit Wizard da Blue Sea antes de fechar.'
      when array_length(v_faltando, 1) > 0 then
        'Faltam dados para dimensionar.'
      else null end,
    'premissas', jsonb_build_object(
      'tensao_v', p_volts, 'queda_max_pct', p_max_drop_pct,
      'isolacao_c', p_insulation_c, 'casa_de_maquinas', p_engine_space,
      'condutores_no_feixe', p_bundle_size,
      'comprimento_considerado', 'ida e volta (o dobro do trecho informado)')
  );
end;
$fn$;

revoke all on function public.dc_cable_sizing(numeric, numeric, numeric, numeric, integer, boolean, integer)
  from public, anon;
grant execute on function public.dc_cable_sizing(numeric, numeric, numeric, numeric, integer, boolean, integer)
  to authenticated;

comment on function public.dc_cable_sizing(numeric, numeric, numeric, numeric, integer, boolean, integer) is
  'Os dois critérios da ABYC E-11 (ampacidade e queda de tensão), com o maior
   governando. Devolve pronto=false e diz o que falta enquanto a tabela de
   ampacidade estiver vazia — meia conta nunca é apresentada como inteira.';
