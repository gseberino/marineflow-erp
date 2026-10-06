-- 06 · Views e materialized views, em ordem de dependência
-- Gerado por scripts/snapshot-producao.mjs a partir dos catálogos do banco de produção.
-- NÃO editar à mão: regenerar. A data e as contagens ficam no README.md ao lado.

-- ── bank_transactions_situacao ──
CREATE VIEW public.bank_transactions_situacao WITH (security_invoker=on) AS
 SELECT id,
    transaction_date,
    description,
    amount,
    transaction_type,
    bank_ref_id,
    reconciled,
    reconciled_payment_id,
    import_batch_id,
    created_at,
    source_type,
    reconciled_service_order_id,
    pix_end_to_end_id,
    counterparty_name,
    counterparty_document,
    balance_after,
    provider,
    dismissed_reason,
    bank_connection_id,
    counterparty_bank,
    counterparty_branch,
    counterparty_account,
    payment_method,
    payment_reason,
    merchant_name,
    merchant_document,
    installment_label,
    dismissed_at,
    dismissed_by,
    dismissed_kind,
    provider_category,
    merchant_category,
    payee_mcc,
    card_last_digits,
    tx_status,
    authentication_code,
    receiver_reference_id,
    bill_id,
    provider_account_id,
        CASE
            WHEN dismissed_reason IS NOT NULL THEN 'fora'::text
            WHEN reconciled_payment_id IS NOT NULL THEN 'conciliada'::text
            WHEN (EXISTS ( SELECT 1
               FROM payables p
              WHERE p.bank_transaction_id = bt.id)) OR (EXISTS ( SELECT 1
               FROM receivables r
              WHERE r.bank_transaction_id = bt.id)) THEN 'lancada'::text
            WHEN reconciled THEN 'sem_rastro'::text
            ELSE 'nova'::text
        END AS situacao,
    source_type = 'credit_card'::text AS e_cartao
   FROM bank_transactions bt;
COMMENT ON VIEW public.bank_transactions_situacao IS 'Linha do extrato com a situacao real derivada: nova, lancada, conciliada, sem_rastro, fora. Substitui a leitura do booleano reconciled, que colapsava tres significados em um.';
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.bank_transactions_situacao TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.bank_transactions_situacao TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.bank_transactions_situacao TO service_role;

-- ── compras_parceladas_em_dobro ──
CREATE VIEW public.compras_parceladas_em_dobro WITH (security_invoker=on) AS
 WITH parcelas AS (
         SELECT p.id AS payable_id,
            p.amount AS lancado,
            p.issue_date,
            p.description,
            bt.bank_connection_id,
            bt.amount AS parcela,
            bt.transaction_date,
            split_part(bt.installment_label, '/'::text, 1)::integer AS k,
            split_part(bt.installment_label, '/'::text, 2)::integer AS n,
            _loja_da_parcela(bt.counterparty_name, bt.description) AS loja
           FROM payables p
             JOIN bank_transactions bt ON bt.id = p.bank_transaction_id
          WHERE p.status <> 'cancelled'::text AND bt.installment_label ~ '^\d{1,2}/\d{1,2}$'::text AND split_part(bt.installment_label, '/'::text, 2)::integer >= 2
        ), saltos AS (
         SELECT parcelas.payable_id,
            parcelas.lancado,
            parcelas.issue_date,
            parcelas.description,
            parcelas.bank_connection_id,
            parcelas.parcela,
            parcelas.transaction_date,
            parcelas.k,
            parcelas.n,
            parcelas.loja,
            parcelas.parcela - lag(parcelas.parcela) OVER (PARTITION BY parcelas.bank_connection_id, parcelas.loja, parcelas.n ORDER BY parcelas.parcela, parcelas.k, parcelas.payable_id) AS salto
           FROM parcelas
        ), compras AS (
         SELECT saltos.payable_id,
            saltos.lancado,
            saltos.issue_date,
            saltos.description,
            saltos.bank_connection_id,
            saltos.parcela,
            saltos.transaction_date,
            saltos.k,
            saltos.n,
            saltos.loja,
            saltos.salto,
            sum(
                CASE
                    WHEN saltos.salto IS NULL OR saltos.salto > (saltos.n::numeric * 0.01) THEN 1
                    ELSE 0
                END) OVER (PARTITION BY saltos.bank_connection_id, saltos.loja, saltos.n ORDER BY saltos.parcela, saltos.k, saltos.payable_id) AS compra
           FROM saltos
        ), grupos AS (
         SELECT compras.bank_connection_id,
            compras.loja,
            compras.n,
            compras.compra,
            count(*) AS lancamentos,
            count(DISTINCT compras.k) AS parcelas_distintas,
            count(*) FILTER (WHERE abs(compras.lancado - compras.n::numeric * compras.parcela) <= ((compras.n * (compras.n - 1))::numeric * 0.01)) AS inteiras,
            max(compras.transaction_date - (compras.k - 1) * 30) - min(compras.transaction_date - (compras.k - 1) * 30) AS folga_da_compra
           FROM compras
          GROUP BY compras.bank_connection_id, compras.loja, compras.n, compras.compra
        ), marcadas AS (
         SELECT c.payable_id,
            c.lancado,
            c.issue_date,
            c.description,
            c.bank_connection_id,
            c.parcela,
            c.transaction_date,
            c.k,
            c.n,
            c.loja,
            c.salto,
            c.compra,
            g.lancamentos,
            g.parcelas_distintas,
            g.inteiras,
            g.folga_da_compra,
            first_value(c.payable_id) OVER (PARTITION BY c.bank_connection_id, c.loja, c.n, c.compra ORDER BY (abs(c.lancado - c.n::numeric * c.parcela) <= ((c.n * (c.n - 1))::numeric * 0.01)) DESC, c.k, c.payable_id) AS fica
           FROM compras c
             JOIN grupos g ON NOT g.bank_connection_id IS DISTINCT FROM c.bank_connection_id AND g.loja = c.loja AND g.n = c.n AND g.compra = c.compra
        )
 SELECT payable_id,
    fica AS payable_que_fica,
    loja,
    n AS parcelas,
    k AS parcela_do_lancamento,
    parcela AS valor_da_parcela,
    lancado,
    issue_date,
    transaction_date,
    description
   FROM marcadas
  WHERE inteiras >= 1 AND lancamentos > 1 AND parcelas_distintas = lancamentos AND folga_da_compra <= 35 AND payable_id <> fica;
