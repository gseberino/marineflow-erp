// Previsão de caixa das próximas semanas: o que ela soma além das contas lançadas (27/09/2026).
//
// A "Programação" somava só contas a receber e a pagar em aberto. Quase todo gasto da HBR é
// lançado DEPOIS que sai (pelo Extrato), então a maior saída previsível — a fatura do cartão —
// e os gastos que se repetem todo mês ficavam de fora, e a previsão dizia que sobrava dinheiro.
// Aqui ficam as regras, puras e testadas; a leitura do banco mora em useCashForecast.
//
// Fatura do cartão — pelo que o próprio cartão mostra, sem inventar compra futura:
//   · o ciclo de cada cartão sai do histórico: o dia em que as faturas antigas começam (o
//     fechamento é a véspera) e o dia do maior pagamento de cada mês (o vencimento);
//   · a fatura FECHADA ainda não quitada vence no dia de pagamento; a do ciclo ABERTO leva as
//     compras feitas até hoje (e as parcelas já lançadas até o fechamento) para o vencimento
//     seguinte;
//   · o dono paga em pedaços e às vezes atrasado. Cada fatura tem a sua janela de pagamento:
//     depois do vencimento da anterior e até o dela (os dois com 5 dias de tolerância). O que
//     cai na janela paga primeiro o que ainda falta da fatura ANTERIOR (pagamento atrasado) e
//     depois a dela; o que vem depois da janela da fechada paga primeiro o que falta dela e só
//     então é adiantamento da aberta. Três faturas entram na conta: a anterior, a fechada e a
//     aberta (revisão de 27/09/2026: o Nubank pagou a de maio 10 e 22 dias depois do vencimento,
//     e a regra só com a fechada via a de junho como paga e a de maio como vencida);
//   · pago na fechada MAIS do que as compras que o extrato do cartão mostra nela não abate a
//     aberta: no dado real (C6, setembro/2026) a fatura foi paga em R$ 1.860,81 e o extrato só
//     trouxe R$ 362,55 de compras — faltam compras no extrato, não houve adiantamento. Levar a
//     "sobra" para a aberta zerava a fatura seguinte e a previsão voltava a dizer que sobrava
//     dinheiro. Vira aviso de extrato incompleto (a partir de R$ 50 — abaixo disso é centavo,
//     IOF ou juro);
//   · o valor de cada fatura é o que o cartão cobrou MENOS o que ele creditou sem ser pagamento:
//     estorno de compra ("Crédito de MERCADOLIVRE…"), juro anulado ("Encerramento de dívida"
//     contra "Juros de dívida encerrada") e a rolagem de dívida ("Saldo em atraso" contra
//     "Crédito de atraso", no mesmo dia). Contar só os débitos criava dívida fantasma: em 15/08
//     e em 27/09/2026 o Nubank aparecia devendo a fatura de agosto, que teve R$ 2.030,05 de
//     débitos e R$ 122,05 de juro anulado e foi paga no centavo (R$ 1.908,00 em 11/08) — terceira
//     revisão de 27/09/2026, conferida contra o saldo corrido do extrato do cartão;
//   · o cartão às vezes registra o mesmo pagamento duas vezes ("Inclusão de Pagamento" e
//     "Pagamento recebido", mesmo dia e valor, contra um só débito na conta): conta uma vez.
// Gastos que se repetem — categoria que apareceu em pelo menos 3 dos 4 últimos meses completos,
// com valor estável (variação até 35%), fora do cartão (esse já vai na fatura) e fora do que não
// é despesa (fatura, transferência). Entram pela média, espalhados pelos dias, descontado o que
// já está lançado como conta a pagar daquela categoria no mês — e, no mês corrente, o que já foi
// pago: o saldo de partida já não tem esse dinheiro.

// A regra da fatura do cartão mora em supabase/functions/_shared/banking/fatura-do-cartao.ts (24/11/2026): a fila de
// pagamentos da semana, no servidor, usa a mesma. Aqui só se reexporta, e a conta não mudou.
import { diasNoMes, mesDe, noDia, somarDias } from '../../supabase/functions/_shared/banking/fatura-do-cartao';

export {
  comPagamentosEmTransito, cartaoDoPagamento, faturasDoCartao, faturasPeloBanco, fechamentosEmVolta, inferirCiclo, somaEmTransito,
  vencimentoDaFatura,
} from '../../supabase/functions/_shared/banking/fatura-do-cartao';
export type {
  CartaoConhecido, CartaoPeloBanco, CicloDoCartao, DebitoDaConta, FaturaInformada, FaturaPeloBanco, FaturaPrevista, FaturasDoCartao,
  LinhaDoCartao, PagamentoPelaConta,
} from '../../supabase/functions/_shared/banking/fatura-do-cartao';

// ── Gastos que se repetem ────────────────────────────────────────────────────────────────

/** Uma despesa lançada (conta a pagar não cancelada). */
export interface DespesaLancada {
  categoria: string | null;
  valor: number;
  /** 'AAAA-MM-DD' — emissão. */
  data: string;
  /** Grupo do DRE da categoria. */
  grupo: string | null;
  /** Paga no cartão de crédito: já vai na fatura. */
  noCartao: boolean;
}

export interface GastoQueSeRepete {
  categoria: string;
  mediaMensal: number;
  /** Em quantos dos 4 meses apareceu. */
  meses: number;
}

