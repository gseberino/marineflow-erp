-- Fase E1 do piloto de e-mail: o ESPELHO.
--
-- Guarda o e-mail que chega, sem nenhuma IA envolvida. A triagem (E2) só preenche
-- colunas desta tabela depois. Ver plans/marineflow-email-agente.md.
--
-- NÃO APLICADA. Este arquivo existe para revisão; a aplicação depende de autorização
-- explícita e de a Fase E0 (canal de entrada) ter sido validada primeiro — sem canal,
-- estas tabelas ficariam vazias.
--
-- Decisões de segurança tomadas aqui, e por quê:
--   · Bucket PRIVADO. Todos os buckets existentes no projeto são públicos, incluindo o
--     `signatures` — que a própria DECISOES-TECNICAS registra como "o risco mais grave"
--     (URL pública permanente gravada no banco). Correspondência de cliente e fornecedor
--     não repete esse erro: guarda-se o PATH, e a entrega é por signed URL temporária.
--   · Leitura só para admin. Correspondência é o dado mais sensível que o ERP vai guardar.
--     Quando `financeiro@` entrar (Fase E4), estende-se para o cargo financeiro.
--   · REVOKE explícito de anon/public: policy sem `to authenticated` não fecha anônimo,
--     porque as funções de cargo devolvem false para NULL em vez de bloquear.
--   · Escrita é exclusiva do service_role (Edge Functions). Nenhuma policy de INSERT
--     para usuário autenticado — o app nunca escreve e-mail, só lê.

-- ─────────────────────────── caixas monitoradas ───────────────────────────

