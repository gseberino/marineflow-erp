// Pacote da contadora (D33, 01/10/2026): o resumo CSV do livro de saída e o período.
import { describe, it, expect } from 'vitest';
import {
  CABECALHO_DO_LIVRO, linhaDoLivroDeSaida, resumoDoLivroDeSaida, nomeDoXml, periodoInicialDaExportacao, limitesDoPeriodo,
  nfseDoPeriodo, janelaDaConsultaDeNfse, modeloDaNota,
} from './fiscal-exportacao';

const venda = {
  id: 'd1', document_type: 'nfe', series: 2, number: 31, status: 'authorized', environment: 'producao',
  access_key: '42260912345678000199550020000000311000000310',
  authorized_at: '2026-09-10T12:00:00-03:00',
  request_payload: {
    recipient: { name: 'MARINA; EXEMPLO\nLTDA', document: '12345678000199' },
    items: [{ quantity: 2, unit_price: 250, discount: 0.5 }],
  },
};

// NFS-e como está gravada em produção: sem authorized_at nem itens; a data é a do evento do
// provedor e o valor é o líquido de `amounts`; o tomador fica em `taker`.
const servico = {
  id: 's3', document_type: 'nfse', series: 1, number: 3, status: 'authorized', environment: 'producao',
  access_key: '42091052200000000000000000000000000000000000000003',
  authorized_at: null,
  created_at: new Date(2026, 8, 15, 10, 0).toISOString(),
  provider_status: { latest_event: { status: 'authorized', created_at: new Date(2026, 8, 15, 10, 0, 1).toISOString() } },
  request_payload: {
    taker: { name: 'CLIENTE DO SERVIÇO', document: '65725468020' },
    amounts: { service_amount: 1200, net_amount: 1150 },
    service: { description: 'Manutenção' },
  },
};

describe('linhaDoLivroDeSaida', () => {
  it('modelo, série, número, chave, data, valor da nota, destinatário saneado, situação e ambiente', () => {
    expect(linhaDoLivroDeSaida(venda)).toBe(
      'NF-e;2;31;42260912345678000199550020000000311000000310;10/09/2026;499,50;MARINA  EXEMPLO LTDA;12345678000199;Autorizada;Producao',
    );
  });

  it('cancelada e homologação aparecem como tais', () => {
    const l = linhaDoLivroDeSaida({ ...venda, status: 'cancelled', environment: 'homologacao' });
    expect(l.endsWith(';Cancelada;Homologacao')).toBe(true);
  });

  it('documento do destinatário em qualquer formato do provedor (cpf_cnpj)', () => {
    const outra = { ...venda, request_payload: { ...venda.request_payload, recipient: { name: 'X', cpf_cnpj: '65725468020' } } };
    expect(linhaDoLivroDeSaida(outra).split(';')[7]).toBe('65725468020');
  });

  it('NFS-e: marcada no modelo, com o tomador, o valor líquido e a data do evento do provedor', () => {
    const campos = linhaDoLivroDeSaida(servico).split(';');
    expect(campos[0]).toBe('NFS-e');
    expect(campos[4]).toBe('15/09/2026');
    expect(campos[5]).toBe('1150,00');
    expect(campos[6]).toBe('CLIENTE DO SERVIÇO');
    expect(campos[7]).toBe('65725468020');
  });
});

describe('modeloDaNota', () => {
  it('NFS-e só pelo document_type; o resto é NF-e', () => {
    expect(modeloDaNota(servico)).toBe('NFS-e');
    expect(modeloDaNota(venda)).toBe('NF-e');
    expect(modeloDaNota({})).toBe('NF-e');
  });
});

describe('NFS-e do período', () => {
  const { inicio, fim } = limitesDoPeriodo('2026-09-01', '2026-09-30');
  const emitidaEm = (d: Date) => ({
    ...servico, created_at: d.toISOString(),
    provider_status: { latest_event: { status: 'authorized', created_at: d.toISOString() } },
  });

  it('corta pela data da nota no dia local, inclusive na virada do mês', () => {
    const dentro = emitidaEm(new Date(2026, 8, 30, 23, 30));
    const depois = emitidaEm(new Date(2026, 9, 1, 0, 30));
    const antes = emitidaEm(new Date(2026, 7, 31, 23, 59));
    expect(nfseDoPeriodo([dentro, depois, antes], inicio, fim)).toEqual([dentro]);
  });

  it('cancelada: o último evento é o cancelamento, e a data que vale é a da criação', () => {
    const cancelada = {
      ...servico, status: 'cancelled', created_at: new Date(2026, 8, 20, 9, 0).toISOString(),
      provider_status: { latest_event: { status: 'cancelled', created_at: new Date(2026, 9, 2, 9, 0).toISOString() } },
    };
    expect(nfseDoPeriodo([cancelada], inicio, fim)).toEqual([cancelada]);
  });

  it('a consulta pelo created_at vai um dia além de cada ponta', () => {
    const janela = janelaDaConsultaDeNfse(inicio, fim);
    expect(new Date(inicio).getTime() - new Date(janela.inicio).getTime()).toBe(86_400_000);
    expect(new Date(janela.fim).getTime() - new Date(fim).getTime()).toBe(86_400_000);
  });
});

describe('resumoDoLivroDeSaida', () => {
  it('BOM, cabeçalho e uma linha por nota, com quebra do Windows', () => {
    const csv = resumoDoLivroDeSaida([venda, { ...venda, number: 32 }]);
    expect(csv.startsWith('﻿' + CABECALHO_DO_LIVRO + '\r\n')).toBe(true);
    expect(csv.split('\r\n')).toHaveLength(4); // cabeçalho + 2 linhas + final vazio
  });
});

describe('nomeDoXml', () => {
  it('número com 9 dígitos e a chave (sem chave, o id)', () => {
    expect(nomeDoXml(venda)).toBe('NFe-2-000000031-42260912345678000199550020000000311000000310.xml');
    expect(nomeDoXml({ ...venda, access_key: null })).toBe('NFe-2-000000031-d1.xml');
  });

  it('NFS-e com o próprio prefixo', () => {
    expect(nomeDoXml(servico)).toBe('NFSe-1-000000003-42091052200000000000000000000000000000000000000003.xml');
  });
});

describe('período', () => {
  it('abre do dia 1º do mês até hoje, no dia local', () => {
    expect(periodoInicialDaExportacao(new Date(2026, 9, 1, 23, 30))).toEqual({ de: '2026-10-01', ate: '2026-10-01' });
    expect(periodoInicialDaExportacao(new Date(2026, 8, 17, 9, 0))).toEqual({ de: '2026-09-01', ate: '2026-09-17' });
  });

  it('os limites cobrem o dia local inteiro', () => {
    const { inicio, fim } = limitesDoPeriodo('2026-09-01', '2026-09-30');
    expect(new Date(inicio).getTime()).toBe(new Date(2026, 8, 1, 0, 0, 0).getTime());
    expect(new Date(fim).getTime()).toBe(new Date(2026, 8, 30, 23, 59, 59, 999).getTime());
  });
});
