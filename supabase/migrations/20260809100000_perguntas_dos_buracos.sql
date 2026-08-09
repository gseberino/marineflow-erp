-- ═══════════════════════════════════════════════════════════════════════════
-- As perguntas que faltavam — medidas, não adivinhadas
--
-- A varredura de cobertura por dimensão mostrou onde o levantamento é cego:
--
--   foto 12 · acesso 9 · medida 9 · identificação 7   → bem servidas
--   compatibilidade 3 · proteção 3 · prazo 3          → magras
--   logística no local 1 · garantia 0                 → buracos
--   verbo `projeto`: 8 serviços, ZERO perguntas       → buraco total
--
-- Entram SETE, não setenta. O levantamento mostra no máximo 9 perguntas por
-- serviço (teto do P16), e elas competem entre si: pergunta a mais no verbo
-- empurra pergunta do sistema para fora da lista. Cada uma abaixo precisa
-- justificar o lugar que ocupa — e o critério é um só: muda o preço?
--
-- Todas INATIVAS, como toda pergunta nova.
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- VERBO `projeto` — 8 serviços e nenhuma pergunta
--
-- São consultoria, assessoria e elaboração: "Projeto Elétrico", "ASSESSORIA E
-- ELABORAÇÃO DE PROJETO DE AUTOMAÇÃO", "CONSULTORIA TÉCNICA". Não se instala
-- nada, então as perguntas de acesso e medida do sistema não bastam — o que
-- decide o preço aqui é o ESCOPO da entrega e quantas voltas ela vai dar.
-- ───────────────────────────────────────────────────────────────────────────
insert into public.service_survey_templates
  (service_id, seq, question, help_text, answer_type, options, price_impact,
   ask_remotely, origin, active, applies_to_verb, version)
select * from (values
  (null::uuid, 1,
   'O que precisa ser entregue no projeto?',
   'Diagrama unifilar, memorial descritivo e lista de materiais são três '
   'trabalhos diferentes, e o cliente costuma pedir "um projeto" pensando em '
   'um só deles. Combinar isto por escrito é o que evita a discussão na '
   'entrega.',
   'escolha',
   '["Diagrama / esquema","Memorial descritivo","Lista de materiais","Diagrama + memorial + lista","Só orientação técnica (sem documento)"]'::jsonb,
   'alto', true, 'ai', false, 'projeto', 1),

  (null::uuid, 2,
   'Já existe projeto ou documentação do que está instalado?',
   'Partir de um desenho existente é atualizar; partir do nada é levantar tudo '
   'em campo antes de desenhar. A diferença entre os dois é a maior parte do '
   'tempo deste serviço.',
   'escolha',
   '["Existe e está atualizado","Existe mas está desatualizado","Não existe nada"]'::jsonb,
   'alto', true, 'ai', false, 'projeto', 1),

  (null::uuid, 3,
   'Quantas revisões estão incluídas?',
   'Projeto sem limite de revisão é o que come a margem: cada "só mais um '
   'ajuste" refaz o desenho inteiro. Dizer o número no orçamento transforma a '
   'revisão extra em item a cobrar, em vez de prejuízo silencioso.',
   'numero', null, 'alto', true, 'ai', false, 'projeto', 1),

  (null::uuid, 4,
   'O projeto precisa de ART ou responsável técnico registrado?',
   'ART tem custo e prazo próprios, e exige profissional habilitado. Descobrir '
   'isso depois de orçar é assumir um custo que não foi cobrado.',
   'sim_nao', null, 'alto', true, 'ai', false, 'projeto', 1),

  (null::uuid, 5,
   'Quem vai executar a obra depois?',
   'Projeto que a própria HBR executa pode deixar detalhe para resolver em '
   'campo. Projeto que vai para a mão de terceiros precisa estar fechado, sem '
   'ambiguidade — e isso é mais trabalho de desenho e de escrita.',
   'escolha', '["A própria HBR","Terceiros","Ainda não definido"]'::jsonb,
   'medio', true, 'ai', false, 'projeto', 1)
) as novas(service_id, seq, question, help_text, answer_type, options, price_impact,
           ask_remotely, origin, active, applies_to_verb, version)
where not exists (
  select 1 from public.service_survey_templates t
  where t.applies_to_verb = 'projeto' and t.question = novas.question);

-- ───────────────────────────────────────────────────────────────────────────
-- GARANTIA — zero perguntas em 78
--
-- Só no verbo `reparo`, que é onde a resposta muda a DECISÃO e não apenas o
-- preço: abrir um equipamento na garantia do fabricante costuma anulá-la, e
-- essa conversa tem que acontecer antes do orçamento, não depois da chave de
-- fenda.
-- ───────────────────────────────────────────────────────────────────────────
insert into public.service_survey_templates
  (service_id, seq, question, help_text, answer_type, options, price_impact,
   ask_remotely, origin, active, applies_to_verb, version)
select null, 6,
  'O equipamento ainda está na garantia do fabricante?',
  'Abrir equipamento na garantia costuma anulá-la. Se estiver, o caminho pode '
  'ser acionar o fabricante em vez de reparar — e essa conversa é antes do '
  'orçamento, não depois de aberto. Pedir a nota ou a data da compra resolve.',
  'escolha',
  '["Sim, na garantia","Fora da garantia","Não sei / sem nota"]'::jsonb,
  'alto', true, 'ai', false, 'reparo', 1
where not exists (
  select 1 from public.service_survey_templates t
  where t.applies_to_verb = 'reparo' and t.question ilike '%garantia do fabricante%');

-- ───────────────────────────────────────────────────────────────────────────
-- LOGÍSTICA NO LOCAL — uma pergunta em 78
--
-- No verbo `instalacao`, que tem 97 serviços — o maior de todos. Trabalho de
-- instalação em marina ou pátio sem tomada obriga a levar gerador, e isso é
-- custo e tempo que ninguém lembra de orçar até chegar lá.
-- ───────────────────────────────────────────────────────────────────────────
insert into public.service_survey_templates
  (service_id, seq, question, help_text, answer_type, options, price_impact,
   ask_remotely, origin, active, applies_to_verb, version)
select null, 5,
  'Há energia elétrica disponível no local do serviço?',
  'Sem tomada, é preciso levar gerador — custo, combustível e tempo de montagem '
  'que não aparecem em lugar nenhum do orçamento se ninguém perguntar. Vale '
  'conferir também se a tomada aguenta a ferramenta.',
  'escolha',
  '["Sim, 220 V","Sim, 127 V","Não há energia no local","Não sei"]'::jsonb,
  'medio', true, 'ai', false, 'instalacao', 1
where not exists (
  select 1 from public.service_survey_templates t
  where t.applies_to_verb = 'instalacao' and t.question ilike '%energia elétrica dispon%');
