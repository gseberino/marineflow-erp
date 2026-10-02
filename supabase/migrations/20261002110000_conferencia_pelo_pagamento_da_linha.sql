-- Conferência "lançamento × extrato" de conta a receber: compara a linha do banco com o PAGAMENTO
-- que ela registrou, e não com o total da conta (02/10/2026).
--
-- Por quê: conta paga em mais de uma vez (Pix + dinheiro) acusava diferença falsa. Caso real: OS-00034
-- de R$ 29.000 = Pix de R$ 25.000 + R$ 4.000 em dinheiro (confirmado pelo dono em 02/10). A
-- conferência dizia "difere R$ 4.000" e travava o mês de junho. Bater com o extrato é o Pix valer o
-- que ele registrou; o resto da conta pode ter sido pago por outro meio. Sem pagamento ligado à linha
-- (conta que nasceu do extrato), continua comparando o total.
--
-- Medido antes de aplicar (ensaio): mudam só OS-00034 (4.000 → 0) e OS-00041 (573,18 → 0), depois do
-- conserto dos vínculos da Rita, e OS-00046 (20 → 0: o cliente pagou R$ 500 pelo Pix e R$ 20 seguem em
-- aberto, que é saldo a receber, não diferença do banco). A forma A (aplicação de pagamento) vai
-- substituir esta comparação por aplicação; até lá, esta é a leitura certa.
create or replace view public.conciliacao_lancamentos with (security_invoker = on) as
SELECT 'payable'::text AS lado,
    p.id,
    p.description,
    p.amount,
    p.status,
    p.due_date,
    p.issue_date,
    COALESCE(s.name, p.supplier_name) AS contraparte,
    p.expense_category AS categoria,
    p.bank_transaction_id,
        CASE
            WHEN p.bank_transaction_id IS NOT NULL THEN 'conciliado'::text
            WHEN p.payment_method = 'credito_fornecedor'::text THEN 'fora_do_banco'::text
            ELSE 'sem_extrato'::text
        END AS situacao,
    bt.transaction_date AS extrato_data,
    bt.amount AS extrato_valor,
    bt.description AS extrato_descricao,
        CASE
            WHEN p.bank_transaction_id IS NOT NULL THEN round(COALESCE(g.soma, p.amount) - bt.amount, 2)
            ELSE NULL::numeric
        END AS diferenca,
    p.origin = 'bank_reconciliation'::text OR (EXISTS ( SELECT 1
           FROM finance_review_queue q
          WHERE q.created_payable_id = p.id)) AS nasceu_do_extrato,
        CASE
            WHEN bt.installment_label ~ '^\d{1,2}/\d{1,2}$'::text AND split_part(bt.installment_label, '/'::text, 2)::integer >= 2 THEN abs(p.amount - split_part(bt.installment_label, '/'::text, 2)::integer::numeric * bt.amount) <= ((split_part(bt.installment_label, '/'::text, 2)::integer * (split_part(bt.installment_label, '/'::text, 2)::integer - 1))::numeric * 0.01)
            ELSE false
        END AS compra_parcelada,
        CASE
            WHEN bt.installment_label ~ '^\d{1,2}/\d{1,2}$'::text THEN split_part(bt.installment_label, '/'::text, 2)::integer
            ELSE NULL::integer
        END AS parcelas,
    d.payable_id IS NOT NULL AS lancada_em_dobro
   FROM payables p
     LEFT JOIN bank_transactions bt ON bt.id = p.bank_transaction_id
     LEFT JOIN suppliers s ON s.id = p.supplier_id
     LEFT JOIN compras_parceladas_em_dobro d ON d.payable_id = p.id
     LEFT JOIN LATERAL ( SELECT sum(x.amount) AS soma
           FROM payables x
          WHERE x.bank_transaction_id = p.bank_transaction_id AND x.status <> 'cancelled'::text AND COALESCE(x.divisao_id, x.id) = COALESCE(p.divisao_id, p.id)) g ON p.bank_transaction_id IS NOT NULL
  WHERE p.status <> 'cancelled'::text
UNION ALL
 SELECT 'receivable'::text AS lado,
    r.id,
    r.description,
    r.amount,
    r.status,
    r.due_date,
    r.issue_date,
    c.name AS contraparte,
    r.category AS categoria,
    r.bank_transaction_id,
        CASE
            WHEN r.bank_transaction_id IS NOT NULL THEN 'conciliado'::text
            ELSE 'sem_extrato'::text
        END AS situacao,
    bt.transaction_date AS extrato_data,
    bt.amount AS extrato_valor,
    bt.description AS extrato_descricao,
        CASE
            WHEN r.bank_transaction_id IS NOT NULL THEN round(COALESCE(pl.amount, r.amount) - bt.amount, 2)
            ELSE NULL::numeric
        END AS diferenca,
    (EXISTS ( SELECT 1
           FROM finance_review_queue q
          WHERE q.created_receivable_id = r.id)) AS nasceu_do_extrato,
    false AS compra_parcelada,
    NULL::integer AS parcelas,
    false AS lancada_em_dobro
   FROM receivables r
     LEFT JOIN bank_transactions bt ON bt.id = r.bank_transaction_id
     LEFT JOIN payments pl ON pl.id = bt.reconciled_payment_id AND pl.receivable_id = r.id AND pl.status = 'confirmed'::text
     LEFT JOIN clients c ON c.id = r.client_id
  WHERE r.status <> 'cancelled'::text;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261002110000', 'conferencia_pelo_pagamento_da_linha')
on conflict do nothing;
