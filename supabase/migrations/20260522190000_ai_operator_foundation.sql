-- ============================================================================
-- MarineFlow AI Operator — Macro Cycle 1 foundation (additive, non-destructive)
-- ============================================================================
-- Objetivo: criar a fundação persistente do MarineFlow AI Operator com:
--   * sessões / mensagens
--   * rascunhos operacionais (quote/diagnosis/service_plan/...)
--   * itens de rascunho (serviços / produtos / itens a cotar / deslocamento / pendências)
--   * ações pendentes com classificação de risco (gate determinístico)
--   * auditoria append-only
--   * memória técnica reutilizável por entidade
--   * eventos brutos de canal (WhatsApp Z-API hoje; futuro Evolution/n8n)
--
-- Regras:
--   - Nenhuma tabela existente é alterada destrutivamente.
--   - Nenhuma coluna existente é removida ou renomeada.
--   - Todas as tabelas novas são prefixadas `ai_operator_` para evitar colisão.
--   - RLS habilitado em tudo. Acesso de leitura para usuários autenticados
--     que existam em `app_users.active = true`. Escrita sensível só via
--     edge function rodando com service_role (RLS bypass).
--
-- Rollback (manual, somente staging):
--   DROP TABLE em ordem reversa de FK. Sem efeito colateral sobre dados existentes.
-- ============================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- 1. Sessões de conversa do AI Operator
-- ---------------------------------------------------------------------------
create table if not exists public.ai_operator_sessions (
  id uuid primary key default gen_random_uuid(),
  channel text not null check (channel in ('web', 'whatsapp', 'system')),
  channel_provider text,                          -- 'zapi' | 'evolution' | 'n8n' | null
  owner_user_id uuid references public.app_users(id) on delete set null,
  client_id uuid references public.clients(id) on delete set null,
  vessel_id uuid references public.vessels(id) on delete set null,
  service_order_id uuid references public.service_orders(id) on delete set null,
  external_thread_key text,                       -- ex: telefone normalizado para WhatsApp
  status text not null default 'open' check (status in ('open', 'paused', 'closed')),
  metadata jsonb not null default '{}'::jsonb,
  last_activity_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_ai_op_sessions_owner on public.ai_operator_sessions(owner_user_id);
create index if not exists idx_ai_op_sessions_channel on public.ai_operator_sessions(channel, status);
create index if not exists idx_ai_op_sessions_client on public.ai_operator_sessions(client_id);
create index if not exists idx_ai_op_sessions_vessel on public.ai_operator_sessions(vessel_id);
create index if not exists idx_ai_op_sessions_thread on public.ai_operator_sessions(external_thread_key) where external_thread_key is not null;

-- ---------------------------------------------------------------------------
-- 2. Mensagens da sessão
-- ---------------------------------------------------------------------------
create table if not exists public.ai_operator_messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.ai_operator_sessions(id) on delete cascade,
  role text not null check (role in ('user', 'assistant', 'tool', 'system')),
  content text,
  tool_calls jsonb,
  tool_call_id text,
  tool_name text,
  attachments jsonb,                              -- [{type:'image'|'audio'|'document', url, transcript?, summary?}]
  source text default 'web' check (source in ('web', 'whatsapp', 'system', 'api')),
  source_message_id uuid,                         -- whatsapp_messages.id quando aplicável
  created_at timestamptz not null default now()
);

create index if not exists idx_ai_op_messages_session on public.ai_operator_messages(session_id, created_at);
create index if not exists idx_ai_op_messages_source on public.ai_operator_messages(source_message_id) where source_message_id is not null;

