// Ferramentas do agente para a caixa de entrada, as regras e os cadastros do financeiro.
//
// O PRINCÍPIO QUE ORGANIZA OS RISCOS AQUI: ensinar é barato, executar é caro.
//
// Criar uma regra ("toda transação com Mercado Livre é peça e material") não move um
// centavo: ela muda como o sistema PROPÕE dali em diante, e desfazer é pausar. Já aprovar
// uma proposta cria lançamento contábil, mexe em saldo e pode aprovar orçamento — isso é
// irreversível na prática e continua exigindo confirmação humana.
//
// Sem essa distinção, ou o agente vira inútil (pede permissão para tudo, e a fadiga faz o
// gestor aprovar no automático) ou vira perigoso (lança dinheiro sozinho). O critério é o
// mesmo que a literatura de agentes em finanças usa: reversibilidade e alcance da escrita.

import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolCtx, type ToolDef } from "./registry.ts";

/** Categorias ativas do plano de contas — o agente não pode inventar categoria. */
async function categoriasValidas(ctx: ToolCtx, tipo: "payable" | "receivable" = "payable") {
  const { data } = await ctx.sb
    .from("financial_categories")
    .select("name, dre_group")
    .eq("type", tipo).eq("active", true);
  return (data ?? []) as { name: string; dre_group: string | null }[];
}

