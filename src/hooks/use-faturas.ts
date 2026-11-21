// Fatura FAT-N do "Fechar juntas" (Fase 1, 20/11/2026): leitura e ações da tela.
//
// Tudo passa pelas funções do banco (migration 20270220100000): fatura_criar, fatura_receber,
// fatura_desfazer e fatura_desfazer_recebimento. A tela não grava em invoices/receivables/payments —
// e nem conseguiria: as contas de uma fatura ficam travadas no banco (só as funções da fatura mexem).
// Receber reaproveita o caminho de sempre: o Pix é uma linha do Extrato aplicada pelo "Este Pix paga"
// (aplicar_entrada_em_contas), o dinheiro é o "Registrar pagamento" (register_payment_and_update_balance).
// Leitura que falha LANÇA (nada de "sem fatura" por erro).
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { mensagemDoErro, recarregarFinanceiro } from '@/hooks/use-lancamentos';

export interface FaturaResumo {
  id: string;
  numero: string;
  clientId: string;
  status: 'open' | 'paid' | 'cancelled';
  vencimento: string | null;
  total: number;
  recebido: number;
  saldo: number;
  contas: number;
  os: string[];
  criadaEm: string;
}

interface RespostaDaFatura {
  ok?: boolean;
  message?: string;
  fatura_id?: string;
  numero?: string;
  criada?: boolean;
  saldo?: number;
}

async function chamar(nome: string, args: Record<string, unknown>): Promise<RespostaDaFatura> {
  const { data, error } = await supabase.rpc(nome as never, args as never);
  if (error) throw error;
  return (data ?? {}) as RespostaDaFatura;
}

/** As faturas abertas e quitadas do cliente (as desfeitas ficam de fora), da mais nova para a mais velha. */
export function useFaturasDoCliente(clienteId: string | null | undefined, enabled = true) {
  return useQuery({
    queryKey: ['faturas', 'cliente', clienteId],
    enabled: enabled && !!clienteId,
    queryFn: async (): Promise<FaturaResumo[]> => {
      const { data, error } = await supabase.from('faturas_resumo')
        .select('id, numero, client_id, status, vencimento, total, recebido, saldo, contas, os, created_at')
        .eq('client_id', clienteId!)
        .in('status', ['open', 'paid'])
        .order('created_at', { ascending: false });
      if (error) throw new Error(`Não consegui ler as faturas do cliente: ${error.message}`);
      return (data ?? []).map((f) => ({
        id: String(f.id),
        numero: String(f.numero),
        clientId: String(f.client_id),
        status: (f.status ?? 'open') as FaturaResumo['status'],
        vencimento: f.vencimento ?? null,
        total: Number(f.total ?? 0),
        recebido: Number(f.recebido ?? 0),
        saldo: Number(f.saldo ?? 0),
        contas: Number(f.contas ?? 0),
        os: f.os ?? [],
        criadaEm: String(f.created_at),
      }));
    },
    staleTime: 30 * 1000,
  });
}

export interface RecebimentoDaFatura {
  pagamentoId: string;
  valor: number;
  data: string;
  /** Veio de uma linha do Extrato (Pix/transferência) ou foi lançado à mão (dinheiro). */
  doExtrato: boolean;
  descricao: string;
}

/** O que entrou pela fatura: os pagamentos confirmados das contas dela feitos depois de ela nascer. */
export function useRecebimentosDaFatura(faturaId: string | null | undefined, criadaEm: string | null | undefined) {
  return useQuery({
    queryKey: ['faturas', 'recebimentos', faturaId],
    enabled: !!faturaId && !!criadaEm,
    queryFn: async (): Promise<RecebimentoDaFatura[]> => {
      const { data, error } = await supabase.from('payments')
        .select('id, amount, payment_date, bank_transaction_id, receivables!inner(invoice_id, description)')
        .eq('receivables.invoice_id', faturaId!)
        .eq('status', 'confirmed')
        .gte('created_at', criadaEm!)
        .order('payment_date', { ascending: true });
      if (error) throw new Error(`Não consegui ler os recebimentos da fatura: ${error.message}`);
      return ((data ?? []) as unknown as Array<{
        id: string; amount: number; payment_date: string; bank_transaction_id: string | null;
        receivables: { description: string | null } | null;
      }>).map((p) => ({
        pagamentoId: p.id,
        valor: Number(p.amount),
        data: p.payment_date,
        doExtrato: !!p.bank_transaction_id,
        descricao: p.receivables?.description ?? 'Conta a receber',
      }));
    },
  });
}

function recarregar(qc: ReturnType<typeof useQueryClient>) {
  recarregarFinanceiro(qc);
  qc.invalidateQueries({ queryKey: ['faturas'] });
  qc.invalidateQueries({ queryKey: ['collections'] });
}

/**
 * Cria a fatura das contas (ou devolve a aberta com exatamente essas contas). Usada pelo Cobrar juntas
 * antes do envio, para o número entrar na mensagem. LANÇA com a frase do banco (nada é enviado).
 */
export async function criarFaturaParaCobrar(clienteId: string, contaIds: string[]): Promise<{ id: string; numero: string; criada: boolean }> {
  const r = await chamar('fatura_criar', { p_cliente: clienteId, p_contas: contaIds });
  if (!r.fatura_id || !r.numero) throw new Error('O banco não devolveu a fatura.');
  return { id: r.fatura_id, numero: r.numero, criada: !!r.criada };
}

/** Receber a fatura: a linha do Extrato (Pix) ou o valor em dinheiro, com o dia. */
export function useReceberFatura() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { faturaId: string; transacaoId?: string | null; valor?: number | null; data?: string | null }) =>
      chamar('fatura_receber', {
        p_fatura: v.faturaId,
        p_transacao: v.transacaoId ?? null,
        p_valor: v.transacaoId ? null : v.valor ?? null,
        p_data: v.transacaoId ? null : v.data ?? null,
      }),
    onSuccess: (r) => { recarregar(qc); if (r.message) toast.success(r.message); },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

/** Desfaz a fatura (só se nada entrou por ela): as contas voltam a ser cobradas cada uma pela sua OS. */
export function useDesfazerFatura() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { faturaId: string; motivo?: string | null }) =>
      chamar('fatura_desfazer', { p_fatura: v.faturaId, p_motivo: v.motivo ?? null }),
    onSuccess: (r) => { recarregar(qc); if (r.message) toast.success(r.message); },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

/** Desfaz um recebimento que entrou pela fatura (o Pix volta para a fila do Extrato; o dinheiro é estornado). */
export function useDesfazerRecebimentoDaFatura() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { pagamentoId: string; motivo?: string | null }) =>
      chamar('fatura_desfazer_recebimento', { p_pagamento: v.pagamentoId, p_motivo: v.motivo ?? null }),
    onSuccess: (r) => { recarregar(qc); if (r.message) toast.success(r.message); },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}
