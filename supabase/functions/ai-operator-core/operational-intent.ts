export type OperatorDraftKind =
  | "quote"
  | "diagnosis"
  | "service_plan"
  | "agenda_proposal"
  | "response_suggestion"
  | "note";

export type BootstrapDraftItem = {
  item_kind:
    | "service"
    | "product"
    | "product_to_quote"
    | "displacement"
    | "engineering"
    | "pending_question"
    | "risk"
    | "reference";
  description: string;
  notes?: string | null;
  quantity?: number;
  unit?: string;
  estimated_total?: number | null;
};

export type OperationalIntent = {
  kind: OperatorDraftKind;
  status: "awaiting_info" | "draft";
  category: string;
  intent: string;
  shouldBootstrapDraft: true;
};

export type ExistingDraftReferenceKind =
  | "lookup"
  | "continue"
  | "link"
  | "cancel"
  | "anaphora";

export type ExistingDraftReference = {
  kind: ExistingDraftReferenceKind;
  matched: string[];
};

export type MessageClassification =
  | { type: "new_demand"; intent: OperationalIntent }
  | { type: "operate_on_existing"; reference: ExistingDraftReference }
  | { type: "none" };

export type BootstrapDraft = {
  kind: OperatorDraftKind;
  status: "awaiting_info" | "draft";
  title: string;
  summary: string;
  interpreted_intent: string;
  interpreted_category: string;
  pending_questions: string[];
  next_steps: string[];
  hypotheses: string[];
  items: BootstrapDraftItem[];
};

function normalizeText(text: string) {
  return text
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase();
}

function squeeze(text: string, max = 96) {
  const clean = text.replace(/\s+/g, " ").trim();
  if (clean.length <= max) return clean;
  return `${clean.slice(0, max - 1).trim()}...`;
}

function detectCategory(normalized: string) {
  if (
    /(raymarine|garmin|simrad|b&g|nmea|seatalk|axiom|radar|sonar|ais|autopilot|piloto|mfd|multifunction|tela|fly)\b/.test(
      normalized
    )
  ) {
    return "marine_electronics";
  }
  if (/(gerador|generator|cummins|onan|energia)\b/.test(normalized)) return "power_generation";
  if (/(ar condicionado|climatizacao|climatização|hvac)\b/.test(normalized)) return "climate_control";
  return "general_service";
}

function inferKind(normalized: string): OperatorDraftKind | null {
  if (/(responda ao cliente|resposta ao cliente|sugestao de resposta|sugestão de resposta)\b/.test(normalized)) {
    return "response_suggestion";
  }
  if (/(plano de servico|plano de serviço|plano de atendimento)\b/.test(normalized)) {
    return "service_plan";
  }
  if (/(diagnostico|diagnóstico|avaliacao tecnica|avaliação técnica|falha|problema tecnico|problema técnico)\b/.test(normalized)) {
    return "diagnosis";
  }
  if (
    /(orcamento|orçamento|cotacao|cotação|instalacao|instalação|substituicao|substituição|nova tela|visita tecnica|visita técnica)\b/.test(
      normalized
    )
  ) {
    return "quote";
  }
  return null;
}

// Regex agrupadas por intenção. Mantidas explícitas e simples para serem
// auditáveis e testáveis sem ambiguidade. Ordem importa: cancel/link/continue
// têm prioridade sobre anáfora pura.
const REF_LOOKUP_REGEX =
  /\b(localiz[ae]r?|encontr[ae]r?|abr[ae]?|pegu[ae]?|pegue|busca|busqu[ae]r?|procura|procur[ae]r?|liste|listar)\b/;
const REF_CONTINUE_REGEX =
  /\b(continu[ae]r?|retom[ae]r?|finaliz[ae]r?|complet[ae]r?|conclu[ai]r?|atualiz[ae]r?|refin[ae]r?|ajust[ae]r?)\b/;
