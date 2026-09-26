// O orçamento escrito no corpo da mensagem.
//
// Os três casos abaixo são orçamentos REAIS da HBR, com os números do banco — porque o que
// esta mensagem promete ao cliente é dinheiro, e um exemplo inventado não prova que o sinal
// e o saldo fecham com o total.
import { describe, it, expect } from 'vitest';
import { buildQuoteWhatsAppSummary } from './quote-whatsapp-summary';

/**
 * O formatador pt-BR separa "R$" do número com espaço NÃO SEPARÁVEL (U+00A0), que é
 * invisível e não casa com o espaço digitado nas asserções. Normalizar aqui mantém os
 * testes legíveis — o alvo é o conteúdo, não o caractere de espaço.
 */
const texto = (t: string) => t.replace(/\u00a0/g, ' ');

const EMPRESA = {
  nome: 'HBR Marine Solutions',
  pixKey: '50057049000159',
  bankName: 'Banco 336 - C6 Bank S.A.',
  bankAgency: '0001',
  bankAccount: '25625409-5',
};

/** ORÇ-00082 (ROBSON): 50% da mão de obra + 100% dos materiais antecipados. */
const ROBSON = {
  numero: 'ORÇ-00082',
  clienteNome: 'ROBSON',
  ativoNome: 'MH - Volvo FH540',
  orcamento: {
    labor_cost_total: 750, parts_cost_total: 1696.45, grand_total: 2446.45,
  },
  parcelas: [
    { label: 'Sinal', services_pct: 50, parts_pct: 100, expenses_pct: 100, days_after_approval: 0, tipo: 'aprovacao' as const },
    { label: 'Saldo', services_pct: 50, parts_pct: 0, expenses_pct: 0, days_after_approval: 0, tipo: 'entrega' as const },
  ],
  condicaoLabel: '50% mão de obra + 100% materiais antecipados',
  validadeDias: 15,
  empresa: EMPRESA,
};

/** OS-00104 (Flávio): serviço técnico, 75% de sinal e 25% na entrega. */
const FLAVIO = {
  numero: 'OS-00104',
  clienteNome: 'Flávio da Igreja',
  ativoNome: 'Itapoã',
  orcamento: { labor_cost_total: 2760, parts_cost_total: 0, grand_total: 2760 },
  parcelas: [
    { label: 'Sinal', services_pct: 75, parts_pct: 0, expenses_pct: 0, days_after_approval: 0, tipo: 'aprovacao' as const },
    { label: 'Saldo', services_pct: 25, parts_pct: 0, expenses_pct: 0, days_after_approval: 0, tipo: 'entrega' as const },
  ],
  condicaoLabel: 'Serviço técnico - 75% sinal / 25% na entrega',
  empresa: EMPRESA,
};

/** OS-00094 (Jose): à vista, com desconto — não há saldo a explicar. */
const JOSE = {
  numero: 'OS-00094',
  clienteNome: 'Jose - Renault Master Homebus',
  orcamento: {
    labor_cost_total: 730, parts_cost_total: 477.02, discount_amount: 127.02, grand_total: 1080,
  },
  parcelas: [
    { label: 'À vista', services_pct: 100, parts_pct: 100, expenses_pct: 100, days_after_approval: 0, tipo: 'aprovacao' as const },
  ],
  condicaoLabel: 'À vista',
  empresa: EMPRESA,
};

