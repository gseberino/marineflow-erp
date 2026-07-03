-- AI Operator — versiona no repo as tabelas ai_operator_* que já existem em produção
-- (criadas por um projeto anterior, "hbr-agent-core", sem migration versionada).
-- Todo CREATE TABLE/CREATE INDEX abaixo é IF NOT EXISTS e reflete EXATAMENTE o schema
-- já confirmado ao vivo via introspecção (information_schema + pg_constraint +
-- pg_indexes + pg_policies) em 03/07/2026 — rodar esta migration em produção é um
-- no-op para o que já existe; só as colunas novas em ai_operator_messages (tokens_in/
-- tokens_out/cache_read_tokens/model) e os 2 índices novos no fim realmente mudam algo.
--
-- FORA DE ESCOPO DE PROPÓSITO: ai_operator_drafts, ai_operator_draft_items e
-- ai_workflows também existem em produção (mesmo projeto órfão) mas não são usadas
-- pelo novo plano do AI Operator (que usa ai_operator_pending_actions diretamente, não
-- o conceito de "draft"). Ficam sem migration por enquanto. As FKs de draft_id abaixo
-- (pending_actions, audit, memory_notes, channel_events) dependem de
-- ai_operator_drafts já existir — em produção já existe; se este arquivo for rodado
-- num banco novo do zero, ai_operator_drafts precisa ser criada antes.
--
-- RLS: todas as 6 tabelas já têm RLS habilitado e policies de SELECT (dono via
-- owner_user_id/requested_by_user_id/created_by, ou admin, via funções auxiliares em
-- private.ai_op_is_admin/is_active/is_internal/is_admin_or_financial — não redefinidas
-- aqui). NÃO há policies de INSERT/UPDATE para usuários autenticados — de propósito:
-- toda escrita nestas tabelas parte do backend (edge functions) usando o client
-- service-role, nunca direto do client autenticado. Não alteramos policies existentes
-- nesta migration (risco desnecessário mexer em RLS de tabelas com dado financeiro/
-- conversas por transcrição manual) — só documentamos abaixo, em comentário, os nomes
-- já vigentes: ai_op_sessions_select, ai_op_messages_select, ai_op_pending_select,
-- ai_op_memory_select, ai_op_audit_select, ai_op_channel_events_select.

-- ============================== ai_operator_sessions ==============================
create table if not exists public.ai_operator_sessions (
  id uuid primary key default gen_random_uuid(),
  channel text not null check (channel = any (array['web','whatsapp','system'])),
  channel_provider text,
  owner_user_id uuid references public.app_users(id) on delete set null,
  client_id uuid references public.clients(id) on delete set null,
  vessel_id uuid references public.vessels(id) on delete set null,
  service_order_id uuid references public.service_orders(id) on delete set null,
  external_thread_key text,
  status text not null default 'open' check (status = any (array['open','paused','closed'])),
  metadata jsonb not null default '{}'::jsonb,
  last_activity_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.ai_operator_sessions enable row level security;

create index if not exists idx_ai_op_sessions_channel on public.ai_operator_sessions using btree (channel, status);
create index if not exists idx_ai_op_sessions_client on public.ai_operator_sessions using btree (client_id);
create index if not exists idx_ai_op_sessions_owner on public.ai_operator_sessions using btree (owner_user_id);
create index if not exists idx_ai_op_sessions_thread on public.ai_operator_sessions using btree (external_thread_key) where (external_thread_key is not null);
create index if not exists idx_ai_op_sessions_vessel on public.ai_operator_sessions using btree (vessel_id);
-- Novo (Fase 2): carregar as sessões mais recentes de um usuário rapidamente.
create index if not exists idx_ai_op_sessions_owner_activity on public.ai_operator_sessions using btree (owner_user_id, last_activity_at desc);

-- ============================== ai_operator_messages ===============================
create table if not exists public.ai_operator_messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.ai_operator_sessions(id) on delete cascade,
  role text not null check (role = any (array['user','assistant','tool','system'])),
  content text,
  tool_calls jsonb,
  tool_call_id text,
  tool_name text,
  attachments jsonb,
  source text default 'web' check (source = any (array['web','whatsapp','system','api'])),
  source_message_id uuid,
  created_at timestamptz not null default now()
);

alter table public.ai_operator_messages enable row level security;

create index if not exists idx_ai_op_messages_session on public.ai_operator_messages using btree (session_id, created_at);
create index if not exists idx_ai_op_messages_source on public.ai_operator_messages using btree (source_message_id) where (source_message_id is not null);

-- Novo (Fase 2): custo/tokens por mensagem — não existiam no schema órfão original.
alter table public.ai_operator_messages add column if not exists tokens_in integer;
alter table public.ai_operator_messages add column if not exists tokens_out integer;
alter table public.ai_operator_messages add column if not exists cache_read_tokens integer;
alter table public.ai_operator_messages add column if not exists model text;

