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
      description: "Busca embarcacoes ou motorhomes por nome/modelo usando termos humanos.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string" },
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
      description: "Retorna historico tecnico (OSs anteriores) de uma embarcacao localizada por termo humano.",
      parameters: {
        type: "object",
        properties: { vessel_query: { type: "string" } },
        required: ["vessel_query"],
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
          status: {
            type: "string",
            enum: ["draft", "awaiting_info"],
          },
          summary: { type: "string" },
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
      name: "update_draft",
      description:
        "Atualiza o rascunho ativo sem criar uma nova OS. Use quando ja existir um draft persistente e voce apenas precisar refinar titulo, resumo, estado operacional, perguntas pendentes, proximos passos, hipoteses e estimativas internas. Status de governanca como approved, rejected, converted ou cancelled nao podem ser definidos pelo modelo.",
      parameters: {
        type: "object",
        properties: {
          title: { type: "string" },
          status: {
            type: "string",
            enum: ["draft", "awaiting_info"],
          },
          summary: { type: "string" },
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
        required: ["item_kind", "description"],
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
          question: { type: "string" },
        },
        required: ["question"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "register_memory_candidate",
      description:
        "Registra uma observação técnica CANDIDATA sobre embarcação/cliente. " +
        "A nota nasce como 'candidate' (não verificada) e só será considerada fato " +
        "operacional após validação humana por papel autorizado. Use para registrar " +
        "informações úteis observadas durante o atendimento, sem afirmar verdade absoluta.",
      parameters: {
        type: "object",
        properties: {
          topic: { type: "string" },
          title: { type: "string" },
          body: { type: "string" },
          confidence: { type: "string", enum: ["low", "medium", "high"] },
        },
        required: ["topic", "title", "body"],
      },
    },
  },
  // ---------- PROPOSTA DE VINCULO (somente sugestao, exige confirmacao UI) ----------
  {
    type: "function",
    function: {
      name: "propose_entity_link",
      description:
        "Apresenta uma sugestao de vinculo de cliente e/ou embarcacao para o rascunho ATIVO da sessao atual. " +
        "NAO grava nada — apenas estrutura uma proposta com nomes humanos para o usuario confirmar na interface. " +
        "O draft alvo NAO e escolhido pelo modelo; e sempre o draft ativo resolvido pelo backend. " +
        "Use nomes ou termos humanos informados pelo usuario; nunca use IDs internos. " +
        "Se nao houver draft ativo, o backend respondera com erro indicando que o usuario precisa selecionar um rascunho primeiro.",
      parameters: {
        type: "object",
        properties: {
          client_query: {
            type: "string",
            description: "Nome ou termo humano do cliente mencionado pelo usuario.",
          },
          vessel_query: {
            type: "string",
            description: "Nome, modelo ou termo humano da embarcacao mencionada pelo usuario.",
          },
          rationale: {
            type: "string",
            description: "Breve justificativa em portugues sobre porque estes candidatos foram escolhidos.",
          },
        },
      },
    },
  },
  // ---------- PROPOSTA DE AÇÃO SENSÍVEL ----------
  {
    type: "function",
    function: {
      name: "propose_external_quote_from_draft",
      description:
        "Prepara um card de confirmacao para formalizar o rascunho ATIVO como orcamento formal em external_quotes. " +
        "NAO persiste o orcamento, NAO cria OS, NAO envia WhatsApp, NAO altera estoque, financeiro ou agenda. " +
        "A criacao real ocorre somente apos confirmacao humana pela interface no endpoint create_external_quote_from_draft. " +
        "O draft, cliente e embarcacao sao resolvidos pelo backend a partir do contexto seguro; nunca envie IDs internos.",
      parameters: {
        type: "object",
        properties: {
          rationale: {
            type: "string",
            description: "Breve justificativa em portugues para formalizar o draft ativo como orcamento.",
          },
        },
      },
    },
  },
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
        },
        required: ["action", "title", "summary_markdown", "payload"],
      },
    },
  },
];
