// Edge Function: ai-agent
// Agente de IA com function calling — Google Gemini API (OpenAI-compatible endpoint).
// Recebe { messages, context } e roda loop de tool-calling até resposta final.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  fetchAIWithRetry,
  resolveOverloadUserMessage,
  resolveRateLimitUserMessage,
} from "../_shared/ai-error.ts";
import { tryFastPathResponse } from "./deterministic-intents.ts";

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
const MODEL_FAST = Deno.env.get("GEMINI_MODEL_FAST") || Deno.env.get("GEMINI_MODEL") || "gemini-2.5-flash";
const MODEL_SMART = Deno.env.get("GEMINI_MODEL_SMART") || Deno.env.get("GEMINI_MODEL") || "gemini-2.5-flash";
const MAX_ITERATIONS = 8;

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
      description: "Lista ordens de serviço com filtros opcionais.",
      parameters: {
        type: "object",
        properties: {
          status: { type: "string" },
          client_id: { type: "string" },
          vessel_id: { type: "string" },
          limit: { type: "number" },
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
      description: "Calcula ou lista as comissões de um técnico. O campo technician_id refere-se ao id do app_users (mesma coluna usada em list_technicians).",
      parameters: {
        type: "object",
        properties: {
          technician_id: { type: "string", description: "UUID do técnico (app_users.id)." },
          status: { type: "string", enum: ["pending", "paid", "cancelled"] },
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
      description: "AÇÃO CRÍTICA — ajuste manual de estoque com privilégio elevado (service_role, bypassa RLS). Define a quantidade absoluta do produto e registra um inventory_movement do tipo 'manual_adjustment'. OBRIGATÓRIO chamar propose_action ANTES com summary_markdown explicitando: produto, quantidade ANTES, quantidade DEPOIS, delta (diferença) e razão detalhada. NUNCA executar sem confirmação humana explícita.",
      parameters: {
        type: "object",
        properties: {
          product_id: { type: "string", description: "UUID do produto (products.id)." },
          new_quantity: { type: "number", description: "Nova quantidade ABSOLUTA (não é delta). O movement_delta é calculado automaticamente como new_quantity - stock_atual." },
          reason: { type: "string", description: "Razão detalhada do ajuste — será registrada em inventory_movements.notes para auditoria." },
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
      description: "Cria uma nova OS (use status='draft' para orçamento).",
      parameters: {
        type: "object",
        properties: {
          client_id: { type: "string" },
          vessel_id: { type: "string" },
          status: { type: "string" },
          problem_description: { type: "string" },
          scheduled_start_at: { type: "string" },
          items: {
            type: "array",
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
      description: "Altera o status de uma OS.",
      parameters: {
        type: "object",
        properties: {
          id: { type: "string" },
          status: {
            type: "string",
            // Alinhado ao CHECK constraint service_orders_status_check.
            enum: ["draft", "open", "scheduled", "in_progress", "awaiting_parts", "awaiting_client", "approved", "completed", "invoiced", "cancelled"],
          },
        },
        required: ["id", "status"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "add_product_to_order",
      description: "Adiciona UM ÚNICO produto/peça do catálogo a uma OS. Para MÚLTIPLOS produtos (listas, tabelas, vários equipamentos de uma vez) use add_products_to_order.",
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
      name: "add_products_to_order",
      description:
        "Adiciona MÚLTIPLOS produtos/peças/equipamentos a uma OS de uma única vez. Use para listas de produtos, tabelas, ou qualquer caso com mais de 1 produto. Aceita product_id OU product_name (busca no catálogo). Recalcula totais uma única vez no final.",
      parameters: {
        type: "object",
        properties: {
          service_order_id: { type: "string" },
          products: {
            type: "array",
            description: "Lista de produtos a adicionar",
            items: {
              type: "object",
              properties: {
                product_id: { type: "string", description: "UUID do produto (se já conhecido)" },
                product_name: { type: "string", description: "Nome do produto para busca no catálogo (se product_id não disponível)" },
                quantity: { type: "number", default: 1 },
                unit_price: { type: "number", description: "Preço de venda unitário (opcional — usa sale_price do catálogo se omitido)" },
              },
            },
            minItems: 1,
          },
        },
        required: ["service_order_id", "products"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "add_service_to_order",
      description: "Adiciona UM ÚNICO serviço de mão de obra a uma OS. Para múltiplos serviços (listas, tabelas) use add_services_to_order.",
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
      name: "add_services_to_order",
      description:
        "Adiciona MÚLTIPLOS serviços de mão de obra a uma OS de uma única vez. Use para listas, tabelas markdown, textos colados de WhatsApp/Excel ou qualquer caso onde o usuário enviar mais de um par 'descrição + valor'. Cada item vira uma linha separada. Recalcula totais uma única vez no final.",
      parameters: {
        type: "object",
        properties: {
          service_order_id: { type: "string" },
          services: {
            type: "array",
            description: "Array de serviços a adicionar (cada item = uma linha separada)",
            items: {
              type: "object",
              properties: {
                service_name: { type: "string", description: "Nome/descrição do serviço (preserve textos longos)" },
                service_id: { type: "string", description: "ID do serviço cadastrado (opcional)" },
                description: { type: "string", description: "Descrição adicional (opcional)" },
                quantity: { type: "number", default: 1 },
                unit_price: { type: "number" },
                billing_unit: { type: "string", enum: ["hour", "visit", "day", "unit"] },
                notes: { type: "string" },
              },
              required: ["service_name", "unit_price"],
            },
            minItems: 1,
          },
        },
        required: ["service_order_id", "services"],
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
          full_name_or_company_name: { type: "string" },
          type: { type: "string", enum: ["individual", "company"] },
          phone: { type: "string" },
          whatsapp: { type: "string" },
          email: { type: "string" },
          cpf_cnpj: { type: "string" },
        },
        required: ["full_name_or_company_name", "type"],
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
          boat_name: { type: "string", description: "Nome da embarcação ou identificação do motorhome" },
          manufacturer: { type: "string" },
          model: { type: "string" },
          year: { type: "number" },
          asset_type: { type: "string", description: "Exemplo: Lancha, Veleiro, Motorhome, Camper, Jet Ski" },
          marina_id: { type: "string" },
        },
        required: ["client_id", "boat_name", "asset_type"],
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
          product_name: { type: "string" },
          sku: { type: "string" },
          sale_price: { type: "number" },
          cost_price: { type: "number" },
          unit: { type: "string" },
        },
        required: ["product_name"],
      },
    },
  },

  // ====== WHATSAPP ======
  {
    type: "function",
    function: {
      name: "send_whatsapp_message",
      description:
        "Envia mensagem de WhatsApp via Z-API. Forneça to_phone OU client_id (busca o WhatsApp/telefone do cliente).",
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
        "Envia o link público de uma OS/orçamento por WhatsApp. Use sempre que o usuário pedir 'enviar orçamento', 'mandar OS', 'enviar para o cliente' etc. O campo service_order_id aceita TANTO o UUID (campo 'id' do list_service_orders) QUANTO o número da OS (campo 'numero', ex: 'OS-2026-152542'). Prefira sempre o UUID.",
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
  // ====== MEMORY ======
  {
    type: "function",
    function: {
      name: "search_memory",
      description: "Busca memórias persistentes sobre clientes, embarcações ou padrões de negócio. Use SEMPRE que iniciar uma conversa sobre um cliente ou embarcação específico. Retorna fatos aprendidos em interações anteriores: preferências, histórico relevante, padrões recorrentes.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "Termos de busca — nome do cliente, embarcação, tipo de problema, etc." },
          entity_id: { type: "string", description: "UUID do cliente, embarcação ou OS para filtrar memórias específicas." },
          scope: { type: "string", enum: ["global", "client", "vessel", "service_order", "operator", "all"], description: "Escopo. Padrão: all." },
          limit: { type: "number", description: "Máximo de resultados. Padrão: 10." },
        },
        required: ["query"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "save_memory",
      description: "Salva um fato importante na memória persistente. Use quando aprender algo relevante sobre um cliente ou embarcação: preferências de contato, problemas recorrentes, equipamentos instalados, histórico significativo, decisões do cliente. Evite duplicar memórias já existentes — verifique com search_memory primeiro.",
      parameters: {
        type: "object",
        properties: {
          scope: { type: "string", enum: ["global", "client", "vessel", "service_order", "operator"], description: "Escopo da memória." },
          entity_id: { type: "string", description: "UUID do cliente, embarcação ou OS relacionado (se aplicável)." },
          entity_name: { type: "string", description: "Nome legível da entidade (ex: nome do cliente, nome da embarcação) — facilita buscas futuras." },
          memory_key: { type: "string", description: "Tipo ou categoria do fato (ex: 'preferencia_contato', 'problema_recorrente', 'equipamento_instalado', 'observacao_cliente'). Use snake_case descritivo." },
          memory_value: { type: "string", description: "Conteúdo do fato a ser lembrado. Seja específico e completo." },
          confidence: { type: "string", enum: ["high", "medium", "low"], description: "Confiança no fato. Padrão: high." },
        },
        required: ["scope", "memory_key", "memory_value"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "get_business_alerts",
      description: "Retorna alertas de negócio ativos: OSs paradas, recebíveis vencidos, orçamentos sem faturamento, etc. Use quando o usuário perguntar sobre 'o que precisa de atenção', 'alertas', 'pendências', 'o que está parado', 'resumo do negócio' ou ao iniciar uma conversa proativamente.",
      parameters: {
        type: "object",
        properties: {
          severity: { type: "string", enum: ["critical", "warning", "info", "all"], description: "Filtrar por severidade. Padrão: all." },
          alert_type: { type: "string", description: "Filtrar por tipo específico (ex: os_awaiting_client_long, receivable_overdue, os_no_technician)." },
          limit: { type: "number", description: "Máximo de alertas. Padrão: 20." },
        },
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

// ---------------- HELPERS ----------------

/**
 * Whitelist + alias normalizer para payloads de create_*.
 * Evita que o modelo envie chaves inexistentes ao schema (que causam erro genérico do PostgREST).
 * - `allowed`: lista exata de colunas aceitas na tabela alvo.
 * - `aliases`: mapeia chaves comuns que o modelo costuma inferir (ex: "name") para a chave real ("full_name_or_company_name").
 * Valores vazios (undefined/null/"") são removidos. Retorna também as chaves descartadas, para que a tool possa avisar.
 */
function pickAllowed(
  args: Record<string, any> | null | undefined,
  allowed: string[],
  aliases: Record<string, string> = {}
): { payload: Record<string, any>; dropped: string[] } {
  const payload: Record<string, any> = {};
  const dropped: string[] = [];
  for (const [rawKey, rawVal] of Object.entries(args || {})) {
    if (rawVal === undefined || rawVal === null || rawVal === "") continue;
    const targetKey = aliases[rawKey] ?? rawKey;
    if (allowed.includes(targetKey)) {
      // Se o alias colide com um valor já presente pela chave real, mantém o real (não sobrescreve).
      if (payload[targetKey] === undefined) payload[targetKey] = rawVal;
    } else {
      dropped.push(rawKey);
    }
  }
  return { payload, dropped };
}

/**
 * Gera próximo po_number sequencial no formato PO-YYYY-NNNN.
 * Replica EXATAMENTE generatePONumber() do hook real (src/hooks/use-purchase-orders.ts:50-63).
 */
async function generatePONumber(sb: any): Promise<string> {
  const year = new Date().getFullYear();
  const { data } = await sb
    .from("purchase_orders")
    .select("po_number")
    .order("created_at", { ascending: false })
    .limit(1);
  let seq = 1;
  if (data?.[0]?.po_number) {
    const match = String(data[0].po_number).match(/(\d+)$/);
    if (match) seq = parseInt(match[1], 10) + 1;
  }
  return `PO-${year}-${String(seq).padStart(4, "0")}`;
}

/**
 * Recalcula totais da OS (labor_cost_total, parts_cost_total, labor_hours_total, grand_total)
 * Replica EXATAMENTE a lógica do frontend em src/hooks/use-service-orders.ts:284-327
 * para garantir paridade entre escrita manual e escrita via IA.
 *
 * IMPORTANTE: usa `sb` (cliente JWT do usuário). Se RLS bloquear, propaga o erro —
 * NÃO faz fallback silencioso para service_role.
 */
async function recalcSoTotals(sb: any, soId: string): Promise<void> {
  const [partsRes, servicesRes, teRes, soRes] = await Promise.all([
    sb.from("service_order_parts").select("line_total_sale").eq("service_order_id", soId),
    sb.from("service_order_services").select("line_total").eq("service_order_id", soId),
    sb.from("time_entries").select("duration_minutes, billable").eq("service_order_id", soId),
    sb
      .from("service_orders")
      .select(
        "travel_cost_total, subcontract_cost_total, discount_amount, tax_amount, operational_cost_total"
      )
      .eq("id", soId)
      .single(),
  ]);

  const parts = partsRes.data || [];
  const serviceLines = servicesRes.data || [];
  const te = teRes.data || [];
  const so = soRes.data || {};

  const partsCost = parts.reduce(
    (s: number, p: any) => s + (Number(p.line_total_sale) || 0),
    0
  );
  const laborCost = serviceLines.reduce(
    (s: number, l: any) => s + (Number(l.line_total) || 0),
    0
  );
  const billableMinutes = te
    .filter((e: any) => e.billable)
    .reduce((s: number, e: any) => s + (Number(e.duration_minutes) || 0), 0);
  const laborHours = Math.round((billableMinutes / 60) * 100) / 100;

  const grand =
    laborCost +
    partsCost +
    (Number(so.travel_cost_total) || 0) +
    (Number(so.operational_cost_total) || 0) +
    (Number(so.subcontract_cost_total) || 0) -
    (Number(so.discount_amount) || 0) +
    (Number(so.tax_amount) || 0);

  const { error } = await sb
    .from("service_orders")
    .update({
      parts_cost_total: Math.round(partsCost * 100) / 100,
      labor_hours_total: laborHours,
      labor_cost_total: Math.round(laborCost * 100) / 100,
      grand_total: Math.round(grand * 100) / 100,
    })
    .eq("id", soId);
  if (error) throw error;
}

/**
 * Insere uma linha em service_order_services com os mesmos campos e cálculo
 * do fluxo manual (src/hooks/use-service-orders.ts:530-561).
 * NÃO chama recalcSoTotals — o caller decide quando recalcular.
 */
async function addServiceOrderServiceLine(
  sb: any,
  params: {
    service_order_id: string;
    service_name: string;
    service_id?: string | null;
    description?: string | null;
    quantity?: number;
    unit_price: number;
    billing_unit?: string;
    notes?: string | null;
  },
  settings: Record<string, string>
): Promise<{ id: string; data: any }> {
  let svc: any = null;
  if (params.service_id) {
    const { data } = await sb
      .from("services")
      .select("service_name, billing_unit, default_price")
      .eq("id", params.service_id)
      .maybeSingle();
    svc = data;
  }

  const qty = Number(params.quantity) || 1;
  const defaultHourlyRate = Number(settings.default_hourly_rate) || 0;
  const price = Number(params.unit_price) || Number(svc?.default_price) || defaultHourlyRate || 0;
  const lineTotal = Math.round(qty * price * 100) / 100;

  const { data, error } = await sb
    .from("service_order_services")
    .insert({
      service_order_id: params.service_order_id,
      service_id: params.service_id || null,
      service_name_snapshot: params.service_name || svc?.service_name || "",
      description_snapshot: params.description || null,
      billing_unit_snapshot: params.billing_unit || svc?.billing_unit || "visit",
      quantity: qty,
      unit_price_snapshot: price,
      line_total: lineTotal,
      notes: params.notes || null,
    })
    .select()
    .single();
  if (error) throw error;
  return { id: data.id, data };
}

// Trims conversation history before sending to the AI provider.
// Caps at maxMessages to reduce token consumption.
// Ensures the result starts with a clean turn (not an orphaned tool result).
function trimConversationHistory(msgs: any[], maxMessages: number): any[] {
  if (msgs.length <= maxMessages) return msgs;
  let trimmed = msgs.slice(msgs.length - maxMessages);
  while (
    trimmed.length > 0 &&
    (trimmed[0].role === "tool" ||
      (trimmed[0].role === "assistant" &&
        Array.isArray(trimmed[0].tool_calls) &&
        trimmed[0].tool_calls.length > 0))
  ) {
    trimmed = trimmed.slice(1);
  }
  return trimmed;
}

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
        .select("id, full_name_or_company_name, type, phone, whatsapp, email, cpf_cnpj")
        .or(
          `full_name_or_company_name.ilike.%${q}%,email.ilike.%${q}%,phone.ilike.%${q}%,whatsapp.ilike.%${q}%,cpf_cnpj.ilike.%${q}%`
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
        .select("id, boat_name, manufacturer, model, year, client_id, marina_id")
        .eq("active", true)
        .or(`boat_name.ilike.%${q}%,model.ilike.%${q}%,manufacturer.ilike.%${q}%`)
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
        .select("id, product_name, sku, brand, sale_price, stock_quantity, unit")
        .eq("active", true)
        .or(`product_name.ilike.%${q}%,sku.ilike.%${q}%,brand.ilike.%${q}%`)
        .limit(limit);
      if (error) throw error;
      return { results: data };
    }

    case "list_agenda": {
      let query = sb
        .from("agenda_tasks")
        .select("id, title, scheduled_start_at, scheduled_end_at, status, priority, location, clients(full_name_or_company_name), app_users(full_name)")
        .gte("scheduled_start_at", args.date_from)
        .lte("scheduled_start_at", args.date_to)
        .order("scheduled_start_at", { ascending: true });
      if (args.technician_id) query = query.eq("technician_user_id", args.technician_id);
      const { data, error } = await query;
      if (error) throw error;
      const mapped = (data || []).map((t: any) => ({
        id: t.id,
        titulo: t.title,
        cliente: t.clients?.full_name_or_company_name || "—",
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
        .select("id, service_order_number, status, grand_total, scheduled_start_at, created_at, clients(full_name_or_company_name), vessels(boat_name)")
        .order("created_at", { ascending: false })
        .limit(Math.min(Number(args.limit) || 20, 50));
      if (args.status) {
        // Mapa alinhado ao CHECK constraint real:
        // service_orders_status_check IN
        //   ('draft','scheduled','open','in_progress','awaiting_parts','awaiting_client',
        //    'approved','completed','invoiced','cancelled')
        const STATUS_PT_EN: Record<string, string> = {
          "rascunho": "draft", "draft": "draft",
          "aberta": "open", "aberto": "open", "em aberto": "open", "open": "open",
          "agendada": "scheduled", "agendado": "scheduled", "scheduled": "scheduled",
          "em andamento": "in_progress", "em execução": "in_progress", "em execucao": "in_progress", "in_progress": "in_progress",
          "aguardando peças": "awaiting_parts", "aguardando pecas": "awaiting_parts", "awaiting_parts": "awaiting_parts",
          "aguardando cliente": "awaiting_client", "aguardando aprovação": "awaiting_client", "aguardando aprovacao": "awaiting_client", "awaiting_client": "awaiting_client",
          "aprovada": "approved", "aprovado": "approved", "approved": "approved",
          "concluída": "completed", "concluida": "completed", "concluído": "completed", "concluido": "completed", "completed": "completed",
          "faturada": "invoiced", "faturado": "invoiced", "invoiced": "invoiced",
          "cancelada": "cancelled", "cancelado": "cancelled", "cancelled": "cancelled",
        };
        const mappedStatus = STATUS_PT_EN[args.status.toLowerCase().trim()] ?? args.status;
        query = query.eq("status", mappedStatus);
      }
      if (args.client_id) query = query.eq("client_id", args.client_id);
      if (args.vessel_id) query = query.eq("vessel_id", args.vessel_id);
      const { data, error } = await query;
      if (error) throw error;
      const mapped = (data || []).map((so: any) => ({
        id: so.id,
        numero: so.service_order_number,
        status: so.status,
        cliente: so.clients?.full_name_or_company_name || "—",
        embarcacao: so.vessels?.boat_name || "—",
        valor_total: so.grand_total || 0,
        agendado_para: so.scheduled_start_at || null,
        criado_em: so.created_at,
      }));
      return { results: mapped };
    }

    case "get_service_order": {
      const { data: so, error } = await sb
        .from("service_orders")
        .select("*, clients(full_name_or_company_name), vessels(boat_name)")
        .eq("id", args.id)
        .maybeSingle();
      if (error) throw error;
      if (!so) return { error: "OS não encontrada" };
      const { data: parts } = await sb
        .from("service_order_parts")
        .select("id, quantity, line_total_sale, products(product_name)")
        .eq("service_order_id", args.id);
      const { data: services } = await sb
        .from("service_order_services")
        .select("id, service_name_snapshot, quantity, unit_price_snapshot, line_total")
        .eq("service_order_id", args.id);
      
      return { 
        service_order: {
          ...so,
          cliente: so.clients?.full_name_or_company_name || "—",
          embarcacao: so.vessels?.boat_name || "—"
        }, 
        parts: (parts || []).map((p: any) => ({
          produto: p.products?.product_name || "Desconhecido",
          quantidade: p.quantity,
          total: p.line_total_sale
        })), 
        services: (services || []).map((s: any) => ({
          servico: s.service_name_snapshot,
          quantidade: s.quantity,
          preco_unitario: s.unit_price_snapshot,
          total: s.line_total
        }))
      };
    }

    case "get_client_history": {
      const { data, error } = await sb
        .from("service_orders")
        .select("id, service_order_number, status, scheduled_start_at, grand_total, created_at, vessels(boat_name)")
        .eq("client_id", args.client_id)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      const mapped = (data || []).map((so: any) => ({
        numero: so.service_order_number,
        status: so.status,
        embarcacao: so.vessels?.boat_name || "—",
        valor_total: so.grand_total || 0,
        agendado_para: so.scheduled_start_at || null,
        criado_em: so.created_at,
      }));
      return { history: mapped };
    }

    case "list_pending_collections": {
      // CHECK constraint real: ['pending','sent','viewed','paid','overdue','disputed','cancelled'].
      // 'scheduled' não existe. "Pendente operacionalmente" = ainda não paga e não cancelada.
      let query = sb
        .from("collections")
        .select("id, client_id, due_date, amount, status, contact_name, contact_whatsapp, description")
        .in("status", ["pending", "sent", "viewed", "overdue", "disputed"])
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
        .select("id, service_name, description, billing_unit, default_price")
        .eq("active", true)
        .or(`service_name.ilike.%${q}%,description.ilike.%${q}%`)
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
        .select("id, marina_name, city, state")
        .eq("active", true)
        .order("marina_name")
        .limit(20);
      if (q) query = query.ilike("marina_name", `%${q}%`);
      const { data, error } = await query;
      if (error) throw error;
      return { results: data };
    }

    case "get_vessel_history": {
      const { data, error } = await sb
        .from("service_orders")
        .select("id, service_order_number, status, scheduled_start_at, grand_total, created_at, problem_description, clients(full_name_or_company_name)")
        .eq("vessel_id", args.vessel_id)
        .order("created_at", { ascending: false })
        .limit(30);
      if (error) throw error;
      const mapped = (data || []).map((so: any) => ({
        numero: so.service_order_number,
        status: so.status,
        cliente: so.clients?.full_name_or_company_name || "—",
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
      // Schema real: commissions.user_id (FK -> app_users.id). NÃO existe `technician_user_id`.
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
      // Gera número sequencial da OS no formato SO-YYYY-NNNNN
      const year = new Date().getFullYear();
      const { data: lastSO } = await sb
        .from("service_orders")
        .select("service_order_number")
        .like("service_order_number", `SO-${year}-%`)
        .order("service_order_number", { ascending: false })
        .limit(1)
        .maybeSingle();
      let seq = 1;
      if (lastSO?.service_order_number) {
        const match = lastSO.service_order_number.match(/(\d+)$/);
        if (match) seq = parseInt(match[1], 10) + 1;
      }
      const num = `SO-${year}-${String(seq).padStart(5, "0")}`;
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
      try {
        await recalcSoTotals(sb, data.id);
      } catch (recalcErr: any) {
        console.error("[ai-agent] recalcSoTotals failed after create_service_order:", recalcErr?.message);
        return { ok: false, error: `OS criada mas falha ao recalcular totais: ${recalcErr?.message || recalcErr}`, service_order: data };
      }
      return { ok: true, service_order: data };
    }

    case "update_service_order_status": {
      const { data, error } = await sb
        .from("service_orders")
        .update({ status: args.status })
        .eq("id", args.id)
        .select()
        .single();
      if (error) throw error;
      return { ok: true, service_order: data };
    }

    case "add_product_to_order":
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
      try {
        await recalcSoTotals(sb, args.service_order_id);
      } catch (recalcErr: any) {
        console.error("[ai-agent] recalcSoTotals failed after add_service_order_item:", recalcErr?.message);
        return { ok: false, error: `Item inserido mas falha ao recalcular totais: ${recalcErr?.message || recalcErr}`, part: data };
      }
      return { ok: true, part: data };
    }

    case "add_products_to_order": {
      if (!args.service_order_id) return { ok: false, error: "service_order_id é obrigatório" };
      const items: any[] = Array.isArray(args.products) ? args.products : [];
      if (items.length === 0) return { ok: false, error: "Array 'products' vazio ou ausente" };

      const created: Array<{ product_id: string; product_name: string; quantity: number; line_total: number }> = [];
      const failed: Array<{ index: number; product_name: string; error: string; candidates?: Array<{ id: string; product_name: string; sale_price: number | null }> }> = [];
      let totalAdded = 0;

      for (let i = 0; i < items.length; i++) {
        const it = items[i] || {};
        let productId: string | null = it.product_id || null;
        let productName: string = it.product_name || "";
        let prod: any = null;

        if (productId) {
          const { data } = await sb
            .from("products")
            .select("id, product_name, cost_price, sale_price, cost_currency")
            .eq("id", productId)
            .maybeSingle();
          prod = data;
          if (!prod) {
            failed.push({ index: i, product_name: productName || productId, error: "Produto não encontrado por ID" });
            continue;
          }
          productName = prod.product_name;
        } else if (productName) {
          const selectCols = "id, product_name, cost_price, sale_price, cost_currency";
          let productCandidates: Array<{ id: string; product_name: string; sale_price: number | null }> | null = null;

          // Pass 1: full name ilike
          const { data: r1 } = await sb.from("products").select(selectCols)
            .ilike("product_name", `%${productName}%`).limit(3);
          if (r1 && r1.length === 1) {
            prod = r1[0];
          } else if (r1 && r1.length > 1) {
            productCandidates = r1.map((c: any) => ({ id: c.id, product_name: c.product_name, sale_price: c.sale_price ?? null }));
          }

          // Pass 2: multi-term AND search — strips parens/stop-words, AND-chains each token
          if (!prod && !productCandidates) {
            const TRIVIAL = new Set(["de","do","da","dos","das","e","em","no","na","para","com","o","a","os","as"]);
            const terms = productName
              .replace(/\([^)]*\)/g, "")
              .split(/[\s/\-]+/)
              .filter((w: string) => w.length > 3 && !TRIVIAL.has(w.toLowerCase()))
              .slice(0, 3);
            if (terms.length > 0) {
              let qk: any = sb.from("products").select(selectCols);
              for (const t of terms) qk = qk.ilike("product_name", `%${t}%`);
              const { data: r2 } = await qk.limit(5);
              if (r2 && r2.length === 1) {
                prod = r2[0];
              } else if (r2 && r2.length > 1) {
                productCandidates = r2.map((c: any) => ({ id: c.id, product_name: c.product_name, sale_price: c.sale_price ?? null }));
              }
            }
          }

          if (prod) {
            productId = prod.id;
            productName = prod.product_name;
          } else if (productCandidates) {
            failed.push({
              index: i,
              product_name: productName,
              error: `"${productName}" não encontrado exatamente — ${productCandidates.length} produto(s) similar(es) encontrado(s) no catálogo`,
              candidates: productCandidates,
            });
            continue;
          } else {
            failed.push({ index: i, product_name: productName, error: `Produto "${productName}" não encontrado no catálogo` });
            continue;
          }
        } else {
          failed.push({ index: i, product_name: "(sem nome)", error: "product_id ou product_name é obrigatório" });
          continue;
        }

        const quantity = Number(it.quantity) || 1;
        const costPrice = prod.cost_price || 0;
        const salePrice = it.unit_price !== undefined && it.unit_price !== null
          ? Number(it.unit_price)
          : (prod.sale_price || 0);

        try {
          const { data, error: insertErr } = await sb
            .from("service_order_parts")
            .insert({
              service_order_id: args.service_order_id,
              product_id: productId,
              quantity,
              unit_cost_snapshot: costPrice,
              unit_sale_snapshot: salePrice,
              currency_snapshot: prod.cost_currency || "BRL",
              line_total_cost: costPrice * quantity,
              line_total_sale: salePrice * quantity,
            })
            .select()
            .single();
          if (insertErr) throw insertErr;
          created.push({ product_id: productId!, product_name: productName, quantity, line_total: salePrice * quantity });
          totalAdded += salePrice * quantity;
        } catch (e: any) {
          console.error(`[ai-agent] add_products_to_order item ${i} failed:`, e?.message);
          failed.push({ index: i, product_name: productName, error: e?.message || "Falha ao inserir" });
        }
      }

      if (created.length > 0) {
        try {
          await recalcSoTotals(sb, args.service_order_id);
        } catch (recalcErr: any) {
          console.error("[ai-agent] recalcSoTotals failed after add_products_to_order:", recalcErr?.message);
        }
      }

      const created_count = created.length;
      const failed_count = failed.length;
      return {
        ok: failed_count === 0,
        created_count,
        failed_count,
        created,
        failed,
        total_added: Math.round(totalAdded * 100) / 100,
        ...(failed_count > 0 ? { warning: `${failed_count} produto(s) não inserido(s) — verifique os nomes no catálogo` } : {}),
      };
    }

    case "add_service_to_order": {
      if (!args.service_order_id) return { ok: false, error: "service_order_id é obrigatório" };
      if (!args.service_name) return { ok: false, error: "service_name é obrigatório" };
      try {
        const { data } = await addServiceOrderServiceLine(
          sb,
          {
            service_order_id: args.service_order_id,
            service_name: args.service_name,
            service_id: args.service_id || null,
            quantity: args.quantity,
            unit_price: args.unit_price,
            billing_unit: args.billing_unit,
            notes: args.notes,
          },
          settings
        );
        try {
          await recalcSoTotals(sb, args.service_order_id);
        } catch (recalcErr: any) {
          console.error("[ai-agent] recalcSoTotals failed after add_service_to_order:", recalcErr?.message);
          return {
            ok: false,
            error: `Serviço inserido mas falha ao recalcular totais: ${recalcErr?.message || recalcErr}`,
            service: data,
          };
        }
        return { ok: true, service: data, created_count: 1, failed_count: 0 };
      } catch (e: any) {
        console.error("[ai-agent] add_service_to_order failed:", e?.message);
        return { ok: false, error: e?.message || "Falha ao inserir serviço" };
      }
    }

    case "add_services_to_order": {
      if (!args.service_order_id) return { ok: false, error: "service_order_id é obrigatório" };
      const items: any[] = Array.isArray(args.services) ? args.services : [];
      if (items.length === 0) return { ok: false, error: "Array 'services' vazio ou ausente" };

      const created: Array<{ id: string; service_name: string; line_total: number }> = [];
      const failed: Array<{ index: number; service_name: string; error: string }> = [];
      let totalAdded = 0;

      for (let i = 0; i < items.length; i++) {
        const it = items[i] || {};
        const name = String(it.service_name || "").trim();
        if (!name) {
          failed.push({ index: i, service_name: "(vazio)", error: "service_name vazio" });
          continue;
        }
        if (it.unit_price === undefined || it.unit_price === null) {
          failed.push({ index: i, service_name: name, error: "unit_price obrigatório" });
          continue;
        }
        try {
          const { id, data } = await addServiceOrderServiceLine(
            sb,
            {
              service_order_id: args.service_order_id,
              service_name: name,
              service_id: it.service_id || null,
              description: it.description || null,
              quantity: it.quantity,
              unit_price: it.unit_price,
              billing_unit: it.billing_unit,
              notes: it.notes,
            },
            settings
          );
          created.push({ id, service_name: name, line_total: Number(data.line_total) || 0 });
          totalAdded += Number(data.line_total) || 0;
        } catch (e: any) {
          console.error(`[ai-agent] add_services_to_order item ${i} failed:`, e?.message);
          failed.push({ index: i, service_name: name, error: e?.message || "Falha no insert" });
        }
      }

      let recalcError: string | null = null;
      if (created.length > 0) {
        try {
          await recalcSoTotals(sb, args.service_order_id);
        } catch (recalcErr: any) {
          console.error("[ai-agent] recalcSoTotals failed after add_services_to_order:", recalcErr?.message);
          recalcError = recalcErr?.message || String(recalcErr);
        }
      }

      const created_count = created.length;
      const failed_count = failed.length;
      const ok = failed_count === 0 && recalcError === null;
      const result: any = {
        ok,
        created_count,
        failed_count,
        created,
        failed,
        total_added: Math.round(totalAdded * 100) / 100,
      };
      if (recalcError) {
        result.error = `Linhas inseridas (${created_count}) mas recalcSoTotals falhou: ${recalcError}`;
      } else if (failed_count > 0 && created_count === 0) {
        result.error = `Nenhum serviço foi inserido. Falhas: ${failed.map((f) => f.service_name + ': ' + f.error).join('; ')}`;
      }
      return result;
    }

    case "schedule_service_order": {
      // Schema real: service_order_technicians (service_order_id uuid, user_id uuid)
      // PK: (service_order_id, user_id). FK user_id -> app_users(id).
      // 1) Validar técnico em app_users ANTES de qualquer escrita.
      if (args.technician_user_id) {
        const { data: tech } = await sb
          .from("app_users")
          .select("id, full_name, active")
          .eq("id", args.technician_user_id)
          .maybeSingle();
        if (!tech) {
          return {
            ok: false,
            error: `Técnico ${args.technician_user_id} não encontrado em app_users. Use list_technicians para obter um ID válido.`,
          };
        }
        if (tech.active === false) {
          return {
            ok: false,
            error: `Técnico ${tech.full_name || args.technician_user_id} está inativo. Escolha outro técnico ativo via list_technicians.`,
          };
        }
      }

      const update: any = { scheduled_start_at: args.scheduled_start_at };
      if (args.scheduled_end_at) update.scheduled_end_at = args.scheduled_end_at;
      if (args.technician_user_id) {
        // Só avança para "scheduled" se o status atual não é terminal (completed/invoiced/cancelled)
        const { data: cur } = await sb.from("service_orders").select("status").eq("id", args.service_order_id).maybeSingle();
        const TERMINAL = new Set(["completed", "invoiced", "cancelled"]);
        if (!cur?.status || !TERMINAL.has(cur.status)) update.status = "scheduled";
      }
      const { data, error } = await sb
        .from("service_orders")
        .update(update)
        .eq("id", args.service_order_id)
        .select()
        .single();
      if (error) throw error;

      if (args.technician_user_id) {
        // Coluna real é `user_id` (NÃO `technician_user_id`). Espelha o fluxo manual do app.
        // Erro NÃO é silenciado — propaga ao chamador como sucesso parcial.
        const { error: techErr } = await sb
          .from("service_order_technicians")
          .upsert(
            { service_order_id: args.service_order_id, user_id: args.technician_user_id },
            { onConflict: "service_order_id,user_id" }
          );
        if (techErr) {
          return {
            ok: false,
            error: `OS agendada mas falha ao vincular técnico: ${techErr.message}`,
            service_order: data,
          };
        }
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
      const optimizeResult = await fetchAIWithRetry(
        `${GEMINI_BASE_URL}/chat/completions`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${GEMINI_API_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model: MODEL_SMART,
            messages: [
              {
                role: "system",
                content: `Você é um especialista em comunicação técnica náutica. Reescreva o texto a seguir como ${label}, mantendo as informações originais mas tornando-o mais claro, profissional e preciso. Responda APENAS com o texto reescrito, sem explicações.`,
              },
              { role: "user", content: args.text },
            ],
            tool_choice: "none",
          }),
        },
        { maxRetries: 1, fallbackModel: MODEL_FAST }
      );
      if (!optimizeResult.ok) {
        return { original: args.text, optimized: args.text };
      }
      const optimizeJson = await optimizeResult.response.json();
      const optimized = optimizeJson.choices?.[0]?.message?.content || args.text;
      return { original: args.text, optimized };
    }

    case "apply_service_order_discount": {
      const soId = args.id || args.service_order_id;
      if (!soId) return { ok: false, error: "id (UUID da OS) é obrigatório" };
      const { data, error } = await sb
        .from("service_orders")
        .update({ discount_amount: args.discount_amount })
        .eq("id", soId)
        .select()
        .single();
      if (error) throw error;
      try {
        await recalcSoTotals(sb, soId);
      } catch (recalcErr: any) {
        console.error("[ai-agent] recalcSoTotals failed after apply_service_order_discount:", recalcErr?.message);
        return { ok: false, error: `Desconto aplicado mas falha ao recalcular totais: ${recalcErr?.message || recalcErr}`, service_order: data };
      }
      return { ok: true, service_order: data };
    }

    case "create_client": {
      // Whitelist alinhada ao schema real (public.clients).
      const allowed = [
        "type", "full_name_or_company_name", "cpf_cnpj", "phone", "whatsapp", "email",
        "address_line_1", "address_line_2", "city", "state", "postal_code", "country",
        "notes", "active",
      ];
      const aliases: Record<string, string> = {
        name: "full_name_or_company_name",
        full_name: "full_name_or_company_name",
        company_name: "full_name_or_company_name",
        nome: "full_name_or_company_name",
        razao_social: "full_name_or_company_name",
        cpf: "cpf_cnpj",
        cnpj: "cpf_cnpj",
        address: "address_line_1",
        endereco: "address_line_1",
        cidade: "city",
        estado: "state",
        cep: "postal_code",
        observacoes: "notes",
      };
      const { payload, dropped } = pickAllowed(args, allowed, aliases);
      // Normaliza `type` (CHECK constraint: 'individual' | 'company').
      const typeMap: Record<string, string> = {
        pf: "individual", pessoa_fisica: "individual", fisica: "individual",
        física: "individual", individual: "individual", individuo: "individual",
        pj: "company", pessoa_juridica: "company", juridica: "company",
        jurídica: "company", company: "company", empresa: "company",
      };
      if (payload.type) {
        const mapped = typeMap[String(payload.type).toLowerCase().trim()];
        if (mapped) payload.type = mapped;
      }
      if (!payload.full_name_or_company_name) {
        return { ok: false, error: "Campo obrigatório ausente: full_name_or_company_name (ou alias: name, nome, company_name, razao_social)." };
      }
      if (!payload.type || !["individual", "company"].includes(payload.type)) {
        return { ok: false, error: "Campo obrigatório ausente/inválido: type. Valores aceitos: 'individual' ou 'company'." };
      }
      const { data, error } = await sb.from("clients").insert(payload).select().single();
      if (error) return { ok: false, error: error.message };
      return { ok: true, client: data, ignored_fields: dropped.length ? dropped : undefined };
    }

    case "create_vessel": {
      // Whitelist alinhada ao schema real (public.vessels).
      const allowed = [
        "client_id", "marina_id", "boat_name", "manufacturer", "model", "year",
        "hull_id_or_registration", "length_feet", "beam_feet", "draft_feet",
        "engine_type", "engine_brand", "engine_model", "engine_quantity",
        "propulsion_type", "shore_power_type", "battery_bank_summary",
        "inverter_charger_summary", "navigation_electronics_summary",
        "electrical_system_notes", "current_marina_name_snapshot",
        "current_dock_position", "active", "asset_type",
      ];
      const aliases: Record<string, string> = {
        name: "boat_name",
        vessel_name: "boat_name",
        nome: "boat_name",
        brand: "manufacturer",
        fabricante: "manufacturer",
        ano: "year",
        marina: "marina_id",
        tipo: "asset_type",
        type: "asset_type",
      };
      const { payload, dropped } = pickAllowed(args, allowed, aliases);
      if (!payload.client_id) return { ok: false, error: "Campo obrigatório ausente: client_id." };
      if (!payload.boat_name) return { ok: false, error: "Campo obrigatório ausente: boat_name (ou alias: name, vessel_name, nome)." };
      if (!payload.asset_type) return { ok: false, error: "Campo obrigatório ausente: asset_type. Exemplos: 'Lancha', 'Veleiro', 'Catamarã', 'Motorhome', 'Camper', 'Trailer', 'Jet Ski'." };
      const { data, error } = await sb.from("vessels").insert(payload).select().single();
      if (error) return { ok: false, error: error.message };
      return { ok: true, vessel: data, ignored_fields: dropped.length ? dropped : undefined };
    }

    case "create_product": {
      // Whitelist alinhada ao schema real (public.products).
      const allowed = [
        "sku", "product_name", "category", "brand", "unit",
        "cost_price", "sale_price", "cost_currency", "sale_currency",
        "stock_quantity", "minimum_stock", "location_bin", "barcode", "notes", "active",
        "ncm", "csosn", "fiscal_origin", "icms_rate", "ipi_rate", "pis_rate", "cofins_rate",
        "commission_rate", "profit_margin", "use_global_fiscal", "product_category_id",
        "is_commissionable", "image_url", "fiscal_complete", "default_warranty_days",
        "supplier_id",
      ];
      const aliases: Record<string, string> = {
        name: "product_name",
        nome: "product_name",
        marca: "brand",
        price: "sale_price",
        preco: "sale_price",
        cost: "cost_price",
        custo: "cost_price",
        stock: "stock_quantity",
        estoque: "stock_quantity",
        unidade: "unit",
        categoria: "category",
      };
      const { payload, dropped } = pickAllowed(args, allowed, aliases);
      if (!payload.product_name) return { ok: false, error: "Campo obrigatório ausente: product_name (ou alias: name, nome)." };
      const { data, error } = await sb.from("products").insert(payload).select().single();
      if (error) return { ok: false, error: error.message };
      return { ok: true, product: data, ignored_fields: dropped.length ? dropped : undefined };
    }

    case "create_purchase_order": {
      // Schema: purchase_orders.po_number TEXT NOT NULL UNIQUE — precisa ser gerado
      // (espelha src/hooks/use-purchase-orders.ts:generatePONumber).
      const { items, ...rest } = args;
      const poNumber = await generatePONumber(sb);
      // purchase_orders.created_by é TEXT DEFAULT 'sistema' — passamos userId (UUID em texto),
      // mantém comportamento atual da tool.
      const poAllowed = [
        "po_number", "status", "supplier_id", "service_order_id",
        "expected_date", "received_date", "notes", "total_amount", "created_by",
      ];
      const { payload: poPayload } = pickAllowed(
        { ...rest, po_number: poNumber, status: rest.status || "draft", created_by: userId },
        poAllowed
      );
      const { data: po, error } = await sb
        .from("purchase_orders")
        .insert(poPayload)
        .select()
        .single();
      if (error) {
        return { ok: false, error: `Falha ao criar purchase_order: ${error.message}` };
      }
      if (Array.isArray(items) && items.length > 0) {
        // Whitelist por item — schema: product_id, description, quantity, unit_cost, received_qty.
        const itemAllowed = ["product_id", "description", "quantity", "unit_cost", "received_qty"];
        const itemsPayload = items.map((it: any) => {
          const { payload } = pickAllowed(it, itemAllowed);
          return { ...payload, purchase_order_id: po.id };
        });
        const { error: itemsErr } = await sb.from("purchase_order_items").insert(itemsPayload);
        if (itemsErr) {
          return {
            ok: false,
            error: `Purchase order criada (${poNumber}) mas falha ao inserir itens: ${itemsErr.message}`,
            purchase_order: po,
          };
        }
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
        .select("id, amount, due_date, contact_whatsapp, contact_phone, contact_name, client_id, description")
        .eq("id", args.collection_id)
        .maybeSingle();
      if (error || !col) return { error: "Cobrança não encontrada" };
      let phone = col.contact_whatsapp || col.contact_phone;
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
        .select("whatsapp, phone, full_name_or_company_name")
        .eq("id", so.client_id)
        .maybeSingle();
      const phone = c?.whatsapp || c?.phone;
      if (!phone) return { error: "Cliente sem WhatsApp/telefone cadastrado." };
      // Garante origem correta: usa settings.app_public_url como fallback
      const origin = appOrigin || settings.app_public_url || "https://hbrmarine.online";
      const link = `${origin}/view/${so.share_token}`;
      const msg =
        args.custom_message ||
        `Olá${c?.full_name_or_company_name ? ` ${c.full_name_or_company_name}` : ""}, segue o link da OS ${so.service_order_number}: ${link}`;
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

    case "search_memory": {
      const q = String(args.query || "").trim();
      const limit = Math.min(Number(args.limit) || 10, 30);
      let dbq = admin
        .from("ai_agent_memory")
        .select("id, scope, entity_id, entity_name, memory_key, memory_value, confidence, created_at, updated_at")
        .order("updated_at", { ascending: false })
        .limit(limit);
      if (args.entity_id) dbq = (dbq as any).eq("entity_id", args.entity_id);
      if (args.scope && args.scope !== "all") dbq = (dbq as any).eq("scope", args.scope);
      if (q) dbq = (dbq as any).or(
        `memory_key.ilike.%${q}%,memory_value.ilike.%${q}%,entity_name.ilike.%${q}%`
      );
      const { data, error } = await dbq;
      if (error) throw error;
      return { results: data || [], total: (data || []).length };
    }

    case "save_memory": {
      const { data, error } = await admin
        .from("ai_agent_memory")
        .insert({
          scope: args.scope,
          entity_id: args.entity_id || null,
          entity_name: args.entity_name || null,
          memory_key: args.memory_key,
          memory_value: args.memory_value,
          confidence: args.confidence || "high",
          source: "ai_agent",
          created_by_user_id: userId,
        })
        .select()
        .single();
      if (error) return { ok: false, error: error.message };
      return { ok: true, id: data.id };
    }

    case "get_business_alerts": {
      const limit = Math.min(Number(args.limit) || 20, 50);
      let q = admin
        .from("ai_business_alerts")
        .select("id, alert_type, severity, title, description, entity_type, entity_number, first_seen_at, last_seen_at, metadata")
        .is("resolved_at", null)
        .order("last_seen_at", { ascending: false })
        .limit(limit);
      if (args.severity && args.severity !== "all") q = (q as any).eq("severity", args.severity);
      if (args.alert_type) q = (q as any).eq("alert_type", args.alert_type);
      const { data, error } = await q;
      if (error) throw error;
      const SORDER: Record<string, number> = { critical: 0, warning: 1, info: 2 };
      const sorted = (data || []).sort(
        (a: any, b: any) => (SORDER[a.severity] ?? 3) - (SORDER[b.severity] ?? 3)
      );
      const summary = {
        total: sorted.length,
        critical: sorted.filter((a: any) => a.severity === "critical").length,
        warning: sorted.filter((a: any) => a.severity === "warning").length,
        info: sorted.filter((a: any) => a.severity === "info").length,
      };
      return { alerts: sorted, summary };
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
    // Cap history at 20 messages (frontend sends up to 30) to reduce per-call token count.
    const incoming = trimConversationHistory(
      Array.isArray(body.messages) ? body.messages : [],
      20
    );
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

      const fetchResult = await fetchAIWithRetry(
        `${GEMINI_BASE_URL}/chat/completions`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${GEMINI_API_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model: MODEL_SMART,
            messages: salesMessages,
          }),
        },
        { maxRetries: 2, fallbackModel: MODEL_FAST }
      );
      if (!fetchResult.ok) {
        console.error("AI gateway sales error:", fetchResult.response.status, fetchResult.rawBody.slice(0, 200));
        if (fetchResult.classification === "provider_overloaded") {
          return jr({ error: resolveOverloadUserMessage(0) }, 503);
        }
        if (fetchResult.classification === "rate_limit") {
          return jr({ error: resolveRateLimitUserMessage(0) }, 429);
        }
        if (fetchResult.classification === "billing") {
          return jr({ error: "Créditos da IA esgotados." }, 402);
        }
        if (fetchResult.classification === "permission") {
          return jr({ error: "Permissão negada pelo provedor de IA. Verifique as configurações de API key e faturamento." }, 403);
        }
        return jr({ error: "Erro no gateway de IA" }, 500);
      }
      const aiJson = await fetchResult.response.json();
      const content = aiJson.choices?.[0]?.message?.content || "";
      return jr({ message: { role: "assistant", content }, tool_events: [] });
    }

    // Fast-path: answer common OS read queries directly from the database —
    // zero AI provider calls made, zero RPM/RPD consumed.
    const fastPathAnswer = await tryFastPathResponse(incoming, context, sb);
    if (fastPathAnswer !== null) {
      return jr({ message: { role: "assistant", content: fastPathAnswer }, tool_events: [] });
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
      systemPrompt = `Hoje é ${dateStr}, ${timeStr} (horário de Brasília).\n\nVocê é o assistente do MarineFlow ERP marítimo. Responda em português, formate em markdown.

⚠️⚠️⚠️ REGRA ABSOLUTA NÚMERO 1 — INVIOLÁVEL:
Após qualquer tool de busca (search_clients, search_vessels, list_service_orders, search_products) retornar MAIS DE UM resultado, você TEM PROIBIÇÃO TOTAL de escrever texto com os resultados. A ÚNICA ação permitida é chamar 'present_options' imediatamente, com os UUIDs reais no campo value. ZERO EXCEÇÕES. Se você escrever uma lista em texto, a função do sistema falhará e o usuário não conseguirá interagir. SEMPRE chame present_options. NUNCA escreva lista.

REGRAS CRÍTICAS — COMPORTAMENTO PRÓ-ATIVO:
- Antes de QUALQUER ação de gravação (criar, atualizar) ou envio de WhatsApp, você DEVE chamar 'propose_action' primeiro.
- Só chame a tool real (create_*, update_*, send_*) APÓS o usuário confirmar.
- Tools de leitura (search_*, list_*, get_*) podem ser chamadas livremente — use-as ANTES de qualquer pergunta.
- NUNCA peça ao usuário para fornecer IDs — descubra você mesmo via search_*.
- NUNCA crie uma nova OS se o usuário não pediu explicitamente uma nova OS.

FLUXO DE DESAMBIGUAÇÃO — OBRIGATÓRIO:
1. Busque SEMPRE antes de perguntar qualquer coisa.
2. Encontrou 1 resultado → use diretamente, informe o usuário qual usou.
3. Encontrou 2 a 5 resultados → chame 'present_options' com todos + IDs REAIS no campo value.
4. Encontrou 6 ou mais resultados → chame 'present_options' com os 5 PRIMEIROS (mais relevantes) + última opção obrigatória: {label:"🔍 Refinar busca — digitar mais detalhes",value:"__refine__"}. Informe o total encontrado na pergunta: "Encontrei 12 clientes chamados João. Escolha ou refine a busca:"
5. Encontrou 0 → informe e use 'present_options' com opção de criar novo.
6. Usuário escolheu __refine__ → peça mais detalhes específicos (sobrenome, telefone, CNPJ, cidade).
7. Qualquer pergunta sim/não → 'present_options' com [{label:"Sim",value:"sim"},{label:"Não",value:"nao"}].
8. Qualquer lista de escolha → 'present_options'. NUNCA texto corrido com opções.

EXEMPLO CORRETO — "envia o orçamento pro João" com 2 resultados:
  ERRADO ❌: "Encontrei João Silva e João Pereira. Qual você quer?"
  CORRETO ✅: present_options("Qual João?", [{label:"João Paulo Demitti — (47) 98841-0198",value:"uuid-1"},{label:"João Marinho — (21) 98765-4321",value:"uuid-2"}])

EXEMPLO CORRETO — "envia o orçamento pro João" com 12 resultados:
  CORRETO ✅: present_options("Encontrei 12 clientes chamados João. Escolha ou refine:", [
    {label:"João Paulo Demitti — (47) 98841-0198", value:"uuid-1"},
    {label:"João Marinho — RJ", value:"uuid-2"},
    {label:"João Carlos Silva — (48) 99999-0000", value:"uuid-3"},
    {label:"João Roberto — Itajaí", value:"uuid-4"},
    {label:"João Souza — (47) 98888-0000", value:"uuid-5"},
    {label:"🔍 Refinar busca — digitar mais detalhes", value:"__refine__"}
  ])

FLUXO COMPLETO — enviar orçamento/OS:
  1. search_clients(nome) → se múltiplos → present_options com nomes+telefone como label, UUID como value
  2. Com cliente definido → list_service_orders(client_id, limit:10) SEM FILTRO DE STATUS → pega as OSs recentes
  3. Se 1 OS → propose_action direto. Se várias → present_options com "OS-XXXX — R$ valor — Status" como label
  4. Após confirmação → send_service_order_link

FLUXO DE CRIAÇÃO DE ORÇAMENTO COMPLETO:
  1. propose_action mostrando tudo que será feito
  2. Após confirmação: create_service_order (salva o ID retornado)
  3. Para os SERVIÇOS de mão de obra (instalação, reparo, diagnóstico, mão de obra em geral):
     SE houver mais de 1 → add_services_to_order (plural, array de uma vez).
     SE houver apenas 1 → add_service_to_order.
  4. Para PRODUTOS/PEÇAS do catálogo (itens físicos, equipamentos, peças de reposição):
     SE houver mais de 1 produto → add_products_to_order (plural, array de uma vez — aceita product_name para busca).
     SE houver apenas 1 produto → add_product_to_order.
  5. Confirmar ao usuário que tudo foi criado.

DISTINÇÃO PRODUTO vs. SERVIÇO — REGRA OBRIGATÓRIA:
  - PRODUTO/PEÇA = item físico do catálogo products (tem SKU, sale_price, stock_quantity). Ex: "bateria 100Ah", "fusível 30A", "cabo elétrico 25m". → add_product_to_order (1 item) ou add_products_to_order (vários).
  - SERVIÇO = mão de obra cobrada (horas/visitas/diárias). Ex: "troca de bateria", "diagnóstico elétrico", "instalação de painel". → add_service_to_order / add_services_to_order.
  - NUNCA use add_product_to_order para mão de obra; NUNCA use add_service_to_order para peça do catálogo.

AÇÕES CRÍTICAS — adjust_inventory:
  - É ajuste manual de estoque com privilégio elevado (bypassa RLS).
  - SEMPRE chamar propose_action ANTES, com summary_markdown contendo: produto (nome + SKU), quantidade ANTES, quantidade DEPOIS, delta, razão detalhada.
  - Recuse se a razão for vaga ("ajuste", "correção"). Peça detalhe específico (perda, quebra, inventário físico, divergência, etc.).

INCLUSÃO DE MÚLTIPLOS SERVIÇOS EM UMA OS EXISTENTE (REGRA OBRIGATÓRIA):
  - Quando o usuário enviar mais de um par "descrição + valor", trate cada par como um item SEPARADO, INDEPENDENTE do formato:
      * tabela markdown com "|"
      * lista com hífens, asteriscos, números, "1)", "•"
      * texto colado de WhatsApp/Excel/Markdown
      * linhas separadas por vírgula, ponto-e-vírgula, quebra de linha, traço ou qualquer separador imperfeito
      * frases tipo "etapa X — R$ Y", "serviço A: 100", "troca de bomba 300", "fusível R$ 30"
  - REGRA DE DETECÇÃO: se você identifica uma descrição de serviço seguida (na mesma linha OU em linha próxima) de um valor monetário em reais, é UM ITEM SEPARADO. NUNCA funda múltiplos pares em um único serviço.
  - Para 2 ou mais itens de SERVIÇO: use add_services_to_order com um array completo. Para 1 único item: use add_service_to_order.
  - Antes de executar SEMPRE chame propose_action com:
      * "Adicionar N serviços à OS"
      * Lista numerada de todos os itens: "1. <nome> — R$ X,XX"
      * Linha de total: "Total: R$ X.XXX,XX"
      * Payload com o array completo de services
  - Quantidade padrão: 1. Unidade padrão: "visit". Use "hour" apenas se o usuário mencionar horas explicitamente.
  - Preserve nomes longos e descrições completas no campo service_name. Não trunque.

EXEMPLO 1 — tabela markdown:
  Usuário cola tabela com 9 linhas "Etapa | Valor estimado".
  Você monta payload com services: [9 itens], cada item com service_name = texto da etapa e unit_price = valor em number.

EXEMPLO 2 — texto livre:
  Usuário diz: "adicione troca de fusível 30 reais; troca de bomba R$ 100; troca de bateria - 200"
  Você monta services: [
    { service_name: "troca de fusível", unit_price: 30 },
    { service_name: "troca de bomba", unit_price: 100 },
    { service_name: "troca de bateria", unit_price: 200 }
  ]

INCLUSÃO DE MÚLTIPLOS PRODUTOS EM UMA OS EXISTENTE (REGRA OBRIGATÓRIA):
  - Quando o usuário listar mais de 1 produto/equipamento/peça para adicionar à OS, use add_products_to_order com um array.
  - O campo product_name é suficiente — a tool busca automaticamente: primeiro pelo nome completo, depois por termos-chave (sem parênteses, sem stop words, AND por token).
  - Antes de executar SEMPRE chame propose_action com lista de todos os produtos e quantidades.
  - QUANDO add_products_to_order retornar failed_count > 0, NUNCA responda apenas "não foi possível adicionar". Siga OBRIGATORIAMENTE:
      * Item com campo "candidates" no failed[]: chame present_options imediatamente com as opções retornadas (label = product_name + preço, value = id) para o usuário escolher o produto correto.
      * Item sem candidates (não encontrado nem por termos-chave): ofereça explicitamente ao usuário: (a) tentar buscar por outro nome usando search_products, (b) informar que o produto precisa ser cadastrado no catálogo antes de ser adicionado.
      * Após escolha do usuário, use add_product_to_order com o product_id selecionado.
      * Relate claramente quais produtos foram inseridos com sucesso e quais precisam de ação.

EXEMPLO — "adicione estes equipamentos: Bateria Lítio 12V/200Ah, SmartShunt 500A, Cerbo GX":
  propose_action → add_products_to_order({ service_order_id: "...", products: [
    { product_name: "Bateria Lítio 12V/200Ah", quantity: 1 },
    { product_name: "SmartShunt 500A", quantity: 1 },
    { product_name: "Cerbo GX", quantity: 1 },
  ]})
  → 1 chamada. Produtos encontrados: inseridos direto. Se failed[] com candidates: present_options para cada um. Se failed[] sem candidates: oferece busca manual ou cadastro.

FLUXO DE ENVIO DE ORÇAMENTO/OS:
  1. Se não houver OS em contexto, busque com list_service_orders
  2. Use send_service_order_link para enviar via WhatsApp
  3. Informe: "✅ Orçamento enviado para [nome do cliente] via WhatsApp. O cliente receberá um link para visualizar e baixar o PDF online."
  4. NUNCA diga que enviou um PDF em anexo — o sistema envia um link de acesso.

FLUXO DE AGENDAMENTO DE WHATSAPP:
  - "Agendar mensagem", "mandar amanhã de manhã", "lembrete no dia X": use schedule_whatsapp_message.
  - Sempre use propose_action antes de agendar.
  - Se o usuário não especificar hora, assuma 09:00 do dia solicitado.
  - Após agendar, confirme: "✅ Mensagem agendada para [data/hora]. Você pode gerenciá-la em WhatsApp → Agendamentos."
  - Para listar ou cancelar agendamentos: use list_scheduled_whatsapp / cancel_scheduled_whatsapp.
  - Informe o status do modo de teste se ativo: "⚠️ Modo de teste ativo — a mensagem será redirecionada para o número de teste."

QUALIDADE DAS RESPOSTAS:
- Os dados já vêm com nomes de clientes e embarcações — use-os diretamente, nunca faça buscas extras para resolver IDs.
- NUNCA exiba IDs técnicos (UUIDs) ao usuário.
- Datas: formato "28 de abril de 2026 às 09:00".
- Valores: formato "R$ 1.500,00".
- Status válidos de Ordem de Serviço (CHECK constraint do banco): draft=Rascunho, open=Aberta, scheduled=Agendada, in_progress=Em andamento, awaiting_parts=Aguardando peças, awaiting_client=Aguardando cliente, approved=Aprovada, completed=Concluída, invoiced=Faturada, cancelled=Cancelada. NUNCA use "pending", "waiting_parts", "waiting_approval", "reopened" — esses NÃO existem no schema.
- Use listas markdown para múltiplos itens.
- Respostas concisas e objetivas.
CONFIGURAÇÕES DA EMPRESA (use sempre que relevante para calcular preços, sugerir valores ou criar registros):
- Empresa: ${settings.company_name || "HBR Marine"}
- Valor hora padrão (mão de obra): R$ ${settings.default_hourly_rate || "0"}/h — use como referência ao adicionar serviços sem preço definido
- Custo por km (deslocamento): R$ ${settings.cost_per_km || "0"}/km — use ao calcular deslocamento
- Margem de lucro padrão: ${settings.default_profit_margin || "30"}% — alerte se OS estiver abaixo disso
- Comissão padrão: ${settings.default_commission_rate || "0"}%
- Chave PIX: ${settings.pix_key || "não configurada"}
- Banco: ${settings.bank_name || ""} Ag: ${settings.bank_agency || ""} Cc: ${settings.bank_account || ""}

CONTEXTO ATUAL:
- Data/hora: ${today.toISOString()} (${today.toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })})
- Usuário logado: ${userName} (ID: ${userId})
- Cargo/Role do usuário: ${userRole.toUpperCase()}

INSTRUÇÕES DE PERMISSÃO E ACESSO DO USUÁRIO ATUAL:
- O sistema possui controle de acesso por cargos. Como agente de IA, você DEVE atuar exatamente com as mesmas limitações do cargo do usuário logado.
- Se o usuário for TECHNICIAN: Você deve responder APENAS a dúvidas técnicas, agendamentos, visualizar OS e inserir dados operacionais. Você está ESTRITAMENTE PROIBIDO de criar, visualizar ou alterar informações de preços, financeiro (cobranças), produtos e configurações do sistema. Se o técnico pedir algo fora do escopo (ex: "me mostre o faturamento" ou "altere o preço"), recuse IMEDIATAMENTE e informe com educação que ele não possui permissão.
- Se o usuário for ADMIN: O acesso é irrestrito para todas as funções.
- Como o banco de dados também impõe RLS, operações não permitidas falharão no backend, mas sua principal função é instruir o usuário antes mesmo de tentar executar a tarefa.
- Rota atual: ${context.route || "desconhecida"}
- Entidade em contexto: ${context.entityType || "nenhuma"} ${context.entityId ? `(id: ${context.entityId})` : ""}

MEMÓRIA PERSISTENTE — REGRAS OBRIGATÓRIAS:
- Ao iniciar conversa sobre um cliente ou embarcação específico, chame search_memory(entity_id=UUID) ANTES de fazer qualquer ação.
- Quando aprender algo relevante durante a conversa (preferência de contato, problema recorrente, equipamento instalado, decisão do cliente), chame save_memory ao final.
- Exemplos de memórias valiosas: "prefere ser contactado pelo WhatsApp à tarde", "barco tem bateria recarregada mensalmente desde problema em Mar/2025", "cliente costuma aprovar orçamentos acima de R$ 5k sem questionar".
- Não salve fatos óbvios ou já armazenados no banco (dados cadastrais). Salve INSIGHTS e PADRÕES comportamentais.

PROATIVIDADE E NEGÓCIOS:
- Use get_business_alerts quando o usuário perguntar sobre 'o que precisa de atenção', 'alertas', 'pendências do negócio', 'status geral', 'o que está parado', 'briefing' ou qualquer variação de resumo operacional. Apresente os alertas críticos primeiro com ícone 🔴, warnings com 🟡 e infos com 🔵.
- Se você notar que um cliente não tem OS recente ou tem orçamentos parados em 'draft', sugira proativamente um follow-up.
- Se identificar baixa lucratividade em uma OS (margem < 20%), alerte o ADMIN de forma discreta.
- Sempre tente resolver ambiguidades buscando no banco antes de perguntar ao usuário.

Quando o usuário disser "este cliente", "esta OS", "este barco", use o ID em contexto se compatível.`;
    }

    const messages: any[] = [{ role: "system", content: systemPrompt }, ...incoming];

    let toolEvents: any[] = [];

    for (let iter = 0; iter < MAX_ITERATIONS; iter++) {
      // Detecta se é consulta simples (usa modelo rápido) ou ação complexa (usa modelo inteligente)
      const lastUserMsg = messages.filter((m: any) => m.role === "user").pop()?.content || "";
      // Usa sempre o modelo inteligente — o Flash ignorava instruções de present_options
      // e escrevia listas em texto em vez de chamar a tool. Pro garante maior fidelidade.
      const modelToUse = MODEL_SMART;

      const fetchResult = await fetchAIWithRetry(
        `${GEMINI_BASE_URL}/chat/completions`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${GEMINI_API_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model: modelToUse,
            messages,
            tools: isSalesCopy ? undefined : TOOLS,
            tool_choice: isSalesCopy ? undefined : "auto",
          }),
        },
        { maxRetries: iter === 0 ? 2 : 0, fallbackModel: MODEL_FAST }
      );
      if (!fetchResult.ok) {
        console.error("AI gateway error:", fetchResult.response.status, fetchResult.rawBody.slice(0, 200));
        if (fetchResult.classification === "provider_overloaded") {
          return jr({ error: resolveOverloadUserMessage(iter) }, 503);
        }
        if (fetchResult.classification === "rate_limit") {
          return jr({ error: resolveRateLimitUserMessage(iter) }, 429);
        }
        if (fetchResult.classification === "billing") {
          return jr({ error: "Créditos da IA esgotados. Adicione créditos em Settings > Workspace > Usage." }, 402);
        }
        if (fetchResult.classification === "permission") {
          return jr({ error: "Permissão negada pelo provedor de IA. Verifique as configurações de API key e faturamento." }, 403);
        }
        return jr({ error: `Erro no gateway de IA (${fetchResult.response.status})` }, 500);
      }

      const aiJson = await fetchResult.response.json();
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
              const parts = [c.full_name_or_company_name];
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
            label: (v) => [v.boat_name, v.model, v.year].filter(Boolean).join(" · "),
            value: (v) => v.id,
          },
          search_products: {
            question: (q, n) => n > 5
              ? `Encontrei ${n} produtos para "${q}". Escolha ou refine:`
              : `Qual produto para "${q}"?`,
            label: (p) => {
              const parts = [p.product_name];
              if (p.sale_price) parts.push(`R$ ${Number(p.sale_price).toFixed(2)}`);
              if (p.sku) parts.push(`SKU: ${p.sku}`);
              if (p.stock_quantity != null) parts.push(`Estoque: ${p.stock_quantity}`);
              return parts.join(" — ");
            },
            value: (p) => p.id,
          },
          search_services: {
            question: (q, n) => n > 5
              ? `Encontrei ${n} serviços para "${q}". Escolha ou refine:`
              : `Qual serviço para "${q}"?`,
            label: (s) => `${s.service_name}${s.default_price ? ` — R$ ${Number(s.default_price).toFixed(2)}` : ""}`,
            value: (s) => s.id,
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
              label: cfg.label(item).slice(0, 120),
              value: cfg.value(item),
            }));
            if (items.length > 5) {
              options.push({ label: "🔍 Refinar busca — digitar mais detalhes", value: "__refine__" });
            }
            const question = cfg.question(searchQuery, items.length);
            return jr({
              message: { role: "assistant", content: `Encontrei ${items.length} resultado(s). Selecione:` },
              options: { question, options, entity_type: fnName },
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
