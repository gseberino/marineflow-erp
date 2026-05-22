-- Signature security hardening.
-- Apply only during an approved cutover, after the compatible frontend and Edge
-- Functions are deployed. This migration intentionally removes anonymous direct
-- access to signature/order data used by the public signing flow.

begin;

alter table public.service_order_signatures
  add column if not exists signature_image_path text,
  add column if not exists signed_pdf_path text,
  add column if not exists pdf_sha256 text;

alter table public.service_orders
  add column if not exists share_token_expires_at timestamptz,
  add column if not exists share_token_revoked_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'service_order_signatures_pdf_sha256_hex'
      and conrelid = 'public.service_order_signatures'::regclass
  ) then
    alter table public.service_order_signatures
      add constraint service_order_signatures_pdf_sha256_hex
      check (pdf_sha256 is null or pdf_sha256 ~ '^[0-9a-f]{64}$');
  end if;
end $$;

create index if not exists idx_service_orders_share_token_active
  on public.service_orders (share_token)
  where share_token is not null and share_token_revoked_at is null;

create index if not exists idx_service_order_signatures_order_signed_at
  on public.service_order_signatures (service_order_id, signed_at desc);

update public.service_order_signatures
set signature_image_path = split_part(split_part(signature_image_url, '/storage/v1/object/public/signatures/', 2), '?', 1)
where signature_image_path is null
  and signature_image_url like '%/storage/v1/object/public/signatures/%';

update public.service_order_signatures
set signed_pdf_path = split_part(split_part(signed_pdf_url, '/storage/v1/object/public/signatures/', 2), '?', 1)
where signed_pdf_path is null
  and signed_pdf_url like '%/storage/v1/object/public/signatures/%';

comment on column public.service_order_signatures.signature_image_path is
  'Private Storage path in bucket signatures. Do not expose directly to clients.';
comment on column public.service_order_signatures.signed_pdf_path is
  'Private Storage path for the archived signed PDF. Use temporary signed URLs only.';
comment on column public.service_order_signatures.pdf_sha256 is
  'SHA-256 hash of the archived final signed PDF bytes.';
comment on column public.service_orders.share_token_expires_at is
  'Optional expiration timestamp for public service-order share links.';
comment on column public.service_orders.share_token_revoked_at is
  'Timestamp set when a public service-order share link is revoked.';

update storage.buckets
set public = false
where id = 'signatures';

drop policy if exists "signatures_public_read" on storage.objects;

drop policy if exists "Public document viewing via share_token" on public.service_orders;
drop policy if exists "Public parts viewing via service order" on public.service_order_parts;
drop policy if exists "Public services viewing via service order" on public.service_order_services;
drop policy if exists "Public clients viewing via service order" on public.clients;
drop policy if exists "Public vessels viewing via service order" on public.vessels;
drop policy if exists "Public company settings viewing" on public.app_settings;
drop policy if exists "anon_read_app_settings" on public.app_settings;
drop policy if exists "anon_read_signatures_by_token" on public.service_order_signatures;

drop policy if exists "staging_open_select" on public.service_orders;
drop policy if exists "staging_open_insert" on public.service_orders;
drop policy if exists "staging_open_update" on public.service_orders;
drop policy if exists "staging_open_delete" on public.service_orders;

drop policy if exists "staging_open_select" on public.service_order_parts;
drop policy if exists "staging_open_insert" on public.service_order_parts;
drop policy if exists "staging_open_update" on public.service_order_parts;
drop policy if exists "staging_open_delete" on public.service_order_parts;

drop policy if exists "staging_open_select" on public.service_order_services;
drop policy if exists "staging_open_insert" on public.service_order_services;
drop policy if exists "staging_open_update" on public.service_order_services;
drop policy if exists "staging_open_delete" on public.service_order_services;

drop policy if exists "staging_open_select" on public.service_order_signatures;
drop policy if exists "staging_open_insert" on public.service_order_signatures;
drop policy if exists "staging_open_update" on public.service_order_signatures;
drop policy if exists "staging_open_delete" on public.service_order_signatures;

drop policy if exists "staging_open_select" on public.clients;
drop policy if exists "staging_open_insert" on public.clients;
drop policy if exists "staging_open_update" on public.clients;
drop policy if exists "staging_open_delete" on public.clients;

drop policy if exists "staging_open_select" on public.vessels;
drop policy if exists "staging_open_insert" on public.vessels;
drop policy if exists "staging_open_update" on public.vessels;
drop policy if exists "staging_open_delete" on public.vessels;

drop policy if exists "staging_open_select" on public.app_settings;
drop policy if exists "staging_open_insert" on public.app_settings;
drop policy if exists "staging_open_update" on public.app_settings;
drop policy if exists "staging_open_delete" on public.app_settings;

drop policy if exists "staging_open_select" on public.audit_log;
drop policy if exists "staging_open_insert" on public.audit_log;
drop policy if exists "staging_open_update" on public.audit_log;
drop policy if exists "staging_open_delete" on public.audit_log;

revoke all on public.service_orders from anon;
revoke all on public.service_order_parts from anon;
revoke all on public.service_order_services from anon;
revoke all on public.service_order_signatures from anon;
revoke all on public.clients from anon;
revoke all on public.vessels from anon;
revoke all on public.app_settings from anon;
revoke all on public.audit_log from anon;

commit;
