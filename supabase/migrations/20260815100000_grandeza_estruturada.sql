-- ═══════════════════════════════════════════════════════════════════════════
-- Grandeza deixa de ser prosa
--
-- No ORÇ-00074 a pergunta da distância foi respondida assim:
--
--   "entre o banco de baterias e o inversor, o caminho que o cabo positivo faz
--    é de aproximadamente 2,5 metros. E até o quadro de disjuntores é de 2 m"
--
-- O motor leu 2,5 e ignorou o resto — cabo dimensionado para metade do
-- percurso. Só não virou erro porque há um alerta na linha, e o alerta existe
-- porque o campo aceita prosa.
--
-- MAS A CULPA NÃO É DE QUEM RESPONDEU. A pergunta pede "a distância entre o
-- banco, O INVERSOR E O QUADRO" — são DOIS trechos, e havia um campo só. Quem
-- respondeu deu a informação completa; o formulário é que não tinha onde
-- guardá-la. O mesmo vale para "consumo diário E autonomia" (duas grandezas) e
-- "as MEDIDAS do vão" (três).
--
-- Então são duas mudanças, e a ordem importa: primeiro o campo passa a guardar
-- número e unidade separados; depois as perguntas que pedem mais de uma coisa
-- são desdobradas.
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- 1. A pergunta declara a unidade e a faixa que espera
-- ───────────────────────────────────────────────────────────────────────────
alter table public.service_survey_templates
  add column if not exists expected_unit text,
  add column if not exists min_expected numeric,
  add column if not exists max_expected numeric;

comment on column public.service_survey_templates.expected_unit is
  'Unidade que a resposta deve ter (m, A, Ah, W, °C, L). Impressa ao lado do
   campo na tela e na folha — "14" sem unidade volta e ninguém sabe se é metro
   ou centímetro, e quem mediu já foi embora.';

comment on column public.service_survey_templates.min_expected is
  'Piso do que é plausível. Não barra: avisa. Faixa que barra leitura correta é
   pior que faixa nenhuma — o mundo real tem exceção, e quem está no local vê o
   que o cadastro não previu.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. A resposta guarda o número separado do texto
