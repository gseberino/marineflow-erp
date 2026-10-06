// Tools: "atualize o extrato" e "me manda o PDF das despesas de setembro" (06/10/2026, pedido do
// dono). Até aqui o assistente respondia às consultas de dinheiro só em texto, e trazer o extrato
// novo exigia ir à tela Cadastros › Contas bancárias.
//
//   atualizar_extrato     → a mesma busca do botão "Atualizar extrato" (edge banking-sync)
//   enviar_relatorio_pdf  → relatório em PDF para o WhatsApp de QUEM PEDIU:
//       despesas / receitas → os mesmos números de gastos_por_categoria (lista inteira)
//       extrato             → as linhas do extrato bancário, por conta e sentido
//
// O PDF passa pelo mesmo caminho do PDF do orçamento (_shared/pdf/gerar-e-guardar.ts): Chromium no
// Vercel, bucket privado por minutos, envio pelo whatsapp-send. A diferença é a credencial do
// /api/pdf: relatório não é de uma OS e não tem token de link, então vai com o token de uso único
// da sessão das Diárias (emitir_token_de_pdf, migration 20261006210000_token_de_pdf). O extrato do
// FREELANCER em PDF é a tool dela, enviar_extrato_freelancer — não se repete aqui.

import { blockTechnician, type Role, type ToolCtx, type ToolDef } from "./registry.ts";
import { caixaTools, normal } from "./caixa.ts";
import { enviarDocumentoWhatsapp } from "./whatsapp.ts";
import { chaveDeEnvio, liberarEnvio } from "../../whatsapp/idempotencia.ts";
import { desviadoPorTeste } from "../../whatsapp/marcar-enviado.ts";
import { guardarEEntregar } from "../../pdf/gerar-e-guardar.ts";
import { montarRelatorioHtml, nomeDoRelatorio, reais, type Relatorio } from "../../pdf/relatorio.ts";

const CARGOS: Role[] = ["admin", "financial"];
export const CONTEXTO_DO_RELATORIO = "agente_relatorio_pdf";

function semAcesso(ctx: ToolCtx): { error: string } | null {
  const b = blockTechnician(ctx);
  if (b) return b;
  if (!CARGOS.includes(ctx.userRole as Role)) return { error: "Só administrador e financeiro podem pedir isto ao assistente." };
  return null;
}

const ehErro = (x: unknown): x is { error: string } => !!x && typeof x === "object" && "error" in (x as object);
const diaBR = (iso: string) => iso.slice(0, 10).split("-").reverse().join("/");

// ── Período ───────────────────────────────────────────────────────────────────────────────────

/** Hoje em Brasília (AAAA-MM-DD). */
export function hojeBrasilia(agora = new Date()): string {
  return new Date(agora.getTime() - 3 * 3600_000).toISOString().slice(0, 10);
}

/**
 * O período pedido: de/ate (AAAA-MM-DD), ou mes/ano, ou "hoje". Sem nada, o mês corrente — e,
 * para o freelancer, nulo (= desde o início da conta corrente).
 */
