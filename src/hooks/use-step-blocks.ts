import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { StepKind, StepMode } from '@/hooks/use-service-steps';

/**
 * Blocos componíveis (service_step_blocks).
 * Plano: plans/marineflow-execucao-os-roteiro.md, seção 10-ter (P27-P29)
 *
 * Roteiro = abertura do SISTEMA + corpo do VERBO + fechamento do SISTEMA.
 * Corrigir um bloco conserta todos os serviços daquele sistema de uma vez —
 * é por isso que a revisão aqui vale muito mais que a revisão de um template
 * de serviço: cada decisão aqui vale por dezenas de roteiros.
 *
 * A trava do banco (block_ai_precisa_aprovacao) impede bloco com origin='ai'
 * ativo sem approved_by. Aprovar é assinar.
 */

export type BlockRole = 'abertura' | 'corpo' | 'fechamento';

export interface StepBlock {
  id: string;
  block_role: BlockRole;
  applies_to_system: string | null;
  applies_to_verb: string | null;
  seq: number;
  title: string;
  detail: string | null;
  kind: StepKind;
  mode: StepMode;
  standard_minutes: number | null;
  is_killer: boolean;
  requires_photo: boolean;
  requires_measure: string | null;
  measure_unit: string | null;
  origin: 'manual' | 'ai';
  approved_by: string | null;
  approved_at: string | null;
  active: boolean;
}

const B_SELECT = `
  id, block_role, applies_to_system, applies_to_verb, seq, title, detail,
  kind, mode, standard_minutes, is_killer, requires_photo, requires_measure,
  measure_unit, origin, approved_by, approved_at, active
`;

/** Nomes de exibição — o banco guarda o slug, a tela mostra a palavra. */
export const SYSTEM_LABEL: Record<string, string> = {
  eletrico_dc: 'Elétrico DC (12/24V)',
  eletrico_ac: 'Elétrico AC (110/220V)',
  gas: 'Gás GLP',
  hidraulico: 'Hidráulico',
  eletronico: 'Eletrônico / dados',
  refrigeracao: 'Refrigeração',
  mecanico: 'Mecânico',
  estrutural: 'Estrutural',
  nenhum: 'Sem sistema',
};

export const VERB_LABEL: Record<string, string> = {
  instalacao: 'Instalação',
  substituicao: 'Substituição',
  reparo: 'Reparo',
  diagnostico: 'Diagnóstico',
  manutencao: 'Manutenção',
  remocao: 'Remoção / desmontagem',
  configuracao: 'Configuração',
  adequacao: 'Adequação',
  logistica: 'Logística / deslocamento',
};

const ROLE_LABEL: Record<BlockRole, string> = {
  abertura: 'Abertura',
  corpo: 'Corpo',
  fechamento: 'Fechamento',
};

export function useStepBlocks() {
  return useQuery({
    queryKey: ['step-blocks'],
    queryFn: async (): Promise<StepBlock[]> => {
      const { data, error } = await supabase
        .from('service_step_blocks')
        .select(B_SELECT)
        .order('block_role')
        .order('seq');
      if (error) throw error;
      return (data || []) as unknown as StepBlock[];
    },
  });
}

export function blockPendingApproval(b: StepBlock): boolean {
  return b.origin === 'ai' && !b.approved_at;
}

/** Aprova um passo do bloco: assina e ativa. */
export function useApproveBlock() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ block, edited }: { block: StepBlock; edited?: boolean }) => {
      const { data: auth } = await supabase.auth.getUser();
      const reviewer = auth?.user?.id ?? null;

      const { error } = await supabase
        .from('service_step_blocks')
        .update({ approved_by: reviewer, approved_at: new Date().toISOString(), active: true })
        .eq('id', block.id);
      if (error) throw error;

      // O diff proposto×aprovado é o sinal de aprendizado (Fase 7).
      await supabase.from('ai_suggestion_reviews').insert({
        suggestion_type: 'step_block',
        target_table: 'service_step_blocks',
        target_id: block.id,
        suggested: {
          title: block.title, detail: block.detail,
          kind: block.kind, standard_minutes: block.standard_minutes,
          block_role: block.block_role,
          eixo: block.applies_to_system ?? block.applies_to_verb,
        },
        approved: { title: block.title, standard_minutes: block.standard_minutes },
        verdict: edited ? 'edited' : 'accepted',
        reviewer_id: reviewer,
      });
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['step-blocks'] }),
  });
}

