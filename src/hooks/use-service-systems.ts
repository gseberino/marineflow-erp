import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

/**
 * Catálogo de sistemas (categorias técnicas).
 * Plano: plans/marineflow-execucao-os-roteiro.md, seção 10-ter
 *
 * O sistema é o eixo que traz a abertura e o fechamento de segurança do
 * roteiro. Antes ele vivia como lista fixa em cinco pontos do código; agora é
 * cadastro, e o dono cria categoria sem depender de migration.
 *
 * Cuidado que a tela precisa comunicar: categoria sem bloco de abertura não
 * protege ninguém — os serviços dela recebem o corpo do verbo e nenhuma
 * preparação, em silêncio.
 */

export interface ServiceSystem {
  slug: string;
  name: string;
  short_name: string | null;
  is_physical: boolean;
  sort: number;
  active: boolean;
}

export interface ServiceSystemStatus extends ServiceSystem {
  passos_abertura: number;
  passos_fechamento: number;
  perguntas: number;
  servicos: number;
}

/** Só os utilizáveis, para preencher seletor. */
export function useServiceSystems() {
  return useQuery({
    queryKey: ['service-systems'],
    queryFn: async (): Promise<ServiceSystem[]> => {
      const { data, error } = await supabase
        .from('service_systems')
        .select('slug, name, short_name, is_physical, sort, active')
        .eq('active', true)
        .order('sort');
      if (error) throw error;
      return (data || []) as unknown as ServiceSystem[];
    },
    staleTime: 5 * 60 * 1000,
  });
}

/** Com a contagem de blocos, perguntas e serviços — para a tela de gestão. */
export function useServiceSystemsStatus() {
  return useQuery({
    queryKey: ['service-systems-status'],
    queryFn: async (): Promise<ServiceSystemStatus[]> => {
      const { data, error } = await supabase
        .from('v_service_systems_status')
        .select('*')
        .order('sort');
      if (error) throw error;
      return (data || []) as unknown as ServiceSystemStatus[];
    },
  });
}

/** Categoria sem abertura nem fechamento não gera preparação nenhuma. */
export function systemIncomplete(s: ServiceSystemStatus): boolean {
  return s.is_physical && (s.passos_abertura === 0 || s.passos_fechamento === 0);
}

/** Slug a partir do nome: 'Ar comprimido' → 'ar_comprimido'. */
export function slugify(nome: string): string {
  return nome
    .normalize('NFD').replace(/[̀-ͯ]/g, '')  // tira acento sem depender do encoding
    .toLowerCase().trim()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 40);
}

export function useCreateServiceSystem() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: { name: string; short_name?: string; is_physical: boolean }) => {
      const slug = slugify(input.name);
      if (!slug) throw new Error('Dê um nome à categoria.');

      const { error } = await supabase.from('service_systems').insert({
        slug,
        name: input.name.trim(),
        short_name: (input.short_name || input.name).trim(),
        is_physical: input.is_physical,
        sort: 500,
      });
      if (error) {
        if (error.code === '23505') throw new Error('Já existe uma categoria com esse nome.');
        throw error;
      }
      return slug;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['service-systems'] });
      qc.invalidateQueries({ queryKey: ['service-systems-status'] });
    },
  });
}

export function useUpdateServiceSystem() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      slug, patch,
    }: { slug: string; patch: Partial<Pick<ServiceSystem, 'name' | 'short_name' | 'active' | 'sort'>> }) => {
      const { error } = await supabase.from('service_systems').update(patch).eq('slug', slug);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['service-systems'] });
      qc.invalidateQueries({ queryKey: ['service-systems-status'] });
    },
  });
}

// ── Tipos de serviço (verbos) ────────────────────────────────────────────────
// Mesma mecânica das categorias. O verbo traz o corpo do roteiro; a categoria
// traz a abertura e o fechamento de segurança.

export interface ServiceVerb {
  slug: string;
  name: string;
  /**
   * true = o trabalho mexe no sistema e expõe a energia, então recebe a
   * abertura e o fechamento de segurança da categoria.
   * false = observa, mede e documenta sem intervir.
   *
   * O critério é a EXPOSIÇÃO, não o lugar: um levantamento de projeto acontece
   * no barco e continua sendo observação. Chamava-se `is_fieldwork` até 03/08,
   * o que fazia a pergunta errada — e o dono percebeu.
   */
  intervem_no_sistema: boolean;
  sort: number;
  active: boolean;
}

export interface ServiceVerbStatus extends ServiceVerb {
  passos_corpo: number;
  perguntas: number;
  servicos: number;
}

