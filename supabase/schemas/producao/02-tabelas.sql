-- 02 · Tabelas: colunas, PK/UNIQUE/CHECK, RLS e comentários (FKs no arquivo 03)
-- Gerado por scripts/snapshot-producao.mjs a partir dos catálogos do banco de produção.
-- NÃO editar à mão: regenerar. A data e as contagens ficam no README.md ao lado.

-- ── agenda_detector_exclusions ──
CREATE TABLE public.agenda_detector_exclusions (
  phone_normalized text NOT NULL,
  label text,
  reason text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT agenda_detector_exclusions_pkey PRIMARY KEY (phone_normalized)
);
ALTER TABLE public.agenda_detector_exclusions ENABLE ROW LEVEL SECURITY;

-- ── agenda_suggestions ──
CREATE TABLE public.agenda_suggestions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  title text NOT NULL,
  kind text DEFAULT 'task'::text NOT NULL,
  suggested_due_at timestamp with time zone,
  suggested_start_at timestamp with time zone,
  priority text DEFAULT 'normal'::text NOT NULL,
  evidence text NOT NULL,
  evidence_at timestamp with time zone,
  confidence numeric NOT NULL,
  detector text NOT NULL,
  origin text DEFAULT 'whatsapp'::text NOT NULL,
  source_message_id uuid,
  source_phone text,
  contact_label text,
  related_entity_type text,
  related_entity_id uuid,
  client_id uuid,
  target_user_id uuid,
  status text DEFAULT 'pending'::text NOT NULL,
  resolved_at timestamp with time zone,
  resolved_by uuid,
  created_task_id uuid,
  dismiss_reason text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  open_loop_id uuid,
  CONSTRAINT agenda_suggestions_confidence_check CHECK (confidence >= 0::numeric AND confidence <= 1::numeric),
  CONSTRAINT agenda_suggestions_detector_check CHECK (detector = ANY (ARRAY['promise'::text, 'client_request'::text, 'third_party_deadline'::text, 'followup'::text, 'voice_note'::text])),
  CONSTRAINT agenda_suggestions_kind_check CHECK (kind = ANY (ARRAY['task'::text, 'appointment'::text])),
  CONSTRAINT agenda_suggestions_origin_check CHECK (origin = ANY (ARRAY['whatsapp'::text, 'voice_app'::text, 'manual_text'::text])),
  CONSTRAINT agenda_suggestions_priority_check CHECK (priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text])),
  CONSTRAINT agenda_suggestions_related_entity_type_check CHECK (related_entity_type IS NULL OR (related_entity_type = ANY (ARRAY['service_order'::text, 'quote'::text, 'external_quote'::text, 'client'::text, 'vessel'::text, 'receivable'::text, 'payable'::text, 'purchase_order'::text, 'collection'::text, 'stock_item'::text, 'quote_request'::text]))),
  CONSTRAINT agenda_suggestions_status_check CHECK (status = ANY (ARRAY['pending'::text, 'accepted'::text, 'dismissed'::text, 'expired'::text])),
  CONSTRAINT agenda_suggestions_pkey PRIMARY KEY (id)
);
ALTER TABLE public.agenda_suggestions ENABLE ROW LEVEL SECURITY;

-- ── agenda_tasks ──
CREATE TABLE public.agenda_tasks (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  title text NOT NULL,
  description text,
  assignee_user_id uuid,
  scheduled_start_at timestamp with time zone,
  scheduled_end_at timestamp with time zone,
  priority text DEFAULT 'normal'::text NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  location text,
  client_id uuid,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  kind text DEFAULT 'task'::text NOT NULL,
  due_at timestamp with time zone,
  all_day boolean DEFAULT false NOT NULL,
  source text DEFAULT 'manual'::text NOT NULL,
  related_entity_type text,
  related_entity_id uuid,
  automation_key text,
  checklist jsonb DEFAULT '[]'::jsonb NOT NULL,
  is_private boolean DEFAULT false NOT NULL,
  completed_at timestamp with time zone,
  completed_by uuid,
  snoozed_until timestamp with time zone,
  rrule text,
  recurrence_parent_id uuid,
  origin_session_id uuid,
  CONSTRAINT agenda_tasks_kind_check CHECK (kind = ANY (ARRAY['task'::text, 'appointment'::text])),
  CONSTRAINT agenda_tasks_related_entity_type_check CHECK (related_entity_type IS NULL OR (related_entity_type = ANY (ARRAY['service_order'::text, 'quote'::text, 'external_quote'::text, 'client'::text, 'vessel'::text, 'receivable'::text, 'payable'::text, 'purchase_order'::text, 'collection'::text, 'stock_item'::text, 'quote_request'::text]))),
  CONSTRAINT agenda_tasks_source_check CHECK (source = ANY (ARRAY['manual'::text, 'ai'::text, 'automation'::text, 'recurrence'::text])),
  CONSTRAINT appointment_needs_start CHECK (kind <> 'appointment'::text OR scheduled_start_at IS NOT NULL),
  CONSTRAINT agenda_tasks_pkey PRIMARY KEY (id),
  CONSTRAINT no_overlapping_appointments EXCLUDE USING gist (assignee_user_id WITH =, tstzrange(scheduled_start_at, scheduled_end_at) WITH &&) WHERE (kind = 'appointment'::text AND (status <> ALL (ARRAY['cancelled'::text, 'done'::text])) AND assignee_user_id IS NOT NULL AND scheduled_start_at IS NOT NULL AND scheduled_end_at IS NOT NULL)
);
ALTER TABLE public.agenda_tasks ENABLE ROW LEVEL SECURITY;

-- ── ai_agent_memory ──
CREATE TABLE public.ai_agent_memory (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  scope text NOT NULL,
  entity_id uuid,
  entity_name text,
  memory_key text NOT NULL,
  memory_value text NOT NULL,
  confidence text DEFAULT 'high'::text NOT NULL,
  source text,
  created_by_user_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ai_agent_memory_confidence_check CHECK (confidence = ANY (ARRAY['high'::text, 'medium'::text, 'low'::text])),
  CONSTRAINT ai_agent_memory_scope_check CHECK (scope = ANY (ARRAY['global'::text, 'client'::text, 'vessel'::text, 'service_order'::text, 'operator'::text])),
  CONSTRAINT ai_agent_memory_pkey PRIMARY KEY (id)
);
ALTER TABLE public.ai_agent_memory ENABLE ROW LEVEL SECURITY;

-- ── ai_agent_tasks ──
CREATE TABLE public.ai_agent_tasks (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  task_type text DEFAULT 'follow_up'::text NOT NULL,
  title text NOT NULL,
  description text NOT NULL,
  due_at timestamp with time zone NOT NULL,
  entity_type text,
  entity_id uuid,
  entity_number text,
  status text DEFAULT 'pending'::text NOT NULL,
  priority text DEFAULT 'normal'::text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_by_agent boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ai_agent_tasks_priority_check CHECK (priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text])),
  CONSTRAINT ai_agent_tasks_status_check CHECK (status = ANY (ARRAY['pending'::text, 'done'::text, 'cancelled'::text, 'snoozed'::text])),
  CONSTRAINT ai_agent_tasks_pkey PRIMARY KEY (id)
);
ALTER TABLE public.ai_agent_tasks ENABLE ROW LEVEL SECURITY;

-- ── ai_business_alerts ──
CREATE TABLE public.ai_business_alerts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  alert_type text NOT NULL,
  severity text DEFAULT 'warning'::text NOT NULL,
  title text NOT NULL,
  description text NOT NULL,
  entity_type text,
  entity_id uuid,
  entity_number text,
  resolved_at timestamp with time zone,
  first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  CONSTRAINT ai_business_alerts_severity_check CHECK (severity = ANY (ARRAY['critical'::text, 'warning'::text, 'info'::text])),
  CONSTRAINT ai_business_alerts_pkey PRIMARY KEY (id),
  CONSTRAINT ai_business_alerts_alert_type_entity_id_key UNIQUE (alert_type, entity_id)
);
ALTER TABLE public.ai_business_alerts ENABLE ROW LEVEL SECURITY;

-- ── ai_comms_log ──
CREATE TABLE public.ai_comms_log (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  tipo text NOT NULL,
  audiencia text,
  entity_kind text,
  entity_id uuid,
  phone text,
  message_preview text,
  status text DEFAULT 'sent'::text NOT NULL,
  block_code text,
  responded_at timestamp with time zone,
  reply_intent text,
  CONSTRAINT ai_comms_log_pkey PRIMARY KEY (id)
);
ALTER TABLE public.ai_comms_log ENABLE ROW LEVEL SECURITY;

-- ── ai_correction_patterns ──
CREATE TABLE public.ai_correction_patterns (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  correction_type text NOT NULL,
  context text NOT NULL,
  original_value text,
  corrected_value text,
  lesson_learned text NOT NULL,
  entity_type text,
  entity_id uuid,
  entity_number text,
  client_id uuid,
  operator_user_id uuid,
  scope text DEFAULT 'global'::text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ai_correction_patterns_scope_check CHECK (scope = ANY (ARRAY['global'::text, 'client'::text, 'operator'::text])),
  CONSTRAINT ai_correction_patterns_pkey PRIMARY KEY (id)
);
ALTER TABLE public.ai_correction_patterns ENABLE ROW LEVEL SECURITY;

-- ── ai_daily_briefings ──
CREATE TABLE public.ai_daily_briefings (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  date date NOT NULL,
  summary_text text NOT NULL,
  critical_count integer DEFAULT 0 NOT NULL,
  warning_count integer DEFAULT 0 NOT NULL,
  tasks_due_count integer DEFAULT 0 NOT NULL,
  agenda_count integer DEFAULT 0 NOT NULL,
  sections jsonb DEFAULT '{}'::jsonb NOT NULL,
  generated_at timestamp with time zone DEFAULT now() NOT NULL,
  whatsapp_sent boolean DEFAULT false NOT NULL,
  whatsapp_sent_at timestamp with time zone,
  CONSTRAINT ai_daily_briefings_pkey PRIMARY KEY (id),
  CONSTRAINT ai_daily_briefings_date_key UNIQUE (date)
);
ALTER TABLE public.ai_daily_briefings ENABLE ROW LEVEL SECURITY;

-- ── ai_inbound_sessions ──
CREATE TABLE public.ai_inbound_sessions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  phone text NOT NULL,
  client_id uuid,
  messages jsonb DEFAULT '[]'::jsonb NOT NULL,
  last_intent text,
  session_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ai_inbound_sessions_pkey PRIMARY KEY (id),
  CONSTRAINT ai_inbound_sessions_phone_key UNIQUE (phone)
);
ALTER TABLE public.ai_inbound_sessions ENABLE ROW LEVEL SECURITY;

-- ── ai_learned_routines ──
CREATE TABLE public.ai_learned_routines (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  title text NOT NULL,
  pattern_key text NOT NULL,
  description text,
  category text DEFAULT 'rotina'::text NOT NULL,
  observations integer DEFAULT 1 NOT NULL,
  last_observed_at timestamp with time zone DEFAULT now() NOT NULL,
  evidence text,
  suggested_automation text,
  automation_payload jsonb,
  status text DEFAULT 'observed'::text NOT NULL,
  approved_at timestamp with time zone,
  approved_by uuid,
  rejected_reason text,
  user_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ai_learned_routines_category_check CHECK (category = ANY (ARRAY['rotina'::text, 'preferencia'::text, 'contexto'::text, 'atalho'::text])),
  CONSTRAINT ai_learned_routines_status_check CHECK (status = ANY (ARRAY['observed'::text, 'proposed'::text, 'approved'::text, 'rejected'::text, 'automated'::text])),
  CONSTRAINT ai_learned_routines_pkey PRIMARY KEY (id)
);
ALTER TABLE public.ai_learned_routines ENABLE ROW LEVEL SECURITY;

-- ── ai_lifecycle_events ──
CREATE TABLE public.ai_lifecycle_events (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  entity_type text DEFAULT 'service_order'::text NOT NULL,
  entity_id uuid NOT NULL,
  entity_number text,
  event_type text NOT NULL,
  old_value text,
  new_value text,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ai_lifecycle_events_pkey PRIMARY KEY (id)
);
ALTER TABLE public.ai_lifecycle_events ENABLE ROW LEVEL SECURITY;

-- ── ai_message_feedback ──
CREATE TABLE public.ai_message_feedback (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  rating text NOT NULL,
  message_excerpt text,
  session_id uuid,
  created_by uuid,
  CONSTRAINT ai_message_feedback_rating_check CHECK (rating = ANY (ARRAY['up'::text, 'down'::text])),
  CONSTRAINT ai_message_feedback_pkey PRIMARY KEY (id)
);
ALTER TABLE public.ai_message_feedback ENABLE ROW LEVEL SECURITY;

-- ── ai_operator_alerts_log ──
CREATE TABLE public.ai_operator_alerts_log (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  alert_key text NOT NULL,
  channel text DEFAULT 'whatsapp'::text NOT NULL,
  meta jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ai_operator_alerts_log_pkey PRIMARY KEY (id)
);
ALTER TABLE public.ai_operator_alerts_log ENABLE ROW LEVEL SECURITY;

-- ── ai_operator_audit ──
CREATE TABLE public.ai_operator_audit (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  session_id uuid,
  draft_id uuid,
  pending_action_id uuid,
  actor_user_id uuid,
  actor_kind text NOT NULL,
  event_type text NOT NULL,
  event_category text DEFAULT 'info'::text NOT NULL,
  payload jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ai_operator_audit_actor_kind_check CHECK (actor_kind = ANY (ARRAY['user'::text, 'ai_model'::text, 'system'::text, 'channel'::text])),
  CONSTRAINT ai_operator_audit_event_category_check CHECK (event_category = ANY (ARRAY['info'::text, 'security'::text, 'data'::text, 'channel'::text, 'error'::text])),
  CONSTRAINT ai_operator_audit_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.ai_operator_audit IS 'MarineFlow AI Operator — auditoria append-only. Sem INSERT/UPDATE/DELETE por authenticated.';
ALTER TABLE public.ai_operator_audit ENABLE ROW LEVEL SECURITY;

-- ── ai_operator_channel_events ──
CREATE TABLE public.ai_operator_channel_events (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  channel text NOT NULL,
  provider text NOT NULL,
  external_event_id text,
  external_thread_key text,
  direction text DEFAULT 'inbound'::text NOT NULL,
  payload jsonb NOT NULL,
  status text DEFAULT 'queued'::text NOT NULL,
  processed_at timestamp with time zone,
  last_error text,
  attempts integer DEFAULT 0 NOT NULL,
  session_id uuid,
  draft_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ai_operator_channel_events_channel_check CHECK (channel = ANY (ARRAY['whatsapp'::text, 'web'::text, 'system'::text])),
  CONSTRAINT ai_operator_channel_events_direction_check CHECK (direction = ANY (ARRAY['inbound'::text, 'outbound'::text])),
  CONSTRAINT ai_operator_channel_events_provider_check CHECK (provider = ANY (ARRAY['zapi'::text, 'evolution'::text, 'n8n'::text, 'web'::text, 'system'::text])),
  CONSTRAINT ai_operator_channel_events_status_check CHECK (status = ANY (ARRAY['queued'::text, 'processing'::text, 'processed'::text, 'skipped'::text, 'failed'::text])),
  CONSTRAINT ai_operator_channel_events_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.ai_operator_channel_events IS 'MarineFlow AI Operator — fila de eventos brutos de canal. Provider-agnóstica.';
ALTER TABLE public.ai_operator_channel_events ENABLE ROW LEVEL SECURITY;

-- ── ai_operator_draft_items ──
CREATE TABLE public.ai_operator_draft_items (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  draft_id uuid NOT NULL,
  item_kind text NOT NULL,
  service_id uuid,
  product_id uuid,
  description text NOT NULL,
  notes text,
  quantity numeric DEFAULT 1,
  unit text DEFAULT 'unit'::text,
  unit_price numeric,
  estimated_total numeric,
  confidence text DEFAULT 'medium'::text,
  source_reference text,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  position integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ai_operator_draft_items_confidence_check CHECK (confidence = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text])),
  CONSTRAINT ai_operator_draft_items_item_kind_check CHECK (item_kind = ANY (ARRAY['service'::text, 'product'::text, 'product_to_quote'::text, 'displacement'::text, 'engineering'::text, 'pending_question'::text, 'risk'::text, 'reference'::text])),
  CONSTRAINT ai_operator_draft_items_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.ai_operator_draft_items IS 'MarineFlow AI Operator — itens de rascunho.';
ALTER TABLE public.ai_operator_draft_items ENABLE ROW LEVEL SECURITY;

-- ── ai_operator_drafts ──
CREATE TABLE public.ai_operator_drafts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  session_id uuid,
  created_by uuid,
  kind text NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  title text,
  summary text,
  client_id uuid,
  vessel_id uuid,
  service_order_id uuid,
  converted_service_order_id uuid,
  interpreted_intent text,
  interpreted_category text,
  estimated_labor_hours numeric,
  estimated_labor_value numeric,
  estimated_parts_value numeric,
  estimated_travel_value numeric,
  estimated_total numeric,
  pending_questions jsonb DEFAULT '[]'::jsonb NOT NULL,
  next_steps jsonb DEFAULT '[]'::jsonb NOT NULL,
  hypotheses jsonb DEFAULT '[]'::jsonb NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ai_operator_drafts_kind_check CHECK (kind = ANY (ARRAY['quote'::text, 'diagnosis'::text, 'service_plan'::text, 'agenda_proposal'::text, 'response_suggestion'::text, 'note'::text])),
  CONSTRAINT ai_operator_drafts_status_check CHECK (status = ANY (ARRAY['draft'::text, 'awaiting_info'::text, 'awaiting_approval'::text, 'approved'::text, 'rejected'::text, 'converted'::text, 'cancelled'::text])),
  CONSTRAINT ai_operator_drafts_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.ai_operator_drafts IS 'MarineFlow AI Operator — rascunhos operacionais separados de OS oficial.';
COMMENT ON COLUMN public.ai_operator_drafts.status IS 'MarineFlow AI Operator — estados: draft, awaiting_info, awaiting_approval, approved, rejected, converted, cancelled. cancelled: rascunho cancelado pelo usuario (preserva trilha; metadata.cancellation_reason opcional).';
ALTER TABLE public.ai_operator_drafts ENABLE ROW LEVEL SECURITY;

-- ── ai_operator_memory_notes ──
CREATE TABLE public.ai_operator_memory_notes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  client_id uuid,
  vessel_id uuid,
  scope text DEFAULT 'vessel'::text NOT NULL,
  topic text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  confidence text DEFAULT 'medium'::text NOT NULL,
  source text DEFAULT 'ai'::text NOT NULL,
  source_reference text,
  verification_status text DEFAULT 'candidate'::text NOT NULL,
  verified_by uuid,
  verified_at timestamp with time zone,
  rejected_by uuid,
  rejected_at timestamp with time zone,
  created_by uuid,
  draft_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  supplier_id uuid,
  CONSTRAINT ai_operator_memory_notes_confidence_check CHECK (confidence = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text])),
  CONSTRAINT ai_operator_memory_notes_scope_check CHECK (scope = ANY (ARRAY['vessel'::text, 'client'::text, 'global'::text, 'supplier'::text])),
  CONSTRAINT ai_operator_memory_notes_source_check CHECK (source = ANY (ARRAY['ai'::text, 'human'::text, 'imported'::text])),
  CONSTRAINT ai_operator_memory_notes_verification_status_check CHECK (verification_status = ANY (ARRAY['candidate'::text, 'verified'::text, 'rejected'::text])),
  CONSTRAINT ai_operator_memory_notes_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.ai_operator_memory_notes IS 'MarineFlow AI Operator — memória técnica com governança candidate/verified/rejected.';
