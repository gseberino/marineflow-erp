import { useEffect, useMemo, useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Input } from '@/components/ui/input';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Checkbox } from '@/components/ui/checkbox';
import { Loader2, LinkIcon, FileText, Send, RefreshCw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { normalizePhoneE164 } from '@/lib/masks';
import { generatePDFBlob, DEFAULT_PDF_OPTIONS, type PDFDocumentType } from '@/lib/pdf-generator';
import { usePDFData } from '@/hooks/use-pdf';
import { useQueryClient } from '@tanstack/react-query';
import { useWhatsAppTemplates, applyTemplateVariables } from '@/hooks/use-whatsapp-templates';
import {
  useClientWhatsAppSettings,
  pickClientSetting,
  type ClientWhatsAppContext,
} from '@/hooks/use-client-whatsapp-settings';

export type SendViaZAPITarget =
  | {
      kind: 'service_order';
      serviceOrderId: string;
      serviceOrderNumber: string;
      shareToken?: string | null;
      clientId?: string | null;
      clientName?: string | null;
      clientPhone?: string | null;
      documentType?: PDFDocumentType; // 'service_order' | 'quote' (default: service_order)
    }
  | {
      kind: 'receivable';
      receivableId: string;
      description: string;
      serviceOrderId?: string | null;
      shareToken?: string | null;
      clientId?: string | null;
      clientName?: string | null;
      clientPhone?: string | null;
      amount?: number | null;
      dueDate?: string | null;
    };

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  target: SendViaZAPITarget | null;
}

type Mode = 'link' | 'document';