COMMENT ON VIEW public.compras_parceladas_em_dobro IS 'Lançamentos que repetem uma compra parcelada já lançada pelo valor inteiro (fica o da parcela mais antiga). Ver 20260927120000.';
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.compras_parceladas_em_dobro TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.compras_parceladas_em_dobro TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.compras_parceladas_em_dobro TO service_role;

-- ── conciliacao_lancamentos ──
CREATE VIEW public.conciliacao_lancamentos WITH (security_invoker=on) AS
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
            WHEN COALESCE(r.bank_transaction_id, lp.linha) IS NOT NULL THEN 'conciliado'::text
            ELSE 'sem_extrato'::text
        END AS situacao,
    bt.transaction_date AS extrato_data,
    bt.amount AS extrato_valor,
    bt.description AS extrato_descricao,
        CASE
            WHEN bt.id IS NOT NULL THEN round(COALESCE(apl.total, r.amount) - bt.amount, 2)
            ELSE NULL::numeric
        END AS diferenca,
    (EXISTS ( SELECT 1
           FROM finance_review_queue q
          WHERE q.created_receivable_id = r.id)) AS nasceu_do_extrato,
    false AS compra_parcelada,
    NULL::integer AS parcelas,
    false AS lancada_em_dobro
   FROM receivables r
     LEFT JOIN LATERAL ( SELECT p.bank_transaction_id AS linha
           FROM payments p
          WHERE p.receivable_id = r.id AND p.status = 'confirmed'::text AND p.bank_transaction_id IS NOT NULL
          ORDER BY p.payment_date DESC, p.created_at DESC
         LIMIT 1) lp ON r.bank_transaction_id IS NULL
     LEFT JOIN bank_transactions bt ON bt.id = COALESCE(r.bank_transaction_id, lp.linha)
     LEFT JOIN LATERAL ( SELECT sum(x.amount) AS total
           FROM payments x
          WHERE x.bank_transaction_id = bt.id AND x.status = 'confirmed'::text AND x.receivable_id IS NOT NULL) apl ON bt.id IS NOT NULL
     LEFT JOIN clients c ON c.id = r.client_id
  WHERE r.status <> 'cancelled'::text;
COMMENT ON VIEW public.conciliacao_lancamentos IS 'Conciliacao vista do lado certo: um lancamento por linha (pagar ou receber), com a linha do extrato que casou e a diferenca. situacao = conciliado | sem_extrato.';
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.conciliacao_lancamentos TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.conciliacao_lancamentos TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.conciliacao_lancamentos TO service_role;

-- ── recebimentos_do_extrato ──
CREATE VIEW public.recebimentos_do_extrato WITH (security_invoker=on) AS
 SELECT t.id AS bank_transaction_id,
    t.bank_connection_id,
    t.transaction_date AS data,
    t.amount AS valor,
    COALESCE(t.counterparty_name, t.description) AS quem,
    t.counterparty_document AS documento,
    t.dismissed_kind,
    COALESCE(a.aplicado, 0::numeric) AS aplicado,
    round(t.amount - COALESCE(a.aplicado, 0::numeric), 2) AS sobra,
    COALESCE(a.contas, 0::bigint) AS contas,
    a.receivable_ids
   FROM bank_transactions t
     LEFT JOIN LATERAL ( SELECT sum(p.amount) AS aplicado,
            count(DISTINCT p.receivable_id) AS contas,
            array_agg(DISTINCT p.receivable_id) AS receivable_ids
           FROM payments p
          WHERE p.bank_transaction_id = t.id AND p.status = 'confirmed'::text AND p.receivable_id IS NOT NULL) a ON true
  WHERE t.transaction_type = 'credit'::text;
COMMENT ON VIEW public.recebimentos_do_extrato IS 'Cada entrada do banco como recebimento: quanto dela foi aplicado em contas a receber (pagamentos confirmados que vieram dela) e quanto sobra.';
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.recebimentos_do_extrato TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.recebimentos_do_extrato TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.recebimentos_do_extrato TO service_role;

-- ── conferencia_dos_pagamentos ──
CREATE VIEW public.conferencia_dos_pagamentos WITH (security_invoker=on) AS
 WITH pagos AS (
         SELECT r.id,
            r.description,
            r.amount,
            r.paid_amount,
            r.status,
            r.bank_transaction_id,
            COALESCE(sum(p.amount) FILTER (WHERE p.status = 'confirmed'::text), 0::numeric) AS soma
           FROM receivables r
             LEFT JOIN payments p ON p.receivable_id = r.id
          GROUP BY r.id
        )
 SELECT 'pago_diferente_da_soma'::text AS problema,
    g.id AS receivable_id,
    NULL::uuid AS bank_transaction_id,
    g.description AS descricao,
    g.paid_amount AS gravado,
    g.soma AS calculado
   FROM pagos g
  WHERE g.status <> 'cancelled'::text AND round(COALESCE(g.paid_amount, 0::numeric), 2) <> round(g.soma, 2)
UNION ALL
 SELECT 'situacao_diferente'::text AS problema,
    g.id AS receivable_id,
    NULL::uuid AS bank_transaction_id,
    g.description AS descricao,
    NULL::numeric AS gravado,
    g.soma AS calculado
   FROM pagos g
  WHERE g.status <> 'cancelled'::text AND g.amount > 0::numeric AND
        CASE
            WHEN round(g.soma, 2) >= round(g.amount, 2) THEN 'paid'::text
            WHEN g.soma > 0::numeric THEN 'partially_paid'::text
            ELSE 'aberta'::text
        END <>
        CASE
            WHEN g.status = ANY (ARRAY['pending'::text, 'overdue'::text]) THEN 'aberta'::text
            ELSE g.status
        END
UNION ALL
 SELECT 'entrada_aplicada_a_mais'::text AS problema,
    NULL::uuid AS receivable_id,
    e.bank_transaction_id,
    e.quem AS descricao,
    e.valor AS gravado,
    e.aplicado AS calculado
   FROM recebimentos_do_extrato e
  WHERE e.aplicado > (e.valor + 0.005)
