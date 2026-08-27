-- ═══════════════════════════════════════════════════════════════════════════
-- A ampacidade da ABYC E-11, inteira, com a forma que a norma tem
--
-- ═══ O QUE ESTAVA ERRADO ═══
--
-- Em 09/08 eu semeei cinco linhas "conferidas" e inventei dois fatores de
-- correção (0,85 para casa de máquinas, 0,70 para feixe) porque não tinha a
-- tabela. Com a tabela na mão, de 15/08, as duas decisões se mostraram erradas:
--
--   1. AS CINCO LINHAS ESTAVAM ERRADAS. Eram valores das linhas AWG gravados
--      com a bitola MÉTRICA vizinha — 6 AWG tem 13,3 mm², não 16. Inclusive a
--      de 35 mm², que eu havia dado como certa: 210 A é o 2 AWG (34 mm²); o
--      35 mm² métrico é 217 A.
--
--   2. A FORMA DA TABELA ESTAVA ERRADA. A norma não dá um valor e fatores: dá
--      QUATRO valores por bitola e temperatura — Tabela VI-A (condutor sozinho
--      ao ar livre) e VI-B (até três condutores em capa, conduíte ou feixe),
--      cada uma com a sua coluna de casa de máquinas. Os fatores implícitos
--      variam: casa de máquinas vai de 0,75 a 0,88 conforme a temperatura, e
--      não é 0,85 fixo como eu havia escrito.
--
-- ═══ POR QUE OS CHECK ESTÃO AQUI ═══
--
-- Esta tabela dimensiona cabo. Um dígito trocado não dá erro — dá cabo fino, e
-- cabo subdimensionado esquenta. Os CHECK abaixo são as mesmas conferências que
-- rodaram sobre a transcrição antes de ela entrar: o banco passa a recusar a
-- linha incoerente em vez de guardá-la.
--
-- Fonte: ABYC E-11, Tabelas VI-A e VI-B, com os dados de referência (diâmetro e
-- resistência) da mesma folha. Transcrita pelo dono a partir do original e
-- conferida por cinco regras de consistência em 18/08/2026.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

drop table if exists public.dc_ampacity_ratings;

create table public.dc_ampacity_ratings (
  id uuid primary key default gen_random_uuid(),
  mm2 numeric not null check (mm2 > 0),
  awg text,
  insulation_c integer not null check (insulation_c in (75, 90, 105)),

  -- Tabela VI-A: condutor sozinho, ao ar livre.
  amps_free_air numeric not null check (amps_free_air > 0),
  amps_free_air_engine numeric not null check (amps_free_air_engine > 0),
  -- Tabela VI-B: até TRÊS condutores em capa, conduíte ou feixe. Acima de três
  -- a norma exige correção adicional que esta folha não traz — ver o aviso em
  -- dc_cable_sizing.
  amps_bundled numeric not null check (amps_bundled > 0),
  amps_bundled_engine numeric not null check (amps_bundled_engine > 0),

  -- Dados de referência da mesma folha. A resistência é o que permite conferir
  -- a fórmula de queda de tensão contra a norma, em vez de confiar na constante.
  ohm_per_km numeric check (ohm_per_km > 0),
  diameter_mm numeric check (diameter_mm > 0),

  source text not null check (length(trim(source)) > 0),
  notes text,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),

  unique (mm2, insulation_c),

  -- Casa de máquinas nunca admite mais corrente que fora dela.
  constraint engrm_menor_que_ar_livre check (amps_free_air_engine < amps_free_air),
  constraint engrm_menor_que_feixe    check (amps_bundled_engine < amps_bundled),
  -- Feixe nunca admite mais que condutor solto.
  constraint feixe_menor_que_ar_livre check (amps_bundled < amps_free_air),
  -- E as razões ficam na faixa que a própria tabela pratica. Fora disso é
  -- digitação trocada, não exceção da norma.
  constraint engrm_em_faixa_plausivel check (
    amps_free_air_engine / amps_free_air between 0.70 and 0.90
    and amps_bundled_engine / amps_bundled between 0.70 and 0.90),
  constraint feixe_em_faixa_plausivel check (
    amps_bundled / amps_free_air between 0.62 and 0.78)
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
  'ABYC E-11, Tabelas VI-A (condutor ao ar livre) e VI-B (até três condutores em
   feixe), cada uma com a coluna de casa de máquinas, mais diâmetro e
   resistência. 30 bitolas × 3 temperaturas de isolação. Os CHECK reproduzem as
   conferências de consistência: linha incoerente é recusada, não guardada.';

