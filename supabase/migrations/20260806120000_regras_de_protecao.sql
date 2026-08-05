-- ═══════════════════════════════════════════════════════════════════════════
-- Proteção sugerida por faixa de corrente
--
-- O dono notou que há muito serviço onde o sistema poderia sugerir material —
-- "dispositivos de proteção, entre outros". É o melhor lugar para a sugestão
-- automática existir: proteção é o item que se esquece de orçar e que ninguém
-- pode deixar de instalar. Sai do orçamento por descuido e volta como prejuízo.
--
-- ATENÇÃO AO QUE ESTAS REGRAS SÃO E AO QUE NÃO SÃO
--
-- Elas amarram FAIXA DE CORRENTE a um produto do catálogo. As faixas foram
-- escritas a partir da própria amperagem que o produto anuncia no nome — um
-- fusível de 60 A cobre a faixa até 60 A —, e NÃO de tabela de norma. O
-- dimensionamento correto depende também da bitola do cabo que a proteção
-- defende, da temperatura e do fabricante: conferir no manual do equipamento
-- e na especificação do cabo.
--
-- Por isso as quatro entram INATIVAS e valem como rascunho para conferência.
-- Uma proteção subdimensionada abre à toa; superdimensionada não protege o
-- cabo, e o cabo é que pega fogo. Ativar sem conferir seria transformar um
-- palpite meu em item de proposta assinada.
--
-- As faixas são contíguas e a semântica é [min, max): 60 A exatos NÃO cai no
-- fusível de 60 A, cai no de 100. É o lado seguro — fusível com a corrente
-- nominal passando por ele abre em serviço.
-- ═══════════════════════════════════════════════════════════════════════════

-- Todas dependem da pergunta de corrente, que também aguarda aprovação. Sem ela
-- ativa, nenhuma dispara — o que é a ordem certa: primeiro se passa a perguntar
-- a corrente, depois a corrente escolhe a proteção.
with corrente as (
  select id from public.service_survey_templates
  where applies_to_system = 'eletrico_dc'
    and question ilike '%corrente máxima do circuito%'
  limit 1
),
faixas as (
  select * from (values
    (null::numeric, 60::numeric, 'Fusível ANL/MIDI 60A + porta-fusível (kit x2)',
     'Até 60 A. O kit já traz o porta-fusível: separar fusível e suporte em '
     'linhas diferentes é como metade dos orçamentos esquece o suporte.'),
    (60::numeric, 100::numeric, 'Fusível Mega 100A/32V - 5 unidades - Victron Energy',
     'De 60 a 100 A. Vem em embalagem de 5 unidades — confira se a quantidade '
     'faz sentido para um circuito só antes de ativar.'),
    (100::numeric, 125::numeric, 'Fusível Mega 125A/32V - 5 unidades - Victron Energy',
     'De 100 a 125 A. Mesma observação da embalagem de 5.'),
    (125::numeric, null::numeric, 'Conjunto porta-fusíveis e fusíveis (80A, 100A, 150A, 300A)',
     'Acima de 125 A cai no conjunto de maior porte. Este item cobre várias '
     'amperagens de uma vez: é o candidato mais provável a precisar de ajuste '
     'manual na hora de fechar o orçamento.')
  ) as f(min_v, max_v, produto, porque)
)
insert into public.survey_material_rules
  (template_id, condition_type, min_value, max_value, product_id,
   qty_mode, qty_fixed, qty_round, rationale, origin, active)
select
  c.id, 'faixa', f.min_v, f.max_v, p.id,
  'fixa', 1, 'nenhum',
  f.porque || ' A FAIXA É RASCUNHO: saiu da amperagem que o próprio produto '
  'anuncia, não de tabela de norma. O dimensionamento real depende da bitola do '
  'cabo protegido — conferir no manual antes de ativar.',
  'ai', false
from corrente c
cross join faixas f
join lateral (
  -- O catálogo tem duplicata do kit de 60 A; pegar um só evita duas linhas
  -- iguais na sugestão.
  select id from public.products
  where active and name = f.produto
  order by created_at limit 1
) p on true
where not exists (
  select 1 from public.survey_material_rules r
  where r.template_id = c.id and r.product_id = p.id);
