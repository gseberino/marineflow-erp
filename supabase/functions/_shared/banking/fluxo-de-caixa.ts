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
// Regras (aprovadas pelo dono):
//   · `amount` é SEMPRE positivo; o sentido está em `transaction_type` (credit = entrou,
//     debit = saiu).
//   · Só conta o que guarda dinheiro: `source_type` bank (conta corrente) e cash (Caixa em
//     dinheiro). Compra no cartão de crédito NÃO é saída de caixa: o dinheiro sai quando a
//     fatura é paga, e esse pagamento é uma linha de débito da conta corrente, que conta.
//   · Fica fora: duplicata, estornada, as linhas da importação manual de 27/07 (o lote inteiro
//     foi repetido pela sincronização automática), linha pendente, linha com data no futuro e
//     o ajuste pela contagem do Caixa ("Contei o dinheiro": a primeira contagem põe o saldo
//     inteiro do Caixa numa linha só — contá-la como "Entrou" inventaria uma receita).
//     Extrato importado por arquivo DEPOIS daquele lote conta normalmente.
//   · Fica À PARTE, sem somar em Entrou/Saiu: transferência entre contas próprias — só a de
//     FATO, com as duas pernas (mesmo valor, sentido oposto, outra conta que guarda dinheiro,
//     até 2 dias) — e o crédito que o cartão põe na conta corrente ("Pix no crédito" do Nubank:
//     é dívida, não receita). A tela diz o valor desses baldes para ninguém achar que sumiram.
//     A marca "transferência" SEM a outra perna não basta: o pagamento da fatura do Nubank pela
//     conta do C6 e as "Vendas" que a maquininha liquida na InfinitePay estavam marcados assim,
//     e são dinheiro que saiu e que entrou de verdade (revisão de 27/09/2026).
//   · Cada recorte (um mês, um período) é pareado com as SUAS linhas mais 2 dias de cada lado,
//     e só com elas. Assim o mesmo mês dá o mesmo número em qualquer tela, leia ela um mês ou o
//     ano inteiro (2ª revisão de 27/09/2026: o painel e o Resumo do mês chegaram a divergir).

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
  tx_status?: string | null;
  import_batch_id?: string | null;
}

/** O lote da importação manual de 27/07/2026 (28/04 a 26/07): todo ele repetido pela sincronização. */
export const LOTE_DA_IMPORTACAO_MANUAL_DE_JULHO = '14a6a33c-3a21-412c-97c0-0843cf373d08';

/** Distância máxima, em dias, entre as duas pernas de uma transferência. */
export const DIAS_ENTRE_AS_PERNAS = 2;

/** Para onde vai cada linha do extrato. */
export type DestinoDaLinha =
  /** Entra em Entrou/Saiu. */
  | 'movimento'
  /** À parte: transferência entre contas próprias. */
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
  transferencia: 'transferência entre contas suas',
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

/**
 * Decide o destino de UMA linha, sozinha. A ordem importa: o que fica fora ganha de tudo (uma
 * transferência duplicada é duplicata, não transferência). A marca "transferência" daqui ainda
 * passa pelo pareamento (paresDeTransferencia) antes de ficar à parte.
 */
export function destinoDaLinha(l: LinhaDoFluxo, hoje: string): DestinoDaLinha {
  // Sem origem gravada vale como conta corrente — a mesma leitura das funções de saldo.
  const origem = l.source_type ?? 'bank';
  if (!ORIGENS_DE_CAIXA.has(origem)) return 'fora_cartao';
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
  if (tipo === 'transferencia') return 'transferencia';
  if (tipo === 'mecanica_cartao') return 'credito_do_cartao';
  return 'movimento';
}

const dataDa = (l: LinhaDoFluxo) => String(l.transaction_date).slice(0, 10);

/** Soma em centavos: somar reais em ponto flutuante deixa R$ 0,01 de sobra no fim. */
function emCentavos(v: number | string): number {
  return Math.round(Math.abs(Number(v)) * 100);
}

const diasEntre = (a: string, b: string) => Math.abs(Date.parse(a) - Date.parse(b)) / 86_400_000;

/** Uma perna candidata a transferência. */
interface Perna {
  id: string;
  data: string;
  centavos: number;
  conta: string;
  marcada: boolean;
  caixa: boolean;
}

