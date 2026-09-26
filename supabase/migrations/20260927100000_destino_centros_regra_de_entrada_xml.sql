-- Etapa de 27/09/2026 — decisões do dono de 26/09/2026:
--   · "3: sigo pela sua sugestão" / "4: confirmado": observação e "para onde foi" na linha do
--     Extrato, centros de custo de verdade, regra de ENTRADA "o Pix do CPF/CNPJ X é do cliente Y";
--   · "3: pode seguir": serviço de terceiro feito para a sede entra como despesa da empresa, não
--     como custo do serviço vendido;
--   · Kamell NF 51038 e TSD NF 132181: a importação do XML ignorava as parcelas e o pagamento com
--     crédito do fornecedor — criava UMA conta com o total, datada do dia da importação.
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
-- 5. Importação do XML: uma conta por PARCELA da nota (<dup>), com o vencimento dela, na data
--    de EMISSÃO (competência da compra, não o dia da importação); a parcela que a própria nota
--    diz ter sido paga com crédito do fornecedor (tPag 05/19, ou 99 "crédito") entra paga e fora
--    do banco; a parcela que JÁ saiu pelo banco (mesmo fornecedor, mesmo valor, até 7 dias do
--    vencimento, lançada pelo Extrato e sem nota) é ligada à nota em vez de virar conta nova —
--    foi o que contou duas vezes os R$ 1.500 da TSD em 22/09.
--    Tudo o mais (produtos, estoque, de-para, sugestões de preço) é o da versão anterior.
-- ───────────────────────────────────────────────────────────────────────────────────────────
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
  v_emissao     date;
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
  v_desc_base   text;
  v_dup         RECORD;
  v_n_dups      int := 0;
  v_parcela     int := 0;
  v_credito     numeric := 0;
  v_credito_usado boolean := false;
  v_ja_pago     uuid;
  v_ids         uuid[] := '{}';
  v_parcelas    jsonb := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT status, items, total_amount, nfe_number, issuer_name, xml_content, issue_date
    INTO v_status, v_items, v_total, v_nfe_number, v_issuer_name, v_xml, v_emissao
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

    -- A data da NOTA é a competência da compra no DRE — não o dia em que alguém importou.
    v_emissao := coalesce(
      v_emissao,
      nullif(substring(coalesce(v_xml, '') from '<dhEmi>(\d{4}-\d{2}-\d{2})'), '')::date,
      nullif(substring(coalesce(v_xml, '') from '<dEmi>(\d{4}-\d{2}-\d{2})'), '')::date,
      now()::date);
    -- Nota de um mês já FECHADO entra no mês de hoje: o fechado não muda sem motivo, e a
    -- mercadoria não pode ficar fora do estoque por causa disso (a trava recusaria a conta).
    IF public.periodo_esta_fechado(v_emissao) THEN
      v_emissao := now()::date;
    END IF;
    v_desc_base :='Compra ref. NF-e ' || coalesce(v_nfe_number, '') || ' - ' || coalesce(v_issuer_name, '');

    -- Quanto a nota diz ter sido pago com crédito do fornecedor (carta de crédito, crédito de
    -- loja, crédito virtual): não sai do banco e não é dívida.
    SELECT coalesce(sum(nullif(substring(b[1] from '<vPag>([0-9.]+)</vPag>'), '')::numeric), 0)
      INTO v_credito
      FROM regexp_matches(coalesce(v_xml, ''), '<detPag>(.*?)</detPag>', 'g') AS b
     WHERE substring(b[1] from '<tPag>(\d+)</tPag>') IN ('05', '19')
        OR (substring(b[1] from '<tPag>(\d+)</tPag>') = '99'
            AND upper(coalesce(substring(b[1] from '<xPag>([^<]*)</xPag>'), '')) LIKE '%CRED%');

    SELECT count(*) INTO v_n_dups
      FROM regexp_matches(coalesce(v_xml, ''), '<dup>(.*?)</dup>', 'g');

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

        IF NOT v_credito_usado AND v_credito > 0 AND abs(v_dup.valor - v_credito) < 0.01 THEN
          -- A parcela que a própria nota diz ter sido paga com crédito do fornecedor.
          INSERT INTO payables (
            supplier_id, supplier_name, amount, paid_amount, balance_amount, description,
            issue_date, due_date, status, expense_category, origin, fiscal_note_id,
            payment_method, notes
          ) VALUES (
            p_supplier_id, v_issuer_name, v_dup.valor, v_dup.valor, 0,
            v_desc_base || ' (parcela ' || v_parcela || '/' || v_n_dups || ')',
            v_emissao, coalesce(v_dup.venc, v_emissao), 'paid', 'Compras de mercadorias', 'fiscal_note', p_note_id,
            'credito_fornecedor',
            'Paga com crédito do fornecedor (carta de crédito), como a nota informa: não sai do banco.'
          ) RETURNING id INTO v_payable_id;
          v_credito_usado := true;
          v_parcelas := v_parcelas || jsonb_build_object('parcela', v_parcela, 'valor', v_dup.valor,
            'vencimento', v_dup.venc, 'payable_id', v_payable_id, 'como', 'credito_do_fornecedor');
        ELSE
          -- Já saiu pelo banco antes da importação? Mesmo fornecedor, mesmo valor, até 7 dias do
          -- vencimento, lançado pelo Extrato e ainda sem nota: é esta parcela — liga, não duplica.
          SELECT p.id INTO v_ja_pago
            FROM payables p
           WHERE p.supplier_id = p_supplier_id
             AND p.fiscal_note_id IS NULL
             AND p.status <> 'cancelled'
             AND p.bank_transaction_id IS NOT NULL
             AND abs(p.amount - v_dup.valor) < 0.01
             AND abs(p.issue_date - coalesce(v_dup.venc, v_emissao)) <= 7
             AND NOT (p.id = ANY (v_ids))
           ORDER BY abs(p.issue_date - coalesce(v_dup.venc, v_emissao)), p.created_at
           LIMIT 1;

          IF v_ja_pago IS NOT NULL THEN
            UPDATE payables
               SET fiscal_note_id = p_note_id,
                   notes = btrim(coalesce(notes, '') || ' ' || 'Parcela ' || v_parcela || '/' || v_n_dups
                           || ' da NF-e ' || coalesce(v_nfe_number, '') || ', paga pelo banco antes da importação.'),
                   updated_at = now()
             WHERE id = v_ja_pago;
            v_payable_id := v_ja_pago;
            v_parcelas := v_parcelas || jsonb_build_object('parcela', v_parcela, 'valor', v_dup.valor,
              'vencimento', v_dup.venc, 'payable_id', v_payable_id, 'como', 'ja_paga_pelo_banco');
          ELSE
            INSERT INTO payables (
              supplier_id, supplier_name, amount, balance_amount, description,
              issue_date, due_date, status, expense_category, origin, fiscal_note_id
            ) VALUES (
              p_supplier_id, v_issuer_name, v_dup.valor, v_dup.valor,
              v_desc_base || ' (parcela ' || v_parcela || '/' || v_n_dups || ')',
              v_emissao, coalesce(v_dup.venc, v_emissao + v_prazo),
              'pending', 'Compras de mercadorias', 'fiscal_note', p_note_id
            ) RETURNING id INTO v_payable_id;
            v_parcelas := v_parcelas || jsonb_build_object('parcela', v_parcela, 'valor', v_dup.valor,
              'vencimento', v_dup.venc, 'payable_id', v_payable_id, 'como', 'a_pagar');
          END IF;
        END IF;
        v_ids := v_ids || v_payable_id;
      END LOOP;

      -- Crédito declarado que não bate com nenhuma parcela: fica o aviso, para alguém conferir.
      IF v_credito > 0 AND NOT v_credito_usado AND array_length(v_ids, 1) > 0 THEN
        UPDATE payables
           SET notes = btrim(coalesce(notes, '') || ' A nota informa R$ '
                       || replace(to_char(v_credito, 'FM999999990.00'), '.', ',')
                       || ' pagos com crédito do fornecedor, e o valor não bate com nenhuma parcela: confira.')
         WHERE id = v_ids[1];
      END IF;
    ELSIF v_credito > 0 AND abs(v_credito - v_total) < 0.01 THEN
      -- Sem parcelas e toda paga com crédito do fornecedor.
      INSERT INTO payables (
        supplier_id, supplier_name, amount, paid_amount, balance_amount, description,
        issue_date, due_date, status, expense_category, origin, fiscal_note_id, payment_method, notes
      ) VALUES (
        p_supplier_id, v_issuer_name, v_total, v_total, 0, v_desc_base,
        v_emissao, v_emissao, 'paid', 'Compras de mercadorias', 'fiscal_note', p_note_id, 'credito_fornecedor',
        'Paga com crédito do fornecedor (carta de crédito), como a nota informa: não sai do banco.'
      ) RETURNING id INTO v_payable_id;
      v_ids := v_ids || v_payable_id;
    ELSE
      -- Sem parcelas na nota: uma conta com o total, no prazo do fornecedor a partir da emissão.
      INSERT INTO payables (
        supplier_id, supplier_name, amount, balance_amount, description,
        issue_date, due_date, status, expense_category, origin, fiscal_note_id
      ) VALUES (
        p_supplier_id, v_issuer_name, v_total, v_total, v_desc_base,
        v_emissao, v_emissao + v_prazo,
        'pending', 'Compras de mercadorias', 'fiscal_note', p_note_id
      ) RETURNING id INTO v_payable_id;
      v_ids := v_ids || v_payable_id;
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
           'payable_ids', to_jsonb(v_ids), 'parcelas', v_parcelas, 'at', now()
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
    'items', v_detail
  );
END;
$function$;

-- A função é SECURITY DEFINER e só barra quem está LOGADO sem ser admin: anônimo não pode chegar.
revoke all on function public.confirm_nfe_import(uuid, uuid, jsonb, uuid) from public, anon;
grant execute on function public.confirm_nfe_import(uuid, uuid, jsonb, uuid) to authenticated, service_role;

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
  if has_function_privilege('anon', 'public.confirm_nfe_import(uuid,uuid,jsonb,uuid)', 'EXECUTE') then
    raise exception 'anon ainda executa confirm_nfe_import';
  end if;
  if (select reloptions from pg_class where oid = 'public.conciliacao_lancamentos'::regclass) is distinct from array['security_invoker=on'] then
    raise exception 'a visão de conciliação perdeu o security_invoker';
  end if;
end $$;
