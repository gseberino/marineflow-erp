// Corrigir, desfazer, cancelar e casar um lançamento — o caminho único.
//
// Estas quatro ações vivem em funções do banco (migration 20260925200000), e a tela, o
// assistente do painel e o do WhatsApp chamam as mesmas funções. Assim a regra é uma só:
// toda mudança vai para a trilha, mês fechado recusa, valor que veio do banco não muda à
// mão e categoria sensível fica só com o administrador.
//
// Antes, cada tela gravava direto na tabela. Mudar o valor de uma conta em aberto não
// recalculava o saldo, conta paga não abria para edição e desfazer não existia — foi o que
// levou o dono a não confiar no que tinha aprovado.
import { useMutation, useQueryClient, type QueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export type TipoDeLancamento = 'payable' | 'receivable';

/** O que se pode corrigir numa conta a pagar. Chave com null limpa o campo. */
export interface CorrecaoDePagavel {
  description?: string;
  notes?: string | null;
  expense_category?: string | null;
  supplier_id?: string | null;
  payee_id?: string | null;
  linked_service_order_id?: string | null;
  cost_center_id?: string | null;
  issue_date?: string;
  due_date?: string;
  amount?: number;
}

/** O que se pode corrigir numa conta a receber. */
export interface CorrecaoDeRecebivel {
  description?: string;
  notes?: string | null;
  category?: string | null;
  client_id?: string;
  service_order_id?: string | null;
  cost_center_id?: string | null;
  issue_date?: string;
  due_date?: string;
  amount?: number;
}

export interface RespostaDoLancamento {
  ok: boolean;
  message: string;
  alterados?: string[];
  acao?: string;
  proposta_voltou?: boolean;
  linha_do_extrato?: 'fora_da_fila' | 'fila' | null;
  pagamento_registrado?: boolean;
  valor_pago?: number;
}

/**
 * Tudo que mostra lançamento, saldo ou fila precisa recarregar depois de qualquer uma das
 * quatro ações: um desfazer mexe na conta, na fila do Extrato, na Conciliação, no DRE e na
 * trilha ao mesmo tempo.
 */
export function recarregarFinanceiro(qc: QueryClient) {
  for (const k of [
    ['payables'], ['receivables'], ['payments'], ['financial-summary'], ['cash-flow'],
    ['bank-transactions'], ['bank-transactions-ignoradas'], ['extrato-a-tratar'],
    ['finance-review-queue'], ['finance-review-count'],
    ['conciliacao-sem-extrato'], ['conciliacao-conciliados'], ['conciliacao-extrato-livre'],
    ['trilha-conciliacao'], ['dre'], ['dashboard'], ['aging-report'], ['service-orders'],
  ]) qc.invalidateQueries({ queryKey: k });
}

/** A mensagem do banco já vem em português e diz o que fazer; só tira o prefixo técnico. */
export function mensagemDoErro(e: unknown): string {
  const texto = (e as { message?: string })?.message ?? String(e);
  return texto.replace(/^(ERROR:\s*)?(P0001|42501|23514):\s*/i, '');
}

async function chamar(nome: string, args: Record<string, unknown>): Promise<RespostaDoLancamento> {
  const { data, error } = await supabase.rpc(nome as never, args as never);
  if (error) throw error;
  return data as unknown as RespostaDoLancamento;
}

export function useCorrigirLancamento() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: {
      tipo: TipoDeLancamento;
      id: string;
      campos: CorrecaoDePagavel | CorrecaoDeRecebivel;
      motivo?: string | null;
    }) => chamar('corrigir_lancamento', {
      p_tipo: v.tipo, p_id: v.id, p_campos: v.campos, p_motivo: v.motivo ?? null,
    }),
    onSuccess: (r) => {
      recarregarFinanceiro(qc);
      toast.success(r.alterados && r.alterados.length === 0 ? 'Nada mudou' : 'Lançamento corrigido');
    },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

export function useDesfazerAprovacao() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { tipo: TipoDeLancamento; id: string; motivo?: string | null }) =>
      chamar('desfazer_aprovacao', { p_tipo: v.tipo, p_id: v.id, p_motivo: v.motivo ?? null }),
    onSuccess: (r) => { recarregarFinanceiro(qc); toast.success(r.message); },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

export function useCancelarLancamento() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { tipo: TipoDeLancamento; id: string; motivo: string }) =>
      chamar('cancelar_lancamento', { p_tipo: v.tipo, p_id: v.id, p_motivo: v.motivo }),
    onSuccess: (r) => { recarregarFinanceiro(qc); toast.success(r.message); },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

/**
 * Casa um lançamento com uma linha do extrato. Se a conta está em aberto, o pagamento é
 * registrado na data do extrato — casar é dizer que ela foi paga.
 */
export function useCasarComExtrato() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { tipo: TipoDeLancamento; id: string; bankTransactionId: string }) =>
      chamar('conciliar_lancamento', { p_tipo: v.tipo, p_id: v.id, p_transacao: v.bankTransactionId }),
    onSuccess: (r) => { recarregarFinanceiro(qc); toast.success(r.message); },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}
