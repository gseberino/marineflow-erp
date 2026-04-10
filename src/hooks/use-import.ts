import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export type ConflictItem = {
  incoming: Record<string, any>;
  existing: any;
  resolution: 'keep' | 'replace' | 'merge';
};

export function useCheckConflicts() {
  return useMutation({
    mutationFn: async ({
      entityType,
      rows,
    }: {
      entityType: string;
      rows: Record<string, any>[];
    }) => {
      const newRows: Record<string, any>[] = [];
      const conflicts: ConflictItem[] = [];

      for (const row of rows) {
        let existing = null;

        if (entityType === 'products') {
          if (row.sku) {
            const { data } = await supabase.from('products')
              .select('*').eq('sku', row.sku).maybeSingle();
            existing = data;
          }
          if (!existing && row.product_name) {
            const { data } = await supabase.from('products')
              .select('*').eq('product_name', row.product_name).maybeSingle();
            existing = data;
          }
        }

        if (entityType === 'services') {
          if (row.service_name) {
            const { data } = await supabase.from('services')
              .select('*').eq('service_name', row.service_name).maybeSingle();
            existing = data;
          }
        }

        if (entityType === 'clients' || entityType === 'mixed') {
          if (row.cnpj_cpf) {
            const { data } = await supabase.from('clients')
              .select('*').eq('cpf_cnpj', row.cnpj_cpf).maybeSingle();
            existing = data;
          }
        }

        if (entityType === 'suppliers' || entityType === 'mixed') {
          if (row.cnpj_cpf && (row._entity_type === 'Fornecedor' || row._entity_type === 'Ambos')) {
            const { data } = await supabase.from('suppliers')
              .select('*').eq('cnpj_cpf', row.cnpj_cpf).maybeSingle();
            if (data) existing = data;
          }
        }

        if (existing) {
          conflicts.push({ incoming: row, existing, resolution: 'keep' });
        } else {
          newRows.push(row);
        }
      }

      return { newRows, conflicts };
    },
  });
}

function chunks<T>(arr: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let i = 0; i < arr.length; i += size) result.push(arr.slice(i, i + size));
  return result;
}

export function useImportRows() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      entityType,
      newRows,
      updates,
    }: {
      entityType: string;
      newRows: Record<string, any>[];
      updates: { id: string; data: Record<string, any> }[];
      sessionId?: string;
    }) => {
      let inserted = 0;
      let updated = 0;

      if (entityType === 'products') {
        for (const chunk of chunks(newRows, 50)) {
          const rows = chunk.map((r: any) => ({
            product_name: r.product_name,
            sku: r.sku || null,
            sale_price: r.sale_price || 0,
            cost_price: r.cost_price || 0,
            stock_quantity: r.stock_quantity || 0,
            minimum_stock: r.minimum_stock || 0,
            unit: r.unit || 'un',
            brand: r.brand || null,
            location_bin: r.location_bin || null,
            notes: r.notes || null,
            active: r.active !== false,
            sale_currency: 'BRL',
            cost_currency: 'BRL',
          }));
          const { data, error } = await supabase.from('products').insert(rows).select('id, stock_quantity');
          if (error) throw error;
          inserted += data?.length || 0;

          for (const p of data || []) {
            if (p.stock_quantity > 0) {
              await supabase.from('inventory_movements').insert({
                product_id: p.id,
                movement_type: 'purchase',
                quantity_delta: p.stock_quantity,
                reference_type: 'import',
              });
            }
          }
        }
        for (const u of updates) {
          await supabase.from('products').update(u.data).eq('id', u.id);
          updated++;
        }
      }

      if (entityType === 'services') {
        for (const chunk of chunks(newRows, 50)) {
          const rows = chunk.map((r: any) => ({
            service_name: r.service_name,
            default_price: r.default_price || 0,
            billing_unit: 'visit',
            currency: 'BRL',
            notes: r.notes || null,
            active: r.active !== false,
          }));
          const { error } = await supabase.from('services').insert(rows);
          if (error) throw error;
          inserted += chunk.length;
        }
        for (const u of updates) {
          await supabase.from('services').update(u.data).eq('id', u.id);
          updated++;
        }
      }

      if (entityType === 'clients') {
        for (const chunk of chunks(newRows, 50)) {
          const rows = chunk.map((r: any) => ({
            full_name_or_company_name: r.full_name_or_company_name,
            type: r._type || 'company',
            cpf_cnpj: r.cnpj_cpf || null,
            email: r.email || null,
            phone: r.phone || r.contact_phone || null,
            address_line_1: r.address_line_1 || null,
            postal_code: r.postal_code || null,
            city: r.city || null,
            state: r.state || null,
            notes: r.notes || null,
            active: r.active !== false,
          }));
          const { error } = await supabase.from('clients').insert(rows);
          if (error) throw error;
          inserted += chunk.length;
        }
      }

      if (entityType === 'suppliers') {
        for (const chunk of chunks(newRows, 50)) {
          const rows = chunk.map((r: any) => ({
            supplier_name: r.full_name_or_company_name || r.supplier_name,
            trade_name: r.trade_name || null,
            cnpj_cpf: r.cnpj_cpf || null,
            contact_email: r.email || null,
            contact_phone: r.phone || r.contact_phone || null,
            address_line_1: r.address_line_1 || null,
            postal_code: r.postal_code || null,
            city: r.city || null,
            state: r.state || null,
            notes: r.notes || null,
            active: r.active !== false,
          }));
          const { error } = await supabase.from('suppliers').insert(rows);
          if (error) throw error;
          inserted += chunk.length;
        }
      }

      if (entityType === 'mixed') {
        const clientRows = newRows.filter(r => r._entity_type === 'Cliente' || r._entity_type === 'Ambos');
        const supplierRows = newRows.filter(r => r._entity_type === 'Fornecedor' || r._entity_type === 'Ambos');

        for (const chunk of chunks(clientRows, 50)) {
          const rows = chunk.map((r: any) => ({
            full_name_or_company_name: r.full_name_or_company_name,
            type: r._type || 'company',
            cpf_cnpj: r.cnpj_cpf || null,
            email: r.email || null,
            phone: r.phone || r.contact_phone || null,
            address_line_1: r.address_line_1 || null,
            postal_code: r.postal_code || null,
            city: r.city || null,
            state: r.state || null,
            notes: r.notes || null,
            active: r.active !== false,
          }));
          await supabase.from('clients').insert(rows);
          inserted += chunk.length;
        }

        for (const chunk of chunks(supplierRows, 50)) {
          const rows = chunk.map((r: any) => ({
            supplier_name: r.full_name_or_company_name,
            trade_name: r.trade_name || null,
            cnpj_cpf: r.cnpj_cpf || null,
            contact_email: r.email || null,
            contact_phone: r.phone || r.contact_phone || null,
            address_line_1: r.address_line_1 || null,
            postal_code: r.postal_code || null,
            city: r.city || null,
            state: r.state || null,
            notes: r.notes || null,
            active: r.active !== false,
          }));
          await supabase.from('suppliers').insert(rows);
          inserted += chunk.length;
        }
      }

      return { inserted, updated };
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['products'] });
      qc.invalidateQueries({ queryKey: ['services'] });
      qc.invalidateQueries({ queryKey: ['clients'] });
      qc.invalidateQueries({ queryKey: ['suppliers'] });
      qc.invalidateQueries({ queryKey: ['inventory'] });
    },
  });
}
