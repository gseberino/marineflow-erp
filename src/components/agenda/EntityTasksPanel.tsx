import { useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Plus, ListChecks } from 'lucide-react';
import { toast } from 'sonner';
import { TaskCard } from '@/components/agenda/TaskCard';
import { AgendaTaskDialog, type ExistingTask } from '@/components/AgendaTaskDialog';
import { useEntityTasks, useCompleteTask, type RelatedEntityType } from '@/hooks/use-agenda';

/**
 * Painel de tarefas vinculadas a uma entidade do ERP (OS, cliente, orçamento, OC).
 * Embutido nas telas de detalhe — cria tarefa já pré-vinculada.
 */
export function EntityTasksPanel({
  entityType, entityId, title = 'Tarefas',
}: {
  entityType: RelatedEntityType;
  entityId: string | undefined;
  title?: string;
}) {
  const { data: tasks = [] } = useEntityTasks(entityType, entityId);
  const complete = useCompleteTask();
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<ExistingTask | null>(null);

  if (!entityId) return null;
  const live = tasks.filter((t: any) => t.status === 'pending' || t.status === 'in_progress');
  const doneRecent = tasks.filter((t: any) => t.status === 'done').slice(0, 5);

  return (
    <Card className="p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2 text-sm font-semibold">
          <ListChecks className="h-4 w-4 text-primary" /> {title}
          {live.length > 0 && (
            <span className="rounded-full bg-primary/10 text-primary px-2 py-0.5 text-[11px] font-medium">
              {live.length}
            </span>
          )}
        </div>
        <Button size="sm" variant="outline" onClick={() => { setEditing(null); setDialogOpen(true); }}>
          <Plus className="h-4 w-4 mr-1" /> Nova tarefa
        </Button>
      </div>

      {live.length === 0 && doneRecent.length === 0 && (
        <p className="text-xs text-muted-foreground">Nenhuma tarefa vinculada.</p>
      )}

      <div className="space-y-1.5">
        {live.map((t: any) => (
          <TaskCard
            key={t.id}
            task={t}
            compact
            onOpen={(task) => { setEditing(task); setDialogOpen(true); }}
            onToggleDone={(id, done) =>
              complete.mutate({ id, done }, { onError: (e: any) => toast.error(e?.message || 'Erro') })}
          />
        ))}
        {doneRecent.map((t: any) => (
          <TaskCard
            key={t.id}
            task={t}
            compact
            onOpen={(task) => { setEditing(task); setDialogOpen(true); }}
            onToggleDone={(id, done) =>
              complete.mutate({ id, done }, { onError: (e: any) => toast.error(e?.message || 'Erro') })}
          />
        ))}
      </div>

      <AgendaTaskDialog
        open={dialogOpen}
        onOpenChange={(v) => { setDialogOpen(v); if (!v) setEditing(null); }}
        existing={editing}
        prefillEntity={{ type: entityType, id: entityId }}
      />
    </Card>
  );
}
