-- ═══════════════════════════════════════════════════════════════════════════
-- A tabela de ampacidade, preenchida — e dois fatores meus que estavam errados
--
-- Quando escrevi o dimensionador, deixei `dc_ampacity_ratings` VAZIA porque não
-- achei os números em fonte legível e me recusei a reproduzi-los de memória.
-- O dono mandou pesquisar. Achei, em fontes que se confirmam entre si, e é
-- isso que entra aqui — com a procedência gravada em cada linha, que é para
-- isso que a coluna `source` é obrigatória e não aceita vazio.
--
-- ═══ OS DOIS FATORES QUE EU TINHA CHUTADO ═══
--
-- Escrevi 0,7 para casa de máquinas e 0,85/0,7 para feixe. Ambos errados:
--
--   · CASA DE MÁQUINAS: 0,85. A redução é de 15%, não 30% — o ambiente é
--     considerado 20 °C mais quente (50 °C contra 30 °C). Confere na tabela:
--     AWG 6 dá 120 A fora e 102 A dentro, e 120 × 0,85 = 102.
--   · FEIXE: 0,70, e ponto. A ABYC usa fator ÚNICO para corrente contínua,
--     independente de quantos condutores — os fatores que variam (0,6 / 0,5 /
--     0,4) são de corrente alternada. Eu tinha inventado uma faixa que não
--     existe para DC.
--
-- Os dois se multiplicam: AWG 6 em feixe dentro de casa de máquinas dá
-- 120 × 0,70 × 0,85 = 71,4 A, que é o valor publicado (71 A).
--
-- ═══ POR QUE AS LINHAS SÃO CONSERVADORAS ═══
--
-- A norma é em AWG; o catálogo da HBR é métrico. Cabo de 16 mm² tem seção
-- MAIOR que o AWG 6 (13,30 mm²), então usar a ampacidade do AWG 6 para ele
-- subestima a capacidade. É de propósito: cada bitola métrica recebe o valor
-- do AWG cuja seção é MENOR OU IGUAL à dela. Errar para baixo aqui significa
-- pedir cabo mais grosso do que o necessário; errar para cima significa cabo
-- que esquenta.
-- ═══════════════════════════════════════════════════════════════════════════

insert into public.dc_ampacity_ratings (mm2, awg, insulation_c, amps_outside_engine_space, source, notes)
select * from (values
  (16::numeric,  '6',   105, 120::numeric,
   'ABYC E-11 / tabela de ampacidade reproduzida por Ancor (catálogo 2021) e EXPLORIST.life; conferidas entre si em 09/08/2026',
   'Valor do AWG 6 (13,30 mm²). O cabo de 16 mm² é mais grosso, então o número é conservador.'),

  (25::numeric,  '4',   105, 160::numeric,
   'ABYC E-11 / tabela de ampacidade reproduzida por Ancor (catálogo 2021); conferida em 09/08/2026',
   'Valor do AWG 4 (21,15 mm²). Conservador para 25 mm².'),

  (35::numeric,  '2',   105, 210::numeric,
   'ABYC E-11 / tabela de ampacidade reproduzida por Ancor (catálogo 2021); conferida em 09/08/2026',
   'Valor do AWG 2 (33,62 mm²). Conservador para 35 mm².'),

  (50::numeric,  '1',   105, 245::numeric,
   'ABYC E-11 / tabela de ampacidade reproduzida por Ancor (catálogo 2021); conferida em 09/08/2026',
   'Valor do AWG 1 (42,41 mm²) — o 1/0 tem 53,49 mm² e seria maior que 50, o que superestimaria.'),

  (70::numeric,  '2/0', 105, 330::numeric,
   'ABYC E-11 / tabela de ampacidade reproduzida por Ancor (catálogo 2021); conferida em 09/08/2026',
   'Valor do AWG 2/0 (67,43 mm²). Conservador para 70 mm².')
) as t(mm2, awg, insulation_c, amps_outside_engine_space, source, notes)
where not exists (
  select 1 from public.dc_ampacity_ratings r
  where r.mm2 = t.mm2 and r.insulation_c = t.insulation_c);

-- ───────────────────────────────────────────────────────────────────────────
-- Os fatores corrigidos
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
    -- 15% a menos em casa de máquinas: o ambiente é considerado 20 °C mais
    -- quente. Eu tinha escrito 30%, que não vem de lugar nenhum.
    if p_engine_space then v_fator := v_fator * 0.85; end if;
    -- 30% a menos em feixe, para QUALQUER quantidade. A ABYC usa fator único
    -- em corrente contínua — os que variam com o número de condutores são de
    -- corrente alternada, e eu tinha misturado os dois.
    if coalesce(p_bundle_size, 1) > 1 then v_fator := v_fator * 0.70; end if;

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
      when v_amp is null and not v_tem_tabela then 'queda de tensão (ampacidade não conferida)'
      -- Corrente acima do que a maior bitola cadastrada aguenta: dizer isso é
      -- mais útil que devolver a maior e deixar parecer que serve.
      when v_amp is null then 'nenhuma bitola cadastrada aguenta esta corrente'
      when coalesce(v_drop,0) >= coalesce(v_amp,0) then 'queda de tensão'
      else 'ampacidade' end,
    'faltando', to_jsonb(v_faltando),
    'ampacidade_cadastrada', v_tem_tabela,
    'aviso', case
      when not v_tem_tabela then
        'A tabela de ampacidade está vazia: só a queda de tensão foi calculada.'
      when v_amp is null and p_amps is not null and p_amps > 0 then
        'Nenhuma bitola cadastrada aguenta ' || p_amps || ' A nas condições informadas. '
        'Cadastre uma seção maior em dc_ampacity_ratings ou reveja a corrente.'
      when array_length(v_faltando, 1) > 0 then 'Faltam dados para dimensionar.'
      else null end,
    'premissas', jsonb_build_object(
      'tensao_v', p_volts, 'queda_max_pct', p_max_drop_pct,
      'isolacao_c', p_insulation_c, 'casa_de_maquinas', p_engine_space,
      'condutores_no_feixe', p_bundle_size,
      'fator_aplicado', v_fator,
      'comprimento_considerado', 'ida e volta (o dobro do trecho informado)')
  );
end;
$fn$;

revoke all on function public.dc_cable_sizing(numeric, numeric, numeric, numeric, integer, boolean, integer)
  from public, anon;
grant execute on function public.dc_cable_sizing(numeric, numeric, numeric, numeric, integer, boolean, integer)
  to authenticated;
