import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Badge } from '@/components/ui/badge';
import { ScrollArea } from '@/components/ui/scroll-area';
import { useWhatsAppSendHistory } from '@/hooks/use-whatsapp-send-log';
import { useI18n } from '@/i18n';
import { CheckCircle2, XCircle, Loader2 } from 'lucide-react';

interface Props {
  serviceOrderId: string | null;
  serviceOrderNumber?: string;
  open: boolean;
  onOpenChange: (v: boolean) => void;
}

export function WhatsAppSendHistoryDialog({ serviceOrderId, serviceOrderNumber, open, onOpenChange }: Props) {
  const { formatDateTime } = useI18n() as any;
  const { data: entries, isLoading } = useWhatsAppSendHistory(open ? serviceOrderId : null);

  const fmt = (d: string) =>
    typeof formatDateTime === 'function'
      ? formatDateTime(d)
      : new Date(d).toLocaleString('pt-BR');

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Histórico de envios Z-API</DialogTitle>
          <DialogDescription>
            {serviceOrderNumber ? `OS ${serviceOrderNumber}` : 'Tentativas de envio via WhatsApp'}
          </DialogDescription>
        </DialogHeader>

        {isLoading ? (
          <div className="flex items-center justify-center py-8 text-muted-foreground">
            <Loader2 className="h-5 w-5 animate-spin mr-2" /> Carregando…
          </div>
        ) : !entries || entries.length === 0 ? (
          <div className="py-8 text-center text-muted-foreground text-sm">
            Nenhum envio via Z-API registrado para esta OS.
          </div>
        ) : (
          <ScrollArea className="max-h-[60vh] pr-2">
            <ul className="space-y-3">
              {entries.map((e) => {
                const nv: any = e.new_value || {};
                const phone = nv?.phone;
                const httpStatus = nv?.http_status;
                const zapiErr = nv?.zapi_response?.error;
                return (
                  <li key={e.id} className="rounded-lg border bg-card p-3 text-sm space-y-2">
                    <div className="flex items-center justify-between gap-2">
                      <div className="flex items-center gap-2">
                        {e.success ? (
                          <Badge className="gap-1 bg-success/15 text-success hover:bg-success/20 border-success/30">
                            <CheckCircle2 className="h-3 w-3" /> Enviado
                          </Badge>
                        ) : (
                          <Badge variant="destructive" className="gap-1">
                            <XCircle className="h-3 w-3" /> Falhou
                          </Badge>
                        )}
                        <span className="text-muted-foreground text-xs">
                          {fmt(e.changed_at)}
                        </span>
                      </div>
                      <span className="text-xs text-muted-foreground">{e.changed_by}</span>
                    </div>
                    <div className="grid grid-cols-2 gap-2 text-xs">
                      <div><span className="text-muted-foreground">Telefone:</span> {phone || '—'}</div>
                      <div><span className="text-muted-foreground">HTTP:</span> {httpStatus ?? '—'}</div>
                    </div>
                    {nv?.message_preview && (
                      <div className="text-xs">
                        <span className="text-muted-foreground">Mensagem:</span>{' '}
                        <span className="italic">"{nv.message_preview}"</span>
                      </div>
                    )}
                    {!e.success && (
                      <div className="text-xs text-destructive">
                        <span className="font-medium">Motivo:</span> {zapiErr || e.reason || `HTTP ${httpStatus}`}
                      </div>
                    )}
                  </li>
                );
              })}
            </ul>
          </ScrollArea>
        )}
      </DialogContent>
    </Dialog>
  );
}
