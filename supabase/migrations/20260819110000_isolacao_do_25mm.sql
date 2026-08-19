-- ═══════════════════════════════════════════════════════════════════════════
-- O 25 mm² entra na faixa de 105 °C
--
-- A política de 19/08 dizia "105 para cabos ACIMA de 25 mm² e 90 para cabos até
-- 16 mm²", e o 25 ficava sem faixa — a migration anterior o deixou nulo de
-- propósito, em vez de deduzir. O dono corrigiu no mesmo dia:
--
--   "a partir de 25 mm², o de 25 mm² também considere 105"
--
-- A política fica sem buraco: até 16 mm² → 90 °C; de 25 mm² para cima → 105 °C.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

update public.products
   set conductor_insulation_c = 105
 where conductor_mm2 is not null and conductor_mm2 >= 25;

comment on column public.products.conductor_insulation_c is
  'Temperatura da isolação (75, 90 ou 105 °C), como consta na especificação do
   fabricante. Política da HBR (19/08/2026): 90 °C para cabo até 16 mm²,
   105 °C a partir de 25 mm². NÃO deduzir fora dessa política: é ela que decide
   quanta corrente o cabo admite, e errar para cima libera bitola que o cabo não
   aguenta.';

commit;
