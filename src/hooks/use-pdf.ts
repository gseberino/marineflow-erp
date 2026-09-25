import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { PDFData } from '@/lib/pdf-generator';
import {
  carregarPDFData as montarPDFData,
  type LeitorDoBanco,
} from '../../supabase/functions/_shared/pdf/dados';

/**
 * Monta o PDFData de uma ordem — a única fonte.
 *
 * A montagem mora em supabase/functions/_shared/pdf/dados.ts, para o assistente do
 * WhatsApp gerar o mesmo documento que a tela. Aqui ela só ganha o cliente da sessão como
 * padrão; o portal passa o cliente do token do link (ver o comentário lá).
 */
export async function carregarPDFData(
  serviceOrderId: string,
  db: LeitorDoBanco = supabase,
): Promise<PDFData> {
  return montarPDFData(serviceOrderId, db);
}

export function usePDFData(serviceOrderId: string | undefined) {
  return useQuery({
    queryKey: ['pdf-data', serviceOrderId],
    queryFn: async () => {
      if (!serviceOrderId) return null;
      return carregarPDFData(serviceOrderId);
    },
    enabled: !!serviceOrderId,
    staleTime: 0,
  });
}

/**
 * Versão imperativa, para quem não está num componente — download em lote,
 * anexo de WhatsApp. Devolve null em vez de lançar: quem chama trata ausência,
 * não exceção.
 */
export async function fetchPDFData(
  serviceOrderId: string,
  db?: Pick<typeof supabase, 'from'>,
): Promise<PDFData | null> {
  try {
    return await carregarPDFData(serviceOrderId, db);
  } catch (e) {
    console.error('[fetchPDFData] failed:', e);
    return null;
  }
}
