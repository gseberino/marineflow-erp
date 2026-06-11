import { useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { useQueryClient } from '@tanstack/react-query';
import { generatePDFBlob, DEFAULT_PDF_OPTIONS, type PDFDocumentType } from '@/lib/pdf-generator';

export interface WhatsAppSendPayload {
  phone: string;
  message: string;
  mode: 'link' | 'document';
  // common
  context: 'service_order' | 'quote' | 'billing' | string;
  service_order_id?: string;
  receivable_id?: string;
  // link mode
  publicUrl?: string;
  link_title?: string;
  link_description?: string;
  // document mode
  pdfData?: any;
  documentType?: PDFDocumentType;
  filename?: string;
  caption?: string;
}

export interface RetryConfig {
  autoRetry: boolean;
  maxAttempts: number;
}

async function uploadPdfBlob(blob: Blob, filename: string): Promise<string> {
  const path = `${new Date().getFullYear()}/${crypto.randomUUID()}-${filename}`;
  const { error } = await supabase.storage
    .from('documents')
    .upload(path, blob, { contentType: 'application/pdf', upsert: false });
  if (error) throw new Error(`Upload falhou: ${error.message}`);
  const { data } = supabase.storage.from('documents').getPublicUrl(path);
  return data.publicUrl;
}

export function useWhatsAppSend() {
  const [sending, setSending] = useState(false);
  const [attemptInfo, setAttemptInfo] = useState('');
  const queryClient = useQueryClient();

  async function attemptSend(payload: ZApiSendPayload, attempt: number): Promise<void> {
    const phoneClean = payload.phone.replace(/\D/g, '');
    const invokeBody: Record<string, unknown> = {
      phone: phoneClean,
      message: payload.message,
      context: payload.context,
      attempt,
    };
    if (payload.service_order_id) invokeBody.service_order_id = payload.service_order_id;
    if (payload.receivable_id) invokeBody.receivable_id = payload.receivable_id;

    if (payload.mode === 'link') {
      if (!payload.publicUrl) throw new Error('Sem link público disponível.');
      invokeBody.kind = 'link';
      invokeBody.link_url = payload.publicUrl;
      invokeBody.link_title = payload.link_title || '';
      invokeBody.link_description = payload.link_description || '';
    } else {
      if (!payload.pdfData) throw new Error('Dados do documento ainda carregando — tente novamente.');
      const blob = await generatePDFBlob(
        { ...payload.pdfData, documentType: payload.documentType } as any,
        DEFAULT_PDF_OPTIONS,
      );
      const filename = payload.filename || 'documento.pdf';
      const url = await uploadPdfBlob(blob, filename);
      invokeBody.kind = 'document';
      invokeBody.document_url = url;
      invokeBody.document_filename = filename;
      invokeBody.document_caption = payload.caption || payload.message;
    }

    const { data, error } = await supabase.functions.invoke('whatsapp-send', { body: invokeBody });
    if (error) throw error;
    if ((data as any)?.error) throw new Error((data as any).error);
  }

  async function send(payload: ZApiSendPayload, retry: RetryConfig): Promise<boolean> {
    if (!payload.phone || payload.phone.replace(/\D/g, '').length < 10) {
      toast.error('Telefone inválido. Inclua DDI+DDD.');
      return false;
    }
    setSending(true);
    setAttemptInfo('');
    const tId = toast.loading(
      payload.mode === 'document' ? 'Gerando PDF e enviando…' : 'Enviando mensagem…',
    );
    const total = retry.autoRetry ? Math.max(1, retry.maxAttempts) : 1;
    let lastErr: any = null;
    try {
      for (let attempt = 1; attempt <= total; attempt++) {
        try {
          if (attempt > 1) {
            setAttemptInfo(`Tentativa ${attempt}/${total}…`);
            toast.loading(`Reenviando (tentativa ${attempt}/${total})…`, { id: tId });
          }
          await attemptSend(payload, attempt);
          toast.success(
            attempt > 1 ? `Enviado na tentativa ${attempt}/${total}!` : 'Enviado com sucesso!',
            { id: tId },
          );
          queryClient.invalidateQueries({ queryKey: ['whatsapp-send-status'] });
          queryClient.invalidateQueries({ queryKey: ['whatsapp-send-history'] });
          return true;
        } catch (err: any) {
          lastErr = err;
          console.warn(`WhatsApp tentativa ${attempt}/${total} falhou`, err);
          if (attempt < total) {
            const delay = Math.min(8000, 1000 * Math.pow(2, attempt - 1));
            await new Promise((r) => setTimeout(r, delay));
          }
        }
      }
      throw lastErr || new Error('Falha desconhecida');
    } catch (err: any) {
      console.error('WhatsApp erro final', err);
      toast.error(
        `Falha após ${total} tentativa${total > 1 ? 's' : ''}: ${err?.message || 'erro desconhecido'}`,
        { id: tId },
      );
      queryClient.invalidateQueries({ queryKey: ['whatsapp-send-status'] });
      queryClient.invalidateQueries({ queryKey: ['whatsapp-send-history'] });
      return false;
    } finally {
      setSending(false);
      setAttemptInfo('');
    }
  }

  return { send, sending, attemptInfo };
}
