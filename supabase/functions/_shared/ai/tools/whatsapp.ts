import { NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";
import { guardaDeEnvio } from "../comms/send-guard.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Prévia amigável de mídia ("identificar e encaminhar" — sem custo de vision/transcrição).
function prettyPreview(body?: string | null): string | null {
  const b = (body || "").trim();
  if (!b) return null;
  if (b === "[audio]") return "🎤 áudio";
  if (b === "[image]") return "📷 imagem";
  if (b === "[video]") return "🎬 vídeo";
  if (b === "[document]") return "📎 arquivo";
  return b.slice(0, 100);
}

/**
 * Usa a edge function whatsapp-send (não whatsapp-send-text) para respeitar
 * wa_test_mode/wa_test_number do app_settings. Lê env em tempo de chamada
 * (não no import do módulo) para não quebrar testes que nunca chamam isto.
 */
export async function sendWhatsapp(phone: string, message: string, jwt: string) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  // No canal WhatsApp não há JWT de usuário (o toolCtx traz jwt=""), então usamos a
  // service-role key: o whatsapp-send tem um bypass explícito (isServiceRoleCall) para
  // chamadas de sistema. No painel, jwt é o token real do usuário.
  const authToken = jwt || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  // NÃO enviar header `apikey`: espelha o chamador que já funciona
  // (whatsapp-process-scheduled manda só Authorization: Bearer <service_role>).
  // Enviar `apikey: anon` JUNTO com um bearer service_role faz o gateway rejeitar com
  // 401 (sem corpo) por conflito de papel — foi o "HTTP 401" que o envio do agente dava.
  // whatsapp-send tem verify_jwt=false, então o apikey nem é necessário.
  const r = await fetch(`${supabaseUrl}/functions/v1/whatsapp-send`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${authToken}`,
    },
    body: JSON.stringify({ phone, message, kind: "text" }),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) return { error: (data as any).error || `HTTP ${r.status}` };
  return { ok: true, messageId: (data as any).messageId };
}

export const whatsappTools: ToolDef[] = [
  {
    name: "send_whatsapp_message",
    description: "Envia mensagem de WhatsApp via Evolution API. Forneça to_phone OU client_id (busca o WhatsApp/telefone do cliente).",
    input_schema: {
      type: "object",
      properties: {
        to_phone: { type: "string" },
        client_id: { type: "string" },
        message: { type: "string" },
      },
      required: ["message"],
    },
    // "pior caso" para o filtro por cargo — o risco real depende do destinatário.
    risk: "high",
    computeRisk: (args) => (args?.client_id ? "high" : "medium"),
    async execute(args, { sb, jwt }) {
      let phone = args.to_phone;
      if (!phone && args.client_id) {
        const { data: c } = await sb.from("clients").select("whatsapp, phone").eq("id", args.client_id).maybeSingle();
        phone = c?.whatsapp || c?.phone;
      }
      if (!phone) return { error: "Telefone não fornecido nem encontrado para o cliente." };
      return await sendWhatsapp(phone, args.message, jwt);
    },
  },
  {
    name: "send_supplier_quote_request",
    description:
      "Envia um pedido de COTAÇÃO por WhatsApp a um ou mais FORNECEDORES (ação sensível — pede confirmação). Informe supplier_ids (ache com suggest_suppliers) e os itens a cotar. As respostas dos fornecedores chegam na caixa normal do WhatsApp — a consolidação é manual (MVP). NÃO cria ordem de compra. MOSTRE a prévia da mensagem e a lista de fornecedores antes de confirmar.",
    input_schema: {
      type: "object",
      properties: {
        supplier_ids: { type: "array", items: { type: "string" }, description: "UUIDs dos fornecedores (de suggest_suppliers/create_supplier)." },
        items: {
          type: "array",
          description: "Itens a cotar.",
          items: {
            type: "object",
            properties: { description: { type: "string" }, quantity: { type: "number" } },
            required: ["description"],
          },
        },
        notes: { type: "string", description: "Observação opcional que VAI na mensagem (ex.: condição de pagamento). NÃO use para prazo (quem define é o fornecedor, só se ele perguntar) nem para descrever a aplicação/'pra que serve' (confunde quem atende)." },
        quote_request_id: { type: "string", description: "UUID de uma cotação criada com create_quote_request. FORMA PREFERIDA: manda o código COT-XXXXX e os itens numerados, o que faz a resposta do fornecedor voltar interpretável." },
      },
    },
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, { sb, jwt }) {
      let supplierIds: string[] = Array.isArray(args.supplier_ids) ? args.supplier_ids : [];
      let items: any[] = Array.isArray(args.items) ? args.items : [];
      let codigo = "";

      // Caminho preferido: a cotação já existe → usa código + itens numerados dela.
      if (args.quote_request_id) {
        const { data: req } = await sb
          .from("quote_requests")
          .select("id, code, sent_supplier_ids, notes")
          .eq("id", args.quote_request_id)
          .maybeSingle();
        if (!req) return { error: "Cotação não encontrada." };
        const { data: qItems } = await sb
          .from("quote_request_items")
          .select("position, description, quantity")
          .eq("quote_request_id", req.id)
          .order("position", { ascending: true });
        codigo = req.code;
        if (supplierIds.length === 0) supplierIds = (req.sent_supplier_ids as string[]) || [];
        items = (qItems || []).map((i: any) => ({ position: i.position, description: i.description, quantity: Number(i.quantity) }));
        // req.notes fica INTERNO de propósito: aplicação ("pra que serve") e prazo NÃO vão na
        // mensagem ao fornecedor — descrever a aplicação confunde quem atende, e o prazo quem
        // define é o fornecedor. Só um args.notes explícito (ex.: condição de pagamento) é enviado.
      }

      if (supplierIds.length === 0) return { error: "Informe ao menos um fornecedor (supplier_ids) ou uma cotação com fornecedores." };
      if (items.length === 0) return { error: "Informe ao menos um item para cotar." };

      const { data: comp } = await sb.from("app_settings").select("value").eq("key", "company_name").maybeSingle();
      const company = comp?.value || "nossa empresa";
      const { data: suppliers } = await sb.from("suppliers").select("id, name, trade_name, phone, opt_out_whatsapp").in("id", supplierIds);
      const byId: Record<string, any> = Object.fromEntries((suppliers || []).map((s: any) => [s.id, s]));
      // Itens NUMERADOS: é o que faz o fornecedor responder "1 - R$ 850 - 5 dias".
      const itemLines = items
        .map((it, i) => `${it.position ?? i + 1}. ${it.quantity ? `${it.quantity}x ` : ""}${it.description ?? ""}`.trimEnd())
        .join("\n");

      const resultados: Array<{ fornecedor: string; status: string }> = [];
      const avisos = new Set<string>();
      for (const sid of supplierIds) {
        const sup = byId[sid];
        if (!sup) { resultados.push({ fornecedor: sid, status: "não encontrado" }); continue; }
        const nomeForn = sup.trade_name || sup.name || sid;
        if (sup.opt_out_whatsapp) { resultados.push({ fornecedor: nomeForn, status: "opt-out (não receber)" }); continue; }
        if (!sup.phone) { resultados.push({ fornecedor: nomeForn, status: "sem WhatsApp cadastrado" }); continue; }
        // Mensagem ENXUTA de propósito: saudação neutra (sem razão social, que às vezes é
        // genérica) + itens numerados. Sem descrever a aplicação, sem estipular prazo e sem
        // ensinar o fornecedor a responder — ele responde pela lista. (Ver feedback do dono.)
        const msg =
          `Olá, tudo bem? Aqui é da ${company}.\n` +
          `Gostaríamos de uma cotação${codigo ? ` (${codigo})` : ""}:\n${itemLines}` +
          `${args.notes ? `\n\n${args.notes}` : ""}\n\n` +
          `Obrigado!`;
        // Portão de comunicação: conformidade (bloqueia) + estilo (avisa).
        const g = guardaDeEnvio(msg, { tipo: "cotacao", audiencia: "fornecedor", canal: "whatsapp", destinatarioIdentificado: true });
        if (g.bloqueado) { resultados.push({ fornecedor: sup.name || sid, status: `bloqueado: ${g.motivo}` }); continue; }
        g.avisos.forEach((a) => avisos.add(a));
        const r = await sendWhatsapp(sup.phone, msg, jwt);
        resultados.push({ fornecedor: nomeForn, status: r.ok ? "enviado" : `falhou: ${r.error}` });
      }
      const enviados = resultados.filter((r) => r.status === "enviado").length;
      return { ok: true, cotacao: codigo || null, enviados, total: supplierIds.length, resultados, ...(avisos.size ? { avisos_estilo: [...avisos] } : {}) };
    },
  },
  {
    name: "send_collection_reminder",
    description: "Envia um lembrete de cobrança por WhatsApp para o contato da cobrança.",
    input_schema: {
      type: "object",
      properties: { collection_id: { type: "string" }, custom_message: { type: "string" } },
      required: ["collection_id"],
    },
    // Sempre envia pro contato da cobrança — sempre cliente, nunca equipe.
    risk: "high",
    async execute(args, { sb, admin, jwt }) {
      const { data: col, error } = await sb
        .from("collections")
        .select("id, amount, due_date, contact_whatsapp, phone, contact_name, client_id, description")
        .eq("id", args.collection_id)
        .maybeSingle();
      if (error || !col) return { error: "Cobrança não encontrada" };
      // Perfil do contato: nome usado (display_name) e opt-out.
      let c: any = null;
      if (col.client_id) {
        const r = await sb.from("clients").select("whatsapp, phone, name, display_name, opt_out_whatsapp").eq("id", col.client_id).maybeSingle();
        c = r.data;
      }
      if (c?.opt_out_whatsapp) return { error: "Este cliente pediu para não receber mensagens no WhatsApp (opt-out). Cobre por outro canal." };
      const phone = col.contact_whatsapp || col.phone || c?.whatsapp || c?.phone;
      if (!phone) return { error: "Sem telefone para enviar o lembrete." };
      const fmt = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(col.amount);
      const nomeUsado = c?.display_name || col.contact_name || (c?.name ? String(c.name).trim().split(/\s+/)[0] : "");
      const msg =
        args.custom_message ||
        `Olá${nomeUsado ? ` ${nomeUsado}` : ""}, lembrete amigável: você possui um valor de ${fmt} com vencimento em ${col.due_date}. Qualquer dúvida estamos à disposição.`;
      // Portão: conformidade (horário, número identificado) bloqueia; estilo (ameaça) avisa.
      const g = guardaDeEnvio(msg, { tipo: "cobranca", audiencia: "cliente", canal: "whatsapp", destinatarioIdentificado: !!col.client_id, texto: msg });
      if (g.bloqueado) return { error: g.motivo };
      const r = await sendWhatsapp(phone, msg, jwt);
      if (r.ok) {
        await admin.from("collections").update({ last_auto_sent_at: new Date().toISOString() }).eq("id", col.id);
      }
      return { ...r, ...(g.avisos.length ? { avisos_estilo: g.avisos } : {}) };
    },
  },
  {
    name: "send_service_order_link",
    description:
      "Envia o link público de uma OS/orçamento por WhatsApp. Use sempre que o usuário pedir 'enviar orçamento', 'mandar OS', 'enviar para o cliente' etc. O campo service_order_id aceita TANTO o UUID (campo 'id' do list_service_orders) QUANTO o número do documento (ex: 'ORÇ-00001' para orçamentos, 'OS-00042' para OS, ou o formato antigo 'OS-2026-XXXXX'). Prefira sempre o UUID.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID (campo id) ou número da OS (campo numero, ex: OS-2026-152542)" },
        custom_message: { type: "string", description: "Mensagem personalizada. Se omitido, usa mensagem padrão com link." },
      },
      required: ["service_order_id"],
    },
    // Sempre envia pro cliente dono da OS — sempre cliente, nunca equipe.
    risk: "high",
    async execute(args, { admin, jwt, appOrigin, settings }) {
      const isUUID = UUID_RE.test(String(args.service_order_id || ""));
      let soQuery = admin.from("service_orders").select("id, service_order_number, share_token, client_id");
      soQuery = isUUID ? soQuery.eq("id", args.service_order_id) : soQuery.eq("service_order_number", args.service_order_id);
      const { data: so, error: soErr } = await soQuery.maybeSingle();
      if (soErr || !so) return { error: `OS não encontrada. Verifique se o número ou ID está correto. Valor recebido: "${args.service_order_id}"` };
      if (!so.share_token) return { error: `A OS ${so.service_order_number} não possui link público ainda. Abra a OS no app, clique em "Compartilhar" para gerar o link, e tente novamente.` };
      const { data: c } = await admin.from("clients").select("whatsapp, phone, name, display_name, opt_out_whatsapp").eq("id", so.client_id).maybeSingle();
      if (c?.opt_out_whatsapp) return { error: "Este cliente pediu para não receber mensagens no WhatsApp (opt-out)." };
      const phone = c?.whatsapp || c?.phone;
      if (!phone) return { error: "Cliente sem WhatsApp/telefone cadastrado." };
      const origin = appOrigin || settings.app_public_url || "https://hbrmarine.online";
      const link = `${origin}/view/${so.share_token}`;
      const nomeUsado = c?.display_name || (c?.name ? String(c.name).trim().split(/\s+/)[0] : "");
      const msg = args.custom_message || `Olá${nomeUsado ? ` ${nomeUsado}` : ""}, segue o link da OS ${so.service_order_number}: ${link}`;
      const g = guardaDeEnvio(msg, { tipo: "os_link", audiencia: "cliente", canal: "whatsapp", destinatarioIdentificado: !!so.client_id });
      if (g.bloqueado) return { error: g.motivo };
      const r = await sendWhatsapp(phone, msg, jwt);
      return { ...r, ...(g.avisos.length ? { avisos_estilo: g.avisos } : {}) };
    },
  },
  {
    name: "schedule_whatsapp_message",
    description:
      "Agenda uma mensagem WhatsApp para ser enviada em data/hora específica. Use para 'agendar envio', 'mandar amanhã', 'lembrete automático' etc. Para envios com link de OS, informe service_order_id.",
    input_schema: {
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
    // "pior caso" para o filtro por cargo — client_id/service_order_id indicam cliente.
    risk: "high",
    computeRisk: (args) => (args?.client_id || args?.service_order_id ? "high" : "medium"),
    async execute(args, { sb, admin, userId }) {
      let phone = args.phone;
      const clientId = args.client_id || null;

      if (!phone && clientId) {
        const { data: c } = await sb.from("clients").select("whatsapp, phone").eq("id", clientId).maybeSingle();
        phone = c?.whatsapp || c?.phone;
      }
      if (!phone) return { error: "Telefone não informado. Forneça phone ou client_id." };

      let soId: string | null = null;
      if (args.service_order_id) {
        const isUUID = UUID_RE.test(String(args.service_order_id));
        if (isUUID) {
          soId = args.service_order_id;
        } else {
          const { data: so } = await admin.from("service_orders").select("id").eq("service_order_number", args.service_order_id).maybeSingle();
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
    },
  },
  {
    name: "list_scheduled_whatsapp",
    description: "Lista as mensagens WhatsApp agendadas. Pode filtrar por status.",
    input_schema: {
      type: "object",
      properties: {
        status: { type: "string", enum: ["pending", "sent", "failed", "cancelled", "all"], description: "Filtro de status. Padrão: pending." },
        limit: { type: "number", description: "Máximo de registros. Padrão: 10." },
      },
    },
    risk: "low",
    async execute(args, { admin }) {
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
    },
  },
  {
    name: "cancel_scheduled_whatsapp",
    description: "Cancela um agendamento de WhatsApp pelo ID.",
    input_schema: {
      type: "object",
      properties: { scheduled_id: { type: "string", description: "UUID do agendamento a cancelar." } },
      required: ["scheduled_id"],
    },
    risk: "low",
    async execute(args, { admin }) {
      const { error } = await admin.from("whatsapp_scheduled_sends").update({ status: "cancelled" }).eq("id", args.scheduled_id);
      if (error) return { error: error.message };
      return { ok: true, cancelled_id: args.scheduled_id };
    },
  },
  {
    name: "schedule_self_reminder",
    description:
      "LEMBRETE PARA O PRÓPRIO USUÁRIO (a pessoa que está falando com você), NUNCA para um cliente. Use SEMPRE que o pedido for 'me lembre', 'me avise', 'lembrete pra mim', 'não me deixe esquecer', 'me cutuca amanhã' etc. Agenda uma mensagem de WhatsApp para o número do próprio solicitante. NÃO use client_id, NÃO use schedule_whatsapp_message, NÃO peça confirmação — é uma ação interna e segura.",
    input_schema: {
      type: "object",
      properties: {
        message: {
          type: "string",
          description: "O texto que a pessoa vai receber. Escreva claro e amigável, já com a lista de pendências que ela pediu para lembrar (uma por linha).",
        },
        delay_minutes: {
          type: "number",
          description: "Para lembretes RELATIVOS ('daqui a X minutos/horas'): minutos a partir de AGORA (ex.: 'daqui a 3 min' → 3; 'em 2 horas' → 120). Use este campo nesses casos e NÃO calcule horário absoluto. Com delay_minutes, pode omitir scheduled_at.",
        },
        scheduled_at: {
          type: "string",
          description: "Para horário ABSOLUTO ('amanhã 8h', 'hoje 15h'): data/hora ISO 8601 no horário de Brasília (ex: 2026-07-19T08:00:00 — pode omitir o fuso, o sistema assume Brasília). 'bem cedo'/'de manhã' → 07:00; 'amanhã' sem hora → 08:00. NÃO use para 'daqui a X' (use delay_minutes).",
        },
        recurrence_type: {
          type: "string",
          enum: ["once", "daily", "weekly", "monthly"],
          description: "Recorrência do lembrete. Padrão: once (uma vez).",
        },
      },
      required: ["message"],
    },
    risk: "low",
    async execute(args, { admin, userId }) {
      let when: Date;
      if (args.delay_minutes != null && Number(args.delay_minutes) > 0) {
        // Lembrete relativo: o servidor calcula "agora + X" (sem conta de fuso pelo modelo).
        when = new Date(Date.now() + Number(args.delay_minutes) * 60000);
      } else {
        const raw = String(args.scheduled_at || "").trim();
        // Horário absoluto sem fuso (naive) → interpreta como Brasília (-03:00), não UTC.
        const hasTz = /[zZ]$|[+-]\d{2}:?\d{2}$/.test(raw);
        when = new Date(hasTz || !raw ? raw : `${raw}-03:00`);
      }
      if (isNaN(when.getTime())) return { error: "Data/hora do lembrete inválida. Informe delay_minutes (relativo) ou scheduled_at (absoluto)." };
      // Rede de segurança: se caiu no passado (ex.: erro de fuso), joga 1 min à frente em vez
      // de disparar imediatamente.
      if (when.getTime() < Date.now() - 30000) when = new Date(Date.now() + 60000);
      const { data: u } = await admin.from("app_users").select("phone_normalized, full_name").eq("id", userId).maybeSingle();
      const phone = (u?.phone_normalized || "").replace(/\D/g, "");
      if (!phone) {
        return { error: "Você ainda não tem um número de WhatsApp cadastrado para receber lembretes. Cadastre em Configurações → Usuários (aba IA/Zap)." };
      }
      // Envelope padronizado do lembrete (com nome, se houver) — evita mensagem crua/genérica.
      const firstName = String(u?.full_name || "").trim().split(/\s+/)[0] || "";
      const reminderText = firstName
        ? `⏰ *Lembrete, ${firstName}!*\n\n${args.message}`
        : `⏰ *Lembrete!*\n\n${args.message}`;
      const scheduledAt = when.toISOString();
      const { data: created, error } = await admin
        .from("whatsapp_scheduled_sends")
        .insert({
          phone,
          message: reminderText,
          scheduled_at: scheduledAt,
          next_run_at: scheduledAt,
          recurrence_type: args.recurrence_type || "once",
          send_mode: "text",
          target_kind: "self_reminder",
          status: "pending",
          created_by: userId,
          auto_retry: true,
          max_attempts: 3,
        })
        .select("id, scheduled_at, recurrence_type")
        .single();
      if (error) return { error: error.message };
      return {
        ok: true,
        reminder_id: created.id,
        scheduled_at: created.scheduled_at,
        recurrence_type: created.recurrence_type,
        message_preview: args.message.slice(0, 120),
      };
    },
  },
  {
    name: "list_unanswered_messages",
    description:
      "CAIXA DE ENTRADA — mensagens recebidas que ainda NÃO foram respondidas. Use SEMPRE que o usuário perguntar coisas como 'quem me mandou mensagem?', 'quais mensagens não respondi?', 'tem alguém esperando resposta?', 'resumo do WhatsApp', 'como está a caixa de entrada?', 'o que chegou?'. Retorna os contatos cuja última mensagem recebida veio DEPOIS da última resposta enviada, com nome, há quanto tempo chegou, quantas não lidas, se é cliente conhecido (vinculado) ou outro contato/fornecedor, e uma prévia. Somente leitura — não pede confirmação. Ao responder, priorize clientes conhecidos e as mensagens mais recentes, e sempre mostre o nome e o horário/tempo.",
    input_schema: {
      type: "object",
      properties: {
        since_hours: { type: "number", description: "Opcional: considerar só mensagens recebidas nas últimas N horas (ex.: 24 = 'hoje', 48). Sem valor = todas as pendentes." },
        limit: { type: "number", description: "Máximo de contatos a retornar. Padrão 15, teto 30." },
      },
    },
    risk: "low",
    async execute(args, { admin }) {
      const limit = Math.min(Math.max(Number(args.limit) || 15, 1), 30);
      const since = Number(args.since_hours) > 0
        ? new Date(Date.now() - Number(args.since_hours) * 3_600_000).toISOString()
        : null;
      // Fonte da verdade = whatsapp_messages (via RPC whatsapp_pending_inbox). NÃO usa o
      // cache whatsapp_leads, que pode congelar. Pendente = última entrada depois da
      // última saída, por telefone; exclui a equipe interna (IA no WhatsApp).
      const { data, error } = await admin.rpc("whatsapp_pending_inbox", { _since: since, _limit: limit });
      if (error) return { error: error.message };
      const rows = (data as any[]) || [];
      if (rows.length === 0) {
        return { ok: true, total: 0, pendentes: [], message: "Nenhuma mensagem pendente de resposta." };
      }
      const now = Date.now();
      const pendentes = rows.map((r: any) => {
        const mins = Math.max(0, Math.round((now - new Date(r.last_inbound_at).getTime()) / 60000));
        const ha = mins < 60 ? `${mins} min` : mins < 1440 ? `${Math.round(mins / 60)} h` : `${Math.round(mins / 1440)} d`;
        return {
          contato: r.contato,
          tipo: r.is_client ? "cliente" : "contato",
          ha,
          recebida_em: r.last_inbound_at,
          nao_lidas: r.unread_count || 0,
          previa: prettyPreview(r.last_body),
        };
      });
      return { ok: true, total: pendentes.length, pendentes };
    },
  },
  {
    name: "mute_contact",
    description:
      "SILENCIAR um contato na caixa de entrada / digest de mensagens. Use quando o usuário disser 'não me avise sobre X', 'silenciar fulano', 'esse contato não é relevante', 'pode ignorar a [empresa]', 'para de me lembrar do fornecedor Y'. O contato para de aparecer em 'quem está esperando resposta'. Informe phone (só dígitos) OU name (parte do nome). Baixo risco.",
    input_schema: {
      type: "object",
      properties: {
        phone: { type: "string", description: "Telefone do contato (só dígitos, DDI+DDD). Opcional se informar o nome." },
        name: { type: "string", description: "Nome (ou parte) do contato. Opcional se informar o telefone." },
      },
    },
    risk: "low",
    async execute(args, { admin }) {
      const phone = String(args.phone || "").replace(/\D/g, "");
      const name = String(args.name || "").trim();
      if (!phone && !name) return { error: "Diga o telefone ou o nome do contato a silenciar." };
      const nowIso = new Date().toISOString();
      if (phone) {
        const { data: existing } = await admin.from("whatsapp_leads").select("id, name, phone_normalized").eq("phone_normalized", phone);
        if (existing && existing.length > 0) {
          await admin.from("whatsapp_leads").update({ muted_at: nowIso }).in("id", existing.map((l: any) => l.id));
          return { ok: true, silenciados: existing.map((l: any) => l.name || l.phone_normalized) };
        }
        const { data: created, error } = await admin.from("whatsapp_leads")
          .insert({ phone_normalized: phone, name: name || null, status: "pending", muted_at: nowIso })
          .select("name, phone_normalized").single();
        if (error) return { error: error.message };
        return { ok: true, silenciados: [created.name || created.phone_normalized] };
      }
      const { data: matches } = await admin.from("whatsapp_leads").select("id, name, phone_normalized").ilike("name", `%${name}%`).limit(10);
      if (!matches || matches.length === 0) return { error: `Não encontrei nenhum contato com "${name}".` };
      if (matches.length > 1) {
        return { precisa_desambiguar: true, opcoes: matches.map((l: any) => ({ nome: l.name, phone: l.phone_normalized })), instrucao: "Pergunte ao usuário qual silenciar e chame de novo com o phone específico." };
      }
      await admin.from("whatsapp_leads").update({ muted_at: nowIso }).eq("id", matches[0].id);
      return { ok: true, silenciados: [matches[0].name || matches[0].phone_normalized] };
    },
  },
  {
    name: "unmute_contact",
    description:
      "REATIVAR um contato silenciado (volta a aparecer na caixa de entrada / digest). Use quando o usuário disser 'volte a me avisar sobre X', 'reativar fulano', 'tirar do silêncio'. Informe phone OU name.",
    input_schema: {
      type: "object",
      properties: {
        phone: { type: "string", description: "Telefone do contato (só dígitos). Opcional se informar o nome." },
        name: { type: "string", description: "Nome (ou parte) do contato. Opcional se informar o telefone." },
      },
    },
    risk: "low",
    async execute(args, { admin }) {
      const phone = String(args.phone || "").replace(/\D/g, "");
      const name = String(args.name || "").trim();
      if (!phone && !name) return { error: "Diga o telefone ou o nome do contato a reativar." };
      let q = admin.from("whatsapp_leads").select("id, name, phone_normalized").not("muted_at", "is", null);
      q = phone ? q.eq("phone_normalized", phone) : q.ilike("name", `%${name}%`);
      const { data: matches } = await q.limit(10);
      if (!matches || matches.length === 0) return { error: "Não encontrei contato silenciado com esse dado." };
      if (matches.length > 1) {
        return { precisa_desambiguar: true, opcoes: matches.map((l: any) => ({ nome: l.name, phone: l.phone_normalized })) };
      }
      await admin.from("whatsapp_leads").update({ muted_at: null }).eq("id", matches[0].id);
      return { ok: true, reativado: matches[0].name || matches[0].phone_normalized };
    },
  },
];
