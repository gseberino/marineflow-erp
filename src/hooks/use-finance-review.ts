// Caixa de entrada financeira: propostas do sistema aguardando decisão do gestor.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

/** Acima deste valor a proposta sai do lote e exige olhar individual (decisão do usuário). */
export const LIMITE_LOTE = 500;

export interface PropostaFinanceira {
  id: string;
  kind: 'create_payable' | 'create_receivable' | 'internal_transfer' | 'categorize' | 'anomaly';
  status: 'pending' | 'approved' | 'rejected' | 'superseded';
  bank_transaction_id: string | null;
  related_transaction_id: string | null;
  title: string;
  reasoning: string | null;
  confidence: number;
  suggested_amount: number | null;
  suggested_date: string | null;
  suggested_category: string | null;
  suggested_description: string | null;
  suggested_supplier_id: string | null;
  dre_group: string | null;
  /** Regra que classificou esta proposta — permite auditar a regra pelo resultado. */
  applied_rule_id: string | null;
  suggested_payee_id: string | null;
  suggested_service_order_id: string | null;
  suggested_purchase_order_id: string | null;
  created_at: string;
  /** Identificação vinda do extrato, para decidir sem abrir o internet banking. */
  bank_transactions?: {
    counterparty_name: string | null;
    counterparty_document: string | null;
    counterparty_bank: string | null;
    counterparty_branch: string | null;
    counterparty_account: string | null;
    payment_method: string | null;
    payment_reason: string | null;
    merchant_name: string | null;
    merchant_document: string | null;
    installment_label: string | null;
    pix_end_to_end_id: string | null;
    description: string | null;
    /** 'bank' = conta corrente, 'credit_card' = fatura. Muda onde se confere o gasto. */
    source_type: string | null;
    /** Id da transação no provedor — é a chave que impede a mesma entrar duas vezes. */
    bank_ref_id: string | null;
  } | null;
}

export interface Correcao {
  category?: string;
  description?: string;
  amount?: number;
  date?: string;
  /** A quem a despesa pertence, quando não é a um fornecedor (sócio, diarista, prestador). */
  payeeId?: string | null;
  /** OS a que a compra pertence — é o que dá custo e margem reais por serviço. */
  serviceOrderId?: string | null;
  /** OC que este pagamento quita. */
  purchaseOrderId?: string | null;
}

/**
 * Mesma leitura de corpo de erro usada na conciliação: `functions.invoke` devolve só
 * "non-2xx status code", e o motivo real (fornecedor inválido, cliente faltando) fica no
 * corpo. Sem isto o gestor vê "erro" e não sabe o que corrigir.
 */
async function invokeReview<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke('finance-review', { body });

  if (error) {
    const resposta = (error as any)?.context as Response | undefined;
    if (resposta && typeof resposta.json === 'function') {
      try {
        const corpo = await resposta.json();
        if (corpo?.error) {
          throw new Error(corpo.detail ? `${corpo.error}: ${corpo.detail}` : String(corpo.error));
        }
      } catch (e) {
        if (e instanceof Error && e.message && !e.message.includes('non-2xx')) throw e;
      }
    }
    throw error;
  }
  if ((data as any)?.error) throw new Error((data as any).error);
  return data as T;
}

/** Fila pendente, mais confiáveis primeiro — o lote começa pelo que é seguro aprovar em bloco. */
export function useFinanceReviewQueue() {
  return useQuery({
    queryKey: ['finance-review-queue'],
    queryFn: async (): Promise<PropostaFinanceira[]> => {
      const { data, error } = await supabase
        .from('finance_review_queue')
        // Traz a identificação da transação junto: sem ela, decidir exige abrir o
        // internet banking em outra aba, que é exatamente o trabalho que esta tela existe
        // para eliminar.
        .select(`*, bank_transactions ( counterparty_name, counterparty_document,
          counterparty_bank, counterparty_branch, counterparty_account, payment_method,
          payment_reason, merchant_name, merchant_document, installment_label,
          pix_end_to_end_id, description, source_type, bank_ref_id )`)
        .eq('status', 'pending')
        .order('confidence', { ascending: false })
        .order('suggested_amount', { ascending: false })
        .limit(500);
      if (error) throw error;
      return (data ?? []) as unknown as PropostaFinanceira[];
    },
    staleTime: 30_000,
  });
}

/**
 * Só a CONTAGEM da fila, para o menu.
 *
 * Consulta separada de propósito: o menu monta em toda tela do sistema e não pode arrastar
 * as 500 linhas da fila junto. `head: true` traz o total sem trazer linha nenhuma.
 */
export function useFinanceReviewCount() {
  return useQuery({
    queryKey: ['finance-review-count'],
    queryFn: async (): Promise<number> => {
      const { count, error } = await supabase
        .from('finance_review_queue')
        .select('id', { count: 'exact', head: true })
        .eq('status', 'pending');
      if (error) throw error;
      return count ?? 0;
    },
    staleTime: 60_000,
  });
}

