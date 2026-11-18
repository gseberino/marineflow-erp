/**
 * "Agrupar para o cliente" (conjunto) — a parte pura: tipos do que o banco devolve, a decisão de como agrupar,
 * o quadro de valores da capa, o nome do arquivo e a mensagem padrão.
 *
 * O conjunto só CITA os documentos (migration 20270124100000_agrupar_para_cliente): nada é cancelado, movido ou
 * renumerado. O agrupar antigo ("juntar de vez": agrupar_orcamentos / agrupar_os) continua existindo.
 *
 * Decisões do dono (18/11/2026): mesma embarcação; um botão "Agrupar" só, que pergunta "juntar de vez ou apresentar
 * junto" apenas quando a fusão também é possível (4B); cada documento mantém a condição e o sinal dele (3A); o que
 * já foi aprovado e assinado não muda.
 */

export type TipoDoDocumento = 'orcamento' | 'os';

/** Um documento do conjunto, como conjunto_do_documento / agrupar_para_cliente devolvem. */
export interface DocumentoDoConjunto {
  id: string;
  numero: string;
  tipo: TipoDoDocumento;
  status: string;
  quote_status: string | null;
  principal: boolean;
  ativo: boolean;
  assinado: boolean;
  grand_total: number;
  recebido: number;
  sinal_a_pagar: number;
  em_aberto: number;
}

export interface Conjunto {
  id: string;
  nome: string;
  ativo: boolean;
  criado_em: string;
  desfeito_em: string | null;
  desfeito_motivo: string | null;
  client_id: string;
  cliente: string | null;
  vessel_id: string | null;
  embarcacao: string | null;
  principal_id: string | null;
  total_geral: number;
  documentos: DocumentoDoConjunto[];
}

/** Um documento que pode (ou não) entrar: documentos_para_conjunto. */
export interface CandidatoAoConjunto {
  id: string;
  numero: string;
  tipo: TipoDoDocumento;
  status: string;
  quote_status: string | null;
  grand_total: number;
  criado_em: string;
  /** Por que não entra no conjunto. Nulo = entra. */
  motivo: string | null;
  /** Por que não dá para JUNTAR DE VEZ (a fusão antiga). Nulo = em princípio dá. */
  motivo_juntar: string | null;
}

export interface LeituraParaConjunto {
  documento: CandidatoAoConjunto;
  candidatos: CandidatoAoConjunto[];
}

const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};

type Bruto = Record<string, unknown>;
const texto = (v: unknown): string => (v == null ? '' : String(v));
const textoOuNulo = (v: unknown): string | null => (v == null ? null : String(v));
const tipoDe = (v: unknown): TipoDoDocumento => (v === 'orcamento' ? 'orcamento' : 'os');

/** O jsonb do banco vem com numeric como string ou número: normaliza para a tela e o PDF. */
export function normalizarConjunto(bruto: unknown): Conjunto | null {
  if (!bruto || typeof bruto !== 'object') return null;
  const c = bruto as Bruto;
  return {
    id: texto(c.id),
    nome: texto(c.nome),
    ativo: !!c.ativo,
    criado_em: texto(c.criado_em),
    desfeito_em: textoOuNulo(c.desfeito_em),
    desfeito_motivo: textoOuNulo(c.desfeito_motivo),
    client_id: texto(c.client_id),
    cliente: textoOuNulo(c.cliente),
    vessel_id: textoOuNulo(c.vessel_id),
    embarcacao: textoOuNulo(c.embarcacao),
    principal_id: textoOuNulo(c.principal_id),
    total_geral: num(c.total_geral),
    documentos: (Array.isArray(c.documentos) ? (c.documentos as Bruto[]) : []).map((d) => ({
      id: texto(d.id),
      numero: texto(d.numero),
      tipo: tipoDe(d.tipo),
      status: texto(d.status),
      quote_status: textoOuNulo(d.quote_status),
      principal: !!d.principal,
      ativo: d.ativo !== false,
      assinado: !!d.assinado,
      grand_total: num(d.grand_total),
      recebido: num(d.recebido),
      sinal_a_pagar: num(d.sinal_a_pagar),
      em_aberto: num(d.em_aberto),
    })),
  };
}

