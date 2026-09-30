-- Estoque, fase E1/E2 (30/09/2026): o saldo só muda por movimento.
-- Plano: plans/marineflow-ledger-fase-e.md. A fase E3 (20/09) já faz o saldo ser a soma dos
-- movimentos no commit; aqui saem as escritas diretas que sobraram nas funções do banco, e a tela
-- e o agente ganham duas funções que gravam o movimento numa transação só.
--
-- Por que o recálculo continua ADIADO (no commit): se alguma escrita direta tivesse escapado,
-- com recálculo imediato ela contaria em dobro em silêncio; adiado, a soma sempre vence. Onde uma
-- função precisa do saldo novo antes do commit, ela lê a soma dos movimentos.
--
-- O que muda para quem usa: nada no valor. O ajuste manual e a entrada pela tela deixam de ser
-- duas chamadas separadas (gravar saldo, depois gravar movimento) e passam a ser uma, com o saldo
-- atual lido da soma sob trava do produto: dois ajustes ao mesmo tempo não se atropelam mais.
--
-- A porta (recusar escrita direta no saldo) é a migration seguinte, aplicada depois que a tela e
-- o agente novos estiverem no ar.

-- Quem fez: o login (auth.uid()) ou, pelo agente com service role, o p_autor. created_by só
-- recebe o id se o cadastro existir em app_users (a chave estrangeira não pode quebrar).
create or replace function private.estoque_autor(p_autor uuid)
returns table (id uuid, nome text)
language sql
stable
security definer
set search_path = public
as $$
  select a.id, coalesce(nullif(btrim(a.full_name), ''), 'sistema')
    from public.app_users a
   where a.id = coalesce(auth.uid(), p_autor)
  union all
  select null::uuid, 'sistema'
   where not exists (select 1 from public.app_users a where a.id = coalesce(auth.uid(), p_autor))
  limit 1;
$$;
revoke all on function private.estoque_autor(uuid) from public, anon, authenticated;

