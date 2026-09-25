// Conciliação vista do lado certo: parte do LANÇAMENTO, não do extrato.
//
// "Conciliação bancária eu faço com tudo aquilo que eu lancei no sistema e vou comparar com
//  o extrato. E não o inverso." — e é assim que QuickBooks (Reconcile), NetSuite (Reconcile
//  Account Statement) e Odoo tratam o assunto: a fila do extrato é uma tela, a conferência
//  do que foi registrado é outra.
//
// A tela antiga listava toda linha do extrato ainda não tratada e chamava isso de
// conciliação. Este hook lê `conciliacao_lancamentos`, que tem uma linha por lançamento e
// diz se ele achou par no banco.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { recarregarFinanceiro, mensagemDoErro, type RespostaDoLancamento } from '@/hooks/use-lancamentos';

export type LadoDoLancamento = 'payable' | 'receivable';
export type SituacaoDaConciliacao = 'conciliado' | 'sem_extrato';

export interface LancamentoParaConciliar {
  lado: LadoDoLancamento;
  id: string;
  description: string | null;
  amount: number;
  status: string | null;
  due_date: string | null;
  issue_date: string | null;
  contraparte: string | null;
  categoria: string | null;
  bank_transaction_id: string | null;
  situacao: SituacaoDaConciliacao;
  extrato_data: string | null;
  extrato_valor: number | null;
  extrato_descricao: string | null;
  /** lançamento − extrato. Só existe quando há par. */
  diferenca: number | null;
  /**
   * Nasceu da aprovação de uma linha do extrato (e não foi só casado com ela). Muda o que
   * "desfazer" significa: o que nasceu é cancelado e a linha volta para a fila; o que já
   * existia só perde o vínculo.
   */
  nasceu_do_extrato?: boolean;
}

/** Uma linha do extrato ainda sem lançamento — o outro lado da conciliação. */
export interface LinhaDoExtratoLivre {
  id: string;
  transaction_date: string;
  description: string | null;
  amount: number;
  transaction_type: 'credit' | 'debit';
  counterparty_name: string | null;
  counterparty_document: string | null;
  e_cartao: boolean;
}

/**
 * Lançamentos sem par no extrato — onde mora o trabalho de verdade.
 *
 * Medido em 09/08/2026: 26 contas a pagar e 23 a receber sem vínculo, sendo que 16 dos
 * recebíveis estão marcados como PAGOS. O dinheiro entrou no banco, alguém deu baixa no
 * sistema, e os dois lados nunca se encontraram.
 */
export function useLancamentosSemExtrato(lado?: LadoDoLancamento) {
  return useQuery({
    queryKey: ['conciliacao-sem-extrato', lado ?? 'todos'],
    queryFn: async (): Promise<LancamentoParaConciliar[]> => {
      let q = supabase
        .from('conciliacao_lancamentos' as never)
        .select('*')
        .eq('situacao', 'sem_extrato');
      if (lado) q = q.eq('lado', lado);

      // Ordem estável: o PostgREST corta em 1000 linhas em silêncio, e sem ordem definida
      // a página 2 pode repetir a 1. Data primeiro, id como desempate.
      const { data, error } = await q
        .order('due_date', { ascending: false, nullsFirst: false })
        .order('id', { ascending: true })
        .limit(500);
      if (error) throw error;
      return (data ?? []) as unknown as LancamentoParaConciliar[];
    },
    staleTime: 30_000,
  });
}

/** Já conciliados — para conferir, e para achar diferença de valor que passou batido. */
export function useLancamentosConciliados(apenasComDiferenca = false) {
  return useQuery({
    queryKey: ['conciliacao-conciliados', apenasComDiferenca],
    queryFn: async (): Promise<LancamentoParaConciliar[]> => {
      let q = supabase
        .from('conciliacao_lancamentos' as never)
        .select('*')
        .eq('situacao', 'conciliado');
      // `neq(0)` sozinho descartaria os nulos junto; aqui diferença nula não existe entre
      // conciliados, mas deixar explícito evita surpresa se a view mudar.
      if (apenasComDiferenca) q = q.neq('diferenca', 0);

      const { data, error } = await q
        .order('extrato_data', { ascending: false, nullsFirst: false })
        .order('id', { ascending: true })
        .limit(500);
      if (error) throw error;
      return (data ?? []) as unknown as LancamentoParaConciliar[];
    },
    staleTime: 30_000,
  });
}

