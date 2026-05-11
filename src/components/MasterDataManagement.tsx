import { useState } from 'react';
import { toast } from 'sonner';
import { Download, Database, AlertTriangle, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { IMPORT_BLOCK_REASON } from '@/lib/master-data-backup';

type BackupRow = Record<string, unknown>;

const EXPORT_TABLES = [
  'app_settings', 'app_users', 'clients', 'suppliers', 'marinas', 'vessels',
  'product_categories', 'financial_categories', 'payment_condition_presets',
  'products', 'services', 'supplier_product_mappings',
  'product_price_history', 'price_update_suggestions', 'inventory_movements',
  'service_orders', 'service_order_parts', 'service_order_services',
  'service_order_technicians', 'agenda_tasks',
  'external_quote_leads', 'external_quotes', 'external_quote_parts', 'external_quote_services',
  'purchase_orders', 'purchase_order_items',
  'fiscal_notes', 'fiscal_note_items',
  'collections', 'payables', 'audit_log',
];

export function MasterDataPanel() {
  const [exporting, setExporting] = useState(false);

  const handleExport = async () => {
    setExporting(true);
    try {
      const backup: Record<string, BackupRow[]> = {};

      for (const table of EXPORT_TABLES) {
        let allRows: BackupRow[] = [];
        let page = 0;
        const limit = 1000;

        while (true) {
          const { data, error } = await supabase
            .from(table as never)
            .select('*')
            .range(page * limit, (page + 1) * limit - 1);

          if (error) {
            if (error.code === 'PGRST116' || error.message.includes('schema cache')) {
              console.warn(`Table ${table} not found in schema cache, skipping.`);
              break;
            }
            throw error;
          }

          if (!data || data.length === 0) {
            break;
          }

          allRows = allRows.concat(data as BackupRow[]);
          if (data.length < limit) {
            break;
          }
          page += 1;
        }

        if (allRows.length > 0) {
          backup[table] = allRows;
        }
      }

      backup._meta = [{ version: '1.2', date: new Date().toISOString() }];

      const jsonStr = JSON.stringify(backup, null, 2);
      const blob = new Blob([jsonStr], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = `marineflow_backup_${new Date().toISOString().slice(0, 10)}.json`;
      document.body.appendChild(anchor);
      anchor.click();
      document.body.removeChild(anchor);
      URL.revokeObjectURL(url);

      toast.success('Backup exportado com sucesso.');
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Tente novamente.';
      toast.error(`Erro ao exportar dados: ${message}`);
    } finally {
      setExporting(false);
    }
  };

  return (
    <div className="rounded-xl border bg-card p-6 shadow-sm max-w-2xl space-y-4">
      <div>
        <h3 className="text-sm font-semibold mb-2 flex items-center gap-2">
          <Database className="h-4 w-4" /> Exportacao e Importacao Global
        </h3>
        <p className="text-sm text-muted-foreground">
          Exporte um backup completo do banco de dados. A importacao operacional ficou fora da UI
          ate a migracao passar a rodar por scripts auditaveis e validacao offline.
        </p>
      </div>

      <Alert className="border-warning/40 bg-warning/10 text-foreground">
        <AlertTriangle className="h-4 w-4" />
        <AlertTitle>Importacao bloqueada</AlertTitle>
        <AlertDescription>{IMPORT_BLOCK_REASON}</AlertDescription>
      </Alert>

      <div className="flex gap-4">
        <Button onClick={handleExport} disabled={exporting}>
          {exporting ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Download className="h-4 w-4 mr-2" />}
          Exportar Dados (Backup)
        </Button>

        <Button variant="outline" disabled>
          Importar Dados
        </Button>
      </div>
    </div>
  );
}