-- Ajuste manual: o usuário informa a quantidade CONTADA; o delta é calculado aqui.
create or replace function public.ajustar_estoque(
  p_produto uuid,
  p_nova_quantidade numeric,
  p_motivo text,
  p_autor uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_atual numeric;
  v_delta numeric;
  v_mov uuid;
  v_autor record;
begin
  if p_nova_quantidade is null or p_nova_quantidade < 0 then
    raise exception 'Informe a quantidade contada (zero ou mais).';
  end if;
  if coalesce(btrim(p_motivo), '') = '' then
    raise exception 'Informe o motivo do ajuste.';
  end if;

  perform 1 from public.products where id = p_produto for update;
  if not found then
    raise exception 'Produto não encontrado.';
  end if;

  select coalesce(sum(quantity_delta), 0) into v_atual
    from public.inventory_movements where product_id = p_produto;
  v_delta := p_nova_quantidade - v_atual;
  if v_delta = 0 then
    return jsonb_build_object('ok', true, 'anterior', v_atual, 'nova', p_nova_quantidade, 'delta', 0);
  end if;

  select * into v_autor from private.estoque_autor(p_autor);
  insert into public.inventory_movements
    (product_id, movement_type, quantity_delta, reference_type, notes, created_by, adjusted_by)
  values
    (p_produto, 'manual_adjustment', v_delta, 'manual_adjustment', btrim(p_motivo), v_autor.id, v_autor.nome)
  returning id into v_mov;

  return jsonb_build_object('ok', true, 'anterior', v_atual, 'nova', p_nova_quantidade,
                            'delta', v_delta, 'movimento_id', v_mov);
end;
$$;

-- Entrada (compra/reposição fora de OC e de XML): soma a quantidade ao que já existe.
create or replace function public.entrada_de_estoque(
  p_produto uuid,
  p_quantidade numeric,
  p_custo numeric default null,
  p_notas text default null,
  p_autor uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_atual numeric;
  v_mov uuid;
  v_autor record;
begin
  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'A quantidade da entrada precisa ser maior que zero.';
  end if;

  perform 1 from public.products where id = p_produto for update;
  if not found then
    raise exception 'Produto não encontrado.';
  end if;

  select coalesce(sum(quantity_delta), 0) into v_atual
    from public.inventory_movements where product_id = p_produto;

  select * into v_autor from private.estoque_autor(p_autor);
  insert into public.inventory_movements
    (product_id, movement_type, quantity_delta, unit_cost_snapshot, reference_type, notes, created_by, adjusted_by)
  values
    (p_produto, 'purchase', p_quantidade, p_custo, 'manual_entry', nullif(btrim(coalesce(p_notas, '')), ''),
     v_autor.id, v_autor.nome)
  returning id into v_mov;

  update public.products set last_stock_entry_at = now() where id = p_produto;

  return jsonb_build_object('ok', true, 'anterior', v_atual, 'nova', v_atual + p_quantidade,
                            'movimento_id', v_mov);
end;
$$;

-- Alcance igual ao de hoje (RLS de products/inventory_movements: qualquer autenticado); anon fora.
revoke all on function public.ajustar_estoque(uuid, numeric, text, uuid) from public, anon;
revoke all on function public.entrada_de_estoque(uuid, numeric, numeric, text, uuid) from public, anon;
grant execute on function public.ajustar_estoque(uuid, numeric, text, uuid) to authenticated, service_role;
grant execute on function public.entrada_de_estoque(uuid, numeric, numeric, text, uuid) to authenticated, service_role;

-- As funções abaixo são as definições em produção de 30/09, com as escritas diretas no saldo
-- removidas (o movimento de cada uma já era gravado).

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

  -- O saldo volta sozinho: apagar os movimentos dispara o recálculo pela soma (fase E).
  SELECT count(*) INTO v_undone FROM inventory_movements
   WHERE reference_type = 'import' AND reference_id = p_note_id;

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

CREATE OR REPLACE FUNCTION public.receive_po(p_po_id uuid, p_items jsonb, p_due_days integer DEFAULT 30)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_item        jsonb;
  v_poi         record;
  v_new_rcv     numeric;
  v_po          record;
  v_all_done    boolean := true;
  v_any_done    boolean := false;
  v_new_status  text;
  v_payable_id  uuid;
  v_total       numeric;
BEGIN
  -- Process each item
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    SELECT * INTO v_poi
      FROM public.purchase_order_items
     WHERE id = (v_item->>'po_item_id')::uuid
       FOR UPDATE;

    IF NOT FOUND THEN CONTINUE; END IF;

    v_new_rcv := COALESCE(v_poi.received_qty, 0) + (v_item->>'received_qty')::numeric;
    v_new_rcv := LEAST(v_new_rcv, v_poi.quantity); -- cap at ordered qty

    -- Update received_qty on item
    UPDATE public.purchase_order_items
       SET received_qty = v_new_rcv
     WHERE id = v_poi.id;

    -- O saldo sobe pelo movimento abaixo (fase E); aqui só a data da última entrada.
    UPDATE public.products
       SET last_stock_entry_at = NOW()
     WHERE id = v_poi.product_id;

    -- Inventory movement
    INSERT INTO public.inventory_movements
      (product_id, movement_type, quantity_delta, reference_type, reference_id, unit_cost_snapshot)
    VALUES
      (v_poi.product_id, 'purchase', (v_item->>'received_qty')::numeric,
       'purchase_order', p_po_id, v_poi.unit_cost);

    v_any_done := true;
    IF v_new_rcv < v_poi.quantity THEN v_all_done := false; END IF;
  END LOOP;

  -- Determine new PO status
  SELECT * INTO v_po FROM public.purchase_orders WHERE id = p_po_id;
  -- Check if ALL items across the entire PO are fully received
  SELECT bool_and(received_qty >= quantity)
    INTO v_all_done
    FROM public.purchase_order_items
   WHERE purchase_order_id = p_po_id;

  v_new_status := CASE
    WHEN v_all_done THEN 'received'
    WHEN v_any_done THEN 'partial'
    ELSE v_po.status
  END;

  -- Create payable when fully received and no payable yet
  IF v_new_status = 'received' AND v_po.payable_id IS NULL AND v_po.supplier_id IS NOT NULL THEN
    SELECT COALESCE(SUM(received_qty * unit_cost), 0)
      INTO v_total
      FROM public.purchase_order_items
     WHERE purchase_order_id = p_po_id;

    INSERT INTO public.payables
      (supplier_id, description, amount, balance_amount, paid_amount,
       issue_date, due_date, status, origin)
    VALUES
      (v_po.supplier_id,
       'Recebimento ' || v_po.po_number,
       v_total, v_total, 0,
       CURRENT_DATE, CURRENT_DATE + p_due_days,
       'pending', 'purchase_order')
    RETURNING id INTO v_payable_id;

    UPDATE public.purchase_orders
       SET status     = v_new_status,
           payable_id = v_payable_id,
           received_date = CURRENT_DATE
     WHERE id = p_po_id;
  ELSE
    UPDATE public.purchase_orders
       SET status = v_new_status,
           received_date = CASE WHEN v_new_status = 'received' THEN CURRENT_DATE ELSE received_date END
     WHERE id = p_po_id;
  END IF;

  RETURN json_build_object(
    'status',      v_new_status,
    'payable_id',  v_payable_id,
    'all_received', v_all_done
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.settle_nfe_stock_and_receivable(p_document_id uuid, p_installments jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_doc          issued_fiscal_documents;
  v_item         jsonb;
  v_pid          uuid;
  v_qty          numeric;
  v_total        numeric := 0;
  v_pay_method   text;
  v_receivable   uuid;
  v_first_recv   uuid := NULL;
  v_stock_items  int := 0;
  v_n            int;
  v_idx          int := 0;
  v_desc         text;
  v_data_nota    date;
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_doc FROM issued_fiscal_documents WHERE id = p_document_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Documento não encontrado.'; END IF;
  IF v_doc.status <> 'authorized' THEN
    RAISE EXCEPTION 'A nota precisa estar autorizada para lançar estoque/recebível.';
  END IF;
  IF v_doc.origin_type <> 'manual' THEN
    RAISE EXCEPTION 'Apenas notas avulsas — as vindas de OS já baixam estoque e geram financeiro pelo fluxo da OS.';
  END IF;
  IF v_doc.stock_settled_at IS NOT NULL THEN
    RAISE EXCEPTION 'Esta nota já teve estoque e recebível lançados.';
  END IF;
  IF v_doc.client_id IS NULL THEN
    RAISE EXCEPTION 'A nota não tem cliente vinculado (necessário para gerar o recebível).';
  END IF;

  -- Baixa de estoque: só itens com product_id.
  IF v_doc.source_items IS NOT NULL THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_doc.source_items) LOOP
      v_pid := NULLIF(v_item->>'product_id','')::uuid;
      v_qty := COALESCE((v_item->>'quantity')::numeric, 0);
      IF v_pid IS NOT NULL AND v_qty > 0 THEN
        INSERT INTO inventory_movements
          (product_id, movement_type, quantity_delta, reference_type, reference_id, notes, created_by)
        VALUES
          (v_pid, 'fiscal_note_exit', -v_qty, 'issued_fiscal_document', p_document_id,
           'Baixa por NF-e ' || COALESCE(v_doc.series::text,'') || '/' || COALESCE(v_doc.number::text,''),
           auth.uid());
        v_stock_items := v_stock_items + 1;
      END IF;
    END LOOP;
  END IF;

  -- ── O VALOR DA NOTA (vNF), e não a forma de pagamento declarada ───────────
  SELECT round(sum(round((i->>'quantity')::numeric * (i->>'unit_price')::numeric, 2)
                   - COALESCE((i->>'discount')::numeric, 0)
                   + COALESCE((i->>'other_expenses')::numeric, 0)
                   + COALESCE((i->'returned_ipi'->>'value')::numeric, 0)), 2)
    INTO v_total
    FROM jsonb_array_elements(COALESCE(v_doc.request_payload->'items', '[]'::jsonb)) i;

  -- NFS-e não tem itens: o líquido é o que o tomador deve. Último recurso, o pagamento
  -- declarado — que só sobra para nota sem item nenhum.
  v_total := COALESCE(
    NULLIF(v_total, 0),
    (v_doc.request_payload->'amounts'->>'net_amount')::numeric,
    (v_doc.request_payload->'amounts'->>'service_amount')::numeric,
    (v_doc.request_payload->'payments'->0->>'amount')::numeric,
    0);

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Não foi possível calcular o valor desta nota — um recebível de R$ 0,00 não seria cobrável.';
  END IF;

  v_pay_method := v_doc.request_payload->'payments'->0->>'method';

  -- ── A DATA DA NOTA, e não a de hoje ───────────────────────────────────────
  -- Mesma ordem de confiabilidade da tela: carimbo da SEFAZ (já com fuso), evento de
  -- autorização da NFS-e, a coluna, e por fim a criação da linha.
  v_data_nota := (COALESCE(
      (v_doc.provider_status->'sefaz'->>'authorized_at')::timestamptz,
      CASE WHEN v_doc.provider_status->'latest_event'->>'status' = 'authorized'
           THEN (v_doc.provider_status->'latest_event'->>'created_at')::timestamptz END,
      v_doc.authorized_at,
      v_doc.created_at
    ) AT TIME ZONE 'America/Sao_Paulo')::date;

  IF p_installments IS NULL OR jsonb_typeof(p_installments) <> 'array' OR jsonb_array_length(p_installments) = 0 THEN
    -- À vista: um recebível, emitido e vencendo na data da nota.
    INSERT INTO receivables
      (client_id, description, issue_date, due_date, amount, balance_amount, status, payment_method, notes, issued_fiscal_document_id)
    VALUES
      (v_doc.client_id,
       'NF-e ' || COALESCE(v_doc.series::text,'') || '/' || COALESCE(v_doc.number::text,''),
       v_data_nota, v_data_nota, v_total, v_total, 'pending', v_pay_method,
       'Gerado a partir da NF-e ' || COALESCE(v_doc.access_key,''), p_document_id)
    RETURNING id INTO v_receivable;
    v_first_recv := v_receivable;
    v_n := 1;
  ELSE
    -- Parcelado: um recebível por parcela, com os valores e vencimentos que vieram --
    -- que são os da própria nota, salvo se o gestor os alterou de propósito na tela.
    v_n := jsonb_array_length(p_installments);
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_installments) LOOP
      v_idx := v_idx + 1;
      v_desc := 'NF-e ' || COALESCE(v_doc.series::text,'') || '/' || COALESCE(v_doc.number::text,'')
                || ' (parcela ' || v_idx || '/' || v_n || ')';
      INSERT INTO receivables
        (client_id, description, issue_date, due_date, amount, balance_amount, status, payment_method, notes, issued_fiscal_document_id)
      VALUES
        (v_doc.client_id, v_desc, v_data_nota,
         (v_item->>'due_date')::date,
         (v_item->>'amount')::numeric, (v_item->>'amount')::numeric,
         'pending', COALESCE(NULLIF(v_item->>'method',''), v_pay_method),
         'Gerado a partir da NF-e ' || COALESCE(v_doc.access_key,''), p_document_id)
      RETURNING id INTO v_receivable;
      IF v_first_recv IS NULL THEN v_first_recv := v_receivable; END IF;
    END LOOP;
  END IF;

  UPDATE issued_fiscal_documents
     SET stock_settled_at = now(), receivable_id = v_first_recv, updated_at = now()
   WHERE id = p_document_id;

  RETURN jsonb_build_object(
    'ok', true, 'receivable_id', v_first_recv, 'stock_items', v_stock_items,
    'amount', v_total, 'installments', v_n, 'issue_date', v_data_nota
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.reverse_nfe_settlement_on_cancel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r record;
BEGIN
  -- Só age na transição para 'cancelled', quando houve lançamento e ainda não
  -- foi revertido (idempotente).
  IF NEW.status = 'cancelled'
     AND OLD.status IS DISTINCT FROM 'cancelled'
     AND NEW.stock_settled_at IS NOT NULL
     AND NEW.stock_reversed_at IS NULL THEN

    -- 1) Cancela os recebíveis NÃO PAGOS desta nota (paid_amount = 0).
    UPDATE receivables
       SET status = 'cancelled', updated_at = now()
     WHERE issued_fiscal_document_id = NEW.id
       AND status <> 'paid'
       AND COALESCE(paid_amount, 0) = 0;

    -- 2) Estorna a baixa de estoque: para cada baixa 'fiscal_note_exit' desta
    --    nota, repõe a quantidade e registra um movimento compensatório.
    FOR r IN
      SELECT product_id, quantity_delta
        FROM inventory_movements
       WHERE reference_type = 'issued_fiscal_document'
         AND reference_id = NEW.id
         AND movement_type = 'fiscal_note_exit'
    LOOP
      INSERT INTO inventory_movements
        (product_id, movement_type, quantity_delta, reference_type, reference_id, notes)
      VALUES
        (r.product_id, 'fiscal_note_cancel_reversal', -r.quantity_delta,
         'issued_fiscal_document', NEW.id,
         'Estorno de estoque — NF-e ' || COALESCE(NEW.series::text,'') || '/'
           || COALESCE(NEW.number::text,'') || ' cancelada');
    END LOOP;

    NEW.stock_reversed_at := now();
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_service_order_cascade(p_service_order_id uuid, p_reason text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_part RECORD;
  v_receivable RECORD;
  v_payment RECORD;
  v_parts_restored INT := 0;
  v_receivables_cancelled INT := 0;
  v_payments_cancelled INT := 0;
  v_collections_cancelled INT := 0;
  v_deposit_paid NUMERIC := 0;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF NOT public.stock_model_v2_on() THEN
    FOR v_part IN
      SELECT id, product_id, quantity, unit_cost_snapshot
      FROM public.service_order_parts
      WHERE service_order_id = p_service_order_id
    LOOP
      INSERT INTO public.inventory_movements
        (product_id, movement_type, quantity_delta, reference_type, reference_id, unit_cost_snapshot)
      VALUES
        (v_part.product_id, 'return', v_part.quantity, 'service_order_cancel', p_service_order_id, v_part.unit_cost_snapshot);

      v_parts_restored := v_parts_restored + 1;
    END LOOP;
  END IF;

  FOR v_receivable IN
    SELECT id, status, is_deposit, paid_amount
    FROM public.receivables
    WHERE service_order_id = p_service_order_id
      AND status <> 'cancelled'
  LOOP
    IF v_receivable.is_deposit AND COALESCE(v_receivable.paid_amount, 0) > 0 THEN
      v_deposit_paid := v_deposit_paid + v_receivable.paid_amount;
    END IF;

    FOR v_payment IN
      SELECT id, amount
      FROM public.payments
      WHERE receivable_id = v_receivable.id
        AND status = 'confirmed'
    LOOP
      UPDATE public.payments
      SET status = 'cancelled',
          cancelled_at = v_now,
          cancellation_reason = p_reason
      WHERE id = v_payment.id;

      UPDATE public.bank_transactions
      SET reconciled = FALSE,
          reconciled_payment_id = NULL
      WHERE reconciled_payment_id = v_payment.id;

      v_payments_cancelled := v_payments_cancelled + 1;
    END LOOP;

    UPDATE public.receivables
    SET status = 'cancelled',
        balance_amount = 0
    WHERE id = v_receivable.id;

    v_receivables_cancelled := v_receivables_cancelled + 1;
  END LOOP;

  UPDATE public.collections
  SET status = 'cancelled'
  WHERE service_order_id = p_service_order_id
    AND status <> 'cancelled';
  GET DIAGNOSTICS v_collections_cancelled = ROW_COUNT;

  UPDATE public.service_orders
  SET status = 'cancelled',
      cancelled_at = v_now,
      cancellation_reason = p_reason
  WHERE id = p_service_order_id;

  RETURN json_build_object(
    'success', TRUE,
    'parts_restored', v_parts_restored,
    'receivables_cancelled', v_receivables_cancelled,
    'payments_cancelled', v_payments_cancelled,
    'collections_cancelled', v_collections_cancelled,
    'deposit_paid', v_deposit_paid
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.deduct_stock_on_os_complete()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' THEN
    INSERT INTO inventory_movements (product_id, movement_type, quantity_delta, reference_type, reference_id, notes, unit_cost_snapshot)
    SELECT sop.product_id, 'service_order_usage', -sop.quantity, 'service_order', NEW.id,
           'Baixa automática ao concluir OS ' || NEW.service_order_number, sop.unit_cost_snapshot
    FROM service_order_parts sop WHERE sop.service_order_id = NEW.id AND sop.product_id IS NOT NULL;
  END IF;
  RETURN NEW;
END; $function$;

CREATE OR REPLACE FUNCTION public.produce_composed_product(p_parent uuid, p_qty numeric DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_type text;
  r record;
  v_falta jsonb := '[]'::jsonb;
  v_consumido jsonb := '[]'::jsonb;
begin
  if p_qty is null or p_qty <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Quantidade deve ser maior que zero.');
  end if;

  select product_type into v_type from products where id = p_parent;
  if v_type is null then
    return jsonb_build_object('ok', false, 'error', 'Produto não encontrado.');
  end if;
  if v_type not in ('composto', 'kit') then
    return jsonb_build_object('ok', false, 'error', 'Produto não é composto/kit — não tem receita para produzir.');
  end if;
  if not exists (select 1 from product_components where parent_product_id = p_parent) then
    return jsonb_build_object('ok', false, 'error', 'Produto composto sem componentes cadastrados.');
  end if;

  -- 1) Checa disponibilidade de TODOS os componentes (disponível = físico − reservado).
  for r in
    select pc.component_product_id, pc.quantity as need_per, c.name,
           c.stock_quantity, coalesce(c.reserved_quantity, 0) as reserved
    from product_components pc
    join products c on c.id = pc.component_product_id
    where pc.parent_product_id = p_parent
  loop
    if (r.stock_quantity - r.reserved) < (r.need_per * p_qty) then
      v_falta := v_falta || jsonb_build_object(
        'produto', r.name, 'necessario', r.need_per * p_qty, 'disponivel', r.stock_quantity - r.reserved);
    end if;
  end loop;
  if jsonb_array_length(v_falta) > 0 then
    return jsonb_build_object('ok', false, 'error', 'Estoque insuficiente de componentes.', 'faltantes', v_falta);
  end if;

  -- 2) Consome os componentes + registra o movimento.
  for r in
    select pc.component_product_id, pc.quantity as need_per, c.name, c.cost_price
    from product_components pc
    join products c on c.id = pc.component_product_id
    where pc.parent_product_id = p_parent
  loop
    insert into inventory_movements(product_id, movement_type, quantity_delta, reference_type, unit_cost_snapshot, notes)
      values (r.component_product_id, 'manual_remove_stock', -(r.need_per * p_qty), 'production', r.cost_price,
              'Consumo em produção de composto/kit');
    v_consumido := v_consumido || jsonb_build_object('produto', r.name, 'consumido', r.need_per * p_qty);
  end loop;

  -- 3) Credita o produto acabado.
  insert into inventory_movements(product_id, movement_type, quantity_delta, reference_type, notes)
    values (p_parent, 'manual_add_stock', p_qty, 'production', 'Produção de composto/kit');

  return jsonb_build_object(
    'ok', true, 'produzido', p_qty, 'consumidos', v_consumido,
    'novo_estoque_pai', (select coalesce(sum(quantity_delta), 0) from inventory_movements where product_id = p_parent));
end;
$function$;

CREATE OR REPLACE FUNCTION public.trg_so_status_stock()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r record;
  saldo_novo numeric;
  was_consumed boolean := old.status in ('completed','invoiced');
  is_consumed  boolean := new.status in ('completed','invoiced');
begin
  if not public.stock_model_v2_on() then return new; end if;

  if new.status is distinct from old.status then

    -- Entra em CONSUMIDO: baixa física, uma baixa por peça.
    if is_consumed and not was_consumed then
      for r in select product_id, quantity, unit_cost_snapshot
                 from public.service_order_parts
                where service_order_id = new.id loop
        select coalesce(sum(m.quantity_delta), 0) - r.quantity into saldo_novo
          from public.inventory_movements m
         where m.product_id = r.product_id;

        insert into public.inventory_movements(
          product_id, movement_type, quantity_delta, reference_type, reference_id,
          unit_cost_snapshot, notes)
        values (r.product_id, 'service_order_usage', -r.quantity, 'service_order', new.id,
                r.unit_cost_snapshot,
                case when saldo_novo < 0
                     then 'ALERTA: saldo ficou negativo (' || saldo_novo
                          || '). A entrada desta peça nunca foi lancada.'
                     else null end);
      end loop;

    -- Sai de CONSUMIDO: devolve SOMENTE o que tem baixa registrada e ainda não
    -- revertida (SAP: estorno com referência; BC: uma reversão por entrada).
    elsif was_consumed and not is_consumed then
      for r in
        select m.id, m.product_id, m.quantity_delta, m.unit_cost_snapshot
          from public.inventory_movements m
         where m.reference_type = 'service_order'
           and m.reference_id = new.id
           and m.movement_type in ('service_order_usage','service_usage')
           and m.quantity_delta < 0
           and not exists (select 1 from public.inventory_movements e where e.reverses_movement_id = m.id)
      loop
        insert into public.inventory_movements(
          product_id, movement_type, quantity_delta, reference_type, reference_id,
          unit_cost_snapshot, reverses_movement_id, notes)
        values (r.product_id, 'return', -r.quantity_delta, 'service_order', new.id,
                r.unit_cost_snapshot, r.id,
                'Estorno da baixa ' || r.id || ' (saida de ' || old.status || ' para ' || new.status || ')');
      end loop;
    end if;

    for r in select distinct product_id from public.service_order_parts where service_order_id = new.id loop
      perform public.recompute_product_reservations(r.product_id);
    end loop;
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.reconcile_stock_to_v2()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  raise exception 'Migração única para o modelo v2, já feita. O saldo agora só muda por movimento (fase E, 30/09/2026).';
end;
$function$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260930140000', 'estoque_so_por_movimento')
on conflict do nothing;
