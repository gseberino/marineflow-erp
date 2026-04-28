-- Migração para suporte a mapeamento inteligente de produtos de fornecedores
-- Nome: 20260428020000_supplier_product_mappings.sql

CREATE TABLE IF NOT EXISTS public.supplier_product_mappings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE CASCADE,
    supplier_sku TEXT NOT NULL,
    supplier_description TEXT,
    internal_product_id UUID REFERENCES public.products(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(supplier_id, supplier_sku)
);

-- Habilitar RLS
ALTER TABLE public.supplier_product_mappings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Enable all for authenticated users" ON public.supplier_product_mappings
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Comentários para documentação
COMMENT ON TABLE public.supplier_product_mappings IS 'Armazena o vínculo entre SKUs de fornecedores (XML) e produtos internos do catálogo.';

-- Atualizar a função confirm_nfe_import para usar mapeamentos
OR REPLACE FUNCTION confirm_nfe_import(
    p_note_id UUID,
    p_supplier_id UUID DEFAULT NULL,
    p_manual_mappings JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_note_status TEXT;
    v_items JSONB;
    v_item RECORD;
    v_product_id UUID;
    v_movement_id UUID;
    v_products_created INT := 0;
    v_movements_created INT := 0;
    v_payable_id UUID;
    v_total_amount DECIMAL;
    v_nfe_number TEXT;
    v_issuer_name TEXT;
    v_issuer_cnpj TEXT;
    v_manual_prod_id UUID;
BEGIN
    -- 1. Validar status da nota
    SELECT status, items, total_amount, nfe_number, issuer_name, issuer_cnpj
    INTO v_note_status, v_items, v_total_amount, v_nfe_number, v_issuer_name, v_issuer_cnpj
    FROM fiscal_notes WHERE id = p_note_id;

    IF v_note_status != 'pending' THEN
        RAISE EXCEPTION 'Esta nota já foi processada ou cancelada.';
    END IF;

    -- 2. Processar cada item
    FOR v_item IN SELECT * FROM jsonb_to_recordset(v_items) AS x(
        sku_supplier TEXT,
        description TEXT,
        ncm TEXT,
        unit TEXT,
        quantity DECIMAL,
        unit_price DECIMAL,
        total_price DECIMAL
    ) LOOP
        
        v_product_id := NULL;

        -- 2.1 Verificar mapeamento manual enviado pelo frontend
        IF p_manual_mappings IS NOT NULL AND v_item.sku_supplier IS NOT NULL THEN
            SELECT (val->>'internal_product_id')::UUID INTO v_manual_prod_id
            FROM jsonb_array_elements(p_manual_mappings) AS val
            WHERE val->>'sku_supplier' = v_item.sku_supplier;
            
            IF v_manual_prod_id IS NOT NULL THEN
                v_product_id := v_manual_prod_id;
            END IF;
        END IF;

        -- 2.2 Se não tem manual, tentar encontrar por mapeamento prévio no banco
        IF v_product_id IS NULL AND p_supplier_id IS NOT NULL AND v_item.sku_supplier IS NOT NULL THEN
            SELECT internal_product_id INTO v_product_id
            FROM supplier_product_mappings
            WHERE supplier_id = p_supplier_id AND supplier_sku = v_item.sku_supplier;
        END IF;

        -- 2.3 Se não encontrou mapping, tentar por SKU interno
        IF v_product_id IS NULL THEN
            SELECT id INTO v_product_id FROM products 
            WHERE sku = v_item.sku_supplier AND active = true;
        END IF;

        -- 2.4 Se ainda não encontrou, tentar por nome exato
        IF v_product_id IS NULL THEN
            SELECT id INTO v_product_id FROM products 
            WHERE LOWER(product_name) = LOWER(v_item.description) AND active = true;
        END IF;

        -- 2.5 Se ainda não encontrou, CRIAR novo produto
        IF v_product_id IS NULL THEN
            INSERT INTO products (
                product_name,
                sku,
                category,
                unit,
                cost_price,
                sale_price,
                stock_quantity,
                fiscal_ncm,
                active,
                fiscal_complete
            ) VALUES (
                v_item.description,
                v_item.sku_supplier,
                'Importados',
                COALESCE(v_item.unit, 'un'),
                v_item.unit_price,
                v_item.unit_price * 1.3, -- Margem padrão 30%
                0, -- Começa com 0, o movimento vai adicionar
                v_item.ncm,
                true,
                false -- Marcar como incompleto para revisão fiscal
            ) RETURNING id INTO v_product_id;
            
            v_products_created := v_products_created + 1;
        END IF;

        -- 2.6 Persistir mapeamento (aprendizado automático)
        IF p_supplier_id IS NOT NULL AND v_item.sku_supplier IS NOT NULL THEN
            INSERT INTO supplier_product_mappings (supplier_id, supplier_sku, supplier_description, internal_product_id)
            VALUES (p_supplier_id, v_item.sku_supplier, v_item.description, v_product_id)
            ON CONFLICT (supplier_id, supplier_sku) DO UPDATE SET
                supplier_description = EXCLUDED.supplier_description,
                internal_product_id = EXCLUDED.internal_product_id,
                updated_at = now();
        END IF;

        -- 3. Registrar movimento de estoque
        INSERT INTO inventory_movements (
            product_id,
            movement_type,
            quantity_delta,
            unit_cost_snapshot,
            reference_type,
            fiscal_note_id,
            notes
        ) VALUES (
            v_product_id,
            'purchase',
            v_item.quantity,
            v_item.unit_price,
            'import',
            p_note_id,
            'Entrada via NF-e ' || v_nfe_number
        ) RETURNING id INTO v_movement_id;

        v_movements_created := v_movements_created + 1;

        -- 4. Inteligência de Preço: Gerar sugestão se o custo aumentou ou para manter margem
        DECLARE
            v_old_cost DECIMAL;
            v_current_sale DECIMAL;
            v_category_margin DECIMAL;
            v_suggested_sale DECIMAL;
        BEGIN
            SELECT cost_price, sale_price INTO v_old_cost, v_current_sale FROM products WHERE id = v_product_id;
            
            -- Buscar margem da categoria (se não tiver, usar 30%)
            SELECT COALESCE(default_profit_margin, 30) INTO v_category_margin 
            FROM product_categories 
            WHERE name = (SELECT category FROM products WHERE id = v_product_id);

            -- Se o novo custo for maior que o antigo, ou se a margem atual estiver defasada
            IF v_item.unit_price > v_old_cost OR v_current_sale < (v_item.unit_price * (1 + v_category_margin/100)) THEN
                v_suggested_sale := v_item.unit_price * (1 + v_category_margin/100);
                
                INSERT INTO price_update_suggestions (product_id, fiscal_note_id, current_sale_price, suggested_sale_price, margin_percent)
                VALUES (v_product_id, p_note_id, v_current_sale, v_suggested_sale, v_category_margin);
            END IF;
        END;

        -- Atualizar custo e estoque no produto
        UPDATE products SET 
            cost_price = v_item.unit_price,
            stock_quantity = stock_quantity + v_item.quantity,
            updated_at = now()
        WHERE id = v_product_id;
    END LOOP;

    -- 4. Gerar conta a pagar se tiver fornecedor
    IF p_supplier_id IS NOT NULL THEN
        INSERT INTO payables (
            supplier_id,
            amount,
            balance_amount,
            description,
            issue_date,
            due_date,
            status,
            expense_category,
            fiscal_note_id,
            origin
        ) VALUES (
            p_supplier_id,
            v_total_amount,
            v_total_amount,
            'Compra ref. NF-e ' || v_nfe_number || ' - ' || v_issuer_name,
            now()::date,
            (now() + interval '28 days')::date, -- Prazo padrão
            'pending',
            'Compras de Mercadorias',
            p_note_id,
            'fiscal_import'
        ) RETURNING id INTO v_payable_id;
    END IF;

    -- 5. Finalizar nota
    UPDATE fiscal_notes SET 
        status = 'confirmed',
        confirmed_at = now(),
        updated_at = now()
    WHERE id = p_note_id;

    RETURN jsonb_build_object(
        'success', true,
        'products_created', v_products_created,
        'movements_created', v_movements_created,
        'payable_id', v_payable_id
    );
END;
$$;