create table if not exists public.email_accounts (
  id uuid primary key default gen_random_uuid(),
  address text not null unique,
  label text,
  -- endereço de inbound que recebe a cópia desta caixa (do provedor; não é domínio da HBR)
  route_alias text,
  active boolean not null default true,
  -- caixa de terceiro exige ciência do titular (LGPD) — ver §3.1.1 do plano
  owner_consent_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table public.email_accounts is
  'Caixas de e-mail espelhadas no ERP. owner_consent_at é obrigatório para caixa nominal de terceiro.';

-- ─────────────────────────── o espelho ───────────────────────────

create table if not exists public.email_messages (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.email_accounts(id) on delete cascade,

  -- Identidade. dedup_key é Message-ID quando existe, senão chave sintética por minuto
  -- (a reentrega do provedor no mesmo minuto não pode virar duas linhas).
  dedup_key text not null,
  message_id text,
  in_reply_to text,
  references_ids text[],
  thread_key text,

  from_name text,
  from_address text not null,
  to_addresses text[],
  cc_addresses text[],
  subject text,
  body_text text,
  received_at timestamptz not null,
  raw_size integer,
  has_attachments boolean not null default false,

  -- Veredito de autenticação da entrega ORIGINAL à GoDaddy. O encaminhamento quebra
  -- SPF, então este cabeçalho é lido, nunca recalculado por nós.
  auth_results text,

  -- Casamento com o cadastro (cascata determinística, sem IA)
  client_id uuid references public.clients(id) on delete set null,
  supplier_id uuid references public.suppliers(id) on delete set null,
  match_confidence numeric,
  match_reason text,

  -- Preenchido pela Fase E2. Null = ainda não triado.
  triage_class text check (triage_class in ('ignore','notify','respond','document','urgent')),
  triage_confidence numeric,
  triage_evidence text,
  triage_reason text,
  triage_fraud_alert boolean not null default false,
  triaged_at timestamptz,

  muted boolean not null default false,
  -- Retenção LGPD: o corpo some em 180 dias, os metadados ficam 24 meses.
  body_purged_at timestamptz,
  created_at timestamptz not null default now(),

  constraint email_messages_dedup_unique unique (account_id, dedup_key)
);

comment on column public.email_messages.dedup_key is
  'Message-ID normalizado, ou chave sintética remetente|assunto|minuto quando o cabeçalho falta.';
comment on column public.email_messages.auth_results is
  'Authentication-Results da entrega original. Encaminhamento quebra SPF: ler, nunca recalcular.';

create index if not exists email_messages_account_received_idx
  on public.email_messages (account_id, received_at desc);
create index if not exists email_messages_thread_idx
  on public.email_messages (thread_key) where thread_key is not null;
create index if not exists email_messages_triage_idx
  on public.email_messages (triage_class, received_at desc) where triage_class is not null;
create index if not exists email_messages_untriaged_idx
  on public.email_messages (received_at) where triaged_at is null;
create index if not exists email_messages_client_idx
  on public.email_messages (client_id) where client_id is not null;
create index if not exists email_messages_supplier_idx
  on public.email_messages (supplier_id) where supplier_id is not null;

-- ─────────────────────────── anexos ───────────────────────────

create table if not exists public.email_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.email_messages(id) on delete cascade,
  filename text,
  mime_type text,
  size_bytes integer,
  -- PATH no bucket privado. Nunca URL pública — ver cabeçalho deste arquivo.
  storage_path text,
  kind text not null default 'outro'
    check (kind in ('nfe_xml','boleto_pdf','danfe','imagem','planilha','outro')),
  -- Extração determinística (chave de NF-e conferida, linha digitável conferida)
  parsed_payload jsonb,
  processed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists email_attachments_message_idx
  on public.email_attachments (message_id);
create index if not exists email_attachments_kind_idx
  on public.email_attachments (kind) where processed_at is null;

-- ─────────────────────────── regras de remetente ───────────────────────────

create table if not exists public.email_sender_rules (
  id uuid primary key default gen_random_uuid(),
  -- endereço exato ou '@dominio.com.br'
  pattern text not null unique,
  action text not null check (action in ('ignore_always','always_notify')),
  reason text,
  created_by uuid references public.app_users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- ─────────────────────────── RLS ───────────────────────────

alter table public.email_accounts enable row level security;
alter table public.email_messages enable row level security;
alter table public.email_attachments enable row level security;
alter table public.email_sender_rules enable row level security;

-- Anônimo não tem nada aqui. REVOKE explícito porque policy sozinha não basta:
-- as funções de cargo devolvem false para NULL, o que não é o mesmo que bloquear.
revoke all on public.email_accounts     from anon, public;
revoke all on public.email_messages     from anon, public;
revoke all on public.email_attachments  from anon, public;
revoke all on public.email_sender_rules from anon, public;

grant select on public.email_accounts     to authenticated;
grant select on public.email_messages     to authenticated;
grant select on public.email_attachments  to authenticated;
grant select, insert, delete on public.email_sender_rules to authenticated;

-- Leitura: admin apenas (Fase E4 estende para financeiro quando financeiro@ entrar).
create policy email_accounts_read on public.email_accounts
  for select to authenticated
  using ((select public.is_admin(auth.uid())));

create policy email_messages_read on public.email_messages
  for select to authenticated
  using ((select public.is_admin(auth.uid())));

create policy email_attachments_read on public.email_attachments
  for select to authenticated
  using ((select public.is_admin(auth.uid())));

-- Silenciar remetente é a única escrita que o app faz.
create policy email_sender_rules_read on public.email_sender_rules
  for select to authenticated
  using ((select public.is_admin(auth.uid())));

create policy email_sender_rules_write on public.email_sender_rules
  for insert to authenticated
  with check ((select public.is_admin(auth.uid())));

create policy email_sender_rules_delete on public.email_sender_rules
  for delete to authenticated
  using ((select public.is_admin(auth.uid())));

-- ─────────────────────────── bucket privado ───────────────────────────

insert into storage.buckets (id, name, public, file_size_limit)
values ('email-attachments', 'email-attachments', false, 26214400)
on conflict (id) do update set public = false, file_size_limit = 26214400;

-- Sem policy de leitura pública, de propósito. A entrega ao app é por signed URL
-- gerada no servidor; o service_role das Edge Functions não passa por RLS.

-- ─────────────────────────── chaves de operação ───────────────────────────

insert into public.app_settings (key, value) values
  ('email_triage_enabled', 'true'),
  ('email_triage_cursor', ''),
  ('email_retention_body_days', '180')
on conflict (key) do nothing;
