// A fatura do cartão pelo extrato do próprio cartão — a regra, pura e sem rede.
//
// Morava em src/lib/previsao-de-caixa.ts (27/09/2026, três revisões contra o dado real). Veio para cá em 24/11/2026 sem
// mudar uma linha da conta, para a fila de pagamentos da semana (WhatsApp e assistente) usar a MESMA regra que a tela de
// previsão de caixa: dois cálculos da mesma fatura acabariam mostrando dois números ao dono. A tela reexporta daqui.
//
// O que a regra faz e por quê está no cabeçalho de src/lib/previsao-de-caixa.ts. Em resumo: o ciclo de cada cartão sai
// do histórico (o banco não informa fechamento nem vencimento), então as DATAS SÃO APROXIMADAS — quem mostra diz "por
// volta de"; o valor é o que o cartão cobrou no ciclo menos os créditos que não são pagamento, menos o que foi pago na
// janela da fatura.
//
// Sem imports: roda igual no navegador (Vite) e no servidor (Deno).

/** 'AAAA-MM-DD' mais (ou menos) n dias, sem fuso no caminho. */
export function somarDias(data: string, n: number): string {
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
  /** PENDING | POSTED, como o banco informa (só a conta pelo banco usa: ver `semParcelaRepetida`). */
  tx_status?: string | null;
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
export const mesDe = (data: string) => data.slice(0, 7);
export const diasNoMes = (ano: number, mes: number) => new Date(Date.UTC(ano, mes, 0)).getUTCDate();
const valorDe = (v: number | string) => Math.abs(Number(v)) || 0;

function mediana(valores: number[]): number | null {
  if (valores.length === 0) return null;
  const o = [...valores].sort((a, b) => a - b);
  const m = Math.floor(o.length / 2);
  return o.length % 2 ? o[m] : Math.round((o[m - 1] + o[m]) / 2);
}

/** A data do dia `d` no mês de `ano`/`mes` (1-12), sem passar do último dia do mês. */
export function noDia(ano: number, mes: number, d: number): string {
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

// ── O pagamento que já saiu da conta e o cartão ainda não mostrou ────────────────────────────────
//
// Medido em 24/11/2026 (200 dias de extrato): o pagamento da fatura aparece no cartão no MESMO dia em que sai da conta
// em 75 de 77 casos; os outros 2, na véspera. Só o pagamento de ontem ou de hoje é que falta do lado do cartão — e é
// justamente o que faz a fatura parecer "vencida, sem pagamento" na manhã seguinte ao pagamento (em 24/11: R$ 590,41
// "vencidos" no C6 com R$ 1.100,00 pagos em 23/11). Quem lê os dois lados entrega aqui os pagamentos feitos pela conta,
// e os que o cartão ainda não mostrou entram como pagamento do cartão. Quando o cartão mostrar, o par é reconhecido e
// nada conta em dobro.

/** Um débito na CONTA que é pagamento de fatura deste cartão. */
export interface PagamentoPelaConta {
  transaction_date: string;
  amount: number | string;
}

/** Pagamento pela conta mais velho que isto e ainda sem par no cartão não é atraso: é outra coisa (fica de fora). */
export const DIAS_EM_TRANSITO = 4;

export const PAGAMENTO_EM_TRANSITO = 'Pagamento de fatura (saiu da conta; o cartão ainda não mostra)';

/**
 * As linhas do cartão MAIS os pagamentos que já saíram da conta e o cartão ainda não mostrou. Um pagamento pela conta
 * tem par quando o cartão mostra um pagamento do mesmo valor entre a véspera e 3 dias depois. Sem pagamento em trânsito,
 * devolve a mesma lista.
 */
export function comPagamentosEmTransito(
  linhas: LinhaDoCartao[],
  pelaConta: PagamentoPelaConta[],
  hoje: string,
): LinhaDoCartao[] {
  const desde = somarDias(hoje, -DIAS_EM_TRANSITO);
  const recentes = pelaConta
    .map((p) => ({ data: String(p.transaction_date).slice(0, 10), valor: valorDe(p.amount) }))
    .filter((p) => p.valor > 0 && p.data > desde && p.data <= hoje)
    .sort((a, b) => (a.data < b.data ? -1 : a.data > b.data ? 1 : 0));
  if (recentes.length === 0) return linhas;

  // O cartão registra o mesmo pagamento duas vezes ("Inclusão de Pagamento" e "Pagamento recebido"): um por dia e valor.
  const noCartao = new Map<string, boolean>();
  for (const l of linhas) {
    if (!pagamentoValido(l)) continue;
    noCartao.set(`${String(l.transaction_date).slice(0, 10)}|${valorDe(l.amount).toFixed(2)}`, false);
  }
  const emTransito: LinhaDoCartao[] = [];
  for (const p of recentes) {
    let par: string | null = null;
    // primeiro o mesmo dia: a véspera de um pagamento pode ser o dia de outro igual
    for (const d of [0, -1, 1, 2, 3]) {
      if (par) break;
      const chave = `${somarDias(p.data, d)}|${p.valor.toFixed(2)}`;
      if (noCartao.get(chave) === false) par = chave;
    }
    if (par) noCartao.set(par, true);
    else {
      emTransito.push({
        transaction_date: p.data, amount: p.valor, transaction_type: 'credit', description: PAGAMENTO_EM_TRANSITO,
        bill_id: null, dismissed_kind: null, import_batch_id: null,
      });
    }
  }
  return emTransito.length ? [...linhas, ...emTransito] : linhas;
}

/** O que soma dos pagamentos em trânsito (para dizer ao dono que já foi considerado). */
export function somaEmTransito(linhas: LinhaDoCartao[]): number {
  return Math.round(linhas.filter((l) => l.description === PAGAMENTO_EM_TRANSITO).reduce((s, l) => s + valorDe(l.amount) * 100, 0)) / 100;
}

// ── De qual cartão é um pagamento feito pela conta ────────────────────────────────────────────────

/** Um débito da conta corrente que pode ser pagamento de fatura. */
export interface DebitoDaConta {
  bank_connection_id: string | null;
  transaction_date: string;
  amount: number | string;
  description?: string | null;
  counterparty_name?: string | null;
}

/** Um cartão conhecido: a conexão do banco e o rótulo dela. */
export interface CartaoConhecido {
  conexao: string;
  rotulo: string;
}

/**
 * Quem emite o cartão, pelo que o banco escreve. O pagamento da fatura do Nubank sai também de outra conta, como Pix
 * para "NU PAGAMENTOS" (medido: 3 dos 17 pagamentos); o do C6 sai sempre como "PGTO FAT CARTAO C6".
 */
const EMISSORES: Array<{ noPagamento: RegExp; noRotulo: RegExp }> = [
  { noPagamento: /\bc6\b/i, noRotulo: /\bc6\b/i },
  { noPagamento: /\bnu\s+pagamentos\b|\bnubank\b/i, noRotulo: /\bnubank\b|\bnu\b/i },
];

/** "PGTO FAT CARTAO", "PGTO FATURA CARTAO", "Fatura de cartão", "Pagamento de fatura". "DEBITO DE CARTAO" é compra. */
const TEXTO_DE_PAGAMENTO_DE_FATURA = /pgto\s+fat\w*\s+cart|fatura\s+de\s+cart|pagamento\s+de\s+fatura|pagamento\s+fatura/i;

const semAcento = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '');

/**
 * A conexão do cartão que este débito da conta pagou, ou null se não é pagamento de fatura (ou não dá para saber de
 * qual). Com o emissor escrito no débito, vale o cartão desse emissor, de qualquer conta que o dinheiro tenha saído;
 * sem emissor escrito ("Pagamento de fatura" na conta do Nubank), vale o cartão da MESMA conexão.
 */
export function cartaoDoPagamento(debito: DebitoDaConta, cartoes: CartaoConhecido[]): string | null {
  const descricao = semAcento(String(debito.description ?? ''));
  const contraparte = semAcento(String(debito.counterparty_name ?? ''));
  const pixParaOEmissor = EMISSORES.find((e) => e.noPagamento.test(contraparte) && /\bpix\b/i.test(descricao));
  const ehPagamento = TEXTO_DE_PAGAMENTO_DE_FATURA.test(descricao);
  if (!ehPagamento && !pixParaOEmissor) return null;

  const emissor = EMISSORES.find((e) => e.noPagamento.test(descricao)) ?? pixParaOEmissor ?? null;
  if (emissor) {
    const doEmissor = cartoes.filter((c) => emissor.noRotulo.test(semAcento(c.rotulo)));
    return doEmissor.length === 1 ? doEmissor[0].conexao : null;
  }
  return cartoes.some((c) => c.conexao === debito.bank_connection_id) ? debito.bank_connection_id : null;
}

// ── A fatura pelo calendário do BANCO ────────────────────────────────────────────────────────────
//
// Desde 24/11/2026 a sincronização guarda as faturas que o banco emitiu (cartao_faturas_do_banco: fechamento,
// vencimento e total). Medido nesse dia, contra 31 faturas dos dois cartões:
//   · o banco só publica a fatura 7 a 14 dias depois de fechar — no dia do vencimento. O TOTAL chega tarde demais para
//     avisar; o CALENDÁRIO (em que dia fecha e em que dia vence) é estável e é do banco;
//   · o ciclo deduzido do histórico (`inferirCiclo`) errava o C6 em um mês: "fecha 22, vence 21" contra fecha 17–19 e
//     vence 25 em 15 de 15 faturas;
//   · o dono quita a fatura logo depois de fechar e segue pagando pedaços durante o mês para liberar limite. A regra das
//     janelas (`faturasDoCartao`) dá esses pedaços à fatura anterior e superestima a seguinte.
// A conta daqui é a do saldo: a última fatura que o banco informou, mais o que o cartão cobrou, menos o que foi pago
// desde então. O que tem data NO dia do fechamento já é da fatura seguinte (medido: no Nubank 19 de 19 compras desse dia
// caíram na fatura seguinte, e no C6 25 de 25; os pagamentos do dia pagam a fatura que fechou).
// Erro medido contra o total do banco, de fatura em fatura: no Nubank mediana zero e máximo de R$ 191 em 12 faturas; no
// C6 uns R$ 90 nas 4 últimas e até R$ 1.000 nas antigas — o extrato do C6 costuma vir incompleto e a conta sai para
// baixo. Por isso o VALOR é sempre "cerca de". O VENCIMENTO é o do calendário do banco; o fechamento da fatura que o
// banco ainda não publicou é projetado (o C6 fecha entre 17 e 19) e quem mostra diz "por volta de".

/** Uma fatura como o banco informou. */
export interface FaturaInformada {
  fechamento: string;
  vencimento: string;
  total: number | string;
}

export interface FaturaPeloBanco {
  conta: string;
  /** o que falta pagar desta fatura */
  valor: number;
  /** quanto a fatura soma (a fechada: no fechamento; a aberta: até agora) */
  total: number;
  /** o que já foi pago dela (a fechada: desde o fechamento; a aberta: adiantado) */
  pago: number;
  vencimento: string;
  fechamento: string;
  situacao: 'fechada' | 'aberta';
  /** o vencimento passou e o extrato não mostra pagamento que cubra */
  vencida: boolean;
  /** 'banco' = o total é o que o banco informou; 'extrato' = estimado (o banco ainda não publicou esta fatura) */
  origem: 'banco' | 'extrato';
}

export interface CartaoPeloBanco {
  faturas: FaturaPeloBanco[];
  /** os dias do mês em que este cartão fecha e vence, pelas últimas faturas do banco. null = o banco não informou nenhuma */
  calendario: { diaDeFechamento: number; diaDeVencimento: number } | null;
  /** a última fatura que o banco informou (de onde a conta parte) */
  ancora: { fechamento: string; vencimento: string; total: number } | null;
  /** quantas faturas já fecharam depois dela sem o banco publicar. Acima de 2 não se estima nada (faturas vem vazio) */
  fechamentosSemOBanco: number;
}

/** O banco publica a fatura até uns 14 dias depois de fechar: com mais de duas fechadas sem publicar, a âncora envelheceu. */
const MAXIMO_SEM_O_BANCO = 2;
/**
 * Vencimento em sábado, domingo ou feriado vai para o dia útil seguinte (medido: o Nubank de 10/10/2026 venceu em 13/10).
 * Só se diz "vencida" depois desta folga.
 */
export const DIAS_DE_FOLGA_NO_VENCIMENTO = 3;
/** A fatura fechada continua na lista (como paga, se for o caso) até estes dias depois de vencer. */
const DIAS_MOSTRANDO_A_FECHADA = 5;

const ehData = (s: unknown): s is string => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s);

