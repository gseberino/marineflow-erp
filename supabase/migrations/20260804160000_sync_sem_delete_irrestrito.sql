-- ─────────────────────────────────────────────────────────────────────────────
-- Corrige "DELETE requires a WHERE clause" ao confirmar a entrada de mercadoria.
--
-- Erro relatado pelo dono em 04/08/2026, na segunda tentativa de importar a nota —
-- e com razão em estranhar: ele não estava apagando nada.
--
-- Causa: `sync_fiscal_note_items`, criada horas antes NESTE MESMO DIA, usava uma
-- tabela TEMPORÁRIA para não perder o vínculo com OS já feito à mão, e a limpava
-- com `delete from _vinculos_preservados;` — sem WHERE. Este banco recusa DELETE
-- irrestrito. Como a função roda por gatilho quando a nota é confirmada, ela
-- derrubava a importação inteira: estoque, conta a pagar, tudo.
--
-- Some a tabela temporária. Os vínculos passam a viver num jsonb local
-- (item_index -> service_order_id): sem tabela auxiliar não há o que limpar, e o
-- único DELETE que resta é o da própria nota, que sempre teve WHERE.
--
-- Lição: tabela temporária dentro de função de gatilho tem custo escondido — além
-- do DELETE irrestrito, ela persiste pela sessão e complica reentrância. Para
-- guardar meia dúzia de pares, uma variável resolve.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.sync_fiscal_note_items(p_note_id uuid)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_inseridos integer := 0;
  v_vinculos  jsonb   := '{}'::jsonb;
begin
  -- Guarda as decisões já tomadas ("esta peça é da OS-00051") antes de reconstruir.
  select coalesce(jsonb_object_agg(item_index::text, service_order_id), '{}'::jsonb)
    into v_vinculos
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
         nullif(v_vinculos->>f.item_index::text, '')::uuid
  from fiscais f
  left join lateral (
    select c.product_id from casados c
    where (f.sku_supplier is not null and c.sku_supplier = f.sku_supplier)
       or (f.sku_supplier is null and c.description = f.description)
    limit 1
  ) c on true;

  get diagnostics v_inseridos = row_count;
  return v_inseridos;
end;
$$;

comment on function public.sync_fiscal_note_items(uuid) is
  'Reconstroi fiscal_note_items a partir de fiscal_notes.items + import_result.items. Idempotente; preserva o vinculo com OS num jsonb local (sem tabela temporaria, que exigia DELETE irrestrito e quebrava a confirmacao).';
