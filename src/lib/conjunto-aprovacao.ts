/**
 * "Agrupar para o cliente" F2 — aprovar o conjunto (migration 20270129100000_agrupar_para_cliente_aprovar). A parte pura.
 *
 * Quem decide o que acontece com cada documento é o BANCO (aprovar_conjunto, com p_ensaio para a janela mostrar antes):
 *   · assinado, OS ou já aprovado: não muda (decisão do dono: o que foi aprovado e assinado nunca é alterado);
 *   · orçamento com sinal na condição: fica aguardando o sinal DELE (3A) e vira OS própria quando o sinal entra;
 *   · orçamento sem sinal na condição: vira OS própria agora;
 *   · os aprovados ficam marcados "complementa OS-X" (5A).
 * Aqui só o VALOR do sinal de cada orçamento, para mostrar — pela lib única (quote-deposit, com o discountRatio).
 */
import {
  CONDICAO_PADRAO,
  computeDeposit,
  depositAmountFromPcts,
  depositBaseFromOrder,
  type DepositInstallment,
  type DepositOrderLike,
} from '@/lib/quote-deposit';
import { type Conjunto, type DocumentoDoConjunto, normalizarConjunto } from '@/lib/conjunto';

export type AcaoNaAprovacao = 'aguardar_sinal' | 'virar_os' | 'nao_muda';

export interface DocumentoNaAprovacao {
  id: string;
  numero: string;
  /** O número depois (ORÇ-00140 → OS-00140 quando vira OS). */
  numero_depois: string;
  /** aprovar | assinado | os | aprovado | reprovado | fora */
  situacao: string;
  acao: AcaoNaAprovacao;
  texto: string;
}

export interface ResultadoDaAprovacao {
  ok: boolean;
  ensaio: boolean;
  conjunto_id: string;
  nome: string;
  complementa: { id: string; numero: string } | null;
  aprovados: number;
  viraram_os: number;
  aguardando_sinal: number;
  documentos: DocumentoNaAprovacao[];
  conjunto: Conjunto | null;
}

type Bruto = Record<string, unknown>;
const texto = (v: unknown): string => (v == null ? '' : String(v));
const inteiro = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
const ACOES: AcaoNaAprovacao[] = ['aguardar_sinal', 'virar_os', 'nao_muda'];

export function normalizarAprovacao(bruto: unknown): ResultadoDaAprovacao | null {
  if (!bruto || typeof bruto !== 'object') return null;
  const r = bruto as Bruto;
  const c = r.complementa && typeof r.complementa === 'object' ? (r.complementa as Bruto) : null;
  return {
    ok: r.ok === true,
    ensaio: r.ensaio === true,
    conjunto_id: texto(r.conjunto_id),
    nome: texto(r.nome),
    complementa: c ? { id: texto(c.id), numero: texto(c.numero) } : null,
    aprovados: inteiro(r.aprovados),
    viraram_os: inteiro(r.viraram_os),
    aguardando_sinal: inteiro(r.aguardando_sinal),
    documentos: (Array.isArray(r.documentos) ? (r.documentos as Bruto[]) : []).map((d) => ({
      id: texto(d.id),
      numero: texto(d.numero),
      numero_depois: texto(d.numero_depois) || texto(d.numero),
      situacao: texto(d.situacao),
      acao: (ACOES as string[]).includes(texto(d.acao)) ? (texto(d.acao) as AcaoNaAprovacao) : 'nao_muda',
      texto: texto(d.texto),
    })),
    conjunto: normalizarConjunto(r.conjunto),
  };
}

/** Os orçamentos do conjunto que dá para aprovar (pendentes, não assinados, ativos). */
export function orcamentosAprovaveis(c: Pick<Conjunto, 'documentos' | 'ativo'>): DocumentoDoConjunto[] {
  if (!c.ativo) return [];
  return c.documentos.filter((d) => d.ativo && d.aprovavel);
}

/**
 * As parcelas da condição como o banco as resolve (_orcamento_tem_sinal e a cobrança da conclusão): as do preset, se forem
 * lista; senão as personalizadas, se forem lista; senão nenhuma (= a condição padrão).
 */
export function parcelasDaCondicao(doPreset: unknown, personalizadas: unknown): DepositInstallment[] | null {
  if (Array.isArray(doPreset)) return doPreset as DepositInstallment[];
  if (Array.isArray(personalizadas)) return personalizadas as DepositInstallment[];
  return null;
}

/**
 * O sinal que o orçamento pede, para MOSTRAR (a cobrança é a do "Receber sinal" de hoje). Sem condição: a condição padrão
 * (CONDICAO_PADRAO: 50% do serviço + 100% de peças e despesas), como o "Receber sinal". Sempre com o discountRatio.
 */
export function sinalDoOrcamento(o: DepositOrderLike, parcelas: DepositInstallment[] | null): { valor: number; padrao: boolean } {
  if (!parcelas || parcelas.length === 0) {
    const b = depositBaseFromOrder(o);
    return {
      valor: depositAmountFromPcts(b.laborCost, b.partsCost, b.expensesTotal, b.discountRatio,
        CONDICAO_PADRAO.servicesPct, CONDICAO_PADRAO.partsPct, CONDICAO_PADRAO.expensesPct),
      padrao: true,
    };
  }
  return { valor: computeDeposit(o, parcelas).amount ?? 0, padrao: false };
}

/** "Pronto: 2 orçamentos aprovados — 1 virou OS (OS-00141) e 1 aguarda o sinal." */
export function resumoDaAprovacao(r: ResultadoDaAprovacao): string {
  const n = r.aprovados;
  const partes: string[] = [];
  if (r.viraram_os > 0) {
    const numeros = r.documentos.filter((d) => d.acao === 'virar_os').map((d) => d.numero_depois).join(', ');
    partes.push(`${r.viraram_os} ${r.viraram_os === 1 ? 'virou OS' : 'viraram OS'}${numeros ? ` (${numeros})` : ''}`);
  }
  if (r.aguardando_sinal > 0) {
    partes.push(`${r.aguardando_sinal} ${r.aguardando_sinal === 1 ? 'aguarda o sinal' : 'aguardam o sinal'}`);
  }
  const cabeca = `${n} ${n === 1 ? 'orçamento aprovado' : 'orçamentos aprovados'}`;
  const corpo = partes.length ? ` — ${partes.join(' e ')}` : '';
  const marca = r.complementa ? `. ${n === 1 ? 'Complementa' : 'Complementam'} a ${r.complementa.numero}` : '';
  return `Pronto: ${cabeca}${corpo}${marca}.`;
}
