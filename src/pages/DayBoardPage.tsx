import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { AlertTriangle, CheckCircle2, CircleDashed, Loader2, PlayCircle } from 'lucide-react';
import { formatMinutes } from '@/hooks/use-service-steps';

/**
 * Quadro do Dia — a visão de quem coordena.
 *
 * Cartões, não tabela larga: em qualquer largura de tela o conteúdo se reorganiza
 * e a página nunca rola de lado. As colunas são estados do trabalho, e a coluna
 * "travadas" existe para gritar — é o que precisa de decisão humana hoje.
 */

interface BoardStep {
  id: string;
  service_order_id: string;
  status: string;
  standard_minutes: number | null;
  actual_minutes: number | null;
  blocked_reason_code: string | null;
  blocked_note: string | null;
  title: string;
}

interface BoardOrder {
  id: string;
  service_order_number: string;
  status: string;
  scheduled_start_at: string | null;
  clients?: { name: string } | null;
  vessels?: { name: string } | null;
  marinas?: { name: string } | null;
}

/** Chave estável por dia — troca de dia invalida o cache sozinha. */
function todayKey() {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d.toISOString().slice(0, 10);
}

function useDayBoard() {
  return useQuery({
    queryKey: ['day-board', todayKey()],
    refetchInterval: 60_000, // o quadro é para olhar durante o dia
    queryFn: async () => {
      // Toda OS em estado ativo entra, com ou sem agendamento. Na operação real
      // a maioria não tem data marcada (3 de 9 no levantamento de 30/07) —
      // filtrar por data esconderia justamente o trabalho que está solto.
      const { data: orders, error } = await supabase
        .from('service_orders')
        .select('id, service_order_number, status, scheduled_start_at, clients(name), vessels(name), marinas(name)')
        .in('status', ['scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client'])
        .order('scheduled_start_at', { ascending: true, nullsFirst: false })
        .limit(60);
      if (error) throw error;

      const ids = (orders || []).map((o: any) => o.id);
      if (ids.length === 0) return { orders: [] as BoardOrder[], stepsByOrder: {} as Record<string, BoardStep[]> };

      const { data: steps, error: stepErr } = await (supabase as any)
        .from('service_order_steps')
        .select('id, service_order_id, status, standard_minutes, actual_minutes, blocked_reason_code, blocked_note, title')
        .in('service_order_id', ids);
      if (stepErr) throw stepErr;

      const stepsByOrder: Record<string, BoardStep[]> = {};
      for (const s of (steps || []) as BoardStep[]) {
        (stepsByOrder[s.service_order_id] ||= []).push(s);
      }
      return { orders: (orders || []) as unknown as BoardOrder[], stepsByOrder };
    },
  });
}

type Column = 'a_comecar' | 'em_execucao' | 'travadas' | 'concluidas';

function classify(steps: BoardStep[], orderStatus: string): Column {
  if (steps.some((s) => s.status === 'blocked')) return 'travadas';
  if (steps.length > 0 && steps.every((s) => s.status === 'done' || s.status === 'not_applicable')) {
    return 'concluidas';
  }
  if (steps.some((s) => s.status === 'in_progress') || orderStatus === 'in_progress') return 'em_execucao';
  return 'a_comecar';
}

const COLUMNS: Array<{ key: Column; label: string; icon: typeof CircleDashed; tone: string }> = [
  { key: 'a_comecar', label: 'A começar', icon: CircleDashed, tone: 'text-muted-foreground' },
  { key: 'em_execucao', label: 'Em execução', icon: PlayCircle, tone: 'text-blue-600 dark:text-blue-400' },
  { key: 'travadas', label: 'Travadas', icon: AlertTriangle, tone: 'text-red-600 dark:text-red-400' },
  { key: 'concluidas', label: 'Concluídas', icon: CheckCircle2, tone: 'text-emerald-600 dark:text-emerald-400' },
];

