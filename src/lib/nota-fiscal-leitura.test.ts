// A lista de notas fiscais lia só o formato da NF-e. As cinco NFS-e da HBR apareciam com
// R$ 0,00 e sem tomador — conferido no banco em 23/09/2026. Os casos abaixo usam os
// payloads reais das duas famílias, porque o defeito nasceu de assumir um formato só.
import { describe, it, expect } from 'vitest';
import {
  tomadorDaNota, totalDaNota, itensDaNota, tipoDaNota, resumirNota,
} from './nota-fiscal-leitura';

/** NF-e 2/25 da Apolo: venda parcelada em 3x, dois itens. */
const NFE = {
  document_type: 'nfe',
  request_payload: {
    recipient: { name: 'APOLO INDUSTRIA E COMERCIO DE VEICULOS DE RECREACAO LTDA', cpf_cnpj: '17589800000192' },
    items: [{ description: 'Cabo' }, { description: 'Conector' }],
    payments: [{ amount: 15713.98 }],
  },
};

/** NFS-e 1/4: serviço com desconto — o desconto entra na descrição, não é um serviço. */
const NFSE = {
  document_type: 'nfse',
  request_payload: {
    taker: { name: 'LUCENIRA MARIA DE MELO', cpf_cnpj: '12345678900' },
    service: {
      description: 'Instalação 2x Carregador DC/DC 50A; Instalação Fogão de Indução; '
        + 'Instalação Sensor de Gás Bluetooth; Desconto comercial aplicado: R$ 68.17',
    },
    amounts: { net_amount: 2431.83, service_amount: 2500 },
  },
};

describe('leitura de nota fiscal', () => {
  it('acha o tomador nos dois formatos, que guardam o nome em chaves diferentes', () => {
    expect(tomadorDaNota(NFE).nome).toMatch(/^APOLO/);
    expect(tomadorDaNota(NFE).documento).toBe('17589800000192');
    expect(tomadorDaNota(NFSE).nome).toBe('LUCENIRA MARIA DE MELO');
  });

  it('NFS-e tem valor: era o zero que aparecia na lista', () => {
    // O defeito exato: `payments` não existe na NFS-e, e a lista lia só de lá.
    expect((NFSE.request_payload as Record<string, unknown>).payments).toBeUndefined();
    expect(totalDaNota(NFSE)).toBe(2431.83);
  });

  it('entre líquido e bruto, vale o líquido — é o que o tomador deve', () => {
    expect(totalDaNota(NFSE)).not.toBe(2500);
  });

  it('nota sem desconto cai no valor do serviço, que é o mesmo número', () => {
    const semDesconto = { document_type: 'nfse', request_payload: { amounts: { service_amount: 500 } } };
    expect(totalDaNota(semDesconto)).toBe(500);
  });

  it('conta os itens da NF-e e os serviços da NFS-e, sem contar o desconto', () => {
    expect(itensDaNota(NFE)).toBe(2);
    // Três serviços; a linha "Desconto comercial aplicado" é aviso, não serviço.
    expect(itensDaNota(NFSE)).toBe(3);
  });

  it('sem nada para contar, devolve null em vez de zero — a tela mostra travessão', () => {
    // Zero diria "nota sem itens", que é diferente de "não dá para saber".
    expect(itensDaNota({ document_type: 'nfse', request_payload: {} })).toBeNull();
    expect(itensDaNota({})).toBeNull();
  });

  it('distingue os três tipos que dividem a mesma lista', () => {
    expect(tipoDaNota(NFE)).toBe('NF-e');
    expect(tipoDaNota(NFSE)).toBe('NFS-e');
    expect(tipoDaNota({ document_type: 'nfce' })).toBe('NFC-e');
    expect(tipoDaNota({})).toBe('NF-e');
  });

  it('nota malformada não derruba a linha: a lista inteira sumia por uma nota torta', () => {
    for (const torta of [null, undefined, {}, { request_payload: null }, { request_payload: { recipient: null } }]) {
      expect(() => resumirNota(torta)).not.toThrow();
      expect(resumirNota(torta).total).toBe(0);
      expect(resumirNota(torta).tomador.nome).toBe('');
    }
  });
});
