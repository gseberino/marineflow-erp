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
    .replace(/[\u0300-\u036f]/g, "")
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