UNION ALL
 SELECT 'conta_ligada_sem_pagamento_da_linha'::text AS problema,
    g.id AS receivable_id,
    g.bank_transaction_id,
    g.description AS descricao,
    NULL::numeric AS gravado,
    NULL::numeric AS calculado
   FROM pagos g
  WHERE g.status <> 'cancelled'::text AND g.bank_transaction_id IS NOT NULL AND NOT (EXISTS ( SELECT 1
           FROM payments p
          WHERE p.receivable_id = g.id AND p.status = 'confirmed'::text AND p.bank_transaction_id = g.bank_transaction_id))
UNION ALL
 SELECT 'linha_aponta_pagamento_de_outra'::text AS problema,
    p.receivable_id,
    t.id AS bank_transaction_id,
    COALESCE(t.counterparty_name, t.description) AS descricao,
    t.amount AS gravado,
    p.amount AS calculado
   FROM bank_transactions t
     JOIN payments p ON p.id = t.reconciled_payment_id
  WHERE p.status = 'confirmed'::text AND p.receivable_id IS NOT NULL AND p.bank_transaction_id IS DISTINCT FROM t.id;
COMMENT ON VIEW public.conferencia_dos_pagamentos IS 'Onde "pago = soma dos pagamentos" e "entrada aplicada ≤ valor da entrada" discordam do que está gravado. Vazia = tudo bate.';
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.conferencia_dos_pagamentos TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.conferencia_dos_pagamentos TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.conferencia_dos_pagamentos TO service_role;

-- ── erp_open_loop_facts ──
CREATE VIEW public.erp_open_loop_facts WITH (security_invoker=on) AS
 SELECT 'client'::text AS entity_type,
    so.client_id AS entity_id,
    'so:'::text || so.id::text AS loop_key,
    'service_order'::text AS kind,
    (('OS '::text || so.service_order_number) || ' — '::text) ||
        CASE so.status
            WHEN 'open'::text THEN 'aberta'::text
            WHEN 'approved'::text THEN 'aprovada, a agendar'::text
            WHEN 'scheduled'::text THEN 'agendada'::text
            WHEN 'in_progress'::text THEN 'em execução'::text
            WHEN 'awaiting_parts'::text THEN 'aguardando peças'::text
            ELSE so.status
        END AS title,
    "left"(COALESCE(so.problem_description, ''::text), 180) AS detail,
    'service_orders'::text AS ref_table,
    so.id AS ref_id,
    so.id AS service_order_id,
    so.scheduled_start_at AS due_at,
        CASE
            WHEN so.status = 'awaiting_parts'::text THEN 'high'::text
            ELSE 'normal'::text
        END AS priority
   FROM service_orders so
  WHERE so.client_id IS NOT NULL AND (so.status = ANY (ARRAY['open'::text, 'approved'::text, 'scheduled'::text, 'in_progress'::text, 'awaiting_parts'::text]))
UNION ALL
 SELECT 'client'::text AS entity_type,
    so.client_id AS entity_id,
    'so-parts:'::text || so.id::text AS loop_key,
    'delivery'::text AS kind,
    ('Materiais da OS '::text || so.service_order_number) || ' a receber'::text AS title,
    (count(DISTINCT poi.id)::text || ' item(ns) pendente(s): '::text) || "left"(string_agg(DISTINCT COALESCE(poi.description, 'item'::text), ', '::text), 150) AS detail,
    'purchase_orders'::text AS ref_table,
    (array_agg(po.id ORDER BY po.expected_date, po.id))[1] AS ref_id,
    so.id AS service_order_id,
    min((po.expected_date::timestamp without time zone AT TIME ZONE 'America/Sao_Paulo'::text)) AS due_at,
        CASE
            WHEN min(po.expected_date) < CURRENT_DATE THEN 'high'::text
            ELSE 'normal'::text
        END AS priority
   FROM purchase_orders po
     JOIN service_orders so ON so.id = po.service_order_id
     JOIN purchase_order_items poi ON poi.purchase_order_id = po.id
  WHERE so.client_id IS NOT NULL AND po.received_date IS NULL AND (COALESCE(po.status, ''::text) <> ALL (ARRAY['cancelled'::text, 'canceled'::text, 'received'::text])) AND COALESCE(poi.received_qty, 0::numeric) < poi.quantity
  GROUP BY so.id, so.client_id, so.service_order_number
UNION ALL
 SELECT 'client'::text AS entity_type,
    q.client_id AS entity_id,
    'quote:'::text || q.id::text AS loop_key,
    'quote'::text AS kind,
    ('Orçamento '::text || COALESCE(q.quote_number, ''::text)) || ' aguardando resposta do cliente'::text AS title,
    "left"(COALESCE(q.problem_description, ''::text), 180) AS detail,
    'external_quotes'::text AS ref_table,
    q.id AS ref_id,
    NULL::uuid AS service_order_id,
    (q.quote_validity_date::timestamp without time zone AT TIME ZONE 'America/Sao_Paulo'::text) AS due_at,
    'normal'::text AS priority
   FROM external_quotes q
  WHERE q.client_id IS NOT NULL AND (q.status = ANY (ARRAY['pending_approval'::text, 'pending_product'::text]))
UNION ALL
 SELECT 'client'::text AS entity_type,
    r.client_id AS entity_id,
    'ar:'::text || r.id::text AS loop_key,
    'receivable'::text AS kind,
    (
        CASE
            WHEN r.due_date < CURRENT_DATE THEN 'Título VENCIDO '::text
            ELSE 'Título a vencer '::text
        END || 'R$ '::text) || translate(to_char(COALESCE(r.balance_amount, r.amount), 'FM999G999G990D00'::text), ',.'::text, '.,'::text) AS title,
    "left"(COALESCE(r.description, ''::text), 180) AS detail,
    'receivables'::text AS ref_table,
    r.id AS ref_id,
    r.service_order_id,
    (r.due_date::timestamp without time zone AT TIME ZONE 'America/Sao_Paulo'::text) AS due_at,
        CASE
            WHEN r.due_date < CURRENT_DATE THEN 'urgent'::text
            ELSE 'high'::text
        END AS priority
   FROM receivables r
  WHERE r.client_id IS NOT NULL AND r.status = 'pending'::text AND r.due_date <= (CURRENT_DATE + 15) AND COALESCE(r.balance_amount, r.amount) > 0::numeric