function normalizarCandidato(d: Bruto): CandidatoAoConjunto {
  return {
    id: texto(d.id),
    numero: texto(d.numero),
    tipo: tipoDe(d.tipo),
    status: texto(d.status),
    quote_status: textoOuNulo(d.quote_status),
    grand_total: num(d.grand_total),
    criado_em: texto(d.criado_em),
    motivo: textoOuNulo(d.motivo),
    motivo_juntar: textoOuNulo(d.motivo_juntar),
  };
}

export function normalizarLeitura(bruto: unknown): LeituraParaConjunto | null {
  if (!bruto || typeof bruto !== 'object') return null;
  const r = bruto as Bruto;
  if (!r.documento || typeof r.documento !== 'object') return null;
  return {
    documento: normalizarCandidato(r.documento as Bruto),
    candidatos: (Array.isArray(r.candidatos) ? (r.candidatos as Bruto[]) : []).map(normalizarCandidato),
  };
}

export type ComoAgrupar =
  | { podeConjunto: false; motivoConjunto: string; fusao: null; porQueNaoFunde: null }
  | { podeConjunto: true; motivoConjunto: null; fusao: 'orcamentos' | 'os' | null; porQueNaoFunde: string | null };

/**
 * Decisão 4B: com os documentos escolhidos, o que a janela oferece.
 *  - conjunto: sempre, se todos podem entrar (o banco repete a régua ao gravar);
 *  - juntar de vez: só se todos são do MESMO tipo e nenhum tem motivo_juntar. Senão, a frase de por que não.
 */
export function decidirComoAgrupar(escolhidos: CandidatoAoConjunto[]): ComoAgrupar {
  if (escolhidos.length < 2) {
    return { podeConjunto: false, motivoConjunto: 'Escolha pelo menos 2 documentos.', fusao: null, porQueNaoFunde: null };
  }
  if (escolhidos.length > 10) {
    return { podeConjunto: false, motivoConjunto: 'Agrupe no máximo 10 documentos de uma vez.', fusao: null, porQueNaoFunde: null };
  }
  const barrado = escolhidos.find((d) => d.motivo);
  if (barrado) return { podeConjunto: false, motivoConjunto: barrado.motivo!, fusao: null, porQueNaoFunde: null };

  const tipos = new Set(escolhidos.map((d) => d.tipo));
  if (tipos.size > 1) {
    return {
      podeConjunto: true, motivoConjunto: null, fusao: null,
      porQueNaoFunde: 'Juntar de vez só une documentos do mesmo tipo (só orçamentos ou só OS).',
    };
  }
  const semFusao = escolhidos.find((d) => d.motivo_juntar);
  if (semFusao) return { podeConjunto: true, motivoConjunto: null, fusao: null, porQueNaoFunde: semFusao.motivo_juntar };
  return { podeConjunto: true, motivoConjunto: null, fusao: escolhidos[0].tipo === 'os' ? 'os' : 'orcamentos', porQueNaoFunde: null };
}

const SITUACAO_DA_OS: Record<string, string> = {
  scheduled: 'agendada',
  open: 'aberta',
  approved: 'aprovada',
  awaiting_parts: 'aguardando peças',
  awaiting_client: 'aguardando cliente',
  in_progress: 'em andamento',
  completed: 'concluída',
  invoiced: 'faturada',
  cancelled: 'cancelada',
};

const SITUACAO_DO_ORCAMENTO: Record<string, string> = {
  draft: 'em elaboração',
  sent: 'enviado',
  awaiting_approval: 'aguardando aprovação',
  approved: 'aprovado',
  awaiting_deposit: 'aguardando sinal',
  rejected: 'reprovado',
};

/** "agendada", "em elaboração", "aprovado e assinado"… — a situação em palavras do cliente. */
export function situacaoDoDocumento(d: Pick<DocumentoDoConjunto, 'tipo' | 'status' | 'quote_status' | 'assinado'>): string {
  const base = d.tipo === 'orcamento'
    ? SITUACAO_DO_ORCAMENTO[d.quote_status ?? 'draft'] ?? 'em elaboração'
    : SITUACAO_DA_OS[d.status] ?? d.status;
  return d.assinado ? `${base}, ${d.tipo === 'os' ? 'assinada' : 'assinado'}` : base;
}

