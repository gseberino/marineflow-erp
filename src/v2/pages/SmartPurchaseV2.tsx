import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { CheckCircle2, ChevronRight, Download, History, Truck } from 'lucide-react';
import { useI18n } from '@/i18n';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { NewQuoteRequestDialog } from '@/components/purchasing/NewQuoteRequestDialog';
import type { NewQuoteItem } from '@/hooks/use-quote-requests';
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
  /** Físico − reservado (product_availability). */
  available: number;
};

/** Quanto repor: até o dobro do mínimo, o que dá folga sem encalhar estoque (a mesma conta da v1). */
const suggestedQty = (p: SuggestionRow) => Math.max(1, Number(p.minimum_stock ?? 0) * 2 - p.available);

export default function SmartPurchaseV2() {
  const { formatCurrency } = useI18n();
  const [quoteItems, setQuoteItems] = useState<NewQuoteItem[] | null>(null);

  // Os dois consertos da v1 (SmartPurchasePage), que esta tela tinha perdido:
  // 1. `.filter('stock_quantity','lte','minimum_stock')` compara com o TEXTO 'minimum_stock' (o
  //    PostgREST não compara coluna com coluna) — a consulta falhava e a tela dizia "Estoque
  //    saudável!". A comparação é feita aqui.
  // 2. Vale o DISPONÍVEL (físico − reservado): peça já prometida a uma OS não repõe prateleira.
  //
  // E o de 11/10/2026: a tela lia TODOS os produtos ativos e TODO o product_availability e só
  // então filtrava no navegador. O PostgREST corta em 1000 linhas sem avisar, e o erro do
  // disponível era ignorado — o cálculo caía no físico e esquecia a reserva. Agora o mínimo
  // é filtrado no servidor, o disponível vem só dos produtos que vieram, e erro é erro.
  const { data: suggestions, isLoading, error } = useQuery({
    queryKey: ['purchase-suggestions'],
    queryFn: async (): Promise<SuggestionRow[]> => {
      // Sem mínimo definido não há régua de reposição — pedir seria adivinhação.
      const { data: comMinimo, error: prodErr } = await supabase
        .from('products')
        .select('*, suppliers!products_supplier_id_fkey(name, contact_name, phone)')
        .eq('active', true)
        .gt('minimum_stock', 0);
      if (prodErr) throw prodErr;

      const produtos = (comMinimo ?? []) as unknown as Omit<SuggestionRow, 'available'>[];
      if (produtos.length === 0) return [];

      const availById = new Map<string, number>();
      const ids = produtos.map((p) => p.id);
      // Fatiado porque a lista de ids vai na URL.
      for (let i = 0; i < ids.length; i += 200) {
        const lote = ids.slice(i, i + 200);
        const { data, error: availErr } = await supabase
          .from('product_availability')
          .select('id, stock_quantity, reserved_quantity')
          .in('id', lote);
        if (availErr) throw availErr;
        for (const a of (data ?? []) as Array<{ id: string; stock_quantity: number | null; reserved_quantity: number | null }>) {
          availById.set(a.id, Number(a.stock_quantity ?? 0) - Number(a.reserved_quantity ?? 0));
        }
      }

      return produtos
        .map((p) => ({ ...p, available: availById.get(p.id) ?? Number(p.stock_quantity ?? 0) }))
        // Coluna com coluna fica aqui: o PostgREST não compara as duas.
        .filter((p) => Number(p.minimum_stock ?? 0) > 0 && p.available <= Number(p.minimum_stock))
        .sort((a, b) => a.available - b.available);
    },
  });

  const rows = suggestions ?? [];
  const stats = {
    criticalItems: rows.filter((p) => p.available <= 0).length,
    totalToRestock: rows.length,
    estimatedCost: rows.reduce((s, p) => s + suggestedQty(p) * (Number(p.cost_price) || 0), 0),
  };

  const exportCsv = () => {
    const out = rows.map((s) => ({
      Produto: s.name,
      SKU: s.sku || '',
      Fornecedor: s.suppliers?.name || '',
      'Estoque Atual': s.stock_quantity ?? 0,
      Disponível: s.available,
      Mínimo: s.minimum_stock ?? 0,
      Sugestão: suggestedQty(s),
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
      key: 'stock', header: 'Disponível', minWidth: 116, priority: 1, align: 'right',
      render: (p) => (
        <StatusChip tone={p.available <= 0 ? 'critical' : 'warning'}>
          {p.available} {p.unit || ''}
        </StatusChip>
      ),
    },
    {
      key: 'suggestion', header: 'Sugestão', minWidth: 96, priority: 1, align: 'right',
      render: (p) => <span className="font-bold text-primary tabular-nums">+{suggestedQty(p)}</span>,
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
        description="Reposição pelo estoque disponível e o mínimo de cada produto — selecione itens e abra a cotação."
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
          // Leitura que falhou não é "estoque saudável": diz que falhou.
          emptyMessage={error
            ? `Não deu para ler o estoque: ${(error as Error).message || 'erro desconhecido'}`
            : 'Estoque saudável! Nenhuma reposição necessária no momento.'}
          rowClassName={(p) => (p.available <= 0 ? 'bg-destructive/5' : undefined)}
          bulkBar={(keys, clear) => (
            <>
              <span className="font-semibold">{keys.length} item{keys.length > 1 ? 'ns' : ''} para cotação</span>
              {/* Antes só dava um aviso e dizia "Lista gerada" — nada era criado. Abre a cotação
                  com os itens escolhidos, como a v1. */}
              <Button
                size="sm" variant="secondary" className="gap-1"
                onClick={() => {
                  setQuoteItems(rows.filter((p) => keys.includes(p.id))
                    .map((p) => ({ description: p.name, quantity: suggestedQty(p), product_id: p.id })));
                  clear();
                }}
              >
                Cotar selecionados <ChevronRight className="h-3.5 w-3.5" />
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
      </PageShell>
      <NewQuoteRequestDialog
        open={quoteItems !== null}
        onOpenChange={(aberto) => { if (!aberto) setQuoteItems(null); }}
        prefilledItems={quoteItems ?? undefined}
      />
    </V2Shell>
  );
}
