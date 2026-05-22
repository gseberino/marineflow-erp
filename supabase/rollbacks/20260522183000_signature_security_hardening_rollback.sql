-- Emergency rollback for 20260522183000_signature_security_hardening.sql.
-- This restores the previous insecure public access model and should only be
-- used to recover service during an approved incident response.

begin;

update storage.buckets
set public = true
where id = 'signatures';

create policy "signatures_public_read"
on storage.objects
for select
to public
using (bucket_id = 'signatures');

grant select, insert, update, delete on public.service_orders to anon;
grant select, insert, update, delete on public.service_order_parts to anon;
grant select, insert, update, delete on public.service_order_services to anon;
grant select, insert, update, delete on public.service_order_signatures to anon;
grant select, insert, update, delete on public.clients to anon;
grant select, insert, update, delete on public.vessels to anon;
grant select, insert, update, delete on public.app_settings to anon;
grant select, insert, update, delete on public.audit_log to anon;

create policy "Public document viewing via share_token"
on public.service_orders
for select
to anon
using (share_token is not null);

create policy "Public parts viewing via service order"
on public.service_order_parts
for select
to anon
using (true);

create policy "Public services viewing via service order"
on public.service_order_services
for select
to anon
using (true);

create policy "Public clients viewing via service order"
on public.clients
for select
to anon
using (true);

create policy "Public vessels viewing via service order"
on public.vessels
for select
to anon
using (true);

create policy "Public company settings viewing"
on public.app_settings
for select
to anon
using (true);

create policy "anon_read_app_settings"
on public.app_settings
for select
to anon
using (true);

create policy "anon_read_signatures_by_token"
on public.service_order_signatures
for select
to anon
using (
  exists (
    select 1
    from public.service_orders so
    where so.id = service_order_signatures.service_order_id
      and so.share_token is not null
      and so.share_token = service_order_signatures.share_token
  )
);

create policy "staging_open_select" on public.service_orders for select to anon, authenticated using (true);
create policy "staging_open_insert" on public.service_orders for insert to anon, authenticated with check (true);
create policy "staging_open_update" on public.service_orders for update to anon, authenticated using (true) with check (true);
create policy "staging_open_delete" on public.service_orders for delete to anon, authenticated using (true);

create policy "staging_open_select" on public.service_order_parts for select to anon, authenticated using (true);
create policy "staging_open_insert" on public.service_order_parts for insert to anon, authenticated with check (true);
create policy "staging_open_update" on public.service_order_parts for update to anon, authenticated using (true) with check (true);
create policy "staging_open_delete" on public.service_order_parts for delete to anon, authenticated using (true);

create policy "staging_open_select" on public.service_order_services for select to anon, authenticated using (true);
create policy "staging_open_insert" on public.service_order_services for insert to anon, authenticated with check (true);
create policy "staging_open_update" on public.service_order_services for update to anon, authenticated using (true) with check (true);
create policy "staging_open_delete" on public.service_order_services for delete to anon, authenticated using (true);

create policy "staging_open_select" on public.service_order_signatures for select to anon, authenticated using (true);
create policy "staging_open_insert" on public.service_order_signatures for insert to anon, authenticated with check (true);
create policy "staging_open_update" on public.service_order_signatures for update to anon, authenticated using (true) with check (true);
create policy "staging_open_delete" on public.service_order_signatures for delete to anon, authenticated using (true);

create policy "staging_open_select" on public.clients for select to anon, authenticated using (true);
create policy "staging_open_insert" on public.clients for insert to anon, authenticated with check (true);
create policy "staging_open_update" on public.clients for update to anon, authenticated using (true) with check (true);
create policy "staging_open_delete" on public.clients for delete to anon, authenticated using (true);

create policy "staging_open_select" on public.vessels for select to anon, authenticated using (true);
create policy "staging_open_insert" on public.vessels for insert to anon, authenticated with check (true);
create policy "staging_open_update" on public.vessels for update to anon, authenticated using (true) with check (true);
create policy "staging_open_delete" on public.vessels for delete to anon, authenticated using (true);

create policy "staging_open_select" on public.app_settings for select to anon, authenticated using (true);
create policy "staging_open_insert" on public.app_settings for insert to anon, authenticated with check (true);
create policy "staging_open_update" on public.app_settings for update to anon, authenticated using (true) with check (true);
create policy "staging_open_delete" on public.app_settings for delete to anon, authenticated using (true);

create policy "staging_open_select" on public.audit_log for select to anon, authenticated using (true);
create policy "staging_open_insert" on public.audit_log for insert to anon, authenticated with check (true);
create policy "staging_open_update" on public.audit_log for update to anon, authenticated using (true) with check (true);
create policy "staging_open_delete" on public.audit_log for delete to anon, authenticated using (true);

commit;
