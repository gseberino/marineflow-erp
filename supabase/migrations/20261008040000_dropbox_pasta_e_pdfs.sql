-- Dropbox Fase 2B/2C (08/10/2026 — plans/marineflow-dropbox-fase2.md): a pasta do barco e os PDFs.
--   1. proximo_codigo_projeto(): o próximo número NNNN.SSS.AA (geral . do ano . ano), calculado
--      sobre pastas_dropbox — não repete nem pula (os contadores à mão geraram 0007 e 0008 com o
--      mesmo .004.25 e buracos).
--   2. dropbox_envios: a fila. Cada linha é "garantir a pasta do barco" ou "guardar o PDF deste
--      orçamento/OS". O worker dropbox-worker (pg_cron, 5 min) processa uma de cada vez — escritas
--      paralelas na pasta compartilhada dão 429 too_many_write_operations.
--   3. Gatilhos: orçamento/OS criado → pasta; enviado ao cliente, aprovado, concluído → PDF;
--      assinatura com PDF → o PDF assinado. O gatilho NUNCA derruba a gravação da OS.
--   4. O agendamento do worker.
-- Não escreve dados de negócio. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. O próximo número de projeto
-- ---------------------------------------------------------------------------------------------
create or replace function public.proximo_codigo_projeto(_quando date default ((now() at time zone 'America/Sao_Paulo')::date))
returns text
language sql
stable
set search_path = ''
as $$
  with c as (select codigo_projeto from public.pastas_dropbox where codigo_projeto is not null),
       a as (select to_char(_quando, 'YY') as yy)
  select lpad((coalesce(max(substr(c.codigo_projeto, 1, 4)::int), 0) + 1)::text, 4, '0')
      || '.'
      || lpad((coalesce(max(substr(c.codigo_projeto, 6, 3)::int) filter (where substr(c.codigo_projeto, 10, 2) = (select yy from a)), 0) + 1)::text, 3, '0')
      || '.'
      || (select yy from a)
    from c;
$$;

comment on function public.proximo_codigo_projeto(date) is
  'Próximo código de pasta de projeto NNNN.SSS.AA (número geral . número do ano . ano com 2 dígitos), sobre pastas_dropbox. Só o servidor chama.';

