import { PageHeader } from '@/components/PageHeader';
import { useI18n } from '@/i18n';
import { inventoryMovements, getProduct, getUser } from '@/data/mock-data';
import { StatusBadge } from '@/components/StatusBadge';

const movementTypeClassNames: Record<string, string> = {
  purchase: 'bg-success/15 text-success',
  service_usage: 'bg-warning/15 text-warning',
  manual_adjustment: 'bg-info/15 text-info',
  return: 'bg-primary/10 text-primary',
  transfer: 'bg-muted text-muted-foreground',
};

export default function InventoryPage() {
  const { t, formatCurrency, formatDate } = useI18n();

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title={t.inventory.title} description={t.inventory.description} />

      <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
        <div className="p-5 border-b"><h3 className="text-sm font-semibold">{t.inventory.recentMovements}</h3></div>
        <table className="w-full text-sm">
          <thead><tr className="border-b bg-muted/50">
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.date}</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.serviceOrders.product}</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.type}</th>
            <th className="px-4 py-3 text-center font-medium text-muted-foreground">{t.serviceOrders.qty}</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">{t.common.notes}</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.inventory.by}</th>
          </tr></thead>
          <tbody>
            {inventoryMovements.map(m => {
              const product = getProduct(m.product_id);
              const user = getUser(m.created_by);
              const className = movementTypeClassNames[m.movement_type] || movementTypeClassNames.transfer;
              const label = (t.inventory.movementType as Record<string, string>)[m.movement_type] || m.movement_type;
              return (
                <tr key={m.id} className="border-b last:border-0 hover:bg-muted/30">
                  <td className="px-4 py-3 text-muted-foreground">{formatDate(m.created_at)}</td>
                  <td className="px-4 py-3 font-medium">{product?.product_name}</td>
                  <td className="px-4 py-3"><StatusBadge className={className}>{label}</StatusBadge></td>
                  <td className="px-4 py-3 text-center font-semibold">
                    <span className={m.quantity_delta > 0 ? 'text-success' : 'text-destructive'}>
                      {m.quantity_delta > 0 ? '+' : ''}{m.quantity_delta}
                    </span>
                  </td>
                  <td className="px-4 py-3 hidden md:table-cell text-muted-foreground text-xs">{m.notes}</td>
                  <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{user?.full_name}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
