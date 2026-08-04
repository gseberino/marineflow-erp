-- ─────────────────────────────────────────────────────────────────────────────
-- fiscal_note_items passa a ser POPULADA — e o histórico de preço volta a existir.
--
-- BUG SILENCIOSO ENCONTRADO EM 04/08/2026: `use-price-history.ts` lê de
-- `fiscal_note_items` para mostrar, na hora de julgar uma cotação, quanto já foi
-- pago por aquele produto ("o fornecedor pede R$ 200 e a última compra saiu por
-- R$ 120"). A tabela tem ZERO linhas. A importação de XML grava os itens em
-- `fiscal_notes.items` (jsonb) e nunca alimentou a tabela normalizada.
--
-- Ou seja: a régua que existe justamente para impedir aceitar um reajuste de 60%
-- sem perceber nunca apareceu na tela. Não dava erro — simplesmente vinha vazia,
-- que é a forma mais cara de um recurso falhar.
--
-- Esta migration NÃO altera `confirm_nfe_import` (7.387 caracteres, mexe em estoque
-- e em contas a pagar — reescrevê-la para isto seria risco desproporcional). Em vez
-- disso, uma função idempotente reconstrói os itens a partir do que a nota já
-- guarda, e um gatilho a chama quando a nota é confirmada.
--
-- A JUNÇÃO entre os dois JSONs: `items` tem os dados fiscais (preço, ncm, cfop,
-- índice) e `import_result.items` tem o casamento com o produto (`product_id`,
-- `match_reason`). O elo entre eles é o `sku_supplier`, presente nos dois; quando
-- falta, cai para a descrição. Itens sem casamento entram com product_id nulo —
-- são registro fiscal válido, apenas não contam para histórico de preço.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.sync_fiscal_note_items(p_note_id uuid)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_inseridos integer := 0;
begin
  -- Idempotente: reconstrói do zero. Preserva o vínculo com OS que já tenha sido
  -- feito à mão, casando pelo índice do item — senão reprocessar uma nota apagaria
  -- a decisão de "esta peça é da OS-00050".
  create temp table if not exists _vinculos_preservados (
    item_index integer, service_order_id uuid
  ) on commit drop;
  delete from _vinculos_preservados;

  insert into _vinculos_preservados (item_index, service_order_id)
  select item_index, service_order_id
  from fiscal_note_items
  where fiscal_note_id = p_note_id and service_order_id is not null;

  delete from fiscal_note_items where fiscal_note_id = p_note_id;

  with fiscais as (
    select (e.value->>'index')::int                       as item_index,
           nullif(e.value->>'sku_supplier', '')           as sku_supplier,
           e.value->>'description'                        as description,
           nullif(e.value->>'ncm', '')                    as ncm,
           nullif(e.value->>'cfop', '')                   as cfop,
           nullif(e.value->>'unit', '')                   as unit,
           coalesce((e.value->>'quantity')::numeric, 0)   as quantity,
           coalesce((e.value->>'unit_price')::numeric, 0) as unit_price,
           coalesce((e.value->>'total_price')::numeric, 0) as total_price
    from fiscal_notes n
    cross join lateral jsonb_array_elements(coalesce(n.items, '[]'::jsonb)) e
    where n.id = p_note_id
  ),
  casados as (
    select nullif(e.value->>'sku_supplier', '') as sku_supplier,
           e.value->>'description'              as description,
           (e.value->>'product_id')::uuid       as product_id
    from fiscal_notes n
    cross join lateral jsonb_array_elements(coalesce(n.import_result->'items', '[]'::jsonb)) e
    where n.id = p_note_id
      and nullif(e.value->>'product_id', '') is not null
  )
  insert into fiscal_note_items (
    fiscal_note_id, item_index, description, sku_supplier, ncm, cfop, unit,
    quantity, unit_price, total_price, product_id, matched_product_id,
    x_prod, q_com, v_un_com, v_prod, processed, service_order_id
  )
  select p_note_id, f.item_index, f.description, f.sku_supplier, f.ncm, f.cfop, f.unit,
         f.quantity, f.unit_price, f.total_price, c.product_id, c.product_id,
         f.description, f.quantity, f.unit_price, f.total_price, true,
         v.service_order_id
  from fiscais f
  left join lateral (
    select c.product_id from casados c
    where (f.sku_supplier is not null and c.sku_supplier = f.sku_supplier)
       or (f.sku_supplier is null and c.description = f.description)
    limit 1
  ) c on true
  left join _vinculos_preservados v on v.item_index = f.item_index;

  get diagnostics v_inseridos = row_count;
  return v_inseridos;
end;
$$;

comment on function public.sync_fiscal_note_items(uuid) is
  'Reconstroi fiscal_note_items a partir de fiscal_notes.items + import_result.items. Idempotente e preserva o vinculo com OS feito a mao. Existe porque confirm_nfe_import nunca populou a tabela, deixando o historico de preco vazio.';

revoke all on function public.sync_fiscal_note_items(uuid) from public;
revoke all on function public.sync_fiscal_note_items(uuid) from anon;
grant execute on function public.sync_fiscal_note_items(uuid) to authenticated, service_role;

-- Mantém sincronizado dali em diante, sem tocar na função crítica de importação.
create or replace function public.trg_sync_fiscal_note_items()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.confirmed_at is not null
     and (old.confirmed_at is null or new.items is distinct from old.items
          or new.import_result is distinct from old.import_result) then
    perform public.sync_fiscal_note_items(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists sync_fiscal_note_items on public.fiscal_notes;
create trigger sync_fiscal_note_items
  after update on public.fiscal_notes
  for each row execute function public.trg_sync_fiscal_note_items();
