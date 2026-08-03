// Favorecidos: quem recebe dinheiro da empresa sem ser fornecedor nem usuário do sistema.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export type TipoFavorecido = 'socio' | 'funcionario' | 'diarista' | 'prestador' | 'comissionado';

export interface Favorecido {
  id: string;
  name: string;
  kind: TipoFavorecido;
  document: string | null;
  phone: string | null;
  email: string | null;
  pix_key: string | null;
  pix_key_type: string | null;
  bank_name: string | null;
  bank_branch: string | null;
  bank_account: string | null;
  account_type: string | null;
  default_category: string | null;
  commission_percentage: number | null;
  notes: string | null;
  active: boolean;
}

export const ROTULO_TIPO: Record<TipoFavorecido, string> = {
  socio: 'Sócio',
  funcionario: 'Funcionário',
  diarista: 'Diarista',
  prestador: 'Prestador de serviço',
  comissionado: 'Comissionado',
};

/**
 * Categorias que pertencem a uma PESSOA, não a um fornecedor.
 *
 * É o que decide quando a tela pergunta "quem recebeu": perguntar sempre viraria ruído em
 * 90% das linhas, e nunca perguntar deixa R$ 36 mil de pró-labore sem dono.
 */
export const CATEGORIAS_COM_FAVORECIDO = [
  'Pró-labore e retirada',
  'Salários e encargos',
  'Serviços de terceiros',
];

/** Categorias em que a compra costuma pertencer a um serviço específico. */
export const CATEGORIAS_COM_OS = [
  'Peças e materiais',
  'Compras de Mercadorias',
  'Ferramentas e equipamentos',
  'Frete e importação',
];

export function usePayees(apenasAtivos = true) {
  return useQuery({
    queryKey: ['payees', apenasAtivos],
    queryFn: async (): Promise<Favorecido[]> => {
      let q = supabase.from('payees').select('*').order('name');
      if (apenasAtivos) q = q.eq('active', true);
      const { data, error } = await q;
      if (error) throw error;
      return (data ?? []) as unknown as Favorecido[];
    },
    staleTime: 5 * 60_000,
  });
}

export function useSalvarPayee() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (f: Partial<Favorecido> & { id?: string }) => {
      // Documento só com dígitos: é assim que ele casa com o extrato, onde vem sem máscara.
      const limpo = { ...f, document: f.document ? f.document.replace(/\D/g, '') : null };
      if (f.id) {
        const { error } = await supabase.from('payees').update(limpo as never).eq('id', f.id);
        if (error) throw error;
        return f.id;
      }
      const { data, error } = await supabase
        .from('payees').insert(limpo as never).select('id').single();
      if (error) throw error;
      return (data as any).id as string;
    },
    onSuccess: () => {
      toast.success('Favorecido salvo');
      qc.invalidateQueries({ queryKey: ['payees'] });
    },
    onError: (e: Error) => {
      const msg = /payees_documento_unico|duplicate key/i.test(e.message)
        ? 'Já existe um favorecido com este CPF/CNPJ. Edite o existente em vez de criar outro.'
        : e.message || 'Não foi possível salvar';
      toast.error(msg);
    },
  });
}

/**
 * Ordens de serviço às quais uma compra pode pertencer.
 *
 * Só as que ainda estão vivas: vincular custo a uma OS já faturada mudaria uma margem que
 * o cliente e a contabilidade já enxergaram.
 */
export function useServiceOrdersVinculaveis() {
  return useQuery({
    queryKey: ['service-orders-vinculaveis'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('service_orders')
        .select('id, service_order_number, status, clients(name)')
        .not('status', 'in', '("cancelled","invoiced")')
        .order('created_at', { ascending: false })
        .limit(200);
      if (error) throw error;
      return (data ?? []) as unknown as Array<{
        id: string; service_order_number: string; status: string;
        clients: { name: string } | null;
      }>;
    },
    staleTime: 2 * 60_000,
  });
}
