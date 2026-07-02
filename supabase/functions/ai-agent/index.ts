// Edge Function: ai-agent
// Agente de IA com function calling — Google Gemini API (OpenAI-compatible endpoint).
// Recebe { messages, context } e roda loop de tool-calling até resposta final.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const jr = (b: unknown, s = 200) => {
  console.log(`[AI-AGENT] Returning status ${s}:`, JSON.stringify(b).slice(0, 200));
  return new Response(JSON.stringify(b), {
    status: 200, // Always return 200 to avoid Supabase generic non-2xx error handling
    headers: { ...corsHeaders, "Content-Type": "application/json", "X-Actual-Status": s.toString() },
  });
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;
const GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/openai";
const MODEL_FAST = "gemini-3.5-flash";
const MODEL_SMART = "gemini-3.5-flash";
const MODEL_FALLBACK = "gemini-2.5-flash";
const MAX_ITERATIONS = 8;

// Chama o Gemini com retry/backoff em 503 (sobrecarga temporária do Google) e,
// se persistir, cai para um modelo mais estabelecido (MODEL_FALLBACK).
async function callGeminiWithRetry(body: Record<string, unknown>): Promise<Response> {
  const primaryModel = body.model as string;
  const models = primaryModel === MODEL_FALLBACK ? [primaryModel] : [primaryModel, MODEL_FALLBACK];
  let lastRes: Response | null = null;
  for (const model of models) {
    for (let attempt = 0; attempt < 3; attempt++) {
      const res = await fetch(`${GEMINI_BASE_URL}/chat/completions`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${GEMINI_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ ...body, model }),
      });
      if (res.status !== 503) return res;
      lastRes = res;
      if (attempt < 2) await new Promise((r) => setTimeout(r, 500 * (attempt + 1)));
    }
  }
  return lastRes!;
}

