-- Dropbox Fase 4 (08/10/2026 — plans/marineflow-dropbox-fase2.md): triagem das fotos de "Envio da
-- câmera". O dono escolhe a OS (ou só o barco) de cada grupo de fotos; o sistema move as fotos para
-- "<pasta do barco>/3- FOTOS/AAAA-MM-DD OS-xxxxx" e liga cada uma à OS aqui.
-- Não escreve dados de negócio. Idempotente.

alter table public.arquivos_dropbox
  add column if not exists order_id uuid references public.service_orders(id) on delete set null;

comment on column public.arquivos_dropbox.order_id is
  'OS a que o arquivo pertence (hoje: fotos ligadas na triagem de "Envio da câmera").';

create index if not exists arquivos_dropbox_ordem on public.arquivos_dropbox (order_id, modificado_em desc)
  where order_id is not null and not apagado;

insert into public.app_settings (key, value)
values ('dropbox_pasta_camera', '/Envio da câmera')
on conflict (key) do nothing;
