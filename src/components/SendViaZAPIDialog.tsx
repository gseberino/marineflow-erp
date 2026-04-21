import { useEffect, useMemo, useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Input } from '@/components/ui/input';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Checkbox } from '@/components/ui/checkbox';
import { Loader2, LinkIcon, FileText, Send } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { normalizePhoneE164 } from '@/lib/masks';
import { generatePDFBlob, DEFAULT_PDF_OPTIONS, type PDFDocumentType } from '@/lib/pdf-generator';
import { usePDFData } from '@/hooks/use-pdf';
import { useQueryClient } from '@tanstack/react-query';
import { useWhatsAppTemplates, applyTemplateVariables } from '@/hooks/use-whatsapp-templates';
import { useI18n } from '@/i18n';

export type SendViaZAPITarget =
  | {
      kind: 'service_order';
      serviceOrderId: string;
      serviceOrderNumber: string;
      shareToken?: string | null;
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
      clientName?: string | null;
      clientPhone?: string | null;
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
  const queryClient = useQueryClient();
  const { formatCurrency } = useI18n();

  const templateCategory =
    target?.kind === 'service_order'
      ? (target.documentType === 'quote' ? 'quote' : 'service_order')
      : 'billing';
  const { data: templates } = useWhatsAppTemplates(templateCategory);

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

  // Defaults ao abrir
  useEffect(() => {
    if (!open || !target) return;
    setPhone(normalizePhoneE164(target.clientPhone || ''));
    setMode('link');
    setIncludeLinkInCaption(true);
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
  }, [open, target, publicUrl, documentType]);

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

  async function handleSend() {
    if (!phone || phone.replace(/\D/g, '').length < 10) {
      toast.error('Telefone inválido. Inclua DDI+DDD.');
      return;
    }
    setSending(true);
    const tId = toast.loading(
      mode === 'document' ? 'Gerando PDF e enviando…' : 'Enviando mensagem…',
    );
    try {
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

      if (mode === 'link') {
        if (!publicUrl) throw new Error('Esta OS não possui link público.');
        invokeBody.kind = 'link';
        invokeBody.link_url = publicUrl;
        invokeBody.link_title = titleLabel;
        invokeBody.link_description =
          target.kind === 'service_order'
            ? 'Toque para visualizar o documento completo.'
            : 'Toque para visualizar a cobrança.';
      } else {
        if (!pdfData) throw new Error('Dados do documento ainda carregando — tente novamente em instantes.');
        const blob = await generatePDFBlob(
          { ...pdfData, documentType } as any,
          DEFAULT_PDF_OPTIONS,
        );
        const filename =
          target.kind === 'service_order'
            ? `${documentType === 'quote' ? 'Orcamento' : 'OS'}-${target.serviceOrderNumber}.pdf`
            : `Cobranca-${target.receivableId.slice(0, 8)}.pdf`;
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

      toast.success('Enviado com sucesso!', { id: tId });
      queryClient.invalidateQueries({ queryKey: ['whatsapp-send-status'] });
      queryClient.invalidateQueries({ queryKey: ['whatsapp-send-history'] });
      onOpenChange(false);
    } catch (err: any) {
      console.error('SendViaZAPI error', err);
      toast.error(`Falha: ${err?.message || 'erro desconhecido'}`, { id: tId });
    } finally {
      setSending(false);
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

          <div className="space-y-2">
            <Label htmlFor="msg-zapi">
              {mode === 'document' ? 'Legenda do PDF' : 'Mensagem'}
            </Label>
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
