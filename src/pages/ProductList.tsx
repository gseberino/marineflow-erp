import { useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { products } from '@/data/mock-data';
import { formatCurrency } from '@/lib/constants';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Plus, Search, AlertTriangle } from 'lucide-react';
import { StatusBadge } from '@/components/StatusBadge';

export default function ProductList() {
  const [search, setSearch] = useState('');
  const filtered = products.filter(p =>
    !search || p.product_name.toLowerCase().includes(search.toLowerCase()) || p.sku.toLowerCase().includes(search.toLowerCase()) || p.category.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <div className="space-y-4 animate-fade-in">
      <PageHeader title="Products & Parts" description="Catalog of marine electrical components and parts">
        <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90"><Plus className="h-4 w-4" /> New Product</Button>
      </PageHeader>
      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input placeholder="Search by name, SKU, or category..." value={search} onChange={e => setSearch(e.target.value)} className="pl-9" />
      </div>
      <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
        <table className="w-full text-sm">
          <thead><tr className="border-b bg-muted/50">
            <th className="px-4 py-3 text-left font-medium text-muted-foreground">Product</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">Category</th>
            <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">Brand</th>
            <th className="px-4 py-3 text-center font-medium text-muted-foreground">Stock</th>
            <th className="px-4 py-3 text-right font-medium text-muted-foreground hidden md:table-cell">Cost</th>
            <th className="px-4 py-3 text-right font-medium text-muted-foreground">Sale Price</th>
          </tr></thead>
          <tbody>
            {filtered.map(p => {
              const lowStock = p.stock_quantity <= p.minimum_stock;
              return (
                <tr key={p.id} className="border-b last:border-0 hover:bg-muted/30 transition-colors">
                  <td className="px-4 py-3">
                    <p className="font-medium">{p.product_name}</p>
                    <p className="text-xs text-muted-foreground">{p.sku}</p>
                  </td>
                  <td className="px-4 py-3 hidden md:table-cell"><StatusBadge className="bg-secondary text-secondary-foreground">{p.category}</StatusBadge></td>
                  <td className="px-4 py-3 hidden lg:table-cell text-muted-foreground">{p.brand}</td>
                  <td className="px-4 py-3 text-center">
                    <span className={lowStock ? 'text-destructive font-semibold' : ''}>{p.stock_quantity}</span>
                    {lowStock && <AlertTriangle className="h-3 w-3 text-destructive inline ml-1" />}
                    <span className="text-xs text-muted-foreground block">min: {p.minimum_stock}</span>
                  </td>
                  <td className="px-4 py-3 text-right hidden md:table-cell text-muted-foreground">{formatCurrency(p.cost_price)}</td>
                  <td className="px-4 py-3 text-right font-medium">{formatCurrency(p.sale_price)}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
