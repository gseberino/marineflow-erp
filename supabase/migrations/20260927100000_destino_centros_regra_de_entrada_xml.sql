-- Etapa de 27/09/2026 — decisões do dono de 26/09/2026:
--   · "3: sigo pela sua sugestão" / "4: confirmado": observação e "para onde foi" na linha do
--     Extrato, centros de custo de verdade, regra de ENTRADA "o Pix do CPF/CNPJ X é do cliente Y";
--   · "3: pode seguir": serviço de terceiro feito para a sede entra como despesa da empresa, não
--     como custo do serviço vendido;
--   · Kamell NF 51038 e TSD NF 132181: a importação do XML ignorava as parcelas e o pagamento com
--     crédito do fornecedor — criava UMA conta com o total, datada do dia da importação.
--
--   · Selo de cobertura do DRE com a mesma regra do fluxo de caixa pelo extrato (seção 7);
--   · "Mês pronto?" sem acusar a parcela da nota como duplicata do pagamento da entrada (seção 8).
--   · Revisão de 27/09/2026: crédito do fornecedor pelos códigos certos (19/21; 05 é crediário),
--     crédito dentro ou fora das parcelas pela soma, e pagamento que parece já ter saído pelo
--     banco vira PERGUNTA na importação (nunca é ligado sozinho).
--
-- Nada aqui apaga dado: centro de custo antigo é DESATIVADO; contas já criadas pela importação
-- não são tocadas (a correção das duas em aberto espera o OK do dono).

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- 1. Centros de custo reais. Os sete de hoje são grupos do DRE (Receitas Operacionais, Custos
--    Variáveis…), não lugares onde o dinheiro é gasto — e só UMA despesa usa um deles.
-- ───────────────────────────────────────────────────────────────────────────────────────────
insert into public.cost_centers (name, type, active)
select v.nome, 'expense', true
  from (values ('Oficina/sede'), ('Obras e reformas da sede'), ('Veículos da empresa'),
               ('Ferramentas e equipamentos próprios'), ('Administrativo'), ('Comercial')) as v(nome)
 where not exists (select 1 from public.cost_centers c where lower(c.name) = lower(v.nome));

update public.cost_centers
   set active = false, updated_at = now()
 where active
   and name in ('Receitas Operacionais', 'Deduções e Impostos', 'Custos Variáveis (CPV/CSV)',
                'Despesas Operacionais Fixas', 'Despesas com Pessoal', 'Despesas Administrativas',
                'Resultado Financeiro (Taxas/Juros)');

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- 2. Serviço de terceiro para a própria HBR: despesa da empresa, fora do custo do serviço.
-- ───────────────────────────────────────────────────────────────────────────────────────────
insert into public.financial_categories (name, type, dre_group, active, description, sort_order)
select 'Serviços de terceiros para a empresa', 'payable', 'despesa_operacional', true,
       'Serviço contratado para a própria HBR: pintura ou obra na sede, veículo, equipamento da empresa. '
       || 'Serviço feito para o trabalho de um cliente é "Serviços de terceiros" (custo do serviço).',
       coalesce((select sort_order from public.financial_categories
                  where name = 'Serviços de terceiros' and type = 'payable' limit 1), 100)
 where not exists (select 1 from public.financial_categories
                    where name = 'Serviços de terceiros para a empresa' and type = 'payable');

update public.financial_categories
   set description = 'Serviço de terceiro feito para o trabalho de um cliente (barco, motorhome, equipamento): '
                  || 'entra no custo do serviço, ligado à OS. Para a própria HBR, use "Serviços de terceiros para a empresa".'
 where name = 'Serviços de terceiros' and type = 'payable';

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- 3. Regra de ENTRADA: "o Pix do CPF/CNPJ X é do cliente Y" (resposta 18). Só por documento,
--    só em entrada, só sugere — a receita continua esperando o OK do dono.
-- ───────────────────────────────────────────────────────────────────────────────────────────
alter table public.finance_rules
  add column if not exists set_client_id uuid references public.clients(id) on delete set null;

alter table public.finance_rules drop constraint if exists finance_rules_cliente_so_por_documento_na_entrada;
alter table public.finance_rules add constraint finance_rules_cliente_so_por_documento_na_entrada
  check (set_client_id is null or (match_type = 'document' and direction = 'credit' and autonomy = 'suggest'));

comment on column public.finance_rules.set_client_id is
  'Regra de entrada: o cliente dono deste CPF/CNPJ. Só com match_type=document, direction=credit e autonomy=suggest.';

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- 4. Parcela paga com crédito do fornecedor não passa pelo banco: não é "sem par no extrato".
--    Mesma visão, mesmas colunas; só a situação ganha 'fora_do_banco'.
-- ───────────────────────────────────────────────────────────────────────────────────────────
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
            WHEN p.bank_transaction_id IS NOT NULL THEN round(p.amount - bt.amount, 2)
            ELSE NULL::numeric
        END AS diferenca,
    p.origin = 'bank_reconciliation'::text OR (EXISTS ( SELECT 1
           FROM finance_review_queue q
          WHERE q.created_payable_id = p.id)) AS nasceu_do_extrato
   FROM payables p
     LEFT JOIN bank_transactions bt ON bt.id = p.bank_transaction_id
     LEFT JOIN suppliers s ON s.id = p.supplier_id
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
            WHEN r.bank_transaction_id IS NOT NULL THEN round(r.amount - bt.amount, 2)
            ELSE NULL::numeric
        END AS diferenca,
    (EXISTS ( SELECT 1
           FROM finance_review_queue q
          WHERE q.created_receivable_id = r.id)) AS nasceu_do_extrato
   FROM receivables r
     LEFT JOIN bank_transactions bt ON bt.id = r.bank_transaction_id
     LEFT JOIN clients c ON c.id = r.client_id
  WHERE r.status <> 'cancelled'::text;

