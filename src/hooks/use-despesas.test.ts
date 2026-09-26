// Despesas: de onde saiu, quem classificou e o total por categoria.
import { describe, it, expect } from 'vitest';
import { paraDespesa, totaisPorCategoria } from './use-despesas';
import { intervaloDoPeriodo } from '@/components/DespesasPanel';

const grupos = new Map([['Alimentação de campo', 'custo_direto'], ['Pagamento de fatura de cartão', 'nao_operacional']]);
const base = {
  id: 'p1', description: 'Almoço', issue_date: '2026-09-25', amount: 100, status: 'paid',
  expense_category: 'Alimentação de campo', supplier_name: null, origin: 'bank_reconciliation',
};

describe('paraDespesa', () => {
  it('Caixa: de onde saiu e quem classificou', () => {
    const d = paraDespesa({ ...base, origin: 'manual', bank_transactions: { source_type: 'cash', description: 'Almoço meu e do Roberto', bank_connections: { label: 'Caixa (dinheiro)', provider: 'caixa' } } }, grupos);
    expect(d.deOnde).toBe('Caixa (dinheiro)');
    expect(d.quemClassificou).toBe('caixa');
    expect(d.grupo).toBe('custo_direto');
    expect(d.semNome).toBe(false);
  });

  it('lançado sozinho pela regra; compra no cartão sai do cartão', () => {
    const d = paraDespesa({ ...base, bank_transactions: { source_type: 'credit_card', description: 'POSTO X', counterparty_name: 'POSTO X', bank_connections: { label: 'C6', provider: 'pluggy' } },
      finance_review_queue: [{ automatica: 'regra', status: 'approved' }] }, grupos);
    expect(d.deOnde).toBe('Cartão de crédito');
    expect(d.quemClassificou).toBe('regra');
    expect(d.quem).toBe('POSTO X');
  });

  it('débito sem loja é marcado "sem quem recebeu"', () => {
    const d = paraDespesa({ ...base, supplier_name: 'DEBITO DE CARTAO', bank_transactions: { source_type: 'bank', description: 'DEBITO DE CARTAO', bank_connections: { label: 'C6', provider: 'pluggy' } },
      finance_review_queue: [{ automatica: null, status: 'approved' }] }, grupos);
    expect(d.semNome).toBe(true);
    expect(d.quemClassificou).toBe('voce');
  });
});

describe('sem quem recebeu', () => {
  it('só vale quando há linha do banco: lançamento à mão sem nome não é "o banco não informou"', () => {
    const d = paraDespesa({ ...base, supplier_name: null, description: 'INSTALADORA BERLIM' }, grupos);
    expect(d.semNome).toBe(false);
  });
});

describe('totaisPorCategoria', () => {
  it('soma e ordena do maior para o menor', () => {
    const ds = [
      paraDespesa({ ...base, id: 'a', amount: 50 }, grupos),
      paraDespesa({ ...base, id: 'b', amount: 70 }, grupos),
      paraDespesa({ ...base, id: 'c', amount: 900, expense_category: 'Pagamento de fatura de cartão' }, grupos),
    ];
    const t = totaisPorCategoria(ds);
    expect(t[0]).toMatchObject({ categoria: 'Pagamento de fatura de cartão', valor: 900, quantidade: 1 });
    expect(t[1]).toMatchObject({ categoria: 'Alimentação de campo', valor: 120, quantidade: 2 });
  });
});

describe('intervaloDoPeriodo', () => {
  it('meses em datas de Brasília', () => {
    const agora = new Date('2026-09-26T02:00:00Z'); // ainda 25/09 em Brasília
    expect(intervaloDoPeriodo('mes', agora)).toEqual(['2026-09-01', '2026-09-30']);
    expect(intervaloDoPeriodo('mes_passado', agora)).toEqual(['2026-08-01', '2026-08-31']);
    expect(intervaloDoPeriodo('tres_meses', agora)).toEqual(['2026-07-01', '2026-09-30']);
    expect(intervaloDoPeriodo('ano', agora)).toEqual(['2026-01-01', '2026-12-31']);
  });
});
