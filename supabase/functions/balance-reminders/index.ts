// Edge Function: balance-reminders
// Roda 1x/dia via pg_cron. RÉGUA INTERNA de cobrança do SALDO — nunca envia ao cliente. Faz DUAS
// coisas para o GESTOR:
//   (A) WhatsApp de marco: quando um saldo cruza marcos de atraso (venceu ontem / 7 / 30 dias),
//       enfileira um resumo em whatsapp_send_queue para os app_users (mesmo canal do resumo matinal).
//   (B) Sugestão no Caixa de Entrada do agente: para CADA saldo vencido sem sugestão pendente, cria
//       uma agenda_suggestion "Cobrar {cliente}" (detector='followup'), que o dono aceita ("quer que
//       eu cobre?") ou descarta. Idempotente por (recebível × usuário). Aceitar segue o fluxo padrão
//       (vira tarefa) — não dispara WhatsApp ao cliente. Cobrança ao cliente segue manual/opt-in.
// Voz única (secretário, Passo 4, 15/10/2026): com app_settings.voz_unica em sombra, o resumo (A) que
// entrou na fila é registrado no portão (avisos_do_dono) como "acaba" — a manhã já cobra (cobrança
// grande, marcos). O que sai não muda. Desligado (o padrão): nada é registrado.
// (20/10/2026, P4.5) Ligada de verdade (a manhã nova e o fechamento ligado no ar): o DONO pergunta ao portão antes e,
// com o "acaba", não recebe o resumo (A); portão ilegível = recebe como sempre. A equipe recebe como sempre.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { emBrasilia } from "../_shared/uma-voz/janela.ts";
import { avisoDosSaldos } from "../_shared/uma-voz/fontes.ts";
import { falaPeloPortao, lerDonoDaVoz, lerPortao, perguntarAoPortao, registrarParaTodos } from "../_shared/uma-voz/registrar.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
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

const fmtDate = (s?: string | null) => {
  if (!s) return "—";
  const [y, m, d] = String(s).slice(0, 10).split("-");
  return d && m && y ? `${d}/${m}/${y}` : String(s);
};

