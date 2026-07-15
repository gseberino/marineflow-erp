import { useEffect, useMemo, useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Checkbox } from '@/components/ui/checkbox';
import { Loader2, Send, CalendarClock, Sparkles } from 'lucide-react';
import { toast } from 'sonner';
import { normalizePhoneE164 } from '@/lib/masks';
import { type PDFDocumentType, resolvePdfOptions } from '@/lib/pdf-generator';
import { usePDFData } from '@/hooks/use-pdf';
import { useAppSettings } from '@/hooks/use-app-settings';
import { useWhatsAppTemplates, applyTemplateVariables } from '@/hooks/use-whatsapp-templates';
import {
  useClientWhatsAppSettings,
  pickClientSetting,
  type ClientWhatsAppContext,
} from '@/hooks/use-client-whatsapp-settings';
import { ModeSelector, type SendMode } from '@/components/whatsapp/ModeSelector';
import { RetrySettings } from '@/components/whatsapp/RetrySettings';
import { MessageEditor } from '@/components/whatsapp/MessageEditor';
import { ScheduleSettings, defaultScheduleConfig, type ScheduleConfig } from '@/components/whatsapp/ScheduleSettings';
import { useWhatsAppSend } from '@/hooks/use-whatsapp-send';
import { useCreateScheduledSend } from '@/hooks/use-scheduled-sends';
import { supabase } from '@/integrations/supabase/client';

export type SendViaWhatsAppTarget =
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
  target: SendViaWhatsAppTarget | null;
}

