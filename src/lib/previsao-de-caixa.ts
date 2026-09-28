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

/** 'AAAA-MM-DD' mais (ou menos) n dias, sem fuso no caminho. */
function somarDias(data: string, n: number): string {
  const d = new Date(`${data.slice(0, 10)}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** Uma linha do cartão de crédito: compra (debit) ou pagamento/estorno (credit). */
export interface LinhaDoCartao {
  transaction_date: string;
  amount: number | string;
  transaction_type: string;
  description?: string | null;
  bill_id?: string | null;
  dismissed_kind?: string | null;
  import_batch_id?: string | null;
}

export interface CicloDoCartao {
  /** Dia do mês em que a fatura fecha (a véspera do início do ciclo). 1 a 31. */
  diaDeFechamento: number;
  /** Dia do mês em que a fatura costuma ser paga. 1 a 31. */
  diaDePagamento: number;
}

export interface FaturaPrevista {
  conta: string;
  valor: number;
  /** 'AAAA-MM-DD' */
  vencimento: string;
  /** 'AAAA-MM-DD' — fechamento da fatura (a fechada) ou o próximo (a aberta). */
  fechamento: string;
  /** Fechada (já tem valor final) ou aberta (compras até hoje). */
  situacao: 'fechada' | 'aberta';
  /** Venceu e o pagamento não cobriu: pode estar em aberto. */
  vencida: boolean;
  /** Lançamentos cobrados no ciclo (compras, parcelas, tarifas e juros). */
  compras: number;
  /** O que já foi pago desta fatura (a tela diz "pago em parte" em vez de "não aparece pagamento"). */
  pago: number;
}

/** As faturas de um cartão e o que o extrato dele não explica. */
export interface FaturasDoCartao {
  faturas: FaturaPrevista[];
  /**
   * Pago na fatura fechada além das compras que o extrato do cartão mostra nela. Quase sempre é
   * compra que o extrato não trouxe (não adiantamento): a aberta não é abatida e pode estar baixa.
   */
  pagoAlemDoExtrato: number;
  /** A fechada: quando fechou, as compras que o extrato mostra e o que foi pago. */
  fechada: { fechamento: string; compras: number; pago: number };
  /** O ciclo deduzido — null quando o banco não identifica a fatura de nenhuma compra recente. */
  ciclo: CicloDoCartao | null;
}

/** O lote da importação manual de julho (repetido pela sincronização) — fora de tudo. */
const LOTE_DE_JULHO = '14a6a33c-3a21-412c-97c0-0843cf373d08';
const PAGAMENTO_DE_FATURA = /pagamento|fatura/i;
/** Pagamento feito até estes dias depois do vencimento anterior ainda é daquela fatura. */
const DIAS_DE_ATRASO_DA_ANTERIOR = 5;

const dia = (data: string) => Number(data.slice(8, 10));
const mesDe = (data: string) => data.slice(0, 7);
const diasNoMes = (ano: number, mes: number) => new Date(Date.UTC(ano, mes, 0)).getUTCDate();
const valorDe = (v: number | string) => Math.abs(Number(v)) || 0;

function mediana(valores: number[]): number | null {
  if (valores.length === 0) return null;
  const o = [...valores].sort((a, b) => a - b);
  const m = Math.floor(o.length / 2);
  return o.length % 2 ? o[m] : Math.round((o[m - 1] + o[m]) / 2);
}

/** A data do dia `d` no mês de `ano`/`mes` (1-12), sem passar do último dia do mês. */
function noDia(ano: number, mes: number, d: number): string {
  const a = mes < 1 ? ano - 1 : mes > 12 ? ano + 1 : ano;
  const m = mes < 1 ? mes + 12 : mes > 12 ? mes - 12 : mes;
  const dd = Math.min(d, diasNoMes(a, m));
  return `${a}-${String(m).padStart(2, '0')}-${String(dd).padStart(2, '0')}`;
}

/** Abaixo disto, pago a mais é centavo, IOF ou juro — não é sinal de extrato incompleto. */
const AVISO_MINIMO = 50;

const compraValida = (l: LinhaDoCartao) => l.transaction_type === 'debit'
  && !['duplicata', 'estornada'].includes(l.dismissed_kind ?? '')
  && l.import_batch_id !== LOTE_DE_JULHO;

/**
 * Crédito no cartão que NÃO é pagamento: estorno, juro anulado, a outra metade da rolagem de
 * dívida. Abate a fatura em que cai (ver o cabeçalho).
 */
const creditoQueAbate = (l: LinhaDoCartao) => l.transaction_type === 'credit'
  && !PAGAMENTO_DE_FATURA.test(String(l.description ?? ''))
  && !['duplicata', 'estornada'].includes(l.dismissed_kind ?? '')
  && l.import_batch_id !== LOTE_DE_JULHO;

const pagamentoValido = (l: LinhaDoCartao) => l.transaction_type === 'credit'
  && PAGAMENTO_DE_FATURA.test(String(l.description ?? ''))
  && !['duplicata', 'estornada'].includes(l.dismissed_kind ?? '')
  && l.import_batch_id !== LOTE_DE_JULHO;

/**
 * O ciclo de UM cartão, pelo histórico: as faturas que o banco identificou (bill_id) dizem em
 * que dia o ciclo começa; os pagamentos dizem em que dia a fatura é paga. Sem nenhuma fatura
 * identificada, não dá para saber quando fecha — devolve null e a previsão diz que ficou de fora.
 */
export function inferirCiclo(linhas: LinhaDoCartao[]): CicloDoCartao | null {
  const inicioDaFatura = new Map<string, { inicio: string; compras: number }>();
  for (const l of linhas) {
    if (!l.bill_id || !compraValida(l)) continue;
    const atual = inicioDaFatura.get(l.bill_id);
    const data = String(l.transaction_date).slice(0, 10);
    if (!atual) inicioDaFatura.set(l.bill_id, { inicio: data, compras: 1 });
    else {
      atual.compras += 1;
      if (data < atual.inicio) atual.inicio = data;
    }
  }
  // As 4 faturas mais recentes com pelo menos 3 compras (uma fatura de 1 compra começa no dia
  // dela, não no do ciclo).
  const faturas = [...inicioDaFatura.values()].filter((f) => f.compras >= 3)
    .sort((a, b) => (a.inicio < b.inicio ? 1 : -1)).slice(0, 4);
  const diaDeInicio = mediana(faturas.map((f) => dia(f.inicio)));
  if (diaDeInicio == null) return null;
  const diaDeFechamento = diaDeInicio === 1 ? 31 : diaDeInicio - 1;

  // O maior pagamento de cada um dos 4 meses mais recentes com pagamento.
  const maiorDoMes = new Map<string, { valor: number; dia: number }>();
  for (const l of linhas) {
    if (!pagamentoValido(l)) continue;
    const data = String(l.transaction_date).slice(0, 10);
    const v = valorDe(l.amount);
    const atual = maiorDoMes.get(mesDe(data));
    if (!atual || v > atual.valor) maiorDoMes.set(mesDe(data), { valor: v, dia: dia(data) });
  }
  const recentes = [...maiorDoMes.entries()].sort((a, b) => (a[0] < b[0] ? 1 : -1)).slice(0, 4).map(([, p]) => p.dia);
  const diaDePagamento = mediana(recentes) ?? Math.min(diaDeFechamento + 8, 28);
  return { diaDeFechamento, diaDePagamento };
}

/** Fechamento de um mês (ano, mês 1-12) no dia do ciclo. */
const fechamentoDoMes = (ano: number, mes: number, c: CicloDoCartao) => noDia(ano, mes, c.diaDeFechamento);

/** O vencimento da fatura que fecha em `fechamento`: o primeiro dia de pagamento depois dele. */
export function vencimentoDaFatura(fechamento: string, c: CicloDoCartao): string {
  const [a, m] = fechamento.split('-').map(Number);
  const noMesmoMes = noDia(a, m, c.diaDePagamento);
  return noMesmoMes > fechamento ? noMesmoMes : noDia(a, m + 1, c.diaDePagamento);
}

/** Os fechamentos em volta de hoje: o último que já passou, o anterior a ele e o próximo. */
export function fechamentosEmVolta(hoje: string, c: CicloDoCartao): { anterior: string; ultimo: string; proximo: string } {
  const [a, m] = hoje.split('-').map(Number);
  const desteMes = fechamentoDoMes(a, m, c);
  // No dia do fechamento a fatura ainda está aberta até o fim do dia.
  if (hoje > desteMes) {
    return { anterior: fechamentoDoMes(a, m - 1, c), ultimo: desteMes, proximo: fechamentoDoMes(a, m + 1, c) };
  }
  return { anterior: fechamentoDoMes(a, m - 2, c), ultimo: fechamentoDoMes(a, m - 1, c), proximo: desteMes };
}

/**
 * As faturas de UM cartão que ainda vão sair do caixa: o que falta da anterior e da fechada (o
 * pagamento não cobriu) e a aberta, com as compras feitas até hoje.
 */
export function faturasDoCartao(conta: string, linhas: LinhaDoCartao[], hoje: string): FaturasDoCartao {
  const ciclo = inferirCiclo(linhas);
  if (!ciclo) return { faturas: [], pagoAlemDoExtrato: 0, fechada: { fechamento: '', compras: 0, pago: 0 }, ciclo: null };
  const { anterior, ultimo, proximo } = fechamentosEmVolta(hoje, ciclo);
  const [anoDaAnterior, mesDaAnterior] = anterior.split('-').map(Number);
  const anteAnterior = fechamentoDoMes(anoDaAnterior, mesDaAnterior - 1, ciclo);
  const vencimentoDaAnteAnterior = vencimentoDaFatura(anteAnterior, ciclo);
  const vencimentoDaAnterior = vencimentoDaFatura(anterior, ciclo);
  const vencimentoDaFechada = vencimentoDaFatura(ultimo, ciclo);
  const vencimentoDaAberta = vencimentoDaFatura(proximo, ciclo);

  const entre = (l: LinhaDoCartao, de: string, ate: string) => {
    const d = String(l.transaction_date).slice(0, 10);
    return d > de && d <= ate;
  };
  const somaEm = (ls: LinhaDoCartao[]) => Math.round(ls.reduce((s, l) => s + valorDe(l.amount) * 100, 0)) / 100;
  /** O mesmo pagamento registrado duas vezes pelo cartão (mesmo dia e valor) conta uma vez. */
  const semRepetir = (ls: LinhaDoCartao[]) => {
    const vistos = new Set<string>();
    return ls.filter((l) => {
      const chave = `${String(l.transaction_date).slice(0, 10)}|${valorDe(l.amount).toFixed(2)}`;
      if (vistos.has(chave)) return false;
      vistos.add(chave);
      return true;
    });
  };

  const centavos = (v: number) => Math.round(v * 100) / 100;
  /** O que o cartão cobrou num ciclo: débitos menos os créditos que não são pagamento. */
  const doCiclo = (de: string, ate: string) => {
    const debitos = linhas.filter((l) => compraValida(l) && entre(l, de, ate));
    const creditos = linhas.filter((l) => creditoQueAbate(l) && entre(l, de, ate));
    return { lancamentos: debitos.length, valor: Math.max(0, centavos(somaEm(debitos) - somaEm(creditos))) };
  };
  const cicloDaAnterior = doCiclo(anteAnterior, anterior);
  const cicloDaFechada = doCiclo(anterior, ultimo);
  // Até o fechamento, não só até hoje: a parcela de uma compra antiga já vem com a data futura
  // em que cai (Coremma 3/4 em outubro) e é cobrança certa desta fatura.
  const cicloDaAberta = doCiclo(ultimo, proximo);

  // A janela de pagamento de cada fatura: do vencimento da fatura de antes (+5 dias) ao dela (+5).
  const fimDaJanela = (vencimento: string) => somarDias(vencimento, DIAS_DE_ATRASO_DA_ANTERIOR);
  const pagamentos = semRepetir(linhas.filter((l) => pagamentoValido(l) && entre(l, fimDaJanela(vencimentoDaAnteAnterior), hoje)));
  const pagoEntre = (de: string, ate: string) => somaEm(pagamentos.filter((l) => entre(l, de, ate)));
  const naJanelaDaAnterior = pagoEntre(fimDaJanela(vencimentoDaAnteAnterior), fimDaJanela(vencimentoDaAnterior));
  const naJanelaDaFechada = pagoEntre(fimDaJanela(vencimentoDaAnterior), fimDaJanela(vencimentoDaFechada));
  const depoisDaFechada = pagoEntre(fimDaJanela(vencimentoDaFechada), hoje);

  // O que cai na janela da fechada paga primeiro o que ainda faltava da anterior (atraso).
  const faltavaDaAnterior = Math.max(0, centavos(cicloDaAnterior.valor - naJanelaDaAnterior));
  const atrasoDaAnterior = Math.min(naJanelaDaFechada, faltavaDaAnterior);
  const paraAFechada = centavos(naJanelaDaFechada - atrasoDaAnterior);
  const totalFechada = cicloDaFechada.valor;
  const faltavaDaFechada = Math.max(0, centavos(totalFechada - paraAFechada));
  // O que foi pago a mais na fechada NÃO abate a aberta (ver o cabeçalho): vira aviso.
  const pagoAlemDoExtrato = Math.max(0, centavos(paraAFechada - totalFechada));
  // O que vem depois da janela da fechada paga primeiro o que ainda falta (anterior, depois a
  // fechada); só o resto é adiantamento da aberta.
  const cobreAnterior = Math.min(depoisDaFechada, centavos(faltavaDaAnterior - atrasoDaAnterior));
  const cobreFechada = Math.min(centavos(depoisDaFechada - cobreAnterior), faltavaDaFechada);
  const adiantado = centavos(depoisDaFechada - cobreAnterior - cobreFechada);
  const faltaDaAnterior = centavos(faltavaDaAnterior - atrasoDaAnterior - cobreAnterior);
  const faltaDaFechada = centavos(faltavaDaFechada - cobreFechada);
  const faltaDaAberta = Math.max(0, centavos(cicloDaAberta.valor - adiantado));
  const pagoDaFechada = centavos(paraAFechada + cobreFechada);

  const faturas: FaturaPrevista[] = [];
  // Menos de R$ 1 é arredondamento do cartão, não conta a pagar.
  if (faltaDaAnterior >= 1) {
    faturas.push({
      conta, valor: faltaDaAnterior, vencimento: vencimentoDaAnterior, fechamento: anterior,
      situacao: 'fechada', vencida: vencimentoDaAnterior < hoje, compras: cicloDaAnterior.lancamentos,
      pago: centavos(naJanelaDaAnterior + atrasoDaAnterior + cobreAnterior),
    });
  }
  if (faltaDaFechada >= 1) {
    faturas.push({
      conta, valor: faltaDaFechada, vencimento: vencimentoDaFechada, fechamento: ultimo,
      situacao: 'fechada', vencida: vencimentoDaFechada < hoje, compras: cicloDaFechada.lancamentos, pago: pagoDaFechada,
    });
  }
  if (faltaDaAberta >= 1) {
    faturas.push({
      conta, valor: faltaDaAberta, vencimento: vencimentoDaAberta, fechamento: proximo,
      situacao: 'aberta', vencida: false, compras: cicloDaAberta.lancamentos, pago: adiantado,
    });
  }
  return {
    faturas,
    pagoAlemDoExtrato: pagoAlemDoExtrato >= AVISO_MINIMO ? pagoAlemDoExtrato : 0,
    fechada: { fechamento: ultimo, compras: totalFechada, pago: pagoDaFechada },
    ciclo,
  };
}

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