--
-- O texto CONTINUA sendo gravado: é ele que carrega o contexto ("2,5 até o
-- inversor, medido por cima do forro"). O número é o que o cálculo usa. Perder
-- o texto para ganhar o número seria trocar informação por conveniência.
-- ───────────────────────────────────────────────────────────────────────────
alter table public.service_survey_answers
  add column if not exists numeric_value numeric,
  add column if not exists answer_unit text;

comment on column public.service_survey_answers.numeric_value is
  'O número, quando a pergunta é de grandeza. O que o dimensionamento e as
   regras de material leem — em vez de garimpar dígito no meio da frase.';

-- ───────────────────────────────────────────────────────────────────────────
-- 3. As unidades e faixas das nove perguntas de grandeza
--
-- As faixas saem do que a HBR faz e do catálogo dela, não de norma: são
-- plausibilidade, não especificação. Entram para AVISAR quando o valor está
-- fora do que se costuma ver — o caso da vírgula trocada, que transforma 2,5 m
-- em 25 m e o cabo em quatro vezes o preço.
--
-- Onde não há base para dizer o que é plausível, a faixa fica NULA. Faixa
-- inventada barra leitura correta, e aí quem está em campo aprende a ignorar o
-- aviso — que é o pior desfecho possível para um alerta.
-- ───────────────────────────────────────────────────────────────────────────
update public.service_survey_templates set expected_unit = 'm',
       min_expected = 0.5, max_expected = 60
 where active and question ilike '%distância entre o banco%';

update public.service_survey_templates set expected_unit = 'A',
       min_expected = 1, max_expected = 600
 where active and question ilike '%corrente máxima do circuito%';

update public.service_survey_templates set expected_unit = 'm',
       min_expected = 0.5, max_expected = 30
 where active and question ilike '%distância do cilindro%';

update public.service_survey_templates set expected_unit = '°C',
       min_expected = -30, max_expected = 40
 where active and question ilike '%temperatura que ele alcança%';

update public.service_survey_templates set expected_unit = 'W',
       min_expected = 100, max_expected = 20000
 where active and question ilike '%potência total%';

update public.service_survey_templates set expected_unit = 'aparelhos',
       min_expected = 1, max_expected = 10
 where active and question ilike '%Quantos aparelhos%';

update public.service_survey_templates set expected_unit = 'L',
       min_expected = 20, max_expected = 2000
 where active and question ilike '%capacidade do tanque%';

-- Horímetro e odômetro não têm faixa: um motorhome pode ter 3.000 km ou
-- 300.000, e as duas leituras são verdade.
update public.service_survey_templates set expected_unit = 'h ou km'
 where active and question ilike '%horas de uso ou quilometragem%';

-- ───────────────────────────────────────────────────────────────────────────
-- 4. As perguntas que pediam mais de uma grandeza
--
-- Cada uma vira quantas grandezas ela realmente pede. As novas entram
-- INATIVAS, como toda pergunta nova, e a original é reescrita para pedir UMA
-- coisa só.
-- ───────────────────────────────────────────────────────────────────────────

-- "distância entre o banco, o inversor E o quadro" → dois trechos.
-- É a que causou o caso real: o percurso do banco ao inversor e o do inversor
-- ao quadro têm correntes diferentes e podem pedir bitolas diferentes.
update public.service_survey_templates
   set question = 'Qual a distância do banco de baterias até o inversor?',
       help_text = 'Só este trecho, medindo o caminho real do cabo — por cima '
                   'do forro, contornando o que houver. O trecho até o quadro '
                   'é perguntado separado, porque a corrente é outra.'
 where active and question ilike '%distância entre o banco%';

insert into public.service_survey_templates
  (service_id, seq, question, help_text, answer_type, options, price_impact,
   ask_remotely, origin, active, applies_to_system, affects, expected_unit,
   min_expected, max_expected, version)
select null, 17,
  'Qual a distância do inversor (ou banco) até o quadro de distribuição?',
  'O segundo trecho. Perguntar junto com o primeiro fazia a resposta vir com '
  'dois números num campo só — e o cálculo lia apenas o primeiro, '
  'dimensionando cabo para metade do percurso.',
  'medida', null, 'alto', false, 'ai', false, 'eletrico_dc',
  array['comprimento'], 'm', 0.5, 60, 1
where not exists (
  select 1 from public.service_survey_templates
  where applies_to_system = 'eletrico_dc' and question ilike '%até o quadro de distribuição%');

-- "consumo diário E autonomia" → duas grandezas, e são elas que dimensionam
-- o banco inteiro. Juntas num campo, nenhuma das duas serve para calcular.
update public.service_survey_templates
   set question = 'Qual o consumo diário esperado?',
       answer_type = 'medida',
       expected_unit = 'Ah/dia',
       min_expected = 10, max_expected = 2000,
       help_text = 'Geladeira, ar, bomba, tomadas — somados por dia. É a metade '
                   'da conta do banco; a outra é a autonomia, perguntada em '
                   'seguida.'
 where active and question ilike '%consumo diário e a autonomia%';

insert into public.service_survey_templates
  (service_id, seq, question, help_text, answer_type, options, price_impact,
   ask_remotely, origin, active, applies_to_system, expected_unit,
   min_expected, max_expected, version)
select null, 18,
  'Quantos dias de autonomia o cliente espera, sem geração?',
  'Sem sol e sem alternador. Consumo diário × dias = o banco mínimo. Perguntado '
  'separado do consumo porque são dois números, e juntos num campo só nenhum '
  'dos dois entra na conta.',
  'medida', null, 'alto', true, 'ai', false, 'eletrico_dc',
  'dias', 1, 15, 1
where not exists (
  select 1 from public.service_survey_templates
  where applies_to_system = 'eletrico_dc' and question ilike '%dias de autonomia%');

-- "as MEDIDAS do vão" → três dimensões. Uma resposta como "60x55x60" obriga
-- quem lê a adivinhar qual é qual.
update public.service_survey_templates
   set question = 'Qual a LARGURA do vão onde o equipamento entra?',
       expected_unit = 'cm', min_expected = 10, max_expected = 300,
       help_text = 'Medir o vão livre, não o equipamento. Altura e profundidade '
                   'vêm em seguida — três medidas num campo só voltam como '
                   '"60x55x60" e ninguém sabe qual é qual.'
 where active and question ilike '%medidas do vão%';

insert into public.service_survey_templates
  (service_id, seq, question, help_text, answer_type, options, price_impact,
   ask_remotely, origin, active, applies_to_system, expected_unit,
   min_expected, max_expected, version)
select * from (values
  (null::uuid, 19, 'Qual a ALTURA do vão?',
   'Vão livre, com a porta ou tampa aberta se for o caso.',
   'medida', null::jsonb, 'alto', false, 'ai', false, 'refrigeracao',
   'cm', 10::numeric, 300::numeric, 1),
  (null::uuid, 20, 'Qual a PROFUNDIDADE do vão?',
   'Até o fundo útil. É a medida que mais reprova equipamento na hora de '
   'encaixar, porque atrás costuma haver mangueira, cabo ou estrutura.',
   'medida', null::jsonb, 'alto', false, 'ai', false, 'refrigeracao',
   'cm', 10::numeric, 300::numeric, 1)
) as novas(service_id, seq, question, help_text, answer_type, options, price_impact,
           ask_remotely, origin, active, applies_to_system, expected_unit,
           min_expected, max_expected, version)
where not exists (
  select 1 from public.service_survey_templates t
  where t.applies_to_system = 'refrigeracao' and t.question = novas.question);
