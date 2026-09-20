// Aba "PaymentConditionsTab + PaymentPresetRow" de Configurações. Extraída de SettingsPage.tsx em 20/09/2026 (o arquivo
// tinha 1.981 linhas); comportamento idêntico, só mudou de endereço.
import { useState } from 'react';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useAllPaymentConditionPresets, useCreatePaymentConditionPreset, useUpdatePaymentConditionPreset } from '@/hooks/use-payment-conditions';
import { Switch } from '@/components/ui/switch';
import { toast } from 'sonner';

interface InstallmentRow {
  label: string;
  services_pct: number;
  parts_pct: number;
  expenses_pct: number;
  days_after_approval: number;
  tipo: 'aprovacao' | 'entrega' | 'prazo';
}

export function PaymentConditionsTab() {
  const { data: presets, isLoading } = useAllPaymentConditionPresets();
  const createPreset = useCreatePaymentConditionPreset();
  const updatePreset = useUpdatePaymentConditionPreset();
  const [newLabel, setNewLabel] = useState('');
  const [showNew, setShowNew] = useState(false);

  const handleCreate = async () => {
    if (!newLabel.trim()) return;
    try {
      await createPreset.mutateAsync(newLabel.trim());
      setNewLabel('');
      setShowNew(false);
      toast.success('Condição criada');
    } catch (e: any) {
      toast.error(e.message);
    }
  };

  if (isLoading) {
    return <div className="rounded-xl border bg-card p-6 shadow-sm text-sm text-muted-foreground">Carregando...</div>;
  }

  return (
    <div className="rounded-xl border bg-card p-6 shadow-sm max-w-3xl space-y-4">
      <div>
        <h3 className="text-sm font-semibold mb-1">Condições de Pagamento</h3>
        <p className="text-xs text-muted-foreground">
          Cadastre condições de pagamento pré-definidas que aparecerão como opções rápidas nas Ordens de Serviço e nos PDFs.
        </p>
      </div>

      <div className="space-y-3">
        {(presets || []).map((p: any) => (
          <PaymentPresetRow key={p.id} preset={p} updatePreset={updatePreset} />
        ))}
        {(presets || []).length === 0 && (
          <div className="rounded-lg border px-3 py-6 text-center text-sm text-muted-foreground">
            Nenhuma condição cadastrada
          </div>
        )}
      </div>

      {showNew ? (
        <div className="space-y-2 rounded-lg border p-3 bg-muted/20">
          <label className="text-xs font-medium text-muted-foreground">Nova Condição</label>
          <Input
            value={newLabel}
            onChange={(e) => setNewLabel(e.target.value)}
            placeholder="Ex: 50% de sinal + 50% na entrega"
            autoFocus
            onKeyDown={(e) => e.key === 'Enter' && handleCreate()}
          />
          <div className="flex gap-2">
            <Button size="sm" onClick={handleCreate} disabled={createPreset.isPending}>
              Salvar
            </Button>
            <Button size="sm" variant="ghost" onClick={() => { setShowNew(false); setNewLabel(''); }}>
              Cancelar
            </Button>
          </div>
        </div>
      ) : (
        <Button variant="outline" size="sm" onClick={() => setShowNew(true)}>
          + Nova Condição
        </Button>
      )}
    </div>
  );
}

