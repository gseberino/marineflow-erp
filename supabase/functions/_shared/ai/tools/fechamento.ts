// O mês e as contas, pela conversa — as mesmas funções do banco que a tela usa.
//
// "O mês está pronto?", "fecha agosto", "quanto tem no C6?", "o que você lançou sozinho
// essa semana?", "para de lançar sozinho". A IA escolhe a função e os argumentos de negócio
// (mês, conta pelo nome); o banco faz a conta — saldo, verificação, trava.
import { blockTechnician, type Role, type ToolCtx, type ToolDef } from "./registry.ts";

const CARGOS_FINANCEIRO: Role[] = ["admin", "financial"];

function semAcesso(ctx: ToolCtx): { error: string } | null {
  const b = blockTechnician(ctx);
  if (b) return b;
  if (!CARGOS_FINANCEIRO.includes(ctx.userRole as Role)) return { error: "Apenas administrador ou financeiro." };
  return null;
}

/** Mês anterior ao de hoje — o mês que normalmente se fecha. */
export function mesAnterior(hoje = new Date()): { ano: number; mes: number } {
  const m = hoje.getMonth(); // 0-11; o anterior em 1-12 é o próprio m
  return m === 0 ? { ano: hoje.getFullYear() - 1, mes: 12 } : { ano: hoje.getFullYear(), mes: m };
}

/** Mês pedido; sem ano, o mais recente que já aconteceu ('dezembro' em janeiro = ano passado). */
export function mesDosArgs(args: Record<string, unknown>, hoje = new Date()): { ano: number; mes: number } {
  const padrao = mesAnterior(hoje);
  if (args.mes == null) return { ano: Number(args.ano ?? padrao.ano), mes: padrao.mes };
  const mes = Number(args.mes);
  const ano = args.ano != null ? Number(args.ano) : (mes > hoje.getMonth() + 1 ? hoje.getFullYear() - 1 : hoje.getFullYear());
  return { ano, mes };
}

/** A conta pelo nome que a pessoa falou ("C6", "nubank", "caixa"). */
async function acharConta(ctx: ToolCtx, nome: unknown): Promise<{ id: string; label: string } | { error: string }> {
  const { data } = await ctx.admin.from("bank_connections").select("id, label").eq("active", true);
  const contas = (data ?? []) as { id: string; label: string }[];
  if (contas.length === 0) return { error: "Nenhuma conta conectada." };
  if (!nome) return contas.length === 1 ? contas[0] : { error: `Qual conta? ${contas.map((c) => c.label).join(", ")}` };
  const alvo = String(nome).toLowerCase();
  const achadas = contas.filter((c) => c.label.toLowerCase().includes(alvo));
  if (achadas.length === 1) return achadas[0];
  return { error: `Não achei uma conta só com "${nome}". Contas: ${contas.map((c) => c.label).join(", ")}` };
}

