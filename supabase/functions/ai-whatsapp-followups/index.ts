// Edge Function: ai-whatsapp-followups (Fase 5)
// Follow-ups proativos com CLIENTES por WhatsApp, em duas réguas:
//   (A) Pós-atendimento: 2 a 7 dias após concluir uma OS (status completed/invoiced),
//       pergunta como foi o serviço. Dedupe: uma vez por OS.
//   (B) Reativação: cliente ativo cujo último serviço foi há mais de 6 meses.
//       Dedupe: uma vez por cliente por mês.
//
// Como fala com CLIENTE, respeita wa_test_mode: se ligado, o número é trocado pelo
// wa_test_number ANTES de enfileirar (o whatsapp-queue-worker não aplica test mode).
// Dedupe via ai_operator_alerts_log (ON CONFLICT DO NOTHING).
// Agendado via pg_cron (jobid 7, */30) — DESATIVADO até validação.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

// Espelha _shared/whatsapp/normalize.ts (Brasil, DDI 55).
function normalizePhone(raw: string, cc = "55"): string {
  if (!raw) return "";
  let d = String(raw).replace(/@s\.whatsapp\.net/g, "").replace(/@g\.us/g, "").replace(/@lid/g, "").replace(/\D/g, "");
  if (!d) return "";
  if (d.startsWith("00")) d = d.slice(2);
  if (d.length === 10 || d.length === 11) d = cc + d;
  if (d.length === 12 && d.startsWith("55")) { const n = d.slice(4); if (/^[6-9]/.test(n)) d = d.slice(0, 4) + "9" + n; }
  return d;
}

const REACT_CAP = 10; // teto de reativações por execução (evita rajada no 1º run)

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  const cronSecret = Deno.env.get("CRON_SECRET");
  if (cronSecret && req.headers.get("x-cron-secret") !== cronSecret) return jr({ error: "Unauthorized" }, 401);

  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: settingsRows } = await admin
      .from("app_settings").select("key, value")
      .in("key", ["wa_test_mode", "zapi_test_mode", "wa_test_number", "zapi_test_number", "company_name"]);
    const s = Object.fromEntries((settingsRows || []).map((r: any) => [r.key, r.value]));
    const testMode = (s["wa_test_mode"] ?? s["zapi_test_mode"]) === "true";
    const testNumber = ((s["wa_test_number"] ?? s["zapi_test_number"]) || "").replace(/\D/g, "");
    const companyName = s["company_name"] || "MarineFlow";
    if (testMode && !testNumber) return jr({ ok: false, reason: "test_mode_no_number" });

    const now = new Date();
    const toPhone = (raw: string) => (testMode ? testNumber : normalizePhone(raw));
    const rows: any[] = [];

    // grava o dedupe; retorna true se é novo (deve agir)
    async function claim(alert_key: string, meta: any): Promise<boolean> {
      const { data } = await admin
        .from("ai_operator_alerts_log")
        .upsert({ alert_key, meta }, { onConflict: "alert_key", ignoreDuplicates: true })
        .select("id");
      return (data?.length ?? 0) > 0;
    }

    // ── (A) Pós-atendimento ─────────────────────────────────────────────
    const d2 = new Date(now.getTime() - 2 * 864e5).toISOString();
    const d7 = new Date(now.getTime() - 7 * 864e5).toISOString();
    const { data: doneOS } = await admin
      .from("service_orders")
      .select("id, service_order_number, client_id, check_out_at")
      .in("status", ["completed", "invoiced"])
      .gte("check_out_at", d7)
      .lte("check_out_at", d2)
      .not("client_id", "is", null);

    let postservice = 0;
    for (const so of doneOS || []) {
      const { data: c } = await admin.from("clients").select("name, whatsapp, phone, active").eq("id", (so as any).client_id).maybeSingle();
      if (!c || c.active === false) continue;
      const raw = (c.whatsapp || c.phone || "") as string;
      if (!raw) continue;
      const phone = toPhone(raw);
      if (phone.length < 10) continue;
      if (!(await claim(`postservice:${(so as any).id}`, { so: (so as any).id }))) continue;
      const nome = (c.name || "").split(" ")[0] || "tudo bem";
      const msg = `Olá ${nome}! Aqui é o assistente da ${companyName} 🛥️. Há alguns dias concluímos o serviço (${(so as any).service_order_number}). Como foi sua experiência? Ficou tudo certo? Sua opinião ajuda muito a gente. 😊`;
      rows.push({ phone_normalized: phone, message: msg, source: "ai_followup", priority: 6 });
      postservice++;
    }

    // ── (B) Reativação (>6 meses sem serviço) ───────────────────────────
    const sixMonths = new Date(now.getTime() - 182 * 864e5);
    const monthKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
    const { data: allOS } = await admin
      .from("service_orders")
      .select("client_id, created_at")
      .not("client_id", "is", null)
      .neq("status", "cancelled")
      .order("created_at", { ascending: false })
      .limit(5000);

    const lastByClient = new Map<string, number>();
    for (const o of allOS || []) {
      const cid = (o as any).client_id as string;
      const t = new Date((o as any).created_at).getTime();
      if (!lastByClient.has(cid) || t > (lastByClient.get(cid) as number)) lastByClient.set(cid, t);
    }
    const inactiveIds = [...lastByClient.entries()].filter(([, t]) => t < sixMonths.getTime()).map(([cid]) => cid);

    let reactivation = 0;
    for (const cid of inactiveIds) {
      if (reactivation >= REACT_CAP) break;
      const { data: c } = await admin.from("clients").select("name, whatsapp, phone, active").eq("id", cid).maybeSingle();
      if (!c || c.active === false) continue;
      const raw = (c.whatsapp || c.phone || "") as string;
      if (!raw) continue;
      const phone = toPhone(raw);
      if (phone.length < 10) continue;
      if (!(await claim(`reactivate:${cid}:${monthKey}`, { client: cid }))) continue;
      const nome = (c.name || "").split(" ")[0] || "tudo bem";
      const msg = `Olá ${nome}! Aqui é o assistente da ${companyName} ⚓. Faz um tempo que não cuidamos da sua embarcação por aqui. Que tal agendar uma revisão ou manutenção? É só me chamar que eu te ajudo. 🙂`;
      rows.push({ phone_normalized: phone, message: msg, source: "ai_followup", priority: 7 });
      reactivation++;
    }

    let queued = 0;
    if (rows.length > 0) {
      const { data: inserted, error: qErr } = await admin.from("whatsapp_send_queue").insert(rows).select("id");
      if (qErr) throw qErr;
      queued = inserted?.length ?? 0;
    }

    return jr({ ok: true, queued, test_mode: testMode, postservice, reactivation });
  } catch (e: any) {
    console.error("[ai-whatsapp-followups] fatal", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});