export function useGerarPropostas() {
  const qc = useQueryClient();
  type Resposta = { ok: boolean; criadas: number; message: string; elegiveis_lote?: number };
  return useMutation<Resposta, Error, boolean>({
    mutationFn: (incluirHistorico: boolean) =>
      invokeReview<Resposta>({ action: 'generate', incluir_historico: incluirHistorico }),
    onSuccess: (r) => {
      toast.success(r.message);
      qc.invalidateQueries({ queryKey: ['finance-review-queue'] });
    },
    onError: (e: Error) => toast.error(e.message || 'Não foi possível gerar as propostas'),
  });
}

export function useAprovarPropostas() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { ids: string[]; overrides?: Record<string, Correcao> }) =>
      invokeReview<{ ok: boolean; aprovadas: number; falhas: string[]; message: string }>({
        action: 'approve', ids: v.ids, overrides: v.overrides ?? {},
      }),
    onSuccess: (r) => {
      if (r.falhas?.length) toast.warning(r.message, { description: r.falhas.slice(0, 3).join(' · ') });
      else toast.success(r.message);
      // Aprovar cria despesa e baixa a transação: as duas listas mudam.
      for (const k of [['finance-review-queue'], ['payables'], ['receivables'], ['bank-transactions'], ['financial-summary']]) {
        qc.invalidateQueries({ queryKey: k });
      }
    },
    onError: (e: Error) => toast.error(e.message || 'Não foi possível aprovar'),
  });
}

/**
 * Cria uma categoria de despesa sem sair da tela onde ela fez falta.
 *
 * Nasce no mesmo grupo do DRE que a proposta deduziu: uma categoria sem grupo fica fora do
 * resultado, e o gestor não teria como perceber que o número parou de fechar.
 */
export function useCriarCategoriaDespesa() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { name: string; dre_group: string | null; type?: 'payable' | 'receivable' }) => {
      const { data, error } = await supabase
        .from('financial_categories')
        .insert({
          name: v.name,
          type: v.type ?? 'payable',
          dre_group: v.dre_group ?? 'despesa_operacional',
          active: true,
          sort_order: 900,   // no fim da lista: o que é novo ainda não provou seu lugar
        } as never)
        .select('name')
        .single();
      if (error) throw error;
      return (data as any).name as string;
    },
    onSuccess: (nome) => {
      toast.success(`Categoria "${nome}" criada`);
      qc.invalidateQueries({ queryKey: ['financial-categories'] });
    },
    onError: (e: Error) => {
      const msg = /duplicate key|financial_categories_nome_tipo/i.test(e.message)
        ? 'Já existe uma categoria de despesa com esse nome.'
        : e.message || 'Não foi possível criar a categoria';
      toast.error(msg);
    },
  });
}

/** Uma regra que o gestor ensinou — ou que a IA propôs e aguarda o aceite dele. */
export interface RegraFinanceira {
  id: string;
  match_type: 'document' | 'supplier' | 'counterparty' | 'text';
  match_value: string;
  direction: 'debit' | 'credit' | 'any';
  min_amount: number | null;
  max_amount: number | null;
  set_category: string | null;
  set_dre_group: string | null;
  set_supplier_id: string | null;
  autonomy: 'suggest' | 'apply';
  origin: 'user' | 'ai';
  status: 'active' | 'paused' | 'proposed' | 'rejected';
  reasoning: string | null;
  note: string | null;
  times_applied: number;
  last_applied_at: string | null;
  created_at: string;
}

export function useFinanceRules() {
  return useQuery({
    queryKey: ['finance-rules'],
    queryFn: async (): Promise<RegraFinanceira[]> => {
      const { data, error } = await supabase
        .from('finance_rules')
        .select('*')
        .in('status', ['active', 'paused', 'proposed'])
        // Propostas primeiro: são as que pedem uma decisão, não as que já trabalham.
        .order('status', { ascending: true })
        .order('times_applied', { ascending: false })
        .limit(300);
      if (error) throw error;
      return (data ?? []) as unknown as RegraFinanceira[];
    },
    staleTime: 60_000,
  });
}

/** Um lançamento que embasa a regra — o que faz aceitar deixar de ser aposta. */
export interface LancamentoDaRegra {
  id: string;
  description: string;
  amount: number;
  issue_date: string;
  expense_category: string | null;
  supplier_name: string | null;
  fornecedor: string | null;
  contraparte: string | null;
  documento: string | null;
  banco: string | null;
  meio: string | null;
}

/**
 * As despesas que a regra usou como evidência.
 *
 * A sugestão diz "as últimas 5 foram lançadas como Ferramentas, sem exceção" — mas sem ver
 * QUAIS, quanto e para quem, aceitar é confiar num resumo. E o resumo esconde justamente o
 * que muda a decisão: um dos cinco pode ser de outro fornecedor com nome parecido, ou de
 * valor tão diferente que denuncia uma classificação apressada.
 */