describe('resumo do orçamento para WhatsApp', () => {
  it('sinal e saldo fecham exatamente com o total', () => {
    // 750×50% + 1.696,45×100% = 2.071,45 de sinal; 750×50% = 375,00 de saldo.
    const t = buildQuoteWhatsAppSummary(ROBSON);
    expect(texto(t)).toContain('Total: R$ 2.446,45');
    expect(texto(t)).toContain('Sinal para iniciar: R$ 2.071,45');
    expect(texto(t)).toContain('Saldo: R$ 375,00');
    // A soma tem de bater: um cliente que confere e acha diferença perde a confiança.
    expect(2071.45 + 375).toBeCloseTo(2446.45, 2);
  });

  it('explica DE ONDE vem o sinal, que é a pergunta seguinte de todo cliente', () => {
    expect(texto(buildQuoteWhatsAppSummary(ROBSON))).toContain('100% dos materiais + 50% da mão de obra');
    expect(texto(buildQuoteWhatsAppSummary(FLAVIO))).toContain('75% da mão de obra');
  });

  it('diz quando o saldo vence, sem o cliente ter de perguntar', () => {
    expect(texto(buildQuoteWhatsAppSummary(ROBSON))).toContain('— na entrega');
  });

  it('à vista não inventa um saldo que não existe', () => {
    const t = buildQuoteWhatsAppSummary(JOSE);
    expect(texto(t)).toContain('Sinal para iniciar: R$ 1.080,00');
    expect(texto(t)).not.toContain('🔹');
    // O desconto aparece: é argumento de venda, e escondê-lo faz o total parecer errado.
    expect(texto(t)).toContain('Desconto: −R$ 127,02');
  });

  it('traz a chave PIX e o favorecido — é o que falta para o cliente pagar', () => {
    const t = buildQuoteWhatsAppSummary(ROBSON);
    expect(texto(t)).toContain('Chave PIX: *50057049000159*');
    expect(texto(t)).toContain('C6 Bank');
    expect(texto(t)).toContain('Ag 0001 · Conta 25625409-5');
    expect(texto(t)).toContain('Favorecido: HBR Marine Solutions');
  });

  it('diz o que acontece depois do pagamento', () => {
    // Sem isso o cliente paga e fica sem saber se alguém viu.
    expect(texto(buildQuoteWhatsAppSummary(ROBSON))).toContain('confirmamos e agendamos');
  });

  it('o que o gestor esconde do PDF não vaza pela mensagem', () => {
    const semPecas = buildQuoteWhatsAppSummary({ ...ROBSON, opcoes: { showPartsPrices: false } });
    expect(texto(semPecas)).not.toContain('1.696,45');
    // Mas o total e o sinal continuam — são o objeto da conversa.
    expect(texto(semPecas)).toContain('Total: R$ 2.446,45');

    const semBanco = buildQuoteWhatsAppSummary({ ...ROBSON, opcoes: { showBankDetails: false } });
    expect(texto(semBanco)).not.toContain('25625409-5');
    expect(texto(semBanco)).toContain('Chave PIX');
  });

  it('nunca manda link nem anexo: este modo é só para os valores', () => {
    // Pedido do dono (24/09/2026). Quem quiser o documento usa os outros dois modos de
    // envio, que continuam disponíveis ao lado.
    const t = texto(buildQuoteWhatsAppSummary(ROBSON));
    expect(t).not.toContain('http');
    expect(t).not.toContain('📎');
  });

  it('com valores ocultos não improvisa números nem sobra mensagem vazia', () => {
    const t = texto(buildQuoteWhatsAppSummary({ ...ROBSON, opcoes: { hideFinancials: true } }));
    expect(t).not.toContain('2.446,45');
    expect(t).not.toContain('http');
    // Sobra uma frase com sentido -- e o diálogo nem oferece este modo nesse caso.
    expect(t).toContain('envio os valores em seguida');
  });

  it('deslocamento não cobrável não entra na conta do cliente', () => {
    const t = buildQuoteWhatsAppSummary({
      ...ROBSON,
      orcamento: { ...ROBSON.orcamento, travel_cost_total: 300, is_travel_billable: false },
    });
    expect(texto(t)).not.toContain('Deslocamento');
  });

  it('usa o primeiro nome: é uma conversa, não um ofício', () => {
    expect(texto(buildQuoteWhatsAppSummary(FLAVIO))).toContain('Olá, Flávio!');
  });

  it('orçamento sem condição de pagamento ainda informa o total', () => {
    const t = buildQuoteWhatsAppSummary({ ...ROBSON, parcelas: null, condicaoLabel: null });
    expect(texto(t)).toContain('Total: R$ 2.446,45');
    expect(texto(t)).not.toContain('Sinal para iniciar');
  });
});

// A validade do texto é a MESMA do PDF do envio (26/09/2026): com data fixa, o PDF diz
// "Válido até …" — e o texto dizia "válida por 7 dias", contradizendo o anexo.
describe('validade no texto', () => {
  it('data fixa vence os dias, igual ao PDF', () => {
    const txt = buildQuoteWhatsAppSummary({ ...ROBSON, validadeDias: 7, validadeAte: '10/10/2026' });
    expect(txt).toContain('Proposta válida até 10/10/2026.');
    expect(txt).not.toContain('válida por 7');
  });
  it('sem data fixa, os dias — no singular quando é um', () => {
    expect(buildQuoteWhatsAppSummary({ ...ROBSON, validadeDias: 7, validadeAte: null })).toContain('Proposta válida por 7 dias.');
    expect(buildQuoteWhatsAppSummary({ ...ROBSON, validadeDias: 1 })).toContain('Proposta válida por 1 dia.');
  });
});
