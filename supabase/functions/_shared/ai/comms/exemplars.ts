// Biblioteca de Exemplares (módulo B). Pesquisa: EXEMPLOS governam tom e formato melhor que
// instruções verbais. Pares "ruim → bom" dos tipos de mensagem mais frequentes, com o porquê.
// São a fonte da verdade (testável) e alimentam um bloco compacto injetado no prompt.

export type TipoMensagem = "cotacao" | "cobranca" | "follow_up_orcamento";

export interface Exemplar {
  tipo: TipoMensagem;
  titulo: string;
  ruim: string;
  bom: string;
  porque: string;
}

export const EXEMPLARES: Record<TipoMensagem, Exemplar> = {
  cotacao: {
    tipo: "cotacao",
    titulo: "Cotação a fornecedor",
    ruim: 'Olá ANDERSON DOS SANTOS ELETRONICA... Cotação para sistema LiFePO4 12V Victron. Prazo desejado: o mais breve. Pode responder com nº, preço e prazo? Ex.: "1 - R$ 850".',
    bom: "Olá, tudo bem? Aqui é da HBR Marine Solutions.\nGostaríamos de uma cotação (COT-00002):\n1. 8x Porta Fusível MIDI\n2. 1x Fusível 50A\n\nObrigado!",
    porque: "Saudação neutra (sem razão social), sem aplicação, sem prazo estipulado, sem ensinar a responder.",
  },
  cobranca: {
    tipo: "cobranca",
    titulo: "Cobrança a cliente",
    ruim: "Prezado, consta em aberto R$ 1.480,00 vencido em 03/07. Regularize o quanto antes para evitar transtornos.",
    bom: "Oi, João, tudo certo? Passando pra lembrar da OS do seu barco: R$ 1.480,00, que venceu dia 03/07. Consigo te mandar o Pix ou a gente parcela — o que fica melhor?",
    porque: "Empatia, nome usado, contexto ('do seu barco'), oferece OPÇÕES (não ultimato), um CTA.",
  },
  follow_up_orcamento: {
    tipo: "follow_up_orcamento",
    titulo: "Follow-up de orçamento",
    ruim: "Olá, passando para saber se você viu o orçamento. Aguardo retorno. (idêntico a cada toque)",
    bom: "João, sobre o ORÇ-00042: consigo garantir o preço da bateria até sexta, antes do reajuste do fornecedor. Faz sentido fechar essa parte agora?",
    porque: "Cada toque traz um VALOR/gancho novo (não repete o mesmo pedido); um CTA claro.",
  },
};

export function exemplarDe(tipo: TipoMensagem): Exemplar | null {
  return EXEMPLARES[tipo] || null;
}

/** Bloco compacto (few-shot) para o prompt estável. Curto de propósito — cacheável. */
export function exemplaresParaPrompt(): string {
  const linhas: string[] = [];
  for (const e of Object.values(EXEMPLARES)) {
    linhas.push(`• ${e.titulo} — RUIM: ${e.ruim.replace(/\n/g, " ")}`);
    linhas.push(`  BOM: ${e.bom.replace(/\n/g, " ")}`);
    linhas.push(`  (${e.porque})`);
  }
  return linhas.join("\n");
}
