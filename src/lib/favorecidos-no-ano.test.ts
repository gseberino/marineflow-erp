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
      peloDocumento: [],
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

  it('Pix dividido em pró-labore + retirada (28/09/2026) é UM pagamento: as partes somam por categoria', () => {
    const t = totaisPorFavorecido([
      l('gus', 1621, 'paid', 'Pró-labore'),
      { ...l('gus', 2379, 'paid', 'Retirada de sócio'), parte_de_divisao: true },
      l('gus', 500, 'paid', 'Retirada de sócio'),
    ]);
    expect(t.get('gus')).toMatchObject({
      pago: 4500, pagamentos: 2,
      porCategoria: [{ categoria: 'Retirada de sócio', valor: 2879 }, { categoria: 'Pró-labore', valor: 1621 }],
    });
  });
});

describe('pelo mesmo CPF/CNPJ, sem o favorecido ligado (documento igual identifica)', () => {
  const favorecidos = [
    { id: 'gus', document: '12345678901' },
    { id: 'mic', document: '98765432100' },
    { id: 'ana', document: null },
  ];
  const semLigar = (amount: number, extra: Partial<LancamentoDoFavorecido>): LancamentoDoFavorecido =>
    ({ payee_id: null, amount, paid_amount: amount, status: 'paid', expense_category: 'Pró-labore', ...extra });

  it('o pró-labore lançado no cadastro de FORNECEDOR com o CPF do sócio é do sócio (o caso real de 2026)', () => {
    const t = totaisPorFavorecido([
      l('gus', 1000, 'paid', 'Pró-labore'),
      semLigar(500, { documento_do_fornecedor: '123.456.789-01', nome_do_fornecedor: 'GUSTAVO SEBERINO' }),
      semLigar(500, { documento_do_fornecedor: '123.456.789-01', nome_do_fornecedor: 'GUSTAVO SEBERINO' }),
      semLigar(200, { documento_da_linha: '12345678901' }),
    ], favorecidos);
    expect(t.get('gus')).toMatchObject({
      pago: 2200, pagamentos: 4,
      peloDocumento: [
        { lancadoEm: 'GUSTAVO SEBERINO', lancamentos: 2, valor: 1000 },
        { lancadoEm: 'sem cadastro ligado', lancamentos: 1, valor: 200 },
      ],
    });
  });

  it('a linha do banco (para onde o dinheiro foi) vence o fornecedor ligado: acha lançamento no cadastro errado', () => {
    // 2 pagamentos ao CPF do Mickael lançados no fornecedor "VIA S.A." (CNPJ de outra empresa).
    const t = totaisPorFavorecido([
      semLigar(500, { documento_da_linha: '98765432100', documento_do_fornecedor: '33.041.260/0652-90', nome_do_fornecedor: 'VIA S.A.', expense_category: 'Salários e encargos' }),
    ], favorecidos);
    expect(t.get('mic')?.peloDocumento).toEqual([{ lancadoEm: 'VIA S.A.', lancamentos: 1, valor: 500 }]);
  });

  it('ligado a um favorecido conta só para ele, sem contar de novo pelo documento', () => {
    const t = totaisPorFavorecido([l('ana', 300, 'paid', 'Serviços de terceiros')].map((x) => ({ ...x, documento_da_linha: '12345678901' })), favorecidos);
    expect(t.get('ana')?.pago).toBe(300);
    expect(t.has('gus')).toBe(false);
  });

  it('documento de dois favorecidos é dúvida e não soma; documento sem dono não soma', () => {
    const repetido = [...favorecidos, { id: 'gus2', document: '123.456.789-01' }];
    const t = totaisPorFavorecido([semLigar(500, { documento_da_linha: '12345678901' }), semLigar(90, { documento_da_linha: '11122233344' })], repetido);
    expect(t.size).toBe(0);
  });

  it('linha do banco com o documento de OUTRA pessoa: o dinheiro foi para ela, não para o favorecido do fornecedor', () => {
    const t = totaisPorFavorecido([
      semLigar(400, { documento_da_linha: '55566677788', documento_do_fornecedor: '123.456.789-01', nome_do_fornecedor: 'GUSTAVO SEBERINO' }),
    ], favorecidos);
    expect(t.has('gus')).toBe(false);
  });

  it('"Inclui N lançamentos" soma só o pago, como o "Recebeu"', () => {
    const t = totaisPorFavorecido([
      semLigar(500, { documento_da_linha: '12345678901' }),
      { ...semLigar(300, { documento_da_linha: '12345678901' }), status: 'pending', paid_amount: 0 },
    ], favorecidos);
    expect(t.get('gus')).toMatchObject({ pago: 500, aPagar: 300, peloDocumento: [{ lancadoEm: 'sem cadastro ligado', lancamentos: 1, valor: 500 }] });
  });

  it('CPF que perdeu o zero à esquerda (planilha) ainda é o mesmo', () => {
    const t = totaisPorFavorecido([semLigar(70, { documento_da_linha: '1234567890' })], [{ id: 'z', document: '01234567890' }]);
    expect(t.get('z')?.pago).toBe(70);
  });
});

describe('somaDosFavorecidos', () => {
  it('soma só os da aba em tela', () => {
    const t = totaisPorFavorecido([l('gus', 1000, 'paid', 'Pró-labore'), l('rob', 200.1, 'paid', 'X'), l('rob', 50, 'pending', 'X'), l('ana', 7, 'paid', 'X')]);
    expect(somaDosFavorecidos(['gus', 'rob', 'sem-lancamento'], t)).toEqual({ pago: 1200.1, aPagar: 50, pagamentos: 2 });
  });
});
