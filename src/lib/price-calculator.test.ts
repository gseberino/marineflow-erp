// Cobertura do cálculo de preço de venda — módulo sem teste até agora.
//
// Por que ele importa mais do que o tamanho sugere: são 50 linhas que decidem por quanto a
// empresa vende. A fórmula é a do Simples Nacional, em que imposto e comissão saem DE DENTRO
// do preço (`custo / (1 - margem - imposto - comissão)`), não são somados por cima. Trocar
// essa divisão por uma multiplicação — o erro clássico — não quebra nada, não acusa em tela e
// devolve um preço plausível e menor do que deveria. Só apareceria no fim do mês.
//
// Os dois modos da tela (`PriceCalculator.tsx`) usam as duas funções em sequência: no modo
// "direto" o usuário digita o preço, o sistema volta a margem e recalcula a composição a
// partir dela. Se as duas não forem inversas exatas, o preço mostrado deixa de ser o digitado
// — por isso os testes de ida e volta no fim do arquivo.
import { describe, it, expect } from 'vitest';
import { calculateSalePrice, calculateMarginFromPrice } from './price-calculator';

describe('calculateSalePrice — imposto e comissão saem de dentro do preço', () => {
  it('caso de referência: custo 100, margem 30%, imposto 6%, comissão 4%', () => {
    // divisor = 1 - 0,30 - 0,06 - 0,04 = 0,60 → 100 / 0,60 = 166,67
    const bd = calculateSalePrice({ cost_price: 100, profit_margin: 30, tax_rate: 6, commission_rate: 4 });
    expect(bd.sale_price).toBe(166.67);
    expect(bd.tax_amount).toBe(10);          // 166,67 × 6%
    expect(bd.commission_amount).toBe(6.67); // 166,67 × 4%
    expect(bd.profit_amount).toBe(50);       // 166,67 × 30%
    expect(bd.markup).toBe(66.67);
  });

  it('NÃO soma imposto por cima do custo — o erro clássico daria 140', () => {
    // Se alguém trocasse a divisão por `custo × (1 + margem + imposto + comissão)`, o preço
    // viria 140 e a empresa venderia 26,67 abaixo do necessário para fechar a conta.
    const bd = calculateSalePrice({ cost_price: 100, profit_margin: 30, tax_rate: 6, commission_rate: 4 });
    expect(bd.sale_price).not.toBe(140);
    expect(bd.sale_price).toBeGreaterThan(140);
  });

  it('o preço cobre exatamente custo + imposto + comissão + lucro', () => {
    for (const caso of [
      { cost_price: 100, profit_margin: 30, tax_rate: 6, commission_rate: 4 },
      { cost_price: 2500, profit_margin: 45, tax_rate: 12, commission_rate: 0 },
      { cost_price: 37.9, profit_margin: 15, tax_rate: 6, commission_rate: 2.5 },
    ]) {
      const bd = calculateSalePrice(caso);
      const soma = bd.cost_price + bd.tax_amount + bd.commission_amount + bd.profit_amount;
      // tolerância de centavo: cada parcela é arredondada antes de somar
      expect(Math.abs(soma - bd.sale_price), `caso ${JSON.stringify(caso)}`).toBeLessThanOrEqual(0.02);
    }
  });

  it('o lucro é sempre a margem aplicada sobre o PREÇO, não sobre o custo', () => {
    // É o que a fórmula garante, e é a diferença que confunde na hora de conferir: 30% de
    // margem sobre custo 100 dá 50 de lucro, não 30.
    const bd = calculateSalePrice({ cost_price: 100, profit_margin: 30, tax_rate: 6, commission_rate: 4 });
    expect(bd.profit_amount).toBe(Math.round(bd.sale_price * 0.30 * 100) / 100);
  });

  it('sem imposto e sem comissão, o preço é custo dividido pelo complemento da margem', () => {
    const bd = calculateSalePrice({ cost_price: 200, profit_margin: 20, tax_rate: 0, commission_rate: 0 });
    expect(bd.sale_price).toBe(250); // 200 / 0,80
    expect(bd.tax_amount).toBe(0);
    expect(bd.commission_amount).toBe(0);
    expect(bd.profit_amount).toBe(50);
    expect(bd.markup).toBe(25);
  });

  it('margem zero devolve o próprio custo acrescido de imposto e comissão', () => {
    const bd = calculateSalePrice({ cost_price: 100, profit_margin: 0, tax_rate: 10, commission_rate: 0 });
    expect(bd.sale_price).toBe(111.11); // 100 / 0,90
    expect(bd.profit_amount).toBe(0);
  });

  it('soma acima de 100% devolve zeros em vez de preço negativo', () => {
    // A tela mostra um aviso nesse caso (`impossiblePrice` em PriceCalculator.tsx). O que
    // não pode acontecer é um preço negativo escapar para o orçamento.
    const caso = { cost_price: 100, profit_margin: 90, tax_rate: 20, commission_rate: 5 };
    const bd = calculateSalePrice(caso);
    expect(bd.sale_price).toBe(0);
    expect(bd.tax_amount).toBe(0);
    expect(bd.commission_amount).toBe(0);
    expect(bd.profit_amount).toBe(0);
    expect(bd.markup).toBe(0);
    // e devolve os componentes de entrada intactos, para a tela conseguir explicar o porquê
    expect(bd.profit_margin).toBe(caso.profit_margin);
    expect(bd.tax_rate).toBe(caso.tax_rate);
  });

  // ⚠️ NOVO-009 — DEFEITO CONHECIDO, registrado em audit/novos-achados.md e NÃO corrigido
  // aqui (regra 3: achado fora do escopo se registra, não se conserta de passagem).
  //
  // Quando margem + imposto + comissão dão EXATAMENTE 100%, o divisor deveria ser zero e cair
  // no guard. Em ponto flutuante binário ele às vezes cai do lado positivo — 60+30+10 dá
  // 2,7755575615628914e-17 — e o guard `divisor <= 0` não pega. O preço vira 3,6 × 10¹⁸.
  //
  // Não é teórico: `PriceCalculator.tsx` sincroniza o preço calculado para o formulário
  // sempre que `breakdown.sale_price > 0`, então esse número entra no campo de preço do
  // produto enquanto o aviso de "impossível" está na tela.
  //
  // O `.fails` é proposital: o dia em que alguém corrigir o guard, este caso passa a passar e
  // o Vitest acusa — obrigando a trocar por `it()` e apagar este comentário.
  it.fails('[NOVO-009] soma EXATAMENTE 100% deveria devolver zeros, e hoje devolve 3,6e18', () => {
    const bd = calculateSalePrice({ cost_price: 100, profit_margin: 60, tax_rate: 30, commission_rate: 10 });
    expect(bd.sale_price).toBe(0);
  });

  it('[NOVO-009] o defeito depende da combinação — algumas somas de 100% caem certo, outras não', () => {
    // Documenta o comportamento de HOJE. Mesma soma, resultados opostos: é o que torna o
    // defeito difícil de reproduzir a partir do relato de quem o encontrou.
    const escapa = calculateSalePrice({ cost_price: 100, profit_margin: 70, tax_rate: 20, commission_rate: 10 });
    const naoEscapa = calculateSalePrice({ cost_price: 100, profit_margin: 50, tax_rate: 30, commission_rate: 20 });
    expect(escapa.sale_price).toBeGreaterThan(1e17);
    expect(naoEscapa.sale_price).toBe(0);
  });

  it('custo zero não divide por zero no markup', () => {
    const bd = calculateSalePrice({ cost_price: 0, profit_margin: 30, tax_rate: 6, commission_rate: 4 });
    expect(bd.sale_price).toBe(0);
    expect(bd.markup).toBe(0);
    expect(Number.isFinite(bd.markup)).toBe(true);
  });

  it('tudo sai arredondado em centavos — nada de 166.66666666666669 no orçamento', () => {
    const bd = calculateSalePrice({ cost_price: 100, profit_margin: 30, tax_rate: 6, commission_rate: 4 });
    // Percorre só os campos NUMÉRICOS: `error` e `warning` (NOVO-009) são texto ou null, e a
    // intenção deste teste sempre foi dinheiro sem dízima — não o formato de uma mensagem.
    const numericos = Object.entries(bd).filter(([, v]) => typeof v === 'number');
    expect(numericos.length, 'o breakdown deveria ter campos numéricos').toBeGreaterThan(0);
    for (const [campo, valor] of numericos) {
      expect(Number.isFinite(valor as number), campo).toBe(true);
      expect(String(valor).split('.')[1]?.length ?? 0, `${campo} com mais de 2 casas`).toBeLessThanOrEqual(2);
    }
  });
});

