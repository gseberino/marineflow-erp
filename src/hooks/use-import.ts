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

      async function batchIn<T>(
        table: string,
        column: string,
        values: string[],
        selectCols: string = '*'
      ): Promise<T[]> {
        if (values.length === 0) return [];
        const size = 100;
        const results: T[] = [];
        for (let i = 0; i < values.length; i += size) {
          const chunk = values.slice(i, i + size);
          const { data, error } = await (supabase
            .from(table as any)
            .select(selectCols) as any)
            .in(column, chunk);
          if (error) throw error;
          results.push(...((data as T[]) || []));
        }
        return results;
      }

      if (entityType === 'products') {
        const skus = rows.map(r => r.sku).filter(Boolean) as string[];
        const names = rows.map(r => r.name).filter(Boolean) as string[];
        const [bySku, byName] = await Promise.all([
          batchIn<any>('products', 'sku', skus, 'id,sku,name:product_name'),
          batchIn<any>('products', 'product_name', names, 'id,sku,name:product_name'),
        ]);
        const skuMap = new Map(bySku.map(p => [p.sku, p]));
        const nameMap = new Map(byName.map(p => [p.name, p]));
        for (const row of rows) {
          const existing = (row.sku && skuMap.get(row.sku))
            || (row.name && nameMap.get(row.name))
            || null;
          if (existing) {
            conflicts.push({ incoming: row, existing, resolution: 'keep' });
          } else {
            newRows.push(row);
          }
        }
      } else if (entityType === 'services') {
        const names = rows.map(r => r.name).filter(Boolean) as string[];
        const existing = await batchIn<any>('services', 'service_name', names, 'id,name:service_name');
        const nameMap = new Map(existing.map(s => [s.name, s]));
        for (const row of rows) {
          const found = row.name ? nameMap.get(row.name) : null;
          if (found) {
            conflicts.push({ incoming: row, existing: found, resolution: 'keep' });
          } else {
            newRows.push(row);
          }
        }
      } else if (entityType === 'clients') {
        const cnpjs = rows.map(r => r.cnpj_cpf).filter(Boolean) as string[];
        const existing = await batchIn<any>('clients', 'cpf_cnpj', cnpjs, 'id,cpf_cnpj');
        const cnpjMap = new Map(existing.map(c => [c.cpf_cnpj, c]));
        for (const row of rows) {
          const found = row.cnpj_cpf ? cnpjMap.get(row.cnpj_cpf) : null;
          if (found) {
            conflicts.push({ incoming: row, existing: found, resolution: 'keep' });
          } else {
            newRows.push(row);
          }
        }
      } else if (entityType === 'suppliers') {
        const cnpjs = rows.map(r => r.cnpj_cpf).filter(Boolean) as string[];
        const existing = await batchIn<any>('suppliers', 'cnpj_cpf', cnpjs, 'id,cnpj_cpf');
        const cnpjMap = new Map(existing.map(s => [s.cnpj_cpf, s]));
        for (const row of rows) {
          const found = row.cnpj_cpf ? cnpjMap.get(row.cnpj_cpf) : null;
          if (found) {
            conflicts.push({ incoming: row, existing: found, resolution: 'keep' });
          } else {
            newRows.push(row);
          }
        }
      } else if (entityType === 'mixed') {
        const clientRows = rows.filter(r =>
          r._entity_type === 'Cliente' || r._entity_type === 'Ambos');
        const supplierRows = rows.filter(r =>
          r._entity_type === 'Fornecedor' || r._entity_type === 'Ambos');
        const clientCnpjs = clientRows.map(r => r.cnpj_cpf).filter(Boolean) as string[];
        const supplierCnpjs = supplierRows.map(r => r.cnpj_cpf).filter(Boolean) as string[];
        const [existingClients, existingSuppliers] = await Promise.all([
          batchIn<any>('clients', 'cpf_cnpj', clientCnpjs, 'id,cpf_cnpj'),
          batchIn<any>('suppliers', 'cnpj_cpf', supplierCnpjs, 'id,cnpj_cpf'),
        ]);
        const clientMap = new Map(existingClients.map(c => [c.cpf_cnpj, c]));
        const supplierMap = new Map(existingSuppliers.map(s => [s.cnpj_cpf, s]));
        for (const row of rows) {
          const isClient = row._entity_type === 'Cliente' || row._entity_type === 'Ambos';
          const isSupplier = row._entity_type === 'Fornecedor' || row._entity_type === 'Ambos';
          const existingClient = isClient && row.cnpj_cpf ? clientMap.get(row.cnpj_cpf) : null;
          const existingSupplier = isSupplier && row.cnpj_cpf ? supplierMap.get(row.cnpj_cpf) : null;
          if (existingClient || existingSupplier) {
            conflicts.push({
              incoming: row,
              existing: existingClient || existingSupplier,
              resolution: 'keep',
            });
          } else {
            newRows.push(row);
          }
        }
      } else {
        newRows.push(...rows);
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
        const validProductRows = newRows.filter(r => r.name);
        for (const chunk of chunks(validProductRows, 50)) {
          const rows = chunk.map((r: any) => ({
            product_name: r.name as string,
            sku: (r.sku || null) as string | null,
            sale_price: (r.sale_price || 0) as number,
            cost_price: (r.cost_price || 0) as number,
            stock_quantity: (r.stock_quantity || 0) as number,
            minimum_stock: (r.minimum_stock || 0) as number,
            unit: (r.unit || 'un') as string,
            brand: (r.brand || null) as string | null,
            location_bin: (r.location_bin || null) as string | null,
            notes: (r.notes || null) as string | null,
            active: r.active !== false,
            sale_currency: 'BRL' as string,
            cost_currency: 'BRL' as string,
            ncm: (r.ncm || null) as string | null,
            barcode: (r.barcode || null) as string | null,
            fiscal_origin: r.fiscal_origin != null ? parseInt(r.fiscal_origin) : 0,
            use_global_fiscal: true,
          }));
          const { data, error } = await supabase.from('products').insert(rows).select('id, stock_quantity');
          if (error) throw error;
          inserted += data?.length || 0;

          const movementInserts = [];
          for (const p of data || []) {
            if ((p.stock_quantity ?? 0) > 0) {
              movementInserts.push({
                product_id: p.id,
                movement_type: 'purchase',
                quantity_delta: p.stock_quantity ?? 0,
                reference_type: 'import',
              });
            }
          }
          
          if (movementInserts.length > 0) {
            try {
              await supabase.from('inventory_movements').insert(movementInserts);
            } catch {
              // Non-critical: inventory movement logging failed
            }
          }
        }
        for (const u of updates) {
          const typedData = u.data as Record<string, string | number | boolean | null>;
          await supabase.from('products').update(typedData as any).eq('id', u.id);
          updated++;
        }
      }

      if (entityType === 'services') {
        const validServiceRows = newRows.filter(r => r.name);
        for (const chunk of chunks(validServiceRows, 50)) {
          const rows = chunk.map((r: any) => ({
            service_name: r.name as string,
            default_price: (r.default_price || 0) as number,
            billing_unit: 'visit' as string,
            currency: 'BRL' as string,
            description: (r.notes || null) as string | null,
            active: r.active !== false,
          }));
          const { error } = await supabase.from('services').insert(rows);
          if (error) throw error;
          inserted += chunk.length;
        }
        for (const u of updates) {
          await supabase.from('services').update(u.data as any).eq('id', u.id);
          updated++;
        }
      }

      if (entityType === 'clients') {
        const validClientRows = newRows.filter(r => r.name);
        for (const chunk of chunks(validClientRows, 50)) {
          const rows = chunk.map((r: any) => ({
            full_name_or_company_name: r.name,
            type: r._type || 'company',
            cpf_cnpj: r.cnpj_cpf || null,
            email: r.email || null,
            phone: r.phone || null,
            address_line_1: r.address_line_1 || null,
            address_line_2: [r.address_number, r.neighborhood, r.address_complement].filter(Boolean).join(', ') || null,
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
        const validSupplierRows = newRows.filter(r => r.name);
        for (const chunk of chunks(validSupplierRows, 50)) {
          const rows = chunk.map((r: any) => ({
            supplier_name: r.name,
            trade_name: r.trade_name || null,
            cnpj_cpf: r.cnpj_cpf || null,
            contact_email: r.email || null,
            contact_phone: r.phone || null,
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
        const clientRows = newRows.filter(r =>
          (r._entity_type === 'Cliente' || r._entity_type === 'Ambos') &&
          r.name);
        const supplierRows = newRows.filter(r =>
          (r._entity_type === 'Fornecedor' || r._entity_type === 'Ambos') &&
          r.name);

        for (const chunk of chunks(clientRows, 50)) {
          const rows = chunk.map((r: any) => ({
            full_name_or_company_name: r.name,
            type: r._type || 'company',
            cpf_cnpj: r.cnpj_cpf || null,
            email: r.email || null,
            phone: r.phone || null,
            address_line_1: r.address_line_1 || null,
            address_line_2: [r.address_number, r.neighborhood, r.address_complement].filter(Boolean).join(', ') || null,
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
            supplier_name: r.name,
            trade_name: r.trade_name || null,
            cnpj_cpf: r.cnpj_cpf || null,
            contact_email: r.email || null,
            contact_phone: r.phone || null,
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
