import type { ToolCtx, ToolDef } from "./registry.ts";

// EMISSÃO FISCAL pelo agente (NF-e e NFS-e) — a ação mais delicada do sistema.
//
// Desenho em dois tempos, de propósito:
//   1. ENSAIO (preview_*): monta a nota a partir da OS sem tocar em SEFAZ/prefeitura e
//      sem consumir numeração. Erra aqui, não na nota.
//   2. EMISSÃO (emit_*): risco ALTO → confirmação + PIN do dono. Irreversível.
//
// A OS mista gera DOIS documentos: NF-e com as peças (SEFAZ) e NFS-e com a mão de obra
// (prefeitura, padrão nacional) — regra do item 14.01 da LC 116, peças ficam no ICMS.

/** Chama a fiscal-emit pelo caminho interno do agente (segredo + admin declarado). */
async function chamarFiscalEmit(ctx: ToolCtx, payload: Record<string, unknown>) {
  const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/fiscal-emit`;
  const r = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      // Só Authorization com service-role (sem `apikey` — lição do 401 no envio de WhatsApp).
      Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
      // Autoriza o caminho interno; a fiscal-emit revalida o cargo do acting_user_id.
      "x-internal-secret": Deno.env.get("AI_INTERNAL_SECRET") ?? "",
    },
    body: JSON.stringify({ ...payload, acting_user_id: ctx.userId }),
  });
  const body = await r.json().catch(() => ({}));
  if (!r.ok) return { erro: (body as any)?.error || `HTTP ${r.status}` };
  return { dados: body as Record<string, unknown> };
}

/** Guarda comum: só admin mexe com nota fiscal, revalidado no execute (não só no filtro). */
function bloqueiaNaoAdmin(ctx: ToolCtx): { error: string } | null {
  if (ctx.userRole !== "admin") return { error: "Só um administrador pode trabalhar com nota fiscal." };
  return null;
}

export const fiscalEmitTools: ToolDef[] = [
  {
    name: "preview_fiscal_note",
    description:
      "Monta o ESPELHO (Pré-DANFE) da NF-e de uma Ordem de Serviço para CONFERÊNCIA. NÃO emite, NÃO toca na SEFAZ e NÃO consome numeração — é ensaio. Mostra o que entra na nota (peças), o total, o número previsto, o ambiente (produção ou homologação) e, principalmente, O QUE FICA DE FORA: a mão de obra, que sai na NFS-e (use preview_fiscal_service_note para ela). Use SEMPRE antes de emitir.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS que vai virar nota." },
        nature_of_operation: { type: "string", description: "Natureza da operação (padrão: venda)." },
      },
      required: ["service_order_id"],
    },
    risk: "low",
    roles: ["admin"],
    async execute(args, ctx) {
      const bloqueio = bloqueiaNaoAdmin(ctx);
      if (bloqueio) return bloqueio;

      const r = await chamarFiscalEmit(ctx, {
        action: "preview",
        service_order_id: args.service_order_id,
        nature_of_operation: args.nature_of_operation,
      });
      if (r.erro) return { error: r.erro };

      const d = r.dados as any;
      const resumo = d?.resumo_os ?? {};
      const producao = d?.environment === "producao";
      return {
        ok: true,
        conferencia: {
          os: resumo.os ?? null,
          cliente: resumo.cliente ?? null,
          pecas_na_nota: resumo.pecas_na_nota ?? null,
          total_da_nota: resumo.total_pecas ?? null,
          numero_previsto: d?.number ?? null,
          serie: d?.series ?? null,
          ambiente: producao ? "PRODUÇÃO (nota real)" : "homologação (teste)",
        },
        fica_de_fora: {
          servicos: resumo.servicos_fora_da_nfe ?? 0,
          total_servicos: resumo.total_servicos_fora ?? 0,
          aviso: resumo.aviso_nfse ?? null,
        },
        proximo_passo: producao
          ? "Se estiver correto, emita com emit_fiscal_note — em PRODUÇÃO a nota é real e irreversível."
          : "Se estiver correto, emita com emit_fiscal_note (ambiente de homologação).",
      };
    },
  },
  {
    name: "emit_fiscal_note",
    description:
      "EMITE a NF-e de uma Ordem de Serviço na SEFAZ. Ação IRREVERSÍVEL em produção. Só admin, exige confirmação e PIN. Regras: (1) SEMPRE rode preview_fiscal_note antes e mostre a conferência ao usuário; (2) diga em voz alta o valor, o ambiente e o que fica de fora (mão de obra); (3) nunca emita por iniciativa própria — só quando o usuário pedir explicitamente para emitir.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS que vira nota." },
        nature_of_operation: { type: "string", description: "Natureza da operação (padrão: venda)." },
      },
      required: ["service_order_id"],
    },
    risk: "high",
    roles: ["admin"],
    async execute(args, ctx) {
      const bloqueio = bloqueiaNaoAdmin(ctx);
      if (bloqueio) return bloqueio;

      const r = await chamarFiscalEmit(ctx, {
        action: "create",
        service_order_id: args.service_order_id,
        nature_of_operation: args.nature_of_operation,
      });
      if (r.erro) return { error: r.erro, dica: "Nada foi emitido. Confira os dados fiscais do cliente e do produto e tente de novo." };

      const d = r.dados as any;
      if (d?.reused) {
        return { ok: true, ja_existia: true, documento_id: d?.data?.id ?? null, mensagem: "Essa OS já tinha uma nota ativa — nada foi emitido em duplicidade." };
      }
      return {
        ok: true,
        documento_id: d?.data?.id ?? null,
        status: d?.data?.status ?? null,
        ambiente: d?.data?.environment === "producao" ? "PRODUÇÃO (nota real)" : "homologação",
        mensagem: "Nota enviada para autorização. A SEFAZ responde em segundos — consulte com list_fiscal_documents para ver se foi autorizada.",
      };
    },
  },
  {
    // [NOVO-010] A tool que faltava: o agente sabia emitir a NF-e e avisava (errado) que
    // a NFS-e "não estava disponível". Espelha o par preview/emit da NF-e.
    name: "preview_fiscal_service_note",
    description:
      "Monta a CONFERÊNCIA da NFS-e (nota de SERVIÇO) de uma Ordem de Serviço. NÃO emite, NÃO toca na prefeitura, NÃO consome numeração — é ensaio. Mostra os serviços que entram, o total, o código de tributação nacional (e de onde ele veio: cadastro do serviço ou verbo fiscal) e avisa que as peças ficam de fora (elas são NF-e). Se algum serviço estiver sem cadastro fiscal, diz QUAL. Use SEMPRE antes de emitir a NFS-e.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS que vai virar nota de serviço." },
      },
      required: ["service_order_id"],
    },
    risk: "low",
    roles: ["admin"],
    async execute(args, ctx) {
      const bloqueio = bloqueiaNaoAdmin(ctx);
      if (bloqueio) return bloqueio;

      const r = await chamarFiscalEmit(ctx, {
        action: "prepare",
        document_type: "nfse",
        service_order_id: args.service_order_id,
      });
      if (r.erro) {
        return {
          error: r.erro,
          dica: "Nada foi emitido. Se faltar cadastro fiscal, o caminho é Configurações → Fiscal → Verbos (vale para a atividade inteira) ou o cadastro do serviço.",
        };
      }

      const d = r.dados as any;
      const resumo = d?.data?.resumo ?? {};
      return {
        ok: true,
        conferencia: {
          os: resumo.os ?? null,
          cliente: resumo.cliente ?? null,
          servicos_na_nota: resumo.servicos_na_nota ?? null,
          total_da_nota: resumo.total_servicos ?? null,
          codigo_de_tributacao: resumo.codigo_de_tributacao ?? null,
          origem_do_codigo: resumo.origem_do_codigo ?? null,
          iss_rate: resumo.iss_rate ?? null,
        },
        fica_de_fora: { aviso: resumo.aviso_nfe ?? "As peças da OS não entram na NFS-e — elas são NF-e." },
        proximo_passo:
          "Se estiver correto, emita com emit_fiscal_service_note. Numa OS com peças, ofereça TAMBÉM a NF-e (preview_fiscal_note).",
      };
    },
  },
  {
    name: "emit_fiscal_service_note",
    description:
      "EMITE a NFS-e (nota de SERVIÇO) de uma Ordem de Serviço na prefeitura, via padrão nacional. Ação IRREVERSÍVEL (o cancelamento tem prazo municipal curto). Só admin, exige confirmação e PIN. Regras: (1) SEMPRE rode preview_fiscal_service_note antes e mostre a conferência; (2) diga em voz alta o valor, o código de tributação e o ambiente; (3) as peças NÃO entram — ofereça a NF-e junto quando houver; (4) nunca emita por iniciativa própria.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS que vira nota de serviço." },
      },
      required: ["service_order_id"],
    },
    risk: "high",
    roles: ["admin"],
    async execute(args, ctx) {
      const bloqueio = bloqueiaNaoAdmin(ctx);
      if (bloqueio) return bloqueio;

      const r = await chamarFiscalEmit(ctx, {
        document_type: "nfse",
        service_order_id: args.service_order_id,
        // Estável por OS: retry do agente não vira segunda nota (mesma chave da tela).
        idempotency_key: `nfse-os-${args.service_order_id}`,
      });
      if (r.erro) {
        return { error: r.erro, dica: "Nada foi emitido. Confira o cadastro fiscal dos serviços e os dados NFS-e da empresa e tente de novo." };
      }

      const d = r.dados as any;
      if (d?.reused) {
        return { ok: true, ja_existia: true, documento_id: d?.data?.id ?? null, mensagem: "Essa OS já tinha uma NFS-e ativa — nada foi emitido em duplicidade." };
      }
      return {
        ok: true,
        documento_id: d?.data?.id ?? null,
        status: d?.data?.status ?? null,
        ambiente: d?.data?.environment === "producao" ? "PRODUÇÃO (nota real)" : "homologação",
        aviso: d?.aviso ?? null,
        mensagem: "NFS-e enviada para emissão. A prefeitura responde em instantes — consulte com list_fiscal_documents.",
      };
    },
  },
];
