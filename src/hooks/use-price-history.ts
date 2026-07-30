import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

/**
 * Histórico do que já foi PAGO por um produto, por fornecedor.
 *
 * A fonte é a nota de entrada (`fiscal_note_items` + `fiscal_notes`), não a ordem de
 * compra: OC é o que foi pedido, a nota é o que foi cobrado — e é o segundo número que
 * serve de régua na hora de julgar uma cotação.
 *
 * Para que serve na tela: quando o fornecedor manda R$ 200 e a última compra do mesmo
 * item saiu por R$ 120, isso precisa estar visível ANTES de escolher. É o que os
 * sistemas de field service chamam de "price tracking over time" e o que evita aceitar
 * um reajuste de 60% sem perceber.
 */

export interface PriceHistoryEntry {
  productId: string;
  supplierId: string | null;
  supplierName: string | null;
  unitPrice: number;
  quantity: number;
  purchasedAt: string;
  noteNumber: string | null;
}

export interface ProductPriceStats {
  lastPrice: number;
  lastSupplierName: string | null;
  lastPurchasedAt: string;
  minPrice: number;
  maxPrice: number;
  entryCount: number;
}

/** Estatística por produto, para consulta O(1) na renderização das linhas. */
export type PriceHistoryMap = Record<string, ProductPriceStats>;

export function usePriceHistory(productIds: (string | null)[]) {
  const ids = [...new Set(productIds.filter((id): id is string => !!id))].sort();
  return useQuery({
    queryKey: ['price-history', ids],
    queryFn: async (): Promise<PriceHistoryMap> => {
      if (!ids.length) return {};
      const { data, error } = await supabase
        .from('fiscal_note_items')
        .select(`
          product_id, unit_price, quantity, created_at,
          fiscal_notes!inner(nfe_number, issue_date, created_at, suppliers(name))
        `)
        .in('product_id', ids)
        .order('created_at', { ascending: false })
        .limit(200);
      if (error) throw error;

      const byProduct = new Map<string, PriceHistoryEntry[]>();
      for (const row of (data ?? []) as any[]) {
        const price = Number(row.unit_price);
        // Item sem preço não é histórico — é linha incompleta da importação.
        if (!Number.isFinite(price) || price <= 0) continue;
        const list = byProduct.get(row.product_id) ?? [];
        list.push({
          productId: row.product_id,
          supplierId: null,
          supplierName: row.fiscal_notes?.suppliers?.name ?? null,
          unitPrice: price,
          quantity: Number(row.quantity) || 0,
          // issue_date é a data do fato (emissão); created_at é quando foi importado.
          purchasedAt: row.fiscal_notes?.issue_date ?? row.fiscal_notes?.created_at ?? row.created_at,
          noteNumber: row.fiscal_notes?.nfe_number ?? null,
        });
        byProduct.set(row.product_id, list);
      }

      const out: PriceHistoryMap = {};
      for (const [productId, entries] of byProduct) {
        const sorted = [...entries].sort((a, b) => b.purchasedAt.localeCompare(a.purchasedAt));
        const prices = sorted.map(e => e.unitPrice);
        out[productId] = {
          lastPrice: sorted[0].unitPrice,
          lastSupplierName: sorted[0].supplierName,
          lastPurchasedAt: sorted[0].purchasedAt,
          minPrice: Math.min(...prices),
          maxPrice: Math.max(...prices),
          entryCount: sorted.length,
        };
      }
      return out;
    },
    enabled: ids.length > 0,
    staleTime: 5 * 60 * 1000,
  });
}

/**
 * Variação da oferta contra o último preço pago.
 * Devolve null quando não há histórico — melhor não dizer nada do que inventar régua.
 */
export function priceDelta(offerPrice: number, stats: ProductPriceStats | undefined) {
  if (!stats || stats.lastPrice <= 0) return null;
  const diff = (offerPrice - stats.lastPrice) / stats.lastPrice;
  return {
    ratio: diff,
    pct: Math.round(diff * 100),
    cheaper: diff < -0.005,
    pricier: diff > 0.005,
  };
}
