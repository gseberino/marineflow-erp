import { describe, it, expect } from 'vitest';
import {
  documentoFormatado, linhasDoCsv, montarExtratoHtml, montarReciboHtml, nomeDoArquivo, textoDoPeriodo, valorPorExtenso, type ContaDoExtrato,
} from './extrato-diarias';

const conta = (o: Partial<ContaDoExtrato> = {}): ContaDoExtrato => ({
  favorecido: { id: 'r', nome: 'Roberto Daniel', desde: '2026-08-25', saldo_inicial: 0, diaria: 160 },
  de: '2026-09-01', ate: '2026-09-30', saldo_anterior: 70, dias: 1.5, trabalhado: 260, pago: 100, saldo_final: 230,
  estado: 'deve',
  linhas: [
    { data: '2026-09-16', tipo: 'dia', id: 'd1', jornada: 'inteiro', fracao: 1, valor_diaria: 160, extras: 20, descontos: 0,
      trabalhado: 180, pago: 0, descricao: null, conta: null, categoria: null, observacao: 'Gerador do Marcelo',
      os: [{ id: 'o1', numero: 'OS-0042' }], saldo: 250 },
    { data: '2026-09-17', tipo: 'dia', id: 'd2', jornada: 'meio', fracao: 0.5, valor_diaria: 160, extras: 0, descontos: 0,
      trabalhado: 80, pago: 0, descricao: null, conta: null, categoria: null, observacao: null, os: [], saldo: 330 },
    { data: '2026-09-16', tipo: 'pagamento', id: 'p1', jornada: null, fracao: null, valor_diaria: null, extras: null,
      descontos: null, trabalhado: 0, pago: 100, descricao: 'Pix enviado para Roberto', conta: 'C6 - Conta PJ HBR',
      categoria: 'Diárias de freelancers', observacao: null, os: [], saldo: 230 },
  ],
  ...o,
});

describe('extrato de diárias em PDF', () => {
  const html = montarExtratoHtml({
    empresa: { nome: 'HBR Marine Solutions', cnpj: '50057049000159', cidade: 'Itajaí/SC' },
    freelancer: { nome: 'Roberto Daniel', documento: '12345678940', pix: 'roberto@pix' },
    conta: conta(),
    // 17:05 UTC = 14:05 em Brasília — o documento escreve a hora de Brasília também no servidor.
    geradoEm: new Date(Date.UTC(2026, 8, 29, 17, 5)),
  });

  it('traz o resumo, os dias com a OS, os pagamentos com a conta e o estado em palavras', () => {
    expect(html).toContain('Extrato de diárias');
    expect(html).toContain('01/09/2026 a 30/09/2026');
    expect(html).toContain('CPF 123.456.789-40');
    expect(html).toContain('CNPJ 50.057.049/0001-59');
    expect(html).toContain('OS-0042');
    expect(html).toContain('Gerador do Marcelo');
    expect(html).toContain('Meio período');
    expect(html).toContain('C6 - Conta PJ HBR');
    expect(html).toMatch(/R\$ 230,00 \(a pagar ao prestador\)/);
    expect(html).toContain('Saldo antes do período');
    expect(html).toContain('Gerado em 29/09/2026 às 14:05');
  });

  it('tem as duas linhas de assinatura: empresa e prestador, com o CPF', () => {
    const assinaturas = html.slice(html.indexOf('<div class="assinaturas">'));
    expect(assinaturas).toContain('HBR Marine Solutions');
    expect(assinaturas).toContain('Roberto Daniel<br>CPF 123.456.789-40');
  });

  it('não registra horário: é prestação por dia, não ponto', () => {
    expect(html).not.toMatch(/entrada|saída|expediente|ponto/i);
  });

  it('texto do cadastro não vira código na página', () => {
    const h = montarExtratoHtml({
      empresa: { nome: 'HBR', cnpj: null, cidade: null },
      freelancer: { nome: '<script>alert(1)</script>', documento: null, pix: null },
      conta: conta(), geradoEm: new Date(),
    });
    expect(h).not.toContain('<script>alert(1)</script>');
    expect(h).toContain('&lt;script&gt;');
  });

  it('período e nome do arquivo acompanham o que foi pedido', () => {
    expect(textoDoPeriodo(conta({ de: null, ate: null }))).toBe('desde 25/08/2026');
    expect(nomeDoArquivo('extrato-diarias', 'Roberto Daniel Corrêa', conta(), 'pdf')).toBe('extrato-diarias-roberto-daniel-correa-2026-09.pdf');
    expect(nomeDoArquivo('diarias', '', conta({ de: '2026-08-25', ate: null }), 'csv')).toBe('diarias-desde-2026-08-25.csv');
    expect(nomeDoArquivo('diarias', '', conta({ de: null, ate: null }), 'csv')).toBe('diarias-historico.csv');
  });

  it('Pix lançado à mão sai marcado: ainda não confirmado pelo banco', () => {
    const c = conta();
    c.linhas = [...c.linhas, { ...c.linhas[2], id: 'a1', aguardando: true, conta: 'Anotado — aguardando o banco' }];
    const h = montarExtratoHtml({ empresa: { nome: 'HBR', cnpj: null, cidade: null },
      freelancer: { nome: 'Roberto', documento: null, pix: null }, conta: c, geradoEm: new Date() });
    expect(h).toContain('Pix lançado à mão *');
    expect(h).toContain('ainda não confirmado pelo extrato do banco');
    expect(html).not.toContain('ainda não confirmado');
    expect(linhasDoCsv([{ conta: c, documento: null }]).filter((l) => l.tipo === 'Pagamento (aguardando o banco)')).toHaveLength(1);
  });
});

