import type { ToolDef } from "./registry.ts";

// CRM proativo (Fase 2) — SÓ LEITURA, sem schema novo.
// A ideia: um negócio náutico de serviço vive de manutenção recorrente. Em vez de esperar o
// cliente lembrar, o agente encontra os ativos que passaram do intervalo e os clientes que
// sumiram — e o dono decide o que fazer. Nada é enviado automaticamente.

const STATUS_FEITO = ["completed", "invoiced"];

/** Data efetiva em que o serviço aconteceu: não existe completed_at no schema. */
function dataDoServico(so: any): string | null {
  return so.check_out_at || so.scheduled_end_at || so.updated_at || null;
}

function mesesDesde(iso: string | null): number | null {
  if (!iso) return null;
  const d = new Date(iso).getTime();
  if (isNaN(d)) return null;
  return Math.floor((Date.now() - d) / (30.44 * 86400000));
}

/** Último serviço concluído por chave (vessel_id ou client_id), em uma passada. */
async function ultimoServicoPor(sb: any, campo: "vessel_id" | "client_id"): Promise<Record<string, string>> {
  const { data } = await sb
    .from("service_orders")
    .select(`${campo}, check_out_at, scheduled_end_at, updated_at`)
    .in("status", STATUS_FEITO)
    .not(campo, "is", null)
    .order("updated_at", { ascending: false })
    .limit(1000);
  const out: Record<string, string> = {};
  for (const so of (data as any[]) || []) {
    const chave = String(so[campo]);
    const quando = dataDoServico(so);
    if (!quando) continue;
    if (!out[chave] || new Date(quando).getTime() > new Date(out[chave]).getTime()) out[chave] = quando;
  }
  return out;
}

/** Resumo curto dos equipamentos do ativo — dá ao agente o "o quê" sugerir revisar. */
function equipamentos(v: any): string[] {
  const eq: string[] = [];
  if (v.engine_brand || v.engine_model || v.engine_type) {
    eq.push(`Motor: ${[v.engine_brand, v.engine_model, v.engine_type].filter(Boolean).join(" ")}`);
  }
  if (v.battery_bank_summary) eq.push(`Baterias: ${String(v.battery_bank_summary).slice(0, 80)}`);
  if (v.inverter_charger_summary) eq.push(`Inversor/carregador: ${String(v.inverter_charger_summary).slice(0, 80)}`);
  if (v.navigation_electronics_summary) eq.push(`Eletrônica: ${String(v.navigation_electronics_summary).slice(0, 80)}`);
  return eq;
}

export const crmTools: ToolDef[] = [
  {
    name: "list_maintenance_due",
    description:
      "Lista ATIVOS (embarcações/motorhomes) que passaram do intervalo de manutenção — sem serviço concluído há X meses, ou nunca atendidos. Traz o cliente, quando foi o último serviço e os EQUIPAMENTOS do ativo, para você sugerir o que revisar (ex.: revisão anual do inversor/baterias). Só leitura — não envia nada ao cliente.",
    input_schema: {
      type: "object",
      properties: {
        months: { type: "number", description: "Intervalo em meses a partir do qual o ativo é considerado vencido (padrão 12)." },
        include_never_serviced: { type: "boolean", description: "Incluir ativos que nunca tiveram serviço concluído (padrão true)." },
        limit: { type: "number", description: "Máximo de ativos (padrão 15, teto 50)." },
      },
    },
    risk: "low",
    async execute(args, { sb }) {
      const meses = Number(args.months) > 0 ? Number(args.months) : 12;
      const incluirNunca = args.include_never_serviced !== false;
      const limite = Math.min(Number(args.limit) || 15, 50);

      const ultimoPorAtivo = await ultimoServicoPor(sb, "vessel_id");

      const { data: vessels, error } = await sb
        .from("vessels")
        .select("id, name, manufacturer, model, year, asset_type, client_id, engine_type, engine_brand, engine_model, battery_bank_summary, inverter_charger_summary, navigation_electronics_summary, clients(name)")
        .eq("active", true)
        .limit(500);
      if (error) throw error;

      const candidatos = ((vessels as any[]) || [])
        .map((v: any) => {
          const ultimo = ultimoPorAtivo[String(v.id)] || null;
          return { v, ultimo, meses: mesesDesde(ultimo) };
        })
        .filter((c) => (c.ultimo === null ? incluirNunca : (c.meses ?? 0) >= meses))
        // Nunca atendidos por último: o vencido de verdade tem prioridade comercial.
        .sort((a, b) => (b.meses ?? -1) - (a.meses ?? -1))
        .slice(0, limite);

      return {
        criterio: `sem serviço concluído há ${meses}+ meses${incluirNunca ? " (inclui nunca atendidos)" : ""}`,
        count: candidatos.length,
        results: candidatos.map((c) => ({
          vessel_id: c.v.id,
          ativo: c.v.name,
          tipo: c.v.asset_type || null,
          modelo: [c.v.manufacturer, c.v.model, c.v.year].filter(Boolean).join(" ") || null,
          cliente: c.v.clients?.name || "—",
          client_id: c.v.client_id,
          ultimo_servico: c.ultimo,
          meses_sem_servico: c.meses,
          nunca_atendido: c.ultimo === null,
          equipamentos: equipamentos(c.v),
        })),
        nota: "Sugestão comercial — confirme com o dono antes de qualquer contato com o cliente.",
      };
    },
  },
  {
    name: "list_inactive_clients",
    description:
      "Lista CLIENTES sem nenhum serviço concluído há X meses (oportunidade de reativação). Traz quando foi o último serviço e quantos ativos o cliente tem. Só leitura — não envia nada.",
    input_schema: {
      type: "object",
      properties: {
        months: { type: "number", description: "Meses sem serviço para considerar inativo (padrão 12)." },
        limit: { type: "number", description: "Máximo de clientes (padrão 15, teto 50)." },
      },
    },
    risk: "low",
    async execute(args, { sb }) {
      const meses = Number(args.months) > 0 ? Number(args.months) : 12;
      const limite = Math.min(Number(args.limit) || 15, 50);

      const ultimoPorCliente = await ultimoServicoPor(sb, "client_id");

      const { data: clients, error } = await sb.from("clients").select("id, name, whatsapp, phone").limit(1000);
      if (error) throw error;

      // Só clientes que JÁ compraram alguma vez — quem nunca comprou é prospecção, não reativação.
      const candidatos = ((clients as any[]) || [])
        .map((c: any) => ({ c, ultimo: ultimoPorCliente[String(c.id)] || null }))
        .filter((x) => x.ultimo !== null)
        .map((x) => ({ ...x, meses: mesesDesde(x.ultimo) }))
        .filter((x) => (x.meses ?? 0) >= meses)
        .sort((a, b) => (b.meses ?? 0) - (a.meses ?? 0))
        .slice(0, limite);

      return {
        criterio: `sem serviço concluído há ${meses}+ meses`,
        count: candidatos.length,
        results: candidatos.map((x) => ({
          client_id: x.c.id,
          cliente: x.c.name,
          tem_whatsapp: !!(x.c.whatsapp || x.c.phone),
          ultimo_servico: x.ultimo,
          meses_sem_servico: x.meses,
        })),
        nota: "Sugestão comercial — confirme com o dono antes de qualquer contato.",
      };
    },
  },
];