COMMENT ON COLUMN public.ai_operator_memory_notes.supplier_id IS 'Fornecedor a que esta nota se refere (scope = supplier). Espelha client_id/vessel_id.';
ALTER TABLE public.ai_operator_memory_notes ENABLE ROW LEVEL SECURITY;

-- ── ai_operator_messages ──
CREATE TABLE public.ai_operator_messages (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  session_id uuid NOT NULL,
  role text NOT NULL,
  content text,
  tool_calls jsonb,
  tool_call_id text,
  tool_name text,
  attachments jsonb,
  source text DEFAULT 'web'::text,
  source_message_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  tokens_in integer,
  tokens_out integer,
  cache_read_tokens integer,
  model text,
  cache_creation_tokens integer,
  openrouter_generation_id text,
  usd_real numeric(12,8),
  usd_cache_discount numeric(12,8),
  custo_reconciliado_em timestamp with time zone,
  reconcile_tentativas smallint DEFAULT 0 NOT NULL,
  CONSTRAINT ai_operator_messages_role_check CHECK (role = ANY (ARRAY['user'::text, 'assistant'::text, 'tool'::text, 'system'::text])),
  CONSTRAINT ai_operator_messages_source_check CHECK (source = ANY (ARRAY['web'::text, 'whatsapp'::text, 'system'::text, 'api'::text])),
  CONSTRAINT ai_operator_messages_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.ai_operator_messages IS 'MarineFlow AI Operator — mensagens. RLS via sessão.';
COMMENT ON COLUMN public.ai_operator_messages.cache_creation_tokens IS 'Tokens gravados no cache de prompt nesta chamada. Custa 1,25x a entrada base (TTL 5min) ou 2x (TTL 1h). Nulo em linhas anteriores a 08/08/2026.';
COMMENT ON COLUMN public.ai_operator_messages.openrouter_generation_id IS 'id da geracao no OpenRouter; chave para consultar o custo real em /api/v1/generation.';
COMMENT ON COLUMN public.ai_operator_messages.usd_real IS 'Custo efetivamente cobrado pelo OpenRouter nesta chamada (total_cost). Nulo enquanto nao reconciliado.';
COMMENT ON COLUMN public.ai_operator_messages.usd_cache_discount IS 'Quanto o cache de prompt economizou nesta chamada, segundo o OpenRouter (cache_discount).';
COMMENT ON COLUMN public.ai_operator_messages.reconcile_tentativas IS 'Quantas vezes ai-cost-reconcile tentou esta linha. Apos 5 tentativas a linha e abandonada.';
ALTER TABLE public.ai_operator_messages ENABLE ROW LEVEL SECURITY;

-- ── ai_operator_pending_actions ──
CREATE TABLE public.ai_operator_pending_actions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  session_id uuid,
  draft_id uuid,
  requested_by_user_id uuid,
  approved_by_user_id uuid,
  rejected_by_user_id uuid,
  action_name text NOT NULL,
  risk_level text DEFAULT 'medium'::text NOT NULL,
  risk_reason text,
  title text,
  summary text,
  payload jsonb NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  result jsonb,
  expires_at timestamp with time zone,
  approved_at timestamp with time zone,
  rejected_at timestamp with time zone,
  executed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ai_operator_pending_actions_risk_level_check CHECK (risk_level = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])),
  CONSTRAINT ai_operator_pending_actions_status_check CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'executed'::text, 'failed'::text, 'expired'::text])),
  CONSTRAINT ai_operator_pending_actions_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.ai_operator_pending_actions IS 'MarineFlow AI Operator — ações sensíveis em pending até aprovação por papel autorizado. Trigger guarda imutabilidade.';
ALTER TABLE public.ai_operator_pending_actions ENABLE ROW LEVEL SECURITY;

-- ── ai_operator_sessions ──
CREATE TABLE public.ai_operator_sessions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  channel text NOT NULL,
  channel_provider text,
  owner_user_id uuid,
  client_id uuid,
  vessel_id uuid,
  service_order_id uuid,
  external_thread_key text,
  status text DEFAULT 'open'::text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  last_activity_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ai_operator_sessions_channel_check CHECK (channel = ANY (ARRAY['web'::text, 'whatsapp'::text, 'system'::text])),
  CONSTRAINT ai_operator_sessions_status_check CHECK (status = ANY (ARRAY['open'::text, 'paused'::text, 'closed'::text])),
  CONSTRAINT ai_operator_sessions_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.ai_operator_sessions IS 'MarineFlow AI Operator — sessões cross-channel. RLS: dono ou admin.';
ALTER TABLE public.ai_operator_sessions ENABLE ROW LEVEL SECURITY;

-- ── ai_suggestion_reviews ──
CREATE TABLE public.ai_suggestion_reviews (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  suggestion_type text NOT NULL,
  target_table text NOT NULL,
  target_id uuid,
  service_id uuid,
  suggested jsonb NOT NULL,
  approved jsonb,
  verdict text NOT NULL,
  change_summary text,
  reviewer_id uuid,
  ai_model text,
  prompt_version text,
  reviewed_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ai_suggestion_reviews_suggestion_type_check CHECK (suggestion_type = ANY (ARRAY['survey_question'::text, 'step'::text, 'duration'::text, 'material'::text, 'quote_line'::text, 'step_template'::text, 'step_block'::text])),
  CONSTRAINT ai_suggestion_reviews_verdict_check CHECK (verdict = ANY (ARRAY['accepted'::text, 'edited'::text, 'rejected'::text])),
  CONSTRAINT ai_suggestion_reviews_pkey PRIMARY KEY (id)
);
ALTER TABLE public.ai_suggestion_reviews ENABLE ROW LEVEL SECURITY;

-- ── ai_workflows ──
CREATE TABLE public.ai_workflows (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  workflow_type text NOT NULL,
  entity_type text DEFAULT 'service_order'::text NOT NULL,
  entity_id uuid NOT NULL,
  entity_number text,
  client_id uuid,
  current_step text NOT NULL,
  steps_completed text[] DEFAULT '{}'::text[] NOT NULL,
  status text DEFAULT 'active'::text NOT NULL,
  context jsonb DEFAULT '{}'::jsonb NOT NULL,
  next_action_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ai_workflows_status_check CHECK (status = ANY (ARRAY['active'::text, 'completed'::text, 'cancelled'::text, 'paused'::text])),
  CONSTRAINT ai_workflows_pkey PRIMARY KEY (id),
  CONSTRAINT ai_workflows_workflow_type_entity_id_key UNIQUE (workflow_type, entity_id)
);
ALTER TABLE public.ai_workflows ENABLE ROW LEVEL SECURITY;

-- ── api_references ──
CREATE TABLE public.api_references (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  provider text NOT NULL,
  category text NOT NULL,
  endpoint_name text NOT NULL,
  http_method text DEFAULT 'POST'::text NOT NULL,
  path text NOT NULL,
  description text,
  payload_example jsonb,
  is_implemented boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT api_references_pkey PRIMARY KEY (id),
  CONSTRAINT api_references_provider_path_key UNIQUE (provider, path)
);
ALTER TABLE public.api_references ENABLE ROW LEVEL SECURITY;

