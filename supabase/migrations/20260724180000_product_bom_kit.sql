-- BOM / Produto composto / Kit.
--  simples   = produto normal.
--  kit       = venda agrupada (1 linha no orçamento; na NF-e, quando implementado, explode nos
--              componentes, pois um kit não é mercadoria autônoma para a Fazenda).
--  composto  = produzido a partir de componentes (produção); custo = Σ custo dos componentes.
-- O cost roll-up mantém o CUSTO do pai em dia sempre que a lista de componentes muda.

alter table public.products
  add column if not exists product_type text not null default 'simples';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'products_product_type_check'
  ) then
    alter table public.products
      add constraint products_product_type_check
      check (product_type in ('simples', 'kit', 'composto'));
  end if;
end $$;

create table if not exists public.product_components (
  id uuid primary key default gen_random_uuid(),
  parent_product_id    uuid not null references public.products(id) on delete cascade,
  component_product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric not null default 1 check (quantity > 0),
  created_at timestamptz not null default now(),
  unique (parent_product_id, component_product_id),
  constraint product_components_no_self check (parent_product_id <> component_product_id)
);
create index if not exists idx_product_components_parent    on public.product_components(parent_product_id);
create index if not exists idx_product_components_component on public.product_components(component_product_id);

alter table public.product_components enable row level security;
-- Espelha o acesso de products: quem está autenticado enxerga/edita a composição.
drop policy if exists product_components_rw on public.product_components;
create policy product_components_rw on public.product_components
  for all to authenticated
  using (auth.uid() is not null)
  with check (auth.uid() is not null);

-- Roll-up: custo do pai = Σ (quantidade × custo do componente). Só para kit/composto.
create or replace function public.recompute_product_cost(_parent uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  total numeric;
begin
  select coalesce(sum(pc.quantity * coalesce(c.cost_price, 0)), 0)
    into total
  from public.product_components pc
  join public.products c on c.id = pc.component_product_id
  where pc.parent_product_id = _parent;

  update public.products
     set cost_price = total
   where id = _parent
     and product_type in ('kit', 'composto');
end;
$$;

create or replace function public.trg_product_components_rollup()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  perform public.recompute_product_cost(coalesce(new.parent_product_id, old.parent_product_id));
  return coalesce(new, old);
end;
$$;

drop trigger if exists product_components_rollup on public.product_components;
create trigger product_components_rollup
  after insert or update or delete on public.product_components
  for each row execute function public.trg_product_components_rollup();