const REF_LINK_REGEX =
  /\b(vincul[ae]r?|vincule|linke|linkar|associ[ae]r?|conect[ae]r?|amarr[ae]r?|liga[r]?\s+(?:o\s+|a\s+)?(?:cliente|embarcacao|barco))\b/;
const REF_CANCEL_REGEX =
  /\b(cancel[ae]r?|cancele|arquiv[ae]r?|descart[ae]r?|apagu?[ae]r?\s+(?:o\s+|esse\s+)?(?:rascunho|orcamento)|remov[ae]r?\s+(?:o\s+|esse\s+)?(?:rascunho|orcamento))\b/;
// Pronome demonstrativo + substantivo de draft. Inclui "do/da NOME" como
// reforço, mas o sinal principal é a anáfora demonstrativa.
const REF_ANAPHORA_REGEX =
  /\b(aquel[ae]|esse|essa|este|esta)\s+(rascunho|orcamento|cotacao|diagnostico|plano|atendimento)\b/;
// "rascunho" sozinho — sempre indica referência a algo existente. "O cliente
// quer orçamento" é demanda nova; "o rascunho do cliente" é referência.
const REF_RASCUNHO_REGEX = /\brascunho\b/;
// Pertencimento explícito: "do <Nome com inicial maiúscula>" em mensagem que
// também mencione um substantivo de draft. Pega "orcamento do Celio".
function matchOwnershipPattern(message: string, normalized: string): boolean {
  if (!/(orcamento|cotacao|rascunho|diagnostico|plano|atendimento)/.test(normalized)) return false;
  return /\b(do|da|de|d['’])\s+[A-ZÁ-Ú][\wÁ-ú-]{2,}\b/.test(message);
}

export function detectExistingDraftReference(message: string): ExistingDraftReference | null {
  const normalized = normalizeText(message);
  const matched: string[] = [];
  let kind: ExistingDraftReferenceKind | null = null;

  if (REF_CANCEL_REGEX.test(normalized)) {
    kind = "cancel";
    matched.push("cancel");
  }
  if (REF_LINK_REGEX.test(normalized)) {
    kind = kind ?? "link";
    matched.push("link");
  }
  if (REF_LOOKUP_REGEX.test(normalized)) {
    kind = kind ?? "lookup";
    matched.push("lookup");
  }
  if (REF_CONTINUE_REGEX.test(normalized)) {
    kind = kind ?? "continue";
    matched.push("continue");
  }
  if (REF_ANAPHORA_REGEX.test(normalized)) {
    kind = kind ?? "anaphora";
    matched.push("anaphora");
  }
  if (REF_RASCUNHO_REGEX.test(normalized)) {
    // "rascunho" sozinho só conta se também tiver um verbo de operação ou
    // anáfora — evita falso positivo para frases como "crie um rascunho".
    if (matched.length > 0) matched.push("rascunho_token");
  }
  if (matchOwnershipPattern(message, normalized)) {
    kind = kind ?? "lookup";
    matched.push("ownership");
  }

  if (!kind) return null;
  return { kind, matched };
}

export function detectOperationalIntent(message: string): OperationalIntent | null {
  const normalized = normalizeText(message);
  const kind = inferKind(normalized);
  if (!kind) return null;

  return {
    kind,
    status: "awaiting_info",
    category: detectCategory(normalized),
    intent:
      kind === "quote"
        ? "prepare_quote"
        : kind === "diagnosis"
          ? "prepare_diagnosis"
          : kind === "service_plan"
            ? "prepare_service_plan"
            : "prepare_response_suggestion",
    shouldBootstrapDraft: true,
  };
}

/**
 * Classificação trinária determinística da mensagem.
 *
 * Regra crítica: se a mensagem contém sinais de referência a draft existente
 * (vincule/cancele/aquele orcamento/do <Nome>/etc.), ela é classificada como
 * `operate_on_existing` mesmo que também contenha palavras-gatilho como
 * "orcamento" ou "instalacao". Isso impede que o backend bootstrape um draft
 * novo quando a real intenção do usuário é operar sobre um draft já existente.
 */
export function classifyMessage(message: string): MessageClassification {
  const reference = detectExistingDraftReference(message);
  if (reference) {
    return { type: "operate_on_existing", reference };
  }
  const intent = detectOperationalIntent(message);
  if (intent) {
    return { type: "new_demand", intent };
  }
  return { type: "none" };
}

function buildTitle(kind: OperatorDraftKind, normalized: string, message: string) {
  const raymarine = /raymarine/i.test(message);
  const fly = /\bfly\b/i.test(message);
  if (kind === "quote" && raymarine) {
    return `Orcamento: Instalacao Raymarine${fly ? " no Fly" : ""}`;
  }
  if (kind === "diagnosis" && raymarine) {
    return `Diagnostico: Sistema Raymarine${fly ? " no Fly" : ""}`;
  }
  if (kind === "response_suggestion") return "Sugestao de resposta ao cliente";
  if (kind === "service_plan") return "Plano de atendimento tecnico";
  if (kind === "diagnosis") return `Diagnostico tecnico: ${squeeze(message, 56)}`;
  if (/(orcamento|orçamento)/.test(normalized)) return `Orcamento: ${squeeze(message, 56)}`;
  return `Rascunho operacional: ${squeeze(message, 56)}`;
}

export function buildBootstrapDraft(
  intent: OperationalIntent,
  params: { message: string }
): BootstrapDraft {
  const normalized = normalizeText(params.message);
  const isMarineElectronics = intent.category === "marine_electronics";

  const pendingQuestions = isMarineElectronics
    ? [
        "Qual e a embarcacao e onde ela esta localizada?",
        "Qual e o modelo exato da nova tela e quais equipamentos existentes precisam integrar?",
        "Ja existe backbone NMEA 2000 ou sera necessario montar a rede auxiliar?",
      ]
    : ["Quais informacoes ainda faltam para fechar o escopo tecnico?"];

  const nextSteps = isMarineElectronics
    ? [
        "Confirmar cliente e embarcacao no ERP.",
        "Revisar compatibilidade com equipamentos antigos.",
        "Refinar o rascunho com materiais e estimativas apos as respostas pendentes.",
      ]
    : ["Coletar as informacoes faltantes e revisar o rascunho com o operador."];

  const hypotheses = isMarineElectronics
    ? [
        "Pode haver cabeamento, alimentacao ou backbone legado que precise de adaptacao.",
        "Pode ser necessaria visita tecnica previa se a integracao com equipamentos antigos estiver indefinida.",
      ]
    : ["O escopo tecnico ainda depende de confirmacao humana."];

  const items: BootstrapDraftItem[] = isMarineElectronics
    ? [
        { item_kind: "service", description: "Mao de obra tecnica para instalacao e configuracao da nova tela" },
        { item_kind: "engineering", description: "Levantamento tecnico de compatibilidade com equipamentos existentes" },
        { item_kind: "product_to_quote", description: "Rede de comunicacao auxiliar, backbone e acessorios de integracao" },
        { item_kind: "product_to_quote", description: "Cabos, conectores, protecao e alimentacao de energia dedicados" },
        { item_kind: "displacement", description: "Deslocamento ate a embarcacao para instalacao ou visita tecnica" },
        { item_kind: "risk", description: "Verificar equipamentos antigos ou incompativeis antes de fechar o escopo" },
      ]
    : [
        { item_kind: "service", description: "Escopo tecnico preliminar em elaboracao" },
        { item_kind: "pending_question", description: "Aguardando detalhes complementares do atendimento" },
      ];

  return {
    kind: intent.kind,
    status: intent.status,
    title: buildTitle(intent.kind, normalized, params.message),
    summary: squeeze(params.message, 240),
    interpreted_intent: intent.intent,
    interpreted_category: intent.category,
    pending_questions: pendingQuestions,
    next_steps: nextSteps,
    hypotheses,
    items,
  };
}
