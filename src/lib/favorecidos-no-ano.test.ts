import { describe, it, expect } from 'vitest';
import { somaDosFavorecidos, totaisPorFavorecido, type LancamentoDoFavorecido } from './favorecidos-no-ano';

const l = (payee_id: string | null, amount: number, status: string, expense_category: string | null, paid_amount?: number): LancamentoDoFavorecido =>
  ({ payee_id, amount, status, expense_category, paid_amount: paid_amount ?? (status === 'paid' ? amount : 0) });

describe('totaisPorFavorecido', () => {
  it('soma o pago por pessoa e separa por categoria, do maior para o menor', () => {
    const t = totaisPorFavorecido([
      l('gus', 3000, 'paid', 'Pró-labore'),
      l('gus', 3000, 'paid', 'Pró-labore'),
      l('gus', 1500.5, 'paid', 'Retirada de sócio'),
      l('gus', 80.1, 'paid', 'Reembolso'),
      l('rob', 150, 'paid', 'Serviços de terceiros'),
    ]);
    expect(t.get('gus')).toEqual({
      pago: 7580.6, aPagar: 0, pagamentos: 4,
      porCategoria: [
        { categoria: 'Pró-labore', valor: 6000 },
        { categoria: 'Retirada de sócio', valor: 1500.5 },
        { categoria: 'Reembolso', valor: 80.1 },
      ],
    });
    expect(t.get('rob')?.pago).toBe(150);
  });

  it('cancelado não conta, nem com valor pago gravado (há 31 assim no banco)', () => {
    const t = totaisPorFavorecido([l('gus', 500, 'cancelled', 'Pró-labore', 500), l('gus', 100, 'paid', 'Pró-labore')]);
    expect(t.get('gus')?.pago).toBe(100);
    expect(t.get('gus')?.pagamentos).toBe(1);
  });

  it('em aberto vai para "a pagar"; pago em parte divide, sem passar do valor', () => {
    const t = totaisPorFavorecido([
      l('rob', 800, 'pending', 'Salários e encargos'),
      l('rob', 300, 'partial', 'Salários e encargos', 100),
      l('rob', 50, 'pending', 'Salários e encargos', 999),
    ]);
    expect(t.get('rob')).toMatchObject({ pago: 150, aPagar: 1000, pagamentos: 2 });
  });

  it('sem favorecido, sem valor ou sem categoria: fica fora ou vai para "Sem categoria"', () => {
    const t = totaisPorFavorecido([l(null, 100, 'paid', 'X'), l('ana', 0, 'paid', 'X'), l('ana', 10, 'paid', '  ')]);
    expect([...t.keys()]).toEqual(['ana']);
    expect(t.get('ana')?.porCategoria).toEqual([{ categoria: 'Sem categoria', valor: 10 }]);
  });

  it('valor em texto (numeric do banco) soma em centavos, sem erro de arredondamento', () => {
    const linhas = Array.from({ length: 10 }, () => ({ payee_id: 'gus', amount: '0.10', paid_amount: '0.10', status: 'paid', expense_category: 'Pró-labore' }));
    expect(totaisPorFavorecido(linhas).get('gus')?.pago).toBe(1);
  });
});

describe('somaDosFavorecidos', () => {
  it('soma só os da aba em tela', () => {
    const t = totaisPorFavorecido([l('gus', 1000, 'paid', 'Pró-labore'), l('rob', 200.1, 'paid', 'X'), l('rob', 50, 'pending', 'X'), l('ana', 7, 'paid', 'X')]);
    expect(somaDosFavorecidos(['gus', 'rob', 'sem-lancamento'], t)).toEqual({ pago: 1200.1, aPagar: 50, pagamentos: 2 });
  });
});
