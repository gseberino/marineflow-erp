// O lote semanal da papelada do escritório (secretário, Passo 5, 16/10/2026) — puro, sem banco e sem IA.
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-papelada.md §3.
//
// "Um secretário de verdade pré-decide, pede um 'sim' para o lote e traz só as exceções." Aqui só se DECIDE o que
// entra; quem aprova continua sendo o caminho de sempre (aprovar_propostas_de_lancamento → finance-review approve),
// depois do "sim <PIN>" do dono.
//
// Entra (um motivo por item, medido e escrito na linha):
//   anotacao      — o dono anotou o que é (a anotação aplicada na proposta, com a mesma categoria);
//   regra         — uma regra DELE (finance_rules.origin = 'user');
//   categoria     — a categoria sugerida que ele mantém em ≥ 90% de ≥ 5 aprovações (medido no histórico);
//   transferencia — transferência entre contas da própria HBR (confiança ≥ 90);
//   aviso_lancado — aviso do vigia ("valor acima", "primeira vez") sobre um pagamento JÁ lançado;
//   aviso_parou   — aviso "parou de aparecer" (só para saber).
// Fica fora (a primeira razão que vale): já lançado, toda entrada, vínculo sugerido, OS/OC, aviso junto, débito sem
// loja, sem categoria, serviço de terceiro, contradiz a última escolha do dono para o mesmo recebedor, acima do limite
// de lote, ele troca a categoria, pouco histórico (1 a 4 decisões, todas mantidas), sem histórico; avisos de
// duplicidade, sobre um Pix ainda na fila, ou soltos.

import { normalizeText } from "../banking/matching.ts";
import { ehIntermediario, historicoSemIdentidade } from "../banking/proposals.ts";
import { nomeDaDescricao } from "../banking/contraparte.ts";
import { exigeDecisao, podeJaEstarLancado, type VinculoSugerido } from "../banking/vinculo.ts";
import { precisaDeDestino } from "../banking/destino.ts";

export type GrupoDoLote = "despesa" | "transferencia" | "aviso";
export type GrupoDeFora = GrupoDoLote | "entrada";

export type MotivoDeEntrada = "anotacao" | "regra" | "categoria" | "transferencia" | "aviso_lancado" | "aviso_parou";
export type MotivoDeFora =
  | "ja_lancado" | "sinal_ja_lancado" | "sem_cliente" | "entrada" | "vinculo" | "os_oc" | "com_aviso" | "sem_loja"
  | "sem_categoria" | "terceiro" | "contradiz" | "acima_do_limite" | "sem_historico" | "pouco_historico" | "troca_categoria"
  | "duplicidade" | "aviso_da_fila" | "aviso_solto" | "comprovante" | "tipo";

/** A linha pendente da fila como a coleta a entrega (finance_review_queue + a linha do banco + o que a cerca). */
export interface LinhaDaFila {
  id: string;
  kind: string;
  title: string;
  suggested_amount: number | null;
  suggested_date: string | null;
  suggested_category: string | null;
  dre_group?: string | null;
  confidence: number | null;
  applied_rule_id: string | null;
  /** finance_rules.origin da regra aplicada ('user' = do dono; 'ai' = aprendida) */
  regra_origem?: string | null;
  suggested_service_order_id?: string | null;
  suggested_purchase_order_id?: string | null;
  suggested_client_id?: string | null;
  vinculo_sugerido?: VinculoSugerido | null;
  // deno-lint-ignore no-explicit-any
  evidencia?: Record<string, any> | null;
  bank_transaction_id: string | null;
  related_transaction_id?: string | null;
  created_at?: string | null;
  /** a chave do vigia nos alertas ('vigia:dup:…', 'vigia:parou:…') */
  suggested_description?: string | null;
  tx?: {
    counterparty_name: string | null;
    counterparty_document: string | null;
    description: string | null;
    transaction_date: string | null;
    amount?: number | null;
  } | null;
  anotacao?: { descricao: string | null; criada_em: string | null; categoria: string | null } | null;
  /** a linha do banco já tem despesa/receita não cancelada */
  tx_lancada?: boolean;
  /** "create_payable:pending,anomaly:approved" — as outras propostas da mesma linha do banco */
  fila_da_tx?: string | null;
  /** alertas do vigia pendentes sobre esta linha do banco */
  alertas_na_tx?: number;
  /** um comprovante (CMP) já ligou esta linha ou a pergunta do extrato espera por ela */
  do_comprovante?: boolean;
}

