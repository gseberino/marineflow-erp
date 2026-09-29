-- Vigia da conexão do WhatsApp: o ERP passa a saber quando o número da HBR cai.
--
-- POR QUE: em 29/09/2026 o celular removeu o aparelho conectado às 16:21 (código 401,
-- "device_removed") e ninguém soube por 4 horas. O vigia do PC (HBR-EvolutionAutoRecover)
-- só confere se o servidor responde — e respondia, com o número desconectado.
--
-- A função whatsapp-conexao roda a cada 5 min, guarda aqui UMA linha com o estado e avisa no
-- sino dos admins depois de 10 min fora do ar (e quando volta). Só a service role lê e escreve:
-- a tela recebe o que precisa pela própria função, depois de conferir que é admin.

create table if not exists public.whatsapp_conexao_vigia (
  id smallint primary key default 1 check (id = 1),
  estado text not null check (estado in ('open', 'connecting', 'close', 'inacessivel')),
  desde timestamptz not null default now(),
  verificado_em timestamptz not null default now(),
  detalhe text,
  avisado_em timestamptz,
  pedido_por uuid references public.app_users(id) on delete set null,
  pedido_em timestamptz
);

comment on table public.whatsapp_conexao_vigia is
  'Uma linha: estado da conexão do WhatsApp visto pelo vigia (whatsapp-conexao, a cada 5 min). Só service role.';

alter table public.whatsapp_conexao_vigia enable row level security;
revoke all on table public.whatsapp_conexao_vigia from anon, authenticated;

-- Reconectado às 20:04 de 29/09; o vigia parte daí.
insert into public.whatsapp_conexao_vigia (id, estado, desde)
values (1, 'open', '2026-09-29 23:04:30+00')
on conflict (id) do nothing;

select cron.schedule(
  'whatsapp-conexao-vigia',
  '*/5 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/whatsapp-conexao',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $$
);

insert into supabase_migrations.schema_migrations (version, name)
values ('20260929230000', 'whatsapp_conexao_vigia')
on conflict do nothing;
