// O lote semanal da papelada no fechamento da sexta (secretário, Passo 5, 16/10/2026): lê a fila, o histórico de
// aprovações do dono e o limite de lote, monta (o puro está em _shared/papelada/lote.ts) e guarda.
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-papelada.md §3 e §5.
//
// Só roda com app_settings.papelada_lote ≠ 'desligado' e no último dia útil da semana (quem chama confere). Só LÊ e
// grava em papelada_lote (RPC papelada_lote_registrar): nenhuma proposta é aprovada aqui.

import { linhasDosComprovantes } from "./comprovantes.ts";
import { type DecisaoPassada, type LinhaDaFila, type LoteMontado, montarLote } from "../_shared/papelada/lote.ts";
import { linhaDoLote } from "../_shared/papelada/texto.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

const PAGINA = 1000;
const LOTE_DO_IN = 150;

function erroDe(nome: string, e: unknown): Error {
  const err = new Error(`papelada: leitura de ${nome} falhou`);
  (err as Error & { code?: unknown }).code = (e as { code?: unknown })?.code;
  return err;
}

/** Lê tudo de uma consulta em páginas de 1.000 (o PostgREST corta em 1.000 sem avisar). */
async function emPaginas<T>(nome: string, consulta: (de: number, ate: number) => Promise<{ data: T[] | null; error: unknown }>): Promise<T[]> {
  const todas: T[] = [];
  for (let de = 0; de < 20 * PAGINA; de += PAGINA) {
    const { data, error } = await consulta(de, de + PAGINA - 1);
    if (error) throw erroDe(nome, error);
    const pagina = data ?? [];
    todas.push(...pagina);
    if (pagina.length < PAGINA) break;
  }
  return todas;
}

/** `.in()` em pedaços (URL curta). */
async function emPedacos<T>(nome: string, ids: string[], consulta: (pedaco: string[]) => Promise<{ data: T[] | null; error: unknown }>): Promise<T[]> {
  const todas: T[] = [];
  for (let i = 0; i < ids.length; i += LOTE_DO_IN) {
    const { data, error } = await consulta(ids.slice(i, i + LOTE_DO_IN));
    if (error) throw erroDe(nome, error);
    todas.push(...(data ?? []));
  }
  return todas;
}

// deno-lint-ignore no-explicit-any
type Linha = Record<string, any>;

const COLUNAS_DA_FILA = "id, kind, status, title, suggested_amount, suggested_date, suggested_category, dre_group, confidence, " +
  "applied_rule_id, suggested_service_order_id, suggested_purchase_order_id, suggested_client_id, vinculo_sugerido, evidencia, " +
  "bank_transaction_id, related_transaction_id, created_at, suggested_description";