/** Os 4 meses completos antes do mês de `hoje`, do mais antigo ao mais novo ('AAAA-MM'). */
export function mesesDeReferencia(hoje: string): string[] {
  const [a, m] = hoje.split('-').map(Number);
  const saida: string[] = [];
  for (let i = 4; i >= 1; i--) {
    const d = new Date(Date.UTC(a, m - 1 - i, 1));
    saida.push(`${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`);
  }
  return saida;
}

const VARIACAO_MAXIMA = 0.35;
const MEDIA_MINIMA = 50;

/**
 * O que sai para o sócio é UM gasto na previsão. Desde 28/09/2026 o Pix ao sócio se divide entre
 * "Pró-labore" (o salário mínimo do mês) e "Retirada de sócio" (o resto, não operacional). Sem
 * juntar, a retirada sairia da previsão por ser não operacional e o caixa pareceria mais folgado;
 * juntos, o mês soma o mesmo que o pró-labore somava antes da divisão.
 */
export const GASTO_DO_SOCIO = 'Pró-labore e retirada de sócio';

export function categoriaNaPrevisao(categoria: string | null): string | null {
  return categoria === 'Pró-labore' || categoria === 'Retirada de sócio' ? GASTO_DO_SOCIO : categoria;
}

export function gastosQueSeRepetem(despesas: DespesaLancada[], hoje: string): GastoQueSeRepete[] {
  const meses = mesesDeReferencia(hoje);
  const porCategoria = new Map<string, Map<string, number>>();
  for (const d of despesas) {
    const categoria = categoriaNaPrevisao(d.categoria);
    if (!categoria || d.noCartao || (d.grupo === 'nao_operacional' && categoria !== GASTO_DO_SOCIO)) continue;
    const mes = mesDe(d.data);
    if (!meses.includes(mes)) continue;
    const doMes = porCategoria.get(categoria) ?? new Map<string, number>();
    doMes.set(mes, (doMes.get(mes) ?? 0) + Math.round(d.valor * 100));
    porCategoria.set(categoria, doMes);
  }
  const saida: GastoQueSeRepete[] = [];
  for (const [categoria, doMes] of porCategoria) {
    const totais = [...doMes.values()].filter((v) => v > 0).map((v) => v / 100);
    if (totais.length < 3) continue;
    const media = totais.reduce((s, v) => s + v, 0) / totais.length;
    const desvio = Math.sqrt(totais.reduce((s, v) => s + (v - media) ** 2, 0) / totais.length);
    if (media < MEDIA_MINIMA || desvio / media > VARIACAO_MAXIMA) continue;
    saida.push({ categoria, mediaMensal: Math.round(media * 100) / 100, meses: totais.length });
  }
  return saida.sort((a, b) => b.mediaMensal - a.mediaMensal);
}

/** Uma conta a pagar em aberto, para descontar do gasto que se repete. */
export interface ContaEmAberto {
  categoria: string | null;
  valor: number;
  /** 'AAAA-MM-DD' */
  vencimento: string;
}

/**
 * Quanto dos gastos que se repetem cai em cada dia de hoje até `ate`, já descontado o que está
 * lançado como conta a pagar da mesma categoria no mês. No mês de hoje, nunca mais do que falta
 * do mês: a média menos o que já foi pago nele (`pagoNoMes`, por categoria) — a contabilidade
 * paga no dia 2 já saiu do saldo de partida e não entra de novo. Sem nada pago, fica a parte dos
 * dias que faltam, como antes. Devolve o valor por dia ('AAAA-MM-DD').
 */
export function gastosQueSeRepetemPorDia(
  gastos: GastoQueSeRepete[], contas: ContaEmAberto[], hoje: string, ate: string,
  pagoNoMes: Map<string, number> = new Map(),
): Map<string, number> {
  const porDia = new Map<string, number>();
  if (ate < hoje) return porDia;
  for (const g of gastos) {
    // Mês a mês dentro da janela.
    let cursor = hoje;
    while (cursor <= ate) {
      const [a, m] = cursor.split('-').map(Number);
      const fimDoMes = noDia(a, m, 31);
      const fim = fimDoMes < ate ? fimDoMes : ate;
      const diasNaJanela = Number(((Date.parse(fim) - Date.parse(cursor)) / 86_400_000).toFixed(0)) + 1;
      const pelosDias = g.mediaMensal * (diasNaJanela / diasNoMes(a, m));
      const esperado = mesDe(cursor) === mesDe(hoje)
        ? Math.min(pelosDias, Math.max(0, g.mediaMensal - (pagoNoMes.get(g.categoria) ?? 0)))
        : pelosDias;
      const lancado = contas
        .filter((c) => categoriaNaPrevisao(c.categoria) === g.categoria && mesDe(c.vencimento) === mesDe(cursor))
        .reduce((s, c) => s + c.valor, 0);
      const falta = Math.max(0, esperado - lancado);
      if (falta > 0) {
        const porDiaNoMes = falta / diasNaJanela;
        for (let d = cursor; d <= fim; d = somarDias(d, 1)) porDia.set(d, (porDia.get(d) ?? 0) + porDiaNoMes);
      }
      cursor = somarDias(fim, 1);
    }
  }
  return porDia;
}
