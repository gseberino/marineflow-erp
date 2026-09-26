import { describe, it, expect } from 'vitest';
import { montarDespesasPorCategoria, SEM_CATEGORIA } from './despesas-por-categoria';

const grupos = new Map([
  ['Combustível e deslocamento', 'despesa_operacional'],
  ['Peças e materiais', 'custo_direto'],
  ['Pagamento de fatura de cartão', 'nao_operacional'],
]);
const meses = ['2026-08', '2026-09'];

describe('montarDespesasPorCategoria', () => {
  it('soma por categoria e por mês, da maior para a menor', () => {
    const r = montarDespesasPorCategoria([
      { issue_date: '2026-08-02', amount: 100, expense_category: 'Combustível e deslocamento' },
      { issue_date: '2026-09-02', amount: 50.5, expense_category: 'Combustível e deslocamento' },
      { issue_date: '2026-09-10', amount: 400, expense_category: 'Peças e materiais' },
    ], grupos, meses);
    expect(r.categorias.map((c) => c.categoria)).toEqual(['Peças e materiais', 'Combustível e deslocamento']);
    expect(r.categorias[1]).toMatchObject({ porMes: [100, 50.5], total: 150.5, quantidade: 2, grupo: 'despesa_operacional' });
    expect(r.totalPorMes).toEqual([100, 450.5]);
    expect(r.total).toBe(550.5);
  });

  it('por padrão deixa fora o que não é despesa do resultado (fatura, transferência…)', () => {
    const linhas = [
      { issue_date: '2026-09-05', amount: 1560.81, expense_category: 'Pagamento de fatura de cartão' },
      { issue_date: '2026-09-05', amount: 10, expense_category: 'Combustível e deslocamento' },
    ];
    expect(montarDespesasPorCategoria(linhas, grupos, meses).total).toBe(10);
    // Com a opção ligada, entra.
    expect(montarDespesasPorCategoria(linhas, grupos, meses, true).total).toBe(1570.81);
  });

  it('despesa sem categoria aparece como "Sem categoria", sem grupo', () => {
    const r = montarDespesasPorCategoria([{ issue_date: '2026-09-01', amount: 7, expense_category: null }], grupos, meses);
    expect(r.categorias[0]).toMatchObject({ categoria: SEM_CATEGORIA, grupo: null, total: 7 });
  });

  it('ignora mês fora da janela', () => {
    const r = montarDespesasPorCategoria([{ issue_date: '2026-01-01', amount: 7, expense_category: 'X' }], grupos, meses);
    expect(r.categorias).toEqual([]);
    expect(r.totalPorMes).toEqual([0, 0]);
  });
});
