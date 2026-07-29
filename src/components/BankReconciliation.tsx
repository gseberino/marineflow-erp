import { useState, useCallback } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useI18n } from '@/i18n';
import {
  useBankTransactions, useImportBankTransactions, useReconcile, useDismissBankTransaction,
  useUnignoreBankTransaction,
  useReceivables, usePayables, useCreateReceivable, useCreatePayable, useRegisterPayment,
} from '@/hooks/use-financial';
import { useServiceOrders } from '@/hooks/use-service-orders';
import { useClients } from '@/hooks/use-clients';
import { useSuppliers } from '@/hooks/use-suppliers';
import { OPERATIONAL_EXPENSE_CATEGORIES } from '@/lib/expense-categories';
import { parseFile, decodeStatementFile, type BankTransaction } from '@/lib/bank-parser';
import {
  useReconcileSuggestions, useAutoReconcile, useApplySuggestion, useApplyGroup, useAnalyzeWithAI,
  useReconciliationHealth,
  CANDIDATE_LABELS, type ReconcileSuggestion, type ReconcileGroup,
} from '@/hooks/use-reconciliation';
import { toast } from 'sonner';
import { Upload, Check, X, Undo2, Sparkles, AlertTriangle } from 'lucide-react';
import { StatusBadge } from '@/components/StatusBadge';
import { BankConnectionsPanel } from '@/components/BankConnectionsPanel';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';

type ReconcileMode = 'existing' | 'service_order' | 'new' | 'dismiss';
type TabType = 'pending' | 'reconciled' | 'ignored';

