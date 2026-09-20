// Aba "FinanceReviewSettingsSection" de Configurações. Extraída de SettingsPage.tsx em 20/09/2026 (o arquivo
// tinha 1.981 linhas); comportamento idêntico, só mudou de endereço.
import { useState } from 'react';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { DollarSign, Loader2 } from 'lucide-react';
import { useAppSettings, useUpdateAppSettings } from '@/hooks/use-app-settings';

export function FinanceReviewSettingsSection() {
  // Limite de aprovação em lote da caixa de entrada financeira (decisão do dono em 14/09/2026:
  // acima disso a proposta só é aprovada uma a uma). Mora em app_settings porque o edge
  // finance-review também o lê — tela e servidor não podem discordar. Antes de 15/09 a chave
  // existia e nada a expunha; mudar exigia SQL.
  const { data: appSettings, isLoading } = useAppSettings();
  const updateSettings = useUpdateAppSettings();
  const [limite, setLimite] = useState<number | null>(null);
  const valor = limite ?? (Number(appSettings?.finance_review_batch_limit) || 500);

  const salvar = async () => {
    try {
      await updateSettings.mutateAsync({ finance_review_batch_limit: String(valor) });
      setLimite(null);
    } catch {
      /* erro já exibido pelo hook */
    }
  };

  if (isLoading) return null;

  return (
    <div className="rounded-xl border bg-card p-6 space-y-4">
      <h3 className="text-sm font-semibold flex items-center gap-2">
        <DollarSign className="h-4 w-4" /> Caixa de entrada financeira
      </h3>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div className="space-y-1.5">
          <Label>Limite para aprovar em lote (R$)</Label>
          <Input type="number" min="0" step="50" value={valor}
            onChange={e => setLimite(Math.max(0, Math.round(Number(e.target.value) || 0)))} />
          <p className="text-xs text-muted-foreground">
            Propostas de lançamento até este valor podem ser aprovadas em grupo ou em seleção. Acima dele, só uma a uma — o servidor também recusa.
          </p>
        </div>
      </div>
      <div className="flex justify-end">
        <Button onClick={salvar} disabled={updateSettings.isPending || limite === null} size="sm">
          {updateSettings.isPending && <Loader2 className="h-4 w-4 animate-spin mr-2" />}
          Salvar limite
        </Button>
      </div>
    </div>
  );
}
