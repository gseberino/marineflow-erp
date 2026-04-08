import { useState, useCallback } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { useI18n } from '@/i18n';
import { useBankTransactions, useImportBankTransactions, useReconcile, useDismissBankTransaction, useReceivables, usePayables } from '@/hooks/use-financial';
import { parseFile, type BankTransaction } from '@/lib/bank-parser';
import { toast } from 'sonner';
import { Upload, Check, X, ArrowRight } from 'lucide-react';
import { StatusBadge } from '@/components/StatusBadge';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible';

export function BankReconciliation() {
  const { t, formatCurrency, formatDate } = useI18n();
  const { data: transactions, isLoading } = useBankTransactions();
  const { data: receivables } = useReceivables();
  const { data: payables } = usePayables();
  const importMutation = useImportBankTransactions();
  const reconcile = useReconcile();
  const dismiss = useDismissBankTransaction();

  const [preview, setPreview] = useState<BankTransaction[] | null>(null);
  const [filter, setFilter] = useState<'all' | 'credit' | 'debit'>('all');
  const [reconcileId, setReconcileId] = useState<string | null>(null);
  const [searchMatch, setSearchMatch] = useState('');

  const handleFile = useCallback((file: File) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      const content = e.target?.result as string;
      const parsed = parseFile(content, file.name);
      if (parsed.length === 0) {
        toast.error('Nenhuma transação encontrada no arquivo');
        return;
      }
      setPreview(parsed);
    };
    reader.readAsText(file);
  }, []);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    const file = e.dataTransfer.files[0];
    if (file) handleFile(file);
  }, [handleFile]);

  const handleImport = async () => {
    if (!preview) return;
    try {
      await importMutation.mutateAsync(preview);
      toast.success(`${preview.length} transações importadas`);
      setPreview(null);
    } catch { toast.error('Erro ao importar'); }
  };

  const unreconciled = (transactions || []).filter(t => !t.reconciled);
  const reconciled = (transactions || []).filter(t => t.reconciled);
  const filtered = unreconciled.filter(t => filter === 'all' || t.transaction_type === filter);

  const getSuggestions = (tx: any) => {
    const isCredit = tx.transaction_type === 'credit';
    const records = isCredit
      ? (receivables || []).filter(r => r.status !== 'paid' && r.status !== 'cancelled')
      : (payables || []).filter(p => p.status !== 'paid' && p.status !== 'cancelled');

    return records
      .filter(r => {
        if (searchMatch) {
          const desc = (r.description || '').toLowerCase();
          const name = isCredit ? ((r as any).clients?.full_name_or_company_name || '').toLowerCase() : '';
          return desc.includes(searchMatch.toLowerCase()) || name.includes(searchMatch.toLowerCase());
        }
        // Auto-match: amount within 5% and date within 7 days
        const amtRatio = Math.abs(Number(r.balance_amount) - tx.amount) / tx.amount;
        const daysDiff = Math.abs(new Date(r.due_date).getTime() - new Date(tx.transaction_date).getTime()) / 86400000;
        return amtRatio <= 0.05 && daysDiff <= 7;
      })
      .slice(0, 5);
  };

  const handleReconcile = async (bankTx: any, record: any, isReceivable: boolean) => {
    try {
      await reconcile.mutateAsync({
        bankTransactionId: bankTx.id,
        receivableId: isReceivable ? record.id : undefined,
        payableId: !isReceivable ? record.id : undefined,
        amount: bankTx.amount,
      });
      toast.success(t.financial.confirmReconciliation);
      setReconcileId(null);
    } catch { toast.error('Erro ao conciliar'); }
  };

  return (
    <div className="space-y-6">
      {/* Import */}
      <div
        className="border-2 border-dashed rounded-xl p-8 text-center cursor-pointer hover:border-primary/50 transition-colors"
        onDragOver={e => e.preventDefault()} onDrop={handleDrop}
        onClick={() => { const i = document.createElement('input'); i.type = 'file'; i.accept = '.ofx,.csv,.xls,.xlsx'; i.onchange = (e: any) => { if (e.target.files[0]) handleFile(e.target.files[0]); }; i.click(); }}
      >
        <Upload className="h-8 w-8 mx-auto mb-2 text-muted-foreground" />
        <p className="text-sm text-muted-foreground">{t.financial.dropStatementHere}</p>
      </div>

      {/* Preview */}
      {preview && (
        <div className="rounded-xl border bg-card p-4 space-y-3">
          <p className="font-medium">{preview.length} transações encontradas</p>
          <div className="max-h-48 overflow-y-auto">
            <table className="w-full text-sm">
              <thead><tr className="border-b"><th className="text-left py-1 px-2">{t.common.date}</th><th className="text-left py-1 px-2">{t.common.description}</th><th className="text-left py-1 px-2">{t.common.type}</th><th className="text-right py-1 px-2">{t.common.amount}</th></tr></thead>
              <tbody>
                {preview.slice(0, 10).map((tx, i) => (
                  <tr key={i} className="border-b last:border-0">
                    <td className="py-1 px-2">{tx.transaction_date}</td>
                    <td className="py-1 px-2 truncate max-w-[200px]">{tx.description}</td>
                    <td className="py-1 px-2"><StatusBadge className={tx.transaction_type === 'credit' ? 'bg-success/15 text-success' : 'bg-destructive/10 text-destructive'}>{tx.transaction_type === 'credit' ? 'Entrada' : 'Saída'}</StatusBadge></td>
                    <td className="py-1 px-2 text-right font-medium">{formatCurrency(tx.amount)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            {preview.length > 10 && <p className="text-sm text-muted-foreground mt-1">e mais {preview.length - 10}...</p>}
          </div>
          <Button onClick={handleImport} disabled={importMutation.isPending}>
            {(t.financial.importTransactions as string).replace('{count}', String(preview.length))}
          </Button>
        </div>
      )}

      {/* Unreconciled */}
      <div>
        <div className="flex items-center justify-between mb-3">
          <h3 className="font-semibold">{t.financial.unreconciledTransactions} ({unreconciled.length})</h3>
          <div className="flex gap-1">
            {(['all', 'credit', 'debit'] as const).map(f => (
              <Button key={f} size="sm" variant={filter === f ? 'default' : 'outline'}
                onClick={() => setFilter(f)}>
                {f === 'all' ? t.common.all : f === 'credit' ? t.financial.inflow : t.financial.outflow}
              </Button>
            ))}
          </div>
        </div>

        {filtered.length === 0 && <p className="text-sm text-muted-foreground py-4 text-center">{t.common.noResults}</p>}

        <div className="space-y-2">
          {filtered.map(tx => (
            <div key={tx.id} className="rounded-lg border bg-card">
              <div className="flex items-center justify-between p-3">
                <div className="flex items-center gap-3">
                  <span className="text-sm text-muted-foreground">{formatDate(tx.transaction_date)}</span>
                  <span className="text-sm truncate max-w-[300px]">{tx.description}</span>
                </div>
                <div className="flex items-center gap-3">
                  <span className={`font-semibold ${tx.transaction_type === 'credit' ? 'text-success' : 'text-destructive'}`}>
                    {tx.transaction_type === 'credit' ? '+' : '-'}{formatCurrency(Number(tx.amount))}
                  </span>
                  <Button size="sm" variant="outline" onClick={() => setReconcileId(reconcileId === tx.id ? null : tx.id)}>
                    {t.financial.reconcile}
                  </Button>
                </div>
              </div>

              {reconcileId === tx.id && (
                <div className="border-t p-3 bg-muted/30 space-y-3">
                  <p className="text-sm font-medium">
                    {tx.transaction_type === 'credit' ? 'Vincular a um recebível' : 'Vincular a um pagável'}
                  </p>
                  <Input placeholder="Buscar..." value={searchMatch} onChange={e => setSearchMatch(e.target.value)} className="max-w-xs" />
                  <div className="space-y-1 max-h-40 overflow-y-auto">
                    {getSuggestions(tx).map(r => {
                      const isRec = tx.transaction_type === 'credit';
                      const amtRatio = Math.abs(Number(r.balance_amount) - Number(tx.amount)) / Number(tx.amount);
                      const isAutoMatch = amtRatio <= 0.05;
                      return (
                        <div key={r.id} className={`flex items-center justify-between p-2 rounded border text-sm ${isAutoMatch ? 'border-warning bg-warning/5' : ''}`}>
                          <div>
                            <span className="font-medium">{r.description}</span>
                            {isRec && (r as any).clients && <span className="text-muted-foreground ml-2">— {(r as any).clients.full_name_or_company_name}</span>}
                            {isAutoMatch && <StatusBadge className="bg-warning/15 text-warning ml-2">{t.financial.autoSuggestion}</StatusBadge>}
                          </div>
                          <div className="flex items-center gap-2">
                            <span className="font-medium">{formatCurrency(Number(r.balance_amount))}</span>
                            <Button size="sm" onClick={() => handleReconcile(tx, r, isRec)} disabled={reconcile.isPending}>
                              <Check className="h-3 w-3 mr-1" />{t.financial.confirmReconciliation}
                            </Button>
                          </div>
                        </div>
                      );
                    })}
                    {getSuggestions(tx).length === 0 && <p className="text-sm text-muted-foreground">{t.common.noResults}</p>}
                  </div>
                  <Button size="sm" variant="ghost" onClick={async () => { await dismiss.mutateAsync(tx.id); setReconcileId(null); }}>
                    <X className="h-3 w-3 mr-1" />{t.financial.ignore}
                  </Button>
                </div>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Reconciled */}
      {reconciled.length > 0 && (
        <Collapsible>
          <CollapsibleTrigger className="flex items-center gap-2 text-sm font-medium text-muted-foreground hover:text-foreground">
            <ArrowRight className="h-4 w-4" /> {t.financial.reconciledTransactions} ({reconciled.length})
          </CollapsibleTrigger>
          <CollapsibleContent className="mt-2 space-y-1">
            {reconciled.map(tx => (
              <div key={tx.id} className="flex items-center justify-between p-2 text-sm border rounded">
                <span className="text-muted-foreground">{formatDate(tx.transaction_date)}</span>
                <span className="truncate max-w-[300px]">{tx.description}</span>
                <span className={tx.transaction_type === 'credit' ? 'text-success' : 'text-destructive'}>
                  {formatCurrency(Number(tx.amount))}
                </span>
                <StatusBadge className="bg-success/15 text-success">✓</StatusBadge>
              </div>
            ))}
          </CollapsibleContent>
        </Collapsible>
      )}
    </div>
  );
}
