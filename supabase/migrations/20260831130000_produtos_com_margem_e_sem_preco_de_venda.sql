-- Produtos que nasceram valendo R$ 0,00 porque a margem era aceita e ignorada.
--
-- `create_product` fazia `insert(args)` cru: o input_schema anuncia `profit_margin` ("Margem em %"),
-- o agente obedecia e mandava `cost_price` + `profit_margin`, e nada calculava `sale_price`. O
-- produto entrava no catálogo sem preço, ia para o orçamento valendo zero, e o dono perguntava
-- "por que a maioria dos materiais está sem preço?" — foi exatamente o que aconteceu em 31/08/2026.
--
-- O defeito já foi corrigido no código (supabase/functions/_shared/ai/product-create.ts, com
-- testes). Esta migration limpa o que ficou para trás.
--
-- ESCOPO DELIBERADAMENTE ESTREITO: só corrige quem tem CUSTO e MARGEM, onde o preço é uma conta e
-- não um palpite. Havia 39 produtos ativos sem preço de venda; 11 se enquadram. Os outros 28 não
-- têm custo — para eles, qualquer número seria invenção, e preço inventado num orçamento é pior do
-- que preço ausente, porque ninguém percebe. Ficam como estão, visíveis pela mesma consulta que
-- gerou esta migration.

do $$
declare
  v_corrigidos integer;
begin
  with alvo as (
    select id, cost_price, profit_margin,
           round(cost_price * (1 + profit_margin / 100.0), 2) as preco_calculado
    from public.products
    where coalesce(active, true)
      and coalesce(sale_price, 0) = 0
      and coalesce(cost_price, 0) > 0
      and profit_margin is not null
      and profit_margin > 0
      and profit_margin <= 200   -- margem acima disso é dado sujo, não margem: não se corrige no escuro
  )
  update public.products p
  set sale_price = a.preco_calculado,
      notes = concat_ws(
        E'\n', nullif(p.notes, ''),
        'Preço de venda calculado em 31/08/2026 a partir do custo (R$ ' || a.cost_price ||
        ') e da margem de ' || a.profit_margin || '% que já estavam no cadastro. ' ||
        'O produto havia sido criado sem preço por um defeito da ferramenta do agente.'),
      updated_at = now()
  from alvo a
  where p.id = a.id;

  get diagnostics v_corrigidos = row_count;
  raise notice 'Produtos com preço de venda calculado: %', v_corrigidos;
end $$;
