-- ═══════════════════════════════════════════════════════════════════════════
-- Primeiras regras de material — e uma pergunta que faltava
--
-- Escrevi POUCAS de propósito. A pesquisa no catálogo mostrou que a HBR
-- trabalha por kit fechado, não por insumo: o material mais lançado é
-- "Kit Cabos/Conectores/Terminais do Novo Sistema" (8 das últimas OSs, sempre
-- quantidade 1) e não existe mangueira de GLP vendida por metro. Faixa de
-- dimensionamento ("até 5 m usa isto, acima usa aquilo") é conhecimento da
-- casa, com número que eu não tenho de onde tirar — e chutar aqui produziria
-- um orçamento errado com cara de conta feita.
--
-- Então entra o que é aritmética indiscutível, e o resto é escrito na tela.
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- A pergunta que destrava o dimensionamento de cabo
--
-- O levantamento pergunta a DISTÂNCIA, que define o comprimento. Não pergunta
-- a CORRENTE, que é o que define a bitola. Sem ela, qualquer regra que escolha
-- entre 16, 25, 35 e 70 mm² seria adivinhação — e cabo subdimensionado
-- esquenta. Com ela, dá para escrever a faixa uma vez e nunca mais pensar.
--
-- Entra inativa: pergunta nova só vale depois de aprovada.
-- ───────────────────────────────────────────────────────────────────────────
insert into public.service_survey_templates
  (service_id, seq, question, help_text, answer_type, options, price_impact,
   ask_remotely, origin, active, applies_to_system, version)
select
  null, 12,
  'Qual a corrente máxima do circuito, em ampères?',
  'É a corrente que define a bitola do cabo — a distância só define o comprimento. '
  'Onde não houver placa, conferir no manual do equipamento: inversor, carregador ou fonte.',
  'medida', null, 'alto', false, 'ai', false, 'eletrico_dc', 1
where not exists (
  select 1 from public.service_survey_templates
  where applies_to_system = 'eletrico_dc'
    and question ilike '%corrente máxima do circuito%');

-- ───────────────────────────────────────────────────────────────────────────
-- Regra 1 — o comprimento do cabo DC
--
-- Esta é a conta que ninguém discute e que todo mundo erra na pressa: o
-- circuito é de ida e volta. Mede-se 14 m entre o banco e o quadro e compra-se
-- 14 m de cabo; faltam 14, porque o negativo tem que voltar. Daí o fator 2.
--
-- A folga de 15% é de corte: cabo se dobra, contorna, e quem compra exato
-- emenda no meio do trecho — emenda em circuito de alta corrente é ponto
-- quente.
--
-- O PRODUTO é uma escolha, não um cálculo. Apontei para o 35 mm² porque é o
-- único da faixa com preço coerente por metro (R$ 4,15/mm² contra R$ 3,10 do
-- 25 e R$ 4,90 do 70). Troque na tela quando a corrente pedir outra bitola —
-- e veja o alerta do 16 mm² no relatório que te mandei.
-- ───────────────────────────────────────────────────────────────────────────
insert into public.survey_material_rules
  (template_id, condition_type, product_id, qty_mode, qty_factor,
   qty_slack_pct, qty_round, rationale, origin, active)
select t.id, 'sempre', p.id, 'proporcional', 2, 15, 'cima',
  'O circuito é de ida e volta: o positivo vai e o negativo volta, por isso 2 m '
  'de cabo por metro medido. Os 15% são folga de corte — comprar exato obriga a '
  'emendar, e emenda em alta corrente é ponto quente. A BITOLA é sua escolha: '
  'troque o produto conforme a corrente do circuito.',
  'ai', false
from public.service_survey_templates t
cross join public.products p
where t.applies_to_system = 'eletrico_dc'
  and t.question ilike '%distância entre o banco%'
  and p.name = 'Cabo flexível 35 mm² - ligação da fonte 120A'
  and not exists (
    select 1 from public.survey_material_rules r
    where r.template_id = t.id and r.product_id = p.id);

-- ───────────────────────────────────────────────────────────────────────────
-- Regra 2 — um conjunto de conexão por aparelho de gás
--
-- Contagem pura: dois aparelhos na mesma linha pedem dois conjuntos de
-- conexão. Não há mangueira por metro no catálogo, então a distância medida
-- não vira material sozinha — ela serve para você decidir o kit.
-- ───────────────────────────────────────────────────────────────────────────
insert into public.survey_material_rules
  (template_id, condition_type, product_id, qty_mode, qty_factor,
   qty_round, rationale, origin, active)
select t.id, 'sempre', p.id, 'por_unidade', 1, 'cima',
  'Um conjunto de conexão por aparelho na linha. A metragem da mangueira não '
  'entra sozinha porque o catálogo não tem mangueira de GLP por metro — só kit '
  'fechado; se passar a comprar por metro, me peça a regra proporcional.',
  'ai', false
from public.service_survey_templates t
cross join public.products p
where t.applies_to_system = 'gas'
  and t.question ilike '%Quantos aparelhos%'
  and p.name = 'Kit Mangueira e Conexões Gás para Fogareiro externo'
  and not exists (
    select 1 from public.survey_material_rules r
    where r.template_id = t.id and r.product_id = p.id);
