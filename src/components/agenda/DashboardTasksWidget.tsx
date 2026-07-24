import { useNavigate } from 'react-router-dom';
import { ListChecks, AlertTriangle } from 'lucide-react';
import { useLiveTasks } from '@/hooks/use-agenda';

/** Faixa "Tarefas" do Dashboard: atrasadas / hoje / total vivo, com link para a Agenda. */
export function DashboardTasksWidget() {
  const navigate = useNavigate();
  const { data: tasks = [] } = useLiveTasks();

  const now = new Date();
  const startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const endToday = new Date(startToday.getTime() + 86400000);

  const overdue = tasks.filter((t: any) => {
    const anchor = t.due_at || t.scheduled_start_at;
    return anchor && new Date(anchor) < startToday;
  }).length;
  const today = tasks.filter((t: any) => {
    const anchor = t.due_at || t.scheduled_start_at;
    return anchor && new Date(anchor) >= startToday && new Date(anchor) < endToday;
  }).length;

  if (tasks.length === 0) return null;

  return (
    <button
      onClick={() => navigate('/agenda')}
      className="w-full rounded-xl border bg-card p-4 shadow-sm text-left hover:shadow-md transition-all"
    >
      <div className="flex flex-wrap items-center gap-x-5 gap-y-2">
        <span className="inline-flex items-center gap-2 text-sm font-semibold">
          <ListChecks className="h-4 w-4 text-primary" /> Tarefas
        </span>
        {overdue > 0 && (
          <span className="inline-flex items-center gap-1.5 text-sm font-medium text-destructive">
            <AlertTriangle className="h-4 w-4" /> {overdue} atrasada{overdue > 1 ? 's' : ''}
          </span>
        )}
        <span className="text-sm text-muted-foreground">{today} para hoje</span>
        <span className="text-sm text-muted-foreground">{tasks.length} em aberto</span>
        <span className="ml-auto text-xs text-primary">Abrir agenda →</span>
      </div>
    </button>
  );
}