describe('calculateMarginFromPrice — a volta, usada no modo "preço direto"', () => {
  it('devolve a margem que sobra depois de custo, imposto e comissão', () => {
    // preço 166,67 · custo 100 → 1 - 0,5999... - 0,06 - 0,04 ≈ 30%
    expect(calculateMarginFromPrice(100, 166.67, 6, 4)).toBe(30);
  });

  it('preço igual ao custo não deixa margem — e ainda fica negativa pelos tributos', () => {
    expect(calculateMarginFromPrice(100, 100, 6, 4)).toBe(-10);
  });

  it('preço abaixo do custo devolve margem negativa, não zero', () => {
    // Zerar aqui esconderia prejuízo: quem digitou 80 num custo de 100 precisa VER o -35.
    expect(calculateMarginFromPrice(100, 80, 6, 4)).toBeLessThan(0);
    expect(calculateMarginFromPrice(100, 80, 6, 4)).toBe(-35);
  });

  it('entrada inválida devolve 0 em vez de Infinity ou NaN', () => {
    expect(calculateMarginFromPrice(0, 150, 6, 4)).toBe(0);
    expect(calculateMarginFromPrice(100, 0, 6, 4)).toBe(0);
    expect(calculateMarginFromPrice(-100, 150, 6, 4)).toBe(0);
    expect(calculateMarginFromPrice(100, -50, 6, 4)).toBe(0);
  });
});

