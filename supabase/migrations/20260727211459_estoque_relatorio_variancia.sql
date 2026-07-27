-- FASE B — enxergar. Somente leitura.
--
-- Equivalente ao "Stock Ledger Variance" do ERPNext: aponta onde o saldo não se
-- sustenta no histórico. Aqui ele NÃO recalcula o saldo verdadeiro, e o motivo é
-- honesto: o backup pré-v2 (25/07) já nasceu contaminado e apenas 3 de 90 produtos
-- batem com "backup + soma dos movimentos". Sem saldo inicial confiável, o número
-- certo só vem de contagem física — que é exatamente para isso que existem o
-- Physical Inventory Journal do Dynamics e o Stock Reconciliation do ERPNext.
--
-- Esta view classifica a contradição de cada produto para dirigir a contagem ao
-- que importa, em vez de contar 423 itens.

create or replace view public.v_estoque_variancia as
with mov as (
  select product_id,
         sum(quantity_delta) filter (where movement_type = 'purchase')                              as compras,
         sum(quantity_delta) filter (where movement_type in ('service_order_usage','service_usage')) as baixas,
         sum(quantity_delta) filter (where movement_type = 'return')                                as estornos,
         sum(quantity_delta) filter (where movement_type = 'manual_adjustment')                     as ajustes,
         sum(quantity_delta)                                                                        as soma_ledger,
         count(*)                                                                                   as qtd_movimentos
    from public.inventory_movements
   group by product_id
)
select
  p.id                       as product_id,
  p.name,
  p.sku,
  p.brand,
  p.stock_quantity           as saldo_atual,
  p.reserved_quantity        as reservado,
  (p.stock_quantity - coalesce(p.reserved_quantity,0)) as disponivel,
  p.sale_price,
  round(p.stock_quantity * coalesce(p.sale_price,0), 2) as valor_em_risco,
  b.stock_quantity           as saldo_no_backup,
  (p.stock_quantity - coalesce(b.stock_quantity,0))    as delta_desde_backup,
  coalesce(m.compras,0)      as compras,
  coalesce(m.baixas,0)       as baixas,
  coalesce(m.estornos,0)     as estornos,
  coalesce(m.ajustes,0)      as ajustes,
  coalesce(m.qtd_movimentos,0) as qtd_movimentos,
  case
    when p.stock_quantity < 0
      then 'estoque negativo'
    when p.stock_quantity > 0 and coalesce(m.compras,0) = 0 and coalesce(m.ajustes,0) = 0
      then 'estoque sem nenhuma compra'
    when coalesce(m.estornos,0) > -coalesce(m.baixas,0)
      then 'estornou mais do que baixou'
    when coalesce(p.reserved_quantity,0) > p.stock_quantity
      then 'reserva maior que o estoque'
    when p.stock_quantity <> coalesce(b.stock_quantity,0) and coalesce(m.qtd_movimentos,0) = 0
      then 'mudou sem nenhum movimento'
    else 'sem contradicao aparente'
  end as contradicao
from public.products p
left join public.products_stock_backup_pre_v2 b on b.id = p.id
left join mov m on m.product_id = p.id
where p.active;

comment on view public.v_estoque_variancia is
  'Fase B do plano de estoque: aponta contradições entre saldo e histórico. Só leitura. Dirige a contagem física; não substitui o saldo.';

grant select on public.v_estoque_variancia to authenticated;
