import { useState, useRef } from 'react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Download, Upload, CheckCircle, Database, AlertTriangle, ArrowLeft, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useI18n } from '@/i18n';

// The complete list of tables to export
const EXPORT_TABLES = [
  'app_settings', 'app_users', 'clients', 'suppliers', 'marinas', 'vessels',
  'product_categories', 'financial_categories', 'payment_condition_presets',
  'products', 'services', 'supplier_product_mappings',
  'product_price_history', 'price_update_suggestions', 'inventory_movements',
  'service_orders', 'service_order_parts', 'service_order_services',
  'service_order_technicians', 'agenda_tasks',
  'external_quotes', 'external_quote_items',
  'purchase_orders', 'purchase_order_items',
  'smart_purchases', 'smart_purchase_items',
  'fiscal_notes', 'fiscal_note_items',
  'collections', 'payables', 'whatsapp_message_logs'
];

export function MasterDataPanel() {
  const { t } = useI18n();
  const fileRef = useRef<HTMLInputElement>(null);
  const [exporting, setExporting] = useState(false);
  const [importOpen, setImportOpen] = useState(false);
  const [importing, setImporting] = useState(false);
  const [importData, setImportData] = useState<Record<string, any[]> | null>(null);

  const handleExport = async () => {
    setExporting(true);
    try {
      const backup: Record<string, any[]> = {};
      
      for (const table of EXPORT_TABLES) {
        let allRows: any[] = [];
        let page = 0;
        const limit = 1000;
        while (true) {
          const { data, error } = await supabase
            .from(table as any)
            .select('*')
            .range(page * limit, (page + 1) * limit - 1);
            
          if (error) throw error;
          if (!data || data.length === 0) break;
          
          allRows = allRows.concat(data);
          if (data.length < limit) break;
          page++;
        }
        backup[table] = allRows;
      }
      
      backup['_meta'] = [{ version: '1.0', date: new Date().toISOString() }];

      const jsonStr = JSON.stringify(backup, null, 2);
      const blob = new Blob([jsonStr], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `marineflow_backup_${new Date().toISOString().slice(0, 10)}.json`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      
      toast.success('Backup exportado com sucesso!');
    } catch (err: any) {
      toast.error('Erro ao exportar dados: ' + (err?.message || 'Tente novamente'));
    } finally {
      setExporting(false);
    }
  };

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    
    const reader = new FileReader();
    reader.onload = () => {
      try {
        const json = JSON.parse(reader.result as string);
        if (!json._meta) {
          toast.error('Arquivo de backup inválido.');
          return;
        }
        setImportData(json);
        setImportOpen(true);
      } catch (err) {
        toast.error('Arquivo JSON inválido.');
      }
    };
    reader.readAsText(file);
    e.target.value = ''; // reset
  };

  const executeImport = async () => {
    if (!importData) return;
    setImporting(true);
    try {
      // Dependecy-safe import order
      const importOrder = [
        'app_settings', 'app_users', 'clients', 'suppliers', 'marinas', 'vessels',
        'product_categories', 'financial_categories', 'payment_condition_presets',
        'products', 'services', 'supplier_product_mappings',
        'inventory_movements', 'service_orders', 'service_order_parts', 
        'service_order_services', 'service_order_technicians', 'agenda_tasks',
        'external_quotes', 'external_quote_items',
        'collections', 'payables', 'fiscal_notes', 'fiscal_note_items',
        'price_update_suggestions', 'product_price_history',
        'purchase_orders', 'purchase_order_items',
        'smart_purchases', 'smart_purchase_items',
        'whatsapp_message_logs'
      ];
      
      // Import any other tables that might be in the file but not in our explicit order
      const fileTables = Object.keys(importData).filter(k => k !== '_meta');
      const allTablesToImport = [...new Set([...importOrder, ...fileTables])];

      for (const table of allTablesToImport) {
        const rows = importData[table] || [];
        if (rows.length === 0) continue;
        
        // Chunk inserts
        const chunk = 100;
        for (let i = 0; i < rows.length; i += chunk) {
          const slice = rows.slice(i, i + chunk);
          const { error } = await supabase.from(table as any).upsert(slice);
          if (error) {
            console.error(`Error importing ${table}:`, error);
            throw new Error(`Erro na tabela ${table}: ${error.message}`);
          }
        }
      }
      
      toast.success('Importação concluída com sucesso!');
      setImportOpen(false);
      setImportData(null);
    } catch (err: any) {
      toast.error('Falha na importação: ' + err.message);
    } finally {
      setImporting(false);
    }
  };

  return (
    <div className="rounded-xl border bg-card p-6 shadow-sm max-w-2xl">
      <h3 className="text-sm font-semibold mb-4 flex items-center gap-2">
        <Database className="h-4 w-4" /> Exportação e Importação Global
      </h3>
      <p className="text-sm text-muted-foreground mb-4">
        Exporte um backup completo do banco de dados (cadastros, logs, OS, etc.) no formato JSON, 
        ou importe um backup existente.
      </p>
      
      <div className="flex gap-4">
        <Button onClick={handleExport} disabled={exporting}>
          {exporting ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Download className="h-4 w-4 mr-2" />}
          Exportar Dados (Backup)
        </Button>
        
        <Button variant="outline" onClick={() => fileRef.current?.click()} disabled={exporting}>
          <Upload className="h-4 w-4 mr-2" />
          Importar Dados
        </Button>
        <input 
          ref={fileRef} 
          type="file" 
          accept=".json" 
          className="hidden" 
          onChange={handleFileSelect} 
        />
      </div>

      <Dialog open={importOpen} onOpenChange={(v) => !importing && setImportOpen(v)}>
        <DialogContent className="max-w-4xl max-h-[85vh] overflow-hidden flex flex-col">
          <DialogHeader>
            <DialogTitle>Revisão de Importação Global</DialogTitle>
          </DialogHeader>
          
          {importData && (
            <div className="flex-1 overflow-hidden flex flex-col">
              <div className="mb-4 text-sm text-muted-foreground bg-warning/10 border border-warning/30 p-3 rounded flex items-start gap-2">
                <AlertTriangle className="h-5 w-5 text-warning shrink-0" />
                <p>
                  Atenção: A importação irá <strong>sobrescrever</strong> registros existentes que possuam o mesmo ID 
                  e adicionar os novos. Certifique-se de que este é o backup correto.
                </p>
              </div>

              <Tabs defaultValue={Object.keys(importData).filter(k => k !== '_meta')[0]} className="flex-1 flex flex-col min-h-0">
                <div className="overflow-x-auto scrollbar-thin pb-2 mb-2">
                  <TabsList className="h-auto whitespace-nowrap px-1">
                    {Object.keys(importData).filter(k => k !== '_meta').map(table => {
                      const count = (importData[table] || []).length;
                      if (count === 0) return null;
                      return (
                        <TabsTrigger key={table} value={table} className="text-xs py-1">
                          {table} ({count})
                        </TabsTrigger>
                      );
                    })}
                  </TabsList>
                </div>
                
                <div className="flex-1 overflow-y-auto border rounded-md p-2 bg-muted/20">
                  {Object.keys(importData).filter(k => k !== '_meta').map(table => {
                    const rows = importData[table] || [];
                    if (rows.length === 0) return null;
                    const keys = Object.keys(rows[0] || {}).slice(0, 8);
                    
                    return (
                      <TabsContent key={table} value={table} className="m-0">
                        <div className="overflow-x-auto scrollbar-thin">
                          <table className="w-full text-xs text-left border-collapse">
                            <thead>
                              <tr className="bg-muted/50 border-b">
                                {keys.map(k => <th key={k} className="p-2 font-medium">{k}</th>)}
                                {Object.keys(rows[0]).length > 8 && <th className="p-2">...</th>}
                              </tr>
                            </thead>
                            <tbody>
                              {rows.slice(0, 10).map((row, i) => (
                                <tr key={i} className="border-b last:border-0 hover:bg-muted/30">
                                  {keys.map(k => (
                                    <td key={k} className="p-2 truncate max-w-[150px]">
                                      {String(row[k] ?? '')}
                                    </td>
                                  ))}
                                  {Object.keys(row).length > 8 && <td className="p-2">...</td>}
                                </tr>
                              ))}
                            </tbody>
                          </table>
                          {rows.length > 10 && (
                            <p className="text-xs text-center text-muted-foreground mt-2">
                              + {rows.length - 10} registros ocultos...
                            </p>
                          )}
                        </div>
                      </TabsContent>
                    );
                  })}
                </div>
              </Tabs>
              
              <div className="mt-4 flex justify-end gap-2 shrink-0">
                <Button variant="outline" onClick={() => setImportOpen(false)} disabled={importing}>
                  Cancelar
                </Button>
                <Button onClick={executeImport} disabled={importing}>
                  {importing && <Loader2 className="h-4 w-4 animate-spin mr-2" />}
                  {importing ? 'Importando...' : 'Confirmar Importação'}
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
