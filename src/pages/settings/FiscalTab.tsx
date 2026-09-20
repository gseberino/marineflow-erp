// Aba "FiscalTab" de Configurações. Extraída de SettingsPage.tsx em 20/09/2026 (o arquivo
// tinha 1.981 linhas); comportamento idêntico, só mudou de endereço.
import { useState, useEffect } from 'react';
import { useI18n } from '@/i18n';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Receipt } from 'lucide-react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { CSOSN_OPTIONS, FISCAL_ORIGIN_OPTIONS } from '@/lib/price-calculator';

export function FiscalTab() {
  const { t } = useI18n();
  const st = t.settings as any;
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [fiscal, setFiscal] = useState<Record<string, any>>({
    simples_aliquota: 6,
    default_profit_margin: 30,
    default_commission_rate: 0,
    default_csosn: '400',
    default_fiscal_origin: 0,
    default_icms_rate: 0,
    default_ipi_rate: 0,
    default_pis_rate: 0,
    default_cofins_rate: 0,
  });

  useEffect(() => {
    (async () => {
      const { data } = await supabase.from('app_settings').select('key, value');
      if (data) {
        const map: Record<string, string> = {};
        for (const row of data) {
          if (row.key) map[row.key] = String(row.value || '');
        }
        setFiscal({
          simples_aliquota: Number(map.simples_aliquota) || 6,
          default_profit_margin: Number(map.default_profit_margin) || 30,
          default_commission_rate: Number(map.default_commission_rate) || 0,
          default_csosn: map.default_csosn || '400',
          default_fiscal_origin: Number(map.default_fiscal_origin) || 0,
          default_icms_rate: Number(map.default_icms_rate) || 0,
          default_ipi_rate: Number(map.default_ipi_rate) || 0,
          default_pis_rate: Number(map.default_pis_rate) || 0,
          default_cofins_rate: Number(map.default_cofins_rate) || 0,
        });
      }
      setLoading(false);
    })();
  }, []);

  const handleSave = async () => {
    setSaving(true);
    try {
      const entries = [
        ['simples_aliquota', String(fiscal.simples_aliquota)],
        ['default_profit_margin', String(fiscal.default_profit_margin)],
        ['default_commission_rate', String(fiscal.default_commission_rate)],
        ['default_csosn', String(fiscal.default_csosn)],
        ['default_fiscal_origin', String(fiscal.default_fiscal_origin)],
        ['default_icms_rate', String(fiscal.default_icms_rate)],
        ['default_ipi_rate', String(fiscal.default_ipi_rate)],
        ['default_pis_rate', String(fiscal.default_pis_rate)],
        ['default_cofins_rate', String(fiscal.default_cofins_rate)],
      ];
      for (const [key, value] of entries) {
        await supabase
          .from('app_settings')
          .upsert({ key, value }, { onConflict: 'key' });
      }
      toast.success('Configurações fiscais salvas com sucesso');
    } catch (e: any) {
      toast.error(e.message || 'Erro');
    } finally {
      setSaving(false);
    }
  };

  if (loading) return <p className="text-sm text-muted-foreground">{t.common.loading}</p>;

  return (
    <div className="space-y-6 max-w-2xl">
      {/* Simples Nacional */}
      <div className="rounded-xl border bg-card p-6 shadow-sm">
        <h3 className="text-sm font-semibold mb-3 flex items-center gap-2">
          <Receipt className="h-4 w-4" /> Simples Nacional
        </h3>
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800 mb-4">
          {st.simplesInfo || 'No Simples Nacional, PIS e COFINS já estão incluídos no DAS. Use a alíquota total do Simples no campo abaixo. Consulte seu contador para confirmar sua alíquota exata.'}
        </div>
        <div>
          <label className="text-xs font-medium text-muted-foreground">{st.simplesAliquota || 'Alíquota do Simples (%)'}</label>
          <Input type="number" step="0.01" className="mt-1 max-w-xs" value={fiscal.simples_aliquota}
            onChange={e => setFiscal(p => ({ ...p, simples_aliquota: parseFloat(e.target.value) || 0 }))} />
          <p className="text-xs text-muted-foreground mt-1">Sua alíquota atual no DAS (ex: 6.00)</p>
        </div>
      </div>

      {/* Pricing Defaults */}
      <div className="rounded-xl border bg-card p-6 shadow-sm space-y-4">
        <h3 className="text-sm font-semibold">Padrões de Precificação</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="text-xs font-medium text-muted-foreground">{st.defaultMargin || 'Margem de lucro padrão (%)'}</label>
            <Input type="number" step="0.01" className="mt-1" value={fiscal.default_profit_margin}
              onChange={e => setFiscal(p => ({ ...p, default_profit_margin: parseFloat(e.target.value) || 0 }))} />
            <p className="text-xs text-muted-foreground mt-1">Ponto de partida no formador de preço</p>
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">{st.defaultCommission || 'Comissão padrão (%)'}</label>
            <Input type="number" step="0.01" className="mt-1" value={fiscal.default_commission_rate}
              onChange={e => setFiscal(p => ({ ...p, default_commission_rate: parseFloat(e.target.value) || 0 }))} />
            <p className="text-xs text-muted-foreground mt-1">Comissão usada como padrão no formador de preço</p>
          </div>
        </div>
      </div>

      {/* Fiscal Product Defaults */}
      <div className="rounded-xl border bg-card p-6 shadow-sm space-y-4">
        <h3 className="text-sm font-semibold">{st.fiscalDefaults || 'Padrões Fiscais dos Produtos'}</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="text-xs font-medium text-muted-foreground">CSOSN padrão</label>
            <Select value={fiscal.default_csosn} onValueChange={v => setFiscal(p => ({ ...p, default_csosn: v }))}>
              <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
              <SelectContent>
                {CSOSN_OPTIONS.map(o => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Origem padrão</label>
            <Select value={String(fiscal.default_fiscal_origin)} onValueChange={v => setFiscal(p => ({ ...p, default_fiscal_origin: Number(v) }))}>
              <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
              <SelectContent>
                {FISCAL_ORIGIN_OPTIONS.map(o => <SelectItem key={o.value} value={String(o.value)}>{o.label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
        </div>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div>
            <label className="text-xs font-medium text-muted-foreground">ICMS %</label>
            <Input type="number" step="0.01" className="mt-1" value={fiscal.default_icms_rate}
              onChange={e => setFiscal(p => ({ ...p, default_icms_rate: parseFloat(e.target.value) || 0 }))} />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">IPI %</label>
            <Input type="number" step="0.01" className="mt-1" value={fiscal.default_ipi_rate}
              onChange={e => setFiscal(p => ({ ...p, default_ipi_rate: parseFloat(e.target.value) || 0 }))} />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">PIS %</label>
            <Input type="number" step="0.01" className="mt-1" value={fiscal.default_pis_rate}
              onChange={e => setFiscal(p => ({ ...p, default_pis_rate: parseFloat(e.target.value) || 0 }))} />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">COFINS %</label>
            <Input type="number" step="0.01" className="mt-1" value={fiscal.default_cofins_rate}
              onChange={e => setFiscal(p => ({ ...p, default_cofins_rate: parseFloat(e.target.value) || 0 }))} />
          </div>
        </div>
      </div>

      <Button onClick={handleSave} disabled={saving} className="bg-accent text-accent-foreground hover:bg-accent/90">
        {t.common.saveChanges}
      </Button>
    </div>
  );
}
