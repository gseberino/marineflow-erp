// [F-NFSE-01] NFS-e — pré-voo, emissão, status, artefatos e cancelamento.
//
// Tudo passa pela edge function `fiscal-emit`: o token da Contora é secret do servidor e
// nunca chega ao navegador.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

/** Faixa da justificativa de cancelamento, igual à do servidor e à da doc da Contora. */
export const MIN_JUSTIFICATIVA = 15;
export const MAX_JUSTIFICATIVA = 255;

export interface DocumentoNfse {
  id: string;
  number: number | null;
  series: number | null;
  status: string;
  environment: string;
  status_message: string | null;
  created_at: string | null;
  origin_id: string | null;
}

export interface NfseHealth {
  pronto: boolean;
  empresa?: { id: string; legal_name?: string | null; document?: string | null };
  contora?: {
    ready?: boolean;
    standard?: string | null;
    city_code?: string | null;
    city_name?: string | null;
    certificate_ok?: boolean;
    certificate_valid_until?: string | null;
    pending?: string[];
    erro?: string;
  };
  cadastro?: Record<string, unknown> | null;
  pendencias_locais?: string[];
  divergencia_de_padrao?: string | null;
}

/**
 * Lê o corpo do erro da edge function.
 *
 * `functions.invoke` devolve só "non-2xx status code" e joga o motivo real no corpo — e o
 * motivo real aqui é justamente o que ensina a corrigir ("falta o percentual do Simples",
 * "códigos de tributação diferentes"). Sem isto, toda rejeição vira a mesma frase inútil.
 */
async function chamar<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke('fiscal-emit', { body });
  if (error) {
    const resposta = (error as { context?: Response }).context;
    if (resposta && typeof resposta.json === 'function') {
      try {
        const corpo = await resposta.json();
        if (corpo?.error) {
          const e = new Error(String(corpo.error));
          // Preserva o sinal de "não adianta repetir" para a tela decidir o que oferecer.
          (e as Error & { cancelUnsupported?: boolean }).cancelUnsupported =
            corpo.cancel_unsupported === true;
          throw e;
        }
      } catch (e) {
        if (e instanceof Error && !e.message.includes('non-2xx')) throw e;
      }
    }
    throw error;
  }
  if ((data as { error?: string })?.error) throw new Error(String((data as { error: string }).error));
  return data as T;
}

export function useNfseHealth() {
  return useQuery({
    queryKey: ['nfse-health'],
    queryFn: async (): Promise<NfseHealth> => {
      const r = await chamar<{ data: NfseHealth }>({ action: 'nfse_health' });
      return r.data;
    },
    // Pré-voo é consulta de cadastro e certificado: muda raramente, e cada chamada bate na
    // Contora. Cinco minutos evita transformar abrir a tela em tráfego.
    staleTime: 5 * 60_000,
    retry: false,
  });
}

export function useNfseDocumentos() {
  return useQuery({
    queryKey: ['nfse-documentos'],
    queryFn: async (): Promise<DocumentoNfse[]> => {
      const { data, error } = await supabase
        .from('issued_fiscal_documents')
        .select('id, number, series, status, environment, status_message, created_at, origin_id')
        .eq('document_type', 'nfse')
        .order('created_at', { ascending: false })
        .order('id', { ascending: true })
        .limit(200);
      if (error) throw error;
      return (data ?? []) as unknown as DocumentoNfse[];
    },
    staleTime: 30_000,
  });
}

export function useEmitirNfse() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { serviceOrderId: string }) => {
      return await chamar<{ data: { id: string; status: string }; aviso?: string }>({
        document_type: 'nfse',
        service_order_id: v.serviceOrderId,
        // Estável por OS: um duplo clique não vira duas notas de serviço para o mesmo
        // trabalho. O servidor tem a própria guarda, esta é a primeira linha.
        idempotency_key: `nfse-os-${v.serviceOrderId}`,
      });
    },
    onSuccess: (r) => {
      qc.invalidateQueries({ queryKey: ['nfse-documentos'] });
      if (r.aviso) toast.warning(r.aviso, { duration: 12_000 });
      else toast.success('NFS-e enviada. Acompanhe o status abaixo.');
    },
    onError: (e: Error) => toast.error(e.message, { duration: 12_000 }),
  });
}

export function useCancelarNfse() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { documentId: string; motivo: string }) => {
      return await chamar({ action: 'cancel', document_id: v.documentId, reason: v.motivo });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['nfse-documentos'] });
      toast.success('Cancelamento enviado.');
    },
    onError: (e: Error) => {
      // Município que não cancela por webservice: repetir não adianta, então a mensagem
      // fica mais tempo na tela e não sugere nova tentativa.
      const semSuporte = (e as Error & { cancelUnsupported?: boolean }).cancelUnsupported;
      toast.error(e.message, { duration: semSuporte ? 20_000 : 10_000 });
    },
  });
}

export function useAtualizarStatusNfse() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async () => await chamar({ action: 'reconcile' }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['nfse-documentos'] });
      toast.success('Status sincronizado.');
    },
    onError: (e: Error) => toast.error(e.message),
  });
}

export function useArtefatoNfse() {
  return useMutation({
    mutationFn: async (v: { documentId: string; tipo: 'xml' | 'pdf' }) => {
      // O download passa pelo servidor porque as URLs da Contora são autenticadas (Bearer):
      // abrir no navegador devolve "token ausente".
      const r = await chamar<{ data: { filename: string; content_base64: string; content_type: string } }>({
        action: 'artifact',
        document_id: v.documentId,
        artifact_type: v.tipo === 'xml' ? 'xml_authorized' : 'pdf_danfse',
      });
      return r.data;
    },
    onSuccess: (d) => {
      const bin = atob(d.content_base64);
      const bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      const url = URL.createObjectURL(new Blob([bytes], { type: d.content_type }));
      const a = document.createElement('a');
      a.href = url;
      a.download = d.filename;
      a.click();
      URL.revokeObjectURL(url);
    },
    onError: (e: Error) => toast.error(`Não deu para baixar: ${e.message}`),
  });
}
