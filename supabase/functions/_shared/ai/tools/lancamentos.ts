// Achar, desfazer, cancelar e casar lançamentos — pelo assistente, no painel e no WhatsApp.
//
// O dono pediu que tudo que se ajusta na tela também se ajuste conversando: "corrige a
// categoria daquele almoço de ontem", "desfaz essa aprovação", "cancela, foi despesa
// pessoal". As ferramentas daqui chamam as MESMAS funções do banco que a tela chama
// (corrigir_lancamento, desfazer_aprovacao, cancelar_lancamento, conciliar_lancamento), então
// as regras não têm como divergir: trilha, mês fechado, valor do banco travado e categoria
// sensível só para o administrador valem igual nos três caminhos.
//
// Corrigir campos continua em update_payable / update_receivable (financial.ts), que agora
// também passam pela função do banco.
import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolCtx, type ToolDef } from "./registry.ts";

export type TipoDeLancamento = "payable" | "receivable";

/** Qual lançamento: exatamente um de payable_id / receivable_id. */
export function alvoDoLancamento(
  args: Record<string, unknown>,
): { tipo: TipoDeLancamento; id: string } | { error: string } {
  const pagar = typeof args.payable_id === "string" && args.payable_id.trim() ? args.payable_id.trim() : null;
  const receber = typeof args.receivable_id === "string" && args.receivable_id.trim() ? args.receivable_id.trim() : null;
  if (pagar && receber) return { error: "Informe só um: payable_id OU receivable_id." };
  if (pagar) return { tipo: "payable", id: pagar };
  if (receber) return { tipo: "receivable", id: receber };
  return { error: "Informe payable_id ou receivable_id (use buscar_lancamentos para achar)." };
}

/** Tira o prefixo técnico do erro do Postgres; a mensagem das funções já é para gente. */
export function mensagemDoBanco(e: unknown): string {
  const texto = (e as { message?: string })?.message ?? String(e);
  return texto.replace(/^(ERROR:\s*)?(P0001|42501|23514):\s*/i, "");
}

/**
 * Chama a função do banco. No painel, `sb` carrega o usuário e a função usa auth.uid(); no
 * WhatsApp, `sb` é o service role e quem pediu vai em p_autor — a função confere o cargo
 * dos dois jeitos.
 */
async function chamar(ctx: ToolCtx, nome: string, args: Record<string, unknown>) {
  const { data, error } = await ctx.sb.rpc(nome, { ...args, p_autor: ctx.userId || null });
  if (error) return { error: mensagemDoBanco(error) };
  return data;
}

/** Tolerância da busca por valor: centavo de arredondamento ou 1%, o que for maior. */
export function faixaDeValor(valor: number): [number, number] {
  const folga = Math.max(0.01, Math.abs(valor) * 0.01);
  return [Math.round((valor - folga) * 100) / 100, Math.round((valor + folga) * 100) / 100];
}

/** Texto seguro para o filtro `or` do PostgREST (vírgula e parêntese quebram a sintaxe). */
export function termoDeBusca(texto: unknown): string | null {
  if (typeof texto !== "string") return null;
  const limpo = texto.replace(/[,()*%\\]/g, " ").replace(/\s+/g, " ").trim();
  return limpo.length >= 2 ? limpo : null;
}

async function idsPorNome(ctx: ToolCtx, tabela: string, termo: string): Promise<string[]> {
  const { data } = await ctx.sb.from(tabela).select("id").ilike("name", `%${termo}%`).limit(50);
  return ((data ?? []) as { id: string }[]).map((r) => r.id);
}

