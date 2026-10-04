// Sugestões de conciliação — num lugar só (03/10/2026).
//
// Vivia dentro da edge `banking-reconcile`. A ferramenta `sugerir_conciliacao` do assistente
// chamava essa edge por HTTP com o JWT do usuário — e no WhatsApp e no Claude Max não existe
// sessão do navegador, então a sugestão nunca rodava fora do painel (401). Sugerir só LÊ, e a
// edge já lia tudo com a chave de serviço; agora a tela (pela edge) e o assistente (direto)
// usam esta mesma função. Registrar dinheiro continua só na edge, com o JWT de quem decide.
//
// A lógica é a mesma que estava na edge, sem mudança de comportamento.
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  findInternalTransfers, looksLikeInternalTransfer, statementSignature, suggestCombinations, suggestMatches,
} from "./matching.ts";
import { carregarCandidatos } from "./candidatos.ts";
import type { BankTx, Candidate, Suggestion } from "./types.ts";

type DbClient = SupabaseClient<any, "public", any>;

export interface SugestaoDaTransacao {
  transaction: BankTx;
  suggestions: Suggestion[];
  groups: ReturnType<typeof suggestCombinations>;
  internalTransfer: boolean;
  internalTransferDetail: string | null;
}

export interface SugestoesDoExtrato {
  /** Transações pendentes analisadas, cada uma com as correspondências pontuadas. */
  porTransacao: SugestaoDaTransacao[];
  /** Quantos candidatos (contas, sinais, saldos de OS...) foram avaliados. */
  candidatosAvaliados: number;
  /** Pares saída↔entrada entre contas da própria empresa. */
  transferenciasInternas: number;
}

/**
 * Pontua as transações pendentes do extrato contra tudo que elas poderiam estar pagando.
 * NÃO grava nada. `admin` é o cliente com a chave de serviço (as duas chamadoras já o têm).
 */
export async function montarSugestoes(
  admin: DbClient,
  opcoes: { transactionId?: string; limite?: number } = {},
  deps: { carregarCandidatos: (admin: DbClient) => Promise<Candidate[]> } = { carregarCandidatos },
): Promise<SugestoesDoExtrato> {
  // ── Transações pendentes ─────────────────────────────────────────────────
  let txQuery = admin
    .from("bank_transactions")
    .select("id, transaction_date, description, amount, transaction_type, pix_end_to_end_id, counterparty_document, counterparty_name, bank_connection_id")
    .eq("reconciled", false)
    .order("transaction_date", { ascending: false })
    .limit(opcoes.limite ?? 200);
  if (opcoes.transactionId) txQuery = txQuery.eq("id", opcoes.transactionId);

  const { data: txRows, error: txErr } = await txQuery;
  if (txErr) throw txErr;
  const transactions = (txRows || []) as BankTx[];
  if (transactions.length === 0) {
    return { porTransacao: [], candidatosAvaliados: 0, transferenciasInternas: 0 };
  }

  const candidates = await deps.carregarCandidatos(admin);

  // ── Memória: o que histórico parecido já ensinou sobre quem paga ─────────
  const assinaturas = new Map<string, string>();
  for (const tx of transactions) {
    const sig = statementSignature(tx.description, tx.counterparty_name);
    if (sig) assinaturas.set(tx.id, sig);
  }
  const memoriaPorTx = new Map<string, Map<string, number>>();
  if (assinaturas.size > 0) {
    const { data: memoria } = await admin
      .from("reconciliation_memory")
      .select("statement_key, client_id, hits")
      .in("statement_key", Array.from(new Set(assinaturas.values())));
    const porChave = new Map<string, Map<string, number>>();
    for (const m of (memoria || []) as any[]) {
      const mapa = porChave.get(m.statement_key) ?? new Map<string, number>();
      mapa.set(m.client_id, Number(m.hits) || 1);
      porChave.set(m.statement_key, mapa);
    }
    for (const [txId, sig] of assinaturas) {
      const mapa = porChave.get(sig);
      if (mapa) memoriaPorTx.set(txId, mapa);
    }
  }

  // Nome da empresa para reconhecer dinheiro circulando entre contas próprias.
  const { data: cfgEmpresa } = await admin
    .from("app_settings")
    .select("value")
    .eq("key", "company_name")
    .maybeSingle();
  const companyName = (cfgEmpresa as any)?.value ?? null;

  // ── Transferências entre contas da própria empresa ───────────────────────
  // Com mais de uma conta conectada, o mesmo dinheiro aparece duas vezes: sai de uma e
  // entra na outra. Sem parear, vira despesa e receita fantasmas — infla faturamento e
  // custo ao mesmo tempo. Marcamos as duas pernas para saírem da caça a candidatos.
  //
  // O pareamento roda sobre TODAS as pendentes, não sobre o lote exibido: as duas pernas
  // podem cair em páginas diferentes, e aí metade dos pares desaparece — foi o que
  // aconteceu quando isto usava só o lote (15 pares vistos de 29 existentes).
  const { data: universoParaPares } = await admin
    .from("bank_transactions")
    .select("id, transaction_date, description, amount, transaction_type, bank_connection_id")
    .eq("reconciled", false)
    .not("bank_connection_id", "is", null)
    .limit(5000);
  const paresInternos = findInternalTransfers((universoParaPares ?? transactions) as never[]);
  const pernaDeTransferencia = new Map<string, string>();
  for (const par of paresInternos) {
    pernaDeTransferencia.set(par.saida.id, par.detail);
    pernaDeTransferencia.set(par.entrada.id, par.detail);
  }

  // ── Pontuação ────────────────────────────────────────────────────────────
  const porTransacao = transactions.map((tx): SugestaoDaTransacao => {
    // Duas formas de reconhecer o mesmo fenômeno: pelo nome da empresa no histórico, ou
    // pelo par saída↔entrada entre contas conectadas. A segunda é mais forte, porque
    // enxerga as duas pernas do movimento em vez de depender do texto.
    const parInterno = pernaDeTransferencia.get(tx.id) ?? null;
    const internalTransfer = !!parInterno ||
      looksLikeInternalTransfer(tx.description, tx.counterparty_name, companyName);

    // Transferência entre contas próprias não tem candidato a procurar: não é receita
    // nem despesa, é o mesmo dinheiro mudando de lugar.
    if (internalTransfer) {
      return { transaction: tx, suggestions: [], groups: [], internalTransfer: true, internalTransferDetail: parInterno };
    }
    const suggestions = suggestMatches(tx, candidates, {}, 5, memoriaPorTx.get(tx.id));
    // Pagamento agrupado só interessa quando nenhuma conta sozinha explica o valor.
    const grupos = suggestions.some((s) => Math.abs(s.difference) < 0.01)
      ? []
      : suggestCombinations(tx, candidates);
    return { transaction: tx, suggestions, groups: grupos, internalTransfer: false, internalTransferDetail: null };
  });

  return { porTransacao, candidatosAvaliados: candidates.length, transferenciasInternas: paresInternos.length };
}