export const fechamentoTools: ToolDef[] = [
  {
    name: "verificar_mes",
    description:
      "Responde 'o mês está pronto para fechar?': saldo de cada conta confere com o banco, extrato sem nada esperando, " +
      "sem despesa em dobro, lançamentos batendo com o extrato, tudo com categoria. Sem mês, usa o mês passado. Só leitura.",
    input_schema: {
      type: "object",
      properties: { mes: { type: "number", description: "1 a 12" }, ano: { type: "number" } },
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const { ano, mes } = mesDosArgs(args);
      const { data, error } = await ctx.sb.rpc("checklist_do_mes", { p_ano: ano, p_mes: mes });
      if (error) return { error: error.message };
      const r = data as { pronto: boolean; itens: Array<Record<string, unknown>> };
      return {
        mes: `${String(mes).padStart(2, "0")}/${ano}`,
        pronto: r.pronto,
        pendencias: r.itens.filter((i) => !i.ok).map((i) => ({ o_que: i.titulo, detalhe: i.detalhe, bloqueia: i.bloqueia })),
        ok: r.itens.filter((i) => i.ok).map((i) => i.titulo),
      };
    },
  },
  {
    name: "fechar_mes",
    description:
      "Fecha um mês: depois disso nenhum lançamento com data nele entra ou muda. O sistema verifica de novo antes; " +
      "com pendência, só fecha se o usuário der um motivo (fica na trilha). Só administrador. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        mes: { type: "number", description: "1 a 12" },
        ano: { type: "number" },
        motivo: { type: "string", description: "Só quando o usuário decidir fechar com pendência — por quê." },
      },
      required: ["mes"],
    },
    risk: "high",
    roles: ["admin"],
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const { ano, mes } = mesDosArgs(args);
      const { data, error } = await ctx.sb.rpc("fechar_mes", {
        p_ano: ano, p_mes: mes, p_motivo: typeof args.motivo === "string" ? args.motivo : null, p_autor: ctx.userId || null,
      });
      if (error) return { error: error.message.replace(/^(P0001|42501|23514):\s*/, "") };
      return data;
    },
  },
  {
    name: "consultar_conta",
    description:
      "Saldo e movimento de uma conta (C6, Nubank, InfinitePay, Caixa…) num mês: saldo no início e no fim, entradas, " +
      "saídas e quantas linhas ainda esperam decisão. Use para 'quanto tem no C6?', 'como foi o mês no Nubank?'. Só leitura.",
    input_schema: {
      type: "object",
      properties: {
        conta: { type: "string", description: "Parte do nome da conta. Omitir se houver uma só." },
        mes: { type: "number" }, ano: { type: "number" },
      },
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const conta = await acharConta(ctx, args.conta);
      if ("error" in conta) return conta;
      const hoje = new Date();
      const ano = Number(args.ano ?? hoje.getFullYear());
      const mes = Number(args.mes ?? hoje.getMonth() + 1);
      const de = `${ano}-${String(mes).padStart(2, "0")}-01`;
      const ate = new Date(ano, mes, 0).toISOString().slice(0, 10);
      const { data, error } = await ctx.sb.rpc("extrato_da_conta", { p_conexao: conta.id, p_de: de, p_ate: ate });
      if (error) return { error: error.message };
      const linhas = ((data ?? []) as any[]).filter((l) => !l.pendente);
      const comSaldo = linhas.filter((l) => l.saldo_apos != null);
      const maisNova = comSaldo[0];
      const maisAntiga = comSaldo[comSaldo.length - 1];
      return {
        conta: conta.label,
        mes: `${String(mes).padStart(2, "0")}/${ano}`,
        saldo_no_fim: maisNova ? Number(maisNova.saldo_apos) : null,
        saldo_no_inicio: maisAntiga ? Number(maisAntiga.saldo_apos) - Number(maisAntiga.valor) : null,
        entradas: linhas.filter((l) => Number(l.valor) > 0).reduce((s, l) => s + Number(l.valor), 0),
        saidas: linhas.filter((l) => Number(l.valor) < 0).reduce((s, l) => s - Number(l.valor), 0),
        movimentos: linhas.length,
        esperando_decisao: linhas.filter((l) => l.proposta_id || l.situacao === "nova").length,
        aviso: maisNova ? undefined : "Saldo ainda sem linha de base — aparece depois da próxima sincronização.",
      };
    },
  },
  {
    name: "configurar_lancamento_automatico",
    description:
      "Liga ou desliga o 'lançar sozinho' (saídas de confiança alta abaixo do limite de lote). Use para 'para de lançar sozinho' " +
      "ou 'pode voltar a lançar sozinho'. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: { ligado: { type: "boolean" } },
      required: ["ligado"],
    },
    risk: "medium",
    roles: ["admin"],
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const { error } = await ctx.admin.from("app_settings")
        .upsert({ key: "finance_auto_approve", value: args.ligado ? "on" : "off" }, { onConflict: "key" });
      if (error) return { error: error.message };
      await ctx.admin.from("reconciliation_log").insert({
        acao: "configurou_automatico", autor: ctx.userId || null,
        detalhe: args.ligado ? "Ligou o lançar sozinho" : "Desligou o lançar sozinho",
      });
      return { ok: true, ligado: !!args.ligado };
    },
  },
  {
    name: "listar_lancados_sozinhos",
    description:
      "O que o sistema lançou sem clique nos últimos dias (por regra sua ou por confiança alta), com o id do lançamento para " +
      "desfazer (desfazer_aprovacao_de_lancamento). Diz também se o lançar sozinho está ligado. Só leitura.",
    input_schema: { type: "object", properties: { dias: { type: "number", description: "Padrão 7." } } },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const desde = new Date(Date.now() - Math.min(90, Number(args.dias ?? 7)) * 86_400_000).toISOString();
      const [{ data }, { data: cfg }] = await Promise.all([
        ctx.admin.from("finance_review_queue")
          .select("title, suggested_amount, suggested_category, suggested_date, automatica, created_payable_id")
          .not("automatica", "is", null).eq("status", "approved").gte("decided_at", desde)
          .order("decided_at", { ascending: false }).limit(50),
        ctx.admin.from("app_settings").select("value").eq("key", "finance_auto_approve").maybeSingle(),
      ]);
      const lista = ((data ?? []) as any[]).map((l) => ({
        o_que: l.title, valor: Number(l.suggested_amount), categoria: l.suggested_category, data: l.suggested_date,
        por: l.automatica === "regra" ? "regra sua" : "confiança alta", payable_id: l.created_payable_id,
      }));
      return {
        ligado: String((cfg as any)?.value ?? "off") === "on",
        total: lista.length, valor_total: lista.reduce((s, l) => s + l.valor, 0), lancados: lista,
      };
    },
  },
];
