-- Portão fiscal (raiz): fiscal_complete deixa de ser um flag cosmético (default true) e passa
-- a refletir a REALIDADE — um produto só está "completo" quando pode entrar numa NF-e:
--   NCM 8 dígitos + CFOP 4 dígitos (+ CSOSN e origem próprios quando NÃO herda o fiscal global).
-- Um trigger mantém o flag correto em QUALQUER caminho de escrita (agente IA, UI, import XML),
-- em vez de depender de cada caller lembrar de setá-lo. "Reforçar o piso, não tapar buraco."

create or replace function public.compute_product_fiscal_complete()
returns trigger
language plpgsql
as $$
declare
  ncm_digits  text := regexp_replace(coalesce(new.ncm, ''),  '\D', '', 'g');
  cfop_digits text := regexp_replace(coalesce(new.cfop, ''), '\D', '', 'g');
  ok boolean;
begin
  ok := length(ncm_digits) = 8 and length(cfop_digits) = 4;
  -- Quando o produto não herda o fiscal global da empresa, precisa de CSOSN e origem próprios.
  if new.use_global_fiscal is false then
    ok := ok
      and (new.csosn is not null and new.csosn <> '')
      and (new.fiscal_origin is not null);
  end if;
  new.fiscal_complete := ok;
  return new;
end;
$$;

drop trigger if exists trg_products_fiscal_complete on public.products;
create trigger trg_products_fiscal_complete
  before insert or update of ncm, cfop, csosn, fiscal_origin, use_global_fiscal
  on public.products
  for each row execute function public.compute_product_fiscal_complete();

-- Backfill: recalcula o flag para o catálogo inteiro. Muitos produtos vão passar a "incompleto"
-- porque de fato NÃO têm NCM — é a verdade fiscal (não dá para faturar sem NCM), não um bug.
-- A expressão abaixo é idêntica à do trigger acima.
update public.products
set fiscal_complete = (
  length(regexp_replace(coalesce(ncm, ''),  '\D', '', 'g')) = 8
  and length(regexp_replace(coalesce(cfop, ''), '\D', '', 'g')) = 4
  and (
    use_global_fiscal is not false
    or ((csosn is not null and csosn <> '') and fiscal_origin is not null)
  )
)
where fiscal_complete is distinct from (
  length(regexp_replace(coalesce(ncm, ''),  '\D', '', 'g')) = 8
  and length(regexp_replace(coalesce(cfop, ''), '\D', '', 'g')) = 4
  and (
    use_global_fiscal is not false
    or ((csosn is not null and csosn <> '') and fiscal_origin is not null)
  )
);
