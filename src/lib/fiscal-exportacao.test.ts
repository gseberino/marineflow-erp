// Pacote da contadora (D33, 01/10/2026): o resumo CSV do livro de saída e o período.
import { describe, it, expect } from 'vitest';
import {
  CABECALHO_DO_LIVRO, linhaDoLivroDeSaida, resumoDoLivroDeSaida, nomeDoXml, periodoInicialDaExportacao, limitesDoPeriodo,
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

describe('linhaDoLivroDeSaida', () => {
  it('série, número, chave, data, valor da nota, destinatário saneado, situação e ambiente', () => {
    expect(linhaDoLivroDeSaida(venda)).toBe(
      '2;31;42260912345678000199550020000000311000000310;10/09/2026;499,50;MARINA  EXEMPLO LTDA;12345678000199;Autorizada;Producao',
    );
  });

  it('cancelada e homologação aparecem como tais', () => {
    const l = linhaDoLivroDeSaida({ ...venda, status: 'cancelled', environment: 'homologacao' });
    expect(l.endsWith(';Cancelada;Homologacao')).toBe(true);
  });

  it('documento do destinatário em qualquer formato do provedor (cpf_cnpj)', () => {
    const outra = { ...venda, request_payload: { ...venda.request_payload, recipient: { name: 'X', cpf_cnpj: '65725468020' } } };
    expect(linhaDoLivroDeSaida(outra).split(';')[6]).toBe('65725468020');
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
