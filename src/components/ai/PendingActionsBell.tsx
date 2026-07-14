import { useState } from 'react';
import { ShieldCheck, Check, X, DollarSign, Trash2, Send, AlertTriangle } from 'lucide-react';
import { toast } from 'sonner';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { ScrollArea } from '@/components/ui/scroll-area';
import { cn } from '@/lib/utils';
import { usePendingActions, type PendingAction } from '@/hooks/use-pending-actions';

function timeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const min = Math.floor(diff / 60000);
  if (min < 1) return 'agora';
  if (min < 60) return `há ${min} min`;
  const hours = Math.floor(min / 60);
  if (hours < 24) return `há ${hours} h`;
  return `há ${Math.floor(hours / 24)} d`;
}

// Ícone/rótulo por tipo de ação, para o card ficar legível (o nome técnico da tool é feio).
function actionMeta(name: string): { Icon: typeof ShieldCheck; label: string } {
  if (name.startsWith('register_payment') || name.startsWith('register_deposit') || name.startsWith('receive_purchase'))
    return { Icon: DollarSign, label: labelFor(name) };
  if (name.startsWith('cancel_') || name.startsWith('reopen_')) return { Icon: Trash2, label: labelFor(name) };
  if (name.startsWith('send_') || name.startsWith('schedule_whatsapp')) return { Icon: Send, label: labelFor(name) };
  return { Icon: AlertTriangle, label: labelFor(name) };
}

function labelFor(name: string): string {
  const map: Record<string, string> = {
    register_payment: 'Registrar pagamento',
    register_deposit_and_convert: 'Registrar sinal e converter em OS',
    receive_purchase_order: 'Receber ordem de compra',
    cancel_service_order: 'Cancelar OS',
    reopen_service_order: 'Reabrir OS',
    send_whatsapp_message: 'Enviar WhatsApp a cliente',
    send_collection_reminder: 'Enviar lembrete de cobrança',
    send_service_order_link: 'Enviar link da OS ao cliente',
    schedule_whatsapp_message: 'Agendar WhatsApp a cliente',
  };
  return map[name] || name.replace(/_/g, ' ');
}

function riskBadge(risk: string) {
  if (risk === 'high' || risk === 'critical')
    return <Badge variant="destructive" className="text-[10px]">Alto risco</Badge>;
  return <Badge className="text-[10px] bg-amber-500/15 text-amber-700 dark:text-amber-400 hover:bg-amber-500/15">Confirmação</Badge>;
}

function PendingRow({ item, acting, onApprove, onReject }: {
  item: PendingAction;
  acting: boolean;
  onApprove: () => void;
  onReject: () => void;
}) {
  const { Icon, label } = actionMeta(item.action_name);
  return (
    <li className="px-3 py-3">
      <div className="flex gap-3">
        <div className="h-8 w-8 shrink-0 rounded-full flex items-center justify-center bg-primary/10 text-primary">
          <Icon className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <p className="text-sm font-medium leading-tight">{item.title || label}</p>
            {riskBadge(item.risk_level)}
          </div>
          {item.summary && (
            <p className="text-xs text-muted-foreground mt-0.5 whitespace-pre-wrap line-clamp-4">{item.summary}</p>
          )}
          <span className="text-[10px] text-muted-foreground">{timeAgo(item.created_at)}</span>
          <div className="flex gap-2 mt-2">
            <Button size="sm" className="h-7 gap-1 text-xs" disabled={acting} onClick={onApprove}>
              <Check className="h-3.5 w-3.5" /> Confirmar
            </Button>
            <Button size="sm" variant="outline" className="h-7 gap-1 text-xs" disabled={acting} onClick={onReject}>
              <X className="h-3.5 w-3.5" /> Rejeitar
            </Button>
          </div>
        </div>
      </div>
    </li>
  );
}

export function PendingActionsBell() {
  const [open, setOpen] = useState(false);
  const { items, count, actingId, approve, reject } = usePendingActions();

  const handle = async (id: string, decision: 'approve' | 'reject') => {
    const res = decision === 'approve' ? await approve(id) : await reject(id);
    if (res.ok) toast.success(decision === 'approve' ? 'Ação confirmada e executada.' : 'Ação rejeitada.');
    else toast.error(res.error || 'Falha ao processar.');
  };

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button
          className="relative rounded-lg p-2 hover:bg-muted transition-colors"
          aria-label="Aprovações pendentes da IA"
          title="Aprovações pendentes da IA"
        >
          <ShieldCheck className="h-5 w-5" />
          {count > 0 && (
            <Badge
              variant="destructive"
              className="absolute -top-0.5 -right-0.5 h-4 min-w-4 px-1 text-[10px] flex items-center justify-center rounded-full"
            >
              {count > 9 ? '9+' : count}
            </Badge>
          )}
        </button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-96 p-0">
        <div className="flex items-center justify-between border-b px-3 py-2">
          <p className="text-sm font-semibold">Aprovações da IA</p>
          {count > 0 && <span className="text-xs text-muted-foreground">{count} pendente{count > 1 ? 's' : ''}</span>}
        </div>
        <ScrollArea className="max-h-[460px]">
          {items.length === 0 ? (
            <div className="py-8 text-center text-sm text-muted-foreground px-4">
              Nenhuma aprovação pendente.<br />
              <span className="text-xs">A IA executa o back-office direto; só ações de dinheiro, cancelamento e mensagem a cliente aparecem aqui.</span>
            </div>
          ) : (
            <ul className={cn('divide-y')}>
              {items.map((item) => (
                <PendingRow
                  key={item.id}
                  item={item}
                  acting={actingId === item.id}
                  onApprove={() => handle(item.id, 'approve')}
                  onReject={() => handle(item.id, 'reject')}
                />
              ))}
            </ul>
          )}
        </ScrollArea>
      </PopoverContent>
    </Popover>
  );
}