revoke all on public.conciliacao_lancamentos from anon;

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- 5. Importação do XML — uma conta por PARCELA da nota (<dup>), com o vencimento dela, na data de
--    EMISSÃO (competência da compra; nota de mês já fechado entra no mês de hoje). Tudo o mais
--    (produtos, estoque, de-para, sugestões de preço) é o da versão anterior.
--    · Crédito do fornecedor — tPag 19 (crédito virtual) e 21 (crédito em loja, IT 2024.002), ou
--      99 com texto de crédito que não seja cartão nem crediário ("CREDITO DE CLIENTE", "CARTA DE
--      CREDITO"). O 05 é cartão da loja/crediário: é dívida, não crédito. O crédito não é dívida nem
--      sai do banco. DENTRO das parcelas (a soma delas é o total da nota: uma parcela é a paga com
--      crédito — Kamell 51038) ou FORA (parcelas + crédito = total): nos dois casos entra paga e
--      fora do banco. Não bate com nada: as parcelas ficam como estão e a conta leva o aviso.
--    · Pagamento que parece JÁ ter saído pelo banco (mesmo fornecedor, mesmo valor, até 7 dias do
--      vencimento, depois da emissão — ou até 3 dias antes, sinal —, lançado pelo Extrato e sem
--      nota) NÃO é ligado sozinho: vira pergunta na tela da importação ("É este?"), e só o "sim"
--      liga (ligar_parcela_ao_pagamento). Decisão do dono de 26/09/2026: "o sistema deve sempre
--      questionar". Foi o que contou duas vezes os R$ 1.500 da TSD em 22/09.
-- ───────────────────────────────────────────────────────────────────────────────────────────

-- Pagamentos lançados pelo Extrato que podem ser uma parcela (uso interno da importação).
create or replace function public._pagamentos_que_podem_ser_a_parcela(
  p_fornecedor uuid, p_valor numeric, p_venc date, p_emissao date)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'payable_id', p.id, 'data', p.issue_date, 'valor', p.amount,
           'descricao', left(coalesce(p.description, ''), 120))
           order by abs(p.issue_date - p_venc), p.created_at), '[]'::jsonb)
    from public.payables p
   where p.supplier_id = p_fornecedor
     and p.fiscal_note_id is null
     and p.status <> 'cancelled'
     and p.bank_transaction_id is not null
     and abs(p.amount - p_valor) < 0.01
     and abs(p.issue_date - p_venc) <= 7
     and p.issue_date >= p_emissao - 3;
$function$;

revoke all on function public._pagamentos_que_podem_ser_a_parcela(uuid, numeric, date, date) from public, anon, authenticated;
grant execute on function public._pagamentos_que_podem_ser_a_parcela(uuid, numeric, date, date) to service_role;

