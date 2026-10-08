-- Feed do Instagram para o site público (08/10/2026).
-- A função instagram-feed guarda aqui o token (renovado sozinho antes dos 60 dias) e os
-- últimos posts do @hbrsystems; o site lê os posts pelo GET público da função.
-- As duas tabelas são só do servidor (service role): RLS ligado, sem policy e sem grants.

create table if not exists public.instagram_conexao (
  id smallint primary key default 1 check (id = 1),
  access_token text not null,
  expira_em timestamptz,
  renovado_em timestamptz,
  ultima_busca timestamptz,
  ultimo_erro text,
  atualizado_em timestamptz not null default now()
);
comment on table public.instagram_conexao is 'Token do Instagram (API com login do Instagram). Linha única. Só service role.';

create table if not exists public.instagram_posts (
  id text primary key,
  tipo text not null,
  imagem text not null,
  permalink text not null,
  legenda text,
  publicado_em timestamptz,
  buscado_em timestamptz not null default now()
);
comment on table public.instagram_posts is 'Últimos posts do Instagram, para o site público. Atualizado pelo cron instagram-feed.';

alter table public.instagram_conexao enable row level security;
alter table public.instagram_posts enable row level security;
revoke all on public.instagram_conexao from anon, authenticated;
revoke all on public.instagram_posts from anon, authenticated;

-- A cada 6 horas: renova o token quando precisa e atualiza os posts (sem token, a função
-- responde sem_token e não faz nada).
do $$
begin
  if exists (select 1 from cron.job where jobname = 'instagram-feed') then
    perform cron.unschedule('instagram-feed');
  end if;
  perform cron.schedule('instagram-feed', '17 */6 * * *', $cron$
    SELECT net.http_post(
      url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/instagram-feed',
      headers    := jsonb_build_object(
        'Content-Type',  'application/json',
        'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
      ),
      body       := '{}'::jsonb,
      timeout_milliseconds := 30000
    );
  $cron$);
end $$;
