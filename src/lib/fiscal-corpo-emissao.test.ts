// O corpo da emissão (o conteúdo da nota que a tela manda ao fiscal-emit). D33, passo 3.
import { describe, it, expect } from 'vitest';
import { montarCorpoDaEmissao, type EstadoDaEmissao } from './fiscal-corpo-emissao';
import { buildEmissionItem } from './fiscal-emission-item';
import { SIMPLES_INFO_NOTE, SIMPLES_INFO_NOTE_BASE } from './nfe-info-complementar';
import { montarParcelas } from './fiscal-parcelas';

const item = {
  productId: 'p1', code: 'BAT-100', name: 'Bateria 100Ah', ncm: '85072010', cfop: '5102', unit: 'UN',
  quantity: 2, unit_price: 1000, discount: 50, csosn: '102', origin: 0,
  icms_rate: 0, pis_rate: 0, cofins_rate: 0, ipi_rate: 0,
};

const base: EstadoDaEmissao = {
  clientId: 'c1',
  natureOfOperation: 'venda',
  selectedNature: { hasPayment: true },
  paymentMethod: '01',
  payMode: 'avista',
  payN: 3,
  payFirstDue: '',
  payInterval: 30,
  total: 1950,
  presenceIndicator: 1,
  consumerFinal: true,
  purchaseOrder: '',
  buyerName: '',
  devolucaoInfo: '',
  additionalInfo: '',
  isReturn: false,
  referencedAccessKey: '',
  recipientName: 'MARINA EXEMPLO LTDA',
  recipientDocument: '12345678000199',
  recipientEmail: '',
  recipientIeIndicator: 9,
  recipientIe: '',
  address: {
    postal_code: '88000000', address_line_1: 'Rua do Porto', address_number: '10', address_complement: '',
    neighborhood: 'Centro', city: 'Florianópolis', state: 'SC',
  },
  activeItems: [item],
};

describe('montarCorpoDaEmissao — pagamento', () => {
  it('à vista: o método escolhido, sem parcelas', () => {
    const c = montarCorpoDaEmissao(base);
    expect(c.payment_method).toBe('01');
    expect(c.payment_terms).toEqual({ mode: 'avista', method: '01', installments: null });
  });

  it('parcelado: duplicata mercantil (14) e as parcelas sobre o total líquido, qualquer que seja o seletor', () => {
    const c = montarCorpoDaEmissao({ ...base, payMode: 'parcelado', payFirstDue: '2026-10-15', paymentMethod: '01' });
    expect(c.payment_method).toBe('14');
    expect(c.payment_terms).toEqual({
      mode: 'parcelado', method: '14', installments: montarParcelas(1950, 3, '2026-10-15', 30, '14'),
    });
  });

  it('parcelado sem a data da 1ª parcela continua à vista', () => {
    const c = montarCorpoDaEmissao({ ...base, payMode: 'parcelado', payFirstDue: '' });
    expect(c.payment_method).toBe('01');
    expect(c.payment_terms).toEqual({ mode: 'avista', method: '01', installments: null });
  });

  it('natureza sem pagamento (devolução, remessa): sem plano', () => {
    const c = montarCorpoDaEmissao({ ...base, selectedNature: { hasPayment: false }, payMode: 'parcelado', payFirstDue: '2026-10-15' });
    expect(c.payment_terms).toBeNull();
    expect(c.payment_method).toBe('01');
  });
});

describe('montarCorpoDaEmissao — destinatário e referência', () => {
  it('inscrição estadual só vai com contribuinte (indicador 1)', () => {
    expect(montarCorpoDaEmissao({ ...base, recipientIeIndicator: 1, recipientIe: '123456789' }).recipient.state_registration).toBe('123456789');
    expect(montarCorpoDaEmissao({ ...base, recipientIeIndicator: 9, recipientIe: '123456789' }).recipient.state_registration).toBeUndefined();
  });

  it('endereço no formato da emissão; vazio vira ausente', () => {
    const c = montarCorpoDaEmissao(base);
    expect(c.recipient.address).toEqual({
      street: 'Rua do Porto', number: '10', complement: undefined, district: 'Centro',
      city_name: 'Florianópolis', state_code: 'SC', postal_code: '88000000',
    });
    expect(c.recipient.email).toBeUndefined();
    expect(c.client_id).toBe('c1');
    expect(montarCorpoDaEmissao({ ...base, clientId: '' }).client_id).toBeNull();
  });

  it('chave referenciada só quando a natureza exige', () => {
    const chave = '42260912345678000199550020000000241000000245';
    expect(montarCorpoDaEmissao({ ...base, referencedAccessKey: chave }).referenced_access_key).toBeUndefined();
    expect(montarCorpoDaEmissao({ ...base, selectedNature: { hasPayment: false, requiresReference: true }, referencedAccessKey: chave })
      .referenced_access_key).toBe(chave);
  });
});

describe('montarCorpoDaEmissao — informações adicionais', () => {
  it('pedido e comprador primeiro, devolução antes do texto livre, declaração do Simples por último', () => {
    const c = montarCorpoDaEmissao({
      ...base, purchaseOrder: ' 4512 ', buyerName: 'Ana',
      devolucaoInfo: 'Devolução da NF 123', additionalInfo: 'Entregar no píer 3',
    });
    const info = c.additional_info!;
    expect(info.startsWith('Pedido de Compra: 4512 - Comprador: Ana')).toBe(true);
    expect(info.indexOf('Devolução da NF 123')).toBeLessThan(info.indexOf('Entregar no píer 3'));
    expect(info.endsWith(SIMPLES_INFO_NOTE)).toBe(true);
    expect(c.customer_po_number).toBe('4512');
    expect(c.customer_buyer_name).toBe('Ana');
  });

  it('devolução usa a declaração do Simples sem a frase de crédito', () => {
    const info = montarCorpoDaEmissao({ ...base, isReturn: true }).additional_info!;
    expect(info.endsWith(SIMPLES_INFO_NOTE_BASE)).toBe(true);
  });

  it('pedido e comprador vazios não viram coluna', () => {
    const c = montarCorpoDaEmissao({ ...base, purchaseOrder: '  ', buyerName: '' });
    expect(c.customer_po_number).toBeUndefined();
    expect(c.customer_buyer_name).toBeUndefined();
  });
});

describe('montarCorpoDaEmissao — itens', () => {
  it('cada item incluído pelo mapeamento testado', () => {
    const outro = { ...item, code: 'CAB-6', quantity: 10, unit_price: 12.5, discount: 0 };
    const c = montarCorpoDaEmissao({ ...base, activeItems: [item, outro] });
    expect(c.items).toEqual([buildEmissionItem(item), buildEmissionItem(outro)]);
  });
});
