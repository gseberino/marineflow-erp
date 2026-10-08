-- E-mail no assistente, rota IMAP (08/10/2026, decisão do dono: "conectar meus e-mails" em vez
-- de encaminhar cópia). As caixas são da GoDaddy (Workspace, imap.secureserver.net:993); o dono
-- cadastrou as senhas como segredos do servidor (EMAIL_FINANCEIRO_SENHA, EMAIL_GUSTAVO_SENHA) —
-- a tabela guarda só o NOME do segredo, nunca a senha.
--
-- Agendamento (aplicar DEPOIS de publicar a função email-imap — mesmo padrão dos outros crons):
--   select cron.schedule('email-imap', '*/10 * * * *', $cron$ select net.http_post(
--     url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/email-imap',
--     headers := jsonb_build_object('Content-Type','application/json','x-cron-secret',
--       (select value::text from app_settings where key = 'cron_worker_secret' limit 1)),
--     body := '{}'::jsonb, timeout_milliseconds := 140000); $cron$);
--
-- O espelho (tabelas de 03/08) já deduplica por Message-ID; o que faltava era o cursor da leitura
-- IMAP: até que UID cada caixa já foi lida, e o UIDVALIDITY (se o servidor renumerar a caixa, o
-- cursor zera e a deduplicação por Message-ID evita repetir).

alter table public.email_accounts
  add column if not exists imap_host text,
  add column if not exists imap_port integer not null default 993,
  add column if not exists secret_name text,
  add column if not exists history_days integer not null default 90,
  add column if not exists imap_uidvalidity bigint,
  add column if not exists imap_last_uid bigint,
  add column if not exists last_sync_at timestamptz,
  add column if not exists last_sync_status text,
  add column if not exists last_sync_message text;

comment on column public.email_accounts.secret_name is
  'NOME do segredo do servidor com a senha da caixa (a senha nunca fica no banco).';
comment on column public.email_accounts.imap_last_uid is
  'Último UID IMAP já lido da INBOX (cursor). Nulo = primeira leitura: busca os últimos history_days dias.';

alter table public.email_messages
  add column if not exists imap_uid bigint,
  add column if not exists imap_uidvalidity bigint,
  add column if not exists alerted_at timestamptz;

comment on column public.email_messages.alerted_at is
  'Quando o e-mail URGENTE foi avisado no WhatsApp (teto de 3 por dia).';

create index if not exists email_messages_alerted_idx on public.email_messages (alerted_at) where alerted_at is not null;

-- As duas caixas que o dono escolheu (07/10/2026).
insert into public.email_accounts (address, label, active, owner_consent_at, imap_host, secret_name)
values
  ('financeiro@hbrmarine.com.br', 'Financeiro', true, now(), 'imap.secureserver.net', 'EMAIL_FINANCEIRO_SENHA'),
  ('gustavo@hbrmarine.com.br', 'Gustavo', true, now(), 'imap.secureserver.net', 'EMAIL_GUSTAVO_SENHA')
on conflict (address) do update
  set imap_host = excluded.imap_host, secret_name = excluded.secret_name, active = true,
      owner_consent_at = coalesce(public.email_accounts.owner_consent_at, excluded.owner_consent_at);

insert into supabase_migrations.schema_migrations (version, name)
values ('20261008100000', 'email_imap');