export function periodoPedido(
  args: Record<string, unknown>,
  semNadaVale: "mes" | "tudo" = "mes",
  agora = new Date(),
): { de: string | null; ate: string | null; rotulo: string } | { error: string } {
  const iso = /^\d{4}-\d{2}-\d{2}$/;
  if (args.hoje === true) {
    const h = hojeBrasilia(agora);
    return { de: h, ate: h, rotulo: `Hoje, ${diaBR(h)}` };
  }
  if (args.de || args.ate) {
    const de = String(args.de ?? args.ate);
    const ate = String(args.ate ?? args.de);
    if (!iso.test(de) || !iso.test(ate)) return { error: "Use de/ate no formato AAAA-MM-DD." };
    if (de > ate) return { error: "O início do período é depois do fim." };
    return { de, ate, rotulo: de === ate ? diaBR(de) : `${diaBR(de)} a ${diaBR(ate)}` };
  }
  if (args.mes || args.ano || semNadaVale === "mes") {
    const h = hojeBrasilia(agora);
    const ano = Number(args.ano ?? h.slice(0, 4));
    const mes = Number(args.mes ?? h.slice(5, 7));
    if (!(mes >= 1 && mes <= 12) || !(ano > 2000)) return { error: "Mês ou ano inválido." };
    const ini = new Date(Date.UTC(ano, mes - 1, 1)).toISOString().slice(0, 10);
    const fim = new Date(Date.UTC(ano, mes, 0)).toISOString().slice(0, 10);
    const nome = new Intl.DateTimeFormat("pt-BR", { month: "long", timeZone: "UTC" }).format(new Date(Date.UTC(ano, mes - 1, 1)));
    return { de: ini, ate: fim, rotulo: `${nome[0].toUpperCase()}${nome.slice(1)} de ${ano}` };
  }
  return { de: null, ate: null, rotulo: "Desde o início da conta corrente" };
}

// ── Montagem de cada relatório ───────────────────────────────────────────────────────────────

type Montado = { relatorio: Relatorio; partesDoNome: string[]; legenda: string } | { error: string };

async function relatorioDeGastos(args: Record<string, unknown>, ctx: ToolCtx, empresa: string): Promise<Montado> {
  const receita = args.relatorio === "receitas";
  const p = periodoPedido(args);
  if ("error" in p) return p;
  const gastos = caixaTools.find((t) => t.name === "gastos_por_categoria")!;
  const r = await gastos.execute({
    categoria: args.categoria, busca: args.busca, de: p.de, ate: p.ate,
    tipo: receita ? "receita" : "despesa", lista_completa: true,
  }, ctx) as Record<string, any>;
  if (ehErro(r)) return r;

  const lanc = r.lancado ?? { total: 0, quantidade: 0, por_categoria: [], itens: [] };
  const itens = [...(lanc.itens ?? [])].sort((a: any, b: any) => String(a.data).localeCompare(String(b.data)));
  const nao = r.nao_lancado as Record<string, any> | undefined;
  const titulo = receita ? "Receitas" : "Despesas";
  const relatorio: Relatorio = {
    empresa,
    titulo: `${titulo} — ${p.rotulo}`,
    periodo: `Período: ${p.rotulo} · pela data do lançamento (competência)`,
    filtros: [
      args.categoria ? `Categoria: ${r.como_entendi ?? args.categoria}` : null,
      args.busca ? `Nome contém: ${args.busca}` : null,
    ].filter(Boolean) as string[],
    resumo: [
      { rotulo: `${titulo.toLowerCase()} lançadas`, valor: reais(Number(lanc.total) || 0) },
      { rotulo: "lançamentos", valor: String(lanc.quantidade ?? itens.length) },
      ...(nao ? [{ rotulo: "ainda não lançado (extrato/cartão)", valor: reais(Number(nao.total) || 0) }] : []),
      ...(r.mes_anterior_lancado != null ? [{ rotulo: "mês anterior (lançado)", valor: reais(Number(r.mes_anterior_lancado)) }] : []),
    ],
    avisos: nao
      ? [`Há ${nao.quantidade} ${nao.quantidade === 1 ? "compra" : "compras"} no extrato ou no cartão ainda sem lançamento (${reais(Number(nao.total) || 0)}): estão na última tabela e não entram no total lançado.`]
      : [],
    tabelas: [
      {
        titulo: "Por categoria",
        colunas: [{ titulo: "Categoria" }, { titulo: "Valor", tipo: "valor" }],
        linhas: (lanc.por_categoria ?? []).map((c: any) => [c.categoria, Number(c.valor)]),
        total: { rotulo: "Total", valor: Number(lanc.total) || 0 },
      },
      {
        titulo: "Lançamentos",
        colunas: [{ titulo: "Data", tipo: "data" }, { titulo: receita ? "Cliente / descrição" : "Fornecedor / descrição" }, { titulo: "Categoria" }, { titulo: "Valor", tipo: "valor" }],
        linhas: itens.map((l: any) => [l.data, l.quem, l.categoria, Number(l.valor)]),
        total: { rotulo: "Total", valor: Number(lanc.total) || 0 },
      },
      ...(nao ? [{
        titulo: "Ainda não lançado",
        nota: String(nao.observacao ?? ""),
        colunas: [{ titulo: "Data", tipo: "data" as const }, { titulo: "Onde" }, { titulo: "Situação" }, { titulo: "Categoria indicada" }, { titulo: "Valor", tipo: "valor" as const }],
        linhas: [...(nao.itens ?? [])].sort((a: any, b: any) => String(a.data).localeCompare(String(b.data)))
          .map((l: any) => [l.data, l.quem, l.situacao, l.categoria_indicada, Number(l.valor)]),
        total: { rotulo: "Total", valor: Number(nao.total) || 0 },
      }] : []),
    ],
  };
  return {
    relatorio,
    partesDoNome: [titulo, p.de ?? "", p.de !== p.ate ? p.ate ?? "" : "", String(args.categoria ?? "")],
    legenda: `📄 ${titulo} — ${p.rotulo}\nLançado: ${reais(Number(lanc.total) || 0)}${nao ? ` · não lançado: ${reais(Number(nao.total) || 0)}` : ""}`,
  };
}

