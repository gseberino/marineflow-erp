// Triagem das fotos de "Envio da câmera" (Fase 4, 08/10/2026 — plans/marineflow-dropbox-fase2.md).
// Tudo passa pela edge dropbox-fotos (só admin): o token do Dropbox nunca chega ao navegador.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { extractInvokeErrorMessage } from '@/lib/invoke-error';

export interface FotoNaCaixa {
  id: string;
  nome: string;
  tamanho: number;
  dia: string | null;
  hora: string | null;
  tipo: 'foto' | 'video' | 'print' | 'outro';
}

export interface OsSugerida {
  id: string;
  numero: string;
  barco: string | null;
  cliente: string | null;
  status: string;
  nota: number;
  motivos: string[];
}

async function chamar<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke('dropbox-fotos', { body });
  if (error) throw new Error(await extractInvokeErrorMessage(error));
  return data as T;
}

export function useFotosDaCaixa() {
  return useQuery({
    queryKey: ['triagem-fotos'],
    queryFn: () => chamar<{ pasta: string; itens: FotoNaCaixa[] }>({ acao: 'listar' }),
    retry: false,
    staleTime: 60_000,
  });
}

/** Miniaturas em JPEG base64 (até 25 por pedido; a tela pede por dia). */
export function useMiniaturas(ids: string[], ligado: boolean) {
  return useQuery({
    queryKey: ['triagem-miniaturas', ids],
    enabled: ligado && ids.length > 0,
    staleTime: 30 * 60_000,
    queryFn: async () => {
      const todas: Record<string, string> = {};
      for (let i = 0; i < ids.length; i += 25) {
        const r = await chamar<{ miniaturas: Record<string, string> }>({ acao: 'miniaturas', ids: ids.slice(i, i + 25) });
        Object.assign(todas, r.miniaturas);
      }
      return todas;
    },
  });
}

export function useSugestoes(dias: string[]) {
  return useQuery({
    queryKey: ['triagem-sugestoes', dias],
    enabled: dias.length > 0,
    staleTime: 5 * 60_000,
    queryFn: async () => {
      const todas: Record<string, OsSugerida[]> = {};
      for (let i = 0; i < dias.length; i += 60) {
        const r = await chamar<{ sugestoes: Record<string, OsSugerida[]> }>({ acao: 'sugestoes', dias: dias.slice(i, i + 60) });
        Object.assign(todas, r.sugestoes);
      }
      return todas;
    },
  });
}

export interface OsParaEscolher {
  id: string;
  service_order_number: string;
  status: string;
  vessels: { name: string } | null;
  clients: { name: string } | null;
}

/** As OS para a escolha manual ("outra OS"), das mais recentes. */
export function useOsRecentes() {
  return useQuery({
    queryKey: ['triagem-os-recentes'],
    staleTime: 5 * 60_000,
    queryFn: async (): Promise<OsParaEscolher[]> => {
      const { data, error } = await supabase
        .from('service_orders')
        .select('id, service_order_number, status, vessels(name), clients(name)')
        .neq('status', 'cancelled')
        .order('updated_at', { ascending: false })
        .limit(200);
      if (error) throw new Error(error.message);
      return (data ?? []) as unknown as OsParaEscolher[];
    },
  });
}

export function useMoverFotos() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (p: { itens: Array<{ id: string; nome: string; dia: string }>; order_id: string }) =>
      chamar<{ movidas: number; falharam: number; destino: string; pendente?: boolean; aviso?: string }>({ acao: 'mover', ...p }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['triagem-fotos'] });
      qc.invalidateQueries({ queryKey: ['dropbox-arquivos'] });
    },
  });
}
