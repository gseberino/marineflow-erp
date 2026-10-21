// A recusa da fila que FICA — e o desfazer dela (20/10/2026, spec-papelada-fix.md, itens A1, A2 e A4).
//
// ═══ OS DEFEITOS ═══
//
// 1. "Recusar não fica". O `gerar` só pulava o que estava PENDENTE na fila (naFila, index.ts) e o índice
//    único finance_review_uma_por_transacao só vale para status 'pending': a linha recusada continuava
//    reconciled=false, voltava à leitura e nascia proposta nova — no dia seguinte (janela de 90 dias) ou no
//    mutirão do histórico. Medido em 20/10/2026: das 14 recusas de despesa/entrada/transferência, 7 são da
//    mesma linha e do mesmo tipo de uma recusa anterior (4 estornos de pedágio e o Pix de R$ 1.000, que
//    voltaram no mutirão de 26/09 e foram recusados de novo; a transferência TICKETEXPRESS, recusada duas
//    vezes em 29/07). Nenhuma das 66 pendentes de hoje é repetição de uma recusada.
// 2. Recusar uma ENTRADA não marcava a linha do banco. O resumo e a tarde contam "entrada sem
//    identificação" pelos créditos com reconciled=false e dismissed_at nulo: as 6 entradas antigas já
//    recusadas (R$ 1.045,95, 5 delas duas vezes) continuavam contadas para sempre.
//
// ═══ A REGRA ═══
//
// 1. A recusa vale para a MESMA linha do banco e o MESMO tipo de proposta. A linha volta a ser proposta só
//    se mudar de verdade (outra data; ou outro valor — na compra parcelada o valor da proposta é o total da
//    compra, então ali só a data conta) ou se o dono desfizer a recusa (reabrirPropostas). Outro tipo para
//    a mesma linha (ex.: a entrada recusada que agora tem a outra perna e virou transferência) é fato novo.
// 2. Recusar uma ENTRADA tira a linha da fila pelo caminho de sempre das linhas sem lançamento (o mesmo do
//    approve para transferência/aporte e do "Tirar da fila" da tela): reconciled=true, dismissed_kind
//    'manual' (conta no saldo e no fluxo como movimento — o dinheiro entrou de verdade), dismissed_reason
//    "Recusada na fila: …", quem e quando. Aparece em Extrato › Fora da fila, e "trazer de volta"
//    (undismiss) desfaz. As RPCs de conciliar já recusam linha fora da fila com "traga-a de volta antes".
// 3. Recusar uma SAÍDA não marca nada: a despesa existe e não está lançada (as contas de "saídas sem
//    lançamento" continuam honestas); ela só não volta a ser proposta.
// 4. Desfazer (reabrirPropostas, a ação 'reopen'): recebe ids de PROPOSTA — o que a tool do assistente
//    tem na mão. A linha que está em Fora da fila volta pelo undismiss de sempre; a recusa de saída (ou de
//    aviso) só reabre a proposta.

// deno-lint-ignore no-explicit-any
type Admin = any;

export const PREFIXO_DA_RECUSA = "Recusada na fila";

export type TipoDeProposta = "create_payable" | "create_receivable" | "internal_transfer";

/** A recusa que vale para uma linha + um tipo: a impressão da linha quando a proposta nasceu. */
export interface Recusa {
  id: string;
  kind: string;
  suggested_date: string | null;
  suggested_amount: number | string | null;
  title: string | null;
  decided_at: string | null;
}

