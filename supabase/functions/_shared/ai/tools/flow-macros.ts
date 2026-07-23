import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";
import { sendWhatsapp } from "./whatsapp.ts";

// Macros de FLUXO (Onda 2b) — "o LLM orquestra, o código executa".
// Cada uma colapsa um procedimento de vários passos numa única tool de risco alto:
// é interceptada por runAgentLoop → UMA confirmação (+ PIN) → executa tudo server-side.
// A confirmação mostra a lista/resumo real via buildPendingSummary (ver agent.ts).

const fmtBRL = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
const hojeISODate = () => new Date().toISOString().slice(0, 10);

export const flowMacroTools: ToolDef[] = [
  // ───────────────────────── COBRANÇA EM LOTE ─────────────────────────
  {
    name: "send_bulk_collection_reminders",
    description:
      "Envia lembrete de cobrança por WhatsApp para VÁRIOS clientes de uma vez (ex.: 'cobra todos os vencidos', 'manda a cobrança da lista'). Levante a lista ANTES (get_delinquency_plan / list_pending_collections) e passe os collection_ids escolhidos — a confirmação vai mostrar quem, quanto e o atraso, e você aprova o lote de uma vez. Quem já foi cobrado hoje é PULADO automaticamente. Envio externo: pede confirmação. Report-only: se um envio falhar, os outros seguem.",
    input_schema: {
      type: "object",
      properties: {
        collection_ids: {
          type: "array",
          items: { type: "string" },
          description: "UUIDs das cobranças (campo id de get_delinquency_plan/list_pending_collections). Passe só os que você escolheu cobrar.",
        },
        custom_message: {
          type: "string",
          description: "Opcional: mensagem única para todos. Se omitido, cada cliente recebe o texto padrão com o próprio valor e vencimento.",
        },
      },
      required: ["collection_ids"],
    },
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb, admin, jwt } = ctx;
      const ids: string[] = Array.isArray(args.collection_ids) ? (args.collection_ids as string[]).filter(Boolean) : [];
      if (ids.length === 0) return { error: "Nenhuma cobrança informada." };

      const hoje = hojeISODate();
      const enviados: Array<Record<string, unknown>> = [];
      const pulados: Array<Record<string, unknown>> = [];
      const falhas: Array<Record<string, unknown>> = [];

      for (const id of ids) {
        const { data: col } = await sb
          .from("collections")
          .select("id, amount, due_date, contact_whatsapp, phone, contact_name, client_id, last_auto_sent_at")
          .eq("id", id)
          .maybeSingle();
        if (!col) { falhas.push({ id, motivo: "cobrança não encontrada" }); continue; }

        // Não recobrar quem já foi cobrado hoje (mesma regra do get_delinquency_plan).
        if (col.last_auto_sent_at && String(col.last_auto_sent_at).slice(0, 10) === hoje) {
          pulados.push({ cliente: col.contact_name || null, motivo: "já cobrado hoje" });
          continue;
        }

        let phone = col.contact_whatsapp || col.phone;
        if (!phone && col.client_id) {
          const { data: c } = await sb.from("clients").select("whatsapp, phone").eq("id", col.client_id).maybeSingle();
          phone = c?.whatsapp || c?.phone;
        }
        if (!phone) { falhas.push({ cliente: col.contact_name || null, motivo: "sem telefone" }); continue; }

        const valor = fmtBRL.format(Number(col.amount) || 0);
        const msg = args.custom_message ||
          `Olá${col.contact_name ? ` ${col.contact_name}` : ""}, lembrete amigável: consta um valor de ${valor} com vencimento em ${col.due_date}. Qualquer dúvida, estamos à disposição.`;

        const r = await sendWhatsapp(phone, msg, jwt);
        if ((r as { ok?: boolean }).ok) {
          await admin.from("collections").update({ last_auto_sent_at: new Date().toISOString() }).eq("id", col.id);
          enviados.push({ cliente: col.contact_name || null, valor: Number(col.amount) || 0 });
        } else {
          falhas.push({ cliente: col.contact_name || null, motivo: (r as { error?: string }).error || "falha no envio" });
        }
      }

      return {
        ok: true,
        total_solicitado: ids.length,
        enviados: enviados.length,
        pulados: pulados.length,
        falhas: falhas.length,
        detalhe: { enviados, pulados, falhas },
        ...(pulados.length ? { nota: "Pulei quem já tinha sido cobrado hoje." } : {}),
      };
    },
  },

  // ──────────────── APROVAR ORÇAMENTO (fluxo completo, sinal já pago) ────────────────
  {
    name: "approve_quote_full",
    description:
      "APROVA um orçamento cujo SINAL JÁ FOI PAGO, em uma ação só: registra o sinal e converte em OS, e (opcional) agenda a OS e cria um lembrete de follow-up. Use quando o cliente aprovou E o dinheiro do sinal já entrou. Se o sinal ainda VAI ser cobrado, NÃO use isto — cobre o sinal primeiro (create_receivable / send_collection_reminder) e converta depois que ele pagar. Ação de dinheiro: confirmação + PIN. Report-only: se um passo falhar, os anteriores NÃO são desfeitos.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID do orçamento (draft)." },
        deposit_amount: { type: "number", description: "Valor do sinal JÁ PAGO." },
        payment_date: { type: "string", description: "Data do pagamento do sinal (ISO date)." },
        payment_method: { type: "string", description: "Forma de pagamento do sinal." },
        card_fee_percent: { type: "number", description: "Taxa de cartão em %, se houver." },
        follow_up_in_days: { type: "number", description: "Opcional: agenda um lembrete de follow-up PARA VOCÊ em N dias (às 08:00)." },
        scheduled_start_at: { type: "string", description: "Opcional: agenda a OS para esta data/hora (ISO)." },
        scheduled_end_at: { type: "string", description: "Opcional: fim do agendamento (ISO)." },
        technician_user_id: { type: "string", description: "Opcional: técnico responsável (define status 'scheduled')." },
        notes: { type: "string" },
      },
      required: ["service_order_id", "deposit_amount", "payment_date", "payment_method"],
    },
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb, admin, userId } = ctx;
      const passos: Array<Record<string, unknown>> = [];

      // 1) Núcleo: sinal + conversão. Se falhar, para aqui — não dá pra agendar OS que não converteu.
      const { error: convErr } = await admin.rpc("register_deposit_and_convert", {
        p_service_order_id: args.service_order_id,
        p_amount: args.deposit_amount,
        p_payment_date: String(args.payment_date).split("T")[0],
        p_payment_method: args.payment_method,
        p_card_fee_percent: args.card_fee_percent || 0,
        p_notes: args.notes || null,
      });
      if (convErr) {
        return { ok: false, passos: [{ passo: "sinal+conversão", status: "✖", erro: convErr.message }], nota: "Nada foi agendado — a conversão falhou." };
      }
      passos.push({ passo: "sinal+conversão", status: "✔" });

      // nº atual da OS (mesma linha; ganha novo número ao converter)
      const { data: so } = await sb.from("service_orders").select("service_order_number, client_id").eq("id", args.service_order_id).maybeSingle();

      // 2) Follow-up para o próprio dono (opcional) — espelha schedule_self_reminder.
      if (Number(args.follow_up_in_days) > 0) {
        try {
          const datePart = new Date(Date.now() + Number(args.follow_up_in_days) * 86400000).toISOString().slice(0, 10);
          const whenISO = new Date(`${datePart}T08:00:00-03:00`).toISOString(); // 08:00 Brasília
          const { data: u } = await admin.from("app_users").select("phone_normalized, full_name").eq("id", userId).maybeSingle();
          const phone = (u?.phone_normalized || "").replace(/\D/g, "");
          if (!phone) {
            passos.push({ passo: "follow-up", status: "✖", erro: "sem número de WhatsApp cadastrado para lembretes" });
          } else {
            const firstName = String(u?.full_name || "").trim().split(/\s+/)[0] || "";
            const texto = `Follow-up do ${so?.service_order_number || "orçamento aprovado"} — verificar andamento com o cliente.`;
            const { error: remErr } = await admin.from("whatsapp_scheduled_sends").insert({
              phone,
              message: firstName ? `⏰ *Lembrete, ${firstName}!*\n\n${texto}` : `⏰ *Lembrete!*\n\n${texto}`,
              scheduled_at: whenISO,
              next_run_at: whenISO,
              recurrence_type: "once",
              send_mode: "text",
              target_kind: "self_reminder",
              status: "pending",
              created_by: userId,
              auto_retry: true,
              max_attempts: 3,
            });
            passos.push(remErr ? { passo: "follow-up", status: "✖", erro: remErr.message } : { passo: "follow-up", status: "✔", em: whenISO.slice(0, 10) });
          }
        } catch (e) {
          passos.push({ passo: "follow-up", status: "✖", erro: (e as Error).message });
        }
      }

      // 3) Agendamento da OS (opcional) — espelha schedule_service_order.
      if (args.scheduled_start_at) {
        try {
          const update: Record<string, unknown> = { scheduled_start_at: args.scheduled_start_at };
          if (args.scheduled_end_at) update.scheduled_end_at = args.scheduled_end_at;
          if (args.technician_user_id) update.status = "scheduled";
          const { error: schErr } = await sb.from("service_orders").update(update).eq("id", args.service_order_id);
          if (!schErr && args.technician_user_id) {
            await sb.from("service_order_technicians")
              .upsert({ service_order_id: args.service_order_id, user_id: args.technician_user_id }, { onConflict: "service_order_id,user_id" })
              .catch(() => null);
          }
          passos.push(schErr ? { passo: "agendamento", status: "✖", erro: schErr.message } : { passo: "agendamento", status: "✔" });
        } catch (e) {
          passos.push({ passo: "agendamento", status: "✖", erro: (e as Error).message });
        }
      }

      return {
        ok: true,
        os: so?.service_order_number || null,
        passos,
        resumo: passos.map((p) => `${p.status} ${p.passo}`).join(" · "),
      };
    },
  },
];
