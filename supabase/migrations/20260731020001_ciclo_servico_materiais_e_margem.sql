-- ═══════════════════════════════════════════════════════════════════════════
-- Ciclo do Serviço — Fase 5: MATERIAIS COMPLEMENTARES E MARGEM REAL
-- Plano: plans/marineflow-execucao-os-roteiro.md (P19, P20)
--
-- O problema medido no baseline: R$ 980 de cabo, R$ 280 de fusível e R$ 85 de
-- selante lançados como SERVIÇO. Isso infla receita de serviço e some com o
-- custo de material — a margem parece boa porque o custo virou receita.
--
-- P19: duas camadas, e a divisão entre elas é econômica, não técnica.
--   Kit do serviço  → o que tem nome e quantidade (terminal, cabo, abraçadeira)
--   Taxa de oficina → o miúdo (fita, lixa, estopa, parafuso avulso)
-- Rastrear parafuso a parafuso destrói o tempo produtivo que o projeto protege.
--
-- P20: EPI comum é custo de operação, embutido no valor-hora. Só EPI específico
-- da tarefa (espaço confinado, altura) entra como item da OS.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. O CATÁLOGO GANHA MATERIAL
--    material_kit_product_id aponta para um produto tipo 'kit', cujos
--    componentes (product_components, que já existe) são os consumíveis.
--    Reusar o BOM em vez de criar uma segunda lista de materiais.
-- ─────────────────────────────────────────────────────────────
alter table public.services
  add column if not exists material_kit_product_id uuid references public.products(id) on delete set null,
  add column if not exists supplies_pct numeric(5,2),
  add column if not exists supplies_cap numeric(12,2);

comment on column public.services.supplies_pct is
  'Taxa de materiais de oficina, em % da mão de obra da linha. Referência de mercado: 3 a 8%. Nulo = usa o padrão de app_settings.';
comment on column public.services.supplies_cap is
  'Teto em reais da taxa de materiais. Sem teto, percentual em serviço caro vira número sem relação com o consumo real.';

-- ─────────────────────────────────────────────────────────────
-- 2. DE ONDE VEIO A PEÇA
--    Sem isso não dá para separar o que foi planejado do que apareceu no meio
--    do serviço — que é justamente o vazamento que se quer medir.
-- ─────────────────────────────────────────────────────────────
alter table public.service_order_parts
  add column if not exists source text not null default 'manual';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'service_order_parts_source_check') then
    alter table public.service_order_parts
      add constraint service_order_parts_source_check
      check (source in ('manual','kit','survey','ai','extra'));
  end if;
end $$;

comment on column public.service_order_parts.source is
  'manual = lançado à mão; kit = veio do kit do serviço; survey = saiu do levantamento; ai = sugerido pela IA; extra = descoberto durante a execução.';

-- ─────────────────────────────────────────────────────────────
-- 3. PADRÕES DA CASA
--    Ficam em app_settings para o dono mudar sem migration.
-- ─────────────────────────────────────────────────────────────
insert into public.app_settings (key, value) values
  ('supplies_pct_padrao', '5'),
  ('supplies_cap_padrao', '250'),
  ('material_valor_de_corte', '15')
on conflict (key) do nothing;

