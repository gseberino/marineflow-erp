// Edge Function: ai-agent
// Agente de IA com function calling — Lovable AI Gateway (Gemini).
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
const LOVABLE_API_KEY = Deno.env.get("LOVABLE_API_KEY")!;
const MODEL_FAST = "google/gemini-2.0-flash";
const MODEL_SMART = "google/gemini-2.5-pro";
const MODEL = MODEL_SMART;
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

  // ====== PROPOSE (preview/confirmation) ======
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
      description: "Cadastra uma nova embarcação para um cliente.",
      parameters: {
        type: "object",
        properties: {
          client_id: { type: "string" },
          boat_name: { type: "string" },
          manufacturer: { type: "string" },
          model: { type: "string" },
          year: { type: "number" },
          marina_id: { type: "string" },
        },
        required: ["client_id", "boat_name"],
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
        "Envia o link público (assinatura/visualização) de uma OS por WhatsApp.",
      parameters: {
        type: "object",
        properties: {
          service_order_id: { type: "string" },
          custom_message: { type: "string" },
        },
        required: ["service_order_id"],
      },
    },
  },
];

// ---------------- TOOL EXECUTORS ----------------
async function executeTool(
  name: string,
  args: any,
  ctx: { sb: any; admin: any; userId: string; jwt: string; appOrigin: string }
): Promise<any> {
  const { sb, admin, userId, jwt, appOrigin } = ctx;

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
        .select("id, title, scheduled_start_at, scheduled_end_at, status, priority, technician_user_id, client_id, location")
        .gte("scheduled_start_at", args.date_from)
        .lte("scheduled_start_at", args.date_to)
        .order("scheduled_start_at", { ascending: true });
      if (args.technician_id) query = query.eq("technician_user_id", args.technician_id);
      const { data, error } = await query;
      if (error) throw error;
      return { results: data };
    }

    case "list_service_orders": {
      let query = sb
        .from("service_orders")
        .select("id, service_order_number, status, client_id, vessel_id, grand_total, scheduled_start_at, created_at")
        .order("created_at", { ascending: false })
        .limit(Math.min(Number(args.limit) || 20, 50));
      if (args.status) query = query.eq("status", args.status);
      if (args.client_id) query = query.eq("client_id", args.client_id);
      if (args.vessel_id) query = query.eq("vessel_id", args.vessel_id);
      const { data, error } = await query;
      if (error) throw error;
      return { results: data };
    }

    case "get_service_order": {
      const { data: so, error } = await sb
        .from("service_orders")
        .select("*")
        .eq("id", args.id)
        .maybeSingle();
      if (error) throw error;
      if (!so) return { error: "OS não encontrada" };
      const { data: parts } = await sb
        .from("service_order_parts")
        .select("id, product_id, quantity, line_total_sale")
        .eq("service_order_id", args.id);
      const { data: services } = await sb
        .from("service_order_services")
        .select("id, service_name_snapshot, quantity, unit_price_snapshot, line_total")
        .eq("service_order_id", args.id);
      return { service_order: so, parts, services };
    }

    case "get_client_history": {
      const { data, error } = await sb
        .from("service_orders")
        .select("id, service_order_number, status, scheduled_start_at, grand_total, created_at")
        .eq("client_id", args.client_id)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      return { history: data };
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
      // Gera número da OS no formato SO-YYYY-XXXXXX
      const year = new Date().getFullYear();
      const rand = Math.floor(100000 + Math.random() * 900000);
      const num = `SO-${year}-${rand}`;
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
      const { data: so, error } = await sb
        .from("service_orders")
        .select("id, service_order_number, share_token, client_id")
        .eq("id", args.service_order_id)
        .maybeSingle();
      if (error || !so) return { error: "OS não encontrada" };
      if (!so.share_token) return { error: "OS sem share_token" };
      const { data: c } = await sb
        .from("clients")
        .select("whatsapp, phone, full_name_or_company_name")
        .eq("id", so.client_id)
        .maybeSingle();
      const phone = c?.whatsapp || c?.phone;
      if (!phone) return { error: "Cliente sem WhatsApp/telefone." };
      const link = `${appOrigin}/view/${so.share_token}`;
      const msg =
        args.custom_message ||
        `Olá${c?.full_name_or_company_name ? ` ${c.full_name_or_company_name}` : ""}, segue o link da OS ${so.service_order_number}: ${link}`;
      return await sendWhatsapp(phone, msg, jwt);
    }

    default:
      return { error: `Tool desconhecida: ${name}` };
  }
}