// Marcos de atraso (dias após o vencimento) para o WhatsApp de escalonamento.
const MILESTONES: { days: number; label: string; icon: string }[] = [
  { days: 1, label: "Venceu ontem", icon: "🟡" },
  { days: 7, label: "Vencido há 7 dias", icon: "🟠" },
  { days: 30, label: "Vencido há 30 dias", icon: "🔴" },
];

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  // Era fail-OPEN (`if (cronSecret) { ... }`): sem o env var, a função ficava aberta.
  const recusa = verificarCronSecret(req, corsHeaders, "balance-reminders");
  if (recusa) return recusa;

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

    const now = new Date();
    const todayISO = now.toISOString().slice(0, 10);
    const isoMinusDays = (n: number) => new Date(now.getTime() - n * 86400000).toISOString().slice(0, 10);
    const dry = new URL(req.url).searchParams.get("dry") === "1";

    // Destinatários internos (mesmo critério do resumo matinal): admin e financeiro.
    const { data: recipients } = await admin
      .from("app_users")
      .select("id, phone_normalized")
      .eq("ai_whatsapp_enabled", true)
      .eq("active", true)
      .not("phone_normalized", "is", null)
      .in("role", ["admin", "financial"]);
    const users = recipients || [];

    // ── (A) WhatsApp de marco ──────────────────────────────────────────────
    const sections: string[] = [];
    let milestoneItems = 0;
    for (const m of MILESTONES) {
      const { data: rows } = await admin
        .from("receivables")
        .select(`balance_amount, amount,
          clients!receivables_client_id_fkey(name),
          service_orders!receivables_service_order_id_fkey(service_order_number)`)
        .eq("is_deposit", false)
        .in("status", ["pending", "partially_paid"])
        .eq("due_date", isoMinusDays(m.days))
        .gt("balance_amount", 0);
      if (!rows || rows.length === 0) continue;
      const lines = rows.map((r: any) =>
        `• ${r.service_orders?.service_order_number || "OS"} — ${r.clients?.name || "cliente"}: *${brl(Number(r.balance_amount ?? r.amount ?? 0))}*`);
      milestoneItems += rows.length;
      sections.push(`${m.icon} *${m.label}:*\n${lines.join("\n")}`);
    }

    let queued = 0;
    let doDono: string | null = null;
    if (milestoneItems > 0 && users.length > 0 && !dry) {
      const message =
        `💰 *Saldos a cobrar*\n\n` + sections.join("\n\n") +
        `\n\n_Para lembrar o cliente, use "Enviar WhatsApp" em Contas a Receber › Cobranças._`;
      const aviso = avisoDosSaldos(emBrasilia(now).dia, milestoneItems, message);
      const portao = await lerPortao(admin);
      // (20/10/2026, P4.5) voz ligada: o dono pergunta antes ("acaba" = não recebe; erro = recebe como sempre)
      const dono = portao.modo === "ligado" ? await lerDonoDaVoz(admin) : null;
      let destinatarios = users;
      const doPortao = users.find((u: any) => falaPeloPortao(portao, dono, String(u.phone_normalized)));
      if (doPortao) {
        const fala = await perguntarAoPortao(admin, String(doPortao.phone_normalized), aviso, now);
        doDono = fala.decisao;
        if (!fala.manda) destinatarios = users.filter((u: any) => u !== doPortao);
      }
      const rows = destinatarios.map((u: any) => ({
        phone_normalized: String(u.phone_normalized), message, source: "balance_escalation", priority: 4,
      }));
      if (rows.length) {
        const { data: ins } = await admin.from("whatsapp_send_queue").insert(rows).select("id");
        queued = ins?.length ?? 0;
      }
      // Voz única em sombra: registra o que o portão faria (acaba: a manhã cobre). Nunca lança. Ligada: não registra.
      if (queued > 0) {
        await registrarParaTodos(admin, portao.modo, users.map((u: any) => u.phone_normalized), [aviso], now);
      }
    }

    // ── (B) Sugestões no Caixa de Entrada (uma por saldo vencido sem sugestão pendente) ──
    let suggestionsCreated = 0;
    if (users.length > 0) {
      const { data: overdue } = await admin
        .from("receivables")
        .select(`id, balance_amount, amount, due_date, client_id,
          clients!receivables_client_id_fkey(name),
          service_orders!receivables_service_order_id_fkey(service_order_number)`)
        .eq("is_deposit", false)
        .in("status", ["pending", "partially_paid"])
        .lt("due_date", todayISO)
        .gt("balance_amount", 0);

      const overdueRows = overdue || [];
      if (overdueRows.length > 0) {
        const recIds = overdueRows.map((r: any) => r.id);
        // Já existe sugestão de cobrança pendente para (recebível × usuário)?
        const { data: existing } = await admin
          .from("agenda_suggestions")
          .select("related_entity_id, target_user_id")
          .eq("related_entity_type", "receivable")
          .eq("status", "pending")
          .in("related_entity_id", recIds);
        const seen = new Set((existing || []).map((e: any) => `${e.related_entity_id}|${e.target_user_id}`));

        const toInsert: Record<string, unknown>[] = [];
        for (const r of overdueRows) {
          const cli = (r as any).clients?.name || "cliente";
          const os = (r as any).service_orders?.service_order_number || "OS";
          const val = Number((r as any).balance_amount ?? (r as any).amount ?? 0);
          const daysOverdue = Math.max(0, Math.round((now.getTime() - new Date(String(r.due_date)).getTime()) / 86400000));
          for (const u of users) {
            if (seen.has(`${r.id}|${u.id}`)) continue;
            toInsert.push({
              title: `Cobrar ${cli} — saldo ${brl(val)}`,
              kind: "task",
              suggested_due_at: now.toISOString(),
              priority: daysOverdue >= 7 ? "high" : "normal",
              evidence: `Saldo da ${os} (${brl(val)}) venceu em ${fmtDate(r.due_date)} — ${daysOverdue} dia(s) em atraso.`,
              confidence: 0.9,
              detector: "followup",
              origin: "manual_text",
              related_entity_type: "receivable",
              related_entity_id: r.id,
              client_id: (r as any).client_id ?? null,
              target_user_id: u.id,
              status: "pending",
            });
          }
        }
        if (toInsert.length > 0 && !dry) {
          const { data: ins } = await admin.from("agenda_suggestions").insert(toInsert as never).select("id");
          suggestionsCreated = ins?.length ?? 0;
        } else if (dry) {
          suggestionsCreated = toInsert.length;
        }
      }
    }

    return jr({ ok: true, dry, queued, milestone_items: milestoneItems, suggestions_created: suggestionsCreated, ...(doDono ? { dono_pelo_portao: doDono } : {}) });
  } catch (e: any) {
    console.error("[balance-reminders] fatal", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});