async function relatorioDeExtrato(args: Record<string, unknown>, ctx: ToolCtx, empresa: string): Promise<Montado> {
  const p = periodoPedido(args);
  if ("error" in p) return p;
  const sentido = args.sentido === "entradas" ? "credit" : args.sentido === "todas" ? null : args.sentido === "saidas" ? "debit" : null;

  const { data: contas, error: cErr } = await ctx.admin.from("bank_connections").select("id, label");
  if (cErr) return { error: `Não consegui ler as contas (${cErr.message}). Diga que a consulta falhou.` };
  const nomeDaConta = new Map(((contas ?? []) as any[]).map((c) => [c.id, String(c.label)]));
  let contaIds: string[] | null = null;
  if (args.conta) {
    const alvo = normal(args.conta);
    contaIds = ((contas ?? []) as any[]).filter((c) => normal(c.label).includes(alvo)).map((c) => c.id);
    if (contaIds.length === 0) {
      return { error: `Não achei conta com "${args.conta}". Contas: ${[...nomeDaConta.values()].join(", ")}.` };
    }
  }

  const linhas: any[] = [];
  for (let ini = 0; ini < 20000; ini += 1000) {
    let q = ctx.admin.from("bank_transactions")
      .select("transaction_date, amount, transaction_type, description, merchant_name, counterparty_name, bank_connection_id, reconciled, dismissed_kind, tx_status")
      .gte("transaction_date", p.de!).lte("transaction_date", p.ate!);
    if (sentido) q = q.eq("transaction_type", sentido);
    if (contaIds) q = q.in("bank_connection_id", contaIds);
    const { data, error } = await q.order("transaction_date").order("id").range(ini, ini + 999);
    if (error) return { error: `Não consegui ler o extrato (${error.message}). Diga que a consulta falhou — não que não houve movimento.` };
    linhas.push(...(data ?? []));
    if ((data ?? []).length < 1000) break;
  }
  const busca = args.busca ? normal(args.busca) : null;
  const doPedido = linhas
    .filter((t) => t.dismissed_kind !== "duplicata")
    .filter((t) => !busca || normal(`${t.merchant_name ?? ""} ${t.counterparty_name ?? ""} ${t.description ?? ""}`).includes(busca));
  const entradas = doPedido.filter((t) => t.transaction_type === "credit").reduce((s, t) => s + Math.abs(Number(t.amount) || 0), 0);
  const saidas = doPedido.filter((t) => t.transaction_type === "debit").reduce((s, t) => s + Math.abs(Number(t.amount) || 0), 0);
  const situacao = (t: any) => String(t.tx_status ?? "").toUpperCase() === "PENDING" ? "pendente no cartão"
    : t.reconciled ? "conciliado" : t.dismissed_kind ? "fora da fila" : "a revisar";

  const rotuloSentido = sentido === "debit" ? "Saídas" : sentido === "credit" ? "Entradas" : "Entradas e saídas";
  const total = sentido === "credit" ? entradas : sentido === "debit" ? saidas : entradas - saidas;
  const relatorio: Relatorio = {
    empresa,
    titulo: `Extrato bancário — ${rotuloSentido}`,
    periodo: `Período: ${p.rotulo}`,
    filtros: [
      contaIds ? `Conta: ${contaIds.map((id) => nomeDaConta.get(id)).join(", ")}` : "Todas as contas",
      busca ? `Texto: ${args.busca}` : null,
    ].filter(Boolean) as string[],
    resumo: [
      ...(sentido !== "debit" ? [{ rotulo: "entradas", valor: reais(entradas) }] : []),
      ...(sentido !== "credit" ? [{ rotulo: "saídas", valor: reais(saidas) }] : []),
      { rotulo: "movimentos", valor: String(doPedido.length) },
    ],
    avisos: [
      "O extrato traz o que o banco já entregou ao Pluggy (uma vez por dia): compra de agora pode ainda não estar aqui.",
    ],
    tabelas: [{
      titulo: rotuloSentido,
      colunas: [{ titulo: "Data", tipo: "data" }, { titulo: "Conta" }, { titulo: "Descrição" }, { titulo: "Situação" }, { titulo: "Valor", tipo: "valor" }],
      linhas: doPedido.map((t) => [
        t.transaction_date,
        nomeDaConta.get(t.bank_connection_id) ?? null,
        t.merchant_name ?? t.counterparty_name ?? t.description,
        situacao(t),
        (t.transaction_type === "debit" ? -1 : 1) * Math.abs(Number(t.amount) || 0),
      ]),
      total: { rotulo: sentido ? "Total" : "Entradas − saídas", valor: total },
    }],
  };
  return {
    relatorio,
    partesDoNome: ["extrato", rotuloSentido, p.de!, p.de !== p.ate ? p.ate! : ""],
    legenda: `📄 Extrato — ${rotuloSentido.toLowerCase()} — ${p.rotulo}\n${sentido !== "debit" ? `Entradas ${reais(entradas)} ` : ""}${sentido !== "credit" ? `Saídas ${reais(saidas)}` : ""}`.trim(),
  };
}