/** A fila pendente com o que cerca cada linha (a linha do banco, a regra, a anotação, o que já foi lançado). */
export async function lerFilaParaOLote(admin: Admin): Promise<LinhaDaFila[]> {
  const pendentes = await emPaginas<Linha>("fila", (de, ate) =>
    admin.from("finance_review_queue").select(COLUNAS_DA_FILA).eq("status", "pending").order("id").range(de, ate));
  if (!pendentes.length) return [];

  const txIds = [...new Set(pendentes.flatMap((p) => [p.bank_transaction_id, p.related_transaction_id]).filter(Boolean).map(String))];
  const regraIds = [...new Set(pendentes.map((p) => p.applied_rule_id).filter(Boolean).map(String))];
  const anotIds = [...new Set(pendentes.map((p) => p.evidencia?.anotacao?.id).filter((x) => typeof x === "string"))] as string[];

  const [txs, regras, anotacoes, despesas, receitas, aprovadas] = await Promise.all([
    emPedacos<Linha>("linhas do banco", txIds, (p) =>
      admin.from("bank_transactions").select("id, counterparty_name, counterparty_document, description, transaction_date, amount").in("id", p)),
    emPedacos<Linha>("regras", regraIds, (p) => admin.from("finance_rules").select("id, origin").in("id", p)),
    emPedacos<Linha>("anotações", anotIds, (p) =>
      admin.from("anotacoes_do_extrato").select("id, descricao, criada_em, categoria").in("id", p)),
    emPedacos<Linha>("despesas da linha", txIds, (p) =>
      admin.from("payables").select("bank_transaction_id, status").in("bank_transaction_id", p).neq("status", "cancelled")),
    emPedacos<Linha>("receitas da linha", txIds, (p) =>
      admin.from("receivables").select("bank_transaction_id, status").in("bank_transaction_id", p).neq("status", "cancelled")),
    emPedacos<Linha>("propostas aprovadas da linha", txIds, (p) =>
      admin.from("finance_review_queue").select("id, kind, status, bank_transaction_id").in("bank_transaction_id", p).eq("status", "approved")),
  ]);
  const doCmp = await linhasDosComprovantes(admin);

  const txPorId = new Map(txs.map((t) => [String(t.id), t]));
  const origemDaRegra = new Map(regras.map((r) => [String(r.id), r.origin ?? null]));
  const anotPorId = new Map(anotacoes.map((a) => [String(a.id), a]));
  const lancadas = new Set([...despesas, ...receitas].map((l) => String(l.bank_transaction_id)));
  // as outras propostas da mesma linha do banco: "kind:status"
  const filaDaTx = new Map<string, string[]>();
  const anotar = (tx: unknown, id: string, rotulo: string) => {
    if (!tx) return;
    const l = filaDaTx.get(String(tx)) ?? [];
    l.push(`${id}|${rotulo}`);
    filaDaTx.set(String(tx), l);
  };
  for (const p of pendentes) anotar(p.bank_transaction_id, String(p.id), `${p.kind}:pending`);
  for (const a of aprovadas) anotar(a.bank_transaction_id, String(a.id), `${a.kind}:approved`);
  const alertasNaTx = new Map<string, number>();
  for (const p of pendentes) {
    if (p.kind === "anomaly" && p.related_transaction_id) {
      alertasNaTx.set(String(p.related_transaction_id), (alertasNaTx.get(String(p.related_transaction_id)) ?? 0) + 1);
    }
  }

  return pendentes.map((p) => {
    const txId = String(p.bank_transaction_id ?? p.related_transaction_id ?? "");
    const tx = txPorId.get(txId) ?? null;
    const anot = p.evidencia?.anotacao?.id ? anotPorId.get(String(p.evidencia.anotacao.id)) ?? null : null;
    const outras = (filaDaTx.get(txId) ?? []).filter((x) => !x.startsWith(`${p.id}|`)).map((x) => x.split("|")[1]);
    return {
      id: String(p.id),
      kind: String(p.kind),
      title: String(p.title ?? ""),
      suggested_amount: p.suggested_amount == null ? null : Number(p.suggested_amount),
      suggested_date: p.suggested_date ?? null,
      suggested_category: p.suggested_category ?? null,
      dre_group: p.dre_group ?? null,
      confidence: p.confidence == null ? null : Number(p.confidence),
      applied_rule_id: p.applied_rule_id ?? null,
      regra_origem: p.applied_rule_id ? origemDaRegra.get(String(p.applied_rule_id)) ?? null : null,
      suggested_service_order_id: p.suggested_service_order_id ?? null,
      suggested_purchase_order_id: p.suggested_purchase_order_id ?? null,
      suggested_client_id: p.suggested_client_id ?? null,
      vinculo_sugerido: p.vinculo_sugerido ?? null,
      evidencia: p.evidencia ?? null,
      bank_transaction_id: p.bank_transaction_id ?? null,
      related_transaction_id: p.related_transaction_id ?? null,
      created_at: p.created_at ?? null,
      suggested_description: p.suggested_description ?? null,
      tx: tx
        ? {
          counterparty_name: tx.counterparty_name ?? null, counterparty_document: tx.counterparty_document ?? null,
          description: tx.description ?? null, transaction_date: tx.transaction_date ?? null, amount: tx.amount == null ? null : Number(tx.amount),
        }
        : null,
      anotacao: anot ? { descricao: anot.descricao ?? null, criada_em: anot.criada_em ?? null, categoria: anot.categoria ?? null } : null,
      tx_lancada: txId ? lancadas.has(txId) : false,
      fila_da_tx: outras.join(",") || null,
      alertas_na_tx: p.bank_transaction_id ? alertasNaTx.get(String(p.bank_transaction_id)) ?? 0 : 0,
      do_comprovante: p.kind === "create_payable" && !!p.bank_transaction_id && doCmp.linhas.has(String(p.bank_transaction_id)),
    } satisfies LinhaDaFila;
  });
}

