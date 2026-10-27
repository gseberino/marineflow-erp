import { describe, it, expect } from 'vitest';
import {
  COLUNAS_DO_CSV, ROTULO_REEMBOLSO, ROTULO_REEMBOLSOS, descricaoDoReembolso, documentoFormatado, linhasDoCsv, montarExtratoHtml,
  montarReciboHtml, nomeDoArquivo, textoDoPeriodo, valorPorExtenso,
  type ContaDoExtrato, type LinhaDoExtrato,
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

  it('a nota diz o que é o extra: o almoço (resposta 6 do dono), não "despesa reembolsada"', () => {
    expect(html).toContain('Extra = o almoço (quando ele traz o próprio) e outros acréscimos combinados do dia.');
    expect(html).not.toContain('Extras são despesas pagas pelo prestador e reembolsadas');
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

  it('Pix que o banco já trouxe e espera a fila: saiu de fato, sem a marca de "lançado à mão"', () => {
    const c = conta();
    c.linhas = [...c.linhas, { ...c.linhas[2], id: 'b1', aguardando: true, conta: 'No banco — falta aprovar na fila' }];
    const h = montarExtratoHtml({ empresa: { nome: 'HBR', cnpj: null, cidade: null },
      freelancer: { nome: 'Roberto', documento: null, pix: null }, conta: c, geradoEm: new Date() });
    expect(h).toContain('Pix (extrato do banco)');
    expect(h).not.toContain('Pix lançado à mão');
    expect(h).not.toContain('ainda não confirmado');
    expect(linhasDoCsv([{ conta: c, documento: null }]).filter((l) => l.tipo === 'Pagamento (falta aprovar na fila)')).toHaveLength(1);
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

// ── Reembolso do técnico (F2b dos comprovantes, 11/10/2026) ──────────────────────────────────
// A despesa da empresa que o prestador pagou do bolso, com comprovante, entra na conta corrente
// dele como crédito (linha `reembolso`, conta = código CMP) e vai para o próximo acerto/recibo.

const reembolso = (o: Partial<LinhaDoExtrato> = {}): LinhaDoExtrato => ({
  data: '2026-09-16', tipo: 'reembolso', id: 'rb1', jornada: null, fracao: null, valor_diaria: null, extras: null,
  descontos: null, trabalhado: 62, pago: 0, descricao: 'Reembolso CMP-00124 · AutoZone', conta: 'CMP-00124',
  categoria: 'Peças e materiais', observacao: null, os: [{ id: 'o1', numero: 'OS-0042' }], saldo: 312, aguardando: false, ...o,
});

/** A conta do Roberto com um reembolso de R$ 62,00 no dia 16/09 (saldo final = 230 + 62). */
const contaComReembolso = () => {
  const c = conta({ reembolsos: 62, saldo_final: 292 });
  c.linhas = [...c.linhas, reembolso()];
  return c;
};
const doc = {
  empresa: { nome: 'HBR Marine Solutions', cnpj: null, cidade: 'Itajaí/SC' },
  freelancer: { nome: 'Roberto Daniel', documento: null, pix: null },
};

describe('o rótulo do reembolso (resposta 9 do dono, 11/10/2026)', () => {
  it('um texto que qualquer leitor entende: pagas pelo técnico, nunca "por mim"', () => {
    expect(ROTULO_REEMBOLSOS).toBe('Reembolso de despesas pagas pelo técnico');
    expect(ROTULO_REEMBOLSO).toBe('Reembolso de despesa paga pelo técnico');
  });
});

describe('reembolso de comprovante no extrato em PDF', () => {
  const html = montarExtratoHtml({ ...doc, conta: contaComReembolso(), geradoEm: new Date(Date.UTC(2026, 8, 29, 17, 5)) });

  it('o total ganha a coluna do reembolso entre Trabalhado e Pago, com o rótulo inteiro', () => {
    expect(html).toContain(
      '<th class="n">Trabalhado</th><th class="n" style="white-space:normal">Reembolso de despesas pagas pelo técnico</th><th class="n">Pago</th>');
    expect(html).toMatch(/<td class="n">R\$ 260,00<\/td><td class="n">R\$ 62,00<\/td><td class="n">R\$ 100,00<\/td>/);
    expect(html).toMatch(/R\$ 292,00 \(a pagar ao prestador\)/);
  });

  it('seção própria com o código do comprovante, a descrição, a categoria, a OS e o valor; fora dos pagamentos', () => {
    expect(html).toContain('<h2>Reembolso de despesas pagas pelo técnico (comprovantes)</h2>');
    const secao = html.slice(html.indexOf('Reembolso de despesas pagas pelo técnico (comprovantes)'), html.indexOf('Pagamentos recebidos'));
    expect(secao).toContain('<th>Data</th><th>Comprovante</th><th>Descrição</th><th>OS</th><th class="n">Valor</th>');
    expect(secao).toContain('<td>CMP-00124</td>');
    // a descrição sem o "Reembolso CMP-00124 · " que o banco grava: o código já está na coluna ao lado
    expect(secao).toContain('<td>AutoZone · Peças e materiais</td>');
    expect(secao).not.toContain('Reembolso CMP-00124');
    expect(secao).toContain('OS-0042');
    expect(secao).toContain('1 reembolso(s)');
    expect(html.slice(html.indexOf('Pagamentos recebidos'))).not.toContain('CMP-00124');
    // reembolso e extra do dia não são a mesma coisa: a nota diz que a despesa não entra nos dois
    expect(html).toContain('Extra = o almoço (quando ele traz o próprio) e outros acréscimos combinados do dia. '
      + 'Reembolso de despesas pagas pelo técnico = despesa da empresa que ele pagou, com o comprovante (CMP) enviado pelo WhatsApp; '
      + 'a mesma despesa não entra também como extra.');
  });

  it('descricaoDoReembolso: tira o prefixo do banco (com e sem fornecedor); o resto fica', () => {
    expect(descricaoDoReembolso({ descricao: 'Reembolso CMP-00124 · AutoZone (compra de 08/10)' })).toBe('AutoZone (compra de 08/10)');
    expect(descricaoDoReembolso({ descricao: 'Reembolso CMP-00124' })).toBe('');
    expect(descricaoDoReembolso({ descricao: 'Almoço do dia' })).toBe('Almoço do dia');
    expect(descricaoDoReembolso({ descricao: null })).toBe('');
  });

  it('sem reembolso: nada de reembolso no papel, e "0" ou ausente dá o mesmo documento', () => {
    const geradoEm = new Date(Date.UTC(2026, 8, 29, 17, 5));
    const sem = montarExtratoHtml({ ...doc, conta: conta(), geradoEm });
    expect(sem).not.toMatch(/Reembols|reembolsos|CMP-/);
    expect(sem).toContain('<th class="n">Trabalhado</th><th class="n">Pago</th>');
    expect(montarExtratoHtml({ ...doc, conta: conta({ reembolsos: 0 }), geradoEm })).toBe(sem);
  });

  it('banco de antes da F2b (sem o total): soma as linhas', () => {
    const c = contaComReembolso();
    delete c.reembolsos;
    const h = montarExtratoHtml({ ...doc, conta: c, geradoEm: new Date() });
    expect(h).toMatch(/<td class="n">R\$ 62,00<\/td><td class="n">R\$ 100,00<\/td>/);
  });
});

describe('reembolso de comprovante no recibo do acerto', () => {
  const linhas = [
    ...conta().linhas, reembolso(),
    reembolso({ id: 'rb2', data: '2026-09-25', trabalhado: 30, conta: 'CMP-00130', descricao: 'Reembolso CMP-00130 · Posto' }),
  ];
  // 260 trabalhado + 92 de reembolsos − 100 de vales = 252 a pagar.
  const acerto = { numero: 8, de: '2026-09-16', ate: '2026-09-30', saldo_anterior: 0, dias: 1.5, trabalhado: 260, pago_no_periodo: 100,
    valor_do_acerto: 252, reembolsos: 92 };
  const recibo = montarReciboHtml({ ...doc, acerto, linhas, geradoEm: new Date(Date.UTC(2026, 9, 1, 15, 0)) });

  it('a conta do acerto soma o reembolso antes dos vales, com os códigos dos comprovantes', () => {
    const contaDoAcerto = recibo.slice(recibo.indexOf('<h2>Acerto</h2>'));
    expect(contaDoAcerto).toMatch(
      /Trabalhado no período[\s\S]*\(\+\) Reembolso de despesas pagas pelo técnico \(CMP-00124, CMP-00130\)<\/td><td class="n">R\$ 92,00[\s\S]*\(−\) Vales/);
  });

  it('a quitação cita o reembolso com o rótulo inequívoco e os códigos; a seção lista cada comprovante', () => {
    expect(recibo).toContain('e ao reembolso de despesas pagas pelo técnico (CMP-00124, CMP-00130): R$ 92,00, já descontados');
    // o texto que confundia (resposta 9 do dono) não volta
    expect(recibo).not.toMatch(/por mim|pelo prestador/);
    expect(recibo).toContain('(duzentos e cinquenta e dois reais)');
    const secao = recibo.slice(recibo.indexOf('<h2>Reembolso de despesas pagas pelo técnico</h2>'), recibo.indexOf('<h2>Acerto</h2>'));
    expect(secao).not.toBe('');
    expect(secao).toContain('CMP-00124');
    expect(secao).toContain('<td>CMP-00130</td><td>Posto</td>');
    expect(secao).not.toContain('Reembolso CMP-00130');
    expect(secao).toContain('R$ 30,00');
  });

  it('o total é o da foto do acerto, não a soma das linhas de hoje', () => {
    const h = montarReciboHtml({ ...doc, acerto: { ...acerto, reembolsos: 62 }, linhas, geradoEm: new Date() });
    expect(h).toContain('e ao reembolso de despesas pagas pelo técnico (CMP-00124, CMP-00130): R$ 62,00');
  });

  it('sem nenhum código de comprovante, nada de "()" vazio', () => {
    const semCodigo = linhas.map((l) => (l.tipo === 'reembolso' ? { ...l, conta: null } : l));
    const h = montarReciboHtml({ ...doc, acerto, linhas: semCodigo, geradoEm: new Date() });
    expect(h).toContain('e ao reembolso de despesas pagas pelo técnico: R$ 92,00');
    expect(h).toContain('(+) Reembolso de despesas pagas pelo técnico</td>');
    expect(h).not.toContain('()');
  });

  it('sem valor a receber, a declaração também diz o reembolso — já compensado neste acerto', () => {
    const h = montarReciboHtml({ ...doc, acerto: { ...acerto, valor_do_acerto: -8, pago_no_periodo: 360 }, linhas, geradoEm: new Date() });
    expect(h).toContain(
      'com o reembolso de despesas pagas pelo técnico (CMP-00124, CMP-00130): R$ 92,00, compensado neste acerto, e já recebi antecipadamente R$ 360,00');
    expect(h).not.toMatch(/por mim|paguei/);
    // a declaração assinada não pode dizer "a reembolsar" do que o próprio recibo já compensou
    expect(h).not.toContain('a reembolsar');
    expect(h).not.toContain('Recebi de');
  });

  it('sem reembolso o recibo não fala de reembolso; "0" ou ausente dá o mesmo recibo', () => {
    const base = { numero: 7, de: '2026-09-16', ate: '2026-09-30', saldo_anterior: 0, dias: 1.5, trabalhado: 260, pago_no_periodo: 100, valor_do_acerto: 160 };
    const geradoEm = new Date(Date.UTC(2026, 9, 1, 15, 0));
    const sem = montarReciboHtml({ ...doc, acerto: base, linhas: conta().linhas, geradoEm });
    expect(sem).not.toMatch(/Reembols|reembolsos|CMP-/);
    expect(montarReciboHtml({ ...doc, acerto: { ...base, reembolsos: 0 }, linhas: conta().linhas, geradoEm })).toBe(sem);
  });
});

describe('reembolso de comprovante no CSV do contador', () => {
  const linhas = linhasDoCsv([{ conta: contaComReembolso(), documento: '12345678940' }]);

  it('no mesmo dia: o dia, o reembolso, o pagamento; o Tipo do reembolso é o rótulo inequívoco', () => {
    expect(linhas.map((l) => `${l.data} ${l.tipo}`)).toEqual([
      '16/09/2026 Diária', '16/09/2026 Reembolso de despesa paga pelo técnico', '16/09/2026 Pagamento', '17/09/2026 Diária',
    ]);
  });

  it('o código vai em "Conta de origem", o valor na coluna Reembolso, a descrição e a OS como no extrato', () => {
    const r = linhas[1];
    expect(r).toMatchObject({ conta: 'CMP-00124', reembolso: '62,00', pago: '', trabalhado: '', observacao: 'Reembolso CMP-00124 · AutoZone',
      os: 'OS-0042', categoria: 'Peças e materiais', jornada: '', diarias: '' });
    expect(linhas.filter((l) => l !== r).every((l) => l.reembolso === '')).toBe(true);
  });

  it('a coluna nova é a última (a planilha da contadora não muda de lugar), com o rótulo inequívoco', () => {
    expect(COLUNAS_DO_CSV.at(-1)).toEqual({ header: 'Reembolso de despesa paga pelo técnico', key: 'reembolso' });
    expect(COLUNAS_DO_CSV.at(-2)).toEqual({ header: 'Observação / identificação', key: 'observacao' });
  });

  it('sem reembolso, as linhas da planilha não falam de reembolso', () => {
    const sem = linhasDoCsv([{ conta: conta(), documento: '12345678940' }]);
    expect(sem.every((l) => l.reembolso === '' && !/reembols/i.test(l.tipo))).toBe(true);
  });
});
