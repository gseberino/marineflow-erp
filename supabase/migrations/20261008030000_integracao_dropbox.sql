-- Conexão do sistema com o Dropbox (Fase 2A, 08/10/2026 — plans/marineflow-dropbox-fase2.md).
-- Uma linha só (id = 1): a conta conectada e o refresh token CIFRADO (AES-GCM, chave no segredo
-- DROPBOX_TOKEN_KEY). Ninguém além do servidor lê: sem grant para anon/authenticated e sem
-- política — a tela pergunta o estado à edge dropbox-conectar, que nunca devolve o token.
-- Também a pasta-base onde o sistema cria as pastas dos barcos (app_settings), que começa na
-- pasta de teste e só depois do ensaio passa para /MANAGEMENT/COMMERCIAL/B2C. Idempotente.

create table if not exists public.integracao_dropbox (
  id                    smallint primary key default 1,
  conta_id              text not null,
  email                 text,
  nome                  text,
  refresh_token_cifrado text not null,
  conectado_em          timestamptz not null default now(),
  conectado_por         uuid references auth.users(id) on delete set null,
  ultimo_uso_em         timestamptz,
  ultimo_erro           text,
  ultimo_erro_em        timestamptz,
  constraint integracao_dropbox_uma_linha check (id = 1)
);

comment on table public.integracao_dropbox is
  'Conexão do MarineFlow com o Dropbox da HBR (uma linha). refresh_token_cifrado só é decifrado pelas edges com o segredo DROPBOX_TOKEN_KEY. Sem acesso para anon/authenticated.';

alter table public.integracao_dropbox enable row level security;
revoke all on table public.integracao_dropbox from public, anon, authenticated;
grant all on table public.integracao_dropbox to service_role;

insert into public.app_settings (key, value)
values ('dropbox_pasta_base', '/HBR-Testes/B2C')
on conflict (key) do nothing;