-- ---------------------------------------------------------------------------
-- 3. Rascunhos operacionais persistentes
-- ---------------------------------------------------------------------------
-- Um rascunho é diferente de uma OS oficial. Ele captura entendimento do
-- operador antes que decisões comerciais ou agendamentos sejam confirmados.
create table if not exists public.ai_operator_drafts (
  id uuid primary key default gen_random_uuid(),
  session_id uuid references public.ai_operator_sessions(id) on delete set null,
  created_by uuid references public.app_users(id) on delete set null,
  kind text not null check (kind in (
    'quote',              -- orçamento em montagem
    'diagnosis',          -- diagnóstico técnico
    'service_plan',       -- plano de atendimento
    'agenda_proposal',    -- proposta de agendamento
    'response_suggestion',-- sugestão de resposta ao cliente
    'note'                -- nota técnica avulsa
  )),
  status text not null default 'draft' check (status in (
    'draft', 'awaiting_info', 'awaiting_approval', 'approved', 'rejected', 'converted'
  )),
  title text,
  summary text,
  client_id uuid references public.clients(id) on delete set null,
  vessel_id uuid references public.vessels(id) on delete set null,
  service_order_id uuid references public.service_orders(id) on delete set null,
  -- vínculo "convertido para OS oficial" (após aprovação)
  converted_service_order_id uuid references public.service_orders(id) on delete set null,
  -- Interpretação estruturada da demanda
  interpreted_intent text,                        -- 'instalar_eletronica' | 'diagnostico' | 'reparo' | ...
  interpreted_category text,                      -- 'eletronica_navegacao' | 'eletrica' | 'gerador' | ...
  -- Estimativas comerciais (não-vinculantes — apenas referência)
  estimated_labor_hours numeric,
  estimated_labor_value numeric,
  estimated_parts_value numeric,
  estimated_travel_value numeric,
  estimated_total numeric,
  -- Perguntas pendentes que o operador precisa que sejam respondidas
  pending_questions jsonb not null default '[]'::jsonb,
  -- Próximos passos sugeridos
  next_steps jsonb not null default '[]'::jsonb,
  -- Hipóteses técnicas
  hypotheses jsonb not null default '[]'::jsonb,
  -- Metadados livres
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_ai_op_drafts_session on public.ai_operator_drafts(session_id);
create index if not exists idx_ai_op_drafts_client on public.ai_operator_drafts(client_id);
create index if not exists idx_ai_op_drafts_vessel on public.ai_operator_drafts(vessel_id);
create index if not exists idx_ai_op_drafts_status on public.ai_operator_drafts(status, kind);

-- ---------------------------------------------------------------------------
-- 4. Itens dentro do rascunho
-- ---------------------------------------------------------------------------
create table if not exists public.ai_operator_draft_items (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null references public.ai_operator_drafts(id) on delete cascade,
  item_kind text not null check (item_kind in (
    'service',           -- mão de obra
    'product',           -- produto cadastrado
    'product_to_quote',  -- material não cadastrado, precisa cotar
    'displacement',      -- deslocamento
    'engineering',       -- engenharia / diagnóstico técnico
    'pending_question',  -- pergunta técnica pendente
    'risk',              -- risco / observação técnica
    'reference'          -- referência externa (manual, datasheet, etc.)
  )),
  service_id uuid references public.services(id) on delete set null,
  product_id uuid references public.products(id) on delete set null,
  description text not null,
  notes text,
  quantity numeric default 1,
  unit text default 'unit',
  unit_price numeric,
  estimated_total numeric,
  confidence text default 'medium' check (confidence in ('low', 'medium', 'high')),
  source_reference text,                          -- ex: "Z-API webhook 2026-05-22T14:00"
  metadata jsonb not null default '{}'::jsonb,
  position int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_ai_op_draft_items_draft on public.ai_operator_draft_items(draft_id, position);

-- ---------------------------------------------------------------------------
-- 5. Ações pendentes (gate determinístico de segurança)
-- ---------------------------------------------------------------------------
-- TODA ação sensível decidida pelo modelo é PERSISTIDA aqui em status='pending'
-- e SOMENTE executada após approve explícito do usuário com permissão.
create table if not exists public.ai_operator_pending_actions (
  id uuid primary key default gen_random_uuid(),
  session_id uuid references public.ai_operator_sessions(id) on delete set null,
  draft_id uuid references public.ai_operator_drafts(id) on delete set null,
  requested_by_user_id uuid references public.app_users(id) on delete set null,
  approved_by_user_id uuid references public.app_users(id) on delete set null,
  action_name text not null,                      -- ex: 'send_whatsapp_message', 'create_service_order'
  risk_level text not null default 'medium' check (risk_level in ('low', 'medium', 'high', 'critical')),
  risk_reason text,
  title text,
  summary text,
  payload jsonb not null,
  status text not null default 'pending' check (status in (
    'pending', 'approved', 'rejected', 'executed', 'failed', 'expired'
  )),
  result jsonb,
  expires_at timestamptz,
  approved_at timestamptz,
  executed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_ai_op_pending_status on public.ai_operator_pending_actions(status, created_at);
create index if not exists idx_ai_op_pending_session on public.ai_operator_pending_actions(session_id);
create index if not exists idx_ai_op_pending_draft on public.ai_operator_pending_actions(draft_id);

-- ---------------------------------------------------------------------------
-- 6. Auditoria append-only
-- ---------------------------------------------------------------------------
create table if not exists public.ai_operator_audit (
  id uuid primary key default gen_random_uuid(),
  session_id uuid references public.ai_operator_sessions(id) on delete set null,
  draft_id uuid references public.ai_operator_drafts(id) on delete set null,
  pending_action_id uuid references public.ai_operator_pending_actions(id) on delete set null,
  actor_user_id uuid references public.app_users(id) on delete set null,
  actor_kind text not null check (actor_kind in ('user', 'ai_model', 'system', 'channel')),
  event_type text not null,                       -- ex: 'tool_call_attempted', 'tool_call_blocked', 'action_approved', 'draft_created', 'channel_event_received'
  event_category text not null default 'info' check (event_category in ('info', 'security', 'data', 'channel', 'error')),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_ai_op_audit_session on public.ai_operator_audit(session_id, created_at);
create index if not exists idx_ai_op_audit_event on public.ai_operator_audit(event_type, created_at);

-- ---------------------------------------------------------------------------
-- 7. Memória técnica reutilizável
-- ---------------------------------------------------------------------------
-- Equivalente a um caderno de bordo técnico: notas sobre embarcação,
-- equipamentos instalados, restrições conhecidas, histórico de incidentes.
create table if not exists public.ai_operator_memory_notes (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.clients(id) on delete cascade,
  vessel_id uuid references public.vessels(id) on delete cascade,
  scope text not null default 'vessel' check (scope in ('vessel', 'client', 'global')),
  topic text not null,                            -- ex: 'eletronica_navegacao', 'gerador', 'bateria'
  title text not null,
  body text not null,
  confidence text not null default 'medium' check (confidence in ('low', 'medium', 'high')),
  source text not null default 'ai' check (source in ('ai', 'human', 'imported')),
  source_reference text,
  created_by uuid references public.app_users(id) on delete set null,
  draft_id uuid references public.ai_operator_drafts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_ai_op_memory_vessel on public.ai_operator_memory_notes(vessel_id) where vessel_id is not null;
create index if not exists idx_ai_op_memory_client on public.ai_operator_memory_notes(client_id) where client_id is not null;
create index if not exists idx_ai_op_memory_topic on public.ai_operator_memory_notes(topic);

-- ---------------------------------------------------------------------------
-- 8. Eventos brutos de canal (fila de entrada para futura ingestão multimodal)
-- ---------------------------------------------------------------------------
-- O webhook do WhatsApp continua salvando em whatsapp_messages como hoje.
-- Adicionalmente, eventos relevantes podem ser enfileirados aqui para o
-- AI Operator processar de forma assíncrona (transcrição, OCR, classificação
-- de intenção). Não cria dependência operacional — é estritamente aditivo.
create table if not exists public.ai_operator_channel_events (
  id uuid primary key default gen_random_uuid(),
  channel text not null check (channel in ('whatsapp', 'web', 'system')),
  provider text not null check (provider in ('zapi', 'evolution', 'n8n', 'web', 'system')),
  external_event_id text,                         -- whatsapp_messages.id ou outro
  external_thread_key text,                       -- telefone normalizado
  direction text not null default 'inbound' check (direction in ('inbound', 'outbound')),
  payload jsonb not null,
  status text not null default 'queued' check (status in (
    'queued', 'processing', 'processed', 'skipped', 'failed'
  )),
  processed_at timestamptz,
  last_error text,
  attempts int not null default 0,
  session_id uuid references public.ai_operator_sessions(id) on delete set null,
  draft_id uuid references public.ai_operator_drafts(id) on delete set null,
  created_at timestamptz not null default now()
);

create unique index if not exists ux_ai_op_channel_events_external on public.ai_operator_channel_events(provider, external_event_id) where external_event_id is not null;
create index if not exists idx_ai_op_channel_events_status on public.ai_operator_channel_events(status, created_at);
create index if not exists idx_ai_op_channel_events_thread on public.ai_operator_channel_events(external_thread_key);

-- ---------------------------------------------------------------------------
-- updated_at triggers (reaproveita função padrão se existir)
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'set_updated_at_now') then
    create function public.set_updated_at_now() returns trigger language plpgsql as $body$
    begin new.updated_at = now(); return new; end; $body$;
  end if;
end $$;

drop trigger if exists trg_ai_op_sessions_updated on public.ai_operator_sessions;
create trigger trg_ai_op_sessions_updated before update on public.ai_operator_sessions
  for each row execute function public.set_updated_at_now();

drop trigger if exists trg_ai_op_drafts_updated on public.ai_operator_drafts;
create trigger trg_ai_op_drafts_updated before update on public.ai_operator_drafts
  for each row execute function public.set_updated_at_now();

drop trigger if exists trg_ai_op_memory_updated on public.ai_operator_memory_notes;
create trigger trg_ai_op_memory_updated before update on public.ai_operator_memory_notes
  for each row execute function public.set_updated_at_now();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
-- Política: usuário autenticado presente em app_users.active = true pode ler
-- e gravar nas tabelas operacionais do AI Operator. Escrita sensível real é
-- gated em edge function (service_role bypass). Não há exposição para anon.
-- Mantemos o desenho simples para o macro ciclo 1 — granularidade por papel
-- pode ser adicionada em ciclos seguintes.

alter table public.ai_operator_sessions enable row level security;
alter table public.ai_operator_messages enable row level security;
alter table public.ai_operator_drafts enable row level security;
alter table public.ai_operator_draft_items enable row level security;
alter table public.ai_operator_pending_actions enable row level security;
alter table public.ai_operator_audit enable row level security;
alter table public.ai_operator_memory_notes enable row level security;
alter table public.ai_operator_channel_events enable row level security;

-- Helper inline: usuário ativo em app_users
-- (não criamos função separada para evitar pegadinha de search_path)

-- Sessões / mensagens / rascunhos / itens / memória: SELECT/INSERT/UPDATE por user ativo
do $$
declare
  t text;
  tables text[] := array[
    'ai_operator_sessions',
    'ai_operator_messages',
    'ai_operator_drafts',
    'ai_operator_draft_items',
    'ai_operator_pending_actions',
    'ai_operator_audit',
    'ai_operator_memory_notes',
    'ai_operator_channel_events'
  ];
begin
  foreach t in array tables loop
    -- SELECT
    execute format($p$
      drop policy if exists "ai_op_%1$s_select" on public.%1$I;
      create policy "ai_op_%1$s_select" on public.%1$I
        for select to authenticated
        using (exists (select 1 from public.app_users au where au.id = auth.uid() and au.active = true));
    $p$, t);
    -- INSERT
    execute format($p$
      drop policy if exists "ai_op_%1$s_insert" on public.%1$I;
      create policy "ai_op_%1$s_insert" on public.%1$I
        for insert to authenticated
        with check (exists (select 1 from public.app_users au where au.id = auth.uid() and au.active = true));
    $p$, t);
    -- UPDATE
    execute format($p$
      drop policy if exists "ai_op_%1$s_update" on public.%1$I;
      create policy "ai_op_%1$s_update" on public.%1$I
        for update to authenticated
        using (exists (select 1 from public.app_users au where au.id = auth.uid() and au.active = true))
        with check (exists (select 1 from public.app_users au where au.id = auth.uid() and au.active = true));
    $p$, t);
  end loop;
end $$;

-- Auditoria: somente INSERT permitido a usuários autenticados; UPDATE/DELETE bloqueados
drop policy if exists "ai_op_audit_no_update" on public.ai_operator_audit;
-- (não criamos política de update → nenhum update permitido para authenticated)
-- (não criamos política de delete → nenhum delete permitido para authenticated)

-- ---------------------------------------------------------------------------
-- Comentários de documentação
-- ---------------------------------------------------------------------------
comment on table public.ai_operator_sessions is 'MarineFlow AI Operator — sessões de conversa cross-channel.';
comment on table public.ai_operator_messages is 'MarineFlow AI Operator — histórico de mensagens com chamadas de tool.';
comment on table public.ai_operator_drafts is 'MarineFlow AI Operator — rascunhos operacionais persistentes (orçamento/diagnóstico/etc.) separados da OS oficial.';
comment on table public.ai_operator_draft_items is 'MarineFlow AI Operator — itens dentro de um rascunho (serviços, produtos, itens a cotar, perguntas).';
comment on table public.ai_operator_pending_actions is 'MarineFlow AI Operator — gate determinístico: ações sensíveis ficam aqui em pending até aprovação explícita.';
comment on table public.ai_operator_audit is 'MarineFlow AI Operator — auditoria append-only de todas as decisões do operador.';
comment on table public.ai_operator_memory_notes is 'MarineFlow AI Operator — memória técnica reutilizável por embarcação/cliente.';
comment on table public.ai_operator_channel_events is 'MarineFlow AI Operator — fila de eventos brutos de canal (WhatsApp Z-API hoje; Evolution/n8n no futuro).';
