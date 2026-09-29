-- Lucro por OS com a mão de obra REAL das diárias (Passo 5 das Diárias, 29/09/2026).
-- Plano: plans/marineflow-diarias-freelancers.md.
--
-- Antes: nenhum cálculo de lucro descontava mão de obra. `vw_os_profitability` (tela "Lucro por
-- OS", relatório de produtividade) fazia receita − peças − deslocamento − despesas − comissões, e
-- o serviço vendido aparecia com 100% de margem.
--
-- Agora: o valor de cada dia de diarista ligado a OS (work_shift_os) entra como custo da OS,
-- dividido em partes iguais quando o dia foi em mais de uma (decisão D5 do dono). Não passa pela
-- despesa da OS (so_expense_add): lá o custo é faturável por padrão e subiria o preço do cliente.
--
-- O que ainda NÃO entra, dito claramente: a mão de obra do próprio dono (não é apontada) e dia de
-- freelancer sem OS. A margem continua otimista enquanto os dias não forem ligados às OS.

-- ---------------------------------------------------------------------------
-- 1. O custo real de mão de obra por OS, das diárias
-- ---------------------------------------------------------------------------
-- A versão de 20260824130000 lia payroll_lines (folha fechada), que nunca existe no regime de
-- diária: estava sempre vazia e ninguém a consultava. Mesmo nome, fonte nova.
drop view if exists public.v_custo_real_mao_de_obra_por_os;

create view public.v_custo_real_mao_de_obra_por_os
with (security_invoker = on) as
with partes as (
  select wo.service_order_id,
         ws.id as shift_id,
         wp.payee_id,
         p.name as pessoa,
         ws.data,
         ws.fracao,
         ws.valor_dia,
         count(*) over (partition by ws.id) as n_os
    from public.work_shift_os wo
    join public.work_shifts ws on ws.id = wo.shift_id
    join public.work_profiles wp on wp.id = ws.work_profile_id
    left join public.payees p on p.id = wp.payee_id
   where ws.fracao is not null
)
select service_order_id,
       round(sum(valor_dia / n_os), 2) as custo_real_mao_de_obra,
       round(sum(fracao / n_os), 2) as dias_trabalhados,
       count(distinct payee_id) as pessoas,
       string_agg(distinct pessoa, ', ') as quem_trabalhou,
       min(data) as primeiro_dia,
       max(data) as ultimo_dia
  from partes
 group by service_order_id;

comment on view public.v_custo_real_mao_de_obra_por_os is
  'Custo real de mão de obra de cada OS: o valor dos dias de diarista ligados a ela (work_shift_os), divididos em partes iguais entre as OS do mesmo dia.';

-- ---------------------------------------------------------------------------
-- 2. vw_os_profitability: desconta a mão de obra; colunas novas no FIM (as telas leem por nome)
-- ---------------------------------------------------------------------------
create or replace view public.vw_os_profitability
with (security_invoker = on) as
with os_costs as (
  select service_order_parts.service_order_id,
         sum(service_order_parts.quantity * service_order_parts.unit_cost_snapshot) as total_parts_cost
    from public.service_order_parts
   group by service_order_parts.service_order_id
), os_commissions as (
  select commissions.service_order_id,
         sum(commissions.amount) as total_commission
    from public.commissions
   where commissions.status <> 'cancelled'::text
   group by commissions.service_order_id
), mao_de_obra as (
  select service_order_id, custo_real_mao_de_obra, dias_trabalhados
    from public.v_custo_real_mao_de_obra_por_os
), horas_vendidas as (
  -- O "homem-hora orçado" que existe de fato: estimated_hours está vazio em quase toda OS; o que
  -- se vende por hora é a linha de serviço cobrada por hora.
  select service_order_id, sum(quantity) filter (where billing_unit_snapshot = 'hour') as horas
    from public.service_order_services
   group by service_order_id
)
select so.id as os_id,
       so.service_order_number,
       so.status,
       so.grand_total as revenue,
       coalesce(oc.total_parts_cost, 0::numeric) as parts_cost,
       coalesce(so.travel_cost_total, 0::numeric) as travel_cost,
       coalesce(so.operational_cost_total, 0::numeric) as operational_cost,
       coalesce(com.total_commission, 0::numeric) as commission_cost,
       so.grand_total - coalesce(oc.total_parts_cost, 0::numeric) as gross_profit,
       so.grand_total - coalesce(oc.total_parts_cost, 0::numeric) - coalesce(so.travel_cost_total, 0::numeric)
         - coalesce(so.operational_cost_total, 0::numeric) - coalesce(com.total_commission, 0::numeric)
         - coalesce(mo.custo_real_mao_de_obra, 0::numeric) as net_profit,
       case
         when so.grand_total > 0::numeric then
           (so.grand_total - coalesce(oc.total_parts_cost, 0::numeric) - coalesce(so.travel_cost_total, 0::numeric)
             - coalesce(so.operational_cost_total, 0::numeric) - coalesce(com.total_commission, 0::numeric)
             - coalesce(mo.custo_real_mao_de_obra, 0::numeric)) / so.grand_total * 100::numeric
         else 0::numeric
       end as net_margin_percent,
       so.created_at,
       so.check_out_at as finished_at,
       c.name as client_name,
       -- Novas (29/09/2026):
       coalesce(mo.custo_real_mao_de_obra, 0::numeric) as labor_cost_real,
       coalesce(mo.dias_trabalhados, 0::numeric) as labor_days,
       coalesce(so.labor_cost_total, 0::numeric) as labor_sold,
       coalesce(hv.horas, 0::numeric) as hours_sold
  from public.service_orders so
  left join os_costs oc on oc.service_order_id = so.id
  left join os_commissions com on com.service_order_id = so.id
  left join mao_de_obra mo on mo.service_order_id = so.id
  left join horas_vendidas hv on hv.service_order_id = so.id
  left join public.clients c on c.id = so.client_id;

comment on column public.vw_os_profitability.net_profit is
  'Receita − peças (custo) − deslocamento − despesas − comissões − mão de obra real das diárias (desde 29/09/2026).';
comment on column public.vw_os_profitability.labor_cost_real is
  'Custo real de mão de obra de freelancers de diária ligados a esta OS (v_custo_real_mao_de_obra_por_os).';
comment on column public.vw_os_profitability.labor_sold is
  'Mão de obra vendida ao cliente (soma das linhas de serviço) — para comparar com o custo real.';

-- View nova vaza por padrão: fechar anon na mesma migration.
revoke all on public.v_custo_real_mao_de_obra_por_os from anon;
revoke all on public.vw_os_profitability from anon;
grant select on public.v_custo_real_mao_de_obra_por_os to authenticated, service_role;
grant select on public.vw_os_profitability to authenticated, service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260929173000', 'lucro_por_os_com_mao_de_obra')
on conflict (version) do nothing;