/** Uma proposta da fila, como lida para decidir qual é a última de cada linha + tipo. */
export interface PropostaDaLinha extends Recusa {
  status: string;
  bank_transaction_id: string | null;
  created_at: string;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const COMPRA_PARCELADA = /\(\d+x\)$/;

/** O tipo de proposta que a linha teria AGORA — a mesma decisão do gerar (par, CNPJ da HBR, sentido). */
export function tipoDaProposta(
  tx: { transaction_type: string; counterparty_document?: string | null },
  ehPernaDeSaidaDeUmPar: boolean,
  cnpjEmpresa: string,
): TipoDeProposta {
  if (ehPernaDeSaidaDeUmPar) return "internal_transfer";
  const doc = String(tx.counterparty_document ?? "").replace(/\D/g, "");
  if (cnpjEmpresa.length === 14 && doc === cnpjEmpresa) return "internal_transfer";
  return tx.transaction_type === "debit" ? "create_payable" : "create_receivable";
}

/**
 * A linha do banco mudou desde a proposta recusada? Outra data, ou outro valor (fora da compra parcelada,
 * em que a proposta guarda o total). Sem a data na proposta não há com o que comparar: vale a recusa.
 */
export function linhaMudou(r: Recusa, tx: { transaction_date: string; amount: number | string }): boolean {
  const dataDaRecusa = String(r.suggested_date ?? "").slice(0, 10);
  if (dataDaRecusa && dataDaRecusa !== String(tx.transaction_date).slice(0, 10)) return true;
  if (COMPRA_PARCELADA.test(String(r.title ?? "").trim())) return false;
  if (r.suggested_amount == null || r.suggested_amount === "") return false;
  return Math.abs(Math.abs(Number(tx.amount)) - Math.abs(Number(r.suggested_amount))) > 0.005;
}

/** A recusa que ainda segura esta linha para este tipo, ou null (propor de novo). */
export function recusaQueVale(
  recusas: Recusa[] | undefined,
  tipo: TipoDeProposta,
  tx: { transaction_date: string; amount: number | string },
): Recusa | null {
  for (const r of recusas ?? []) {
    if (r.kind === tipo && !linhaMudou(r, tx)) return r;
  }
  return null;
}

/**
 * De todas as propostas das linhas, a recusa que vale por linha: para cada linha + tipo, a ÚLTIMA proposta
 * (a mais nova); só conta se ela for 'rejected'. Uma recusa antiga seguida de aprovação (a linha foi
 * desfeita e voltou) não segura nada; aviso do vigia (anomaly) não entra.
 */
export function recusasPorLinha(propostas: PropostaDaLinha[]): Map<string, Recusa[]> {
  const ultima = new Map<string, PropostaDaLinha>();
  for (const p of propostas) {
    if (!p.bank_transaction_id || p.kind === "anomaly") continue;
    const chave = `${p.bank_transaction_id}|${p.kind}`;
    const atual = ultima.get(chave);
    if (!atual || String(p.created_at) > String(atual.created_at)) ultima.set(chave, p);
  }
  const porLinha = new Map<string, Recusa[]>();
  for (const p of ultima.values()) {
    if (p.status !== "rejected") continue;
    const tx = String(p.bank_transaction_id);
    const lista = porLinha.get(tx) ?? [];
    lista.push({
      id: p.id, kind: p.kind, suggested_date: p.suggested_date, suggested_amount: p.suggested_amount,
      title: p.title, decided_at: p.decided_at,
    });
    porLinha.set(tx, lista);
  }
  return porLinha;
}

/** As recusas que valem para estas linhas do banco (em pedaços de 150). Lança se a leitura falhar. */
export async function lerRecusas(admin: Admin, txIds: string[]): Promise<Map<string, Recusa[]>> {
  const ids = [...new Set(txIds.filter((id) => UUID.test(String(id))))];
  const todas: PropostaDaLinha[] = [];
  for (let i = 0; i < ids.length; i += 150) {
    const { data, error } = await admin.from("finance_review_queue")
      .select("id, kind, status, bank_transaction_id, created_at, decided_at, suggested_amount, suggested_date, title")
      .in("bank_transaction_id", ids.slice(i, i + 150))
      .neq("kind", "anomaly");
    if (error) throw error;
    todas.push(...((data ?? []) as PropostaDaLinha[]));
  }
  return recusasPorLinha(todas);
}

/**
 * Das propostas de uma linha devolvida à fila (undismiss), quais reabrir: a ÚLTIMA de cada linha + tipo.
 * Reabrir todas estourava o índice "uma pendente por linha e tipo" quando a mesma linha tinha duas
 * recusas (os 4 estornos de pedágio) — e o undismiss inteiro caía. Aviso do vigia não volta junto.
 */
export function propostasAReabrir(
  propostas: Array<{ id: string; kind?: string | null; bank_transaction_id: string | null; created_at?: string | null }>,
): string[] {
  const ultima = new Map<string, { id: string; created_at: string }>();
  for (const p of propostas) {
    if (p.kind === "anomaly") continue;
    const chave = `${p.bank_transaction_id ?? `sem-linha:${p.id}`}|${p.kind ?? ""}`;
    const atual = ultima.get(chave);
    const quando = String(p.created_at ?? "");
    if (!atual || quando > atual.created_at) ultima.set(chave, { id: p.id, created_at: quando });
  }
  return [...ultima.values()].map((v) => v.id);
}

/** O motivo gravado na linha da entrada recusada (aparece em Extrato › Fora da fila). */
export function motivoDaRecusa(nota: string | null | undefined): string {
  const t = String(nota ?? "").replace(/\s+/g, " ").trim();
  return `${PREFIXO_DA_RECUSA}: ${t || "não é receita a lançar"}`.slice(0, 300);
}

type Anotar = (registro: {
  acao: string;
  autor?: string | null;
  bank_transaction_id?: string | null;
  valor?: number | null;
  detalhe?: string | null;
  antes?: unknown;
  depois?: unknown;
}) => Promise<void>;

/**
 * Recusa as propostas pendentes e, nas ENTRADAS, tira a linha do banco da fila (regra 2). Só marca a linha
 * que ainda está livre (não conciliada, não fora da fila, é crédito): a recusa nunca desfaz o que outro
 * caminho fez. Falhar em marcar não desfaz a recusa: vira aviso na resposta.
 */
export async function recusarPropostas(
  admin: Admin,
  ids: string[],
  userId: string | null,
  nota: string | null,
  anotar: Anotar,
): Promise<{ status: number; corpo: Record<string, unknown> }> {
  if (!Array.isArray(ids) || ids.length === 0) return { status: 400, corpo: { error: "nenhuma proposta informada" } };
  const agora = new Date().toISOString();
  const { data, error } = await admin.from("finance_review_queue").update({
    status: "rejected", decided_by: userId, decided_at: agora, decision_note: nota,
  }).in("id", ids).eq("status", "pending").select("id, kind, bank_transaction_id, title, suggested_amount");
  if (error) throw error;
  const recusadas = (data ?? []) as Array<{ id: string; kind: string; bank_transaction_id: string | null; title: string | null; suggested_amount: number | null }>;

  let entradasForaDaFila = 0;
  const avisos: string[] = [];
  const motivo = motivoDaRecusa(nota);
  for (const p of recusadas) {
    if (p.kind !== "create_receivable" || !p.bank_transaction_id) continue;
    const { data: marcada, error: eMarca } = await admin.from("bank_transactions").update({
      reconciled: true,
      dismissed_kind: "manual",
      dismissed_reason: motivo,
      dismissed_at: agora,
      dismissed_by: userId,
    }).eq("id", p.bank_transaction_id).eq("transaction_type", "credit").eq("reconciled", false)
      .is("dismissed_reason", null).select("id");
    if (eMarca) {
      avisos.push(`${String(p.title ?? "Entrada").slice(0, 60)}: recusada, mas a linha do banco não saiu da fila (${String(eMarca.message ?? eMarca).slice(0, 80)})`);
      continue;
    }
    if (!(marcada as unknown[] | null)?.length) continue;
    entradasForaDaFila += 1;
    await anotar({
      acao: "ignorou",
      autor: userId,
      bank_transaction_id: p.bank_transaction_id,
      valor: p.suggested_amount == null ? null : Number(p.suggested_amount),
      detalhe: `${motivo} · ${String(p.title ?? "").slice(0, 120)}`.slice(0, 300),
      antes: { estado: "pendente", proposta: p.id },
      depois: { estado: "fora_da_fila", dismissed_kind: "manual" },
    });
  }

  const n = recusadas.length;
  const message = `${n} proposta(s) recusada(s)`
    + (entradasForaDaFila > 0
      ? ` · ${entradasForaDaFila} entrada(s) saíram da fila do banco (para trazer de volta: Extrato › Fora da fila)` : "")
    + (n < ids.length ? ` · ${ids.length - n} já não estava(m) pendente(s)` : "")
    + (avisos.length ? ` · ${avisos.join(" · ")}` : "");
  return {
    status: 200,
    corpo: { ok: avisos.length === 0, recusadas: n, entradas_fora_da_fila: entradasForaDaFila, avisos, message },
  };
}

export interface DependenciasDoReabrir {
  anotar: Anotar;
  /** O lançamento ativo que já usa a linha, descrito; null = nenhum (index.ts). */
  lancamentoDaTransacao: (txId: string) => Promise<string | null>;
  /** O undismiss de sempre (Extrato › Fora da fila › trazer de volta), com ids de LINHA do banco. */
  desfazerIgnorada: (txIds: string[], userId: string | null) => Promise<Record<string, unknown>>;
}

function hojeBR(): string {
  const [a, m, d] = new Date(Date.now() - 3 * 3_600_000).toISOString().slice(0, 10).split("-");
  return `${d}/${m}/${a}`;
}

/**
 * Desfaz a recusa (ou a saída da fila) de PROPOSTAS — regra 4. Para cada id:
 *  - pendente: nada a fazer ("já está na fila");
 *  - a linha do banco está em Fora da fila (a entrada recusada, a transferência aprovada, a parcela, a
 *    duplicata): volta pelo undismiss de sempre, que devolve a linha e reabre a última proposta dela;
 *  - recusada com a linha livre (saída, ou aviso do vigia): reabre a proposta — se a linha não ganhou
 *    lançamento nem outra proposta pendente desde então;
 *  - aprovada (virou lançamento): não é aqui — "desfazer_aprovacao_de_lancamento".
 */
export async function reabrirPropostas(
  admin: Admin,
  ids: string[],
  userId: string | null,
  deps: DependenciasDoReabrir,
): Promise<{ status: number; corpo: Record<string, unknown> }> {
  const lista = [...new Set((Array.isArray(ids) ? ids : []).map(String).filter((id) => UUID.test(id)))];
  if (lista.length === 0) return { status: 400, corpo: { error: "nenhuma proposta informada (use os ids das propostas)" } };

  const { data, error } = await admin.from("finance_review_queue")
    .select("id, kind, status, bank_transaction_id, title").in("id", lista);
  if (error) throw error;
  const porId = new Map(((data ?? []) as Array<{ id: string; kind: string; status: string; bank_transaction_id: string | null; title: string | null }>)
    .map((p) => [String(p.id), p]));

  const txIds = [...new Set([...porId.values()].map((p) => p.bank_transaction_id).filter((v): v is string => !!v))];
  const linhas = new Map<string, { id: string; reconciled: boolean | null; dismissed_reason: string | null; dismissed_kind: string | null }>();
  if (txIds.length > 0) {
    const { data: lidas, error: eLinhas } = await admin.from("bank_transactions")
      .select("id, reconciled, dismissed_reason, dismissed_kind").in("id", txIds);
    if (eLinhas) throw eLinhas;
    for (const l of (lidas ?? []) as Array<{ id: string; reconciled: boolean | null; dismissed_reason: string | null; dismissed_kind: string | null }>) {
      linhas.set(String(l.id), l);
    }
  }

  const falhas: string[] = [];
  const reabertas: string[] = [];
  const paraOUndismiss = new Set<string>();
  const rotulo = (p: { title: string | null }, id: string) => String(p.title ?? id).slice(0, 60);

  for (const id of lista) {
    const p = porId.get(id);
    if (!p) { falhas.push(`${id}: não está na caixa de entrada`); continue; }
    if (p.status === "pending") { falhas.push(`${rotulo(p, id)}: já está na fila`); continue; }
    const linha = p.bank_transaction_id ? linhas.get(String(p.bank_transaction_id)) : undefined;
    if (linha?.dismissed_reason) { paraOUndismiss.add(String(linha.id)); continue; }
    if (p.status !== "rejected") {
      falhas.push(p.status === "approved"
        ? `${rotulo(p, id)}: foi aprovada e virou lançamento — para desfazer, use desfazer_aprovacao_de_lancamento`
        : `${rotulo(p, id)}: saiu da fila porque já estava lançada por outro caminho`);
      continue;
    }
    if (p.bank_transaction_id) {
      if (linha?.reconciled) { falhas.push(`${rotulo(p, id)}: a linha do banco já foi conciliada por outro caminho`); continue; }
      const ja = await deps.lancamentoDaTransacao(String(p.bank_transaction_id));
      if (ja) { falhas.push(`${rotulo(p, id)}: a linha já foi lançada como ${ja}`); continue; }
      const { data: outra, error: eOutra } = await admin.from("finance_review_queue").select("id")
        .eq("bank_transaction_id", p.bank_transaction_id).eq("kind", p.kind).eq("status", "pending").limit(1);
      if (eOutra) throw eOutra;
      if ((outra as unknown[] | null)?.length) { falhas.push(`${rotulo(p, id)}: já há outra proposta pendente desta linha`); continue; }
    }
    const { data: aberta, error: eAbre } = await admin.from("finance_review_queue").update({
      status: "pending", decided_by: null, decided_at: null, decision_note: `Recusa desfeita em ${hojeBR()}`,
    }).eq("id", id).eq("status", "rejected").select("id");
    if (eAbre) {
      const corrida = /uma_por_transacao|duplicate key|23505/i.test(String(eAbre.message ?? eAbre.code ?? eAbre));
      falhas.push(`${rotulo(p, id)}: ${corrida ? "já há outra proposta pendente desta linha" : String(eAbre.message ?? eAbre).slice(0, 120)}`);
      continue;
    }
    if (!(aberta as unknown[] | null)?.length) { falhas.push(`${rotulo(p, id)}: mudou enquanto eu desfazia — confira a fila`); continue; }
    reabertas.push(id);
    await deps.anotar({
      acao: "devolveu",
      autor: userId,
      bank_transaction_id: p.bank_transaction_id,
      detalhe: `Recusa desfeita: a proposta voltou para a fila · ${rotulo(p, id)}`.slice(0, 300),
      antes: { status: "rejected" },
      depois: { status: "pending" },
    });
  }

  let undismiss: Record<string, unknown> | null = null;
  if (paraOUndismiss.size > 0) {
    undismiss = await deps.desfazerIgnorada([...paraOUndismiss], userId);
    if (undismiss?.error) falhas.push(`a linha não voltou da Fora da fila: ${String(undismiss.error).slice(0, 120)}`);
  }

  const linhasDeVolta = Number(undismiss?.transacoes ?? 0);
  const reabertasPeloUndismiss = Number(undismiss?.propostas_reabertas ?? 0);
  const partes = [
    reabertas.length > 0 ? `${reabertas.length} recusa(s) desfeita(s): a proposta voltou para a fila` : "",
    undismiss ? String(undismiss.message ?? `${linhasDeVolta} linha(s) de volta à fila`) : "",
    falhas.length ? `${falhas.length} não: ${falhas.join(" · ")}` : "",
  ].filter(Boolean);
  return {
    status: 200,
    corpo: {
      ok: falhas.length === 0,
      reabertas: reabertas.length + reabertasPeloUndismiss,
      linhas_de_volta: linhasDeVolta,
      falhas,
      message: partes.join(" · ") || "Nada para desfazer",
    },
  };
}
