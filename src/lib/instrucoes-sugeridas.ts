// Via do técnico v2, F2 (20/11/2026): a tela das instruções sugeridas pelo assistente (canal A, botão na tela da OS).
//
// Quem decide é o banco (via_instrucao_pedir / via_instrucao_pendentes / via_instrucao_decidir, migration 20270131100000):
// elegibilidade, número do serviço, cobrança e o que fica velho. Aqui é só o que a tela mostra e o mesmo limite de texto
// que o banco aplica (para avisar antes de mandar). Na tela a palavra é "sugestão do assistente", nunca "rascunho": o selo
// âmbar "rascunho" já marca serviço não salvo (services-section.tsx).

export const MINIMO_DA_INSTRUCAO = 10;
/** Duas linhas no cartão do serviço: acima disso, aviso suave. */
export const LIMITE_SUAVE_DA_INSTRUCAO = 160;
export const LIMITE_DA_INSTRUCAO = 400;

export interface SugestaoDeInstrucao {
  id: string;
  linha_id: string;
  /** O número do serviço no papel (cobrança conta, regra 4A). */
  numero: number;
  nome: string;
  texto: string;
  origem: 'ia' | 'reuso';
  /** Reuso: "igual à do ORÇ-00131 · serviço 4". */
  fonte_rotulo: string | null;
  criado_em: string;
}

export interface JobDaInstrucao {
  id: string;
  status: string;
  criado_em: string;
  iniciado_em: string | null;
  terminado_em: string | null;
  error_code: string | null;
  error: string | null;
  linhas: number;
  recebidos: number | null;
  sem_sugestao: number | null;
}

export interface RetratoDasInstrucoes {
  service_order_id: string;
  documento: string | null;
  em_uso: boolean;
  pendentes: SugestaoDeInstrucao[];
  /** Quantos serviços ainda podem pedir sugestão (sem instrução, sem pendente, não cobrança). */
  elegiveis: number;
  /** O pedido aberto ao assistente, ou o último das 2 últimas horas. */
  job: JobDaInstrucao | null;
}

export interface ResultadoDoPedido {
  job_id: string | null;
  job_novo: boolean;
  reusadas: number;
  pedidas: number;
  esperando_job: number;
  ja_tem: number;
  cobranca: number;
  pendentes: number;
  sem_sugestao: number;
}

export interface ResultadoDaDecisao {
  itens: Array<{ id: string; linha_id?: string; numero?: number; resultado: string }>;
  totais: Partial<Record<'aprovado' | 'corrigido' | 'descartado' | 'ja_decidido' | 'substituido' | 'obsoleto' | 'fora_de_uso' | 'nao_encontrado', number>>;
}

export function retratoVazio(orderId: string): RetratoDasInstrucoes {
  return { service_order_id: orderId, documento: null, em_uso: false, pendentes: [], elegiveis: 0, job: null };
}

/** O texto como o banco grava: uma linha só, espaços simples. */
export function normalizarInstrucao(texto: string): string {
  return texto.replace(/[\r\n\t]+/g, ' ').replace(/ {2,}/g, ' ').trim();
}

/** Por que o banco recusaria este texto (ou null). */
export function problemaDaInstrucao(texto: string): string | null {
  const t = normalizarInstrucao(texto);
  if (t.length < MINIMO_DA_INSTRUCAO) return `Escreva pelo menos ${MINIMO_DA_INSTRUCAO} letras.`;
  if (t.length > LIMITE_DA_INSTRUCAO) return `Passou de ${LIMITE_DA_INSTRUCAO} letras: encurte para caber no cartão.`;
  if (/R\$/i.test(t)) return 'Sem valor em R$: a via não imprime linha com preço, e a instrução sumiria do papel.';
  return null;
}

export type EstadoDoPedido = 'livre' | 'na_fila' | 'rascunhando' | 'falhou';

export function estadoDoPedido(r: RetratoDasInstrucoes): EstadoDoPedido {
  switch (r.job?.status) {
    case 'pending':
      return 'na_fila';
    case 'processing':
      return 'rascunhando';
    case 'failed':
    case 'cancelled':
      return 'falhou';
    default:
      return 'livre';
  }
}

const plural = (n: number, um: string, varios: string) => `${n} ${n === 1 ? um : varios}`;

export function resumoDoPedido(r: ResultadoDoPedido): string {
  if (!r.job_novo && r.esperando_job > 0 && r.reusadas === 0) return 'O assistente já está rascunhando estas instruções.';
  const partes: string[] = [];
  if (r.reusadas > 0) {
    partes.push(`${r.reusadas === 1 ? '1 veio de serviço igual já aprovado' : `${r.reusadas} vieram de serviços iguais já aprovados`}`);
  }
  if (r.pedidas > 0) {
    partes.push(r.reusadas > 0
      ? `o assistente está rascunhando ${r.pedidas === 1 ? 'a outra' : `as outras ${r.pedidas}`}`
      : `O assistente está rascunhando ${plural(r.pedidas, 'instrução', 'instruções')}`);
  }
  if (!partes.length) return 'Nenhum serviço precisa de sugestão agora.';
  return `${partes.join('; ')}.`;
}

export function resumoDaDecisao(r: ResultadoDaDecisao): string {
  const t = r.totais ?? {};
  const aprovadas = (t.aprovado ?? 0) + (t.corrigido ?? 0);
  const fora = (t.substituido ?? 0) + (t.obsoleto ?? 0) + (t.fora_de_uso ?? 0) + (t.nao_encontrado ?? 0);
  const partes: string[] = [];
  if (aprovadas > 0) partes.push(`${plural(aprovadas, 'instrução aprovada', 'instruções aprovadas')}.`);
  if (t.descartado) partes.push(t.descartado === 1 ? 'Sugestão descartada.' : `${t.descartado} sugestões descartadas.`);
  if (fora > 0) {
    partes.push(`${fora === 1 ? '1 não entrou' : `${fora} não entraram`}: o serviço já tinha instrução ou mudou.`);
  }
  if (t.ja_decidido && !aprovadas && !t.descartado && !fora) {
    return t.ja_decidido === 1 ? 'Esta sugestão já tinha sido decidida.' : `${t.ja_decidido} sugestões já tinham sido decididas.`;
  }
  return partes.join(' ') || 'Nada mudou.';
}

/** A linha do aviso antes de imprimir a via (somada às faltas da via). */
export function faltaDeInstrucaoNaVia(pendentes: number): string | null {
  if (pendentes <= 0) return null;
  return `instrução sugerida esperando aprovação em ${plural(pendentes, 'serviço', 'serviços')}`;
}
