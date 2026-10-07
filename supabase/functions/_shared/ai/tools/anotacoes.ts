// As anotações de Pix que esperam o banco, pela conversa (07/10/2026).
//
// "quais Pix eu anotei que ainda não chegaram?", "cancela a anotação dos 493 da Eliane, paguei em
// dinheiro", "a anotação de 1.500 para a TSD era 1.050, corrige", "tem anotação parada há mais de uma
// semana?". A tela é o bloco "Anotado, esperando o banco" do Caixa (src/components/CaixaDialogs.tsx,
// AnotacoesAguardando): lista as que esperam e cancela. Listar e cancelar fazem o MESMO aqui (a mesma
// tabela, os mesmos campos — e o motivo e a hora do cancelamento, que as funções do banco gravam e a
// tela ainda não). Corrigir não existe na tela: é a função corrigir_anotacao (migration
// 20261007100000), que cancela e anota de novo pela MESMA anotar_transacao, numa transação só — se a
// corrigida não couber, nada muda.
//
// A anotação é achada pelo que a pessoa diz: nome e valor. Nome igual ou cortado (nunca parecido);
// mais de uma → as opções, e a pessoa escolhe.
import { lerRetrato, type ToolCtx, type ToolDef } from "./registry.ts";
import { categoriaValida, dataDita, ehErro } from "./caixa.ts";
import { mensagemDoBanco } from "./lancamentos.ts";
import {
  alvoDoRetrato, brl, CARGOS_DO_FINANCEIRO, casaNome, ddmm, diasEntre, mesmoValor, semAcessoDoFinanceiro, valorDito,
} from "./financeiro-comum.ts";
import { hojeEmBrasilia } from "../../banking/fluxo-de-caixa.ts";

const CAMPOS = "id, sentido, valor, data_prevista, data_exata, documento, nome, categoria, descricao, status, criada_em, " +
  "suppliers(name), payees(name), clients(name), service_orders(service_order_number)";

export interface Anotacao {
  id: string;
  sentido: "debit" | "credit";
  valor: number | string;
  data_prevista: string;
  data_exata: boolean | null;
  documento: string | null;
  nome: string | null;
  categoria: string | null;
  descricao: string | null;
  status: string;
  criada_em: string;
  suppliers: { name: string } | null;
  payees: { name: string } | null;
  clients: { name: string } | null;
  service_orders: { service_order_number: string } | null;
}

/** Para quem (ou de quem) — o mesmo que a tela mostra na linha. */
export function quemDaAnotacao(a: Anotacao): string {
  return a.suppliers?.name ?? a.payees?.name ?? a.clients?.name ?? a.nome ?? (a.documento ? `CPF/CNPJ ${a.documento}` : null)
    ?? a.categoria ?? a.service_orders?.service_order_number ?? a.descricao ?? "sem nome";
}

/** "saída de R$ 493,00 para Eliane · prevista 05/10 · Alimentação de campo" — uma linha, sem quebra. */
export function rotuloDaAnotacao(a: Anotacao): string {
  return [
    `${a.sentido === "debit" ? "saída" : "entrada"} de ${brl.format(Number(a.valor))} ${a.sentido === "debit" ? "para" : "de"} ${quemDaAnotacao(a)}`,
    `prevista ${ddmm(a.data_prevista)}`,
    a.categoria,
    a.service_orders?.service_order_number,
  ].filter(Boolean).join(" · ");
}

async function lerAguardando(cliente: ToolCtx["sb"]): Promise<Anotacao[] | { error: string }> {
  const { data, error } = await cliente.from("anotacoes_do_extrato").select(CAMPOS)
    .eq("status", "aguardando").order("data_prevista", { ascending: false }).limit(200);
  // Leitura que falha não vira "nenhuma anotação" (02/10/2026).
  if (error) return { error: `Não consegui ler as anotações (${mensagemDoBanco(error)}). Diga que a consulta falhou — não que não há anotação.` };
  return (data ?? []) as Anotacao[];
}