CREATE OR REPLACE FUNCTION public.confirm_nfe_import(p_note_id uuid, p_supplier_id uuid DEFAULT NULL::uuid, p_manual_mappings jsonb DEFAULT '[]'::jsonb, p_purchase_order_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_status      text;
  v_items       jsonb;
  v_total       numeric;
  v_nfe_number  text;
  v_issuer_name text;
  v_xml         text;
  v_issue_ts    timestamptz;
  v_issued_ts   timestamptz;
  v_item        RECORD;
  v_match       RECORD;
  v_manual      uuid;
  v_forcar      boolean;
  v_product_id  uuid;
  v_reason      text;
  v_created     int := 0;
  v_moved       int := 0;
  v_payable_id  uuid;
  v_margin      numeric;
  v_cat_id      uuid;
  v_old_cost    numeric;
  v_sale        numeric;
  v_detail      jsonb := '[]'::jsonb;
  v_prazo       int;
  -- Parcelas
  v_emissao_real   date;
  v_emissao        date;
  v_a_vista        boolean := false;
  v_desc_base      text;
  v_dup            RECORD;
  v_n_dups         int := 0;
  v_soma_dups      numeric := 0;
  v_parcela        int := 0;
  v_credito        numeric := 0;
  v_credito_dentro boolean := false;
  v_credito_fora   boolean := false;
  v_credito_usado  boolean := false;
  v_venc           date;
  v_cand           jsonb;
  v_ids            uuid[] := '{}';
  v_parcelas       jsonb := '[]'::jsonb;
  c_obs_credito    constant text := 'Paga com crédito do fornecedor (carta de crédito), como a nota informa: não sai do banco.';
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT status, items, total_amount, nfe_number, issuer_name, xml_content, issue_date, issued_at
    INTO v_status, v_items, v_total, v_nfe_number, v_issuer_name, v_xml, v_issue_ts, v_issued_ts
    FROM fiscal_notes WHERE id = p_note_id
    FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Nota fiscal não encontrada.';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Esta nota já foi processada ou cancelada (status: %).', v_status;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_to_recordset(v_items) AS x(
    index int, description text, quantity numeric, unit_price numeric
  ) LOOP
    IF v_item.quantity IS NULL OR v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Item % (%): quantidade ausente ou inválida no XML. Confira o arquivo.',
        coalesce(v_item.index, 0), coalesce(v_item.description, 'sem descrição');
    END IF;
    IF v_item.unit_price IS NULL OR v_item.unit_price < 0 THEN
      RAISE EXCEPTION 'Item % (%): valor unitário ausente ou inválido no XML.',
        coalesce(v_item.index, 0), coalesce(v_item.description, 'sem descrição');
    END IF;
  END LOOP;

  FOR v_item IN SELECT * FROM jsonb_to_recordset(v_items) AS x(
    index int, sku_supplier text, description text, ncm text, unit text,
    quantity numeric, unit_price numeric, total_price numeric,
    barcode text, origin text
  ) LOOP
    v_manual := NULL; v_forcar := false;
    SELECT (val->>'internal_product_id')::uuid, coalesce((val->>'force_new')::boolean, false)
      INTO v_manual, v_forcar
      FROM jsonb_array_elements(coalesce(p_manual_mappings, '[]'::jsonb)) AS val
      WHERE val->>'sku_supplier' = v_item.sku_supplier
      LIMIT 1;

    IF v_forcar THEN
      v_product_id := NULL; v_reason := 'novo';
    ELSE
      SELECT * INTO v_match FROM match_nfe_item(
        p_supplier_id, v_item.barcode, v_item.sku_supplier, v_item.description, v_manual);
      v_product_id := v_match.product_id;
      v_reason     := v_match.match_reason;
    END IF;

    IF v_product_id IS NULL THEN
      SELECT id, coalesce(default_profit_margin, 30) INTO v_cat_id, v_margin
        FROM product_categories WHERE lower(name) = 'importados' AND active LIMIT 1;
      v_margin := coalesce(v_margin, 30);

      INSERT INTO products (
        name, sku, barcode, category, product_category_id, unit,
        cost_price, sale_price, stock_quantity, ncm, fiscal_origin,
        supplier_id, active, fiscal_complete
      ) VALUES (
        v_item.description,
        v_item.sku_supplier,
        v_item.barcode,
        'Importados',
        v_cat_id,
        coalesce(nullif(btrim(v_item.unit), ''), 'UN'),
        v_item.unit_price,
        round(v_item.unit_price * (1 + v_margin / 100), 2),
        0,
        regexp_replace(coalesce(v_item.ncm, ''), '\D', '', 'g'),
        coalesce(nullif(regexp_replace(coalesce(v_item.origin, ''), '\D', '', 'g'), '')::int, 0),
        p_supplier_id,
        true,
        false
      ) RETURNING id INTO v_product_id;
      v_created := v_created + 1;
    ELSE
      UPDATE products
         SET barcode = coalesce(barcode, nullif(v_item.barcode, '')),
             supplier_id = coalesce(supplier_id, p_supplier_id),
             updated_at = now()
       WHERE id = v_product_id;
    END IF;

    IF p_supplier_id IS NOT NULL AND coalesce(v_item.sku_supplier, '') <> '' THEN
      INSERT INTO supplier_product_mappings (supplier_id, supplier_sku, supplier_description, internal_product_id)
      VALUES (p_supplier_id, v_item.sku_supplier, v_item.description, v_product_id)
      ON CONFLICT (supplier_id, supplier_sku) DO UPDATE
        SET supplier_description = EXCLUDED.supplier_description,
            internal_product_id  = EXCLUDED.internal_product_id,
            updated_at = now();
    END IF;

    INSERT INTO inventory_movements (
      product_id, movement_type, quantity_delta, unit_cost_snapshot,
      reference_type, reference_id, notes
    ) VALUES (
      v_product_id, 'purchase', v_item.quantity, v_item.unit_price,
      'import', p_note_id, 'Entrada via NF-e ' || coalesce(v_nfe_number, '')
    );
    v_moved := v_moved + 1;

    SELECT cost_price, sale_price INTO v_old_cost, v_sale FROM products WHERE id = v_product_id;
    SELECT coalesce(default_profit_margin, 30) INTO v_margin
      FROM product_categories pc
      JOIN products p ON p.id = v_product_id
      WHERE pc.id = p.product_category_id OR lower(pc.name) = lower(p.category)
      LIMIT 1;
    v_margin := coalesce(v_margin, 30);
    IF v_item.unit_price > coalesce(v_old_cost, 0)
       OR coalesce(v_sale, 0) < v_item.unit_price * (1 + v_margin / 100) THEN
      INSERT INTO price_update_suggestions (
        product_id, fiscal_note_id, current_sale_price, suggested_sale_price, margin_percent
      ) VALUES (
        v_product_id, p_note_id, v_sale,
        round(v_item.unit_price * (1 + v_margin / 100), 2), v_margin
      );
    END IF;

    UPDATE products
       SET cost_price = v_item.unit_price,
           stock_quantity = coalesce(stock_quantity, 0) + v_item.quantity,
           last_stock_entry_at = now(),
           updated_at = now()
     WHERE id = v_product_id;

    v_detail := v_detail || jsonb_build_object(
      'sku_supplier', v_item.sku_supplier,
      'description',  v_item.description,
      'product_id',   v_product_id,
      'match_reason', v_reason,
      'quantity',     v_item.quantity
    );
  END LOOP;

  IF p_supplier_id IS NOT NULL THEN
    SELECT nullif(regexp_replace(coalesce(payment_terms, ''), '\D', '', 'g'), '')::int
      INTO v_prazo FROM suppliers WHERE id = p_supplier_id;
    IF v_prazo IS NULL OR v_prazo <= 0 OR v_prazo > 365 THEN v_prazo := 28; END IF;

    -- A data da NOTA: o dia local que o próprio XML diz; sem ele, o gravado, no fuso de São Paulo.
    v_emissao_real := coalesce(
      nullif(substring(coalesce(v_xml, '') from '<dhEmi>(\d{4}-\d{2}-\d{2})'), '')::date,
      nullif(substring(coalesce(v_xml, '') from '<dEmi>(\d{4}-\d{2}-\d{2})'), '')::date,
      (v_issued_ts AT TIME ZONE 'America/Sao_Paulo')::date,
      (v_issue_ts AT TIME ZONE 'America/Sao_Paulo')::date,
      now()::date);
    -- A competência: nota de mês já FECHADO entra no mês de hoje — o fechado não muda sem motivo,
    -- e a mercadoria não pode ficar fora do estoque porque a trava recusaria a conta. A data real
    -- continua valendo para os vencimentos e para achar o pagamento no banco.
    v_emissao := v_emissao_real;
    IF public.periodo_esta_fechado(v_emissao) THEN
      v_emissao := now()::date;
    END IF;
    v_desc_base := 'Compra ref. NF-e ' || coalesce(v_nfe_number, '') || ' - ' || coalesce(v_issuer_name, '');

    -- Quanto a nota diz ter sido pago com crédito do fornecedor.
    SELECT coalesce(sum(nullif(substring(b[1] from '<vPag>([0-9.]+)</vPag>'), '')::numeric), 0)
      INTO v_credito
      FROM regexp_matches(coalesce(v_xml, ''), '<detPag>(.*?)</detPag>', 'g') AS b
     WHERE substring(b[1] from '<tPag>(\d+)</tPag>') IN ('19', '21')
        OR (substring(b[1] from '<tPag>(\d+)</tPag>') = '99'
            AND translate(upper(coalesce(substring(b[1] from '<xPag>([^<]*)</xPag>'), '')),
                          'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC')
                ~ '(CARTA DE CREDITO|CREDITO (DE|DO|DA|EM|NA) (CLIENTE|LOJA|FORNECEDOR|DEVOLUCAO)|CREDITO LOJA|VALE CREDITO)'
            AND translate(upper(coalesce(substring(b[1] from '<xPag>([^<]*)</xPag>'), '')),
                          'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC')
                !~ '(CARTAO|CREDIARIO)');

    -- Pago na hora (à vista, ou por Pix/débito/transferência/cartão): sem parcela, vence na emissão.
    SELECT exists (
      SELECT 1 FROM regexp_matches(coalesce(v_xml, ''), '<detPag>(.*?)</detPag>', 'g') AS b
       WHERE substring(b[1] from '<indPag>(\d)</indPag>') = '0'
          OR substring(b[1] from '<tPag>(\d+)</tPag>') IN ('01', '03', '04', '17', '18', '20'))
      INTO v_a_vista;

    SELECT count(*), coalesce(sum(nullif(substring(d[1] from '<vDup>([0-9.]+)</vDup>'), '')::numeric), 0)
      INTO v_n_dups, v_soma_dups
      FROM regexp_matches(coalesce(v_xml, ''), '<dup>(.*?)</dup>', 'g') AS d;

    -- Onde está o crédito: DENTRO das parcelas (a soma delas é o total) ou FORA delas.
    IF v_credito > 0 THEN
      v_credito_dentro := v_n_dups > 0 AND abs(v_soma_dups - v_total) < 0.05;
      v_credito_fora := NOT v_credito_dentro AND abs(v_soma_dups + v_credito - v_total) < 0.05;
    END IF;

    -- Crédito FORA das parcelas (ou a nota inteira paga com crédito): uma conta paga, à parte.
    IF v_credito_fora THEN
      INSERT INTO payables (
        supplier_id, supplier_name, amount, paid_amount, balance_amount, description,
        issue_date, due_date, status, expense_category, origin, fiscal_note_id, payment_method, notes
      ) VALUES (
        p_supplier_id, v_issuer_name, v_credito, v_credito, 0,
        v_desc_base || CASE WHEN v_n_dups > 0 THEN ' (parte paga com crédito)' ELSE '' END,
        v_emissao, v_emissao_real, 'paid', 'Compras de mercadorias', 'fiscal_note', p_note_id,
        'credito_fornecedor', c_obs_credito
      ) RETURNING id INTO v_payable_id;
      v_credito_usado := true;
      v_ids := v_ids || v_payable_id;
      v_parcelas := v_parcelas || jsonb_build_object('parcela', 0, 'valor', v_credito, 'vencimento', v_emissao_real,
        'payable_id', v_payable_id, 'como', 'credito_do_fornecedor', 'candidatos', '[]'::jsonb);
    END IF;

    IF v_n_dups > 0 THEN
      FOR v_dup IN
        SELECT substring(d[1] from '<nDup>([^<]*)</nDup>') AS numero,
               nullif(substring(d[1] from '<dVenc>(\d{4}-\d{2}-\d{2})</dVenc>'), '')::date AS venc,
               nullif(substring(d[1] from '<vDup>([0-9.]+)</vDup>'), '')::numeric AS valor
          FROM regexp_matches(v_xml, '<dup>(.*?)</dup>', 'g') AS d
         ORDER BY 2 NULLS LAST, 1
      LOOP
        v_parcela := v_parcela + 1;
        CONTINUE WHEN v_dup.valor IS NULL OR v_dup.valor <= 0;

        IF v_credito_dentro AND NOT v_credito_usado AND abs(v_dup.valor - v_credito) < 0.01 THEN
          -- A parcela que a própria nota diz ter sido paga com crédito do fornecedor.
          INSERT INTO payables (
            supplier_id, supplier_name, amount, paid_amount, balance_amount, description,
            issue_date, due_date, status, expense_category, origin, fiscal_note_id, payment_method, notes
          ) VALUES (
            p_supplier_id, v_issuer_name, v_dup.valor, v_dup.valor, 0,
            v_desc_base || ' (parcela ' || v_parcela || '/' || v_n_dups || ')',
            v_emissao, coalesce(v_dup.venc, v_emissao_real), 'paid', 'Compras de mercadorias', 'fiscal_note', p_note_id,
            'credito_fornecedor', c_obs_credito
          ) RETURNING id INTO v_payable_id;
          v_credito_usado := true;
          v_parcelas := v_parcelas || jsonb_build_object('parcela', v_parcela, 'valor', v_dup.valor,
            'vencimento', v_dup.venc, 'payable_id', v_payable_id, 'como', 'credito_do_fornecedor',
            'candidatos', '[]'::jsonb);
        ELSE
          v_venc := coalesce(v_dup.venc, v_emissao_real + v_prazo);
          v_cand := public._pagamentos_que_podem_ser_a_parcela(p_supplier_id, v_dup.valor, v_venc, v_emissao_real);
          INSERT INTO payables (
            supplier_id, supplier_name, amount, balance_amount, description,
            issue_date, due_date, status, expense_category, origin, fiscal_note_id, notes
          ) VALUES (
            p_supplier_id, v_issuer_name, v_dup.valor, v_dup.valor,
            v_desc_base || ' (parcela ' || v_parcela || '/' || v_n_dups || ')',
            v_emissao, v_venc, 'pending', 'Compras de mercadorias', 'fiscal_note', p_note_id,
            CASE WHEN jsonb_array_length(v_cand) > 0
              THEN 'Pode já ter sido paga: há pagamento de mesmo valor a este fornecedor, lançado pelo Extrato. Confirme na importação da nota.'
            END
          ) RETURNING id INTO v_payable_id;
          v_parcelas := v_parcelas || jsonb_build_object('parcela', v_parcela, 'valor', v_dup.valor,
            'vencimento', v_venc, 'payable_id', v_payable_id, 'como', 'a_pagar', 'candidatos', v_cand);
        END IF;
        v_ids := v_ids || v_payable_id;
      END LOOP;
    ELSIF NOT v_credito_fora THEN
      -- Sem parcelas na nota: uma conta com o total — à vista vence na emissão; a prazo, no prazo
      -- do fornecedor a partir da emissão.
      v_venc := CASE WHEN v_a_vista THEN v_emissao_real ELSE v_emissao_real + v_prazo END;
      v_cand := public._pagamentos_que_podem_ser_a_parcela(p_supplier_id, v_total, v_emissao_real, v_emissao_real);
      INSERT INTO payables (
        supplier_id, supplier_name, amount, balance_amount, description,
        issue_date, due_date, status, expense_category, origin, fiscal_note_id, notes
      ) VALUES (
        p_supplier_id, v_issuer_name, v_total, v_total, v_desc_base,
        v_emissao, v_venc, 'pending', 'Compras de mercadorias', 'fiscal_note', p_note_id,
        CASE WHEN jsonb_array_length(v_cand) > 0
          THEN 'Pode já ter sido paga: há pagamento de mesmo valor a este fornecedor, lançado pelo Extrato. Confirme na importação da nota.'
        END
      ) RETURNING id INTO v_payable_id;
      v_ids := v_ids || v_payable_id;
      v_parcelas := v_parcelas || jsonb_build_object('parcela', 1, 'valor', v_total, 'vencimento', v_venc,
        'payable_id', v_payable_id, 'como', 'a_pagar', 'candidatos', v_cand);
    END IF;

    -- Crédito que não bate com nada: as parcelas ficam como estão, e a primeira conta leva o aviso.
    IF v_credito > 0 AND NOT v_credito_usado AND array_length(v_ids, 1) > 0 THEN
      UPDATE payables
         SET notes = btrim(coalesce(notes, '') || ' A nota informa R$ '
                     || replace(to_char(v_credito, 'FM999999990.00'), '.', ',')
                     || ' pagos com crédito do fornecedor, e o valor não bate com as parcelas: confira.')
       WHERE id = v_ids[1];
    END IF;

    v_payable_id := v_ids[1];
  END IF;

  UPDATE fiscal_notes
     SET status = 'confirmed',
         confirmed_at = now(),
         supplier_id = coalesce(p_supplier_id, supplier_id),
         purchase_order_id = coalesce(p_purchase_order_id, purchase_order_id),
         import_result = jsonb_build_object(
           'items', v_detail, 'products_created', v_created,
           'movements', v_moved, 'payable_id', v_payable_id,
           'payable_ids', to_jsonb(v_ids), 'parcelas', v_parcelas,
           'credito_sem_par', v_credito > 0 AND NOT v_credito_usado, 'at', now()
         ),
         updated_at = now()
   WHERE id = p_note_id;

  RETURN jsonb_build_object(
    'success', true,
    'products_created', v_created,
    'movements_created', v_moved,
    'payable_id', v_payable_id,
    'payable_ids', to_jsonb(v_ids),
    'parcelas', v_parcelas,
    'credito_sem_par', v_credito > 0 AND NOT v_credito_usado,
    'items', v_detail
  );
END;
$function$;

-- A função é SECURITY DEFINER e só barra quem está LOGADO sem ser admin: anônimo não pode chegar.
revoke all on function public.confirm_nfe_import(uuid, uuid, jsonb, uuid) from public, anon;
grant execute on function public.confirm_nfe_import(uuid, uuid, jsonb, uuid) to authenticated, service_role;

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- 6. "Desfazer importação" acompanha as parcelas. Antes apagava só as contas sem pagamento: a
--    parcela paga com crédito do fornecedor sobraria, e o pagamento que foi LIGADO à nota
--    continuaria ligado — reimportar a nota duplicaria as duas. Agora: sai o que a importação
--    CRIOU (a pagar e a paga com crédito), volta a ficar sem nota o que foi só ligado (e a marca
--    "[NF-e …]" sai da observação dele), e parcela paga de verdade pela nota (Registrar
--    pagamento) pede para desfazer o pagamento antes.
-- ───────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.revert_nfe_import(p_note_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_status     text;
  v_mov        RECORD;
  v_undone     int := 0;
  v_payable    int := 0;
  v_desligadas int := 0;
  v_pago       numeric;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT status INTO v_status FROM fiscal_notes WHERE id = p_note_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Nota fiscal não encontrada.';
  END IF;
  IF v_status <> 'confirmed' THEN
    RAISE EXCEPTION 'Só é possível desfazer uma importação confirmada (status: %).', v_status;
  END IF;

  -- Parcela criada pela importação e já paga de verdade: desfazer apagaria o registro do
  -- pagamento, e reimportar criaria a parcela de novo.
  SELECT coalesce(sum(paid_amount), 0) INTO v_pago
    FROM payables
   WHERE fiscal_note_id = p_note_id AND origin = 'fiscal_note' AND status <> 'cancelled'
     AND coalesce(paid_amount, 0) > 0
     AND payment_method IS DISTINCT FROM 'credito_fornecedor';
  IF v_pago > 0 THEN
    RAISE EXCEPTION 'Esta nota tem parcela já paga (R$ %). Desfaça o pagamento antes de desfazer a importação.',
      replace(to_char(v_pago, 'FM999999990.00'), '.', ',');
  END IF;

  FOR v_mov IN
    SELECT product_id, quantity_delta FROM inventory_movements
     WHERE reference_type = 'import' AND reference_id = p_note_id
  LOOP
    UPDATE products
       SET stock_quantity = coalesce(stock_quantity, 0) - v_mov.quantity_delta,
           updated_at = now()
     WHERE id = v_mov.product_id;
    v_undone := v_undone + 1;
  END LOOP;

  DELETE FROM inventory_movements WHERE reference_type = 'import' AND reference_id = p_note_id;

  -- O que a importação criou: a pagar (sem pagamento) e a parcela paga com crédito do fornecedor.
  -- Conta cancelada fica (é trilha de uma decisão), só deixa de apontar para a nota.
  DELETE FROM payables
   WHERE fiscal_note_id = p_note_id AND origin = 'fiscal_note' AND status <> 'cancelled'
     AND (coalesce(paid_amount, 0) = 0 OR payment_method = 'credito_fornecedor');
  GET DIAGNOSTICS v_payable = ROW_COUNT;

  -- O que foi só ligado (o pagamento que já tinha saído pelo banco) e o que foi cancelado voltam a
  -- ficar sem nota — senão a reimportação não reconheceria o pagamento e criaria a parcela de novo.
  UPDATE payables
     SET fiscal_note_id = NULL,
         notes = nullif(btrim(regexp_replace(coalesce(notes, ''), '\s*\[NF-e [^]]*\]', '', 'g')), ''),
         updated_at = now()
   WHERE fiscal_note_id = p_note_id AND (origin <> 'fiscal_note' OR status = 'cancelled');
  GET DIAGNOSTICS v_desligadas = ROW_COUNT;

  DELETE FROM price_update_suggestions WHERE fiscal_note_id = p_note_id;

  UPDATE fiscal_notes
     SET status = 'pending', confirmed_at = NULL, import_result = NULL, updated_at = now()
   WHERE id = p_note_id;

  RETURN jsonb_build_object(
    'success', true, 'movements_reverted', v_undone, 'payables_removed', v_payable,
    'payables_desligadas', v_desligadas
  );
END;
$function$;

revoke all on function public.revert_nfe_import(uuid) from public, anon;
grant execute on function public.revert_nfe_import(uuid) to authenticated, service_role;

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- 6b. "É este?" — a pergunta da importação respondida com SIM: o pagamento que já tinha saído pelo
--     banco passa a ser aquela parcela da nota (ligado a ela, com a marca "[NF-e …]" na
--     observação), e a parcela a pagar que a importação criou sai. Tudo conferido de novo aqui:
--     parcela ainda a pagar e criada pela importação; pagamento lançado pelo Extrato, sem nota,
--     do MESMO fornecedor e do MESMO valor.
-- ───────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.ligar_parcela_ao_pagamento(p_parcela uuid, p_pagamento uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_parc   public.payables%rowtype;
  v_pag    public.payables%rowtype;
  v_numero text;
  v_qual   text;
begin
  if auth.uid() is not null and not public.is_admin(auth.uid()) then
    raise exception 'forbidden';
  end if;

  select * into v_parc from public.payables where id = p_parcela for update;
  select * into v_pag from public.payables where id = p_pagamento for update;
  if v_parc.id is null or v_pag.id is null then
    raise exception 'Parcela ou pagamento não encontrado — nada foi ligado.';
  end if;
  if v_parc.origin <> 'fiscal_note' or v_parc.fiscal_note_id is null or v_parc.status <> 'pending'
     or coalesce(v_parc.paid_amount, 0) > 0 then
    raise exception 'Esta parcela não está mais a pagar — nada foi ligado.';
  end if;
  if v_pag.bank_transaction_id is null or v_pag.fiscal_note_id is not null or v_pag.status = 'cancelled' then
    raise exception 'Este pagamento não está livre para ser ligado a uma nota — nada foi ligado.';
  end if;
  if v_pag.supplier_id is distinct from v_parc.supplier_id or abs(v_pag.amount - v_parc.amount) >= 0.01 then
    raise exception 'Fornecedor ou valor diferentes — não é a mesma parcela. Nada foi ligado.';
  end if;

  select nfe_number into v_numero from public.fiscal_notes where id = v_parc.fiscal_note_id;
  v_qual := coalesce(substring(v_parc.description from '\((parcela [0-9]+/[0-9]+)\)'), 'à vista');

  update public.payables
     set fiscal_note_id = v_parc.fiscal_note_id,
         notes = btrim(coalesce(notes, '') || ' [NF-e ' || coalesce(v_numero, '') || ', ' || v_qual
                 || ': paga por este pagamento]'),
         updated_at = now()
   where id = p_pagamento;
  delete from public.payables where id = p_parcela;

  insert into public.reconciliation_log (acao, autor, payable_id, bank_transaction_id, valor, detalhe)
  values ('ligou_parcela_da_nota', auth.uid(), p_pagamento, v_pag.bank_transaction_id, v_pag.amount,
          left('NF-e ' || coalesce(v_numero, '') || ', ' || v_qual || ': o pagamento lançado pelo Extrato é esta parcela '
               || '(confirmado na importação da nota); a parcela a pagar que a importação criou saiu.', 300));

  return jsonb_build_object('ok', true, 'pagamento', p_pagamento, 'nota', v_parc.fiscal_note_id);
end;
$function$;

revoke all on function public.ligar_parcela_ao_pagamento(uuid, uuid) from public, anon;
grant execute on function public.ligar_parcela_ao_pagamento(uuid, uuid) to authenticated, service_role;

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- 7. Selo de cobertura do DRE com a MESMA regra do fluxo de caixa pelo extrato
--    (src/lib/fluxo-de-caixa.ts): só conta corrente e Caixa; fora duplicata, estornada, a
--    importação manual de 27/07 (sem conta ligada), pendente e data futura; transferência entre
--    contas e crédito do cartão na conta não são entrada nem saída. E conta cancelada não é
--    despesa lançada — as três notas da Kamell canceladas em 26/09 ainda contavam em julho.
-- ───────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.dre_cobertura(p_ano integer)
 returns table(mes integer, receita_lancada numeric, entrada_banco numeric, despesa_lancada numeric, saida_banco numeric)
 language sql
 stable
 set search_path to 'public'
as $function$
  with meses as (select generate_series(1, 12) m),
  rec as (
    select extract(month from issue_date)::int m, sum(amount) total
      from public.receivables
     where extract(year from issue_date) = p_ano
       and coalesce(status, '') <> 'cancelled'
     group by 1
  ),
  pag as (
    select extract(month from issue_date)::int m, sum(amount) total
      from public.payables
     where extract(year from issue_date) = p_ano
       and coalesce(status, '') <> 'cancelled'
     group by 1
  ),
  banco as (
    select extract(month from transaction_date)::int m,
           sum(amount) filter (where transaction_type = 'credit') entradas,
           sum(amount) filter (where transaction_type = 'debit') saidas
      from public.bank_transactions
     where extract(year from transaction_date) = p_ano
       and coalesce(source_type, 'bank') in ('bank', 'cash')
       and coalesce(tx_status, '') <> 'PENDING'
       and coalesce(dismissed_kind, '') not in ('duplicata', 'estornada', 'transferencia', 'mecanica_cartao')
       and not (coalesce(provider, '') = 'manual' and bank_connection_id is null)
       and transaction_date <= current_date
     group by 1
  )
  select meses.m,
         coalesce(rec.total, 0)::numeric,
         coalesce(banco.entradas, 0)::numeric,
         coalesce(pag.total, 0)::numeric,
         coalesce(banco.saidas, 0)::numeric
    from meses
    left join rec on rec.m = meses.m
    left join pag on pag.m = meses.m
    left join banco on banco.m = meses.m
   order by meses.m;
$function$;

revoke all on function public.dre_cobertura(integer) from public, anon;
grant execute on function public.dre_cobertura(integer) to authenticated, service_role;

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- 8. "Mês pronto?" — o item "Nenhuma despesa lançada em dobro" com as parcelas da nota. A parcela
--    nasce com a data da NOTA; comparar essa data com a do pagamento da entrada (no mesmo dia, do
--    mesmo valor) acusava duplicata onde não havia. Conta em aberto se compara pelo VENCIMENTO;
--    pagamento já ligado à nota não é duplicata das outras parcelas dela; e a parte paga com
--    crédito do fornecedor não tem par no banco. O resto da função é o de produção, sem mudança.
-- ───────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.checklist_do_mes(p_ano integer, p_mes integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_ini date := make_date(p_ano, p_mes, 1);
  v_fim date := (make_date(p_ano, p_mes, 1) + interval '1 month - 1 day')::date;
  v_itens jsonb := '[]'::jsonb;
  v_n integer;
  v_valor numeric;
  v_det text;
begin
  -- 1. Saldo de cada conta confere com o banco (a última conferência).
  select count(*), string_agg(c.label || ' difere ' || public._brl(abs(k.diferenca)), '; ')
    into v_n, v_det
    from public.bank_connections c
    join lateral (select * from public.bank_balance_checks b where b.bank_connection_id = c.id
                   order by b.conferido_em desc limit 1) k on true
   where coalesce(c.active, true) and not k.fecha;
  v_itens := v_itens || jsonb_build_object('chave', 'saldo_confere', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'O saldo de cada conta confere com o banco', 'quantidade', v_n,
    'detalhe', coalesce(v_det, 'Todas as contas conferem na última sincronização.'));

  -- 2. Nada do extrato do mês sem destino (nem lançado, nem casado, nem fora da fila).
  select count(*), coalesce(sum(t.amount), 0) into v_n, v_valor
    from public.bank_transactions_situacao t
   where t.transaction_date between v_ini and v_fim and t.situacao = 'nova'
     and coalesce(t.tx_status, '') <> 'PENDING';
  v_itens := v_itens || jsonb_build_object('chave', 'extrato_tratado', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'Todo movimento do banco no mês tem destino', 'quantidade', v_n, 'valor', v_valor,
    'detalhe', case when v_n = 0 then 'Nada esperando no Extrato.' else v_n || ' linha(s) esperando no Extrato.' end);

  -- 3. Nenhuma despesa lançada em dobro: uma com banco e outra sem, mesmo valor, mesma
  --    contraparte, até 5 dias. (Duas COM banco são dois pagamentos reais.) Conta em aberto se
  --    compara pelo vencimento; pagamento já ligado a uma nota não é duplicata das parcelas dela;
  --    a parte paga com crédito do fornecedor não passa pelo banco (revisão de 27/09/2026).
  select count(*) into v_n
    from public.payables a
    join public.payables b on b.id <> a.id
     and a.bank_transaction_id is not null and b.bank_transaction_id is null
     and b.status <> 'cancelled' and abs(a.amount - b.amount) < 0.01
     and abs(a.issue_date - case when b.status in ('pending', 'partially_paid', 'overdue') then b.due_date else b.issue_date end) <= 5
     and not (a.fiscal_note_id is not null and a.fiscal_note_id = b.fiscal_note_id)
     and b.payment_method is distinct from 'credito_fornecedor'
     and coalesce(a.supplier_id::text, upper(a.supplier_name), '') = coalesce(b.supplier_id::text, upper(b.supplier_name), '')
     and coalesce(a.supplier_id::text, upper(a.supplier_name), '') <> ''
   where a.status <> 'cancelled' and a.issue_date between v_ini and v_fim;
  v_itens := v_itens || jsonb_build_object('chave', 'sem_duplicata', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'Nenhuma despesa lançada em dobro', 'quantidade', v_n,
    'detalhe', case when v_n = 0 then 'Nenhum par suspeito.' else v_n || ' par(es) com o mesmo valor e fornecedor, um pelo banco e outro à mão.' end);

  -- 4. Lançamento casado com o extrato pelo mesmo valor.
  select count(*) into v_n
    from public.conciliacao_lancamentos l
   where l.situacao = 'conciliado' and coalesce(l.diferenca, 0) <> 0
     and coalesce(l.extrato_data, l.issue_date) between v_ini and v_fim;
  v_itens := v_itens || jsonb_build_object('chave', 'conciliacao_bate', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'Nenhum lançamento com valor diferente do extrato', 'quantidade', v_n,
    'detalhe', case when v_n = 0 then 'Todos batem.' else v_n || ' lançamento(s) difere(m) do banco — veja a Conciliação.' end);

  -- 5. Tudo tem categoria (sem ela o valor some do resultado).
  select (select count(*) from public.payables where status <> 'cancelled' and issue_date between v_ini and v_fim and expense_category is null)
       + (select count(*) from public.receivables where status <> 'cancelled' and issue_date between v_ini and v_fim and category is null)
    into v_n;
  v_itens := v_itens || jsonb_build_object('chave', 'tudo_categorizado', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'Todo lançamento tem categoria', 'quantidade', v_n,
    'detalhe', case when v_n = 0 then 'Nada sem categoria.' else v_n || ' lançamento(s) sem categoria não entram no DRE.' end);

  -- 6. Aviso: pago sem nenhum rastro no banco (ou no caixa).
  select count(*) into v_n from public.conciliacao_lancamentos l
   where l.situacao = 'sem_extrato' and l.status = 'paid' and l.issue_date between v_ini and v_fim;
  v_itens := v_itens || jsonb_build_object('chave', 'pago_sem_banco', 'bloqueia', false, 'ok', v_n = 0,
    'titulo', 'Pagos com rastro no banco ou no caixa', 'quantidade', v_n,
    'detalhe', case when v_n = 0 then 'Todo pagamento tem rastro.' else v_n || ' lançamento(s) pago(s) sem linha do banco — confira na Conciliação.' end);

  -- 7. Aviso: "Outras despesas" costuma esconder o que merecia categoria própria.
  select count(*), coalesce(sum(amount), 0) into v_n, v_valor from public.payables
   where status <> 'cancelled' and issue_date between v_ini and v_fim and expense_category = 'Outras despesas';
  v_itens := v_itens || jsonb_build_object('chave', 'outras_despesas', 'bloqueia', false, 'ok', v_n = 0,
    'titulo', 'Pouco em "Outras despesas"', 'quantidade', v_n, 'valor', v_valor,
    'detalhe', case when v_n = 0 then 'Nada em "Outras despesas".' else v_n || ' lançamento(s), ' || public._brl(v_valor) || ', em "Outras despesas".' end);

  return jsonb_build_object(
    'ano', p_ano, 'mes', p_mes,
    'pronto', not exists (select 1 from jsonb_array_elements(v_itens) i where (i ->> 'bloqueia')::boolean and not (i ->> 'ok')::boolean),
    'itens', v_itens
  );
end;
$function$;

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- Conferências: se algo acima não ficou como deveria, nada é gravado.
-- ───────────────────────────────────────────────────────────────────────────────────────────
do $$
begin
  if (select count(*) from public.cost_centers
       where active and name in ('Oficina/sede', 'Obras e reformas da sede', 'Veículos da empresa',
                                 'Ferramentas e equipamentos próprios', 'Administrativo', 'Comercial')) <> 6 then
    raise exception 'os 6 centros de custo novos não ficaram ativos';
  end if;
  if exists (select 1 from public.cost_centers
              where active and name in ('Receitas Operacionais', 'Deduções e Impostos', 'Custos Variáveis (CPV/CSV)',
                                        'Despesas Operacionais Fixas', 'Despesas com Pessoal', 'Despesas Administrativas',
                                        'Resultado Financeiro (Taxas/Juros)')) then
    raise exception 'algum centro de custo antigo continua ativo';
  end if;
  if not exists (select 1 from public.financial_categories
                  where name = 'Serviços de terceiros para a empresa' and type = 'payable'
                    and active and dre_group = 'despesa_operacional') then
    raise exception 'a categoria de serviço para a empresa não ficou ativa em despesa_operacional';
  end if;
  if has_function_privilege('anon', 'public.confirm_nfe_import(uuid,uuid,jsonb,uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.revert_nfe_import(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.ligar_parcela_ao_pagamento(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.dre_cobertura(integer)', 'EXECUTE')
     or has_function_privilege('anon', 'public._pagamentos_que_podem_ser_a_parcela(uuid,numeric,date,date)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public._pagamentos_que_podem_ser_a_parcela(uuid,numeric,date,date)', 'EXECUTE') then
    raise exception 'anon (ou authenticated, na função interna) ainda executa uma função da importação ou da cobertura';
  end if;
  if (select reloptions from pg_class where oid = 'public.conciliacao_lancamentos'::regclass) is distinct from array['security_invoker=on'] then
    raise exception 'a visão de conciliação perdeu o security_invoker';
  end if;
end $$;
