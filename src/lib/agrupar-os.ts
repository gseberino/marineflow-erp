// Agrupar ORDENS DE SERVIÇO (28/10/2026): N OS que ainda não começaram, do MESMO cliente e da MESMA
// embarcação, viram UMA OS nova (agrupar_os, migration 20261028120000). Quem decide é o banco; estas funções
// só antecipam na tela o que ele vai recusar ou avisar, para o dono escolher sabendo o que acontece.
// Decisões do dono (iguais às de orçamento): preços mantidos; condição de pagamento, contato e comissão vêm da
// OS PRINCIPAL (comissão recalculada sobre o total novo). O que muda: o dinheiro (sinais, contas a receber,
// cobranças), as tarefas manuais e as compras ACOMPANHAM para a OS nova; as assinaturas ficam nas originais.
// OS já executada fica de fora (pesquisa de mercado, 27/10): agrupar junta só OS que ainda não começaram.
import {
  diferencasAoAgrupar,
  emReais,
  type CandidatoAgrupar,
  type PalavrasDoAgrupamento,
} from '@/lib/agrupar-orcamentos';

export { MAX_AGRUPAR, MIN_AGRUPAR, emReais, mesmoClienteEEmbarcacao, principalPadrao, somaDosTotais } from '@/lib/agrupar-orcamentos';

/**
 * Situações em que a OS ainda não começou e pode entrar (as mesmas do banco). 'in_progress', 'completed' e
 * 'invoiced' ficam de fora: cada OS executada mantém o seu histórico.
 */
export const STATUS_AGRUPAVEIS_OS = ['scheduled', 'open', 'awaiting_parts', 'awaiting_client', 'approved'] as const;

const agrupavel = (status: string | null | undefined) =>
  (STATUS_AGRUPAVEIS_OS as readonly string[]).includes(status ?? '');

/**
 * Origem agrupada (merged_into_id) é de OS ou de orçamento? As duas ficam `cancelled`. Não basta
 * `converted_to_os_at`: há OS antigas sem ele e o banco as agrupa (para ele, fora de rascunho é OS). O
 * agrupar_os grava na origem o motivo "Agrupada em OS-N (reúne …)"; o de orçamento, "Agrupado em …".
 */
export function origemAgrupadaDeOs(
  o: { converted_to_os_at?: string | null; cancellation_reason?: string | null } | null | undefined,
): boolean {
  return !!o && (!!o.converted_to_os_at || /^Agrupada em /.test(o.cancellation_reason ?? ''));
}

export type CandidataOs = CandidatoAgrupar & {
  scheduled_start_at: string | null;
  card_fee_passthrough_enabled: boolean | null;
  operational_cost_total: number | null;
};

/** Conta a receber / sinal ligado a uma das OS escolhidas: vai junto para a OS nova. */
export type RecebivelDaPrevia = {
  id: string;
  service_order_id: string | null;
  description: string;
  amount: number;
  paid_amount: number | null;
  status: string | null;
  is_deposit: boolean | null;
  due_date: string;
};

/** Tarefa manual pendente ligada a uma das OS (visita, "comprar 1 item"…): vai junto. */
export type TarefaDaPrevia = {
  id: string;
  related_entity_id: string | null;
  title: string;
  due_at: string | null;
  scheduled_start_at: string | null;
};

/** Pedido de compra de uma das OS: passa a ser da OS nova. */
export type CompraDaPrevia = {
  id: string;
  service_order_id: string | null;
  po_number: string;
  status: string;
  total_amount: number;
};

/**
 * Por que esta OS não pode entrar no agrupamento (null = pode).
 *
 * A ordem importa: a origem de um agrupamento fica `cancelled` — "Já agrupada" diz mais que "Cancelada".
 * As outras recusas do banco (nota fiscal, fatura, comissão lançada, hora apontada, foto, baixa de estoque,
 * total desatualizado) não cabem nas colunas da lista e chegam como a frase do próprio banco ao tentar.
 */
