-- Prova: devolução de compra autorizada baixa o estoque, e o cancelamento estorna
-- (migration 20261004130000_devolucao_baixa_estoque). Termina em ROLLBACK: nada fica gravado.
--
-- Usa a nota de entrada REAL da Cerbo GX (chave 3224…9088, item 5 → produto da Cerbo GX) para
-- montar devoluções de mentira, com número 999901+ em produção, e confere no razão:
--   1. referência por item (chave + nItem) → baixa de 1, nota com stock_settled_at;
--   2. cancelamento → estorno pelo gatilho que já existia (fiscal_note_cancel_reversal);
--   3. item sem número, só a chave da nota + o cProd → acha o mesmo produto;
--   4. chave que não existe → nada baixa, a autorização passa e o aviso vai para app_error_logs;
--   5. homologação → nada baixa;
--   6. nota que já nasce autorizada (INSERT) → baixa também;
--   7. passar a 'authorized' de novo não baixa duas vezes.
-- Rodar: npx supabase db query --linked -f supabase/tests/devolucao_baixa_estoque.sql

begin;

do $teste$
declare
  c_chave   constant text := '32241012696968000183550010000343951006319088';
  v_prod    uuid;
  v_antes   numeric;
  v_doc     uuid;
  v_n       int;
  v_soma    numeric;
  v_doc_rec record;
  v_logs    int;

