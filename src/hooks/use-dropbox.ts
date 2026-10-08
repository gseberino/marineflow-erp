// A pasta do barco no Dropbox e o "salvar agora" (Fase 2B/2C, 08/10/2026 —
// plans/marineflow-dropbox-fase2.md). Só o admin enxerga (RLS de pastas_dropbox e dropbox_envios);
// para os outros cargos as consultas voltam vazias e os botões não aparecem.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { extractInvokeErrorMessage } from '@/lib/invoke-error';

// As tabelas novas ainda não estão nos tipos gerados.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const db = supabase as any;

export interface PastaDoBarco {
  caminho: string;
  codigo_projeto: string | null;
}

export interface EnvioDropbox {
  id: string;
  motivo: string;
  status: 'pendente' | 'processando' | 'feito' | 'ignorado' | 'falhou';
  resultado: string | null;
  caminho: string | null;
  versao: number | null;
  created_at: string;
}

/** Link para abrir no site do Dropbox (precisa estar logado na conta da HBR). */
export function linkNoDropbox(caminho: string): string {
  return 'https://www.dropbox.com/home' + caminho.split('/').map((p) => encodeURIComponent(p)).join('/');
}

export function usePastaDoBarco(vesselId: string | null | undefined) {
  return useQuery({
    queryKey: ['dropbox-pasta', vesselId],
    enabled: !!vesselId,
    queryFn: async (): Promise<PastaDoBarco | null> => {
      const { data, error } = await db
        .from('pastas_dropbox')
        .select('caminho, codigo_projeto')
        .eq('vessel_id', vesselId)
        .eq('situacao', 'vinculada')
        .order('codigo_projeto', { ascending: false, nullsFirst: false })
        .limit(1);
      if (error) throw new Error(error.message);
      return (data?.[0] as PastaDoBarco | undefined) ?? null;
    },
  });
}

export function useEnviosDaOrdem(orderId: string | null | undefined) {
  return useQuery({
    queryKey: ['dropbox-envios', orderId],
    enabled: !!orderId,
    queryFn: async (): Promise<EnvioDropbox[]> => {
      const { data, error } = await db
        .from('dropbox_envios')
        .select('id, motivo, status, resultado, caminho, versao, created_at')
        .eq('order_id', orderId)
        .order('created_at', { ascending: false })
        .limit(10);
      if (error) throw new Error(error.message);
      return (data ?? []) as EnvioDropbox[];
    },
  });
}

type Relatorio = { ok?: boolean; processados?: number; motivo?: string; relatorio?: Array<{ id: string; status: string; resultado: string }> };

/**
 * Pede à fila (criar a pasta do barco ou guardar o PDF da ordem agora) e já chama o worker.
 * Devolve o que aconteceu com ESTE pedido, ou "na fila" se o worker ainda não chegou nele.
 */
export function usePedirAoDropbox() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (p: { orderId?: string; vesselId?: string; motivo: 'pasta' | 'manual' }) => {
      const { data: inserido, error } = await db
        .from('dropbox_envios')
        .insert({ order_id: p.orderId ?? null, vessel_id: p.vesselId ?? null, motivo: p.motivo })
        .select('id')
        .maybeSingle();
      // 23505 = já tem um pedido igual esperando: segue e chama o worker do mesmo jeito.
      if (error && error.code !== '23505') throw new Error(error.message);
      const meuId: string | null = inserido?.id ?? null;

      const { data, error: eInv } = await supabase.functions.invoke('dropbox-worker', { body: {} });
      if (eInv) throw new Error(await extractInvokeErrorMessage(eInv));
      const r = data as Relatorio;
      if (r?.motivo) return { status: 'pendente', resultado: r.motivo };
      const meu = r?.relatorio?.find((x) => x.id === meuId);
      return meu ?? { status: 'pendente', resultado: 'Na fila: sai em até 5 minutos.' };
    },
    onSettled: (_d, _e, p) => {
      qc.invalidateQueries({ queryKey: ['dropbox-pasta'] });
      if (p.orderId) qc.invalidateQueries({ queryKey: ['dropbox-envios', p.orderId] });
    },
  });
}
