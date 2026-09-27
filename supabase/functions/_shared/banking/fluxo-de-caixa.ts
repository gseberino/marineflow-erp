// Fluxo de caixa pelo EXTRATO — o dinheiro que de fato entrou e saiu das contas.
//
// Até 26/09/2026 o gráfico "Fluxo de caixa" e os números "Recebido/Pago este mês" liam a
// tabela `payments`: só os 52 pagamentos registrados à mão no sistema inteiro. O resultado
// era um fluxo quase vazio, com quase nada saindo. O extrato (`bank_transactions`) tem cada
// Pix, boleto e débito — é ele que diz quanto dinheiro passou pelas contas.
//
// Este módulo é a regra ÚNICA: a tela (src/lib/fluxo-de-caixa.ts reexporta daqui), o painel
// inicial e o assistente ("fechamento do período") contam do mesmo jeito — três números
// diferentes para "quanto entrou no mês" era o que o dono não aceita (revisão de 27/09/2026).
//
// Regras (aprovadas pelo dono, afinadas no extrato real em 27/09/2026):
//   · `amount` é SEMPRE positivo; o sentido está em `transaction_type` (credit = entrou,
//     debit = saiu).
//   · Só conta o que guarda dinheiro: `source_type` bank (conta corrente) e cash (Caixa em
//     dinheiro). Compra no cartão de crédito NÃO é saída de caixa: o dinheiro sai quando a
//     fatura é paga, e esse pagamento é uma linha de débito da conta corrente, que conta.
//   · Fica fora: duplicata, estornada, as linhas da importação manual de 27/07 (o lote inteiro
//     foi repetido pela sincronização automática), linha pendente, linha com data no futuro e
//     o ajuste pela contagem do Caixa ("Contei o dinheiro": a primeira contagem põe o saldo
//     inteiro do Caixa numa linha só — contá-la como "Entrou" inventaria uma receita).
//   · Fica À PARTE, sem somar em Entrou/Saiu: a transferência entre contas suas e o crédito que
//     o cartão põe na conta corrente ("Pix no crédito" do Nubank: é dívida, não receita).
//
// Transferência entre contas suas — a linha diz, não a marca:
//   1. Pix, TED, TEF ou DOC cuja outra ponta tem o CNPJ da própria empresa (as contas da HBR em
//      bancos que não estão ligados ao sistema também — a outra perna nem aparece aqui);
//   2. aplicação e resgate de investimento (CDB, RDB, LCI, LCA), nos dois sentidos: é o dinheiro
//      da empresa mudando de lugar. No extrato real, as aplicações não tinham marca e os
//      resgates tinham — contar só um lado distorcia R$ 37 mil;
//   3. a linha MARCADA "transferência" sem nenhuma dessas provas só vale se tiver o par dentro
//      do mesmo mês (mesmo valor, sentido oposto, outra conta, até 2 dias) — é o caso do Caixa
//      e de extrato sem dados da outra ponta.
// A marca sozinha não basta: "Vendas" (o dinheiro das vendas no cartão que a InfinitePay põe na
// conta), a fatura do Nubank paga pelo C6, o Pix do sócio, o estorno de uma loja e uma cobrança
// por boleto estavam marcados como transferência. Parear sem olhar a outra ponta errava para o
// outro lado: R$ 80 mil de resgates e de transferências de contas da HBR fora do sistema viravam
// "Entrou" (medido no extrato real em 27/09/2026).
//
// O par nunca atravessa a virada do mês: cada mês é pareado com as suas linhas. É o que faz o
// mesmo mês dar o mesmo número em qualquer tela — leia ela um mês ou o ano — e impede que a
// mesma perna sirva de par em dois meses (2ª revisão de 27/09/2026).

export interface LinhaDoFluxo {
  /** Necessário para parear as duas pernas de uma transferência. */
  id?: string;
  transaction_date: string;
  amount: number | string;
  transaction_type: string;
  source_type?: string | null;
  provider?: string | null;
  bank_connection_id?: string | null;
  dismissed_kind?: string | null;
  /** O "+ Lançar" grava o mesmo motivo nas duas pontas do saque ou depósito do Caixa. */
  dismissed_reason?: string | null;
  tx_status?: string | null;
  import_batch_id?: string | null;
  description?: string | null;
  counterparty_document?: string | null;
  payment_method?: string | null;
}

