-- Correção de vazamento: as duas views de estoque criadas em 27/07 nasceram sem
-- security_invoker e com SELECT liberado para anon. View sem security_invoker roda
-- com os direitos do DONO, ignorando a RLS das tabelas base — e com anon podendo
-- ler, qualquer portador da chave pública veria catálogo, custo, preço e estoque.
--
-- Regra para toda view nova neste projeto: security_invoker=on E revoke de anon,
-- na MESMA migration que cria a view.

alter view public.v_estoque_variancia set (security_invoker = on);
alter view public.v_estoque_entradas_pendentes set (security_invoker = on);

revoke all on public.v_estoque_variancia from anon;
revoke all on public.v_estoque_entradas_pendentes from anon;

grant select on public.v_estoque_variancia to authenticated;
grant select on public.v_estoque_entradas_pendentes to authenticated;
