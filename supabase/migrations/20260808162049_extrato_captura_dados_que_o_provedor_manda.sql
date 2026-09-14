-- Recuperada do transcript da sessão (C--Users-PC/374b5203-fb74-4f92-b284-ba488b300c96.jsonl, 2026-08-08T16:20:44.102Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260808162049 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

-- FASE A1 — parar de jogar fora o que o provedor já manda.
--
-- Medição em 2.141 transações: cartão traz documento em 4% e estabelecimento em 5%, e o
-- EndToEndId do Pix está zerado em 100% — o que torna INERTE a camada de certeza do motor
-- de conciliação, construída inteira sobre ele. A causa não é o provedor mandar pouco: é
-- lermos ~60% do que ele manda e tratarmos compra de cartão com o modelo de dados de
-- transferência bancária, que não tem contraparte porque compra em loja não é transferência.

ALTER TABLE public.bank_transactions
  -- Categoria que a própria Pluggy atribui (produto de enriquecimento deles). Construímos
  -- um classificador do zero sem nunca olhar o que já vinha classificado.
  ADD COLUMN IF NOT EXISTS provider_category text,
  ADD COLUMN IF NOT EXISTS merchant_category text,
  -- MCC (ISO 18245): a chave UNIVERSAL de tipo de estabelecimento. 5812 é restaurante em
  -- qualquer adquirente do mundo. Resolve de forma determinística o que hoje mandamos
  -- para a IA adivinhar pelo nome.
  ADD COLUMN IF NOT EXISTS payee_mcc text,
  -- Últimos dígitos: com mais de um cartão, é o que separa um do outro.
  ADD COLUMN IF NOT EXISTS card_last_digits text,
  -- PENDING vs POSTED. Transação pendente muda de valor ou some — lançar despesa em cima
  -- dela é construir sobre areia.
  ADD COLUMN IF NOT EXISTS tx_status text,
  -- Provas do pagamento e pistas de casamento, hoje declaradas no tipo e nunca lidas.
  ADD COLUMN IF NOT EXISTS authentication_code text,
  ADD COLUMN IF NOT EXISTS receiver_reference_id text,
  -- Fatura do cartão: fecha o ciclo (soma das compras = valor da fatura).
  ADD COLUMN IF NOT EXISTS bill_id text,
  -- Conta de origem no provedor. Temos a conexão, não a conta.
  ADD COLUMN IF NOT EXISTS provider_account_id text;

COMMENT ON COLUMN public.bank_transactions.payee_mcc IS
  'Merchant Category Code (ISO 18245). Classificação determinística de estabelecimento — '
  'precede memória e IA na ordem de decisão.';
COMMENT ON COLUMN public.bank_transactions.tx_status IS
  'PENDING | POSTED. Pendente não vira proposta de lançamento.';

CREATE INDEX IF NOT EXISTS idx_bank_transactions_mcc
  ON public.bank_transactions (payee_mcc) WHERE payee_mcc IS NOT NULL;

/**
 * Amostra do payload cru, para descobrir ONDE está o EndToEndId do Pix.
 *
 * O motor casa transação com cobrança pelo EndToEndId — único no SPI, prova irrefutável —
 * e o campo está vazio em 2.141 linhas. Sem ver o payload real não dá para saber se o
 * provedor manda em outro campo, se aquela instituição não manda, ou se o método não vem
 * escrito "PIX". Guardar 40 amostras responde isso sem chutar.
 */
CREATE TABLE IF NOT EXISTS public.pluggy_amostra_payload (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bank_ref_id text NOT NULL,
  source_type text NOT NULL,
  payload jsonb NOT NULL,
  colhida_em timestamptz NOT NULL DEFAULT now()
);

-- Tabela nova no Supabase é legível por anônimo até que se diga o contrário, e esta guarda
-- payload bancário cru. Fecha antes de existir para alguém.
ALTER TABLE public.pluggy_amostra_payload ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pluggy_amostra_payload FROM anon, authenticated;

CREATE UNIQUE INDEX IF NOT EXISTS pluggy_amostra_unica
  ON public.pluggy_amostra_payload (bank_ref_id);
