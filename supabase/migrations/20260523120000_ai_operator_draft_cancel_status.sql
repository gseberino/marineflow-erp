-- ============================================================================
-- MarineFlow AI Operator — adiciona status 'cancelled' a ai_operator_drafts
-- ============================================================================
-- Macro Ciclo evolução operacional: rascunhos criados incorretamente precisam
-- ser cancelados de forma audit ável sem hard delete. Esta migration é
-- ADITIVA e NÃO destrutiva: apenas amplia o CHECK constraint do campo
-- status para incluir 'cancelled'. Os dados existentes continuam válidos
-- (nenhum draft nasce em 'cancelled').
--
-- Endpoint `cancel_draft` (ai-operator-core) gerencia transição de estado
-- com regras explícitas:
--   * só drafts em ('draft', 'awaiting_info') podem ser cancelados;
--   * drafts com pending_actions abertas são bloqueados;
--   * razão opcional gravada em metadata.cancellation_reason;
--   * audit event 'draft_cancelled' registrado.
--
-- Aplicação: SOMENTE staging okurngvcodmljjicopdp.
-- Rollback: idempotente — drop do constraint novo e re-criação do anterior.
-- ============================================================================

do $cancel_status$
begin
  -- Idempotência: se já existir 'cancelled', não recria o constraint.
  if not exists (
    select 1
    from information_schema.check_constraints
    where constraint_name = 'ai_operator_drafts_status_check'
      and check_clause like '%cancelled%'
  ) then
    alter table public.ai_operator_drafts
      drop constraint if exists ai_operator_drafts_status_check;

    alter table public.ai_operator_drafts
      add constraint ai_operator_drafts_status_check
      check (status in (
        'draft',
        'awaiting_info',
        'awaiting_approval',
        'approved',
        'rejected',
        'converted',
        'cancelled'
      ));
  end if;
end
$cancel_status$;

comment on column public.ai_operator_drafts.status is
  'MarineFlow AI Operator — estados: draft, awaiting_info, awaiting_approval, approved, rejected, converted, cancelled. cancelled: rascunho cancelado pelo usuario (preserva trilha; metadata.cancellation_reason opcional).';
