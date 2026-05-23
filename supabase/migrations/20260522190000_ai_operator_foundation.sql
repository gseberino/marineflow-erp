-- ============================================================================
-- MarineFlow AI Operator — Macro Cycle 1 foundation (v2: security hardened)
-- ============================================================================
-- Esta migration é ADITIVA e NÃO destrutiva. Cria a fundação persistente do
-- MarineFlow AI Operator com policies RLS granulares por papel.
--
-- Mudanças em relação ao primeiro draft (que NÃO foi aplicado em staging):
--   * Auditoria (`ai_operator_audit`) realmente append-only para qualquer
--     papel autenticado — apenas SELECT condicionado a admin/financial; sem
--     INSERT/UPDATE/DELETE por clientes (gravação só via service_role).
--   * Pending actions imutáveis pelo cliente — leitura limitada ao dono
--     da sessão ou admin; sem INSERT/UPDATE/DELETE por clientes.
--   * Sessions / messages / drafts / draft_items: SELECT/UPDATE só pelo
--     dono da sessão (`owner_user_id = auth.uid()`) ou admin. INSERT cliente
--     bloqueado — gravação só via service_role (o backend valida ownership).
--   * Memory notes: novo campo `verification_status` ('candidate', 'verified',
--     'rejected'). Tudo que vem da IA nasce 'candidate'. Promoção a 'verified'
--     só por admin/technician. Consultas operacionais devem filtrar.
--   * Channel events: visíveis só para admin; ingestão pelo service_role.
--   * Helpers SECURITY DEFINER para papel/ownership, com search_path fixo.
--   * WhatsApp bridge: NÃO acompanha esta migration; o arquivo da bridge fica
--     em `supabase/deferred-migrations/` (não aplicada automaticamente).
--
-- Rollback (manual, somente staging):
--   DROP TABLE em ordem reversa de FK. Sem efeito colateral sobre dados.
-- ============================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Helpers (SECURITY DEFINER, search_path fixo)
-- ---------------------------------------------------------------------------
create or replace function public.ai_op_is_admin(_user_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.app_users
    where id = _user_id and role = 'admin' and active = true
  );
$$;

create or replace function public.ai_op_is_active(_user_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.app_users
    where id = _user_id and active = true
  );
$$;

-- Helper local: admin OU financial. Implementado para evitar dependência
-- implícita da `public.is_admin_or_financial` (que vive fora do módulo).
create or replace function public.ai_op_is_admin_or_financial(_user_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.app_users
    where id = _user_id and role in ('admin','financial') and active = true
  );
$$;

create or replace function public.ai_op_is_internal(_user_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.app_users
    where id = _user_id and active = true
      and role in ('admin', 'technician', 'financial', 'seller', 'other')
  );
$$;

-- ----------------------------------------------------------------------------
-- Matriz de aprovação — Macro Ciclo 1 RESTRITIVA.
-- Decisão arquitetural: nesta primeira ativação NENHUMA delegação por papel é
-- permitida. Apenas `admin` ativo aprova qualquer pending action. A regra
-- ampliada para seller/financial/technician depende de termos um executor
-- real para cada classe de ação e atribuição formal — fica para macro ciclo
-- posterior. Memória técnica é exceção: como é uma validação técnica de
-- conteúdo, admin OU technician podem verify/reject (operação afeta apenas
-- a flag interna `verification_status`).
-- ----------------------------------------------------------------------------
create or replace function public.ai_op_can_approve(_user_id uuid, _action text)
returns boolean
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_role text;
  v_active boolean;
begin
  select role, active into v_role, v_active
  from public.app_users where id = _user_id;
  if v_role is null or v_active is not true then return false; end if;

  -- Governança de memória técnica: admin OU technician.
  if _action in ('verify_memory_note', 'reject_memory_note') then
    return v_role in ('admin', 'technician');
  end if;

  -- Macro Ciclo 1 — qualquer outra ação pendente: somente admin.
  return v_role = 'admin';
end;
$$;

comment on function public.ai_op_can_approve is
  'MarineFlow AI Operator — Macro Ciclo 1 restritivo: somente admin aprova ações operacionais; admin/technician validam memória técnica.';

