-- Rascunhos de emissão de NF-e.
--
-- Permite salvar o que está sendo montado na tela de emissão (itens, destinatário,
-- natureza, pagamento, dados da devolução…) e retomar depois — mesma ideia do
-- rascunho de OS/Orçamento (service_orders status='draft'). NÃO reserva número
-- fiscal (número só é consumido na emissão real, senão vira lacuna).
--
-- Guarda o ESTADO COMPLETO do formulário em form_state (jsonb) para restaurar
-- exatamente como estava. Alguns campos são desnormalizados (label, recipient_name,
-- total_amount, nature_of_operation) só para a listagem ser barata.

create table if not exists public.fiscal_emission_drafts (
  id                  uuid primary key default gen_random_uuid(),
  created_by          uuid references public.app_users(id) on delete set null,
  label               text,          -- nome amigável (cliente + data), editável
  nature_of_operation text,          -- para exibir/filtrar na lista
  recipient_name      text,          -- para exibir na lista
  total_amount        numeric,       -- para exibir na lista
  form_state          jsonb not null, -- estado completo do formulário de emissão
  status              text not null default 'draft' check (status in ('draft', 'archived')),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

alter table public.fiscal_emission_drafts enable row level security;

-- Admin-only, igual às notas fiscais (issued_fiscal_documents).
create policy "fed_select" on public.fiscal_emission_drafts
  for select to authenticated using (public.is_admin(auth.uid()));
create policy "fed_insert" on public.fiscal_emission_drafts
  for insert to authenticated with check (public.is_admin(auth.uid()));
create policy "fed_update" on public.fiscal_emission_drafts
  for update to authenticated using (public.is_admin(auth.uid()));
create policy "fed_delete" on public.fiscal_emission_drafts
  for delete to authenticated using (public.is_admin(auth.uid()));

create index if not exists idx_fed_status_updated
  on public.fiscal_emission_drafts (status, updated_at desc);

-- updated_at automático em qualquer UPDATE.
create or replace function public.touch_fiscal_emission_draft()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_touch_fed on public.fiscal_emission_drafts;
create trigger trg_touch_fed before update on public.fiscal_emission_drafts
  for each row execute function public.touch_fiscal_emission_draft();

-- Arquivamento: rascunhos 'draft' parados há mais de N dias viram 'archived' —
-- ficam para registro, mas saem da lista ativa. Chamado por cron.
create or replace function public.archive_old_fiscal_drafts(p_days int default 30)
returns integer language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  update public.fiscal_emission_drafts
     set status = 'archived'
   where status = 'draft'
     and updated_at < now() - (p_days || ' days')::interval;
  get diagnostics v_count = row_count;
  return v_count;
end $$;
revoke all on function public.archive_old_fiscal_drafts(int) from public, anon, authenticated;

-- Cron diário (04:20) — idempotente, só se pg_cron estiver disponível.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'archive-fiscal-drafts') then
      perform cron.unschedule('archive-fiscal-drafts');
    end if;
    perform cron.schedule('archive-fiscal-drafts', '20 4 * * *', 'select public.archive_old_fiscal_drafts(30);');
  end if;
end $$;
