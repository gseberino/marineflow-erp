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
 * Escreve na tabela base, nunca na view. O `bank_transaction_id` tem índice único parcial
 * nas duas tabelas, então uma linha do extrato não pode ser usada duas vezes — o banco
 * recusa antes de qualquer dano.
 */
export function useConciliarLancamento() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { lado: LadoDoLancamento; id: string; bankTransactionId: string }) => {
      const tabela = v.lado === 'payable' ? 'payables' : 'receivables';
      const { error } = await supabase
        .from(tabela)
        .update({ bank_transaction_id: v.bankTransactionId } as never)
        .eq('id', v.id);
      if (error) throw error;

      // A linha do extrato sai da fila do Extrato porque agora tem lançamento — isso já é
      // derivado pela view. Marcar `reconciled` mantém as telas antigas coerentes enquanto
      // elas existirem.
      const { error: erroTx } = await supabase
        .from('bank_transactions')
        .update({ reconciled: true } as never)
        .eq('id', v.bankTransactionId);
      if (erroTx) throw erroTx;
    },
    onSuccess: () => {
      for (const k of [
        ['conciliacao-sem-extrato'], ['conciliacao-conciliados'], ['conciliacao-extrato-livre'],
        ['extrato-a-tratar'], ['finance-review-count'], ['bank-transactions'],
      ]) qc.invalidateQueries({ queryKey: k });
      toast.success('Conciliado');
    },
    onError: (e: Error) => {
      // O índice único devolve 23505 quando a linha do extrato já foi usada. Sem esta
      // tradução o gestor vê "duplicate key value violates unique constraint".
      const jaUsada = /duplicate key|23505/i.test(e.message);
      toast.error(jaUsada
        ? 'Essa linha do extrato já está vinculada a outro lançamento.'
        : `Não deu para conciliar: ${e.message}`);
    },
  });
}

/** Desfaz o vínculo — sem isso um casamento errado é permanente. */
export function useDesconciliarLancamento() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { lado: LadoDoLancamento; id: string; bankTransactionId: string }) => {
      const tabela = v.lado === 'payable' ? 'payables' : 'receivables';
      const { error } = await supabase
        .from(tabela)
        .update({ bank_transaction_id: null } as never)
        .eq('id', v.id);
      if (error) throw error;

      // Devolve a linha à fila do Extrato. Só mexe em `reconciled` — `dismissed_reason`
      // fica como está, porque desfazer conciliação não é o mesmo que tirar do descarte.
      const { error: erroTx } = await supabase
        .from('bank_transactions')
        .update({ reconciled: false, reconciled_payment_id: null } as never)
        .eq('id', v.bankTransactionId);
      if (erroTx) throw erroTx;
    },
    onSuccess: () => {
      for (const k of [
        ['conciliacao-sem-extrato'], ['conciliacao-conciliados'], ['conciliacao-extrato-livre'],
        ['extrato-a-tratar'], ['finance-review-count'], ['bank-transactions'],
      ]) qc.invalidateQueries({ queryKey: k });
      toast.success('Vínculo desfeito — a linha voltou para o Extrato');
    },
    onError: (e: Error) => toast.error(`Não deu para desfazer: ${e.message}`),
  });
}
