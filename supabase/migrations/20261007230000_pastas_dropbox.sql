-- Pastas do Dropbox ligadas a cliente e embarcação (07/10/2026).
-- Fase 1 da integração com o Dropbox: o Dropbox guarda os arquivos, o sistema guarda o índice.
-- Uma linha por pasta (cliente, embarcação, parceiro ou prospecção). O vínculo é pelo id do
-- Dropbox, que sobrevive a renomear e mover a pasta; o caminho é só para mostrar.
-- Não escreve dados de negócio. Idempotente.

create table if not exists public.pastas_dropbox (
  id             uuid primary key default gen_random_uuid(),
  dropbox_id     text not null,
  caminho        text not null,
  client_id      uuid references public.clients(id) on delete set null,
  vessel_id      uuid references public.vessels(id) on delete set null,
  codigo_projeto text,
  situacao       text not null default 'vinculada',
  nome_na_pasta  text,
  observacao     text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint pastas_dropbox_id_formato check (dropbox_id ~ '^id:[A-Za-z0-9_-]+$'),
  constraint pastas_dropbox_situacao_chk check (situacao in ('vinculada', 'dono_a_identificar', 'prospeccao', 'arquivo')),
  constraint pastas_dropbox_codigo_formato check (codigo_projeto is null or codigo_projeto ~ '^[0-9]{4}\.[0-9]{3}\.[0-9]{2}$'),
  -- Vinculada precisa de alguém; embarcação sem cliente não existe (vessels.client_id é obrigatório).
  constraint pastas_dropbox_vinculada_tem_dono check (situacao <> 'vinculada' or client_id is not null)
);

comment on table public.pastas_dropbox is
  'Índice das pastas do Dropbox da HBR (Dropbox = arquivo; sistema = índice). dropbox_id é o id estável do Dropbox; codigo_projeto segue o padrão NNNN.SSS.AA das pastas do dono (número geral . número do ano . ano).';
comment on column public.pastas_dropbox.situacao is
  'vinculada: ligada a cliente (e embarcação, se houver); dono_a_identificar: barco conhecido, dono não; prospeccao: parceiro/estaleiro sem relação comercial; arquivo: guardada sem vínculo.';

create unique index if not exists pastas_dropbox_dropbox_id_unico on public.pastas_dropbox (dropbox_id);
create unique index if not exists pastas_dropbox_codigo_unico on public.pastas_dropbox (codigo_projeto) where codigo_projeto is not null;
create index if not exists pastas_dropbox_client on public.pastas_dropbox (client_id) where client_id is not null;
create index if not exists pastas_dropbox_vessel on public.pastas_dropbox (vessel_id) where vessel_id is not null;

drop trigger if exists update_pastas_dropbox_updated_at on public.pastas_dropbox;
create trigger update_pastas_dropbox_updated_at before update on public.pastas_dropbox
  for each row execute function public.update_updated_at_column();

alter table public.pastas_dropbox enable row level security;
revoke all on table public.pastas_dropbox from public, anon, authenticated;
grant select, insert, update on table public.pastas_dropbox to authenticated;
grant all on table public.pastas_dropbox to service_role;

drop policy if exists pastas_dropbox_admin_le on public.pastas_dropbox;
create policy pastas_dropbox_admin_le on public.pastas_dropbox
  for select to authenticated using (public.is_admin((select auth.uid())));
drop policy if exists pastas_dropbox_admin_cria on public.pastas_dropbox;
create policy pastas_dropbox_admin_cria on public.pastas_dropbox
  for insert to authenticated with check (public.is_admin((select auth.uid())));
drop policy if exists pastas_dropbox_admin_muda on public.pastas_dropbox;
create policy pastas_dropbox_admin_muda on public.pastas_dropbox
  for update to authenticated using (public.is_admin((select auth.uid()))) with check (public.is_admin((select auth.uid())));
