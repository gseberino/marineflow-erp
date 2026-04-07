import { useState, useEffect } from 'react';
import { PageHeader } from '@/components/PageHeader';
import { useI18n, type Locale } from '@/i18n';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { MapPin, DollarSign, Users, Globe, Banknote, CreditCard, FileText } from 'lucide-react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useCardFees, useUpdateCardFee } from '@/hooks/use-card-fees';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

const TERM_KEYS = [
  { key: 'terms_warranty', labelKey: 'termsWarranty' as const },
  { key: 'terms_cancellation', labelKey: 'termsCancellation' as const },
  { key: 'terms_delivery', labelKey: 'termsDelivery' as const },
  { key: 'terms_responsibilities', labelKey: 'termsResponsibilities' as const },
  { key: 'terms_general', labelKey: 'termsGeneral' as const },
];

export default function SettingsPage() {
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

  return (
    <div className="space-y-6 animate-fade-in">
      <PageHeader title={t.settings.title} description={t.settings.description} />

      <Tabs defaultValue="company">
        <TabsList className="flex-wrap h-auto gap-1">
          <TabsTrigger value="company">{t.settings.tabCompany}</TabsTrigger>
          <TabsTrigger value="travel">{t.settings.tabTravel}</TabsTrigger>
          <TabsTrigger value="users">{t.settings.tabUsers}</TabsTrigger>
          <TabsTrigger value="language">{t.settings.tabLanguage}</TabsTrigger>
          <TabsTrigger value="currency">{t.settings.tabCurrency}</TabsTrigger>
          <TabsTrigger value="cardFees">{t.settings.tabCardFees}</TabsTrigger>
          <TabsTrigger value="terms">{t.settings.tabTerms}</TabsTrigger>
        </TabsList>

        <TabsContent value="company" className="mt-4 space-y-4">
          <div className="rounded-xl border bg-card p-6 shadow-sm max-w-2xl">
            <h3 className="text-sm font-semibold mb-4 flex items-center gap-2"><MapPin className="h-4 w-4" /> {t.settings.companyInfo}</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div><label className="text-xs font-medium text-muted-foreground">{t.settings.companyName}</label><Input defaultValue="NautiTech Marine Services" className="mt-1" /></div>
              <div><label className="text-xs font-medium text-muted-foreground">{t.settings.cnpj}</label><Input defaultValue="11.222.333/0001-44" className="mt-1" /></div>
              <div className="md:col-span-2"><label className="text-xs font-medium text-muted-foreground">{t.settings.baseAddress}</label><Input defaultValue="Av. Brasil, 500 - Centro, Rio de Janeiro, RJ" className="mt-1" /></div>
              <div><label className="text-xs font-medium text-muted-foreground">{t.settings.latitude}</label><Input defaultValue="-22.9068" className="mt-1" /></div>
              <div><label className="text-xs font-medium text-muted-foreground">{t.settings.longitude}</label><Input defaultValue="-43.1729" className="mt-1" /></div>
              <div><label className="text-xs font-medium text-muted-foreground">{t.settings.phone}</label><Input defaultValue="+55 21 3000-0000" className="mt-1" /></div>
              <div><label className="text-xs font-medium text-muted-foreground">{t.settings.email}</label><Input defaultValue="contact@nautitech.com" className="mt-1" /></div>
            </div>
            <Button className="mt-6 bg-accent text-accent-foreground hover:bg-accent/90">{t.common.saveChanges}</Button>
          </div>
        </TabsContent>

        <TabsContent value="travel" className="mt-4 space-y-4">
          <div className="rounded-xl border bg-card p-6 shadow-sm max-w-2xl">
            <h3 className="text-sm font-semibold mb-4 flex items-center gap-2"><DollarSign className="h-4 w-4" /> {t.settings.travelSettings}</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div><label className="text-xs font-medium text-muted-foreground">{t.settings.defaultCostPerKm}</label><Input type="number" defaultValue="3.50" className="mt-1" /></div>
              <div><label className="text-xs font-medium text-muted-foreground">{t.settings.defaultHourlyRate}</label><Input type="number" defaultValue="150" className="mt-1" /></div>
            </div>
            <div className="mt-4 space-y-3">
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" defaultChecked className="rounded border-input" />
                {t.settings.multiplyByTechnicians}
              </label>
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" className="rounded border-input" />
                {t.settings.roundTrip}
              </label>
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" defaultChecked className="rounded border-input" />
                {t.settings.allowManualOverride}
              </label>
            </div>
            <Button className="mt-6 bg-accent text-accent-foreground hover:bg-accent/90">{t.common.saveSettings}</Button>
          </div>
        </TabsContent>

        <TabsContent value="users" className="mt-4 space-y-4">
          <div className="rounded-xl border bg-card p-6 shadow-sm">
            <h3 className="text-sm font-semibold mb-4 flex items-center gap-2"><Users className="h-4 w-4" /> {t.settings.teamMembers}</h3>
            <p className="text-sm text-muted-foreground mb-4">{t.settings.userManagementNote}</p>
            <div className="space-y-3">
              {[
                { name: 'Carlos Mendes', role: 'admin', email: 'carlos@nautitech.com' },
                { name: 'Ricardo Silva', role: 'technician', email: 'ricardo@nautitech.com' },
                { name: 'André Costa', role: 'technician', email: 'andre@nautitech.com' },
                { name: 'Fernanda Lima', role: 'financial', email: 'fernanda@nautitech.com' },
              ].map(u => (
                <div key={u.email} className="flex items-center justify-between p-3 rounded-lg bg-muted/50 border">
                  <div>
                    <p className="text-sm font-medium">{u.name}</p>
                    <p className="text-xs text-muted-foreground">{u.email}</p>
                  </div>
                  <span className="text-xs font-medium px-2 py-1 rounded bg-primary/10 text-primary">{(t.roles as Record<string, string>)[u.role]}</span>
                </div>
              ))}
            </div>
          </div>
        </TabsContent>

        <TabsContent value="language" className="mt-4 space-y-4">
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
        </TabsContent>

        <TabsContent value="currency" className="mt-4 space-y-4">
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
        </TabsContent>

        {/* Card Fees Tab */}
        <TabsContent value="cardFees" className="mt-4 space-y-4">
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
        </TabsContent>

        {/* Terms Tab */}
        <TabsContent value="terms" className="mt-4 space-y-4">
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
        </TabsContent>
      </Tabs>
    </div>
  );
}
