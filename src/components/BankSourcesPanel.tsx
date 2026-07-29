import { useState, useCallback } from 'react';
import { Button } from '@/components/ui/button';
import { StatusBadge } from '@/components/StatusBadge';
import { useI18n } from '@/i18n';
import { BankConnectionsPanel } from '@/components/BankConnectionsPanel';
import { useImportBankTransactions } from '@/hooks/use-financial';
import { parseFile, decodeStatementFile, type BankTransaction } from '@/lib/bank-parser';
import { toast } from 'sonner';
import { Upload } from 'lucide-react';

/**
 * Contas bancárias e importação de extrato.
 *
 * Seção própria porque conectar banco é configuração de infraestrutura, não parte do
 * trabalho diário de conciliar. Enquanto morava dentro da aba de conciliação, ficava
 * enterrada atrás de uma sub-aba e o usuário não a encontrava.
 */
export function BankSourcesPanel() {
  const { t, formatCurrency } = useI18n();
  const importMutation = useImportBankTransactions();
  const [preview, setPreview] = useState<BankTransaction[] | null>(null);
  const [previewSource, setPreviewSource] = useState<'bank' | 'credit_card'>('bank');

  const handleFile = useCallback((file: File) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      // Lido como bytes: o encoding do extrato varia por banco e decodificar
      // Latin-1 como UTF-8 corrompe todos os acentos das descrições.
      const content = decodeStatementFile(e.target?.result as ArrayBuffer);
      const result = parseFile(content, file.name);
      if (result.transactions.length === 0) {
        toast.error('Nenhuma transação encontrada no arquivo');
        return;
      }
      setPreview(result.transactions);
      setPreviewSource(result.source_type);
    };
    reader.readAsArrayBuffer(file);
  }, []);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    const file = e.dataTransfer.files[0];
    if (file) handleFile(file);
  }, [handleFile]);

  const handleImport = async () => {
    if (!preview) return;
    try {
      const { imported, skipped } = await importMutation.mutateAsync({
        transactions: preview, source_type: previewSource,
      });
      if (imported === 0 && skipped > 0) {
        toast.info(`Nada novo: as ${skipped} transações do arquivo já haviam sido importadas`);
      } else {
        toast.success(
          skipped > 0
            ? `${imported} transações importadas · ${skipped} já existiam e foram ignoradas`
            : `${imported} transações importadas`,
        );
      }
      setPreview(null);
    } catch {
      toast.error('Erro ao importar');
    }
  };

  return (
    <div className="space-y-6">
      <BankConnectionsPanel />

      <div className="space-y-2">
        <div>
          <h3 className="font-semibold">Importar extrato por arquivo</h3>
          <p className="text-sm text-muted-foreground">
            Alternativa para banco sem Open Finance, ou para trazer histórico antigo.
            Transações repetidas são descartadas automaticamente.
          </p>
        </div>

        <div
          className="border-2 border-dashed rounded-xl p-8 text-center cursor-pointer hover:border-primary/50 transition-colors"
          onDragOver={e => e.preventDefault()}
          onDrop={handleDrop}
          onClick={() => {
            const i = document.createElement('input');
            i.type = 'file';
            i.accept = '.ofx,.csv,.xls,.xlsx';
            i.onchange = (e: any) => { if (e.target.files[0]) handleFile(e.target.files[0]); };
            i.click();
          }}
        >
          <Upload className="h-8 w-8 mx-auto mb-2 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">{t.financial.dropStatementHere}</p>
        </div>
      </div>

      {preview && (
        <div className="rounded-xl border bg-card p-4 space-y-3">
          {previewSource === 'credit_card' && (
            <div className="rounded-lg bg-warning/10 border border-warning/30 p-3 text-sm text-warning">
              {t.financial.cardStatementDetected}
            </div>
          )}
          <p className="font-medium">{preview.length} transações encontradas</p>
          <div className="max-h-64 overflow-x-auto scrollbar-thin">
            <table className="w-full text-sm min-w-[520px]">
              <thead>
                <tr className="border-b">
                  <th className="text-left py-1 px-2">{t.common.date}</th>
                  <th className="text-left py-1 px-2">{t.common.description}</th>
                  <th className="text-left py-1 px-2">{t.common.type}</th>
                  <th className="text-right py-1 px-2">{t.common.amount}</th>
                </tr>
              </thead>
              <tbody>
                {preview.slice(0, 10).map((tx, i) => (
                  <tr key={i} className="border-b last:border-0">
                    <td className="py-1 px-2">{tx.transaction_date}</td>
                    <td className="py-1 px-2 truncate max-w-[220px]">{tx.description}</td>
                    <td className="py-1 px-2">
                      <StatusBadge className={tx.transaction_type === 'credit' ? 'bg-success/15 text-success' : 'bg-destructive/10 text-destructive'}>
                        {tx.transaction_type === 'credit' ? 'Entrada' : 'Saída'}
                      </StatusBadge>
                    </td>
                    <td className="py-1 px-2 text-right font-medium tabular-nums">{formatCurrency(tx.amount)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            {preview.length > 10 && (
              <p className="text-sm text-muted-foreground mt-1">e mais {preview.length - 10}...</p>
            )}
          </div>
          <div className="flex gap-2">
            <Button onClick={handleImport} disabled={importMutation.isPending}>
              {(t.financial.importTransactions as string).replace('{count}', String(preview.length))}
            </Button>
            <Button variant="outline" onClick={() => setPreview(null)}>Cancelar</Button>
          </div>
        </div>
      )}
    </div>
  );
}
