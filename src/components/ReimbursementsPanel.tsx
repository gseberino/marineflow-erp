// Reembolsos pendentes: o que técnicos pagaram do bolso numa OS e a empresa ainda devolve.
//
// Era uma tabela de 800 px de largura mínima — no celular, rolagem lateral (princípio nº 0 do
// dono: nunca). Virou lista: cada reembolso é um cartão que cabe em qualquer largura.
import { useI18n } from '@/i18n';
import { usePendingReimbursements, useMarkExpenseReimbursed } from '@/hooks/use-service-order-expenses';
import { Button } from '@/components/ui/button';
import { StatusBadge } from '@/components/StatusBadge';
import { Skeleton } from '@/components/ui/skeleton';
import { toast } from 'sonner';
import { Check } from 'lucide-react';

type Reembolso = {
  id: string;
  amount: number | string;
  expense_date: string;
  category?: string | null;
  description?: string | null;
  app_users?: { full_name?: string | null } | null;
  service_orders?: { service_order_number?: string | null } | null;
};

export function ReimbursementsPanel() {
  const { t, formatCurrency, formatDate } = useI18n();
  const { data: pending, isLoading } = usePendingReimbursements();
  const markReimbursed = useMarkExpenseReimbursed();

  const handleMark = async (id: string) => {
    try {
      await markReimbursed.mutateAsync({ expenseId: id });
      toast.success(t.financial.reimbursedSuccess);
    } catch {
      toast.error('Erro ao registrar reembolso');
    }
  };

  if (isLoading) return <Skeleton className="h-32 rounded-xl" />;

  if (!pending || pending.length === 0) {
    return <p className="py-4 text-center text-sm text-muted-foreground">Nenhum reembolso pendente.</p>;
  }

  const lista = pending as unknown as Reembolso[];
  const total = lista.reduce((s, e) => s + Number(e.amount || 0), 0);

  return (
    <div className="space-y-2">
      <p className="text-sm">
        {lista.length} reembolso(s) pendente(s): <b className="tabular-nums">{formatCurrency(total)}</b>
      </p>
      <ul className="divide-y rounded-lg border bg-card">
        {lista.map((exp) => (
          <li key={exp.id} className="flex min-w-0 flex-wrap items-start gap-2 p-3">
            <span className="min-w-0 flex-1">
              <span className="flex min-w-0 items-baseline justify-between gap-2">
                <span className="truncate font-medium">{exp.app_users?.full_name || '—'}</span>
                <span className="shrink-0 font-semibold tabular-nums">{formatCurrency(Number(exp.amount))}</span>
              </span>
              <span className="mt-0.5 flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted-foreground">
                <span>OS {exp.service_orders?.service_order_number || '—'}</span>
                <span>·</span>
                <span>{formatDate(exp.expense_date)}</span>
                {exp.category && <StatusBadge className="bg-secondary text-secondary-foreground">{exp.category}</StatusBadge>}
              </span>
              {exp.description && <span className="mt-0.5 block break-words text-sm">{exp.description}</span>}
            </span>
            <Button size="sm" variant="outline" className="shrink-0" onClick={() => handleMark(exp.id)} disabled={markReimbursed.isPending}>
              <Check className="mr-1 h-3 w-3" /> {t.financial.markReimbursed}
            </Button>
          </li>
        ))}
      </ul>
    </div>
  );
}
