-- O dimensionamento de cabo quebrava EXATAMENTE no caminho que existia para degradar com elegância.
--
-- `v_faltando` é `text[]`. A linha `v_faltando := v_faltando || 'corrente máxima do circuito (A)'`
-- concatena um array com um literal de tipo `unknown`, e o Postgres resolve isso como
-- `array_cat(anyarray, anyarray)` — não como `array_append` —, tentando ler a frase inteira como
-- se fosse a representação textual de um array. O resultado é:
--
--   ERROR: malformed array literal: "corrente máxima do circuito (A)"
--
-- Ou seja: a função foi escrita para responder "faltam dados" e, em vez disso, explodia. Medido na
-- auditoria de 31/08/2026: 9 das 21 chamadas de `size_dc_cable` falharam (43%) — todas as que
-- passaram `survey_id`, porque é esse caminho que chega aqui sem a corrente resolvida.
--
-- O conserto é o cast explícito, que força a resolução para `array_append`. Validado em produção
-- antes de escrever esta migration: `'{}'::text[] || 'x'::text` devolve `{x}`, enquanto
-- `'{}'::text[] || 'x'` levanta o erro acima.
--
-- Nada mais muda: mesma assinatura, mesma conta, mesmos defaults. Duas linhas.

create or replace function public.dc_cable_sizing(
  p_amps numeric,
  p_one_way_meters numeric,
  p_volts numeric default 12,
  p_max_drop_pct numeric default 3,
  p_insulation_c integer default 90,
  p_engine_space boolean default false,
  p_bundle_size integer default 1
) returns jsonb
language plpgsql
stable
set search_path to 'public'
as $function$
declare
  v_drop numeric; v_amp numeric; v_tem_tabela boolean;
  v_faltando text[] := '{}'; v_n integer := coalesce(p_bundle_size, 1);
  v_coluna text; v_acima_de_tres boolean; v_pronto boolean;
begin
  v_drop := public.dc_cable_min_mm2_by_drop(p_amps, p_one_way_meters, p_volts, p_max_drop_pct);

  if p_amps is null or p_amps <= 0 then
    -- O ::text é o conserto. Sem ele, esta linha derruba a função inteira.
    v_faltando := v_faltando || 'corrente máxima do circuito (A)'::text;
  end if;
  if p_one_way_meters is null or p_one_way_meters <= 0 then
    v_faltando := v_faltando || 'comprimento do trecho (m)'::text;
  end if;

  select exists (select 1 from public.dc_ampacity_ratings where insulation_c = p_insulation_c)
    into v_tem_tabela;

  v_acima_de_tres := v_n > 3;
  v_coluna := case
    when v_n > 1 and p_engine_space then 'feixe, casa de máquinas'
    when v_n > 1                    then 'feixe'
    when p_engine_space             then 'ao ar livre, casa de máquinas'
    else 'ao ar livre' end;

  if v_tem_tabela and p_amps is not null and p_amps > 0 then
    select min(r.mm2) into v_amp
    from public.dc_ampacity_ratings r
    where r.insulation_c = p_insulation_c
      and case
            when v_n > 1 and p_engine_space then r.amps_bundled_engine
            when v_n > 1                    then r.amps_bundled
            when p_engine_space             then r.amps_free_air_engine
            else r.amps_free_air
          end >= p_amps;
  end if;

  v_pronto := v_drop is not null and v_amp is not null and not v_acima_de_tres;

  return jsonb_build_object(
    'pronto', v_pronto,
    'mm2_por_queda_de_tensao', v_drop,
    'mm2_por_ampacidade', v_amp,
    -- Só existe quando os DOIS critérios existem. Sem isso não há mínimo: há
    -- metade de uma conta, e ela não vira número.
    'mm2_minimo', case when v_drop is not null and v_amp is not null
                       then greatest(v_drop, v_amp) end,
    'criterio_que_manda', case
      when v_drop is null or v_amp is null then null
      when v_drop >= v_amp then 'queda de tensão'
      else 'ampacidade' end,
    'faltando', to_jsonb(v_faltando),
    'ampacidade_cadastrada', v_tem_tabela,
    'coluna_da_norma', v_coluna,
    'aviso', case
      when not v_tem_tabela then
        'Não há ampacidade cadastrada para isolação de ' || p_insulation_c ||
        ' °C. Só a queda de tensão foi calculada, e a ABYC exige os dois critérios.'
      when array_length(v_faltando, 1) > 0 then
        'Faltam dados para dimensionar: ' || array_to_string(v_faltando, ', ') || '.'
      when v_acima_de_tres then
        'São ' || v_n || ' condutores no mesmo feixe. As Tabelas VI-A e VI-B cobrem '
        'até TRÊS; acima disso a norma exige correção adicional que não está '
        'cadastrada aqui. O valor abaixo usou a coluna de feixe SEM essa correção '
        '— trate como piso, não como resposta.'
      when v_amp is null then
        'Nenhuma bitola cadastrada atende ' || p_amps || ' A na condição "' ||
        v_coluna || '" a ' || p_insulation_c || ' °C. Reveja a corrente, a '
        'condição de instalação, ou divida o circuito.'
      else null end,
    'premissas', jsonb_build_object(
      'tensao_v', p_volts, 'queda_max_pct', p_max_drop_pct,
      'isolacao_c', p_insulation_c, 'casa_de_maquinas', p_engine_space,
      'condutores_no_feixe', v_n,
      'tabela_da_norma', case when v_n > 1 then 'VI-B' else 'VI-A' end,
      'comprimento_considerado', 'ida e volta (o dobro do trecho informado)')
  );
end;
$function$;

comment on function public.dc_cable_sizing(numeric, numeric, numeric, numeric, integer, boolean, integer) is
  'Bitola minima de cabo CC pelos DOIS criterios da ABYC E-11 (queda de tensao e ampacidade). Quando falta corrente ou comprimento, devolve o que falta em "faltando" -- antes de 31/08/2026 esse caminho levantava "malformed array literal" porque text[] || literal resolvia como array_cat; o cast ::text corrige.';