-- ----------------------------------------------------------------------------
-- Helper para REJEIÇÃO: o próprio solicitante pode rejeitar a sua ação,
-- ou um admin ativo pode rejeitar qualquer uma. Roles intermediários não
-- têm autoridade de rejeição cruzada nesta fase.
-- ----------------------------------------------------------------------------
create or replace function public.ai_op_can_reject(_user_id uuid, _pending_action_id uuid)
returns boolean
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_role text;
  v_active boolean;
  v_requested_by uuid;
  v_action text;
begin
  select role, active into v_role, v_active
  from public.app_users where id = _user_id;
  if v_role is null or v_active is not true then return false; end if;

  select requested_by_user_id, action_name into v_requested_by, v_action
  from public.ai_operator_pending_actions where id = _pending_action_id;
  if v_requested_by is null then return false; end if;

  -- external_seller nunca participa de governança de pending actions do operator.
  if v_role = 'external_seller' then return false; end if;

  -- Memória técnica: aplica a mesma matriz de approve (admin/technician).
  if v_action in ('verify_memory_note', 'reject_memory_note') then
    return v_role in ('admin', 'technician');
  end if;

  -- Demais ações: admin OU o próprio solicitante.
  return v_role = 'admin' or v_requested_by = _user_id;
end;
$$;

comment on function public.ai_op_can_reject is
  'MarineFlow AI Operator — Macro Ciclo 1: rejeição permitida ao solicitante da ação ou a um admin ativo.';