/** As aprovações do dono com a categoria de antes e a de depois (reconciliation_log) e a linha do banco. */
export async function lerHistoricoDeAprovacoes(admin: Admin): Promise<DecisaoPassada[]> {
  const log = await emPaginas<Linha>("histórico", (de, ate) =>
    admin.from("reconciliation_log").select("id, ocorrido_em, antes, depois, payable_id, receivable_id, bank_transaction_id")
      .eq("acao", "aprovou_proposta").not("bank_transaction_id", "is", null).order("id").range(de, ate));
  const txIds = [...new Set(log.map((l) => String(l.bank_transaction_id)))];
  const txs = await emPedacos<Linha>("linhas do histórico", txIds, (p) =>
    admin.from("bank_transactions").select("id, counterparty_name, counterparty_document, description").in("id", p));
  const txPorId = new Map(txs.map((t) => [String(t.id), t]));
  return log
    .filter((l) => l.payable_id || l.receivable_id)
    .map((l) => {
      const tx = txPorId.get(String(l.bank_transaction_id)) ?? {};
      return {
        em: String(l.ocorrido_em),
        sug: l.antes?.categoria_sugerida ?? null,
        fin: l.depois?.categoria ?? null,
        kind: l.payable_id ? "create_payable" : "create_receivable",
        counterparty_name: tx.counterparty_name ?? null,
        counterparty_document: tx.counterparty_document ?? null,
        description: tx.description ?? null,
      };
    });
}

/** finance_review_batch_limit (o mesmo número que a tela e o servidor usam); padrão R$ 500. */
export function limiteDoLote(cfg: Record<string, string>): number {
  const n = parseFloat(String(cfg["finance_review_batch_limit"] ?? "").replace(",", "."));
  return Number.isFinite(n) && n > 0 ? n : 500;
}

/** Monta o lote da semana com o banco de agora. Lança se uma leitura essencial falhar (quem chama segue sem lote). */
export async function montarLoteDaSemana(admin: Admin, p: { cfg: Record<string, string> }): Promise<LoteMontado> {
  const [fila, historico] = await Promise.all([lerFilaParaOLote(admin), lerHistoricoDeAprovacoes(admin)]);
  return montarLote(fila, { limite: limiteDoLote(p.cfg), historico });
}

/** Quantas regras sugeridas esperam (ficam guardadas, fora do lote). null = não deu para contar. */
export async function contarRegrasGuardadas(admin: Admin): Promise<number | null> {
  try {
    const r = await admin.from("finance_rules").select("id", { count: "exact", head: true }).eq("origin", "ai").eq("status", "proposed");
    if (r.error) return null;
    return r.count ?? null;
  } catch {
    return null;
  }
}

/**
 * Guarda o lote (uma vez por dia e telefone). `formato` = 'ligado' só quando a chave está ligada E a tarde foi
 * enviada; senão 'sombra' (nunca aplicado). Nunca lança: devolve o que a RPC disse ou o erro.
 */
export async function registrarLote(admin: Admin, p: {
  dia: string;
  phone: string;
  appUserId: string | null;
  formato: "sombra" | "ligado";
  lote: LoteMontado;
  validoAte: string;
  regrasGuardadas?: number | null;
}): Promise<{ ok: boolean; novo?: boolean; id?: string; erro?: string }> {
  try {
    const { data, error } = await admin.rpc("papelada_lote_registrar", {
      p: {
        dia: p.dia,
        phone: p.phone,
        app_user_id: p.appUserId,
        formato: p.formato,
        itens: p.lote.itens,
        excecoes: p.lote.fora,
        contagens: { ...p.lote.contagens, minutos: p.lote.minutos, regras_guardadas: p.regrasGuardadas ?? null },
        total: p.lote.total,
        linha: linhaDoLote(p.lote),
        valido_ate: p.validoAte,
      },
    });
    if (error) return { ok: false, erro: String(error.code ?? "rpc") };
    return (data ?? { ok: false, erro: "sem_resposta" }) as { ok: boolean; novo?: boolean; id?: string; erro?: string };
  } catch (e) {
    return { ok: false, erro: (e as Error)?.name ?? "erro" };
  }
}