export function PaymentPresetRow({ preset, updatePreset }: { preset: any; updatePreset: ReturnType<typeof useUpdatePaymentConditionPreset> }) {
  const [open, setOpen] = useState(false);
  const initial: InstallmentRow[] = Array.isArray(preset.installments) && preset.installments.length > 0
    ? (preset.installments as any[]).map((r: any) => ({
        label: r.label || '',
        services_pct: r.services_pct ?? r.percent ?? 0,
        parts_pct: r.parts_pct ?? r.percent ?? 0,
        expenses_pct: r.expenses_pct ?? 0,
        days_after_approval: r.days_after_approval ?? 0,
        tipo: r.tipo || (r.days_after_approval > 0 ? 'prazo' : 'aprovacao'),
      }))
    : [];
  const [rows, setRows] = useState<InstallmentRow[]>(initial);
  const [autoGenerate, setAutoGenerate] = useState<boolean>(preset.auto_generate_collections !== false);

  const isValid = rows.length > 0;
  const dirty =
    JSON.stringify(rows) !== JSON.stringify(initial) ||
    autoGenerate !== (preset.auto_generate_collections !== false);

  const addRow = () => setRows((r) => [...r, { label: '', services_pct: 0, parts_pct: 0, expenses_pct: 0, days_after_approval: 0, tipo: 'aprovacao' }]);
  const removeRow = (i: number) => setRows((r) => r.filter((_, idx) => idx !== i));
  const updateRow = (i: number, patch: Partial<InstallmentRow>) =>
    setRows((r) => r.map((row, idx) => (idx === i ? { ...row, ...patch } : row)));

  const handleSave = async () => {
    if (!isValid) return;
    await updatePreset.mutateAsync({
      id: preset.id,
      patch: { installments: rows as any, auto_generate_collections: autoGenerate },
    });
  };

  return (
    <div className="rounded-lg border bg-background">
      <div className="grid grid-cols-[1fr_auto_auto] gap-3 px-3 py-2 items-center">
        <div className={`text-sm font-medium ${preset.active ? '' : 'text-muted-foreground line-through'}`}>
          {preset.label}
          {rows.length > 0 && (
            <span className="ml-2 text-xs text-muted-foreground">
              ({rows.length} parcela{rows.length > 1 ? 's' : ''})
            </span>
          )}
        </div>
        <Button variant="ghost" size="sm" onClick={() => setOpen((v) => !v)} className="h-7 px-2 text-xs">
          {open ? 'Fechar' : 'Configurar Parcelas'}
        </Button>
        <Switch
          checked={preset.active}
          onCheckedChange={(v) => updatePreset.mutate({ id: preset.id, patch: { active: v } })}
        />
      </div>

      {open && (
        <div className="border-t px-3 py-3 space-y-3 bg-muted/20">
          <div className="flex items-center justify-between">
            <label className="text-xs font-medium">Gerar cobranças automaticamente</label>
            <Switch checked={autoGenerate} onCheckedChange={setAutoGenerate} />
          </div>

          <div className="space-y-2">
            <div className="sm:hidden text-[11px] text-muted-foreground px-1 mb-1">
              Preencha os campos de cada parcela abaixo
            </div>
            <div className="hidden sm:grid grid-cols-[1fr_130px_70px_70px_70px_90px_36px] gap-2 text-[11px] uppercase tracking-wide text-muted-foreground px-1">
              <div>Descrição</div>
              <div className="text-center">Tipo</div>
              <div className="text-center">% Serv.</div>
              <div className="text-center">% Peças</div>
              <div className="text-center">% Desp.</div>
              <div className="text-center">Dias</div>
              <div></div>
            </div>
            {rows.map((row, i) => (
              <div key={i} className="grid grid-cols-1 sm:grid-cols-[1fr_130px_70px_70px_70px_90px_36px] gap-2 items-start sm:items-center border sm:border-0 rounded p-2 sm:p-0">
                <div>
                  <label className="text-[10px] text-muted-foreground sm:hidden">Descrição</label>
                  <Input
                    value={row.label}
                    onChange={(e) => updateRow(i, { label: e.target.value })}
                    placeholder="Ex: Sinal"
                    className="h-8 text-sm"
                  />
                </div>
                <div>
                  <label className="text-[10px] text-muted-foreground sm:hidden">Tipo</label>
                  <Select
                    value={row.tipo || 'aprovacao'}
                    onValueChange={(v) => updateRow(i, { tipo: v as any, days_after_approval: v === 'prazo' ? (row.days_after_approval || 30) : 0 })}
                  >
                    <SelectTrigger className="h-8 text-xs">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="aprovacao">Na aprovação</SelectItem>
                      <SelectItem value="entrega">Na entrega</SelectItem>
                      <SelectItem value="prazo">Em X dias</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <label className="text-[10px] text-muted-foreground sm:hidden">% Serv.</label>
                  <Input
                    type="number"
                    step="0.01"
                    min={0}
                    max={100}
                    value={row.services_pct}
                    onChange={(e) => updateRow(i, { services_pct: parseFloat(e.target.value) || 0 })}
                    className="h-8 text-sm text-center"
                  />
                </div>
                <div>
                  <label className="text-[10px] text-muted-foreground sm:hidden">% Peças</label>
                  <Input
                    type="number"
                    step="0.01"
                    min={0}
                    max={100}
                    value={row.parts_pct}
                    onChange={(e) => updateRow(i, { parts_pct: parseFloat(e.target.value) || 0 })}
                    className="h-8 text-sm text-center"
                  />
                </div>
                <div>
                  <label className="text-[10px] text-muted-foreground sm:hidden">% Desp.</label>
                  <Input
                    type="number"
                    step="0.01"
                    min={0}
                    max={100}
                    value={row.expenses_pct}
                    onChange={(e) => updateRow(i, { expenses_pct: parseFloat(e.target.value) || 0 })}
                    className="h-8 text-sm text-center"
                  />
                </div>
                <div>
                  <label className="text-[10px] text-muted-foreground sm:hidden">Dias</label>
                  <Input
                    type="number"
                    min={0}
                    value={row.days_after_approval}
                    onChange={(e) => updateRow(i, { days_after_approval: parseInt(e.target.value, 10) || 0 })}
                    className="h-8 text-sm text-center"
                    disabled={row.tipo !== 'prazo'}
                    placeholder={row.tipo === 'prazo' ? '30' : '—'}
                  />
                </div>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-8 w-8 text-destructive justify-self-end sm:justify-self-auto"
                  onClick={() => removeRow(i)}
                >
                  ×
                </Button>
              </div>
            ))}
            {rows.length === 0 && (
              <div className="text-xs text-muted-foreground text-center py-3">
                Nenhuma parcela configurada — fallback será cobrança única do valor total.
              </div>
            )}
            {(() => {
              const overS = rows.reduce((s, r) => s + r.services_pct, 0) > 100;
              const overP = rows.reduce((s, r) => s + r.parts_pct, 0) > 100;
              const overE = rows.reduce((s, r) => s + r.expenses_pct, 0) > 100;
              const cols = [overS && 'Serviços', overP && 'Peças', overE && 'Despesas'].filter(Boolean).join(', ');
              return cols ? (
                <div className="text-xs text-destructive px-1">
                  Atenção: soma de % em {cols} ultrapassa 100%.
                </div>
              ) : null;
            })()}
          </div>

          <div className="flex items-center justify-between pt-2 border-t border-dashed">
            <Button variant="outline" size="sm" onClick={addRow} className="h-7 text-xs">
              + Adicionar Parcela
            </Button>
          </div>

          <div className="flex justify-end gap-2 pt-2">
            <Button
              size="sm"
              onClick={handleSave}
              disabled={!isValid || !dirty || updatePreset.isPending}
            >
              Salvar Parcelas
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}


/** Tipos de documento que têm o que configurar. Recibo fica de fora: não tem toggle nenhum. */