UNION ALL
 SELECT 'supplier'::text AS entity_type,
    po.supplier_id AS entity_id,
    'po:'::text || po.id::text AS loop_key,
    'purchase_order'::text AS kind,
    ('Compra '::text || COALESCE(po.po_number, ''::text)) || ' aguardando entrega'::text AS title,
    "left"(COALESCE(po.notes, ''::text), 180) AS detail,
    'purchase_orders'::text AS ref_table,
    po.id AS ref_id,
    po.service_order_id,
    (po.expected_date::timestamp without time zone AT TIME ZONE 'America/Sao_Paulo'::text) AS due_at,
        CASE
            WHEN po.expected_date < CURRENT_DATE THEN 'high'::text
            ELSE 'normal'::text
        END AS priority
   FROM purchase_orders po
  WHERE po.supplier_id IS NOT NULL AND po.received_date IS NULL AND (COALESCE(po.status, ''::text) <> ALL (ARRAY['cancelled'::text, 'canceled'::text, 'received'::text]))
UNION ALL
 SELECT 'supplier'::text AS entity_type,
    p.supplier_id AS entity_id,
    'ap:'::text || p.id::text AS loop_key,
    'payable'::text AS kind,
    (
        CASE
            WHEN p.due_date < CURRENT_DATE THEN 'Pagamento VENCIDO '::text
            ELSE 'Pagamento a vencer '::text
        END || 'R$ '::text) || translate(to_char(COALESCE(p.balance_amount, p.amount), 'FM999G999G990D00'::text), ',.'::text, '.,'::text) AS title,
    "left"(COALESCE(p.description, ''::text), 180) AS detail,
    'payables'::text AS ref_table,
    p.id AS ref_id,
    p.linked_service_order_id AS service_order_id,
    (p.due_date::timestamp without time zone AT TIME ZONE 'America/Sao_Paulo'::text) AS due_at,
        CASE
            WHEN p.due_date < CURRENT_DATE THEN 'urgent'::text
            ELSE 'high'::text
        END AS priority
   FROM payables p
  WHERE p.supplier_id IS NOT NULL AND p.status = 'pending'::text AND p.due_date <= (CURRENT_DATE + 15) AND COALESCE(p.balance_amount, p.amount) > 0::numeric;
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.erp_open_loop_facts TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.erp_open_loop_facts TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.erp_open_loop_facts TO service_role;

-- ── extrato_a_tratar ──
CREATE VIEW public.extrato_a_tratar WITH (security_invoker=on) AS
 SELECT v.id,
    v.transaction_date,
    v.description,
    v.amount,
    v.transaction_type,
    v.source_type,
    v.situacao,
    v.e_cartao,
    v.bank_ref_id,
    v.balance_after,
    v.tx_status,
    v.counterparty_name,
    v.counterparty_document,
    v.counterparty_bank,
    v.payment_method,
    v.payment_reason,
    v.merchant_name,
    v.merchant_document,
    v.payee_mcc,
    v.merchant_category,
    v.provider_category,
    v.card_last_digits,
    v.installment_label,
    v.bill_id,
    q.id AS proposta_id,
    q.title AS proposta_titulo,
    q.reasoning AS proposta_motivo,
    q.confidence AS proposta_confianca,
    q.suggested_category AS proposta_categoria,
    q.suggested_supplier_id AS proposta_fornecedor_id,
    q.suggested_client_id AS proposta_cliente_id,
    q.suggested_payee_id AS proposta_favorecido_id,
    q.suggested_description AS proposta_descricao,
    q.dre_group AS proposta_dre_group,
    q.applied_rule_id AS proposta_regra_id
   FROM bank_transactions_situacao v
     LEFT JOIN LATERAL ( SELECT fq.id,
            fq.kind,
            fq.status,
            fq.bank_transaction_id,
            fq.related_transaction_id,
            fq.title,
            fq.reasoning,
            fq.confidence,
            fq.suggested_amount,
            fq.suggested_date,
            fq.suggested_category,
            fq.suggested_supplier_id,
            fq.suggested_client_id,
            fq.suggested_description,
            fq.dre_group,
            fq.created_payable_id,
            fq.created_receivable_id,
            fq.decided_by,
            fq.decided_at,
            fq.decision_note,
            fq.created_at,
            fq.updated_at,
            fq.applied_rule_id,
            fq.suggested_payee_id,
            fq.suggested_service_order_id,
            fq.suggested_purchase_order_id
           FROM finance_review_queue fq
          WHERE fq.bank_transaction_id = v.id AND fq.status = 'pending'::text
          ORDER BY fq.created_at DESC
         LIMIT 1) q ON true
  WHERE v.situacao = ANY (ARRAY['nova'::text, 'sem_rastro'::text]);
COMMENT ON VIEW public.extrato_a_tratar IS 'A fila do Extrato: linhas que o banco trouxe e ainda nao viraram lancamento, com a proposta da IA anexada quando existe. A proposta e atributo da linha, nao a fonte da lista.';
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.extrato_a_tratar TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.extrato_a_tratar TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.extrato_a_tratar TO service_role;

-- ── faturas_do_cartao ──
CREATE VIEW public.faturas_do_cartao WITH (security_invoker=on) AS
 WITH compras AS (
         SELECT bt.bill_id,
            bt.provider_account_id,
            count(*) AS compras,
            min(bt.transaction_date) AS primeira_compra,
            max(bt.transaction_date) AS ultima_compra,
            round(sum(bt.amount), 2) AS total,
            string_agg(DISTINCT bt.card_last_digits, ', '::text ORDER BY bt.card_last_digits) AS cartoes,
            count(*) FILTER (WHERE bt.installment_label IS NOT NULL) AS compras_parceladas
           FROM bank_transactions bt
          WHERE bt.source_type = 'credit_card'::text AND bt.transaction_type = 'debit'::text AND bt.bill_id IS NOT NULL
          GROUP BY bt.bill_id, bt.provider_account_id
        )
 SELECT c.bill_id,
    c.provider_account_id,
    c.compras,
    c.compras_parceladas,
    c.primeira_compra,
    c.ultima_compra,
    c.total,
    c.cartoes,
    pg.id AS pagamento_id,
    pg.transaction_date AS pagamento_data,
    pg.amount AS pagamento_valor,
    pg.description AS pagamento_descricao
   FROM compras c
     LEFT JOIN LATERAL ( SELECT b.id,
            b.transaction_date,
            b.amount,
            b.description
           FROM bank_transactions b
          WHERE b.source_type = 'bank'::text AND b.transaction_type = 'debit'::text AND (b.description ~~* '%FAT%CARTAO%'::text OR b.description ~~* '%FATURA%CART%'::text OR b.description ~~* '%PGTO%CARTAO%'::text) AND round(b.amount::numeric, 2) = c.total AND b.transaction_date >= c.ultima_compra AND b.transaction_date <= (c.ultima_compra + '45 days'::interval)
          ORDER BY b.transaction_date
         LIMIT 1) pg ON true;
