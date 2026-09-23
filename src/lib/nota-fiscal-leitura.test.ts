// A lista de notas mostrava valores que não eram os da nota. Três defeitos somados:
// lia `payments[0].amount` (que devolução não tem, e NFS-e nem possui), e datava a linha
// por `created_at` em vez da autorização.
//
// Os números abaixo NÃO foram inventados: saíram dos XMLs autorizados pela SEFAZ, baixados
// do storage em 23/09/2026. A tag `vNF` é a fonte da verdade — nota emitida não admite
// aproximação.
import { describe, it, expect } from 'vitest';
import {
  tomadorDaNota, totalDaNota, itensDaNota, tipoDaNota, resumirNota,
  dataDaNota, naturezaDaNota, ehDevolucao, textoBuscavelDaNota,
} from './nota-fiscal-leitura';

/**
 * NF-e 2/24 — DEVOLUÇÃO de compra, autorizada 28/07/2026.
 * XML: vProd 1699.25 · vDesc 50.98 · vIPIDevol 214.28 · **vNF 1862.55**
 * Na lista aparecia R$ 0,00, porque devolução não declara pagamento.
 */
const DEVOLUCAO = {
  document_type: 'nfe',
  status: 'authorized',
  authorized_at: '2026-07-28T20:06:00Z',
  created_at: '2026-07-28T20:06:30Z',
  request_payload: {
    purpose: 4,
    nature_operation: 'Devolução de compra',
    recipient: { name: 'FORNECEDOR EXEMPLO LTDA', cpf_cnpj: '12696968000183' },
    payments: [{ amount: 0 }],
    items: [{
      quantity: 1,
      unit_price: 1699.2474,
      discount: 50.98,
      returned_ipi: { value: 214.28 },
    }],
  },
};

/**
 * NF-e 2/29 — venda com 7 itens, autorizada 27/08/2026.
 * XML: vProd 18060.67 · vDesc 492.50 · **vNF 17568.17**
 */
const VENDA_7_ITENS = {
  document_type: 'nfe',
  status: 'authorized',
  authorized_at: '2026-08-27T22:56:00Z',
  created_at: '2026-08-27T22:56:10Z',
  request_payload: {
    purpose: 1,
    nature_operation: 'Venda de mercadoria',
    recipient: { name: 'APOLO INDUSTRIA E COMERCIO DE VEICULOS DE RECREACAO LTDA', cpf_cnpj: '17589800000192' },
    payments: [{ amount: 17568.17 }],
    items: [
      { quantity: 1, unit_price: 980.00, discount: 7.64 },
      { quantity: 1, unit_price: 350.00, discount: 26.72 },
      { quantity: 1, unit_price: 13500.00, discount: 368.24 },
      { quantity: 2, unit_price: 890.00, discount: 48.55 },
      { quantity: 1, unit_price: 620.67, discount: 16.93 },
      { quantity: 3, unit_price: 190.00, discount: 15.55 },
      { quantity: 1, unit_price: 260.00, discount: 8.87 },
    ],
  },
};

/** NFS-e 1/5 — XML: vLiq 500.00. Não tem `payments` nem `items`. */
const SERVICO = {
  document_type: 'nfse',
  status: 'authorized',
  authorized_at: null,
  created_at: '2026-09-16T19:31:47Z',
  request_payload: {
    taker: { name: 'SILVANA LAPPE BOMBARDELLI', document: '65725468020' },
    service: { description: 'Remoção de Camper Casa de Carroceria Veículo: Toyota Hilux' },
    amounts: { service_amount: 500 },
  },
};

