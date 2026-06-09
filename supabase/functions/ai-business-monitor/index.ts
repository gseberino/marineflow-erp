// Edge Function: ai-business-monitor
// Scans the database every hour for business conditions requiring attention and
// upserts structured alerts into ai_business_alerts. The ai-agent reads these
// via the get_business_alerts tool to give proactive briefings.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const respHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
};

type Severity = "critical" | "warning" | "info";

interface AlertInput {
  alert_type: string;
  severity: Severity;
  title: string;
  description: string;
  entity_type: string;
  entity_id: string;
  entity_number?: string | null;
  metadata?: Record<string, unknown>;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: { "Access-Control-Allow-Origin": "*" } });
  }

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Auth: same cron_worker_secret used by whatsapp workers
  const secret = req.headers.get("x-cron-secret") ?? "";
  const { data: setting } = await admin
    .from("app_settings")
    .select("value")
    .eq("key", "cron_worker_secret")
    .single();
  if (!setting || secret !== String(setting.value)) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: respHeaders,
    });
  }

  const now = new Date();
  const todayStr = now.toISOString().split("T")[0];
  const stats = { upserted: 0, resolved: 0, errors: [] as string[] };

  async function upsertAlert(a: AlertInput): Promise<void> {
    const { error } = await admin.from("ai_business_alerts").upsert(
      {
        alert_type: a.alert_type,
        severity: a.severity,
        title: a.title,
        description: a.description,
        entity_type: a.entity_type,
        entity_id: a.entity_id,
        entity_number: a.entity_number ?? null,
        metadata: a.metadata ?? {},
        last_seen_at: now.toISOString(),
        resolved_at: null,
      },
      { onConflict: "alert_type,entity_id" }
    );
    if (error) {
      stats.errors.push(`upsert(${a.alert_type},${a.entity_id}): ${error.message}`);
    } else {
      stats.upserted++;
    }
  }

  // Resolve alerts of a given type whose entity_id is no longer in the active set.
  async function resolveStale(alertType: string, activeIds: string[]): Promise<void> {
    let q = admin
      .from("ai_business_alerts")
      .update({ resolved_at: now.toISOString() })
      .eq("alert_type", alertType)
      .is("resolved_at", null);
    if (activeIds.length > 0) {
      // PostgREST `in` filter for UUID columns does not need quotes
      q = (q as any).not("entity_id", "in", `(${activeIds.join(",")})`);
    }
    const { error } = await q;
    if (error) stats.errors.push(`resolve(${alertType}): ${error.message}`);
  }

  function brl(v: unknown): string {
    return Number(v || 0).toLocaleString("pt-BR", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    });
  }

  try {
    const cut48h = new Date(now.getTime() - 48 * 3_600_000).toISOString();
    const cut5d  = new Date(now.getTime() -  5 * 86_400_000).toISOString();
    const cut3d  = new Date(now.getTime() -  3 * 86_400_000).toISOString();
    const cut24h = new Date(now.getTime() - 24 * 3_600_000).toISOString();

    // ── 1. OS em awaiting_client há mais de 48h ──────────────────────────────
    {
      const { data } = await admin
        .from("service_orders")
        .select("id, service_order_number, updated_at, grand_total, clients(full_name_or_company_name)")
        .eq("status", "awaiting_client")
        .lt("updated_at", cut48h)
        .limit(30);

      const activeIds: string[] = [];
      for (const so of data ?? []) {
        activeIds.push(so.id);
        const h = Math.round((now.getTime() - new Date(so.updated_at).getTime()) / 3_600_000);
        const client = (so.clients as any)?.full_name_or_company_name ?? "—";
        await upsertAlert({
          alert_type: "os_awaiting_client_long",
          severity: h > 96 ? "critical" : "warning",
          title: `OS ${so.service_order_number} aguardando aprovação do cliente`,
          description: `OS ${so.service_order_number} (${client}) aguarda aprovação há ${h}h.${so.grand_total ? ` Valor: R$ ${brl(so.grand_total)}` : ""}`,
          entity_type: "service_order",
          entity_id: so.id,
          entity_number: so.service_order_number,
          metadata: { hours_waiting: h, grand_total: so.grand_total },
        });
      }
      await resolveStale("os_awaiting_client_long", activeIds);
    }

    // ── 2. OS em awaiting_parts há mais de 5 dias ────────────────────────────
    {
      const { data } = await admin
        .from("service_orders")
        .select("id, service_order_number, updated_at, clients(full_name_or_company_name)")
        .eq("status", "awaiting_parts")
        .lt("updated_at", cut5d)
        .limit(30);

      const activeIds: string[] = [];
      for (const so of data ?? []) {
        activeIds.push(so.id);
        const d = Math.round((now.getTime() - new Date(so.updated_at).getTime()) / 86_400_000);
        const client = (so.clients as any)?.full_name_or_company_name ?? "—";
        await upsertAlert({
          alert_type: "os_awaiting_parts_long",
          severity: d > 10 ? "critical" : "warning",
          title: `OS ${so.service_order_number} aguardando peças há ${d} dias`,
          description: `OS ${so.service_order_number} (${client}) está há ${d} dias aguardando peças.`,
          entity_type: "service_order",
          entity_id: so.id,
          entity_number: so.service_order_number,
          metadata: { days_waiting: d },
        });
      }
      await resolveStale("os_awaiting_parts_long", activeIds);
    }

    // ── 3. OS completed sem faturamento há mais de 3 dias ───────────────────
    {
      const { data } = await admin
        .from("service_orders")
        .select("id, service_order_number, updated_at, grand_total, clients(full_name_or_company_name)")
        .eq("status", "completed")
        .eq("invoicing_status", "not_invoiced")
        .lt("updated_at", cut3d)
        .limit(30);

      const activeIds: string[] = [];
      for (const so of data ?? []) {
        activeIds.push(so.id);
        const d = Math.round((now.getTime() - new Date(so.updated_at).getTime()) / 86_400_000);
        const client = (so.clients as any)?.full_name_or_company_name ?? "—";
        await upsertAlert({
          alert_type: "os_completed_not_invoiced",
          severity: d > 7 ? "critical" : "warning",
          title: `OS ${so.service_order_number} concluída sem faturamento`,
          description: `OS ${so.service_order_number} (${client}) concluída há ${d} dias sem faturar.${so.grand_total ? ` Valor: R$ ${brl(so.grand_total)}` : ""}`,
          entity_type: "service_order",
          entity_id: so.id,
          entity_number: so.service_order_number,
          metadata: { days_since_completion: d, grand_total: so.grand_total },
        });
      }
      await resolveStale("os_completed_not_invoiced", activeIds);
    }

    // ── 4. Recebíveis vencidos ────────────────────────────────────────────────
    {
      const { data } = await admin
        .from("receivables")
        .select("id, description, due_date, amount, balance_amount, clients(full_name_or_company_name), service_orders(service_order_number)")
        .lt("due_date", todayStr)
        .neq("status", "paid")
        .limit(30);

      const activeIds: string[] = [];
      for (const rec of data ?? []) {
        activeIds.push(rec.id);
        const daysOverdue = Math.round(
          (now.getTime() - new Date(rec.due_date).getTime()) / 86_400_000
        );
        const amt = Number(rec.balance_amount || rec.amount || 0);
        const client = (rec.clients as any)?.full_name_or_company_name ?? rec.description ?? "—";
        const soNum = (rec.service_orders as any)?.service_order_number;
        await upsertAlert({
          alert_type: "receivable_overdue",
          severity: daysOverdue > 30 ? "critical" : daysOverdue > 7 ? "warning" : "info",
          title: `Recebível vencido: ${client}`,
          description: `${client}${soNum ? ` (${soNum})` : ""} — R$ ${brl(amt)} venceu há ${daysOverdue} dia${daysOverdue !== 1 ? "s" : ""} (${rec.due_date}).`,
          entity_type: "receivable",
          entity_id: rec.id,
          entity_number: soNum ?? null,
          metadata: { days_overdue: daysOverdue, amount: amt, due_date: rec.due_date },
        });
      }
      await resolveStale("receivable_overdue", activeIds);
    }

    // ── 5. Orçamentos externos aguardando revisão interna > 48h ─────────────
    {
      const { data } = await admin
        .from("external_quotes")
        .select("id, quote_number, created_at, grand_total, clients(full_name_or_company_name)")
        .eq("status", "pending_approval")
        .lt("created_at", cut48h)
        .limit(20);

      const activeIds: string[] = [];
      for (const q of data ?? []) {
        activeIds.push(q.id);
        const h = Math.round((now.getTime() - new Date(q.created_at).getTime()) / 3_600_000);
        const client = (q.clients as any)?.full_name_or_company_name ?? "—";
        await upsertAlert({
          alert_type: "external_quote_pending_review",
          severity: h > 96 ? "critical" : "warning",
          title: `Orçamento ${q.quote_number} aguardando revisão`,
          description: `Orçamento ${q.quote_number} (${client}) aguarda revisão interna há ${h}h.${q.grand_total ? ` Valor: R$ ${brl(q.grand_total)}` : ""}`,
          entity_type: "external_quote",
          entity_id: q.id,
          entity_number: q.quote_number,
          metadata: { hours_pending: h, grand_total: q.grand_total },
        });
      }
      await resolveStale("external_quote_pending_review", activeIds);
    }

    // ── 6. OS scheduled/open há mais de 24h sem técnico ─────────────────────
    {
      const { data } = await admin
        .from("service_orders")
        .select(
          "id, service_order_number, status, created_at, clients(full_name_or_company_name), service_order_technicians(id)"
        )
        .in("status", ["scheduled", "open"])
        .lt("created_at", cut24h)
        .limit(30);

      const noTechOs = (data ?? []).filter(
        (so) => !((so.service_order_technicians as any[])?.length > 0)
      );
      const activeIds: string[] = [];
      for (const so of noTechOs) {
        activeIds.push(so.id);
        const h = Math.round((now.getTime() - new Date(so.created_at).getTime()) / 3_600_000);
        const client = (so.clients as any)?.full_name_or_company_name ?? "—";
        const statusLabel = so.status === "scheduled" ? "agendada" : "aberta";
        await upsertAlert({
          alert_type: "os_no_technician",
          severity: "warning",
          title: `OS ${so.service_order_number} sem técnico responsável`,
          description: `OS ${so.service_order_number} (${client}) está ${statusLabel} há ${h}h sem técnico atribuído.`,
          entity_type: "service_order",
          entity_id: so.id,
          entity_number: so.service_order_number,
          metadata: { hours_open: h, os_status: so.status },
        });
      }
      await resolveStale("os_no_technician", activeIds);
    }

    // ── 7. Due agent tasks → surface as alerts ──────────────────────────────
    {
      const { data: dueTasks } = await admin
        .from("ai_agent_tasks")
        .select("id, title, description, due_at, entity_type, entity_id, entity_number, priority")
        .eq("status", "pending")
        .lte("due_at", now.toISOString())
        .limit(20);

      const dueTaskIds: string[] = [];
      for (const task of dueTasks ?? []) {
        dueTaskIds.push(task.id);
        await upsertAlert({
          alert_type: "agent_task_due",
          severity: task.priority === "urgent" || task.priority === "high" ? "critical" : "warning",
          title: `Tarefa: ${task.title}`,
          description: task.description,
          entity_type: task.entity_type ?? "agent_task",
          entity_id: task.id,
          entity_number: task.entity_number ?? null,
          metadata: { task_entity_id: task.entity_id, task_entity_type: task.entity_type, priority: task.priority },
        });
      }
      await resolveStale("agent_task_due", dueTaskIds);
    }
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    stats.errors.push(`main: ${msg}`);
    console.error("[ai-business-monitor] Fatal error:", err);
  }

  console.log("[ai-business-monitor]", JSON.stringify(stats));
  return new Response(
    JSON.stringify({ ok: stats.errors.length === 0, ...stats }),
    { headers: respHeaders }
  );
});
