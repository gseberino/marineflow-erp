-- Módulo de COTAÇÃO a fornecedores (Fase 2 · Etapa 1) — 100% ADITIVO.
-- Não altera nenhuma tabela, trigger, RPC ou policy existente.
--
-- Contexto real da operação (confirmado com o dono):
--   • Compra sob demanda, SEM estoque → cada orçamento gera uma ou mais cotações (quase diária).
--   • Itens MISTURADOS: parte é produto do catálogo, parte é texto livre.
--     Por isso quote_request_items.product_id é NULLABLE e description é obrigatória.
--   • O ganho final é o custo cotado VOLTAR para o item do orçamento (recalcula margem),
--     por isso o item guarda de qual linha do orçamento ele veio.
--
-- Regra de confiança: nada aqui vira custo ou ordem de compra sozinho —
-- quote_responses.confirmed só fica true após confirmação humana.

create table if not exists public.quote_requests (
  id                 uuid primary key default gen_random_uuid(),
  code               text not null unique,                    -- COT-00042
  service_order_id   uuid references public.service_orders(id) on delete set null,
  status             text not null default 'open',            -- open | closed | cancelled
  sent_supplier_ids  uuid[] not null default '{}',            -- casa a resposta que chega no WhatsApp
  notes              text,
  created_by         uuid,
  created_at         timestamptz default now(),
  updated_at         timestamptz default now(),
  closed_at          timestamptz,
  constraint chk_qr_status check (status in ('open','closed','cancelled'))
);

create table if not exists public.quote_request_items (
  id                        uuid primary key default gen_random_uuid(),
  quote_request_id          uuid not null references public.quote_requests(id) on delete cascade,
  product_id                uuid references public.products(id) on delete set null,  -- NULL = item de texto livre
  description               text not null,
  quantity                  numeric(12,3) not null default 1,
  -- origem no orçamento, para devolver o custo depois (uma das duas, ou nenhuma)
  service_order_part_id     uuid references public.service_order_parts(id) on delete set null,
  service_order_service_id  uuid references public.service_order_services(id) on delete set null,
  position                  int not null default 1,                                 -- numeração enviada ao fornecedor
  created_at                timestamptz default now()
);

create table if not exists public.quote_responses (
  id                     uuid primary key default gen_random_uuid(),
  quote_request_id       uuid not null references public.quote_requests(id) on delete cascade,
  supplier_id            uuid not null references public.suppliers(id) on delete cascade,
  quote_request_item_id  uuid references public.quote_request_items(id) on delete cascade,
  unit_price             numeric(12,2),
  lead_time_days         int,
  source                 text not null default 'text',        -- text | audio | pdf | image | manual
  source_excerpt         text,                                -- trecho de onde o número saiu (auditoria)
  confirmed              boolean not null default false,      -- só vira custo/OC depois de confirmado
  whatsapp_message_id    text,
  created_at             timestamptz default now(),
  updated_at             timestamptz default now(),
  constraint chk_qresp_source check (source in ('text','audio','pdf','image','manual'))
);

-- Índices: casamento da resposta (fornecedor + cotações abertas) e montagem do comparativo.
create index if not exists idx_qr_status          on public.quote_requests (status);
create index if not exists idx_qr_service_order   on public.quote_requests (service_order_id);
create index if not exists idx_qr_sent_suppliers  on public.quote_requests using gin (sent_supplier_ids);
create index if not exists idx_qri_request        on public.quote_request_items (quote_request_id);
create index if not exists idx_qresp_request      on public.quote_responses (quote_request_id);
create index if not exists idx_qresp_supplier     on public.quote_responses (supplier_id);

-- RLS — mesmo padrão do restante do schema (authenticated_all_<tabela>).
alter table public.quote_requests      enable row level security;
alter table public.quote_request_items enable row level security;
alter table public.quote_responses     enable row level security;

drop policy if exists authenticated_all_quote_requests on public.quote_requests;
create policy authenticated_all_quote_requests on public.quote_requests
  for all to authenticated using (true) with check (true);

drop policy if exists authenticated_all_quote_request_items on public.quote_request_items;
create policy authenticated_all_quote_request_items on public.quote_request_items
  for all to authenticated using (true) with check (true);

drop policy if exists authenticated_all_quote_responses on public.quote_responses;
create policy authenticated_all_quote_responses on public.quote_responses
  for all to authenticated using (true) with check (true);

-- updated_at automático (reusa a função já existente no schema).
drop trigger if exists update_quote_requests_updated_at on public.quote_requests;
create trigger update_quote_requests_updated_at
  before update on public.quote_requests
  for each row execute function public.update_updated_at_column();

drop trigger if exists update_quote_responses_updated_at on public.quote_responses;
create trigger update_quote_responses_updated_at
  before update on public.quote_responses
  for each row execute function public.update_updated_at_column();
