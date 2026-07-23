// Manejo de Resposta — inbound (módulo G). "Metade da conversa é a resposta que volta."
// Classifica a resposta de cliente/fornecedor para decidir o manejo: de-escalar cobrança em
// disputa, aceitar cotação parcial, responder/escalar pergunta, honrar opt-out.
// Função PURA e testável — dá um sinal determinístico ao agente (que também lê o texto).

export type IntencaoResposta =
  | "opt_out" // "pare de me mandar"
  | "disputa" // "já paguei", "serviço deu problema", cobrança indevida
  | "acordo" // "pode mandar o pix", "vou pagar", "fechado"
  | "cotacao_parcial" // fornecedor: "só tenho o item 1 e 3"
  | "pergunta" // "qual a bitola?", "vocês têm em estoque?"
  | "outro";

export interface ResultadoResposta {
  intencao: IntencaoResposta;
  manejo: string; // o que o agente deve fazer
  sinais: string[]; // trechos que dispararam
}

function norm(s: string): string {
  return String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

// Ordem de precedência (do mais sensível ao menos): opt_out > disputa > acordo > parcial > pergunta.
const REGRAS: Array<{ intencao: IntencaoResposta; re: RegExp; manejo: string }> = [
  {
    intencao: "opt_out",
    re: /\b(para|pare|parar) de (me )?(mandar|enviar)|nao (quero|desejo) (mais )?(receber|mensagens)|nao me mand|descadastr|sair da lista|remover meu (numero|contato)|nunca mais|me tira/,
    manejo: "Marque opt_out_whatsapp=true no cliente/fornecedor (update_client/update_supplier) e NÃO envie mais. Confirme educadamente.",
  },
  {
    intencao: "disputa",
    re: /ja paguei|nao devo|nao reconhe|cobranca indevida|nao concordo|servico (deu problema|nao ficou|incompleto|com defeito|nao foi)|reclama|\berrad[oa]\b|cobranca errada/,
    manejo: "NÃO reenvie cobrança. De-escale e ESCALE ao dono com o contexto (o cliente contesta). Não insista.",
  },
  {
    intencao: "acordo",
    re: /pode (mandar|enviar|passar) (o )?pix|manda o pix|vou pagar|combinado|fechado|fecho|topo|pode fazer|aceito|tá certo|ta certo|de acordo|ok pode/,
    manejo: "Cliente aceitou. Siga o combinado (ex.: enviar Pix/gerar recebível) — passos de dinheiro ainda pedem sua confirmação.",
  },
  {
    intencao: "cotacao_parcial",
    re: /(so|só|apenas) (tenho|trabalho|consigo)|nao (tenho|trabalho) (o |com )|nao temos (o |esse )|item \d+ (nao|indispon)|dos itens|em falta|indisponivel|indisponível/,
    manejo: "Registre a cotação SÓ dos itens respondidos (record_quote_response) — não cobre o resto do fornecedor.",
  },
  {
    intencao: "pergunta",
    re: /\?|^\s*(qual|quanto|como|onde|quando|quais|voces tem|vocês têm|tem em estoque|qual a bitola|voltagem|amperagem|modelo|serve para|é compativel|é compatível)/,
    manejo: "Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.",
  },
];

export function classificarResposta(texto: string): ResultadoResposta {
  const n = norm(texto);
  for (const r of REGRAS) {
    const m = n.match(r.re);
    if (m) return { intencao: r.intencao, manejo: r.manejo, sinais: [m[0].slice(0, 40)] };
  }
  return { intencao: "outro", manejo: "Trate normalmente conforme o contexto da conversa.", sinais: [] };
}
