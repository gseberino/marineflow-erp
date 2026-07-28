import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

/** Espelha os tipos de `supabase/functions/_shared/banking/types.ts`. */
export type CandidateKind =
  | 'receivable' | 'payable' | 'collection' | 'quote_deposit'
  | 'service_order_balance' | 'existing_payment';

export interface ReconcileCandidate {
  kind: CandidateKind;
  id: string;
  label: string;
  amount: number;
  direction: 'credit' | 'debit';
  dueDate?: string | null;
  referenceDate?: string | null;
  clientId?: string | null;
  clientName?: string | null;
  clientDocument?: string | null;
  documentNumber?: string | null;
  serviceOrderId?: string | null;
  convertsQuote?: boolean;
  /**
   * "condicao" = combinado no orçamento; "padrao" = condição padrão da casa
   * (100% materiais + 50% mão de obra); "percentual" = estimativa liso sobre o total.
   */
  amountSource?: 'condicao' | 'padrao' | 'percentual';
  conditionLabel?: string | null;
}

export interface ReconcileSuggestion {
  candidate: ReconcileCandidate;
  score: number;
  tier: 'certain' | 'probable' | 'weak';
  reasons: { signal: string; detail: string; points: number }[];
  difference: number;
  autoApply: boolean;
}

/** Um depósito só que paga várias contas do mesmo cliente. */
export interface ReconcileGroup {
  candidates: ReconcileCandidate[];
  total: number;
  difference: number;
  clientName: string | null;
  detail: string;
}

export interface ReconcileResponse {
  transactions: {
    transaction: { id: string };
    suggestions: ReconcileSuggestion[];
    groups?: ReconcileGroup[];
    /** Dinheiro circulando entre contas da própria empresa: não é receita nem despesa. */
    internalTransfer?: boolean;
  }[];
  applied: { transaction_id: string; candidate: ReconcileCandidate; message: string }[];
  summary: {
    pendentes: number; conciliadas: number; sugeridas: number;
    sem_candidato: number; candidatos_avaliados?: number;
  };
}

/**
 * Chama a função e devolve a mensagem REAL quando ela recusa a operação.
 *
 * `functions.invoke` entrega apenas "Edge Function returned a non-2xx status code" em
 * qualquer erro HTTP — o motivo fica no corpo da resposta. Sem ler esse corpo, quem está
 * conciliando vê "erro na edge function" e não tem como saber que faltou permissão, que a
 * transação já estava conciliada ou que o valor não bate.
 */
async function invokeReconcile<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke('banking-reconcile', { body });

  if (error) {
    const resposta = (error as any)?.context as Response | undefined;
    if (resposta && typeof resposta.json === 'function') {
      try {
        const corpo = await resposta.json();
        if (corpo?.error) throw new Error(String(corpo.error));
      } catch (e) {
        if (e instanceof Error && e.message && !e.message.includes('non-2xx')) throw e;
      }
    }
    throw error;
  }

  if ((data as any)?.error) throw new Error((data as any).error);
  return data as T;
}

async function callReconcile(body: Record<string, unknown>): Promise<ReconcileResponse> {
  return invokeReconcile<ReconcileResponse>(body);
}

/**
 * Sugestões do motor para todas as transações pendentes.
 * Fica em cache curto porque conciliar uma transação muda os candidatos das outras
 * (uma conta baixada deixa de ser candidata).
 */
export function useReconcileSuggestions(enabled = true) {
  return useQuery({
    queryKey: ['reconcile-suggestions'],
    queryFn: () => callReconcile({ action: 'suggest' }),
    enabled,
    staleTime: 30_000,
  });
}

/** Roda as camadas e concilia sozinho apenas o que é certeza. */
export function useAutoReconcile() {
  const qc = useQueryClient();
  return useMutation<ReconcileResponse, Error, boolean>({
    mutationFn: (dryRun: boolean) => callReconcile({ action: 'auto', dry_run: dryRun }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
      qc.invalidateQueries({ queryKey: ['reconcile-suggestions'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
      qc.invalidateQueries({ queryKey: ['payments'] });
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: ['financial-summary'] });
    },
  });
}

/**
 * Aplica uma sugestão escolhida na tela.
 *
 * Passa pela edge function em vez de escrever daqui para que exista um único caminho de
 * escrita no financeiro — o mesmo que a conciliação automática e o agente usam — e para
 * que toda confirmação alimente a memória de conciliação. Sinal de orçamento continua
 * passando pela rotina do botão "Receber sinal", então o gatilho que aprova o orçamento
 * dispara igual.
 */
export function useApplySuggestion() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: { transactionId: string; candidate: ReconcileCandidate }) =>
      invokeReconcile<{ ok: boolean; message: string }>({
        action: 'apply',
        transaction_id: input.transactionId,
        candidate: input.candidate,
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
      qc.invalidateQueries({ queryKey: ['reconcile-suggestions'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
      qc.invalidateQueries({ queryKey: ['payments'] });
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: ['financial-summary'] });
    },
  });
}