// ── Chamada à busca do extrato ───────────────────────────────────────────────────────────────

/** Mesma credencial que o finance-rules usa: JWT no painel; no WhatsApp, o segredo do cron + quem pediu. */
async function chamarBankingSync(ctx: ToolCtx, body: Record<string, unknown>, limiteMs = 110_000) {
  const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/banking-sync`;
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (ctx.jwt) headers.Authorization = `Bearer ${ctx.jwt}`;
  else {
    const segredo = Deno.env.get("CRON_SECRET");
    if (!segredo) return { error: "Sem credencial para buscar o extrato por este canal." };
    headers["x-cron-secret"] = segredo;
  }
  const controle = new AbortController();
  const relogio = setTimeout(() => controle.abort(), limiteMs);
  try {
    const r = await fetch(url, { method: "POST", headers, body: JSON.stringify(body), signal: controle.signal });
    const dados = await r.json().catch(() => ({}));
    if (!r.ok || (dados as any)?.error) return { error: String((dados as any)?.detail ?? (dados as any)?.error ?? `banking-sync respondeu ${r.status}`) };
    return dados as Record<string, unknown>;
  } catch (e) {
    const abortado = e instanceof DOMException && e.name === "AbortError";
    return { error: abortado ? "a busca do extrato passou de 110 s; ela pode ter terminado — consulte de novo daqui a pouco" : String((e as Error)?.message ?? e) };
  } finally {
    clearTimeout(relogio);
  }
}

const quando = (iso: string | null | undefined) => {
  if (!iso) return null;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null
    : new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo" }).format(d);
};

export const relatorioTools: ToolDef[] = [
  {
    name: "atualizar_extrato",
    description:
      "Traz o extrato novo dos bancos para o sistema — o mesmo que o botão 'Atualizar extrato'. Use quando pedirem 'atualize o " +
      "extrato', 'puxa os bancos', 'busca as transações novas', ou ANTES de responder sobre movimento de hoje/ontem se a pessoa " +
      "achar que falta algo. Lê o que o banco já entregou ao Pluggy: o banco manda uma vez por dia, então compra de agora pode " +
      "ainda não ter chegado — diga isso com a data de cada conta (dado_do_banco). Sem argumentos = todas as contas.",
    input_schema: {
      type: "object",
      properties: {
        conta: { type: "string", description: "Parte do nome da conta (C6, Nubank…); vazio = todas." },
      },
    },
    risk: "low",
    roles: CARGOS,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      let connection_id: string | undefined;
      if (args.conta) {
        const { data, error } = await ctx.admin.from("bank_connections").select("id, label").eq("active", true).neq("provider", "caixa");
        if (error) return { error: `Não consegui ler as contas (${error.message}).` };
        const achadas = ((data ?? []) as any[]).filter((c) => normal(c.label).includes(normal(args.conta)));
        if (achadas.length !== 1) {
          return { error: achadas.length ? `Qual delas: ${achadas.map((c) => c.label).join(" ou ")}?` : `Não achei conta com "${args.conta}". Contas: ${((data ?? []) as any[]).map((c) => c.label).join(", ")}.` };
        }
        connection_id = achadas[0].id;
      }
      const r = await chamarBankingSync(ctx, connection_id ? { connection_id } : {});
      if (ehErro(r)) return { error: `Não consegui atualizar o extrato: ${r.error}.` };

      const { data: conexoes } = await ctx.admin.from("bank_connections")
        .select("label, last_sync_status, last_sync_message, provider_updated_at, provider_next_sync_at")
        .eq("active", true).neq("provider", "caixa");
      return {
        ok: true,
        resultado: (r as any).message,
        contas: ((conexoes ?? []) as any[]).map((c) => ({
          conta: c.label,
          situacao: c.last_sync_status === "error" ? "com problema" : "ok",
          mensagem: c.last_sync_message,
          dado_do_banco: quando(c.provider_updated_at),
          proxima_ida_ao_banco: quando(c.provider_next_sync_at),
        })),
        observacao: "Diga quantas transações novas entraram e, por conta, de quando é o dado do banco. Conta 'com problema' = mostre a mensagem (ex.: reconectar no meu.pluggy.ai).",
      };
    },
  },
  {
    name: "enviar_relatorio_pdf",
    description:
      "Manda um RELATÓRIO em PDF para o WhatsApp de QUEM PEDIU (nunca para cliente). Tipos: 'despesas' ou 'receitas' de um mês/período " +
      "(com categoria ou nome, se pedirem: 'PDF das despesas de setembro', 'PDF do combustível do mês'); 'extrato' = linhas do extrato " +
      "bancário ('PDF das saídas de hoje', 'extrato do C6 de setembro'). Período: mes/ano, de/ate (AAAA-MM-DD) ou hoje=true; sem " +
      "período = mês atual. Os números são os mesmos de gastos_por_categoria. Extrato de FREELANCER em PDF é enviar_extrato_freelancer; " +
      "PDF de orçamento/OS é send_document_pdf_to_self.",
    input_schema: {
      type: "object",
      properties: {
        relatorio: { type: "string", enum: ["despesas", "receitas", "extrato"] },
        mes: { type: "number" }, ano: { type: "number" },
        de: { type: "string", description: "Início (AAAA-MM-DD)." },
        ate: { type: "string", description: "Fim (AAAA-MM-DD)." },
        hoje: { type: "boolean", description: "Só o dia de hoje." },
        categoria: { type: "string", description: "despesas/receitas: categoria ou palavra do dia a dia (combustível, peças)." },
        busca: { type: "string", description: "Parte do nome do fornecedor, estabelecimento ou texto do extrato." },
        conta: { type: "string", description: "relatorio=extrato: parte do nome da conta (C6, Nubank); vazio = todas." },
        sentido: { type: "string", enum: ["saidas", "entradas", "todas"], description: "relatorio=extrato. Padrão: todas." },
      },
      required: ["relatorio"],
    },
    // Só para quem pede, com o que ele já vê na tela: nada a confirmar (como o PDF do orçamento).
    risk: "low",
    roles: CARGOS,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const empresa = String(ctx.settings.company_name || "HBR Marine");

      const { data: u, error: uErr } = await ctx.admin.from("app_users").select("phone_normalized").eq("id", ctx.userId).maybeSingle();
      if (uErr) return { error: `Falha ao ler o seu cadastro: ${uErr.message}` };
      const telefone = String(u?.phone_normalized ?? "").replace(/\D/g, "");
      if (!telefone) return { error: "Você não tem um WhatsApp cadastrado para receber o PDF. Cadastre em Configurações → Usuários (aba IA/Zap)." };

      const montado = args.relatorio === "extrato" ? await relatorioDeExtrato(args, ctx, empresa)
        : args.relatorio === "despesas" || args.relatorio === "receitas" ? await relatorioDeGastos(args, ctx, empresa)
        : args.relatorio === "freelancer" ? { error: "Extrato de freelancer em PDF é com enviar_extrato_freelancer." }
        : { error: "Diga o tipo: despesas, receitas ou extrato." };
      if ("error" in montado) return montado;

      const html = montarRelatorioHtml(montado.relatorio);
      const nomeDoArquivo = nomeDoRelatorio(montado.partesDoNome.filter(Boolean));
      const { data: token, error: tErr } = await ctx.admin.rpc("emitir_token_de_pdf", { p_finalidade: `relatorio:${args.relatorio}` });
      if (tErr || !token) return { error: `Não consegui gerar o PDF: sem credencial para o servidor de PDF (${tErr?.message ?? "token vazio"}).` };

      // O mesmo relatório para a mesma pessoa em 2 minutos não sai duas vezes.
      const chave = chaveDeEnvio("agente-relatorio", nomeDoArquivo, telefone, String(html.length), Math.floor(Date.now() / 120_000));
      const entrega = await guardarEEntregar({
        admin: ctx.admin,
        doc: { html, nomeDoArquivo },
        pdfToken: String(token),
        baseUrl: ctx.settings.app_public_url || "",
        rotuloDoLog: "enviar_relatorio_pdf",
        entregar: (url) => enviarDocumentoWhatsapp({
          phone: telefone, url, filename: nomeDoArquivo, caption: montado.legenda,
          context: CONTEXTO_DO_RELATORIO, jwt: ctx.jwt, dedupeKey: chave,
        }),
      });
      if (!entrega.ok) return { error: `Não consegui gerar o PDF: ${entrega.motivo}. Diga que falhou, sem fingir que mandou; os números podem ir em texto.` };
      const envio = entrega.valor;
      if (!envio.ok) {
        if (envio.semResposta) await liberarEnvio(ctx.admin, chave).catch(() => {});
        return { error: `O PDF ficou pronto, mas o envio pelo WhatsApp falhou: ${envio.error}.` };
      }
      if (envio.deduplicated) return { ok: true, deduplicated: true, aviso: "Esse mesmo relatório já foi mandado há instantes; não reenviei." };
      return {
        ok: true,
        enviado_para: desviadoPorTeste(ctx.settings) ? "o número de TESTE do WhatsApp (modo de teste ligado)" : "o WhatsApp de quem pediu",
        arquivo: nomeDoArquivo,
        resumo: montado.legenda.replace(/^📄 /, ""),
        observacao: "O arquivo já foi enviado ao WhatsApp de quem pediu. Diga isso e repita o resumo em uma linha.",
      };
    },
  },
];
