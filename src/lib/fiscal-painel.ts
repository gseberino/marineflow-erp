/**
 * A lista de notas e o painel de saúde fiscal: filtro, naturezas, números do mês e validade do
 * certificado.
 *
 * Extraído de FiscalEmission.tsx (D33, passo 2, 01/10/2026) sem mudar a conta, para ter teste.
 * Cada nota é lida pelas funções de nota-fiscal-leitura, que sabem onde NF-e e NFS-e guardam
 * cada coisa.
 */
import {
  contaParaFaturamento, dataDaNota, naturezaDaNota, textoBuscavelDaNota, tipoDaNota, totalDaNota,
} from './nota-fiscal-leitura';

/**
 * As naturezas que existem NESTAS notas, não uma lista fixa.
 *
 * A natureza é texto livre na emissão ("Venda de mercadoria", "Devolução de compra", e o que
 * mais for escrito amanhã). Uma lista fixa no código envelheceria calada: a natureza nova
 * simplesmente não apareceria como opção de filtro e ninguém saberia por quê.
 */
export function naturezasDasNotas(docs: readonly unknown[] | null | undefined): string[] {
  const vistas = new Set<string>();
  for (const doc of docs ?? []) {
    const n = naturezaDaNota(doc);
    if (n) vistas.add(n);
  }
  return [...vistas].sort((a, b) => a.localeCompare(b, 'pt-BR'));
}

/** O filtro da lista, no formato do useMultiFilter da tela. */
export interface FiltroDeNotas {
  search?: unknown;
  status?: unknown;
  tipo?: unknown;
  natureza?: unknown;
  ambiente?: unknown;
  dateFrom?: unknown;
  dateTo?: unknown;
}

/** AAAA-MM-DD do dia LOCAL de um instante. */
function diaLocal(bruta: string): string {
  const d = new Date(bruta);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/**
 * As notas que passam no filtro: status, tipo, natureza, ambiente (sem ambiente conta como
 * produção), período e busca por texto.
 */
export function filtrarNotas<T>(docs: readonly T[] | null | undefined, filtro: FiltroDeNotas): T[] {
  const busca = String(filtro.search ?? '').trim().toLowerCase();
  const status = (filtro.status ?? []) as string[];
  const tipos = (filtro.tipo ?? []) as string[];
  const naturezas = (filtro.natureza ?? []) as string[];
  const ambientes = (filtro.ambiente ?? []) as string[];
  const de = String(filtro.dateFrom ?? '');
  const ate = String(filtro.dateTo ?? '');

  return (docs ?? []).filter((doc) => {
    const d = doc as { status?: string; environment?: string | null };
    if (status.length && !status.includes(d.status ?? '')) return false;
    if (tipos.length && !tipos.includes(tipoDaNota(doc))) return false;
    if (naturezas.length && !naturezas.includes(naturezaDaNota(doc))) return false;
    if (ambientes.length && !ambientes.includes(d.environment ?? 'producao')) return false;

    if (de || ate) {
      // Compara pelo DIA local da nota. Recortar por string ISO cortaria errado a nota
      // emitida à noite, cuja hora UTC já caiu no dia seguinte.
      const bruta = dataDaNota(doc);
      if (!bruta) return false;
      const dia = diaLocal(bruta);
      if (de && dia < de) return false;
      if (ate && dia > ate) return false;
    }

    if (busca && !textoBuscavelDaNota(doc).includes(busca)) return false;
    return true;
  });
}

/**
 * Os números do mês corrente para o painel de saúde fiscal.
 *
 * O faturamento do mês. Medido em 23/09/2026: o painel mostrava R$ 0,00 em setembro. Três
 * defeitos somados, todos herdados de ler a nota pelo campo errado:
 *
 *  1. o valor vinha de `payments[0].amount`, a forma de pagamento declarada. A NFS-e não tem
 *     esse campo, e a única nota de setembro era uma NFS-e de R$ 500: o mês inteiro aparecia
 *     zerado. Em agosto faltavam R$ 2.800,38 pelo mesmo motivo;
 *  2. o mês vinha de `created_at`, que é quando a LINHA nasceu, em UTC: nota emitida à noite
 *     no fim do mês caía no mês seguinte;
 *  3. nota de HOMOLOGAÇÃO entrava na conta. Julho mostrava R$ 8.100 quando o faturamento real
 *     foi R$ 4.050: metade era um teste que não vale nada fiscalmente.
 *
 * Devolução também fica de fora, por um motivo diferente: ela É uma nota autorizada de
 * verdade, mas não é receita (é mercadoria voltando para o fornecedor).
 */
export function estatisticasDoMes(docs: readonly unknown[] | null | undefined, agora: Date = new Date()) {
  const y = agora.getFullYear();
  const m = agora.getMonth();
  const doMes = (docs ?? []).filter((d) => {
    const bruta = dataDaNota(d);
    if (!bruta) return false;
    const dt = new Date(bruta);
    return dt.getFullYear() === y && dt.getMonth() === m;
  });
  const por = (s: string) => doMes.filter((d) => (d as { status?: string })?.status === s);
  const authorized = por('authorized');
  const faturaveis = authorized.filter(contaParaFaturamento);
  const faturamento = faturaveis.reduce<number>((sum, d) => sum + totalDaNota(d), 0);
  const rejected = por('rejected').length;
  const cancelled = por('cancelled').length;
  return {
    authorized: authorized.length,
    rejected,
    cancelled,
    faturamento,
    // Proxy da cota da Contora: eventos que chegaram à SEFAZ (autorizada+rejeitada+cancelada).
    eventos: authorized.length + rejected + cancelled,
    faturaveis: faturaveis.length,
    foraDoFaturamento: authorized.length - faturaveis.length,
  };
}

/**
 * Validade do certificado A1 → dias a vencer (alerta antecipado de "apagão fiscal": certificado
 * vencido trava toda a emissão de NF-e).
 *
 * `validUntil` vem de CompanyCertificateSummary.valid_until da Contora, `format: date`
 * (AAAA-MM-DD), conferido na especificação OpenAPI em 01/10/2026. Vale até o fim desse dia.
 * Data que não se lê devolve null (antes a tela mostraria "NaN dias").
 */
export function validadeDoCertificado(
  validUntil: string | null | undefined,
  agora: number = Date.now(),
): { validUntil: string; days: number } | null {
  if (!validUntil) return null;
  const fim = new Date(`${validUntil}T23:59:59`).getTime();
  if (Number.isNaN(fim)) return null;
  return { validUntil, days: Math.floor((fim - agora) / 86_400_000) };
}
