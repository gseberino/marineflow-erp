import { useState } from 'react';
import { ChevronDown, Loader2, XCircle, RotateCcw, Undo2 } from 'lucide-react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { useToast } from '@/hooks/use-toast';
import { useUpdateServiceOrderStatus, useCancelServiceOrder, useReopenServiceOrder, STATUS_TRANSITIONS, STATUS_BACKWARD_TRANSITIONS } from '@/hooks/use-service-orders';
import { statusConfig } from '@/lib/constants';
import { useI18n } from '@/i18n';
import { cn } from '@/lib/utils';
import { supabase } from '@/integrations/supabase/client';
import { CompletionSendDialog } from '@/components/CompletionSendDialog';
import { FaturarOsDialog } from '@/components/fiscal/FaturarOsDialog';
import { useOptionalAuth } from '@/hooks/use-auth';
import type { ServiceOrderStatus } from '@/types/domain';

interface Props {
  orderId: string;
  currentStatus: ServiceOrderStatus;
}

export function StatusQuickChange({ orderId, currentStatus }: Props) {
  const { t } = useI18n();
  const { toast } = useToast();
  const updateStatus = useUpdateServiceOrderStatus();
  const cancelOrder = useCancelServiceOrder();
  const reopenOrder = useReopenServiceOrder();

  const user = useOptionalAuth()?.user ?? null;
  const [cancelOpen, setCancelOpen] = useState(false);
  const [reopenOpen, setReopenOpen] = useState(false);
  const [reason, setReason] = useState('');
  const [completionSend, setCompletionSend] = useState<{
    open: boolean; osNumber: string; balance: number; dueDate: string | null; clientName: string | null; clientPhone: string | null;
  }>({ open: false, osNumber: '', balance: 0, dueDate: null, clientName: null, clientPhone: null });
  // Assistente "Faturar OS" (NFS-e + NF-e). Abre ao concluir, ANTES do aviso de WhatsApp —
  // primeiro o documento fiscal, depois a cobrança. Só para admin: a página fiscal e a
  // emissão são admin-only, oferecer a outro papel seria porta para um 401.
  const [faturar, setFaturar] = useState<{ open: boolean; osNumber: string | null }>({ open: false, osNumber: null });
  // O prompt de WhatsApp fica ARMADO aqui enquanto o assistente está aberto.
  const [completionPendente, setCompletionPendente] = useState<typeof completionSend | null>(null);
  // [NOVO-nfse-03] Navegação pedida pelo assistente, adiada até o aviso de saldo fechar.
  const [navegarDepois, setNavegarDepois] = useState<(() => void) | null>(null);

  const cfg = statusConfig[currentStatus];
  const validTransitions = STATUS_TRANSITIONS[currentStatus] ?? [];
  const backwardTransitions = STATUS_BACKWARD_TRANSITIONS[currentStatus] ?? [];
  const isTerminal = currentStatus === 'invoiced' || currentStatus === 'cancelled';
  const isBusy = updateStatus.isPending || cancelOrder.isPending || reopenOrder.isPending;

  const handleReopen = async () => {
    if (!reason.trim()) return;
    try {
      await reopenOrder.mutateAsync({ id: orderId, reason: reason.trim() });
      toast({ title: 'OS reaberta com sucesso' });
      setReopenOpen(false);
      setReason('');
    } catch (err: any) {
      toast({ title: 'Erro ao reabrir OS', description: err.message, variant: 'destructive' });
    }
  };

  // Terminal states — show badge + reopen option
  if (validTransitions.length === 0) {
    return (
      <>
        <div className="flex items-center gap-1.5">
          <span className={cn('inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium', cfg?.className)}>
            {(t.status as Record<string, string>)[currentStatus]}
          </span>
          {isTerminal && (
            <button
              type="button"
              onClick={() => { setReason(''); setReopenOpen(true); }}
              className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
              title="Reabrir OS"
            >
              <RotateCcw className="h-3 w-3" />
              <span className="hidden sm:inline">Reabrir</span>
            </button>
          )}
        </div>

        <Dialog open={reopenOpen} onOpenChange={v => { setReopenOpen(v); if (!v) setReason(''); }}>
          <DialogContent className="max-w-sm">
            <DialogHeader>
              <DialogTitle>Reabrir OS</DialogTitle>
            </DialogHeader>
            <p className="text-sm text-muted-foreground">
              Informe o motivo da reabertura. A OS voltará ao status anterior e o recebível será recriado se necessário.
            </p>
            <Textarea
              placeholder="Motivo da reabertura..."
              value={reason}
              onChange={e => setReason(e.target.value)}
              rows={3}
              className="resize-none"
            />
            <DialogFooter>
              <Button variant="outline" onClick={() => setReopenOpen(false)}>Cancelar</Button>
              <Button
                disabled={!reason.trim() || reopenOrder.isPending}
                onClick={handleReopen}
              >
                {reopenOrder.isPending && <Loader2 className="h-4 w-4 animate-spin mr-2" />}
                Confirmar reabertura
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </>
    );
  }

  const handleTransition = async (target: ServiceOrderStatus) => {
    try {
      await updateStatus.mutateAsync({ id: orderId, status: target });
      toast({ title: `Status atualizado para "${(t.status as Record<string, string>)[target]}"` });

      // Conclusão pela lista → mesmo prompt opt-in de "avisar o cliente + saldo" do formulário.
      if (target === 'completed') {
        const [{ data: so }, { data: recRows }] = await Promise.all([
          supabase.from('service_orders')
            .select('service_order_number, clients(name, whatsapp, phone)')
            .eq('id', orderId).maybeSingle(),
          supabase.from('receivables')
            .select('balance_amount, due_date, is_deposit, status')
            .eq('service_order_id', orderId).neq('status', 'cancelled'),
        ]);
        const pend = (recRows || []).filter((r: any) => !r.is_deposit && r.status !== 'paid');
        const outstanding = pend.reduce((s: number, r: any) => s + Number(r.balance_amount || 0), 0);
        const osNumber = (so as any)?.service_order_number || '';
        let promptSaldo: typeof completionSend | null = null;
        if (outstanding > 0.009) {
          const dueRow = pend.slice().sort((a: any, b: any) => String(a.due_date).localeCompare(String(b.due_date)))[0];
          const cli = (so as any)?.clients;
          promptSaldo = {
            open: true,
            osNumber,
            balance: Math.round(outstanding * 100) / 100,
            dueDate: dueRow?.due_date ?? null,
            clientName: cli?.name ?? null,
            clientPhone: cli?.whatsapp || cli?.phone || null,
          };
        }
        if (user?.role === 'admin') {
          // Fiscal primeiro; o aviso de saldo (se houver) fica armado para depois.
          setCompletionPendente(promptSaldo);
          setFaturar({ open: true, osNumber });
        } else if (promptSaldo) {
          setCompletionSend(promptSaldo);
        }
      }
    } catch (err: any) {
      toast({ title: 'Erro ao atualizar status', description: err.message, variant: 'destructive' });
    }
  };

  const handleCancel = async () => {
    if (!reason.trim()) return;
    try {
      await cancelOrder.mutateAsync({ id: orderId, reason: reason.trim() });
      toast({ title: 'OS cancelada com sucesso' });
      setCancelOpen(false);
      setReason('');
    } catch (err: any) {
      toast({ title: 'Erro ao cancelar', description: err.message, variant: 'destructive' });
    }
  };

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            disabled={isBusy}
            className={cn(
              'inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium transition-opacity',
              cfg?.className,
              isBusy ? 'opacity-50 cursor-wait' : 'cursor-pointer hover:opacity-80',
            )}
          >
            {isBusy
              ? <Loader2 className="h-3 w-3 animate-spin" />
              : <>{(t.status as Record<string, string>)[currentStatus]}<ChevronDown className="h-3 w-3 opacity-60" /></>
            }
          </button>
        </DropdownMenuTrigger>

        <DropdownMenuContent align="start" className="w-56">
          <DropdownMenuLabel className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wide">
            Mover para
          </DropdownMenuLabel>
          <DropdownMenuSeparator />
          {validTransitions.map(target => {
            const targetCfg = statusConfig[target as ServiceOrderStatus];
            const isCancelTarget = target === 'cancelled';
            return (
              <DropdownMenuItem
                key={target}
                onClick={() => {
                  if (isCancelTarget) {
                    setCancelOpen(true);
                  } else {
                    handleTransition(target as ServiceOrderStatus);
                  }
                }}
                className={cn(
                  'gap-2 cursor-pointer',
                  isCancelTarget && 'text-destructive focus:text-destructive focus:bg-destructive/10',
                )}
              >
                {isCancelTarget && <XCircle className="h-3.5 w-3.5 shrink-0" />}
                <span className={cn(
                  'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium',
                  targetCfg?.className,
                )}>
                  {(t.status as Record<string, string>)[target]}
                </span>
              </DropdownMenuItem>
            );
          })}

          {/* Backward corrections — visually separated */}
          {backwardTransitions.length > 0 && (
            <>
              <DropdownMenuSeparator />
              <DropdownMenuLabel className="text-[10px] font-semibold text-amber-600 uppercase tracking-wide flex items-center gap-1">
                <Undo2 className="h-3 w-3" /> Corrigir para
              </DropdownMenuLabel>
              {backwardTransitions.map(target => {
                const targetCfg = statusConfig[target as ServiceOrderStatus];
                return (
                  <DropdownMenuItem
                    key={target}
                    onClick={() => handleTransition(target as ServiceOrderStatus)}
                    className="gap-2 cursor-pointer text-amber-700 focus:text-amber-800 focus:bg-amber-50"
                  >
                    <Undo2 className="h-3 w-3 shrink-0 opacity-60" />
                    <span className={cn(
                      'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium',
                      targetCfg?.className,
                    )}>
                      {(t.status as Record<string, string>)[target]}
                    </span>
                  </DropdownMenuItem>
                );
              })}
            </>
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      {/* Cancel dialog */}
      <Dialog open={cancelOpen} onOpenChange={v => { setCancelOpen(v); if (!v) setReason(''); }}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Cancelar OS</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            Informe o motivo do cancelamento. Peças serão estornadas ao estoque e recebíveis vinculados serão cancelados.
          </p>
          <Textarea
            placeholder="Motivo do cancelamento..."
            value={reason}
            onChange={e => setReason(e.target.value)}
            rows={3}
            className="resize-none"
          />
          <DialogFooter>
            <Button variant="outline" onClick={() => setCancelOpen(false)}>Voltar</Button>
            <Button
              variant="destructive"
              disabled={!reason.trim() || cancelOrder.isPending}
              onClick={handleCancel}
            >
              {cancelOrder.isPending && <Loader2 className="h-4 w-4 animate-spin mr-2" />}
              Confirmar cancelamento
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Faturar OS (NFS-e + NF-e) — ao concluir pela lista, admin. Ao fechar, dispara o
          prompt de saldo que ficou armado. */}
      <FaturarOsDialog
        open={faturar.open}
        onOpenChange={(v) => {
          setFaturar(prev => ({ ...prev, open: v }));
          if (!v && completionPendente) {
            setCompletionSend(completionPendente);
            setCompletionPendente(null);
          }
        }}
        serviceOrderId={orderId}
        orderNumber={faturar.osNumber}
        onAntesDeNavegar={(continuar) => {
          setFaturar(prev => ({ ...prev, open: false }));
          if (completionPendente) {
            setCompletionSend(completionPendente);
            setCompletionPendente(null);
            setNavegarDepois(() => continuar);
          } else {
            continuar();
          }
        }}
      />

      {/* Prompt opt-in de conclusão (avisar cliente + saldo) — ao concluir pela lista */}
      <CompletionSendDialog
        open={completionSend.open}
        onOpenChange={v => {
          setCompletionSend(prev => ({ ...prev, open: v }));
          if (!v && navegarDepois) { const ir = navegarDepois; setNavegarDepois(null); ir(); }
        }}
        serviceOrderId={orderId}
        osNumber={completionSend.osNumber}
        clientName={completionSend.clientName}
        clientPhone={completionSend.clientPhone}
        balance={completionSend.balance}
        dueDate={completionSend.dueDate}
      />
    </>
  );
}