// ---------------- TOOL DEFINITIONS ----------------
const TOOLS = [
  // ====== READ ======
  {
    type: "function",
    function: {
      name: "search_clients",
      description: "Busca clientes por nome, email, telefone ou CPF/CNPJ (tolerante a erros).",
      parameters: {
        type: "object",
        properties: { query: { type: "string" }, limit: { type: "number" } },
        required: ["query"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "search_vessels",
      description: "Busca embarcações por nome/modelo. Pode filtrar por client_id.",
      parameters: {
        type: "object",
        properties: { query: { type: "string" }, client_id: { type: "string" } },
        required: ["query"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "search_products",
      description: "Busca produtos/equipamentos no catálogo.",
      parameters: {
        type: "object",
        properties: { query: { type: "string" }, limit: { type: "number" } },
        required: ["query"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "list_agenda",
      description: "Lista compromissos da agenda em um intervalo de datas (ISO).",
      parameters: {
        type: "object",
        properties: {
          date_from: { type: "string", description: "ISO datetime" },
          date_to: { type: "string", description: "ISO datetime" },
          technician_id: { type: "string" },
        },
        required: ["date_from", "date_to"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "list_service_orders",
      description: "Lista orçamentos ou ordens de serviço. IMPORTANTE: orçamentos têm status='draft' (número ORÇ-XXXXX). OS têm outros status (número OS-XXXXX). Use is_quote=true para listar apenas orçamentos, is_quote=false para listar apenas OS, ou omita para listar tudo.",
      parameters: {
        type: "object",
        properties: {
          is_quote: { type: "boolean", description: "true=apenas orçamentos (draft), false=apenas OS (non-draft), omitir=todos" },
          status: { type: "string", description: "Filtro por status específico (ex: 'approved', 'in_progress'). Ignorado se is_quote for fornecido." },
          client_id: { type: "string" },
          vessel_id: { type: "string" },
          limit: { type: "number", description: "Máximo de registros (padrão 20)" },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "get_service_order",
      description: "Detalhes completos de uma OS incluindo itens e serviços.",
      parameters: {
        type: "object",
        properties: { id: { type: "string" } },
        required: ["id"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "get_client_history",
      description: "Histórico de OSs de um cliente.",
      parameters: {
        type: "object",
        properties: { client_id: { type: "string" } },
        required: ["client_id"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "list_pending_collections",
      description: "Lista cobranças pendentes ou atrasadas. Pode filtrar por client_id.",
      parameters: {
        type: "object",
        properties: { client_id: { type: "string" } },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "search_services",
      description: "Busca serviços de mão de obra no catálogo por nome ou descrição.",
      parameters: {
        type: "object",
        properties: { query: { type: "string" }, limit: { type: "number" } },
        required: ["query"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "list_technicians",
      description: "Lista os técnicos disponíveis no sistema.",
      parameters: { type: "object", properties: {} },
    },
  },
  {
    type: "function",
    function: {
      name: "list_marinas",
      description: "Lista marinas cadastradas.",
      parameters: { type: "object", properties: { query: { type: "string" } } },
    },
  },
  {
    type: "function",
    function: {
      name: "get_vessel_history",
      description: "Retorna o histórico completo de serviços realizados em uma embarcação.",
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
      name: "get_financial_dre",
      description: "Retorna o DRE (Demonstrativo de Resultados) de um período específico.",
      parameters: {
        type: "object",
        properties: {
          year: { type: "number" },
          month: { type: "number" },
        },
        required: ["year", "month"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "get_technician_commissions",
      description: "Calcula ou lista as comissões de um técnico.",
      parameters: {
        type: "object",
        properties: {
          technician_id: { type: "string" },
          status: { type: "string", enum: ["pending", "paid"] },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "get_os_profitability",
      description: "Analisa a lucratividade detalhada de uma Ordem de Serviço.",
      parameters: {
        type: "object",
        properties: { service_order_id: { type: "string" } },
        required: ["service_order_id"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "adjust_inventory",
      description: "Realiza um ajuste manual no estoque de um produto.",
      parameters: {
        type: "object",
        properties: {
          product_id: { type: "string" },
          new_quantity: { type: "number" },
          reason: { type: "string" },
        },
        required: ["product_id", "new_quantity", "reason"],
      },
    },
  },

  {
    type: "function",
    function: {
      name: "propose_action",
      description:
        "OBRIGATÓRIO antes de qualquer escrita ou envio de WhatsApp. Apresenta um resumo ao usuário e aguarda confirmação. Após receber 'Confirmado pelo usuário', chame a tool real correspondente.",
      parameters: {
        type: "object",
        properties: {
          action: { type: "string", description: "Nome da action (ex: create_service_order)" },
          title: { type: "string", description: "Título legível para o card de confirmação" },
          summary_markdown: { type: "string", description: "Resumo detalhado em markdown" },
          payload: { type: "object", description: "Payload exato que será passado à tool real" },
        },
        required: ["action", "title", "summary_markdown", "payload"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "present_options",
      description:
        "Use quando precisar que o usuário escolha entre opções. Exemplos: múltiplos clientes, múltiplas OSs, sim/não. NUNCA escreva lista em texto — sempre use esta tool. Máximo 6 opções visíveis. Se houver mais de 5 resultados, mostre os 5 mais relevantes + última opção sempre sendo {label:'🔍 Refinar busca — digitar mais detalhes',value:'__refine__'}. Se usuário escolher __refine__, peça mais informações específicas (sobrenome, telefone, CNPJ).",
      parameters: {
        type: "object",
        properties: {
          question: { type: "string", description: "Pergunta clara para o usuário (ex: 'Qual cliente você quer?')" },
          options: {
            type: "array",
            maxItems: 6,
            items: {
              type: "object",
              properties: {
                label: { type: "string", description: "Texto visível no botão (curto, max 50 chars). Inclua info útil: nome + telefone ou nome + cidade." },
                value: { type: "string", description: "Valor interno: UUID do registro, ou '__refine__' para pedir mais detalhes." },
              },
              required: ["label", "value"],
            },
            description: "Lista de opções (máx 6). Se resultados > 5, inclua os 5 melhores + {label:'🔍 Refinar busca',value:'__refine__'}.",
          },
          total_found: { type: "number", description: "Total de resultados encontrados (para informar o usuário quando > 5)" },
        },
        required: ["question", "options"],
      },
    },
  },

  // ====== WRITE ======
  {
    type: "function",
    function: {
      name: "create_agenda_task",
      description: "Cria um compromisso na agenda.",
      parameters: {
        type: "object",
        properties: {
          title: { type: "string" },
          scheduled_start_at: { type: "string" },
          scheduled_end_at: { type: "string" },
          technician_user_id: { type: "string" },
          client_id: { type: "string" },
          location: { type: "string" },
          notes: { type: "string" },
          priority: { type: "string" },
        },
        required: ["title", "scheduled_start_at", "technician_user_id"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "update_agenda_task",
      description: "Atualiza campos de um compromisso.",
      parameters: {
        type: "object",
        properties: {
          id: { type: "string" },
          title: { type: "string" },
          scheduled_start_at: { type: "string" },
          scheduled_end_at: { type: "string" },
          status: { type: "string" },
          notes: { type: "string" },
        },
        required: ["id"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "create_service_order",
      description: "Cria um novo orçamento (status='draft', número ORÇ-XXXXX) ou OS (outro status, número OS-XXXXX). SEMPRE pesquise o cliente e o ativo/embarcação antes de criar. Se não houver ativo cadastrado, use create_vessel primeiro (suporta Camper, Motorhome, Lancha, etc.).",
      parameters: {
        type: "object",
        properties: {
          client_id: { type: "string", description: "UUID do cliente (obrigatório)" },
          vessel_id: { type: "string", description: "UUID do ativo/embarcação (obrigatório — use search_vessels ou create_vessel antes)" },
          status: { type: "string", description: "Status inicial. Use 'draft' para orçamento. Padrão: draft." },
          problem_description: { type: "string", description: "Descrição do problema ou escopo do serviço" },
          extra_notes: { type: "string", description: "Observações visíveis ao cliente no PDF (condições, ressalvas, validade)" },
          internal_notes: { type: "string", description: "Notas internas (não aparecem no PDF do cliente)" },
          scheduled_start_at: { type: "string", description: "Data/hora de início agendada (ISO)" },
          quote_validity_days: { type: "number", description: "Validade do orçamento em dias (padrão 30)" },
          payment_conditions: { type: "string", description: "Condições de pagamento (ex: '50% na aprovação, 50% na entrega')" },
          items: {
            type: "array",
            description: "Produtos do catálogo a adicionar (opcional — prefira add_service_to_order e add_material_to_order após criar)",
            items: {
              type: "object",
              properties: {
                product_id: { type: "string" },
                quantity: { type: "number" },
              },
              required: ["product_id", "quantity"],
            },
          },
        },
        required: ["client_id", "vessel_id"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "update_service_order_status",
      description: "Altera o status de uma OS/orçamento. IMPORTANTE: ao aprovar um orçamento (draft → outro status), o sistema automaticamente renomeia o número de ORÇ-XXXXX para OS-XXXXX.",
      parameters: {
        type: "object",
        properties: {
          id: { type: "string", description: "UUID da OS/orçamento" },
          status: {
            type: "string",
            enum: ["draft", "open", "pending", "approved", "scheduled", "in_progress", "waiting_parts", "waiting_approval", "completed", "cancelled", "invoiced", "reopened"],
            description: "Novo status. 'draft'=Rascunho/Orçamento, 'open'=Aberto, 'pending'=Pendente, 'approved'=Aprovado, 'scheduled'=Agendado, 'in_progress'=Em andamento, 'waiting_parts'=Aguardando peças, 'waiting_approval'=Aguardando aprovação, 'completed'=Concluído, 'cancelled'=Cancelado, 'invoiced'=Faturado, 'reopened'=Reaberto",
          },
          cancellation_reason: { type: "string", description: "Motivo do cancelamento (quando status=cancelled)" },
        },
        required: ["id", "status"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "add_service_order_item",
      description: "Adiciona um produto a uma OS.",
      parameters: {
        type: "object",
        properties: {
          service_order_id: { type: "string" },
          product_id: { type: "string" },
          quantity: { type: "number" },
        },
        required: ["service_order_id", "product_id", "quantity"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "add_service_to_order",
      description: "Adiciona um serviço de mão de obra a uma OS existente.",
      parameters: {
        type: "object",
        properties: {
          service_order_id: { type: "string" },
          service_name: { type: "string", description: "Nome/descrição do serviço" },
          service_id: { type: "string", description: "ID do serviço cadastrado (opcional)" },
          quantity: { type: "number", default: 1 },
          unit_price: { type: "number" },
          billing_unit: { type: "string", enum: ["hour", "visit", "day", "unit"] },
          notes: { type: "string" },
        },
        required: ["service_order_id", "service_name", "unit_price"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "add_material_to_order",
      description: "Adiciona um item de material/insumo livre a uma OS sem necessitar de produto cadastrado no catálogo. Use quando o usuário descreve materiais estimados (ex: 'R$ 4.500 em materiais elétricos') sem produto específico. O item fica registrado como serviço do tipo 'material'.",
      parameters: {
        type: "object",
        properties: {
          service_order_id: { type: "string", description: "UUID da OS/orçamento" },
          name: { type: "string", description: "Nome/descrição do conjunto de materiais (ex: 'Materiais e Insumos de Instalação')" },
          unit_price: { type: "number", description: "Valor total ou unitário em R$" },
          quantity: { type: "number", description: "Quantidade (padrão 1 para valor total)" },
          notes: { type: "string", description: "Detalhamento dos itens incluídos" },
        },
        required: ["service_order_id", "name", "unit_price"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "get_os_receivables",
      description: "Lista os recebíveis e pagamentos de uma OS. Use para responder perguntas sobre o status financeiro de uma OS: quanto foi cobrado, quanto foi pago, saldo em aberto.",
      parameters: {
        type: "object",
        properties: {
          service_order_id: { type: "string", description: "UUID da OS" },
        },
        required: ["service_order_id"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "schedule_service_order",
      description: "Agenda uma OS definindo data/hora de início, fim e técnico responsável.",
      parameters: {
        type: "object",
        properties: {
          service_order_id: { type: "string" },
          scheduled_start_at: { type: "string", description: "ISO datetime" },
          scheduled_end_at: { type: "string", description: "ISO datetime" },
          technician_user_id: { type: "string" },
        },
        required: ["service_order_id", "scheduled_start_at"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "optimize_text",
      description: "Melhora/reescreve um texto de observação, descrição de problema ou proposta usando IA. Retorna o texto otimizado.",
      parameters: {
        type: "object",
        properties: {
          text: { type: "string", description: "Texto original a ser melhorado" },
          context: { type: "string", description: "Contexto: 'problem_description', 'service_notes', 'proposal', 'observation'" },
        },
        required: ["text", "context"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "apply_service_order_discount",
      description: "Aplica desconto em uma OS (em valor, não percentual).",
      parameters: {
        type: "object",
        properties: { id: { type: "string" }, discount_amount: { type: "number" } },
        required: ["id", "discount_amount"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "create_client",
      description: "Cadastra um novo cliente.",
      parameters: {
        type: "object",
        properties: {
          name: { type: "string" },
          type: { type: "string", enum: ["individual", "company"] },
          phone: { type: "string" },
          whatsapp: { type: "string" },
          email: { type: "string" },
          cpf_cnpj: { type: "string" },
        },
        required: ["name", "type"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "create_vessel",
      description: "Cadastra uma nova unidade/ativo (embarcação ou motorhome) para um cliente.",
      parameters: {
        type: "object",
        properties: {
          client_id: { type: "string" },
          name: { type: "string", description: "Nome da embarcação ou identificação do motorhome" },
          manufacturer: { type: "string" },
          model: { type: "string" },
          year: { type: "number" },
          asset_type: { type: "string", description: "Exemplo: Lancha, Veleiro, Motorhome, Camper, Jet Ski" },
          marina_id: { type: "string" },
        },
        required: ["client_id", "name", "asset_type"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "create_product",
      description: "Cadastra um novo produto/equipamento.",
      parameters: {
        type: "object",
        properties: {
          name: { type: "string" },
          sku: { type: "string" },
          sale_price: { type: "number" },
          cost_price: { type: "number" },
          unit: { type: "string" },
        },
        required: ["name"],
      },
    },
  },

  // ====== WHATSAPP ======
  {
    type: "function",
    function: {
      name: "send_whatsapp_message",
      description:
        "Envia mensagem de WhatsApp via Evolution API. Forneça to_phone OU client_id (busca o WhatsApp/telefone do cliente).",
      parameters: {
        type: "object",
        properties: {
          to_phone: { type: "string" },
          client_id: { type: "string" },
          message: { type: "string" },
        },
        required: ["message"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "send_collection_reminder",
      description:
        "Envia um lembrete de cobrança por WhatsApp para o contato da cobrança.",
      parameters: {
        type: "object",
        properties: {
          collection_id: { type: "string" },
          custom_message: { type: "string" },
        },
        required: ["collection_id"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "send_service_order_link",
      description:
        "Envia o link público de uma OS/orçamento por WhatsApp. Use sempre que o usuário pedir 'enviar orçamento', 'mandar OS', 'enviar para o cliente' etc. O campo service_order_id aceita TANTO o UUID (campo 'id' do list_service_orders) QUANTO o número do documento (ex: 'ORÇ-00001' para orçamentos, 'OS-00042' para OS, ou o formato antigo 'OS-2026-XXXXX'). Prefira sempre o UUID.",
      parameters: {
        type: "object",
        properties: {
          service_order_id: { type: "string", description: "UUID (campo id) ou número da OS (campo numero, ex: OS-2026-152542)" },
          custom_message: { type: "string", description: "Mensagem personalizada. Se omitido, usa mensagem padrão com link." },
        },
        required: ["service_order_id"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "schedule_whatsapp_message",
      description:
        "Agenda uma mensagem WhatsApp para ser enviada em data/hora específica. Use para 'agendar envio', 'mandar amanhã', 'lembrete automático' etc. Para envios com link de OS, informe service_order_id.",
      parameters: {
        type: "object",
        properties: {
          phone: { type: "string", description: "Telefone do destinatário com DDI+DDD (ex: 5547999999999). Obrigatório se não informar client_id." },
          client_id: { type: "string", description: "UUID do cliente — busca o WhatsApp/telefone automaticamente." },
          message: { type: "string", description: "Texto da mensagem a ser enviada." },
          scheduled_at: { type: "string", description: "Data e hora do envio em ISO 8601 (ex: 2026-05-10T09:00:00)." },
          recurrence_type: { type: "string", enum: ["once", "daily", "weekly", "monthly"], description: "Recorrência do envio. Padrão: once." },
          service_order_id: { type: "string", description: "UUID ou número da OS para envio de link (send_mode=link)." },
          send_mode: { type: "string", enum: ["text", "link"], description: "Modo de envio. Padrão: text. Use 'link' para enviar o link público de uma OS." },
        },
        required: ["message", "scheduled_at"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "list_scheduled_whatsapp",
      description: "Lista as mensagens WhatsApp agendadas. Pode filtrar por status.",
      parameters: {
        type: "object",
        properties: {
          status: { type: "string", enum: ["pending", "sent", "failed", "cancelled", "all"], description: "Filtro de status. Padrão: pending." },
          limit: { type: "number", description: "Máximo de registros. Padrão: 10." },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "cancel_scheduled_whatsapp",
      description: "Cancela um agendamento de WhatsApp pelo ID.",
      parameters: {
        type: "object",
        properties: {
          scheduled_id: { type: "string", description: "UUID do agendamento a cancelar." },
        },
        required: ["scheduled_id"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "create_purchase_order",
      description: "Cria uma nova ordem de compra para um fornecedor.",
      parameters: {
        type: "object",
        properties: {
          supplier_id: { type: "string" },
          service_order_id: { type: "string" },
          expected_date: { type: "string", description: "Data esperada (ISO date)" },
          notes: { type: "string" },
          items: {
            type: "array",
            items: {
              type: "object",
              properties: {
                product_id: { type: "string" },
                description: { type: "string" },
                quantity: { type: "number" },
                unit_cost: { type: "number" },
              },
              required: ["description", "quantity", "unit_cost"],
            },
          },
        },
        required: ["supplier_id"],
      },
    },
  },
];

// ---------------- TOOL EXECUTORS ----------------
async function executeTool(
  name: string,
  args: any,
  ctx: { sb: any; admin: any; userId: string; jwt: string; appOrigin: string; settings: Record<string, string> }
): Promise<any> {
  const { sb, admin, userId, jwt, appOrigin, settings } = ctx;

  switch (name) {
    case "search_clients": {
      const q = String(args.query || "").trim();
      const limit = Math.min(Number(args.limit) || 10, 25);
      const { data, error } = await sb
        .from("clients")
        .select("id, name, type, phone, whatsapp, email, cpf_cnpj")
        .or(
          `name.ilike.%${q}%,email.ilike.%${q}%,phone.ilike.%${q}%,whatsapp.ilike.%${q}%,cpf_cnpj.ilike.%${q}%`
        )
        .eq("active", true)
        .limit(limit);
      if (error) throw error;
      return { results: data };
    }

    case "search_vessels": {
      const q = String(args.query || "").trim();
      let query = sb
        .from("vessels")
        .select("id, name, manufacturer, model, year, client_id, marina_id")
        .eq("active", true)
        .or(`name.ilike.%${q}%,model.ilike.%${q}%,manufacturer.ilike.%${q}%`)
        .limit(15);
      if (args.client_id) query = query.eq("client_id", args.client_id);
      const { data, error } = await query;
      if (error) throw error;
      return { results: data };
    }

    case "search_products": {
      const q = String(args.query || "").trim();
      const limit = Math.min(Number(args.limit) || 10, 25);
      const { data, error } = await sb
        .from("products")
        .select("id, name, sku, brand, sale_price, stock_quantity, unit")
        .eq("active", true)
        .or(`name.ilike.%${q}%,sku.ilike.%${q}%,brand.ilike.%${q}%`)
        .limit(limit);
      if (error) throw error;
      return { results: data };
    }

    case "list_agenda": {
      let query = sb
        .from("agenda_tasks")
        .select("id, title, scheduled_start_at, scheduled_end_at, status, priority, location, clients(name), app_users(full_name)")
        .gte("scheduled_start_at", args.date_from)
        .lte("scheduled_start_at", args.date_to)
        .order("scheduled_start_at", { ascending: true });
      if (args.technician_id) query = query.eq("technician_user_id", args.technician_id);
      const { data, error } = await query;
      if (error) throw error;
      const mapped = (data || []).map((t: any) => ({
        id: t.id,
        titulo: t.title,
        cliente: t.clients?.name || "—",
        tecnico: t.app_users?.full_name || "—",
        inicio: t.scheduled_start_at,
        fim: t.scheduled_end_at,
        status: t.status,
        prioridade: t.priority,
        local: t.location || "—",
      }));
      return { results: mapped };
    }

    case "list_service_orders": {
      let query = sb
        .from("service_orders")
        .select("id, service_order_number, status, grand_total, payment_status, scheduled_start_at, created_at, clients(name), vessels(name)")
        .order("created_at", { ascending: false })
        .limit(Math.min(Number(args.limit) || 20, 50));

      // Filtro is_quote: true=apenas orçamentos (draft), false=apenas OS (non-draft)
      if (args.is_quote === true) {
        query = query.eq("status", "draft");
      } else if (args.is_quote === false) {
        query = query.neq("status", "draft");
      } else if (args.status) {
        const STATUS_PT_EN: Record<string, string> = {
          "rascunho": "draft", "orçamento": "draft", "orcamento": "draft",
          "aberto": "open", "pendente": "pending", "aprovado": "approved",
          "agendado": "scheduled", "em andamento": "in_progress", "em execução": "in_progress",
          "concluído": "completed", "concluido": "completed",
          "cancelado": "cancelled", "faturado": "invoiced",
          "aguardando peças": "waiting_parts", "aguardando aprovação": "waiting_approval",
          "reaberto": "reopened",
        };
        const mappedStatus = STATUS_PT_EN[args.status.toLowerCase()] ?? args.status;
        query = query.eq("status", mappedStatus);
      }

      if (args.client_id) query = query.eq("client_id", args.client_id);
      if (args.vessel_id) query = query.eq("vessel_id", args.vessel_id);
      const { data, error } = await query;
      if (error) throw error;

      const STATUS_LABELS: Record<string, string> = {
        draft: "Orçamento", open: "Aberto", pending: "Pendente", approved: "Aprovado",
        scheduled: "Agendado", in_progress: "Em andamento", waiting_parts: "Aguardando peças",
        waiting_approval: "Aguardando aprovação", completed: "Concluído",
        cancelled: "Cancelado", invoiced: "Faturado", reopened: "Reaberto",
      };

      const mapped = (data || []).map((so: any) => ({
        id: so.id,
        numero: so.service_order_number,
        tipo: so.status === "draft" ? "Orçamento" : "OS",
        status: STATUS_LABELS[so.status] || so.status,
        status_raw: so.status,
        status_pagamento: so.payment_status || null,
        cliente: so.clients?.name || "—",
        ativo: so.vessels?.name || "—",
        valor_total: so.grand_total || 0,
        agendado_para: so.scheduled_start_at || null,
        criado_em: so.created_at,
      }));
      return { results: mapped };
    }

    case "get_service_order": {
      const { data: so, error } = await sb
        .from("service_orders")
        .select("*, clients(name), vessels(name)")
        .eq("id", args.id)
        .maybeSingle();
      if (error) throw error;
      if (!so) return { error: "OS não encontrada" };
      const { data: parts } = await sb
        .from("service_order_parts")
        .select("id, quantity, line_total_sale, products(name)")
        .eq("service_order_id", args.id);
      const { data: services } = await sb
        .from("service_order_services")
        .select("id, name_snapshot, quantity, unit_price_snapshot, line_total")
        .eq("service_order_id", args.id);
      
      return { 
        service_order: {
          ...so,
          cliente: so.clients?.name || "—",
          embarcacao: so.vessels?.name || "—"
        }, 
        parts: (parts || []).map((p: any) => ({
          produto: p.products?.name || "Desconhecido",
          quantidade: p.quantity,
          total: p.line_total_sale
        })), 
        services: (services || []).map((s: any) => ({
          servico: s.name_snapshot,
          quantidade: s.quantity,
          preco_unitario: s.unit_price_snapshot,
          total: s.line_total
        }))
      };
    }

    case "get_client_history": {
      const { data, error } = await sb
        .from("service_orders")
        .select("id, service_order_number, status, scheduled_start_at, grand_total, created_at, vessels(name)")
        .eq("client_id", args.client_id)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      const mapped = (data || []).map((so: any) => ({
        numero: so.service_order_number,
        status: so.status,
        embarcacao: so.vessels?.name || "—",
        valor_total: so.grand_total || 0,
        agendado_para: so.scheduled_start_at || null,
        criado_em: so.created_at,
      }));
      return { history: mapped };
    }

    case "list_pending_collections": {
      let query = sb
        .from("collections")
        .select("id, client_id, due_date, amount, status, contact_name, contact_whatsapp, description")
        .in("status", ["pending", "overdue", "scheduled"])
        .order("due_date", { ascending: true })
        .limit(50);
      if (args.client_id) query = query.eq("client_id", args.client_id);
      const { data, error } = await query;
      if (error) throw error;
      return { results: data };
    }

    case "search_services": {
      const q = String(args.query || "").trim();
      const limit = Math.min(Number(args.limit) || 10, 25);
      const { data, error } = await sb
        .from("services")
        .select("id, name, description, billing_unit, default_price")
        .eq("active", true)
        .or(`name.ilike.%${q}%,description.ilike.%${q}%`)
        .limit(limit);
      if (error) throw error;
      return { results: data };
    }

    case "list_technicians": {
      const { data, error } = await sb
        .from("app_users")
        .select("id, full_name, role")
        .in("role", ["technician", "admin"])
        .eq("active", true)
        .order("full_name");
      if (error) throw error;
      return { results: data };
    }

    case "list_marinas": {
      const q = String(args.query || "").trim();
      let query = sb
        .from("marinas")
        .select("id, name, city, state")
        .eq("active", true)
        .order("name")
        .limit(20);
      if (q) query = query.ilike("name", `%${q}%`);
      const { data, error } = await query;
      if (error) throw error;
      return { results: data };
    }

    case "get_vessel_history": {
      const { data, error } = await sb
        .from("service_orders")
        .select("id, service_order_number, status, scheduled_start_at, grand_total, created_at, problem_description, clients(name)")
        .eq("vessel_id", args.vessel_id)
        .order("created_at", { ascending: false })
        .limit(30);
      if (error) throw error;
      const mapped = (data || []).map((so: any) => ({
        numero: so.service_order_number,
        status: so.status,
        cliente: so.clients?.name || "—",
        problema: so.problem_description || "—",
        valor_total: so.grand_total || 0,
        agendado_para: so.scheduled_start_at || null,
        criado_em: so.created_at,
      }));
      return { history: mapped };
    }

    case "get_financial_dre": {
      const { year, month } = args;
      const start = new Date(year, month - 1, 1).toISOString();
      const end = new Date(year, month, 0, 23, 59, 59).toISOString();

      const { data: rec } = await admin.from("receivables").select("amount, cost_centers(name, type)").gte("due_date", start).lte("due_date", end);
      const { data: pay } = await admin.from("payables").select("amount, cost_centers(name, type)").gte("due_date", start).lte("due_date", end);

      const summary: Record<string, number> = {};
      let totalRevenue = 0;
      let totalExpense = 0;

      (rec || []).forEach((r: any) => {
        const cat = r.cost_centers?.name || "Outras Receitas";
        summary[cat] = (summary[cat] || 0) + Number(r.amount);
        totalRevenue += Number(r.amount);
      });

      (pay || []).forEach((p: any) => {
        const cat = p.cost_centers?.name || "Outras Despesas";
        summary[cat] = (summary[cat] || 0) - Number(p.amount);
        totalExpense += Number(p.amount);
      });

      return {
        periodo: `${month}/${year}`,
        receita_total: totalRevenue,
        despesa_total: totalExpense,
        lucro_liquido: totalRevenue - totalExpense,
        detalhamento: summary
      };
    }

    case "get_technician_commissions": {
      let query = admin.from("commissions").select("*, service_orders(service_order_number)");
      if (args.technician_id) query = query.eq("user_id", args.technician_id);
      if (args.status) query = query.eq("status", args.status);
      const { data, error } = await query;
      if (error) throw error;
      return { results: data };
    }

    case "get_os_profitability": {
      const { data: so, error } = await admin.from("service_orders").select("grand_total, labor_cost_total, parts_cost_total, travel_cost_total, operational_cost_total").eq("id", args.service_order_id).single();
      if (error) throw error;
      const revenue = Number(so.grand_total);
      const directCosts = Number(so.parts_cost_total) + Number(so.travel_cost_total) + Number(so.operational_cost_total);
      const grossProfit = revenue - directCosts;
      return {
        receita: revenue,
        custos_diretos: directCosts,
        lucro_bruto: grossProfit,
        margem: revenue > 0 ? (grossProfit / revenue) * 100 : 0
      };
    }

    case "adjust_inventory": {
      const { product_id, new_quantity, reason } = args;
      const { data: prod } = await admin.from("products").select("stock_quantity").eq("id", product_id).single();
      const delta = new_quantity - (prod?.stock_quantity || 0);
      
      const { error: updateErr } = await admin.from("products").update({ stock_quantity: new_quantity }).eq("id", product_id);
      if (updateErr) throw updateErr;

      await admin.from("inventory_movements").insert({
        product_id,
        quantity_delta: delta,
        movement_type: "manual_adjustment",
        notes: reason
      });

      return { ok: true, new_quantity };
    }

    case "propose_action": {
      // Read-only: apenas devolve o resumo. O frontend renderiza o card.
      return {
        proposed: true,
        action: args.action,
        title: args.title,
        summary_markdown: args.summary_markdown,
        payload: args.payload,
        instruction: "Aguardando confirmação do usuário no chat antes de prosseguir.",
      };
    }

    case "present_options": {
      // Read-only: sinaliza para o frontend renderizar botões clicáveis.
      return {
        options_ready: true,
        question: args.question,
        options: args.options,
        instruction: "Aguardando seleção do usuário.",
      };
    }

    case "create_agenda_task": {
      const { data, error } = await sb
        .from("agenda_tasks")
        .insert({ ...args, created_by: userId })
        .select()
        .single();
      if (error) throw error;
      return { ok: true, task: data };
    }

    case "update_agenda_task": {
      const { id, ...rest } = args;
      const { data, error } = await sb
        .from("agenda_tasks")
        .update(rest)
        .eq("id", id)
        .select()
        .single();
      if (error) throw error;
      return { ok: true, task: data };
    }

    case "create_service_order": {
      // Usa a sequência unificada document_number_seq via RPC next_document_number
      // Orçamentos (draft) recebem prefixo ORÇ-XXXXX; OS recebem OS-XXXXX
      const isQuote = !args.status || args.status === "draft";
      const prefix = isQuote ? "ORÇ" : "OS";
      let num: string;
      try {
        const { data: seqVal, error: seqErr } = await admin.rpc("next_document_number");
        if (seqErr || seqVal === null) throw new Error(seqErr?.message || "seq null");
        num = `${prefix}-${String(seqVal as number).padStart(5, "0")}`;
      } catch {
        // Fallback seguro: timestamp-based se a RPC falhar
        num = `${prefix}-${Date.now().toString().slice(-5)}`;
      }
      const { items, ...rest } = args;
      const { data, error } = await sb
        .from("service_orders")
        .insert({
          ...rest,
          service_order_number: num,
          status: rest.status || "draft",
          created_by: userId,
        })
        .select()
        .single();
      if (error) throw error;

      if (Array.isArray(items) && items.length > 0) {
        const partsRows = [];
        for (const it of items) {
          const { data: prod } = await sb
            .from("products")
            .select("cost_price, sale_price, cost_currency")
            .eq("id", it.product_id)
            .maybeSingle();
          if (!prod) continue;
          partsRows.push({
            service_order_id: data.id,
            product_id: it.product_id,
            quantity: it.quantity,
            unit_cost_snapshot: prod.cost_price || 0,
            unit_sale_snapshot: prod.sale_price || 0,
            currency_snapshot: prod.cost_currency || "BRL",
            line_total_cost: (prod.cost_price || 0) * it.quantity,
            line_total_sale: (prod.sale_price || 0) * it.quantity,
          });
        }
        if (partsRows.length) await sb.from("service_order_parts").insert(partsRows);
      }
      await sb.rpc("recalc_so_totals", { so_id: data.id }).catch(() => null);
      return { ok: true, service_order: data };
    }

    case "update_service_order_status": {
      // Quando transicionando de draft → non-draft, renomeia ORÇ-XXXXX → OS-XXXXX
      const { data: current } = await sb
        .from("service_orders")
        .select("status, service_order_number")
        .eq("id", args.id)
        .maybeSingle();

      const updatePayload: Record<string, any> = { status: args.status };
      if (args.cancellation_reason) updatePayload.cancellation_reason = args.cancellation_reason;

      if (current?.status === "draft" && args.status !== "draft") {
        // Gera novo número OS-XXXXX
        try {
          const { data: seqVal } = await admin.rpc("next_document_number");
          if (seqVal !== null) {
            updatePayload.service_order_number = `OS-${String(seqVal as number).padStart(5, "0")}`;
            updatePayload.converted_to_os_at = new Date().toISOString();
          }
        } catch { /* mantém número atual se RPC falhar */ }
      }

      const { data, error } = await sb
        .from("service_orders")
        .update(updatePayload)
        .eq("id", args.id)
        .select()
        .single();
      if (error) throw error;
      return { ok: true, service_order: data };
    }

    case "add_service_order_item": {
      const { data: prod } = await sb
        .from("products")
        .select("cost_price, sale_price, cost_currency")
        .eq("id", args.product_id)
        .maybeSingle();
      if (!prod) return { error: "Produto não encontrado" };
      const { data, error } = await sb
        .from("service_order_parts")
        .insert({
          service_order_id: args.service_order_id,
          product_id: args.product_id,
          quantity: args.quantity,
          unit_cost_snapshot: prod.cost_price || 0,
          unit_sale_snapshot: prod.sale_price || 0,
          currency_snapshot: prod.cost_currency || "BRL",
          line_total_cost: (prod.cost_price || 0) * args.quantity,
          line_total_sale: (prod.sale_price || 0) * args.quantity,
        })
        .select()
        .single();
      if (error) throw error;
      await sb.rpc("recalc_so_totals", { so_id: args.service_order_id || args.id }).catch(() => null);
      return { ok: true, part: data };
    }

    case "add_service_to_order": {
      const { data: svc } = args.service_id
        ? await sb.from("services").select("name, billing_unit, default_price").eq("id", args.service_id).maybeSingle()
        : { data: null };
      const qty = Number(args.quantity) || 1;
      const defaultHourlyRate = Number(settings.default_hourly_rate) || 0;
      const price = Number(args.unit_price) || svc?.default_price || defaultHourlyRate || 0;
      const { data, error } = await sb
        .from("service_order_services")
        .insert({
          service_order_id: args.service_order_id,
          service_id: args.service_id || null,
          name_snapshot: args.service_name || svc?.name || "",
          billing_unit_snapshot: args.billing_unit || svc?.billing_unit || "visit",
          quantity: qty,
          unit_price_snapshot: price,
          line_total: qty * price,
          notes: args.notes || null,
        })
        .select()
        .single();
      if (error) throw error;
      await sb.rpc("recalc_so_totals", { so_id: args.service_order_id }).catch(() => null);
      return { ok: true, service: data };
    }

    case "schedule_service_order": {
      const update: any = { scheduled_start_at: args.scheduled_start_at };
      if (args.scheduled_end_at) update.scheduled_end_at = args.scheduled_end_at;
      if (args.technician_user_id) update.status = "scheduled";
      const { data, error } = await sb
        .from("service_orders")
        .update(update)
        .eq("id", args.service_order_id)
        .select()
        .single();
      if (error) throw error;
      if (args.technician_user_id) {
        await sb.from("service_order_technicians")
          .upsert({ service_order_id: args.service_order_id, user_id: args.technician_user_id }, { onConflict: "service_order_id,user_id" })
          .catch(() => null);
      }
      return { ok: true, service_order: data };
    }

    case "optimize_text": {
      const contextLabels: Record<string, string> = {
        problem_description: "descrição de problema técnico em embarcação",
        service_notes: "observações de serviço técnico náutico",
        proposal: "proposta comercial de serviço náutico",
        observation: "observação técnica",
      };
      const label = contextLabels[args.context] || args.context;
      const optimizeRes = await callGeminiWithRetry({
        model: MODEL_SMART,
        messages: [
          {
            role: "system",
            content: `Você é um especialista em comunicação técnica náutica. Reescreva o texto a seguir como ${label}, mantendo as informações originais mas tornando-o mais claro, profissional e preciso. Responda APENAS com o texto reescrito, sem explicações.`,
          },
          { role: "user", content: args.text },
        ],
        tool_choice: "none",
      });
      const optimizeJson = await optimizeRes.json();
      const optimized = optimizeJson.choices?.[0]?.message?.content || args.text;
      return { original: args.text, optimized };
    }

    case "apply_service_order_discount": {
      const { data, error } = await sb
        .from("service_orders")
        .update({ discount_amount: args.discount_amount })
        .eq("id", args.id)
        .select()
        .single();
      if (error) throw error;
      await sb.rpc("recalc_so_totals", { so_id: args.service_order_id || args.id }).catch(() => null);
      return { ok: true, service_order: data };
    }

    case "create_client": {
      const { data, error } = await sb.from("clients").insert(args).select().single();
      if (error) throw error;
      return { ok: true, client: data };
    }

    case "create_vessel": {
      const { data, error } = await sb.from("vessels").insert(args).select().single();
      if (error) throw error;
      return { ok: true, vessel: data };
    }

    case "create_product": {
      const { data, error } = await sb.from("products").insert(args).select().single();
      if (error) throw error;
      return { ok: true, product: data };
    }

    case "create_purchase_order": {
      const { supplier_id, service_order_id, items, ...rest } = args;
      const { data: po, error } = await sb.from("purchase_orders").insert({
        ...rest,
        supplier_id,
        service_order_id,
        status: rest.status || "draft",
        created_by: userId
      }).select().single();
      if (error) throw error;
      if (Array.isArray(items) && items.length > 0) {
        await sb.from("purchase_order_items").insert(
          items.map((it: any) => ({ ...it, purchase_order_id: po.id }))
        );
      }
      return { ok: true, purchase_order: po };
    }

    // ===== WhatsApp =====
    case "send_whatsapp_message": {
      let phone = args.to_phone;
      if (!phone && args.client_id) {
        const { data: c } = await sb
          .from("clients")
          .select("whatsapp, phone")
          .eq("id", args.client_id)
          .maybeSingle();
        phone = c?.whatsapp || c?.phone;
      }
      if (!phone) return { error: "Telefone não fornecido nem encontrado para o cliente." };
      return await sendWhatsapp(phone, args.message, jwt);
    }

    case "send_collection_reminder": {
      const { data: col, error } = await sb
        .from("collections")
        .select("id, amount, due_date, contact_whatsapp, phone, contact_name, client_id, description")
        .eq("id", args.collection_id)
        .maybeSingle();
      if (error || !col) return { error: "Cobrança não encontrada" };
      let phone = col.contact_whatsapp || col.phone;
      if (!phone) {
        const { data: c } = await sb
          .from("clients")
          .select("whatsapp, phone")
          .eq("id", col.client_id)
          .maybeSingle();
        phone = c?.whatsapp || c?.phone;
      }
      if (!phone) return { error: "Sem telefone para enviar o lembrete." };
      const fmt = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(col.amount);
      const msg =
        args.custom_message ||
        `Olá${col.contact_name ? ` ${col.contact_name}` : ""}, lembrete amigável: você possui um valor de ${fmt} com vencimento em ${col.due_date}. Qualquer dúvida estamos à disposição.`;
      const r = await sendWhatsapp(phone, msg, jwt);
      if (r.ok) {
        await admin
          .from("collections")
          .update({ last_auto_sent_at: new Date().toISOString() })
          .eq("id", col.id);
      }
      return r;
    }

    case "send_service_order_link": {
      // Aceita UUID (campo id) OU número da OS (campo service_order_number)
      const isUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(args.service_order_id || ""));
      let soQuery = admin
        .from("service_orders")
        .select("id, service_order_number, share_token, client_id");
      if (isUUID) {
        soQuery = soQuery.eq("id", args.service_order_id);
      } else {
        // Aceita "OS-2026-XXXXX" ou "SO-2026-XXXXX"
        soQuery = soQuery.eq("service_order_number", args.service_order_id);
      }
      const { data: so, error: soErr } = await soQuery.maybeSingle();
      if (soErr || !so) return { error: `OS não encontrada. Verifique se o número ou ID está correto. Valor recebido: "${args.service_order_id}"` };
      if (!so.share_token) return { error: `A OS ${so.service_order_number} não possui link público ainda. Abra a OS no app, clique em "Compartilhar" para gerar o link, e tente novamente.` };
      const { data: c } = await admin
        .from("clients")
        .select("whatsapp, phone, name")
        .eq("id", so.client_id)
        .maybeSingle();
      const phone = c?.whatsapp || c?.phone;
      if (!phone) return { error: "Cliente sem WhatsApp/telefone cadastrado." };
      // Garante origem correta: usa settings.app_public_url como fallback
      const origin = appOrigin || settings.app_public_url || "https://hbrmarine.online";
      const link = `${origin}/view/${so.share_token}`;
      const msg =
        args.custom_message ||
        `Olá${c?.name ? ` ${c.name}` : ""}, segue o link da OS ${so.service_order_number}: ${link}`;
      return await sendWhatsapp(phone, msg, jwt);
    }

    // ===== WhatsApp Scheduling =====
    case "schedule_whatsapp_message": {
      let phone = args.phone;
      let clientId = args.client_id || null;

      if (!phone && clientId) {
        const { data: c } = await sb
          .from("clients")
          .select("whatsapp, phone")
          .eq("id", clientId)
          .maybeSingle();
        phone = c?.whatsapp || c?.phone;
      }
      if (!phone) return { error: "Telefone não informado. Forneça phone ou client_id." };

      // Resolve service_order_id se fornecido como número
      let soId: string | null = null;
      if (args.service_order_id) {
        const isUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(args.service_order_id));
        if (isUUID) {
          soId = args.service_order_id;
        } else {
          const { data: so } = await admin
            .from("service_orders")
            .select("id")
            .eq("service_order_number", args.service_order_id)
            .maybeSingle();
          soId = so?.id || null;
        }
      }

      const scheduledAt = new Date(args.scheduled_at).toISOString();
      const sendMode = args.send_mode || (soId ? "link" : "text");
      const recurrenceType = args.recurrence_type || "once";

      const { data: created, error: insErr } = await admin
        .from("whatsapp_scheduled_sends")
        .insert({
          phone: String(phone).replace(/\D/g, ""),
          message: args.message,
          scheduled_at: scheduledAt,
          next_run_at: scheduledAt,
          recurrence_type: recurrenceType,
          send_mode: sendMode,
          target_kind: soId ? "service_order" : "manual",
          service_order_id: soId,
          client_id: clientId,
          status: "pending",
          created_by: userId,
          auto_retry: true,
          max_attempts: 3,
        })
        .select()
        .single();

      if (insErr) return { error: insErr.message };
      return {
        ok: true,
        scheduled_id: created.id,
        phone: created.phone,
        scheduled_at: created.scheduled_at,
        recurrence_type: created.recurrence_type,
        message_preview: created.message.slice(0, 100),
      };
    }

    case "list_scheduled_whatsapp": {
      const status = args.status || "pending";
      const limit = Math.min(Number(args.limit) || 10, 30);

      let q = admin
        .from("whatsapp_scheduled_sends")
        .select("id, phone, message, status, next_run_at, recurrence_type, send_mode, last_error, client_id")
        .order("next_run_at", { ascending: true })
        .limit(limit);

      if (status !== "all") q = q.eq("status", status);

      const { data, error } = await q;
      if (error) return { error: error.message };
      return { results: data, count: data?.length ?? 0 };
    }

    case "cancel_scheduled_whatsapp": {
      const { error } = await admin
        .from("whatsapp_scheduled_sends")
        .update({ status: "cancelled" })
        .eq("id", args.scheduled_id);
      if (error) return { error: error.message };
      return { ok: true, cancelled_id: args.scheduled_id };
    }

    case "add_material_to_order": {
      // Insere material livre (sem product_id do catálogo) como linha de serviço tipo 'unit'
      const qty = Number(args.quantity) || 1;
      const price = Number(args.unit_price) || 0;
      const { data, error } = await sb
        .from("service_order_services")
        .insert({
          service_order_id: args.service_order_id,
          service_id: null,
          name_snapshot: args.name,
          billing_unit_snapshot: "unit",
          quantity: qty,
          unit_price_snapshot: price,
          line_total: qty * price,
          notes: args.notes || null,
        })
        .select()
        .single();
      if (error) throw error;
      await sb.rpc("recalc_so_totals", { so_id: args.service_order_id }).catch(() => null);
      return { ok: true, material_item: data };
    }

    case "get_os_receivables": {
      const soId = args.service_order_id;
      // Busca recebíveis ativos (não cancelados)
      const { data: recs, error: recErr } = await sb
        .from("receivables")
        .select("id, description, amount, due_date, status, payment_method, is_deposit")
        .eq("service_order_id", soId)
        .neq("status", "cancelled")
        .order("due_date", { ascending: true });
      if (recErr) throw recErr;

      // Busca pagamentos confirmados via join
      const recIds = (recs || []).map((r: any) => r.id);
      let payments: any[] = [];
      if (recIds.length > 0) {
        const { data: pays } = await sb
          .from("payments")
          .select("id, receivable_id, amount, payment_date, payment_method, notes")
          .in("receivable_id", recIds)
          .eq("status", "confirmed")
          .order("payment_date", { ascending: false });
        payments = pays || [];
      }

      // Totais resumidos
      const totalCharged = (recs || []).reduce((s: number, r: any) => s + Number(r.amount), 0);
      const totalPaid = payments.reduce((s: number, p: any) => s + Number(p.amount), 0);

      const statusMap: Record<string, string> = {
        pending: "Pendente", partial: "Parcialmente pago", paid: "Pago", overdue: "Vencido", cancelled: "Cancelado"
      };

      return {
        total_cobrado: totalCharged,
        total_pago: totalPaid,
        saldo_aberto: totalCharged - totalPaid,
        recebíveis: (recs || []).map((r: any) => ({
          id: r.id,
          descricao: r.description,
          valor: r.amount,
          vencimento: r.due_date,
          status: statusMap[r.status] || r.status,
          is_sinal: r.is_deposit,
        })),
        pagamentos: payments.map((p: any) => ({
          valor: p.amount,
          data: p.payment_date,
          forma: p.payment_method,
          obs: p.notes,
        })),
      };
    }

    default:
      return { error: `Tool desconhecida: ${name}` };
  }
}

async function sendWhatsapp(phone: string, message: string, jwt: string) {
  // Usa whatsapp-send (não whatsapp-send-text) para respeitar test_mode e test_number do app_settings
  const r = await fetch(`${SUPABASE_URL}/functions/v1/whatsapp-send`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${jwt}`,
      apikey: ANON,
    },
    body: JSON.stringify({ phone, message, kind: "text" }),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) return { error: (data as any).error || `HTTP ${r.status}` };
  return { ok: true, messageId: (data as any).messageId };
}

// ---------------- HANDLER ----------------
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    if (!GEMINI_API_KEY) return jr({ error: "GEMINI_API_KEY não configurada no Supabase" }, 500);

    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return jr({ error: "Não autenticado" }, 401);

    const sb = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const { data: userData, error: userErr } = await sb.auth.getUser(jwt);
    if (userErr || !userData?.user?.id) return jr({ error: "Não autenticado" }, 401);
    const userId = userData.user.id;

    const { data: userProfile } = await sb.from("app_users").select("role, full_name").eq("id", userId).maybeSingle();
    const userRole = userProfile?.role || "unknown";
    const userName = userProfile?.full_name || "Usuário";

    const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // ---- Carrega TODAS as configuracoes do sistema uma unica vez ----
    const { data: settingsRows } = await admin.from("app_settings").select("key, value");
    const settings: Record<string, string> = {};
    (settingsRows || []).forEach((r: any) => { if (r.key) settings[r.key] = String(r.value ?? ""); });

    const body = await req.json().catch(() => ({}));
    const incoming = Array.isArray(body.messages) ? body.messages : [];
    const context = body.context || {};
    const isSalesCopy = body.is_sales_copy === true;

    // ---------- MODO SALES COPY (sem tools, foco em copy persuasiva para WhatsApp) ----------
    if (isSalesCopy) {
      const salesPrompt = `Você é um Copywriter de Vendas Náuticas especialista do MarineFlow, atuando para um prestador de serviços de elétrica e eletrônica embarcada de alto padrão.

OBJETIVO:
- Gerar mensagens de WhatsApp persuasivas, humanas e diretas para prospecção e relacionamento com proprietários de embarcações, marinas e estaleiros.

ESTILO:
- Tom profissional, próximo, sem ser bajulador. Cordial, confiante e consultivo.
- Português brasileiro natural, evite anglicismos desnecessários.
- Frases curtas. Quebra de linha entre ideias. Use 1 ou 2 emojis no máximo, com bom gosto (⚓ ⚡ 🛥️).
- Nunca soe genérico ou robótico. Personalize quando houver contexto (nome, embarcação, marina, problema).
- Foque em benefício concreto (segurança elétrica, autonomia, evitar pane no mar, valorização do barco).
- CTA claro no final (responder, agendar visita, enviar foto do painel, etc.).

REGRAS:
- NUNCA invente dados que não foram fornecidos.
- NUNCA inclua links suspeitos ou promessas mirabolantes.
- Não use markdown pesado — WhatsApp aceita *negrito* simples e quebras de linha.
- Tamanho ideal: 4 a 8 linhas. Nunca ultrapasse 12 linhas.
- Não inclua assinatura institucional a menos que solicitado.

Responda APENAS com o texto da mensagem pronta para envio, sem explicações ou comentários adicionais.`;

      const salesMessages: any[] = [{ role: "system", content: salesPrompt }, ...incoming];

      const aiRes = await callGeminiWithRetry({
        model: MODEL_SMART,
        messages: salesMessages,
      });

      if (aiRes.status === 429) {
        const t = await aiRes.text();
        let msg = "Limite de requisições atingido.";
        try {
          const j = JSON.parse(t);
          msg = j.error?.message || t;
        } catch { msg = t; }
        return jr({ error: `IA Limite (429): ${msg}` }, 429);
      }
      if (aiRes.status === 402) return jr({ error: "Créditos da IA esgotados." }, 402);
      if (!aiRes.ok) {
        const t = await aiRes.text();
        console.error("AI gateway sales error:", aiRes.status, t);
        return jr({ error: "Erro no gateway de IA" }, 500);
      }
      const aiJson = await aiRes.json();
      const content = aiJson.choices?.[0]?.message?.content || "";
      return jr({ message: { role: "assistant", content }, tool_events: [] });
    }

    const appOrigin =
      req.headers.get("origin") ||
      req.headers.get("referer")?.replace(/\/$/, "") ||
      "";

    const today = new Date();
    const now = today;
    const dateStr = now.toLocaleDateString('pt-BR', {
      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
    });
    const timeStr = now.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
    
    let systemPrompt = "";
    if (isSalesCopy) {
      systemPrompt = `Hoje é ${dateStr}, ${timeStr} (horário de Brasília).\n\nVocê é um Copywriter Especialista em Vendas focado no mercado náutico. Seu objetivo é escrever mensagens curtas, extremamente persuasivas e educadas para serem enviadas pelo WhatsApp a clientes finais de uma oficina/marina.
      
REGRAS:
- A mensagem vai DIRETAMENTE para o cliente final. NÃO fale sobre o sistema, ERP ou sobre você ser uma IA.
- Seja amigável, direto e use gatilhos mentais (escassez, urgência, reciprocidade) de forma sutil.
- Fale como se você fosse o próprio dono/gerente do negócio abordando o cliente.
- NUNCA use marcadores de markdown pesados (asteriscos duplos, etc) pois no WhatsApp puro pode ficar estranho. Use formatação simples.
- Limite a mensagem a no máximo 3 parágrafos curtos.
- Seja caloroso!
`;
    } else {
      systemPrompt = `Hoje é ${dateStr}, ${timeStr} (horário de Brasília).

Você é o assistente do MarineFlow ERP. Responda em português, formate em markdown.

════════════════════════════════════════
⚠️ REGRA ABSOLUTA — INVIOLÁVEL:
Após qualquer busca retornar MAIS DE UM resultado, você TEM PROIBIÇÃO TOTAL de escrever texto com os resultados. A ÚNICA ação permitida é chamar 'present_options' imediatamente com os UUIDs reais. ZERO EXCEÇÕES.
════════════════════════════════════════

REGRAS CRÍTICAS:
- Antes de QUALQUER escrita (criar, atualizar) ou envio de WhatsApp → chame 'propose_action' primeiro.
- Só execute a tool real APÓS o usuário confirmar.
- Tools de leitura (search_*, list_*, get_*) → use livremente, sem pedir confirmação.
- NUNCA peça IDs ao usuário — descubra via search_*.
- NUNCA crie uma nova OS/orçamento sem pedido explícito do usuário.

════ ORÇAMENTOS vs ORDENS DE SERVIÇO ════

O sistema distingue dois tipos de documento:

| Tipo       | Status   | Número    | Página no app      |
|------------|----------|-----------|--------------------|
| Orçamento  | draft    | ORÇ-XXXXX | /quotes            |
| Ordem de Serviço | qualquer outro | OS-XXXXX | /service-orders |

- Ao criar → sempre começa como orçamento (draft, número ORÇ-XXXXX).
- Ao aprovar um orçamento (draft → outro status) → o sistema gera automaticamente um novo número OS-XXXXX.
- Quando o usuário diz "orçamento" → use is_quote=true em list_service_orders.
- Quando diz "OS" ou "ordem de serviço" → use is_quote=false.
- Quando diz "enviar orçamento ORÇ-00001" → use esse número em send_service_order_link.

════ ATIVOS/EMBARCAÇÕES ════

O campo "vessel" suporta QUALQUER tipo de ativo, não apenas embarcações náuticas:
- Lancha, Veleiro, Jet Ski, Catamarã (asset_type marítimo)
- Camper, Motorhome, Trailer (asset_type terrestre)
- O campo "name" representa o nome/identificação do ativo do cliente (embarcação, motorhome, etc.).

Fluxo quando o ativo não existe ainda:
  1. search_vessels(query, client_id) → se não encontrar →
  2. propose_action para create_vessel (name=nome do ativo, asset_type=tipo, model=modelo, manufacturer=fabricante) →
  3. Após criar o ativo → criar o orçamento/OS com vessel_id retornado.

════ FLUXO DE CRIAÇÃO DE ORÇAMENTO ════

1. search_clients(nome do cliente)
   → 0 encontrado: propose_action para create_client
   → 1 encontrado: usar diretamente
   → 2-5: present_options
   → 6+: present_options com 5 melhores + opção Refinar

2. search_vessels(query, client_id)
   → não encontrado: propose_action para create_vessel
   → encontrado: usar

3. propose_action mostrando TUDO que será criado (resumo completo)

4. Após confirmação → executar na ordem:
   a. create_service_order(client_id, vessel_id, status='draft', problem_description, extra_notes se houver observações contratuais, payment_conditions se houver)
   b. Para cada SERVIÇO/MÃO DE OBRA → add_service_to_order(service_order_id, service_name, unit_price, notes=detalhamento, billing_unit='unit'|'hour'|'visit')
   c. Para MATERIAIS SEM CATÁLOGO (estimativas, conjuntos de insumos) → add_material_to_order(service_order_id, name, unit_price, notes=detalhamento)
   d. Para PRODUTOS DO CATÁLOGO → search_products primeiro → add_service_order_item(service_order_id, product_id, quantity)

5. Confirmar: "✅ Orçamento **ORÇ-XXXXX** criado com sucesso para [cliente] / [ativo]."

CAMPO extra_notes: Use para observações que devem aparecer no PDF ao cliente (condições, ressalvas, validade, avisos sobre estimativas). É diferente de internal_notes (que o cliente não vê).

════ FLUXO DE ENVIO ════

1. Se não houver OS em contexto → list_service_orders(client_id, is_quote=true) para orçamentos
2. Se 1 resultado → propose_action direto. Se vários → present_options com "ORÇ-XXXXX / OS-XXXXX — R$ valor — Status"
3. Após confirmação → send_service_order_link
4. Confirmar: "✅ Orçamento enviado para [cliente] via WhatsApp. O cliente receberá um link para visualizar e baixar o PDF online."
5. NUNCA diga que enviou PDF em anexo — o sistema envia um link.

════ FINANCEIRO ════

O sistema possui módulo financeiro completo:
- **Recebíveis** (receivables): valores a cobrar vinculados a OSs
- **Pagamentos** (payments): registros de pagamentos contra recebíveis
- **Pagáveis** (payables): despesas/contas a pagar
- **payment_status** na OS: null | 'pending' | 'partial' | 'paid'

Para verificar situação financeira de uma OS → use get_os_receivables(service_order_id).
Para listar OSs com pagamentos pendentes → list_service_orders(is_quote=false) e observe campo status_pagamento.

Recebíveis são criados automaticamente quando uma OS é aprovada (saí de 'draft').
Sinal/depósito: recebível com is_deposit=true.

════ AGENDAMENTO DE WHATSAPP ════

"Agendar mensagem", "mandar amanhã", "lembrete no dia X" → use schedule_whatsapp_message.
- Sempre propose_action antes.
- Sem hora especificada → assume 09:00 do dia solicitado.
- Após agendar: "✅ Mensagem agendada para [data/hora]."
- ⚠️ Se modo de teste ativo → mensagem redirecionada para número de teste.
- Para listar/cancelar → list_scheduled_whatsapp / cancel_scheduled_whatsapp.

════ DESAMBIGUAÇÃO — FLUXO OBRIGATÓRIO ════

1. Busque SEMPRE antes de perguntar.
2. 1 resultado → use diretamente, informe qual usou.
3. 2-5 resultados → present_options com label rico (nome + telefone/cidade) + UUID como value.
4. 6+ resultados → present_options com os 5 melhores + {label:"🔍 Refinar busca",value:"__refine__"}. Informe total: "Encontrei 12 clientes. Escolha ou refine:"
5. 0 resultados → informe + present_options com opção criar novo.
6. __refine__ escolhido → peça mais detalhes (sobrenome, telefone, CNPJ, cidade).
7. Pergunta sim/não → present_options([{label:"Sim",value:"sim"},{label:"Não",value:"nao"}]).

ERRADO ❌: "Encontrei João Silva e João Pereira. Qual você quer?"
CORRETO ✅: present_options("Qual João?", [{label:"João Silva — (47) 99999-0000",value:"uuid-1"},{label:"João Pereira — RJ",value:"uuid-2"}])

════ QUALIDADE DAS RESPOSTAS ════

- NUNCA exiba UUIDs ao usuário.
- Datas: "28 de abril de 2026 às 09:00".
- Valores: "R$ 1.500,00".
- Status traduzidos: draft=Orçamento, open=Aberto, pending=Pendente, approved=Aprovado, scheduled=Agendado, in_progress=Em andamento, waiting_parts=Aguardando peças, waiting_approval=Aguardando aprovação, completed=Concluído, cancelled=Cancelado, invoiced=Faturado, reopened=Reaberto.
- Use listas markdown para múltiplos itens. Respostas concisas.

════ CONFIGURAÇÕES DA EMPRESA ════
- Empresa: ${settings.company_name || "HBR Marine"}
- Valor hora mão de obra: R$ ${settings.default_hourly_rate || "0"}/h (referência quando não há preço definido)
- Margem de lucro padrão: ${settings.default_profit_margin || "30"}% (alerte ADMIN se OS estiver abaixo de 20%)
- Comissão padrão: ${settings.default_commission_rate || "0"}%
- ISS: ${settings.iss_rate_pct || "5"}% (aplica sobre serviços — Simples Nacional, Itajaí/SC)
- Deslocamento: R$ ${settings.travel_km_rate || "1.10"}/km | 1 técnico: R$ ${settings.travel_hourly_1 || "90"}/h | 2 técnicos: R$ ${settings.travel_hourly_2 || "170"}/h | 3 técnicos: R$ ${settings.travel_hourly_3 || "250"}/h
- Multiplicadores: urgência ${settings.travel_urgency_mult || "1.5"}x | FDS/feriado ${settings.travel_weekend_mult || "1.3"}x
- Chave PIX: ${settings.pix_key || "não configurada"}
- Banco: ${settings.bank_name || ""} Ag: ${settings.bank_agency || ""} Cc: ${settings.bank_account || ""}

════ CONTEXTO ATUAL ════
- Data/hora: ${today.toISOString()} (${today.toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })})
- Usuário logado: ${userName} | Cargo: ${userRole.toUpperCase()}
- Rota atual: ${context.route || "desconhecida"}
- Entidade em contexto: ${context.entityType || "nenhuma"} ${context.entityId ? `(id: ${context.entityId})` : ""}

════ PERMISSÕES ════
- TECHNICIAN: apenas dúvidas técnicas, agendamentos, visualizar OS e inserir dados operacionais. PROIBIDO acessar preços, financeiro, produtos ou configurações.
- ADMIN: acesso irrestrito.
- O banco de dados impõe RLS — operações não permitidas falharão no backend.

PROATIVIDADE:
- Cliente sem OS recente ou orçamentos parados em draft → sugira follow-up.
- OS com margem < 20% → alerte ADMIN discretamente.
- "este cliente", "esta OS", "este barco" → use o ID em contexto se compatível.`;
    }

    const messages: any[] = [{ role: "system", content: systemPrompt }, ...incoming];

    let toolEvents: any[] = [];

    for (let iter = 0; iter < MAX_ITERATIONS; iter++) {
      // Detecta se é consulta simples (usa modelo rápido) ou ação complexa (usa modelo inteligente)
      const lastUserMsg = messages.filter((m: any) => m.role === "user").pop()?.content || "";
      // Usa sempre o modelo inteligente — o Flash ignorava instruções de present_options
      // e escrevia listas em texto em vez de chamar a tool. Pro garante maior fidelidade.
      const modelToUse = MODEL_SMART;

      const aiRes = await callGeminiWithRetry({
        model: modelToUse,
        messages,
        tools: isSalesCopy ? undefined : TOOLS,
        tool_choice: isSalesCopy ? undefined : "auto",
      });

      if (aiRes.status === 429) {
        const t = await aiRes.text();
        let msg = "Limite de requisições atingido.";
        try {
          const j = JSON.parse(t);
          msg = j.error?.message || t;
        } catch { msg = t; }
        return jr({ error: `IA Limite (429): ${msg}` }, 429);
      }
      if (aiRes.status === 402) return jr({ error: "Créditos da IA esgotados. Adicione créditos em Settings > Workspace > Usage." }, 402);
      if (!aiRes.ok) {
        const t = await aiRes.text();
        console.error("AI gateway error:", aiRes.status, t);
        let errorMsg = `Erro no gateway de IA (${aiRes.status})`;
        try {
          const errJson = JSON.parse(t);
          errorMsg = errJson.error?.message || t;
        } catch {
          errorMsg = t;
        }
        return jr({ error: `IA Falhou: ${errorMsg}` }, aiRes.status);
      }

      const aiJson = await aiRes.json();
      const choice = aiJson.choices?.[0];
      const aiMsg = choice?.message;
      if (!aiMsg) return jr({ error: "Resposta vazia do modelo" }, 500);

      messages.push(aiMsg);

      const toolCalls = aiMsg.tool_calls || [];
      if (toolCalls.length === 0) {
        return jr({
          message: { role: "assistant", content: aiMsg.content || "" },
          tool_events: toolEvents,
        });
      }

      // Executa cada tool call
      for (const tc of toolCalls) {
        const fnName = tc.function?.name;
        let fnArgs: any = {};
        try {
          fnArgs = JSON.parse(tc.function?.arguments || "{}");
        } catch {
          fnArgs = {};
        }

        let result: any;
        try {
          result = await executeTool(fnName, fnArgs, { sb, admin, userId, jwt, appOrigin, settings });
        } catch (e: any) {
          result = { error: e?.message || "Falha na execução da tool" };
        }

        toolEvents.push({ name: fnName, args: fnArgs, result });

        messages.push({
          role: "tool",
          tool_call_id: tc.id,
          content: JSON.stringify(result),
        });

        // ── AUTO-DISAMBIGUATION ──────────────────────────────────────────────
        // Se a busca retornou múltiplos resultados, o LOOP gera os botões
        // diretamente — sem depender do modelo chamar present_options.
        const autoDisambig: Record<string, {
          question: (q: string, total: number) => string;
          label: (item: any) => string;
          value: (item: any) => string;
        }> = {
          search_clients: {
            question: (q, n) => n > 5
              ? `Encontrei ${n} clientes para "${q}". Escolha ou refine:`
              : `Qual cliente chamado "${q}"?`,
            label: (c) => {
              const parts = [c.name];
              const contact = c.whatsapp || c.phone || c.email || c.cpf_cnpj || c.city;
              if (contact) parts.push(contact);
              return parts.join(" — ");
            },
            value: (c) => c.id,
          },
          search_vessels: {
            question: (q, n) => n > 5
              ? `Encontrei ${n} embarcações para "${q}". Escolha ou refine:`
              : `Qual embarcação chamada "${q}"?`,
            label: (v) => [v.name, v.model, v.year].filter(Boolean).join(" · "),
            value: (v) => v.id,
          },
          search_products: {
            question: (q, n) => n > 5
              ? `Encontrei ${n} produtos para "${q}". Escolha ou refine:`
              : `Qual produto para "${q}"?`,
            label: (p) => `${p.name}${p.sale_price ? ` — R$ ${Number(p.sale_price).toFixed(2)}` : ""}`,
            value: (p) => p.id,
          },
          list_service_orders: {
            question: (_q, n) => n > 5
              ? `Encontrei ${n} ordens de serviço. Escolha ou refine:`
              : "Qual ordem de serviço?",
            label: (so) => `${so.numero} — R$ ${Number(so.valor_total || 0).toFixed(2)} — ${so.status}${so.embarcacao && so.embarcacao !== "—" ? ` · ${so.embarcacao}` : ""}`,
            value: (so) => so.id,
          },
        };

        if (autoDisambig[fnName]) {
          const items: any[] = result?.results ?? [];
          if (items.length > 1) {
            const cfg = autoDisambig[fnName];
            const searchQuery = fnArgs.query || fnArgs.client_id || "";
            const top5 = items.slice(0, 5);
            const options = top5.map((item: any) => ({
              label: cfg.label(item).slice(0, 60),
              value: cfg.value(item),
            }));
            if (items.length > 5) {
              options.push({ label: "🔍 Refinar busca — digitar mais detalhes", value: "__refine__" });
            }
            const question = cfg.question(searchQuery, items.length);
            return jr({
              message: { role: "assistant", content: `Encontrei ${items.length} resultado(s). Selecione:` },
              options: { question, options },
              tool_events: toolEvents,
              updated_messages: messages.slice(1),
            });
          }
        }
        // ── FIM AUTO-DISAMBIGUATION ──────────────────────────────────────────

        // Se foi propose_action, retorna IMEDIATAMENTE para o frontend renderizar o card
        if (fnName === "propose_action") {
          return jr({
            message: { role: "assistant", content: aiMsg.content || "" },
            proposal: {
              action: fnArgs.action,
              title: fnArgs.title,
              summary_markdown: fnArgs.summary_markdown,
              payload: fnArgs.payload,
            },
            tool_events: toolEvents,
            updated_messages: messages.slice(1), // remove system
          });
        }

        // Se foi present_options, retorna IMEDIATAMENTE para o frontend renderizar os botões
        if (fnName === "present_options") {
          return jr({
            message: { role: "assistant", content: aiMsg.content || "" },
            options: {
              question: fnArgs.question,
              options: fnArgs.options,
            },
            tool_events: toolEvents,
            updated_messages: messages.slice(1), // remove system
          });
        }
      }
    }

    return jr({ error: "Limite de iterações de tool-calling atingido" }, 500);
  } catch (e: any) {
    console.error("ai-agent error", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});
