// Edge Function: ai-agent
// Agente de IA com function calling — Google Gemini API (OpenAI-compatible endpoint).
// Recebe { messages, context } e roda loop de tool-calling até resposta final.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const jr = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), {
    status: s,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;
const GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/openai";
const MODEL_FAST = "gemini-2.0-flash";
const MODEL_SMART = "gemini-2.0-flash";
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
            enum: ["draft", "approved", "scheduled", "in_progress", "completed", "cancelled", "invoiced"],
          },
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
        const STATUS_PT_EN: Record<string, string> = {
          "rascunho": "draft", "pendente": "pending", "aprovado": "approved",
          "agendado": "scheduled", "em andamento": "in_progress", "em execução": "in_progress",
          "concluído": "completed", "concluido": "completed",
          "cancelado": "cancelled", "faturado": "invoiced",
          "aguardando peças": "waiting_parts", "aguardando aprovação": "waiting_approval", "reaberto": "reopened",
        };
        const mappedStatus = STATUS_PT_EN[args.status.toLowerCase()] ?? args.status;
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
      let query = admin.from("commissions").select("*, service_orders(service_order_number)");
      if (args.technician_id) query = query.eq("technician_user_id", args.technician_id);
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
      await sb.rpc("recalc_so_totals", { so_id: data.id }).catch(() => null);
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
        ? await sb.from("services").select("service_name, billing_unit, default_price").eq("id", args.service_id).maybeSingle()
        : { data: null };
      const qty = Number(args.quantity) || 1;
      const defaultHourlyRate = Number(settings.default_hourly_rate) || 0;
      const price = Number(args.unit_price) || svc?.default_price || defaultHourlyRate || 0;
      const { data, error } = await sb
        .from("service_order_services")
        .insert({
          service_order_id: args.service_order_id,
          service_id: args.service_id || null,
          service_name_snapshot: args.service_name || svc?.service_name || "",
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
          .upsert({ service_order_id: args.service_order_id, technician_user_id: args.technician_user_id }, { onConflict: "service_order_id,technician_user_id" })
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
      const optimizeRes = await fetch(`${GEMINI_BASE_URL}/chat/completions`, {
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

      const aiRes = await fetch(`${GEMINI_BASE_URL}/chat/completions`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${GEMINI_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: MODEL_SMART,
          messages: salesMessages,
        }),
      });

      if (aiRes.status === 429) return jr({ error: "Limite de requisições atingido. Tente novamente em alguns segundos." }, 429);
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
  3. Para cada serviço: add_service_to_order com o ID da OS criada
  4. Para cada produto: add_service_order_item com o ID da OS criada
  5. Confirmar ao usuário que tudo foi criado.

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
- Status: draft=Rascunho, pending=Pendente, approved=Aprovado, scheduled=Agendado, in_progress=Em andamento, completed=Concluído, cancelled=Cancelado, invoiced=Faturado.
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

PROATIVIDADE E NEGÓCIOS:
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

      const aiRes = await fetch(`${GEMINI_BASE_URL}/chat/completions`, {
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
      });

      if (aiRes.status === 429) return jr({ error: "Limite de requisições atingido. Tente novamente em alguns segundos." }, 429);
      if (aiRes.status === 402) return jr({ error: "Créditos da IA esgotados. Adicione créditos em Settings > Workspace > Usage." }, 402);
      if (!aiRes.ok) {
        const t = await aiRes.text();
        console.error("AI gateway error:", aiRes.status, t);
        try {
          const errJson = JSON.parse(t);
          return jr({ error: `IA Erro (${aiRes.status}): ${errJson.error?.message || t}` }, 500);
        } catch {
          return jr({ error: `Erro no gateway de IA (${aiRes.status})` }, 500);
        }
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
            label: (p) => `${p.product_name}${p.sale_price ? ` — R$ ${Number(p.sale_price).toFixed(2)}` : ""}`,
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
