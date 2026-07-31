import type { ToolDef } from "./registry.ts";
import { blockTechnician, NON_TECHNICIAN_ROLES } from "./registry.ts";

// Fase 5 — materiais complementares e margem real.
// Plano: plans/marineflow-execucao-os-roteiro.md (P19, P20)
//
// Estas tools mexem em custo e margem: cargo `technician` NÃO acessa, pela mesma
// regra que já vale no resto do sistema (técnico não vê preço).

export const materialsOpsTools: ToolDef[] = [
  {
    name: "apply_service_material_kit",
    description:
      "Lança na OS os materiais complementares do kit do serviço (terminais, cabos, abraçadeiras, veda-rosca). Use quando alguém pedir para 'lançar os materiais', 'colocar os complementares' ou ao preparar a OS para execução. Idempotente: rodar de novo não duplica.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS." },
        service_id: { type: "string", description: "UUID do serviço cujo kit será aplicado." },
      },
      required: ["service_order_id", "service_id"],
    },
    risk: "medium",   // mexe em estoque (a inserção dispara reserva) e em custo
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const bloqueio = blockTechnician(ctx);
      if (bloqueio) return bloqueio;

      const { data, error } = await ctx.sb.rpc("apply_service_material_kit", {
        p_service_order_id: args.service_order_id,
        p_service_id: args.service_id,
      });
      if (error) throw error;
      return data;
    },
  },

  {
    name: "get_service_order_margin",
    description:
      "Margem REAL de uma OS: faturado menos mão de obra apontada no roteiro, material consumido e taxa de materiais de oficina. Use quando perguntarem 'deu lucro?', 'como ficou a margem', 'valeu a pena'. Atenção: se o roteiro não tiver horas apontadas, a mão de obra entra como zero e a margem sai inflada — avise quando for o caso.",
    input_schema: {
      type: "object",
      properties: { service_order_id: { type: "string" } },
      required: ["service_order_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const bloqueio = blockTechnician(ctx);
      if (bloqueio) return bloqueio;

      const { data, error } = await ctx.sb
        .from("v_service_order_margin")
        .select("*")
        .eq("id", args.service_order_id)
        .maybeSingle();
      if (error) throw error;
      if (!data) return { error: "OS não encontrada." };

      const semApontamento = Number(data.horas_reais || 0) === 0;
      return {
        os: data.service_order_number,
        faturado: data.faturado,
        custo_mao_de_obra: data.custo_mao_de_obra,
        horas_reais: data.horas_reais,
        custo_material: data.custo_material,
        custo_material_extra: data.custo_material_extra,
        taxa_materiais: data.taxa_materiais,
        margem_reais: data.margem_reais,
        margem_pct: data.margem_pct,
        confiavel: !semApontamento,
        ressalva: semApontamento
          ? "SEM HORAS APONTADAS no roteiro: a mão de obra entrou como zero, então esta margem está INFLADA. Diga isso ao responder."
          : null,
      };
    },
  },

  {
    name: "list_material_leakage",
    description:
      "Lista o material que entrou na OS FORA do que estava planejado (source='extra') e os serviços que ainda não têm kit de materiais cadastrado. É o vazamento de margem: custo que aparece na execução e ninguém orçou. Use em revisão de resultado ou quando o dono perguntar por que a margem caiu.",
    input_schema: {
      type: "object",
      properties: {
        dias: { type: "number", description: "Janela em dias. Padrão 90." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const bloqueio = blockTechnician(ctx);
      if (bloqueio) return bloqueio;
      const dias = args.dias ?? 90;
      const desde = new Date(Date.now() - dias * 86400000).toISOString();

      const { data: extras } = await ctx.sb
        .from("service_order_parts")
        .select("quantity, line_total_cost, source, products(name), service_orders(service_order_number, created_at)")
        .eq("source", "extra")
        .gte("created_at", desde)
        .limit(50);

      const { data: semKit } = await ctx.sb
        .from("services")
        .select("id, name")
        .is("material_kit_product_id", null)
        .eq("active", true)
        .limit(20);

      const total = (extras || []).reduce((s: number, e: any) => s + Number(e.line_total_cost || 0), 0);

      return {
        janela_dias: dias,
        material_extra: {
          linhas: (extras || []).length,
          custo_total: Math.round(total * 100) / 100,
          itens: (extras || []).map((e: any) => ({
            os: e.service_orders?.service_order_number,
            produto: e.products?.name,
            quantidade: e.quantity,
            custo: e.line_total_cost,
          })),
        },
        servicos_sem_kit: (semKit || []).map((s: any) => s.name),
        leitura:
          (extras || []).length === 0
            ? "Nenhum material extra registrado na janela. Ou a operação está previsível, ou ninguém está marcando o que aparece no meio do serviço — vale conferir qual dos dois."
            : "Cada item aqui é custo que a execução descobriu e o orçamento não previu. Se o mesmo item repete, ele merece entrar no kit do serviço.",
      };
    },
  },
];