-- ---------------------------------------------------------------------------
-- 1. Sessões de conversa
-- ---------------------------------------------------------------------------
create table if not exists public.ai_operator_sessions (
  id uuid primary key default gen_random_uuid(),
  channel text not null check (channel in ('web', 'whatsapp', 'system')),
  channel_provider text,
  owner_user_id uuid references public.app_users(id) on delete set null,
  client_id uuid references public.clients(id) on delete set null,
  vessel_id uuid references public.vessels(id) on delete set null,
  service_order_id uuid references public.service_orders(id) on delete set null,
  external_thread_key text,
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
-- 2. Mensagens
-- ---------------------------------------------------------------------------
create table if not exists public.ai_operator_messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.ai_operator_sessions(id) on delete cascade,
  role text not null check (role in ('user', 'assistant', 'tool', 'system')),
  content text,
  tool_calls jsonb,
  tool_call_id text,
  tool_name text,
  attachments jsonb,
  source text default 'web' check (source in ('web', 'whatsapp', 'system', 'api')),
  source_message_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists idx_ai_op_messages_session on public.ai_operator_messages(session_id, created_at);
create index if not exists idx_ai_op_messages_source on public.ai_operator_messages(source_message_id) where source_message_id is not null;

-- ---------------------------------------------------------------------------
-- 3. Rascunhos
-- ---------------------------------------------------------------------------
create table if not exists public.ai_operator_drafts (
  id uuid primary key default gen_random_uuid(),
  session_id uuid references public.ai_operator_sessions(id) on delete set null,
  created_by uuid references public.app_users(id) on delete set null,
  kind text not null check (kind in (
    'quote', 'diagnosis', 'service_plan', 'agenda_proposal', 'response_suggestion', 'note'
  )),
  status text not null default 'draft' check (status in (
    'draft', 'awaiting_info', 'awaiting_approval', 'approved', 'rejected', 'converted'
  )),
  title text,
  summary text,
  client_id uuid references public.clients(id) on delete set null,
  vessel_id uuid references public.vessels(id) on delete set null,
  service_order_id uuid references public.service_orders(id) on delete set null,
  converted_service_order_id uuid references public.service_orders(id) on delete set null,
  interpreted_intent text,
  interpreted_category text,
  estimated_labor_hours numeric,
  estimated_labor_value numeric,
  estimated_parts_value numeric,
  estimated_travel_value numeric,
  estimated_total numeric,
  pending_questions jsonb not null default '[]'::jsonb,
  next_steps jsonb not null default '[]'::jsonb,
  hypotheses jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_ai_op_drafts_session on public.ai_operator_drafts(session_id);
create index if not exists idx_ai_op_drafts_client on public.ai_operator_drafts(client_id);
create index if not exists idx_ai_op_drafts_vessel on public.ai_operator_drafts(vessel_id);
create index if not exists idx_ai_op_drafts_status on public.ai_operator_drafts(status, kind);

-- ---------------------------------------------------------------------------
-- 4. Itens
-- ---------------------------------------------------------------------------
create table if not exists public.ai_operator_draft_items (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null references public.ai_operator_drafts(id) on delete cascade,
  item_kind text not null check (item_kind in (
    'service', 'product', 'product_to_quote', 'displacement', 'engineering',
    'pending_question', 'risk', 'reference'
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
  source_reference text,
  metadata jsonb not null default '{}'::jsonb,
  position int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_ai_op_draft_items_draft on public.ai_operator_draft_items(draft_id, position);

-- ---------------------------------------------------------------------------
-- 5. Pending actions (gate)
-- ---------------------------------------------------------------------------
create table if not exists public.ai_operator_pending_actions (
  id uuid primary key default gen_random_uuid(),
  session_id uuid references public.ai_operator_sessions(id) on delete set null,
  draft_id uuid references public.ai_operator_drafts(id) on delete set null,
  requested_by_user_id uuid references public.app_users(id) on delete set null,
  approved_by_user_id uuid references public.app_users(id) on delete set null,
  rejected_by_user_id uuid references public.app_users(id) on delete set null,
  action_name text not null,
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
  rejected_at timestamptz,
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
  event_type text not null,
  event_category text not null default 'info' check (event_category in ('info', 'security', 'data', 'channel', 'error')),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_ai_op_audit_session on public.ai_operator_audit(session_id, created_at);
create index if not exists idx_ai_op_audit_event on public.ai_operator_audit(event_type, created_at);

-- ---------------------------------------------------------------------------
-- 7. Memória técnica reutilizável (com governança)
-- ---------------------------------------------------------------------------
create table if not exists public.ai_operator_memory_notes (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.clients(id) on delete cascade,
  vessel_id uuid references public.vessels(id) on delete cascade,
  scope text not null default 'vessel' check (scope in ('vessel', 'client', 'global')),
  topic text not null,
  title text not null,
  body text not null,
  confidence text not null default 'medium' check (confidence in ('low', 'medium', 'high')),
  source text not null default 'ai' check (source in ('ai', 'human', 'imported')),
  source_reference text,
  -- Governança: nota nasce 'candidate'. Só admin/technician promovem a 'verified'.
  verification_status text not null default 'candidate'
    check (verification_status in ('candidate', 'verified', 'rejected')),
  verified_by uuid references public.app_users(id) on delete set null,
  verified_at timestamptz,
  rejected_by uuid references public.app_users(id) on delete set null,
  rejected_at timestamptz,
  created_by uuid references public.app_users(id) on delete set null,
  draft_id uuid references public.ai_operator_drafts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_ai_op_memory_vessel on public.ai_operator_memory_notes(vessel_id) where vessel_id is not null;
create index if not exists idx_ai_op_memory_client on public.ai_operator_memory_notes(client_id) where client_id is not null;
create index if not exists idx_ai_op_memory_topic on public.ai_operator_memory_notes(topic);
create index if not exists idx_ai_op_memory_verified on public.ai_operator_memory_notes(verification_status);

-- ---------------------------------------------------------------------------
-- 8. Eventos de canal
-- ---------------------------------------------------------------------------
create table if not exists public.ai_operator_channel_events (
  id uuid primary key default gen_random_uuid(),
  channel text not null check (channel in ('whatsapp', 'web', 'system')),
  provider text not null check (provider in ('zapi', 'evolution', 'n8n', 'web', 'system')),
  external_event_id text,
  external_thread_key text,
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
-- updated_at triggers
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
-- Trigger: protege pending_actions de adulteração no servidor
-- ---------------------------------------------------------------------------
-- Independente das policies de RLS, este trigger impede que campos imutáveis
-- sejam alterados após a criação E só permite transições de status válidas.
-- O trigger roda em qualquer UPDATE — INCLUSIVE quando feito por service_role.
-- Não existe mecanismo de bypass. Se uma evolução futura precisar mover algum
-- campo do conjunto imutável, esta migration deve ser substituída por outra
-- aditiva que altere conscientemente a função.
create or replace function public.ai_op_protect_pending_action()
returns trigger
language plpgsql
as $$
begin
  -- Bloqueia UPDATE em campos imutáveis após criação.
  if TG_OP = 'UPDATE' then
    if NEW.action_name is distinct from OLD.action_name
       or NEW.risk_level is distinct from OLD.risk_level
       or NEW.payload is distinct from OLD.payload
       or NEW.requested_by_user_id is distinct from OLD.requested_by_user_id
       or NEW.session_id is distinct from OLD.session_id
       or NEW.draft_id is distinct from OLD.draft_id
       or NEW.created_at is distinct from OLD.created_at then
      raise exception 'ai_operator_pending_actions: campos imutáveis não podem ser alterados (action_name, risk_level, payload, requested_by, session_id, draft_id, created_at)';
    end if;

    -- Transições válidas:
    --   pending -> approved | rejected | expired
    --   approved -> executed | failed
    if OLD.status = 'pending' and NEW.status not in ('pending', 'approved', 'rejected', 'expired') then
      raise exception 'ai_operator_pending_actions: transição inválida % -> %', OLD.status, NEW.status;
    end if;
    if OLD.status = 'approved' and NEW.status not in ('approved', 'executed', 'failed') then
      raise exception 'ai_operator_pending_actions: transição inválida % -> %', OLD.status, NEW.status;
    end if;
    if OLD.status in ('rejected', 'executed', 'failed', 'expired')
       and NEW.status is distinct from OLD.status then
      raise exception 'ai_operator_pending_actions: estado terminal não pode mudar (% -> %)', OLD.status, NEW.status;
    end if;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_ai_op_pending_guard on public.ai_operator_pending_actions;
create trigger trg_ai_op_pending_guard
  before update on public.ai_operator_pending_actions
  for each row execute function public.ai_op_protect_pending_action();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.ai_operator_sessions enable row level security;
alter table public.ai_operator_messages enable row level security;
alter table public.ai_operator_drafts enable row level security;
alter table public.ai_operator_draft_items enable row level security;
alter table public.ai_operator_pending_actions enable row level security;
alter table public.ai_operator_audit enable row level security;
alter table public.ai_operator_memory_notes enable row level security;
alter table public.ai_operator_channel_events enable row level security;

-- Limpa policies herdadas do draft inicial (caso já estejam aplicadas em ambiente de dev)
do $$
declare
  t text;
  p text;
  tables text[] := array[
    'ai_operator_sessions','ai_operator_messages','ai_operator_drafts',
    'ai_operator_draft_items','ai_operator_pending_actions','ai_operator_audit',
    'ai_operator_memory_notes','ai_operator_channel_events'
  ];
  ops text[] := array['select','insert','update'];
begin
  foreach t in array tables loop
    foreach p in array ops loop
      execute format('drop policy if exists "ai_op_%s_%s" on public.%I;', t, p, t);
    end loop;
  end loop;
end $$;

-- ATENÇÃO: TODAS as policies SELECT começam exigindo `ai_op_is_active(auth.uid())`.
-- Isso fecha o caminho "owner_user_id = auth.uid()" / "created_by = auth.uid()"
-- / "requested_by_user_id = auth.uid()" quando o usuário foi desativado mas
-- ainda possui JWT válido. Helpers `ai_op_is_admin` e `ai_op_is_internal` já
-- exigem active=true; ainda assim a checagem topo-de-policy é mantida como
-- defesa em profundidade e para uniformizar a leitura das regras.

-- ----- SESSIONS: dono ativo OU admin ativo -----
create policy "ai_op_sessions_select"
  on public.ai_operator_sessions for select to authenticated
  using (
    public.ai_op_is_active(auth.uid())
    and (owner_user_id = auth.uid() or public.ai_op_is_admin(auth.uid()))
  );
-- INSERT/UPDATE só via service_role (backend). Não criamos policy de INSERT/UPDATE
-- para 'authenticated' — o backend valida ownership e usa SUPABASE_SERVICE_ROLE_KEY.

-- ----- MESSAGES: visível só se a sessão é do user ativo (ou admin ativo) -----
create policy "ai_op_messages_select"
  on public.ai_operator_messages for select to authenticated
  using (
    public.ai_op_is_active(auth.uid())
    and exists (
      select 1 from public.ai_operator_sessions s
      where s.id = ai_operator_messages.session_id
        and (s.owner_user_id = auth.uid() or public.ai_op_is_admin(auth.uid()))
    )
  );

-- ----- DRAFTS: visível só se sessão do user ativo, ou admin ativo, ou created_by = user ativo -----
create policy "ai_op_drafts_select"
  on public.ai_operator_drafts for select to authenticated
  using (
    public.ai_op_is_active(auth.uid())
    and (
      created_by = auth.uid()
      or public.ai_op_is_admin(auth.uid())
      or exists (
        select 1 from public.ai_operator_sessions s
        where s.id = ai_operator_drafts.session_id
          and s.owner_user_id = auth.uid()
      )
    )
  );

create policy "ai_op_draft_items_select"
  on public.ai_operator_draft_items for select to authenticated
  using (
    public.ai_op_is_active(auth.uid())
    and exists (
      select 1 from public.ai_operator_drafts d
      where d.id = ai_operator_draft_items.draft_id
        and (
          d.created_by = auth.uid()
          or public.ai_op_is_admin(auth.uid())
          or exists (
            select 1 from public.ai_operator_sessions s
            where s.id = d.session_id and s.owner_user_id = auth.uid()
          )
        )
    )
  );

-- ----- PENDING ACTIONS: leitura por solicitante ativo, dono ativo da sessão ou admin ativo -----
create policy "ai_op_pending_select"
  on public.ai_operator_pending_actions for select to authenticated
  using (
    public.ai_op_is_active(auth.uid())
    and (
      requested_by_user_id = auth.uid()
      or public.ai_op_is_admin(auth.uid())
      or exists (
        select 1 from public.ai_operator_sessions s
        where s.id = ai_operator_pending_actions.session_id
          and s.owner_user_id = auth.uid()
      )
    )
  );
-- INSERT/UPDATE: somente service_role.

-- ----- AUDIT: leitura só admin OU financial ativos (registro forense) -----
create policy "ai_op_audit_select"
  on public.ai_operator_audit for select to authenticated
  using (public.ai_op_is_admin_or_financial(auth.uid()));
-- INSERT/UPDATE/DELETE: nunca por authenticated. Apenas service_role.

-- ----- MEMORY NOTES: leitura granular por verification_status × papel × atividade -----
-- Decisão Macro Ciclo 1:
--   * verified  → visível a qualquer usuário INTERNO ativo (admin/technician/
--                 financial/seller/other). External_seller NÃO recebe.
--   * candidate → visível a admin/technician ativos OU ao criador ativo.
--   * rejected  → mesma visibilidade restrita do candidate (trilha forense).
create policy "ai_op_memory_select"
  on public.ai_operator_memory_notes for select to authenticated
  using (
    public.ai_op_is_active(auth.uid())
    and (
      (
        verification_status = 'verified'
        and public.ai_op_is_internal(auth.uid())
      )
      or (
        verification_status in ('candidate', 'rejected')
        and (
          public.ai_op_is_admin(auth.uid())
          or exists (
            select 1 from public.app_users au
            where au.id = auth.uid() and au.active = true and au.role = 'technician'
          )
          or created_by = auth.uid()
        )
      )
    )
  );
-- INSERT/UPDATE: somente service_role.

-- ----- CHANNEL EVENTS: leitura admin ativo (forense). Ingestão via service_role. -----
create policy "ai_op_channel_events_select"
  on public.ai_operator_channel_events for select to authenticated
  using (public.ai_op_is_admin(auth.uid()));

-- ---------------------------------------------------------------------------
-- Comentários
-- ---------------------------------------------------------------------------
comment on table public.ai_operator_sessions is 'MarineFlow AI Operator — sessões cross-channel. RLS: dono ou admin.';
comment on table public.ai_operator_messages is 'MarineFlow AI Operator — mensagens. RLS via sessão.';
comment on table public.ai_operator_drafts is 'MarineFlow AI Operator — rascunhos operacionais separados de OS oficial.';
comment on table public.ai_operator_draft_items is 'MarineFlow AI Operator — itens de rascunho.';
comment on table public.ai_operator_pending_actions is 'MarineFlow AI Operator — ações sensíveis em pending até aprovação por papel autorizado. Trigger guarda imutabilidade.';
comment on table public.ai_operator_audit is 'MarineFlow AI Operator — auditoria append-only. Sem INSERT/UPDATE/DELETE por authenticated.';
comment on table public.ai_operator_memory_notes is 'MarineFlow AI Operator — memória técnica com governança candidate/verified/rejected.';
comment on table public.ai_operator_channel_events is 'MarineFlow AI Operator — fila de eventos brutos de canal. Provider-agnóstica.';