export const lancamentoTools: ToolDef[] = [
  {
    name: "buscar_lancamentos",
    description:
      "Acha contas a pagar e a receber JÁ LANÇADAS por texto (descrição, fornecedor, favorecido ou cliente), valor, período, situação ou número da OS. Use antes de corrigir, desfazer ou cancelar — 'o almoço de 50 reais de ontem', 'a despesa da Coremma de agosto'. Devolve o id que as outras ferramentas pedem. Só leitura.",
    input_schema: {
      type: "object",
      properties: {
        texto: { type: "string", description: "Parte da descrição ou do nome do fornecedor/favorecido/cliente." },
        valor: { type: "number", description: "Valor aproximado (tolerância de 1%)." },
        de: { type: "string", description: "Data inicial (ISO date) do lançamento." },
        ate: { type: "string", description: "Data final (ISO date) do lançamento." },
        tipo: { type: "string", enum: ["pagar", "receber", "ambos"], description: "Padrão: ambos." },
        situacao: { type: "string", enum: ["aberto", "pago", "cancelado", "todos"], description: "Padrão: todos menos cancelado." },
        os_numero: { type: "string", description: "Número da OS, ex.: OS-60." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const bloqueio = blockTechnician(ctx);
      if (bloqueio) return bloqueio;

      const termo = termoDeBusca(args.texto);
      const tipo = args.tipo === "pagar" || args.tipo === "receber" ? args.tipo : "ambos";
      const valor = typeof args.valor === "number" && args.valor > 0 ? faixaDeValor(args.valor) : null;
      if (!termo && !valor && !args.de && !args.ate && !args.os_numero) {
        return { error: "Diga ao menos um filtro: texto, valor, período ou OS." };
      }

      let osId: string | null = null;
      if (typeof args.os_numero === "string" && args.os_numero.trim()) {
        const { data } = await ctx.sb.from("service_orders").select("id")
          .ilike("service_order_number", `%${args.os_numero.trim()}%`).limit(1).maybeSingle();
        if (!data) return { total: 0, lancamentos: [], aviso: `Nenhuma OS com número parecido com ${args.os_numero}.` };
        osId = (data as { id: string }).id;
      }

      // Categoria sensível (pró-labore, retirada) só aparece para o administrador — a mesma
      // regra da RLS, que no WhatsApp não protege porque lá a consulta roda sem usuário.
      let sensiveis: string[] = [];
      if (ctx.userRole !== "admin") {
        const { data } = await ctx.admin.from("financial_categories").select("name").eq("sensitive", true);
        sensiveis = ((data ?? []) as { name: string }[]).map((c) => c.name);
      }

      const aplicarSituacao = (q: any) => {
        if (args.situacao === "aberto") return q.in("status", ["pending", "overdue", "partially_paid"]);
        if (args.situacao === "pago") return q.eq("status", "paid");
        if (args.situacao === "cancelado") return q.eq("status", "cancelled");
        if (args.situacao === "todos") return q;
        return q.neq("status", "cancelled");
      };

      const resultado: Array<Record<string, unknown>> = [];

      if (tipo !== "receber") {
        let q = ctx.sb.from("payables")
          .select("id, description, amount, paid_amount, status, issue_date, due_date, expense_category, supplier_name, bank_transaction_id, origin, suppliers!payables_supplier_id_fkey(name), payees(name), service_orders!payables_linked_service_order_id_fkey(service_order_number)")
          .order("issue_date", { ascending: false }).limit(15);
        q = aplicarSituacao(q);
        if (valor) q = q.gte("amount", valor[0]).lte("amount", valor[1]);
        if (args.de) q = q.gte("issue_date", String(args.de).slice(0, 10));
        if (args.ate) q = q.lte("issue_date", String(args.ate).slice(0, 10));
        if (osId) q = q.eq("linked_service_order_id", osId);
        if (termo) {
          const [fornecedores, favorecidos] = await Promise.all([idsPorNome(ctx, "suppliers", termo), idsPorNome(ctx, "payees", termo)]);
          const partes = [`description.ilike.%${termo}%`, `supplier_name.ilike.%${termo}%`];
          if (fornecedores.length) partes.push(`supplier_id.in.(${fornecedores.join(",")})`);
          if (favorecidos.length) partes.push(`payee_id.in.(${favorecidos.join(",")})`);
          q = q.or(partes.join(","));
        }
        const { data, error } = await q;
        if (error) return { error: error.message };
        for (const p of (data ?? []) as any[]) {
          if (p.expense_category && sensiveis.includes(p.expense_category)) continue;
          resultado.push({
            tipo: "pagar", payable_id: p.id, data: p.issue_date, vencimento: p.due_date,
            valor: Number(p.amount), pago: Number(p.paid_amount ?? 0), situacao: p.status,
            descricao: p.description,
            contraparte: p.suppliers?.name ?? p.payees?.name ?? p.supplier_name ?? null,
            favorecido: p.payees?.name ?? null,
            categoria: p.expense_category, os: p.service_orders?.service_order_number ?? null,
            veio_do_banco: !!p.bank_transaction_id,
          });
        }
      }

      if (tipo !== "pagar") {
        let q = ctx.sb.from("receivables")
          .select("id, description, amount, paid_amount, status, issue_date, due_date, category, bank_transaction_id, clients!receivables_client_id_fkey(name), service_orders!receivables_service_order_id_fkey(service_order_number)")
          .order("issue_date", { ascending: false }).limit(15);
        q = aplicarSituacao(q);
        if (valor) q = q.gte("amount", valor[0]).lte("amount", valor[1]);
        if (args.de) q = q.gte("issue_date", String(args.de).slice(0, 10));
        if (args.ate) q = q.lte("issue_date", String(args.ate).slice(0, 10));
        if (osId) q = q.eq("service_order_id", osId);
        if (termo) {
          const clientes = await idsPorNome(ctx, "clients", termo);
          const partes = [`description.ilike.%${termo}%`];
          if (clientes.length) partes.push(`client_id.in.(${clientes.join(",")})`);
          q = q.or(partes.join(","));
        }
        const { data, error } = await q;
        if (error) return { error: error.message };
        for (const r of (data ?? []) as any[]) {
          resultado.push({
            tipo: "receber", receivable_id: r.id, data: r.issue_date, vencimento: r.due_date,
            valor: Number(r.amount), pago: Number(r.paid_amount ?? 0), situacao: r.status,
            descricao: r.description, contraparte: r.clients?.name ?? null,
            categoria: r.category, os: r.service_orders?.service_order_number ?? null,
            veio_do_banco: !!r.bank_transaction_id,
          });
        }
      }

      resultado.sort((a, b) => String(b.data ?? "").localeCompare(String(a.data ?? "")));
      return {
        total: resultado.length,
        lancamentos: resultado.slice(0, 20),
        dica: resultado.length > 1
          ? "Mais de um resultado: confirme com a pessoa qual é (data e valor) antes de mexer."
          : undefined,
      };
    },
  },

  {
    name: "desfazer_aprovacao_de_lancamento",
    description:
      "Desfaz a aprovação de um lançamento que veio do extrato do banco: o lançamento é cancelado e a linha volta para a fila do Extrato, para ser aprovada de outro jeito. Se o lançamento já existia e só tinha sido casado com o extrato, apenas o vínculo é desfeito. Use para 'aprovei errado', 'desfaz isso'. Para só trocar categoria/fornecedor/OS, prefira update_payable/update_receivable. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        payable_id: { type: "string", description: "Conta a pagar (de buscar_lancamentos)." },
        receivable_id: { type: "string", description: "Conta a receber (de buscar_lancamentos)." },
        motivo: { type: "string", description: "Por que desfazer — vai para a trilha." },
      },
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const bloqueio = blockTechnician(ctx);
      if (bloqueio) return bloqueio;
      const alvo = alvoDoLancamento(args);
      if ("error" in alvo) return alvo;
      return await chamar(ctx, "desfazer_aprovacao", {
        p_tipo: alvo.tipo, p_id: alvo.id, p_motivo: typeof args.motivo === "string" ? args.motivo : null,
      });
    },
  },

  {
    name: "cancelar_lancamento",
    description:
      "Cancela um lançamento (o 'excluir' que não apaga): sai do resultado e das listas, mas fica registrado com o motivo. Se veio do extrato, a linha do banco vai para 'Fora da fila' com o mesmo motivo. Use para 'foi despesa pessoal', 'lançado em dobro', 'não aconteceu'. Motivo obrigatório. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        payable_id: { type: "string", description: "Conta a pagar (de buscar_lancamentos)." },
        receivable_id: { type: "string", description: "Conta a receber (de buscar_lancamentos)." },
        motivo: { type: "string", description: "Por que cancelar. Obrigatório." },
      },
      required: ["motivo"],
    },
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const bloqueio = blockTechnician(ctx);
      if (bloqueio) return bloqueio;
      const alvo = alvoDoLancamento(args);
      if ("error" in alvo) return alvo;
      if (typeof args.motivo !== "string" || args.motivo.trim().length < 3) {
        return { error: "Pergunte à pessoa por que o lançamento deve ser cancelado." };
      }
      return await chamar(ctx, "cancelar_lancamento", { p_tipo: alvo.tipo, p_id: alvo.id, p_motivo: args.motivo.trim() });
    },
  },

  {
    name: "casar_lancamento_com_extrato",
    description:
      "Liga um lançamento JÁ EXISTENTE a uma linha do extrato do banco (conciliação). Se a conta estava em aberto, registra o pagamento na data do extrato. Conta a pagar só casa com saída; a receber, só com entrada. Ache a linha com listar_transacoes_pendentes. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        payable_id: { type: "string" },
        receivable_id: { type: "string" },
        bank_transaction_id: { type: "string", description: "Linha do extrato (de listar_transacoes_pendentes)." },
      },
      required: ["bank_transaction_id"],
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const bloqueio = blockTechnician(ctx);
      if (bloqueio) return bloqueio;
      const alvo = alvoDoLancamento(args);
      if ("error" in alvo) return alvo;
      if (typeof args.bank_transaction_id !== "string" || !args.bank_transaction_id.trim()) {
        return { error: "Informe a linha do extrato (bank_transaction_id)." };
      }
      return await chamar(ctx, "conciliar_lancamento", {
        p_tipo: alvo.tipo, p_id: alvo.id, p_transacao: args.bank_transaction_id.trim(),
      });
    },
  },
];
