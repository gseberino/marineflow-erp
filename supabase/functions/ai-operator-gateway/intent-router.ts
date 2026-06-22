// AI Operator — roteador determinístico de intenções
//
// ECONOMIA DE TOKENS: casos comuns são reconhecidos por regras (sem LLM).
// Só o que cai em "unknown" escala para o modelo. Determinístico e testável.
//
// O resultado alimenta o orquestrador: intenções de back-office (criar/buscar)
// executam via camada compartilhada; intenções de saída (enviar ao cliente)
// passam pelo Motor de Regras de Saída.

export type OperatorIntentKind =
  | "create_quote" // criar orçamento (back-office → executa)
  | "create_service_order" // criar OS (back-office → executa)
  | "search_client" // buscar cliente (leitura)
  | "search_vessel" // buscar embarcação (leitura)
  | "search_product" // buscar produto (leitura)
  | "send_to_client" // enviar algo ao cliente (saída → motor de regras)
  | "unknown"; // escala para o LLM

export interface OperatorIntent {
  kind: OperatorIntentKind;
  /** 0..1. Alto = determinístico (resolve sem LLM). 0 = escala. */
  confidence: number;
  params: Record<string, string>;
  /** Qual regra casou (auditoria/depuração). */
  matchedBy: string;
}

function normalize(s: string): string {
  return s
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "") // remove acentos
    .trim();
}

const CREATE_VERB = /\b(criar|cria|crie|novo|nova|gerar|gere|montar|monte|fazer|faca|abrir|abra)\b/;
const SEARCH_VERB = /\b(buscar|busca|busque|localizar|localize|procurar|procure|achar|ache|consultar|consulte|ver|mostrar|mostre)\b/;
const SEND_VERB = /\b(enviar|envie|envia|mandar|manda|mande|encaminhar|encaminhe|disparar|dispare)\b/;

/** Extrai um alvo textual após preposições comuns ("para", "do", "de", "ao"). */
function extractTarget(text: string, anchor: RegExp): string | undefined {
  const m = text.match(anchor);
  if (!m) return undefined;
  const rest = text.slice((m.index ?? 0) + m[0].length).trim();
  // pega até pontuação ou conector
  const target = rest.split(/[,.;]| que | com | para | sobre /)[0]?.trim();
  return target && target.length > 1 ? target : undefined;
}

export function routeIntent(rawText: string): OperatorIntent {
  const text = normalize(rawText);
  if (!text) {
    return { kind: "unknown", confidence: 0, params: {}, matchedBy: "empty" };
  }

  const has = (re: RegExp) => re.test(text);

  // ---- SAÍDA (enviar ao cliente) — prioridade alta p/ rotear ao motor ----
  if (has(SEND_VERB) && /\b(cliente|whats|whatsapp|cobranca|orcamento|link|os)\b/.test(text)) {
    return {
      kind: "send_to_client",
      confidence: 0.9,
      params: { raw: rawText },
      matchedBy: "send_verb+client_object",
    };
  }

  // ---- CRIAR ORÇAMENTO ----
  if (has(CREATE_VERB) && /\bor[çc]amento\b/.test(rawText.toLowerCase())) {
    const client = extractTarget(text, /\b(para o cliente|para a|para o|para|cliente)\b/);
    return {
      kind: "create_quote",
      confidence: 0.9,
      params: client ? { client } : {},
      matchedBy: "create_verb+orcamento",
    };
  }

  // ---- CRIAR OS ----
  if (
    (has(CREATE_VERB) && /\b(os|ordem de servico)\b/.test(text)) ||
    /\b(abrir os|nova os|abrir ordem de servico)\b/.test(text)
  ) {
    const client = extractTarget(text, /\b(para o cliente|para a|para o|para|cliente)\b/);
    return {
      kind: "create_service_order",
      confidence: 0.85,
      params: client ? { client } : {},
      matchedBy: "create_verb+os",
    };
  }

  // ---- BUSCAR CLIENTE / EMBARCAÇÃO / PRODUTO (leitura) ----
  if (has(SEARCH_VERB) && /\bcliente\b/.test(text)) {
    const q = extractTarget(text, /\bcliente\b/);
    return {
      kind: "search_client",
      confidence: 0.85,
      params: q ? { query: q } : {},
      matchedBy: "search_verb+cliente",
    };
  }
  if (has(SEARCH_VERB) && /\b(embarcacao|barco|lancha|veleiro|motorhome)\b/.test(text)) {
    const q = extractTarget(text, /\b(embarcacao|barco|lancha|veleiro|motorhome)\b/);
    return {
      kind: "search_vessel",
      confidence: 0.85,
      params: q ? { query: q } : {},
      matchedBy: "search_verb+vessel",
    };
  }
  if (has(SEARCH_VERB) && /\b(produto|peca|item)\b/.test(text)) {
    const q = extractTarget(text, /\b(produto|peca|item)\b/);
    return {
      kind: "search_product",
      confidence: 0.8,
      params: q ? { query: q } : {},
      matchedBy: "search_verb+product",
    };
  }

  // ---- ESCALA PARA O LLM ----
  return { kind: "unknown", confidence: 0, params: {}, matchedBy: "no_rule" };
}
