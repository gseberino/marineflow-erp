import { PageHeader } from '@/components/PageHeader';
import { inventoryMovements, getProduct, getUser } from '@/data/mock-data';
import { formatCurrency, formatDate } from '@/lib/constants';
import { StatusBadge } from '@/components/StatusBadge';

const movementTypeConfig: Record<string, { label: string; className: string }> = {
  purchase: { label: 'Purchase', className: 'bg-success/15 text-success' },
  service_usage: { label: 'Service Usage', className: 'bg-warning/15 text-warning' },
  manual_adjustment: { label: 'Adjustment', className: 'bg-info/15 text-info' },
  return: { label: 'Return', className: 'bg-primary/10 text-primary' },
  transfer: { label: 'Transfer', className: 'bg-muted text-muted-foreground' },
};

export default function InventoryPage() {
  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title="Inventory" description="Stock movements and inventory control" />

      <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
        <div className="p-5 border-b"><h3 className="text-sm font-semibold">Recent Stock Movements</h3></div>
        <table className="w-full text-sm">
          <thead><tr className="border-b bg-muted/50">
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">Date</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">Product</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">Type</th>
            <th className="px-4 py-3 text-center font-medium text-muted-foreground">Qty</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">Notes</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">By</th>
          </tr></thead>
          <tbody>
            {inventoryMovements.map(m => {
              const product = getProduct(m.product_id);
              const user = getUser(m.created_by);
              const config = movementTypeConfig[m.movement_type] || movementTypeConfig.transfer;
              return (
                <tr key={m.id} className="border-b last:border-0 hover:bg-muted/30">
                  <td className="px-4 py-3 text-muted-foreground">{formatDate(m.created_at)}</td>
                  <td className="px-4 py-3 font-medium">{product?.product_name}</td>
                  <td className="px-4 py-3"><StatusBadge className={config.className}>{config.label}</StatusBadge></td>
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
