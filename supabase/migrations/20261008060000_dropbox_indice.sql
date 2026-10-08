-- Dropbox Fase 3 (08/10/2026 — plans/marineflow-dropbox-fase2.md, seção "Fase 3"): o índice dos
-- arquivos que o dono solta nas pastas.
--   arquivos_dropbox: a ficha de cada arquivo (nome, caminho, tamanho, data) ligada à pasta do
--     barco/cliente (pastas_dropbox) que a contém. Só a ficha: o conteúdo continua no Dropbox.
--   integracao_dropbox ganha o cursor do Dropbox ("o que mudou desde a última vez").
--   app_settings.dropbox_indice_raiz: de onde o índice lê (começa em /MANAGEMENT/COMMERCIAL).
--   pg_cron a cada 10 min chama a edge dropbox-indice, que segue o cursor e, na primeira vez,
--   lê o histórico inteiro aos poucos (retoma de onde parou).
-- Não escreve dados de negócio. Idempotente.

create table if not exists public.arquivos_dropbox (
  id            uuid primary key default gen_random_uuid(),
  dropbox_id    text not null,
  caminho       text not null,
  caminho_lower text not null,
  nome          text not null,
  extensao      text,
  tamanho       bigint,
  modificado_em timestamptz,
  content_hash  text,
  pasta_id      uuid references public.pastas_dropbox(id) on delete set null,
  origem        text not null default 'dono',
  apagado       boolean not null default false,
  apagado_em    timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint arquivos_dropbox_origem_chk check (origem in ('dono', 'sistema'))
);

comment on table public.arquivos_dropbox is
  'Índice dos arquivos do Dropbox (só a ficha, nunca o conteúdo), ligado à pasta do barco/cliente. Mantido pela edge dropbox-indice com o cursor do Dropbox. origem sistema = subido pelo dropbox-worker.';

create unique index if not exists arquivos_dropbox_dropbox_id_unico on public.arquivos_dropbox (dropbox_id);
create index if not exists arquivos_dropbox_pasta on public.arquivos_dropbox (pasta_id, modificado_em desc) where not apagado;
create index if not exists arquivos_dropbox_caminho on public.arquivos_dropbox (caminho_lower text_pattern_ops);

drop trigger if exists update_arquivos_dropbox_updated_at on public.arquivos_dropbox;
create trigger update_arquivos_dropbox_updated_at before update on public.arquivos_dropbox
  for each row execute function public.update_updated_at_column();

alter table public.arquivos_dropbox enable row level security;
revoke all on table public.arquivos_dropbox from public, anon, authenticated;
grant select on table public.arquivos_dropbox to authenticated;
grant all on table public.arquivos_dropbox to service_role;

drop policy if exists arquivos_dropbox_admin_le on public.arquivos_dropbox;
create policy arquivos_dropbox_admin_le on public.arquivos_dropbox
  for select to authenticated using (public.is_admin((select auth.uid())));

-- Apagar uma pasta no Dropbox chega como UM aviso com o caminho: marca tudo que estava embaixo.
create or replace function public.dropbox_marcar_apagados(_caminhos text[])
returns integer
language sql
security definer
set search_path = ''
as $$
  with alvo as (select lower(c) as c from unnest(_caminhos) as c),
  mudou as (
    update public.arquivos_dropbox a
       set apagado = true, apagado_em = now()
      from alvo
     where not a.apagado
       and (a.caminho_lower = alvo.c or a.caminho_lower like replace(replace(alvo.c, '_', '\_'), '%', '\%') || '/%')
    returning 1
  )
  select count(*)::int from mudou;
$$;

revoke all on function public.dropbox_marcar_apagados(text[]) from public;
revoke all on function public.dropbox_marcar_apagados(text[]) from anon;
revoke all on function public.dropbox_marcar_apagados(text[]) from authenticated;
grant execute on function public.dropbox_marcar_apagados(text[]) to service_role;

alter table public.integracao_dropbox
  add column if not exists indice_cursor        text,
  add column if not exists indice_raiz          text,
  add column if not exists indice_carga_inicial boolean not null default false,
  add column if not exists indice_atualizado_em timestamptz;

insert into public.app_settings (key, value)
values ('dropbox_indice_raiz', '/MANAGEMENT/COMMERCIAL')
on conflict (key) do nothing;

do $$
begin
  perform cron.unschedule('dropbox-indice') where exists (select 1 from cron.job where jobname = 'dropbox-indice');
  perform cron.schedule('dropbox-indice', '*/10 * * * *', $cron$
    SELECT net.http_post(
      url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/dropbox-indice',
      headers    := jsonb_build_object(
        'Content-Type',  'application/json',
        'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
      ),
      body       := '{}'::jsonb,
      timeout_milliseconds := 55000
    );
  $cron$);
end $$;