async function sendWhatsapp(phone: string, message: string, jwt: string) {
  const r = await fetch(`${SUPABASE_URL}/functions/v1/whatsapp-send-text`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${jwt}`,
      apikey: ANON,
    },
    body: JSON.stringify({ phone, message }),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) return { error: (data as any).error || `HTTP ${r.status}` };
  return { ok: true, messageId: (data as any).messageId };
}

// ---------------- HANDLER ----------------
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    if (!LOVABLE_API_KEY) return jr({ error: "LOVABLE_API_KEY não configurada" }, 500);

    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return jr({ error: "Não autenticado" }, 401);

    const sb = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const { data: userData, error: userErr } = await sb.auth.getUser(jwt);
    if (userErr || !userData?.user?.id) return jr({ error: "Não autenticado" }, 401);
    const userId = userData.user.id;

    const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const body = await req.json().catch(() => ({}));
    const incoming = Array.isArray(body.messages) ? body.messages : [];
    const context = body.context || {};
    const appOrigin =
      req.headers.get("origin") ||
      req.headers.get("referer")?.replace(/\/$/, "") ||
      "";

    const today = new Date();
    const systemPrompt = `Você é o assistente do MarineFlow ERP marítimo. Responda em português, formate em markdown.

REGRAS CRÍTICAS:
- Antes de QUALQUER ação de gravação (criar, atualizar) ou envio de WhatsApp, você DEVE chamar 'propose_action' primeiro com um resumo claro em markdown e o payload exato.
- Só chame a tool real (create_*, update_*, send_*) APÓS o usuário enviar uma mensagem confirmando (texto contendo "Confirmado pelo usuário" ou similar).
- Tools de leitura (search_*, list_*, get_*) podem ser chamadas livremente.
- Use as tools de busca para resolver nomes em IDs. Seja tolerante a erros de digitação.
- NUNCA peça ao usuário para fornecer IDs — descubra você mesmo via search_*.

CONTEXTO ATUAL:
- Data/hora: ${today.toISOString()} (${today.toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })})
- Usuário logado: ${userId}
- Rota atual: ${context.route || "desconhecida"}
- Entidade em contexto: ${context.entityType || "nenhuma"} ${context.entityId ? `(id: ${context.entityId})` : ""}

Quando o usuário disser "este cliente", "esta OS", "este barco", use o ID em contexto se compatível.`;

    const messages: any[] = [{ role: "system", content: systemPrompt }, ...incoming];

    let toolEvents: any[] = [];

    for (let iter = 0; iter < MAX_ITERATIONS; iter++) {
      // Detecta se é consulta simples (usa modelo rápido) ou ação complexa (usa modelo inteligente)
      const lastUserMsg = messages.filter((m: any) => m.role === "user").pop()?.content || "";
      const isComplexTask = /cri(ar?|e)|cadastr|atualiz|envi(ar?|e)|agendar?|otimiz|desconto|duplicar?|cancel/i.test(lastUserMsg);
      const modelToUse = isComplexTask ? MODEL_SMART : MODEL_FAST;

      const aiRes = await fetch("https://ai.gateway.lovable.dev/v1/chat/completions", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${LOVABLE_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: modelToUse,
          messages,
          tools: TOOLS,
          tool_choice: "auto",
        }),
      });

      if (aiRes.status === 429) return jr({ error: "Limite de requisições atingido. Tente novamente em alguns segundos." }, 429);
      if (aiRes.status === 402) return jr({ error: "Créditos da IA esgotados. Adicione créditos em Settings > Workspace > Usage." }, 402);
      if (!aiRes.ok) {
        const t = await aiRes.text();
        console.error("AI gateway error:", aiRes.status, t);
        return jr({ error: "Erro no gateway de IA" }, 500);
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
          result = await executeTool(fnName, fnArgs, { sb, admin, userId, jwt, appOrigin });
        } catch (e: any) {
          result = { error: e?.message || "Falha na execução da tool" };
        }

        toolEvents.push({ name: fnName, args: fnArgs, result });

        messages.push({
          role: "tool",
          tool_call_id: tc.id,
          content: JSON.stringify(result),
        });

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
            // Devolve mensagens atualizadas para o frontend continuar a conversa
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