insert into public.dc_ampacity_ratings
  (mm2, awg, insulation_c, amps_free_air, amps_free_air_engine,
   amps_bundled, amps_bundled_engine, ohm_per_km, diameter_mm, source)
select v.*, 'ABYC E-11 Tabelas VI-A e VI-B (folha com dados de referência), transcrita do original em 18/08/2026'
from (values
  (0.75, null, 75, 9.5, 7, 6.6, 5.0, 23.92, 0.98),
  (0.82, '18', 75, 10, 8, 7, 5, 21.88, 1.02),
  (1.0, null, 75, 13, 10, 9, 7, 17.94, 1.13),
  (1.3, '16', 75, 15, 11, 11, 8, 13.70, 1.29),
  (1.5, null, 75, 16, 12, 11, 9, 11.96, 1.38),
  (2.1, '14', 75, 20, 15, 14, 11, 8.63, 1.63),
  (2.5, null, 75, 21, 16, 15, 11, 7.18, 1.78),
  (3.3, '12', 75, 25, 19, 18, 13, 5.42, 2.05),
  (4.0, null, 75, 34, 25, 24, 18, 4.49, 2.26),
  (5.3, '10', 75, 40, 30, 28, 21, 3.41, 2.59),
  (6.0, null, 75, 53, 40, 37, 28, 2.99, 2.76),
  (8.4, '8', 75, 65, 49, 46, 34, 2.14, 3.27),
  (10.0, null, 75, 79, 60, 56, 42, 1.79, 3.6),
  (13.3, '6', 75, 95, 71, 67, 50, 1.35, 4.1),
  (16.0, null, 75, 105, 79, 73, 55, 1.12, 4.5),
  (21, '4', 75, 125, 94, 88, 66, 0.85, 5.2),
  (25, null, 75, 141, 106, 99, 74, 0.72, 5.6),
  (27, '3', 75, 145, 109, 102, 76, 0.67, 5.8),
  (34, '2', 75, 170, 128, 119, 89, 0.53, 6.5),
  (35, null, 75, 173, 130, 121, 91, 0.51, 6.7),
  (42, '1', 75, 195, 146, 137, 102, 0.42, 7.3),
  (50, null, 75, 220, 165, 154, 116, 0.36, 8.0),
  (54, '0', 75, 230, 173, 161, 121, 0.34, 8.3),
  (68, '00', 75, 265, 199, 186, 139, 0.27, 9.3),
  (70, null, 75, 274, 206, 192, 144, 0.26, 9.4),
  (85, '000', 75, 310, 233, 217, 163, 0.21, 10.4),
  (95, null, 75, 334, 251, 234, 175, 0.19, 11.0),
  (107, '0000', 75, 360, 270, 252, 189, 0.17, 11.7),
  (120, null, 75, 387, 290, 271, 203, 0.15, 12.4),
  (150, null, 75, 445, 333, 311, 233, 0.12, 13.8),
  (0.75, null, 90, 19, 15.5, 13, 11, 23.92, 0.98),
  (0.82, '18', 90, 20, 16, 14, 12, 21.88, 1.02),
  (1.0, null, 90, 21, 17, 15, 12, 17.94, 1.13),
  (1.3, '16', 90, 25, 21, 18, 14, 13.70, 1.29),
  (1.5, null, 90, 24, 20, 17, 14, 11.96, 1.38),
  (2.1, '14', 90, 30, 25, 21, 17, 8.63, 1.63),
  (2.5, null, 90, 34, 28, 23, 19, 7.18, 1.78),
  (3.3, '12', 90, 40, 33, 28, 23, 5.42, 2.05),
  (4.0, null, 90, 46, 38, 32, 27, 4.49, 2.26),
  (5.3, '10', 90, 55, 45, 39, 32, 3.41, 2.59),
  (6.0, null, 90, 57, 47, 40, 33, 2.99, 2.76),
  (8.4, '8', 90, 70, 57, 49, 40, 2.14, 3.27),
  (10.0, null, 90, 84, 69, 59, 48, 1.79, 3.6),
  (13.3, '6', 90, 100, 82, 70, 57, 1.35, 4.1),
  (16.0, null, 90, 113, 93, 79, 65, 1.12, 4.5),
  (21, '4', 90, 135, 111, 95, 78, 0.85, 5.2),
  (25, null, 90, 150, 123, 105, 86, 0.72, 5.6),
  (27, '3', 90, 155, 127, 109, 89, 0.67, 5.8),
  (34, '2', 90, 180, 148, 126, 103, 0.53, 6.5),
  (35, null, 90, 186, 153, 130, 107, 0.51, 6.7),
  (42, '1', 90, 210, 172, 147, 121, 0.42, 7.3),
  (50, null, 90, 235, 193, 164, 135, 0.36, 8.0),
  (54, '0', 90, 245, 201, 172, 141, 0.34, 8.3),
  (68, '00', 90, 285, 234, 200, 164, 0.27, 9.3),
  (70, null, 90, 292, 239, 204, 168, 0.26, 9.4),
  (85, '000', 90, 330, 271, 231, 189, 0.21, 10.4),
  (95, null, 90, 357, 293, 250, 205, 0.19, 11.0),
  (107, '0000', 90, 385, 316, 270, 221, 0.17, 11.7),
  (120, null, 90, 414, 339, 290, 237, 0.15, 12.4),
  (150, null, 90, 476, 390, 333, 273, 0.12, 13.8),
  (0.75, null, 105, 19, 16, 13, 11, 23.92, 0.98),
  (0.82, '18', 105, 20, 17, 14, 12, 21.88, 1.02),
  (1.0, null, 105, 21, 18, 15, 13, 17.94, 1.13),
  (1.3, '16', 105, 25, 21, 18, 15, 13.70, 1.29),
  (1.5, null, 105, 29, 24, 20, 17, 11.96, 1.38),
  (2.1, '14', 105, 35, 30, 25, 21, 8.63, 1.63),
  (2.5, null, 105, 38, 32, 26, 22, 7.18, 1.78),
  (3.3, '12', 105, 45, 38, 32, 27, 5.42, 2.05),
  (4.0, null, 105, 51, 43, 35, 30, 4.49, 2.26),
  (5.3, '10', 105, 60, 51, 42, 36, 3.41, 2.59),
  (6.0, null, 105, 65, 55, 45, 39, 2.99, 2.76),
  (8.4, '8', 105, 80, 68, 56, 48, 2.14, 3.27),
  (10.0, null, 105, 100, 85, 70, 60, 1.79, 3.6),
  (13.3, '6', 105, 120, 102, 84, 71, 1.35, 4.1),
  (16.0, null, 105, 134, 114, 94, 80, 1.12, 4.5),
  (21, '4', 105, 160, 136, 112, 95, 0.85, 5.2),
  (25, null, 105, 175, 148, 122, 104, 0.72, 5.6),
  (27, '3', 105, 180, 153, 126, 107, 0.67, 5.8),
  (34, '2', 105, 210, 179, 147, 125, 0.53, 6.5),
  (35, null, 105, 217, 185, 152, 129, 0.51, 6.7),
  (42, '1', 105, 245, 208, 172, 146, 0.42, 7.3),
  (50, null, 105, 273, 232, 191, 163, 0.36, 8.0),
  (54, '0', 105, 285, 242, 200, 170, 0.34, 8.3),
  (68, '00', 105, 330, 281, 231, 196, 0.27, 9.3),
  (70, null, 105, 341, 289, 238, 203, 0.26, 9.4),
  (85, '000', 105, 385, 327, 270, 229, 0.21, 10.4),
  (95, null, 105, 413, 351, 289, 246, 0.19, 11.0),
  (107, '0000', 105, 445, 378, 312, 265, 0.17, 11.7),
  (120, null, 105, 478, 406, 335, 284, 0.15, 12.4),
  (150, null, 105, 550, 467, 385, 327, 0.12, 13.8)) as v(mm2, awg, insulation_c, a, ae, b, be, ohm, dia);