-- ── app_error_logs ──
CREATE TABLE public.app_error_logs (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  fingerprint text NOT NULL,
  source text NOT NULL,
  level text DEFAULT 'error'::text NOT NULL,
  context text,
  action text,
  message text NOT NULL,
  details jsonb,
  user_id uuid,
  user_email text,
  user_agent text,
  occurrences integer DEFAULT 1 NOT NULL,
  first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  resolved_at timestamp with time zone,
  CONSTRAINT app_error_logs_level_check CHECK (level = ANY (ARRAY['error'::text, 'warn'::text])),
  CONSTRAINT app_error_logs_source_check CHECK (source = ANY (ARRAY['frontend'::text, 'edge'::text, 'db'::text])),
  CONSTRAINT app_error_logs_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.app_error_logs IS 'Erros da aplicação (front e edge), agrupados por fingerprint. Leitura só admin; escrita via log_app_error().';
ALTER TABLE public.app_error_logs ENABLE ROW LEVEL SECURITY;

-- ── app_notifications ──
CREATE TABLE public.app_notifications (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid NOT NULL,
  type text NOT NULL,
  title text NOT NULL,
  body text,
  navigate_to text,
  read_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT app_notifications_pkey PRIMARY KEY (id)
);
ALTER TABLE public.app_notifications ENABLE ROW LEVEL SECURITY;

-- ── app_settings ──
CREATE TABLE public.app_settings (
  key text NOT NULL,
  value text NOT NULL,
  description text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  default_csosn text DEFAULT '400'::text,
  default_fiscal_origin integer DEFAULT 0,
  default_icms_rate numeric(6,4) DEFAULT 0,
  default_ipi_rate numeric(6,4) DEFAULT 0,
  default_pis_rate numeric(6,4) DEFAULT 0,
  default_cofins_rate numeric(6,4) DEFAULT 0,
  default_commission_rate numeric(6,4) DEFAULT 0,
  default_profit_margin numeric(6,4) DEFAULT 30,
  simples_aliquota numeric(6,4) DEFAULT 6,
  CONSTRAINT app_settings_pkey PRIMARY KEY (key)
);
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- ── app_users ──
CREATE TABLE public.app_users (
  id uuid NOT NULL,
  full_name text NOT NULL,
  email text NOT NULL,
  phone text,
  role text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  avatar_url text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  postal_code text,
  address_line_1 text,
  address_number text,
  address_complement text,
  neighborhood text,
  city text,
  state text,
  country text DEFAULT 'Brazil'::text,
  notes text,
  cpf text,
  rg text,
  birth_date date,
  hiring_date date,
  resignation_date date,
  department text,
  salary_base numeric(15,2),
  pix_key text,
  emergency_contact_name text,
  emergency_contact_phone text,
  metadata jsonb DEFAULT '{}'::jsonb,
  phone_normalized text,
  ai_whatsapp_enabled boolean DEFAULT false NOT NULL,
  ai_whatsapp_pin_hash text,
  CONSTRAINT app_users_pkey PRIMARY KEY (id),
  CONSTRAINT app_users_email_key UNIQUE (email)
);
COMMENT ON COLUMN public.app_users.cpf IS 'Sensible data';
COMMENT ON COLUMN public.app_users.salary_base IS 'Sensible data - restricted to admin/HR';
ALTER TABLE public.app_users ENABLE ROW LEVEL SECURITY;

-- ── audit_log ──
CREATE TABLE public.audit_log (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  table_name text NOT NULL,
  record_id uuid NOT NULL,
  action text NOT NULL,
  changed_by text DEFAULT 'sistema'::text NOT NULL,
  changed_at timestamp with time zone DEFAULT now(),
  previous_value jsonb,
  new_value jsonb,
  reason text,
  triggered_by_table text,
  triggered_by_id uuid,
  CONSTRAINT audit_log_action_check CHECK (action = ANY (ARRAY['update'::text, 'cancel'::text, 'reopen'::text, 'reversal'::text, 'cascade_update'::text, 'client_signature'::text, 'whatsapp_send'::text, 'whatsapp_send_api'::text, 'whatsapp_received'::text, 'lead_created'::text, 'lead_matched'::text, 'lead_converted'::text])),
  CONSTRAINT audit_log_pkey PRIMARY KEY (id)
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- ── bank_balance_checks ──
CREATE TABLE public.bank_balance_checks (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  bank_connection_id uuid NOT NULL,
  conferido_em timestamp with time zone DEFAULT now() NOT NULL,
  saldo_do_provedor numeric(14,2),
  saldo_calculado numeric(14,2),
  diferenca numeric(14,2),
  transacoes_no_periodo integer,
  fecha boolean DEFAULT false NOT NULL,
  observacao text,
  CONSTRAINT bank_balance_checks_pkey PRIMARY KEY (id)
);
ALTER TABLE public.bank_balance_checks ENABLE ROW LEVEL SECURITY;

-- ── bank_charges ──
CREATE TABLE public.bank_charges (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  receivable_id uuid,
  service_order_id uuid,
  client_id uuid,
  provider text NOT NULL,
  provider_charge_id text,
  kind text NOT NULL,
  amount numeric(14,2) NOT NULL,
  due_date date,
  status text DEFAULT 'pending'::text NOT NULL,
  digitable_line text,
  barcode text,
  pix_copy_paste text,
  pix_qr_base64 text,
  pix_end_to_end_id text,
  pdf_url text,
  paid_at timestamp with time zone,
  paid_amount numeric(14,2),
  raw jsonb,
  error_message text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT bank_charges_amount_check CHECK (amount > 0::numeric),
  CONSTRAINT bank_charges_kind_check CHECK (kind = ANY (ARRAY['boleto'::text, 'pix'::text, 'bolepix'::text])),
  CONSTRAINT bank_charges_status_check CHECK (status = ANY (ARRAY['pending'::text, 'registered'::text, 'paid'::text, 'overdue'::text, 'cancelled'::text, 'failed'::text])),
  CONSTRAINT bank_charges_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.bank_charges IS 'Cobrancas emitidas no banco (boleto/Pix). Instrumento de recebimento, distinto da conta a receber.';
COMMENT ON COLUMN public.bank_charges.raw IS 'Resposta bruta do provedor, para investigar divergencia sem depender de log.';
ALTER TABLE public.bank_charges ENABLE ROW LEVEL SECURITY;

-- ── bank_connections ──
CREATE TABLE public.bank_connections (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  provider text DEFAULT 'pluggy'::text NOT NULL,
  external_id text NOT NULL,
  label text NOT NULL,
  institution text,
  account_kind text DEFAULT 'bank'::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  last_synced_at timestamp with time zone,
  last_sync_status text,
  last_sync_message text,
  last_sync_imported integer,
  last_transaction_date date,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  consent_expires_at timestamp with time zone,
  provider_status text,
  sincronizacoes_vazias integer DEFAULT 0 NOT NULL,
  CONSTRAINT bank_connections_account_kind_check CHECK (account_kind = ANY (ARRAY['bank'::text, 'credit_card'::text])),
  CONSTRAINT bank_connections_last_sync_status_check CHECK (last_sync_status = ANY (ARRAY['ok'::text, 'error'::text, 'never'::text])),
  CONSTRAINT bank_connections_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.bank_connections IS 'Conexoes de leitura de extrato (Open Finance). external_id = itemId do Pluggy.';
COMMENT ON COLUMN public.bank_connections.last_synced_at IS 'Ultima sincronizacao bem-sucedida. Serve de alarme: consentimento do Open Finance expira e a coleta para em silencio.';
COMMENT ON COLUMN public.bank_connections.consent_expires_at IS 'Vencimento do consentimento de Open Finance (12 meses). Sem aviso, a conexão morre calada e o gestor descobre no fechamento, com o período já perdido.';
ALTER TABLE public.bank_connections ENABLE ROW LEVEL SECURITY;

-- ── bank_transactions ──
CREATE TABLE public.bank_transactions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  transaction_date date NOT NULL,
  description text NOT NULL,
  amount numeric(12,2) NOT NULL,
  transaction_type text NOT NULL,
  bank_ref_id text,
  reconciled boolean DEFAULT false,
  reconciled_payment_id uuid,
  import_batch_id text,
  created_at timestamp with time zone DEFAULT now(),
  source_type text DEFAULT 'bank'::text NOT NULL,
  reconciled_service_order_id uuid,
  pix_end_to_end_id text,
  counterparty_name text,
  counterparty_document text,
  balance_after numeric(14,2),
  provider text DEFAULT 'manual'::text NOT NULL,
  dismissed_reason text,
  bank_connection_id uuid,
  counterparty_bank text,
  counterparty_branch text,
  counterparty_account text,
  payment_method text,
  payment_reason text,
  merchant_name text,
  merchant_document text,
  installment_label text,
  dismissed_at timestamp with time zone,
  dismissed_by uuid,
  dismissed_kind text,
  provider_category text,
  merchant_category text,
  payee_mcc text,
  card_last_digits text,
  tx_status text,
  authentication_code text,
  receiver_reference_id text,
  bill_id text,
  provider_account_id text,
  CONSTRAINT bank_transactions_transaction_type_check CHECK (transaction_type = ANY (ARRAY['credit'::text, 'debit'::text])),
  CONSTRAINT bank_transactions_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.bank_transactions.provider IS 'Origem da linha: manual (importacao OFX/CSV) ou o provedor que a sincronizou (pluggy, cora, c6, inter).';
COMMENT ON COLUMN public.bank_transactions.dismissed_reason IS 'Motivo informado ao ignorar a transacao na tela de conciliacao.';
COMMENT ON COLUMN public.bank_transactions.counterparty_bank IS 'Banco de quem recebeu/pagou (routingNumber ou ISPB). Existe para o gestor identificar sem abrir o internet banking.';
COMMENT ON COLUMN public.bank_transactions.payment_reason IS 'Mensagem que o pagador escreveu na transferência — costuma dizer a que a despesa se refere.';
COMMENT ON COLUMN public.bank_transactions.merchant_name IS 'Razão social do estabelecimento. Identifica melhor que o histórico: "NETFLIX ENTRETENIMENTO BRASIL" contra "EC *NETFLIX SAO PAULO BRA".';
COMMENT ON COLUMN public.bank_transactions.dismissed_kind IS 'Por que saiu da fila: duplicata | fatura_cartao | transferencia | mecanica_cartao | parcela | manual. Sem CHECK de propósito — lista fechada faz um tipo novo falhar em silêncio no lugar de aparecer.';
COMMENT ON COLUMN public.bank_transactions.payee_mcc IS 'Merchant Category Code (ISO 18245). Classificação determinística de estabelecimento — precede memória e IA na ordem de decisão.';
COMMENT ON COLUMN public.bank_transactions.tx_status IS 'PENDING | POSTED. Pendente não vira proposta de lançamento.';
ALTER TABLE public.bank_transactions ENABLE ROW LEVEL SECURITY;

-- ── card_installment_fees ──
CREATE TABLE public.card_installment_fees (
  installments integer NOT NULL,
  fee_percent numeric(6,4) DEFAULT 0 NOT NULL,
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT card_installment_fees_installments_check CHECK (installments >= 1 AND installments <= 6),
  CONSTRAINT card_installment_fees_pkey PRIMARY KEY (installments)
);
ALTER TABLE public.card_installment_fees ENABLE ROW LEVEL SECURITY;

-- ── client_whatsapp_settings ──
CREATE TABLE public.client_whatsapp_settings (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  client_id uuid NOT NULL,
  context text NOT NULL,
  message_body text,
  link_title text,
  link_description text,
  pdf_filename_pattern text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT client_whatsapp_settings_context_check CHECK (context = ANY (ARRAY['service_order'::text, 'quote'::text, 'billing'::text])),
  CONSTRAINT client_whatsapp_settings_pkey PRIMARY KEY (id),
  CONSTRAINT client_whatsapp_settings_client_id_context_key UNIQUE (client_id, context)
);
ALTER TABLE public.client_whatsapp_settings ENABLE ROW LEVEL SECURITY;

-- ── clients ──
CREATE TABLE public.clients (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  type text NOT NULL,
  name text NOT NULL,
  cpf_cnpj text,
  phone text,
  whatsapp text,
  email text,
  address_line_1 text,
  address_line_2 text,
  city text,
  state text,
  postal_code text,
  country text DEFAULT 'Brazil'::text,
  notes text,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  state_registration text,
  ie_indicator integer DEFAULT 9,
  address_number text,
  address_complement text,
  neighborhood text,
  display_name text,
  communication_tone text,
  opt_out_whatsapp boolean DEFAULT false NOT NULL,
  CONSTRAINT chk_clients_ie_indicator CHECK (ie_indicator IS NULL OR (ie_indicator = ANY (ARRAY[1, 2, 9]))),
  CONSTRAINT clients_type_check CHECK (type = ANY (ARRAY['individual'::text, 'company'::text])),
  CONSTRAINT clients_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.clients.display_name IS 'Nome usado na comunicação (fantasia/primeiro nome), preferido sobre a razao social/name.';
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;

-- ── collection_contacts ──
CREATE TABLE public.collection_contacts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  collection_id uuid NOT NULL,
  contact_type text NOT NULL,
  notes text,
  promised_date date,
  created_by uuid,
  CONSTRAINT collection_contacts_contact_type_check CHECK (contact_type = ANY (ARRAY['whatsapp_sent'::text, 'whatsapp_delivered'::text, 'whatsapp_read'::text, 'call_made'::text, 'call_answered'::text, 'call_no_answer'::text, 'email_sent'::text, 'manual_note'::text, 'payment_promised'::text, 'paid'::text])),
  CONSTRAINT collection_contacts_pkey PRIMARY KEY (id)
);
ALTER TABLE public.collection_contacts ENABLE ROW LEVEL SECURITY;

-- ── collection_templates ──
CREATE TABLE public.collection_templates (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  name text NOT NULL,
  body text NOT NULL,
  is_default boolean DEFAULT false,
  send_method text DEFAULT 'text_link'::text,
  CONSTRAINT collection_templates_send_method_check CHECK (send_method = ANY (ARRAY['pdf'::text, 'text'::text, 'text_link'::text])),
  CONSTRAINT collection_templates_pkey PRIMARY KEY (id)
);
ALTER TABLE public.collection_templates ENABLE ROW LEVEL SECURITY;

-- ── collections ──
CREATE TABLE public.collections (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  service_order_id uuid,
  receivable_id uuid,
  description text,
  standalone_amount numeric(12,2),
  client_id uuid NOT NULL,
  amount numeric(12,2) NOT NULL,
  due_date date NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  contact_name text,
  phone text,
  contact_whatsapp text,
  send_method text DEFAULT 'text_link'::text,
  message_template text,
  paid_at timestamp with time zone,
  paid_amount numeric(12,2),
  paid_method text,
  payment_confirmed_by text DEFAULT 'manual'::text,
  auto_rule_enabled boolean DEFAULT false,
  rule_days_before integer DEFAULT 3,
  rule_days_after integer DEFAULT 5,
  last_auto_sent_at timestamp with time zone,
  created_by uuid,
  notes text,
  CONSTRAINT collections_payment_confirmed_by_check CHECK (payment_confirmed_by = ANY (ARRAY['manual'::text, 'whatsapp'::text, 'auto'::text])),
  CONSTRAINT collections_send_method_check CHECK (send_method = ANY (ARRAY['pdf'::text, 'text'::text, 'text_link'::text])),
  CONSTRAINT collections_status_check CHECK (status = ANY (ARRAY['pending'::text, 'sent'::text, 'viewed'::text, 'paid'::text, 'overdue'::text, 'disputed'::text, 'cancelled'::text])),
  CONSTRAINT collections_pkey PRIMARY KEY (id)
);
ALTER TABLE public.collections ENABLE ROW LEVEL SECURITY;

-- ── commissions ──
CREATE TABLE public.commissions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  service_order_id uuid,
  user_id uuid,
  amount numeric(12,2) NOT NULL,
  base_value numeric(12,2),
  percentage numeric(5,2),
  status text DEFAULT 'pending'::text,
  paid_at timestamp with time zone,
  payable_id uuid,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  payee_id uuid,
  CONSTRAINT commissions_pkey PRIMARY KEY (id),
  CONSTRAINT commissions_so_user_unique UNIQUE (service_order_id, user_id)
);
COMMENT ON COLUMN public.commissions.payee_id IS 'Comissionado que não é usuário do sistema. Alternativo a user_id — um dos dois, nunca ambos.';
ALTER TABLE public.commissions ENABLE ROW LEVEL SECURITY;

-- ── company_fiscal_settings ──
CREATE TABLE public.company_fiscal_settings (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  legal_name text,
  trade_name text,
  cnpj text,
  state_registration text,
  municipal_registration text,
  tax_regime text DEFAULT 'simples'::text NOT NULL,
  crt integer DEFAULT 1 NOT NULL,
  street text,
  number text,
  complement text,
  district text,
  city_name text,
  ibge_city_code text,
  state_code text,
  postal_code text,
  provider text DEFAULT 'contora'::text NOT NULL,
  contora_template_id text,
  active_environment text DEFAULT 'homologacao'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  singleton_guard boolean DEFAULT true NOT NULL,
  nfe_series_producao integer DEFAULT 1 NOT NULL,
  nfse_standard text DEFAULT 'nacional'::text NOT NULL,
  nfse_total_tax_rate_sn numeric,
  nfse_simples_nacional_option smallint,
  nfse_municipal_registration_in_cnc boolean DEFAULT true NOT NULL,
  nfse_default_series integer DEFAULT 1 NOT NULL,
  CONSTRAINT cfs_nfse_simples_option_valido CHECK (nfse_simples_nacional_option IS NULL OR (nfse_simples_nacional_option = ANY (ARRAY[1, 2, 3]))),
  CONSTRAINT cfs_nfse_standard_valido CHECK (nfse_standard = ANY (ARRAY['nacional'::text, 'municipal'::text])),
  CONSTRAINT cfs_nfse_total_tax_rate_sn_faixa CHECK (nfse_total_tax_rate_sn IS NULL OR nfse_total_tax_rate_sn >= 0::numeric AND nfse_total_tax_rate_sn <= 100::numeric),
  CONSTRAINT chk_cfs_environment CHECK (active_environment = ANY (ARRAY['homologacao'::text, 'producao'::text])),
  CONSTRAINT chk_cfs_tax_regime CHECK (tax_regime = ANY (ARRAY['mei'::text, 'simples'::text, 'presumido'::text, 'real'::text])),
  CONSTRAINT company_fiscal_settings_pkey PRIMARY KEY (id),
  CONSTRAINT company_fiscal_settings_cnpj_key UNIQUE (cnpj),
  CONSTRAINT uq_company_fiscal_settings_singleton UNIQUE (singleton_guard)
);
COMMENT ON COLUMN public.company_fiscal_settings.nfse_standard IS 'nacional | municipal. Quem decide e o MUNICIPIO, nao o regime da empresa. Confirmar em GET /companies/{id}/nfse/health antes da primeira emissao.';
COMMENT ON COLUMN public.company_fiscal_settings.nfse_total_tax_rate_sn IS 'Percentual TOTAL de tributos da faixa do Simples na competencia — so a contabilidade sabe. Obrigatorio para ME/EPP no padrao nacional (E0712). Nao e a aliquota de ISS.';
COMMENT ON COLUMN public.company_fiscal_settings.nfse_simples_nacional_option IS '1 nao optante | 2 optante MEI | 3 optante ME/EPP. Preencher so quando o regime cadastrado divergir do cadastro do Simples (E0160).';
COMMENT ON COLUMN public.company_fiscal_settings.nfse_municipal_registration_in_cnc IS 'A inscricao municipal so entra no documento quando o municipio tem dados no CNC NFS-e. Onde nao tem, o envio e recusado com E0120 — ai marque false.';
COMMENT ON COLUMN public.company_fiscal_settings.nfse_default_series IS 'Serie padrao da NFS-e. Separada de nfe_series_producao: sao numeracoes independentes.';
ALTER TABLE public.company_fiscal_settings ENABLE ROW LEVEL SECURITY;

-- ── cost_centers ──
CREATE TABLE public.cost_centers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name character varying NOT NULL,
  type character varying NOT NULL,
  parent_id uuid,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT cost_centers_type_check CHECK (type::text = ANY (ARRAY['revenue'::character varying, 'expense'::character varying, 'both'::character varying]::text[])),
  CONSTRAINT cost_centers_pkey PRIMARY KEY (id)
);
ALTER TABLE public.cost_centers ENABLE ROW LEVEL SECURITY;

-- ── dc_ampacity_ratings ──
CREATE TABLE public.dc_ampacity_ratings (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  mm2 numeric NOT NULL,
  awg text,
  insulation_c integer NOT NULL,
  amps_free_air numeric NOT NULL,
  amps_free_air_engine numeric NOT NULL,
  amps_bundled numeric NOT NULL,
  amps_bundled_engine numeric NOT NULL,
  ohm_per_km numeric,
  diameter_mm numeric,
  source text NOT NULL,
  notes text,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT dc_ampacity_ratings_amps_bundled_check CHECK (amps_bundled > 0::numeric),
  CONSTRAINT dc_ampacity_ratings_amps_bundled_engine_check CHECK (amps_bundled_engine > 0::numeric),
  CONSTRAINT dc_ampacity_ratings_amps_free_air_check CHECK (amps_free_air > 0::numeric),
  CONSTRAINT dc_ampacity_ratings_amps_free_air_engine_check CHECK (amps_free_air_engine > 0::numeric),
  CONSTRAINT dc_ampacity_ratings_diameter_mm_check CHECK (diameter_mm > 0::numeric),
  CONSTRAINT dc_ampacity_ratings_insulation_c_check CHECK (insulation_c = ANY (ARRAY[75, 90, 105])),
  CONSTRAINT dc_ampacity_ratings_mm2_check CHECK (mm2 > 0::numeric),
  CONSTRAINT dc_ampacity_ratings_ohm_per_km_check CHECK (ohm_per_km > 0::numeric),
  CONSTRAINT dc_ampacity_ratings_source_check CHECK (length(TRIM(BOTH FROM source)) > 0),
  CONSTRAINT engrm_em_faixa_plausivel CHECK ((amps_free_air_engine / amps_free_air) >= 0.70 AND (amps_free_air_engine / amps_free_air) <= 0.90 AND (amps_bundled_engine / amps_bundled) >= 0.70 AND (amps_bundled_engine / amps_bundled) <= 0.90),
  CONSTRAINT engrm_menor_que_ar_livre CHECK (amps_free_air_engine < amps_free_air),
  CONSTRAINT engrm_menor_que_feixe CHECK (amps_bundled_engine < amps_bundled),
  CONSTRAINT feixe_em_faixa_plausivel CHECK ((amps_bundled / amps_free_air) >= 0.62 AND (amps_bundled / amps_free_air) <= 0.78),
  CONSTRAINT feixe_menor_que_ar_livre CHECK (amps_bundled < amps_free_air),
  CONSTRAINT dc_ampacity_ratings_pkey PRIMARY KEY (id),
  CONSTRAINT dc_ampacity_ratings_mm2_insulation_c_key UNIQUE (mm2, insulation_c)
);
COMMENT ON TABLE public.dc_ampacity_ratings IS 'ABYC E-11, Tabelas VI-A (condutor ao ar livre) e VI-B (até três condutores em
   feixe), cada uma com a coluna de casa de máquinas, mais diâmetro e
   resistência. 30 bitolas × 3 temperaturas de isolação. Os CHECK reproduzem as
   conferências de consistência: linha incoerente é recusada, não guardada.';
ALTER TABLE public.dc_ampacity_ratings ENABLE ROW LEVEL SECURITY;

-- ── entity_open_loops ──
CREATE TABLE public.entity_open_loops (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid NOT NULL,
  loop_key text NOT NULL,
  source text NOT NULL,
  kind text NOT NULL,
  title text NOT NULL,
  detail text,
  ref_table text,
  ref_id uuid,
  service_order_id uuid,
  due_at timestamp with time zone,
  priority text DEFAULT 'normal'::text NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  evidence text,
  evidence_at timestamp with time zone,
  source_message_id uuid,
  task_id uuid,
  mentions integer DEFAULT 1 NOT NULL,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  resolved_at timestamp with time zone,
  resolved_reason text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  direction text DEFAULT 'ours'::text NOT NULL,
  CONSTRAINT entity_open_loops_direction_check CHECK (direction = ANY (ARRAY['ours'::text, 'theirs'::text])),
  CONSTRAINT entity_open_loops_entity_type_check CHECK (entity_type = ANY (ARRAY['client'::text, 'supplier'::text])),
  CONSTRAINT entity_open_loops_priority_check CHECK (priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text])),
  CONSTRAINT entity_open_loops_source_check CHECK (source = ANY (ARRAY['erp'::text, 'conversation'::text])),
  CONSTRAINT entity_open_loops_status_check CHECK (status = ANY (ARRAY['open'::text, 'resolved'::text])),
  CONSTRAINT entity_open_loops_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.entity_open_loops.direction IS 'Para o fio ANDAR, quem precisa agir: ours = ação nossa (executar/pagar/cobrar/responder); theirs = esperando a contraparte. Não é "de quem é a obrigação" — título vencido é ours, porque cobrar é ação nossa.';
ALTER TABLE public.entity_open_loops ENABLE ROW LEVEL SECURITY;

-- ── exchange_rates ──
CREATE TABLE public.exchange_rates (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  from_currency text NOT NULL,
  to_currency text NOT NULL,
  rate numeric(18,8) NOT NULL,
  source text DEFAULT 'manual'::text,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT exchange_rates_pkey PRIMARY KEY (id)
);
ALTER TABLE public.exchange_rates ENABLE ROW LEVEL SECURITY;

-- ── external_quote_leads ──
CREATE TABLE public.external_quote_leads (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  created_by uuid NOT NULL,
  promoted_client_id uuid,
  type text DEFAULT 'individual'::text NOT NULL,
  name text NOT NULL,
  cpf_cnpj text,
  phone text,
  whatsapp text,
  email text,
  address_line_1 text,
  address_line_2 text,
  city text,
  state text,
  postal_code text,
  country text DEFAULT 'Brazil'::text,
  boat_name text,
  boat_manufacturer text,
  boat_model text,
  boat_year integer,
  boat_length_feet numeric,
  marina_name text,
  notes text,
  promoted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT external_quote_leads_pkey PRIMARY KEY (id)
);
ALTER TABLE public.external_quote_leads ENABLE ROW LEVEL SECURITY;

-- ── external_quote_parts ──
CREATE TABLE public.external_quote_parts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  external_quote_id uuid NOT NULL,
  product_id uuid,
  name_snapshot text NOT NULL,
  quantity numeric DEFAULT 1 NOT NULL,
  unit_cost_snapshot numeric DEFAULT 0 NOT NULL,
  unit_sale_snapshot numeric DEFAULT 0 NOT NULL,
  currency_snapshot text DEFAULT 'BRL'::text,
  line_total_cost numeric DEFAULT 0 NOT NULL,
  line_total_sale numeric DEFAULT 0 NOT NULL,
  warranty_days integer DEFAULT 0,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT external_quote_parts_pkey PRIMARY KEY (id)
);
ALTER TABLE public.external_quote_parts ENABLE ROW LEVEL SECURITY;

-- ── external_quote_services ──
CREATE TABLE public.external_quote_services (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  external_quote_id uuid NOT NULL,
  service_id uuid,
  name_snapshot text NOT NULL,
  description_snapshot text,
  billing_unit_snapshot text DEFAULT 'hour'::text NOT NULL,
  quantity numeric DEFAULT 1 NOT NULL,
  unit_price_snapshot numeric DEFAULT 0 NOT NULL,
  line_total numeric DEFAULT 0 NOT NULL,
  warranty_days integer DEFAULT 0,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT external_quote_services_pkey PRIMARY KEY (id)
);
ALTER TABLE public.external_quote_services ENABLE ROW LEVEL SECURITY;

-- ── external_quotes ──
CREATE TABLE public.external_quotes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  quote_number text DEFAULT ((('EQ-'::text || to_char(now(), 'YYYYMMDD'::text)) || '-'::text) || substr((gen_random_uuid())::text, 1, 6)) NOT NULL,
  created_by uuid NOT NULL,
  lead_id uuid,
  client_id uuid,
  vessel_id uuid,
  marina_id uuid,
  status text DEFAULT 'draft'::text NOT NULL,
  service_type text,
  problem_description text,
  initial_findings text,
  customer_visible_report text,
  internal_notes text,
  hourly_rate numeric DEFAULT 0,
  estimated_hours numeric DEFAULT 0,
  labor_cost_total numeric DEFAULT 0,
  travel_distance_km numeric DEFAULT 0,
  travel_cost_per_km numeric DEFAULT 0,
  travel_cost_total numeric DEFAULT 0,
  parts_cost_total numeric DEFAULT 0,
  subcontract_cost_total numeric DEFAULT 0,
  discount_amount numeric DEFAULT 0,
  tax_amount numeric DEFAULT 0,
  grand_total numeric DEFAULT 0,
  currency text DEFAULT 'BRL'::text,
  quote_validity_days integer DEFAULT 15,
  quote_validity_date date,
  payment_conditions text,
  submitted_at timestamp with time zone,
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  rejection_reason text,
  converted_service_order_id uuid,
  converted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  ai_operator_draft_id uuid,
  CONSTRAINT external_quotes_pkey PRIMARY KEY (id),
  CONSTRAINT external_quotes_quote_number_key UNIQUE (quote_number)
);
COMMENT ON COLUMN public.external_quotes.ai_operator_draft_id IS 'AI Operator draft that originated this formal ERP quote. Used for idempotent draft-to-quote formalization.';
ALTER TABLE public.external_quotes ENABLE ROW LEVEL SECURITY;