/** O que a regra precisa saber além das linhas. */
export interface OpcoesDoFluxo {
  /** Os 8 primeiros dígitos do CNPJ da própria empresa (company_fiscal_settings). */
  raizDaEmpresa?: string | null;
}

/** O lote da importação manual de 27/07/2026 (28/04 a 26/07): todo ele repetido pela sincronização. */
export const LOTE_DA_IMPORTACAO_MANUAL_DE_JULHO = '14a6a33c-3a21-412c-97c0-0843cf373d08';

/** Distância máxima, em dias, entre as duas pernas de uma transferência pareada. */
export const DIAS_ENTRE_AS_PERNAS = 2;

/** Para onde vai cada linha do extrato. */
export type DestinoDaLinha =
  /** Entra em Entrou/Saiu. */
  | 'movimento'
  /** À parte: transferência entre contas suas (a marcada sem prova ainda passa pelo par). */
  | 'transferencia'
  /** À parte: dinheiro que o cartão de crédito pôs na conta corrente (é dívida). */
  | 'credito_do_cartao'
  /** Fora: compra no cartão de crédito — conta quando a fatura é paga. */
  | 'fora_cartao'
  | 'fora_duplicata'
  | 'fora_estornada'
  | 'fora_importacao_manual'
  | 'fora_ajuste_caixa'
  | 'fora_pendente'
  | 'fora_futuro'
  /** Fora: sentido ou valor que não dá para ler. */
  | 'fora_ilegivel';

export type DestinoDeFora = Extract<DestinoDaLinha, `fora_${string}`>;

/** O nome de cada balde em português simples, para a tela. */
export const ROTULO_DO_DESTINO: Record<DestinoDaLinha, string> = {
  movimento: 'entrou ou saiu',
  transferencia: 'transferência entre contas suas (inclui aplicação e resgate)',
  credito_do_cartao: 'crédito do cartão na conta (Pix no crédito)',
  fora_cartao: 'compra no cartão de crédito (conta quando a fatura é paga)',
  fora_duplicata: 'linha repetida da importação',
  fora_estornada: 'lançamento estornado',
  fora_importacao_manual: 'importação manual de julho (repetida pela sincronização)',
  fora_ajuste_caixa: 'ajuste pela contagem do Caixa (acerta o saldo, não é dinheiro que entrou ou saiu)',
  fora_pendente: 'ainda pendente no banco',
  fora_futuro: 'data no futuro',
  fora_ilegivel: 'linha sem sentido ou valor legível',
};

/** Contas que guardam dinheiro: conta corrente e Caixa em dinheiro. */
const ORIGENS_DE_CAIXA = new Set(['bank', 'cash']);

/** Meios de pagamento de uma transferência entre contas. Boleto e "OTHER" (estorno, cartão) não. */
const MEIOS_DE_TRANSFERENCIA = new Set(['PIX', 'TED', 'TEF', 'DOC']);

/** Aplicação e resgate de investimento, pelo texto do banco ("CDB C6 LIM. GARANT.", "Resgate RDB"). */
const INVESTIMENTO = /\b(CDB|RDB|LCI|LCA)\b/i;

/**
 * "Valor adicionado na conta por cartão de crédito | Valor adicionado para PIX no Crédito" (Nubank):
 * dívida do cartão entrando na conta. No extrato real, 8 linhas assim estavam marcadas como crédito
 * do cartão e 1 como transferência — e essa casava por acaso com uma compra de R$ 80 no mesmo dia.
 */
const CREDITO_DO_CARTAO_NA_CONTA = /valor adicionado.*(cart[aã]o de cr[eé]dito|pix no cr[eé]dito)/i;

/** O motivo que o "+ Lançar" (mover_caixa) grava nas duas pontas quando liga a linha do banco. */
const MOTIVOS_DO_CAIXA_LIGADO = new Set(['saque do banco para o caixa', 'depósito do caixa no banco', 'deposito do caixa no banco']);

const dataDa = (l: LinhaDoFluxo) => String(l.transaction_date).slice(0, 10);
const origemDa = (l: LinhaDoFluxo) => l.source_type ?? 'bank';

/** "Vendas": o dinheiro das vendas no cartão que a maquininha (InfinitePay) põe na conta. É receita. */
function ehVendaDaMaquininha(l: LinhaDoFluxo): boolean {
  return l.transaction_type === 'credit' && String(l.description ?? '').trim().toLowerCase() === 'vendas';
}

