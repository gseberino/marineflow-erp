import { useI18n } from '@/i18n';
import { usePendingReimbursements, useMarkExpenseReimbursed } from '@/hooks/use-service-order-expenses';
import { Button } from '@/components/ui/button';
import { StatusBadge } from '@/components/StatusBadge';
import { Skeleton } from '@/components/ui/skeleton';
import { toast } from 'sonner';
import { Check } from 'lucide-react';

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
    return <p className="text-sm text-muted-foreground py-4 text-center">{t.common.noResults}</p>;
  }

  return (
    <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
      <table className="w-full text-sm min-w-[800px]">
        <thead>
          <tr className="border-b bg-muted/50">
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.serviceOrders.technicians}</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">OS</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.date}</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.products.category}</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.description}</th>
            <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.amount}</th>
            <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.actions}</th>
          </tr>
        </thead>
        <tbody>
          {pending.map((exp: any) => (
            <tr key={exp.id} className="border-b last:border-0 hover:bg-muted/30">
              <td className="px-4 py-3 font-medium">{exp.app_users?.full_name || '—'}</td>
              <td className="px-4 py-3 text-muted-foreground">{exp.service_orders?.service_order_number || '—'}</td>
              <td className="px-4 py-3 text-muted-foreground">{formatDate(exp.expense_date)}</td>
              <td className="px-4 py-3"><StatusBadge className="bg-secondary text-secondary-foreground">{exp.category}</StatusBadge></td>
              <td className="px-4 py-3">{exp.description}</td>
              <td className="px-4 py-3 text-right font-semibold">{formatCurrency(Number(exp.amount))}</td>
              <td className="px-4 py-3 text-right">
                <Button size="sm" variant="outline" onClick={() => handleMark(exp.id)}
                  disabled={markReimbursed.isPending}>
                  <Check className="h-3 w-3 mr-1" /> {t.financial.markReimbursed}
                </Button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
