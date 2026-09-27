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
//     foi repetido pela sincronização automática), linha pendente e linha com data no futuro.
//     Extrato importado por arquivo DEPOIS daquele lote conta normalmente.
//   · Fica À PARTE, sem somar em Entrou/Saiu: transferência entre contas próprias — só a de
//     FATO, com as duas pernas (mesmo valor, sentido oposto, outra conta que guarda dinheiro,
//     até 2 dias) — e o crédito que o cartão põe na conta corrente ("Pix no crédito" do Nubank:
//     é dívida, não receita). A tela diz o valor desses baldes para ninguém achar que sumiram.
//     A marca "transferência" SEM a outra perna não basta: o pagamento da fatura do Nubank pela
//     conta do C6 e as "Vendas" que a maquininha liquida na InfinitePay estavam marcados assim,
//     e são dinheiro que saiu e que entrou de verdade (revisão de 27/09/2026).

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
  if (l.import_batch_id === LOTE_DA_IMPORTACAO_MANUAL_DE_JULHO) return 'fora_importacao_manual';
  if ((l.tx_status ?? '') === 'PENDING') return 'fora_pendente';
  // Comparação de texto 'AAAA-MM-DD': sem Date, sem fuso deslocando o dia.
  if (String(l.transaction_date).slice(0, 10) > hoje) return 'fora_futuro';
  if (l.transaction_type !== 'credit' && l.transaction_type !== 'debit') return 'fora_ilegivel';
  if (!Number.isFinite(Number(l.amount))) return 'fora_ilegivel';
  if (tipo === 'transferencia') return 'transferencia';
  if (tipo === 'mecanica_cartao') return 'credito_do_cartao';
  return 'movimento';
}

/** Soma em centavos: somar reais em ponto flutuante deixa R$ 0,01 de sobra no fim. */
function emCentavos(v: number | string): number {
  return Math.round(Math.abs(Number(v)) * 100);
}

const diasEntre = (a: string, b: string) =>
  Math.abs(Date.parse(String(a).slice(0, 10)) - Date.parse(String(b).slice(0, 10))) / 86_400_000;

/**
 * As transferências de FATO: pares de linhas (ids) com o mesmo valor, sentido oposto, em contas
 * diferentes que guardam dinheiro, até 2 dias de diferença — um par por linha, o mais próximo.
 *   1ª passada: as duas pernas marcadas "transferência".
 *   2ª passada: a perna do CAIXA marcada (saque ou depósito lançado pelo "+ Lançar") com a
 *   linha do banco, marcada ou não — senão o saque contava duas vezes (a saída no banco e o
 *   gasto em dinheiro).
 */