-- ========================== ai_operator_pending_actions =============================
create table if not exists public.ai_operator_pending_actions (
  id uuid primary key default gen_random_uuid(),
  session_id uuid references public.ai_operator_sessions(id) on delete set null,
  draft_id uuid references public.ai_operator_drafts(id) on delete set null,
  requested_by_user_id uuid references public.app_users(id) on delete set null,
  approved_by_user_id uuid references public.app_users(id) on delete set null,
  rejected_by_user_id uuid references public.app_users(id) on delete set null,
  action_name text not null,
  risk_level text not null default 'medium' check (risk_level = any (array['low','medium','high','critical'])),
  risk_reason text,
  title text,
  summary text,
  payload jsonb not null,
  status text not null default 'pending' check (status = any (array['pending','approved','rejected','executed','failed','expired'])),
  result jsonb,
  expires_at timestamptz,
  approved_at timestamptz,
  rejected_at timestamptz,
  executed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.ai_operator_pending_actions enable row level security;

create index if not exists idx_ai_op_pending_draft on public.ai_operator_pending_actions using btree (draft_id);
create index if not exists idx_ai_op_pending_session on public.ai_operator_pending_actions using btree (session_id);
create index if not exists idx_ai_op_pending_status on public.ai_operator_pending_actions using btree (status, created_at);
-- Novo (Fase 2, preparando a Fase 5): expire-pending-actions vai filtrar por isso.
create index if not exists idx_ai_op_pending_status_expires on public.ai_operator_pending_actions using btree (status, expires_at);

-- =========================== ai_operator_memory_notes ================================
create table if not exists public.ai_operator_memory_notes (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.clients(id) on delete cascade,
  vessel_id uuid references public.vessels(id) on delete cascade,
  scope text not null default 'vessel' check (scope = any (array['vessel','client','global'])),
  topic text not null,
  title text not null,
  body text not null,
  confidence text not null default 'medium' check (confidence = any (array['low','medium','high'])),
  source text not null default 'ai' check (source = any (array['ai','human','imported'])),
  source_reference text,
  verification_status text not null default 'candidate' check (verification_status = any (array['candidate','verified','rejected'])),
  verified_by uuid references public.app_users(id) on delete set null,
  verified_at timestamptz,
  rejected_by uuid references public.app_users(id) on delete set null,
  rejected_at timestamptz,
  created_by uuid references public.app_users(id) on delete set null,
  draft_id uuid references public.ai_operator_drafts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.ai_operator_memory_notes enable row level security;

create index if not exists idx_ai_op_memory_client on public.ai_operator_memory_notes using btree (client_id) where (client_id is not null);
create index if not exists idx_ai_op_memory_topic on public.ai_operator_memory_notes using btree (topic);
create index if not exists idx_ai_op_memory_verified on public.ai_operator_memory_notes using btree (verification_status);
create index if not exists idx_ai_op_memory_vessel on public.ai_operator_memory_notes using btree (vessel_id) where (vessel_id is not null);

-- Nota (Fase 2): scope aqui é vessel/client/global (não user/global como o plano
-- original supunha) — usamos scope='global' para as notas que remember_note grava,
-- já que é o valor mais próximo do que a Fase 2 precisa (nenhuma nota por-usuário
-- ainda). Adaptado ao schema real em vez de forçar o desenho original.

-- =============================== ai_operator_audit ====================================
create table if not exists public.ai_operator_audit (
  id uuid primary key default gen_random_uuid(),
  session_id uuid references public.ai_operator_sessions(id) on delete set null,
  draft_id uuid references public.ai_operator_drafts(id) on delete set null,
  pending_action_id uuid references public.ai_operator_pending_actions(id) on delete set null,
  actor_user_id uuid references public.app_users(id) on delete set null,
  actor_kind text not null check (actor_kind = any (array['user','ai_model','system','channel'])),
  event_type text not null,
  event_category text not null default 'info' check (event_category = any (array['info','security','data','channel','error'])),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.ai_operator_audit enable row level security;

create index if not exists idx_ai_op_audit_event on public.ai_operator_audit using btree (event_type, created_at);
create index if not exists idx_ai_op_audit_session on public.ai_operator_audit using btree (session_id, created_at);

-- ============================ ai_operator_channel_events ================================
create table if not exists public.ai_operator_channel_events (
  id uuid primary key default gen_random_uuid(),
  channel text not null check (channel = any (array['whatsapp','web','system'])),
  provider text not null check (provider = any (array['zapi','evolution','n8n','web','system'])),
  external_event_id text,
  external_thread_key text,
  direction text not null default 'inbound' check (direction = any (array['inbound','outbound'])),
  payload jsonb not null,
  status text not null default 'queued' check (status = any (array['queued','processing','processed','skipped','failed'])),
  processed_at timestamptz,
  last_error text,
  attempts integer not null default 0,
  session_id uuid references public.ai_operator_sessions(id) on delete set null,
  draft_id uuid references public.ai_operator_drafts(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.ai_operator_channel_events enable row level security;

create index if not exists idx_ai_op_channel_events_status on public.ai_operator_channel_events using btree (status, created_at);
create index if not exists idx_ai_op_channel_events_thread on public.ai_operator_channel_events using btree (external_thread_key);
create unique index if not exists ux_ai_op_channel_events_external on public.ai_operator_channel_events using btree (provider, external_event_id) where (external_event_id is not null);