/**
 * A própria linha prova que é transferência entre contas suas — não precisa de par: aplicação ou
 * resgate de investimento, ou Pix/TED/TEF/DOC cuja outra ponta tem o CNPJ da empresa.
 */
export function transferenciaProvada(l: LinhaDoFluxo, opcoes: OpcoesDoFluxo = {}): boolean {
  if (origemDa(l) !== 'bank' || ehVendaDaMaquininha(l)) return false;
  if (INVESTIMENTO.test(String(l.description ?? ''))) return true;
  const raiz = String(opcoes.raizDaEmpresa ?? '').replace(/\D/g, '');
  if (raiz.length !== 8) return false;
  const documento = String(l.counterparty_document ?? '').replace(/\D/g, '');
  return documento.length === 14 && documento.startsWith(raiz)
    && MEIOS_DE_TRANSFERENCIA.has(String(l.payment_method ?? '').toUpperCase());
}

/**
 * Decide o destino de UMA linha, sozinha. A ordem importa: o que fica fora ganha de tudo (uma
 * transferência duplicada é duplicata, não transferência). A linha MARCADA "transferência" sem
 * prova (transferenciaProvada) ainda passa pelo pareamento antes de ficar à parte.
 */
export function destinoDaLinha(l: LinhaDoFluxo, hoje: string, opcoes: OpcoesDoFluxo = {}): DestinoDaLinha {
  // Sem origem gravada vale como conta corrente — a mesma leitura das funções de saldo.
  if (!ORIGENS_DE_CAIXA.has(origemDa(l))) return 'fora_cartao';
  const tipo = l.dismissed_kind ?? '';
  if (tipo === 'duplicata') return 'fora_duplicata';
  if (tipo === 'estornada') return 'fora_estornada';
  if (tipo === 'ajuste_caixa') return 'fora_ajuste_caixa';
  if (l.import_batch_id === LOTE_DA_IMPORTACAO_MANUAL_DE_JULHO) return 'fora_importacao_manual';
  if ((l.tx_status ?? '') === 'PENDING') return 'fora_pendente';
  // Comparação de texto 'AAAA-MM-DD': sem Date, sem fuso deslocando o dia.
  if (dataDa(l) > hoje) return 'fora_futuro';
  if (l.transaction_type !== 'credit' && l.transaction_type !== 'debit') return 'fora_ilegivel';
  if (!Number.isFinite(Number(l.amount))) return 'fora_ilegivel';
  if (tipo === 'mecanica_cartao') return 'credito_do_cartao';
  if (l.transaction_type === 'credit' && origemDa(l) === 'bank' && CREDITO_DO_CARTAO_NA_CONTA.test(String(l.description ?? ''))) {
    return 'credito_do_cartao';
  }
  if (ehVendaDaMaquininha(l)) return 'movimento';
  if (transferenciaProvada(l, opcoes) || tipo === 'transferencia') return 'transferencia';
  return 'movimento';
}

/** Soma em centavos: somar reais em ponto flutuante deixa R$ 0,01 de sobra no fim. */
function emCentavos(v: number | string): number {
  return Math.round(Math.abs(Number(v)) * 100);
}

const diasEntre = (a: string, b: string) => Math.abs(Date.parse(a) - Date.parse(b)) / 86_400_000;

/** Uma perna candidata a par. */
interface Perna {
  id: string;
  data: string;
  centavos: number;
  conta: string;
  marcada: boolean;
  caixa: boolean;
  debito: boolean;
  /** dismissed_reason normalizado — para achar as duas pontas ligadas pelo "+ Lançar". */
  motivo: string;
}

