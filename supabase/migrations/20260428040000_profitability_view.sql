-- View de Lucratividade Real por Ordem de Serviço
-- Nome: 20260428040000_profitability_view.sql

CREATE OR REPLACE VIEW public.vw_os_profitability AS
WITH os_costs AS (
    -- Soma dos custos de peças baseados no snapshot de custo (vindo do XML ou entrada manual)
    SELECT 
        service_order_id,
        SUM(quantity * unit_cost_snapshot) as total_parts_cost
    FROM public.service_order_parts
    GROUP BY service_order_id
),
os_commissions AS (
    -- Soma das comissões aprovadas ou pendentes para a OS
    SELECT 
        service_order_id,
        SUM(amount) as total_commission
    FROM public.commissions
    WHERE status != 'cancelled'
    GROUP BY service_order_id
)
SELECT 
    so.id as os_id,
    so.service_order_number,
    so.status,
    so.grand_total as revenue,
    COALESCE(oc.total_parts_cost, 0) as parts_cost,
    COALESCE(so.travel_cost_total, 0) as travel_cost,
    COALESCE(so.operational_cost_total, 0) as operational_cost,
    COALESCE(com.total_commission, 0) as commission_cost,
    -- Lucro Bruto (Receita - Custo de Peças)
    (so.grand_total - COALESCE(oc.total_parts_cost, 0)) as gross_profit,
    -- Lucro Líquido (Receita - Todos os Custos)
    (so.grand_total - 
        COALESCE(oc.total_parts_cost, 0) - 
        COALESCE(so.travel_cost_total, 0) - 
        COALESCE(so.operational_cost_total, 0) - 
        COALESCE(com.total_commission, 0)
    ) as net_profit,
    -- Margem Líquida %
    CASE 
        WHEN so.grand_total > 0 THEN 
            ((so.grand_total - COALESCE(oc.total_parts_cost, 0) - COALESCE(so.travel_cost_total, 0) - COALESCE(so.operational_cost_total, 0) - COALESCE(com.total_commission, 0)) / so.grand_total) * 100
        ELSE 0 
    END as net_margin_percent,
    so.created_at,
    COALESCE(so.finished_at, so.check_out_at) as finished_at,
    c.full_name_or_company_name as client_name
FROM 
    public.service_orders so
LEFT JOIN os_costs oc ON oc.service_order_id = so.id
LEFT JOIN os_commissions com ON com.service_order_id = so.id
LEFT JOIN public.clients c ON c.id = so.client_id;

-- Permissões
GRANT SELECT ON public.vw_os_profitability TO authenticated;