function OrderCard({ order, steps }: { order: BoardOrder; steps: BoardStep[] }) {
  const done = steps.filter((s) => s.status === 'done' || s.status === 'not_applicable').length;
  const standard = steps.reduce((sum, s) => sum + (s.standard_minutes || 0), 0);
  const actual = steps.reduce((sum, s) => sum + (s.actual_minutes || 0), 0);
  const pct = standard > 0 ? Math.min(150, Math.round((actual / standard) * 100)) : 0;
  const over = standard > 0 && actual > standard;
  const blocked = steps.find((s) => s.status === 'blocked');

  return (
    <Link
      to={`/service-orders/${order.id}`}
      className="block rounded-md border bg-card p-2.5 hover:border-primary/50 transition-colors"
    >
      <div className="flex items-start justify-between gap-2">
        <span className="text-xs font-semibold">{order.service_order_number}</span>
        {steps.length > 0 && (
          <span className="text-[10px] text-muted-foreground tabular-nums shrink-0">
            {done}/{steps.length}
          </span>
        )}
      </div>
      <p className="mt-0.5 text-xs text-muted-foreground truncate">{order.clients?.name || 'Sem cliente'}</p>
      {order.vessels?.name && (
        <p className="text-[11px] text-muted-foreground truncate">{order.vessels.name}</p>
      )}

      {standard > 0 && (
        <div className="mt-1.5 space-y-1">
          <div className="h-1 w-full rounded-full bg-muted overflow-hidden">
            <div
              className={`h-full rounded-full ${over ? 'bg-amber-500' : 'bg-primary'}`}
              style={{ width: `${Math.max(2, pct)}%` }}
            />
          </div>
          <p className="text-[10px] text-muted-foreground tabular-nums">
            {formatMinutes(actual)} de {formatMinutes(standard)}
          </p>
        </div>
      )}

      {blocked && (
        <p className="mt-1.5 text-[11px] text-red-600 dark:text-red-400 line-clamp-2">
          travado: {blocked.blocked_note || blocked.title}
        </p>
      )}

      {steps.length === 0 && (
        <Badge variant="outline" className="mt-1.5 text-[10px]">sem roteiro</Badge>
      )}
    </Link>
  );
}

export default function DayBoardPage() {
  const { data, isLoading, error } = useDayBoard();

  const buckets = useMemo(() => {
    const empty: Record<Column, Array<{ order: BoardOrder; steps: BoardStep[] }>> = {
      a_comecar: [], em_execucao: [], travadas: [], concluidas: [],
    };
    if (!data) return empty;
    for (const order of data.orders) {
      const steps = data.stepsByOrder[order.id] || [];
      empty[classify(steps, order.status)].push({ order, steps });
    }
    return empty;
  }, [data]);

  const emExecucao = buckets.em_execucao.length;

  return (
    <div className="p-4 lg:p-6 space-y-4">
      <div>
        <h1 className="text-lg font-semibold">Quadro do dia</h1>
        <p className="text-sm text-muted-foreground">
          O que está em campo agora. Atualiza sozinho a cada minuto.
        </p>
      </div>

      {isLoading && (
        <p className="flex items-center gap-2 text-sm text-muted-foreground">
          <Loader2 className="h-4 w-4 animate-spin" /> Carregando o dia…
        </p>
      )}

      {error && (
        <Card className="p-4 text-sm text-destructive">
          Não deu para carregar o quadro. Recarregue a página.
        </Card>
      )}

      {/* Limite de trabalho simultâneo: o número em si não bloqueia nada, mas
          torna visível a hora em que a operação começou a se espalhar demais. */}
      {emExecucao > 3 && (
        <Card className="flex items-start gap-2 border-amber-500/50 bg-amber-50 dark:bg-amber-950/30 p-3 text-sm">
          <AlertTriangle className="h-4 w-4 mt-0.5 text-amber-600 shrink-0" />
          <span>
            <strong>{emExecucao} OS em execução ao mesmo tempo.</strong>{' '}
            Trabalho espalhado costuma terminar mais tarde do que trabalho em fila.
          </span>
        </Card>
      )}

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {COLUMNS.map((col) => {
          const items = buckets[col.key];
          const Icon = col.icon;
          return (
            <section key={col.key} className="min-w-0 space-y-2">
              <header className="flex items-center gap-1.5 text-sm font-medium">
                <Icon className={`h-4 w-4 ${col.tone}`} />
                {col.label}
                <span className="text-xs text-muted-foreground tabular-nums">{items.length}</span>
              </header>
              <div className="space-y-2">
                {items.map(({ order, steps }) => (
                  <OrderCard key={order.id} order={order} steps={steps} />
                ))}
                {items.length === 0 && !isLoading && (
                  <p className="rounded-md border border-dashed px-2.5 py-3 text-xs text-muted-foreground">
                    nada aqui
                  </p>
                )}
              </div>
            </section>
          );
        })}
      </div>
    </div>
  );
}