COMMENT ON VIEW public.faturas_do_cartao IS 'Uma linha por fatura de cartao (bill_id): compras, periodo, total, cartoes do ciclo e o pagamento no extrato quando o valor casa exatamente. O pagamento e sugestao — o provedor nao entrega esse vinculo. "DEBITO DE CARTAO" (compra no debito) NAO e pagamento de fatura (26/09/2026).';
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.faturas_do_cartao TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.faturas_do_cartao TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.faturas_do_cartao TO service_role;

-- ── product_availability ──
CREATE VIEW public.product_availability WITH (security_invoker=on) AS
 SELECT id,
    name,
    sku,
    unit,
    stock_quantity,
    reserved_quantity,
    stock_quantity - reserved_quantity AS available_quantity
   FROM products;
-- ACL: postgres=arwdDxtm/postgres anon=arwd/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.product_availability TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.product_availability TO anon;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.product_availability TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.product_availability TO service_role;

-- ── service_order_parts_tecnico ──
CREATE VIEW public.service_order_parts_tecnico WITH (security_invoker=on) AS
 SELECT id,
    service_order_id,
    service_order_service_id,
    product_id,
    quantity,
    serial_number,
    notes,
    source,
    warranty_days,
    warranty_months,
    warranty_expires_at,
    created_at,
    updated_at
   FROM service_order_parts;
COMMENT ON VIEW public.service_order_parts_tecnico IS 'Peças da OS sem unit_cost/unit_sale/line_total/desconto (NOVO-008). security_invoker=on.';
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.service_order_parts_tecnico TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.service_order_parts_tecnico TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.service_order_parts_tecnico TO service_role;

-- ── service_order_services_tecnico ──
CREATE VIEW public.service_order_services_tecnico WITH (security_invoker=on) AS
 SELECT id,
    service_order_id,
    service_id,
    name_snapshot,
    description_snapshot,
    billing_unit_snapshot,
    quantity,
    notes,
    technician_user_id,
    started_at,
    finished_at,
    elapsed_minutes,
    service_system,
    service_verb,
    fiscal_verb,
    warranty_days,
    warranty_months,
    warranty_expires_at,
    created_at,
    updated_at,
    technician_instructions,
    field_status,
    field_status_note
   FROM service_order_services;
COMMENT ON VIEW public.service_order_services_tecnico IS 'Serviços da OS sem unit_price/line_total/desconto (NOVO-008). security_invoker=on.';
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.service_order_services_tecnico TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.service_order_services_tecnico TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.service_order_services_tecnico TO service_role;

-- ── service_orders_tecnico ──
CREATE VIEW public.service_orders_tecnico WITH (security_invoker=on) AS
 SELECT id,
    service_order_number,
    client_id,
    vessel_id,
    marina_id,
    requested_by_name,
    requested_by_contact_id,
    scheduled_start_at,
    scheduled_end_at,
    check_in_at,
    check_out_at,
    status,
    quote_status,
    priority,
    service_type,
    problem_description,
    initial_findings,
    diagnosis,
    solution_applied,
    technician_notes,
    internal_notes,
    extra_notes,
    customer_visible_report,
    estimated_hours,
    labor_hours_total,
    travel_distance_km,
    technician_count_for_travel,
    travel_hours,
    travel_type,
    is_travel_billable,
    currency,
    client_signature_url,
    signed_at,
    signed_by_name,
    signed_document_hash,
    requires_resignature,
    resignature_requested_at,
    survey_id,
    estimate_confidence,
    customer_po_number,
    customer_buyer_name,
    quote_validity_days,
    quote_validity_date,
    converted_to_os_at,
    cancelled_at,
    cancellation_reason,
    reopened_at,
    reopen_reason,
    reminder_sent_at,
    created_by,
    created_at,
    updated_at,
    technician_instructions,
    site_access
   FROM service_orders;
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.service_orders_tecnico TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.service_orders_tecnico TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.service_orders_tecnico TO service_role;

-- ── unidentified_contacts ──
CREATE VIEW public.unidentified_contacts WITH (security_invoker=on) AS
 SELECT phone_normalized,
    count(*) AS mensagens,
    max(occurred_at) AS ultima_mensagem,
    (array_agg(body ORDER BY occurred_at DESC) FILTER (WHERE body IS NOT NULL AND body <> ''::text))[1] AS ultima_frase
   FROM whatsapp_messages m
  WHERE client_id IS NULL AND supplier_id IS NULL AND lead_id IS NULL AND phone_normalized IS NOT NULL AND occurred_at > (now() - '90 days'::interval)
  GROUP BY phone_normalized
 HAVING count(*) >= 2
  ORDER BY (count(*)) DESC;
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.unidentified_contacts TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.unidentified_contacts TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.unidentified_contacts TO service_role;

