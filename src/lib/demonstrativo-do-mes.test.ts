// O demonstrativo do mês em PDF. O que se protege: os números são os do DRE (a mesma conta), o
// não operacional fica fora do resultado e aparece à parte, a lista do "Mês pronto?" e o extrato
// saem como vieram, cada lançamento tem uma linha para conferir e texto do banco não vira HTML.
import { describe, expect, it } from 'vitest';
import {
  lancamentosPorGrupo, montarDemonstrativoHtml, nomeDoArquivoDoDemonstrativo, nomeDoMesPorExtenso,
  type LancamentoDoDemonstrativo,
} from './demonstrativo-do-mes';

const l = (x: Partial<LancamentoDoDemonstrativo>): LancamentoDoDemonstrativo => ({
  data: '2026-08-10', valor: 100, categoria: 'Outras despesas', grupo: 'despesa_operacional', tipo: 'despesa',
  descricao: 'Compra', quem: null, situacao: 'paid', ...x,
});

const LANCAMENTOS = [
  l({ tipo: 'receita', grupo: 'receita', categoria: 'Receita de serviços', valor: 10000, descricao: 'OS-00060', quem: 'Cliente A', situacao: 'received', data: '2026-08-05' }),
  l({ grupo: 'custo_direto', categoria: 'Peças e materiais', valor: 3000, descricao: 'Cabo 16mm', quem: 'Kamell' }),
  l({ grupo: 'despesa_operacional', categoria: 'Alimentação de campo', valor: 200, descricao: 'Almoço equipe' }),
  l({ grupo: 'despesa_operacional', categoria: 'Pró-labore', valor: 1062, descricao: 'Pix sócio' }),
  l({ grupo: 'financeiro', categoria: 'Juros e encargos', valor: 38, descricao: 'Juros de atraso' }),
  l({ grupo: 'nao_operacional', categoria: 'Retirada de sócio', valor: 3247.56, descricao: 'Pix sócio' }),
  l({ grupo: 'nao_operacional', categoria: 'Pagamento de fatura de cartão', valor: 1908, descricao: 'Fatura Nubank' }),
  l({ grupo: 'despesa_operacional', categoria: 'Gasto Pessoal Sócio - Descontar PL', valor: 559, descricao: 'FARMAVIDA <b>FARMACIA</b>' }),
];

function montar(extra: Partial<Parameters<typeof montarDemonstrativoHtml>[0]> = {}) {
  return montarDemonstrativoHtml({
    empresa: { nome: 'HBR Marine', cnpj: '12345678000190' },
    mes: '2026-08',
    lancamentos: LANCAMENTOS,
    extrato: { entrou: 12000, saiu: 9500.5, liquido: 2499.5, transferencias: { entrou: 500, saiu: 500 }, creditoDoCartao: { entrou: 30, saiu: 0 } },
    checklist: {
      pronto: false,
      itens: [
        { titulo: 'Saldos conferem com o banco', ok: true, bloqueia: true, detalhe: '3 contas conferidas' },
        { titulo: 'Nada esperando no Extrato', ok: false, bloqueia: true, detalhe: '2 linhas na fila' },
      ],
    },
    fechado: false,
    geradoEm: new Date('2026-09-30T12:00:00Z'),
    ...extra,
  });
}

describe('demonstrativo do mês', () => {
  it('título, empresa e situação do mês', () => {
    const html = montar();
    expect(nomeDoMesPorExtenso('2026-08')).toBe('agosto de 2026');
    expect(nomeDoArquivoDoDemonstrativo('2026-08')).toBe('demonstrativo-2026-08.pdf');
    expect(html).toContain('Demonstrativo de agosto de 2026');
    expect(html).toContain('CNPJ 12.345.678/0001-90');
    expect(html).toContain('Mês aberto: os números ainda podem mudar');
    expect(montar({ fechado: true })).toContain('Mês fechado');
  });

  it('resultado igual ao do DRE, com o não operacional fora e à parte', () => {
    const html = montar();
    // 10.000 − 3.000 − (200 + 1.062 + 559) − 38 = 5.141
    expect(html).toContain('= Resultado do período');
    expect(html).toMatch(/Resultado do mês<\/span><b>R\$\s5\.141,00/);
    expect(html).toMatch(/Fora do resultado \(não operacional\): R\$\s5\.155,56/);
  });

  it('quadro do sócio soma pró-labore, retirada e gasto pessoal', () => {
    const html = montar();
    expect(html).toContain('Sócio no mês');
    expect(html).toMatch(/Total pago ao sócio<\/td><td class="n">R\$\s4\.868,56/);
    const semSocio = montar({ lancamentos: LANCAMENTOS.filter((x) => !/sócio|Pró-labore|Gasto Pessoal/i.test(x.categoria ?? '')) });
    expect(semSocio).not.toContain('Sócio no mês');
  });

  it('lista do Mês pronto? e extrato como vieram; falta de dado é dita', () => {
    const html = montar();
    expect(html).toContain('O mês está pronto? — ainda não');
    expect(html).toContain('Nada esperando no Extrato</td><td class="b">Falta');
    expect(html).toMatch(/Entrou<\/td><td class="n">R\$\s12\.000,00/);
    const semDados = montar({ checklist: null, extrato: null });
    expect(semDados).toContain('não respondeu na hora de gerar');
  });

  it('cada lançamento vira uma linha para conferir, e texto do banco não vira HTML', () => {
    const html = montar();
    expect(html).toContain('Lançamentos do mês, para conferir linha a linha (8)');
    expect(html).toContain('FARMAVIDA &lt;b&gt;FARMACIA&lt;/b&gt;');
    expect(html).not.toContain('<b>FARMACIA</b>');
    expect((html.match(/class="caixa"/g) ?? []).length).toBe(8);
  });

  it('agrupa na ordem do resultado e ordena as categorias pelo total', () => {
    const grupos = lancamentosPorGrupo(LANCAMENTOS);
    expect(grupos.map((g) => g.grupo)).toEqual(['receita', 'custo_direto', 'despesa_operacional', 'financeiro', 'nao_operacional']);
    expect(grupos[2].categorias.map((c) => c.categoria)).toEqual(['Pró-labore', 'Gasto Pessoal Sócio - Descontar PL', 'Alimentação de campo']);
  });
});

describe('demonstrativo cabe na folha', () => {
  it('tabelas com largura fixa por coluna e quebra dentro da célula (as colunas saíam cortadas em 30/09)', () => {
    const html = montar();
    expect(html).toContain('table-layout: fixed');
    expect(html).toContain('overflow-wrap: anywhere');
    expect(html).toContain('<table class="lancs"><colgroup>');
  });
});
