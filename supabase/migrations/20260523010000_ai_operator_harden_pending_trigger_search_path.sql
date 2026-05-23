-- ============================================================================
-- MarineFlow AI Operator — Macro Cycle 1 (continuação)
-- Hardening da trigger function `public.ai_op_protect_pending_action`.
-- ============================================================================
-- Contexto: a foundation `ai_operator_foundation` (registro Supabase
-- 20260523005653) já foi aplicada em okurngvcodmljjicopdp ANTES do deploy
-- do `ai-operator-core`. Pós-aplicação, o Supabase Security Advisor
-- sinalizou:
--   * `function_search_path_mutable`
--   * em `public.ai_op_protect_pending_action`
--
-- Esta migration é ADITIVA, NÃO destrutiva e ESCOPO ESTRITAMENTE LIMITADO
-- à correção do search_path da trigger function. Não cria tabelas, não
-- altera policies, não altera dados, não toca em outras funções e não
-- altera o bridge WhatsApp (que permanece em supabase/deferred-migrations/).
--
-- A função `ai_op_protect_pending_action` não consulta nenhuma tabela:
-- usa apenas `NEW`, `OLD`, `TG_OP` e `raise exception`. Portanto não
-- precisa de search_path para resolver nomes — `set search_path = ''` é
-- a opção mais segura e atende a recomendação do Advisor.
--
-- Rollback (manual, somente staging): re-aplique a versão anterior da
-- função sem `set search_path = ''`. Não recomendado — perderia o
-- hardening sem ganho.
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

-- Reafirma permissões (idempotente). A foundation original já aplicou estes
-- GRANT/REVOKE; reaplicamos aqui para garantir o estado correto mesmo que a
-- ordem de aplicação difira.
revoke execute on function public.ai_op_protect_pending_action() from public;
revoke execute on function public.ai_op_protect_pending_action() from anon, authenticated;
grant  execute on function public.ai_op_protect_pending_action() to service_role;

-- Trigger continua o mesmo — anexado a public.ai_operator_pending_actions
-- pela foundation. Não recriamos para não disparar reanexação desnecessária.