-- ── v_ai_custo_diario ──
CREATE VIEW public.v_ai_custo_diario WITH (security_invoker=on) AS
 WITH base AS (
         SELECT date_trunc('day'::text, m.created_at)::date AS dia,
            COALESCE(m.source, 'web'::text) AS canal,
            m.model AS modelo,
            COALESCE(m.tokens_in, 0) AS tokens_in,
            COALESCE(m.tokens_out, 0) AS tokens_out,
            COALESCE(m.cache_read_tokens, 0) AS cache_lido,
            COALESCE(m.cache_creation_tokens, 0) AS cache_gravado,
            GREATEST(0, COALESCE(m.tokens_in, 0) - COALESCE(m.cache_read_tokens, 0)) AS tokens_preco_cheio,
            m.usd_real
           FROM ai_operator_messages m
          WHERE m.model IS NOT NULL
        ), com_preco AS (
         SELECT b.dia,
            b.canal,
            b.modelo,
            b.tokens_in,
            b.tokens_out,
            b.cache_lido,
            b.cache_gravado,
            b.tokens_preco_cheio,
            b.usd_real,
                CASE
                    WHEN b.modelo ~~ '%haiku%'::text THEN 1.00
                    WHEN b.dia <= '2026-08-31'::date THEN 2.00
                    ELSE 3.00
                END AS usd_entrada_por_milhao,
                CASE
                    WHEN b.modelo ~~ '%haiku%'::text THEN 5.00
                    WHEN b.dia <= '2026-08-31'::date THEN 10.00
                    ELSE 15.00
                END AS usd_saida_por_milhao
           FROM base b
        ), com_custo AS (
         SELECT c_1.dia,
            c_1.canal,
            c_1.modelo,
            c_1.tokens_in,
            c_1.tokens_out,
            c_1.cache_lido,
            c_1.cache_gravado,
            c_1.tokens_preco_cheio,
            c_1.usd_real,
            c_1.usd_entrada_por_milhao,
            c_1.usd_saida_por_milhao,
            (c_1.tokens_preco_cheio::numeric * c_1.usd_entrada_por_milhao + c_1.cache_lido::numeric * c_1.usd_entrada_por_milhao * 0.10 + c_1.cache_gravado::numeric * c_1.usd_entrada_por_milhao * 0.25 + c_1.tokens_out::numeric * c_1.usd_saida_por_milhao) / '1000000'::numeric AS usd_estimado
           FROM com_preco c_1
        )
 SELECT dia,
    canal,
    modelo,
    count(*) AS chamadas,
    count(*) FILTER (WHERE cache_lido = 0) AS chamadas_sem_cache,
    round(100.0 * count(*) FILTER (WHERE cache_lido > 0)::numeric / NULLIF(count(*), 0)::numeric, 1) AS pct_com_cache,
    count(*) FILTER (WHERE usd_real IS NOT NULL) AS chamadas_reconciliadas,
    round(100.0 * count(*) FILTER (WHERE usd_real IS NOT NULL)::numeric / NULLIF(count(*), 0)::numeric, 1) AS pct_reconciliado,
    max(usd_entrada_por_milhao) AS usd_entrada_vigente,
    sum(tokens_in) AS tokens_entrada,
    sum(cache_lido) AS tokens_lidos_do_cache,
    sum(cache_gravado) AS tokens_gravados_no_cache,
    sum(tokens_preco_cheio) AS tokens_preco_cheio,
    sum(tokens_out) AS tokens_saida,
    round(sum(usd_estimado), 4) AS usd_estimado,
    round(sum(usd_real), 4) AS usd_real_parcial,
    round(sum(COALESCE(usd_real, usd_estimado)), 4) AS usd_total,
    round(sum(COALESCE(usd_real, usd_estimado)) / NULLIF(count(*), 0)::numeric, 5) AS usd_por_chamada
   FROM com_custo c
  GROUP BY dia, canal, modelo
  ORDER BY dia DESC, canal;
COMMENT ON VIEW public.v_ai_custo_diario IS 'Custo do agente por dia/canal/modelo. O preco e funcao do DIA: Sonnet 5 a USD 2/10 por milhao ate 31/08/2026 e 3/15 a partir de 01/09 (fim do promocional); Haiku a 1/5 sempre. Leitura de cache 0,1x a entrada; gravacao +25% (TTL de 5 min), ADICIONAL ao preco cheio. usd_total prefere o valor real reconciliado do OpenRouter e so cai na estimativa onde ele falta.';
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.v_ai_custo_diario TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.v_ai_custo_diario TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.v_ai_custo_diario TO service_role;

-- ── v_custo_real_mao_de_obra_por_os ──
CREATE VIEW public.v_custo_real_mao_de_obra_por_os WITH (security_invoker=on) AS
 WITH partes AS (
         SELECT wo.service_order_id,
            ws.id AS shift_id,
            wp.payee_id,
            p.name AS pessoa,
            ws.data,
            ws.fracao,
            ws.valor_dia,
            count(*) OVER (PARTITION BY ws.id) AS n_os
           FROM work_shift_os wo
             JOIN work_shifts ws ON ws.id = wo.shift_id
             JOIN work_profiles wp ON wp.id = ws.work_profile_id
             LEFT JOIN payees p ON p.id = wp.payee_id
          WHERE ws.fracao IS NOT NULL
        )
 SELECT service_order_id,
    round(sum(valor_dia / n_os::numeric), 2) AS custo_real_mao_de_obra,
    round(sum(fracao / n_os::numeric), 2) AS dias_trabalhados,
    count(DISTINCT payee_id) AS pessoas,
    string_agg(DISTINCT pessoa, ', '::text) AS quem_trabalhou,
    min(data) AS primeiro_dia,
    max(data) AS ultimo_dia
   FROM partes
  GROUP BY service_order_id;
COMMENT ON VIEW public.v_custo_real_mao_de_obra_por_os IS 'Custo real de mão de obra de cada OS: o valor dos dias de diarista ligados a ela (work_shift_os), divididos em partes iguais entre as OS do mesmo dia.';
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.v_custo_real_mao_de_obra_por_os TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.v_custo_real_mao_de_obra_por_os TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.v_custo_real_mao_de_obra_por_os TO service_role;

-- ── v_estoque_entradas_pendentes ──
CREATE VIEW public.v_estoque_entradas_pendentes WITH (security_invoker=on) AS
 SELECT id AS product_id,
    name,
    sku,
    brand,
    stock_quantity AS saldo,
    abs(stock_quantity) AS unidades_a_lancar,
    round(abs(stock_quantity) * COALESCE(cost_price, sale_price, 0::numeric), 2) AS custo_estimado,
    is_equipment,
    ( SELECT max(m.created_at) AS max
           FROM inventory_movements m
          WHERE m.product_id = p.id AND m.notes ~~ 'ALERTA:%'::text) AS ultimo_alerta,
    ( SELECT count(*) AS count
           FROM inventory_movements m
          WHERE m.product_id = p.id AND m.notes ~~ 'ALERTA:%'::text) AS vezes_que_ficou_negativo
   FROM products p
  WHERE active AND stock_quantity < 0::numeric
  ORDER BY (abs(stock_quantity) * COALESCE(cost_price, sale_price, 0::numeric)) DESC;
COMMENT ON VIEW public.v_estoque_entradas_pendentes IS 'Peças usadas cuja entrada nunca foi lancada. Politica: avisar, nao bloquear (decisao do dono, 27/07/2026).';
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.v_estoque_entradas_pendentes TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.v_estoque_entradas_pendentes TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.v_estoque_entradas_pendentes TO service_role;