export function useLancamentosDaRegra(regra: RegraFinanceira | null) {
  return useQuery({
    queryKey: ['lancamentos-da-regra', regra?.id, regra?.match_type, regra?.match_value],
    enabled: !!regra,
    queryFn: async (): Promise<LancamentoDaRegra[]> => {
      if (!regra) return [];

      let q = supabase
        .from('payables')
        .select(`id, description, amount, issue_date, expense_category, supplier_name,
                 suppliers ( name ),
                 bank_transactions ( counterparty_name, counterparty_document,
                                     counterparty_bank, payment_method )`)
        .order('issue_date', { ascending: false })
        .limit(25);

      // Cada tipo de regra procura por um caminho diferente — o mesmo caminho que ela usa
      // para reconhecer, senão o histórico mostraria coisa que a regra não pegaria.
      if (regra.match_type === 'supplier') {
        q = q.eq('supplier_id', regra.match_value);
      } else if (regra.match_type === 'counterparty') {
        q = q.ilike('supplier_name', `%${regra.match_value}%`);
      } else if (regra.match_type === 'text') {
        q = q.ilike('description', `%${regra.match_value}%`);
      } else {
        // Por documento: o vínculo está na transação bancária, não no lançamento.
        const { data: txs } = await supabase
          .from('bank_transactions')
          .select('id')
          .eq('counterparty_document', regra.match_value.replace(/\D/g, ''))
          .limit(50);
        const ids = (txs ?? []).map((t: any) => t.id);
        if (ids.length === 0) return [];
        q = q.in('bank_transaction_id', ids);
      }

      const { data, error } = await q;
      if (error) throw error;

      return ((data ?? []) as any[]).map((p) => ({
        id: p.id,
        description: p.description,
        amount: Number(p.amount),
        issue_date: p.issue_date,
        expense_category: p.expense_category,
        supplier_name: p.supplier_name,
        fornecedor: p.suppliers?.name ?? null,
        contraparte: p.bank_transactions?.counterparty_name ?? null,
        documento: p.bank_transactions?.counterparty_document ?? null,
        banco: p.bank_transactions?.counterparty_bank ?? null,
        meio: p.bank_transactions?.payment_method ?? null,
      }));
    },
    staleTime: 60_000,
  });
}

export function useSalvarRegra() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (r: Partial<RegraFinanceira> & { id?: string }) => {
      if (r.id) {
        const { error } = await supabase.from('finance_rules').update(r as never).eq('id', r.id);
        if (error) throw error;
        return r.id;
      }
      const { data, error } = await supabase
        .from('finance_rules').insert(r as never).select('id').single();
      if (error) throw error;
      return (data as any).id as string;
    },
    onSuccess: () => {
      toast.success('Regra salva');
      qc.invalidateQueries({ queryKey: ['finance-rules'] });
    },
    onError: (e: Error) => {
      // Violação do índice de alvo único vira a explicação real do problema: já existe
      // uma regra viva para o mesmo alvo, e duas instruções para o mesmo fato dariam
      // resultado imprevisível.
      const msg = /finance_rules_uma_por_alvo|duplicate key/i.test(e.message)
        ? 'Já existe uma regra para este mesmo alvo. Edite a existente em vez de criar outra.'
        : e.message || 'Não foi possível salvar a regra';
      toast.error(msg);
    },
  });
}

export function useMudarStatusRegra() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { id: string; status: RegraFinanceira['status'] }) => {
      const { error } = await supabase
        .from('finance_rules').update({ status: v.status } as never).eq('id', v.id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['finance-rules'] }),
    onError: (e: Error) => toast.error(e.message),
  });
}

/** Pede ao sistema que olhe as decisões já tomadas e proponha regras. */
export function useProporRegras() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () => invokeReview<{ ok: boolean; propostas: number; message: string }>({ action: 'suggest_rules' }),
    onSuccess: (r) => {
      toast.success(r.message);
      qc.invalidateQueries({ queryKey: ['finance-rules'] });
    },
    onError: (e: Error) => toast.error(e.message),
  });
}

/**
 * Marca a transação como duplicata e descarta a proposta que nasceu dela.
 *
 * As duas coisas juntas de propósito: só recusar a proposta deixaria a transação na fila
 * para ser proposta de novo na próxima varredura.
 */
export function useMarcarDuplicata() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { propostaId: string; bankTransactionId: string | null }) => {
      if (v.bankTransactionId) {
        const { error } = await supabase.from('bank_transactions')
          .update({ reconciled: true, dismissed_reason: 'Duplicata' } as never)
          .eq('id', v.bankTransactionId);
        if (error) throw error;
      }
      const { error: e2 } = await supabase.from('finance_review_queue')
        .update({ status: 'rejected', decision_note: 'Duplicata' } as never)
        .eq('id', v.propostaId);
      if (e2) throw e2;
    },
    onSuccess: () => {
      toast.success('Marcada como duplicata');
      qc.invalidateQueries({ queryKey: ['finance-review-queue'] });
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
    },
    onError: (e: Error) => toast.error(e.message),
  });
}

export function useRecusarPropostas() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { ids: string[]; note?: string }) =>
      invokeReview<{ ok: boolean; message: string }>({ action: 'reject', ids: v.ids, note: v.note }),
    onSuccess: (r) => {
      toast.success(r.message);
      qc.invalidateQueries({ queryKey: ['finance-review-queue'] });
    },
    onError: (e: Error) => toast.error(e.message || 'Não foi possível recusar'),
  });
}
