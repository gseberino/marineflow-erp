import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { writeAuditLog } from '@/hooks/use-audit-log';

// ── KPIs ──────────────────────────────────────────────────
export function useInventoryOverview() {
  return useQuery({
    queryKey: ['inventory', 'overview'],
    queryFn: async () => {
      const { data: products, error } = await supabase
        .from('products')
        .select('id, stock_quantity, minimum_stock, cost_price, active')
        .eq('active', true);
      if (error) throw error;
      const list = products || [];
      return {
        total_products: list.length,
        low_stock_count: list.filter(p => (p.stock_quantity ?? 0) < (p.minimum_stock ?? 0) && (p.minimum_stock ?? 0) > 0).length,
        out_of_stock_count: list.filter(p => (p.stock_quantity ?? 0) === 0).length,
        total_stock_value: list.reduce((s, p) => s + (p.stock_quantity ?? 0) * (p.cost_price ?? 0), 0),
      };
    },
    staleTime: 60_000,
  });
}

// ── Products list with filters ────────────────────────────
export interface InventoryProductFilters {
  search?: string;
  category?: string;
  stockStatus?: 'all' | 'low' | 'out' | 'ok';
}

export function useInventoryProducts(filters: InventoryProductFilters = {}) {
  return useQuery({
    queryKey: ['inventory', 'products', filters],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('products')
        .select('id, name, sku, category, brand, unit, stock_quantity, minimum_stock, cost_price, sale_price, location_bin, active, product_category_id, product_categories(name)')
        .eq('active', true)
        .order('name', { ascending: true });
      if (error) throw error;
      let list = data || [];

      if (filters.search) {
        const q = filters.search.toLowerCase();
        list = list.filter(p =>
          (p.name || '').toLowerCase().includes(q) ||
          (p.sku || '').toLowerCase().includes(q) ||
          (p.category || '').toLowerCase().includes(q)
        );
      }
      if (filters.category) {
        list = list.filter(p => p.category === filters.category);
      }
      if (filters.stockStatus === 'low') {
        list = list.filter(p => (p.stock_quantity ?? 0) < (p.minimum_stock ?? 0) && (p.minimum_stock ?? 0) > 0);
      } else if (filters.stockStatus === 'out') {
        list = list.filter(p => (p.stock_quantity ?? 0) === 0);
      } else if (filters.stockStatus === 'ok') {
        list = list.filter(p => (p.stock_quantity ?? 0) >= (p.minimum_stock ?? 0) || (p.minimum_stock ?? 0) === 0);
      }

      return list;
    },
    staleTime: 60_000,
  });
}

// ── Movements ─────────────────────────────────────────────
export interface MovementFilters {
  product_id?: string;
  movement_type?: string;
  dateFrom?: string;
  dateTo?: string;
  limit?: number;
}

export function useInventoryMovements(filters: MovementFilters = {}) {
  return useQuery({
    queryKey: ['inventory', 'movements', filters],
    queryFn: async () => {
      let q = supabase
        .from('inventory_movements')
        .select('*, products(name, sku, unit)')
        .order('created_at', { ascending: false })
        .limit(filters.limit || 200);

      if (filters.product_id) q = q.eq('product_id', filters.product_id);
      if (filters.movement_type) q = q.eq('movement_type', filters.movement_type);
      if (filters.dateFrom) q = q.gte('created_at', filters.dateFrom);
      if (filters.dateTo) q = q.lte('created_at', filters.dateTo + 'T23:59:59');

      const { data, error } = await q;
      if (error) throw error;
      return data || [];
    },
    staleTime: 30_000,
  });
}

// ── Adjust stock ──────────────────────────────────────────
export function useAdjustStock() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      product_id: string;
      new_quantity: number;
      reason: string;
      notes?: string;
    }) => {
      // Fase E (30/09/2026): o saldo só muda por movimento. A função do banco lê o saldo atual
      // pela soma dos movimentos, com o produto travado, e grava o ajuste numa transação só.
      const { data, error } = await supabase.rpc('ajustar_estoque' as never, {
        p_produto: input.product_id,
        p_nova_quantidade: input.new_quantity,
        p_motivo: input.reason + (input.notes ? ': ' + input.notes : ''),
      } as never);
      if (error) throw new Error('Erro ao ajustar estoque: ' + error.message);
      const r = data as unknown as { anterior: number; nova: number };

      writeAuditLog({
        table_name: 'products',
        record_id: input.product_id,
        action: 'update',
        previous_value: { stock_quantity: r.anterior },
        new_value: { stock_quantity: r.nova },
        reason: input.reason,
      });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['inventory'] });
      qc.invalidateQueries({ queryKey: ['products'] });
      qc.invalidateQueries({ queryKey: ['dashboard'] });
    },
  });
}

// ── Add stock entry ───────────────────────────────────────
export function useAddStockEntry() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      product_id: string;
      quantity: number;
      unit_cost?: number;
      notes?: string;
    }) => {
      // Fase E: a entrada é um movimento; o saldo sobe pela soma (função do banco, uma transação).
      const { error } = await supabase.rpc('entrada_de_estoque' as never, {
        p_produto: input.product_id,
        p_quantidade: input.quantity,
        p_custo: input.unit_cost ?? null,
        p_notas: input.notes || null,
      } as never);
      if (error) throw new Error('Erro ao registrar entrada: ' + error.message);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['inventory'] });
      qc.invalidateQueries({ queryKey: ['products'] });
      qc.invalidateQueries({ queryKey: ['dashboard'] });
    },
  });
}