-- ── finance_review_queue ──
CREATE TABLE public.finance_review_queue (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  kind text NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  bank_transaction_id uuid,
  related_transaction_id uuid,
  title text NOT NULL,
  reasoning text,
  confidence integer DEFAULT 50 NOT NULL,
  suggested_amount numeric(14,2),
  suggested_date date,
  suggested_category text,
  suggested_supplier_id uuid,
  suggested_client_id uuid,
  suggested_description text,
  dre_group text,
  created_payable_id uuid,
  created_receivable_id uuid,
  decided_by uuid,
  decided_at timestamp with time zone,
  decision_note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  applied_rule_id uuid,
  suggested_payee_id uuid,
  suggested_service_order_id uuid,
  suggested_purchase_order_id uuid,
  CONSTRAINT finance_review_queue_confidence_check CHECK (confidence >= 0 AND confidence <= 100),
  CONSTRAINT finance_review_queue_kind_check CHECK (kind = ANY (ARRAY['create_payable'::text, 'create_receivable'::text, 'internal_transfer'::text, 'categorize'::text, 'anomaly'::text])),
  CONSTRAINT finance_review_queue_status_check CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'superseded'::text])),
  CONSTRAINT finance_review_queue_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.finance_review_queue IS 'Propostas do sistema aguardando decisao do gestor. Aprovar cria lancamento; nada aqui movimenta dinheiro.';
COMMENT ON COLUMN public.finance_review_queue.reasoning IS 'Por que o sistema propos isto — a trilha guarda a decisao, nao apenas a acao.';
COMMENT ON COLUMN public.finance_review_queue.applied_rule_id IS 'Regra que classificou esta proposta. Permite auditar a regra pelo resultado dela.';
ALTER TABLE public.finance_review_queue ENABLE ROW LEVEL SECURITY;

-- ── finance_rules ──
CREATE TABLE public.finance_rules (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  match_type text NOT NULL,
  match_value text NOT NULL,
  direction text DEFAULT 'debit'::text NOT NULL,
  min_amount numeric(14,2),
  max_amount numeric(14,2),
  set_category text,
  set_dre_group text,
  set_supplier_id uuid,
  autonomy text DEFAULT 'suggest'::text NOT NULL,
  origin text DEFAULT 'user'::text NOT NULL,
  status text DEFAULT 'active'::text NOT NULL,
  reasoning text,
  note text,
  times_applied integer DEFAULT 0 NOT NULL,
  last_applied_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT finance_rules_autonomy_check CHECK (autonomy = ANY (ARRAY['suggest'::text, 'apply'::text])),
  CONSTRAINT finance_rules_direction_check CHECK (direction = ANY (ARRAY['debit'::text, 'credit'::text, 'any'::text])),
  CONSTRAINT finance_rules_match_type_check CHECK (match_type = ANY (ARRAY['document'::text, 'supplier'::text, 'counterparty'::text, 'text'::text])),
  CONSTRAINT finance_rules_origin_check CHECK (origin = ANY (ARRAY['user'::text, 'ai'::text])),
  CONSTRAINT finance_rules_status_check CHECK (status = ANY (ARRAY['active'::text, 'paused'::text, 'proposed'::text, 'rejected'::text])),
  CONSTRAINT finance_rules_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.finance_rules IS 'O que o gestor ensinou ao sistema sobre as próprias despesas. A IA propõe (status proposed); quem aceita é gente.';
COMMENT ON COLUMN public.finance_rules.autonomy IS 'suggest = preenche e espera confirmação; apply = lança sozinha, marcada como criada por regra.';
ALTER TABLE public.finance_rules ENABLE ROW LEVEL SECURITY;

-- ── financial_categories ──
CREATE TABLE public.financial_categories (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  type text NOT NULL,
  color text DEFAULT '#6b7280'::text,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  dre_group text,
  sort_order integer DEFAULT 100 NOT NULL,
  description text,
  sensitive boolean DEFAULT false NOT NULL,
  CONSTRAINT financial_categories_type_check CHECK (type = ANY (ARRAY['payable'::text, 'receivable'::text])),
  CONSTRAINT financial_categories_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.financial_categories.dre_group IS 'Onde a categoria entra no resultado: receita, custo_direto, despesa_operacional, financeiro, nao_operacional. O grupo nao_operacional fica FORA do resultado.';
COMMENT ON COLUMN public.financial_categories.sensitive IS 'Categoria cujos lançamentos só o administrador enxerga (pró-labore, folha).';
ALTER TABLE public.financial_categories ENABLE ROW LEVEL SECURITY;

-- ── fiscal_document_sequences ──
CREATE TABLE public.fiscal_document_sequences (
  document_type text NOT NULL,
  series integer DEFAULT 1 NOT NULL,
  environment text DEFAULT 'homologacao'::text NOT NULL,
  last_number integer DEFAULT 0 NOT NULL,
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT fiscal_document_sequences_pkey PRIMARY KEY (document_type, series, environment)
);
ALTER TABLE public.fiscal_document_sequences ENABLE ROW LEVEL SECURITY;

-- ── fiscal_emission_drafts ──
CREATE TABLE public.fiscal_emission_drafts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  created_by uuid,
  label text,
  nature_of_operation text,
  recipient_name text,
  total_amount numeric,
  form_state jsonb NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT fiscal_emission_drafts_status_check CHECK (status = ANY (ARRAY['draft'::text, 'archived'::text])),
  CONSTRAINT fiscal_emission_drafts_pkey PRIMARY KEY (id)
);
ALTER TABLE public.fiscal_emission_drafts ENABLE ROW LEVEL SECURITY;

-- ── fiscal_note_items ──
CREATE TABLE public.fiscal_note_items (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  fiscal_note_id uuid,
  product_id uuid,
  item_index integer,
  description text,
  sku_internal text,
  sku_supplier text,
  quantity numeric(12,4),
  unit_price numeric(12,2),
  total_price numeric(12,2),
  ncm text,
  cfop text,
  processed boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  c_prod text,
  x_prod text,
  unit text,
  q_com numeric DEFAULT 0,
  v_un_com numeric DEFAULT 0,
  v_prod numeric DEFAULT 0,
  matched_product_id uuid,
  inventory_movement_id uuid,
  service_order_id uuid,
  CONSTRAINT fiscal_note_items_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.fiscal_note_items.service_order_id IS 'OS para a qual ESTE item foi comprado. NULL = compra para estoque, sem dono. O vinculo e por linha (nao pela nota) porque uma nota costuma trazer peca de varias OS.';
ALTER TABLE public.fiscal_note_items ENABLE ROW LEVEL SECURITY;

-- ── fiscal_notes ──
CREATE TABLE public.fiscal_notes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  company_id uuid,
  nfe_key text,
  nfe_number text,
  issue_date timestamp with time zone,
  issuer_name text,
  issuer_cnpj text,
  total_value numeric(12,2),
  xml_url text,
  status text DEFAULT 'pending'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  issued_at timestamp with time zone,
  total_amount numeric(14,2) DEFAULT 0,
  tax_icms numeric(14,2) DEFAULT 0,
  tax_ipi numeric(14,2) DEFAULT 0,
  tax_pis numeric(14,2) DEFAULT 0,
  tax_cofins numeric(14,2) DEFAULT 0,
  items jsonb DEFAULT '[]'::jsonb,
  xml_content text,
  confirmed_at timestamp with time zone,
  supplier_id uuid,
  purchase_order_id uuid,
  import_result jsonb,
  total_products numeric,
  total_discount numeric,
  total_freight numeric,
  total_other numeric,
  total_insurance numeric,
  CONSTRAINT fiscal_notes_status_check CHECK (status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'cancelled'::text, 'error'::text])),
  CONSTRAINT fiscal_notes_pkey PRIMARY KEY (id),
  CONSTRAINT fiscal_notes_nfe_key_key UNIQUE (nfe_key)
);
COMMENT ON COLUMN public.fiscal_notes.import_result IS 'Resultado da confirmação: itens, produto casado e o motivo do casamento (auditoria).';
COMMENT ON COLUMN public.fiscal_notes.total_products IS 'vProd do <ICMSTot>: soma dos itens, antes de IPI/frete/desconto.';
ALTER TABLE public.fiscal_notes ENABLE ROW LEVEL SECURITY;

-- ── import_sessions ──
CREATE TABLE public.import_sessions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  entity_type text NOT NULL,
  filename text NOT NULL,
  total_rows integer DEFAULT 0,
  imported_rows integer DEFAULT 0,
  skipped_rows integer DEFAULT 0,
  conflict_rows integer DEFAULT 0,
  status text DEFAULT 'pending'::text,
  column_mapping jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT import_sessions_entity_type_check CHECK (entity_type = ANY (ARRAY['products'::text, 'services'::text, 'clients'::text, 'suppliers'::text])),
  CONSTRAINT import_sessions_status_check CHECK (status = ANY (ARRAY['pending'::text, 'mapping'::text, 'reviewing'::text, 'completed'::text, 'cancelled'::text])),
  CONSTRAINT import_sessions_pkey PRIMARY KEY (id)
);
ALTER TABLE public.import_sessions ENABLE ROW LEVEL SECURITY;

