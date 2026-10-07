/**
 * O que a tela deixa fazer com uma ordem de compra, conforme a situação dela (07/10/2026).
 *
 * As mesmas travas das ferramentas do assistente (supabase/functions/_shared/ai/tools/compras-ciclo.ts):
 *  · mudar a situação pelo menu: só rascunho ↔ enviada ↔ cancelada — "recebida" e "recebida em parte"
 *    só pelo recebimento (receive_po), que dá entrada no estoque e cria a conta a pagar;
 *  · cancelar: só rascunho ou enviada, sem nada recebido — o que chegou já está no estoque e a conta a
 *    pagar só nasce quando tudo chega: cancelar uma recebida em parte deixaria a compra sem conta;
 *  · excluir: só rascunho, sem nada recebido — para desistir de uma enviada, cancela-se (fica a trilha);
 *  · editar (fornecedor, previsão, itens): só rascunho ou enviada.
 * Recebida não muda mais de situação.
 *
 * Antes, a lista deixava cancelar e excluir OC recebida (o estoque e a conta a pagar ficavam sem a OC
 * de origem) e o diálogo Editar mudava a situação de qualquer OC para qualquer outra, até "recebida".
 */
import type { POStatus } from '@/hooks/use-purchase-orders';

interface OcParaTravar {
  status: POStatus;
  purchase_order_items?: Array<{ received_qty: number | null }> | null;
}

const MANUAIS: POStatus[] = ['draft', 'sent', 'cancelled'];

const temRecebido = (oc: OcParaTravar) => (oc.purchase_order_items ?? []).some((i) => Number(i.received_qty ?? 0) > 0);

/** Situações para onde o menu pode levar a OC (sem a atual). */
export function situacoesPermitidas(oc: OcParaTravar): POStatus[] {
  if (!MANUAIS.includes(oc.status) || temRecebido(oc)) return [];
  return MANUAIS.filter((s) => s !== oc.status);
}

export function podeCancelar(oc: OcParaTravar): boolean {
  return (oc.status === 'draft' || oc.status === 'sent') && !temRecebido(oc);
}

export function podeExcluir(oc: OcParaTravar): boolean {
  return oc.status === 'draft' && !temRecebido(oc);
}

export function podeEditar(oc: OcParaTravar): boolean {
  return oc.status === 'draft' || oc.status === 'sent';
}

/** Por que não dá — o texto que a tela mostra no lugar da ação. */
export function motivoDaTrava(oc: OcParaTravar, acao: 'editar' | 'excluir' | 'cancelar'): string | null {
  if (acao === 'editar' && podeEditar(oc)) return null;
  if (acao === 'excluir' && podeExcluir(oc)) return null;
  if (acao === 'cancelar' && podeCancelar(oc)) return null;
  if (oc.status === 'received') return 'Toda recebida: o que chegou está no estoque e a conta a pagar já existe.';
  if (oc.status === 'partial' || temRecebido(oc)) {
    return 'Recebida em parte: o que chegou está no estoque e a conta a pagar só nasce quando tudo chegar — receba o resto.';
  }
  if (oc.status === 'cancelled') return acao === 'editar' ? 'Cancelada: volte para rascunho para editar.' : 'Já está cancelada.';
  if (acao === 'excluir') return 'Só rascunho se exclui. Para desistir de uma enviada, cancele.';
  return null;
}