/** Baixa de uma vez as contas que juntas somam o depósito, cada uma pelo próprio valor. */
export function useApplyGroup() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: { transactionId: string; candidates: ReconcileCandidate[] }) =>
      invokeReconcile<{ ok: boolean; message: string; feitos: string[]; falhas: string[] }>({
        action: 'apply_group',
        transaction_id: input.transactionId,
        candidates: input.candidates,
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
      qc.invalidateQueries({ queryKey: ['reconcile-suggestions'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
      qc.invalidateQueries({ queryKey: ['payments'] });
      qc.invalidateQueries({ queryKey: ['financial-summary'] });
    },
  });
}

/**
 * Manda uma transação específica para o agente analisar.
 *
 * Serve para quando o motor não achou nada: o agente enxerga o que regra nenhuma alcança
 * — conversas de WhatsApp, histórico do cliente, orçamentos em negociação. Ele responde
 * com a leitura dele; registrar o dinheiro continua sendo ação explícita de quem lê.
 */
export function useAnalyzeWithAI() {
  return useMutation({
    mutationFn: async (input: { transactionId: string; description: string; amount: number; date: string }) => {
      const pergunta =
        `Analise esta entrada do extrato bancário que não foi identificada automaticamente: ` +
        `${input.date}, valor R$ ${input.amount.toFixed(2)}, histórico "${input.description}". ` +
        `Use sugerir_conciliacao com transaction_id ${input.transactionId} e cruze com o que você ` +
        `souber de conversas, orçamentos em aberto e histórico dos clientes. Responda em no máximo ` +
        `4 linhas: do que provavelmente se trata, de qual cliente, e o que confirmar. Não concilie nada.`;

      const { data, error } = await supabase.functions.invoke('ai-agent', {
        body: { messages: [{ role: 'user', content: pergunta }] },
      });
      if (error) throw error;
      const resposta = (data as any)?.reply ?? (data as any)?.message ?? (data as any)?.content;
      if (!resposta) throw new Error('O agente não retornou uma análise.');
      return String(resposta);
    },
  });
}

export interface ReconciliationHealth {
  total: number;
  conciliadas: number;
  pendentes: number;
  /** Percentual do extrato já explicado. */
  taxa: number;
  valorPendente: number;
  /** Dias desde a transação pendente mais antiga. */
  diasMaisAntiga: number | null;
  /** Padrões de histórico bancário que o sistema já aprendeu. */
  padroesAprendidos: number;
}

/**
 * Saúde da conciliação: quanto do extrato já está explicado, o que está encalhado e há
 * quanto tempo. É a métrica que diz se a rotina está em dia — e o número de padrões
 * aprendidos mostra o motor ficando melhor com o uso, que de outro modo é invisível.
 */
export function useReconciliationHealth() {
  return useQuery({
    queryKey: ['reconciliation-health'],
    queryFn: async (): Promise<ReconciliationHealth> => {
      const [todas, memoria] = await Promise.all([
        supabase.from('bank_transactions').select('amount, reconciled, transaction_date'),
        supabase.from('reconciliation_memory').select('id', { count: 'exact', head: true }),
      ]);

      const linhas = todas.data || [];
      const pendentes = linhas.filter(l => !l.reconciled);
      const conciliadas = linhas.length - pendentes.length;

      let diasMaisAntiga: number | null = null;
      if (pendentes.length > 0) {
        const maisAntiga = pendentes.reduce((min, l) =>
          String(l.transaction_date) < min ? String(l.transaction_date) : min,
          String(pendentes[0].transaction_date));
        diasMaisAntiga = Math.floor(
          (Date.now() - new Date(`${maisAntiga}T12:00:00`).getTime()) / 86400000,
        );
      }

      return {
        total: linhas.length,
        conciliadas,
        pendentes: pendentes.length,
        taxa: linhas.length > 0 ? Math.round((conciliadas / linhas.length) * 100) : 0,
        valorPendente: pendentes.reduce((s, l) => s + Number(l.amount || 0), 0),
        diasMaisAntiga,
        padroesAprendidos: memoria.count ?? 0,
      };
    },
    staleTime: 60_000,
  });
}

/** Rótulo curto do tipo de candidato, para a etiqueta na sugestão. */
export const CANDIDATE_LABELS: Record<CandidateKind, string> = {
  receivable: 'Conta a receber',
  payable: 'Conta a pagar',
  collection: 'Cobrança',
  quote_deposit: 'Sinal de orçamento',
  service_order_balance: 'Saldo de OS',
  existing_payment: 'Pagamento já registrado',
};
