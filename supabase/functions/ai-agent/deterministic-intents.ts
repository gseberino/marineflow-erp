/**
 * Deterministic fast-path for common ERP read queries on service orders.
 *
 * Eliminates AI provider calls for queries that can be answered directly
 * from the database when a service_order entityId is available in context.
 * A saved provider call = no RPM/RPD consumed, no 429 risk.
 *
 * Pure functions (detectSOQueryIntent, formatSODeterministicResponse) are
 * isolated for testability; tryFastPathResponse integrates with Supabase.
 */

export type SOQueryIntent =
  | "so_total"
  | "so_status"
  | "so_client"
  | "so_items"
  | "so_vessel";

// Write-action verbs — fast-path must NOT activate when present.
const WRITE_VERB_RE =
  /\b(cri[ae]r?|crie|adicion[ae]r?|adicione|atualiz[ae]r?|atualize|envi[ae]r?|cancel[ae]r?|cancele|agenda[rr]?|agende|ajust[ae]r?|ajuste|aplic[ae]r?|aplique|mud[ae]r?|alter[ae]r?|remov[ae]r?|exclui[rr]?|exclu[ia]|delet[ae]r?|insert|update|delete)\b/i;

// Explicit OS number in the message → let Gemini resolve it correctly.
const OS_NUMBER_RE = /OS[-\s]?\d{4}[-\s]?\d+|OS\s*#\s*\d+/i;

/**
 * Detects if a message is a simple, deterministic SO query that can be
 * answered directly from the database without calling the AI provider.
 *
 * Returns null when:
 *   - No entityId or entityType is not "service_order"
 *   - Message exceeds 200 characters (likely a complex multi-step request)
 *   - Message references an explicit OS number (Gemini should resolve it)
 *   - Message contains write-action verbs
 *   - No recognized read pattern found
 */
export function detectSOQueryIntent(
  message: string,
  contextEntityType: string | undefined,
  contextEntityId: string | null | undefined
): SOQueryIntent | null {
  if (!contextEntityId || contextEntityType !== "service_order") return null;

  const msg = message.toLowerCase().trim();

  if (msg.length > 200) return null;
  if (OS_NUMBER_RE.test(message)) return null;
  if (WRITE_VERB_RE.test(msg)) return null;

  if (/\b(valor|total|custo|preço|preco)\b/.test(msg)) return "so_total";
  if (/\b(status|estado|situa[çc][aã]o)\b/.test(msg)) return "so_status";
  if (/\b(cliente|dono|propriet[aá]rio)\b/.test(msg)) return "so_client";
  if (/\b(item|itens|pe[çc][ao]s?|servi[çc]os?)\b/.test(msg)) return "so_items";
  if (/\b(embarca[çc][aã]o|barco|lancha|veleiro)\b/.test(msg)) return "so_vessel";

  return null;
}

const fmtBRL = (v: number) =>
  new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(
    v ?? 0
  );

const STATUS_LABELS: Record<string, string> = {
  draft: "Rascunho",
  open: "Aberta",
  scheduled: "Agendada",
  in_progress: "Em andamento",
  awaiting_parts: "Aguardando peças",
  awaiting_client: "Aguardando cliente",
  approved: "Aprovada",
  completed: "Concluída",
  invoiced: "Faturada",
  cancelled: "Cancelada",
};

export type SOData = {
  service_order?: {
    service_order_number?: string;
    status?: string;
    grand_total?: number;
    discount_amount?: number;
    cliente?: string;
    embarcacao?: string;
    clients?: { full_name_or_company_name?: string };
    vessels?: { boat_name?: string };
    [key: string]: any;
  };
  parts?: { produto: string; quantidade: number; total: number }[];
  services?: {
    servico: string;
    quantidade: number;
    preco_unitario: number;
    total: number;
  }[];
};

/**
 * Formats a deterministic response from SO data for a recognized intent.
 * soData should match the shape returned by the get_service_order tool.
 */
