import { useState, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { useI18n, type Locale } from '@/i18n';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { MapPin, DollarSign, Users, Globe, Banknote, CreditCard, FileText, Tag, Receipt, Package, Mail, MessageCircle, Pencil } from 'lucide-react';
import { WhatsAppTemplatesManager } from '@/components/WhatsAppTemplatesManager';
import { LogoCropDialog } from '@/components/LogoCropDialog';
import { WhatsAppReminderSettings } from '@/components/WhatsAppReminderSettings';
import { WhatsAppQueuePanel } from '@/components/WhatsAppQueuePanel';
import { WhatsAppWebhookValidator } from '@/components/WhatsAppWebhookValidator';
import { WhatsAppZApiSettings } from '@/components/WhatsAppZApiSettings';
import { AppUserEditDialog } from '@/components/AppUserEditDialog';
import { useAuth } from '@/hooks/use-auth';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useCardFees, useUpdateCardFee } from '@/hooks/use-card-fees';
import { useFinancialCategories, useCreateFinancialCategory, useUpdateFinancialCategory } from '@/hooks/use-financial-categories';
import { useAllProductCategories, useCreateProductCategory, useUpdateProductCategory } from '@/hooks/use-product-categories';
import { useAppUsers as useAppUsersHook, useCreateAppUser, useUpdateAppUser, USER_ROLES } from '@/hooks/use-app-users';
import { useAllPaymentConditionPresets, useCreatePaymentConditionPreset, useUpdatePaymentConditionPreset } from '@/hooks/use-payment-conditions';
import { Switch } from '@/components/ui/switch';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { CSOSN_OPTIONS, FISCAL_ORIGIN_OPTIONS } from '@/lib/price-calculator';
import { maskCNPJ, maskPhone, maskCEP } from '@/lib/masks';

const TERM_KEYS = [
  { key: 'terms_warranty', labelKey: 'termsWarranty' as const },
  { key: 'terms_cancellation', labelKey: 'termsCancellation' as const },
  { key: 'terms_delivery', labelKey: 'termsDelivery' as const },
  { key: 'terms_responsibilities', labelKey: 'termsResponsibilities' as const },
  { key: 'terms_general', labelKey: 'termsGeneral' as const },
];