export function SendViaWhatsAppDialog({ open, onOpenChange, target }: Props) {
  const [mode, setMode] = useState<SendMode>('link');
  const [phone, setPhone] = useState('');
  const [message, setMessage] = useState('');
  const [includeLinkInCaption, setIncludeLinkInCaption] = useState(true);
  const [templateId, setTemplateId] = useState<string>('');
  const [isGenerating, setIsGenerating] = useState(false);

  const [autoRetry, setAutoRetry] = useState<boolean>(() => {
    try { return localStorage.getItem('wa.autoRetry') !== '0'; } catch { return true; }
  });
  const [maxAttempts, setMaxAttempts] = useState<number>(() => {
    try {
      const v = parseInt(localStorage.getItem('wa.maxAttempts') || '3', 10);
      return Number.isFinite(v) && v >= 1 && v <= 5 ? v : 3;
    } catch { return 3; }
  });

  const [schedule, setSchedule] = useState<ScheduleConfig>(defaultScheduleConfig());
  const { send, sending, attemptInfo } = useWhatsAppSend();
  const createScheduled = useCreateScheduledSend();

  useEffect(() => {
    try { localStorage.setItem('wa.autoRetry', autoRetry ? '1' : '0'); } catch {}
  }, [autoRetry]);
  useEffect(() => {
    try { localStorage.setItem('wa.maxAttempts', String(maxAttempts)); } catch {}
  }, [maxAttempts]);

  const salesTemplates = useMemo(() => {
    if (target?.kind !== 'service_order') return [];
    const name = target.clientName?.split(' ')[0] || 'Cliente';
    const os = target.serviceOrderNumber;
    return [
      {
        id: 'tpl_follow_up',
        name: '📢 Lembrete / Follow-up',
        body: `Olá ${name}, passando para lembrar da proposta ${os} que enviamos. Ficou alguma dúvida ou algo que possamos ajudar?`,
        category: 'sales',
        active: true,
        sort_order: 0,
      },
      {
        id: 'tpl_negotiation',
        name: '💳 Negociação de Pagamento',
        body: `Olá ${name}, sobre o orçamento ${os}, podemos conversar sobre as condições de pagamento se necessário. O que fica melhor para você hoje?`,
        category: 'sales',
        active: true,
        sort_order: 1,
      },
      {
        id: 'tpl_scarcity',
        name: '⏳ Garantia de Vaga (Urgência)',
        body: `Olá ${name}, nossa agenda para os próximos dias está enchendo rapidamente. Gostaria de garantir sua vaga para a execução do serviço ${os}?`,
        category: 'sales',
        active: true,
        sort_order: 2,
      }
    ];
  }, [target]);

  const templateCategory =
    target?.kind === 'service_order'
      ? (target.documentType === 'quote' ? 'quote' : 'service_order')
      : 'billing';

  const { data: dbTemplates } = useWhatsAppTemplates(templateCategory);

  const templates = useMemo(() => {
    const list = [...(dbTemplates || [])];
    if (target?.kind === 'service_order') {
      list.unshift(...salesTemplates);
    }
    return list;
  }, [dbTemplates, salesTemplates, target]);

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

  // Mesma preferência de opções (mostrar termos, preços etc.) configurada em
  // Baixar/Imprimir PDF — sem isso, o envio via WhatsApp sempre usava o padrão de fábrica,
  // ignorando o que foi salvo em Configurações/PDFOptionsDialog para este tipo de documento.
  const { data: appSettings } = useAppSettings();
  const pdfOptions = useMemo(
    () => resolvePdfOptions(appSettings, documentType),
    [appSettings, documentType],
  );

  const publicUrl = useMemo(() => {
    if (!target) return '';
    const token = (target as any).shareToken;
    if (!token) return '';
    return `${window.location.origin}/view/${token}`;
  }, [target]);

  const templateVars = useMemo<Record<string, string | number>>(() => {
    if (!target) return {};
    const base: Record<string, string | number> = {
      cliente: target.clientName || '',
      link: publicUrl || '',
    };
    if (target.kind === 'service_order') {
      base.os = target.serviceOrderNumber;
      base.descricao = target.serviceOrderNumber;
    } else {
      base.descricao = target.description;
      if (target.amount != null) base.valor = Number(target.amount);
      base.vencimento = target.dueDate || '';
    }
    return base;
  }, [target, publicUrl]);

  useEffect(() => {
    if (!open || !target) return;
    setPhone(normalizePhoneE164(target.clientPhone || ''));
    setMode('link');
    setIncludeLinkInCaption(false);
    setTemplateId('');
    setSchedule(defaultScheduleConfig());

    if (clientSetting?.message_body) {
      setMessage(applyTemplateVariables(clientSetting.message_body, templateVars));
      return;
    }
    const name = target.clientName ? ` ${target.clientName}` : '';
    if (target.kind === 'service_order') {
      const label = documentType === 'quote' ? 'Orçamento' : 'Ordem de Serviço';
      setMessage(`Olá${name}, segue o ${label} ${target.serviceOrderNumber}.`);
    } else {
      setMessage(`Olá${name}, segue cobrança referente a: ${target.description}.`);
    }
  }, [open, target, publicUrl, documentType, clientSetting?.id, templateVars]);

  const handleGenerateAI = async () => {
    if (!target || target.kind !== 'service_order') return;
    setIsGenerating(true);
    try {
      const clientName = target.clientName?.split(' ')[0] || 'Cliente';
      const prompt = target.documentType === 'quote'
        ? `Crie uma mensagem curta de WhatsApp muito persuasiva e educada para ${clientName}. Ele tem um orçamento (${target.serviceOrderNumber}) pendente. O objetivo é fechar a venda agora. Ofereça de forma sutil uma facilidade ou prioridade na agenda. Use gatilhos mentais. Não pareça desesperado.`
        : `Crie uma mensagem de follow-up profissional para ${clientName} sobre a OS ${target.serviceOrderNumber}. Seja prestativo e foque na excelência do serviço.`;

      const { data, error } = await supabase.functions.invoke('ai-agent', {
        body: {
          messages: [{ role: 'user', content: prompt }],
          is_sales_copy: true,
          context: { route: '/crm', target: target.serviceOrderNumber }
        }
      });

      if (error) throw error;
      const aiText = data?.message?.content || data?.reply || "";
      if (aiText) setMessage(aiText.replace(/[*#]/g, ''));
      toast.success('Mensagem gerada com IA!');
    } catch (e) {
      console.error(e);
      toast.error('Falha ao gerar mensagem com IA');
    } finally {
      setIsGenerating(false);
    }
  };

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

    if (schedule.enabled) {
      const scheduledIso = new Date(schedule.scheduledAt).toISOString();
      if (new Date(scheduledIso).getTime() <= Date.now()) {
        toast.error('Escolha uma data/hora futura para o agendamento.');
        return;
      }
      try {
        await createScheduled.mutateAsync({
          target_kind: target.kind,
          service_order_id:
            target.kind === 'service_order' ? target.serviceOrderId : target.serviceOrderId || null,
          receivable_id: target.kind === 'receivable' ? target.receivableId : null,
          client_id: target.clientId || null,
          phone,
          message,
          send_mode: mode,
          context: target.kind === 'service_order' ? documentType : 'billing',
          link_title,
          link_description,
          pdf_filename: filename,
          caption,
          include_link_in_caption: includeLinkInCaption,
          scheduled_at: scheduledIso,
          recurrence_type: schedule.recurrenceType,
          recurrence_days_of_week:
            schedule.recurrenceType === 'weekly' ? schedule.daysOfWeek : undefined,
          recurrence_day_of_month:
            schedule.recurrenceType === 'monthly' ? schedule.dayOfMonth : undefined,
          recurrence_end_date: schedule.endDate
            ? new Date(schedule.endDate).toISOString()
            : null,
          auto_retry: autoRetry,
          max_attempts: maxAttempts,
        });
        onOpenChange(false);
      } catch {
        /* erro já exibido pelo hook */
      }
      return;
    }

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
        pdfOptions,
      },
      { autoRetry, maxAttempts },
    );
    if (ok) onOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={(v) => !sending && onOpenChange(v)}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Send className="h-5 w-5" /> Enviar via WhatsApp
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
            <Label htmlFor="phone-whatsapp">Telefone (com DDI)</Label>
            <Input
              id="phone-whatsapp"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="5521999998888"
            />
          </div>

          <div className="space-y-2">
            <div className="flex justify-between items-center">
              <Label>Mensagem</Label>
              {target?.kind === 'service_order' && (
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-7 text-xs gap-1.5 text-primary hover:text-primary hover:bg-primary/10"
                  onClick={handleGenerateAI}
                  disabled={isGenerating || sending}
                >
                  {isGenerating ? (
                    <Loader2 className="h-3 w-3 animate-spin" />
                  ) : (
                    <Sparkles className="h-3 w-3" />
                  )}
                  Gerar com IA
                </Button>
              )}
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

          <RetrySettings
            autoRetry={autoRetry}
            onAutoRetryChange={setAutoRetry}
            maxAttempts={maxAttempts}
            onMaxAttemptsChange={setMaxAttempts}
            attemptInfo={attemptInfo}
            disabled={sending}
          />

          <ScheduleSettings
            value={schedule}
            onChange={setSchedule}
            disabled={sending || createScheduled.isPending}
          />
        </div>

        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={sending || createScheduled.isPending}
          >
            Cancelar
          </Button>
          <Button
            onClick={handleSend}
            disabled={sending || createScheduled.isPending}
            className="gap-2"
          >
            {sending || createScheduled.isPending ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : schedule.enabled ? (
              <CalendarClock className="h-4 w-4" />
            ) : (
              <Send className="h-4 w-4" />
            )}
            {schedule.enabled ? 'Agendar envio' : 'Enviar agora'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
