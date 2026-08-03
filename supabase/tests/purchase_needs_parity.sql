-- ─────────────────────────────────────────────────────────────────────────────
-- PARIDADE lib × RPC — aceite da Fase C0 do plano de Compras.
--
-- Roda contra public.compute_purchase_needs os MESMOS 14 casos de
-- src/lib/purchase-needs.test.ts. Se a regra divergir entre o TypeScript (telas)
-- e o SQL (agente), alguma linha aqui sai FALHOU.
--
-- É de leitura pura: não insere, não altera, não depende de dado de produção.
-- Rodar com:
--   npx supabase db query --linked -f supabase/tests/purchase_needs_parity.sql
-- ou colando no SQL Editor. Esperado: 14 linhas, todas PASS.
--
-- Ao mudar a regra, mude nos DOIS lugares e atualize os casos aqui e no .test.ts.
-- ─────────────────────────────────────────────────────────────────────────────

with casos as (
  select * from (values
   ('01 disponivel cobre',
    '[{"id":"a","product_id":"P1","quantity":4,"product_name":"Terminal M8"}]'::jsonb,'[]'::jsonb,
    '[{"id":"P1","stock_quantity":9,"reserved_quantity":0}]'::jsonb,'[]'::jsonb,
    '{"needsPurchase":false,"i0status":"ok","i0shortage":0,"i0available":4}'::jsonb),
   ('02 desconta reservado',
    '[{"id":"a","product_id":"P1","quantity":4}]'::jsonb,'[]'::jsonb,
    '[{"id":"P1","stock_quantity":10,"reserved_quantity":9}]'::jsonb,'[]'::jsonb,
    '{"needsPurchase":true,"i0status":"partial","i0shortage":3,"i0available":1}'::jsonb),
   ('03 reserva maior que fisico',
    '[{"id":"a","product_id":"P1","quantity":2}]'::jsonb,'[]'::jsonb,
    '[{"id":"P1","stock_quantity":1,"reserved_quantity":5}]'::jsonb,'[]'::jsonb,
    '{"needsPurchase":true,"i0status":"missing","i0shortage":2,"i0available":0}'::jsonb),
   ('04 desconta OC aberta',
    '[{"id":"a","product_id":"P1","quantity":6}]'::jsonb,'[]'::jsonb,
    '[{"id":"P1","stock_quantity":0,"reserved_quantity":0}]'::jsonb,
    '[{"product_id":"P1","quantity":6,"received_qty":0}]'::jsonb,
    '{"needsPurchase":false,"i0status":"on_order","i0shortage":0,"i0onOrder":6}'::jsonb),
   ('05 saldo de OC parcial',
    '[{"id":"a","product_id":"P1","quantity":6}]'::jsonb,'[]'::jsonb,
    '[{"id":"P1","stock_quantity":0,"reserved_quantity":0}]'::jsonb,
    '[{"product_id":"P1","quantity":6,"received_qty":4}]'::jsonb,
    '{"needsPurchase":true,"i0shortage":4,"i0onOrder":2}'::jsonb),
   ('06 duas linhas mesmo produto',
    '[{"id":"a","product_id":"P1","quantity":2},{"id":"b","product_id":"P1","quantity":2}]'::jsonb,'[]'::jsonb,
    '[{"id":"P1","stock_quantity":3,"reserved_quantity":0}]'::jsonb,'[]'::jsonb,
    '{"needsPurchase":true,"i0shortage":0,"i1available":1,"i1shortage":1}'::jsonb),
   ('07 produto sem disponibilidade',
    '[{"id":"a","product_id":"P2","quantity":3}]'::jsonb,'[]'::jsonb,'[]'::jsonb,'[]'::jsonb,
    '{"needsPurchase":true,"i0status":"missing","i0shortage":3}'::jsonb),
   ('08 numeric como string',
    '[{"id":"a","product_id":"P1","quantity":"2.500","unit_cost_snapshot":"10.50"}]'::jsonb,'[]'::jsonb,
    '[{"id":"P1","stock_quantity":"1.000","reserved_quantity":"0"}]'::jsonb,'[]'::jsonb,
    '{"needsPurchase":true,"i0required":2.5,"i0shortage":1.5,"estimatedCost":15.75}'::jsonb),
   ('09 material sem cadastro',
    '[]'::jsonb,'[{"id":"s1","service_id":null,"name_snapshot":"Cabo","billing_unit_snapshot":"unit","quantity":3,"unit_price_snapshot":40}]'::jsonb,
    '[]'::jsonb,'[]'::jsonb,
    '{"needsPurchase":true,"shortageCount":1,"i0status":"uncatalogued","i0shortage":3,"estimatedCost":120}'::jsonb),
   ('10 hora e deslocamento fora',
    '[]'::jsonb,'[{"id":"h","service_id":null,"name_snapshot":"Hora","billing_unit_snapshot":"hour","quantity":3},{"id":"v","service_id":null,"name_snapshot":"Desloc","billing_unit_snapshot":"visit","quantity":3}]'::jsonb,
    '[]'::jsonb,'[]'::jsonb,
    '{"needsPurchase":false,"nItems":0}'::jsonb),
   ('11 servico com cadastro fora',
    '[]'::jsonb,'[{"id":"s1","service_id":"svc-1","name_snapshot":"Cabo","billing_unit_snapshot":"unit","quantity":3}]'::jsonb,
    '[]'::jsonb,'[]'::jsonb,
    '{"needsPurchase":false,"nItems":0}'::jsonb),
   ('12 quantidade zero ou negativa',
    '[]'::jsonb,'[{"id":"s1","service_id":null,"name_snapshot":"C","billing_unit_snapshot":"unit","quantity":0},{"id":"s2","service_id":null,"name_snapshot":"C","billing_unit_snapshot":"unit","quantity":-1}]'::jsonb,
    '[]'::jsonb,'[]'::jsonb,
    '{"needsPurchase":false,"nItems":0}'::jsonb),
   ('13 ordem missing-partial-uncat',
    '[{"id":"parcial","product_id":"P1","quantity":4},{"id":"zerado","product_id":"P2","quantity":2}]'::jsonb,
    '[{"id":"livre","service_id":null,"name_snapshot":"Livre","billing_unit_snapshot":"unit","quantity":1}]'::jsonb,
    '[{"id":"P1","stock_quantity":2,"reserved_quantity":0},{"id":"P2","stock_quantity":0,"reserved_quantity":0}]'::jsonb,'[]'::jsonb,
    '{"needsPurchase":true,"shortageCount":3,"ordem":"zerado,parcial,livre"}'::jsonb),
   ('14 OS vazia',
    '[]'::jsonb,'[]'::jsonb,'[]'::jsonb,'[]'::jsonb,
    '{"needsPurchase":false,"shortageCount":0,"estimatedCost":0}'::jsonb)
  ) as t(caso, parts, free, avail, on_order, esperado)
),
res as (
  select c.caso, c.esperado,
         public.compute_purchase_needs('00000000-0000-0000-0000-000000000001'::uuid,
                                       c.parts, c.free, c.avail, c.on_order) as r
  from casos c
)
select caso,
  case when
    coalesce((esperado->>'needsPurchase')  is null or (r->>'needsPurchase') = (esperado->>'needsPurchase'), true)
    and coalesce((esperado->>'shortageCount') is null or (r->>'shortageCount')::numeric = (esperado->>'shortageCount')::numeric, true)
    and coalesce((esperado->>'estimatedCost') is null or (r->>'estimatedCost')::numeric = (esperado->>'estimatedCost')::numeric, true)
    and coalesce((esperado->>'nItems')     is null or jsonb_array_length(r->'items') = (esperado->>'nItems')::int, true)
    and coalesce((esperado->>'i0status')   is null or r->'items'->0->>'status' = (esperado->>'i0status'), true)
    and coalesce((esperado->>'i0shortage') is null or (r->'items'->0->>'shortage')::numeric = (esperado->>'i0shortage')::numeric, true)
    and coalesce((esperado->>'i0available')is null or (r->'items'->0->>'available')::numeric = (esperado->>'i0available')::numeric, true)
    and coalesce((esperado->>'i0onOrder')  is null or (r->'items'->0->>'onOrder')::numeric = (esperado->>'i0onOrder')::numeric, true)
    and coalesce((esperado->>'i0required') is null or (r->'items'->0->>'required')::numeric = (esperado->>'i0required')::numeric, true)
    and coalesce((esperado->>'i1available')is null or (r->'items'->1->>'available')::numeric = (esperado->>'i1available')::numeric, true)
    and coalesce((esperado->>'i1shortage') is null or (r->'items'->1->>'shortage')::numeric = (esperado->>'i1shortage')::numeric, true)
    and coalesce((esperado->>'ordem') is null or
        (select string_agg(s->>'sourceId', ',' order by ord)
         from jsonb_array_elements(r->'shortages') with ordinality as x(s, ord)) = (esperado->>'ordem'), true)
  then 'PASS' else 'FALHOU' end as resultado,
  r->>'shortageCount' as qtd_falta,
  r->>'estimatedCost' as custo,
  (select string_agg(s->>'sourceId', ',' order by ord)
     from jsonb_array_elements(r->'shortages') with ordinality as x(s, ord)) as ordem_real
from res order by caso;