export interface LinhaDoQuadro {
  numero: string;
  tipo: TipoDoDocumento;
  situacao: string;
  total: number;
  recebido: number;
  /** Decisão 3A: o sinal em aberto de CADA documento (o complemento traz o dele). */
  aPagarAgora: number;
  saldo: number;
}

export interface QuadroDeValores {
  linhas: LinhaDoQuadro[];
  total: number;
  recebido: number;
  aPagarAgora: number;
  saldo: number;
}

const centavos = (v: number) => Math.round(v * 100) / 100;

/** O quadro da capa: por documento e somado. Saldo = total − já pago − a pagar agora (nunca negativo). */
export function quadroDeValores(c: Pick<Conjunto, 'documentos'>): QuadroDeValores {
  const linhas = c.documentos.filter((d) => d.ativo).map((d): LinhaDoQuadro => {
    const aPagarAgora = centavos(d.sinal_a_pagar);
    return {
      numero: d.numero,
      tipo: d.tipo,
      situacao: situacaoDoDocumento(d),
      total: centavos(d.grand_total),
      recebido: centavos(d.recebido),
      aPagarAgora,
      saldo: centavos(Math.max(0, d.grand_total - d.recebido - aPagarAgora)),
    };
  });
  const soma = (k: keyof Pick<LinhaDoQuadro, 'total' | 'recebido' | 'aPagarAgora' | 'saldo'>) =>
    centavos(linhas.reduce((s, l) => s + l[k], 0));
  return { linhas, total: soma('total'), recebido: soma('recebido'), aPagarAgora: soma('aPagarAgora'), saldo: soma('saldo') };
}

/** "A", "A e B", "A, B e C". */
export function listaNatural(itens: string[]): string {
  if (itens.length <= 1) return itens[0] ?? '';
  return `${itens.slice(0, -1).join(', ')} e ${itens[itens.length - 1]}`;
}

/** Os números ativos na ordem do conjunto (principal primeiro). */
export function numerosDoConjunto(c: Pick<Conjunto, 'documentos'>): string[] {
  return c.documentos.filter((d) => d.ativo).map((d) => d.numero);
}

/** "OS-00104 + ORÇ-00140.pdf" — sem caracteres que o WhatsApp ou o Windows recusam. */
export function nomeDoArquivoDoConjunto(c: Pick<Conjunto, 'documentos'>): string {
  return `${numerosDoConjunto(c).join(' + ')}.pdf`.replace(/[\\/:*?"<>|]/g, '_');
}

/** Mensagem padrão, no tom do envio de hoje ("Segue o ORÇ-00123, conforme solicitado…"). */
export function mensagemPadraoDoConjunto(c: Pick<Conjunto, 'documentos'>): string {
  return `Segue ${listaNatural(numerosDoConjunto(c))} num documento só, conforme solicitado. Qualquer dúvida, estamos à disposição.`;
}

/** O tipo do PDF de cada documento: orçamento ainda em rascunho sai como orçamento; o resto, como OS. */
export function tipoDoPdf(d: Pick<DocumentoDoConjunto, 'tipo'>): 'quote' | 'service_order' {
  return d.tipo === 'orcamento' ? 'quote' : 'service_order';
}

/**
 * Para o envio: o documento que leva o contexto "orçamento" (o 1º orçamento do conjunto) e os demais orçamentos, que o
 * whatsapp-send também marca como enviados (mesmas regras). Sem orçamento: contexto de OS, no principal.
 */
export function alvosDoEnvio(c: Pick<Conjunto, 'documentos' | 'principal_id'>): {
  context: 'quote' | 'service_order';
  serviceOrderId: string;
  outrosOrcamentos: string[];
} {
  const ativos = c.documentos.filter((d) => d.ativo);
  const orcamentos = ativos.filter((d) => d.tipo === 'orcamento');
  if (orcamentos.length > 0) {
    return { context: 'quote', serviceOrderId: orcamentos[0].id, outrosOrcamentos: orcamentos.slice(1).map((d) => d.id) };
  }
  return { context: 'service_order', serviceOrderId: c.principal_id ?? ativos[0]?.id ?? '', outrosOrcamentos: [] };
}