-- ───────────────────────────────────────────────────────────────────────────
-- O dimensionador passa a LER a norma, em vez de aplicar fator inventado
--
-- Some o `v_fator`. A escolha agora é de COLUNA:
--   1 condutor              → VI-A (ao ar livre)
--   2 ou 3 condutores       → VI-B (feixe)
--   mais de 3               → VI-B, e `pronto` = false: a folha da norma cobre
--                             até três, e acima disso há correção adicional que
--                             não está aqui. Chutar de novo seria repetir o
--                             erro que esta migration existe para desfazer.
--   casa de máquinas        → a coluna EngRm da opção acima
--
-- E `mm2_minimo` deixa de existir quando falta um dos dois critérios. Antes era
-- `greatest(coalesce(v_drop,0), coalesce(v_amp,0))`: sem ampacidade, o coalesce
-- a virava zero, ela sumia do máximo, e a metade que sobrou saía como se fosse
-- a conta inteira (NOVO-lev-20). Meia conta agora não tem número.
--
-- O padrão de isolação passa de 105 °C para 90 °C. 105 é o TOPO da escala —
-- cabo marítimo premium —, e assumi-lo libera bitola que o cabo real pode não
-- suportar. Enquanto a isolação não vier do produto no catálogo, o padrão tem
-- que ser o conservador.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.dc_cable_sizing(
  p_amps numeric,
  p_one_way_meters numeric,
  p_volts numeric default 12,
  p_max_drop_pct numeric default 3,
  p_insulation_c integer default 90,
  p_engine_space boolean default false,
  p_bundle_size integer default 1)
