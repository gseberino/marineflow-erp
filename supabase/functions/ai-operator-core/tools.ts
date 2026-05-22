// MarineFlow AI Operator — Tool definitions exposed ao modelo.
// Apenas tools SEGURAS (leitura + operações internas do operador) ficam
// expostas. Ações sensíveis viram propose_action, que cria um pending
// action no banco e é resolvido por aprovação humana explícita.

export const OPERATOR_TOOLS = [
  // ---------- LEITURA ----------
  {
    type: "function",
    function: {
      name: "search_clients",
      description: "Busca clientes por nome, email, telefone ou CPF/CNPJ.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string" },
          limit: { type: "number" },
        },
        required: ["query"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "search_vessels",
      description: "Busca embarcações ou motorhomes por nome/modelo. Pode filtrar por client_id.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string" },
          client_id: { type: "string" },
        },
        required: ["query"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "search_products",
      description: "Busca produtos no catálogo (com preço e estoque).",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string" },
          limit: { type: "number" },
        },
        required: ["query"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "search_services",
      description: "Busca serviços de mão de obra no catálogo.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string" },
          limit: { type: "number" },
        },
        required: ["query"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "get_vessel_history",
      description: "Retorna histórico técnico (OSs anteriores) de uma embarcação.",
      parameters: {
        type: "object",
        properties: { vessel_id: { type: "string" } },
        required: ["vessel_id"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "list_technicians",
      description: "Lista técnicos ativos.",
      parameters: { type: "object", properties: {} },
    },
  },
  // ---------- INTERNAS DO OPERATOR (rascunhos, perguntas, memória) ----------
  {
    type: "function",
    function: {
      name: "create_draft",
      description:
        "Cria um rascunho operacional persistente (orçamento, diagnóstico, plano de atendimento, etc.). " +
        "É SEMPRE seguro chamar — nada é enviado ao cliente nem criado no ERP oficial. " +
        "Use isto para registrar a interpretação estruturada da demanda.",
      parameters: {
        type: "object",
        properties: {
          kind: {
            type: "string",
            enum: ["quote", "diagnosis", "service_plan", "agenda_proposal", "response_suggestion", "note"],
          },
          title: { type: "string" },
          summary: { type: "string" },
          client_id: { type: "string" },
          vessel_id: { type: "string" },
          interpreted_intent: { type: "string" },
          interpreted_category: { type: "string" },
          estimated_labor_hours: { type: "number" },
          estimated_labor_value: { type: "number" },
          estimated_parts_value: { type: "number" },
          estimated_travel_value: { type: "number" },
          estimated_total: { type: "number" },
          pending_questions: { type: "array", items: { type: "string" } },
          next_steps: { type: "array", items: { type: "string" } },
          hypotheses: { type: "array", items: { type: "string" } },
        },
        required: ["kind", "title"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "add_draft_item",
      description:
        "Adiciona um item ao rascunho atual (serviço, produto, item a cotar, deslocamento, pergunta técnica, risco).",
      parameters: {
        type: "object",
        properties: {
          draft_id: { type: "string" },
          item_kind: {
            type: "string",
            enum: ["service", "product", "product_to_quote", "displacement", "engineering", "pending_question", "risk", "reference"],
          },
          description: { type: "string" },
          notes: { type: "string" },
          quantity: { type: "number" },
          unit: { type: "string" },
          unit_price: { type: "number" },
          estimated_total: { type: "number" },
          product_id: { type: "string" },
          service_id: { type: "string" },
          confidence: { type: "string", enum: ["low", "medium", "high"] },
        },
        required: ["draft_id", "item_kind", "description"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "ask_pending_question",
      description: "Registra uma pergunta técnica pendente que precisa de resposta humana.",
      parameters: {
        type: "object",
        properties: {
          draft_id: { type: "string" },
          question: { type: "string" },
        },
        required: ["draft_id", "question"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "register_memory_note",
      description: "Registra uma nota técnica reutilizável sobre embarcação/cliente (caderno de bordo).",
      parameters: {
        type: "object",
        properties: {
          vessel_id: { type: "string" },
          client_id: { type: "string" },
          topic: { type: "string" },
          title: { type: "string" },
          body: { type: "string" },
          confidence: { type: "string", enum: ["low", "medium", "high"] },
        },
        required: ["topic", "title", "body"],
      },
    },
  },
  // ---------- PROPOSTA DE AÇÃO SENSÍVEL ----------
  {
    type: "function",
    function: {
      name: "propose_action",
      description:
        "OBRIGATÓRIO antes de qualquer ação sensível (criar OS oficial, enviar WhatsApp ao cliente, agendar técnico, alterar estoque, " +
        "executar ação financeira). Persiste a ação em pending_actions e aguarda aprovação humana — NUNCA executa diretamente.",
      parameters: {
        type: "object",
        properties: {
          action: { type: "string", description: "Nome técnico da ação (ex: create_service_order)." },
          title: { type: "string" },
          summary_markdown: { type: "string" },
          payload: { type: "object" },
          draft_id: { type: "string" },
        },
        required: ["action", "title", "summary_markdown", "payload"],
      },
    },
  },
];