export function paresDeTransferencia(linhas: LinhaDoFluxo[], hoje: string): Set<string> {
  const validas = linhas.filter((l) => !!l.id && !destinoDaLinha(l, hoje).startsWith('fora_'));
  const marcadas = validas.filter((l) => (l.dismissed_kind ?? '') === 'transferencia');
  const conta = (l: LinhaDoFluxo) => l.bank_connection_id ?? `origem:${l.source_type ?? 'bank'}`;
  const usadas = new Set<string>();

  const parDe = (l: LinhaDoFluxo, candidatas: LinhaDoFluxo[]): LinhaDoFluxo | undefined => {
    let melhor: LinhaDoFluxo | undefined;
    let menor = Infinity;
    for (const m of candidatas) {
      if (m.id === l.id || usadas.has(m.id!) || m.transaction_type === l.transaction_type) continue;
      if (emCentavos(m.amount) !== emCentavos(l.amount) || conta(m) === conta(l)) continue;
      const d = diasEntre(m.transaction_date, l.transaction_date);
      if (d <= 2 && d < menor) { menor = d; melhor = m; }
    }
    return melhor;
  };
  const casar = (l: LinhaDoFluxo, candidatas: LinhaDoFluxo[]) => {
    if (usadas.has(l.id!)) return;
    const m = parDe(l, candidatas);
    if (m) { usadas.add(l.id!); usadas.add(m.id!); }
  };

  for (const l of marcadas) casar(l, marcadas);
  const doBanco = validas.filter((v) => (v.source_type ?? 'bank') !== 'cash');
  for (const l of marcadas) if ((l.source_type ?? 'bank') === 'cash') casar(l, doBanco);
  return usadas;
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

export interface FluxoDeCaixa {
  meses: MesDoFluxo[];
  total: SomaDoFluxo;
  /** O que não entrou em conta nenhuma, por motivo — para a tela poder dizer. */
  deFora: Partial<Record<DestinoDeFora, { quantidade: number; valor: number }>>;
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

/**
 * Soma as linhas nos baldes que `baldeDe` escolher ('AAAA-MM', 'periodo'…; null = fora do
 * recorte, mas ainda serve para parear transferência na virada do mês).
 */
function acumular(
  linhas: LinhaDoFluxo[],
  hoje: string,
  baldeDe: (data: string) => string | null,
  baldes: Map<string, Acumulador>,
): { total: Acumulador; deFora: FluxoDeCaixa['deFora'] } {
  const total = vazio();
  const deFora: FluxoDeCaixa['deFora'] = {};
  const pareadas = paresDeTransferencia(linhas, hoje);

  for (const l of linhas) {
    const chave = baldeDe(String(l.transaction_date).slice(0, 10));
    const acc = chave ? baldes.get(chave) : undefined;
    if (!acc) continue;
    let destino = destinoDaLinha(l, hoje);
    if (destino.startsWith('fora_')) {
      const d = destino as DestinoDeFora;
      const atual = deFora[d] ?? { quantidade: 0, valor: 0 };
      const valor = Number.isFinite(Number(l.amount)) ? emCentavos(l.amount) : 0;
      deFora[d] = { quantidade: atual.quantidade + 1, valor: Math.round(atual.valor * 100 + valor) / 100 };
      continue;
    }
    // A marca "transferência" só vale com o par; a linha do banco pareada com o Caixa também é.
    const pareada = !!l.id && pareadas.has(l.id);
    if (destino === 'transferencia' && !pareada) destino = 'movimento';
    else if (destino === 'movimento' && pareada) destino = 'transferencia';

    const c = emCentavos(l.amount);
    const entrada = l.transaction_type === 'credit';
    for (const a of [acc, total]) {
      if (destino === 'transferencia') {
        if (entrada) a.tEntrou += c; else a.tSaiu += c;
      } else if (destino === 'credito_do_cartao') {
        if (entrada) a.cEntrou += c; else a.cSaiu += c;
      } else {
        if (entrada) a.entrou += c; else a.saiu += c;
        a.quantidade += 1;
      }
    }
  }
  return { total, deFora };
}

/**
 * Monta o fluxo dos meses pedidos (em ordem), a partir das linhas cruas do extrato.
 * Linha de mês fora da lista não soma (mas ajuda a parear). Mês sem movimento aparece zerado —
 * um buraco no gráfico diz "não houve nada", uma ausência diria "não sei".
 */
export function montarFluxoDeCaixa(linhas: LinhaDoFluxo[], meses: string[], hoje: string): FluxoDeCaixa {
  const porMes = new Map<string, Acumulador>(meses.map((m) => [m, vazio()]));
  const { total, deFora } = acumular(linhas, hoje, (d) => d.slice(0, 7), porMes);
  return {
    meses: meses.map((mes) => ({ mes, ...paraReais(porMes.get(mes)!) })),
    total: paraReais(total),
    deFora,
  };
}

/** Entrou e saiu num período de dias ('AAAA-MM-DD' a 'AAAA-MM-DD', inclusive). */
export function somarFluxoDoPeriodo(linhas: LinhaDoFluxo[], de: string, ate: string, hoje: string): SomaDoFluxo & { deFora: FluxoDeCaixa['deFora'] } {
  const baldes = new Map<string, Acumulador>([['periodo', vazio()]]);
  const { deFora } = acumular(linhas, hoje, (d) => (d >= de && d <= ate ? 'periodo' : null), baldes);
  return { ...paraReais(baldes.get('periodo')!), deFora };
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
 * Margem de dias que a leitura pega antes e depois do recorte: a outra perna de uma
 * transferência feita na virada do mês fica do outro lado dela.
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
