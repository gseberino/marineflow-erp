-- 01 · Sequências (as de coluna IDENTITY nascem com a tabela e ficam só comentadas)
-- Gerado por scripts/snapshot-producao.mjs a partir dos catálogos do banco de produção.
-- NÃO editar à mão: regenerar. A data e as contagens ficam no README.md ao lado.

CREATE SEQUENCE IF NOT EXISTS public.document_number_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807;
