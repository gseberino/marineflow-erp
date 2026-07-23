-- Loop de Aprendizado (F) + fonte da Cadência (D). Aplicado em prod via MCP (comms_log).
create table if not exists ai_comms_log (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  tipo text not null,
  audiencia text,
  entity_kind text,
  entity_id uuid,
  phone text,
  message_preview text,
  status text not null default 'sent',
  block_code text,
  responded_at timestamptz,
  reply_intent text
);
create index if not exists idx_ai_comms_log_entity on ai_comms_log (entity_kind, entity_id, tipo, created_at desc);
create index if not exists idx_ai_comms_log_created on ai_comms_log (created_at desc);
alter table ai_comms_log enable row level security;
drop policy if exists authenticated_all_ai_comms_log on ai_comms_log;
create policy authenticated_all_ai_comms_log on ai_comms_log for all to authenticated using (true) with check (true);