/**
 * Linhas do extrato ainda livres, para oferecer como par.
 *
 * Filtra por sinal: um lançamento a pagar só pode casar com débito, um a receber só com
 * crédito. Sem isso a lista de candidatos vira ruído — e o erro de casar entrada com saída
 * é silencioso, porque o valor bate.
 */
export function useExtratoLivre(paraLado: LadoDoLancamento | null) {
  return useQuery({
    enabled: paraLado != null,
    queryKey: ['conciliacao-extrato-livre', paraLado],
    queryFn: async (): Promise<LinhaDoExtratoLivre[]> => {
      const { data, error } = await supabase
        .from('extrato_a_tratar' as never)
        .select('id, transaction_date, description, amount, transaction_type, counterparty_name, counterparty_document, e_cartao')
        .eq('transaction_type', paraLado === 'payable' ? 'debit' : 'credit')
        .order('transaction_date', { ascending: false })
        .order('id', { ascending: true })
        .limit(300);
      if (error) throw error;
      return (data ?? []) as unknown as LinhaDoExtratoLivre[];
    },
    staleTime: 30_000,
  });
}

/**
 * Casa um lançamento com uma linha do extrato.
 *
 * Passa pela função do banco `conciliar_lancamento`, a mesma que o assistente usa. Ela
 * confere o sinal (a pagar só com saída, a receber só com entrada), recusa linha já usada
 * ou fora da fila, grava na trilha — e, se a conta está em ABERTO, registra o pagamento na
 * data do extrato. Antes o casamento só gravava o vínculo, e a conta continuava "pendente"
 * com o dinheiro já fora do banco.
 */
export function useConciliarLancamento() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { lado: LadoDoLancamento; id: string; bankTransactionId: string }) => {
      const { data, error } = await supabase.rpc('conciliar_lancamento' as never, {
        p_tipo: v.lado, p_id: v.id, p_transacao: v.bankTransactionId,
      } as never);
      if (error) throw error;
      return data as unknown as RespostaDoLancamento;
    },
    onSuccess: (r) => {
      recarregarFinanceiro(qc);
      toast.success(r?.message ?? 'Conciliado');
    },
    onError: (e: Error) => toast.error(`Não deu para conciliar: ${mensagemDoErro(e)}`),
  });
}

/**
 * Desfaz o vínculo — sem isso um casamento errado é permanente.
 *
 * Mesma função do "Desfazer aprovação" das contas: se o lançamento NASCEU da linha do
 * extrato, ele é cancelado e a proposta volta para a fila (soltar só o vínculo deixaria uma
 * despesa paga sem banco, e a próxima varredura proporia a mesma despesa de novo). Se ele
 * já existia, perde o vínculo e o pagamento que o casamento registrou é estornado.
 */
export function useDesconciliarLancamento() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { lado: LadoDoLancamento; id: string; bankTransactionId: string }) => {
      const { data, error } = await supabase.rpc('desfazer_aprovacao' as never, {
        p_tipo: v.lado, p_id: v.id, p_motivo: 'Desfeito na Conciliação',
      } as never);
      if (error) throw error;
      return data as unknown as RespostaDoLancamento;
    },
    onSuccess: (r) => {
      recarregarFinanceiro(qc);
      toast.success(r?.message ?? 'Vínculo desfeito — a linha voltou para o Extrato');
    },
    onError: (e: Error) => toast.error(`Não deu para desfazer: ${mensagemDoErro(e)}`),
  });
}
