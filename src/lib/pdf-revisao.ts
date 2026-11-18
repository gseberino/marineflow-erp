import { supabase } from '@/integrations/supabase/client';
import { createShareClient } from '@/integrations/supabase/share-client';
import { carimbarRevisao, type ChamadorDeRpc } from '../../supabase/functions/_shared/pdf/revisao';
import type { PDFData } from '../../supabase/functions/_shared/pdf/documento';

/** Avisado (com o id da ordem) quando um PDF é gerado: a tela relê a revisão (useRevisaoDoDocumento). */
export const EVENTO_REVISAO_EMITIDA = 'mf:revisao-emitida';

/**
 * A revisão do documento pedida pela TELA (sessão do usuário) ou pelo PORTAL (token do link no cabeçalho).
 *
 * Fica fora de pdf-generator.ts porque aquele arquivo é lib pura, testada sem cliente do Supabase; ele importa
 * este sob demanda, só quando o documento é de uma ordem real (tem id) e ainda não tem a revisão.
 */
export async function comRevisao(data: PDFData, ctx?: { shareToken?: string }): Promise<PDFData> {
  const db = ctx?.shareToken ? createShareClient(ctx.shareToken) : supabase;
  const carimbado = await carimbarRevisao(db as unknown as ChamadorDeRpc, data);
  if (carimbado.revisao && data.serviceOrder?.id && typeof window !== 'undefined') {
    window.dispatchEvent(new CustomEvent(EVENTO_REVISAO_EMITIDA, { detail: data.serviceOrder.id }));
  }
  return carimbado;
}