-- ── inventory_movements ──
CREATE TABLE public.inventory_movements (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  product_id uuid NOT NULL,
  movement_type text NOT NULL,
  quantity_delta numeric(10,3) NOT NULL,
  reference_type text,
  reference_id uuid,
  unit_cost_snapshot numeric(12,2),
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  adjusted_by text DEFAULT 'sistema'::text,
  reverses_movement_id uuid,
  CONSTRAINT inventory_movements_movement_type_check CHECK (movement_type = ANY (ARRAY['purchase'::text, 'manual_adjustment'::text, 'service_usage'::text, 'return'::text, 'transfer'::text, 'manual_add'::text, 'manual_remove'::text, 'import'::text, 'fiscal_note_entry'::text, 'service_order_usage'::text, 'manual_add_stock'::text, 'manual_remove_stock'::text, 'fiscal_note_exit'::text, 'fiscal_note_cancel_reversal'::text])),
  CONSTRAINT inventory_movements_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.inventory_movements.reverses_movement_id IS 'Baixa que este movimento reverte. Único: uma baixa só pode ser revertida uma vez (regra do Dynamics 365 BC). Nulo em movimentos que não são estorno.';
ALTER TABLE public.inventory_movements ENABLE ROW LEVEL SECURITY;

-- ── invoices ──
CREATE TABLE public.invoices (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  invoice_number text NOT NULL,
  service_order_id uuid,
  client_id uuid NOT NULL,
  issue_date date NOT NULL,
  due_date date NOT NULL,
  subtotal numeric(12,2) DEFAULT 0,
  discount_amount numeric(12,2) DEFAULT 0,
  tax_amount numeric(12,2) DEFAULT 0,
  total_amount numeric(12,2) DEFAULT 0,
  currency text DEFAULT 'BRL'::text,
  status text DEFAULT 'draft'::text,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT invoices_status_check CHECK (status = ANY (ARRAY['draft'::text, 'sent'::text, 'paid'::text, 'overdue'::text, 'cancelled'::text])),
  CONSTRAINT invoices_pkey PRIMARY KEY (id),
  CONSTRAINT invoices_invoice_number_key UNIQUE (invoice_number)
);
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;

-- ── issued_fiscal_documents ──
CREATE TABLE public.issued_fiscal_documents (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  document_type text NOT NULL,
  origin_type text DEFAULT 'manual'::text NOT NULL,
  origin_id uuid,
  client_id uuid,
  provider text DEFAULT 'contora'::text NOT NULL,
  provider_document_id text,
  environment text DEFAULT 'homologacao'::text NOT NULL,
  series integer,
  number integer,
  access_key text,
  protocol text,
  status text DEFAULT 'draft'::text NOT NULL,
  status_code text,
  status_message text,
  xml_url text,
  xml_storage_path text,
  pdf_url text,
  idempotency_key text,
  request_payload jsonb,
  provider_status jsonb,
  authorized_at timestamp with time zone,
  cancelled_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  pdf_storage_path text,
  source_items jsonb,
  stock_settled_at timestamp with time zone,
  receivable_id uuid,
  stock_reversed_at timestamp with time zone,
  payment_terms jsonb,
  customer_po_number text,
  customer_buyer_name text,
  CONSTRAINT chk_ifd_document_type CHECK (document_type = ANY (ARRAY['nfe'::text, 'nfce'::text, 'nfse'::text])),
  CONSTRAINT chk_ifd_environment CHECK (environment = ANY (ARRAY['homologacao'::text, 'producao'::text])),
  CONSTRAINT chk_ifd_origin_type CHECK (origin_type = ANY (ARRAY['invoice'::text, 'service_order'::text, 'manual'::text])),
  CONSTRAINT chk_ifd_status CHECK (status = ANY (ARRAY['draft'::text, 'queued'::text, 'processing'::text, 'authorized'::text, 'rejected'::text, 'failed'::text, 'cancelled'::text])),
  CONSTRAINT issued_fiscal_documents_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.issued_fiscal_documents.pdf_storage_path IS 'Caminho do DANFE (PDF) arquivado no bucket fiscal-xml: {env}/{type}/{id}.pdf. Usado para gerar URL assinada e enviar ao cliente.';
COMMENT ON COLUMN public.issued_fiscal_documents.source_items IS 'Itens da emissão com vínculo ao catálogo: [{product_id, quantity, unit_price}] — usado pela baixa de estoque (só itens ligados a produto).';
COMMENT ON COLUMN public.issued_fiscal_documents.payment_terms IS 'Plano de pagamento da emissão: {mode: avista|parcelado, method, installments:[{due_date,amount,method}]}. Reaproveitado nos recebíveis.';
COMMENT ON COLUMN public.issued_fiscal_documents.customer_po_number IS 'Ordem de compra do cliente (NF-e: xPed, 15 caract.). Sai no início do infCpl.';
COMMENT ON COLUMN public.issued_fiscal_documents.customer_buyer_name IS 'Nome do comprador do cliente. Sai no início do infCpl, junto do pedido.';
ALTER TABLE public.issued_fiscal_documents ENABLE ROW LEVEL SECURITY;

-- ── maintenance_plans ──
CREATE TABLE public.maintenance_plans (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  vessel_id uuid NOT NULL,
  name text NOT NULL,
  interval_months integer NOT NULL,
  scope text,
  estimated_value numeric,
  last_service_at date,
  advance_days integer DEFAULT 14 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT maintenance_plans_advance_days_check CHECK (advance_days >= 0 AND advance_days <= 90),
  CONSTRAINT maintenance_plans_interval_months_check CHECK (interval_months >= 1 AND interval_months <= 60),
  CONSTRAINT maintenance_plans_pkey PRIMARY KEY (id)
);
ALTER TABLE public.maintenance_plans ENABLE ROW LEVEL SECURITY;

-- ── marinas ──
CREATE TABLE public.marinas (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  contact_name text,
  phone text,
  email text,
  address_line_1 text,
  city text,
  state text,
  postal_code text,
  country text DEFAULT 'Brazil'::text,
  latitude numeric(10,7),
  longitude numeric(10,7),
  access_notes text,
  billing_notes text,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT marinas_pkey PRIMARY KEY (id)
);
ALTER TABLE public.marinas ENABLE ROW LEVEL SECURITY;

-- ── payables ──
CREATE TABLE public.payables (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  supplier_name text,
  expense_category text,
  description text NOT NULL,
  issue_date date NOT NULL,
  due_date date NOT NULL,
  amount numeric(12,2) NOT NULL,
  currency text DEFAULT 'BRL'::text,
  status text DEFAULT 'pending'::text,
  payment_method text,
  paid_amount numeric(12,2) DEFAULT 0,
  balance_amount numeric(12,2) DEFAULT 0,
  linked_service_order_id uuid,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  supplier_id uuid,
  origin text DEFAULT 'manual'::text,
  bank_transaction_id uuid,
  cost_center_id uuid,
  sub_category character varying,
  fiscal_note_id uuid,
  payee_id uuid,
  CONSTRAINT chk_payables_origin CHECK (origin = ANY (ARRAY['manual'::text, 'service_order_expense'::text, 'bank_reconciliation'::text, 'fiscal_note'::text, 'commission'::text, 'purchase_order'::text, 'folha'::text])),
  CONSTRAINT payables_status_check CHECK (status = ANY (ARRAY['pending'::text, 'partially_paid'::text, 'paid'::text, 'overdue'::text, 'cancelled'::text])),
  CONSTRAINT payables_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.payables.payee_id IS 'Favorecido pessoa física/prestador. Complementar a supplier_id, nunca simultâneo a ele.';
ALTER TABLE public.payables ENABLE ROW LEVEL SECURITY;

-- ── payees ──
CREATE TABLE public.payees (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  kind text DEFAULT 'prestador'::text NOT NULL,
  document text,
  phone text,
  email text,
  pix_key text,
  pix_key_type text,
  bank_name text,
  bank_branch text,
  bank_account text,
  account_type text,
  default_category text,
  notes text,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  commission_percentage numeric(5,2),
  app_user_id uuid,
  CONSTRAINT payees_account_type_check CHECK (account_type = ANY (ARRAY['corrente'::text, 'poupanca'::text, 'pagamento'::text])),
  CONSTRAINT payees_kind_check CHECK (kind = ANY (ARRAY['socio'::text, 'funcionario'::text, 'diarista'::text, 'prestador'::text, 'comissionado'::text])),
  CONSTRAINT payees_pix_key_type_check CHECK (pix_key_type = ANY (ARRAY['cpf'::text, 'cnpj'::text, 'email'::text, 'telefone'::text, 'aleatoria'::text])),
  CONSTRAINT payees_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.payees IS 'Favorecidos que recebem dinheiro sem ser fornecedor nem usuário: sócios, funcionários, diaristas e prestadores.';
COMMENT ON COLUMN public.payees.kind IS 'socio = pró-labore (fora do resultado operacional); funcionario = folha; diarista = apoio pontual; prestador = PJ de serviço; comissionado = recebe percentual sobre venda.';
COMMENT ON COLUMN public.payees.commission_percentage IS 'Percentual habitual de comissão. Padrão para novas vendas; sempre editável na venda.';
COMMENT ON COLUMN public.payees.app_user_id IS 'Conta de acesso desta pessoa, quando ela passar a usar o sistema. Nulo = trabalha e recebe, mas nao acessa. O perfil de pagamento continua apontando para o favorecido: e a identidade de pagamento, e o historico nao muda de dono.';
ALTER TABLE public.payees ENABLE ROW LEVEL SECURITY;

-- ── payment_condition_presets ──
CREATE TABLE public.payment_condition_presets (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  label text NOT NULL,
  sort_order integer DEFAULT 0,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  installments jsonb DEFAULT '[]'::jsonb,
  auto_generate_collections boolean DEFAULT true,
  CONSTRAINT payment_condition_presets_pkey PRIMARY KEY (id)
);
ALTER TABLE public.payment_condition_presets ENABLE ROW LEVEL SECURITY;

-- ── payments ──
CREATE TABLE public.payments (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  receivable_id uuid,
  payable_id uuid,
  payment_date date DEFAULT CURRENT_DATE NOT NULL,
  amount numeric(12,2) NOT NULL,
  payment_method text DEFAULT 'pix'::text NOT NULL,
  installments integer DEFAULT 1,
  card_fee_percent numeric(6,4) DEFAULT 0,
  net_amount numeric(12,2),
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  cancelled_at timestamp with time zone,
  cancellation_reason text,
  status text DEFAULT 'confirmed'::text,
  receipt_url text,
  receipt_storage_path text,
  CONSTRAINT chk_payment_target CHECK (receivable_id IS NOT NULL AND payable_id IS NULL OR receivable_id IS NULL AND payable_id IS NOT NULL),
  CONSTRAINT payments_payment_method_check CHECK (payment_method = ANY (ARRAY['pix'::text, 'credit_card'::text, 'debit_card'::text, 'cash'::text, 'bank_transfer'::text, 'check'::text])),
  CONSTRAINT payments_status_check CHECK (status = ANY (ARRAY['confirmed'::text, 'cancelled'::text])),
  CONSTRAINT payments_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.payments.receipt_url IS 'URL pública do comprovante anexado (bucket expense-receipts).';
COMMENT ON COLUMN public.payments.receipt_storage_path IS 'Caminho do comprovante no storage (para remoção/gestão).';
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

-- ── payroll_lines ──
CREATE TABLE public.payroll_lines (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  payroll_period_id uuid NOT NULL,
  work_profile_id uuid NOT NULL,
  horas_normais numeric(8,2) DEFAULT 0 NOT NULL,
  horas_extras numeric(8,2) DEFAULT 0 NOT NULL,
  horas_noturnas numeric(8,2) DEFAULT 0 NOT NULL,
  horas_domingo numeric(8,2) DEFAULT 0 NOT NULL,
  diarias_inteiras numeric(6,2) DEFAULT 0 NOT NULL,
  diarias_meias numeric(6,2) DEFAULT 0 NOT NULL,
  valor_normais numeric(12,2) DEFAULT 0 NOT NULL,
  valor_extras numeric(12,2) DEFAULT 0 NOT NULL,
  valor_noturnas numeric(12,2) DEFAULT 0 NOT NULL,
  valor_domingo numeric(12,2) DEFAULT 0 NOT NULL,
  valor_diarias numeric(12,2) DEFAULT 0 NOT NULL,
  valor_mensal numeric(12,2) DEFAULT 0 NOT NULL,
  valor_comissoes numeric(12,2) DEFAULT 0 NOT NULL,
  valor_dsr numeric(12,2) DEFAULT 0 NOT NULL,
  descontos numeric(12,2) DEFAULT 0 NOT NULL,
  valor_bruto numeric(12,2) DEFAULT 0 NOT NULL,
  retencoes numeric(12,2) DEFAULT 0 NOT NULL,
  valor_liquido numeric(12,2) DEFAULT 0 NOT NULL,
  nfse_numero text,
  nfse_valor numeric(12,2),
  detalhamento jsonb,
  payable_id uuid,
  observacao text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT payroll_lines_pkey PRIMARY KEY (id),
  CONSTRAINT payroll_lines_uma_por_perfil UNIQUE (payroll_period_id, work_profile_id)
);
COMMENT ON TABLE public.payroll_lines IS 'Apuracao por pessoa no periodo, com a memoria de calculo aberta. payable_id liga no trilho que ja existe (commissions -> payables).';
COMMENT ON COLUMN public.payroll_lines.payable_id IS 'Conta a pagar gerada por este fechamento. Preenchida por gravar_fechamento_de_folha; e o caminho de volta (payable -> quem trabalhou, quando, quantas horas) de que a Fase 5 precisa para o custo real por OS.';
ALTER TABLE public.payroll_lines ENABLE ROW LEVEL SECURITY;

-- ── payroll_periods ──
CREATE TABLE public.payroll_periods (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  de date NOT NULL,
  ate date NOT NULL,
  descricao text,
  status text DEFAULT 'aberto'::text NOT NULL,
  fechado_por uuid,
  fechado_em timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT payroll_periods_intervalo CHECK (ate >= de),
  CONSTRAINT payroll_periods_status_check CHECK (status = ANY (ARRAY['aberto'::text, 'fechado'::text, 'pago'::text])),
  CONSTRAINT payroll_periods_pkey PRIMARY KEY (id)
);
ALTER TABLE public.payroll_periods ENABLE ROW LEVEL SECURITY;

-- ── periodos_fechados ──
CREATE TABLE public.periodos_fechados (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  ano integer NOT NULL,
  mes integer NOT NULL,
  fechado_em timestamp with time zone DEFAULT now() NOT NULL,
  fechado_por uuid,
  reaberto_em timestamp with time zone,
  reaberto_por uuid,
  motivo_da_reabertura text,
  CONSTRAINT periodos_fechados_mes_check CHECK (mes >= 1 AND mes <= 12),
  CONSTRAINT periodos_fechados_pkey PRIMARY KEY (id),
  CONSTRAINT periodos_fechados_ano_mes_key UNIQUE (ano, mes)
);
ALTER TABLE public.periodos_fechados ENABLE ROW LEVEL SECURITY;

-- ── pluggy_amostra_payload ──
CREATE TABLE public.pluggy_amostra_payload (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  bank_ref_id text NOT NULL,
  source_type text NOT NULL,
  payload jsonb NOT NULL,
  colhida_em timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT pluggy_amostra_payload_pkey PRIMARY KEY (id)
);
ALTER TABLE public.pluggy_amostra_payload ENABLE ROW LEVEL SECURITY;

-- ── price_update_suggestions ──
CREATE TABLE public.price_update_suggestions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  product_id uuid,
  fiscal_note_id uuid,
  current_sale_price numeric,
  suggested_sale_price numeric,
  margin_percent numeric,
  status text DEFAULT 'pending'::text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT price_update_suggestions_pkey PRIMARY KEY (id)
);
ALTER TABLE public.price_update_suggestions ENABLE ROW LEVEL SECURITY;

-- ── product_aliases ──
CREATE TABLE public.product_aliases (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  alias_normalized text NOT NULL,
  alias_original text NOT NULL,
  product_id uuid NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT product_aliases_pkey PRIMARY KEY (id),
  CONSTRAINT product_aliases_alias_normalized_key UNIQUE (alias_normalized)
);
ALTER TABLE public.product_aliases ENABLE ROW LEVEL SECURITY;

-- ── product_categories ──
CREATE TABLE public.product_categories (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  description text,
  default_profit_margin numeric(6,4) DEFAULT 30,
  default_commission_rate numeric(6,4) DEFAULT 0,
  is_commissionable boolean DEFAULT true,
  default_csosn text DEFAULT '400'::text,
  default_fiscal_origin integer DEFAULT 0,
  default_ncm text,
  default_icms_rate numeric(6,4) DEFAULT 0,
  default_ipi_rate numeric(6,4) DEFAULT 0,
  default_pis_rate numeric(6,4) DEFAULT 0,
  default_cofins_rate numeric(6,4) DEFAULT 0,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT product_categories_pkey PRIMARY KEY (id),
  CONSTRAINT product_categories_name_key UNIQUE (name)
);
ALTER TABLE public.product_categories ENABLE ROW LEVEL SECURITY;

-- ── product_components ──
CREATE TABLE public.product_components (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  parent_product_id uuid NOT NULL,
  component_product_id uuid NOT NULL,
  quantity numeric DEFAULT 1 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT product_components_no_self CHECK (parent_product_id <> component_product_id),
  CONSTRAINT product_components_quantity_check CHECK (quantity > 0::numeric),
  CONSTRAINT product_components_pkey PRIMARY KEY (id),
  CONSTRAINT product_components_parent_product_id_component_product_id_key UNIQUE (parent_product_id, component_product_id)
);
ALTER TABLE public.product_components ENABLE ROW LEVEL SECURITY;

-- ── product_price_history ──
CREATE TABLE public.product_price_history (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  product_id uuid,
  old_cost numeric,
  new_cost numeric,
  fiscal_note_id uuid,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT product_price_history_pkey PRIMARY KEY (id)
);
ALTER TABLE public.product_price_history ENABLE ROW LEVEL SECURITY;

-- ── product_suppliers ──
CREATE TABLE public.product_suppliers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  product_id uuid NOT NULL,
  supplier_id uuid NOT NULL,
  supplier_sku text,
  cost_price numeric(12,2),
  currency text DEFAULT 'BRL'::text,
  lead_time_days integer,
  minimum_order_qty numeric(10,3) DEFAULT 1,
  is_preferred boolean DEFAULT false,
  last_purchase_date date,
  last_purchase_price numeric(12,2),
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT product_suppliers_pkey PRIMARY KEY (id),
  CONSTRAINT product_suppliers_product_id_supplier_id_key UNIQUE (product_id, supplier_id)
);
ALTER TABLE public.product_suppliers ENABLE ROW LEVEL SECURITY;

-- ── products ──
CREATE TABLE public.products (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  sku text,
  name text NOT NULL,
  category text,
  brand text,
  unit text DEFAULT 'pcs'::text,
  cost_price numeric(12,2) DEFAULT 0,
  sale_price numeric(12,2) DEFAULT 0,
  cost_currency text DEFAULT 'BRL'::text,
  sale_currency text DEFAULT 'BRL'::text,
  stock_quantity numeric(10,3) DEFAULT 0,
  minimum_stock numeric(10,3) DEFAULT 0,
  location_bin text,
  barcode text,
  notes text,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  ncm text,
  csosn text DEFAULT '400'::text,
  fiscal_origin integer DEFAULT 0,
  icms_rate numeric(6,4) DEFAULT 0,
  ipi_rate numeric(6,4) DEFAULT 0,
  pis_rate numeric(6,4) DEFAULT 0,
  cofins_rate numeric(6,4) DEFAULT 0,
  commission_rate numeric(6,4) DEFAULT 0,
  profit_margin numeric(6,4) DEFAULT 0,
  use_global_fiscal boolean DEFAULT true,
  product_category_id uuid,
  is_commissionable boolean DEFAULT true,
  image_url text,
  fiscal_complete boolean DEFAULT true NOT NULL,
  default_warranty_days integer DEFAULT 0,
  last_stock_entry_at timestamp with time zone,
  supplier_id uuid,
  cfop text DEFAULT '5102'::text,
  product_type text DEFAULT 'simples'::text NOT NULL,
  reserved_quantity numeric DEFAULT 0 NOT NULL,
  is_equipment boolean,
  vende_isolado boolean DEFAULT true NOT NULL,
  conductor_mm2 numeric,
  conductor_insulation_c integer,
  CONSTRAINT products_conductor_insulation_c_check CHECK (conductor_insulation_c = ANY (ARRAY[75, 90, 105])),
  CONSTRAINT products_conductor_mm2_check CHECK (conductor_mm2 > 0::numeric),
  CONSTRAINT products_product_type_check CHECK (product_type = ANY (ARRAY['simples'::text, 'kit'::text, 'composto'::text])),
  CONSTRAINT products_pkey PRIMARY KEY (id),
  CONSTRAINT products_sku_key UNIQUE (sku)
);
COMMENT ON COLUMN public.products.vende_isolado IS 'Produto que se vende isoladamente. false = complementar de sistema (cabo, sensor, interface, fusível, suporte): aparece em orçamento e no leve-junto, mas nunca vira oferta avulsa na curadoria de promoção.';
COMMENT ON COLUMN public.products.conductor_mm2 IS 'Seção do condutor, em mm². Só para cabo de potência de UM condutor vendido por
   metro — é o que permite escolher o cabo pela bitola que o dimensionamento
   apontou. Cabo multipolar, de dados ou kit deixa nulo.';
COMMENT ON COLUMN public.products.conductor_insulation_c IS 'Temperatura da isolação (75, 90 ou 105 °C), como consta na especificação do
   fabricante. Política da HBR (19/08/2026): 90 °C para cabo até 16 mm²,
   105 °C a partir de 25 mm². NÃO deduzir fora dessa política: é ela que decide
   quanta corrente o cabo admite, e errar para cima libera bitola que o cabo não
   aguenta.';
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- ── products_stock_backup_pre_v2 ──
CREATE TABLE public.products_stock_backup_pre_v2 (
  id uuid,
  stock_quantity numeric(10,3),
  reserved_quantity numeric,
  backed_up_at timestamp with time zone
);
ALTER TABLE public.products_stock_backup_pre_v2 ENABLE ROW LEVEL SECURITY;

-- ── purchase_order_items ──
CREATE TABLE public.purchase_order_items (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  purchase_order_id uuid NOT NULL,
  product_id uuid,
  description text NOT NULL,
  quantity numeric(10,3) DEFAULT 1 NOT NULL,
  unit_cost numeric(12,2) DEFAULT 0 NOT NULL,
  received_qty numeric(10,3) DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT purchase_order_items_pkey PRIMARY KEY (id)
);
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;

-- ── purchase_orders ──
CREATE TABLE public.purchase_orders (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  po_number text NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  supplier_id uuid,
  service_order_id uuid,
  expected_date date,
  received_date date,
  notes text,
  total_amount numeric(12,2) DEFAULT 0 NOT NULL,
  created_by text DEFAULT 'sistema'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  payable_id uuid,
  CONSTRAINT purchase_orders_status_check CHECK (status = ANY (ARRAY['draft'::text, 'sent'::text, 'partial'::text, 'received'::text, 'cancelled'::text])),
  CONSTRAINT purchase_orders_pkey PRIMARY KEY (id),
  CONSTRAINT purchase_orders_po_number_key UNIQUE (po_number)
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

-- ── push_subscriptions ──
CREATE TABLE public.push_subscriptions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  user_id uuid NOT NULL,
  endpoint text NOT NULL,
  p256dh text NOT NULL,
  auth text NOT NULL,
  user_agent text,
  CONSTRAINT push_subscriptions_pkey PRIMARY KEY (id),
  CONSTRAINT push_subscriptions_endpoint_key UNIQUE (endpoint)
);
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

-- ── quote_request_items ──
CREATE TABLE public.quote_request_items (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  quote_request_id uuid NOT NULL,
  product_id uuid,
  description text NOT NULL,
  quantity numeric(12,3) DEFAULT 1 NOT NULL,
  service_order_part_id uuid,
  service_order_service_id uuid,
  position integer DEFAULT 1 NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT quote_request_items_pkey PRIMARY KEY (id)
);
ALTER TABLE public.quote_request_items ENABLE ROW LEVEL SECURITY;

-- ── quote_request_sends ──
CREATE TABLE public.quote_request_sends (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  quote_request_id uuid NOT NULL,
  supplier_id uuid NOT NULL,
  phone_normalized text NOT NULL,
  queue_id uuid,
  channel text DEFAULT 'whatsapp'::text NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT quote_request_sends_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.quote_request_sends IS 'Cada tentativa REAL de envio de uma cotacao a um fornecedor. O status vive em whatsapp_send_queue (via queue_id) — aqui fica so o vinculo, para nao existir duas versoes da mesma verdade.';
COMMENT ON COLUMN public.quote_request_sends.queue_id IS 'Linha da fila que carrega esta mensagem. O worker atualiza status/failed_reason la; a tela le por juncao.';
ALTER TABLE public.quote_request_sends ENABLE ROW LEVEL SECURITY;

-- ── quote_requests ──
CREATE TABLE public.quote_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  code text NOT NULL,
  service_order_id uuid,
  status text DEFAULT 'open'::text NOT NULL,
  sent_supplier_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  closed_at timestamp with time zone,
  CONSTRAINT chk_qr_status CHECK (status = ANY (ARRAY['open'::text, 'closed'::text, 'cancelled'::text])),
  CONSTRAINT quote_requests_pkey PRIMARY KEY (id),
  CONSTRAINT quote_requests_code_key UNIQUE (code)
);
COMMENT ON TABLE public.quote_requests IS 'Cotações a fornecedores (COT-). Acesso restrito a admin/financeiro pela RLS.';
ALTER TABLE public.quote_requests ENABLE ROW LEVEL SECURITY;

-- ── quote_responses ──
CREATE TABLE public.quote_responses (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  quote_request_id uuid NOT NULL,
  supplier_id uuid NOT NULL,
  quote_request_item_id uuid,
  unit_price numeric(12,2),
  lead_time_days integer,
  source text DEFAULT 'text'::text NOT NULL,
  source_excerpt text,
  confirmed boolean DEFAULT false NOT NULL,
  whatsapp_message_id text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT chk_qresp_source CHECK (source = ANY (ARRAY['text'::text, 'audio'::text, 'pdf'::text, 'image'::text, 'manual'::text])),
  CONSTRAINT quote_responses_pkey PRIMARY KEY (id)
);
ALTER TABLE public.quote_responses ENABLE ROW LEVEL SECURITY;

-- ── receivables ──
CREATE TABLE public.receivables (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  client_id uuid NOT NULL,
  invoice_id uuid,
  service_order_id uuid,
  description text NOT NULL,
  issue_date date NOT NULL,
  due_date date NOT NULL,
  amount numeric(12,2) NOT NULL,
  currency text DEFAULT 'BRL'::text,
  status text DEFAULT 'pending'::text,
  payment_method text,
  paid_amount numeric(12,2) DEFAULT 0,
  balance_amount numeric(12,2) DEFAULT 0,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  category text,
  cost_center_id uuid,
  sub_category character varying,
  is_deposit boolean DEFAULT false,
  reminder_sent_at timestamp with time zone,
  issued_fiscal_document_id uuid,
  due_on_completion boolean DEFAULT false NOT NULL,
  bank_transaction_id uuid,
  CONSTRAINT receivables_status_check CHECK (status = ANY (ARRAY['pending'::text, 'partially_paid'::text, 'paid'::text, 'overdue'::text, 'cancelled'::text])),
  CONSTRAINT receivables_pkey PRIMARY KEY (id)
);
ALTER TABLE public.receivables ENABLE ROW LEVEL SECURITY;

-- ── reconciliation_log ──
CREATE TABLE public.reconciliation_log (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  ocorrido_em timestamp with time zone DEFAULT now() NOT NULL,
  autor uuid,
  acao text NOT NULL,
  bank_transaction_id uuid,
  payable_id uuid,
  receivable_id uuid,
  finance_rule_id uuid,
  valor numeric(14,2),
  detalhe text,
  antes jsonb,
  depois jsonb,
  CONSTRAINT reconciliation_log_pkey PRIMARY KEY (id)
);
ALTER TABLE public.reconciliation_log ENABLE ROW LEVEL SECURITY;

-- ── reconciliation_memory ──
CREATE TABLE public.reconciliation_memory (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  statement_key text NOT NULL,
  client_id uuid,
  candidate_kind text,
  hits integer DEFAULT 1 NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT reconciliation_memory_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.reconciliation_memory IS 'Aprendizado da conciliacao: liga a assinatura do historico bancario ao cliente confirmado pelo operador.';
COMMENT ON COLUMN public.reconciliation_memory.statement_key IS 'Tokens identificadores do historico, normalizados e ordenados. Ver statementSignature em _shared/banking/matching.ts.';
COMMENT ON COLUMN public.reconciliation_memory.hits IS 'Quantas vezes essa ligacao foi confirmada. Mais confirmacoes, mais confianca no casamento.';
ALTER TABLE public.reconciliation_memory ENABLE ROW LEVEL SECURITY;

-- ── reparo_coremma_20260805 ──
CREATE TABLE public.reparo_coremma_20260805 (
  id uuid,
  supplier_name text,
  expense_category text,
  description text,
  issue_date date,
  due_date date,
  amount numeric(12,2),
  currency text,
  status text,
  payment_method text,
  paid_amount numeric(12,2),
  balance_amount numeric(12,2),
  linked_service_order_id uuid,
  notes text,
  created_at timestamp with time zone,
  updated_at timestamp with time zone,
  supplier_id uuid,
  origin text,
  bank_transaction_id uuid,
  cost_center_id uuid,
  sub_category character varying,
  fiscal_note_id uuid,
  payee_id uuid,
  reparado_em timestamp with time zone
);
COMMENT ON TABLE public.reparo_coremma_20260805 IS 'Cópia das 82 despesas atribuídas por engano à Coremma (nome fantasia "Itajai" casava com qualquer estabelecimento de Itajaí). Devolvidas à fila em 05/08/2026 para reclassificação.';
ALTER TABLE public.reparo_coremma_20260805 ENABLE ROW LEVEL SECURITY;

-- ── saved_filters ──
CREATE TABLE public.saved_filters (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  filter_type text NOT NULL,
  filter_config jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  user_id uuid,
  is_default boolean DEFAULT false NOT NULL,
  CONSTRAINT saved_filters_filter_type_check CHECK (filter_type = ANY (ARRAY['payable'::text, 'receivable'::text, 'service_orders'::text, 'quotes'::text, 'products'::text, 'vessels'::text, 'agenda'::text, 'clients'::text, 'suppliers'::text, 'marinas'::text, 'services'::text, 'inventory'::text, 'purchase_orders'::text, 'collections'::text, 'crm'::text, 'external_quotes'::text, 'whatsapp_leads'::text, 'whatsapp_scheduled'::text, 'whatsapp_logs'::text])),
  CONSTRAINT saved_filters_pkey PRIMARY KEY (id)
);
ALTER TABLE public.saved_filters ENABLE ROW LEVEL SECURITY;

-- ── service_cases ──
CREATE TABLE public.service_cases (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  service_order_id uuid NOT NULL,
  service_id uuid,
  vessel_id uuid,
  client_id uuid,
  marina_id uuid,
  asset_type text,
  features jsonb DEFAULT '{}'::jsonb NOT NULL,
  planned_minutes integer,
  actual_minutes integer,
  materials_cost numeric(12,2),
  parts_used jsonb,
  variance_pct numeric(6,2),
  outcome text,
  usable boolean DEFAULT true NOT NULL,
  unusable_reason text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT service_cases_outcome_check CHECK (outcome = ANY (ARRAY['dentro'::text, 'estourou'::text, 'sobrou'::text])),
  CONSTRAINT service_cases_pkey PRIMARY KEY (id),
  CONSTRAINT service_cases_os_uk UNIQUE (service_order_id, service_id)
);
ALTER TABLE public.service_cases ENABLE ROW LEVEL SECURITY;

-- ── service_fiscal_verbs ──
CREATE TABLE public.service_fiscal_verbs (
  verb_slug text NOT NULL,
  default_national_tax_code text,
  default_service_code text,
  default_cnae text,
  default_iss_rate numeric,
  default_iss_withheld boolean DEFAULT false NOT NULL,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT sfv_cnae_formato CHECK (default_cnae IS NULL OR default_cnae ~ '^[0-9]{7}$'::text),
  CONSTRAINT sfv_iss_rate_faixa CHECK (default_iss_rate IS NULL OR default_iss_rate >= 0::numeric AND default_iss_rate <= 100::numeric),
  CONSTRAINT sfv_national_tax_code_formato CHECK (default_national_tax_code IS NULL OR default_national_tax_code ~ '^[0-9]{6}$'::text),
  CONSTRAINT service_fiscal_verbs_pkey PRIMARY KEY (verb_slug)
);
COMMENT ON TABLE public.service_fiscal_verbs IS 'Cadastro fiscal por verbo de servico. O servico herda daqui quando nao tem valor proprio
   (ver public.resolve_service_fiscal). Dez linhas — contra 243 se fosse por servico.';
COMMENT ON COLUMN public.service_fiscal_verbs.default_national_tax_code IS 'Codigo de tributacao NACIONAL, 6 digitos sem pontuacao (ex.: 140101). Evita E0310. NAO e o
   municipal sem os pontos: "14.01" corresponde a 140101, nao a 140100.';
COMMENT ON COLUMN public.service_fiscal_verbs.default_iss_rate IS 'Aliquota de ISS em PERCENTUAL (5 = 5%), nao fracao. E a aliquota de Itajai — so a
   contabilidade sabe.';
COMMENT ON COLUMN public.service_fiscal_verbs.notes IS 'Onde a contabilidade registra por que este codigo, e nao outro. E o unico lugar em que essa
   justificativa fica gravada.';
ALTER TABLE public.service_fiscal_verbs ENABLE ROW LEVEL SECURITY;

-- ── service_order_expenses ──
CREATE TABLE public.service_order_expenses (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  service_order_id uuid,
  category text NOT NULL,
  description text NOT NULL,
  amount numeric(12,2) NOT NULL,
  currency text DEFAULT 'BRL'::text,
  expense_date date DEFAULT CURRENT_DATE NOT NULL,
  paid_by text DEFAULT 'company'::text NOT NULL,
  technician_user_id uuid,
  reimbursed boolean DEFAULT false,
  reimbursed_at timestamp with time zone,
  reimbursed_payment_id uuid,
  receipt_url text,
  linked_payable_id uuid,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  supplier_id uuid,
  receipt_storage_path text,
  billable_to_client boolean DEFAULT true NOT NULL,
  CONSTRAINT service_order_expenses_paid_by_check CHECK (paid_by = ANY (ARRAY['company'::text, 'technician'::text])),
  CONSTRAINT service_order_expenses_pkey PRIMARY KEY (id)
);
ALTER TABLE public.service_order_expenses ENABLE ROW LEVEL SECURITY;

-- ── service_order_parts ──
CREATE TABLE public.service_order_parts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  service_order_id uuid NOT NULL,
  product_id uuid NOT NULL,
  quantity numeric(10,3) NOT NULL,
  unit_cost_snapshot numeric(12,2) NOT NULL,
  unit_sale_snapshot numeric(12,2) NOT NULL,
  currency_snapshot text DEFAULT 'BRL'::text,
  line_total_cost numeric(12,2) NOT NULL,
  line_total_sale numeric(12,2) NOT NULL,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  warranty_days integer DEFAULT 0,
  warranty_months integer DEFAULT 0,
  warranty_expires_at date,
  serial_number text,
  discount_pct numeric(5,2) DEFAULT 0 NOT NULL,
  discount_amount numeric(12,2) DEFAULT 0 NOT NULL,
  source text DEFAULT 'manual'::text NOT NULL,
  service_order_service_id uuid,
  CONSTRAINT service_order_parts_source_check CHECK (source = ANY (ARRAY['manual'::text, 'kit'::text, 'survey'::text, 'ai'::text, 'extra'::text])),
  CONSTRAINT service_order_parts_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.service_order_parts.source IS 'manual = lançado à mão; kit = veio do kit do serviço; survey = saiu do levantamento; ai = sugerido pela IA; extra = descoberto durante a execução.';
ALTER TABLE public.service_order_parts ENABLE ROW LEVEL SECURITY;

-- ── service_order_photos ──
CREATE TABLE public.service_order_photos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  service_order_id uuid NOT NULL,
  uploaded_by uuid,
  storage_path text NOT NULL,
  public_url text NOT NULL,
  caption text,
  photo_type text DEFAULT 'progress'::text NOT NULL,
  step_id uuid,
  captured_live boolean DEFAULT false NOT NULL,
  CONSTRAINT service_order_photos_photo_type_check CHECK (photo_type = ANY (ARRAY['before'::text, 'progress'::text, 'after'::text, 'problem'::text])),
  CONSTRAINT service_order_photos_pkey PRIMARY KEY (id)
);
ALTER TABLE public.service_order_photos ENABLE ROW LEVEL SECURITY;

-- ── service_order_services ──
CREATE TABLE public.service_order_services (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  service_order_id uuid NOT NULL,
  service_id uuid,
  name_snapshot text NOT NULL,
  description_snapshot text,
  billing_unit_snapshot text DEFAULT 'hour'::text NOT NULL,
  quantity numeric(10,3) DEFAULT 1 NOT NULL,
  unit_price_snapshot numeric(12,2) DEFAULT 0 NOT NULL,
  line_total numeric(12,2) DEFAULT 0 NOT NULL,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  technician_user_id uuid,
  warranty_days integer DEFAULT 0,
  warranty_months integer DEFAULT 0,
  warranty_expires_at date,
  started_at timestamp with time zone,
  finished_at timestamp with time zone,
  elapsed_minutes integer DEFAULT 0,
  discount_pct numeric(5,2) DEFAULT 0 NOT NULL,
  discount_amount numeric(12,2) DEFAULT 0 NOT NULL,
  service_system text,
  service_verb text,
  fiscal_verb text,
  CONSTRAINT service_order_services_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.service_order_services.service_system IS 'Sistema que ESTA linha toca. Sobrepõe o do catálogo — é assim que um serviço
   genérico ("diagnóstico no local") vira elétrico numa OS e gás na seguinte.
   Nulo = usa o do serviço.';
COMMENT ON COLUMN public.service_order_services.service_verb IS 'Verbo desta linha. Sobrepõe o do catálogo e, em linha de texto livre (sem
   service_id), é a única fonte — é ele que traz o corpo do roteiro.';
COMMENT ON COLUMN public.service_order_services.fiscal_verb IS 'Verbo fiscal DESTA LINHA, para quando não há serviço de catálogo por trás
   (linha digitada à mão). É FALLBACK: só vale quando o catálogo não resolve o
   código de tributação — verbo genérico não passa por cima do cadastro que a
   contabilidade fez. Os dez verbos têm hoje valores idênticos (14.01 / ISS 3%),
   então escolhê-lo não altera imposto: ele liga a herança que já existe.';
ALTER TABLE public.service_order_services ENABLE ROW LEVEL SECURITY;

-- ── service_order_signatures ──
CREATE TABLE public.service_order_signatures (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  service_order_id uuid NOT NULL,
  share_token uuid NOT NULL,
  signature_image_url text,
  accepted_name text NOT NULL,
  accepted_terms_snapshot text,
  document_hash text NOT NULL,
  ip_address text,
  user_agent text,
  signed_at timestamp with time zone DEFAULT now() NOT NULL,
  superseded_at timestamp with time zone,
  superseded_reason text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  signed_pdf_url text,
  CONSTRAINT service_order_signatures_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.service_order_signatures.signed_pdf_url IS 'URL publica do PDF da OS no exato estado em que foi assinado pelo cliente. Usado como prova juridica imutavel.';
ALTER TABLE public.service_order_signatures ENABLE ROW LEVEL SECURITY;

-- ── service_order_steps ──
CREATE TABLE public.service_order_steps (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  service_order_id uuid NOT NULL,
  service_order_service_id uuid,
  template_id uuid,
  seq integer NOT NULL,
  block text,
  title text NOT NULL,
  detail text,
  kind text DEFAULT 'do'::text NOT NULL,
  mode text DEFAULT 'do_confirm'::text NOT NULL,
  standard_minutes integer,
  is_killer boolean DEFAULT false NOT NULL,
  requires_photo boolean DEFAULT false NOT NULL,
  requires_measure text,
  measure_unit text,
  measure_value numeric,
  status text DEFAULT 'pending'::text NOT NULL,
  na_reason text,
  blocked_reason_code text,
  blocked_note text,
  assigned_user_id uuid,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  actual_minutes integer,
  origin text DEFAULT 'template'::text NOT NULL,
  ai_confidence numeric(3,2),
  ai_source text,
  approved_by uuid,
  approved_at timestamp with time zone,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  block_key text,
  block_note text,
  CONSTRAINT service_order_steps_ai_confidence_check CHECK (ai_confidence IS NULL OR ai_confidence >= 0::numeric AND ai_confidence <= 1::numeric),
  CONSTRAINT service_order_steps_blocked_needs_reason CHECK (status <> 'blocked'::text OR blocked_reason_code IS NOT NULL),
  CONSTRAINT service_order_steps_kind_check CHECK (kind = ANY (ARRAY['do'::text, 'check'::text, 'safety'::text, 'evidence'::text, 'handoff'::text])),
  CONSTRAINT service_order_steps_mode_check CHECK (mode = ANY (ARRAY['read_do'::text, 'do_confirm'::text])),
  CONSTRAINT service_order_steps_na_needs_reason CHECK (status <> 'not_applicable'::text OR COALESCE(na_reason, ''::text) <> ''::text),
  CONSTRAINT service_order_steps_origin_check CHECK (origin = ANY (ARRAY['template'::text, 'ai'::text, 'manual'::text, 'client_request'::text, 'composed'::text])),
  CONSTRAINT service_order_steps_status_check CHECK (status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'done'::text, 'not_applicable'::text, 'blocked'::text])),
  CONSTRAINT service_order_steps_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.service_order_steps.block_key IS 'Chave estável do bloco (abertura:gas, linha:<uuid>, fechamento:gas). O rótulo
   em `block` muda com a numeração; esta não muda, e é por ela que se deduplica.';
COMMENT ON COLUMN public.service_order_steps.block_note IS 'Linha de escopo do bloco compartilhado: a quais serviços da OS ele se aplica.';
ALTER TABLE public.service_order_steps ENABLE ROW LEVEL SECURITY;

-- ── service_order_technicians ──
CREATE TABLE public.service_order_technicians (
  id uuid DEFAULT gen_random_uuid(),
  service_order_id uuid NOT NULL,
  user_id uuid NOT NULL,
  role_in_order text DEFAULT 'technician'::text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT service_order_technicians_pkey PRIMARY KEY (service_order_id, user_id)
);
ALTER TABLE public.service_order_technicians ENABLE ROW LEVEL SECURITY;

-- ── service_orders ──
CREATE TABLE public.service_orders (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  service_order_number text NOT NULL,
  client_id uuid NOT NULL,
  vessel_id uuid NOT NULL,
  marina_id uuid,
  requested_by_name text,
  scheduled_start_at timestamp with time zone,
  scheduled_end_at timestamp with time zone,
  check_in_at timestamp with time zone,
  check_out_at timestamp with time zone,
  status text DEFAULT 'draft'::text NOT NULL,
  priority text DEFAULT 'normal'::text NOT NULL,
  service_type text,
  problem_description text,
  initial_findings text,
  diagnosis text,
  solution_applied text,
  technician_notes text,
  internal_notes text,
  customer_visible_report text,
  hourly_rate numeric(10,2) DEFAULT 0,
  estimated_hours numeric(8,2) DEFAULT 0,
  labor_hours_total numeric(8,2) DEFAULT 0,
  labor_cost_total numeric(12,2) DEFAULT 0,
  travel_distance_km numeric(8,2) DEFAULT 0,
  travel_cost_per_km numeric(8,2) DEFAULT 0,
  technician_count_for_travel integer DEFAULT 1,
  travel_cost_total numeric(12,2) DEFAULT 0,
  parts_cost_total numeric(12,2) DEFAULT 0,
  subcontract_cost_total numeric(12,2) DEFAULT 0,
  discount_amount numeric(12,2) DEFAULT 0,
  tax_amount numeric(12,2) DEFAULT 0,
  grand_total numeric(12,2) DEFAULT 0,
  currency text DEFAULT 'BRL'::text,
  invoicing_status text DEFAULT 'not_invoiced'::text,
  payment_status text DEFAULT 'unpaid'::text,
  client_signature_url text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  operational_cost_total numeric(12,2) DEFAULT 0,
  cancelled_at timestamp with time zone,
  cancellation_reason text,
  reopened_at timestamp with time zone,
  reopen_reason text,
  commission_rate numeric(6,4) DEFAULT 0,
  commission_amount numeric(12,2) DEFAULT 0,
  commissioned_person text,
  extra_notes text,
  commissioned_user_id uuid,
  quote_validity_days integer DEFAULT 15,
  quote_validity_date date,
  requested_by_contact_id uuid,
  payment_conditions text,
  share_token uuid DEFAULT gen_random_uuid(),
  signed_at timestamp with time zone,
  signed_document_hash text,
  signed_by_name text,
  requires_resignature boolean DEFAULT false NOT NULL,
  resignature_requested_at timestamp with time zone,
  payment_condition_preset_id uuid,
  payment_method text,
  card_installments integer DEFAULT 1,
  travel_hours numeric DEFAULT 0,
  ferry_cost numeric DEFAULT 0,
  travel_type text DEFAULT 'comercial'::text,
  photos jsonb DEFAULT '[]'::jsonb,
  reminder_sent_at timestamp with time zone,
  discount_services_pct numeric(5,2) DEFAULT 0 NOT NULL,
  discount_parts_pct numeric(5,2) DEFAULT 0 NOT NULL,
  converted_to_os_at timestamp with time zone,
  quote_status text DEFAULT 'draft'::text,
  payment_method_preferred text,
  financial_notes text,
  original_quote_amount numeric(12,2),
  is_travel_billable boolean DEFAULT true NOT NULL,
  card_fee_passthrough_enabled boolean DEFAULT false NOT NULL,
  card_fee_amount numeric(12,2) DEFAULT 0 NOT NULL,
  custom_payment_installments jsonb,
  customer_po_number text,
  customer_buyer_name text,
  survey_id uuid,
  estimate_confidence text,
  contingency_pct numeric(5,2),
  CONSTRAINT service_orders_estimate_confidence_check CHECK (estimate_confidence IS NULL OR (estimate_confidence = ANY (ARRAY['alta'::text, 'media'::text, 'baixa'::text]))),
  CONSTRAINT service_orders_invoicing_status_check CHECK (invoicing_status = ANY (ARRAY['not_invoiced'::text, 'invoiced'::text, 'partially_invoiced'::text])),
  CONSTRAINT service_orders_payment_status_check CHECK (payment_status = ANY (ARRAY['unpaid'::text, 'partially_paid'::text, 'paid'::text])),
  CONSTRAINT service_orders_priority_check CHECK (priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text])),
  CONSTRAINT service_orders_quote_status_check CHECK (quote_status = ANY (ARRAY['draft'::text, 'sent'::text, 'awaiting_approval'::text, 'approved'::text, 'awaiting_deposit'::text, 'rejected'::text])),
  CONSTRAINT service_orders_service_type_check CHECK (service_type = ANY (ARRAY['diagnosis'::text, 'repair'::text, 'installation'::text, 'preventive_maintenance'::text, 'consulting'::text, 'engineering_project'::text, 'commissioning'::text, 'inspection'::text])),
  CONSTRAINT service_orders_status_check CHECK (status = ANY (ARRAY['draft'::text, 'scheduled'::text, 'open'::text, 'in_progress'::text, 'awaiting_parts'::text, 'awaiting_client'::text, 'approved'::text, 'completed'::text, 'invoiced'::text, 'cancelled'::text])),
  CONSTRAINT service_orders_travel_type_check CHECK (travel_type = ANY (ARRAY['comercial'::text, 'urgencia'::text, 'fds_feriado'::text])),
  CONSTRAINT service_orders_pkey PRIMARY KEY (id),
  CONSTRAINT service_orders_service_order_number_key UNIQUE (service_order_number),
  CONSTRAINT service_orders_share_token_key UNIQUE (share_token)
);
COMMENT ON COLUMN public.service_orders.customer_po_number IS 'Ordem de compra do cliente, capturada na OS/orçamento e levada à emissão da NF-e.';
COMMENT ON COLUMN public.service_orders.customer_buyer_name IS 'Comprador informado pelo cliente; default do campo Comprador na emissão da NF-e.';
ALTER TABLE public.service_orders ENABLE ROW LEVEL SECURITY;

-- ── service_step_blocks ──
CREATE TABLE public.service_step_blocks (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  block_role text NOT NULL,
  applies_to_system text,
  applies_to_verb text,
  seq integer NOT NULL,
  title text NOT NULL,
  detail text,
  kind text DEFAULT 'do'::text NOT NULL,
  mode text DEFAULT 'do_confirm'::text NOT NULL,
  standard_minutes integer,
  is_killer boolean DEFAULT false NOT NULL,
  requires_photo boolean DEFAULT false NOT NULL,
  requires_measure text,
  measure_unit text,
  origin text DEFAULT 'manual'::text NOT NULL,
  approved_by uuid,
  approved_at timestamp with time zone,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT block_ai_precisa_aprovacao CHECK (origin <> 'ai'::text OR NOT active OR approved_by IS NOT NULL),
  CONSTRAINT block_tem_eixo CHECK ((block_role = ANY (ARRAY['abertura'::text, 'fechamento'::text])) AND applies_to_system IS NOT NULL OR block_role = 'corpo'::text AND applies_to_verb IS NOT NULL),
  CONSTRAINT service_step_blocks_block_role_check CHECK (block_role = ANY (ARRAY['abertura'::text, 'corpo'::text, 'fechamento'::text])),
  CONSTRAINT service_step_blocks_kind_check CHECK (kind = ANY (ARRAY['do'::text, 'check'::text, 'safety'::text, 'evidence'::text, 'handoff'::text])),
  CONSTRAINT service_step_blocks_mode_check CHECK (mode = ANY (ARRAY['read_do'::text, 'do_confirm'::text])),
  CONSTRAINT service_step_blocks_origin_check CHECK (origin = ANY (ARRAY['manual'::text, 'ai'::text])),
  CONSTRAINT service_step_blocks_pkey PRIMARY KEY (id)
);
ALTER TABLE public.service_step_blocks ENABLE ROW LEVEL SECURITY;

-- ── service_step_templates ──
CREATE TABLE public.service_step_templates (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  service_id uuid NOT NULL,
  seq integer NOT NULL,
  block text,
  title text NOT NULL,
  detail text,
  kind text DEFAULT 'do'::text NOT NULL,
  mode text DEFAULT 'do_confirm'::text NOT NULL,
  standard_minutes integer,
  is_killer boolean DEFAULT false NOT NULL,
  requires_photo boolean DEFAULT false NOT NULL,
  requires_measure text,
  measure_unit text,
  requires_part boolean DEFAULT false NOT NULL,
  role_hint text,
  origin text DEFAULT 'manual'::text NOT NULL,
  approved_by uuid,
  approved_at timestamp with time zone,
  version integer DEFAULT 1 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT service_step_templates_ai_needs_approval CHECK (origin <> 'ai'::text OR NOT active OR approved_by IS NOT NULL),
  CONSTRAINT service_step_templates_kind_check CHECK (kind = ANY (ARRAY['do'::text, 'check'::text, 'safety'::text, 'evidence'::text, 'handoff'::text])),
  CONSTRAINT service_step_templates_mode_check CHECK (mode = ANY (ARRAY['read_do'::text, 'do_confirm'::text])),
  CONSTRAINT service_step_templates_origin_check CHECK (origin = ANY (ARRAY['manual'::text, 'ai'::text])),
  CONSTRAINT service_step_templates_standard_minutes_check CHECK (standard_minutes IS NULL OR standard_minutes > 0),
  CONSTRAINT service_step_templates_pkey PRIMARY KEY (id),
  CONSTRAINT service_step_templates_seq_uk UNIQUE (service_id, version, seq)
);
ALTER TABLE public.service_step_templates ENABLE ROW LEVEL SECURITY;

-- ── service_survey_answers ──
CREATE TABLE public.service_survey_answers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  survey_id uuid NOT NULL,
  template_id uuid,
  seq integer NOT NULL,
  question_snapshot text NOT NULL,
  answer_value text,
  answer_json jsonb,
  photo_path text,
  skipped_reason text,
  answered_at timestamp with time zone DEFAULT now() NOT NULL,
  numeric_value numeric,
  answer_unit text,
  CONSTRAINT service_survey_answers_pkey PRIMARY KEY (id),
  CONSTRAINT service_survey_answers_uk UNIQUE (survey_id, seq)
);
COMMENT ON COLUMN public.service_survey_answers.numeric_value IS 'O número, quando a pergunta é de grandeza. O que o dimensionamento e as
   regras de material leem — em vez de garimpar dígito no meio da frase.';
