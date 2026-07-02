-- Ondas financeiras do ServiceOrderForm (1D, 1C, 2)
-- Onda 1D: flag de faturável ao cliente para despesas e deslocamento
alter table public.service_order_expenses
  add column if not exists billable_to_client boolean not null default true;

alter table public.service_orders
  add column if not exists is_travel_billable boolean not null default true;

-- Onda 1C: repasse da taxa de cartão ao cliente
alter table public.service_orders
  add column if not exists card_fee_passthrough_enabled boolean not null default false;

alter table public.service_orders
  add column if not exists card_fee_amount numeric(12,2) not null default 0;

-- Onda 2: desconto percentual por linha (serviço/peça)
alter table public.service_order_services
  add column if not exists discount_pct numeric(5,2) not null default 0;

alter table public.service_order_parts
  add column if not exists discount_pct numeric(5,2) not null default 0;

-- Onda 1C: visibilidade da taxa de cartão no orçamento/OS público (segue padrão public_view_show_*)
insert into public.app_settings (key, value, description)
values ('public_view_show_card_fee', 'true', 'Mostrar taxa de cartão repassada no link público')
on conflict (key) do nothing;
