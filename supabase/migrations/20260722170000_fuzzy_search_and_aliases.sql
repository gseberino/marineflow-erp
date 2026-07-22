-- Busca fuzzy real + aprender apelidos de produto (Onda 1 do plano de eficiência).
-- 100% ADITIVO: extensões, um índice, uma tabela nova e uma função de leitura. Nada existente
-- é alterado. Ver plans/marineflow-llm-orquestra-codigo-executa.md e o artifact das 26 melhorias.

create extension if not exists pg_trgm;
create extension if not exists unaccent;

-- Índice trigrama para a busca por similaridade não varrer a tabela conforme o catálogo cresce.
create index if not exists idx_products_name_trgm on public.products using gin (name gin_trgm_ops);

-- Busca fuzzy: word_similarity acha o termo como PARTE do nome (tolera "MultiPlus-II 12/3000"
-- casar "MultiPlus 12/3000/120"), e cobre erro de digitação e acento. O resolvedor no código
-- ainda pontua os candidatos por sobreposição de tokens para a escolha final.
create or replace function public.search_products_trgm(_term text, _lim int default 20)
returns table (id uuid, name text, sku text, brand text, sale_price numeric, cost_price numeric, sim real)
language sql stable
set search_path = public, extensions
as $$
  select p.id, p.name, p.sku, p.brand, p.sale_price, p.cost_price,
         word_similarity(unaccent(_term), unaccent(coalesce(p.name, ''))) as sim
  from products p
  where p.active
    and (
      word_similarity(unaccent(_term), unaccent(coalesce(p.name, ''))) >= 0.3
      or unaccent(coalesce(p.name, '')) ilike '%' || unaccent(_term) || '%'
      or coalesce(p.sku, '') ilike '%' || _term || '%'
    )
  order by sim desc
  limit greatest(1, least(coalesce(_lim, 20), 40));
$$;
grant execute on function public.search_products_trgm(text, int) to authenticated, service_role;

-- APELIDOS: quando o dono corrige um match ("MultiPlus-II é o 12/3000/120"), guardamos o
-- apelido normalizado -> produto. Na próxima, o resolvedor acerta de primeira. O agente fica
-- mais certeiro a cada uso, sem retreinar nada.
create table if not exists public.product_aliases (
  id               uuid primary key default gen_random_uuid(),
  alias_normalized text not null unique,          -- minúsculo, sem acento, trim
  alias_original   text not null,
  product_id       uuid not null references public.products(id) on delete cascade,
  created_by       uuid,
  created_at       timestamptz default now()
);
create index if not exists idx_product_aliases_product on public.product_aliases (product_id);

alter table public.product_aliases enable row level security;
drop policy if exists authenticated_all_product_aliases on public.product_aliases;
create policy authenticated_all_product_aliases on public.product_aliases
  for all to authenticated using (true) with check (true);

-- Normalização — a MESMA regra usada no código (minúsculo, sem acento, espaços colapsados).
create or replace function public.normalize_alias(_s text)
returns text language sql immutable set search_path = public, extensions as $$
  select trim(regexp_replace(lower(unaccent(coalesce(_s, ''))), '\s+', ' ', 'g'));
$$;