-- ─────────────────────────────────────────────────────────────
-- 4. APLICAR O KIT DE MATERIAIS DE UM SERVIÇO NA OS
--    Idempotente: rodar de novo não duplica (não relança o que já veio do kit).
--    Usa o preço praticado do produto, como qualquer outra linha de peça.
-- ─────────────────────────────────────────────────────────────
create or replace function public.apply_service_material_kit(
  p_service_order_id uuid,
  p_service_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_kit uuid;
  v_criadas integer := 0;
  v_ja integer := 0;
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select material_kit_product_id into v_kit from public.services where id = p_service_id;
  if v_kit is null then
    return jsonb_build_object('ok', false,
      'mensagem', 'Este serviço não tem kit de materiais cadastrado. Cadastre o kit no catálogo (produto do tipo kit) e ligue-o ao serviço.');
  end if;

  -- Quantas linhas do kit já estão na OS: não duplicar é mais importante que
  -- inserir, porque peça duplicada vira reserva de estoque duplicada.
  select count(*) into v_ja
  from public.service_order_parts sop
  join public.product_components pc on pc.component_product_id = sop.product_id
  where sop.service_order_id = p_service_order_id
    and pc.parent_product_id = v_kit
    and sop.source = 'kit';

  insert into public.service_order_parts
    (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
     line_total_cost, line_total_sale, source, notes)
  select
    p_service_order_id,
    pc.component_product_id,
    pc.quantity,
    coalesce(p.cost_price, 0),
    coalesce(p.sale_price, 0),
    coalesce(p.cost_price, 0) * pc.quantity,
    coalesce(p.sale_price, 0) * pc.quantity,
    'kit',
    'Do kit de materiais do serviço'
  from public.product_components pc
  join public.products p on p.id = pc.component_product_id
  where pc.parent_product_id = v_kit
    and not exists (
      select 1 from public.service_order_parts x
      where x.service_order_id = p_service_order_id
        and x.product_id = pc.component_product_id
        and x.source = 'kit'
    );

  get diagnostics v_criadas = row_count;

  return jsonb_build_object(
    'ok', true,
    'linhas_criadas', v_criadas,
    'ja_estavam', v_ja,
    'mensagem', case
      when v_criadas = 0 and v_ja > 0 then 'O kit já estava aplicado nesta OS.'
      when v_criadas = 0 then 'O kit não tem componentes cadastrados.'
      else v_criadas || ' item(ns) de material lançado(s).'
    end);
end;
$fn$;

revoke all on function public.apply_service_material_kit(uuid, uuid) from public, anon;
grant execute on function public.apply_service_material_kit(uuid, uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────
-- 5. A CONTA QUE FECHA O CICLO
--    Faturado − mão de obra real − material real − taxa de oficina.
--    security_invoker + revoke de anon na MESMA migration.
-- ─────────────────────────────────────────────────────────────
create or replace view public.v_service_order_margin
with (security_invoker = on) as
with mo as (
  -- Mão de obra REAL: minutos apontados no roteiro, ao custo-hora da OS.
  select st.service_order_id,
         sum(coalesce(st.actual_minutes, 0)) as minutos_reais
  from public.service_order_steps st
  group by st.service_order_id
),
mat as (
  select sop.service_order_id,
         sum(coalesce(sop.line_total_cost, 0)) as custo_material,
         sum(coalesce(sop.line_total_sale, 0)) as venda_material,
         sum(coalesce(sop.line_total_cost, 0)) filter (where sop.source = 'extra') as custo_material_extra
  from public.service_order_parts sop
  group by sop.service_order_id
),
taxa as (
  select sos.service_order_id,
         sum(
           least(
             coalesce(sos.line_total, 0) * (coalesce(s.supplies_pct,
               (select value::numeric from public.app_settings where key = 'supplies_pct_padrao')) / 100),
             coalesce(s.supplies_cap,
               (select value::numeric from public.app_settings where key = 'supplies_cap_padrao'))
           )
         ) as taxa_materiais
  from public.service_order_services sos
  left join public.services s on s.id = sos.service_id
  group by sos.service_order_id
)
select
  so.id,
  so.service_order_number,
  so.status,
  so.client_id,
  coalesce(so.grand_total, 0)                                   as faturado,
  round(coalesce(mo.minutos_reais, 0) / 60.0, 2)                as horas_reais,
  round((coalesce(mo.minutos_reais, 0) / 60.0) * coalesce(so.hourly_rate, 0), 2) as custo_mao_de_obra,
  coalesce(mat.custo_material, 0)                               as custo_material,
  coalesce(mat.custo_material_extra, 0)                         as custo_material_extra,
  round(coalesce(taxa.taxa_materiais, 0), 2)                    as taxa_materiais,
  round(
    coalesce(so.grand_total, 0)
    - (coalesce(mo.minutos_reais, 0) / 60.0) * coalesce(so.hourly_rate, 0)
    - coalesce(mat.custo_material, 0)
    - coalesce(taxa.taxa_materiais, 0)
  , 2)                                                          as margem_reais,
  case when coalesce(so.grand_total, 0) > 0 then round((
    (coalesce(so.grand_total, 0)
     - (coalesce(mo.minutos_reais, 0) / 60.0) * coalesce(so.hourly_rate, 0)
     - coalesce(mat.custo_material, 0)
     - coalesce(taxa.taxa_materiais, 0)
    ) / so.grand_total) * 100, 1) end                            as margem_pct
from public.service_orders so
left join mo on mo.service_order_id = so.id
left join mat on mat.service_order_id = so.id
left join taxa on taxa.service_order_id = so.id;

revoke all on public.v_service_order_margin from anon;
grant select on public.v_service_order_margin to authenticated;

comment on view public.v_service_order_margin is
  'Margem real por OS: faturado menos mão de obra apontada no roteiro, material consumido e taxa de oficina. A hora aqui é CUSTO — a HBR cobra por serviço/visita, não por hora.';
