import { useState, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { useI18n, type Locale } from '@/i18n';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { TaskAutomationSettings } from '@/components/agenda/TaskAutomationSettings';
import { InstallAgendaCard } from '@/components/agenda/InstallAgendaCard';
import { DollarSign, Globe, Banknote, CreditCard, FileText, Tag, Package } from 'lucide-react';
import { MasterDataPanel } from '@/components/MasterDataManagement';
import { VerbosFiscaisGrid } from '@/components/fiscal/VerbosFiscaisGrid';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useCardFees, useUpdateCardFee } from '@/hooks/use-card-fees';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { CompanyTab } from './settings/CompanyTab';
import { FiscalTab } from './settings/FiscalTab';
import { CategoriesTab } from './settings/CategoriesTab';
import { ProductCategoriesTab } from './settings/ProductCategoriesTab';
import { UsersTab } from './settings/UsersTab';
import { FinanceReviewSettingsSection } from './settings/FinanceReviewSettingsSection';
import { QuoteSettingsSection } from './settings/QuoteSettingsSection';
import { PaymentConditionsTab } from './settings/PaymentConditionsTab';
import { PdfDefaultsSection } from './settings/PdfDefaultsSection';

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
          <QuoteSettingsSection />
          <FinanceReviewSettingsSection />
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
          <PdfDefaultsSection />
          {termsContent}
        </TabsContent>

        <TabsContent value="categories" className="mt-4 space-y-4">
          <ProductCategoriesTab />
          {/* Simétrico ao fiscal das categorias de produto: lá o NCM é por categoria, aqui o
              código de tributação é por verbo. Mesma ideia de herança, chave diferente porque
              a LC 116 organiza serviço por atividade, não por sistema. */}
          <VerbosFiscaisGrid />
        </TabsContent>

        <TabsContent value="system" className="mt-4 space-y-4">
          {languageContent}
          <InstallAgendaCard />
          <TaskAutomationSettings />
          <MasterDataPanel />
        </TabsContent>
      </Tabs>
    </div>
  );
}
