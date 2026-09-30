-- Estoque, fase E: o saldo só muda por movimento. Run: npx supabase db query --linked -f supabase/tests/estoque_so_por_movimento.sql
-- Termina em ROLLBACK: os produtos de teste, os movimentos e a volta de status da OS não ficam gravados.
-- O recálculo do saldo é adiado para o commit; aqui ele é forçado com SET CONSTRAINTS ... IMMEDIATE.
begin;

do $$
declare
  v_p uuid;
  v_kit uuid;
  v_admin record;
  v_os uuid;
  v_antes jsonb;
  r jsonb;
  n int;
  v_saldo numeric;
begin
  set constraints all immediate;

  insert into public.products (name, stock_quantity) values ('TESTE fase E — peça', 0) returning id into v_p;

  -- 1. Ajuste manual: informa a contagem, o delta é calculado; o saldo é a soma.
  r := public.ajustar_estoque(v_p, 5, 'contagem de teste');
  if (r ->> 'delta')::numeric <> 5 or (select stock_quantity from public.products where id = v_p) <> 5 then
    raise exception '1: ajuste para 5 não deu 5: %', r;
  end if;
  if not exists (select 1 from public.inventory_movements where product_id = v_p and movement_type = 'manual_adjustment'
                  and quantity_delta = 5 and notes = 'contagem de teste' and adjusted_by = 'sistema' and created_by is null) then
    raise exception '1: movimento do ajuste sem os campos esperados';
  end if;

  -- 2. Entrada soma ao que existe e marca a data da última entrada.
  r := public.entrada_de_estoque(v_p, 3, 10.5, 'nota de teste');
  if (select stock_quantity from public.products where id = v_p) <> 8 or (r ->> 'nova')::numeric <> 8 then
    raise exception '2: entrada de 3 sobre 5 não deu 8: %', r;
  end if;
  if (select last_stock_entry_at from public.products where id = v_p) is null then
    raise exception '2: last_stock_entry_at não foi marcado';
  end if;

  -- 3. Ajuste para o mesmo valor não grava movimento.
  select count(*) into n from public.inventory_movements where product_id = v_p;
  r := public.ajustar_estoque(v_p, 8, 'recontagem');
  if (r ->> 'delta')::numeric <> 0 or (select count(*) from public.inventory_movements where product_id = v_p) <> n then
    raise exception '3: ajuste sem diferença gravou movimento';
  end if;

  -- 4. A porta: escrita direta no saldo é recusada...
  begin
    update public.products set stock_quantity = 99 where id = v_p;
    raise exception 'escrita direta passou';
  exception when others then
    if sqlerrm not like '%só muda por movimento%' then raise exception '4: %', sqlerrm; end if;
  end;
  -- ...mas gravar o produto reenviando o MESMO saldo (formulário) continua livre.
  update public.products set name = name || ' (editado)', stock_quantity = stock_quantity where id = v_p;

  -- 5. Entradas inválidas.
  begin
    perform public.ajustar_estoque(v_p, -1, 'x');
    raise exception 'ajuste negativo passou';
  exception when others then
    if sqlerrm not like '%zero ou mais%' then raise exception '5: %', sqlerrm; end if;
  end;
  begin
    perform public.ajustar_estoque(v_p, 2, '  ');
    raise exception 'ajuste sem motivo passou';
  exception when others then
    if sqlerrm not like '%motivo%' then raise exception '5: %', sqlerrm; end if;
  end;

  -- 6. Autor: com p_autor de um cadastro que existe, grava quem foi.
  select id, full_name into v_admin from public.app_users where active and full_name is not null limit 1;
  perform public.ajustar_estoque(v_p, 7, 'ajuste com autor', v_admin.id);
  if not exists (select 1 from public.inventory_movements where product_id = v_p and notes = 'ajuste com autor'
                  and created_by = v_admin.id and adjusted_by = v_admin.full_name) then
    raise exception '6: autor não gravado';
  end if;

  -- 7. Produção de kit: consome a peça e credita o kit; o retorno mostra o saldo novo do kit.
  insert into public.products (name, product_type, stock_quantity) values ('TESTE fase E — kit', 'kit', 0) returning id into v_kit;
  insert into public.product_components (parent_product_id, component_product_id, quantity) values (v_kit, v_p, 2);
  r := public.produce_composed_product(v_kit, 1);
  if not (r ->> 'ok')::boolean or (r ->> 'novo_estoque_pai')::numeric <> 1 then
    raise exception '7: produção falhou: %', r;
  end if;
  if (select stock_quantity from public.products where id = v_p) <> 5 or (select stock_quantity from public.products where id = v_kit) <> 1 then
    raise exception '7: saldos depois da produção errados';
  end if;

  -- 8. Recálculo adiado (o normal): o saldo só muda no "commit", e passa pela porta.
  set constraints all deferred;
  perform public.ajustar_estoque(v_p, 4, 'ajuste adiado');
  if (select stock_quantity from public.products where id = v_p) <> 5 then
    raise exception '8: com o recálculo adiado o saldo mudou antes do commit';
  end if;
  set constraints all immediate;
  if (select stock_quantity from public.products where id = v_p) <> 4 then
    raise exception '8: no commit o saldo não virou a soma';
  end if;

  -- 9. Baixa e estorno da OS (modelo v2), numa OS concluída de verdade, só dentro desta transação.
  select so.id into v_os
    from public.service_orders so
   where so.status = 'completed'
     and exists (select 1 from public.service_order_parts p where p.service_order_id = so.id and p.product_id is not null)
   order by so.updated_at desc limit 1;
  select jsonb_object_agg(id, stock_quantity) into v_antes
    from public.products where id in (select product_id from public.service_order_parts where service_order_id = v_os);

  update public.service_orders set status = 'in_progress' where id = v_os;   -- estorna as baixas registradas
  if exists (
    select 1 from public.products p
     where p.id in (select product_id from public.service_order_parts where service_order_id = v_os)
       and p.stock_quantity <> (v_antes ->> p.id::text)::numeric
          + coalesce((select sum(m.quantity_delta) from public.inventory_movements m
                       where m.product_id = p.id and m.reference_id = v_os and m.movement_type = 'return'
                         and m.created_at = now()), 0)) then
    raise exception '9: o estorno da OS não voltou o saldo pelo movimento';
  end if;
  if not exists (select 1 from public.inventory_movements where reference_id = v_os and movement_type = 'return' and created_at = now()) then
    raise exception '9: saída de concluída não gerou estorno';
  end if;

  update public.service_orders set status = 'completed' where id = v_os;     -- baixa de novo, peça a peça
  if exists (
    select 1 from public.products p
     where p.id in (select product_id from public.service_order_parts where service_order_id = v_os)
       and p.stock_quantity <> (select coalesce(sum(m.quantity_delta), 0) from public.inventory_movements m where m.product_id = p.id)) then
    raise exception '9: saldo diferente da soma depois da baixa';
  end if;
  select count(*) into n from public.inventory_movements
   where reference_id = v_os and movement_type = 'service_order_usage' and created_at = now();
  if n <> (select count(*) from public.service_order_parts where service_order_id = v_os and product_id is not null) then
    raise exception '9: esperava uma baixa por peça, vieram %', n;
  end if;

  -- 10. A migração única do v2 não roda mais.
  begin
    perform public.reconcile_stock_to_v2();
    raise exception 'reconcile_stock_to_v2 rodou';
  exception when others then
    if sqlerrm not like '%já feita%' then raise exception '10: %', sqlerrm; end if;
  end;

  -- 11. Nenhuma função do banco escreve o saldo, fora o recálculo pela soma.
  select count(*) into n
    from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname in ('public', 'private') and p.prokind = 'f'
     and p.proname <> 'estoque_recalcular_saldo'
     and pg_get_functiondef(p.oid) ~* '(set\s+stock_quantity|[\s,(]stock_quantity\s*=\s*(coalesce|greatest|stock_quantity|p\.|\w+\s*[-+]))';
  if n > 0 then raise exception '11: % função(ões) ainda escrevem o saldo', n; end if;

  -- 12. Quem pode chamar.
  if has_function_privilege('anon', 'public.ajustar_estoque(uuid, numeric, text, uuid)', 'execute')
     or has_function_privilege('anon', 'public.entrada_de_estoque(uuid, numeric, numeric, text, uuid)', 'execute') then
    raise exception '12: anon não pode mexer no estoque';
  end if;
  if not has_function_privilege('authenticated', 'public.ajustar_estoque(uuid, numeric, text, uuid)', 'execute') then
    raise exception '12: usuário logado precisa poder ajustar';
  end if;

  -- 13. Nada divergente no fim (inclui todos os produtos reais).
  select count(*) into n from public.estoque_saldos_divergentes();
  if n > 0 then raise exception '13: % produto(s) com saldo diferente da soma', n; end if;
end $$;

select 'ok: ajuste e entrada por movimento, porta fechada, kit, recálculo adiado, OS baixa/estorna, nenhuma função escreve o saldo, 0 divergentes' as resultado;
rollback;
