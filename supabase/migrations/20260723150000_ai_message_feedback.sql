-- Feedback 👍/👎 por mensagem do agente (Onda 4). Aplicado via MCP (ai_message_feedback).
create table if not exists ai_message_feedback (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  rating text not null check (rating in ('up','down')),
  message_excerpt text,
  session_id uuid,
  created_by uuid
);
create index if not exists idx_ai_message_feedback_created on ai_message_feedback (created_at desc);
alter table ai_message_feedback enable row level security;
drop policy if exists authenticated_all_ai_message_feedback on ai_message_feedback;
create policy authenticated_all_ai_message_feedback on ai_message_feedback for all to authenticated using (true) with check (true);