/** "Coremma 2/4": a parcela, que o banco lança com a data futura em que cai. */
const PARCELA = /\b\d{1,2}\/\d{1,2}\s*$/;

/**
 * Tira a parcela PENDENTE que já tem a mesma parcela LANÇADA (mesma descrição, mesmo valor): o banco lança a parcela e a
 * cópia pendente fica para trás, com outro código (medido em 24/11/2026: 4 no Nubank, R$ 345,74). Só parcela: compra
 * comum de mesmo nome e valor é outra compra (o mesmo posto, R$ 17,00, um mês depois).
 */
export function semParcelaRepetida(linhas: LinhaDoCartao[]): LinhaDoCartao[] {
  const chave = (l: LinhaDoCartao) => `${l.transaction_type}|${String(l.description ?? '').trim()}|${valorDe(l.amount).toFixed(2)}`;
  const ehParcela = (l: LinhaDoCartao) => l.transaction_type === 'debit' && PARCELA.test(String(l.description ?? ''));
  const lancadas = new Map<string, number>();
  for (const l of linhas) {
    if (l.tx_status === 'POSTED' && ehParcela(l)) lancadas.set(chave(l), (lancadas.get(chave(l)) ?? 0) + 1);
  }
  if (lancadas.size === 0) return linhas;
  return linhas.filter((l) => {
    if (l.tx_status !== 'PENDING' || !ehParcela(l)) return true;
    const n = lancadas.get(chave(l)) ?? 0;
    if (n === 0) return true;
    lancadas.set(chave(l), n - 1);
    return false;
  });
}

