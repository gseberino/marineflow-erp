// Cartões: a fatura como coisa, não como um monte de compras soltas.
//
// "E cartões é totalmente separado. Lembra que a gente teve aquele problema com transações
//  de cartão misturada com transações de Pix e transferências?" — e está certo: cartão é
// outro objeto. Não tem contraparte (a bandeira repassa o estabelecimento e o MCC, não o
// CNPJ), não sai do caixa na data da compra, e pertence a um ciclo que fecha.
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export interface FaturaDoCartao {
  bill_id: string;
  provider_account_id: string | null;
  compras: number;
  compras_parceladas: number;
  primeira_compra: string;
  ultima_compra: string;
  total: number;
  cartoes: string | null;
  /** Pagamento no extrato cujo valor casa EXATO com o total. Quase sempre nulo — ver abaixo. */
  pagamento_id: string | null;
  pagamento_data: string | null;
  pagamento_valor: number | null;
  pagamento_descricao: string | null;
}

export interface CompraDaFatura {
  id: string;
  transaction_date: string;
  description: string | null;
  amount: number;
  counterparty_name: string | null;
  payee_mcc: string | null;
  provider_category: string | null;
  card_last_digits: string | null;
  installment_label: string | null;
}

export interface PagamentoDeFatura {
  id: string;
  transaction_date: string;
  description: string | null;
  amount: number;
}

/** Como o banco escreve o pagamento da fatura. Uma lista, porque ele usa quatro variações. */
const HISTORICOS_DE_FATURA = [
  'description.ilike.%FAT%CARTAO%',
  'description.ilike.%FATURA%CART%',
  'description.ilike.%PGTO%CARTAO%',
  'description.eq.DEBITO DE CARTAO',
].join(',');

export function useFaturasDoCartao() {
  return useQuery({
    queryKey: ['faturas-do-cartao'],
    queryFn: async (): Promise<FaturaDoCartao[]> => {
      const { data, error } = await supabase
        .from('faturas_do_cartao' as never)
        .select('*')
        .order('ultima_compra', { ascending: false })
        .limit(120);
      if (error) throw error;
      return (data ?? []) as unknown as FaturaDoCartao[];
    },
    staleTime: 60_000,
  });
}

/** As compras de UMA fatura — carregadas só quando alguém abre o ciclo. */
export function useComprasDaFatura(billId: string | null) {
  return useQuery({
    enabled: billId != null,
    queryKey: ['compras-da-fatura', billId],
    queryFn: async (): Promise<CompraDaFatura[]> => {
      const { data, error } = await supabase
        .from('bank_transactions')
        .select('id, transaction_date, description, amount, counterparty_name, payee_mcc, provider_category, card_last_digits, installment_label')
        .eq('bill_id', billId!)
        .eq('transaction_type', 'debit')
        .order('transaction_date', { ascending: false })
        .order('id', { ascending: true })
        .limit(500);
      if (error) throw error;
      return (data ?? []) as unknown as CompraDaFatura[];
    },
    staleTime: 60_000,
  });
}

/**
 * Tudo que saiu do banco para o cartão.
 *
 * Existe separado das faturas de propósito: o casamento fatura ↔ pagamento quase nunca
 * fecha (1 de 23 medido em 10/08/2026), porque a empresa paga a fatura PARCIALMENTE e
 * carrega saldo. Uma fatura de R$ 1.515 recebeu R$ 1.000 e R$ 990; outra de R$ 4.751 foi
 * paga com R$ 6.370 (o ciclo mais o saldo anterior). Somar os dois lados no período diz a
 * verdade; fingir um vínculo 1:1 não diria.
 */
export function usePagamentosDeFatura() {
  return useQuery({
    queryKey: ['pagamentos-de-fatura'],
    queryFn: async (): Promise<PagamentoDeFatura[]> => {
      const { data, error } = await supabase
        .from('bank_transactions')
        .select('id, transaction_date, description, amount')
        .eq('source_type', 'bank')
        .eq('transaction_type', 'debit')
        .or(HISTORICOS_DE_FATURA)
        .order('transaction_date', { ascending: false })
        .order('id', { ascending: true })
        .limit(500);
      if (error) throw error;
      return (data ?? []) as unknown as PagamentoDeFatura[];
    },
    staleTime: 60_000,
  });
}

/**
 * Encargos do cartão — juros, IOF, multa, anuidade.
 *
 * São o preço do rotativo, e ninguém os enxergava separados. Contá-los é o primeiro passo
 * para decidir se vale a pena continuar pagando a fatura pela metade.
 */
export function useEncargosDoCartao() {
  return useQuery({
    queryKey: ['encargos-do-cartao'],
    queryFn: async (): Promise<{ quantidade: number; total: number }> => {
      const { data, error } = await supabase
        .from('bank_transactions')
        .select('amount')
        .eq('source_type', 'credit_card')
        .or('description.ilike.%juros%,description.ilike.%encargo%,description.ilike.%rotativ%,description.ilike.%iof%,description.ilike.%multa%,description.ilike.%anuidade%')
        .limit(500);
      if (error) throw error;
      const linhas = (data ?? []) as Array<{ amount: number }>;
      return {
        quantidade: linhas.length,
        total: linhas.reduce((s, l) => s + Number(l.amount ?? 0), 0),
      };
    },
    staleTime: 5 * 60_000,
  });
}

/**
 * Compras que não pertencem a fatura nenhuma.
 *
 * `bill_id` veio nulo em 82 delas. Não é erro de ninguém — o provedor só passa a fatura
 * depois que o ciclo fecha —, mas elas somem de qualquer visão por fatura, e some sem
 * aviso é como um gasto deixa de ser conferido.
 */
export function useComprasSemFatura() {
  return useQuery({
    queryKey: ['compras-sem-fatura'],
    queryFn: async (): Promise<CompraDaFatura[]> => {
      const { data, error } = await supabase
        .from('bank_transactions')
        .select('id, transaction_date, description, amount, counterparty_name, payee_mcc, provider_category, card_last_digits, installment_label')
        .eq('source_type', 'credit_card')
        .eq('transaction_type', 'debit')
        .is('bill_id', null)
        .order('transaction_date', { ascending: false })
        .order('id', { ascending: true })
        .limit(300);
      if (error) throw error;
      return (data ?? []) as unknown as CompraDaFatura[];
    },
    staleTime: 60_000,
  });
}
