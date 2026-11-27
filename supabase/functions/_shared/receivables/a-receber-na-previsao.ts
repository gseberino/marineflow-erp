// O que a previsão de caixa conta como ENTRADA de cada conta a receber em aberto (cobrança, fatia 6 — 27/11/2026).
//
// POR QUE ISTO EXISTE: a previsão da tela (useCashForecast) parte do saldo que os bancos informam HOJE e somava o saldo
// de toda conta a receber em aberto, com todo o vencido na primeira semana. Medido em 24/11/2026: R$ 45,9 mil vencidos
// entravam como "entrada desta semana", e duas coisas ali não iam entrar:
//   · dinheiro que JÁ entrou no banco e espera baixa no Extrato (7 das 12 vencidas, R$ 22,8 mil): ele já está no saldo
//     de hoje; contá-lo de novo como entrada dobrava o dinheiro;
//   · conta vencida há mais de 90 dias (3 contas, todas com 125 dias): sem data para entrar, não é entrada "desta semana".
//
// A REGRA (pura; a leitura do Extrato é a MESMA da trava da cobrança, lerDinheiroEsperando):
//   1. a entrada que aponta uma conta (o vínculo sugerido) cobre primeiro essa conta, até o saldo dela; o que sobra
//      vai para o cliente;
//   2. a entrada só com o cliente (e a sobra) cobre as contas dele da mais antiga para a mais nova;
//   3. a parte coberta sai das entradas e aparece à parte ("já no banco, esperando baixa");
//   4. do que resta, a conta vencida há mais de DIAS_SEM_DATA dias sai das entradas e aparece à parte ("vencido há mais
//      de 90 dias").
// A entrada que aponta uma conta fora da lista (vence depois da janela da previsão) não cobre outra conta: é dela.
// O lado de errar é o de menos entrada: o vínculo pode ter nascido só de valor e data, e aí a previsão fica mais curta,
// nunca mais folgada. Isto não dá baixa nem liga nada — a baixa continua sendo do dono, no Extrato.

import type { EntradaEsperando } from "./dinheiro-esperando.ts";

/** Conta vencida há mais do que isto (em dias) sai das entradas da previsão. */
export const DIAS_SEM_DATA = 90;

export interface ContaParaAPrevisao {
  id: string;
  client_id: string | null;
  /** 'AAAA-MM-DD' */
  due_date: string;
  /** o saldo em aberto */
  saldo: number;
}

export interface ContaNaPrevisao extends ContaParaAPrevisao {
  /** a parte do saldo que já entrou no banco (entrada esperando baixa no Extrato) */
  noBanco: number;
  /** venceu há mais de DIAS_SEM_DATA dias */
  antiga: boolean;
  /** o que a previsão conta como entrada desta conta (0 = nada) */
  aReceber: number;
}

export interface Parte { total: number; contas: number }

export interface AReceberNaPrevisao {
  contas: ContaNaPrevisao[];
  /** a soma do que já está no banco esperando baixa (fora das entradas) */
  noBanco: Parte;
  /** a soma do vencido há mais de DIAS_SEM_DATA dias, fora o que já está no banco (fora das entradas) */
  antigas: Parte;
}

const centavos = (v: number) => Math.round((Number(v) || 0) * 100);

function somarDiasIso(dia: string, n: number): string {
  const d = new Date(`${dia}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

export function aReceberNaPrevisao(contas: ContaParaAPrevisao[], esperando: EntradaEsperando[], hoje: string): AReceberNaPrevisao {
  const saldo = new Map(contas.map((c) => [c.id, Math.max(0, centavos(c.saldo))]));
  const coberto = new Map<string, number>(contas.map((c) => [c.id, 0]));
  const porId = new Map(contas.map((c) => [c.id, c]));
  const doCliente = new Map<string, number>();

  // 1. a entrada que aponta uma conta cobre essa conta primeiro
  for (const e of esperando) {
    let valor = Math.max(0, centavos(e.valor));
    if (e.contaId) {
      const conta = porId.get(e.contaId);
      if (!conta) continue; // conta fora da lista: a entrada é dela, não cobre outra
      const falta = saldo.get(conta.id)! - coberto.get(conta.id)!;
      const usa = Math.min(falta, valor);
      coberto.set(conta.id, coberto.get(conta.id)! + usa);
      valor -= usa;
    }
    if (valor > 0) doCliente.set(e.clienteId, (doCliente.get(e.clienteId) ?? 0) + valor);
  }

  // 2. o dinheiro do cliente cobre as contas dele, da mais antiga para a mais nova
  const ordenadas = [...contas].sort((a, b) => a.due_date.localeCompare(b.due_date) || a.id.localeCompare(b.id));
  for (const c of ordenadas) {
    if (!c.client_id) continue;
    let resta = doCliente.get(c.client_id) ?? 0;
    if (resta <= 0) continue;
    const falta = saldo.get(c.id)! - coberto.get(c.id)!;
    const usa = Math.min(falta, resta);
    coberto.set(c.id, coberto.get(c.id)! + usa);
    resta -= usa;
    doCliente.set(c.client_id, resta);
  }

  // 3 e 4. o coberto e o antigo saem das entradas
  const limiteAntiga = somarDiasIso(hoje, -DIAS_SEM_DATA);
  const noBanco: Parte = { total: 0, contas: 0 };
  const antigas: Parte = { total: 0, contas: 0 };
  const saida: ContaNaPrevisao[] = contas.map((c) => {
    const s = saldo.get(c.id)!;
    const nb = coberto.get(c.id)!;
    const antiga = c.due_date < limiteAntiga;
    const resto = s - nb;
    if (nb > 0) { noBanco.total += nb; noBanco.contas += 1; }
    if (antiga && resto > 0) { antigas.total += resto; antigas.contas += 1; }
    return { ...c, noBanco: nb / 100, antiga, aReceber: antiga ? 0 : resto / 100 };
  });
  noBanco.total /= 100;
  antigas.total /= 100;
  return { contas: saida, noBanco, antigas };
}