ALTER TABLE public.service_survey_answers ENABLE ROW LEVEL SECURITY;

-- ── service_survey_templates ──
CREATE TABLE public.service_survey_templates (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  service_id uuid,
  seq integer NOT NULL,
  question text NOT NULL,
  help_text text,
  answer_type text DEFAULT 'escolha'::text NOT NULL,
  options jsonb,
  price_impact text DEFAULT 'medio'::text NOT NULL,
  affects text[],
  branch_on jsonb,
  ask_remotely boolean DEFAULT false NOT NULL,
  origin text DEFAULT 'manual'::text NOT NULL,
  approved_by uuid,
  approved_at timestamp with time zone,
  version integer DEFAULT 1 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  applies_to_system text,
  applies_to_verb text,
  expected_unit text,
  min_expected numeric,
  max_expected numeric,
  CONSTRAINT service_survey_templates_ai_needs_approval CHECK (origin <> 'ai'::text OR NOT active OR approved_by IS NOT NULL),
  CONSTRAINT service_survey_templates_answer_type_check CHECK (answer_type = ANY (ARRAY['sim_nao'::text, 'escolha'::text, 'numero'::text, 'texto'::text, 'foto'::text, 'medida'::text])),
  CONSTRAINT service_survey_templates_origin_check CHECK (origin = ANY (ARRAY['manual'::text, 'ai'::text])),
  CONSTRAINT service_survey_templates_price_impact_check CHECK (price_impact = ANY (ARRAY['alto'::text, 'medio'::text, 'baixo'::text])),
  CONSTRAINT survey_tpl_tem_alvo CHECK (service_id IS NOT NULL OR applies_to_system IS NOT NULL OR applies_to_verb IS NOT NULL),
  CONSTRAINT service_survey_templates_pkey PRIMARY KEY (id),
  CONSTRAINT service_survey_templates_seq_uk UNIQUE (service_id, version, seq)
);
COMMENT ON COLUMN public.service_survey_templates.expected_unit IS 'Unidade que a resposta deve ter (m, A, Ah, W, °C, L). Impressa ao lado do
   campo na tela e na folha — "14" sem unidade volta e ninguém sabe se é metro
   ou centímetro, e quem mediu já foi embora.';
