import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Check, SkipForward, Timer, X } from 'lucide-react';
import { toast } from 'sonner';
import { TaskCard } from '@/components/agenda/TaskCard';
import { useCompleteTask, useSnoozeTask } from '@/hooks/use-agenda';

/**
 * Modo foco (padrão HubSpot task queues): uma tarefa por vez, na ordem
 * atrasadas → hoje → sem data, prioridade dentro de cada grupo.
 */
export function FocusMode({
  open, onOpenChange, tasks,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  tasks: any[];
}) {
  const [idx, setIdx] = useState(0);
  const [doneCount, setDoneCount] = useState(0);
  const complete = useCompleteTask();
  const snooze = useSnoozeTask();

  const current = tasks[idx];
  const remaining = tasks.length - idx;

  const advance = () => {
    if (idx + 1 >= tasks.length) {
      toast.success(`Fila concluída! ${doneCount + 1 <= tasks.length ? `${doneCount} tarefa(s) resolvida(s).` : ''}`);
      onOpenChange(false);
      setIdx(0);
      setDoneCount(0);
    } else {
      setIdx(idx + 1);
    }
  };

  const handleDone = () => {
    if (!current) return;
    complete.mutate({ id: current.id, done: true }, {
      onSuccess: () => { setDoneCount((n) => n + 1); advance(); },
      onError: (e: any) => toast.error(e?.message || 'Erro ao concluir'),
    });
  };

  const handleSnooze = () => {
    if (!current) return;
    snooze.mutate({ id: current.id, until: new Date(Date.now() + 3600000).toISOString() }, {
      onSuccess: advance,
      onError: (e: any) => toast.error(e?.message || 'Erro ao adiar'),
    });
  };

  return (
    <Dialog open={open} onOpenChange={(v) => { onOpenChange(v); if (!v) { setIdx(0); setDoneCount(0); } }}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center justify-between">
            <span>Modo foco</span>
            <span className="text-sm font-normal text-muted-foreground">
              {remaining} restante{remaining !== 1 ? 's' : ''} · {doneCount} feita{doneCount !== 1 ? 's' : ''}
            </span>
          </DialogTitle>
        </DialogHeader>

        {current ? (
          <div className="space-y-4">
            <TaskCard task={current} />
            <div className="grid grid-cols-3 gap-2">
              <Button onClick={handleDone} disabled={complete.isPending}>
                <Check className="h-4 w-4 mr-1" /> Concluir
              </Button>
              <Button variant="outline" onClick={handleSnooze} disabled={snooze.isPending}>
                <Timer className="h-4 w-4 mr-1" /> Adiar 1h
              </Button>
              <Button variant="ghost" onClick={advance}>
                <SkipForward className="h-4 w-4 mr-1" /> Pular
              </Button>
            </div>
          </div>
        ) : (
          <div className="py-8 text-center text-sm text-muted-foreground">
            <X className="h-6 w-6 mx-auto mb-2" /> Nada na fila.
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