/**
 * A anotação do pedido: pelo id (o retrato da pendência ou o que listar_anotacoes_do_extrato
 * devolveu), ou pelo nome e valor ditos. Só as que ainda esperam o banco. Mensagens numa linha só:
 * a do resumo vira recusa (resumoQueRecusa) em vez de pendência.
 */
export async function acharAnotacao(
  cliente: ToolCtx["sb"], args: Record<string, unknown>,
): Promise<{ anotacao: Anotacao } | { error: string }> {
  const id = alvoDoRetrato(lerRetrato(args), "anotacao_id")
    ?? (typeof args.anotacao_id === "string" && args.anotacao_id.trim() ? args.anotacao_id.trim() : null);
  if (id) {
    const { data, error } = await cliente.from("anotacoes_do_extrato").select(CAMPOS).eq("id", id).maybeSingle();
    if (error) return { error: `Não consegui ler a anotação (${mensagemDoBanco(error)}).` };
    if (!data) return { error: "Anotação não encontrada: veja as que esperam com listar_anotacoes_do_extrato." };
    const a = data as Anotacao;
    if (a.status !== "aguardando") {
      return { error: `Essa anotação (${rotuloDaAnotacao(a)}) não está mais esperando o banco: ${a.status === "aplicada" ? "já foi aplicada a uma transação" : "foi cancelada"}.` };
    }
    return { anotacao: a };
  }
  const valor = args.valor != null && args.valor !== "" ? valorDito(args.valor) : null;
  const quem = typeof args.quem === "string" && args.quem.trim() ? args.quem.trim() : null;
  if (!quem && valor == null) return { error: "Diga de quem é a anotação (o nome) e/ou o valor." };
  const todas = await lerAguardando(cliente);
  if (ehErro(todas)) return todas;
  const achadas = todas.filter((a) =>
    (!quem || [quemDaAnotacao(a), a.nome, a.descricao].some((n) => casaNome(quem, n))) &&
    (valor == null || mesmoValor(a.valor, valor))
  );
  const dito = [quem, valor != null ? brl.format(valor) : null].filter(Boolean).join(", ");
  if (achadas.length === 1) return { anotacao: achadas[0] };
  if (achadas.length > 1) {
    return { error: `Há ${achadas.length} anotações esperando com ${dito}: ${achadas.slice(0, 6).map(rotuloDaAnotacao).join("; ")}. Diga qual (valor ou data).` };
  }
  return {
    error: `Nenhuma anotação esperando o banco com ${dito}.` +
      (todas.length ? ` As que esperam: ${todas.slice(0, 6).map(rotuloDaAnotacao).join("; ")}.` : " Não há nenhuma esperando."),
  };
}

const ACOES = ["cancelar", "corrigir"] as const;

/** O que vai mudar — a confirmação mostra a anotação RESOLVIDA, não o nome dito. */
export async function resumirAnotacao(ctx: ToolCtx, args: Record<string, unknown>): Promise<string | null> {
  const r = await acharAnotacao(ctx.admin, args);
  if (ehErro(r)) return `⚠️ ${r.error}`;
  const a = r.anotacao;
  if (args.acao === "cancelar") {
    return [
      `Cancelar a anotação: *${rotuloDaAnotacao(a)}*`,
      args.motivo ? `- Motivo: ${String(args.motivo)}` : null,
      "- Ela deixa de esperar o banco: se a transação chegar mesmo assim, entra na fila do Extrato sem esta classificação.",
    ].filter(Boolean).join("\n");
  }
  const mudancas: string[] = [];
  const novoValor = valorDito(args.novo_valor);
  if (novoValor != null) mudancas.push(`valor ${brl.format(Number(a.valor))} → *${brl.format(novoValor)}*`);
  if (args.nova_categoria) {
    const cat = await categoriaValida(ctx, args.nova_categoria, a.sentido === "credit" ? "receivable" : "payable");
    if (ehErro(cat)) return `⚠️ ${cat.error}`;
    if (cat) mudancas.push(`categoria ${a.categoria ?? "—"} → *${cat.nome}*`);
  }
  const novaData = dataDita(args.nova_data);
  if (args.nova_data && !novaData) return `⚠️ Não entendi a data "${String(args.nova_data)}". Use dd/mm, ontem ou hoje.`;
  if (novaData) mudancas.push(`data ${ddmm(a.data_prevista)} → *${ddmm(novaData)}*`);
  if (!mudancas.length) return "⚠️ Diga o que corrigir na anotação: valor, categoria ou data.";
  return [
    `Corrigir a anotação: ${rotuloDaAnotacao(a)}`,
    `- ${mudancas.join("; ")}`,
    "- A antiga é cancelada e a corrigida passa a esperar o banco (se a transação já chegou, já classifica). Se a corrigida não couber — outra anotação igual, duas transações do mesmo valor —, nada muda.",
  ].join("\n");
}

