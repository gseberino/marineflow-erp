// [F-NFSE-03] Cadastro fiscal por verbo e código fiscal EFETIVO dos serviços.
//
// A herança é resolvida no BANCO (view `v_services_fiscal_efetivo` / função
// `resolve_service_fiscal`), não aqui. A tela só lê o resultado — repetir o COALESCE no
// frontend criaria uma terceira implementação da mesma regra, para divergir das outras duas
// no primeiro ajuste.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

// Migration `20260811003000_nfse_verbos_fiscais_com_heranca` APLICADA em 13/08/2026 e tipos
// regenerados na mesma sessão — o acesso destipado (`supabase as any`) que vivia aqui foi
// removido, como o próprio aviso original pedia. O typecheck volta a cobrir estas queries.
const db = supabase;

/** De onde veio o código de tributação que sairia na nota. */
export type FiscalCodeSource = 'proprio' | 'verbo' | 'nenhum';

export interface ServiceFiscalEfetivo {
  id: string;
  name: string;
  active: boolean;
  service_verb: string | null;
  fiscal_verb: string | null;
  national_tax_code_efetivo: string | null;
  service_code_efetivo: string | null;
  cnae_efetivo: string | null;
  iss_rate_efetivo: number | null;
  iss_withheld_efetivo: boolean;
  code_source: FiscalCodeSource;
  sem_codigo_fiscal: boolean;
}

export interface ServiceFiscalVerb {
  verb_slug: string;
  default_national_tax_code: string | null;
  default_service_code: string | null;
  default_cnae: string | null;
  default_iss_rate: number | null;
  default_iss_withheld: boolean | null;
  notes: string | null;
}

/** Verbo + o nome legível e a contagem de serviços que dependem dele. */
export interface ServiceFiscalVerbRow extends ServiceFiscalVerb {
  name: string;
  servicos: number;
}

export function useServicesFiscalEfetivo() {
  return useQuery({
    queryKey: ['services-fiscal-efetivo'],
    queryFn: async (): Promise<ServiceFiscalEfetivo[]> => {
      const { data, error } = await db
        .from('v_services_fiscal_efetivo')
        .select('*');
      if (error) throw error;
      return (data ?? []) as ServiceFiscalEfetivo[];
    },
  });
}

/**
 * As dez linhas da grade de Settings, com o nome do verbo e quantos serviços herdam dele.
 *
 * A contagem importa na hora de preencher: mexer no verbo que 84 serviços usam não é a mesma
 * coisa que mexer no que ninguém usa, e a grade precisa deixar isso à vista.
 */
export function useServiceFiscalVerbs() {
  return useQuery({
    queryKey: ['service-fiscal-verbs'],
    queryFn: async (): Promise<ServiceFiscalVerbRow[]> => {
      const { data, error } = await db
        .from('service_fiscal_verbs')
        .select('*, service_verbs!inner(name, sort)');
      if (error) throw error;

      const { data: servicos, error: erroServicos } = await db
        .from('services')
        .select('fiscal_verb')
        .eq('active', true)
        .not('fiscal_verb', 'is', null);
      if (erroServicos) throw erroServicos;

      const contagem = new Map<string, number>();
      for (const s of (servicos ?? []) as { fiscal_verb: string }[]) {
        contagem.set(s.fiscal_verb, (contagem.get(s.fiscal_verb) ?? 0) + 1);
      }

      return ((data ?? []) as any[])
        .map((v) => ({
          verb_slug: v.verb_slug,
          default_national_tax_code: v.default_national_tax_code,
          default_service_code: v.default_service_code,
          default_cnae: v.default_cnae,
          default_iss_rate: v.default_iss_rate,
          default_iss_withheld: v.default_iss_withheld,
          notes: v.notes,
          name: v.service_verbs?.name ?? v.verb_slug,
          sort: v.service_verbs?.sort ?? 100,
          servicos: contagem.get(v.verb_slug) ?? 0,
        }))
        .sort((a, b) => a.sort - b.sort || a.name.localeCompare(b.name))
        .map(({ sort: _sort, ...linha }) => linha);
    },
  });
}

export function useUpdateServiceFiscalVerb() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ verb_slug, ...campos }: Partial<ServiceFiscalVerb> & { verb_slug: string }) => {
      const { error } = await db
        .from('service_fiscal_verbs')
        .update(campos)
        .eq('verb_slug', verb_slug);
      if (error) throw error;
    },
    onSuccess: () => {
      // O código efetivo dos serviços muda junto — é o ponto de mudar o verbo.
      qc.invalidateQueries({ queryKey: ['service-fiscal-verbs'] });
      qc.invalidateQueries({ queryKey: ['services-fiscal-efetivo'] });
      toast.success('Verbo fiscal atualizado');
    },
    onError: (e: any) => {
      // Os CHECKs de formato vivem no banco; a mensagem crua ("violates check constraint
      // sfv_cnae_formato") não diz nada a quem preenche. Traduzir aqui é o que faz o erro
      // servir para corrigir.
      const msg = String(e?.message ?? '');
      if (msg.includes('sfv_national_tax_code_formato')) {
        toast.error('Código de tributação nacional precisa ter exatamente 6 dígitos, sem pontos.');
      } else if (msg.includes('sfv_cnae_formato')) {
        toast.error('CNAE precisa ter exatamente 7 dígitos, sem pontos nem barra.');
      } else if (msg.includes('sfv_iss_rate_faixa')) {
        toast.error('Alíquota de ISS deve estar entre 0 e 100 (é percentual, não fração).');
      } else {
        toast.error(`Não foi possível salvar: ${msg}`);
      }
    },
  });
}
