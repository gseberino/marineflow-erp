-- Duas decisões do dono de 14/09/2026.
--
-- (1) Vigilante de despesas (Executivo Financeiro, módulo IV): só AVISA. A edge finance-review
--     ganha a ação `vigiar`, que grava propostas de kind 'anomaly' na caixa de entrada
--     (valor fora do padrão do fornecedor, fornecedor novo, recorrência que parou,
--     duplicidade). Roda uma vez por dia, cedo, para o briefing das 07:30 já contar os alertas.
--
-- (7) Telas legadas (MF-AUD-037): as 19 telas v1 serão apagadas em 15/10/2026 — as que
--     ninguém abrir até lá. Esta tabela mede isso: um registro por tela por sessão quando a
--     tela legada é renderizada de fato (`?legacy=1`).

create table if not exists public.legacy_screen_hits (
  id uuid primary key default gen_random_uuid(),
  path text not null,
  user_id uuid default auth.uid() references public.app_users(id) on delete set null,
  user_agent text,
  hit_at timestamptz not null default now()
);
comment on table public.legacy_screen_hits is
  'Acessos às telas legadas (?legacy=1). Base para apagar em 15/10/2026 o que ninguém abriu (MF-AUD-037).';
create index if not exists legacy_screen_hits_path_hit on public.legacy_screen_hits (path, hit_at desc);

alter table public.legacy_screen_hits enable row level security;
drop policy if exists "legacy_hits_insert" on public.legacy_screen_hits;
create policy "legacy_hits_insert" on public.legacy_screen_hits
  for insert to authenticated with check (true);
drop policy if exists "legacy_hits_select_admin" on public.legacy_screen_hits;
create policy "legacy_hits_select_admin" on public.legacy_screen_hits
  for select to authenticated using (public.is_admin(auth.uid()));
revoke all on public.legacy_screen_hits from anon;

-- Vigilante: diário às 06:30 de Brasília (09:30 UTC), antes do briefing das 07:30.
select cron.schedule(
  'finance-vigilante',
  '30 9 * * *',
  $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/finance-review',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{"action": "vigiar"}'::jsonb,
    timeout_milliseconds := 60000
  );
  $cron$
)
where not exists (select 1 from cron.job where jobname = 'finance-vigilante');

-- Auto-registro da versão do arquivo (regra 1 do CLAUDE.md).
insert into supabase_migrations.schema_migrations (version, name)
values ('20260914150000', 'vigilante_e_telas_legadas')
on conflict (version) do nothing;