/** Uma aprovação passada do dono (reconciliation_log 'aprovou_proposta' + a linha do banco). */
export interface DecisaoPassada {
  em: string;
  sug: string | null;
  fin: string | null;
  kind: string;
  counterparty_name: string | null;
  counterparty_document: string | null;
  description: string | null;
}

export interface ContextoDoLote {
  /** finance_review_batch_limit (R$ 500): igual ou acima, é um por um */
  limite: number;
  historico: DecisaoPassada[];
}

/** O que o "sim" confere de novo no banco (papelada_lote_conferir): igual ao da montagem ou o item sai. */
export interface Impressao {
  kind: string;
  valor: number | null;
  categoria: string | null;
  data: string | null;
  regra: string | null;
  vinculo: boolean;
}

export interface ItemDoLote {
  n: number;
  id: string;
  grupo: GrupoDoLote;
  titulo: string;
  valor: number;
  categoria: string | null;
  codigo: MotivoDeEntrada;
  motivo: string;
  impressao: Impressao;
}

export interface ItemDeFora {
  id: string;
  grupo: GrupoDeFora;
  titulo: string;
  valor: number;
  codigo: MotivoDeFora;
  motivo: string;
}

export interface LoteMontado {
  itens: ItemDoLote[];
  fora: ItemDeFora[];
  /** a soma das despesas do lote (transferência e aviso não são gasto) */
  total: number;
  contagens: {
    despesas: number;
    transferencias: number;
    avisos: number;
    fora: number;
    fora_por_grupo: Record<string, number>;
    fora_por_codigo: Record<string, number>;
  };
  /** uns N minutos: 2 para o lote + a conta de sempre sobre o que ficou de fora */
  minutos: number;
}

/** "≥ 90% de ≥ 5 aprovações sem trocar a categoria" — o corte da categoria confiável. */
export const CATEGORIA_CONFIAVEL = { minimo: 5, taxa: 0.9 } as const;
/** A transferência entre contas entra com a confiança do motor a partir disto (97% aprovadas: 56 de 58). */
export const CONFIANCA_DA_TRANSFERENCIA = 90;

const SEM_CATEGORIA = new Set(["", "Outras despesas", "Outras receitas"]);

function numero(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? Math.round(n * 100) / 100 : 0;
}

