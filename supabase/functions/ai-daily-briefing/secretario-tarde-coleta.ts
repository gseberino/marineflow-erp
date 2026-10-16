// As leituras da tarde (secretário, Passo 3, 15/10/2026) que a coleta da manhã não faz.
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-fechamento.md §4.
//
// Os candidatos (cobranças, orçamentos, OS, quem espera resposta) vêm da MESMA coleta da manhã
// (secretario-coleta.ts), rodada de novo às 17:30. Aqui ficam: a lista de quem espera resposta montada como
// no resumo (index.ts:284-317), a papelada do escritório contada como no resumo (index.ts:373-525), o
// "Amanhã", o panorama (mês corrigido, vigia, semana), o mês que fechou, a conversa em andamento e a manhã
// gravada de hoje. Tudo só leitura.
//
// Essencial (lança — quem chama não monta a tarde): a manhã de hoje e quem espera resposta (sem ela, todo
// cliente pareceria respondido e sumiria do fechamento). O resto é enriquecimento: erro = a linha some,
// com aviso no log (só o código).

import { diaBR, horaBR } from "../_shared/pdf/datas.ts";
import { diaDaSemana, somarDias } from "../_shared/secretario/base.ts";
import { conversaEncerradaPeloContato } from "../_shared/whatsapp/contato-encerrou.ts";
import { historicoSemIdentidade } from "../_shared/banking/proposals.ts";
import { normalizeText } from "../_shared/banking/matching.ts";
import { lerAnalise } from "../_shared/financeiro/vigia-do-negocio.ts";
import { debitosSemComprovante, linhasDosComprovantes } from "./comprovantes.ts";
import { type EntradaDoBanco, type PagamentoSemExtrato, separarEntradas } from "./entradas.ts";
import { despesasPendentesDoMes, faturamentoPorCliente, GRUPOS_DO_RESULTADO } from "./mes.ts";
import { contarPropostas } from "./secretario.ts";
import type { OsCrua } from "./secretario-candidatos.ts";
import type { ItemDaManha } from "./secretario-tarde-regras.ts";
import type { ContaDoMes, DiaDeAmanha, Panorama } from "./secretario-tarde-texto.ts";
import type { DadosDoEscritorio } from "./secretario-texto.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

const FUSO_BR = "-03:00";

