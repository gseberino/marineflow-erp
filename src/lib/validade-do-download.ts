import { supabase } from '@/integrations/supabase/client';
import type { PDFOptions } from '@/lib/pdf-generator';

// Retorno rápido, F5, dúvida 5 (dono, 13/11/2026: "Sim, o download também fixa hoje + 7"). O "Baixar PDF" de um orçamento
// ainda não enviado fixa a validade como o envio pelo sistema (K6: hoje + os dias da empresa), gravada no orçamento, e o PDF
// sai com essa data: quase todo download é para mandar pelo celular, e sem a data fixa o orçamento fica sem lembrete.
// Baixar de novo antes de mandar refaz a data. Já enviado: a data do 1º envio. Chave desligada, cargo, vencida ou erro:
// o PDF sai como antes (a validade do cadastro). Só o BAIXAR: o imprimir abre janela, e esperar o banco antes dela
// faria o bloqueador de pop-up barrar a impressão.

const DIA_ISO = /^\d{4}-\d{2}-\d{2}$/;
// Os mesmos do diálogo de envio (SendViaWhatsAppDialog): sem a data da F5.
const SEM_A_F5 = new Set(['desligada', 'funil', 'cargo', 'erro', 'mudou', 'vencida']);

/** A data (aaaa-mm-dd) que o PDF baixado deve levar, já gravada no orçamento; null = o PDF de antes. Nunca lança. */
export async function validadeDoDownload(osId: string | null | undefined): Promise<string | null> {
  if (!osId) return null;
  try {
    const { data, error } = await supabase.rpc('orcamento_validade_do_envio', { p_os: osId, p_gravar: true });
    if (error) return null;
    const d = (data ?? {}) as Record<string, unknown>;
    if (d.ok !== true) return null;
    const motivo = d.fixou === true ? 'fixou' : typeof d.motivo === 'string' && d.motivo ? d.motivo : 'erro';
    if (SEM_A_F5.has(motivo)) return null;
    return typeof d.data === 'string' && DIA_ISO.test(d.data) ? d.data : null;
  } catch {
    return null;
  }
}

/** As opções do PDF com a validade do download, só no orçamento; nos outros documentos, as mesmas opções. */
export async function comValidadeDoDownload(osId: string | null | undefined, tipo: string,
                                            opcoes: PDFOptions): Promise<PDFOptions> {
  if (tipo !== 'quote') return opcoes;
  const dia = await validadeDoDownload(osId);
  return dia ? { ...opcoes, validity: { mode: 'date', date: dia } } : opcoes;
}