export function motivoForaDoAgrupamentoOs(
  c: Pick<CandidataOs, 'status' | 'converted_to_os_at' | 'merged_into_id' | 'card_fee_passthrough_enabled' | 'operational_cost_total'>,
): string | null {
  if (c.merged_into_id) return 'Já agrupada';
  // Como o banco: rascunho é orçamento; fora dele é OS, mesmo a antiga sem converted_to_os_at.
  if (c.status === 'draft') return 'Ainda é orçamento';
  if (c.status === 'cancelled') return 'Cancelada';
  if (c.status === 'in_progress') return 'Em execução';
  if (c.status === 'completed') return 'Concluída';
  if (c.status === 'invoiced') return 'Faturada';
  if (!agrupavel(c.status)) return 'Situação não permite';
  if (Math.round((Number(c.operational_cost_total) || 0) * 100) !== 0) return 'Já tem despesa';
  if (c.card_fee_passthrough_enabled) return 'Repassa a taxa do cartão';
  return null;
}

/**
 * Palpite da tela, SÓ enquanto a leitura do banco (desagrupavelPeloBanco) não chega ou quando ela falha:
 * pela situação e pela assinatura, a tela sabe o que o banco SEMPRE recusa (começou, concluiu, faturou,
 * cancelou, o cliente assinou a nova). O resto (hora apontada, foto, despesa, recebível novo…) só o banco vê
 * — e é por isso que quem decide o Desagrupar/Cancelar é a leitura dele.
 */
export function osAgrupadaDesagrupavel(os: { status: string | null | undefined; signed_at?: string | null } | null | undefined): boolean {
  return !!os && agrupavel(os.status) && !os.signed_at;
}

/** O que o banco diz de UMA OS agrupada (os_para_agrupar → agrupados_ativos): dá para desagrupar e, se não, por quê. */
export type DesagrupavelPeloBanco = { podeDesagrupar: boolean; motivo: string | null };

/**
 * Lê `agrupados_ativos[id = agrupadoId]` de os_para_agrupar (Json) sem confiar na forma. É a MESMA régua do
 * desagrupar_os e da guarda que recusa cancelar a agrupada (_os_impedimento_para_desagrupar): hora apontada,
 * foto, despesa, nota, assinatura, dinheiro lançado depois de agrupar… null = a leitura não diz (a agrupada
 * não está na lista, ou a forma veio errada): a tela cai no palpite osAgrupadaDesagrupavel.
 */
export function desagrupavelPeloBanco(json: unknown, agrupadoId: string): DesagrupavelPeloBanco | null {
  const lista = (json as { agrupados_ativos?: unknown } | null)?.agrupados_ativos;
  if (!Array.isArray(lista)) return null;
  for (const item of lista) {
    const a = item as { id?: unknown; pode_desagrupar?: unknown; motivo?: unknown };
    if (a?.id !== agrupadoId || typeof a.pode_desagrupar !== 'boolean') continue;
    return {
      podeDesagrupar: a.pode_desagrupar,
      motivo: !a.pode_desagrupar && typeof a.motivo === 'string' && a.motivo.trim() ? a.motivo : null,
    };
  }
  return null;
}

/** O que o banco diz de cada OS (os_para_agrupar): entra ou não, e a frase exata de por que não. */
export type LeituraDoBanco = Map<string, { elegivel: boolean; motivo: string | null }>;

/** Lê o `os` de os_para_agrupar (Json) sem confiar na forma: o que não tiver id e elegivel fica de fora. */
export function leituraDoBanco(json: unknown): LeituraDoBanco {
  const mapa: LeituraDoBanco = new Map();
  const lista = (json as { os?: unknown } | null)?.os;
  if (!Array.isArray(lista)) return mapa;
  for (const item of lista) {
    const o = item as { id?: unknown; elegivel?: unknown; motivo?: unknown };
    if (typeof o?.id !== 'string' || typeof o.elegivel !== 'boolean') continue;
    mapa.set(o.id, { elegivel: o.elegivel, motivo: typeof o.motivo === 'string' && o.motivo.trim() ? o.motivo : null });
  }
  return mapa;
}

export const PALAVRAS_DE_OS: PalavrasDoAgrupamento = {
  todos: 'as OS',
  noAgrupado: 'na agrupada',
  inteiro: 'a OS inteira',
  deCadaUm: 'de cada uma',
  maisDeUm: 'Mais de uma OS',
  emUmSo: 'em uma só',
};