export function SendViaZAPIDialog({ open, onOpenChange, target }: Props) {
  const [mode, setMode] = useState<Mode>('link');
  const [phone, setPhone] = useState('');
  const [message, setMessage] = useState('');
  const [includeLinkInCaption, setIncludeLinkInCaption] = useState(true);
  const [sending, setSending] = useState(false);
  const [templateId, setTemplateId] = useState<string>('');
  const [autoRetry, setAutoRetry] = useState<boolean>(() => {
    try { return localStorage.getItem('zapi.autoRetry') !== '0'; } catch { return true; }
  });
  const [maxAttempts, setMaxAttempts] = useState<number>(() => {
    try {
      const v = parseInt(localStorage.getItem('zapi.maxAttempts') || '3', 10);
      return Number.isFinite(v) && v >= 1 && v <= 5 ? v : 3;
    } catch { return 3; }
  });
  const [attemptInfo, setAttemptInfo] = useState<string>('');
  const queryClient = useQueryClient();

  useEffect(() => {
    try { localStorage.setItem('zapi.autoRetry', autoRetry ? '1' : '0'); } catch {}
  }, [autoRetry]);
  useEffect(() => {
    try { localStorage.setItem('zapi.maxAttempts', String(maxAttempts)); } catch {}
  }, [maxAttempts]);

  const templateCategory =
    target?.kind === 'service_order'
      ? (target.documentType === 'quote' ? 'quote' : 'service_order')
      : 'billing';
  const { data: templates } = useWhatsAppTemplates(templateCategory);

  const clientCtx: ClientWhatsAppContext =
    target?.kind === 'service_order'
      ? (target.documentType === 'quote' ? 'quote' : 'service_order')
      : 'billing';
  const { data: clientSettings } = useClientWhatsAppSettings(
    open ? (target?.clientId ?? null) : null,
  );
  const clientSetting = pickClientSetting(clientSettings, clientCtx);

  // Carrega dados completos quando precisamos gerar PDF
  const pdfSourceId =
    target?.kind === 'service_order'
      ? target.serviceOrderId
      : target?.kind === 'receivable'
      ? target.serviceOrderId || undefined
      : undefined;
  const { data: pdfData } = usePDFData(open && mode === 'document' ? pdfSourceId : undefined);

  const documentType: PDFDocumentType = useMemo(() => {
    if (target?.kind === 'service_order') return target.documentType || 'service_order';
    return 'invoice';
  }, [target]);

  const publicUrl = useMemo(() => {
    if (!target) return '';
    const token = (target as any).shareToken;
    if (!token) return '';
    return `${window.location.origin}/view/${token}`;
  }, [target]);

  // Variáveis disponíveis para placeholders
  const templateVars = useMemo<Record<string, string>>(() => {
    if (!target) return {};
    const base: Record<string, string> = {
      cliente: target.clientName || '',
      link: publicUrl || '',
    };
    if (target.kind === 'service_order') {
      base.os = target.serviceOrderNumber;
      base.descricao = target.serviceOrderNumber;
    } else {
      base.descricao = target.description;
      base.valor = target.amount != null ? String(target.amount) : '';
      base.vencimento = target.dueDate || '';
    }
    return base;
  }, [target, publicUrl]);

  // Defaults ao abrir
  useEffect(() => {
    if (!open || !target) return;
    setPhone(normalizePhoneE164(target.clientPhone || ''));
    setMode('link');
    setIncludeLinkInCaption(true);
    setTemplateId('');
    // Prioridade: config do cliente > template default
    if (clientSetting?.message_body) {
      setMessage(applyTemplateVariables(clientSetting.message_body, templateVars));
      return;
    }
    const name = target.clientName ? ` ${target.clientName}` : '';
    if (target.kind === 'service_order') {
      const label = documentType === 'quote' ? 'Orçamento' : 'Ordem de Serviço';
      setMessage(
        publicUrl
          ? `Olá${name}, segue o link do ${label} ${target.serviceOrderNumber}: ${publicUrl}`
          : `Olá${name}, segue o ${label} ${target.serviceOrderNumber} em anexo.`,
      );
    } else {
      setMessage(`Olá${name}, segue cobrança referente a: ${target.description}.`);
    }
  }, [open, target, publicUrl, documentType, clientSetting?.id, templateVars]);

  const applyTemplate = (id: string) => {
    setTemplateId(id);
    const tpl = templates?.find(t => t.id === id);
    if (!tpl || !target) return;
    const vars: Record<string, string> = {
      cliente: target.clientName || '',
      link: publicUrl || '',
    };
    if (target.kind === 'service_order') {
      vars.os = target.serviceOrderNumber;
      vars.descricao = target.serviceOrderNumber;
    } else {
      vars.descricao = target.description;
      vars.valor = '';
      vars.vencimento = '';
    }
    setMessage(applyTemplateVariables(tpl.body, vars));
  };

  const canSendLink = !!publicUrl && target?.kind === 'service_order';
  const canSendDocument = target?.kind === 'service_order' && !!pdfSourceId;

  // Força modo document para receivable sem link público (raro)
  useEffect(() => {
    if (!canSendLink && mode === 'link' && canSendDocument) setMode('document');
  }, [canSendLink, canSendDocument, mode]);

  if (!target) return null;

  const titleLabel =
    target.kind === 'service_order'
      ? documentType === 'quote'
        ? `Orçamento ${target.serviceOrderNumber}`
        : `OS ${target.serviceOrderNumber}`
      : `Cobrança — ${target.description}`;

  async function uploadPdfBlob(blob: Blob, filename: string): Promise<string> {
    const path = `${new Date().getFullYear()}/${crypto.randomUUID()}-${filename}`;
    const { error } = await supabase.storage
      .from('documents')
      .upload(path, blob, { contentType: 'application/pdf', upsert: false });
    if (error) throw new Error(`Upload falhou: ${error.message}`);
    const { data } = supabase.storage.from('documents').getPublicUrl(path);
    return data.publicUrl;
  }

  async function attemptSend(attempt: number): Promise<void> {
    const phoneClean = phone.replace(/\D/g, '');
    let invokeBody: Record<string, unknown> = { phone: phoneClean, message };

    if (target.kind === 'service_order') {
      invokeBody.service_order_id = target.serviceOrderId;
      invokeBody.context = documentType;
    } else {
      invokeBody.receivable_id = target.receivableId;
      invokeBody.context = 'billing';
      if (target.serviceOrderId) invokeBody.service_order_id = target.serviceOrderId;
    }
    invokeBody.attempt = attempt;

    if (mode === 'link') {
      if (!publicUrl) throw new Error('Esta OS não possui link público.');
      invokeBody.kind = 'link';
      invokeBody.link_url = publicUrl;
      invokeBody.link_title = clientSetting?.link_title
        ? applyTemplateVariables(clientSetting.link_title, templateVars)
        : titleLabel;
      invokeBody.link_description = clientSetting?.link_description
        ? applyTemplateVariables(clientSetting.link_description, templateVars)
        : (target.kind === 'service_order'
            ? 'Toque para visualizar o documento completo.'
            : 'Toque para visualizar a cobrança.');
    } else {
      if (!pdfData) throw new Error('Dados do documento ainda carregando — tente novamente em instantes.');
      // Recalcula o PDF a cada tentativa (garante dados atualizados)
      const blob = await generatePDFBlob(
        { ...pdfData, documentType } as any,
        DEFAULT_PDF_OPTIONS,
      );
      const defaultFilename =
        target.kind === 'service_order'
          ? `${documentType === 'quote' ? 'Orcamento' : 'OS'}-${target.serviceOrderNumber}.pdf`
          : `Cobranca-${target.receivableId.slice(0, 8)}.pdf`;
      const filename = clientSetting?.pdf_filename_pattern
        ? applyTemplateVariables(clientSetting.pdf_filename_pattern, templateVars)
            .replace(/[\\/:*?"<>|]/g, '_')
            .replace(/\.pdf$/i, '') + '.pdf'
        : defaultFilename;
      const url = await uploadPdfBlob(blob, filename);
      invokeBody.kind = 'document';
      invokeBody.document_url = url;
      invokeBody.document_filename = filename;
      invokeBody.document_caption = includeLinkInCaption && publicUrl
        ? `${message}\n\nLink online: ${publicUrl}`
        : message;
    }

    const { data, error } = await supabase.functions.invoke('whatsapp-send', {
      body: invokeBody,
    });
    if (error) throw error;
    if ((data as any)?.error) throw new Error((data as any).error);
  }

  async function handleSend() {
    if (!phone || phone.replace(/\D/g, '').length < 10) {
      toast.error('Telefone inválido. Inclua DDI+DDD.');
      return;
    }
    setSending(true);
    setAttemptInfo('');
    const tId = toast.loading(
      mode === 'document' ? 'Gerando PDF e enviando…' : 'Enviando mensagem…',
    );
    const total = autoRetry ? Math.max(1, maxAttempts) : 1;
    let lastErr: any = null;
    try {
      for (let attempt = 1; attempt <= total; attempt++) {
        try {
          if (attempt > 1) {
            setAttemptInfo(`Tentativa ${attempt}/${total}…`);
            toast.loading(`Reenviando (tentativa ${attempt}/${total})…`, { id: tId });
          }
          await attemptSend(attempt);
          toast.success(
            attempt > 1 ? `Enviado na tentativa ${attempt}/${total}!` : 'Enviado com sucesso!',
            { id: tId },
          );
          queryClient.invalidateQueries({ queryKey: ['whatsapp-send-status'] });
          queryClient.invalidateQueries({ queryKey: ['whatsapp-send-history'] });
          onOpenChange(false);
          return;
        } catch (err: any) {
          lastErr = err;
          console.warn(`SendViaZAPI tentativa ${attempt}/${total} falhou`, err);
          if (attempt < total) {
            // Backoff exponencial leve: 1s, 2s, 4s…
            const delay = Math.min(8000, 1000 * Math.pow(2, attempt - 1));
            await new Promise(r => setTimeout(r, delay));
          }
        }
      }
      throw lastErr || new Error('Falha desconhecida');
    } catch (err: any) {
      console.error('SendViaZAPI error final', err);
      toast.error(
        `Falha após ${total} tentativa${total > 1 ? 's' : ''}: ${err?.message || 'erro desconhecido'}`,
        { id: tId },
      );
      queryClient.invalidateQueries({ queryKey: ['whatsapp-send-status'] });
      queryClient.invalidateQueries({ queryKey: ['whatsapp-send-history'] });
    } finally {
      setSending(false);
      setAttemptInfo('');
    }
  }

  return (
    <Dialog open={open} onOpenChange={(v) => !sending && onOpenChange(v)}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Send className="h-5 w-5" /> Enviar via Z-API
          </DialogTitle>
          <DialogDescription>{titleLabel}</DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-2">
            <Label>Modo de envio</Label>
            <RadioGroup
              value={mode}
              onValueChange={(v) => setMode(v as Mode)}
              className="grid grid-cols-2 gap-2"
            >
              <label
                className={`flex items-start gap-2 rounded-lg border p-3 cursor-pointer transition ${
                  mode === 'link' ? 'border-accent bg-accent/5' : 'hover:bg-muted/40'
                } ${!canSendLink ? 'opacity-50 cursor-not-allowed' : ''}`}
              >
                <RadioGroupItem value="link" disabled={!canSendLink} className="mt-0.5" />
                <div>
                  <div className="font-medium text-sm flex items-center gap-1.5">
                    <LinkIcon className="h-3.5 w-3.5" /> Link com preview
                  </div>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    Card clicável apontando para a página pública.
                  </p>
                </div>
              </label>
              <label
                className={`flex items-start gap-2 rounded-lg border p-3 cursor-pointer transition ${
                  mode === 'document' ? 'border-accent bg-accent/5' : 'hover:bg-muted/40'
                } ${!canSendDocument ? 'opacity-50 cursor-not-allowed' : ''}`}
              >
                <RadioGroupItem value="document" disabled={!canSendDocument} className="mt-0.5" />
                <div>
                  <div className="font-medium text-sm flex items-center gap-1.5">
                    <FileText className="h-3.5 w-3.5" /> PDF anexado
                  </div>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    Gera e anexa o arquivo .pdf na mensagem.
                  </p>
                </div>
              </label>
            </RadioGroup>
            {!canSendLink && (
              <p className="text-xs text-muted-foreground">
                ⚠ OS sem link público — apenas envio por PDF disponível.
              </p>
            )}
          </div>

          <div className="space-y-2">
            <Label htmlFor="phone-zapi">Telefone (com DDI)</Label>
            <Input
              id="phone-zapi"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="5521999998888"
            />
          </div>

          {!!templates?.length && (
            <div className="space-y-2">
              <Label>Template</Label>
              <select
                className="w-full h-10 rounded-md border border-input bg-background px-3 text-sm"
                value={templateId}
                onChange={(e) => applyTemplate(e.target.value)}
              >
                <option value="">— mensagem livre —</option>
                {templates.map(t => (
                  <option key={t.id} value={t.id}>{t.name}</option>
                ))}
              </select>
            </div>
          )}

          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <Label htmlFor="msg-zapi">
                {mode === 'document' ? 'Legenda do PDF' : 'Mensagem'}
              </Label>
              {clientSetting?.message_body && (
                <span className="text-xs text-muted-foreground">
                  ✓ Usando mensagem padrão do cliente
                </span>
              )}
            </div>
            <Textarea
              id="msg-zapi"
              rows={4}
              value={message}
              onChange={(e) => setMessage(e.target.value)}
            />
          </div>

          {mode === 'document' && publicUrl && (
            <label className="flex items-center gap-2 text-sm">
              <Checkbox
                checked={includeLinkInCaption}
                onCheckedChange={(v) => setIncludeLinkInCaption(!!v)}
              />
              Incluir também o link online na legenda
            </label>
          )}

          <div className="rounded-lg border p-3 space-y-2 bg-muted/30">
            <label className="flex items-center gap-2 text-sm font-medium cursor-pointer">
              <Checkbox
                checked={autoRetry}
                onCheckedChange={(v) => setAutoRetry(!!v)}
              />
              <RefreshCw className="h-3.5 w-3.5" />
              Reenviar automaticamente em caso de falha
            </label>
            {autoRetry && (
              <div className="flex items-center gap-2 text-xs text-muted-foreground pl-6 flex-wrap">
                <span>Máx. tentativas:</span>
                <select
                  className="h-7 rounded border border-input bg-background px-2 text-xs"
                  value={maxAttempts}
                  onChange={(e) => setMaxAttempts(parseInt(e.target.value, 10))}
                  disabled={sending}
                >
                  {[2, 3, 4, 5].map(n => (
                    <option key={n} value={n}>{n}</option>
                  ))}
                </select>
                <span>(backoff 1s → 2s → 4s; PDF é recalculado a cada tentativa)</span>
              </div>
            )}
            {attemptInfo && (
              <p className="text-xs text-accent pl-6">{attemptInfo}</p>
            )}
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={sending}>
            Cancelar
          </Button>
          <Button onClick={handleSend} disabled={sending} className="gap-2">
            {sending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
            Enviar agora
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