export function useRejectBlock() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (block: StepBlock) => {
      const { data: auth } = await supabase.auth.getUser();
      const reviewer = auth?.user?.id ?? null;

      await supabase.from('ai_suggestion_reviews').insert({
        suggestion_type: 'step_block',
        target_table: 'service_step_blocks',
        target_id: block.id,
        suggested: {
          title: block.title, detail: block.detail,
          kind: block.kind, standard_minutes: block.standard_minutes,
          block_role: block.block_role,
          eixo: block.applies_to_system ?? block.applies_to_verb,
        },
        approved: null,
        verdict: 'rejected',
        reviewer_id: reviewer,
      });

      const { error } = await supabase.from('service_step_blocks').delete().eq('id', block.id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['step-blocks'] }),
  });
}

export function useUpdateBlock() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      id, patch,
    }: { id: string; patch: Partial<Pick<StepBlock, 'title' | 'detail' | 'standard_minutes'>> }) => {
      const { error } = await supabase.from('service_step_blocks').update(patch).eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['step-blocks'] }),
  });
}

/**
 * Quantos serviços do catálogo cada eixo alcança.
 *
 * É o que dá peso à decisão: aprovar o bloco de abertura do elétrico DC não
 * vale por um serviço, vale por dezenas. São 261 linhas — agregar no cliente
 * sai mais barato que uma view só para isso.
 */
export function useBlockImpact() {
  return useQuery({
    queryKey: ['step-blocks-impact'],
    queryFn: async (): Promise<{ porSistema: Record<string, number>; porVerbo: Record<string, number> }> => {
      const { data, error } = await supabase
        .from('services')
        .select('service_verb, service_system')
        .eq('active', true);
      if (error) throw error;

      const porSistema: Record<string, number> = {};
      const porVerbo: Record<string, number> = {};
      for (const s of data || []) {
        if (s.service_system) porSistema[s.service_system] = (porSistema[s.service_system] || 0) + 1;
        if (s.service_verb) porVerbo[s.service_verb] = (porVerbo[s.service_verb] || 0) + 1;
      }
      return { porSistema, porVerbo };
    },
    staleTime: 5 * 60 * 1000,
  });
}

export interface BlockGroup {
  key: string;
  role: BlockRole;
  roleLabel: string;
  eixo: string;
  eixoLabel: string;
  steps: StepBlock[];
  pendentes: number;
  minutosTotais: number;
}

/** Um grupo por (papel × eixo) — é o "bloco" no sentido do plano. */
export function groupBlocks(blocks: StepBlock[]): BlockGroup[] {
  const ordemPapel: Record<BlockRole, number> = { abertura: 1, corpo: 2, fechamento: 3 };
  const mapa = new Map<string, BlockGroup>();

  for (const b of blocks) {
    const eixo = b.applies_to_system ?? b.applies_to_verb ?? '—';
    const key = `${b.block_role}:${eixo}`;
    let g = mapa.get(key);
    if (!g) {
      g = {
        key,
        role: b.block_role,
        roleLabel: ROLE_LABEL[b.block_role] ?? b.block_role,
        eixo,
        eixoLabel:
          b.block_role === 'corpo'
            ? VERB_LABEL[eixo] ?? eixo
            : SYSTEM_LABEL[eixo] ?? eixo,
        steps: [], pendentes: 0, minutosTotais: 0,
      };
      mapa.set(key, g);
    }
    g.steps.push(b);
    if (blockPendingApproval(b)) g.pendentes++;
    g.minutosTotais += b.standard_minutes || 0;
  }

  return [...mapa.values()].sort(
    (a, b) =>
      ordemPapel[a.role] - ordemPapel[b.role] || a.eixoLabel.localeCompare(b.eixoLabel),
  );
}
