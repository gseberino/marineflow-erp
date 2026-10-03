// O que a correção diz e oferece para um lançamento ligado ao extrato (02/10/2026). Os casos são
// os quatro reais medidos no dia: ORÇ-00073 (+0,53), OS-00046 (R$ 20 em aberto), OS-00034 e
// OS-00041 (dois pagamentos).
import { describe, it, expect } from 'vitest';
import { diagnosticoDoVinculo, type PagamentoDoLancamento } from './vinculo-extrato';

const formatar = (v: number) => 'R$ ' + v.toFixed(2).replace('.', ',');
const formatarData = (d: string) => d.split('-').reverse().join('/');
const base = { formatar, formatarData, nasceuDoExtrato: false };
const pag = (id: string, valor: number, data = '2026-07-31'): PagamentoDoLancamento => ({ id, valor, data });

describe('diagnosticoDoVinculo', () => {
  it('banco maior (o sinal do ORÇ-00073): oferece ajustar para o valor do banco', () => {
    const d = diagnosticoDoVinculo({
      ...base, tipo: 'receivable', valor: 1865.47,
      linha: { data: '2026-07-30', descricao: 'RF SILVA', valor: 1866, pagamentoId: 'p1' },
      pagamentos: [pag('p1', 1865.47)],
    });
    expect(d.situacao).toBe('banco_maior');
    expect(d.diferenca).toBe(0.53);
    expect(d.texto).toBe('O banco mostra R$ 1866,00: o cliente pagou R$ 0,53 a mais que este lançamento.');
    expect(d.podeAjustar).toBe(true);
    expect(d.rotuloDoAjuste).toBe('Ajustar para R$ 1866,00');
  });

  it('banco menor (OS-00046): oferece o ajuste como desconto e avisa que o saldo pode ficar em aberto', () => {
    const d = diagnosticoDoVinculo({
      ...base, tipo: 'receivable', valor: 520,
      linha: { data: '2026-06-09', descricao: 'MP MOTORHOMES', valor: 500, pagamentoId: 'p1' },
      pagamentos: [pag('p1', 500)],
    });
    expect(d.situacao).toBe('banco_menor');
    expect(d.rotuloDoAjuste).toBe('Ajustar para R$ 500,00 (desconto de R$ 20,00)');
    expect(d.texto).toMatch(/não ajuste: o saldo fica em aberto/);
    expect(d.efeitoDoAjuste).toMatch(/deixam de ser cobrados \(desconto\)/);
  });

  it('dois pagamentos (OS-00034): lista os pagamentos e NÃO oferece ajuste', () => {
    const d = diagnosticoDoVinculo({
      ...base, tipo: 'receivable', valor: 29000,
      linha: { data: '2026-05-20', descricao: 'RITA', valor: 25000, pagamentoId: 'p1' },
      pagamentos: [pag('p1', 25000, '2026-05-20'), pag('p2', 4000, '2026-07-20')],
    });
    expect(d.situacao).toBe('varios_pagamentos');
    expect(d.podeAjustar).toBe(false);
    expect(d.texto).toContain('R$ 25000,00 em 20/05/2026 (por esta linha do banco)');
    expect(d.texto).toContain('R$ 4000,00 em 20/07/2026 (sem esta linha do banco)');
  });

  it('vínculo trocado (OS-00041): a linha aponta para um pagamento que não é o dela — sem ajuste', () => {
    const d = diagnosticoDoVinculo({
      ...base, tipo: 'receivable', valor: 8573.18,
      linha: { data: '2026-06-09', descricao: 'RITA', valor: 8000, pagamentoId: 'p2' },
      pagamentos: [pag('p1', 8000, '2026-06-09'), pag('p2', 573.18, '2026-07-20')],
    });
    expect(d.situacao).toBe('varios_pagamentos');
    expect(d.podeAjustar).toBe(false);
  });

  it('bate: nada a ajustar', () => {
    const d = diagnosticoDoVinculo({
      ...base, tipo: 'receivable', valor: 300,
      linha: { data: '2026-09-01', descricao: 'X', valor: 300, pagamentoId: 'p1' },
      pagamentos: [pag('p1', 300)],
    });
    expect(d.situacao).toBe('bate');
    expect(d.podeAjustar).toBe(false);
  });

  it('lançamento bate mas o pagamento não: ajusta só o pagamento', () => {
    const d = diagnosticoDoVinculo({
      ...base, tipo: 'receivable', valor: 1866,
      linha: { data: '2026-09-01', descricao: 'X', valor: 1866, pagamentoId: 'p1' },
      pagamentos: [pag('p1', 1865.47)],
    });
    expect(d.podeAjustar).toBe(true);
    expect(d.rotuloDoAjuste).toBe('Ajustar o pagamento para R$ 1866,00');
  });

  it('conta a pagar: explica e manda desfazer (sem ajuste automático)', () => {
    const d = diagnosticoDoVinculo({
      ...base, tipo: 'payable', valor: 100,
      linha: { data: '2026-09-01', descricao: 'X', valor: -110, pagamentoId: 'p1' },
      pagamentos: [pag('p1', 100)],
    });
    expect(d.situacao).toBe('conta_a_pagar');
    expect(d.podeAjustar).toBe(false);
    expect(d.texto).toMatch(/R\$ 10,00 a mais .* desfazer a aprovação/);
  });

  it('o que desfazer faz depende de como o lançamento nasceu', () => {
    const casado = diagnosticoDoVinculo({
      ...base, tipo: 'receivable', valor: 10, linha: { data: '2026-09-01', descricao: 'X', valor: 10, pagamentoId: 'p1' },
      pagamentos: [pag('p1', 10)],
    });
    const nasceu = diagnosticoDoVinculo({
      ...base, nasceuDoExtrato: true, tipo: 'receivable', valor: 10,
      linha: { data: '2026-09-01', descricao: 'X', valor: 10, pagamentoId: 'p1' }, pagamentos: [pag('p1', 10)],
    });
    expect(casado.efeitoDoDesfazer).toMatch(/mantém este lançamento/);
    expect(nasceu.efeitoDoDesfazer).toMatch(/cancela este lançamento/);
  });
});

