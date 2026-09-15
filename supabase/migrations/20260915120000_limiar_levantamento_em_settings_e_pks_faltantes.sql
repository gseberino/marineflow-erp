-- (1) NOVO-lev-32, metade que faltava: `should_survey_service` já lê
-- `app_settings.survey_valor_limiar` (com parse_valor_ptbr e padrão 3000) desde 10/09,
-- mas a chave nunca foi semeada — o "3000" só existia como literal dentro da função e
-- ninguém tinha onde mudar. Semear com o mesmo valor não muda comportamento nenhum; só
-- dá ao dono um lugar para ajustar quando quiser.
insert into public.app_settings (key, value, description)
values ('survey_valor_limiar', '3000',
        'Valor de orçamento (R$) a partir do qual o levantamento técnico passa a ser exigido antes do serviço.')
on conflict (key) do nothing;

-- (2) Advisor no_primary_key (15/09/2026): duas tabelas de apoio sem chave primária.
-- `products_stock_backup_pre_v2` é a foto do estoque antes do modelo v2 (413 ids únicos);
-- `reparo_coremma_20260805` é a cópia de segurança do reparo de 05/08 (82 ids únicos).
-- Sem PK, replicação lógica e o próprio Studio tratam a tabela como "não editável".
-- Provado antes: count(*) = count(distinct id) e zero nulos nas duas.
alter table public.products_stock_backup_pre_v2 add primary key (id);
alter table public.reparo_coremma_20260805 add primary key (id);

insert into supabase_migrations.schema_migrations (version, name)
values ('20260915120000', 'limiar_levantamento_em_settings_e_pks_faltantes')
on conflict do nothing;
