-- Adiciona discount_amount (R$) como fonte da verdade do desconto por linha,
-- em vez de discount_pct (numeric(5,2), 2 casas decimais). Editar o desconto
-- via valor em R$ ou "valor final" e depois converter para % antes de
-- persistir perdia centavos (ex.: R$10,12 sobre R$1.000,00 vira 1,012%,
-- que arredondado a 2 casas fica 1,01%, e o valor real aplicado cai para
-- R$10,10). discount_pct continua existindo, mas passa a ser só exibição,
-- derivado de discount_amount.

alter table public.service_order_services
  add column if not exists discount_amount numeric(12,2) not null default 0;

alter table public.service_order_parts
  add column if not exists discount_amount numeric(12,2) not null default 0;

-- Backfill: linhas existentes já têm discount_pct definido, mas ainda não
-- têm discount_amount (acabou de ser criada com default 0).
update public.service_order_services
set discount_amount = round(quantity * unit_price_snapshot * discount_pct / 100, 2)
where discount_pct > 0 and discount_amount = 0;

update public.service_order_parts
set discount_amount = round(quantity * unit_sale_snapshot * discount_pct / 100, 2)
where discount_pct > 0 and discount_amount = 0;