export const anotacaoTools: ToolDef[] = [
  {
    name: "listar_anotacoes_do_extrato",
    description:
      "Lista as anotações de Pix/transferência que ainda ESPERAM o banco (o que foi dito com anotar_transacao_do_banco ou pago " +
      "a freelancer por Pix): 'quais Pix eu anotei que ainda não chegaram?', 'tem anotação parada há mais de uma semana?'. " +
      "Traz quem, valor, data prevista, categoria, OS e há quantos dias espera. Só leitura. Se vier error, diga que a consulta falhou.",
    input_schema: {
      type: "object",
      properties: {
        quem: { type: "string", description: "Só as de uma pessoa/empresa (nome como a pessoa falou)." },
        parada_ha_mais_de_dias: { type: "number", description: "Só as que passaram da data prevista há mais de N dias (ex.: 7 = mais de uma semana)." },
      },
    },
    risk: "low",
    roles: CARGOS_DO_FINANCEIRO,
    async execute(args, ctx) {
      const b = semAcessoDoFinanceiro(ctx);
      if (b) return b;
      const todas = await lerAguardando(ctx.sb);
      if (ehErro(todas)) return todas;
      const hoje = hojeEmBrasilia();
      const minimo = Number(args.parada_ha_mais_de_dias);
      const lista = todas
        .filter((a) => !args.quem || [quemDaAnotacao(a), a.nome, a.descricao].some((n) => casaNome(args.quem, n)))
        .filter((a) => !(minimo > 0) || diasEntre(a.data_prevista, hoje) > minimo)
        .map((a) => {
          const dias = diasEntre(a.data_prevista, hoje);
          return {
            anotacao_id: a.id,
            sentido: a.sentido === "debit" ? "saída" : "entrada",
            quem: quemDaAnotacao(a),
            valor: Number(a.valor),
            data_prevista: a.data_prevista,
            data_exata: !!a.data_exata,
            categoria: a.categoria,
            os: a.service_orders?.service_order_number ?? null,
            descricao: a.descricao,
            anotada_em: String(a.criada_em).slice(0, 10),
            dias_desde_a_data_prevista: Math.max(0, dias),
            ...(dias > 7 ? { aviso: "Mais de uma semana depois da data prevista e o banco não trouxe: confira se o Pix saiu mesmo, ou cancele a anotação." } : {}),
          };
        });
      return {
        total: lista.length,
        total_valor: Math.round(lista.reduce((s, a) => s + a.valor, 0) * 100) / 100,
        anotacoes: lista,
        ...(lista.length === 0 ? { observacao: "Nenhuma anotação esperando o banco com esse filtro." } : {}),
      };
    },
  },
  {
    name: "alterar_anotacao_do_extrato",
    description:
      "Cancela ou corrige uma anotação de Pix que ainda espera o banco. Cancelar: 'cancela a anotação dos 493 da Eliane, paguei em " +
      "dinheiro' (acao=cancelar, motivo). Corrigir valor, categoria ou data: 'a anotação de 1.500 para a TSD era 1.050, corrige' " +
      "(acao=corrigir, novo_valor) — a antiga é cancelada e a corrigida passa a esperar, numa vez só; se a corrigida não couber, nada muda. " +
      "Ache pela pessoa e pelo valor ditos (quem, valor) ou pelo anotacao_id de listar_anotacoes_do_extrato; mais de uma → o sistema " +
      "devolve as opções e você pergunta. Anotação já aplicada não muda aqui (corrija o lançamento). Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        acao: { type: "string", enum: [...ACOES] },
        anotacao_id: { type: "string", description: "De listar_anotacoes_do_extrato, quando já se sabe qual." },
        quem: { type: "string", description: "Nome dito ('Eliane', 'TSD')." },
        valor: { type: "number", description: "O valor ATUAL da anotação, como a pessoa disse ('a de 1.500')." },
        motivo: { type: "string", description: "Por que cancelar/corrigir ('paguei em dinheiro')." },
        novo_valor: { type: "number", description: "Só para corrigir: o valor certo." },
        nova_categoria: { type: "string", description: "Só para corrigir: a categoria certa." },
        nova_data: { type: "string", description: "Só para corrigir: a data certa do Pix ('ontem', dd/mm)." },
      },
      required: ["acao"],
    },
    risk: "medium",
    roles: CARGOS_DO_FINANCEIRO,
    preValidar(args) {
      if (!ACOES.includes(args?.acao)) return { error: "acao: cancelar ou corrigir." };
      if (!args?.anotacao_id && !args?.quem && args?.valor == null) return { error: "Diga de quem é a anotação (o nome) e/ou o valor." };
      if (args.acao === "corrigir" && args.novo_valor == null && !args.nova_categoria && !args.nova_data) {
        return { error: "Diga o que corrigir: novo_valor, nova_categoria ou nova_data." };
      }
      return null;
    },
    // O "sim" é sobre a anotação que o resumo mostrou: o id dela vai na pendência.
    retratoDaPendencia: async (args, ctx) => {
      const r = await acharAnotacao(ctx.admin, args);
      return ehErro(r) ? null : { anotacao_id: r.anotacao.id };
    },
    async execute(args, ctx) {
      const b = semAcessoDoFinanceiro(ctx);
      if (b) return b;
      if (!ACOES.includes(args.acao)) return { error: "acao: cancelar ou corrigir." };
      const r = await acharAnotacao(ctx.sb, args);
      if (ehErro(r)) return r;
      const a = r.anotacao;
      const motivo = typeof args.motivo === "string" && args.motivo.trim() ? args.motivo.trim() : null;

      if (args.acao === "cancelar") {
        // O mesmo que o X da tela (status 'cancelada'), com a hora e o motivo, como as funções do banco gravam.
        const { data, error } = await ctx.sb.from("anotacoes_do_extrato")
          .update({ status: "cancelada", cancelada_em: new Date().toISOString(), motivo_cancelamento: motivo ?? "cancelada a pedido, pelo assistente" })
          .eq("id", a.id).eq("status", "aguardando").select("id");
        if (error) return { error: `Não consegui cancelar a anotação: ${mensagemDoBanco(error)}` };
        if (!(data ?? []).length) return { error: "A anotação deixou de esperar o banco antes do cancelamento (foi aplicada ou cancelada): nada mudou." };
        return { ok: true, cancelada: a.id, message: `Cancelei a anotação: ${rotuloDaAnotacao(a)}.` };
      }

      const novoValor = args.novo_valor != null && args.novo_valor !== "" ? valorDito(args.novo_valor) : null;
      if (args.novo_valor != null && args.novo_valor !== "" && novoValor == null) return { error: `Não entendi o valor "${String(args.novo_valor)}".` };
      const cat = await categoriaValida(ctx, args.nova_categoria, a.sentido === "credit" ? "receivable" : "payable");
      if (ehErro(cat)) return cat;
      const novaData = dataDita(args.nova_data);
      if (args.nova_data && !novaData) return { error: `Não entendi a data "${String(args.nova_data)}". Use dd/mm, ontem ou hoje.` };
      if (novoValor == null && !cat && !novaData) return { error: "Diga o que corrigir: valor, categoria ou data." };
      const { data, error } = await ctx.sb.rpc("corrigir_anotacao", {
        p_anotacao: a.id, p_valor: novoValor, p_categoria: cat?.nome ?? null, p_data: novaData, p_motivo: motivo,
        p_autor: ctx.userId || null,
      });
      if (error) return { error: mensagemDoBanco(error) };
      return data;
    },
  },
];