export default function SettingsPage() {
  const [searchParams] = useSearchParams();
  const defaultTab = searchParams.get('tab') || 'company';
  const { t, locale, setLocale, currency, setCurrency } = useI18n();
  const { data: cardFees } = useCardFees();
  const updateFee = useUpdateCardFee();

  // Card fee local state
  const [localFees, setLocalFees] = useState<Record<number, string>>({});
  useEffect(() => {
    if (cardFees) {
      const map: Record<number, string> = {};
      cardFees.forEach((f) => { map[f.installments] = String(f.fee_percent); });
      setLocalFees(map);
    }
  }, [cardFees]);

  const handleFeeBlur = async (installments: number) => {
    const val = parseFloat(localFees[installments] || '0');
    try {
      await updateFee.mutateAsync({ installments, fee_percent: val });
      toast.success(t.settings.feeSaved);
    } catch (e: any) {
      toast.error(e.message || 'Error');
    }
  };

  // Terms state
  const [terms, setTerms] = useState<Record<string, string>>({});
  const [termsLoading, setTermsLoading] = useState(true);

  useEffect(() => {
    (async () => {
      const keys = TERM_KEYS.map((t) => t.key);
      const { data } = await supabase
        .from('app_settings')
        .select('key, value')
        .in('key', keys);
      const map: Record<string, string> = {};
      (data || []).forEach((r) => { map[r.key] = r.value; });
      setTerms(map);
      setTermsLoading(false);
    })();
  }, []);

  const handleSaveTerms = async () => {
    try {
      for (const tk of TERM_KEYS) {
        await supabase.from('app_settings').upsert(
          { key: tk.key, value: terms[tk.key] || '' },
          { onConflict: 'key' }
        );
      }
      toast.success(t.settings.termsSaved);
    } catch (e: any) {
      toast.error(e.message || 'Error');
    }
  };

  const [categoriesSubTab, setCategoriesSubTab] = useState<'service' | 'product'>('service');

  // Currency tab content (extracted to keep below render readable)
  const currencyContent = (
    <div className="rounded-xl border bg-card p-6 shadow-sm max-w-2xl">
      <h3 className="text-sm font-semibold mb-4 flex items-center gap-2"><Banknote className="h-4 w-4" /> {t.settings.currencySettings}</h3>
      <p className="text-sm text-muted-foreground mb-4">{t.settings.exchangeRateNote}</p>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <label className="text-xs font-medium text-muted-foreground">{t.settings.baseCurrency}</label>
          <Select value={currency.baseCurrency} onValueChange={(v) => setCurrency({ baseCurrency: v })}>
            <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="BRL">BRL - Real Brasileiro</SelectItem>
              <SelectItem value="USD">USD - US Dollar</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div>
          <label className="text-xs font-medium text-muted-foreground">{t.settings.displayCurrency}</label>
          <Select value={currency.displayCurrency} onValueChange={(v) => setCurrency({ displayCurrency: v })}>
            <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="BRL">BRL - Real Brasileiro</SelectItem>
              <SelectItem value="USD">USD - US Dollar</SelectItem>
            </SelectContent>
          </Select>
        </div>
      </div>
      <div className="mt-6">
        <h4 className="text-sm font-semibold mb-3">{t.settings.exchangeRates}</h4>
        <div className="rounded-lg border overflow-hidden">
          <table className="w-full text-sm">
            <thead><tr className="border-b bg-muted/50">
              <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.settings.from}</th>
              <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.settings.to}</th>
              <th className="px-4 py-2 text-right font-medium text-muted-foreground">{t.settings.rateValue}</th>
              <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.settings.rateSource}</th>
            </tr></thead>
            <tbody>
              <tr className="border-b">
                <td className="px-4 py-3">USD</td>
                <td className="px-4 py-3">BRL</td>
                <td className="px-4 py-3 text-right font-medium">5.65</td>
                <td className="px-4 py-3 text-muted-foreground">{t.settings.manual}</td>
              </tr>
              <tr>
                <td className="px-4 py-3">BRL</td>
                <td className="px-4 py-3">USD</td>
                <td className="px-4 py-3 text-right font-medium">0.177</td>
                <td className="px-4 py-3 text-muted-foreground">{t.settings.manual}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );

  const cardFeesContent = (
    <div className="rounded-xl border bg-card p-6 shadow-sm max-w-2xl">
      <h3 className="text-sm font-semibold mb-4 flex items-center gap-2"><CreditCard className="h-4 w-4" /> {t.settings.cardFees}</h3>
      <p className="text-sm text-muted-foreground mb-4">{t.settings.cardFeesDescription}</p>
      <div className="rounded-lg border overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b bg-muted/50">
              <th className="px-4 py-2 text-left font-medium text-muted-foreground">{t.settings.installments}</th>
              <th className="px-4 py-2 text-right font-medium text-muted-foreground">{t.settings.feePercent}</th>
            </tr>
          </thead>
          <tbody>
            {[1, 2, 3, 4, 5, 6].map((n) => (
              <tr key={n} className="border-b last:border-0">
                <td className="px-4 py-3 font-medium">{n}x</td>
                <td className="px-4 py-3 text-right">
                  <Input
                    type="number"
                    step="0.01"
                    className="w-24 h-8 text-right text-sm ml-auto"
                    value={localFees[n] ?? ''}
                    onChange={(e) => setLocalFees((p) => ({ ...p, [n]: e.target.value }))}
                    onBlur={() => handleFeeBlur(n)}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );

  const termsContent = (
    <div className="rounded-xl border bg-card p-6 shadow-sm max-w-2xl">
      <h3 className="text-sm font-semibold mb-4 flex items-center gap-2"><FileText className="h-4 w-4" /> {t.settings.terms}</h3>
      {termsLoading ? (
        <p className="text-sm text-muted-foreground">{t.common.loading}</p>
      ) : (
        <div className="space-y-4">
          {TERM_KEYS.map((tk) => (
            <div key={tk.key}>
              <label className="text-xs font-medium text-muted-foreground">{t.settings[tk.labelKey]}</label>
              <Textarea
                className="mt-1"
                rows={3}
                value={terms[tk.key] || ''}
                onChange={(e) => setTerms((p) => ({ ...p, [tk.key]: e.target.value }))}
              />
            </div>
          ))}
          <Button onClick={handleSaveTerms} className="bg-accent text-accent-foreground hover:bg-accent/90">
            {t.common.saveChanges}
          </Button>
        </div>
      )}
    </div>
  );

  const languageContent = (
    <div className="rounded-xl border bg-card p-6 shadow-sm max-w-2xl">
      <h3 className="text-sm font-semibold mb-4 flex items-center gap-2"><Globe className="h-4 w-4" /> {t.settings.languageSettings}</h3>
      <p className="text-sm text-muted-foreground mb-4">{t.settings.languageNote}</p>
      <div>
        <label className="text-xs font-medium text-muted-foreground">{t.settings.selectLanguage}</label>
        <Select value={locale} onValueChange={(v) => setLocale(v as Locale)}>
          <SelectTrigger className="mt-1 w-full max-w-xs">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="pt-BR">Português (Brasil)</SelectItem>
            <SelectItem value="en">English</SelectItem>
          </SelectContent>
        </Select>
      </div>
    </div>
  );

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title={t.settings.title} description={t.settings.description} />

      <Tabs defaultValue={defaultTab}>
        <TabsList className="flex-wrap h-auto gap-1">
          <TabsTrigger value="company">Empresa</TabsTrigger>
          <TabsTrigger value="users">Usuários</TabsTrigger>
          <TabsTrigger value="financial">
            <DollarSign className="h-3.5 w-3.5 mr-1" />
            Financeiro
          </TabsTrigger>
          <TabsTrigger value="documents">
            <FileText className="h-3.5 w-3.5 mr-1" />
            Documentos
          </TabsTrigger>
          <TabsTrigger value="categories">
            <Package className="h-3.5 w-3.5 mr-1" />
            Categorias de Produto
          </TabsTrigger>
          <TabsTrigger value="whatsapp">
            <MessageCircle className="h-3.5 w-3.5 mr-1" />
            WhatsApp
          </TabsTrigger>
          <TabsTrigger value="system">Sistema</TabsTrigger>
        </TabsList>

        <TabsContent value="company" className="mt-4 space-y-4">
          <CompanyTab />
        </TabsContent>

        <TabsContent value="users" className="mt-4 space-y-4">
          <UsersTab />
        </TabsContent>

        <TabsContent value="financial" className="mt-4 space-y-6">
          {currencyContent}
          {cardFeesContent}
          <PaymentConditionsTab />
          <FiscalTab />
          <div>
            <h3 className="text-sm font-semibold mb-3 flex items-center gap-2">
              <Tag className="h-4 w-4" /> Categorias Financeiras
            </h3>
            <CategoriesTab />
          </div>
        </TabsContent>

        <TabsContent value="documents" className="mt-4 space-y-6">
          {termsContent}
        </TabsContent>

        <TabsContent value="categories" className="mt-4 space-y-4">
          <ProductCategoriesTab />
        </TabsContent>

        <TabsContent value="whatsapp" className="mt-4 space-y-6">
          <WhatsAppZApiSettings />
          <WhatsAppTemplatesManager />
          <WhatsAppWebhookValidator />
          <WhatsAppQueuePanel />
          <WhatsAppReminderSettings />
        </TabsContent>

        <TabsContent value="system" className="mt-4 space-y-4">
          {languageContent}
        </TabsContent>
      </Tabs>
    </div>
  );
}

function CompanyTab() {
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
    cost_per_km: '3.50',
    default_hourly_rate: '150',
    bank_name: '',
    bank_agency: '',
    bank_account: '',
    pix_key: '',
    app_public_url: 'https://hbrmarine.online',
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
          cost_per_km: map.cost_per_km || '3.50',
          default_hourly_rate: map.default_hourly_rate || '150',
          bank_name: map.bank_name || '',
          bank_agency: map.bank_agency || '',
          bank_account: map.bank_account || '',
          pix_key: map.pix_key || '',
          app_public_url: map.app_public_url || 'https://hbrmarine.online',
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
            <label className="text-xs font-medium text-muted-foreground">Custo por km (R$)</label>
            <Input type="number" step="0.01" value={form.cost_per_km}
              onChange={e => set('cost_per_km', e.target.value)} className="mt-1" />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Taxa horária padrão (R$)</label>
            <Input type="number" step="0.01" value={form.default_hourly_rate}
              onChange={e => set('default_hourly_rate', e.target.value)} className="mt-1" />
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
              placeholder="https://hbrmarine.online"
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

function FiscalTab() {
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

function CategoriesTab() {
  const { t } = useI18n();
  const st = t.settings as any;
  const { data: payableCats } = useFinancialCategories('payable');
  const { data: receivableCats } = useFinancialCategories('receivable');
  const createCat = useCreateFinancialCategory();
  const updateCat = useUpdateFinancialCategory();

  const [newPayName, setNewPayName] = useState('');
  const [newPayColor, setNewPayColor] = useState('#6b7280');
  const [newRecName, setNewRecName] = useState('');
  const [newRecColor, setNewRecColor] = useState('#6b7280');
  const [showNewPay, setShowNewPay] = useState(false);
  const [showNewRec, setShowNewRec] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editName, setEditName] = useState('');

  const handleCreate = async (type: 'payable' | 'receivable') => {
    const name = type === 'payable' ? newPayName : newRecName;
    const color = type === 'payable' ? newPayColor : newRecColor;
    if (!name.trim()) return;
    try {
      await createCat.mutateAsync({ name: name.trim(), type, color });
      if (type === 'payable') { setNewPayName(''); setNewPayColor('#6b7280'); setShowNewPay(false); }
      else { setNewRecName(''); setNewRecColor('#6b7280'); setShowNewRec(false); }
      toast.success(st.newCategory);
    } catch { toast.error('Erro'); }
  };

  const handleRename = async (id: string) => {
    if (!editName.trim()) return;
    try {
      await updateCat.mutateAsync({ id, name: editName.trim() });
      setEditingId(null);
    } catch { toast.error('Erro'); }
  };

  const renderColumn = (
    title: string, cats: any[] | undefined, type: 'payable' | 'receivable',
    showNew: boolean, setShowNew: (v: boolean) => void,
    newName: string, setNewName: (v: string) => void,
    newColor: string, setNewColor: (v: string) => void
  ) => (
    <div className="rounded-xl border bg-card p-6 shadow-sm">
      <h3 className="text-sm font-semibold mb-4 flex items-center gap-2"><Tag className="h-4 w-4" /> {title}</h3>
      <div className="space-y-2">
        {(cats || []).map(c => (
          <div key={c.id} className="flex items-center gap-3 p-2 rounded-lg hover:bg-muted/50">
            <span className="w-3 h-3 rounded-full shrink-0" style={{ backgroundColor: c.color || '#6b7280' }} />
            {editingId === c.id ? (
              <Input className="h-7 text-sm flex-1" value={editName} onChange={e => setEditName(e.target.value)}
                onBlur={() => handleRename(c.id)} onKeyDown={e => e.key === 'Enter' && handleRename(c.id)} autoFocus />
            ) : (
              <button className="flex-1 text-left text-sm font-medium hover:underline"
                onClick={() => { setEditingId(c.id); setEditName(c.name); }}>
                {c.name}
              </button>
            )}
            <Switch checked={c.active} onCheckedChange={v => updateCat.mutate({ id: c.id, active: v })} />
          </div>
        ))}
      </div>
      {showNew ? (
        <div className="mt-3 p-3 rounded-lg border bg-muted/30 space-y-2">
          <div className="flex gap-2">
            <Input placeholder={st.categoryName} value={newName} onChange={e => setNewName(e.target.value)} className="flex-1 h-8" />
            <input type="color" value={newColor} onChange={e => setNewColor(e.target.value)} className="w-8 h-8 rounded cursor-pointer" />
          </div>
          <div className="flex gap-1">
            <Button size="sm" onClick={() => handleCreate(type)} disabled={createCat.isPending}>{t.common.save}</Button>
            <Button size="sm" variant="ghost" onClick={() => setShowNew(false)}>{t.common.cancel}</Button>
          </div>
        </div>
      ) : (
        <Button variant="outline" size="sm" className="mt-3" onClick={() => setShowNew(true)}>
          + {st.newCategory}
        </Button>
      )}
    </div>
  );

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
      {renderColumn(st.payableCategories, payableCats, 'payable', showNewPay, setShowNewPay, newPayName, setNewPayName, newPayColor, setNewPayColor)}
      {renderColumn(st.receivableCategories, receivableCats, 'receivable', showNewRec, setShowNewRec, newRecName, setNewRecName, newRecColor, setNewRecColor)}
    </div>
  );
}

function ProductCategoriesTab() {
  const { t } = useI18n();
  const st = t.settings as any;
  const { data: categories, isLoading } = useAllProductCategories();
  const createCat = useCreateProductCategory();
  const updateCat = useUpdateProductCategory();

  const [showNew, setShowNew] = useState(false);
  const [newForm, setNewForm] = useState({
    name: '',
    default_profit_margin: 30,
    default_commission_rate: 0,
    is_commissionable: true,
    default_csosn: '400',
    default_ncm: '',
  });
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editField, setEditField] = useState<string>('');
  const [editValue, setEditValue] = useState<any>('');

  const handleCreate = async () => {
    if (!newForm.name.trim()) return;
    try {
      await createCat.mutateAsync({
        name: newForm.name.trim(),
        default_profit_margin: newForm.default_profit_margin,
        default_commission_rate: newForm.default_commission_rate,
        is_commissionable: newForm.is_commissionable,
        default_csosn: newForm.default_csosn,
        default_ncm: newForm.default_ncm || null,
      });
      setShowNew(false);
      setNewForm({ name: '', default_profit_margin: 30, default_commission_rate: 0, is_commissionable: true, default_csosn: '400', default_ncm: '' });
      toast.success(st.newProductCategory || 'Categoria criada');
    } catch (e: any) {
      toast.error(e.message || 'Erro');
    }
  };

  const handleInlineEdit = async (id: string, field: string, value: any) => {
    try {
      await updateCat.mutateAsync({ id, [field]: value });
      setEditingId(null);
    } catch (e: any) {
      toast.error(e.message || 'Erro');
    }
  };

  if (isLoading) return <p className="text-sm text-muted-foreground">{t.common.loading}</p>;

  return (
    <div className="space-y-4 max-w-4xl">
      <div className="rounded-lg border border-primary/20 bg-primary/5 p-3 text-sm">
        <Package className="h-4 w-4 inline mr-1.5 text-primary" />
        {st.productCategoriesInfo || 'As categorias definem margens e comissões padrão para grupos de produtos. Produtos herdam estas configurações mas podem ter valores personalizados individualmente.'}
      </div>

      <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b bg-muted/50">
              <th className="px-4 py-2 text-left font-medium text-muted-foreground">Nome</th>
              <th className="px-3 py-2 text-right font-medium text-muted-foreground">{st.defaultProfitMargin || 'Margem %'}</th>
              <th className="px-3 py-2 text-right font-medium text-muted-foreground">{st.defaultCommissionRate || 'Comissão %'}</th>
              <th className="px-3 py-2 text-center font-medium text-muted-foreground">Comissionável</th>
              <th className="px-3 py-2 text-left font-medium text-muted-foreground">NCM</th>
              <th className="px-3 py-2 text-center font-medium text-muted-foreground">{t.common.active}</th>
            </tr>
          </thead>
          <tbody>
            {(categories || []).map(cat => (
              <tr key={cat.id} className="border-b last:border-0 hover:bg-muted/30">
                <td className="px-4 py-2">
                  {editingId === cat.id && editField === 'name' ? (
                    <Input
                      className="h-7 text-sm"
                      value={editValue}
                      onChange={e => setEditValue(e.target.value)}
                      onBlur={() => handleInlineEdit(cat.id, 'name', editValue)}
                      onKeyDown={e => e.key === 'Enter' && handleInlineEdit(cat.id, 'name', editValue)}
                      autoFocus
                    />
                  ) : (
                    <button
                      className="font-medium hover:underline text-left"
                      onClick={() => { setEditingId(cat.id); setEditField('name'); setEditValue(cat.name); }}
                    >
                      {cat.name}
                    </button>
                  )}
                </td>
                <td className="px-3 py-2 text-right">
                  {editingId === cat.id && editField === 'default_profit_margin' ? (
                    <Input
                      type="number" step="0.01" className="h-7 text-sm w-20 ml-auto text-right"
                      value={editValue}
                      onChange={e => setEditValue(e.target.value)}
                      onBlur={() => handleInlineEdit(cat.id, 'default_profit_margin', parseFloat(editValue) || 0)}
                      autoFocus
                    />
                  ) : (
                    <button
                      className="hover:underline"
                      onClick={() => { setEditingId(cat.id); setEditField('default_profit_margin'); setEditValue(cat.default_profit_margin); }}
                    >
                      {cat.default_profit_margin}%
                    </button>
                  )}
                </td>
                <td className="px-3 py-2 text-right">
                  {editingId === cat.id && editField === 'default_commission_rate' ? (
                    <Input
                      type="number" step="0.01" className="h-7 text-sm w-20 ml-auto text-right"
                      value={editValue}
                      onChange={e => setEditValue(e.target.value)}
                      onBlur={() => handleInlineEdit(cat.id, 'default_commission_rate', parseFloat(editValue) || 0)}
                      autoFocus
                    />
                  ) : (
                    <button
                      className="hover:underline"
                      onClick={() => { setEditingId(cat.id); setEditField('default_commission_rate'); setEditValue(cat.default_commission_rate); }}
                    >
                      {cat.default_commission_rate}%
                    </button>
                  )}
                </td>
                <td className="px-3 py-2 text-center">
                  <Switch
                    checked={cat.is_commissionable ?? true}
                    onCheckedChange={v => updateCat.mutate({ id: cat.id, is_commissionable: v })}
                  />
                </td>
                <td className="px-3 py-2">
                  {editingId === cat.id && editField === 'default_ncm' ? (
                    <Input
                      className="h-7 text-sm w-24"
                      value={editValue}
                      maxLength={8}
                      onChange={e => setEditValue(e.target.value.replace(/\D/g, '').slice(0, 8))}
                      onBlur={() => handleInlineEdit(cat.id, 'default_ncm', editValue || null)}
                      autoFocus
                    />
                  ) : (
                    <button
                      className="hover:underline text-muted-foreground"
                      onClick={() => { setEditingId(cat.id); setEditField('default_ncm'); setEditValue(cat.default_ncm || ''); }}
                    >
                      {cat.default_ncm || '—'}
                    </button>
                  )}
                </td>
                <td className="px-3 py-2 text-center">
                  <Switch
                    checked={cat.active ?? true}
                    onCheckedChange={v => updateCat.mutate({ id: cat.id, active: v })}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <p className="text-xs text-muted-foreground">{(categories || []).length} categorias cadastradas</p>

      {showNew ? (
        <div className="rounded-xl border bg-card p-4 shadow-sm space-y-3">
          <h4 className="text-sm font-semibold">{st.newProductCategory || 'Nova Categoria'}</h4>
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2">
              <label className="text-xs font-medium text-muted-foreground">Nome *</label>
              <Input value={newForm.name} onChange={e => setNewForm(p => ({ ...p, name: e.target.value }))} className="mt-1" />
            </div>
            <div>
              <label className="text-xs font-medium text-muted-foreground">{st.defaultProfitMargin || 'Margem %'}</label>
              <Input type="number" step="0.01" value={newForm.default_profit_margin}
                onChange={e => setNewForm(p => ({ ...p, default_profit_margin: parseFloat(e.target.value) || 0 }))} className="mt-1" />
            </div>
            <div>
              <label className="text-xs font-medium text-muted-foreground">{st.defaultCommissionRate || 'Comissão %'}</label>
              <Input type="number" step="0.01" value={newForm.default_commission_rate}
                onChange={e => setNewForm(p => ({ ...p, default_commission_rate: parseFloat(e.target.value) || 0 }))} className="mt-1" />
            </div>
            <div className="flex items-center gap-2 col-span-2 pt-1">
              <Switch
                checked={newForm.is_commissionable}
                onCheckedChange={v => setNewForm(p => ({ ...p, is_commissionable: v }))}
              />
              <label className="text-xs">Permite comissionamento</label>
            </div>
            <div>
              <label className="text-xs font-medium text-muted-foreground">NCM Padrão</label>
              <Input value={newForm.default_ncm} maxLength={8}
                onChange={e => setNewForm(p => ({ ...p, default_ncm: e.target.value.replace(/\D/g, '').slice(0, 8) }))} className="mt-1" />
            </div>
          </div>
          <div className="flex gap-2">
            <Button size="sm" onClick={handleCreate} disabled={createCat.isPending || !newForm.name.trim()}>{t.common.save}</Button>
            <Button size="sm" variant="ghost" onClick={() => setShowNew(false)}>{t.common.cancel}</Button>
          </div>
        </div>
      ) : (
        <Button variant="outline" size="sm" onClick={() => setShowNew(true)}>
          + {st.newProductCategory || 'Nova Categoria'}
        </Button>
      )}
    </div>
  );
}

function UsersTab() {
  const { t } = useI18n();
  const { user: currentUser } = useAuth();
  const isCurrentUserAdmin = currentUser?.role === 'admin';
  const { data: users, isLoading } = useAppUsersHook();
  const createUser = useCreateAppUser();
  const updateUser = useUpdateAppUser();
  const [showNew, setShowNew] = useState(false);
  const [editingUser, setEditingUser] = useState<any | null>(null);
  const [newForm, setNewForm] = useState({
    full_name: '', email: '', role: 'technician', phone: '',
  });

  const handleCreate = async () => {
    if (!newForm.full_name || !newForm.email) {
      toast.error('Nome e email são obrigatórios'); return;
    }
    try {
      await createUser.mutateAsync(newForm);
      setShowNew(false);
      setNewForm({ full_name: '', email: '', role: 'technician', phone: '' });
      toast.success('Usuário criado com sucesso');
    } catch (e: any) { toast.error(e.message || 'Erro'); }
  };

  if (isLoading) return <p className="text-sm text-muted-foreground">{t.common.loading}</p>;

  return (
    <div className="space-y-4 max-w-3xl">
      <div className="rounded-lg border border-primary/20 bg-primary/5 p-3 text-sm">
        <Users className="h-4 w-4 inline mr-1.5 text-primary" />
        Cadastre técnicos, vendedores e outros membros da equipe. Eles aparecerão como opções nas OS.
      </div>

      <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b bg-muted/50">
              <th className="px-4 py-2 text-left font-medium text-muted-foreground">Nome</th>
              <th className="px-4 py-2 text-left font-medium text-muted-foreground">Email</th>
              <th className="px-4 py-2 text-left font-medium text-muted-foreground">Função</th>
              <th className="px-4 py-2 text-left font-medium text-muted-foreground">Telefone</th>
              <th className="px-4 py-2 text-center font-medium text-muted-foreground">{t.common.active}</th>
              <th className="px-4 py-2 text-center font-medium text-muted-foreground">Ações</th>
            </tr>
          </thead>
          <tbody>
            {(users || []).map(u => (
              <tr key={u.id} className="border-b last:border-0 hover:bg-muted/30">
                <td className="px-4 py-2 font-medium">{u.full_name}</td>
                <td className="px-4 py-2 text-muted-foreground">{u.email}</td>
                <td className="px-4 py-2">
                  <span className="text-xs font-medium px-2 py-1 rounded bg-primary/10 text-primary">
                    {USER_ROLES.find(r => r.value === u.role)?.label || u.role}
                  </span>
                </td>
                <td className="px-4 py-2 text-muted-foreground">{u.phone || '—'}</td>
                <td className="px-4 py-2 text-center">
                  <Switch checked={u.active} onCheckedChange={v => updateUser.mutate({ id: u.id, active: v })} />
                </td>
                <td className="px-4 py-2 text-center">
                  <div className="flex items-center justify-center gap-1">
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setEditingUser(u)}
                    >
                      <Pencil className="h-3.5 w-3.5 mr-1" />
                      Editar
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={async () => {
                        try {
                          await supabase.auth.resetPasswordForEmail(u.email, {
                            redirectTo: window.location.origin + '/reset-password',
                          });
                          toast.success(`Link enviado para ${u.email}`);
                        } catch {
                          toast.error('Erro ao enviar email');
                        }
                      }}
                    >
                      <Mail className="h-3.5 w-3.5 mr-1" />
                      Enviar acesso
                    </Button>
                  </div>
                </td>
              </tr>
            ))}
            {(users || []).length === 0 && (
              <tr><td colSpan={6} className="px-4 py-8 text-center text-muted-foreground">Nenhum usuário cadastrado ainda</td></tr>
            )}
          </tbody>
        </table>
      </div>

      <p className="text-xs text-muted-foreground">{(users || []).length} usuários</p>

      {showNew ? (
        <div className="rounded-xl border bg-card p-4 shadow-sm space-y-3">
          <h4 className="text-sm font-semibold">Novo Usuário</h4>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-xs font-medium text-muted-foreground">Nome *</label>
              <Input value={newForm.full_name} onChange={e => setNewForm(p => ({ ...p, full_name: e.target.value }))} className="mt-1" />
            </div>
            <div>
              <label className="text-xs font-medium text-muted-foreground">Email *</label>
              <Input value={newForm.email} onChange={e => setNewForm(p => ({ ...p, email: e.target.value }))} className="mt-1" />
            </div>
            <div>
              <label className="text-xs font-medium text-muted-foreground">Telefone</label>
              <Input value={newForm.phone} onChange={e => setNewForm(p => ({ ...p, phone: maskPhone(e.target.value) }))} className="mt-1" placeholder="(47) 99999-9999" maxLength={15} />
            </div>
            <div>
              <label className="text-xs font-medium text-muted-foreground">Função</label>
              <Select value={newForm.role} onValueChange={v => setNewForm(p => ({ ...p, role: v }))}>
                <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {USER_ROLES.map(r => <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="flex gap-2">
            <Button size="sm" onClick={handleCreate} disabled={createUser.isPending}>Salvar</Button>
            <Button size="sm" variant="ghost" onClick={() => setShowNew(false)}>{t.common.cancel}</Button>
          </div>
        </div>
      ) : (
        <Button variant="outline" size="sm" onClick={() => setShowNew(true)}>
          + Novo Usuário
        </Button>
      )}

      <AppUserEditDialog
        user={editingUser}
        open={!!editingUser}
        onOpenChange={(o) => { if (!o) setEditingUser(null); }}
        isCurrentUserAdmin={isCurrentUserAdmin}
      />
    </div>
  );
}

function PaymentConditionsTab() {
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

interface InstallmentRow {
  label: string;
  services_pct: number;
  parts_pct: number;
  expenses_pct: number;
  days_after_approval: number;
  tipo: 'aprovacao' | 'entrega' | 'prazo';
}

function PaymentPresetRow({ preset, updatePreset }: { preset: any; updatePreset: ReturnType<typeof useUpdatePaymentConditionPreset> }) {
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
            <div className="grid grid-cols-[1fr_130px_70px_70px_70px_90px_36px] gap-2 text-[11px] uppercase tracking-wide text-muted-foreground px-1">
              <div>Descrição</div>
              <div className="text-center">Tipo</div>
              <div className="text-center">% Serv.</div>
              <div className="text-center">% Peças</div>
              <div className="text-center">% Desp.</div>
              <div className="text-center">Dias</div>
              <div></div>
            </div>
            {rows.map((row, i) => (
              <div key={i} className="grid grid-cols-[1fr_130px_70px_70px_70px_90px_36px] gap-2 items-center">
                <Input
                  value={row.label}
                  onChange={(e) => updateRow(i, { label: e.target.value })}
                  placeholder="Ex: Sinal"
                  className="h-8 text-sm"
                />
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
                <Input
                  type="number"
                  step="0.01"
                  min={0}
                  max={100}
                  value={row.services_pct}
                  onChange={(e) => updateRow(i, { services_pct: parseFloat(e.target.value) || 0 })}
                  className="h-8 text-sm text-center"
                />
                <Input
                  type="number"
                  step="0.01"
                  min={0}
                  max={100}
                  value={row.parts_pct}
                  onChange={(e) => updateRow(i, { parts_pct: parseFloat(e.target.value) || 0 })}
                  className="h-8 text-sm text-center"
                />
                <Input
                  type="number"
                  step="0.01"
                  min={0}
                  max={100}
                  value={row.expenses_pct}
                  onChange={(e) => updateRow(i, { expenses_pct: parseFloat(e.target.value) || 0 })}
                  className="h-8 text-sm text-center"
                />
                <Input
                  type="number"
                  min={0}
                  value={row.days_after_approval}
                  onChange={(e) => updateRow(i, { days_after_approval: parseInt(e.target.value, 10) || 0 })}
                  className="h-8 text-sm text-center"
                  disabled={row.tipo !== 'prazo'}
                  placeholder={row.tipo === 'prazo' ? '30' : '—'}
                />
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-8 w-8 text-destructive"
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