begin
  select coalesce(fni.product_id, fni.matched_product_id) into v_prod
    from fiscal_notes fn join fiscal_note_items fni on fni.fiscal_note_id = fn.id
   where fn.nfe_key = c_chave and fni.item_index = 5;
  if v_prod is null then raise exception 'FALHOU: a nota de entrada da Cerbo GX não tem o item 5 ligado a produto'; end if;

  select coalesce(sum(quantity_delta), 0) into v_antes from inventory_movements where product_id = v_prod;

  -- 1. Referência por item ------------------------------------------------------------------
  insert into issued_fiscal_documents (document_type, origin_type, environment, status, series, number, request_payload)
  values ('nfe', 'manual', 'producao', 'processing', 2, 999901, jsonb_build_object(
    'purpose', '4',
    'referenced_documents', jsonb_build_array(jsonb_build_object('access_key', c_chave)),
    'items', jsonb_build_array(jsonb_build_object(
      'code', '2390', 'name', 'CENTRAL DE CONTROLE CERBO GX', 'quantity', 1, 'unit_price', 2147.74,
      'referenced_document', jsonb_build_object('access_key', c_chave, 'item', 5)))))
  returning id into v_doc;

  select count(*) into v_n from inventory_movements where reference_id = v_doc;
  if v_n <> 0 then raise exception 'FALHOU: baixou antes de autorizar (% movimentos)', v_n; end if;

  update issued_fiscal_documents set status = 'authorized' where id = v_doc;

  select count(*), coalesce(sum(quantity_delta), 0) into v_n, v_soma
    from inventory_movements
   where reference_type = 'issued_fiscal_document' and reference_id = v_doc
     and movement_type = 'fiscal_note_exit' and product_id = v_prod;
  if v_n <> 1 or v_soma <> -1 then raise exception 'FALHOU 1: esperava 1 baixa de -1, veio % de %', v_n, v_soma; end if;
  select * into v_doc_rec from issued_fiscal_documents where id = v_doc;
  if v_doc_rec.stock_settled_at is null then raise exception 'FALHOU 1: a nota não ficou com stock_settled_at'; end if;

  -- 7. Autorizar de novo não duplica
  update issued_fiscal_documents set status = 'authorized' where id = v_doc;
  select count(*) into v_n from inventory_movements where reference_id = v_doc and movement_type = 'fiscal_note_exit';
  if v_n <> 1 then raise exception 'FALHOU 7: baixou duas vezes (% baixas)', v_n; end if;

  -- O saldo do produto segue a soma (o gatilho adiado roda já aqui).
  set constraints all immediate;
  if (select stock_quantity from products where id = v_prod) <> v_antes - 1 then
    raise exception 'FALHOU 1: saldo do produto não caiu 1 (antes %, agora %)', v_antes, (select stock_quantity from products where id = v_prod);
  end if;
  set constraints all deferred;

  -- 2. Cancelamento estorna ----------------------------------------------------------------
  update issued_fiscal_documents set status = 'cancelled' where id = v_doc;
  select count(*), coalesce(sum(quantity_delta), 0) into v_n, v_soma
    from inventory_movements
   where reference_id = v_doc and movement_type = 'fiscal_note_cancel_reversal' and product_id = v_prod;
  if v_n <> 1 or v_soma <> 1 then raise exception 'FALHOU 2: esperava 1 estorno de +1, veio % de %', v_n, v_soma; end if;
  select * into v_doc_rec from issued_fiscal_documents where id = v_doc;
  if v_doc_rec.stock_reversed_at is null then raise exception 'FALHOU 2: a nota não ficou com stock_reversed_at'; end if;
  select coalesce(sum(quantity_delta), 0) into v_soma from inventory_movements where product_id = v_prod;
  if v_soma <> v_antes then raise exception 'FALHOU 2: o saldo não voltou (antes %, agora %)', v_antes, v_soma; end if;

  -- 3. Sem número do item: pela chave da nota + cProd ----------------------------------------
  insert into issued_fiscal_documents (document_type, origin_type, environment, status, series, number, request_payload)
  values ('nfe', 'manual', 'producao', 'processing', 2, 999902, jsonb_build_object(
    'purpose', '4',
    'referenced_documents', jsonb_build_array(jsonb_build_object('access_key', c_chave)),
    'items', jsonb_build_array(jsonb_build_object('code', '2390', 'name', 'CERBO GX', 'quantity', 2))))
  returning id into v_doc;
  update issued_fiscal_documents set status = 'authorized' where id = v_doc;
  select coalesce(sum(quantity_delta), 0) into v_soma
    from inventory_movements where reference_id = v_doc and movement_type = 'fiscal_note_exit' and product_id = v_prod;
  if v_soma <> -2 then raise exception 'FALHOU 3: pelo cProd esperava -2, veio %', v_soma; end if;

  -- 4. Chave que não existe: nada baixa, autoriza mesmo assim, avisa ----------------------------
  select count(*) into v_logs from app_error_logs where context = 'devolucao_baixa_estoque' and resolved_at is null;
  insert into issued_fiscal_documents (document_type, origin_type, environment, status, series, number, request_payload)
  values ('nfe', 'manual', 'producao', 'processing', 2, 999903, jsonb_build_object(
    'purpose', '4',
    'items', jsonb_build_array(jsonb_build_object(
      'code', 'XYZ', 'name', 'ITEM SEM NOTA DE ENTRADA', 'quantity', 1,
      'referenced_document', jsonb_build_object('access_key', '00000000000000000000000000000000000000000000', 'item', 1)))))
  returning id into v_doc;
  update issued_fiscal_documents set status = 'authorized' where id = v_doc;
  select * into v_doc_rec from issued_fiscal_documents where id = v_doc;
  if v_doc_rec.status <> 'authorized' then raise exception 'FALHOU 4: a autorização não passou'; end if;
  if v_doc_rec.stock_settled_at is not null then raise exception 'FALHOU 4: marcou baixa sem baixar nada'; end if;
  select count(*) into v_n from inventory_movements where reference_id = v_doc;
  if v_n <> 0 then raise exception 'FALHOU 4: baixou % movimento(s) sem produto', v_n; end if;
  if (select count(*) from app_error_logs where context = 'devolucao_baixa_estoque' and resolved_at is null) <= v_logs
     and not exists (select 1 from app_error_logs where context = 'devolucao_baixa_estoque' and resolved_at is null
                      and details->'itens' ? 'ITEM SEM NOTA DE ENTRADA') then
    raise exception 'FALHOU 4: o item sem produto não foi avisado em app_error_logs';
  end if;

  -- 5. Homologação não mexe no estoque -----------------------------------------------------------
  insert into issued_fiscal_documents (document_type, origin_type, environment, status, series, number, request_payload)
  values ('nfe', 'manual', 'homologacao', 'processing', 2, 999904, jsonb_build_object(
    'purpose', '4',
    'items', jsonb_build_array(jsonb_build_object('code', '2390', 'quantity', 1,
      'referenced_document', jsonb_build_object('access_key', c_chave, 'item', 5)))))
  returning id into v_doc;
  update issued_fiscal_documents set status = 'authorized' where id = v_doc;
  select count(*) into v_n from inventory_movements where reference_id = v_doc;
  if v_n <> 0 then raise exception 'FALHOU 5: homologação baixou estoque'; end if;

  -- 6. Nasce autorizada ---------------------------------------------------------------------------
  insert into issued_fiscal_documents (document_type, origin_type, environment, status, series, number, request_payload)
  values ('nfe', 'manual', 'producao', 'authorized', 2, 999905, jsonb_build_object(
    'purpose', '4',
    'items', jsonb_build_array(jsonb_build_object('code', '2390', 'quantity', 1,
      'referenced_document', jsonb_build_object('access_key', c_chave, 'item', 5)))))
  returning id into v_doc;
  select coalesce(sum(quantity_delta), 0) into v_soma from inventory_movements where reference_id = v_doc;
  if v_soma <> -1 then raise exception 'FALHOU 6: a nota que nasce autorizada não baixou (veio %)', v_soma; end if;

  -- Venda comum (finalidade 1) não é tocada por esta regra.
  insert into issued_fiscal_documents (document_type, origin_type, environment, status, series, number, request_payload)
  values ('nfe', 'manual', 'producao', 'authorized', 2, 999906, jsonb_build_object(
    'purpose', '1', 'items', jsonb_build_array(jsonb_build_object('code', '2390', 'quantity', 1))))
  returning id into v_doc;
  select count(*) into v_n from inventory_movements where reference_id = v_doc;
  if v_n <> 0 then raise exception 'FALHOU: venda comum foi baixada por esta regra'; end if;

  raise notice 'OK: devolução baixa, cancelamento estorna, cProd acha, sem produto avisa, homologação e venda não mexem.';
end;
$teste$;

rollback;