export function formatSODeterministicResponse(
  intent: SOQueryIntent,
  soData: SOData
): string {
  const so = soData.service_order ?? {};
  const num = so.service_order_number ?? "?";
  const clientName =
    so.cliente ?? so.clients?.full_name_or_company_name ?? "—";
  const vesselName = so.embarcacao ?? so.vessels?.boat_name ?? "—";
  const parts = soData.parts ?? [];
  const services = soData.services ?? [];

  switch (intent) {
    case "so_total": {
      const partsTotal = parts.reduce((s, p) => s + (p.total ?? 0), 0);
      const servicesTotal = services.reduce((s, sv) => s + (sv.total ?? 0), 0);
      const discount = Number(so.discount_amount ?? 0);
      const grand = Number(
        so.grand_total ?? partsTotal + servicesTotal - discount
      );
      const rows = [
        partsTotal > 0 ? `| Peças | ${fmtBRL(partsTotal)} |` : "",
        servicesTotal > 0 ? `| Serviços | ${fmtBRL(servicesTotal)} |` : "",
        discount > 0 ? `| Desconto | −${fmtBRL(discount)} |` : "",
        `| **Total** | **${fmtBRL(grand)}** |`,
      ].filter(Boolean);
      return (
        `**OS ${num}** — ${clientName} / ${vesselName}\n\n` +
        `| Item | Valor |\n|---|---|\n` +
        rows.join("\n")
      );
    }
    case "so_status": {
      const label =
        STATUS_LABELS[so.status ?? ""] ?? so.status ?? "Desconhecido";
      return `**OS ${num}** está com status: **${label}**.`;
    }
    case "so_client":
      return `A **OS ${num}** pertence ao cliente **${clientName}**.`;
    case "so_items": {
      if (parts.length === 0 && services.length === 0) {
        return `A **OS ${num}** ainda não possui itens cadastrados.`;
      }
      const lines: string[] = [];
      if (parts.length > 0) {
        lines.push(`**Peças (${parts.length})**`);
        for (const p of parts)
          lines.push(`- ${p.produto} × ${p.quantidade} = ${fmtBRL(p.total)}`);
      }
      if (services.length > 0) {
        lines.push(`**Serviços (${services.length})**`);
        for (const s of services)
          lines.push(
            `- ${s.servico} × ${s.quantidade} = ${fmtBRL(s.total)}`
          );
      }
      return `**OS ${num}** — Itens:\n\n${lines.join("\n")}`;
    }
    case "so_vessel":
      return `A **OS ${num}** é da embarcação **${vesselName}**.`;
  }
}

/**
 * Tries to answer an incoming request directly from the database,
 * bypassing the AI provider entirely. Returns the formatted response
 * string when a fast-path applies, null otherwise (caller proceeds
 * to the normal AI loop).
 *
 * When this returns a non-null string: zero AI provider calls are made.
 */
export async function tryFastPathResponse(
  incoming: { role: string; content?: string }[],
  context: { entityType?: string; entityId?: string } | null | undefined,
  sb: any
): Promise<string | null> {
  const entityId = context?.entityId;
  const entityType = context?.entityType;

  const lastUserMsg =
    [...incoming].reverse().find((m) => m.role === "user")?.content ?? "";

  const intent = detectSOQueryIntent(lastUserMsg, entityType, entityId);
  if (intent === null) return null;

  const { data: so, error: soErr } = await sb
    .from("service_orders")
    .select("*, clients(full_name_or_company_name), vessels(boat_name)")
    .eq("id", entityId)
    .maybeSingle();
  if (soErr || !so) return null;

  const { data: parts } = await sb
    .from("service_order_parts")
    .select("id, quantity, line_total_sale, products(product_name)")
    .eq("service_order_id", entityId);

  const { data: services } = await sb
    .from("service_order_services")
    .select(
      "id, service_name_snapshot, quantity, unit_price_snapshot, line_total"
    )
    .eq("service_order_id", entityId);

  const soData: SOData = {
    service_order: {
      ...so,
      cliente: so.clients?.full_name_or_company_name ?? "—",
      embarcacao: so.vessels?.boat_name ?? "—",
    },
    parts: (parts ?? []).map((p: any) => ({
      produto: p.products?.product_name ?? "Desconhecido",
      quantidade: p.quantity,
      total: p.line_total_sale,
    })),
    services: (services ?? []).map((s: any) => ({
      servico: s.service_name_snapshot,
      quantidade: s.quantity,
      preco_unitario: s.unit_price_snapshot,
      total: s.line_total,
    })),
  };

  return formatSODeterministicResponse(intent, soData);
}