describe('valor da nota — tem que bater com o DANFE, no centavo', () => {
  it('DEVOLUÇÃO: vale R$ 1.862,55 e a lista mostrava R$ 0,00', () => {
    // O defeito exato: o pagamento declarado é zero, porque devolução não é cobrança.
    expect(DEVOLUCAO.request_payload.payments[0].amount).toBe(0);
    // vNF do XML autorizado pela SEFAZ.
    expect(totalDaNota(DEVOLUCAO)).toBe(1862.55);
  });

  it('venda com 7 itens fecha no vNF do XML', () => {
    expect(totalDaNota(VENDA_7_ITENS)).toBe(17568.17);
  });

  it('o total é calculado da nota, não copiado do pagamento declarado', () => {
    // Se alguém declarar um pagamento errado, o valor da nota continua sendo o da nota.
    const comPagamentoErrado = {
      ...VENDA_7_ITENS,
      request_payload: { ...VENDA_7_ITENS.request_payload, payments: [{ amount: 99999 }] },
    };
    expect(totalDaNota(comPagamentoErrado)).toBe(17568.17);
  });

  it('NFS-e tem valor: não tem `payments` e aparecia zerada', () => {
    expect((SERVICO.request_payload as Record<string, unknown>).payments).toBeUndefined();
    expect(totalDaNota(SERVICO)).toBe(500);
  });

  it('entre líquido e bruto vale o líquido — é o que o tomador deve', () => {
    const comDesconto = {
      document_type: 'nfse',
      request_payload: { amounts: { net_amount: 2431.83, service_amount: 2500 } },
    };
    expect(totalDaNota(comDesconto)).toBe(2431.83);
  });

  it('preço com mais de duas casas não vira dízima na soma', () => {
    // unit_price vem com 4 casas do provedor; a linha é arredondada antes de somar,
    // que é o que o XML faz.
    const centavos = {
      document_type: 'nfe',
      request_payload: { items: [{ quantity: 3, unit_price: 0.335 }] },
    };
    expect(totalDaNota(centavos)).toBe(1.01);
  });
});