export function useServiceVerbs() {
  return useQuery({
    queryKey: ['service-verbs'],
    queryFn: async (): Promise<ServiceVerb[]> => {
      const { data, error } = await supabase
        .from('service_verbs')
        .select('slug, name, intervem_no_sistema, sort, active')
        .eq('active', true)
        .order('sort');
      if (error) throw error;
      return (data || []) as unknown as ServiceVerb[];
    },
    staleTime: 5 * 60 * 1000,
  });
}

export function useServiceVerbsStatus() {
  return useQuery({
    queryKey: ['service-verbs-status'],
    queryFn: async (): Promise<ServiceVerbStatus[]> => {
      const { data, error } = await supabase
        .from('v_service_verbs_status')
        .select('*')
        .order('sort');
      if (error) throw error;
      return (data || []) as unknown as ServiceVerbStatus[];
    },
  });
}

/** Tipo de serviço sem corpo escrito não gera passo nenhum. */
export function verbIncomplete(v: ServiceVerbStatus): boolean {
  return v.passos_corpo === 0;
}

export function useCreateServiceVerb() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: { name: string; intervem_no_sistema: boolean }) => {
      const slug = slugify(input.name);
      if (!slug) throw new Error('Dê um nome ao tipo de serviço.');

      const { error } = await supabase.from('service_verbs').insert({
        slug, name: input.name.trim(), intervem_no_sistema: input.intervem_no_sistema, sort: 500,
      });
      if (error) {
        if (error.code === '23505') throw new Error('Já existe um tipo com esse nome.');
        throw error;
      }
      return slug;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['service-verbs'] });
      qc.invalidateQueries({ queryKey: ['service-verbs-status'] });
    },
  });
}

export function useUpdateServiceVerb() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      slug, patch,
    }: { slug: string; patch: Partial<Pick<ServiceVerb, 'name' | 'active' | 'intervem_no_sistema' | 'sort'>> }) => {
      const { error } = await supabase.from('service_verbs').update(patch).eq('slug', slug);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['service-verbs'] });
      qc.invalidateQueries({ queryKey: ['service-verbs-status'] });
    },
  });
}

// ── Sistema da linha da OS ───────────────────────────────────────────────────

/**
 * Como este eixo se chama na interface, em todas as telas.
 *
 * O dono notou que a mesma coisa aparecia como "Sistema" numa tela e
 * "Categoria (sistema)" na outra. Um nome só, num lugar só.
 */
export const AXIS_LABEL = 'Sistema / categoria';

/**
 * Valor de tela para "este serviço não tem sistema fixo — pergunte na OS".
 *
 * No banco isso é NULL, mas o Select não aceita string vazia como valor, e sem
 * um item explícito não havia como TORNAR um serviço genérico: dava para tirar
 * o genérico e não para colocar. É este sentinel que fecha o caminho de volta.
 */
export const DEPENDS_ON_ORDER = '__depende_da_os__';
export const DEPENDS_ON_ORDER_LABEL = 'Depende da OS — perguntar a cada uma';

/** Converte a escolha da tela no que vai para o banco. */
export function systemChoiceToDb(escolha: string | null | undefined): string | null {
  return !escolha || escolha === DEPENDS_ON_ORDER ? null : escolha;
}

/** E o caminho inverso, para o Select exibir o item certo. */
export function systemDbToChoice(valor: string | null | undefined): string {
  return valor || DEPENDS_ON_ORDER;
}

export interface LineMissingSystem {
  line_id: string;
  service_name: string;
  service_verb: string | null;
  /** Palpite da regra, para o campo já vir preenchido. Sempre editável. */
  sistema_sugerido: string | null;
  motivo_sugestao: string | null;
}

/**
 * Linhas cujo sistema ninguém definiu — nem a linha, nem o catálogo.
 *
 * São os serviços genéricos ("diagnóstico no local") antes de alguém dizer o
 * que eles vão tocar nesta OS. Sem essa resposta o roteiro sai sem bloco de
 * segurança, e é por isso que a tela avisa em vez de gerar calada.
 */
export function useLinesMissingSystem(serviceOrderId: string | undefined) {
  return useQuery({
    queryKey: ['lines-missing-system', serviceOrderId],
    enabled: !!serviceOrderId,
    queryFn: async (): Promise<LineMissingSystem[]> => {
      const { data, error } = await supabase.rpc('lines_missing_system', {
        p_service_order_id: serviceOrderId!,
      });
      if (error) throw error;
      return (data || []) as unknown as LineMissingSystem[];
    },
  });
}

export function useSetLineSystem() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ lineId, system }: { lineId: string; system: string }) => {
      const { error } = await supabase
        .from('service_order_services')
        .update({ service_system: system })
        .eq('id', lineId);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['lines-missing-system'] });
      qc.invalidateQueries({ queryKey: ['service-order-steps'] });
    },
  });
}
