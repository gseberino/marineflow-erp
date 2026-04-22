import { useEffect, useMemo, useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Checkbox } from '@/components/ui/checkbox';
import { Loader2, Send } from 'lucide-react';
import { normalizePhoneE164 } from '@/lib/masks';
import { type PDFDocumentType } from '@/lib/pdf-generator';
import { usePDFData } from '@/hooks/use-pdf';
import { useWhatsAppTemplates, applyTemplateVariables } from '@/hooks/use-whatsapp-templates';
import {
  useClientWhatsAppSettings,
  pickClientSetting,
  type ClientWhatsAppContext,
} from '@/hooks/use-client-whatsapp-settings';
import { ModeSelector, type SendMode } from '@/components/zapi/ModeSelector';
import { RetrySettings } from '@/components/zapi/RetrySettings';
import { MessageEditor } from '@/components/zapi/MessageEditor';
import { ScheduleSettings, defaultScheduleConfig, type ScheduleConfig } from '@/components/zapi/ScheduleSettings';
import { useZApiSend } from '@/hooks/use-zapi-send';
import { useCreateScheduledSend } from '@/hooks/use-scheduled-sends';

export type SendViaZAPITarget =
  | {
      kind: 'service_order';
      serviceOrderId: string;
      serviceOrderNumber: string;
      shareToken?: string | null;
      clientId?: string | null;
      clientName?: string | null;
      clientPhone?: string | null;
      documentType?: PDFDocumentType;
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

export function SendViaZAPIDialog({ open, onOpenChange, target }: Props) {
  const [mode, setMode] = useState<SendMode>('link');
  const [phone, setPhone] = useState('');
  const [message, setMessage] = useState('');
  const [includeLinkInCaption, setIncludeLinkInCaption] = useState(true);
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

  const [schedule, setSchedule] = useState<ScheduleConfig>(defaultScheduleConfig());

  const { send, sending, attemptInfo } = useZApiSend();
  const createScheduled = useCreateScheduledSend();

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

  useEffect(() => {
    if (!open || !target) return;
    setPhone(normalizePhoneE164(target.clientPhone || ''));
    setMode('link');
    setIncludeLinkInCaption(true);
    setTemplateId('');
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
    setMessage(applyTemplateVariables(tpl.body, templateVars));
  };

  const canSendLink = !!publicUrl && target?.kind === 'service_order';
  const canSendDocument = target?.kind === 'service_order' && !!pdfSourceId;

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

  async function handleSend() {
    if (!target) return;
    const defaultFilename =
      target.kind === 'service_order'
        ? `${documentType === 'quote' ? 'Orcamento' : 'OS'}-${target.serviceOrderNumber}.pdf`
        : `Cobranca-${target.receivableId.slice(0, 8)}.pdf`;
    const filename = clientSetting?.pdf_filename_pattern
      ? applyTemplateVariables(clientSetting.pdf_filename_pattern, templateVars)
          .replace(/[\\/:*?"<>|]/g, '_')
          .replace(/\.pdf$/i, '') + '.pdf'
      : defaultFilename;

    const link_title = clientSetting?.link_title
      ? applyTemplateVariables(clientSetting.link_title, templateVars)
      : titleLabel;
    const link_description = clientSetting?.link_description
      ? applyTemplateVariables(clientSetting.link_description, templateVars)
      : (target.kind === 'service_order'
          ? 'Toque para visualizar o documento completo.'
          : 'Toque para visualizar a cobrança.');

    const caption = includeLinkInCaption && publicUrl
      ? `${message}\n\nLink online: ${publicUrl}`
      : message;

    const ok = await send(
      {
        phone,
        message,
        mode,
        context: target.kind === 'service_order' ? documentType : 'billing',
        service_order_id:
          target.kind === 'service_order'
            ? target.serviceOrderId
            : target.serviceOrderId || undefined,
        receivable_id: target.kind === 'receivable' ? target.receivableId : undefined,
        publicUrl,
        link_title,
        link_description,
        pdfData,
        documentType,
        filename,
        caption,
      },
      { autoRetry, maxAttempts },
    );
    if (ok) onOpenChange(false);
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
          <ModeSelector
            mode={mode}
            onChange={setMode}
            canSendLink={canSendLink}
            canSendDocument={canSendDocument}
          />

          <div className="space-y-2">
            <Label htmlFor="phone-zapi">Telefone (com DDI)</Label>
            <Input
              id="phone-zapi"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="5521999998888"
            />
          </div>

          <MessageEditor
            message={message}
            onMessageChange={setMessage}
            mode={mode}
            templates={templates}
            templateId={templateId}
            onTemplateChange={applyTemplate}
            usingClientDefault={!!clientSetting?.message_body}
          />

          {mode === 'document' && publicUrl && (
            <label className="flex items-center gap-2 text-sm">
              <Checkbox
                checked={includeLinkInCaption}
                onCheckedChange={(v) => setIncludeLinkInCaption(!!v)}
              />
              Incluir também o link online na legenda
            </label>
          )}

          <RetrySettings
            autoRetry={autoRetry}
            onAutoRetryChange={setAutoRetry}
            maxAttempts={maxAttempts}
            onMaxAttemptsChange={setMaxAttempts}
            attemptInfo={attemptInfo}
            disabled={sending}
          />
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