const antes = (a: Perna, b: Perna) => (a.data < b.data ? -1 : a.data > b.data ? 1 : a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

/**
 * Emparelhamento máximo por caminhos aumentantes entre débitos e créditos, que continua de uma
 * fase para a outra: `aumentar` casa quem está livre, podendo trocar o par de quem já casou, desde
 * que ninguém casado fique sem par — o total de pares é o maior possível com os candidatos da fase.
 * O que estiver em `congeladas` não é tocado.
 */
function emparelhamento(debitos: Perna[], creditos: Perna[]) {
  const ordenados = debitos.slice().sort(antes);
  const porValor = new Map<number, Perna[]>();
  for (const c of creditos) {
    const lista = porValor.get(c.centavos) ?? [];
    lista.push(c);
    porValor.set(c.centavos, lista);
  }
  const debitoDoCredito = new Map<string, Perna>();
  const creditoDoDebito = new Map<string, Perna>();

  return {
    aumentar(casam: (d: Perna, c: Perna) => boolean, congeladas: Set<string> = new Set()) {
      // Candidatos do melhor para o pior: menos dias de distância, depois o mais antigo e o id —
      // o resultado não depende da ordem em que as linhas chegaram.
      const candidatos = new Map<string, Perna[]>();
      const candidatosDe = (d: Perna): Perna[] => {
        let lista = candidatos.get(d.id);
        if (!lista) {
          lista = (porValor.get(d.centavos) ?? [])
            .filter((c) => !congeladas.has(c.id) && c.conta !== d.conta
              && diasEntre(d.data, c.data) <= DIAS_ENTRE_AS_PERNAS && casam(d, c))
            .sort((a, b) => diasEntre(d.data, a.data) - diasEntre(d.data, b.data) || antes(a, b));
          candidatos.set(d.id, lista);
        }
        return lista;
      };
      const tentar = (d: Perna, vistos: Set<string>): boolean => {
        for (const c of candidatosDe(d)) {
          if (vistos.has(c.id)) continue;
          vistos.add(c.id);
          const atual = debitoDoCredito.get(c.id);
          if (!atual || tentar(atual, vistos)) {
            debitoDoCredito.set(c.id, d);
            creditoDoDebito.set(d.id, c);
            return true;
          }
        }
        return false;
      };
      for (const d of ordenados) {
        if (!creditoDoDebito.has(d.id) && !congeladas.has(d.id)) tentar(d, new Set());
      }
    },
    casadas(): Set<string> {
      const ids = new Set<string>();
      for (const [d, c] of creditoDoDebito) { ids.add(d); ids.add(c.id); }
      return ids;
    },
  };
}

/**
 * Os pares de transferência entre as linhas MARCADAS "transferência" sem prova (e a linha do
 * banco que casa com a perna do Caixa). Chame com as linhas de UM mês: o par não atravessa a
 * virada do mês (use paresPorMes).
 *
 *   1ª fase: as duas pontas que o "+ Lançar" ligou (o mover_caixa grava o mesmo motivo — "Saque
 *   do banco para o Caixa" ou "Depósito do Caixa no banco" — e a mesma data nas duas). É prova:
 *   nenhuma fase seguinte mexe nelas (conferência final de 27/09/2026 — antes, uma fatura marcada
 *   podia roubar a linha do depósito e deixar o Caixa casando com um Pix do sócio).
 *   2ª fase: marcada com marcada entre contas do banco, o maior número de pares.
 *   3ª fase: a perna do CAIXA que sobrou com a linha MARCADA do banco que sobrou.
 *   4ª fase: a perna do CAIXA que ainda sobrou (lançada sem ligar a linha do banco) com uma linha
 *   comum do banco — senão o saque contava duas vezes (a saída no banco e o gasto em dinheiro).
 * Cada fase só casa o que as anteriores deixaram livre.
 *
 * Linha com prova (transferenciaProvada), "Vendas", crédito do cartão e o que fica fora não entram
 * aqui: não precisam de par, e não podem roubar o par de outra.
 */
export function paresDeTransferencia(linhas: LinhaDoFluxo[], hoje: string, opcoes: OpcoesDoFluxo = {}): Set<string> {
  const debitos: Perna[] = [];
  const creditos: Perna[] = [];
  for (const l of linhas) {
    if (!l.id) continue;
    const destino = destinoDaLinha(l, hoje, opcoes);
    if (destino !== 'movimento' && destino !== 'transferencia') continue;
    if (transferenciaProvada(l, opcoes) || ehVendaDaMaquininha(l)) continue;
    const perna: Perna = {
      id: l.id,
      data: dataDa(l),
      centavos: emCentavos(l.amount),
      conta: l.bank_connection_id ?? `origem:${origemDa(l)}`,
      marcada: destino === 'transferencia',
      caixa: origemDa(l) === 'cash',
      debito: l.transaction_type === 'debit',
      motivo: String(l.dismissed_reason ?? '').trim().toLowerCase(),
    };
    (l.transaction_type === 'debit' ? debitos : creditos).push(perna);
  }

  // 1ª fase: as duas pontas que o "+ Lançar" ligou — mesmo motivo, mesmo dia, mesmo valor (o
  // mover_caixa aceita até R$ 0,01 de diferença). É prova, não palpite: ficam como estão.
  const ligadas = new Set<string>();
  {
    const doBanco = [...debitos, ...creditos]
      .filter((p) => !p.caixa && p.marcada && MOTIVOS_DO_CAIXA_LIGADO.has(p.motivo)).sort(antes);
    const doCaixa = [...debitos, ...creditos]
      .filter((p) => p.caixa && p.marcada && MOTIVOS_DO_CAIXA_LIGADO.has(p.motivo)).sort(antes);
    // Candidatas de cada ponta do Caixa, a menor diferença de valor primeiro. Também aqui o maior
    // número de pares (caminhos aumentantes): dois saques ligados no mesmo dia com centavos
    // cruzados (500,01 e 500,02 no banco, 500,00 e 500,01 no Caixa) não podem deixar um solto.
    const candidatas = new Map(doCaixa.map((cx) => [cx.id, doBanco
      .filter((b) => b.debito !== cx.debito && b.motivo === cx.motivo && b.data === cx.data
        && Math.abs(b.centavos - cx.centavos) <= 1)
      .sort((a, b) => Math.abs(a.centavos - cx.centavos) - Math.abs(b.centavos - cx.centavos) || antes(a, b))]));
    const caixaDoBanco = new Map<string, Perna>();
    const tentar = (cx: Perna, vistos: Set<string>): boolean => {
      for (const b of candidatas.get(cx.id) ?? []) {
        if (vistos.has(b.id)) continue;
        vistos.add(b.id);
        const atual = caixaDoBanco.get(b.id);
        if (!atual || tentar(atual, vistos)) {
          caixaDoBanco.set(b.id, cx);
          return true;
        }
      }
      return false;
    };
    for (const cx of doCaixa) tentar(cx, new Set());
    for (const [banco, cx] of caixaDoBanco) { ligadas.add(banco); ligadas.add(cx.id); }
  }

  const pares = emparelhamento(debitos.filter((d) => !ligadas.has(d.id)), creditos.filter((c) => !ligadas.has(c.id)));
  // 2ª fase: marcada com marcada entre contas do banco — o maior número de pares.
  pares.aumentar((d, c) => d.marcada && c.marcada && !d.caixa && !c.caixa);
  // 3ª fase: a perna do Caixa que sobrou com a linha MARCADA do banco que sobrou.
  const caixaCom = (marcadaNoBanco: boolean) => (d: Perna, c: Perna) =>
    (d.marcada && d.caixa && !c.caixa && c.marcada === marcadaNoBanco)
    || (c.marcada && c.caixa && !d.caixa && d.marcada === marcadaNoBanco);
  pares.aumentar(caixaCom(true), pares.casadas());
  // 4ª fase: a perna do Caixa que ainda sobrou com uma linha comum do banco (o saque lançado sem
  // ligar a linha do banco). Uma linha comum nunca desmancha um par de marcadas.
  pares.aumentar(caixaCom(false), pares.casadas());

  const todas = pares.casadas();
  for (const id of ligadas) todas.add(id);
  return todas;
}

/** Os pares de cada mês, juntos: o par nunca atravessa a virada do mês. */
export function paresPorMes(linhas: LinhaDoFluxo[], hoje: string, opcoes: OpcoesDoFluxo = {}): Set<string> {
  const porMes = new Map<string, LinhaDoFluxo[]>();
  for (const l of linhas) {
    const mes = dataDa(l).slice(0, 7);
    const lista = porMes.get(mes) ?? [];
    lista.push(l);
    porMes.set(mes, lista);
  }
  const todas = new Set<string>();
  for (const doMes of porMes.values()) for (const id of paresDeTransferencia(doMes, hoje, opcoes)) todas.add(id);
  return todas;
}

export interface EntrouSaiu {
  entrou: number;
  saiu: number;
}

export interface SomaDoFluxo extends EntrouSaiu {
  /** Entrou − Saiu. */
  liquido: number;
  /** Linhas somadas em Entrou/Saiu. */
  quantidade: number;
  /** À parte: transferências entre contas suas (inclui aplicação e resgate). */
  transferencias: EntrouSaiu;
  /** À parte: crédito do cartão na conta corrente. */
  creditoDoCartao: EntrouSaiu;
}

export interface MesDoFluxo extends SomaDoFluxo {
  /** 'AAAA-MM' */
  mes: string;
}

export type ForaDoFluxo = Partial<Record<DestinoDeFora, { quantidade: number; valor: number }>>;

export interface FluxoDeCaixa {
  meses: MesDoFluxo[];
  total: SomaDoFluxo;
  /** O que não entrou em conta nenhuma, por motivo — para a tela poder dizer. */
  deFora: ForaDoFluxo;
}

type Acumulador = {
  entrou: number; saiu: number; quantidade: number;
  tEntrou: number; tSaiu: number; cEntrou: number; cSaiu: number;
};

const vazio = (): Acumulador => ({ entrou: 0, saiu: 0, quantidade: 0, tEntrou: 0, tSaiu: 0, cEntrou: 0, cSaiu: 0 });

function paraReais(a: Acumulador): SomaDoFluxo {
  return {
    entrou: a.entrou / 100,
    saiu: a.saiu / 100,
    liquido: (a.entrou - a.saiu) / 100,
    quantidade: a.quantidade,
    transferencias: { entrou: a.tEntrou / 100, saiu: a.tSaiu / 100 },
    creditoDoCartao: { entrou: a.cEntrou / 100, saiu: a.cSaiu / 100 },
  };
}

/** O que ficou fora, por motivo, em centavos (ponto flutuante deixaria R$ 0,01 de sobra). */
type ForaEmCentavos = Partial<Record<DestinoDeFora, { quantidade: number; centavos: number }>>;

const foraEmReais = (fora: ForaEmCentavos): ForaDoFluxo => Object.fromEntries(
  Object.entries(fora).map(([motivo, v]) => [motivo, { quantidade: v!.quantidade, valor: v!.centavos / 100 }]),
) as ForaDoFluxo;

/** Soma uma linha no acumulador do balde dela. */
function somarLinha(
  l: LinhaDoFluxo, soma: Acumulador, fora: ForaEmCentavos, pareadas: Set<string>, hoje: string, opcoes: OpcoesDoFluxo,
) {
  let destino = destinoDaLinha(l, hoje, opcoes);
  if (destino.startsWith('fora_')) {
    const motivo = destino as DestinoDeFora;
    const atual = fora[motivo] ?? { quantidade: 0, centavos: 0 };
    const c = Number.isFinite(Number(l.amount)) ? emCentavos(l.amount) : 0;
    fora[motivo] = { quantidade: atual.quantidade + 1, centavos: atual.centavos + c };
    return;
  }
  const pareada = !!l.id && pareadas.has(l.id);
  if (destino === 'transferencia' && !pareada && !transferenciaProvada(l, opcoes)) destino = 'movimento';
  else if (destino === 'movimento' && pareada) destino = 'transferencia';

  const c = emCentavos(l.amount);
  const entrada = l.transaction_type === 'credit';
  if (destino === 'transferencia') {
    if (entrada) soma.tEntrou += c; else soma.tSaiu += c;
  } else if (destino === 'credito_do_cartao') {
    if (entrada) soma.cEntrou += c; else soma.cSaiu += c;
  } else {
    if (entrada) soma.entrou += c; else soma.saiu += c;
    soma.quantidade += 1;
  }
}

/**
 * Monta o fluxo dos meses pedidos (em ordem), a partir das linhas cruas do extrato. As linhas
 * precisam cobrir os meses INTEIROS: o pareamento de cada mês usa todas as linhas dele.
 * Mês sem movimento aparece zerado — um buraco no gráfico diz "não houve nada", uma ausência
 * diria "não sei".
 */
export function montarFluxoDeCaixa(linhas: LinhaDoFluxo[], meses: string[], hoje: string, opcoes: OpcoesDoFluxo = {}): FluxoDeCaixa {
  const pareadas = paresPorMes(linhas, hoje, opcoes);
  const porMes = new Map<string, Acumulador>(meses.map((m) => [m, vazio()]));
  const fora: ForaEmCentavos = {};
  for (const l of linhas) {
    const acc = porMes.get(dataDa(l).slice(0, 7));
    if (acc) somarLinha(l, acc, fora, pareadas, hoje, opcoes);
  }
  const total = vazio();
  for (const acc of porMes.values()) {
    for (const k of Object.keys(total) as Array<keyof Acumulador>) total[k] += acc[k];
  }
  return {
    meses: meses.map((mes) => ({ mes, ...paraReais(porMes.get(mes)!) })),
    total: paraReais(total),
    deFora: foraEmReais(fora),
  };
}

/**
 * Entrou e saiu num período de dias ('AAAA-MM-DD' a 'AAAA-MM-DD', inclusive). As linhas precisam
 * cobrir os meses INTEIROS que o período toca — o mesmo pareamento das telas mês a mês.
 */
export function somarFluxoDoPeriodo(
  linhas: LinhaDoFluxo[], de: string, ate: string, hoje: string, opcoes: OpcoesDoFluxo = {},
): SomaDoFluxo & { deFora: ForaDoFluxo } {
  const pareadas = paresPorMes(linhas, hoje, opcoes);
  const soma = vazio();
  const fora: ForaEmCentavos = {};
  for (const l of linhas) {
    const d = dataDa(l);
    if (d < de || d > ate) continue;
    somarLinha(l, soma, fora, pareadas, hoje, opcoes);
  }
  return { ...paraReais(soma), deFora: foraEmReais(fora) };
}

// ── Datas ────────────────────────────────────────────────────────────────────────────

/** Hoje em Brasília, 'AAAA-MM-DD' — o extrato é gravado na data local do banco. */
export function hojeEmBrasilia(agora: Date = new Date()): string {
  // en-CA formata como AAAA-MM-DD.
  return agora.toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' });
}

/** 'AAAA-MM-DD' mais (ou menos) n dias, sem fuso no caminho. */
export function somarDias(data: string, n: number): string {
  const d = new Date(`${data.slice(0, 10)}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** Os `n` meses que terminam em `ate` ('AAAA-MM' ou 'AAAA-MM-DD'), do mais antigo ao mais novo. */
export function ultimosMeses(n: number, ate: string): string[] {
  const [a, m] = ate.slice(0, 7).split('-').map(Number);
  const saida: string[] = [];
  for (let i = n - 1; i >= 0; i--) {
    const d = new Date(Date.UTC(a, m - 1 - i, 1));
    saida.push(`${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`);
  }
  return saida;
}

/** Primeiro e último dia dos meses (em ordem), para a consulta. */
export function limitesDosMeses(meses: string[]): { de: string; ate: string } {
  const primeiro = meses[0];
  const ultimo = meses[meses.length - 1];
  const [a, m] = ultimo.split('-').map(Number);
  const dias = new Date(Date.UTC(a, m, 0)).getUTCDate();
  return { de: `${primeiro}-01`, ate: `${ultimo}-${String(dias).padStart(2, '0')}` };
}

/** Os meses inteiros que um período de dias toca: é o que a leitura precisa trazer. */
export function mesesInteirosDoPeriodo(de: string, ate: string): { de: string; ate: string } {
  return limitesDosMeses([de.slice(0, 7), ate.slice(0, 7)]);
}

const MESES_CURTOS = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
const MESES_LONGOS = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

/** 'AAAA-MM' → 'Set/26' (eixo do gráfico). */
export function rotuloDoMes(mes: string): string {
  const [a, m] = mes.split('-');
  return `${MESES_CURTOS[Number(m) - 1]}/${a.slice(2)}`;
}

/** 'AAAA-MM' → 'setembro de 2026'. */
export function nomeDoMes(mes: string): string {
  const [a, m] = mes.split('-');
  return `${MESES_LONGOS[Number(m) - 1]} de ${a}`;
}

/** As colunas que a regra lê — a mesma lista para a tela e para o assistente. */
export const COLUNAS_DO_FLUXO =
  'id, transaction_date, amount, transaction_type, source_type, provider, bank_connection_id, dismissed_kind, dismissed_reason, tx_status, import_batch_id, description, counterparty_document, payment_method';

/** A função do banco que devolve a raiz do CNPJ da empresa (a tabela fiscal é só do admin). */
export const FUNCAO_DA_RAIZ_DA_EMPRESA = 'raiz_do_cnpj_da_empresa';
