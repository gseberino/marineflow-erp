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
import { NewQuoteRequestDialog } from '@/components/purchasing/NewQuoteRequestDialog';
import type { NewQuoteItem } from '@/hooks/use-quote-requests';

export default function SmartPurchasePage() {
  const { t, formatCurrency } = useI18n();
  const [selectedItems, setSelectedItems] = useState<string[]>([]);
  const [quoteOpen, setQuoteOpen] = useState(false);
  const [quoteItems, setQuoteItems] = useState<NewQuoteItem[]>([]);

  // Produtos que precisam de reposição.
  //
  // Duas correções em relação à versão anterior desta tela:
  //
  // 1. O filtro era `.filter('stock_quantity','lte','minimum_stock')`. O PostgREST
  //    trata 'minimum_stock' como VALOR literal, não como coluna — não existe
  //    comparação coluna-a-coluna nessa sintaxe. Agora a comparação é feita aqui.
  // 2. Comparava o estoque FÍSICO com o mínimo. Com o modelo de reserva v2 ligado,
  //    o que importa é o DISPONÍVEL (físico − reservado): peça já prometida a uma OS
  //    não está disponível para repor prateleira.
  const { data: suggestions, isLoading } = useQuery({
    queryKey: ['purchase-suggestions'],
    queryFn: async () => {
      const [prodRes, availRes] = await Promise.all([
        supabase
          .from('products')
          .select('*, suppliers!products_supplier_id_fkey(name, contact_name, phone)')
          .eq('active', true),
        supabase.from('product_availability').select('id, stock_quantity, reserved_quantity'),
      ]);
      if (prodRes.error) throw prodRes.error;

      const availById = new Map<string, number>();
      for (const a of (availRes.data ?? []) as any[]) {
        availById.set(a.id, Number(a.stock_quantity ?? 0) - Number(a.reserved_quantity ?? 0));
      }

      return ((prodRes.data ?? []) as any[])
        .map(p => ({ ...p, available: availById.get(p.id) ?? Number(p.stock_quantity ?? 0) }))
        // Sem mínimo definido não há régua de reposição — pedir seria adivinhação.
        .filter(p => Number(p.minimum_stock ?? 0) > 0 && p.available <= Number(p.minimum_stock))
        .sort((a, b) => a.available - b.available);
    },
  });

  const handleToggleSelect = (id: string) => {
    setSelectedItems(prev => 
      prev.includes(id) ? prev.filter(i => i !== id) : [...prev, id]
    );
  };

  /** Quanto repor: repõe até o dobro do mínimo, o que dá folga sem encalhar estoque. */
  const suggestedQty = (p: any) =>
    Math.max(1, Number(p.minimum_stock ?? 0) * 2 - Number(p.available ?? 0));

  // Antes este botão só emitia um aviso ("itens prontos para cotação!") e limpava a
  // seleção — nada era criado. Agora abre a cotação com os itens escolhidos, que é o
  // que o texto sempre prometeu.
  const handleGenerateOrders = () => {
    if (selectedItems.length === 0) {
      toast.error('Selecione ao menos um item para cotar.');
      return;
    }
    const chosen = (suggestions ?? []).filter((p: any) => selectedItems.includes(p.id));
    setQuoteItems(chosen.map((p: any) => ({
      description: p.name,
      quantity: suggestedQty(p),
      product_id: p.id,
    })));
    setQuoteOpen(true);
  };

  const stats = {
    criticalItems: suggestions?.filter((p: any) => (p.available ?? 0) <= 0).length || 0,
    totalToRestock: suggestions?.length || 0,
    estimatedCost: suggestions?.reduce(
      (s: number, p: any) => s + suggestedQty(p) * (Number(p.cost_price) || 0), 0,
    ) || 0,
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
                    <TableHead className="text-right">Disponível</TableHead>
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
                          <Badge
                            variant="outline"
                            className={(p as any).available <= 0
                              ? 'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300'
                              : 'bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300'}
                          >
                            {(p as any).available ?? 0} {p.unit}
                          </Badge>
                          {Number(p.reserved_quantity) > 0 && (
                            <div className="text-[10px] text-muted-foreground">
                              {p.stock_quantity} físico − {p.reserved_quantity} reservado
                            </div>
                          )}
                        </TableCell>
                        <TableCell className="text-right text-muted-foreground text-xs">{p.minimum_stock || 0}</TableCell>
                        <TableCell className="text-right font-bold text-primary">
                          +{suggestedQty(p)}
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
                Cotar selecionados <ChevronRight className="h-4 w-4 ml-1" />
              </Button>
              
              <div className="space-y-3 pt-4 border-t">
                <div className="flex items-start gap-2 text-xs text-muted-foreground">
                  <CheckCircle2 className="h-4 w-4 text-emerald-500 shrink-0" />
                  <span>A conta usa o <strong>disponível</strong> (físico menos reservado): peça já prometida a uma OS não conta como estoque.</span>
                </div>
                <div className="flex items-start gap-2 text-xs text-muted-foreground">
                  <History className="h-4 w-4 text-blue-500 shrink-0" />
                  <span>A estimativa usa o último custo conhecido; a cotação dá o preço real.</span>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>

      <NewQuoteRequestDialog
        open={quoteOpen}
        onOpenChange={v => {
          setQuoteOpen(v);
          if (!v) setSelectedItems([]);
        }}
        prefilledItems={quoteItems}
      />
    </div>
  );
}