const antes = (a: Perna, b: Perna) => (a.data < b.data ? -1 : a.data > b.data ? 1 : a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

/**
 * As transferências de FATO: o MAIOR número de pares débito × crédito com o mesmo valor, em
 * contas diferentes que guardam dinheiro, até 2 dias de diferença — cada linha em um par só.
 *
 *   1ª fase: só as pernas marcadas "transferência".
 *   2ª fase: a perna do CAIXA marcada (saque ou depósito lançado pelo "+ Lançar") pode casar com
 *   a linha do banco, marcada ou não — senão o saque contava duas vezes (a saída no banco e o
 *   gasto em dinheiro). O crédito do cartão na conta ("Pix no crédito") não é candidato: não é
 *   dinheiro do Caixa indo ou vindo.
 *
 * O maior número de pares, e não "o primeiro que aparecer": numa transferência do Nubank para o
 * C6 seguida de um saque do mesmo valor no C6, pegar o primeiro par deixava as duas pernas do C6
 * órfãs — e elas viravam Entrou e Saiu (2ª revisão de 27/09/2026). Entre escolhas igualmente
 * boas, vale a mais próxima em dias, depois a mais antiga e o id — o resultado não depende da
 * ordem em que as linhas chegaram.
 */
export function paresDeTransferencia(linhas: LinhaDoFluxo[], hoje: string): Set<string> {
  const debitos: Perna[] = [];
  const creditos: Perna[] = [];
  for (const l of linhas) {
    if (!l.id) continue;
    const destino = destinoDaLinha(l, hoje);
    if (destino !== 'movimento' && destino !== 'transferencia') continue;
    const perna: Perna = {
      id: l.id,
      data: dataDa(l),
      centavos: emCentavos(l.amount),
      conta: l.bank_connection_id ?? `origem:${l.source_type ?? 'bank'}`,
      marcada: destino === 'transferencia',
      caixa: (l.source_type ?? 'bank') === 'cash',
    };
    (l.transaction_type === 'debit' ? debitos : creditos).push(perna);
  }
  debitos.sort(antes);

  const creditosPorValor = new Map<number, Perna[]>();
  for (const c of creditos) {
    const lista = creditosPorValor.get(c.centavos) ?? [];
    lista.push(c);
    creditosPorValor.set(c.centavos, lista);
  }

  const casam = (d: Perna, c: Perna, fase: 1 | 2): boolean => {
    if (d.conta === c.conta || diasEntre(d.data, c.data) > DIAS_ENTRE_AS_PERNAS) return false;
    if (d.marcada && c.marcada) return true;
    if (fase === 1) return false;
    return (d.marcada && d.caixa && !c.caixa) || (c.marcada && c.caixa && !d.caixa);
  };

  // Candidatos de cada débito em cada fase, do melhor para o pior.
  const candidatos = new Map<string, Perna[]>();
  const candidatosDe = (d: Perna, fase: 1 | 2): Perna[] => {
    const chave = `${fase}:${d.id}`;
    let lista = candidatos.get(chave);
    if (!lista) {
      lista = (creditosPorValor.get(d.centavos) ?? [])
        .filter((c) => casam(d, c, fase))
        .sort((a, b) => diasEntre(d.data, a.data) - diasEntre(d.data, b.data) || antes(a, b));
      candidatos.set(chave, lista);
    }
    return lista;
  };

  // Emparelhamento máximo por caminhos aumentantes: um débito já casado só troca de par se o
  // antigo par dele puder casar com outro — ninguém que já estava casado fica sem par.
  const debitoDoCredito = new Map<string, Perna>();
  const creditoDoDebito = new Map<string, Perna>();
  const casar = (d: Perna, fase: 1 | 2, vistos: Set<string>): boolean => {
    for (const c of candidatosDe(d, fase)) {
      if (vistos.has(c.id)) continue;
      vistos.add(c.id);
      const atual = debitoDoCredito.get(c.id);
      if (!atual || casar(atual, fase, vistos)) {
        debitoDoCredito.set(c.id, d);
        creditoDoDebito.set(d.id, c);
        return true;
      }
    }
    return false;
  };
  for (const fase of [1, 2] as const) {
    for (const d of debitos) if (!creditoDoDebito.has(d.id)) casar(d, fase, new Set());
  }

  const pareadas = new Set<string>();
  for (const [d, c] of creditoDoDebito) { pareadas.add(d); pareadas.add(c.id); }
  return pareadas;
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
  /** À parte: transferências entre contas próprias. */
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

/** Soma o que ficou fora, por motivo, em centavos (ponto flutuante deixaria R$ 0,01 de sobra). */
type ForaEmCentavos = Partial<Record<DestinoDeFora, { quantidade: number; centavos: number }>>;

function anotarFora(fora: ForaEmCentavos, motivo: DestinoDeFora, quantidade: number, centavos: number) {
  const atual = fora[motivo] ?? { quantidade: 0, centavos: 0 };
  fora[motivo] = { quantidade: atual.quantidade + quantidade, centavos: atual.centavos + centavos };
}

const foraEmReais = (fora: ForaEmCentavos): ForaDoFluxo => Object.fromEntries(
  Object.entries(fora).map(([motivo, v]) => [motivo, { quantidade: v!.quantidade, valor: v!.centavos / 100 }]),
) as ForaDoFluxo;

/**
 * Soma UM recorte de dias ('AAAA-MM-DD' a 'AAAA-MM-DD', inclusive). O pareamento usa só as
 * linhas do recorte e as de até 2 dias antes e depois — nunca o resto do que foi lido —, para o
 * resultado não depender de quanto a tela leu.
 */
function somarRecorte(linhas: LinhaDoFluxo[], de: string, ate: string, hoje: string): { soma: Acumulador; fora: ForaEmCentavos } {
  const inicioDaJanela = somarDias(de, -DIAS_ENTRE_AS_PERNAS);
  const fimDaJanela = somarDias(ate, DIAS_ENTRE_AS_PERNAS);
  const janela = linhas.filter((l) => {
    const d = dataDa(l);
    return d >= inicioDaJanela && d <= fimDaJanela;
  });
  const pareadas = paresDeTransferencia(janela, hoje);

  const soma = vazio();
  const fora: ForaEmCentavos = {};
  for (const l of janela) {
    const d = dataDa(l);
    if (d < de || d > ate) continue;
    let destino = destinoDaLinha(l, hoje);
    if (destino.startsWith('fora_')) {
      anotarFora(fora, destino as DestinoDeFora, 1, Number.isFinite(Number(l.amount)) ? emCentavos(l.amount) : 0);
      continue;
    }
    // A marca "transferência" só vale com o par; a linha do banco pareada com o Caixa também é.
    const pareada = !!l.id && pareadas.has(l.id);
    if (destino === 'transferencia' && !pareada) destino = 'movimento';
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
  return { soma, fora };
}

/**
 * Monta o fluxo dos meses pedidos (em ordem), a partir das linhas cruas do extrato — cada mês
 * pareado com as suas linhas e 2 dias de cada lado, exatamente como o Resumo do mês faz.
 * Mês sem movimento aparece zerado — um buraco no gráfico diz "não houve nada", uma ausência
 * diria "não sei".
 */
export function montarFluxoDeCaixa(linhas: LinhaDoFluxo[], meses: string[], hoje: string): FluxoDeCaixa {
  const total = vazio();
  const fora: ForaEmCentavos = {};
  const porMes = meses.map((mes) => {
    const { de, ate } = limitesDosMeses([mes]);
    const r = somarRecorte(linhas, de, ate, hoje);
    for (const k of Object.keys(total) as Array<keyof Acumulador>) total[k] += r.soma[k];
    for (const [motivo, v] of Object.entries(r.fora)) anotarFora(fora, motivo as DestinoDeFora, v!.quantidade, v!.centavos);
    return { mes, ...paraReais(r.soma) };
  });
  return { meses: porMes, total: paraReais(total), deFora: foraEmReais(fora) };
}

/** Entrou e saiu num período de dias ('AAAA-MM-DD' a 'AAAA-MM-DD', inclusive). */
export function somarFluxoDoPeriodo(linhas: LinhaDoFluxo[], de: string, ate: string, hoje: string): SomaDoFluxo & { deFora: ForaDoFluxo } {
  const r = somarRecorte(linhas, de, ate, hoje);
  return { ...paraReais(r.soma), deFora: foraEmReais(r.fora) };
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

/**
 * Margem de dias que a LEITURA pega antes e depois do recorte: a outra perna de uma
 * transferência feita na virada do mês fica do outro lado dela. Maior ou igual a
 * DIAS_ENTRE_AS_PERNAS — o que passa disso é lido e ignorado.
 */
export const MARGEM_PARA_PAREAR = 3;

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
  'id, transaction_date, amount, transaction_type, source_type, provider, bank_connection_id, dismissed_kind, tx_status, import_batch_id';
