-- Permite definir uma condição de pagamento personalizada (parcelas com %
-- e prazo próprios) quando nenhum preset pré-definido bate com o que foi
-- acordado com o cliente. Mesma estrutura de um preset
-- (PaymentInstallment[]: label, services_pct, parts_pct, expenses_pct,
-- days_after_approval, tipo) para reaproveitar 100% da lógica já existente
-- (calcInstallmentAmount, signalRow, signalAmount, RegisterDepositDialog).
alter table public.service_orders
  add column if not exists custom_payment_installments jsonb null;