describe('CSV do contador', () => {
  const linhas = linhasDoCsv([{ conta: conta(), documento: '12345678940' }]);

  it('uma linha por dia e por pagamento, em ordem de data, dia antes do pagamento no mesmo dia', () => {
    expect(linhas.map((l) => `${l.data} ${l.tipo}`)).toEqual([
      '16/09/2026 Diária', '16/09/2026 Pagamento', '17/09/2026 Diária',
    ]);
  });

  it('valores com vírgula, meia diária como 0,5, e o pagamento com a conta de origem', () => {
    const [dia, pagamento, meio] = linhas;
    expect(dia).toMatchObject({ cpf: '123.456.789-40', jornada: 'Dia inteiro', diarias: '1', valor_diaria: '160,00',
      extras: '20,00', trabalhado: '180,00', pago: '', os: 'OS-0042', observacao: 'Gerador do Marcelo' });
    expect(meio).toMatchObject({ jornada: 'Meio período', diarias: '0,5', trabalhado: '80,00' });
    expect(pagamento).toMatchObject({ tipo: 'Pagamento', pago: '100,00', trabalhado: '', conta: 'C6 - Conta PJ HBR',
      categoria: 'Diárias de freelancers', observacao: 'Pix enviado para Roberto' });
  });

  it('documento de outro formato passa como veio', () => {
    expect(documentoFormatado('')).toBe('');
    expect(documentoFormatado('abc')).toBe('abc');
  });
});

describe('recibo do acerto', () => {
  it('valor por extenso em reais, com o "e" no lugar certo', () => {
    expect(valorPorExtenso(190)).toBe('cento e noventa reais');
    expect(valorPorExtenso(100)).toBe('cem reais');
    expect(valorPorExtenso(1)).toBe('um real');
    expect(valorPorExtenso(21.5)).toBe('vinte e um reais e cinquenta centavos');
    expect(valorPorExtenso(1250)).toBe('mil duzentos e cinquenta reais');
    expect(valorPorExtenso(1100)).toBe('mil e cem reais');
    expect(valorPorExtenso(2000)).toBe('dois mil reais');
    expect(valorPorExtenso(1_200_000)).toBe('um milhão e duzentos mil reais');
    expect(valorPorExtenso(2_000_000)).toBe('dois milhões de reais');
    expect(valorPorExtenso(0.01)).toBe('um centavo');
    expect(valorPorExtenso(0)).toBe('zero real');
  });

  const acerto = { numero: 7, de: '2026-09-16', ate: '2026-09-30', saldo_anterior: 0, dias: 1.5, trabalhado: 260, pago_no_periodo: 100, valor_do_acerto: 160 };
  const recibo = montarReciboHtml({
    empresa: { nome: 'HBR Marine Solutions', cnpj: '50057049000159', cidade: 'Itajaí/SC' },
    freelancer: { nome: 'Roberto Daniel', documento: '12345678940', pix: 'roberto@pix' },
    acerto, linhas: conta().linhas, geradoEm: new Date(Date.UTC(2026, 9, 1, 15, 0)),
  });

  it('número, competência, valor por extenso, vales descontados e a assinatura do prestador', () => {
    expect(recibo).toContain('RECIBO DE DIÁRIAS Nº 0007');
    expect(recibo).toContain('Competência: 16/09/2026 a 30/09/2026');
    expect(recibo).toContain('(cento e sessenta reais)');
    expect(recibo).toContain('Vales e adiantamentos já pagos no período');
    expect(recibo).toContain('Pix enviado para Roberto');
    expect(recibo).toContain('Itajaí/SC, 1 de outubro de 2026.');
    expect(recibo.slice(recibo.indexOf('class="assinatura"'))).toContain('Roberto Daniel, CPF 123.456.789-40');
    expect(recibo).toContain('Chave Pix do prestador: roberto@pix');
  });

  it('sem valor a receber, vira declaração (não "recebi")', () => {
    const h = montarReciboHtml({ empresa: { nome: 'HBR', cnpj: null, cidade: null }, freelancer: { nome: 'R', documento: null, pix: null },
      acerto: { ...acerto, valor_do_acerto: -40 }, linhas: [], geradoEm: new Date() });
    expect(h).toContain('Sem valor a receber');
    expect(h).toContain('um adiantamento de R$ 40,00 a compensar');
    expect(h).not.toContain('Recebi de');
  });
});