-- ── v_service_order_labor_variance ──
CREATE VIEW public.v_service_order_labor_variance WITH (security_invoker=on) AS
 SELECT so.id,
    so.service_order_number,
    so.client_id,
    so.status,
    (so.estimated_hours * 60::numeric)::integer AS orcado_min,
    COALESCE(sum(st.standard_minutes), 0::bigint)::integer AS padrao_roteiro_min,
    COALESCE(sum(st.actual_minutes), 0::bigint)::integer AS real_min,
    count(st.id) AS passos,
    count(st.id) FILTER (WHERE st.status = 'done'::text) AS passos_feitos,
    count(st.id) FILTER (WHERE st.status = 'blocked'::text) AS passos_travados,
    count(st.id) FILTER (WHERE st.status = 'not_applicable'::text) AS passos_na,
        CASE
            WHEN COALESCE(sum(st.standard_minutes), 0::bigint) > 0 THEN round((COALESCE(sum(st.actual_minutes), 0::bigint) - sum(st.standard_minutes))::numeric / sum(st.standard_minutes)::numeric * 100::numeric, 1)
            ELSE NULL::numeric
        END AS variacao_pct
   FROM service_orders so
     LEFT JOIN service_order_steps st ON st.service_order_id = so.id
  GROUP BY so.id, so.service_order_number, so.client_id, so.status, so.estimated_hours;
COMMENT ON VIEW public.v_service_order_labor_variance IS 'Orçado x padrão do roteiro x real por OS. O tempo aqui é custo, não unidade de faturamento.';
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.v_service_order_labor_variance TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.v_service_order_labor_variance TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.v_service_order_labor_variance TO service_role;

-- ── v_service_order_margin ──
CREATE VIEW public.v_service_order_margin WITH (security_invoker=on) AS
 WITH mo AS (
         SELECT st.service_order_id,
            sum(COALESCE(st.actual_minutes, 0)) AS minutos_reais
           FROM service_order_steps st
          GROUP BY st.service_order_id
        ), mat AS (
         SELECT sop.service_order_id,
            sum(COALESCE(sop.line_total_cost, 0::numeric)) AS custo_material,
            sum(COALESCE(sop.line_total_sale, 0::numeric)) AS venda_material,
            sum(COALESCE(sop.line_total_cost, 0::numeric)) FILTER (WHERE sop.source = 'extra'::text) AS custo_material_extra
           FROM service_order_parts sop
          GROUP BY sop.service_order_id
        ), taxa AS (
         SELECT sos.service_order_id,
            sum(LEAST(COALESCE(sos.line_total, 0::numeric) * (COALESCE(s.supplies_pct, ( SELECT app_settings.value::numeric AS value
                   FROM app_settings
                  WHERE app_settings.key = 'supplies_pct_padrao'::text)) / 100::numeric), COALESCE(s.supplies_cap, ( SELECT app_settings.value::numeric AS value
                   FROM app_settings
                  WHERE app_settings.key = 'supplies_cap_padrao'::text)))) AS taxa_materiais
           FROM service_order_services sos
             LEFT JOIN services s ON s.id = sos.service_id
          GROUP BY sos.service_order_id
        )
 SELECT so.id,
    so.service_order_number,
    so.status,
    so.client_id,
    COALESCE(so.grand_total, 0::numeric) AS faturado,
    round(COALESCE(mo.minutos_reais, 0::bigint)::numeric / 60.0, 2) AS horas_reais,
    round(COALESCE(mo.minutos_reais, 0::bigint)::numeric / 60.0 * COALESCE(so.hourly_rate, 0::numeric), 2) AS custo_mao_de_obra,
    COALESCE(mat.custo_material, 0::numeric) AS custo_material,
    COALESCE(mat.custo_material_extra, 0::numeric) AS custo_material_extra,
    round(COALESCE(taxa.taxa_materiais, 0::numeric), 2) AS taxa_materiais,
    round(COALESCE(so.grand_total, 0::numeric) - COALESCE(mo.minutos_reais, 0::bigint)::numeric / 60.0 * COALESCE(so.hourly_rate, 0::numeric) - COALESCE(mat.custo_material, 0::numeric) - COALESCE(taxa.taxa_materiais, 0::numeric), 2) AS margem_reais,
        CASE
            WHEN COALESCE(so.grand_total, 0::numeric) > 0::numeric THEN round((COALESCE(so.grand_total, 0::numeric) - COALESCE(mo.minutos_reais, 0::bigint)::numeric / 60.0 * COALESCE(so.hourly_rate, 0::numeric) - COALESCE(mat.custo_material, 0::numeric) - COALESCE(taxa.taxa_materiais, 0::numeric)) / so.grand_total * 100::numeric, 1)
            ELSE NULL::numeric
        END AS margem_pct
   FROM service_orders so
     LEFT JOIN mo ON mo.service_order_id = so.id
     LEFT JOIN mat ON mat.service_order_id = so.id
     LEFT JOIN taxa ON taxa.service_order_id = so.id;
COMMENT ON VIEW public.v_service_order_margin IS 'Margem real por OS: faturado menos mão de obra apontada no roteiro, material consumido e taxa de oficina. A hora aqui é CUSTO — a HBR cobra por serviço/visita, não por hora.';
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.v_service_order_margin TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.v_service_order_margin TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.v_service_order_margin TO service_role;

-- ── v_service_systems_status ──
CREATE VIEW public.v_service_systems_status WITH (security_invoker=on) AS
 SELECT slug,
    name,
    short_name,
    is_physical,
    sort,
    active,
    ( SELECT count(*) AS count
           FROM service_step_blocks b
          WHERE b.applies_to_system = ss.slug AND b.block_role = 'abertura'::text AND b.active) AS passos_abertura,
    ( SELECT count(*) AS count
           FROM service_step_blocks b
          WHERE b.applies_to_system = ss.slug AND b.block_role = 'fechamento'::text AND b.active) AS passos_fechamento,
    ( SELECT count(*) AS count
           FROM service_survey_templates t
          WHERE t.applies_to_system = ss.slug AND t.active) AS perguntas,
    ( SELECT count(*) AS count
           FROM services s
          WHERE s.service_system = ss.slug AND s.active) AS servicos
   FROM service_systems ss;
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.v_service_systems_status TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.v_service_systems_status TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.v_service_systems_status TO service_role;

