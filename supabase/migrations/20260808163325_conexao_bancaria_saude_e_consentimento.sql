-- Recuperada do transcript da sessão (C--Users-PC/374b5203-fb74-4f92-b284-ba488b300c96.jsonl, 2026-08-08T16:33:21.792Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260808163325 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

-- FASE D — a integração tem de avisar antes de parar de funcionar.
--
-- O consentimento de Open Finance expira em 12 meses e o item pode cair por MFA,
-- mudança de senha ou revogação. Hoje isso falha em SILÊNCIO: a sincronização volta sem
-- transação nova, o que é indistinguível de "não houve movimento". O gestor só descobre
-- quando percebe que o extrato parou — geralmente no fechamento, semanas depois, com o
-- período já perdido.

ALTER TABLE public.bank_connections
  -- Quando o consentimento expira. Vindo do provedor; null enquanto não se sabe.
  ADD COLUMN IF NOT EXISTS consent_expires_at timestamptz,
  -- Situação do item no provedor: UPDATED | WAITING_USER_INPUT | LOGIN_ERROR | OUTDATED.
  ADD COLUMN IF NOT EXISTS provider_status text,
  -- Quantas sincronizações seguidas não trouxeram nada. Sozinho não prova problema;
  -- combinado com movimento esperado, denuncia conexão morta.
  ADD COLUMN IF NOT EXISTS sincronizacoes_vazias integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.bank_connections.consent_expires_at IS
  'Vencimento do consentimento de Open Finance (12 meses). Sem aviso, a conexão morre calada '
  'e o gestor descobre no fechamento, com o período já perdido.';

/**
 * Conferência de saldo — proof of completeness.
 *
 * O controle que os ERPs aplicam para provar que NADA falta: o saldo que o banco informa
 * tem de bater com o saldo anterior mais a soma das transações do período. Se não bate,
 * falta transação — e falta em silêncio, que é o pior jeito de faltar. Sem isto, uma
 * transação perdida na sincronização nunca é descoberta: ela simplesmente não existe para
 * o sistema, e o sistema não tem como saber o que não recebeu.
 */
CREATE TABLE IF NOT EXISTS public.bank_balance_checks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bank_connection_id uuid NOT NULL REFERENCES public.bank_connections(id) ON DELETE CASCADE,
  conferido_em timestamptz NOT NULL DEFAULT now(),
  saldo_do_provedor numeric(14,2),
  saldo_calculado numeric(14,2),
  diferenca numeric(14,2),
  transacoes_no_periodo integer,
  fecha boolean NOT NULL DEFAULT false,
  observacao text
);

ALTER TABLE public.bank_balance_checks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.bank_balance_checks FROM anon;

-- Leitura para quem cuida do financeiro; escrita só pelo motor (service_role ignora RLS).
CREATE POLICY "financeiro le conferencias de saldo"
  ON public.bank_balance_checks FOR SELECT TO authenticated
  USING (public.is_admin_or_financial(auth.uid()));

CREATE INDEX IF NOT EXISTS idx_balance_checks_conexao
  ON public.bank_balance_checks (bank_connection_id, conferido_em DESC);