export function BankReconciliation() {
  const { t, formatCurrency, formatDate } = useI18n();
  const qc = useQueryClient();
  const { data: transactions, isLoading } = useBankTransactions();
  const { data: receivables } = useReceivables();
  const { data: payables } = usePayables();
  const { data: serviceOrders } = useServiceOrders();
  const { data: clients } = useClients();
  const { data: suppliers } = useSuppliers();
  const importMutation = useImportBankTransactions();
  const reconcile = useReconcile();
  const dismiss = useDismissBankTransaction();
  const unignore = useUnignoreBankTransaction();
  const createReceivable = useCreateReceivable();
  const createPayable = useCreatePayable();
  const registerPayment = useRegisterPayment();

  // Motor de conciliação: sugestões pontuadas vindas do backend, que enxerga candidatos
  // que a tela não tinha — sinal de orçamento, saldo de OS e cobranças avulsas.
  const { data: engine, isLoading: engineLoading, refetch: refetchEngine } = useReconcileSuggestions();
  const autoReconcile = useAutoReconcile();
  const applySuggestion = useApplySuggestion();
  const applyGroup = useApplyGroup();
  const analyzeWithAI = useAnalyzeWithAI();
  const { data: health } = useReconciliationHealth();
  const [aiAnalysis, setAiAnalysis] = useState<Record<string, string>>({});
  const suggestionsByTx = new Map<string, ReconcileSuggestion[]>(
    (engine?.transactions || []).map(t => [t.transaction.id, t.suggestions]),
  );
  const groupsByTx = new Map<string, ReconcileGroup[]>(
    (engine?.transactions || []).map(t => [t.transaction.id, t.groups || []]),
  );
  const internalTransferTx = new Set(
    (engine?.transactions || []).filter(t => t.internalTransfer).map(t => t.transaction.id),
  );

  const [tab, setTab] = useState<TabType>('pending');
  const [search, setSearch] = useState('');
  const [matchFilter, setMatchFilter] = useState<'all' | 'with' | 'without'>('all');
  const [sortBy, setSortBy] = useState<'date' | 'amount'>('date');
  const [preview, setPreview] = useState<BankTransaction[] | null>(null);
  const [previewSource, setPreviewSource] = useState<'bank' | 'credit_card'>('bank');
  const [filter, setFilter] = useState<'all' | 'credit' | 'debit'>('all');
  const [sourceFilter, setSourceFilter] = useState<'all' | 'bank' | 'credit_card'>('all');
  const [reconcileId, setReconcileId] = useState<string | null>(null);
  const [reconcileMode, setReconcileMode] = useState<ReconcileMode>('existing');
  const [searchMatch, setSearchMatch] = useState('');
  const [soSearch, setSoSearch] = useState('');
  const [dismissReason, setDismissReason] = useState('');
  const [isProcessing, setIsProcessing] = useState(false);
  const [newForm, setNewForm] = useState({
    description: '', client_id: '', supplier_id: '', expense_category: '',
    service_order_id: '', notes: '',
  });

  const allTx = transactions || [];
  const pending = allTx.filter(t => !t.reconciled);
  const reconciledTx = allTx.filter(t => t.reconciled && t.reconciled_payment_id);
  const ignoredTx = allTx.filter(t => t.reconciled && !t.reconciled_payment_id);

  const bestMatch = (txId: string): ReconcileSuggestion | undefined =>
    (suggestionsByTx.get(txId) || [])[0];

  const filtered = pending
    .filter(t => filter === 'all' || t.transaction_type === filter)
    .filter(t => sourceFilter === 'all' || t.source_type === sourceFilter)
    .filter(t => {
      if (matchFilter === 'all') return true;
      const tem = !!bestMatch(t.id) || (groupsByTx.get(t.id) || []).length > 0;
      return matchFilter === 'with' ? tem : !tem;
    })
    .filter(t => {
      if (!search.trim()) return true;
      const alvo = `${t.description} ${bestMatch(t.id)?.candidate.label ?? ''} ${bestMatch(t.id)?.candidate.clientName ?? ''}`;
      return alvo.toLowerCase().includes(search.trim().toLowerCase());
    })
    .slice()
    .sort((a, b) => sortBy === 'amount'
      ? Number(b.amount) - Number(a.amount)
      : (a.transaction_date < b.transaction_date ? 1 : -1));

  // Números do topo: o operador precisa saber o tamanho da fila e quanto dela o sistema
  // já sabe explicar, antes de abrir transação por transação.
  const resumo = {
    total: pending.length,
    valorEntradas: pending.filter(t => t.transaction_type === 'credit')
      .reduce((s, t) => s + Number(t.amount), 0),
    comSugestao: pending.filter(t => !!bestMatch(t.id)).length,
    semCandidato: pending.filter(t => !bestMatch(t.id) && (groupsByTx.get(t.id) || []).length === 0).length,
  };

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
      const { imported, skipped } = await importMutation.mutateAsync({ transactions: preview, source_type: previewSource });
      if (imported === 0 && skipped > 0) {
        toast.info(`Nada novo: as ${skipped} transações do arquivo já haviam sido importadas`);
      } else {
        toast.success(
          skipped > 0
            ? `${imported} transações importadas · ${skipped} já existiam e foram ignoradas`
            : `${imported} transações importadas`
        );
      }
      setPreview(null);
    } catch { toast.error('Erro ao importar'); }
  };

  const getSuggestions = (tx: any) => {
    const isCredit = tx.transaction_type === 'credit';
    const records = isCredit
      ? (receivables || []).filter(r => r.status !== 'paid' && r.status !== 'cancelled')
      : (payables || []).filter(p => p.status !== 'paid' && p.status !== 'cancelled');
    return records
      .filter(r => {
        if (searchMatch) {
          const desc = (r.description || '').toLowerCase();
          const name = isCredit ? ((r as any).clients?.name || '').toLowerCase() : '';
          return desc.includes(searchMatch.toLowerCase()) || name.includes(searchMatch.toLowerCase());
        }
        const amtRatio = Math.abs(Number(r.balance_amount) - tx.amount) / tx.amount;
        const daysDiff = Math.abs(new Date(r.due_date).getTime() - new Date(tx.transaction_date).getTime()) / 86400000;
        return amtRatio <= 0.05 && daysDiff <= 7;
      })
      .slice(0, 5);
  };

  const invalidateAll = () => {
    qc.invalidateQueries({ queryKey: ['bank-transactions'] });
    qc.invalidateQueries({ queryKey: ['receivables'] });
    qc.invalidateQueries({ queryKey: ['payables'] });
    qc.invalidateQueries({ queryKey: ['payments'] });
    qc.invalidateQueries({ queryKey: ['financial-summary'] });
  };

  const handleReconcileExisting = async (bankTx: any, record: any, isReceivable: boolean) => {
    try {
      await reconcile.mutateAsync({
        bankTransactionId: bankTx.id,
        receivableId: isReceivable ? record.id : undefined,
        payableId: !isReceivable ? record.id : undefined,
        amount: bankTx.amount,
      });
      toast.success(t.financial.confirmReconciliation);
      setReconcileId(null);
      invalidateAll();
    } catch { toast.error('Erro ao conciliar'); }
  };

  const getFilteredSOs = (isCredit: boolean) => {
    const sos = serviceOrders || [];
    const list = isCredit ? sos.filter(so => ['completed', 'invoiced'].includes(so.status)) : sos;
    if (soSearch) {
      const s = soSearch.toLowerCase();
      return list.filter(so =>
        so.service_order_number.toLowerCase().includes(s) ||
        (so as any).clients?.name?.toLowerCase().includes(s) ||
        (so as any).vessels?.name?.toLowerCase().includes(s)
      );
    }
    return list.slice(0, 10);
  };

  const handleReconcileSO = async (bankTx: any, so: any) => {
    setIsProcessing(true);
    try {
      const isCredit = bankTx.transaction_type === 'credit';
      if (isCredit) {
        const { data: rec } = await supabase.from('receivables').insert({
          client_id: so.client_id, service_order_id: so.id,
          description: `Pagamento ${so.service_order_number}`,
          issue_date: bankTx.transaction_date, due_date: bankTx.transaction_date,
          amount: Number(bankTx.amount), paid_amount: Number(bankTx.amount),
          balance_amount: 0, status: 'paid',
        }).select().single();
        if (rec) {
          const { data: payment } = await supabase.from('payments').insert({
            receivable_id: rec.id, payment_date: bankTx.transaction_date,
            amount: Number(bankTx.amount), payment_method: 'bank_transfer',
          }).select().single();
          await supabase.from('bank_transactions').update({
            reconciled: true, reconciled_payment_id: payment?.id,
            reconciled_service_order_id: so.id,
          }).eq('id', bankTx.id);
        }
      } else {
        const { data: pay } = await supabase.from('payables').insert({
          description: `Despesa OS ${so.service_order_number}`,
          linked_service_order_id: so.id, amount: Number(bankTx.amount),
          issue_date: bankTx.transaction_date, due_date: bankTx.transaction_date,
          paid_amount: Number(bankTx.amount), balance_amount: 0, status: 'paid',
          origin: 'bank_reconciliation',
        }).select().single();
        if (pay) {
          const { data: payment } = await supabase.from('payments').insert({
            payable_id: pay.id, payment_date: bankTx.transaction_date,
            amount: Number(bankTx.amount), payment_method: 'bank_transfer',
          }).select().single();
          await supabase.from('bank_transactions').update({
            reconciled: true, reconciled_payment_id: payment?.id,
            reconciled_service_order_id: so.id,
          }).eq('id', bankTx.id);
        }
      }
      toast.success(t.financial.confirmReconciliation);
      setReconcileId(null);
      invalidateAll();
    } catch { toast.error('Erro ao conciliar'); }
    setIsProcessing(false);
  };

  const handleReconcileNew = async (bankTx: any) => {
    if (!newForm.description) return;
    setIsProcessing(true);
    try {
      const isCredit = bankTx.transaction_type === 'credit';
      if (isCredit) {
        const clientId = newForm.client_id || (clients && clients.length > 0 ? clients[0].id : '');
        if (!clientId) { toast.error('Selecione um cliente'); setIsProcessing(false); return; }
        const { data: rec } = await supabase.from('receivables').insert({
          client_id: clientId, service_order_id: newForm.service_order_id || null,
          description: newForm.description, issue_date: bankTx.transaction_date,
          due_date: bankTx.transaction_date, amount: Number(bankTx.amount),
          paid_amount: Number(bankTx.amount), balance_amount: 0, status: 'paid',
          notes: newForm.notes || null,
        }).select().single();
        if (rec) {
          const { data: payment } = await supabase.from('payments').insert({
            receivable_id: rec.id, payment_date: bankTx.transaction_date,
            amount: Number(bankTx.amount), payment_method: 'bank_transfer',
          }).select().single();
          await supabase.from('bank_transactions').update({
            reconciled: true, reconciled_payment_id: payment?.id,
          }).eq('id', bankTx.id);
        }
      } else {
        const { data: pay } = await supabase.from('payables').insert({
          description: newForm.description, expense_category: newForm.expense_category || null,
          supplier_id: newForm.supplier_id || null,
          linked_service_order_id: newForm.service_order_id || null,
          amount: Number(bankTx.amount), issue_date: bankTx.transaction_date,
          due_date: bankTx.transaction_date, paid_amount: Number(bankTx.amount),
          balance_amount: 0, status: 'paid', notes: newForm.notes || null,
          origin: 'bank_reconciliation',
        }).select().single();
        if (pay) {
          const { data: payment } = await supabase.from('payments').insert({
            payable_id: pay.id, payment_date: bankTx.transaction_date,
            amount: Number(bankTx.amount), payment_method: 'bank_transfer',
          }).select().single();
          await supabase.from('bank_transactions').update({
            reconciled: true, reconciled_payment_id: payment?.id,
          }).eq('id', bankTx.id);
        }
      }
      toast.success(t.financial.confirmReconciliation);
      setReconcileId(null);
      setNewForm({ description: '', client_id: '', supplier_id: '', expense_category: '', service_order_id: '', notes: '' });
      invalidateAll();
    } catch { toast.error('Erro ao conciliar'); }
    setIsProcessing(false);
  };

  const handleDismiss = async (bankTx: any) => {
    try {
      await dismiss.mutateAsync(bankTx.id);
      toast.success('Transação ignorada');
      setReconcileId(null);
      invalidateAll();
    } catch { toast.error('Erro'); }
  };

  const handleAutoReconcile = async () => {
    try {
      const r = await autoReconcile.mutateAsync(false);
      const { conciliadas, sugeridas, sem_candidato } = r.summary;
      if (conciliadas === 0 && sugeridas === 0) {
        toast.info('Nenhuma correspondência encontrada para as transações pendentes');
      } else if (conciliadas === 0) {
        // Sem identificador Pix nem documento do pagador no extrato, nada atinge o grau
        // de certeza exigido para conciliar sozinho — e dizer só "0 conciliadas" faz
        // parecer que o motor não achou nada, quando ele achou e está pedindo conferência.
        toast.success(
          `${sugeridas} transações com correspondência para você conferir na lista · ${sem_candidato} sem candidato. ` +
          `Nada foi conciliado sozinho porque este extrato não traz identificador do Pix nem CPF/CNPJ do pagador.`,
        );
      } else {
        toast.success(
          `${conciliadas} conciliada(s) automaticamente · ${sugeridas} com sugestão para conferir · ${sem_candidato} sem candidato`,
        );
      }
      setMatchFilter(sugeridas > 0 ? 'with' : 'all');
      invalidateAll();
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao conciliar');
    }
  };

  const handleApplySuggestion = async (tx: any, s: ReconcileSuggestion) => {
    try {
      await applySuggestion.mutateAsync({ transactionId: tx.id, candidate: s.candidate });
      toast.success(
        s.candidate.convertsQuote
          ? `Sinal registrado — ${s.candidate.documentNumber} aprovado e convertido em OS`
          : `Conciliado com ${s.candidate.label}`,
      );
      setReconcileId(null);
      invalidateAll();
      refetchEngine();
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao aplicar sugestão');
    }
  };

  const handleApplyGroup = async (tx: any, g: ReconcileGroup) => {
    try {
      const r = await applyGroup.mutateAsync({ transactionId: tx.id, candidates: g.candidates });
      if (r.falhas?.length) {
        toast.warning(`${r.message}. Não deu certo em: ${r.falhas.join('; ')}`);
      } else {
        toast.success(r.message);
      }
      setReconcileId(null);
      invalidateAll();
      refetchEngine();
    } catch (e: any) {
      toast.error(e?.message || 'Erro ao baixar as contas');
    }
  };

  const handleAnalyzeWithAI = async (tx: any) => {
    try {
      const analise = await analyzeWithAI.mutateAsync({
        transactionId: tx.id,
        description: tx.description,
        amount: Number(tx.amount),
        date: tx.transaction_date,
      });
      setAiAnalysis(prev => ({ ...prev, [tx.id]: analise }));
    } catch (e: any) {
      toast.error(e?.message || 'Não consegui analisar agora');
    }
  };

  const handleUnignore = async (id: string) => {
    try {
      await unignore.mutateAsync(id);
      toast.success('Transação restaurada');
    } catch { toast.error('Erro'); }
  };

  const openReconcile = (txId: string, tx: any) => {
    if (reconcileId === txId) { setReconcileId(null); return; }
    setReconcileId(txId);
    setReconcileMode('existing');
    setSearchMatch('');
    setSoSearch('');
    setDismissReason('');
    setNewForm({ description: tx.description, client_id: '', supplier_id: '', expense_category: '', service_order_id: '', notes: '' });
  };

  const modeButtons: { mode: ReconcileMode; label: string }[] = [
    { mode: 'existing', label: t.financial.linkToExisting },
    { mode: 'service_order', label: t.financial.linkToServiceOrder },
    { mode: 'new', label: t.financial.createNew },
    { mode: 'dismiss', label: t.financial.ignoreTransaction },
  ];

  const sourceBadge = (st: string | null) =>
    st === 'credit_card'
      ? <StatusBadge className="bg-accent/15 text-accent">{t.financial.sourceCard}</StatusBadge>
      : <StatusBadge className="bg-muted text-muted-foreground">{t.financial.sourceBank}</StatusBadge>;

  return (
    <div className="space-y-6">
      {/* Contas conectadas: o caminho automático. A importação por arquivo continua
          logo abaixo, como alternativa e para extrato de banco sem Open Finance. */}
      <BankConnectionsPanel />

      {/* Import area — always visible */}
      <div
        className="border-2 border-dashed rounded-xl p-8 text-center cursor-pointer hover:border-primary/50 transition-colors"
        onDragOver={e => e.preventDefault()} onDrop={handleDrop}
        onClick={() => { const i = document.createElement('input'); i.type = 'file'; i.accept = '.ofx,.csv,.xls,.xlsx'; i.onchange = (e: any) => { if (e.target.files[0]) handleFile(e.target.files[0]); }; i.click(); }}
      >
        <Upload className="h-8 w-8 mx-auto mb-2 text-muted-foreground" />
        <p className="text-sm text-muted-foreground">{t.financial.dropStatementHere}</p>
      </div>

      {preview && (
        <div className="rounded-xl border bg-card p-4 space-y-3">
          {previewSource === 'credit_card' && (
            <div className="rounded-lg bg-warning/10 border border-warning/30 p-3 text-sm text-warning">
              {t.financial.cardStatementDetected}
            </div>
          )}
          <p className="font-medium">{preview.length} transações encontradas</p>
          <div className="max-h-48 overflow-x-auto scrollbar-thin">
            <table className="w-full text-sm min-w-[600px]">
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

      {/* Tab selector */}
      <div className="flex gap-1">
        {([
          { key: 'pending' as TabType, label: t.financial.pendingTab, count: pending.length },
          { key: 'reconciled' as TabType, label: t.financial.reconciledTab, count: reconciledTx.length },
          { key: 'ignored' as TabType, label: t.financial.ignoredTab, count: ignoredTx.length },
        ]).map(({ key, label, count }) => (
          <Button key={key} size="sm" variant={tab === key ? 'default' : 'outline'} onClick={() => setTab(key)}>
            {label} ({count})
          </Button>
        ))}
      </div>

      {/* === PENDING TAB === */}
      {tab === 'pending' && (
        <div>
          {/* Painel de situação: quanto está pendente, quanto disso o sistema já sabe
              explicar e quanto vai exigir análise. Sem isto, "13 sugestões" era um número
              sem lugar nenhum para olhar. */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-2 mb-3">
            {[
              { label: 'Pendentes', valor: String(resumo.total), tom: '' },
              { label: 'Entradas a identificar', valor: formatCurrency(resumo.valorEntradas), tom: 'text-success' },
              { label: 'Com correspondência', valor: String(resumo.comSugestao), tom: 'text-warning' },
              { label: 'Sem candidato', valor: String(resumo.semCandidato), tom: 'text-muted-foreground' },
            ].map(k => (
              <div key={k.label} className="rounded-lg border bg-card px-3 py-2">
                <p className="text-[11px] uppercase tracking-wide text-muted-foreground">{k.label}</p>
                <p className={`text-lg font-semibold tabular-nums ${k.tom}`}>{k.valor}</p>
              </div>
            ))}
          </div>

          {/* Saúde da rotina: quanto do extrato já está explicado, o que está encalhado e
              há quanto tempo. O contador de padrões mostra o motor melhorando com o uso —
              caso contrário esse ganho é invisível. */}
          {health && health.total > 0 && (
            <div className="rounded-lg border bg-card p-3 mb-3 flex items-center gap-4 flex-wrap text-sm">
              <div className="flex items-center gap-2 min-w-[180px] flex-1">
                <div className="h-2 flex-1 rounded-full bg-muted overflow-hidden">
                  <div
                    className={`h-full rounded-full ${health.taxa >= 80 ? 'bg-success' : health.taxa >= 40 ? 'bg-warning' : 'bg-destructive'}`}
                    style={{ width: `${health.taxa}%` }}
                  />
                </div>
                <span className="tabular-nums font-medium whitespace-nowrap">{health.taxa}% do extrato</span>
              </div>
              <span className="text-muted-foreground">
                {health.conciliadas} de {health.total} conciliadas
              </span>
              {health.diasMaisAntiga !== null && health.diasMaisAntiga > 0 && (
                <span className={health.diasMaisAntiga > 30 ? 'text-warning' : 'text-muted-foreground'}>
                  Mais antiga pendente: {health.diasMaisAntiga} dias
                </span>
              )}
              {health.padroesAprendidos > 0 && (
                <span className="text-muted-foreground">
                  {health.padroesAprendidos} {health.padroesAprendidos === 1 ? 'padrão aprendido' : 'padrões aprendidos'}
                </span>
              )}
            </div>
          )}

          <div className="rounded-lg border bg-card p-3 mb-3 space-y-2">
            <div className="flex items-center gap-2 flex-wrap">
              <Input
                placeholder="Buscar por histórico, cliente ou documento..."
                value={search}
                onChange={e => setSearch(e.target.value)}
                className="h-8 max-w-xs"
              />
              <Button size="sm" onClick={handleAutoReconcile} disabled={autoReconcile.isPending || pending.length === 0}>
                <Sparkles className="h-3.5 w-3.5 mr-1.5" />
                {autoReconcile.isPending ? 'Analisando...' : 'Analisar tudo'}
              </Button>
              <Button size="sm" variant="outline" onClick={() => refetchEngine()} disabled={engineLoading}>
                {engineLoading ? 'Atualizando...' : 'Atualizar análise'}
              </Button>
            </div>

            <div className="flex items-center gap-3 flex-wrap text-sm">
              <div className="flex items-center gap-1">
                <span className="text-xs text-muted-foreground mr-1">Tipo</span>
                {(['all', 'credit', 'debit'] as const).map(f => (
                  <Button key={f} size="sm" variant={filter === f ? 'default' : 'outline'}
                    className="h-7 px-2 text-xs" onClick={() => setFilter(f)}>
                    {f === 'all' ? t.common.all : f === 'credit' ? t.financial.inflow : t.financial.outflow}
                  </Button>
                ))}
              </div>

              <div className="flex items-center gap-1">
                <span className="text-xs text-muted-foreground mr-1">Análise</span>
                {([
                  { v: 'all' as const, l: 'Todas' },
                  { v: 'with' as const, l: 'Com correspondência' },
                  { v: 'without' as const, l: 'Sem candidato' },
                ]).map(({ v, l }) => (
                  <Button key={v} size="sm" variant={matchFilter === v ? 'default' : 'outline'}
                    className="h-7 px-2 text-xs" onClick={() => setMatchFilter(v)}>
                    {l}
                  </Button>
                ))}
              </div>

              <div className="flex items-center gap-1">
                <span className="text-xs text-muted-foreground mr-1">Origem</span>
                {([
                  { v: 'all' as const, l: t.financial.sourceAll },
                  { v: 'bank' as const, l: t.financial.sourceBank },
                  { v: 'credit_card' as const, l: t.financial.sourceCard },
                ]).map(({ v, l }) => (
                  <Button key={v} size="sm" variant={sourceFilter === v ? 'default' : 'outline'}
                    className="h-7 px-2 text-xs" onClick={() => setSourceFilter(v)}>
                    {l}
                  </Button>
                ))}
              </div>

              <div className="flex items-center gap-1">
                <span className="text-xs text-muted-foreground mr-1">Ordenar</span>
                {([
                  { v: 'date' as const, l: 'Data' },
                  { v: 'amount' as const, l: 'Valor' },
                ]).map(({ v, l }) => (
                  <Button key={v} size="sm" variant={sortBy === v ? 'default' : 'outline'}
                    className="h-7 px-2 text-xs" onClick={() => setSortBy(v)}>
                    {l}
                  </Button>
                ))}
              </div>
            </div>
          </div>

          <p className="text-sm text-muted-foreground mb-2">
            Mostrando {filtered.length} de {pending.length} transações
          </p>

          {filtered.length === 0 && <p className="text-sm text-muted-foreground py-4 text-center">{t.common.noResults}</p>}

          <div className="space-y-2">
            {filtered.map(tx => {
              const melhor = bestMatch(tx.id);
              const temGrupo = (groupsByTx.get(tx.id) || []).length > 0;
              return (
              <div
                key={tx.id}
                className={`rounded-lg border bg-card ${
                  melhor?.tier === 'certain' ? 'border-l-4 border-l-success'
                    : melhor?.tier === 'probable' ? 'border-l-4 border-l-warning' : ''
                }`}
              >
                <div className="flex items-start justify-between p-3 gap-3 flex-wrap">
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-sm text-muted-foreground tabular-nums">{formatDate(tx.transaction_date)}</span>
                      <span className="text-sm truncate max-w-[320px]">{tx.description}</span>
                      {tx.source_type === 'credit_card' && (
                        <StatusBadge className="bg-accent/15 text-accent">{t.financial.sourceCard}</StatusBadge>
                      )}
                    </div>
                    {/* A correspondência aparece aqui, na linha fechada: antes ela só existia
                        depois de abrir a transação, e o resumo "N sugestões" não levava a lugar nenhum. */}
                    {melhor ? (
                      <p className="text-xs mt-1 flex items-center gap-1.5 flex-wrap">
                        <Sparkles className="h-3 w-3 text-primary shrink-0" />
                        <span className="font-medium">{melhor.candidate.label}</span>
                        {melhor.candidate.clientName && (
                          <span className="text-muted-foreground">· {melhor.candidate.clientName}</span>
                        )}
                        <StatusBadge className={
                          melhor.tier === 'certain' ? 'bg-success/15 text-success'
                            : melhor.tier === 'probable' ? 'bg-warning/15 text-warning'
                            : 'bg-muted text-muted-foreground'
                        }>
                          {melhor.score}%
                        </StatusBadge>
                      </p>
                    ) : internalTransferTx.has(tx.id) ? (
                      <p className="text-xs mt-1 text-muted-foreground">
                        Parece transferência entre contas da empresa — não é receita nem despesa
                      </p>
                    ) : temGrupo ? (
                      <p className="text-xs mt-1 text-muted-foreground flex items-center gap-1.5">
                        <Sparkles className="h-3 w-3 shrink-0" />
                        Pode ser um pagamento agrupado
                      </p>
                    ) : !engineLoading && (
                      <p className="text-xs mt-1 text-muted-foreground">Sem correspondência encontrada</p>
                    )}
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <span className={`font-semibold tabular-nums ${tx.transaction_type === 'credit' ? 'text-success' : 'text-destructive'}`}>
                      {tx.transaction_type === 'credit' ? '+' : '-'}{formatCurrency(Number(tx.amount))}
                    </span>
                    {melhor && reconcileId !== tx.id && (
                      <Button
                        size="sm"
                        onClick={() => handleApplySuggestion(tx, melhor)}
                        disabled={applySuggestion.isPending}
                        title={melhor.reasons.map(r => r.detail).join(' · ')}
                      >
                        <Check className="h-3 w-3 mr-1" />Confirmar
                      </Button>
                    )}
                    {internalTransferTx.has(tx.id) && reconcileId !== tx.id && (
                      <Button size="sm" variant="outline" onClick={() => handleDismiss(tx)} disabled={dismiss.isPending}>
                        Marcar como transferência
                      </Button>
                    )}
                    <Button size="sm" variant="outline" onClick={() => openReconcile(tx.id, tx)}>
                      {reconcileId === tx.id ? 'Fechar' : melhor ? 'Ver opções' : t.financial.reconcile}
                    </Button>
                  </div>
                </div>

                {reconcileId === tx.id && (
                  <div className="border-t p-4 bg-muted/30 space-y-4">
                    {/* Sugestões do motor: já consideram sinal de orçamento, saldo de OS e
                        cobranças — candidatos que as opções manuais abaixo não alcançam. */}
                    {(() => {
                      const smart = suggestionsByTx.get(tx.id) || [];
                      if (engineLoading) {
                        return <p className="text-sm text-muted-foreground">Analisando correspondências...</p>;
                      }
                      if (smart.length === 0) return null;
                      return (
                        <div className="space-y-2">
                          <p className="text-sm font-medium flex items-center gap-1.5">
                            <Sparkles className="h-3.5 w-3.5 text-primary" />
                            Correspondências encontradas
                          </p>
                          {smart.map(s => (
                            <div
                              key={`${s.candidate.kind}-${s.candidate.id}`}
                              className={`rounded-lg border p-3 space-y-2 ${
                                s.tier === 'certain' ? 'border-success bg-success/5'
                                  : s.tier === 'probable' ? 'border-warning bg-warning/5' : ''
                              }`}
                            >
                              <div className="flex items-start justify-between gap-3 flex-wrap">
                                <div className="min-w-0">
                                  <div className="flex items-center gap-2 flex-wrap">
                                    <span className="font-medium">{s.candidate.label}</span>
                                    <StatusBadge className="bg-muted text-muted-foreground">
                                      {CANDIDATE_LABELS[s.candidate.kind]}
                                    </StatusBadge>
                                    <StatusBadge className={
                                      s.tier === 'certain' ? 'bg-success/15 text-success'
                                        : s.tier === 'probable' ? 'bg-warning/15 text-warning'
                                        : 'bg-muted text-muted-foreground'
                                    }>
                                      {s.score}% de confiança
                                    </StatusBadge>
                                  </div>
                                  {s.candidate.clientName && (
                                    <p className="text-sm text-muted-foreground">{s.candidate.clientName}</p>
                                  )}
                                  {/* De onde veio o valor esperado: o combinado no orçamento
                                      ou uma estimativa. Sem isso, uma estimativa de 30% parece
                                      tão firme quanto uma condição acordada com o cliente. */}
                                  {s.candidate.amountSource === 'condicao' && (
                                    <p className="text-xs text-muted-foreground">
                                      Conforme a condição do orçamento
                                      {s.candidate.conditionLabel ? `: ${s.candidate.conditionLabel}` : ''}
                                    </p>
                                  )}
                                  {s.candidate.amountSource === 'padrao' && (
                                    <p className="text-xs text-muted-foreground">
                                      Pela condição padrão (100% materiais + 50% mão de obra) — este
                                      orçamento não tem condição própria definida
                                    </p>
                                  )}
                                  {s.candidate.amountSource === 'percentual' && (
                                    <p className="text-xs text-warning">
                                      Valor estimado — não foi possível separar mão de obra e materiais
                                    </p>
                                  )}
                                  <p className="text-xs text-muted-foreground mt-1">
                                    {s.reasons.map(r => r.detail).join(' · ')}
                                  </p>
                                </div>
                                <div className="flex items-center gap-2">
                                  <span className="font-medium">{formatCurrency(s.candidate.amount)}</span>
                                  <Button
                                    size="sm"
                                    onClick={() => handleApplySuggestion(tx, s)}
                                    disabled={applySuggestion.isPending}
                                  >
                                    <Check className="h-3 w-3 mr-1" />{t.financial.confirmReconciliation}
                                  </Button>
                                </div>
                              </div>

                              {/* Diz o que a confirmação vai fazer com a diferença, não só
                                  que ela existe: recebeu menos deixa saldo em aberto,
                                  recebeu mais costuma ser juros ou multa. */}
                              {Math.abs(s.difference) >= 0.01 && (
                                <p className="text-xs flex items-start gap-1.5 text-warning">
                                  <AlertTriangle className="h-3 w-3 shrink-0 mt-0.5" />
                                  <span>
                                    {s.difference > 0
                                      ? `Entrou ${formatCurrency(Math.abs(s.difference))} a mais que o esperado — costuma ser juros ou multa por atraso. A baixa será pelo valor recebido.`
                                      : `Entrou ${formatCurrency(Math.abs(s.difference))} a menos que o esperado — pode ser tarifa do banco ou pagamento parcial. Confirmar dá baixa parcial e mantém ${formatCurrency(Math.abs(s.difference))} em aberto.`}
                                  </span>
                                </p>
                              )}

                              {s.candidate.kind === 'existing_payment' && (
                                <p className="text-xs text-muted-foreground">
                                  Este recebimento já está lançado no financeiro. Confirmar apenas
                                  liga esta linha do extrato a ele — nenhum valor novo é registrado.
                                </p>
                              )}

                              {s.candidate.convertsQuote && (
                                <p className="text-xs flex items-center gap-1.5 text-muted-foreground">
                                  <AlertTriangle className="h-3 w-3 shrink-0" />
                                  Confirmar vai aprovar o {s.candidate.documentNumber} e convertê-lo em OS.
                                </p>
                              )}
                            </div>
                          ))}
                        </div>
                      );
                    })()}

                    {/* Quando o cálculo não alcança, o agente entra: ele lê conversas,
                        histórico e orçamentos em negociação. Só opina — não concilia. */}
                    <div className="space-y-2">
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => handleAnalyzeWithAI(tx)}
                        disabled={analyzeWithAI.isPending}
                      >
                        <Sparkles className="h-3.5 w-3.5 mr-1.5" />
                        {analyzeWithAI.isPending ? 'Analisando...' : 'Analisar com IA'}
                      </Button>
                      {aiAnalysis[tx.id] && (
                        <div className="rounded-lg border bg-card p-3 text-sm whitespace-pre-wrap">
                          {aiAnalysis[tx.id]}
                        </div>
                      )}
                    </div>

                    {/* Pagamento agrupado: o cliente quitou várias contas num depósito só.
                        Aparece apenas quando nenhuma conta sozinha explica o valor. */}
                    {(groupsByTx.get(tx.id) || []).length > 0 && (
                      <div className="space-y-2">
                        <p className="text-sm font-medium">Pode ser um pagamento agrupado</p>
                        {(groupsByTx.get(tx.id) || []).map((g, i) => (
                          <div key={i} className="rounded-lg border p-3 text-sm space-y-1">
                            <div className="flex items-center justify-between gap-3 flex-wrap">
                              <span className="font-medium">
                                {g.candidates.length} contas de {g.clientName || 'um mesmo cliente'}
                              </span>
                              <span className="font-medium">{formatCurrency(g.total)}</span>
                            </div>
                            <ul className="text-xs text-muted-foreground space-y-0.5">
                              {g.candidates.map(c => (
                                <li key={`${c.kind}-${c.id}`}>• {c.label} — {formatCurrency(c.amount)}</li>
                              ))}
                            </ul>
                            <div className="flex items-center justify-between gap-2 flex-wrap pt-1">
                              <span className="text-xs text-muted-foreground">
                                Cada conta é baixada pelo próprio valor.
                              </span>
                              <Button
                                size="sm"
                                onClick={() => handleApplyGroup(tx, g)}
                                disabled={applyGroup.isPending}
                              >
                                <Check className="h-3 w-3 mr-1" />
                                Baixar as {g.candidates.length} contas
                              </Button>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}

                    <div className="flex flex-wrap gap-1.5">
                      {modeButtons.map(({ mode, label }) => (
                        <Button key={mode} size="sm" variant={reconcileMode === mode ? 'default' : 'outline'} onClick={() => setReconcileMode(mode)}>
                          {label}
                        </Button>
                      ))}
                    </div>

                    {/* OPTION A: Link to existing */}
                    {reconcileMode === 'existing' && (
                      <div className="space-y-3">
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
                                  {isRec && (r as any).clients && <span className="text-muted-foreground ml-2">— {(r as any).clients.name}</span>}
                                  {isAutoMatch && <StatusBadge className="bg-warning/15 text-warning ml-2">{t.financial.autoSuggestion}</StatusBadge>}
                                </div>
                                <div className="flex items-center gap-2">
                                  <span className="font-medium">{formatCurrency(Number(r.balance_amount))}</span>
                                  <Button size="sm" onClick={() => handleReconcileExisting(tx, r, isRec)} disabled={reconcile.isPending}>
                                    <Check className="h-3 w-3 mr-1" />{t.financial.confirmReconciliation}
                                  </Button>
                                </div>
                              </div>
                            );
                          })}
                          {getSuggestions(tx).length === 0 && <p className="text-sm text-muted-foreground">{t.common.noResults}</p>}
                        </div>
                      </div>
                    )}

                    {/* OPTION B: Link to SO */}
                    {reconcileMode === 'service_order' && (
                      <div className="space-y-3">
                        <p className="text-sm font-medium">{t.financial.linkToServiceOrder}</p>
                        <Input placeholder="Buscar OS..." value={soSearch} onChange={e => setSoSearch(e.target.value)} className="max-w-xs" />
                        <div className="space-y-1 max-h-48 overflow-y-auto">
                          {getFilteredSOs(tx.transaction_type === 'credit').map((so: any) => (
                            <div key={so.id} className="flex items-center justify-between p-2 rounded border text-sm hover:bg-muted/50">
                              <div>
                                <span className="font-bold">{so.service_order_number}</span>
                                <span className="text-muted-foreground ml-2">{(so as any).clients?.name}</span>
                                <span className="text-muted-foreground ml-2">— {(so as any).vessels?.name}</span>
                              </div>
                              <div className="flex items-center gap-2">
                                <span className="font-medium">{formatCurrency(Number(so.grand_total || 0))}</span>
                                <Button size="sm" onClick={() => handleReconcileSO(tx, so)} disabled={isProcessing}>
                                  <Check className="h-3 w-3 mr-1" />{t.financial.confirmReconciliation}
                                </Button>
                              </div>
                            </div>
                          ))}
                          {getFilteredSOs(tx.transaction_type === 'credit').length === 0 && (
                            <p className="text-sm text-muted-foreground">{t.common.noResults}</p>
                          )}
                        </div>
                      </div>
                    )}

                    {/* OPTION C: Create new */}
                    {reconcileMode === 'new' && (
                      <div className="space-y-3">
                        <p className="text-sm font-medium">{t.financial.createNew}</p>
                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                          <div>
                            <Label>{t.common.description}</Label>
                            <Input value={newForm.description} onChange={e => setNewForm({ ...newForm, description: e.target.value })} />
                          </div>
                          {tx.transaction_type === 'credit' ? (
                            <div>
                              <Label>{t.serviceOrders.client}</Label>
                              <Select value={newForm.client_id} onValueChange={v => setNewForm({ ...newForm, client_id: v })}>
                                <SelectTrigger><SelectValue placeholder="Selecionar cliente" /></SelectTrigger>
                                <SelectContent>
                                  {clients?.map(c => (
                                    <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>
                                  ))}
                                </SelectContent>
                              </Select>
                            </div>
                          ) : (
                            <div>
                              <Label>{t.financial.expenseCategory}</Label>
                              <Select value={newForm.expense_category} onValueChange={v => setNewForm({ ...newForm, expense_category: v })}>
                                <SelectTrigger><SelectValue placeholder={t.financial.expenseCategory} /></SelectTrigger>
                                <SelectContent>
                                  {OPERATIONAL_EXPENSE_CATEGORIES.map(c => (
                                    <SelectItem key={c} value={c}>{c}</SelectItem>
                                  ))}
                                </SelectContent>
                              </Select>
                            </div>
                          )}
                        </div>
                        {tx.transaction_type === 'debit' && (
                          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                            <div>
                              <Label>{t.financial.supplierOptional}</Label>
                              <Select value={newForm.supplier_id} onValueChange={v => setNewForm({ ...newForm, supplier_id: v })}>
                                <SelectTrigger><SelectValue placeholder={t.financial.supplierOptional} /></SelectTrigger>
                                <SelectContent>
                                  {suppliers?.map(s => (
                                    <SelectItem key={s.id} value={s.id}>{s.name}</SelectItem>
                                  ))}
                                </SelectContent>
                              </Select>
                            </div>
                            <div>
                              <Label>{t.financial.linkedOrder}</Label>
                              <Select value={newForm.service_order_id} onValueChange={v => setNewForm({ ...newForm, service_order_id: v })}>
                                <SelectTrigger><SelectValue placeholder="OS (opcional)" /></SelectTrigger>
                                <SelectContent>
                                  {serviceOrders?.slice(0, 20).map((so: any) => (
                                    <SelectItem key={so.id} value={so.id}>{so.service_order_number}</SelectItem>
                                  ))}
                                </SelectContent>
                              </Select>
                            </div>
                          </div>
                        )}
                        <div>
                          <Label>{t.common.notes}</Label>
                          <Input value={newForm.notes} onChange={e => setNewForm({ ...newForm, notes: e.target.value })} />
                        </div>
                        <Button size="sm" onClick={() => handleReconcileNew(tx)} disabled={isProcessing || !newForm.description}>
                          <Check className="h-3 w-3 mr-1" />{t.financial.confirmReconciliation}
                        </Button>
                      </div>
                    )}

                    {/* OPTION D: Dismiss */}
                    {reconcileMode === 'dismiss' && (
                      <div className="space-y-3">
                        <p className="text-sm font-medium">{t.financial.ignoreTransaction}</p>
                        <div className="max-w-xs">
                          <Label>{t.financial.dismissReason}</Label>
                          <Select value={dismissReason} onValueChange={setDismissReason}>
                            <SelectTrigger><SelectValue placeholder={t.financial.dismissReason} /></SelectTrigger>
                            <SelectContent>
                              <SelectItem value="internal_transfer">Transferência interna</SelectItem>
                              <SelectItem value="personal">Uso pessoal</SelectItem>
                              <SelectItem value="duplicate">Duplicata</SelectItem>
                              <SelectItem value="reversal">Estorno</SelectItem>
                              <SelectItem value="other">Outro</SelectItem>
                            </SelectContent>
                          </Select>
                        </div>
                        <Button size="sm" variant="destructive" onClick={() => handleDismiss(tx)} disabled={dismiss.isPending}>
                          <X className="h-3 w-3 mr-1" />{t.financial.ignore}
                        </Button>
                      </div>
                    )}
                  </div>
                )}
              </div>
              );
            })}
          </div>
        </div>
      )}

      {/* === RECONCILED TAB === */}
      {tab === 'reconciled' && (
        <div>
          <h3 className="font-semibold mb-3">{t.financial.reconciledTab} ({reconciledTx.length})</h3>
          {reconciledTx.length === 0 ? (
            <p className="text-sm text-muted-foreground py-4 text-center">{t.common.noResults}</p>
          ) : (
            <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
              <table className="w-full text-sm min-w-[800px]">
                <thead><tr className="border-b bg-muted/50">
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.date}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.description}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">Fonte</th>
                  <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.amount}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.financial.reconciledLinkedTo}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden lg:table-cell">{t.financial.importBatch}</th>
                </tr></thead>
                <tbody>
                  {reconciledTx.map(tx => (
                    <tr key={tx.id} className="border-b last:border-0 hover:bg-muted/30">
                      <td className="px-4 py-3 text-muted-foreground">{formatDate(tx.transaction_date)}</td>
                      <td className="px-4 py-3">{tx.description}</td>
                      <td className="px-4 py-3 hidden md:table-cell">{sourceBadge(tx.source_type)}</td>
                      <td className={`px-4 py-3 text-right font-medium ${tx.transaction_type === 'credit' ? 'text-success' : 'text-destructive'}`}>
                        {tx.transaction_type === 'credit' ? '+' : '-'}{formatCurrency(Number(tx.amount))}
                      </td>
                      <td className="px-4 py-3 hidden lg:table-cell">
                        {(tx as any).service_orders?.service_order_number
                          ? <span className="font-medium">OS: {(tx as any).service_orders.service_order_number}</span>
                          : <span className="text-muted-foreground">Lançamento financeiro</span>}
                      </td>
                      <td className="px-4 py-3 hidden lg:table-cell font-mono text-xs text-muted-foreground">
                        {tx.import_batch_id ? `#${tx.import_batch_id.slice(0, 8)}` : '—'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* === IGNORED TAB === */}
      {tab === 'ignored' && (
        <div>
          <h3 className="font-semibold mb-3">{t.financial.ignoredTab} ({ignoredTx.length})</h3>
          {ignoredTx.length === 0 ? (
            <p className="text-sm text-muted-foreground py-4 text-center">{t.common.noResults}</p>
          ) : (
            <div className="rounded-xl border bg-card shadow-sm overflow-x-auto scrollbar-thin">
              <table className="w-full text-sm min-w-[800px]">
                <thead><tr className="border-b bg-muted/50">
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.date}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">{t.common.description}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground hidden md:table-cell">Fonte</th>
                  <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.amount}</th>
                  <th className="px-4 py-3 text-left font-medium text-muted-foreground">Motivo</th>
                  <th className="px-4 py-3 text-right font-medium text-muted-foreground">{t.common.actions}</th>
                </tr></thead>
                <tbody>
                  {ignoredTx.map(tx => (
                    <tr key={tx.id} className="border-b last:border-0 hover:bg-muted/30">
                      <td className="px-4 py-3 text-muted-foreground">{formatDate(tx.transaction_date)}</td>
                      <td className="px-4 py-3">{tx.description}</td>
                      <td className="px-4 py-3 hidden md:table-cell">{sourceBadge(tx.source_type)}</td>
                      <td className={`px-4 py-3 text-right font-medium ${tx.transaction_type === 'credit' ? 'text-success' : 'text-destructive'}`}>
                        {tx.transaction_type === 'credit' ? '+' : '-'}{formatCurrency(Number(tx.amount))}
                      </td>
                      <td className="px-4 py-3 text-muted-foreground">Ignorado manualmente</td>
                      <td className="px-4 py-3 text-right">
                        <Button size="sm" variant="outline" onClick={() => handleUnignore(tx.id)} disabled={unignore.isPending}>
                          <Undo2 className="h-3 w-3 mr-1" />{t.financial.undoIgnore}
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
