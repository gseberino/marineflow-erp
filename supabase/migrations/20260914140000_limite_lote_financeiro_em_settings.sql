-- Executivo Financeiro, trava nº 2 do plano de 29/07/2026: "o limite vive no banco, não no
-- prompt nem no código". O valor (R$ 500 por proposta para entrar na aprovação em lote) foi
-- decidido pelo dono em 29/07 e estava duplicado como constante em dois lugares
-- (supabase/functions/finance-review/index.ts e src/hooks/use-finance-review.ts), livres para
-- divergir. Agora edge e tela leem a mesma chave; a constante vira só o padrão de segurança.

insert into public.app_settings (key, value)
values ('finance_review_batch_limit', '500')
on conflict (key) do nothing;

-- Auto-registro da versão do arquivo (regra 1 do CLAUDE.md).
insert into supabase_migrations.schema_migrations (version, name)
values ('20260914140000', 'limite_lote_financeiro_em_settings')
on conflict (version) do nothing;
