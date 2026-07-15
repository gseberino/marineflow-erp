-- recalc_so_totals nunca existiu neste banco. As tools de IA que adicionam serviço/peça/
-- material a uma OS chamam esta RPC após cada insert; sem ela, o item era gravado com
-- sucesso mas o total da OS nunca refletia o item novo — silenciosamente, sem erro (e, até
-- a correção do bug de encadeamento .rpc().catch() em service-orders.ts, a chamada quebrada
-- fazia a tool inteira reportar falha para um item que já tinha sido gravado).
--
-- Fórmula espelha EXATAMENTE o cálculo client-side de
-- src/components/ServiceOrderForm.tsx (grandTotal), para os dois ficarem consistentes:
--
--   subtotal = labor_cost_total + parts_cost_total + operational_cost_total
--              + (is_travel_billable != false ? travel_cost_total : 0)
--              + subcontract_cost_total
--   base     = subtotal - discount_amount + tax_amount
--   grand_total = base + (repasse de taxa de cartão, se habilitado)
--
-- labor_cost_total e parts_cost_total são recalculados a partir das tabelas-filha (fonte
-- da verdade); os demais campos são preservados como já configurados na OS.
--
-- Validado contra todas as OS não-canceladas do banco em produção: bate exatamente com o
-- grand_total já salvo em todas, exceto 3 casos explicáveis (dados históricos
-- dessincronizados de orçamentos rejeitados/antigos, não causados por esta função).
--
-- Proteção: OS canceladas têm o total histórico "congelado" de propósito (o cancelamento
-- em cascata pode alterar/zerar itens-filho para estornar estoque/financeiro, sem
-- resalvar o total) — a função nunca deve sobrescrever uma OS cancelada.
create or replace function public.recalc_so_totals(so_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_labor numeric;
  v_parts numeric;
  v_operational numeric;
  v_travel numeric;
  v_subcontract numeric;
  v_discount numeric;
  v_tax numeric;
  v_is_travel_billable boolean;
  v_card_passthrough_enabled boolean;
  v_card_installments integer;
  v_fee_percent numeric;
  v_billable_travel numeric;
  v_subtotal numeric;
  v_base numeric;
  v_card_fee_amount numeric;
  v_grand_total numeric;
begin
  select status into v_status from service_orders where id = so_id;
  if not found or v_status = 'cancelled' then
    return;
  end if;

  select coalesce(sum(line_total), 0) into v_labor
  from service_order_services where service_order_id = so_id;

  select coalesce(sum(line_total_sale), 0) into v_parts
  from service_order_parts where service_order_id = so_id;

  select
    coalesce(operational_cost_total, 0),
    coalesce(travel_cost_total, 0),
    coalesce(subcontract_cost_total, 0),
    coalesce(discount_amount, 0),
    coalesce(tax_amount, 0),
    is_travel_billable,
    card_fee_passthrough_enabled,
    card_installments
  into
    v_operational, v_travel, v_subcontract, v_discount, v_tax,
    v_is_travel_billable, v_card_passthrough_enabled, v_card_installments
  from service_orders where id = so_id;

  v_billable_travel := case when v_is_travel_billable is distinct from false then v_travel else 0 end;
  v_subtotal := v_labor + v_parts + v_operational + v_billable_travel + v_subcontract;
  v_base := v_subtotal - v_discount + v_tax;

  v_fee_percent := 0;
  if v_card_passthrough_enabled and v_card_installments is not null then
    select fee_percent into v_fee_percent
    from card_installment_fees where installments = v_card_installments;
    v_fee_percent := coalesce(v_fee_percent, 0);
  end if;

  v_card_fee_amount := case when v_fee_percent > 0
    then round(v_base * v_fee_percent / (100 - v_fee_percent), 2)
    else 0
  end;

  v_grand_total := v_base + v_card_fee_amount;

  update service_orders
  set labor_cost_total = v_labor,
      parts_cost_total = v_parts,
      card_fee_amount = v_card_fee_amount,
      grand_total = v_grand_total
  where id = so_id;
end;
$$;

grant execute on function public.recalc_so_totals(uuid) to authenticated, service_role;
