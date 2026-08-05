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

function quemRecebeu(tx: PernaDeParcelamento): string {
  return normalizeText(tx.counterparty_name || tx.description || "");
}

/**
 * Junta as pernas de cada compra parcelada.
 *
 * Devolve também `pernaDe`: para cada transação, a chave da compra a que ela pertence —
 * é o que permite ao motor propor a compra UMA vez e não propor as outras pernas.
 */
interface Perna { tx: PernaDeParcelamento; numero: number; total: number }

/**
 * Monta a compra a partir das pernas dela. Devolve null quando o conjunto não é coerente.
 *
 * O valor da compra é a SOMA das parcelas presentes mais a estimativa das ausentes, não
 * "parcela × total": quando o parcelamento inteiro está no extrato, isso dá o valor exato
 * mesmo com o centavo que o cartão joga numa parcela só.
 */
function montarCompra(chave: string, itens: Perna[]): CompraParcelada | null {
  const numeros = new Set(itens.map((i) => i.numero));
  if (numeros.size !== itens.length) return null;

  const ordenadas = [...itens].sort((a, b) => a.numero - b.numero);
  const total = ordenadas[0].total;
  const menor = ordenadas[0].numero;
  const maior = ordenadas[ordenadas.length - 1].numero;

  const somaPresentes = ordenadas.reduce((s, i) => s + i.tx.amount, 0);
  const media = somaPresentes / ordenadas.length;
  const anteriores = menor - 1;
  const futuras = total - maior;

  const jaPago = somaPresentes + anteriores * media;
  const aVencer = futuras * media;

  return {
    chave,
    rotulo: (ordenadas[0].tx.counterparty_name || ordenadas[0].tx.description || "").trim(),
    valorDaParcela: Number(media.toFixed(2)),
    totalDeParcelas: total,
    valorDaCompra: Number((jaPago + aVencer).toFixed(2)),
    pernas: ordenadas.map((i) => i.tx),
    ancora: ordenadas[0].tx,
    menorParcelaVista: menor,
    maiorParcelaVista: maior,
    jaPago: Number(jaPago.toFixed(2)),
    aVencer: Number(aVencer.toFixed(2)),
    anterioresForaDoExtrato: anteriores,
  };
}

export function agruparParcelamentos(transacoes: PernaDeParcelamento[]): {
  compras: CompraParcelada[];
  pernaDe: Map<string, string>;
} {
  // Chave: QUEM recebeu e em QUANTAS vezes. O valor da parcela ficou de fora de propósito.
  //
  // Exigir valor idêntico parecia seguro e era o defeito: o cartão distribui o centavo que
  // não divide, então uma compra de R$ 100,01 em 3x vira 33,34 + 33,34 + 33,33. Com o valor
  // na chave, essa compra virava DUAS — 98 grupos onde havia 64 compras de verdade, e o
  // gestor classificando a mesma compra duas vezes.
  const porChave = new Map<string, Perna[]>();
  for (const tx of transacoes) {
    const parcela = lerParcela(tx.installment_label);
    if (!parcela) continue;
    const chave = `${quemRecebeu(tx)}|${parcela.total}`;
    const lista = porChave.get(chave) ?? [];
    lista.push({ tx, numero: parcela.numero, total: parcela.total });
    porChave.set(chave, lista);
  }

  const compras: CompraParcelada[] = [];
  const pernaDe = new Map<string, string>();

  for (const [chave, itens] of porChave) {
    const compra = montarCompra(chave, itens);
    if (compra) {
      compras.push(compra);
      for (const i of itens) pernaDe.set(i.tx.id, chave);
      continue;
    }

    // Número de parcela repetido: são DUAS compras no mesmo lugar, no mesmo plano, que
    // caíram na mesma chave. Aí o valor volta a ser o critério — é o que resta para
    // separá-las. O que continuar ambíguo depois disso segue uma a uma: errar juntando
    // compras diferentes é pior que deixar duas linhas para o gestor.
    const porValor = new Map<string, Perna[]>();
    for (const i of itens) {
      const k = `${chave}|${i.tx.amount.toFixed(2)}`;
      porValor.set(k, [...(porValor.get(k) ?? []), i]);
    }
    for (const [k, lista] of porValor) {
      const c = montarCompra(k, lista);
      if (!c) continue;
      compras.push(c);
      for (const i of lista) pernaDe.set(i.tx.id, k);
    }
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
