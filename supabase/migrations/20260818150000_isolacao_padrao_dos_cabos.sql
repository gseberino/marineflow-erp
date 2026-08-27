-- ═══════════════════════════════════════════════════════════════════════════
-- A isolação dos cabos do catálogo, pela política da HBR
--
-- O dono definiu em 19/08/2026:
--
--   "considere padrão a isolação 105 para cabos acima de 25 mm² e 90 para
--    cabos até 16 mm²"
--
-- É a especificação que a HBR compra, e é o que faltava para o dimensionamento
-- escolher o cabo: sem a temperatura da isolação não há como saber quanta
-- corrente o condutor admite.
--
-- ═══ O 25 mm² FICA DE FORA, DE PROPÓSITO ═══
--
-- A regra dita cobre "acima de 25" e "até 16". O 25 mm² não cai em nenhuma das
-- duas faixas. Não preenchi por dedução: a diferença entre 90 e 105 °C no
-- 25 mm² é 150 A contra 175 A ao ar livre, e escolher a maior sem alguém dizer
-- seria liberar corrente que o cabo pode não admitir.
--
-- Enquanto ficar nulo, `dc_cable_product_for` simplesmente não o oferece e sobe
-- para o 35 mm² — mais caro, e seguro. Nada quebra.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

update public.products
   set conductor_insulation_c = 90
 where conductor_mm2 is not null and conductor_mm2 <= 16;

update public.products
   set conductor_insulation_c = 105
 where conductor_mm2 is not null and conductor_mm2 > 25;

comment on column public.products.conductor_insulation_c is
  'Temperatura da isolação (75, 90 ou 105 °C), como consta na especificação do
   fabricante. Política da HBR (19/08/2026): 90 °C para cabo até 16 mm², 105 °C
   acima de 25 mm². O 25 mm² não está coberto pela política — preencher com a
   especificação na mão. NÃO deduzir: é ela que decide quanta corrente o cabo
   admite, e errar para cima libera bitola que o cabo não aguenta.';

commit;