-- ── v_service_verbs_status ──
CREATE VIEW public.v_service_verbs_status WITH (security_invoker=on) AS
 SELECT slug,
    name,
    intervem_no_sistema,
    sort,
    active,
    ( SELECT count(*) AS count
           FROM service_step_blocks b
          WHERE b.applies_to_verb = sv.slug AND b.block_role = 'corpo'::text AND b.active) AS passos_corpo,
    ( SELECT count(*) AS count
           FROM service_survey_templates t
          WHERE t.applies_to_verb = sv.slug AND t.active) AS perguntas,
    ( SELECT count(*) AS count
           FROM services s
          WHERE s.service_verb = sv.slug AND s.active) AS servicos
   FROM service_verbs sv;
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.v_service_verbs_status TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.v_service_verbs_status TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.v_service_verbs_status TO service_role;

-- ── v_services_fiscal_efetivo ──
CREATE VIEW public.v_services_fiscal_efetivo WITH (security_invoker=on) AS
 SELECT s.id,
    s.name,
    s.active,
    s.service_verb,
    s.fiscal_verb,
    COALESCE(s.national_tax_code, f.default_national_tax_code) AS national_tax_code_efetivo,
    COALESCE(s.service_code, f.default_service_code) AS service_code_efetivo,
    COALESCE(s.cnae, f.default_cnae) AS cnae_efetivo,
    COALESCE(s.iss_rate, f.default_iss_rate) AS iss_rate_efetivo,
    COALESCE(s.iss_withheld, f.default_iss_withheld, false) AS iss_withheld_efetivo,
        CASE
            WHEN s.national_tax_code IS NOT NULL THEN 'proprio'::text
            WHEN f.default_national_tax_code IS NOT NULL THEN 'verbo'::text
            ELSE 'nenhum'::text
        END AS code_source,
    COALESCE(s.national_tax_code, f.default_national_tax_code) IS NULL AS sem_codigo_fiscal
   FROM services s
     LEFT JOIN service_fiscal_verbs f ON f.verb_slug = s.fiscal_verb;
COMMENT ON VIEW public.v_services_fiscal_efetivo IS 'Codigo fiscal EFETIVO de cada servico (proprio ou herdado do verbo) e de onde ele veio.
   sem_codigo_fiscal olha o efetivo — o filtro da tela depende disso para nao acusar pendencia
   em servico que ja resolve pelo verbo.';
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.v_services_fiscal_efetivo TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.v_services_fiscal_efetivo TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.v_services_fiscal_efetivo TO service_role;

-- ── vw_os_profitability ──
CREATE VIEW public.vw_os_profitability WITH (security_invoker=on) AS
 WITH os_costs AS (
         SELECT service_order_parts.service_order_id,
            sum(service_order_parts.quantity * service_order_parts.unit_cost_snapshot) AS total_parts_cost
           FROM service_order_parts
          GROUP BY service_order_parts.service_order_id
        ), os_commissions AS (
         SELECT commissions.service_order_id,
            sum(commissions.amount) AS total_commission
           FROM commissions
          WHERE commissions.status <> 'cancelled'::text
          GROUP BY commissions.service_order_id
        ), mao_de_obra AS (
         SELECT v_custo_real_mao_de_obra_por_os.service_order_id,
            v_custo_real_mao_de_obra_por_os.custo_real_mao_de_obra,
            v_custo_real_mao_de_obra_por_os.dias_trabalhados
           FROM v_custo_real_mao_de_obra_por_os
        ), horas_vendidas AS (
         SELECT service_order_services.service_order_id,
            sum(service_order_services.quantity) FILTER (WHERE service_order_services.billing_unit_snapshot = 'hour'::text) AS horas
           FROM service_order_services
          GROUP BY service_order_services.service_order_id
        )
 SELECT so.id AS os_id,
    so.service_order_number,
    so.status,
    so.grand_total AS revenue,
    COALESCE(oc.total_parts_cost, 0::numeric) AS parts_cost,
    COALESCE(so.travel_cost_total, 0::numeric) AS travel_cost,
    COALESCE(so.operational_cost_total, 0::numeric) AS operational_cost,
    COALESCE(com.total_commission, 0::numeric) AS commission_cost,
    so.grand_total - COALESCE(oc.total_parts_cost, 0::numeric) AS gross_profit,
    so.grand_total - COALESCE(oc.total_parts_cost, 0::numeric) - COALESCE(so.travel_cost_total, 0::numeric) - COALESCE(so.operational_cost_total, 0::numeric) - COALESCE(com.total_commission, 0::numeric) - COALESCE(mo.custo_real_mao_de_obra, 0::numeric) AS net_profit,
        CASE
            WHEN so.grand_total > 0::numeric THEN (so.grand_total - COALESCE(oc.total_parts_cost, 0::numeric) - COALESCE(so.travel_cost_total, 0::numeric) - COALESCE(so.operational_cost_total, 0::numeric) - COALESCE(com.total_commission, 0::numeric) - COALESCE(mo.custo_real_mao_de_obra, 0::numeric)) / so.grand_total * 100::numeric
            ELSE 0::numeric
        END AS net_margin_percent,
    so.created_at,
    so.check_out_at AS finished_at,
    c.name AS client_name,
    COALESCE(mo.custo_real_mao_de_obra, 0::numeric) AS labor_cost_real,
    COALESCE(mo.dias_trabalhados, 0::numeric) AS labor_days,
    COALESCE(so.labor_cost_total, 0::numeric) AS labor_sold,
    COALESCE(hv.horas, 0::numeric) AS hours_sold
   FROM service_orders so
     LEFT JOIN os_costs oc ON oc.service_order_id = so.id
     LEFT JOIN os_commissions com ON com.service_order_id = so.id
     LEFT JOIN mao_de_obra mo ON mo.service_order_id = so.id
     LEFT JOIN horas_vendidas hv ON hv.service_order_id = so.id
     LEFT JOIN clients c ON c.id = so.client_id;
-- ACL: postgres=arwdDxtm/postgres authenticated=arwd/postgres service_role=arwdDxtm/postgres
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.vw_os_profitability TO postgres;
GRANT INSERT, SELECT, UPDATE, DELETE ON TABLE public.vw_os_profitability TO authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, m ON TABLE public.vw_os_profitability TO service_role;

