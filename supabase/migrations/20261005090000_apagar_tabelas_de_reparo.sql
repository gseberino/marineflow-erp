-- Apaga as duas tabelas de reparo e a view de diagnóstico que dependia de uma delas
-- (autorização do dono na conversa, 05/10/2026: "pode apagar as tabelas de reparo junto com a
-- view de variância").
--
-- · products_stock_backup_pre_v2 — cópia do estoque antes da mudança de julho (413 linhas);
-- · reparo_coremma_20260805 — conserto pontual de 05/08 (82 linhas);
-- · v_estoque_variancia — diagnóstico da Fase B do estoque (27/07); nenhuma tela nem função a lia.
--   O estoque hoje é a soma do razão (fases A–E, 30/09) e o diagnóstico vivo é
--   estoque_saldos_divergentes().
--
-- Cópia antes de apagar: D:/IA-HBR/Backups/reparo-20261004/ (as duas tabelas em JSON, uma linha por
-- registro, e a definição da view).

drop view if exists public.v_estoque_variancia;
drop table if exists public.products_stock_backup_pre_v2;
drop table if exists public.reparo_coremma_20260805;
