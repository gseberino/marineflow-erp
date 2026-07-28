-- FASE 2 do conserto do link público — amarra o token de verdade.
--
-- ATENÇÃO À ORDEM: esta migration só pode ser aplicada DEPOIS que o frontend que
-- envia o cabeçalho `x-share-token` estiver no ar. Aplicada antes, derruba o link
-- do cliente, porque nenhuma requisição traria o token para comparar.
--
-- O que muda: em vez de "existe um token nesta OS" (que libera TODAS as OS
-- compartilhadas para quem tem a chave publicável), a política passa a exigir que
-- o token da OS seja IGUAL ao token apresentado na requisição. Se o cabeçalho não
-- vier, a comparação dá NULL e nada é visível — negar por omissão.
--
-- O `.eq('share_token', ...)` que o app faz na query continua existindo, mas
-- deixa de ser a única coisa entre o visitante e o banco. Filtro de cliente é
-- conveniência de leitura; controle de acesso é isto aqui.

create or replace function public.share_token_da_requisicao()
returns text
language sql
stable
security definer
set search_path to 'public'
as $$
  select nullif(
    current_setting('request.headers', true)::json ->> 'x-share-token',
    ''
  );
$$;

comment on function public.share_token_da_requisicao is
  'Token do link público apresentado no cabeçalho x-share-token. NULL quando ausente, o que faz as políticas anônimas negarem por omissão.';

grant execute on function public.share_token_da_requisicao to anon, authenticated;

-- ---------------------------------------------------------------- service_orders
drop policy if exists "Public document viewing via share_token" on public.service_orders;
drop policy if exists anon_service_orders_via_share_token on public.service_orders;

create policy anon_service_orders_via_share_token
  on public.service_orders for select to anon
  using (share_token is not null and share_token = public.share_token_da_requisicao());

-- ---------------------------------------------------------------------- clients
drop policy if exists anon_clients_via_share_token on public.clients;

create policy anon_clients_via_share_token
  on public.clients for select to anon
  using (exists (
    select 1 from public.service_orders so
     where so.client_id = clients.id
       and so.share_token = public.share_token_da_requisicao()
  ));

-- ---------------------------------------------------------------------- vessels
drop policy if exists anon_vessels_via_share_token on public.vessels;

create policy anon_vessels_via_share_token
  on public.vessels for select to anon
  using (exists (
    select 1 from public.service_orders so
     where so.vessel_id = vessels.id
       and so.share_token = public.share_token_da_requisicao()
  ));

-- ---------------------------------------------------------------------- marinas
drop policy if exists anon_marinas_via_share_token on public.marinas;

create policy anon_marinas_via_share_token
  on public.marinas for select to anon
  using (exists (
    select 1 from public.service_orders so
     where so.marina_id = marinas.id
       and so.share_token = public.share_token_da_requisicao()
  ));

-- --------------------------------------------------------------------- products
drop policy if exists anon_products_via_share_token on public.products;

create policy anon_products_via_share_token
  on public.products for select to anon
  using (exists (
    select 1
      from public.service_order_parts sp
      join public.service_orders so on so.id = sp.service_order_id
     where sp.product_id = products.id
       and so.share_token = public.share_token_da_requisicao()
  ));

-- ---------------------------------------------------------- service_order_parts
drop policy if exists anon_service_order_parts_via_share_token on public.service_order_parts;

create policy anon_service_order_parts_via_share_token
  on public.service_order_parts for select to anon
  using (exists (
    select 1 from public.service_orders so
     where so.id = service_order_parts.service_order_id
       and so.share_token = public.share_token_da_requisicao()
  ));

-- ------------------------------------------------------- service_order_services
drop policy if exists anon_service_order_services_via_share_token on public.service_order_services;

create policy anon_service_order_services_via_share_token
  on public.service_order_services for select to anon
  using (exists (
    select 1 from public.service_orders so
     where so.id = service_order_services.service_order_id
       and so.share_token = public.share_token_da_requisicao()
  ));

-- ----------------------------------------------- payment_condition_presets
drop policy if exists anon_payment_condition_presets_via_share_token on public.payment_condition_presets;

create policy anon_payment_condition_presets_via_share_token
  on public.payment_condition_presets for select to anon
  using (exists (
    select 1 from public.service_orders so
     where so.payment_condition_preset_id = payment_condition_presets.id
       and so.share_token = public.share_token_da_requisicao()
  ));

-- service_order_signatures já compara o token desde a fase 1 (a política correta
-- existia; o que faltava era remover a frouxa que a anulava). Fica como está.
