import { useState } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { KPICard } from '@/components/KPICard';
import { useI18n } from '@/i18n';
import { 
  ShoppingCart,
  Package,
  AlertTriangle,
  TrendingUp,
  ArrowRight,
  Truck,
  History,
  CheckCircle2,
  ChevronRight,
  Download
} from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { toast } from 'sonner';

export default function SmartPurchasePage() {
  const { t, formatCurrency } = useI18n();
  const [selectedItems, setSelectedItems] = useState<string[]>([]);

  // 1. Buscar produtos com estoque baixo ou sugestão de compra
  const { data: suggestions, isLoading } = useQuery({
    queryKey: ['purchase-suggestions'],
    queryFn: async () => {
      // Busca produtos onde estoque <= estoque mínimo
      const { data, error } = await supabase
        .from('products')
        .select(`
          *,
          suppliers!products_supplier_id_fkey(name, contact_name, phone)
        `)
        .filter('stock_quantity', 'lte', 'minimum_stock')
        .order('stock_quantity', { ascending: true });
      
      if (error) throw error;
      return data;
    }
  });

  const handleToggleSelect = (id: string) => {
    setSelectedItems(prev => 
      prev.includes(id) ? prev.filter(i => i !== id) : [...prev, id]
    );
  };

  const handleGenerateOrders = () => {
    if (selectedItems.length === 0) {
      toast.error('Selecione ao menos um item para gerar a lista de compra.');
      return;
    }
    // Simulação de geração de pedido
    toast.success(`${selectedItems.length} itens prontos para cotação!`);
    setSelectedItems([]);
  };

  const stats = {
    criticalItems: suggestions?.filter(p => (p.stock_quantity || 0) === 0).length || 0,
    totalToRestock: suggestions?.length || 0,
    estimatedCost: suggestions?.reduce((s, p) => s + ((p.minimum_stock || 1) - (p.stock_quantity || 0)) * (p.cost_price || 0), 0) || 0
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader 
        title="Assistente de Compras Inteligente" 
        description="Reposição automática baseada em demanda real e estoque mínimo. Economize tempo e evite falta de peças."
      />

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <KPICard title="Itens Críticos (Zerados)" value={String(stats.criticalItems)} icon={AlertTriangle} className="border-destructive/30 bg-destructive/5" />
        <KPICard title="Sugestões de Reposição" value={String(stats.totalToRestock)} icon={Package} />
        <KPICard title="Estimativa de Investimento" value={formatCurrency(stats.estimatedCost)} icon={TrendingUp} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-6">
        <div className="lg:col-span-3 space-y-4">
          <Card>
            <CardHeader className="flex flex-row items-start justify-between space-y-0">
              <div>
                <CardTitle>Sugestões de Reposição</CardTitle>
                <CardDescription>Produtos abaixo do nível de segurança em estoque.</CardDescription>
              </div>
              <Button variant="outline" size="sm" className="gap-1 shrink-0" onClick={() => {
                const rows = (suggestions || []).map((s: any) => ({
                  'Produto': s.name,
                  'SKU': s.sku || '',
                  'Fornecedor': s.suppliers?.name || '',
                  'Estoque Atual': s.stock_quantity ?? 0,
                  'Mínimo': s.minimum_stock ?? 0,
                  'Sugestão': Math.max(0, (s.minimum_stock ?? 0) * 2 - (s.stock_quantity ?? 0)),
                }));
                if (!rows.length) return;
                const csv = [Object.keys(rows[0]).join(','), ...rows.map(r => Object.values(r).map(v => `"${String(v ?? '').replace(/"/g, '""')}"`).join(','))].join('\n');
                const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' })); a.download = 'sugestoes_compra.csv'; a.click();
              }}>
                <Download className="h-3.5 w-3.5" /> Exportar
              </Button>
            </CardHeader>
            <CardContent>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className="w-[50px]"></TableHead>
                    <TableHead>Produto / SKU</TableHead>
                    <TableHead>Fornecedor Preferencial</TableHead>
                    <TableHead className="text-right">Estoque Atual</TableHead>
                    <TableHead className="text-right">Mínimo</TableHead>
                    <TableHead className="text-right">Sugestão</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {isLoading ? (
                    <TableRow><TableCell colSpan={6} className="text-center py-8">Analisando estoque...</TableCell></TableRow>
                  ) : suggestions?.length === 0 ? (
                    <TableRow><TableCell colSpan={6} className="text-center py-8 text-muted-foreground">Estoque está saudável! Nenhuma reposição necessária no momento.</TableCell></TableRow>
                  ) : (
                    suggestions?.map((p) => (
                      <TableRow key={p.id} className={selectedItems.includes(p.id) ? 'bg-accent/30' : ''}>
                        <TableCell>
                          <input 
                            type="checkbox" 
                            className="rounded border-gray-300 text-primary focus:ring-primary h-4 w-4"
                            checked={selectedItems.includes(p.id)}
                            onChange={() => handleToggleSelect(p.id)}
                          />
                        </TableCell>
                        <TableCell>
                          <div className="font-medium">{p.name}</div>
                          <div className="text-[10px] text-muted-foreground">SKU: {p.sku || '—'}</div>
                        </TableCell>
                        <TableCell>
                          <div className="flex items-center gap-1.5">
                            <Truck className="h-3 w-3 text-muted-foreground" />
                            <span className="text-sm">{(p as any).suppliers?.name || 'Não vinculado'}</span>
                          </div>
                        </TableCell>
                        <TableCell className="text-right">
                          <Badge variant="outline" className={p.stock_quantity === 0 ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-700'}>
                            {p.stock_quantity || 0} {p.unit}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-right text-muted-foreground text-xs">{p.minimum_stock || 0}</TableCell>
                        <TableCell className="text-right font-bold text-primary">
                          +{(p.minimum_stock || 0) - (p.stock_quantity || 0) + 1}
                        </TableCell>
                      </TableRow>
                    ))
                  )}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        </div>

        <div className="lg:col-span-1 space-y-4">
          <Card className="bg-primary/5 border-primary/20 sticky top-4">
            <CardHeader>
              <CardTitle className="text-sm">Ações Rápidas</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="p-3 bg-card border rounded-lg">
                <div className="text-xs text-muted-foreground mb-1">Itens Selecionados</div>
                <div className="text-2xl font-bold">{selectedItems.length}</div>
              </div>
              
              <Button className="w-full bg-primary hover:bg-primary/90" onClick={handleGenerateOrders} disabled={selectedItems.length === 0}>
                Gerar Lista de Compra <ChevronRight className="h-4 w-4 ml-1" />
              </Button>
              
              <div className="space-y-3 pt-4 border-t">
                <div className="flex items-start gap-2 text-xs text-muted-foreground">
                  <CheckCircle2 className="h-4 w-4 text-emerald-500 shrink-0" />
                  <span>Sugerimos priorizar itens vinculados a fornecedores para agilizar a cotação.</span>
                </div>
                <div className="flex items-start gap-2 text-xs text-muted-foreground">
                  <History className="h-4 w-4 text-blue-500 shrink-0" />
                  <span>O sistema usará o último custo do XML como referência de preço.</span>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
