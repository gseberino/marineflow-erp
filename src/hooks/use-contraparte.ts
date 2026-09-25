// Cadastrar quem o extrato trouxe — fornecedor, favorecido ou cliente — sem digitar.
//
// Quando a linha do extrato não bate com nenhum cadastro, a tela oferece "cadastrar". Com
// CNPJ, os dados vêm da Receita (BrasilAPI, via edge finance-review, com cache de 30 dias);
// com CPF, vêm o nome e o documento do próprio extrato. O cadastro passa pela função do
// banco `cadastrar_contraparte`, que não duplica documento e faz TODA linha pendente com o
// mesmo documento apontar para o cadastro novo.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import type { DadosDaReceita } from '../../supabase/functions/_shared/banking/cnae';
import { mensagemDoErro } from '@/hooks/use-lancamentos';

export type TipoDeCadastro = 'fornecedor' | 'favorecido' | 'cliente';

export interface ConsultaDeDocumento {
  ok: boolean;
  tipo: 'cpf' | 'cnpj';
  documento: string;
  dados: DadosDaReceita | null;
  aviso?: string;
}

/** Dados da Receita para um CNPJ. CPF não tem consulta pública: volta sem dados. */
export function useConsultaDeDocumento(documento: string | null | undefined, ativo: boolean) {
  const doc = (documento ?? '').replace(/\D/g, '');
  return useQuery({
    queryKey: ['consulta-documento', doc],
    enabled: ativo && doc.length === 14,
    staleTime: 30 * 60_000,
    retry: false,
    queryFn: async (): Promise<ConsultaDeDocumento> => {
      const { data, error } = await supabase.functions.invoke('finance-review', {
        body: { action: 'consult_document', documento: doc },
      });
      if (error) throw error;
      return data as ConsultaDeDocumento;
    },
  });
}

export interface DadosDoCadastro {
  documento?: string | null;
  nome: string;
  nome_fantasia?: string | null;
  tipo_de_favorecido?: string | null;
  categoria?: string | null;
  telefone?: string | null;
  email?: string | null;
  cep?: string | null;
  logradouro?: string | null;
  numero?: string | null;
  complemento?: string | null;
  bairro?: string | null;
  cidade?: string | null;
  uf?: string | null;
  observacao?: string | null;
}

export function useCadastrarContraparte() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { tipo: TipoDeCadastro; dados: DadosDoCadastro }) => {
      const { data, error } = await supabase.rpc('cadastrar_contraparte' as never, {
        p_tipo: v.tipo, p_dados: v.dados,
      } as never);
      if (error) throw error;
      return data as unknown as { ok: boolean; id: string; ja_existia: boolean; linhas_atualizadas: number; message: string };
    },
    onSuccess: (r) => {
      for (const k of [['finance-review-queue'], ['suppliers'], ['clients'], ['clientes-para-receita'], ['payees'], ['trilha-conciliacao']]) {
        qc.invalidateQueries({ queryKey: k });
      }
      toast.success(r.message);
    },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}
