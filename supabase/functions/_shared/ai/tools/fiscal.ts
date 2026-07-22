import { NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";

// Tools de fiscal SÓ-LEITURA. O agente consulta status/lista de notas emitidas, mas NUNCA
// emite, cancela ou corrige nota — emissão é ação fiscal real na SEFAZ, admin-only, e fica
// exclusivamente na tela (fiscal-emit). Ver plans/marineflow-ciclo2-fase1-execucao.md.

const STATUS_LABELS: Record<string, string> = {
  draft: "Rascunho",
  queued: "Na fila",
  processing: "Processando",
  authorized: "Autorizada",
  rejected: "Rejeitada",
  failed: "Falhou",
  cancelled: "Cancelada",
};

const STATUS_PT_EN: Record<string, string> = {
  rascunho: "draft",
  "na fila": "queued",
  processando: "processing",
  autorizada: "authorized",
  autorizadas: "authorized",
  rejeitada: "rejected",
  falhou: "failed",
  falha: "failed",
  falhas: "failed",
  cancelada: "cancelled",
};

const DOC_TYPE_LABELS: Record<string, string> = { nfe: "NF-e", nfce: "NFC-e", nfse: "NFS-e" };

// Valor best-effort a partir de source_items (só itens de produto do catálogo; serviços não
// entram no NF-e). Rotulado como "valor_itens" para não se confundir com o total da OS.
function sumSourceItems(sourceItems: unknown): number | null {
  if (!Array.isArray(sourceItems) || sourceItems.length === 0) return null;
  let total = 0;
  for (const it of sourceItems as Array<Record<string, unknown>>) {
    total += (Number(it.quantity) || 0) * (Number(it.unit_price) || 0);
  }
  return Math.round(total * 100) / 100;
}

export const fiscalTools: ToolDef[] = [
  {
    name: "list_fiscal_documents",
    description:
      "Lista notas fiscais JÁ EMITIDAS (só leitura — nunca emite). Filtre por cliente, por OS de origem, por status (autorizada/rejeitada/falhou/cancelada/processando) e por período em dias. Use para responder 'a nota do fulano saiu?', 'quais notas falharam essa semana?', 'notas emitidas hoje'. O agente NÃO emite, cancela nem corrige nota — isso é só pela tela.",
    input_schema: {
      type: "object",
      properties: {
        client_id: { type: "string", description: "Filtra pelas notas de um cliente." },
        service_order_id: { type: "string", description: "Filtra pela OS/venda de origem (origin_id)." },
        status: { type: "string", description: "Status: authorized|rejected|failed|cancelled|processing|queued|draft (aceita também em português)." },
        days: { type: "number", description: "Só notas dos últimos N dias (por created_at)." },
        limit: { type: "number", description: "Máximo de registros (padrão 20, teto 50)." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, { sb }) {
      let query = sb
        .from("issued_fiscal_documents")
        .select("id, document_type, origin_type, origin_id, client_id, environment, series, number, access_key, status, status_message, pdf_url, source_items, authorized_at, created_at")
        .order("created_at", { ascending: false })
        .limit(Math.min(Number(args.limit) || 20, 50));

      if (args.client_id) query = query.eq("client_id", args.client_id);
      if (args.service_order_id) query = query.eq("origin_id", args.service_order_id);
      if (args.status) {
        const raw = String(args.status).toLowerCase().trim();
        query = query.eq("status", STATUS_PT_EN[raw] ?? raw);
      }
      if (args.days != null && Number(args.days) > 0) {
        const since = new Date(Date.now() - Number(args.days) * 86400000).toISOString();
        query = query.gte("created_at", since);
      }

      const { data, error } = await query;
      if (error) throw error;

      // Nomes dos clientes em uma consulta (sem depender de FK embed).
      const clientIds = [...new Set((data || []).map((d: any) => d.client_id).filter(Boolean))];
      const namesById: Record<string, string> = {};
      if (clientIds.length) {
        const { data: clients } = await sb.from("clients").select("id, name").in("id", clientIds);
        for (const c of clients || []) namesById[String(c.id)] = c.name;
      }

      const results = (data || []).map((d: any) => ({
        id: d.id,
        tipo: DOC_TYPE_LABELS[d.document_type] || d.document_type,
        numero: d.number ? `${d.series ?? ""}/${d.number}` : null,
        status: STATUS_LABELS[d.status] || d.status,
        status_raw: d.status,
        motivo: d.status === "failed" || d.status === "rejected" ? d.status_message || null : null,
        ambiente: d.environment === "producao" ? "produção" : "homologação",
        cliente: d.client_id ? namesById[String(d.client_id)] || "—" : "—",
        origem: d.origin_type,
        chave_acesso: d.access_key || null,
        valor_itens: sumSourceItems(d.source_items),
        tem_danfe: !!d.pdf_url,
        autorizada_em: d.authorized_at || null,
        criada_em: d.created_at,
      }));
      return { count: results.length, results };
    },
  },
  {
    name: "get_fiscal_document",
    description:
      "Detalhe de UMA nota fiscal emitida (só leitura), por id ou por chave de acesso. Traz status atual, motivo de falha/rejeição (se houver) e se o DANFE/XML já está disponível. Não emite nem altera nada.",
    input_schema: {
      type: "object",
      properties: {
        id: { type: "string", description: "UUID do documento em issued_fiscal_documents." },
        access_key: { type: "string", description: "Chave de acesso da NF-e (44 dígitos)." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, { sb }) {
      if (!args.id && !args.access_key) return { error: "Informe id ou access_key da nota." };
      let query = sb
        .from("issued_fiscal_documents")
        .select("id, document_type, origin_type, origin_id, client_id, environment, series, number, access_key, protocol, status, status_code, status_message, pdf_url, xml_url, source_items, authorized_at, cancelled_at, created_at, updated_at");
      query = args.id ? query.eq("id", args.id) : query.eq("access_key", args.access_key);
      const { data: d, error } = await query.maybeSingle();
      if (error) throw error;
      if (!d) return { error: "Nota fiscal não encontrada." };

      let cliente = "—";
      if (d.client_id) {
        const { data: c } = await sb.from("clients").select("name").eq("id", d.client_id).maybeSingle();
        cliente = c?.name || "—";
      }

      return {
        nota: {
          id: d.id,
          tipo: DOC_TYPE_LABELS[d.document_type] || d.document_type,
          numero: d.number ? `${d.series ?? ""}/${d.number}` : null,
          status: STATUS_LABELS[d.status] || d.status,
          status_raw: d.status,
          codigo_sefaz: d.status_code || null,
          motivo: d.status_message || null,
          ambiente: d.environment === "producao" ? "produção" : "homologação",
          cliente,
          origem: { tipo: d.origin_type, id: d.origin_id },
          chave_acesso: d.access_key || null,
          protocolo: d.protocol || null,
          valor_itens: sumSourceItems(d.source_items),
          danfe_disponivel: !!d.pdf_url,
          xml_disponivel: !!d.xml_url,
          autorizada_em: d.authorized_at || null,
          cancelada_em: d.cancelled_at || null,
          criada_em: d.created_at,
          atualizada_em: d.updated_at,
        },
      };
    },
  },
];
