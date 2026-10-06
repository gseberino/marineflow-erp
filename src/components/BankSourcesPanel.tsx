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
export function BankSourcesPanel({ semBotaoGeral = false }: { semBotaoGeral?: boolean } = {}) {
  const { t, formatCurrency, formatDate } = useI18n();
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
      <BankConnectionsPanel semBotaoGeral={semBotaoGeral} />

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
          {/* Lista, não tabela: a tabela de 520px rolava de lado no celular (princípio nº 0 do dono). */}
          <div className="max-h-64 overflow-y-auto scrollbar-thin">
            <ul className="divide-y text-sm">
              {preview.slice(0, 10).map((tx, i) => (
                <li key={i} className="flex min-w-0 items-center justify-between gap-3 py-1.5">
                  <div className="min-w-0">
                    <p className="truncate">{tx.description}</p>
                    <p className="text-xs text-muted-foreground tabular-nums">{formatDate(tx.transaction_date)}</p>
                  </div>
                  <div className="flex shrink-0 items-center gap-2">
                    <StatusBadge className={tx.transaction_type === 'credit' ? 'bg-success/15 text-success' : 'bg-destructive/10 text-destructive'}>
                      {tx.transaction_type === 'credit' ? 'Entrada' : 'Saída'}
                    </StatusBadge>
                    <span className="font-medium tabular-nums">{formatCurrency(tx.amount)}</span>
                  </div>
                </li>
              ))}
            </ul>
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
