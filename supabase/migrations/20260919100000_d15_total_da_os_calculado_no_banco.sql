-- D15 (decisão do dono, 17/09/2026) / MF-AUD-011: UMA fórmula para o total da OS, no banco.
--
-- Até aqui a fórmula existia em três lugares: recalc_so_totals (SQL, usada pelo agente),
-- recalcTotals em use-service-orders.ts e o recálculo de use-service-order-expenses.ts
-- (navegador, usadas pelas telas). Três cópias = a classe de bug "a tela diz um total e o
-- PDF diz outro". Agora:
--   calc_so_totals(so_id)   → CALCULA e devolve (sem gravar). SECURITY INVOKER: obedece a RLS
--                             de quem chama; técnico que não vê valores não calcula valores.
--   recalc_so_totals(so_id) → chama calc e GRAVA (mesma assinatura de sempre).
-- O navegador passa a: calc → cascata dos recebíveis com piso (continua em TS, onde já
-- estava testada) → recalc. A conta, em si, só existe aqui.
--
-- labor_hours_total entra na função (a cópia do navegador já gravava; a SQL não).

create or replace function public.calc_so_totals(so_id uuid)
returns table (
  labor_cost_total numeric,
  parts_cost_total numeric,
  labor_hours_total numeric,
  operational_cost_total numeric,
  travel_billable numeric,
  subcontract_cost_total numeric,
  discount_amount numeric,
  tax_amount numeric,
  subtotal numeric,
  base numeric,
  card_fee_percent numeric,
  card_fee_amount numeric,
  grand_total numeric
)
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_labor numeric; v_parts numeric; v_hours numeric;
  v_operational numeric; v_travel numeric; v_subcontract numeric; v_discount numeric; v_tax numeric;
  v_is_travel_billable boolean; v_card_passthrough_enabled boolean; v_card_installments integer;
  v_fee_percent numeric := 0; v_billable_travel numeric; v_subtotal numeric; v_base numeric;
  v_card_fee_amount numeric; v_grand numeric;
begin
  select coalesce(sum(s.line_total), 0) into v_labor
  from service_order_services s where s.service_order_id = so_id;

  select coalesce(sum(p.line_total_sale), 0) into v_parts
  from service_order_parts p where p.service_order_id = so_id;

  select round(coalesce(sum(t.duration_minutes), 0) / 60.0, 2) into v_hours
  from time_entries t where t.service_order_id = so_id and t.billable;

  select coalesce(so.operational_cost_total, 0), coalesce(so.travel_cost_total, 0),
         coalesce(so.subcontract_cost_total, 0), coalesce(so.discount_amount, 0),
         coalesce(so.tax_amount, 0), so.is_travel_billable,
         so.card_fee_passthrough_enabled, so.card_installments
    into v_operational, v_travel, v_subcontract, v_discount, v_tax,
         v_is_travel_billable, v_card_passthrough_enabled, v_card_installments
  from service_orders so where so.id = so_id;
  if not found then return; end if;

  v_billable_travel := case when v_is_travel_billable is distinct from false then v_travel else 0 end;
  v_subtotal := v_labor + v_parts + v_operational + v_billable_travel + v_subcontract;
  v_base := v_subtotal - v_discount + v_tax;

  if v_card_passthrough_enabled and v_card_installments is not null then
    select f.fee_percent into v_fee_percent
    from card_installment_fees f where f.installments = v_card_installments;
    v_fee_percent := coalesce(v_fee_percent, 0);
  end if;
  -- Gross-up: a taxa é repassada por cima do valor já ajustado (Onda 1C).
  v_card_fee_amount := case when v_fee_percent > 0 and v_fee_percent < 100
    then round(v_base * v_fee_percent / (100 - v_fee_percent), 2) else 0 end;
  v_grand := round(v_base + v_card_fee_amount, 2);

  return query select
    round(v_labor, 2), round(v_parts, 2), v_hours, v_operational, v_billable_travel, v_subcontract,
    v_discount, v_tax, round(v_subtotal, 2), round(v_base, 2), v_fee_percent, v_card_fee_amount, v_grand;
end;
$$;

create or replace function public.recalc_so_totals(so_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  r record;
begin
  select status into v_status from service_orders where id = so_id;
  if not found or v_status = 'cancelled' then
    return;
  end if;

  select * into r from public.calc_so_totals(so_id);
  if r.grand_total is null then return; end if;

  update service_orders
  set labor_cost_total  = r.labor_cost_total,
      parts_cost_total  = r.parts_cost_total,
      labor_hours_total = r.labor_hours_total,
      card_fee_amount   = r.card_fee_amount,
      grand_total       = r.grand_total
  where id = so_id;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260919100000', 'd15_total_da_os_calculado_no_banco')
on conflict do nothing;
