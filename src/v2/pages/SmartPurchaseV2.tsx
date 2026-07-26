import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { CheckCircle2, ChevronRight, Download, History, Truck } from 'lucide-react';
import { toast } from 'sonner';
import { useI18n } from '@/i18n';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { PageShell } from '@/v2/components/PageShell';
import { KPIStat } from '@/v2/components/KPIStat';
import { StatusChip } from '@/v2/components/StatusChip';
import { DataTable, type DataColumn } from '@/v2/components/DataTable';
import { V2Shell } from '@/v2/components/V2Shell';
import '@/v2/tokens.css';

/* Onda B · Assistente de Compras v2 — paridade com SmartPurchasePage v1
   (sugestões por estoque mínimo, seleção, CSV); seleção nativa da DataTable
   com bulk bar no lugar do painel lateral fixo. */

type SuggestionRow = {
  id: string;
  name: string;
  sku?: string | null;
  unit?: string | null;
  stock_quantity?: number | null;
  minimum_stock?: number | null;
  cost_price?: number | null;
  suppliers?: { name?: string } | null;
};

export default function SmartPurchaseV2() {
  const { formatCurrency } = useI18n();
  const [generated, setGenerated] = useState(false);

  const { data: suggestions, isLoading } = useQuery({
    queryKey: ['purchase-suggestions'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('products')
        .select('*, suppliers!products_supplier_id_fkey(name, contact_name, phone)')
        .filter('stock_quantity', 'lte', 'minimum_stock')
        .order('stock_quantity', { ascending: true });
      if (error) throw error;
      return data as unknown as SuggestionRow[];
    },
  });

  const rows = suggestions ?? [];
  const stats = {
    criticalItems: rows.filter((p) => (p.stock_quantity || 0) === 0).length,
    totalToRestock: rows.length,
    estimatedCost: rows.reduce((s, p) => s + ((p.minimum_stock || 1) - (p.stock_quantity || 0)) * (p.cost_price || 0), 0),
  };

  const exportCsv = () => {
    const out = rows.map((s) => ({
      Produto: s.name,
      SKU: s.sku || '',
      Fornecedor: s.suppliers?.name || '',
      'Estoque Atual': s.stock_quantity ?? 0,
      Mínimo: s.minimum_stock ?? 0,
      Sugestão: Math.max(0, (s.minimum_stock ?? 0) * 2 - (s.stock_quantity ?? 0)),
    }));
    if (!out.length) return;
    const csv = [Object.keys(out[0]).join(','), ...out.map((r) => Object.values(r).map((v) => `"${String(v ?? '').replace(/"/g, '""')}"`).join(','))].join('\n');
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' }));
    a.download = 'sugestoes_compra.csv';
    a.click();
  };

  const columns: DataColumn<SuggestionRow>[] = [
    {
      key: 'name', header: 'Produto / SKU', minWidth: 230, priority: 0,
      render: (p) => (
        <span className="block leading-tight">
          <span className="block truncate font-semibold">{p.name}</span>
          <span className="block truncate text-xs text-muted-foreground">SKU: {p.sku || '—'}</span>
        </span>
      ),
    },
    {
      key: 'stock', header: 'Estoque atual', minWidth: 116, priority: 1, align: 'right',
      render: (p) => (
        <StatusChip tone={(p.stock_quantity || 0) === 0 ? 'critical' : 'warning'}>
          {p.stock_quantity || 0} {p.unit || ''}
        </StatusChip>
      ),
    },
    {
      key: 'suggestion', header: 'Sugestão', minWidth: 96, priority: 1, align: 'right',
      render: (p) => <span className="font-bold text-primary tabular-nums">+{(p.minimum_stock || 0) - (p.stock_quantity || 0) + 1}</span>,
    },
    {
      key: 'supplier', header: 'Fornecedor preferencial', minWidth: 180, priority: 2, detailLabel: 'Fornecedor',
      render: (p) => (
        <span className="flex items-center gap-1.5 truncate text-muted-foreground">
          <Truck className="h-3.5 w-3.5 shrink-0" /> {p.suppliers?.name || 'Não vinculado'}
        </span>
      ),
    },
    {
      key: 'min', header: 'Mínimo', minWidth: 80, priority: 3, align: 'right', detailLabel: 'Mínimo',
      render: (p) => <span className="text-muted-foreground tabular-nums">{p.minimum_stock || 0}</span>,
    },
  ];

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Estoque & Compras' }, { label: 'Assistente de Compras' }]}
        title="Assistente de Compras"
        count={stats.totalToRestock}
        description="Reposição baseada em demanda real e estoque mínimo — selecione itens e gere a lista de compra."
        actions={
          <Button variant="outline" size="sm" className="gap-1.5" onClick={exportCsv}>
            <Download className="h-4 w-4" /> Exportar CSV
          </Button>
        }
      >
        <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
          <KPIStat label="Itens críticos (zerados)" value={String(stats.criticalItems)} tone={stats.criticalItems > 0 ? 'critical' : 'success'} />
          <KPIStat label="Sugestões de reposição" value={String(stats.totalToRestock)} />
          <KPIStat label="Estimativa de investimento" value={formatCurrency(stats.estimatedCost)} />
        </div>

        <DataTable<SuggestionRow>
          rows={rows}
          rowKey={(p) => p.id}
          columns={columns}
          selectable
          isLoading={isLoading}
          emptyMessage="Estoque saudável! Nenhuma reposição necessária no momento."
          rowClassName={(p) => ((p.stock_quantity || 0) === 0 ? 'bg-destructive/5' : undefined)}
          bulkBar={(keys, clear) => (
            <>
              <span className="font-semibold">{keys.length} item{keys.length > 1 ? 'ns' : ''} para cotação</span>
              <Button
                size="sm" variant="secondary" className="gap-1"
                onClick={() => { toast.success(`${keys.length} itens prontos para cotação!`); setGenerated(true); clear(); }}
              >
                Gerar lista de compra <ChevronRight className="h-3.5 w-3.5" />
              </Button>
              <button type="button" className="ml-auto text-xs underline-offset-2 hover:underline" onClick={clear}>Cancelar</button>
            </>
          )}
        />

        <div className="grid grid-cols-1 gap-3 rounded-lg border bg-card p-4 text-xs text-muted-foreground sm:grid-cols-2">
          <span className="flex items-start gap-2">
            <CheckCircle2 className="h-4 w-4 shrink-0 text-success" />
            Priorize itens vinculados a fornecedores para agilizar a cotação.
          </span>
          <span className="flex items-start gap-2">
            <History className="h-4 w-4 shrink-0 text-info" />
            O sistema usa o último custo do XML como referência de preço.
          </span>
        </div>
        {generated && (
          <p className="text-xs text-muted-foreground">
            Lista gerada — acompanhe em <span className="font-semibold text-foreground">Ordens de Compra</span>.
          </p>
        )}
      </PageShell>
    </V2Shell>
  );
}
