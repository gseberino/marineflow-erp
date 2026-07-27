// Edge Function: balance-reminders
// Roda 1x/dia via pg_cron. RÉGUA INTERNA de cobrança do SALDO: avisa o GESTOR (não o cliente)
// quando um saldo cruza marcos de atraso (venceu ontem / 7 / 30 dias vencido), para ele decidir
// cobrar. Decisão do dono: lembrete automático de saldo é INTERNO; o cliente só é avisado no
// completion (opt-in) ou manualmente (botão "Enviar WhatsApp" na tela de Cobranças).
//
// Interno = enfileira em whatsapp_send_queue para os app_users com IA habilitada (mesmo canal do
// resumo matinal). Não envia nada ao cliente. Marcos com data EXATA (due = hoje − N) → cada título
// alerta no máximo 1x por marco, sem precisar de coluna "já alertado".

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const brl = (v: number) =>
  new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(v);

// Marcos de atraso (dias após o vencimento) e o rótulo de cada um.
const MILESTONES: { days: number; label: string; icon: string }[] = [
  { days: 1, label: "Venceu ontem", icon: "🟡" },
  { days: 7, label: "Vencido há 7 dias", icon: "🟠" },
  { days: 30, label: "Vencido há 30 dias", icon: "🔴" },
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const cronSecret = Deno.env.get("CRON_SECRET");
  if (cronSecret) {
    const incoming = req.headers.get("x-cron-secret");
    if (incoming !== cronSecret) return jr({ error: "Unauthorized" }, 401);
  }

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

    const now = new Date();
    const isoMinusDays = (n: number) => new Date(now.getTime() - n * 86400000).toISOString().slice(0, 10);

    // Coleta os saldos vencidos EXATAMENTE em cada marco.
    const sections: string[] = [];
    let totalItems = 0;
    for (const m of MILESTONES) {
      const target = isoMinusDays(m.days);
      const { data: rows } = await admin
        .from("receivables")
        .select(`
          balance_amount, amount, due_date,
          clients!receivables_client_id_fkey(name),
          service_orders!receivables_service_order_id_fkey(service_order_number)
        `)
        .eq("is_deposit", false)
        .in("status", ["pending", "partially_paid"])
        .eq("due_date", target)
        .gt("balance_amount", 0);

      if (!rows || rows.length === 0) continue;
      const lines = rows.map((r: any) => {
        const os = r.service_orders?.service_order_number || "OS";
        const cli = r.clients?.name || "cliente";
        const val = Number(r.balance_amount ?? r.amount ?? 0);
        return `• ${os} — ${cli}: *${brl(val)}*`;
      });
      totalItems += rows.length;
      sections.push(`${m.icon} *${m.label}:*\n${lines.join("\n")}`);
    }

    if (totalItems === 0) return jr({ ok: true, queued: 0, reason: "no_overdue_at_milestones" });

    const message =
      `💰 *Saldos a cobrar*\n\n` +
      sections.join("\n\n") +
      `\n\n_Para lembrar o cliente, use "Enviar WhatsApp" na tela de Cobranças._`;

    // Destinatários internos (mesmo critério do resumo matinal).
    const { data: recipients } = await admin
      .from("app_users")
      .select("id, phone_normalized")
      .eq("ai_whatsapp_enabled", true)
      .eq("active", true)
      .not("phone_normalized", "is", null);

    if (!recipients || recipients.length === 0) return jr({ ok: true, queued: 0, reason: "no_recipients" });

    // Dry-run (?dry=1): não enfileira — só pré-visualiza.
    if (new URL(req.url).searchParams.get("dry") === "1") {
      return jr({ ok: true, dry: true, items: totalItems, recipients: recipients.length, preview: message });
    }

    const rows = recipients.map((rec: any) => ({
      phone_normalized: String(rec.phone_normalized),
      message,
      source: "balance_escalation",
      priority: 4,
    }));
    const { data: inserted, error: qErr } = await admin.from("whatsapp_send_queue").insert(rows).select("id");
    if (qErr) throw qErr;

    return jr({ ok: true, queued: inserted?.length ?? 0, items: totalItems });
  } catch (e: any) {
    console.error("[balance-reminders] fatal", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});
