// Motor de Registro (módulo A) — a MESMA competência, quatro vozes.
// Cada interlocutor tem um perfil de voz explícito: registro, teto de tamanho, como saudar,
// o que NUNCA incluir. As tools de envio consultam perfilDeVoz() e o linter usa as proibições.
// Fonte: matriz do plano (plans/marineflow-comunicacao-inteligente.md) + máximas de Grice.

export type Audiencia = "dono" | "cliente" | "fornecedor" | "tecnico";
export type Canal = "panel" | "whatsapp";
export type ModoSaudacao = "nome" | "neutra" | "informal";

export interface VoiceProfile {
  audiencia: Audiencia;
  canal: Canal;
  /** Descrição curta do registro (entra no prompt quando útil). */
  registro: string;
  /** Teto de linhas sugerido para a mensagem (0 = sem teto rígido). */
  tetoLinhas: number;
  /** Como saudar: pelo nome usado, saudação neutra, ou informal. */
  saudacao: ModoSaudacao;
  /** Fecho sugerido (vazio = sem fecho fixo). */
  fecho: string;
  /** Códigos de coisas que NUNCA devem aparecer (o linter cruza com isto). */
  proibicoes: ProibicaoCodigo[];
}

// Códigos de proibição compartilhados com o message-linter.
export type ProibicaoCodigo =
  | "razao_social" // saudar pela razão social (LTDA/EIRELI/ME...)
  | "aplicacao" // descrever "pra que serve" o material
  | "prazo_estipulado" // o remetente estipular prazo
  | "tutorial_resposta" // ensinar o outro a responder
  | "preco" // preço/custo/margem (técnico não vê)
  | "jargao_tecnico" // SKU/modelo cru para o cliente
  | "ameaca"; // ultimato/ameaça (cobrança)

const PERFIS: Record<Audiencia, Omit<VoiceProfile, "canal" | "tetoLinhas">> = {
  dono: {
    audiencia: "dono",
    registro: "Parceiro, direto, decisivo. Síntese primeiro, detalhe só se pedir. Aponta o próximo passo.",
    saudacao: "informal",
    fecho: "",
    proibicoes: [],
  },
  cliente: {
    audiencia: "cliente",
    registro: "Cordial, profissional, voz da marca HBR. Curto e claro. Oferece opções, nunca ameaça.",
    saudacao: "nome",
    fecho: "Qualquer dúvida, estou à disposição.",
    proibicoes: ["jargao_tecnico", "ameaca"],
  },
  fornecedor: {
    audiencia: "fornecedor",
    registro: "Neutro, transacional, enxuto. Saudação + itens. Quem dita preço/prazo/pagamento é ele.",
    saudacao: "neutra",
    fecho: "Obrigado!",
    proibicoes: ["razao_social", "aplicacao", "prazo_estipulado", "tutorial_resposta"],
  },
  tecnico: {
    audiencia: "tecnico",
    registro: "Operacional, curto, camarada. Qual OS, endereço, horário, o que registrar.",
    saudacao: "informal",
    fecho: "",
    proibicoes: ["preco"],
  },
};

// Teto de linhas por canal: WhatsApp é conversa curta; painel tolera mais.
function tetoLinhasDe(audiencia: Audiencia, canal: Canal): number {
  if (canal === "panel") return 0; // sem teto rígido no painel
  switch (audiencia) {
    case "tecnico": return 3;
    case "fornecedor": return 14; // saudação + lista de itens
    case "cliente": return 10;
    default: return 0;
  }
}

export function perfilDeVoz(audiencia: Audiencia, canal: Canal = "whatsapp"): VoiceProfile {
  const base = PERFIS[audiencia] || PERFIS.cliente;
  return { ...base, canal, tetoLinhas: tetoLinhasDe(base.audiencia, canal) };
}

/** Bloco compacto para injetar no prompt (só o perfil relevante — barato em tokens). */
export function perfilParaPrompt(p: VoiceProfile): string {
  const linhas = [`REGISTRO (${p.audiencia}/${p.canal}): ${p.registro}`];
  if (p.tetoLinhas) linhas.push(`Tamanho: até ~${p.tetoLinhas} linhas.`);
  if (p.proibicoes.length) linhas.push(`Nunca: ${p.proibicoes.join(", ")}.`);
  return linhas.join(" ");
}