describe('ida e volta — o que a tela faz no modo "preço direto"', () => {
  // Fluxo real: o usuário digita o preço → o sistema calcula a margem → recalcula a
  // composição a partir dessa margem. Se as duas funções não forem inversas, o preço exibido
  // deixa de ser o digitado, e ninguém entende por quê.
  const casos = [
    { cost: 100, margem: 30, imposto: 6, comissao: 4 },
    { cost: 1500, margem: 22.5, imposto: 6, comissao: 0 },
    { cost: 89.9, margem: 40, imposto: 12, comissao: 5 },
    { cost: 12345.67, margem: 10, imposto: 6, comissao: 2 },
  ];

  it('preço → margem → preço volta ao mesmo lugar (até o centavo)', () => {
    for (const c of casos) {
      const ida = calculateSalePrice({ cost_price: c.cost, profit_margin: c.margem, tax_rate: c.imposto, commission_rate: c.comissao });
      const margemDeVolta = calculateMarginFromPrice(c.cost, ida.sale_price, c.imposto, c.comissao);
      const volta = calculateSalePrice({ cost_price: c.cost, profit_margin: margemDeVolta, tax_rate: c.imposto, commission_rate: c.comissao });
      expect(Math.abs(volta.sale_price - ida.sale_price), `caso ${JSON.stringify(c)}`).toBeLessThanOrEqual(0.05);
    }
  });

  it('a margem recuperada é a margem original (até 0,01 ponto percentual)', () => {
    for (const c of casos) {
      const ida = calculateSalePrice({ cost_price: c.cost, profit_margin: c.margem, tax_rate: c.imposto, commission_rate: c.comissao });
      const margemDeVolta = calculateMarginFromPrice(c.cost, ida.sale_price, c.imposto, c.comissao);
      expect(Math.abs(margemDeVolta - c.margem), `caso ${JSON.stringify(c)}`).toBeLessThanOrEqual(0.01);
    }
  });
});

