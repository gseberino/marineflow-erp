// O "Favorecido" dos dados de pagamento é o TITULAR da conta (26/11/2026).
//
// O dono trocou o nome da empresa para "HBR Marine & RV Systems", mas a conta continua no nome
// registrado no CNPJ. O "Favorecido" saía do nome da empresa: o cliente leria um nome no
// documento e outro no app do banco na hora do PIX, o que parece golpe. Agora sai de
// app_settings.bank_holder; vazio, continua o nome da empresa (como era).
import { afterEach, describe, expect, it, vi } from 'vitest';
import { buildHTMLDocument, DEFAULT_PDF_OPTIONS, type PDFData } from './pdf-generator';
import { buildQuoteWhatsAppSummary as daTela, type ResumoDeOrcamentoInput } from './quote-whatsapp-summary';
import { buildQuoteWhatsAppSummary as doAssistente } from '../../supabase/functions/_shared/pdf/resumo-whatsapp';
import { AGORA, ORCAMENTO, OS_COM_PAGAMENTO } from '../../supabase/functions/_shared/pdf/amostras';

const NOME = 'HBR Marine & RV Systems';
const TITULAR = 'HBR MARINE SOLUTIONS LTDA';

afterEach(() => vi.useRealTimers());

function html(base: PDFData, tipo: PDFData['documentType'], holder?: string): string {
  vi.useFakeTimers();
  vi.setSystemTime(new Date(AGORA));
  const dados = {
    ...base,
    documentType: tipo,
    company: { ...base.company, name: NOME },
    bank: { ...base.bank, holder },
  } as PDFData;
  return buildHTMLDocument(dados, { ...DEFAULT_PDF_OPTIONS });
}

describe('Favorecido nos documentos', () => {
  const casos: Array<[string, PDFData, PDFData['documentType']]> = [
    ['orçamento', ORCAMENTO, 'quote'],
    ['OS', OS_COM_PAGAMENTO, 'service_order'],
    ['fatura', OS_COM_PAGAMENTO, 'invoice'],
  ];

  for (const [rotulo, base, tipo] of casos) {
    it(`${rotulo}: com titular, o Favorecido é o titular, não o nome da empresa`, () => {
      const h = html(base, tipo, TITULAR);
      expect(h).toContain(`Favorecido: ${TITULAR}`);
      expect(h).not.toContain(`Favorecido: ${NOME.replace('&', '&amp;')}`);
    });

    it(`${rotulo}: sem titular, continua o nome da empresa (como era)`, () => {
      const h = html(base, tipo, undefined);
      expect(h).toContain(`Favorecido: ${NOME.replace('&', '&amp;')}`);
    });
  }
});

describe('Favorecido no resumo do WhatsApp (tela e assistente)', () => {
  const base: ResumoDeOrcamentoInput = {
    numero: 'ORÇ-00999',
    clienteNome: 'Cliente Teste',
    orcamento: { labor_cost_total: 1000, parts_cost_total: 500, grand_total: 1500 },
    parcelas: null,
    empresa: { nome: NOME, pixKey: '50057049000159', bankName: 'C6 Bank', bankAgency: '0001', bankAccount: '123456-7' },
  } as ResumoDeOrcamentoInput;

  it('com titular: os dois caminhos mostram o titular, e o mesmo texto', () => {
    const entrada = { ...base, empresa: { ...base.empresa, titular: TITULAR } };
    const tela = daTela(entrada);
    expect(tela).toContain(`_Favorecido: ${TITULAR}_`);
    // O nome da empresa continua no título da mensagem.
    expect(tela).toContain(`— ${NOME}`);
    expect(doAssistente(entrada)).toBe(tela);
  });

  it('sem titular (ou só espaços): o Favorecido é o nome da empresa, nos dois caminhos', () => {
    for (const titular of [undefined, null, '   ']) {
      const entrada = { ...base, empresa: { ...base.empresa, titular } };
      const tela = daTela(entrada);
      expect(tela).toContain(`_Favorecido: ${NOME}_`);
      expect(doAssistente(entrada)).toBe(tela);
    }
  });
});
