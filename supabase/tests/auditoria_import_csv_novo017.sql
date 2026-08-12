-- [NOVO-017] Auditoria SOMENTE LEITURA dos registros que o importador de CSV pode ter gravado
-- errado. Nenhum UPDATE, nenhum DELETE. A correção dos dados passados é decisão do dono.
--
--   psql:      \i supabase/tests/auditoria_import_csv_novo017.sql
--   supabase:  supabase db query --linked -f supabase/tests/auditoria_import_csv_novo017.sql
--
-- ─────────────────────────────────────────────────────────────────────────────────────────
-- O QUE DÁ PARA PROVAR, E O QUE NÃO DÁ
--
-- O defeito era `parseFloat(str.replace(',', '.'))`: trocava só a PRIMEIRA vírgula e deixava
-- o ponto de milhar. Isso produz DOIS resultados diferentes, e só um deles deixa rastro:
--
--   "1.234,56"  → "1.234.56" → parseFloat para no 2º ponto → 1.234   ← 3 casas decimais: RASTRO
--   "12.500,00" → "12.500.00" → 12.5                                  ← indistinguível de 12,50
--   "1.500"     → parseInt → 1                                        ← indistinguível de 1
--
-- Ou seja: o critério forte (mais de 2 casas decimais) acha só o primeiro caso. Os outros
-- dois são MATEMATICAMENTE indistinguíveis de um valor legítimo — nenhuma consulta os separa,
-- e quem quiser certeza precisa do arquivo CSV original.
--
-- Medido em 11/08/2026 nesta base: o critério forte devolveu ZERO produtos. Isso NÃO significa
-- "nada foi corrompido"; significa que, se houve, caiu nos casos sem rastro.
-- ─────────────────────────────────────────────────────────────────────────────────────────

\echo '=== 1. CRITÉRIO FORTE — preço com mais de 2 casas decimais ==='
\echo '    Preço de catálogo não tem 3 casas. Encontrar aqui é quase certeza do defeito.'
select 'sale_price' as campo, id, sku, name, sale_price as valor,
       sale_price * 1000 as valor_se_fosse_milhar
from public.products
where sale_price is not null and scale(sale_price::numeric) > 2
union all
select 'cost_price', id, sku, name, cost_price, cost_price * 1000
from public.products
where cost_price is not null and scale(cost_price::numeric) > 2
order by 1, 5 desc;

\echo ''
\echo '=== 2. CRITÉRIO FRACO — suspeitos por ordem de grandeza (NÃO é prova) ==='
\echo '    Produto cujo preço é ao menos 100x menor que a mediana da sua categoria.'
\echo '    Serve para OLHAR, não para corrigir em lote: produto barato de verdade cai aqui.'
with mediana as (
  select category_id,
         percentile_cont(0.5) within group (order by sale_price) as med
  from public.products
  where sale_price > 0
  group by category_id
)
select p.id, p.sku, p.name, p.sale_price, round(m.med, 2) as mediana_da_categoria,
       round((m.med / nullif(p.sale_price, 0))::numeric, 1) as quantas_vezes_menor
from public.products p
join mediana m on m.category_id is not distinct from p.category_id
where p.sale_price > 0
  and m.med > 0
  and p.sale_price < m.med / 100
order by quantas_vezes_menor desc
limit 50;

\echo ''
\echo '=== 3. ESTOQUE que pode ter virado 1 ==='
\echo '    parseInt("1.500") = 1. Estoque exatamente 1 é comum de verdade, então isto é só'
\echo '    uma lista para conferir contra a planilha de origem — nunca para corrigir sozinho.'
select id, sku, name, stock_quantity, minimum_stock
from public.products
where stock_quantity = 1
order by name;

\echo ''
\echo '=== 4. TELEFONE possivelmente apagado pela coluna vazia ==='
\echo '    O mapeamento manda Celular E Telefone para o mesmo campo, e o vazio sobrescrevia.'
\echo '    Cliente COM e-mail (sinal de cadastro completo) e SEM telefone é o suspeito.'
select id, name, email, created_at::date as criado_em
from public.clients
where (phone is null or btrim(phone) = '')
  and email is not null and btrim(email) <> ''
order by created_at desc
limit 100;

\echo ''
\echo '=== 5. RESUMO ==='
select
  (select count(*) from public.products
     where (sale_price is not null and scale(sale_price::numeric) > 2)
        or (cost_price is not null and scale(cost_price::numeric) > 2)) as criterio_forte_precos,
  (select count(*) from public.products where stock_quantity = 1)       as estoque_igual_1,
  (select count(*) from public.clients
     where (phone is null or btrim(phone) = '')
       and email is not null and btrim(email) <> '')                    as sem_telefone_com_email,
  (select count(*) from public.products)                                as total_produtos,
  (select count(*) from public.clients)                                 as total_clientes;
