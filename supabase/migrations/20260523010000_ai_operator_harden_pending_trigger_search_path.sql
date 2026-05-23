-- ============================================================================
-- MarineFlow AI Operator — Macro Cycle 1 (continuação)
-- Hardening de search_path em duas trigger functions do caminho da foundation.
-- ============================================================================
-- Contexto: a foundation `ai_operator_foundation` (registro Supabase
-- 20260523005653) já foi aplicada em okurngvcodmljjicopdp ANTES do deploy
-- do `ai-operator-core`. Pós-aplicação, o Supabase Security Advisor
-- sinalizou DUAS instâncias do aviso `function_search_path_mutable` no
-- caminho da foundation do AI Operator:
--   1. `public.ai_op_protect_pending_action`
--      — trigger que protege adulteração de pending_actions.
--   2. `public.set_updated_at_now`
--      — helper compartilhado de updated_at (usado também por outros
--        módulos; CREATE OR REPLACE preserva os triggers já anexados).
--
-- Esta migration é ADITIVA, NÃO destrutiva e ESCOPO ESTRITAMENTE LIMITADO
-- às duas correções acima. Não cria tabelas, não altera policies, não
-- altera dados, não toca em outras funções e não altera o bridge WhatsApp
-- (que permanece em `supabase/deferred-migrations/`).
--
-- As funções alvo NÃO consultam tabelas: usam apenas NEW/OLD/TG_OP/
-- raise exception e pg_catalog.now(). Portanto `set search_path = ''`
-- é a opção mais segura — elimina qualquer dependência de resolução
-- implícita de nomes e atende a recomendação do Advisor.
--
-- Rollback (manual, somente staging): re-aplicar as versões anteriores
-- sem `set search_path = ''`. Não recomendado — perderia o hardening
-- sem ganho. Permissões de execução não são alteradas para
-- `set_updated_at_now` (ela continua sendo usada por outros módulos).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) public.ai_op_protect_pending_action()
-- ---------------------------------------------------------------------------
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

-- Reafirma permissões server-only (idempotente). A foundation original já
-- aplicou estes GRANT/REVOKE; reaplicamos aqui para garantir o estado correto.
revoke execute on function public.ai_op_protect_pending_action() from public;
revoke execute on function public.ai_op_protect_pending_action() from anon, authenticated;
grant  execute on function public.ai_op_protect_pending_action() to service_role;

-- Trigger `trg_ai_op_pending_guard` permanece anexado a
-- public.ai_operator_pending_actions pela foundation. NÃO recriado aqui
-- para não disparar reanexação desnecessária.

-- ---------------------------------------------------------------------------
-- 2) public.set_updated_at_now()
-- ---------------------------------------------------------------------------
-- Helper compartilhado (pode ser usado por outros módulos do projeto).
-- CREATE OR REPLACE preserva os triggers já anexados em qualquer tabela
-- — incluindo trg_ai_op_sessions_updated, trg_ai_op_drafts_updated e
-- trg_ai_op_memory_updated do AI Operator.
--
-- Não alteramos permissões de execução desta função: continua disponível
-- a quem já a usa em outros módulos. O hardening aqui se limita a
-- search_path e qualificação explícita de pg_catalog.now().
create or replace function public.set_updated_at_now()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = pg_catalog.now();
  return new;
end;
$$;
