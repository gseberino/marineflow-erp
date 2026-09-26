// A mesma regra do servidor, na tela: qual vínculo vale para uma linha do Extrato e quando
// a linha não pode ser aprovada sem alguém escolher.
//
// A política mora em supabase/functions/_shared/banking/vinculo.ts (vinculoAutomatico,
// exigeDecisao) e destino.ts ("para onde foi" do serviço de terceiro) e é importada daqui — a
// tela e o servidor não podem discordar sobre o que acontece quando se clica em aprovar.
import {
  exigeDecisao, osAnotada, podeJaEstarLancado, vinculoAutomatico, type OpcaoDeVinculo, type VinculoSugerido,
} from '../../supabase/functions/_shared/banking/vinculo';
import { faltaNoDestino, type FaltaNoDestino } from '../../supabase/functions/_shared/banking/destino';

export type EscolhaDeVinculo = { id: string } | 'nenhum' | undefined;

/** Todas as opções de uma sugestão, a principal primeiro. */
export function opcoesDoVinculo(v: VinculoSugerido | null | undefined): OpcaoDeVinculo[] {
  return v ? [v.principal, ...(v.alternativas ?? [])] : [];
}

/**
 * O que a aprovação vai usar: a escolha da pessoa; sem escolha, o vínculo automático.
 * `null` = lança novo.
 */
export function vinculoEfetivo(v: VinculoSugerido | null | undefined, escolha: EscolhaDeVinculo): OpcaoDeVinculo | null {
  if (escolha === 'nenhum') return null;
  if (escolha && typeof escolha === 'object') return opcoesDoVinculo(v).find((o) => o.id === escolha.id) ?? null;
  return vinculoAutomatico(v);
}

/**
 * Há vínculo sugerido e ninguém respondeu: não aprova no escuro (decisão do dono, 26/09/2026 —
 * toda sugestão de vínculo é pergunta).
 */
export function precisaDecidir(v: VinculoSugerido | null | undefined, escolha: EscolhaDeVinculo): boolean {
  if (escolha) return false;
  return exigeDecisao(v);
}

export { podeJaEstarLancado };

export {
  osVemDoVinculo, osAnotada, temPerguntaDaOS, temPerguntaDaOC, perguntaDaOSAberta, type LinhaComPerguntas,
} from '../../supabase/functions/_shared/banking/vinculo';

export {
  SERVICO_DE_CLIENTE, SERVICO_DA_EMPRESA, CATEGORIAS_COM_DESTINO, precisaDeDestino, destinoEfetivo,
  categoriaDoDestino, fraseDaFalta, type FaltaNoDestino, type Destino,
} from '../../supabase/functions/_shared/banking/destino';
export { faltaNoDestino };

/** O que uma linha da fila precisa para a pergunta "Para onde foi?". */
interface LinhaParaODestino {
  kind: string;
  suggested_category: string | null;
  suggested_service_order_id?: string | null;
  evidencia?: { anotacao?: { id?: string; os_id?: string | null } | null } | null;
}

/** O que a tela respondeu na linha (os campos da correção que importam aqui). */
interface RespostaDaLinha {
  category?: string;
  serviceOrderId?: string | null;
  costCenterId?: string | null;
  notes?: string | null;
  destino?: 'cliente' | 'empresa' | null;
  vinculo?: { id: string } | 'nenhum';
}

/**
 * O que falta para aprovar uma linha de serviço de terceiro — a MESMA conta que o servidor faz
 * em finance-review/aprovar: a categoria escolhida na tela, a OS anotada pelo WhatsApp quando
 * ninguém respondeu outra, e nada quando a linha vai CASAR com um lançamento que já existe
 * (ele já tem a categoria dele).
 */
export function faltaNoDestinoDaLinha(p: LinhaParaODestino, r: RespostaDaLinha | undefined): FaltaNoDestino[] {
  if (r?.vinculo && typeof r.vinculo === 'object') return [];
  const categoria = r?.category ?? p.suggested_category ?? '';
  const osJaDita = r?.serviceOrderId === undefined ? osAnotada(p) : null;
  return faltaNoDestino(p.kind, categoria, r, osJaDita);
}