export const financeRulesTools: ToolDef[] = [
  // ── ENSINAR: muda o que o sistema propõe, não o que ele já lançou ──────────────
  {
    name: "criar_regra_financeira",
    description:
      "Ensina o sistema a classificar despesas automaticamente. Use quando o usuário disser algo como " +
      "'toda transação com Mercado Livre é peças e materiais', 'pagamentos para Fulano são sempre pró-labore' " +
      "ou 'despesas do fornecedor X vão para categoria Y'. A regra vale para o que vier DEPOIS; " +
      "não altera lançamentos já feitos.",
    input_schema: {
      type: "object",
      properties: {
        reconhecer_por: {
          type: "string",
          enum: ["texto", "fornecedor", "documento", "nome_de_quem_recebe"],
          description:
            "texto = trecho que aparece no histórico do extrato (ex: MERCADOLIVRE). " +
            "fornecedor = id de fornecedor cadastrado. documento = CNPJ/CPF. " +
            "nome_de_quem_recebe = nome exato da contraparte.",
        },
        valor_de_busca: { type: "string", description: "O trecho, id, documento ou nome procurado." },
        categoria: { type: "string", description: "Categoria do plano de contas a aplicar." },
        valor_minimo: { type: "number", description: "Opcional: só vale acima deste valor." },
        valor_maximo: { type: "number", description: "Opcional: só vale até este valor." },
        lancar_sozinha: {
          type: "boolean",
          description:
            "false (padrão) = a despesa fica na fila já classificada, aguardando o OK do gestor. " +
            "true = a despesa é lançada automaticamente. Só use true se o usuário pedir explicitamente.",
        },
      },
      required: ["reconhecer_por", "valor_de_busca", "categoria"],
    },
    // Média, não alta: a regra não move dinheiro e desfazer é pausá-la. Mas escreve
    // configuração que afeta lançamentos futuros, então passa pela confirmação.
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const bloqueio = blockTechnician(ctx);
      if (bloqueio) return bloqueio;

      const cats = await categoriasValidas(ctx);
      const cat = cats.find((c) => c.name.toLowerCase() === String(args.categoria).toLowerCase());
      if (!cat) {
        return {
          error: `A categoria "${args.categoria}" não existe no plano de contas.`,
          categorias_disponiveis: cats.map((c) => c.name),
          dica: "Use criar_categoria_de_despesa antes, ou escolha uma da lista.",
        };
      }

      const tipoMap: Record<string, string> = {
        texto: "text",
        fornecedor: "supplier",
        documento: "document",
        nome_de_quem_recebe: "counterparty",
      };

      const { data, error } = await ctx.sb
        .from("finance_rules")
        .insert({
          match_type: tipoMap[String(args.reconhecer_por)],
          match_value: String(args.valor_de_busca).trim(),
          direction: "debit",
          set_category: cat.name,
          set_dre_group: cat.dre_group,
          min_amount: args.valor_minimo ?? null,
          max_amount: args.valor_maximo ?? null,
          autonomy: args.lancar_sozinha ? "apply" : "suggest",
          origin: "user",
          status: "active",
          reasoning: "Criada pelo assistente a pedido do usuário.",
        })
        .select("id")
        .single();

      if (error) {
        if (/uma_por_alvo|duplicate key/i.test(error.message)) {
          return { error: "Já existe uma regra ativa para este mesmo alvo. Edite a existente." };
        }
        return { error: error.message };
      }

      return {
        ok: true,
        id: (data as any).id,
        resumo: `${args.valor_de_busca} → ${cat.name}`,
        vale_a_partir_de: "as próximas análises do extrato",
        lanca_sozinha: !!args.lancar_sozinha,
      };
    },
  },

  {
    name: "listar_regras_financeiras",
    description:
      "Mostra as regras de classificação já ensinadas, quantas vezes cada uma foi aplicada e quais " +
      "estão apenas sugeridas pelo sistema aguardando aceite.",
    input_schema: {
      type: "object",
      properties: {
        situacao: { type: "string", enum: ["ativas", "sugeridas", "pausadas", "todas"] },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const mapa: Record<string, string> = {
        ativas: "active", sugeridas: "proposed", pausadas: "paused",
      };
      let q = ctx.sb.from("finance_rules")
        .select("id, match_type, match_value, set_category, autonomy, status, times_applied, reasoning")
        .order("times_applied", { ascending: false }).limit(100);
      const alvo = mapa[String(args.situacao ?? "ativas")];
      if (alvo) q = q.eq("status", alvo);

      const { data, error } = await q;
      if (error) return { error: error.message };
      return { regras: data ?? [], total: (data ?? []).length };
    },
  },

  {
    name: "mudar_situacao_da_regra",
    description:
      "Ativa, pausa ou recusa uma regra. Use para 'pare de aplicar a regra do posto', " +
      "'aceite a regra que você sugeriu para a Coremma' ou 'reative aquela regra'.",
    input_schema: {
      type: "object",
      properties: {
        regra_id: { type: "string" },
        nova_situacao: { type: "string", enum: ["ativa", "pausada", "recusada"] },
      },
      required: ["regra_id", "nova_situacao"],
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const bloqueio = blockTechnician(ctx);
      if (bloqueio) return bloqueio;
      const mapa: Record<string, string> = { ativa: "active", pausada: "paused", recusada: "rejected" };
      const { error } = await ctx.sb.from("finance_rules")
        .update({ status: mapa[String(args.nova_situacao)] })
        .eq("id", args.regra_id);
      if (error) return { error: error.message };
      return { ok: true, situacao: args.nova_situacao };
    },
  },

  {
    name: "criar_categoria_de_despesa",
    description:
      "Cria uma categoria nova no plano de contas, quando nenhuma existente serve. " +
      "Sempre confira a lista antes com listar_categorias_financeiras — categoria duplicada " +
      "divide o mesmo gasto em duas linhas do resultado.",
    input_schema: {
      type: "object",
      properties: {
        nome: { type: "string" },
        grupo: {
          type: "string",
          enum: ["custo_direto", "despesa_operacional", "financeiro", "nao_operacional", "receita"],
          description:
            "Onde entra no resultado. custo_direto = ligado à execução do serviço. " +
            "despesa_operacional = manter a empresa aberta. financeiro = juros e tarifas. " +
            "nao_operacional = NÃO entra no resultado (fatura de cartão, transferência própria).",
        },
      },
      required: ["nome", "grupo"],
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const bloqueio = blockTechnician(ctx);
      if (bloqueio) return bloqueio;
      const { error } = await ctx.sb.from("financial_categories").insert({
        name: String(args.nome).trim(),
        type: args.grupo === "receita" ? "receivable" : "payable",
        dre_group: args.grupo,
        active: true,
        sort_order: 900,
      });
      if (error) {
        if (/duplicate key|nome_tipo/i.test(error.message)) {
          return { error: `A categoria "${args.nome}" já existe.` };
        }
        return { error: error.message };
      }
      return { ok: true, categoria: args.nome, grupo: args.grupo };
    },
  },

  {
    name: "listar_categorias_financeiras",
    description: "Lista as categorias do plano de contas com o grupo de cada uma no resultado.",
    input_schema: {
      type: "object",
      properties: { tipo: { type: "string", enum: ["despesa", "receita"] } },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const cats = await categoriasValidas(ctx, args.tipo === "receita" ? "receivable" : "payable");
      return { categorias: cats, total: cats.length };
    },
  },

  // ── A CAIXA DE ENTRADA: propor é barato, aprovar cria lançamento ───────────────
  {
    name: "analisar_extrato_e_propor_lancamentos",
    description:
      "Varre as movimentações do banco que ainda não viraram lançamento e monta propostas de despesa, " +
      "já classificadas pelas regras. NÃO lança nada — só enche a fila para o gestor decidir. " +
      "Use para 'analise o extrato', 'o que ainda não foi lançado'.",
    input_schema: {
      type: "object",
      properties: {
        incluir_historico_antigo: {
          type: "boolean",
          description: "false (padrão) olha os últimos 90 dias; true varre tudo.",
        },
      },
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const bloqueio = blockTechnician(ctx);
      if (bloqueio) return bloqueio;
      const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/finance-review`;
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${ctx.jwt}` },
        body: JSON.stringify({ action: "generate", incluir_historico: !!args.incluir_historico_antigo }),
      });
      if (!res.ok) return { error: `finance-review respondeu ${res.status}` };
      return await res.json();
    },
  },

  {
    name: "listar_propostas_de_lancamento",
    description:
      "Mostra o que está esperando decisão na caixa de entrada financeira: o que o sistema propôs lançar, " +
      "com valor, categoria sugerida e o motivo.",
    input_schema: {
      type: "object",
      properties: { limite: { type: "number" } },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const { data, error } = await ctx.sb
        .from("finance_review_queue")
        .select("id, title, suggested_amount, suggested_category, suggested_date, confidence, reasoning, kind")
        .eq("status", "pending")
        .order("suggested_amount", { ascending: false })
        .limit(Number(args.limite ?? 30));
      if (error) return { error: error.message };
      const linhas = (data ?? []) as any[];
      return {
        propostas: linhas,
        total: linhas.length,
        valor_total: linhas.reduce((s, p) => s + Number(p.suggested_amount ?? 0), 0),
      };
    },
  },

  {
    name: "aprovar_propostas_de_lancamento",
    description:
      "Aprova propostas da caixa de entrada, CRIANDO as contas a pagar correspondentes. " +
      "Só use quando o usuário confirmar explicitamente quais aprovar.",
    input_schema: {
      type: "object",
      properties: {
        ids: { type: "array", items: { type: "string" }, description: "Ids das propostas a aprovar." },
      },
      required: ["ids"],
    },
    // ALTA: cria lançamento contábil. Diferente de criar regra, isto não se desfaz
    // pausando nada — vira despesa registrada com data e valor.
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const bloqueio = blockTechnician(ctx);
      if (bloqueio) return bloqueio;
      const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/finance-review`;
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${ctx.jwt}` },
        body: JSON.stringify({ action: "approve", ids: args.ids }),
      });
      if (!res.ok) return { error: `finance-review respondeu ${res.status}` };
      return await res.json();
    },
  },

  {
    name: "recusar_propostas_de_lancamento",
    description: "Descarta propostas da caixa de entrada sem criar lançamento nenhum.",
    input_schema: {
      type: "object",
      properties: {
        ids: { type: "array", items: { type: "string" } },
        motivo: { type: "string" },
      },
      required: ["ids"],
    },
    // Baixa: recusar não cria nem apaga nada — a transação volta a ficar pendente.
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/finance-review`;
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${ctx.jwt}` },
        body: JSON.stringify({ action: "reject", ids: args.ids, note: args.motivo ?? null }),
      });
      if (!res.ok) return { error: `finance-review respondeu ${res.status}` };
      return await res.json();
    },
  },

  // ── CADASTRO DE FAVORECIDOS ───────────────────────────────────────────────────
  {
    name: "cadastrar_favorecido",
    description:
      "Cadastra quem recebe dinheiro sem ser fornecedor: sócio, funcionário, diarista, prestador ou " +
      "comissionado. Use quando o usuário disser 'cadastre o Fulano como diarista' ou ao lançar uma " +
      "despesa de pró-labore para alguém que ainda não existe.",
    input_schema: {
      type: "object",
      properties: {
        nome: { type: "string" },
        tipo: { type: "string", enum: ["socio", "funcionario", "diarista", "prestador", "comissionado"] },
        documento: { type: "string", description: "CPF ou CNPJ, só números." },
        chave_pix: { type: "string" },
        percentual_comissao: { type: "number", description: "Só para comissionado." },
      },
      required: ["nome", "tipo"],
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const bloqueio = blockTechnician(ctx);
      if (bloqueio) return bloqueio;
      const { data, error } = await ctx.sb.from("payees").insert({
        name: String(args.nome).trim(),
        kind: args.tipo,
        document: args.documento ? String(args.documento).replace(/\D/g, "") : null,
        pix_key: args.chave_pix ?? null,
        commission_percentage: args.tipo === "comissionado" ? args.percentual_comissao ?? null : null,
        active: true,
      }).select("id").single();
      if (error) {
        if (/documento_unico|duplicate key/i.test(error.message)) {
          return { error: "Já existe um favorecido com este CPF/CNPJ." };
        }
        return { error: error.message };
      }
      return { ok: true, id: (data as any).id, nome: args.nome, tipo: args.tipo };
    },
  },

  {
    name: "listar_favorecidos",
    description: "Lista sócios, funcionários, diaristas, prestadores e comissionados cadastrados.",
    input_schema: {
      type: "object",
      properties: {
        tipo: { type: "string", enum: ["socio", "funcionario", "diarista", "prestador", "comissionado"] },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      let q = ctx.sb.from("payees")
        .select("id, name, kind, document, pix_key, commission_percentage")
        .eq("active", true).order("name");
      if (args.tipo) q = q.eq("kind", args.tipo);
      const { data, error } = await q;
      if (error) return { error: error.message };
      return { favorecidos: data ?? [], total: (data ?? []).length };
    },
  },

  // ── LEITURA DO RESULTADO ──────────────────────────────────────────────────────
  {
    name: "resultado_do_periodo",
    description:
      "Monta o resultado (DRE) de um ano ou mês: receita, custo dos serviços, despesas operacionais, " +
      "resultado financeiro e o que ficou fora do resultado. Use para 'como fechou julho', " +
      "'quanto gastamos com peças este ano', 'estamos no lucro?'.",
    input_schema: {
      type: "object",
      properties: {
        ano: { type: "number" },
        mes: { type: "number", description: "1 a 12. Omita para o ano inteiro." },
      },
      required: ["ano"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const ano = Number(args.ano);
      const de = args.mes
        ? `${ano}-${String(args.mes).padStart(2, "0")}-01`
        : `${ano}-01-01`;
      const ate = args.mes
        ? new Date(ano, Number(args.mes), 0).toISOString().slice(0, 10)
        : `${ano}-12-31`;

      const [cats, pays, recs] = await Promise.all([
        ctx.sb.from("financial_categories").select("name, type, dre_group"),
        ctx.sb.from("payables").select("amount, expense_category").gte("issue_date", de).lte("issue_date", ate),
        ctx.sb.from("receivables").select("amount, category, status").gte("issue_date", de).lte("issue_date", ate),
      ]);

      const grupoDe = new Map<string, string>();
      for (const c of (cats.data ?? []) as any[]) {
        if (c.dre_group) grupoDe.set(`${c.type}:${c.name}`, c.dre_group);
      }

      const total = (g: string) =>
        ((pays.data ?? []) as any[])
          .filter((p) => grupoDe.get(`payable:${p.expense_category}`) === g)
          .reduce((s, p) => s + Number(p.amount), 0);

      const receita = ((recs.data ?? []) as any[])
        .filter((r) => r.status !== "cancelled")
        .reduce((s, r) => s + Number(r.amount), 0);

      const custo = total("custo_direto");
      const despesa = total("despesa_operacional");
      const financeiro = total("financeiro");
      const foraDoResultado = total("nao_operacional");

      // Este número engana quando a receita ainda não foi conciliada — a caixa de entrada
      // lança despesa sozinha e receita nunca, então o resultado nasce pessimista.
      const { count: entradasPendentes } = await ctx.sb
        .from("bank_transactions")
        .select("id", { count: "exact", head: true })
        .eq("transaction_type", "credit").eq("reconciled", false).eq("source_type", "bank")
        .gte("transaction_date", de).lte("transaction_date", ate);

      return {
        periodo: args.mes ? `${String(args.mes).padStart(2, "0")}/${ano}` : String(ano),
        receita,
        custo_dos_servicos: custo,
        lucro_bruto: receita - custo,
        despesas_operacionais: despesa,
        resultado_operacional: receita - custo - despesa,
        resultado_financeiro: financeiro,
        resultado_do_periodo: receita - custo - despesa - financeiro,
        fora_do_resultado: foraDoResultado,
        aviso: (entradasPendentes ?? 0) > 0
          ? `ATENÇÃO: ${entradasPendentes} entrada(s) do banco ainda não viraram receita lançada. ` +
            "O resultado acima está incompleto do lado da receita e parece pior do que é. " +
            "Avise isto ao usuário antes de comentar o número."
          : null,
      };
    },
  },
];
