-- FASE 2 do conserto do link público — amarra o token de verdade.
--
-- Antes: as políticas anônimas diziam apenas "share_token IS NOT NULL", ou seja,
-- qualquer portador da chave publicável (que vai no bundle, por definição) lia
-- TODAS as OS compartilhadas — 70 de 70, com 31 clientes, 33 embarcações e 118
-- produtos com preço e custo. O filtro por token existia, mas morava no frontend,
-- e filtro de cliente não é controle de acesso.
--
-- Agora: a política exige que o token da OS seja IGUAL ao apresentado no
-- cabeçalho x-share-token. Cabeçalho ausente => comparação NULL => nada visível.
-- Nega por omissão.
--
-- ORDEM: aplicada só DEPOIS que o frontend que envia o cabeçalho estava no ar e
-- o dono confirmou que o link do cliente abria normalmente (29/07/2026).
--
-- share_token é uuid e o cabeçalho chega como texto. A comparação é feita como
-- TEXTO de propósito: assim um token malformado simplesmente não casa, em vez de
-- derrubar a consulta com erro de cast — que viraria um jeito de distinguir
-- "token inválido" de "token válido de outra OS".
--
-- Verificado com o papel anon real, em transação abortada:
--   token certo  -> 1 OS, 1 cliente, 1 peça, 1 produto
--   token errado -> 0 em tudo
--   sem cabeçalho-> 0 em tudo

create or replace function public.share_token_da_requisicao()
returns text
language sql
stable
security definer
set search_path to 'public'
as $$
  select nullif(current_setting('request.headers', true)::json ->> 'x-share-token', '');
$$;

comment on function public.share_token_da_requisicao is
  'Token do link público apresentado no cabeçalho x-share-token. NULL quando ausente, o que faz as políticas anônimas negarem por omissão.';

grant execute on function public.share_token_da_requisicao to anon, authenticated;

drop policy if exists "Public document viewing via share_token" on public.service_orders;
drop policy if exists anon_service_orders_via_share_token on public.service_orders;
create policy anon_service_orders_via_share_token
  on public.service_orders for select to anon
  using (share_token is not null and share_token::text = public.share_token_da_requisicao());

drop policy if exists anon_clients_via_share_token on public.clients;
create policy anon_clients_via_share_token
  on public.clients for select to anon
  using (exists (select 1 from public.service_orders so
                  where so.client_id = clients.id
                    and so.share_token::text = public.share_token_da_requisicao()));

drop policy if exists anon_vessels_via_share_token on public.vessels;
create policy anon_vessels_via_share_token
  on public.vessels for select to anon
  using (exists (select 1 from public.service_orders so
                  where so.vessel_id = vessels.id
                    and so.share_token::text = public.share_token_da_requisicao()));

drop policy if exists anon_marinas_via_share_token on public.marinas;
create policy anon_marinas_via_share_token
  on public.marinas for select to anon
  using (exists (select 1 from public.service_orders so
                  where so.marina_id = marinas.id
                    and so.share_token::text = public.share_token_da_requisicao()));

drop policy if exists anon_products_via_share_token on public.products;
create policy anon_products_via_share_token
  on public.products for select to anon
  using (exists (select 1
                   from public.service_order_parts sp
                   join public.service_orders so on so.id = sp.service_order_id
                  where sp.product_id = products.id
                    and so.share_token::text = public.share_token_da_requisicao()));

drop policy if exists anon_service_order_parts_via_share_token on public.service_order_parts;
create policy anon_service_order_parts_via_share_token
  on public.service_order_parts for select to anon
  using (exists (select 1 from public.service_orders so
                  where so.id = service_order_parts.service_order_id
                    and so.share_token::text = public.share_token_da_requisicao()));

drop policy if exists anon_service_order_services_via_share_token on public.service_order_services;
create policy anon_service_order_services_via_share_token
  on public.service_order_services for select to anon
  using (exists (select 1 from public.service_orders so
                  where so.id = service_order_services.service_order_id
                    and so.share_token::text = public.share_token_da_requisicao()));

drop policy if exists anon_payment_condition_presets_via_share_token on public.payment_condition_presets;
create policy anon_payment_condition_presets_via_share_token
  on public.payment_condition_presets for select to anon
  using (exists (select 1 from public.service_orders so
                  where so.payment_condition_preset_id = payment_condition_presets.id
                    and so.share_token::text = public.share_token_da_requisicao()));

-- service_order_signatures já compara o token desde a fase 1 (a política correta
-- existia; o que faltava era remover a frouxa que a anulava). Fica como está.