describe('diagnosticoDoVinculo — um Pix para várias contas (forma A, F2, 02/10/2026)', () => {
  // O Pix de R$ 4.800 do Lenine: sinal do ORÇ-00074 (R$ 2.280) + sinal do ORÇ-00077 (R$ 2.520).
  const linha = { data: '2026-08-11', descricao: 'LENINE', valor: 4800, pagamentoId: 'pa' };

  it('a entrada pagou outra conta: diz qual e não oferece ajustar (contaria o dinheiro duas vezes)', () => {
    const d = diagnosticoDoVinculo({
      ...base, tipo: 'receivable', valor: 2280, linha, pagamentos: [pag('pa', 2280, '2026-08-11')],
      outrasContas: [{ descricao: 'Sinal — ORÇ-00077', valor: 2520 }], sobraDaEntrada: 0,
    });
    expect(d.situacao).toBe('varias_contas');
    expect(d.texto).toBe('Esta entrada de R$ 4800,00 pagou também Sinal — ORÇ-00077 (R$ 2520,00). Ela está toda aplicada.');
    expect(d.podeAjustar).toBe(false);
    expect(d.podeAplicarSobra).toBe(false);
    expect(d.efeitoDoDesfazer).toMatch(/a entrada continua pagando as outras contas/);
  });

  it('Pix maior que a conta, sem outra conta ainda: oferece aplicar a sobra e avisa acima de R$ 10', () => {
    const d = diagnosticoDoVinculo({
      ...base, tipo: 'receivable', valor: 2280, linha, pagamentos: [pag('pa', 2280, '2026-08-11')],
      sobraDaEntrada: 2520,
    });
    expect(d.situacao).toBe('banco_maior');
    expect(d.texto).toMatch(/Acima de R\$ 10, avalie/);
    expect(d.podeAplicarSobra).toBe(true);
    expect(d.rotuloDaSobra).toBe('Aplicar os R$ 2520,00 que sobraram em outra conta');
    expect(d.podeAjustar).toBe(true);
  });

  it('centavos a mais (ORÇ-00073) não falam em outra conta', () => {
    const d = diagnosticoDoVinculo({
      ...base, tipo: 'receivable', valor: 1865.47,
      linha: { data: '2026-07-30', descricao: 'RF SILVA', valor: 1866, pagamentoId: 'p1' },
      pagamentos: [pag('p1', 1865.47)], sobraDaEntrada: 0.53,
    });
    expect(d.texto).not.toMatch(/avalie/);
    expect(d.podeAplicarSobra).toBe(true);
  });
});
