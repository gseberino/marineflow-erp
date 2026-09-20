-- Estoque, fase E3 (20/09/2026): o saldo passa a ser a soma dos movimentos.
-- Plano: plans/marineflow-ledger-fase-e.md. Medido antes: 86 produtos com saldo ≠ soma.
--
-- Como funciona:
--   1) saldo de abertura: para cada produto cujo saldo em tela difere da soma dos movimentos,
--      um movimento fecha a diferença HOJE (nada muda de valor; só passa a ter história).
--   2) gatilho ADIADO (constraint trigger, initially deferred) em inventory_movements: no commit
--      de qualquer transação que inseriu/alterou/apagou movimento, o saldo do produto é
--      recalculado como soma. Adiado de propósito: as 9 funções do banco ainda fazem
--      `update products set stock_quantity ± delta` antes ou depois de inserir o movimento;
--      no commit a soma vence, então não há dupla contagem nem dependência de ordem.
--   3) função estoque_saldos_divergentes(): o que ainda escreve saldo sem movimento aparece
--      aqui (e o monitor avisa). Fechar essas portas é a fase E2/E4, caminho a caminho.
--
-- Mudança de comportamento assumida: baixa de OS com estoque insuficiente deixava o saldo em 0
-- e a soma negativa (a origem do "fantasma"); agora o saldo mostra o negativo honesto, que a
-- view de variância já aponta como "estoque negativo" para ajuste.

create or replace function private.estoque_recalcular_saldo()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids uuid[];
  v_id uuid;
begin
  v_ids := array_remove(array[
    case when tg_op in ('INSERT', 'UPDATE') then new.product_id end,
    case when tg_op in ('UPDATE', 'DELETE') then old.product_id end
  ], null);
  foreach v_id in array (select array_agg(distinct x) from unnest(v_ids) x) loop
    update public.products p
       set stock_quantity = coalesce((select sum(m.quantity_delta) from public.inventory_movements m where m.product_id = v_id), 0),
           updated_at = now()
     where p.id = v_id
       and p.stock_quantity is distinct from coalesce((select sum(m.quantity_delta) from public.inventory_movements m where m.product_id = v_id), 0);
  end loop;
  return null;
end;
$$;

revoke all on function private.estoque_recalcular_saldo() from public, anon, authenticated;

drop trigger if exists trg_estoque_saldo_por_soma on public.inventory_movements;
create constraint trigger trg_estoque_saldo_por_soma
  after insert or update or delete on public.inventory_movements
  deferrable initially deferred
  for each row execute function private.estoque_recalcular_saldo();

-- Vigia: produtos cujo saldo em tela não é a soma dos movimentos (porta aberta em algum caminho).
create or replace function public.estoque_saldos_divergentes()
returns table (product_id uuid, name text, sku text, saldo numeric, soma numeric, diferenca numeric)
language sql
stable
security invoker
set search_path = public
as $$
  select p.id, p.name, p.sku, p.stock_quantity,
         coalesce(m.soma, 0) as soma,
         p.stock_quantity - coalesce(m.soma, 0) as diferenca
    from public.products p
    left join (select product_id, sum(quantity_delta) soma from public.inventory_movements group by product_id) m on m.product_id = p.id
   where p.stock_quantity is distinct from coalesce(m.soma, 0)
   order by abs(p.stock_quantity - coalesce(m.soma, 0)) desc;
$$;
revoke all on function public.estoque_saldos_divergentes() from public, anon;

-- Saldo de abertura: fecha a diferença de cada produto, hoje, com trilha. Dispara o gatilho no
-- commit; como a soma passa a ser igual ao saldo, NENHUM saldo muda de valor nesta migration.
insert into public.inventory_movements (product_id, movement_type, quantity_delta, reference_type, notes, adjusted_by)
select d.product_id, 'manual_adjustment', d.diferenca, 'cutover_fase_e',
       'Saldo de abertura da fase E (saldo em tela ' || d.saldo || ' − soma dos movimentos ' || d.soma || ' em 20/09/2026).',
       'fase-e 20/09/2026'
  from public.estoque_saldos_divergentes() d;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260920110000', 'ledger_fase_e3_saldo_por_soma')
on conflict do nothing;