describe('data da nota', () => {
  it('vale o carimbo da SEFAZ, com o fuso que veio nele', () => {
    // provider_status.sefaz.authorized_at da NF-e 2/25, exatamente como o provedor devolveu.
    const nfe = {
      authorized_at: '2026-08-21T18:47:42Z',
      created_at: '2026-08-21T18:47:38Z',
      provider_status: { sefaz: { authorized_at: '2026-08-21T15:47:42-03:00' } },
    };
    expect(dataDaNota(nfe)).toBe('2026-08-21T15:47:42-03:00');
  });

  it('NFS-e emitida à noite não pula para o dia seguinte', () => {
    // Caso real da NFS-e 1/4: created_at em UTC é "2026-08-28T01:22", mas o XML diz
    // dCompet 2026-08-27. Sem isto a tela discordava do documento por um dia inteiro.
    const nfse = {
      document_type: 'nfse',
      authorized_at: null,
      created_at: '2026-08-28T01:22:27Z',
      provider_status: {
        latest_event: { status: 'authorized', created_at: '2026-08-27T22:22:27-03:00' },
      },
    };
    const data = dataDaNota(nfse)!;
    expect(data).toBe('2026-08-27T22:22:27-03:00');
    // O que importa de verdade: o DIA bate com o da nota.
    expect(new Date(data).toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' })).toBe('27/08/2026');
  });

  it('evento que não é de autorização não serve como data da nota', () => {
    const emFila = {
      created_at: '2026-08-27T03:02:00Z',
      provider_status: { latest_event: { status: 'processing', created_at: '2026-08-27T00:02:00-03:00' } },
    };
    expect(dataDaNota(emFila)).toBe('2026-08-27T03:02:00Z');
  });

  it('sem autorização sobra a data da tentativa, e ela é honesta', () => {
    const rejeitada = { status: 'rejected', authorized_at: null, created_at: '2026-08-27T03:02:00Z' };
    expect(dataDaNota(rejeitada)).toBe('2026-08-27T03:02:00Z');
  });

  it('cai para a coluna de autorização quando o provedor não respondeu nada', () => {
    expect(dataDaNota(VENDA_7_ITENS)).toBe('2026-08-27T22:56:00Z');
    expect(dataDaNota(SERVICO)).toBe('2026-09-16T19:31:47Z');
  });
});

describe('natureza da operação', () => {
  it('distingue venda de devolução — duas notas iguais podem ser opostas', () => {
    expect(naturezaDaNota(VENDA_7_ITENS)).toBe('Venda de mercadoria');
    expect(naturezaDaNota(DEVOLUCAO)).toBe('Devolução de compra');
    expect(ehDevolucao(DEVOLUCAO)).toBe(true);
    expect(ehDevolucao(VENDA_7_ITENS)).toBe(false);
  });

  it('NFS-e não declara natureza, mas tem uma', () => {
    expect(naturezaDaNota(SERVICO)).toBe('Prestação de serviço');
  });
});

describe('tomador, itens e tipo', () => {
  it('acha o tomador nos dois formatos, que usam chaves diferentes', () => {
    expect(tomadorDaNota(VENDA_7_ITENS).nome).toMatch(/^APOLO/);
    expect(tomadorDaNota(VENDA_7_ITENS).documento).toBe('17589800000192');
    // NFS-e guarda em `taker.document`, não em `recipient.cpf_cnpj`.
    expect(tomadorDaNota(SERVICO).nome).toBe('SILVANA LAPPE BOMBARDELLI');
    expect(tomadorDaNota(SERVICO).documento).toBe('65725468020');
  });

  it('conta itens da NF-e e serviços da NFS-e, sem contar o desconto', () => {
    expect(itensDaNota(VENDA_7_ITENS)).toBe(7);
    const tresServicos = {
      document_type: 'nfse',
      request_payload: { service: { description: 'A; B; C; Desconto comercial aplicado: R$ 68.17' } },
    };
    expect(itensDaNota(tresServicos)).toBe(3);
  });

  it('sem nada para contar devolve null — a tela mostra travessão, não zero', () => {
    expect(itensDaNota({ document_type: 'nfse', request_payload: {} })).toBeNull();
  });

  it('distingue os três tipos que dividem a mesma lista', () => {
    expect(tipoDaNota(VENDA_7_ITENS)).toBe('NF-e');
    expect(tipoDaNota(SERVICO)).toBe('NFS-e');
    expect(tipoDaNota({ document_type: 'nfce' })).toBe('NFC-e');
    expect(tipoDaNota({})).toBe('NF-e');
  });
});

describe('busca', () => {
  it('acha por tomador, por número, por natureza e pela chave de acesso', () => {
    const texto = textoBuscavelDaNota({ ...VENDA_7_ITENS, series: 2, number: 29, access_key: '42260850057049000159550020000000251661355724' });
    expect(texto).toContain('apolo');
    expect(texto).toContain('2/29');
    expect(texto).toContain('venda de mercadoria');
    expect(texto).toContain('4226085005704900015955');
  });

  it('acha o CNPJ digitado com pontuação ou sem', () => {
    const texto = textoBuscavelDaNota({ request_payload: { recipient: { name: 'X', cpf_cnpj: '17.589.800/0001-92' } } });
    expect(texto).toContain('17589800000192');
    expect(texto).toContain('17.589.800/0001-92');
  });
});

describe('robustez', () => {
  it('nota torta não derruba a lista inteira', () => {
    for (const torta of [null, undefined, {}, { request_payload: null }, { request_payload: { items: 'nao-e-array' } }]) {
      expect(() => resumirNota(torta)).not.toThrow();
      expect(resumirNota(torta).total).toBe(0);
      expect(resumirNota(torta).tomador.nome).toBe('');
    }
  });

  it('item com campo faltando conta como zero, não como NaN', () => {
    const incompleto = { document_type: 'nfe', request_payload: { items: [{ quantity: 2 }, { unit_price: 10 }] } };
    expect(totalDaNota(incompleto)).toBe(0);
  });
});
