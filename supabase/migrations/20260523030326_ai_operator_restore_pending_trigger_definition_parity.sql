-- ============================================================================
-- MarineFlow AI Operator — Macro Cycle 1 (staging parity remediation)
-- Restaura no Git a mesma definição de trigger já corrigida no staging.
-- ============================================================================
-- Contexto operacional:
--   * A foundation já foi aplicada no staging.
--   * A migration de hardening também já foi aplicada no staging.
--   * Durante a transferência conectada do SQL, a definição remota de
--     `public.ai_op_protect_pending_action()` ficou com divergência textual
--     em uma mensagem de exceção (faltou o `)` final no estado terminal).
--   * A remediação mínima já foi aplicada remotamente antes desta sessão.
--
-- Esta migration existe SOMENTE para restaurar a paridade Git ↔ staging.
-- Não recria triggers, não altera tabelas, policies, dados, outras funções,
-- bridge WhatsApp ou qualquer integração externa.
-- ============================================================================

create or replace function public.ai_op_protect_pending_action()
returns trigger
language plpgsql
set search_path = ''
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

revoke execute on function public.ai_op_protect_pending_action() from public;
revoke execute on function public.ai_op_protect_pending_action() from anon, authenticated;
grant execute on function public.ai_op_protect_pending_action() to service_role;
