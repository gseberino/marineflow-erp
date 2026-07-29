-- Plano de contas do financeiro — desenhado a partir do extrato real da empresa.
--
-- POR QUE REFAZER: a tabela tinha 36 linhas que eram 18 categorias DUPLICADAS (a mesma
-- carga rodou duas vezes, em abril e maio), e nenhuma delas estava ligada a lançamento
-- nenhum — contas a pagar e receber guardam categoria como texto livre. Na prática não
-- havia plano de contas, havia uma lista esquecida.
--
-- A lista nova saiu de 1.583 saídas reais do extrato do último ano, cruzadas com a
-- estrutura de DRE de prestadora de serviços (receita → custo dos serviços prestados →
-- despesas operacionais → resultado financeiro).
--
-- A DECISÃO MAIS IMPORTANTE está no grupo `nao_operacional`: transferência entre contas
-- da própria empresa, pagamento de fatura de cartão, aplicação financeira e principal de
-- empréstimo NÃO são despesa. Sem separar isso, o resultado fica grosseiramente errado —
-- e o extrato mostra que esse dinheiro é volumoso: pagamento de fatura do cartão sozinho
-- soma R$ 76 mil, e a despesa de verdade está nos itens dentro da fatura, não nela.

ALTER TABLE public.financial_categories
  ADD COLUMN IF NOT EXISTS dre_group text,
  ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS description text;

COMMENT ON COLUMN public.financial_categories.dre_group IS
  'Onde a categoria entra no resultado: receita, custo_direto, despesa_operacional, financeiro, nao_operacional. O grupo nao_operacional fica FORA do resultado.';

-- Desativa tudo que existia: duplicado e sem uso. Desativar em vez de apagar preserva
-- qualquer referência histórica por nome.
UPDATE public.financial_categories SET active = false;

-- Recria a lista pelo par (nome, tipo), que é o que identifica a categoria na prática.
CREATE UNIQUE INDEX IF NOT EXISTS financial_categories_nome_tipo
  ON public.financial_categories (name, type);

INSERT INTO public.financial_categories (name, type, dre_group, sort_order, color, active, description) VALUES
  -- ── RECEITAS ──────────────────────────────────────────────────────────────
  ('Serviços prestados',            'receivable', 'receita', 10, '#10b981', true, 'Mão de obra dos serviços executados'),
  ('Venda de peças e produtos',     'receivable', 'receita', 20, '#3b82f6', true, 'Revenda de peças, equipamentos e materiais'),
  ('Contrato recorrente',           'receivable', 'receita', 30, '#84cc16', true, 'Mensalidades e contratos de manutenção'),
  ('Sinal e adiantamento',          'receivable', 'receita', 40, '#f59e0b', true, 'Entrada recebida antes da execução'),
  ('Reembolso de cliente',          'receivable', 'receita', 50, '#06b6d4', true, 'Despesa adiantada e depois cobrada do cliente'),
  ('Outras receitas',               'receivable', 'receita', 90, '#6b7280', true, null),

  -- ── CUSTO DIRETO (varia com a operação) ───────────────────────────────────
  ('Peças e materiais',             'payable', 'custo_direto', 110, '#3b82f6', true, 'Fornecedores de peças e insumos aplicados no serviço'),
  ('Serviços de terceiros',         'payable', 'custo_direto', 120, '#8b5cf6', true, 'Subcontratação e prestadores que executam serviço'),
  ('Frete e importação',            'payable', 'custo_direto', 130, '#0ea5e9', true, 'Transporte de peças, despacho e tributos de importação'),
  ('Combustível e deslocamento',    'payable', 'custo_direto', 140, '#f59e0b', true, 'Abastecimento e transporte para atendimento'),
  ('Alimentação de campo',          'payable', 'custo_direto', 150, '#a16207', true, 'Refeição da equipe em atendimento externo'),
  ('Pedágio e estacionamento',      'payable', 'custo_direto', 160, '#78716c', true, null),

  -- ── DESPESA OPERACIONAL (existe mesmo sem serviço) ────────────────────────
  ('Salários e encargos',           'payable', 'despesa_operacional', 210, '#ec4899', true, 'Folha, encargos e benefícios'),
  ('Pró-labore e retirada',         'payable', 'despesa_operacional', 220, '#db2777', true, 'Remuneração dos sócios'),
  ('Aluguel e condomínio',          'payable', 'despesa_operacional', 230, '#84cc16', true, null),
  ('Contabilidade e assessoria',    'payable', 'despesa_operacional', 240, '#14b8a6', true, 'Contador, advogado e consultorias'),
  ('Telefonia e internet',          'payable', 'despesa_operacional', 250, '#22d3ee', true, null),
  ('Software e assinaturas',        'payable', 'despesa_operacional', 260, '#818cf8', true, 'Sistemas, licenças e serviços recorrentes'),
  ('Ferramentas e equipamentos',    'payable', 'despesa_operacional', 270, '#8b5cf6', true, 'Compra e reposição de ferramental'),
  ('Manutenção de veículo',         'payable', 'despesa_operacional', 280, '#f97316', true, null),
  ('Material de escritório',        'payable', 'despesa_operacional', 290, '#94a3b8', true, null),
  ('Marketing e publicidade',       'payable', 'despesa_operacional', 300, '#f97316', true, null),
  ('Seguro',                        'payable', 'despesa_operacional', 310, '#06b6d4', true, null),
  ('Outras despesas',               'payable', 'despesa_operacional', 390, '#6b7280', true, null),

  -- ── FINANCEIRO E TRIBUTÁRIO ───────────────────────────────────────────────
  ('Impostos e taxas',              'payable', 'financeiro', 410, '#ef4444', true, 'DAS, DARF, ISS e demais tributos'),
  ('Tarifas bancárias',             'payable', 'financeiro', 420, '#64748b', true, null),
  ('Juros e encargos',              'payable', 'financeiro', 430, '#dc2626', true, 'Juros de financiamento, multa e mora'),

  -- ── NÃO OPERACIONAL — fica FORA do resultado ──────────────────────────────
  ('Transferência entre contas',    'payable', 'nao_operacional', 510, '#94a3b8', true, 'Dinheiro movido entre contas da própria empresa: não é despesa'),
  ('Pagamento de fatura de cartão', 'payable', 'nao_operacional', 520, '#94a3b8', true, 'A despesa está nos itens da fatura; lançar aqui de novo duplicaria'),
  ('Aplicação financeira',          'payable', 'nao_operacional', 530, '#94a3b8', true, 'Aplicação e resgate de investimento'),
  ('Empréstimo e financiamento',    'payable', 'nao_operacional', 540, '#94a3b8', true, 'Principal de empréstimo; os juros vão para Juros e encargos'),
  ('Transferência entre contas',    'receivable', 'nao_operacional', 550, '#94a3b8', true, 'Entrada vinda de outra conta da própria empresa'),
  ('Aporte de sócio',               'receivable', 'nao_operacional', 560, '#94a3b8', true, null)
ON CONFLICT (name, type) DO UPDATE SET
  dre_group = EXCLUDED.dre_group,
  sort_order = EXCLUDED.sort_order,
  color = EXCLUDED.color,
  description = EXCLUDED.description,
  active = true;