/**
 * As faturas de UM cartão pelo calendário do banco: a que fechou (o que falta dela) e a aberta (o que soma até agora).
 * `extrato` é o extrato do cartão (já com os pagamentos em trânsito, se houver); `informadas`, as faturas do banco.
 * O ciclo vai do dia do fechamento anterior (inclusive) ao dia do fechamento (exclusive): compra, estorno e pagamento com
 * a data do fechamento já são do ciclo seguinte — o pagamento desse dia paga a fatura que fechou.
 */
export function faturasPeloBanco(conta: string, extrato: LinhaDoCartao[], informadas: FaturaInformada[], hoje: string): CartaoPeloBanco {
  const linhas = semParcelaRepetida(extrato);
  const validas = informadas
    // total que o banco não mandou não vira zero: Number(null) é 0
    .map((f) => ({ fechamento: f.fechamento, vencimento: f.vencimento, total: f.total === null || f.total === undefined || f.total === '' ? NaN : Number(f.total) }))
    .filter((f) => ehData(f.fechamento) && ehData(f.vencimento) && Number.isFinite(f.total) && f.total >= 0 && f.fechamento <= hoje)
    .sort((a, b) => (a.fechamento < b.fechamento ? -1 : a.fechamento > b.fechamento ? 1 : 0));
  if (validas.length === 0) return { faturas: [], calendario: null, ancora: null, fechamentosSemOBanco: 0 };

  const ultimas = validas.slice(-4);
  const diaDeFechamento = mediana(ultimas.map((f) => dia(f.fechamento))) as number;
  // O banco só ADIA o vencimento (fim de semana, feriado). Com número par de faturas, a mediana de baixo: dizer o
  // vencimento um dia depois do real é o erro que custa multa.
  const diasDeVencimento = ultimas.map((f) => dia(f.vencimento)).sort((a, b) => a - b);
  const diaDeVencimento = diasDeVencimento[Math.floor((diasDeVencimento.length - 1) / 2)];
  const calendario = { diaDeFechamento, diaDeVencimento };
  const ancora = validas[validas.length - 1];

  // Os fechamentos depois da âncora: os que já passaram (o banco ainda não publicou) e o próximo.
  const [anoDaAncora, mesDaAncora] = ancora.fechamento.split('-').map(Number);
  const passados: string[] = [];
  let proximo = '';
  for (let k = 1; k <= 12 && !proximo; k++) {
    const f = noDia(anoDaAncora, mesDaAncora + k, diaDeFechamento);
    // No dia do fechamento a fatura já fechou: o que tem a data de hoje é da seguinte.
    if (f <= hoje) passados.push(f);
    else proximo = f;
  }
  if (!proximo || passados.length > MAXIMO_SEM_O_BANCO) {
    return { faturas: [], calendario, ancora, fechamentosSemOBanco: passados.length };
  }

  const centavos = (v: number) => Math.round(v * 100) / 100;
  const dataDe = (l: LinhaDoCartao) => String(l.transaction_date).slice(0, 10);
  const somaDe = (ls: LinhaDoCartao[]) => centavos(ls.reduce((s, l) => s + valorDe(l.amount), 0));
  // O cartão às vezes registra o mesmo pagamento duas vezes (mesmo dia e valor): conta uma vez.
  const vistos = new Set<string>();
  const pagamentos = linhas.filter(pagamentoValido).filter((l) => {
    const chave = `${dataDe(l)}|${valorDe(l.amount).toFixed(2)}`;
    if (vistos.has(chave)) return false;
    vistos.add(chave);
    return true;
  });
  const cobrado = (de: string, ate: string) => centavos(
    somaDe(linhas.filter((l) => compraValida(l) && dataDe(l) >= de && dataDe(l) < ate))
    - somaDe(linhas.filter((l) => creditoQueAbate(l) && dataDe(l) >= de && dataDe(l) < ate)),
  );
  const pagoEntre = (de: string, ate: string) => somaDe(pagamentos.filter((l) => dataDe(l) >= de && dataDe(l) < ate));

  // O saldo anda de fechamento em fechamento: o que se devia, mais o cobrado, menos o pago no ciclo.
  const limites = [ancora.fechamento, ...passados];
  let saldo = ancora.total;
  for (let i = 1; i < limites.length; i++) {
    saldo = centavos(saldo + cobrado(limites[i - 1], limites[i]) - pagoEntre(limites[i - 1], limites[i]));
  }
  const fechouEm = limites[limites.length - 1];
  const publicada = passados.length === 0;
  const vencimentoDe = (fechamento: string) => {
    const [a, m] = fechamento.split('-').map(Number);
    const noMesmoMes = noDia(a, m, diaDeVencimento);
    return noMesmoMes > fechamento ? noMesmoMes : noDia(a, m + 1, diaDeVencimento);
  };
  const vencimentoDaFechada = publicada ? ancora.vencimento : vencimentoDe(fechouEm);

  // Saldo negativo no fechamento é crédito (pagou adiantado mais do que gastou): a fechada não deve nada e ele abate a aberta.
  const devido = Math.max(0, saldo);
  const pagoDepois = pagoEntre(fechouEm, somarDias(hoje, 1));
  const falta = centavos(Math.max(0, devido - pagoDepois));
  const adiantado = centavos(Math.max(0, pagoDepois - devido) + Math.max(0, -saldo));
  // Até o próximo fechamento (exclusive), não só até hoje: a parcela já vem com a data futura em que cai.
  const cobradoNaAberta = Math.max(0, cobrado(fechouEm, proximo));
  const faltaDaAberta = centavos(Math.max(0, cobradoNaAberta - adiantado));

  const faturas: FaturaPeloBanco[] = [];
  // A fechada fica na lista enquanto faltar pagar e, paga, até uns dias depois do vencimento (o dono vê que está coberta).
  if (falta >= 1 || hoje <= somarDias(vencimentoDaFechada, DIAS_MOSTRANDO_A_FECHADA)) {
    faturas.push({
      conta, valor: falta >= 1 ? falta : 0, total: devido, pago: pagoDepois, vencimento: vencimentoDaFechada, fechamento: fechouEm,
      situacao: 'fechada', vencida: falta >= 1 && somarDias(vencimentoDaFechada, DIAS_DE_FOLGA_NO_VENCIMENTO) < hoje,
      origem: publicada ? 'banco' : 'extrato',
    });
  }
  if (faltaDaAberta >= 1) {
    faturas.push({
      conta, valor: faltaDaAberta, total: cobradoNaAberta, pago: Math.min(adiantado, cobradoNaAberta), vencimento: vencimentoDe(proximo),
      fechamento: proximo, situacao: 'aberta', vencida: false, origem: 'extrato',
    });
  }
  return { faturas, calendario, ancora, fechamentosSemOBanco: passados.length };
}
