import { useState, useRef } from 'react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Download, Upload, CheckCircle, Database, AlertTriangle, ArrowLeft, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useI18n } from '@/i18n';

// The complete list of tables to export
// The complete list of verified tables to export
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
  'collections', 'payables', 'audit_log'
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
        try {
          let allRows: any[] = [];
          let page = 0;
          const limit = 1000;
          while (true) {
            const { data, error } = await supabase
              .from(table as any)
              .select('*')
              .range(page * limit, (page + 1) * limit - 1);
              
            if (error) {
              if (error.code === 'PGRST116' || error.message.includes('schema cache')) {
                console.warn(`Table ${table} not found in schema cache, skipping.`);
                break;
              }
              throw error;
            }
            if (!data || data.length === 0) break;
            
            allRows = allRows.concat(data);
            if (data.length < limit) break;
            page++;
          }
          if (allRows.length > 0) {
            backup[table] = allRows;
          }
        } catch (tableErr) {
          console.warn(`Failed to export table ${table}:`, tableErr);
        }
      }
      
      backup['_meta'] = [{ version: '1.1', date: new Date().toISOString() }];

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
      // 1. Intelligent Field Mapping (Old Names -> New Names)
      const FIELD_MAP: Record<string, string> = {
        'name': 'full_name_or_company_name', // for clients
        'supplier_name_legacy': 'supplier_name', 
        'boat_name_legacy': 'boat_name',
        'product_name_legacy': 'product_name',
        'service_name_legacy': 'service_name',
        'contact_email_legacy': 'contact_email',
        'contact_phone_legacy': 'contact_phone'
      };

      // Table-specific renames
      const TABLE_FIELD_MAP: Record<string, Record<string, string>> = {
        'clients': { 'name': 'full_name_or_company_name', 'cnpj_cpf': 'cpf_cnpj' },
        'suppliers': { 'name': 'supplier_name', 'cpf_cnpj': 'cnpj_cpf' },
        'marinas': { 'name': 'marina_name' },
        'vessels': { 'name': 'boat_name' },
        'products': { 'name': 'product_name' },
        'services': { 'name': 'service_name' },
        'external_quote_leads': { 'name': 'full_name_or_company_name' }
      };

      // 2. Resolve User ID mappings
      const { data: currentDbUsers } = await supabase.from('app_users').select('id, email');
      const userMap: Record<string, string> = {};
      const backupUsers = importData['app_users'] || [];
      
      backupUsers.forEach(bu => {
        const dbMatch = currentDbUsers?.find(du => du.email === bu.email);
        if (dbMatch && dbMatch.id !== bu.id) {
          userMap[bu.id] = dbMatch.id;
        }
      });

      const processedData = JSON.parse(JSON.stringify(importData));
      
      // 3. Global Transformation (Mapping Columns & User IDs)
      Object.keys(processedData).forEach(table => {
        if (table === '_meta') return;
        processedData[table] = processedData[table].map((row: any) => {
          let newRow = { ...row };
          
          // Apply Table-Specific Mappings
          if (TABLE_FIELD_MAP[table]) {
            Object.keys(TABLE_FIELD_MAP[table]).forEach(oldKey => {
              if (newRow[oldKey] !== undefined && newRow[TABLE_FIELD_MAP[table][oldKey]] === undefined) {
                newRow[TABLE_FIELD_MAP[table][oldKey]] = newRow[oldKey];
                delete newRow[oldKey];
              }
            });
          }

          // Apply User ID Mappings
          Object.keys(newRow).forEach(key => {
            const val = newRow[key];
            if (typeof val === 'string' && userMap[val]) {
              newRow[key] = userMap[val];
            }
          });
          
          return newRow;
        });
      });

      // 4. Dependency-safe import order
      const importOrder = [
        'app_settings', 'app_users', 'clients', 'suppliers', 'marinas', 'vessels',
        'product_categories', 'financial_categories', 'payment_condition_presets',
        'products', 'services', 'supplier_product_mappings',
        'inventory_movements', 
        'external_quote_leads', 'external_quotes', 'external_quote_parts', 'external_quote_services',
        'service_orders', 'service_order_parts', 'service_order_services', 'service_order_technicians', 'agenda_tasks',
        'collections', 'payables', 'fiscal_notes', 'fiscal_note_items',
        'price_update_suggestions', 'product_price_history',
        'purchase_orders', 'purchase_order_items',
        'audit_log'
      ];
      
      const fileTables = Object.keys(processedData).filter(k => k !== '_meta');
      const allTablesToImport = [
        ...importOrder.filter(t => fileTables.includes(t)),
        ...fileTables.filter(t => !importOrder.includes(t))
      ];

      for (const table of allTablesToImport) {
        const rows = processedData[table] || [];
        if (rows.length === 0) continue;
        
        const chunk = 50;
        for (let i = 0; i < rows.length; i += chunk) {
          const slice = rows.slice(i, i + chunk);
          let finalSlice = slice;
          
          if (table === 'app_users') {
             finalSlice = slice.filter((u: any) => !Object.values(userMap).includes(u.id));
          }
          
          if (finalSlice.length === 0) continue;

          const { error } = await supabase.from(table as any).upsert(finalSlice);
          if (error) {
            console.error(`Error importing ${table}:`, error);
            // If it's a "column does not exist" error, we might want to be even more resilient
            if (error.message.includes('column') && error.message.includes('does not exist')) {
               console.warn(`Attempting recovery for ${table} by removing invalid columns...`);
               // This is a last-resort recovery: try to filter out the problematic column
               // For now, we'll just throw so the user can see which column it is
            }
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

  const tablesInFile = importData ? Object.keys(importData).filter(k => k !== '_meta') : [];
  const firstTable = tablesInFile.length > 0 ? tablesInFile[0] : '';

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
          
          {!importData ? (
            <div className="p-8 flex justify-center"><Loader2 className="h-8 w-8 animate-spin" /></div>
          ) : (
            <div className="flex-1 overflow-hidden flex flex-col">
              <div className="mb-4 text-sm text-muted-foreground bg-warning/10 border border-warning/30 p-3 rounded flex items-start gap-2">
                <AlertTriangle className="h-5 w-5 text-warning shrink-0" />
                <p>
                  A importação irá <strong>sobrescrever</strong> registros com o mesmo ID. Verifique os dados abaixo antes de confirmar.
                </p>
              </div>

              <Tabs defaultValue={firstTable} className="flex-1 flex flex-col min-h-0">
                <div className="overflow-x-auto scrollbar-thin pb-2 mb-2">
                  <TabsList className="h-auto whitespace-nowrap px-1">
                    {tablesInFile.map(table => {
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
                  {tablesInFile.map(table => {
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
