-- Estoque, fase E4 (30/09/2026): fecha a porta. Plano: plans/marineflow-ledger-fase-e.md.
-- Aplicada DEPOIS da 20260930140000 e da tela/agente novos no ar: nenhum caminho conhecido escreve
-- mais o saldo direto. Qualquer caminho esquecido passa a quebrar alto (erro na hora) em vez de
-- corromper baixo (saldo que o próximo movimento desfaz em silêncio).
--
-- Só o recálculo pela soma (private.estoque_recalcular_saldo, fase E3) pode mudar
-- products.stock_quantity. Ele liga estoque.via_movimento = '1' só em volta do próprio UPDATE e
-- devolve o valor anterior logo depois (o Supabase não aceita esse parâmetro no SET da função).
-- Gravar o produto com o MESMO saldo (formulário que reenvia a linha inteira) continua livre.
--
-- Fica de fora de propósito: INSERT de produto com saldo (a importação CSV grava o movimento
-- junto; o vigia estoque_saldos_divergentes() mostra se algum cadastro vier sem).
-- Rollback: drop trigger trg_estoque_saldo_so_por_movimento on public.products.

create or replace function private.estoque_recalcular_saldo()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids uuid[];
  v_id uuid;
  v_antes text := coalesce(current_setting('estoque.via_movimento', true), '');
begin
  v_ids := array_remove(array[
    case when tg_op in ('INSERT', 'UPDATE') then new.product_id end,
    case when tg_op in ('UPDATE', 'DELETE') then old.product_id end
  ], null);
  perform set_config('estoque.via_movimento', '1', true);
  foreach v_id in array (select array_agg(distinct x) from unnest(v_ids) x) loop
    update public.products p
       set stock_quantity = coalesce((select sum(m.quantity_delta) from public.inventory_movements m where m.product_id = v_id), 0),
           updated_at = now()
     where p.id = v_id
       and p.stock_quantity is distinct from coalesce((select sum(m.quantity_delta) from public.inventory_movements m where m.product_id = v_id), 0);
  end loop;
  perform set_config('estoque.via_movimento', v_antes, true);
  return null;
end;
$$;

create or replace function private.estoque_recusa_escrita_direta()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(current_setting('estoque.via_movimento', true), '') <> '1' then
    raise exception 'O saldo do estoque só muda por movimento (ajuste, entrada, OS, nota). Use "Ajustar estoque"; se a tela estava aberta há muito tempo, recarregue a página.'
      using errcode = 'P0001',
            detail = format('produto %s: saldo %s → %s recusado', new.id, old.stock_quantity, new.stock_quantity);
  end if;
  return new;
end;
$$;
revoke all on function private.estoque_recusa_escrita_direta() from public, anon, authenticated;

drop trigger if exists trg_estoque_saldo_so_por_movimento on public.products;
create trigger trg_estoque_saldo_so_por_movimento
  before update of stock_quantity on public.products
  for each row
  when (new.stock_quantity is distinct from old.stock_quantity)
  execute function private.estoque_recusa_escrita_direta();

insert into supabase_migrations.schema_migrations (version, name)
values ('20260930150000', 'estoque_porta_fechada')
on conflict do nothing;
