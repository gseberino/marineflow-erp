-- Lucro por OS desconta o custo da HBR (Comprovantes F2, 11/10/2026). OK NOMEADO SEPARADO (P2).
--
-- Decisão do dono: a compra de OS que NÃO é cobrada do cliente ("custo da HBR") sai do lucro da OS.
-- Antes, vw_os_profitability (20260929173000) descontava só o operational_cost_total, que é a soma
-- das despesas FATURÁVEIS (as que o cliente paga e que já estão na receita): a despesa não
-- faturável não entrava em lugar nenhum e a OS parecia mais lucrativa do que é.
--
-- Agora: net_profit e net_margin_percent descontam também a soma das despesas da OS com
-- billable_to_client = false, exceto as marcadas cobrar_a_parte (a OS já estava faturada e o valor
-- vai ser cobrado do cliente fora do total: não é custo da HBR). Coluna nova hbr_cost no FIM (as
-- telas leem por nome); as outras colunas ficam iguais e na mesma ordem.
--
-- Em produção, em 11/10/2026, há 0 despesas não faturáveis: nenhuma OS muda de lucro no dia.
-- Depende de service_order_expenses.cobrar_a_parte (20261011203000). Não escreve dados (a prova
-- grava uma despesa de teste numa subtransação desfeita). Idempotente.

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
), custo_hbr as (
  -- Custo da HBR (11/10/2026): despesa da OS que o cliente não paga. "Cobrar à parte" não entra.
  select service_order_id, sum(amount) as custo
    from public.service_order_expenses
   where billable_to_client = false and not cobrar_a_parte
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
         - coalesce(mo.custo_real_mao_de_obra, 0::numeric)
         - coalesce(ch.custo, 0::numeric) as net_profit,
       case
         when so.grand_total > 0::numeric then
           (so.grand_total - coalesce(oc.total_parts_cost, 0::numeric) - coalesce(so.travel_cost_total, 0::numeric)
             - coalesce(so.operational_cost_total, 0::numeric) - coalesce(com.total_commission, 0::numeric)
             - coalesce(mo.custo_real_mao_de_obra, 0::numeric)
             - coalesce(ch.custo, 0::numeric)) / so.grand_total * 100::numeric
         else 0::numeric
       end as net_margin_percent,
       so.created_at,
       so.check_out_at as finished_at,
       c.name as client_name,
       -- 29/09/2026:
       coalesce(mo.custo_real_mao_de_obra, 0::numeric) as labor_cost_real,
       coalesce(mo.dias_trabalhados, 0::numeric) as labor_days,
       coalesce(so.labor_cost_total, 0::numeric) as labor_sold,
       coalesce(hv.horas, 0::numeric) as hours_sold,
       -- 11/10/2026:
       coalesce(ch.custo, 0::numeric) as hbr_cost
  from public.service_orders so
  left join os_costs oc on oc.service_order_id = so.id
  left join os_commissions com on com.service_order_id = so.id
  left join mao_de_obra mo on mo.service_order_id = so.id
  left join horas_vendidas hv on hv.service_order_id = so.id
  left join custo_hbr ch on ch.service_order_id = so.id
  left join public.clients c on c.id = so.client_id;

comment on column public.vw_os_profitability.net_profit is
  'Receita − peças (custo) − deslocamento − despesas faturáveis − comissões − mão de obra real das diárias (29/09/2026) − custo da HBR (despesa da OS não cobrada do cliente, 11/10/2026).';
comment on column public.vw_os_profitability.hbr_cost is
  'Custo da HBR: soma das despesas da OS não faturáveis (billable_to_client = false), exceto as "cobrar à parte". Já descontado do net_profit.';

-- view recriada: fechar anon de novo na mesma migration
revoke all on public.vw_os_profitability from anon;
grant select on public.vw_os_profitability to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova: anon sem select; hbr_cost é a última coluna; uma despesa não faturável de 10 tira 10 do
-- lucro e uma "cobrar à parte" não tira nada (numa subtransação desfeita, na OS mais recente).
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_os uuid;
  v_antes numeric;
  v_custo numeric;
  v_parte numeric;
  v_hbr numeric;
begin
  if has_table_privilege('anon', 'public.vw_os_profitability', 'select') then
    raise exception 'vw_os_profitability aberta para o anon';
  end if;
  if not has_table_privilege('authenticated', 'public.vw_os_profitability', 'select') then
    raise exception 'vw_os_profitability sem select para authenticated';
  end if;
  if (select a.attname from pg_attribute a
       where a.attrelid = 'public.vw_os_profitability'::regclass and a.attnum > 0 and not a.attisdropped
       order by a.attnum desc limit 1) is distinct from 'hbr_cost' then
    raise exception 'hbr_cost não é a última coluna de vw_os_profitability';
  end if;

  select so.id into v_os from public.service_orders so
   where so.grand_total is not null and so.status <> 'cancelled'
   order by so.created_at desc limit 1;
  if v_os is not null then
    begin
      select p.net_profit into v_antes from public.vw_os_profitability p where p.os_id = v_os;
      insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client)
      values (v_os, 'Outras despesas', 'prova da migration (desfeita)', 10, 'company', false);
      select p.net_profit, p.hbr_cost into v_custo, v_hbr from public.vw_os_profitability p where p.os_id = v_os;
      insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client, cobrar_a_parte)
      values (v_os, 'Outras despesas', 'prova da migration (desfeita)', 7, 'company', false, true);
      select p.net_profit into v_parte from public.vw_os_profitability p where p.os_id = v_os;
      raise exception 'desfaz a prova' using errcode = 'MFR00';
    exception when sqlstate 'MFR00' then
      null;
    end;
    if v_antes - v_custo is distinct from 10 or v_parte is distinct from v_custo or v_hbr < 10 then
      raise exception 'Lucro por OS: custo da HBR não desconta certo (antes %, com 10 %, com à parte %)', v_antes, v_custo, v_parte;
    end if;
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011205000', 'lucro_por_os_custo_hbr')
on conflict do nothing;