COMMENT ON COLUMN public.service_survey_templates.min_expected IS 'Piso do que é plausível. Não barra: avisa. Faixa que barra leitura correta é
   pior que faixa nenhuma — o mundo real tem exceção, e quem está no local vê o
   que o cadastro não previu.';
ALTER TABLE public.service_survey_templates ENABLE ROW LEVEL SECURITY;

-- ── service_surveys ──
CREATE TABLE public.service_surveys (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  service_order_id uuid,
  client_id uuid,
  vessel_id uuid,
  service_id uuid,
  trigger_reason text NOT NULL,
  mode text DEFAULT 'local'::text NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  confidence text,
  confidence_rationale text,
  questions_planned integer,
  questions_asked integer,
  estimated_minutes_p50 integer,
  estimated_minutes_p80 integer,
  contingency_pct numeric(5,2),
  materials_draft jsonb,
  cases_used jsonb,
  share_token text,
  answered_by uuid,
  answered_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT service_surveys_confidence_check CHECK (confidence = ANY (ARRAY['alta'::text, 'media'::text, 'baixa'::text])),
  CONSTRAINT service_surveys_confidence_needs_reason CHECK (confidence IS NULL OR COALESCE(confidence_rationale, ''::text) <> ''::text),
  CONSTRAINT service_surveys_contingency_pct_check CHECK (contingency_pct IS NULL OR contingency_pct >= 0::numeric),
  CONSTRAINT service_surveys_mode_check CHECK (mode = ANY (ARRAY['remoto'::text, 'local'::text])),
  CONSTRAINT service_surveys_status_check CHECK (status = ANY (ARRAY['draft'::text, 'sent'::text, 'answered'::text, 'closed'::text, 'skipped'::text])),
  CONSTRAINT service_surveys_pkey PRIMARY KEY (id),
  CONSTRAINT service_surveys_share_token_key UNIQUE (share_token)
);
ALTER TABLE public.service_surveys ENABLE ROW LEVEL SECURITY;

-- ── service_systems ──
CREATE TABLE public.service_systems (
  slug text NOT NULL,
  name text NOT NULL,
  short_name text,
  is_physical boolean DEFAULT true NOT NULL,
  sort integer DEFAULT 100 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT service_systems_pkey PRIMARY KEY (slug)
);
COMMENT ON TABLE public.service_systems IS 'Catálogo de sistemas (categorias técnicas). O sistema traz a abertura e o
   fechamento de segurança do roteiro; criar um sem escrever esses blocos deixa
   os serviços dele sem preparação — a tela avisa.';
COMMENT ON COLUMN public.service_systems.is_physical IS 'false = não toca sistema físico (mão de obra, frete, fora de escopo). Não
   recebe bloco de abertura porque não há o que desligar.';
ALTER TABLE public.service_systems ENABLE ROW LEVEL SECURITY;

-- ── service_verbs ──
CREATE TABLE public.service_verbs (
  slug text NOT NULL,
  name text NOT NULL,
  intervem_no_sistema boolean DEFAULT true NOT NULL,
  sort integer DEFAULT 100 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT service_verbs_pkey PRIMARY KEY (slug)
);
COMMENT ON TABLE public.service_verbs IS 'Tipos de serviço (o que se faz). O verbo traz o corpo do roteiro; o sistema
   traz a abertura e o fechamento de segurança.';
COMMENT ON COLUMN public.service_verbs.intervem_no_sistema IS 'true = o trabalho mexe no sistema e expõe a energia (elétrica, gás, pressão),
   então recebe a abertura e o fechamento de segurança da categoria.
   false = observa, mede e documenta sem intervir — vai a campo do mesmo jeito,
   mas não há o que desligar. O critério é a exposição, não o lugar.';
ALTER TABLE public.service_verbs ENABLE ROW LEVEL SECURITY;

