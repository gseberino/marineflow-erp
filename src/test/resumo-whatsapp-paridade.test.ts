// Guarda de paridade do resumo de valores (05/10/2026).
//
// O botão "Enviar via WhatsApp › Resumo" da tela usa `src/lib/quote-whatsapp-summary.ts`; o
// assistente (formato 'resumo' de send_service_order_link) usa o espelho em
// `_shared/pdf/resumo-whatsapp.ts`, porque Vite e Deno não compartilham módulos aqui. O cliente
// tem de ler o MESMO texto pelos dois caminhos — este teste roda os dois e falha se divergirem.
import { describe, it, expect } from 'vitest';
import { buildQuoteWhatsAppSummary as daTela, type ResumoDeOrcamentoInput } from '@/lib/quote-whatsapp-summary';
import { buildQuoteWhatsAppSummary as doAssistente } from '../../supabase/functions/_shared/pdf/resumo-whatsapp';

const empresa = { nome: 'HBR Marine', pixKey: '12.345.678/0001-90', bankName: 'C6 Bank', bankAgency: '0001', bankAccount: '123456-7' };

// ORÇ-00112 (Nelson) com o preset "100% Materiais na aprovação + Serviço na entrega".
const nelson: ResumoDeOrcamentoInput = {
  numero: 'ORÇ-00112',
  clienteNome: 'Nelson - S.I. 7.8',
  ativoNome: 'Santo Inácio 7.8',
  orcamento: { labor_cost_total: 3100, parts_cost_total: 8164.23, discount_amount: 764.23, grand_total: 10500 },
  parcelas: [
    { label: 'Sinal', tipo: 'aprovacao', parts_pct: 100, services_pct: 0, expenses_pct: 0 },
    { label: 'Serviços', tipo: 'entrega', parts_pct: 0, services_pct: 100, expenses_pct: 0 },
  ],
  condicaoLabel: '100% Materiais na aprovação + Serviço na entrega',
  validadeAte: '15/10/2026',
  empresa,
};

const casos: ResumoDeOrcamentoInput[] = [
  nelson,
  // Sem condição (cai no padrão do cálculo), validade em dias, com despesas e deslocamento.
  {
    numero: 'ORÇ-00090', clienteNome: 'Ana Paula', orcamento: {
      labor_cost_total: 1000, parts_cost_total: 500, operational_cost_total: 200, travel_cost_total: 300,
      is_travel_billable: true, discount_amount: 100, grand_total: 1900,
    }, parcelas: null, validadeDias: 7, empresa,
  },
  // Opções do documento escondendo preços de peças, banco e desconto.
  { ...nelson, opcoes: { showPartsPrices: false, showBankDetails: false, showDiscount: false } },
  // Financeiros ocultos: só o cumprimento.
  { ...nelson, opcoes: { hideFinancials: true } },
  // Sem sinal: tudo na entrega; sem PIX cadastrado.
  { ...nelson, parcelas: [{ label: 'Na entrega', tipo: 'entrega', services_pct: 100, parts_pct: 100 }], empresa: { nome: 'HBR Marine' } },
];

describe('resumo de valores: tela × assistente', () => {
  it('o texto é idêntico nos dois caminhos', () => {
    for (const c of casos) {
      expect(doAssistente(c as never)).toBe(daTela(c));
    }
  });

  it('o caso do Nelson sai com o sinal e o saldo que o dono combinou', () => {
    // A moeda sai com espaço não separável entre "R$" e o número.
    const texto = doAssistente(nelson as never).replace(/ /g, ' ');
    expect(texto).toContain('Sinal para iniciar: R$ 7.610,32');
    expect(texto).toContain('Serviços: R$ 2.889,68 — na entrega');
    expect(texto).toContain('Chave PIX: *12.345.678/0001-90*');
  });
});