// [NOVO-009] A borda dos 100%.
//
// Margem, imposto e comissão saem da RECEITA. Somados a 100% não sobra nada para pagar o
// custo; acima disso a conta vira negativa. O código devolvia `sale_price: 0` calado — e zero
// é um preço que PARECE válido: entra no campo, salva no produto e sai numa proposta.
describe('[NOVO-009] margem + imposto + comissão na borda de 100%', () => {
  const base = { cost_price: 100, tax_rate: 0, commission_rate: 0 };

  it('99% ainda calcula, mas AVISA que o preço ficou 100× o custo', () => {
    const r = calculateSalePrice({ ...base, profit_margin: 99 });
    expect(r.error).toBeNull();
    expect(r.sale_price).toBe(10000);
    expect(r.warning).toMatch(/100× o custo/);
    expect(r.warning).toMatch(/confira se era isso/);
  });

  it('100% devolve ERRO e preço zero — não é preço alto, é impossível', () => {
    const r = calculateSalePrice({ ...base, profit_margin: 100 });
    expect(r.sale_price).toBe(0);
    expect(r.error).toMatch(/somam 100%/);
    expect(r.error).toMatch(/ABAIXO de 100%/);
    expect(r.warning).toBeNull();
  });

  it('101% também é erro, e a mensagem diz a soma real', () => {
    const r = calculateSalePrice({ ...base, profit_margin: 101 });
    expect(r.sale_price).toBe(0);
    expect(r.error).toMatch(/somam 101%/);
  });

  it('a soma dos TRÊS é que importa, não cada um isolado', () => {
    // 40 + 30 + 30 = 100: nenhum é absurdo sozinho, e é assim que se cai nisso sem perceber.
    const r = calculateSalePrice({ cost_price: 100, profit_margin: 40, tax_rate: 30, commission_rate: 30 });
    expect(r.error).toMatch(/somam 100%/);
    expect(r.error).toMatch(/40%/);
    expect(r.error).toMatch(/30%/);
  });

  it('logo abaixo do corte de aviso não avisa — para o alerta não virar ruído', () => {
    // 95% → 20× o custo, exatamente no corte (e é o caso que expõe o ponto flutuante: a
    // divisão crua dá 19.999999999999982, então o multiplicador é arredondado antes de
    // comparar). 94% → 16,67×, abaixo do corte.
    expect(calculateSalePrice({ ...base, profit_margin: 95 }).warning).not.toBeNull();
    expect(calculateSalePrice({ ...base, profit_margin: 94 }).warning).toBeNull();
  });

  it('caso normal segue sem erro e sem aviso', () => {
    const r = calculateSalePrice({ cost_price: 100, profit_margin: 30, tax_rate: 6, commission_rate: 4 });
    expect(r.error).toBeNull();
    expect(r.warning).toBeNull();
    expect(r.sale_price).toBe(166.67);
  });

  it('entrada inválida devolve motivo, não NaN', () => {
    expect(calculateSalePrice({ ...base, profit_margin: NaN }).error).toMatch(/números/);
    expect(calculateSalePrice({ ...base, profit_margin: -10 }).error).toMatch(/negativos/);
    expect(calculateSalePrice({ ...base, cost_price: -1, profit_margin: 30 }).error).toMatch(/custo não pode/);
    // O que importa: nunca sai NaN no campo de preço.
    expect(calculateSalePrice({ ...base, profit_margin: NaN }).sale_price).toBe(0);
  });
});