revoke all on function public.proximo_codigo_projeto(date) from public;
revoke all on function public.proximo_codigo_projeto(date) from anon;
revoke all on function public.proximo_codigo_projeto(date) from authenticated;
grant execute on function public.proximo_codigo_projeto(date) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 2. A fila
-- ---------------------------------------------------------------------------------------------
create table if not exists public.dropbox_envios (
  id                uuid primary key default gen_random_uuid(),
  order_id          uuid references public.service_orders(id) on delete cascade,
  vessel_id         uuid references public.vessels(id) on delete cascade,
  motivo            text not null,
  referencia        text,
  status            text not null default 'pendente',
  tentativas        integer not null default 0,
  proxima_em        timestamptz not null default now(),
  processando_desde timestamptz,
  resultado         text,
  impressao_digital text,
  versao            integer,
  dropbox_id        text,
  caminho           text,
  pedido_por        uuid references auth.users(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint dropbox_envios_motivo_chk check (motivo in ('pasta', 'enviado', 'aprovado', 'concluido', 'assinado', 'manual')),
  constraint dropbox_envios_status_chk check (status in ('pendente', 'processando', 'feito', 'ignorado', 'falhou')),
  constraint dropbox_envios_alvo_chk check (order_id is not null or vessel_id is not null)
);

comment on table public.dropbox_envios is
  'Fila do Dropbox: garantir a pasta do barco (motivo pasta) ou guardar o PDF do orçamento/OS (enviado/aprovado/concluido/assinado/manual). Processada pela edge dropbox-worker, uma de cada vez.';
comment on column public.dropbox_envios.referencia is 'motivo assinado: caminho do PDF assinado no bucket signatures.';
comment on column public.dropbox_envios.impressao_digital is 'Conteúdo do documento sem o carimbo de emissão: igual ao último guardado = não sobe de novo.';

-- Um pendente por alvo e motivo: pedir duas vezes não duplica.
create unique index if not exists dropbox_envios_um_pendente
  on public.dropbox_envios (coalesce(order_id, vessel_id), motivo)
  where status in ('pendente', 'processando');
create index if not exists dropbox_envios_fila on public.dropbox_envios (proxima_em) where status = 'pendente';
create index if not exists dropbox_envios_ordem on public.dropbox_envios (order_id, created_at desc) where order_id is not null;

drop trigger if exists update_dropbox_envios_updated_at on public.dropbox_envios;
create trigger update_dropbox_envios_updated_at before update on public.dropbox_envios
  for each row execute function public.update_updated_at_column();

alter table public.dropbox_envios enable row level security;
revoke all on table public.dropbox_envios from public, anon, authenticated;
grant select, insert on table public.dropbox_envios to authenticated;
grant all on table public.dropbox_envios to service_role;

drop policy if exists dropbox_envios_admin_le on public.dropbox_envios;
create policy dropbox_envios_admin_le on public.dropbox_envios
  for select to authenticated using (public.is_admin((select auth.uid())));
-- Pela tela só se pede "criar a pasta" ou "salvar agora"; o resto vem dos gatilhos.
drop policy if exists dropbox_envios_admin_pede on public.dropbox_envios;
create policy dropbox_envios_admin_pede on public.dropbox_envios
  for insert to authenticated
  with check (public.is_admin((select auth.uid())) and motivo in ('pasta', 'manual') and status = 'pendente' and tentativas = 0);

-- O worker pega um lote (e devolve à fila o que ficou travado em "processando" por mais de 10 min).
create or replace function public.dropbox_pegar_envios(_limite integer default 5)
returns setof public.dropbox_envios
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.dropbox_envios
     set status = 'pendente', processando_desde = null
   where status = 'processando' and processando_desde < now() - interval '10 minutes';

  return query
  update public.dropbox_envios e
     set status = 'processando', processando_desde = now(), tentativas = e.tentativas + 1
   where e.id in (
     select id from public.dropbox_envios
      where status = 'pendente' and proxima_em <= now()
      order by proxima_em, created_at
      limit greatest(1, least(_limite, 20))
      for update skip locked
   )
  returning e.*;
end $$;

revoke all on function public.dropbox_pegar_envios(integer) from public;
revoke all on function public.dropbox_pegar_envios(integer) from anon;
revoke all on function public.dropbox_pegar_envios(integer) from authenticated;
grant execute on function public.dropbox_pegar_envios(integer) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 3. Gatilhos (nunca derrubam a gravação de origem)
-- ---------------------------------------------------------------------------------------------
create or replace function private.dropbox_enfileirar_ordem()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  _motivo text;
begin
  if tg_op = 'INSERT' then
    _motivo := 'pasta';
  elsif new.quote_status = 'sent' and old.quote_status is distinct from 'sent' then
    _motivo := 'enviado';
  elsif (new.status = 'approved' and old.status is distinct from 'approved')
     or (new.quote_status = 'approved' and old.quote_status is distinct from 'approved') then
    _motivo := 'aprovado';
  elsif new.status = 'completed' and old.status is distinct from 'completed' then
    _motivo := 'concluido';
  else
    return new;
  end if;
  insert into public.dropbox_envios (order_id, vessel_id, motivo)
  values (new.id, new.vessel_id, _motivo)
  on conflict do nothing;
  return new;
exception when others then
  raise warning 'dropbox_enfileirar_ordem (%): %', new.id, sqlerrm;
  return new;
end $$;

drop trigger if exists trg_dropbox_ordem on public.service_orders;
create trigger trg_dropbox_ordem
  after insert or update of status, quote_status on public.service_orders
  for each row execute function private.dropbox_enfileirar_ordem();

create or replace function private.dropbox_enfileirar_assinatura()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.signed_pdf_url is null
     or (tg_op = 'UPDATE' and old.signed_pdf_url is not distinct from new.signed_pdf_url) then
    return new;
  end if;
  insert into public.dropbox_envios (order_id, motivo, referencia)
  values (new.service_order_id, 'assinado', new.signed_pdf_url)
  on conflict do nothing;
  return new;
exception when others then
  raise warning 'dropbox_enfileirar_assinatura (%): %', new.id, sqlerrm;
  return new;
end $$;

drop trigger if exists trg_dropbox_assinatura on public.service_order_signatures;
create trigger trg_dropbox_assinatura
  after insert or update of signed_pdf_url on public.service_order_signatures
  for each row execute function private.dropbox_enfileirar_assinatura();

-- ---------------------------------------------------------------------------------------------
-- 4. O worker a cada 5 minutos (mesmo padrão dos outros: x-cron-secret de app_settings)
-- ---------------------------------------------------------------------------------------------
do $$
begin
  perform cron.unschedule('dropbox-worker') where exists (select 1 from cron.job where jobname = 'dropbox-worker');
  perform cron.schedule('dropbox-worker', '*/5 * * * *', $cron$
    SELECT net.http_post(
      url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/dropbox-worker',
      headers    := jsonb_build_object(
        'Content-Type',  'application/json',
        'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
      ),
      body       := '{}'::jsonb,
      timeout_milliseconds := 55000
    );
  $cron$);
end $$;
