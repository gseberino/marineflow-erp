-- Cotação: frete e desconto por fornecedor passam a ser gravados (Diário de Bordo, item
-- "Cotação · Frete e desconto por fornecedor não persistem").
--
-- A tela de comparação tinha um campo "Frete" por fornecedor que vivia só na memória da
-- página: fechou a aba, perdeu. O comparador (src/lib/quote-comparison.ts) já calculava
-- "pacote = itens − desconto + frete"; faltava o lugar para guardar os dois números.
-- Uma linha por (cotação, fornecedor); mesma RLS das respostas de cotação.

create table if not exists public.quote_request_supplier_terms (
  quote_request_id uuid not null references public.quote_requests(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  freight numeric(12,2) not null default 0 check (freight >= 0),
  discount numeric(12,2) not null default 0 check (discount >= 0),
  notes text,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (quote_request_id, supplier_id)
);

create index if not exists quote_request_supplier_terms_supplier_idx
  on public.quote_request_supplier_terms (supplier_id);

alter table public.quote_request_supplier_terms enable row level security;

create policy quote_request_supplier_terms_select on public.quote_request_supplier_terms
  for select to authenticated using (is_admin_or_financial(auth.uid()));
create policy quote_request_supplier_terms_insert on public.quote_request_supplier_terms
  for insert to authenticated with check (is_admin_or_financial(auth.uid()));
create policy quote_request_supplier_terms_update on public.quote_request_supplier_terms
  for update to authenticated using (is_admin_or_financial(auth.uid())) with check (is_admin_or_financial(auth.uid()));
create policy quote_request_supplier_terms_delete on public.quote_request_supplier_terms
  for delete to authenticated using (is_admin_or_financial(auth.uid()));

comment on table public.quote_request_supplier_terms is
  'Frete e desconto negociados por fornecedor dentro de uma cotação; entram no total do pacote (itens - desconto + frete).';

-- Aplicada por `db query -f` (sem `db push`): registra a si mesma.
insert into supabase_migrations.schema_migrations (version, name)
values ('20260919130000', 'cotacao_frete_desconto_por_fornecedor')
on conflict do nothing;