-- ── services ──
CREATE TABLE public.services (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  description text,
  category text,
  billing_unit text DEFAULT 'hour'::text NOT NULL,
  default_price numeric(12,2) DEFAULT 0,
  currency text DEFAULT 'BRL'::text,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  default_warranty_days integer DEFAULT 0,
  standard_minutes integer,
  standard_source text,
  field_factor numeric(4,2) DEFAULT 1.00 NOT NULL,
  requires_survey boolean DEFAULT false NOT NULL,
  material_kit_product_id uuid,
  supplies_pct numeric(5,2),
  supplies_cap numeric(12,2),
  service_verb text,
  service_system text,
  classified_by text,
  classified_at timestamp with time zone,
  classification_confidence numeric(3,2),
  national_tax_code text,
  service_code text,
  cnae text,
  iss_rate numeric,
  iss_withheld boolean,
  fiscal_verb text,
  CONSTRAINT services_billing_unit_check CHECK (billing_unit = ANY (ARRAY['hour'::text, 'visit'::text, 'day'::text, 'unit'::text])),
  CONSTRAINT services_cnae_formato CHECK (cnae IS NULL OR cnae ~ '^[0-9]{7}$'::text),
  CONSTRAINT services_iss_rate_faixa CHECK (iss_rate IS NULL OR iss_rate >= 0::numeric AND iss_rate <= 100::numeric),
  CONSTRAINT services_national_tax_code_formato CHECK (national_tax_code IS NULL OR national_tax_code ~ '^[0-9]{6}$'::text),
  CONSTRAINT services_standard_source_check CHECK (standard_source IS NULL OR (standard_source = ANY (ARRAY['oem'::text, 'manual'::text, 'historico'::text]))),
  CONSTRAINT services_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.services.supplies_pct IS 'Taxa de materiais de oficina, em % da mão de obra da linha. Referência de mercado: 3 a 8%. Nulo = usa o padrão de app_settings.';
COMMENT ON COLUMN public.services.supplies_cap IS 'Teto em reais da taxa de materiais. Sem teto, percentual em serviço caro vira número sem relação com o consumo real.';
COMMENT ON COLUMN public.services.national_tax_code IS 'Codigo de tributacao NACIONAL, 6 digitos sem pontuacao (ex.: 140101). Obrigatorio no padrao nacional. Nao e o municipal sem os pontos.';
COMMENT ON COLUMN public.services.service_code IS 'Codigo MUNICIPAL do servico, informativo no padrao nacional. Pode ser pontuado (ex.: 01.05.01).';
COMMENT ON COLUMN public.services.cnae IS 'CNAE com 7 digitos, sem pontuacao (ex.: 3313901 = manutencao e reparacao de motores eletricos).';
COMMENT ON COLUMN public.services.iss_rate IS 'Aliquota de ISS em PERCENTUAL (5 = 5%), nao fracao. Para MEI, 0 e aceito quando for o enquadramento.';
COMMENT ON COLUMN public.services.iss_withheld IS 'ISS retido na fonte pelo tomador.';
COMMENT ON COLUMN public.services.fiscal_verb IS 'Verbo FISCAL do servico — de onde ele herda codigo de tributacao, CNAE e ISS. Separado de
   service_verb (que decide o roteiro do tecnico) de proposito: um servico pode estar
   operacionalmente classificado e fiscalmente em branco. NULL = sem heranca; so o valor
   proprio vale.';
ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;

-- ── supplier_product_mappings ──
CREATE TABLE public.supplier_product_mappings (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  supplier_id uuid,
  supplier_sku text NOT NULL,
  supplier_description text,
  internal_product_id uuid,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT supplier_product_mappings_pkey PRIMARY KEY (id),
  CONSTRAINT supplier_product_mappings_supplier_id_supplier_sku_key UNIQUE (supplier_id, supplier_sku)
);
COMMENT ON TABLE public.supplier_product_mappings IS 'Armazena o vínculo entre SKUs de fornecedores (XML) e produtos internos do catálogo.';
ALTER TABLE public.supplier_product_mappings ENABLE ROW LEVEL SECURITY;

-- ── suppliers ──
CREATE TABLE public.suppliers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  trade_name text,
  cnpj_cpf text,
  contact_name text,
  phone text,
  email text,
  website text,
  postal_code text,
  address_line_1 text,
  address_number text,
  address_complement text,
  neighborhood text,
  city text,
  state text,
  country text DEFAULT 'Brazil'::text,
  payment_terms text,
  notes text,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  display_name text,
  communication_tone text,
  opt_out_whatsapp boolean DEFAULT false NOT NULL,
  CONSTRAINT suppliers_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.suppliers.display_name IS 'Nome usado na comunicacao; a razao social nao deve ser usada em saudacao.';
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

-- ── survey_material_rules ──
CREATE TABLE public.survey_material_rules (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  template_id uuid NOT NULL,
  condition_type text DEFAULT 'sempre'::text NOT NULL,
  match_value text,
  min_value numeric,
  max_value numeric,
  product_id uuid NOT NULL,
  qty_mode text DEFAULT 'fixa'::text NOT NULL,
  qty_fixed numeric DEFAULT 1 NOT NULL,
  qty_factor numeric DEFAULT 1 NOT NULL,
  qty_slack_pct numeric DEFAULT 0 NOT NULL,
  qty_round text DEFAULT 'cima'::text NOT NULL,
  rationale text,
  origin text DEFAULT 'ai'::text NOT NULL,
  active boolean DEFAULT false NOT NULL,
  approved_by uuid,
  approved_at timestamp with time zone,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  product_pick text DEFAULT 'fixo'::text NOT NULL,
  CONSTRAINT faixa_precisa_de_limite CHECK (condition_type <> 'faixa'::text OR min_value IS NOT NULL OR max_value IS NOT NULL),
  CONSTRAINT igual_precisa_de_valor CHECK ((condition_type <> ALL (ARRAY['igual'::text, 'contem'::text])) OR match_value IS NOT NULL),
  CONSTRAINT proporcional_precisa_de_fator CHECK (qty_mode = 'fixa'::text OR qty_factor > 0::numeric),
  CONSTRAINT survey_material_rules_condition_type_check CHECK (condition_type = ANY (ARRAY['sempre'::text, 'igual'::text, 'contem'::text, 'faixa'::text, 'sim'::text, 'nao'::text])),
  CONSTRAINT survey_material_rules_origin_check CHECK (origin = ANY (ARRAY['ai'::text, 'human'::text])),
  CONSTRAINT survey_material_rules_product_pick_check CHECK (product_pick = ANY (ARRAY['fixo'::text, 'cabo_por_dimensionamento'::text])),
  CONSTRAINT survey_material_rules_qty_factor_check CHECK (qty_factor >= 0::numeric),
  CONSTRAINT survey_material_rules_qty_fixed_check CHECK (qty_fixed >= 0::numeric),
  CONSTRAINT survey_material_rules_qty_mode_check CHECK (qty_mode = ANY (ARRAY['fixa'::text, 'proporcional'::text, 'por_unidade'::text])),
  CONSTRAINT survey_material_rules_qty_round_check CHECK (qty_round = ANY (ARRAY['nenhum'::text, 'cima'::text, 'meio'::text])),
  CONSTRAINT survey_material_rules_qty_slack_pct_check CHECK (qty_slack_pct >= 0::numeric AND qty_slack_pct <= 100::numeric),
  CONSTRAINT survey_material_rules_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.survey_material_rules IS 'Converte resposta de levantamento em material do orçamento. Entra inativa e
   só vale depois de aprovada na tela — regra de material mexe em preço.';
COMMENT ON COLUMN public.survey_material_rules.product_pick IS 'De onde vem o PRODUTO. "fixo" usa product_id, como sempre.
   "cabo_por_dimensionamento" ignora product_id e pergunta a
   dc_cable_product_for() qual cabo do catálogo atende o circuito deste
   levantamento pelos dois critérios da ABYC. A quantidade continua saindo da
   regra nos dois casos.';
ALTER TABLE public.survey_material_rules ENABLE ROW LEVEL SECURITY;

-- ── task_reminders ──
CREATE TABLE public.task_reminders (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  task_id uuid NOT NULL,
  remind_at timestamp with time zone NOT NULL,
  channel text DEFAULT 'app'::text NOT NULL,
  sent_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT task_reminders_channel_check CHECK (channel = ANY (ARRAY['app'::text, 'whatsapp'::text])),
  CONSTRAINT task_reminders_pkey PRIMARY KEY (id)
);
ALTER TABLE public.task_reminders ENABLE ROW LEVEL SECURITY;

-- ── time_entries ──
CREATE TABLE public.time_entries (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  service_order_id uuid NOT NULL,
  technician_user_id uuid NOT NULL,
  started_at timestamp with time zone NOT NULL,
  ended_at timestamp with time zone,
  duration_minutes integer,
  billable boolean DEFAULT true,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  step_id uuid,
  stop_reason_code text,
  shift_id uuid,
  CONSTRAINT time_entries_pkey PRIMARY KEY (id)
);
ALTER TABLE public.time_entries ENABLE ROW LEVEL SECURITY;

-- ── vessel_contacts ──
CREATE TABLE public.vessel_contacts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  vessel_id uuid NOT NULL,
  full_name text NOT NULL,
  role text DEFAULT 'owner'::text NOT NULL,
  phone text,
  email text,
  notes text,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT vessel_contacts_pkey PRIMARY KEY (id)
);
ALTER TABLE public.vessel_contacts ENABLE ROW LEVEL SECURITY;

-- ── vessels ──
CREATE TABLE public.vessels (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  client_id uuid NOT NULL,
  marina_id uuid,
  name text NOT NULL,
  manufacturer text,
  model text,
  year integer,
  hull_id_or_registration text,
  length_feet numeric(6,2),
  beam_feet numeric(6,2),
  draft_feet numeric(6,2),
  engine_type text,
  engine_brand text,
  engine_model text,
  engine_quantity integer DEFAULT 1,
  propulsion_type text,
  shore_power_type text,
  battery_bank_summary text,
  inverter_charger_summary text,
  navigation_electronics_summary text,
  electrical_system_notes text,
  current_marina_name_snapshot text,
  current_dock_position text,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  asset_type text DEFAULT 'Lancha'::text,
  CONSTRAINT vessels_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.vessels.asset_type IS 'Tipo do ativo (Lancha, Veleiro, Catamarã, Motorhome, Camper, Trailer)';
ALTER TABLE public.vessels ENABLE ROW LEVEL SECURITY;

-- ── whatsapp_blocked_numbers ──
CREATE TABLE public.whatsapp_blocked_numbers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  phone_normalized text NOT NULL,
  reason text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  created_by uuid,
  CONSTRAINT whatsapp_blocked_numbers_pkey PRIMARY KEY (id),
  CONSTRAINT whatsapp_blocked_numbers_phone_normalized_key UNIQUE (phone_normalized)
);
ALTER TABLE public.whatsapp_blocked_numbers ENABLE ROW LEVEL SECURITY;

-- ── whatsapp_conversation_assignments ──
CREATE TABLE public.whatsapp_conversation_assignments (
  phone_normalized text NOT NULL,
  assigned_to uuid,
  notified_at timestamp with time zone,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT whatsapp_conversation_assignments_pkey PRIMARY KEY (phone_normalized)
);
ALTER TABLE public.whatsapp_conversation_assignments ENABLE ROW LEVEL SECURITY;

-- ── whatsapp_leads ──
CREATE TABLE public.whatsapp_leads (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  phone_normalized text NOT NULL,
  name text,
  first_message text,
  last_message_at timestamp with time zone DEFAULT now() NOT NULL,
  message_count integer DEFAULT 1 NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  linked_client_id uuid,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  assigned_to uuid,
  is_broadcast boolean DEFAULT false,
  unread_count integer DEFAULT 0,
  last_inbound_at timestamp with time zone,
  last_outbound_at timestamp with time zone,
  muted_at timestamp with time zone,
  CONSTRAINT whatsapp_leads_status_check CHECK (status = ANY (ARRAY['pending'::text, 'linked'::text, 'converted'::text, 'discarded'::text])),
  CONSTRAINT whatsapp_leads_pkey PRIMARY KEY (id),
  CONSTRAINT whatsapp_leads_phone_normalized_key UNIQUE (phone_normalized)
);
ALTER TABLE public.whatsapp_leads ENABLE ROW LEVEL SECURITY;

-- ── whatsapp_messages ──
CREATE TABLE public.whatsapp_messages (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  direction text NOT NULL,
  phone_normalized text NOT NULL,
  message_type text DEFAULT 'text'::text NOT NULL,
  body text,
  media_url text,
  client_id uuid,
  lead_id uuid,
  service_order_id uuid,
  wa_message_id text,
  delivery_status text DEFAULT 'received'::text,
  raw_payload jsonb,
  occurred_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  is_broadcast boolean DEFAULT false,
  sent_by uuid,
  supplier_id uuid,
  CONSTRAINT whatsapp_messages_delivery_status_check CHECK (delivery_status = ANY (ARRAY['received'::text, 'sent'::text, 'delivered'::text, 'read'::text, 'failed'::text])),
  CONSTRAINT whatsapp_messages_direction_check CHECK (direction = ANY (ARRAY['inbound'::text, 'outbound'::text])),
  CONSTRAINT whatsapp_messages_message_type_check CHECK (message_type = ANY (ARRAY['text'::text, 'image'::text, 'audio'::text, 'video'::text, 'document'::text, 'location'::text, 'contact'::text, 'sticker'::text, 'other'::text])),
  CONSTRAINT whatsapp_messages_pkey PRIMARY KEY (id)
);
COMMENT ON COLUMN public.whatsapp_messages.supplier_id IS 'Fornecedor dono deste número, quando identificado. Preenchido por link_contact_to_entity (agente) — espelha o papel de client_id para o outro lado da operação.';
ALTER TABLE public.whatsapp_messages ENABLE ROW LEVEL SECURITY;

-- ── whatsapp_quick_replies ──
CREATE TABLE public.whatsapp_quick_replies (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  shortcut text NOT NULL,
  body text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  sort_order integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT whatsapp_quick_replies_pkey PRIMARY KEY (id)
);
ALTER TABLE public.whatsapp_quick_replies ENABLE ROW LEVEL SECURITY;

-- ── whatsapp_read_state ──
CREATE TABLE public.whatsapp_read_state (
  user_id uuid NOT NULL,
  last_read_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT whatsapp_read_state_pkey PRIMARY KEY (user_id)
);
ALTER TABLE public.whatsapp_read_state ENABLE ROW LEVEL SECURITY;

-- ── whatsapp_scheduled_sends ──
CREATE TABLE public.whatsapp_scheduled_sends (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  target_kind text NOT NULL,
  service_order_id uuid,
  receivable_id uuid,
  client_id uuid,
  phone text NOT NULL,
  message text NOT NULL,
  send_mode text DEFAULT 'link'::text NOT NULL,
  context text,
  document_type text,
  link_title text,
  link_description text,
  pdf_filename text,
  caption text,
  include_link_in_caption boolean DEFAULT true NOT NULL,
  scheduled_at timestamp with time zone NOT NULL,
  recurrence_type text DEFAULT 'once'::text NOT NULL,
  recurrence_days_of_week integer[],
  recurrence_day_of_month integer,
  recurrence_end_date timestamp with time zone,
  next_run_at timestamp with time zone NOT NULL,
  last_run_at timestamp with time zone,
  auto_retry boolean DEFAULT true NOT NULL,
  max_attempts integer DEFAULT 3 NOT NULL,
  attempt_count integer DEFAULT 0 NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  last_error text,
  last_response jsonb,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  document_url text,
  CONSTRAINT chk_target CHECK (target_kind = 'service_order'::text AND service_order_id IS NOT NULL OR target_kind = 'receivable'::text AND receivable_id IS NOT NULL OR target_kind = 'manual'::text OR target_kind = 'self_reminder'::text),
  CONSTRAINT whatsapp_scheduled_sends_recurrence_type_check CHECK (recurrence_type = ANY (ARRAY['once'::text, 'daily'::text, 'weekly'::text, 'monthly'::text])),
  CONSTRAINT whatsapp_scheduled_sends_send_mode_check CHECK (send_mode = ANY (ARRAY['link'::text, 'document'::text, 'text'::text])),
  CONSTRAINT whatsapp_scheduled_sends_status_check CHECK (status = ANY (ARRAY['pending'::text, 'processing'::text, 'sent'::text, 'failed'::text, 'cancelled'::text])),
  CONSTRAINT whatsapp_scheduled_sends_pkey PRIMARY KEY (id)
);
ALTER TABLE public.whatsapp_scheduled_sends ENABLE ROW LEVEL SECURITY;

-- ── whatsapp_send_queue ──
CREATE TABLE public.whatsapp_send_queue (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  phone_normalized text NOT NULL,
  message text NOT NULL,
  source text DEFAULT 'manual'::text NOT NULL,
  source_ref_id uuid,
  priority integer DEFAULT 5 NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  max_attempts integer DEFAULT 3 NOT NULL,
  scheduled_for timestamp with time zone DEFAULT now() NOT NULL,
  processing_started_at timestamp with time zone,
  sent_at timestamp with time zone,
  failed_reason text,
  zapi_message_id text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT whatsapp_send_queue_pkey PRIMARY KEY (id)
);
ALTER TABLE public.whatsapp_send_queue ENABLE ROW LEVEL SECURITY;

-- ── whatsapp_status_scheduled ──
CREATE TABLE public.whatsapp_status_scheduled (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  content_type text NOT NULL,
  media_url text,
  text_content text,
  background_color text DEFAULT '#000000'::text,
  font_type integer DEFAULT 0,
  scheduled_at timestamp with time zone NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  error_message text,
  zapi_message_id text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT whatsapp_status_scheduled_content_type_check CHECK (content_type = ANY (ARRAY['text'::text, 'image'::text, 'video'::text])),
  CONSTRAINT whatsapp_status_scheduled_status_check CHECK (status = ANY (ARRAY['pending'::text, 'processing'::text, 'sent'::text, 'failed'::text, 'cancelled'::text])),
  CONSTRAINT whatsapp_status_scheduled_pkey PRIMARY KEY (id)
);
ALTER TABLE public.whatsapp_status_scheduled ENABLE ROW LEVEL SECURITY;

-- ── whatsapp_templates ──
CREATE TABLE public.whatsapp_templates (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  category text DEFAULT 'general'::text NOT NULL,
  body text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  sort_order integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT whatsapp_templates_pkey PRIMARY KEY (id)
);
ALTER TABLE public.whatsapp_templates ENABLE ROW LEVEL SECURITY;

-- ── work_profiles ──
CREATE TABLE public.work_profiles (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  app_user_id uuid,
  payee_id uuid,
  tipo_vinculo text NOT NULL,
  modo_pagamento text NOT NULL,
  valor_hora numeric(12,2),
  valor_diaria numeric(12,2),
  valor_mensal numeric(12,2),
  meia_diaria_ate_horas numeric(4,2),
  jornada_diaria_horas numeric(4,2) DEFAULT 8 NOT NULL,
  divisor_mensal integer DEFAULT 220 NOT NULL,
  pct_hora_extra numeric(5,2) DEFAULT 50 NOT NULL,
  pct_noturno numeric(5,2) DEFAULT 20 NOT NULL,
  pct_domingo numeric(5,2) DEFAULT 100 NOT NULL,
  paga_dsr boolean DEFAULT false NOT NULL,
  vigencia_inicio date DEFAULT CURRENT_DATE NOT NULL,
  vigencia_fim date,
  observacao text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT work_profiles_modo_pagamento_check CHECK (modo_pagamento = ANY (ARRAY['hora'::text, 'diaria'::text, 'mensal'::text, 'empreitada'::text])),
  CONSTRAINT work_profiles_tipo_vinculo_check CHECK (tipo_vinculo = ANY (ARRAY['clt'::text, 'diarista'::text, 'freelancer'::text, 'pj'::text, 'socio'::text])),
  CONSTRAINT work_profiles_um_titular CHECK (app_user_id IS NOT NULL AND payee_id IS NULL OR app_user_id IS NULL AND payee_id IS NOT NULL),
  CONSTRAINT work_profiles_valor_do_modo CHECK (modo_pagamento = 'hora'::text AND valor_hora IS NOT NULL OR modo_pagamento = 'diaria'::text AND valor_diaria IS NOT NULL OR modo_pagamento = 'mensal'::text AND valor_mensal IS NOT NULL OR modo_pagamento = 'empreitada'::text),
  CONSTRAINT work_profiles_vigencia_coerente CHECK (vigencia_fim IS NULL OR vigencia_fim >= vigencia_inicio),
  CONSTRAINT work_profiles_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.work_profiles IS 'Como cada pessoa e paga, com vigencia. Mudar o valor-hora hoje nao altera o que ja foi pago: fecha-se o perfil antigo e abre-se outro.';
ALTER TABLE public.work_profiles ENABLE ROW LEVEL SECURITY;

-- ── work_shifts ──
CREATE TABLE public.work_shifts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  work_profile_id uuid NOT NULL,
  data date NOT NULL,
  inicio timestamp with time zone,
  fim timestamp with time zone,
  intervalo_minutos integer DEFAULT 0 NOT NULL,
  duracao_minutos integer,
  tipo text DEFAULT 'normal'::text NOT NULL,
  origem text DEFAULT 'painel'::text NOT NULL,
  status text DEFAULT 'rascunho'::text NOT NULL,
  observacao text,
  registrado_por uuid,
  aprovado_por uuid,
  aprovado_em timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  service_order_id uuid,
  CONSTRAINT work_shifts_aprovacao_tem_autor CHECK (status = 'rascunho'::text OR aprovado_por IS NOT NULL AND aprovado_em IS NOT NULL),
  CONSTRAINT work_shifts_duracao_minutos_check CHECK (duracao_minutos >= 0),
  CONSTRAINT work_shifts_fim_depois_do_inicio CHECK (fim IS NULL OR inicio IS NULL OR fim >= inicio),
  CONSTRAINT work_shifts_intervalo_minutos_check CHECK (intervalo_minutos >= 0),
  CONSTRAINT work_shifts_origem_check CHECK (origem = ANY (ARRAY['whatsapp'::text, 'painel'::text, 'agente'::text, 'importado'::text])),
  CONSTRAINT work_shifts_status_check CHECK (status = ANY (ARRAY['rascunho'::text, 'aprovado'::text, 'pago'::text])),
  CONSTRAINT work_shifts_tipo_check CHECK (tipo = ANY (ARRAY['normal'::text, 'diaria'::text, 'folga'::text, 'falta'::text, 'atestado'::text, 'feriado'::text])),
  CONSTRAINT work_shifts_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.work_shifts IS 'Jornada trabalhada, independente de OS. Base do que a PESSOA recebe; time_entries continua sendo a base do que o CLIENTE paga.';
COMMENT ON COLUMN public.work_shifts.service_order_id IS 'OS em que o dia foi trabalhado, quando o dia inteiro foi de uma so. Opcional: dia de oficina, deslocamento e administrativo nao tem OS -- e e justamente por eles nao caberem em time_entries (service_order_id NOT NULL) que work_shifts existe.';
ALTER TABLE public.work_shifts ENABLE ROW LEVEL SECURITY;

-- ── work_stop_reasons ──
CREATE TABLE public.work_stop_reasons (
  code text NOT NULL,
  label text NOT NULL,
  category text NOT NULL,
  counts_as_billable boolean DEFAULT false NOT NULL,
  sort integer DEFAULT 0 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  CONSTRAINT work_stop_reasons_category_check CHECK (category = ANY (ARRAY['espera'::text, 'logistica'::text, 'tecnico'::text, 'pessoal'::text, 'externo'::text])),
  CONSTRAINT work_stop_reasons_pkey PRIMARY KEY (code)
);
ALTER TABLE public.work_stop_reasons ENABLE ROW LEVEL SECURITY;

-- Sequências de colunas serial: vínculo OWNED BY
