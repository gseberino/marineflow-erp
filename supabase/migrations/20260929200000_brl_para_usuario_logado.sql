-- "O mês está pronto?" quebrava com "permission denied for function _brl" (dono, 29/09/2026).
--
-- _brl formata um número em "R$ 1.234,56" (SQL puro, IMMUTABLE, não lê tabela nenhuma). A
-- migration 20260925200000 fechou a execução dela para authenticated junto com as funções de
-- escrita do Financeiro. Só que checklist_do_mes (20260926120000) roda com a permissão de quem
-- chama (SECURITY INVOKER) e usa _brl para escrever a diferença de saldo da conta que não fecha
-- ("C6 difere R$ …"). Resultado: o dono logado não conseguia ver se o mês estava pronto, nem
-- fechar o mês. As outras funções que usam _brl são SECURITY DEFINER e não sentiam o corte.
--
-- A correção é devolver a execução de _brl a quem está logado. anon continua sem (conferido no
-- teste supabase/tests/brl_usuario_logado.sql).

grant execute on function public._brl(numeric) to authenticated;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260929200000', 'brl_para_usuario_logado')
on conflict do nothing;
