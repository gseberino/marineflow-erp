-- Pagamento de fatura de cartão não é pedágio.
--
-- O gestor viu duas linhas na fila com histórico "DEBITO DE CARTAO" classificadas como
-- "Pedágio e estacionamento". A causa: a memória por nome aprendeu essa associação de
-- lançamentos antigos — provavelmente débitos automáticos de pedágio feitos no cartão, que
-- o banco também descreve assim. O nome "DEBITO DE CARTAO" não identifica nada; é rótulo
-- genérico do banco, e usá-lo como chave de aprendizado ensina o motor a errar.
--
-- POR QUE IMPORTA, SENDO SÓ R$ 35,60
-- Não é o valor: é o SINAL. Pagamento de fatura é `nao_operacional` — não entra no resultado,
-- porque a despesa já foi reconhecida na compra. Classificado como "Pedágio e estacionamento"
-- (custo_direto), ele vira custo pela segunda vez e infla o custo direto. São 145 linhas de
-- pagamento de fatura no extrato somando R$ 105 mil; bastaria a memória errada pegar mais
-- algumas para o DRE mentir de verdade.
--
-- Corrige o que já foi lançado E as propostas ainda pendentes, porque as duas superfícies
-- mostram o mesmo erro para o gestor.

-- 1. Lançamentos já feitos: 4 registros.
update public.payables p
set expense_category = 'Pagamento de fatura de cartão',
    updated_at = now()
from public.bank_transactions bt
where bt.id = p.bank_transaction_id
  and bt.source_type = 'bank'
  and bt.transaction_type = 'debit'
  and (bt.description ilike '%FAT%CARTAO%'
    or bt.description ilike '%FATURA%CART%'
    or bt.description ilike '%PGTO%CARTAO%'
    or bt.description = 'DEBITO DE CARTAO')
  and p.expense_category is distinct from 'Pagamento de fatura de cartão';

-- 2. Propostas pendentes: as que o gestor está vendo agora na fila do Extrato.
update public.finance_review_queue q
set suggested_category = 'Pagamento de fatura de cartão',
    dre_group = 'nao_operacional',
    reasoning = trim(both ' ·' from coalesce(q.reasoning, '')
      || ' · Histórico do banco identifica pagamento de fatura de cartão — a despesa já foi'
      || ' reconhecida na compra, então isto não entra no resultado'),
    updated_at = now()
from public.bank_transactions bt
where bt.id = q.bank_transaction_id
  and q.status = 'pending'
  and bt.source_type = 'bank'
  and bt.transaction_type = 'debit'
  and (bt.description ilike '%FAT%CARTAO%'
    or bt.description ilike '%FATURA%CART%'
    or bt.description ilike '%PGTO%CARTAO%'
    or bt.description = 'DEBITO DE CARTAO')
  and q.suggested_category is distinct from 'Pagamento de fatura de cartão';