/** "R$ 500" (sem centavos quando é inteiro) */
function brlInteiro(v: number): string {
  return Number.isInteger(v) ? `R$ ${v.toLocaleString("pt-BR")}` : `R$ ${v.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

function digitos(s: string | null | undefined): string {
  return String(s ?? "").replace(/\D/g, "");
}

/** O nome de quem recebeu, como uma pessoa leria ("Pix enviado para X" → X). */
export function nomeDeQuem(tx: LinhaDaFila["tx"], titulo?: string | null): string {
  const bruto = nomeDaDescricao(tx?.counterparty_name) ?? tx?.counterparty_name ?? nomeDaDescricao(tx?.description) ??
    tx?.description ?? String(titulo ?? "").replace(/^(Despesa|Receita|Transferência entre contas):\s*/i, "");
  return String(bruto ?? "")
    // "Pix recebido c6 de X" (o banco no meio) também é só o nome
    .replace(/^(?:pix|ted|doc|transf\w*)\s+(?:enviad[oa]|recebid[oa]|realizad[oa])\s+(?:\w{1,3}\s+)?(?:de|para|por)\s+/i, "")
    .replace(/\|/g, " ").replace(/\s+/g, " ").trim();
}

const MINUSCULAS = new Set(["de", "da", "do", "das", "dos", "e", "em"]);
const SUFIXOS = /\b(LTDA\.?|S\/?A\.?|S\.A\.?|ME|EPP|EIRELI|INSTITUICAO DE PAGAMENTO|INSTITUIÇÃO DE PAGAMENTO)\b\.?/gi;

function capitalizar(s: string): string {
  return s.toLowerCase().split(" ").filter(Boolean)
    .map((p, i) => (i > 0 && MINUSCULAS.has(p) ? p : p.charAt(0).toUpperCase() + p.slice(1))).join(" ");
}

/**
 * O nome curto da linha: pessoa (CPF) = primeiro nome + inicial do último ("Eliane U."); empresa = sem o sufixo
 * societário, com maiúscula só no começo das palavras, até 26 caracteres.
 */
export function nomeCurto(nome: string, documento?: string | null): string {
  // a parcela no nome ("MERCADO*MERCADOLIVRE 1/2") vira "(2x)" no fim
  const parcela = /\b\d{1,2}\/(\d{1,2})\b/.exec(nome);
  const semParcela = parcela ? nome.replace(parcela[0], " ") : nome;
  const marca = /MERCADO\s*\*?\s*MERCADO\s*LIVRE|MERCADOLIVRE/i.test(semParcela) ? "Mercado Livre" : null;
  const limpo = (marca ?? semParcela).replace(/^\s*(?:DL|PAG|MP|PG|EC|IFD|PICPAY|MERCADOPAGO|EBANX|CAPPTA|STAFE BANK)\s*\*\s*/i, "")
    .replace(/\*/g, " ").replace(/\s+BRA?$/i, "").replace(/\s+/g, " ").trim();
  const comParcela = (t: string) => (parcela ? `${t} (${parcela[1]}x)` : t);
  if (marca) return comParcela(marca);
  if (digitos(documento).length === 11) {
    const p = limpo.split(" ").filter(Boolean);
    if (p.length > 1) return `${capitalizar(p[0])} ${p[p.length - 1].charAt(0).toUpperCase()}.`;
    return capitalizar(limpo);
  }
  const semSufixo = limpo.replace(SUFIXOS, " ").replace(/[-–]\s*$/, "").replace(/\s+/g, " ").trim() || limpo;
  const t = /[a-z]/.test(semSufixo) ? semSufixo : capitalizar(semSufixo);
  return comParcela(t.length <= 26 ? t : `${t.slice(0, 25).trimEnd()}…`);
}

/** "Fatura C6" / "Fatura Nubank" / "Fatura do cartão" — o pagamento de fatura com o banco. */
function rotuloDaFatura(nome: string): string {
  const n = normalizeText(nome);
  if (/\bNU\b|NUBANK|NU PAGAMENTOS/.test(n)) return "Fatura Nubank";
  if (/\bC6\b/.test(n)) return "Fatura C6";
  return "Fatura do cartão";
}

/** O título curto do item (sem "Despesa:"). */
export function tituloDaLinha(l: LinhaDaFila): string {
  if (l.kind === "anomaly") return tituloDoAviso(l.title, l.tx?.counterparty_document);
  // o débito sem loja: o banco não diz quem; a data diz qual é
  if (semIdentidade(l) === "debito") return `Débito sem loja de ${ddmm(l.tx?.transaction_date ?? l.suggested_date)}`;
  const nome = nomeDeQuem(l.tx, l.title);
  if (l.suggested_category === "Pagamento de fatura de cartão") return rotuloDaFatura(nome);
  if (l.kind === "internal_transfer") {
    return /\bHBR\b/i.test(nome) ? "Para a outra conta da HBR" : `Para ${nomeCurto(nome, l.tx?.counterparty_document)}`;
  }
  return nomeCurto(nome, l.tx?.counterparty_document);
}

/** O aviso do vigia numa linha curta: "Unifique parou de aparecer (último em 09/09)". */
export function tituloDoAviso(titulo: string, documento?: string | null): string {
  const t = String(titulo ?? "").replace(/\s+/g, " ").trim();
  const quem = (s: string) => nomeCurto(nomeDaDescricao(s) ?? s.replace(/^Pix enviado para\s+/i, ""), documento);
  const parou = /^(.+?) aparecia todo mês e parou \(último em (\d{2}\/\d{2})\)/.exec(t);
  if (parou) return `${quem(parou[1])} parou de aparecer (último em ${parou[2]})`;
  const valor = /^Valor acima do padrão: (.+?) — (R\$ [\d.,]+)(?: \(costuma ser ~?(R\$ [\d.,]+)\))?/.exec(t);
  if (valor) return `${quem(valor[1])}: ${valor[2]} acima do normal${valor[3] ? ` (~${valor[3]})` : ""}`;
  const novo = /^Primeira vez no extrato: (.+?) — (R\$ [\d.,]+)/.exec(t);
  if (novo) return `${quem(novo[1])}: primeira vez, ${novo[2]}`;
  const dup = /^Possível duplicidade: (.+?) — (R\$ [\d.,]+) em (\d{2}\/\d{2}) e (\d{2}\/\d{2})/.exec(t);
  if (dup) return `${quem(dup[1])}: ${dup[2]} duas vezes (${dup[3]} e ${dup[4]})`;
  return t.length <= 70 ? t : `${t.slice(0, 69).trimEnd()}…`;
}

/** A chave de quem recebeu: o documento (≥ 11 dígitos), senão o nome normalizado ("" = não identifica ninguém). */
export function chavesDoRecebedor(p: { counterparty_name: string | null; counterparty_document: string | null; description: string | null }): string[] {
  const chaves: string[] = [];
  const doc = digitos(p.counterparty_document);
  if (doc.length >= 11) chaves.push(`doc:${doc}`);
  const nome = normalizeText(nomeDaDescricao(p.counterparty_name) ?? p.counterparty_name ?? nomeDaDescricao(p.description) ?? p.description ?? "");
  if (nome && !historicoSemIdentidade(nome) && !ehIntermediario(nome)) chaves.push(`nome:${nome}`);
  return chaves;
}

/** Quantas aprovações de cada categoria sugerida o dono manteve (só despesas). */
export function aceitacaoPorCategoria(h: DecisaoPassada[]): Map<string, { n: number; igual: number }> {
  const m = new Map<string, { n: number; igual: number }>();
  for (const d of h) {
    if (d.kind !== "create_payable" || !d.sug) continue;
    const a = m.get(d.sug) ?? { n: 0, igual: 0 };
    a.n += 1;
    if (d.sug === d.fin) a.igual += 1;
    m.set(d.sug, a);
  }
  return m;
}

/** O que o dono escolheu por último para cada recebedor (só despesas), e se ele já trocou alguma vez. */
export interface EscolhaDoRecebedor {
  ultima: string;
  /** quantas das últimas decisões seguidas foram para `ultima` */
  seguidas: number;
  trocou: boolean;
}

export function escolhasPorRecebedor(h: DecisaoPassada[]): Map<string, EscolhaDoRecebedor> {
  const porChave = new Map<string, DecisaoPassada[]>();
  for (const d of [...h].sort((a, b) => a.em.localeCompare(b.em))) {
    if (d.kind !== "create_payable" || !d.fin) continue;
    for (const k of chavesDoRecebedor(d)) {
      const l = porChave.get(k) ?? [];
      l.push(d);
      porChave.set(k, l);
    }
  }
  const m = new Map<string, EscolhaDoRecebedor>();
  for (const [k, l] of porChave) {
    const ultima = l[l.length - 1].fin!;
    let seguidas = 0;
    for (let i = l.length - 1; i >= 0 && l[i].fin === ultima; i--) seguidas += 1;
    m.set(k, { ultima, seguidas, trocou: l.some((d) => d.sug !== d.fin) });
  }
  return m;
}

/** O débito (ou o Pix) em que o banco não disse para quem foi — e que o dono não anotou. */
export function semIdentidade(l: LinhaDaFila): "debito" | "sem_nome" | null {
  if (l.anotacao || l.evidencia?.anotacao) return null;
  const tx = l.tx;
  if (!tx || digitos(tx.counterparty_document).length >= 11) return null;
  if (!historicoSemIdentidade(tx.counterparty_name || tx.description)) return null;
  return /^(DEBITO|COMPRA)/.test(normalizeText(String(tx.description ?? ""))) ? "debito" : "sem_nome";
}

function umaLinhaCurta(s: string, max: number): string {
  const t = s.replace(/\s+/g, " ").trim();
  return t.length <= max ? t : `${t.slice(0, max - 1).trimEnd()}…`;
}

function ddmm(iso: string | null | undefined): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso ?? ""));
  return m ? `${m[3]}/${m[2]}` : "";
}

/** A data de Brasília de um carimbo (a anotação foi "em 06/10"). */
function ddmmBR(ts: string | null | undefined): string {
  const t = Date.parse(String(ts ?? ""));
  if (!Number.isFinite(t)) return ddmm(ts);
  return ddmm(new Date(t - 3 * 3600_000).toISOString());
}

function filaDaTx(l: LinhaDaFila): string[] {
  return String(l.fila_da_tx ?? "").split(",").map((s) => s.trim()).filter(Boolean);
}

type Decisao =
  | { entra: true; codigo: MotivoDeEntrada; motivo: string }
  | { entra: false; codigo: MotivoDeFora; motivo: string };

const fora = (codigo: MotivoDeFora, motivo: string): Decisao => ({ entra: false, codigo, motivo });
const entra = (codigo: MotivoDeEntrada, motivo: string): Decisao => ({ entra: true, codigo, motivo });

/** Por que esta linha entra (ou não) no lote. A primeira razão que vale. */
export function decidir(
  l: LinhaDaFila,
  ctx: ContextoDoLote,
  medidas: { aceitacao: Map<string, { n: number; igual: number }>; escolhas: Map<string, EscolhaDoRecebedor> },
): Decisao {
  const valor = numero(l.suggested_amount);
  const cat = String(l.suggested_category ?? "").trim();
  const outras = filaDaTx(l);

  if (l.kind === "anomaly") {
    const chave = String(l.suggested_description ?? "");
    if (chave.startsWith("vigia:dup:")) return fora("duplicidade", "pode ser cobrança em dobro: confira os dois");
    if (outras.some((o) => o.endsWith(":pending"))) return fora("aviso_da_fila", "o Pix está na fila: vai junto com a despesa");
    if (chave.startsWith("vigia:parou:")) return entra("aviso_parou", "só para saber");
    if (l.tx_lancada || outras.some((o) => o.endsWith(":approved"))) return entra("aviso_lancado", "o pagamento já está lançado");
    return fora("aviso_solto", "o pagamento não está lançado nem na fila");
  }

  if (l.tx_lancada || outras.some((o) => o.endsWith(":approved"))) return fora("ja_lancado", "a linha do banco já está lançada");

  if (l.kind === "create_receivable") {
    const v = l.vinculo_sugerido ?? null;
    if (v?.principal && (v.principal.jaLancado || podeJaEstarLancado(v))) {
      const rotulo = String(v.principal.rotulo ?? "").replace(/^Pagamento já lançado:\s*/i, "");
      return fora("sinal_ja_lancado", `parece ${rotulo || "algo"} já lançado: é ligar ao extrato, não lançar de novo`);
    }
    if (exigeDecisao(v)) return fora("vinculo", `parece ${String(v!.principal.rotulo ?? "uma conta")}: só você liga`);
    if (!l.suggested_client_id && !l.evidencia?.cliente?.id) return fora("sem_cliente", "de quem é? a entrada não tem cliente");
    return fora("entrada", "entrada: pode pagar uma cobrança em aberto; só você liga");
  }

  if (l.kind === "internal_transfer") {
    if (Number(l.confidence ?? 0) < CONFIANCA_DA_TRANSFERENCIA) return fora("sem_historico", "não tenho certeza de que é entre contas suas");
    return entra("transferencia", "dinheiro entre contas da HBR");
  }

  if (l.kind !== "create_payable") return fora("tipo", "outro tipo de proposta");
  if (l.do_comprovante) return fora("comprovante", "um comprovante seu está cuidando desta");

  // ── despesa ──
  if (exigeDecisao(l.vinculo_sugerido)) {
    const rotulo = umaLinhaCurta(String(l.vinculo_sugerido!.principal.rotulo ?? "")
      .replace(/^Pagamento já lançado:\s*/i, "").replace(/^Pago por [^:]+:\s*/i, ""), 50);
    return fora("vinculo", podeJaEstarLancado(l.vinculo_sugerido) ? `pode já estar lançada (${rotulo})` : `parece pagar ${rotulo}: só você liga`);
  }
  if (l.suggested_service_order_id || l.suggested_purchase_order_id) return fora("os_oc", "tem OS ou OC para você confirmar");
  if (Number(l.alertas_na_tx ?? 0) > 0) return fora("com_aviso", "tem aviso de gasto junto: veja os dois");
  const semNome = semIdentidade(l);
  if (semNome) return fora("sem_loja", semNome === "debito" ? "débito sem loja: o banco não diz onde foi" : "o banco não diz para quem foi");
  if (SEM_CATEGORIA.has(cat)) return fora("sem_categoria", "não sei o que é");
  if (precisaDeDestino(l.kind, cat)) return fora("terceiro", "serviço de terceiro: falta para onde foi e o que foi feito");

  // a anotação é a palavra do dono sobre ESTA linha: vale mais que o histórico do recebedor
  const anot = l.anotacao ?? null;
  const anotada = !!(anot || l.evidencia?.anotacao) && (!anot?.categoria || anot.categoria === cat);
  // a última escolha do dono para o mesmo recebedor contradiz a sugestão (e ele já trocou antes)
  if (!anotada) {
    for (const k of l.tx ? chavesDoRecebedor(l.tx) : []) {
      const e = medidas.escolhas.get(k);
      if (e && e.trocou && e.ultima !== cat) {
        return fora("contradiz", `${e.seguidas === 1 ? "na última vez" : `nas ${e.seguidas} últimas vezes`} você lançou como ${e.ultima}`);
      }
    }
  }
  if (!(valor < ctx.limite)) return fora("acima_do_limite", `${brlInteiro(ctx.limite)} ou mais: é um por um`);

  if (anotada) return entra("anotacao", anot?.criada_em ? `você anotou em ${ddmmBR(anot.criada_em)}` : "você anotou");
  if (l.applied_rule_id && l.regra_origem === "user") return entra("regra", "regra sua");
  const a = medidas.aceitacao.get(cat);
  if (a && a.n >= CATEGORIA_CONFIAVEL.minimo && a.igual / a.n >= CATEGORIA_CONFIAVEL.taxa) {
    return entra("categoria", `${a.igual} de ${a.n} sem troca`);
  }
  if (!a) return fora("sem_historico", "ainda sem histórico para decidir");
  // (21/10/2026) o motivo diz a verdade: antes era "você troca esta categoria às vezes (1 de 1)" quando a única decisão
  // foi MANTIDA (a "Retirada de sócio" de 28/09), e o número era o das mantidas lido como trocas ("2 de 10" no
  // Combustível, que ele trocou 8 vezes)
  const trocas = a.n - a.igual;
  // (22/10/2026) código próprio: o resumo do *lote* conta por código, e "sem_historico" virava "ainda sem histórico"
  // para quem tem 1 a 4 decisões (resumoDeFora, texto.ts)
  if (trocas === 0) {
    return fora("pouco_historico", `só ${a.n} ${a.n === 1 ? "vez" : "vezes"} nesta categoria, sem troca (o lote pede ${CATEGORIA_CONFIAVEL.minimo})`);
  }
  return fora("troca_categoria", a.n === 1 ? "você trocou esta categoria na única vez" : `você trocou esta categoria em ${trocas} de ${a.n} vezes`);
}

export function impressaoDa(l: LinhaDaFila): Impressao {
  return {
    kind: l.kind,
    valor: l.suggested_amount == null ? null : numero(l.suggested_amount),
    categoria: l.suggested_category ?? null,
    data: l.suggested_date ? String(l.suggested_date).slice(0, 10) : null,
    regra: l.applied_rule_id ?? null,
    vinculo: !!l.vinculo_sugerido,
  };
}

const GRUPO: Record<string, GrupoDoLote> = { create_payable: "despesa", internal_transfer: "transferencia", anomaly: "aviso" };
const ORDEM_DO_GRUPO: Record<GrupoDoLote, number> = { despesa: 0, transferencia: 1, aviso: 2 };

/** Quanto tempo: 2 min para o lote + 20 s por item de fora + 1 min a mais por débito sem loja (arredonda em 5). */
export function minutosDoLote(itens: number, fora: ItemDeFora[]): number {
  const semLoja = fora.filter((f) => f.codigo === "sem_loja").length;
  const segundos = (itens > 0 ? 120 : 0) + fora.length * 20 + semLoja * 60;
  if (segundos <= 0) return 0;
  return Math.max(5, Math.round(segundos / 300) * 5);
}

/** Monta o lote da semana a partir da fila pendente. Determinístico: mesma fila, mesmo lote. */
export function montarLote(fila: LinhaDaFila[], ctx: ContextoDoLote): LoteMontado {
  const medidas = { aceitacao: aceitacaoPorCategoria(ctx.historico), escolhas: escolhasPorRecebedor(ctx.historico) };
  const dentro: Array<Omit<ItemDoLote, "n">> = [];
  const foraDoLote: ItemDeFora[] = [];
  for (const l of fila) {
    const d = decidir(l, ctx, medidas);
    const titulo = tituloDaLinha(l);
    const valor = numero(l.suggested_amount);
    if (d.entra) {
      dentro.push({
        id: l.id, grupo: GRUPO[l.kind], titulo, valor, categoria: l.suggested_category ?? null,
        codigo: d.codigo, motivo: d.motivo, impressao: impressaoDa(l),
      });
    } else {
      const grupo: GrupoDeFora = l.kind === "create_receivable" ? "entrada" : GRUPO[l.kind] ?? "despesa";
      foraDoLote.push({ id: l.id, grupo, titulo, valor, codigo: d.codigo, motivo: d.motivo });
    }
  }
  dentro.sort((a, b) => ORDEM_DO_GRUPO[a.grupo] - ORDEM_DO_GRUPO[b.grupo] || b.valor - a.valor || a.id.localeCompare(b.id));
  foraDoLote.sort((a, b) => b.valor - a.valor || a.id.localeCompare(b.id));
  const itens = dentro.map((i, k) => ({ n: k + 1, ...i }));
  const conta = (lista: string[]) => lista.reduce<Record<string, number>>((m, k) => ((m[k] = (m[k] ?? 0) + 1), m), {});
  const despesas = itens.filter((i) => i.grupo === "despesa");
  return {
    itens,
    fora: foraDoLote,
    total: numero(despesas.reduce((s, i) => s + i.valor, 0)),
    contagens: {
      despesas: despesas.length,
      transferencias: itens.filter((i) => i.grupo === "transferencia").length,
      avisos: itens.filter((i) => i.grupo === "aviso").length,
      fora: foraDoLote.length,
      fora_por_grupo: conta(foraDoLote.map((f) => f.grupo)),
      fora_por_codigo: conta(foraDoLote.map((f) => f.codigo)),
    },
    minutos: minutosDoLote(itens.length, foraDoLote),
  };
}
