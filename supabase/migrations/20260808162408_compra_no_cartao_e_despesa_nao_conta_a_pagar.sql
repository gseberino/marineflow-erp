-- Recuperada do transcript da sessão (C--Users-PC/374b5203-fb74-4f92-b284-ba488b300c96.jsonl, 2026-08-08T16:24:03.616Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260808162408 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

-- Compra no cartão é DESPESA, nunca conta a pagar.
--
-- 41 compras parceladas ficaram como `partially_paid`, somando R$ 33.204,47 de saldo em
-- aberto. Foi decisão minha ao implementar o parcelamento — "não esconder dívida" — e o
-- efeito foi o oposto: essas 41 apareciam na lista de contas a pagar como se o gestor
-- devesse ao LOJISTA. Ele não deve. A compra, para ele, está paga; quem ele deve é o
-- BANCO, e essa dívida é a FATURA, uma só. Manter as duas conta a mesma dívida duas vezes.
--
-- A competência não muda: a despesa inteira já estava reconhecida na data da compra, e o
-- pagamento da fatura é não operacional (sai do resultado). Nada é contado em dobro.

UPDATE public.payables p
   SET paid_amount = p.amount,
       balance_amount = 0,
       status = 'paid'
 WHERE p.status = 'partially_paid'
   AND p.origin = 'bank_reconciliation'
   AND EXISTS (
     SELECT 1 FROM public.bank_transactions b
      WHERE b.id = p.bank_transaction_id AND b.source_type = 'credit_card'
   );