function falhou(evento: string, e: unknown): void {
  console.warn(JSON.stringify({ fn: "ai-daily-briefing", tarde: evento, codigo: String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro") }));
}

function ou<T>(r: { data: T | null; error: unknown }, nome: string): T {
  if (r.error) {
    const e = new Error(`tarde: leitura de ${nome} falhou`);
    (e as Error & { code?: unknown }).code = (r.error as { code?: unknown })?.code;
    throw e;
  }
  return (r.data ?? []) as T;
}

function nomeDe(c: unknown): string | null {
  // deno-lint-ignore no-explicit-any
  const x = (Array.isArray(c) ? c[0] : c) as any;
  const n = x?.display_name || x?.name;
  return typeof n === "string" && n.trim() ? n : null;
}

// ─── A manhã gravada de hoje ──────────────────────────────────────────────────────────────────

export interface ManhaDeHoje {
  id: string;
  modo: "sombra" | "novo";
  itens: ItemDaManha[];
}

const COLUNAS_DO_ITEM =
  "letra, principal, posicao, ordem, familia, tipo, secao, referencia, nome, titulo, recomendacao, motivo, pedido, detalhe, acao, adiado_ate, fato, valor";

/** A manhã de hoje do telefone (resumo_manha + resumo_itens), ou null se não foi gravada. Erro lança. */
export async function lerManhaDeHoje(admin: Admin, phone: string, hoje: string): Promise<ManhaDeHoje | null> {
  const m = await admin.from("resumo_manha").select("id, modo").eq("dia", hoje).eq("phone_normalized", phone).maybeSingle();
  if (m.error) throw Object.assign(new Error("tarde: leitura da manhã falhou"), { code: m.error.code });
  if (!m.data) return null;
  const itens = ou(await admin.from("resumo_itens").select(COLUNAS_DO_ITEM).eq("resumo_id", m.data.id)
    .order("ordem", { ascending: true }).limit(300), "itens da manhã") as ItemDaManha[];
  return { id: String(m.data.id), modo: m.data.modo === "novo" ? "novo" : "sombra", itens };
}

// ─── Quem espera resposta (o mesmo filtro do resumo, index.ts:284-317) ────────────────────────

/**
 * whatsapp_esperando_resposta de 7 dias, sem os que só disseram "ok/obrigado" (encerrada) e sem quem disse que
 * fechou com outra empresa ou desistiu (as 5 últimas recebidas). Erro na RPC LANÇA (diferente do resumo, que
 * segue sem a seção): sem esta lista todo cliente da manhã pareceria respondido. Erro nas recebidas = a lista
 * sem o 2º filtro, como no resumo.
 */
export async function lerEsperando(admin: Admin, agora: Date): Promise<{
  // deno-lint-ignore no-explicit-any
  esperando: any[];
  recebidas: Array<{ phone_normalized: string; body: string | null; occurred_at: string }> | null;
}> {
  const since7d = new Date(agora.getTime() - 7 * 86400000).toISOString();
  // deno-lint-ignore no-explicit-any
  const todas = ou(await admin.rpc("whatsapp_esperando_resposta", { _since: since7d, _limit: 60 }), "quem espera resposta") as any[];
  let esperando = (todas ?? []).filter((w) => !w.encerrada);
  let recebidas: Array<{ phone_normalized: string; body: string | null; occurred_at: string }> | null = null;
  try {
    const fones = esperando.map((w) => String(w.phone ?? "")).filter(Boolean);
    if (fones.length > 0) {
      const lidas = ou(await admin.from("whatsapp_messages")
        .select("phone_normalized, body, occurred_at")
        .eq("direction", "inbound").in("phone_normalized", fones).gte("occurred_at", since7d)
        .order("occurred_at", { ascending: false }).limit(1000), "recebidas da semana") as Array<{ phone_normalized: string; body: string | null; occurred_at: string }>;
      recebidas = lidas;
      const porFone = new Map<string, Array<string | null>>();
      for (const m of lidas) {
        const l = porFone.get(m.phone_normalized) ?? [];
        l.push(m.body);
        porFone.set(m.phone_normalized, l);
      }
      esperando = esperando.filter((w) => !conversaEncerradaPeloContato(porFone.get(String(w.phone)) ?? []));
    }
  } catch (e) {
    falhou("recebidas_da_semana", e);
  }
  return { esperando, recebidas };
}

/** Os fornecedores que esperam resposta há mais de 24 h (da mesma lista), mais antigos primeiro. */
// deno-lint-ignore no-explicit-any
export function fornecedoresEsperando(esperando: any[], agora: Date): string[] {
  const corte = agora.getTime() - 24 * 3_600_000;
  return esperando
    .filter((w) => w.categoria === "fornecedor" && Date.parse(String(w.last_inbound_at)) <= corte)
    .sort((a, b) => Date.parse(String(a.last_inbound_at)) - Date.parse(String(b.last_inbound_at)))
    .map((w) => String(w.contato || w.phone).replace(/\s+/g, " ").trim());
}

// ─── O escritório (as mesmas contagens do resumo, index.ts:373-525) ───────────────────────────

/** A papelada contada agora. Cada parte que falhar fica null (o texto a omite), como no resumo. */
export async function contarEscritorio(admin: Admin, hoje: string): Promise<DadosDoEscritorio> {
  const d: DadosDoEscritorio = { propostas: null, alertas: null, regras: null, debitosSemLoja: null, entradas: null };
  try {
    const todas = ou(await admin.from("finance_review_queue").select("suggested_amount, kind, title")
      .eq("status", "pending").limit(1000), "propostas") as Array<{ kind: string | null }>;
    d.propostas = contarPropostas(todas.filter((p) => p.kind !== "anomaly"));
    d.alertas = todas.filter((p) => p.kind === "anomaly").length;
    const regras = await admin.from("finance_rules").select("id", { count: "exact", head: true })
      .eq("origin", "ai").eq("status", "proposed");
    if (regras.error) throw regras.error;
    d.regras = regras.count ?? null;
  } catch (e) {
    falhou("propostas", e);
  }
  try {
    const pendentes = ou(await admin.from("finance_review_queue")
      .select(`suggested_amount, suggested_date, evidencia, bank_transaction_id,
               bank_transactions!finance_review_queue_bank_transaction_id_fkey ( description, counterparty_name, counterparty_document )`)
      .eq("status", "pending").eq("kind", "create_payable")
      .order("suggested_date", { ascending: false }).limit(1000), "débitos") as Array<Record<string, unknown>>;
    // a mesma conta de index.ts:438-452: compra no débito/cartão em que o banco não diz a loja, menos o que um
    // comprovante já ligou ou que a pergunta do extrato espera
    const semLoja = pendentes.filter((l) => {
      // deno-lint-ignore no-explicit-any
      const t = l.bank_transactions as any;
      if (!t || String(t.counterparty_document ?? "").replace(/\D/g, "").length >= 11) return false;
      return historicoSemIdentidade(t.counterparty_name || t.description)
        && /^(DEBITO|COMPRA)/.test(normalizeText(String(t.description ?? "")));
    });
    const doCmp = semLoja.length ? await linhasDosComprovantes(admin) : { linhas: new Set<string>(), anotacoes: new Set<string>() };
    d.debitosSemLoja = debitosSemComprovante(semLoja, doCmp).debitos.length;
  } catch (e) {
    falhou("debitos_sem_loja", e);
  }
  try {
    const banco = ou(await admin.from("bank_transactions").select("id, transaction_date, description, amount")
      .eq("reconciled", false).eq("transaction_type", "credit").eq("source_type", "bank").is("dismissed_at", null)
      .order("amount", { ascending: false }).limit(1000), "entradas do banco") as EntradaDoBanco[];
    let pagamentos: PagamentoSemExtrato[] = [];
    try {
      const pags = ou(await admin.from("payments")
        .select("id, amount, payment_date, payment_method, receivables(description, bank_transaction_id, clients(name))")
        .eq("status", "confirmed").is("bank_transaction_id", null).not("receivable_id", "is", null)
        .gte("payment_date", somarDias(hoje, -60)).limit(1000), "pagamentos") as Array<Record<string, unknown>>;
      // deno-lint-ignore no-explicit-any
      const lidos = pags.filter((p) => !(p.receivables as any)?.bank_transaction_id);
      const ids = lidos.map((p) => String(p.id));
      const ligados = new Set<string>();
      if (ids.length) {
        const lig = ou(await admin.from("bank_transactions").select("reconciled_payment_id").in("reconciled_payment_id", ids),
          "pagamentos ligados") as Array<{ reconciled_payment_id: string }>;
        for (const r of lig) ligados.add(String(r.reconciled_payment_id));
      }
      pagamentos = lidos.filter((p) => !ligados.has(String(p.id))).map((p) => {
        // deno-lint-ignore no-explicit-any
        const rec = p.receivables as any;
        const desc = rec?.description ?? "Pagamento já lançado";
        const cliente = rec?.clients?.name;
        return { id: String(p.id), amount: p.amount as number, payment_date: String(p.payment_date), rotulo: cliente ? `${desc} (${cliente})` : desc, forma: (p.payment_method as string | null) ?? null };
      });
    } catch (e) {
      falhou("pagamentos_sem_extrato", e);
    }
    const s = separarEntradas(banco, pagamentos, hoje);
    d.entradas = { doMes: s.doMes.length, sinais: s.sinais.length, antigas: s.antigas.length };
  } catch (e) {
    falhou("entradas_do_banco", e);
  }
  return d;
}

// ─── Amanhã ───────────────────────────────────────────────────────────────────────────────────

const ATIVAS = new Set(["approved", "scheduled", "in_progress", "awaiting_parts", "open"]);

/**
 * O "Amanhã" do fechamento: OS marcada e tarefa do dono com hora (ou com prazo, fora as da automação) no dia
 * `amanha`, e a compra que precisa sair (OS ativa com a tarefa de compra aberta e serviço marcado até o dia
 * seguinte a `amanha`). Erro = null (a linha some).
 */
export async function lerAmanha(
  admin: Admin, dono: { id: string }, hoje: string, amanha: string, oss: OsCrua[],
  /** (16/10/2026, F3) traz as contas a pagar que vencem depois de hoje até `amanha` (voz_unica_regras.amanha_a_pagar) */
  comPagar = false,
): Promise<DiaDeAmanha | null> {
  try {
    const inicio = new Date(`${amanha}T00:00:00${FUSO_BR}`).toISOString();
    const fim = new Date(new Date(inicio).getTime() + 86_400_000).toISOString();
    const [comHora, comPrazo, agendadas] = await Promise.all([
      admin.from("agenda_tasks").select("id, title, scheduled_start_at, due_at, source")
        .eq("assignee_user_id", dono.id).in("status", ["pending", "in_progress"])
        .gte("scheduled_start_at", inicio).lt("scheduled_start_at", fim).limit(50),
      admin.from("agenda_tasks").select("id, title, scheduled_start_at, due_at, source")
        .eq("assignee_user_id", dono.id).in("status", ["pending", "in_progress"])
        .gte("due_at", inicio).lt("due_at", fim).limit(50),
      admin.from("service_orders").select("service_order_number, scheduled_start_at, vessels(name)")
        .gte("scheduled_start_at", inicio).lt("scheduled_start_at", fim).neq("status", "cancelled").limit(20),
    ]);
    const tarefas = new Map<string, Record<string, unknown>>();
    for (const t of [...ou(comHora, "agenda") as Array<Record<string, unknown>>, ...ou(comPrazo, "agenda") as Array<Record<string, unknown>>]) {
      tarefas.set(String(t.id), t);
    }
    const noDia = (iso: unknown) => {
      const t = typeof iso === "string" ? Date.parse(iso) : NaN;
      return !Number.isNaN(t) && t >= Date.parse(inicio) && t < Date.parse(fim);
    };
    const itens: Array<{ hora: string | null; texto: string; ord: string }> = [];
    for (const t of tarefas.values()) {
      const comHoraNoDia = noDia(t.scheduled_start_at) ? String(t.scheduled_start_at) : null;
      if (!comHoraNoDia && t.source === "automation") continue; // a R16 recriada não é compromisso
      itens.push({ hora: comHoraNoDia ? horaBR(new Date(comHoraNoDia)) : null, texto: String(t.title), ord: comHoraNoDia ?? String(t.due_at ?? "") });
    }
    for (const o of ou(agendadas, "OS de amanhã") as Array<Record<string, unknown>>) {
      const barco = nomeDe(o.vessels);
      itens.push({ hora: horaBR(new Date(String(o.scheduled_start_at))), texto: `${o.service_order_number}${barco ? ` (${barco})` : ""}`, ord: String(o.scheduled_start_at) });
    }
    itens.sort((a, b) => a.ord.localeCompare(b.ord));
    const ate = somarDias(amanha, 1);
    const compras = oss.filter((o) => ATIVAS.has(o.status) && o.tarefa_compra && o.agendada_em)
      .filter((o) => {
        const d = diaBR(new Date(o.agendada_em!));
        return d >= hoje && d <= ate;
      })
      .map((o) => {
        const n = /Comprar (\d+) (item|itens)/.exec(o.tarefa_compra!.titulo);
        const dia = diaBR(new Date(o.agendada_em!));
        return { hora: null, texto: `comprar ${n ? `${n[1]} ${n[2]}` : "os itens"} da ${o.numero} (marcada para ${dia.slice(8, 10)}/${dia.slice(5, 7)})` };
      });
    // F3 (16/10/2026): a conta a pagar que vence até a próxima manhã (o "Amanhã vence" da manhã chega tarde para pagar).
    // Erro aqui = sem a parte do pagar (o resto do "Amanhã" continua).
    let pagar: DiaDeAmanha["pagar"] = null;
    if (comPagar) {
      try {
        const contas = ou(await admin.from("payables").select("balance_amount, amount, due_date")
          .in("status", ["pending", "partially_paid", "overdue"]).gt("due_date", hoje).lte("due_date", amanha).limit(200),
          "a pagar de amanhã") as Array<{ balance_amount: unknown; amount: unknown }>;
        const valores = contas.map((c) => Number(c.balance_amount ?? c.amount ?? 0)).filter((v) => v > 0);
        pagar = { n: valores.length, total: Math.round(valores.reduce((s, v) => s + v, 0) * 100) / 100 };
      } catch (e) {
        falhou("amanha_a_pagar", e);
      }
    }
    return { dia: amanha, itens: [...itens.map(({ hora, texto }) => ({ hora, texto })), ...compras], ...(comPagar ? { pagar } : {}) };
  } catch (e) {
    falhou("amanha", e);
    return null;
  }
}

// ─── O mês (corrigido) e o panorama ───────────────────────────────────────────────────────────

/** Receita, custos e despesas lançados e as despesas ainda na fila de um período (a conta do resumo + a fila). */
export async function contaDoPeriodo(admin: Admin, de: string, ate: string): Promise<{ conta: ContaDoMes; faturamento: string | null }> {
  const [cats, pays, recs, fila] = await Promise.all([
    admin.from("financial_categories").select("name, type, dre_group"),
    admin.from("payables").select("amount, expense_category").neq("status", "cancelled").gte("issue_date", de).lte("issue_date", ate),
    admin.from("receivables").select("amount, status, client_id, clients(name)").gte("issue_date", de).lte("issue_date", ate),
    admin.from("finance_review_queue").select("suggested_amount, dre_group, suggested_category")
      .eq("status", "pending").eq("kind", "create_payable").gte("suggested_date", de).lte("suggested_date", ate).limit(1000),
  ]);
  const categorias = ou(cats, "categorias") as Array<{ name: string; type: string; dre_group: string | null }>;
  // os dois mapas do resumo (index.ts:581-590): o das despesas lançadas olha toda categoria com grupo; o da fila,
  // só as de despesa
  const grupoDe = new Map<string, string>();
  const grupoDaCategoria = new Map<string, string>();
  for (const c of categorias) {
    if (!c.dre_group) continue;
    grupoDe.set(String(c.name), c.dre_group);
    if (c.type === "payable") grupoDaCategoria.set(String(c.name), c.dre_group);
  }
  const saidas = (ou(pays, "despesas do mês") as Array<{ amount: unknown; expense_category: string | null }>)
    .filter((p) => (GRUPOS_DO_RESULTADO as readonly string[]).includes(grupoDe.get(String(p.expense_category)) ?? ""))
    .reduce((s, p) => s + Number(p.amount || 0), 0);
  const recebiveis = ou(recs, "receitas do mês") as Array<{ amount: unknown; status: string | null; client_id: string | null; clients: unknown }>;
  const receita = recebiveis.filter((r) => r.status !== "cancelled").reduce((s, r) => s + Number(r.amount || 0), 0);
  const pendentes = despesasPendentesDoMes(ou(fila, "fila do mês") as Array<{ suggested_amount: number | null; dre_group: string | null; suggested_category: string | null }>, grupoDaCategoria);
  const fat = faturamentoPorCliente(recebiveis.map((r) => ({ amount: r.amount as number, status: r.status, client_id: r.client_id ?? null, nome: nomeDe(r.clients) })));
  return {
    conta: { mes: de.slice(0, 7), receita: Math.round(receita * 100) / 100, saidas: Math.round(saidas * 100) / 100, pendentes },
    faturamento: fat ? fat.replace(/^\S*\s*Faturamento do mês por cliente:\s*/u, "Quem mais faturou: ") : null,
  };
}

/** 'aaaa-mm' do último mês "pronto" (fechado) da analise_do_negocio, ou null. */
export function ultimoMesPronto(analise: { meses?: Array<{ mes: string; pronto: boolean }> } | null | undefined): string | null {
  const prontos = (analise?.meses ?? []).filter((m) => m.pronto).map((m) => String(m.mes).slice(0, 7)).sort();
  return prontos.length ? prontos[prontos.length - 1] : null;
}

/** 'aaaa-mm' do mês anterior ao de `hoje`. */
export function mesPassado(hoje: string): string {
  return somarDias(`${hoje.slice(0, 7)}-01`, -1).slice(0, 7);
}

/**
 * F5 (16/10/2026, padrão recomendado, aguarda o dono): a linha do vigia da revisão de segunda só sai quando o último mês
 * "pronto" da analise_do_negocio é o mês passado ou mais novo — em 19/10 ela falaria de julho (agosto e setembro não
 * estão fechados), o que confunde mais do que ajuda.
 */
export function vigiaValeNaRevisao(analise: { meses?: Array<{ mes: string; pronto: boolean }> } | null | undefined, hoje: string): boolean {
  const ultimo = ultimoMesPronto(analise);
  return !!ultimo && ultimo >= mesPassado(hoje);
}

/** Mês até aqui (corrigido), a 1ª constatação do vigia e o dinheiro da semana (de hoje a domingo). */
export async function lerPanorama(
  admin: Admin,
  hoje: string,
  /** (16/10/2026, F5) a linha do vigia só com o último mês pronto recente (voz_unica_regras.vigia_so_mes_recente) */
  vigiaSoMesRecente = false,
): Promise<Panorama> {
  const p: Panorama = { mes: null, vigia: null, semana: null };
  try {
    p.mes = (await contaDoPeriodo(admin, `${hoje.slice(0, 7)}-01`, hoje)).conta;
  } catch (e) {
    falhou("mes_ate_aqui", e);
  }
  try {
    const { data, error } = await admin.rpc("analise_do_negocio", { p_meses: 6 });
    if (error) throw error;
    const fmt = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
    p.vigia = vigiaSoMesRecente && !vigiaValeNaRevisao(data, hoje)
      ? null
      : lerAnalise(data ?? {}, (v) => fmt.format(v).replace(/\u00a0/g, " ")).constatacoes[0] ?? null;
  } catch (e) {
    falhou("vigia", e);
  }
  try {
    const ds = diaDaSemana(hoje);
    const domingo = somarDias(hoje, ds === 0 ? 0 : 7 - ds);
    const [rec, pag] = await Promise.all([
      admin.from("receivables").select("balance_amount, amount").in("status", ["pending", "partially_paid"]).eq("is_deposit", false)
        .gte("due_date", hoje).lte("due_date", domingo).limit(500),
      admin.from("payables").select("balance_amount, amount").in("status", ["pending", "partially_paid", "overdue"])
        .gte("due_date", hoje).lte("due_date", domingo).limit(500),
    ]);
    const soma = (l: Array<{ balance_amount: unknown; amount: unknown }>) => l.reduce((s, r) => s + Number(r.balance_amount ?? r.amount ?? 0), 0);
    const r = ou(rec, "a receber da semana") as Array<{ balance_amount: unknown; amount: unknown }>;
    const g = ou(pag, "a pagar da semana") as Array<{ balance_amount: unknown; amount: unknown }>;
    p.semana = { entra: soma(r), nEntra: r.length, sai: soma(g), nSai: g.length, ate: domingo };
  } catch (e) {
    falhou("semana", e);
  }
  return p;
}

/** O mês anterior ao de `hoje`: a conta (corrigida) e quem mais faturou. Erro = null. */
export async function lerMesQueFechou(admin: Admin, hoje: string): Promise<{ conta: ContaDoMes; faturamento: string | null } | null> {
  try {
    const inicioDeste = `${hoje.slice(0, 7)}-01`;
    const fimDoAnterior = somarDias(inicioDeste, -1);
    return await contaDoPeriodo(admin, `${fimDoAnterior.slice(0, 7)}-01`, fimDoAnterior);
  } catch (e) {
    falhou("mes_que_fechou", e);
    return null;
  }
}

// ─── O dono está conversando? ─────────────────────────────────────────────────────────────────

/**
 * O dono mandou mensagem ao sistema nos últimos 10 min, ou há pergunta aberta para o telefone dele há menos de
 * 20 min. Erro = false (não segura a tarde por causa de uma leitura).
 */
export async function conversaAtiva(admin: Admin, phone: string, agora: Date): Promise<boolean> {
  try {
    const [msgs, perguntas] = await Promise.all([
      admin.from("whatsapp_messages").select("id", { count: "exact", head: true })
        .eq("phone_normalized", phone).eq("direction", "inbound").gte("occurred_at", new Date(agora.getTime() - 10 * 60_000).toISOString()),
      admin.from("whatsapp_perguntas").select("id", { count: "exact", head: true })
        .eq("phone_normalized", phone).eq("status", "aberta").gte("aberta_em", new Date(agora.getTime() - 20 * 60_000).toISOString()),
    ]);
    if (msgs.error) throw msgs.error;
    if (perguntas.error) throw perguntas.error;
    return (msgs.count ?? 0) > 0 || (perguntas.count ?? 0) > 0;
  } catch (e) {
    falhou("conversa_ativa", e);
    return false;
  }
}
