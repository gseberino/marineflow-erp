// Aba "CompanyTab" de Configurações. Extraída de SettingsPage.tsx em 20/09/2026 (o arquivo
// tinha 1.981 linhas); comportamento idêntico, só mudou de endereço.
import { useState, useEffect } from 'react';
import { useI18n } from '@/i18n';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { MapPin, DollarSign, Banknote, FileText } from 'lucide-react';
import { LogoCropDialog } from '@/components/LogoCropDialog';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { maskCNPJ, maskPhone, maskCEP } from '@/lib/masks';

export function CompanyTab() {
  const { t } = useI18n();
  const [saving, setSaving] = useState(false);
  const [loading, setLoading] = useState(true);
  const [logoUrl, setLogoUrl] = useState<string>('');
  const [logoUploading, setLogoUploading] = useState(false);
  const [cropFile, setCropFile] = useState<File | null>(null);
  const [cropOpen, setCropOpen] = useState(false);
  const [form, setForm] = useState({
    company_name: '',
    cnpj: '',
    address_line_1: '',
    address_number: '',
    neighborhood: '',
    city: '',
    state: '',
    postal_code: '',
    phone: '',
    email: '',
    base_latitude: '-26.9189',
    base_longitude: '-48.6728',
    default_hourly_rate: '150',
    travel_km_rate: '1.10',
    travel_hourly_1: '90',
    travel_hourly_2: '170',
    travel_hourly_3: '250',
    travel_urgency_mult: '1.5',
    travel_weekend_mult: '1.3',
    bank_name: '',
    bank_agency: '',
    bank_account: '',
    pix_key: '',
    payment_link_url: '',
    app_public_url: 'https://marineflow-erp.vercel.app',
  });

  useEffect(() => {
    (async () => {
      const { data } = await supabase
        .from('app_settings')
        .select('key, value');
      if (data) {
        const map: Record<string, string> = {};
        for (const row of data) {
          if (row.key && row.value !== null) map[row.key] = String(row.value);
        }
        setForm(prev => ({
          ...prev,
          company_name: map.company_name || '',
          cnpj: map.cnpj || '',
          address_line_1: map.address_line_1 || '',
          address_number: map.address_number || '',
          neighborhood: map.neighborhood || '',
          city: map.city || '',
          state: map.state || '',
          postal_code: map.postal_code || '',
          phone: map.phone || '',
          email: map.email || '',
          base_latitude: map.base_latitude || '-26.9189',
          base_longitude: map.base_longitude || '-48.6728',
          default_hourly_rate: map.default_hourly_rate || '150',
          travel_km_rate: map.travel_km_rate || '1.10',
          travel_hourly_1: map.travel_hourly_1 || '90',
          travel_hourly_2: map.travel_hourly_2 || '170',
          travel_hourly_3: map.travel_hourly_3 || '250',
          travel_urgency_mult: map.travel_urgency_mult || '1.5',
          travel_weekend_mult: map.travel_weekend_mult || '1.3',
          bank_name: map.bank_name || '',
          bank_agency: map.bank_agency || '',
          bank_account: map.bank_account || '',
          pix_key: map.pix_key || '',
          payment_link_url: map.payment_link_url || '',
          app_public_url: map.app_public_url || 'https://marineflow-erp.vercel.app',
        }));
        setLogoUrl(map.company_logo_url || '');
      }
      setLoading(false);
    })();
  }, []);

  const handleLogoSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    if (!/^image\/(png|jpeg|jpg|webp|svg\+xml)$/.test(file.type)) {
      toast.error('Formato inválido. Use PNG, JPG, WEBP ou SVG.');
      return;
    }
    if (file.size > 2 * 1024 * 1024) {
      toast.error('Arquivo muito grande. Máximo 2MB.');
      return;
    }
    // SVG: upload as-is (no raster crop). Otherwise open cropper.
    if (file.type === 'image/svg+xml') {
      uploadLogoBlob(file, 'svg');
    } else {
      setCropFile(file);
      setCropOpen(true);
    }
  };

  const uploadLogoBlob = async (blob: Blob, ext: string) => {
    setLogoUploading(true);
    try {
      const path = `company/logo.${ext}`;
      try {
        const exts = ['png', 'jpg', 'jpeg', 'webp', 'svg'];
        await supabase.storage.from('company-assets').remove(
          exts.filter(x => x !== ext).map(x => `company/logo.${x}`)
        );
      } catch {}
      const { error: upErr } = await supabase.storage
        .from('company-assets')
        .upload(path, blob, { upsert: true, contentType: blob.type || `image/${ext}`, cacheControl: '3600' });
      if (upErr) throw upErr;
      const { data: pub } = supabase.storage.from('company-assets').getPublicUrl(path);
      const url = `${pub.publicUrl}?t=${Date.now()}`;
      const { error: dbErr } = await supabase
        .from('app_settings')
        .upsert({ key: 'company_logo_url', value: url }, { onConflict: 'key' });
      if (dbErr) throw dbErr;
      setLogoUrl(url);
      toast.success('Logo enviado com sucesso');
    } catch (err: any) {
      toast.error(err?.message || 'Erro ao enviar logo');
    } finally {
      setLogoUploading(false);
    }
  };

  const handleCropConfirm = (blob: Blob) => {
    setCropOpen(false);
    setCropFile(null);
    uploadLogoBlob(blob, 'png');
  };

  const handleLogoRemove = async () => {
    setLogoUploading(true);
    try {
      const exts = ['png', 'jpg', 'jpeg', 'webp', 'svg'];
      await supabase.storage.from('company-assets').remove(
        exts.map(x => `company/logo.${x}`)
      );
      await supabase.from('app_settings').delete().eq('key', 'company_logo_url');
      setLogoUrl('');
      toast.success('Logo removido');
    } catch (err: any) {
      toast.error(err?.message || 'Erro ao remover logo');
    } finally {
      setLogoUploading(false);
    }
  };

  const set = (key: string, value: string) =>
    setForm(prev => ({ ...prev, [key]: value }));

  const handleSave = async () => {
    setSaving(true);
    try {
      const results = await Promise.all(
        Object.entries(form).map(([key, value]) =>
          supabase
            .from('app_settings')
            .upsert(
              { key, value: String(value ?? '') },
              { onConflict: 'key', ignoreDuplicates: false }
            )
        )
      );
      const failed = results.filter(r => r.error);
      if (failed.length > 0) {
        const msg = failed[0].error?.message || 'Erro ao salvar';
        throw new Error(msg);
      }
      toast.success('Configurações salvas com sucesso');
    } catch (e: any) {
      toast.error(e.message || 'Erro ao salvar configurações');
      console.error('Settings save error:', e);
    } finally {
      setSaving(false);
    }
  };

  if (loading) return <p className="text-sm text-muted-foreground">{t.common.loading}</p>;

  return (
    <div className="space-y-6 max-w-2xl">
      <div className="rounded-xl border bg-card p-6 shadow-sm">
        <h3 className="text-sm font-semibold mb-1 flex items-center gap-2">
          <FileText className="h-4 w-4" /> Logo da empresa
        </h3>
        <p className="text-xs text-muted-foreground mb-4">
          Aparece no cabeçalho dos PDFs, no menu, no login e na página pública.
          Proporção 2:1 (recomendado 320×160px). PNG transparente.
        </p>
        <div className="flex items-center gap-4">
          {logoUrl ? (
            <div className="relative inline-block">
              <img
                src={logoUrl}
                alt="Logo da empresa"
                style={{ width: 160, height: 80, objectFit: 'contain' }}
                className="rounded border bg-white p-1"
              />
              <button
                type="button"
                onClick={handleLogoRemove}
                disabled={logoUploading}
                className="absolute -top-2 -right-2 h-5 w-5 rounded-full bg-destructive text-destructive-foreground text-xs leading-none flex items-center justify-center shadow disabled:opacity-50"
                aria-label="Remover logo"
              >
                ×
              </button>
            </div>
          ) : (
            <div
              style={{ width: 160, height: 80 }}
              className="rounded border border-dashed flex items-center justify-center text-[10px] text-muted-foreground"
            >
              sem logo
            </div>
          )}
          <div>
            <input
              id="company-logo-upload"
              type="file"
              accept="image/png,image/jpeg,image/webp,image/svg+xml"
              className="hidden"
              onChange={handleLogoSelect}
              disabled={logoUploading}
            />
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => document.getElementById('company-logo-upload')?.click()}
              disabled={logoUploading}
            >
              {logoUploading ? 'Enviando...' : (logoUrl ? 'Trocar logo' : 'Enviar logo')}
            </Button>
          </div>
        </div>
        <LogoCropDialog
          file={cropFile}
          open={cropOpen}
          onOpenChange={(o) => { setCropOpen(o); if (!o) setCropFile(null); }}
          onConfirm={handleCropConfirm}
        />
      </div>

      <div className="rounded-xl border bg-card p-6 shadow-sm">
        <h3 className="text-sm font-semibold mb-4 flex items-center gap-2">
          <MapPin className="h-4 w-4" /> Dados da Empresa
        </h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="text-xs font-medium text-muted-foreground">Nome da Empresa *</label>
            <Input value={form.company_name} onChange={e => set('company_name', e.target.value)}
              placeholder="HBR Consultoria Náutica" className="mt-1" />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">CNPJ</label>
            <Input value={form.cnpj} onChange={e => set('cnpj', maskCNPJ(e.target.value))}
              placeholder="00.000.000/0001-00" maxLength={18} className="mt-1" />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Telefone</label>
            <Input value={form.phone} onChange={e => set('phone', maskPhone(e.target.value))}
              placeholder="(47) 99999-9999" maxLength={15} className="mt-1" />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">E-mail</label>
            <Input value={form.email} onChange={e => set('email', e.target.value)}
              placeholder="contato@empresa.com.br" type="email" className="mt-1" />
          </div>
        </div>
      </div>

      <div className="rounded-xl border bg-card p-6 shadow-sm">
        <h3 className="text-sm font-semibold mb-4 flex items-center gap-2">
          <MapPin className="h-4 w-4" /> Endereço
        </h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="text-xs font-medium text-muted-foreground">Logradouro</label>
            <Input value={form.address_line_1} onChange={e => set('address_line_1', e.target.value)}
              placeholder="Rua das Palmeiras" className="mt-1" />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Número</label>
            <Input value={form.address_number} onChange={e => set('address_number', e.target.value)}
              placeholder="123" className="mt-1" />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Bairro</label>
            <Input value={form.neighborhood} onChange={e => set('neighborhood', e.target.value)}
              placeholder="Centro" className="mt-1" />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">CEP</label>
            <Input value={form.postal_code} onChange={e => set('postal_code', maskCEP(e.target.value))}
              placeholder="88000-000" maxLength={9} className="mt-1" />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Cidade</label>
            <Input value={form.city} onChange={e => set('city', e.target.value)}
              placeholder="Itajaí" className="mt-1" />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Estado</label>
            <Input value={form.state} onChange={e => set('state', e.target.value)}
              placeholder="SC" maxLength={2} className="mt-1" />
          </div>
        </div>
      </div>

      <div className="rounded-xl border bg-card p-6 shadow-sm">
        <h3 className="text-sm font-semibold mb-4 flex items-center gap-2">
          <DollarSign className="h-4 w-4" /> Parâmetros Operacionais
        </h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="text-xs font-medium text-muted-foreground">Latitude base (para cálculo de deslocamento)</label>
            <Input value={form.base_latitude} onChange={e => set('base_latitude', e.target.value)}
              placeholder="-26.9189" className="mt-1" />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Longitude base</label>
            <Input value={form.base_longitude} onChange={e => set('base_longitude', e.target.value)}
              placeholder="-48.6728" className="mt-1" />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Custo por km (R$) — deslocamento</label>
            <Input type="number" step="0.01" value={form.travel_km_rate}
              onChange={e => set('travel_km_rate', e.target.value)} className="mt-1" />
            <p className="text-[10px] text-muted-foreground mt-0.5">Multiplica a distância (ida+volta) no cálculo da OS</p>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
            <div>
              <label className="text-xs font-medium text-muted-foreground">R$/h — 1 téc.</label>
              <Input type="number" step="0.01" value={form.travel_hourly_1}
                onChange={e => set('travel_hourly_1', e.target.value)} className="mt-1" />
            </div>
            <div>
              <label className="text-xs font-medium text-muted-foreground">R$/h — 2 téc.</label>
              <Input type="number" step="0.01" value={form.travel_hourly_2}
                onChange={e => set('travel_hourly_2', e.target.value)} className="mt-1" />
            </div>
            <div>
              <label className="text-xs font-medium text-muted-foreground">R$/h — 3 téc.</label>
              <Input type="number" step="0.01" value={form.travel_hourly_3}
                onChange={e => set('travel_hourly_3', e.target.value)} className="mt-1" />
            </div>
          </div>
          {/* D8 (17/09/2026): a regra acima de 3 técnicos deixa de ser "provisória" e passa a
              ser a política oficial, escrita onde a tabela é editada. */}
          <p className="text-[10px] text-muted-foreground -mt-1">
            Acima de 3 técnicos: + R$ {Math.max(0, Number(form.travel_hourly_3) - Number(form.travel_hourly_2)).toFixed(0)}/h por técnico adicional (o passo entre 2 e 3). Com {form.travel_hourly_1}/{form.travel_hourly_2}/{form.travel_hourly_3}, o 4º técnico entra por R$ {(2 * Number(form.travel_hourly_3) - Number(form.travel_hourly_2)).toFixed(0)}/h.
          </p>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Multiplicador urgência (ex: 1.5 = +50%)</label>
            <Input type="number" step="0.05" value={form.travel_urgency_mult}
              onChange={e => set('travel_urgency_mult', e.target.value)} className="mt-1" />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Multiplicador fim de semana/feriado (ex: 1.3 = +30%)</label>
            <Input type="number" step="0.05" value={form.travel_weekend_mult}
              onChange={e => set('travel_weekend_mult', e.target.value)} className="mt-1" />
          </div>
        </div>
      </div>

      <div className="rounded-xl border bg-card p-6 shadow-sm">
        <h3 className="text-sm font-semibold mb-4 flex items-center gap-2">
          <Banknote className="h-4 w-4" /> Dados Bancários (para Faturas)
        </h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="text-xs font-medium text-muted-foreground">Banco</label>
            <Input value={form.bank_name} onChange={e => set('bank_name', e.target.value)}
              placeholder="Banco do Brasil" className="mt-1" />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Agência</label>
            <Input value={form.bank_agency} onChange={e => set('bank_agency', e.target.value)}
              placeholder="0001-2" className="mt-1" />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Conta</label>
            <Input value={form.bank_account} onChange={e => set('bank_account', e.target.value)}
              placeholder="12345-6" className="mt-1" />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Chave PIX</label>
            <Input value={form.pix_key} onChange={e => set('pix_key', e.target.value)}
              placeholder="CNPJ, e-mail, telefone ou chave aleatória" className="mt-1" />
          </div>
          <div className="md:col-span-2">
            <label className="text-xs font-medium text-muted-foreground">Link de Pagamento Online (Portal do Cliente)</label>
            <Input
              type="url"
              value={form.payment_link_url}
              onChange={e => set('payment_link_url', e.target.value)}
              placeholder="https://link.mercadopago.com.br/... ou link do Stripe"
              className="mt-1"
            />
            <p className="text-xs text-muted-foreground mt-1">
              Se preenchido, um botão "Pagar agora" aparecerá no portal público da OS. Deixe em branco para ocultar.
            </p>
          </div>
        </div>
      </div>

      <div className="rounded-xl border bg-card p-6 shadow-sm">
        <h3 className="text-sm font-semibold mb-4 flex items-center gap-2">
          <MapPin className="h-4 w-4" /> Integrações
        </h3>
        <div className="grid grid-cols-1 gap-4">
          <div>
            <label className="text-xs font-medium text-muted-foreground">URL pública do app</label>
            <Input
              type="url"
              value={form.app_public_url}
              onChange={e => set('app_public_url', e.target.value)}
              placeholder="https://marineflow-erp.vercel.app"
              className="mt-1"
            />
            <p className="text-xs text-muted-foreground mt-1">
              Usada para gerar links nos envios agendados via WhatsApp. Ex: https://seuapp.lovable.app
            </p>
          </div>
        </div>
      </div>

      <Button onClick={handleSave} disabled={saving} className="bg-accent text-accent-foreground hover:bg-accent/90">
        {saving ? 'Salvando...' : 'Salvar Configurações'}
      </Button>
    </div>
  );
}