/** Diferenças entre as OS (comissão, condição de pagamento, desconto, imposto, deslocamento em duas). */
export function diferencasEntreOs(cs: ReadonlyArray<CandidataOs>): string[] {
  return diferencasAoAgrupar(cs, PALAVRAS_DE_OS);
}

const listaDeNumeros = (cs: ReadonlyArray<Pick<CandidataOs, 'service_order_number'>>) =>
  cs.map((c) => c.service_order_number).join(', ');

const dataEHora = (iso: string) =>
  new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' });

/**
 * Avisos que não impedem nada, mas que o dono precisa ler antes (os mesmos que o banco devolve depois de
 * agrupar): a assinatura do cliente fica na OS que ele assinou (a nova nasce sem); a OS nova fica com a
 * situação e a data de atendimento da PRINCIPAL; e a regra da nota fiscal de serviço para a OS juntada.
 */
export function avisosDaOsNova(cs: ReadonlyArray<CandidataOs>, principalId?: string): string[] {
  if (cs.length < 2) return [];
  const avisos: string[] = [];
  const principal = cs.find((c) => c.id === principalId) ?? null;
  const assinadas = cs.filter((c) => !!c.signed_at);
  if (assinadas.length === 1) {
    avisos.push(
      `${assinadas[0]!.service_order_number} foi assinada pelo cliente: a assinatura fica nela, como histórico. A OS nova nasce sem assinatura; se precisar, peça uma nova ao cliente.`,
    );
  } else if (assinadas.length > 1) {
    avisos.push(
      `${listaDeNumeros(assinadas)} foram assinadas pelo cliente: as assinaturas ficam nas OS originais, como histórico. A OS nova nasce sem assinatura; se precisar, peça uma nova ao cliente.`,
    );
  }
  if (principal && new Set(cs.map((c) => c.status)).size > 1) {
    avisos.push(`As OS estão em situações diferentes: a OS nova fica com a situação da principal (${principal.service_order_number}).`);
  }
  if (principal) {
    const outraData = cs.filter(
      (c) => c.id !== principal.id && c.scheduled_start_at && c.scheduled_start_at !== principal.scheduled_start_at,
    );
    if (outraData.length > 0) {
      avisos.push(
        `Tem atendimento marcado em outra data: ${outraData.map((c) => `${c.service_order_number} (${dataEHora(c.scheduled_start_at!)})`).join(', ')}. A OS nova fica com a data da principal (${principal.service_order_number}): confira a agenda.`,
      );
    }
  }
  avisos.push(
    'Nota fiscal: uma NFS-e cobre um tomador, um código de serviço e uma competência. Se os serviços juntados tiverem códigos diferentes, a OS nova vai precisar de mais de uma nota.',
  );
  return avisos;
}

const centavos = (v: number | null | undefined) => Math.round((Number(v) || 0) * 100);

/** Recebível que conta: o cancelado não vai a lugar nenhum (o banco só move os ativos). */
export const recebivelAtivo = (r: Pick<RecebivelDaPrevia, 'status'>) => r.status !== 'cancelled';

/** Quanto dinheiro acompanha: total lançado, já recebido e quanto disso é sinal (em reais, somado em centavos). */
export function resumoDosRecebiveis(rs: ReadonlyArray<RecebivelDaPrevia>): {
  quantidade: number;
  total: number;
  recebido: number;
  emAberto: number;
} {
  const ativos = rs.filter(recebivelAtivo);
  const total = ativos.reduce((t, r) => t + centavos(r.amount), 0);
  const recebido = ativos.reduce((t, r) => t + Math.min(centavos(r.paid_amount), centavos(r.amount)), 0);
  return { quantidade: ativos.length, total: total / 100, recebido: recebido / 100, emAberto: (total - recebido) / 100 };
}

/** "Sinal de R$ 1.000,00 · pago", "Conta a receber de R$ 2.839,50 · em aberto". */
export function rotuloDoRecebivel(r: RecebivelDaPrevia): string {
  const tipo = r.is_deposit ? 'Sinal' : 'Conta a receber';
  const pago = centavos(r.paid_amount);
  const situacao =
    r.status === 'paid' ? 'pago'
    : pago > 0 ? `${emReais(pago / 100)} recebido`
    : r.status === 'overdue' ? 'vencido'
    : 'em aberto';
  return `${tipo} de ${emReais(Number(r.amount) || 0)} · ${situacao}`;
}
