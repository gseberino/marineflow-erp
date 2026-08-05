// Compra parcelada no cartão: uma compra, não N despesas.
//
// O extrato mostra a parcela, não a compra. Sem ler isso, uma compra de R$ 1.024 em 10x
// virava dez despesas de R$ 102,40 — dez linhas para classificar, dez fornecedores
// "diferentes" no relatório, e um custo por serviço que não fecha com nota nenhuma. A
// compra aconteceu UMA vez, num dia só, por um valor só.
//
// O QUE IDENTIFICA A COMPRA
// O rótulo do parcelamento ("3/10") vem do provedor e é explícito: diz o número da parcela
// e quantas são. Junto do favorecido e do valor da parcela, ele identifica a compra sem
// ambiguidade — duas compras diferentes no mesmo lugar teriam valor de parcela diferente,
// e se tiverem o mesmo valor e o mesmo número de parcelas, são indistinguíveis no extrato
// de qualquer forma (inclusive para quem olha à mão).
//
// O QUE JÁ FOI PAGO
// Tudo até a ÚLTIMA parcela vista já saiu da conta — inclusive as parcelas anteriores à
// primeira que aparece no extrato importado, que são passado que o recorte não alcança.
// O que falta são as parcelas seguintes, que ainda vão vencer. Por isso o lançamento nasce
// com saldo em aberto quando o parcelamento não terminou, em vez de fingir que a compra
// inteira já foi paga.

import { normalizeText } from "./matching.ts";

export interface PernaDeParcelamento {
  id: string;
  transaction_date: string;
  description: string;
  amount: number;
  counterparty_name?: string | null;
  installment_label?: string | null;
}

/** Número e total de parcelas a partir do rótulo "3/10". Null quando não é parcelamento. */
export function lerParcela(rotulo: string | null | undefined): { numero: number; total: number } | null {
  const m = String(rotulo || "").match(/^\s*(\d{1,2})\s*\/\s*(\d{1,2})\s*$/);
  if (!m) return null;
  const numero = Number(m[1]);
  const total = Number(m[2]);
  // "1/1" é compra à vista com rótulo: não há o que agrupar.
  if (!Number.isFinite(numero) || !Number.isFinite(total)) return null;
  if (total < 2 || numero < 1 || numero > total) return null;
  return { numero, total };
}

export interface CompraParcelada {
  chave: string;
  /** Nome do favorecido como aparece no extrato. */
  rotulo: string;
  valorDaParcela: number;
  totalDeParcelas: number;
  /** O que a compra custou: é este o valor da despesa. */
  valorDaCompra: number;
  /** Pernas presentes no extrato, da primeira parcela para a última. */
  pernas: PernaDeParcelamento[];
  /** Onde a proposta mora: a parcela mais antiga que o extrato tem. */
  ancora: PernaDeParcelamento;
  menorParcelaVista: number;
  maiorParcelaVista: number;
  /** Parcelas que já saíram da conta, incluindo as anteriores ao período importado. */
  jaPago: number;
  /** Parcelas que ainda vão vencer. */
  aVencer: number;
  /** Quantas parcelas ficaram fora do extrato importado, antes da primeira vista. */
  anterioresForaDoExtrato: number;
}

function chaveDaCompra(tx: PernaDeParcelamento, total: number): string {
  const quem = normalizeText(tx.counterparty_name || tx.description || "");
  return `${quem}|${tx.amount.toFixed(2)}|${total}`;
}

/**
 * Junta as pernas de cada compra parcelada.
 *
 * Devolve também `pernaDe`: para cada transação, a chave da compra a que ela pertence —
 * é o que permite ao motor propor a compra UMA vez e não propor as outras pernas.
 */
export function agruparParcelamentos(transacoes: PernaDeParcelamento[]): {
  compras: CompraParcelada[];
  pernaDe: Map<string, string>;
} {
  const porChave = new Map<string, { tx: PernaDeParcelamento; numero: number; total: number }[]>();

  for (const tx of transacoes) {
    const parcela = lerParcela(tx.installment_label);
    if (!parcela) continue;
    const chave = chaveDaCompra(tx, parcela.total);
    const lista = porChave.get(chave) ?? [];
    lista.push({ tx, numero: parcela.numero, total: parcela.total });
    porChave.set(chave, lista);
  }

  const compras: CompraParcelada[] = [];
  const pernaDe = new Map<string, string>();

  for (const [chave, itens] of porChave) {
    // Duas cobranças com o MESMO número de parcela são coisas distintas que colidiram na
    // chave (mesma loja, mesmo valor, mesmo plano, compras diferentes). Sem como separá-las
    // com honestidade, ficam de fora e seguem uma a uma — errar juntando é pior.
    const numeros = new Set(itens.map((i) => i.numero));
    if (numeros.size !== itens.length) continue;

    itens.sort((a, b) => a.numero - b.numero);
    const total = itens[0].total;
    const valorDaParcela = itens[0].tx.amount;
    const menor = itens[0].numero;
    const maior = itens[itens.length - 1].numero;

    const compra: CompraParcelada = {
      chave,
      rotulo: (itens[0].tx.counterparty_name || itens[0].tx.description || "").trim(),
      valorDaParcela,
      totalDeParcelas: total,
      valorDaCompra: Number((valorDaParcela * total).toFixed(2)),
      pernas: itens.map((i) => i.tx),
      ancora: itens[0].tx,
      menorParcelaVista: menor,
      maiorParcelaVista: maior,
      jaPago: Number((valorDaParcela * maior).toFixed(2)),
      aVencer: Number((valorDaParcela * (total - maior)).toFixed(2)),
      anterioresForaDoExtrato: menor - 1,
    };
    compras.push(compra);
    for (const i of itens) pernaDe.set(i.tx.id, chave);
  }

  return { compras, pernaDe };
}

/** Frase que explica a compra para quem decide — e para quem for auditar depois. */
export function descreverParcelamento(c: CompraParcelada): string {
  const partes = [
    `Compra parcelada em ${c.totalDeParcelas}x de ${brl(c.valorDaParcela)}`,
    `total ${brl(c.valorDaCompra)}`,
  ];
  if (c.pernas.length < c.totalDeParcelas) {
    partes.push(`${c.pernas.length} parcela(s) no extrato importado`);
  }
  if (c.anterioresForaDoExtrato > 0) {
    partes.push(
      `${c.anterioresForaDoExtrato} parcela(s) anteriores ao período importado — já pagas, fora deste extrato`,
    );
  }
  if (c.aVencer > 0) {
    partes.push(`${brl(c.aVencer)} ainda a vencer`);
  }
  return partes.join(" · ");
}

function brl(v: number): string {
  return `R$ ${v.toFixed(2).replace(".", ",")}`;
}