returns jsonb
language plpgsql stable security invoker set search_path = public
as $fn$
declare
  v_drop numeric; v_amp numeric; v_tem_tabela boolean;
  v_faltando text[] := '{}'; v_n integer := coalesce(p_bundle_size, 1);
  v_coluna text; v_acima_de_tres boolean; v_pronto boolean;
begin
  v_drop := public.dc_cable_min_mm2_by_drop(p_amps, p_one_way_meters, p_volts, p_max_drop_pct);

  if p_amps is null or p_amps <= 0 then
    v_faltando := v_faltando || 'corrente máxima do circuito (A)';
  end if;
  if p_one_way_meters is null or p_one_way_meters <= 0 then
    v_faltando := v_faltando || 'comprimento do trecho (m)';
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
$fn$;

revoke all on function public.dc_cable_sizing(numeric, numeric, numeric, numeric, integer, boolean, integer)
  from public, anon;
grant execute on function public.dc_cable_sizing(numeric, numeric, numeric, numeric, integer, boolean, integer)
  to authenticated;

comment on function public.dc_cable_sizing(numeric, numeric, numeric, numeric, integer, boolean, integer) is
  'Os dois critérios da ABYC E-11, com o maior governando. Lê a COLUNA da norma
   conforme a instalação (ar livre / feixe × casa de máquinas ou não) — não há
   mais fator de correção inventado. mm2_minimo só existe quando os dois
   critérios existem: meia conta não vira número.';

commit;
