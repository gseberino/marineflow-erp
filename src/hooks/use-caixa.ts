// Caixa em dinheiro e anotações antecipadas — as mesmas funções do banco que o assistente
// usa (lancar_no_caixa, mover_caixa, ajustar_caixa, anotar_transacao).
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { mensagemDoErro, recarregarFinanceiro } from '@/hooks/use-lancamentos';

interface Resposta { ok: boolean; message: string; saldo_do_caixa?: number; aplicada?: boolean; ja_lancada?: boolean }

async function chamar(fn: string, args: Record<string, unknown>): Promise<Resposta> {
  const { data, error } = await supabase.rpc(fn as never, args as never);
  if (error) throw error;
  return data as unknown as Resposta;
}

function useAcaoDoCaixa<A>(fn: string, montar: (v: A) => Record<string, unknown>) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: A) => chamar(fn, montar(v)),
    onSuccess: (r) => {
      recarregarFinanceiro(qc);
      qc.invalidateQueries({ queryKey: ['anotacoes-do-extrato'] });
      if (r?.ok === false) toast.warning(r.message);
      else toast.success(r?.message ?? 'Feito');
    },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

export interface LancamentoNoCaixa {
  sentido: 'saida' | 'entrada';
  valor: number;
  descricao: string;
  data?: string | null;
  categoria?: string | null;
  fornecedorId?: string | null;
  favorecidoId?: string | null;
  clienteId?: string | null;
  osId?: string | null;
  pagoPor?: 'caixa' | 'socio';
  socioId?: string | null;
}

export function useLancarNoCaixa() {
  return useAcaoDoCaixa<LancamentoNoCaixa>('lancar_no_caixa', (v) => ({
    p_sentido: v.sentido, p_valor: v.valor, p_descricao: v.descricao, p_data: v.data || null,
    p_categoria: v.categoria || null, p_fornecedor_id: v.fornecedorId || null, p_favorecido_id: v.favorecidoId || null,
    p_cliente_id: v.clienteId || null, p_os_id: v.osId || null, p_pago_por: v.pagoPor ?? 'caixa', p_socio_id: v.socioId || null,
  }));
}

export function useMoverCaixa() {
  return useAcaoDoCaixa<{ sentido: 'saque' | 'deposito'; valor: number; data?: string | null }>('mover_caixa', (v) => ({
    p_sentido: v.sentido, p_valor: v.valor, p_data: v.data || null, p_transacao_banco: null,
  }));
}

export function useAjustarCaixa() {
  return useAcaoDoCaixa<{ saldoContado: number; motivo: string }>('ajustar_caixa', (v) => ({
    p_saldo_contado: v.saldoContado, p_motivo: v.motivo,
  }));
}

export interface AnotacaoNova {
  sentido: 'saida' | 'entrada';
  valor: number;
  data?: string | null;
  documento?: string | null;
  fornecedorId?: string | null;
  favorecidoId?: string | null;
  clienteId?: string | null;
  categoria?: string | null;
  osId?: string | null;
  descricao?: string | null;
}

export function useAnotarTransacao() {
  return useAcaoDoCaixa<AnotacaoNova>('anotar_transacao', (v) => ({
    p_sentido: v.sentido, p_valor: v.valor, p_data: v.data || null, p_documento: v.documento || null, p_nome: null,
    p_fornecedor_id: v.fornecedorId || null, p_favorecido_id: v.favorecidoId || null, p_cliente_id: v.clienteId || null,
    p_categoria: v.categoria || null, p_os_id: v.osId || null, p_descricao: v.descricao || null,
  }));
}

export interface Anotacao {
  id: string;
  sentido: 'debit' | 'credit';
  valor: number;
  data_prevista: string;
  documento: string | null;
  nome: string | null;
  categoria: string | null;
  descricao: string | null;
  criada_em: string;
  suppliers?: { name: string } | null;
  payees?: { name: string } | null;
  clients?: { name: string } | null;
  service_orders?: { service_order_number: string } | null;
}

/** Anotações esperando a transação chegar do banco. */
export function useAnotacoesAguardando() {
  return useQuery({
    queryKey: ['anotacoes-do-extrato'],
    queryFn: async (): Promise<Anotacao[]> => {
      const { data, error } = await supabase
        .from('anotacoes_do_extrato' as never)
        .select('id, sentido, valor, data_prevista, documento, nome, categoria, descricao, criada_em, suppliers(name), payees(name), clients(name), service_orders(service_order_number)')
        .eq('status', 'aguardando')
        .order('data_prevista', { ascending: false })
        .limit(100);
      if (error) throw error;
      return (data ?? []) as unknown as Anotacao[];
    },
    staleTime: 30_000,
  });
}

export function useCancelarAnotacao() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from('anotacoes_do_extrato' as never)
        .update({ status: 'cancelada' } as never).eq('id', id).eq('status', 'aguardando');
      if (error) throw error;
    },
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['anotacoes-do-extrato'] }); toast.success('Anotação cancelada'); },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}
