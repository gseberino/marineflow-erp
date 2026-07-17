import type { ToolDef } from "./registry.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Usa a edge function whatsapp-send (não whatsapp-send-text) para respeitar
 * wa_test_mode/wa_test_number do app_settings. Lê env em tempo de chamada
 * (não no import do módulo) para não quebrar testes que nunca chamam isto.
 */
async function sendWhatsapp(phone: string, message: string, jwt: string) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const r = await fetch(`${supabaseUrl}/functions/v1/whatsapp-send`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${jwt}`,
      apikey: anon,
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
      let phone = col.contact_whatsapp || col.phone;
      if (!phone) {
        const { data: c } = await sb.from("clients").select("whatsapp, phone").eq("id", col.client_id).maybeSingle();
        phone = c?.whatsapp || c?.phone;
      }
      if (!phone) return { error: "Sem telefone para enviar o lembrete." };
      const fmt = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(col.amount);
      const msg =
        args.custom_message ||
        `Olá${col.contact_name ? ` ${col.contact_name}` : ""}, lembrete amigável: você possui um valor de ${fmt} com vencimento em ${col.due_date}. Qualquer dúvida estamos à disposição.`;
      const r = await sendWhatsapp(phone, msg, jwt);
      if (r.ok) {
        await admin.from("collections").update({ last_auto_sent_at: new Date().toISOString() }).eq("id", col.id);
      }
      return r;
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
      const { data: c } = await admin.from("clients").select("whatsapp, phone, name").eq("id", so.client_id).maybeSingle();
      const phone = c?.whatsapp || c?.phone;
      if (!phone) return { error: "Cliente sem WhatsApp/telefone cadastrado." };
      const origin = appOrigin || settings.app_public_url || "https://hbrmarine.online";
      const link = `${origin}/view/${so.share_token}`;
      const msg = args.custom_message || `Olá${c?.name ? ` ${c.name}` : ""}, segue o link da OS ${so.service_order_number}: ${link}`;
      return await sendWhatsapp(phone, msg, jwt);
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
        scheduled_at: {
          type: "string",
          description: "Data e hora do lembrete em ISO 8601 (ex: 2026-07-17T07:00:00). 'bem cedo'/'de manhã' → 07:00; 'amanhã' sem hora → 08:00; 'mais tarde' → +3h.",
        },
        recurrence_type: {
          type: "string",
          enum: ["once", "daily", "weekly", "monthly"],
          description: "Recorrência do lembrete. Padrão: once (uma vez).",
        },
      },
      required: ["message", "scheduled_at"],
    },
    risk: "low",
    async execute(args, { admin, userId }) {
      const when = new Date(args.scheduled_at);
      if (isNaN(when.getTime())) return { error: "Data/hora do lembrete inválida." };
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
          previa: r.last_body ? String(r.last_body).slice(0, 100) : null,
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
