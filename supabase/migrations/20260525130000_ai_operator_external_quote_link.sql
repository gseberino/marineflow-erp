-- Macro Cycle 2: auditable relationship between an AI Operator draft and
-- the formal ERP quote created from it. Additive only; no data rewrite.

alter table public.external_quotes
  add column if not exists ai_operator_draft_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'external_quotes_ai_operator_draft_id_fkey'
  ) then
    alter table public.external_quotes
      add constraint external_quotes_ai_operator_draft_id_fkey
      foreign key (ai_operator_draft_id)
      references public.ai_operator_drafts(id)
      on delete set null;
  end if;
end $$;

create unique index if not exists external_quotes_ai_operator_draft_id_uidx
  on public.external_quotes(ai_operator_draft_id)
  where ai_operator_draft_id is not null;

comment on column public.external_quotes.ai_operator_draft_id is
  'AI Operator draft that originated this formal ERP quote. Used for idempotent draft-to-quote formalization.';
