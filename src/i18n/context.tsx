import { createContext, useContext, useState, useCallback, ReactNode, useEffect } from 'react';
import { en, type TranslationKeys } from './en';
import { ptBR } from './pt-BR';

export type Locale = 'en' | 'pt-BR';

interface CurrencyConfig {
  baseCurrency: string;
  displayCurrency: string;
}

interface I18nContextType {
  locale: Locale;
  setLocale: (locale: Locale) => void;
  t: TranslationKeys;
  formatCurrency: (value: number, currencyCode?: string) => string;
  formatDate: (date: string) => string;
  formatDateTime: (date: string) => string;
  formatNumber: (value: number) => string;
  currency: CurrencyConfig;
  setCurrency: (config: Partial<CurrencyConfig>) => void;
}

const translations: Record<Locale, TranslationKeys> = { en, 'pt-BR': ptBR };

const LOCALE_KEY = 'nautitech-locale';
const CURRENCY_KEY = 'nautitech-currency';

function getStoredLocale(): Locale {
  try {
    const stored = localStorage.getItem(LOCALE_KEY);
    if (stored === 'en' || stored === 'pt-BR') return stored;
  } catch {}
  return 'pt-BR';
}

function getStoredCurrency(): CurrencyConfig {
  try {
    const stored = localStorage.getItem(CURRENCY_KEY);
    if (stored) return JSON.parse(stored);
  } catch {}
  return { baseCurrency: 'BRL', displayCurrency: 'BRL' };
}

const I18nContext = createContext<I18nContextType | null>(null);

export function I18nProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(getStoredLocale);
  const [currency, setCurrencyState] = useState<CurrencyConfig>(getStoredCurrency);

  const setLocale = useCallback((l: Locale) => {
    setLocaleState(l);
    localStorage.setItem(LOCALE_KEY, l);
  }, []);

  const setCurrency = useCallback((config: Partial<CurrencyConfig>) => {
    setCurrencyState(prev => {
      const next = { ...prev, ...config };
      localStorage.setItem(CURRENCY_KEY, JSON.stringify(next));
      return next;
    });
  }, []);

  const formatCurrency = useCallback((value: number, currencyCode?: string) => {
    const code = currencyCode || currency.displayCurrency;
    const loc = locale === 'pt-BR' ? 'pt-BR' : 'en-US';
    return new Intl.NumberFormat(loc, { style: 'currency', currency: code }).format(value);
  }, [locale, currency.displayCurrency]);

  const formatDate = useCallback((date: string) => {
    const d = new Date(date);
    if (locale === 'pt-BR') {
      return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric' });
    }
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  }, [locale]);

  const formatDateTime = useCallback((date: string) => {
    const d = new Date(date);
    if (locale === 'pt-BR') {
      return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
    }
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
  }, [locale]);

  const formatNumber = useCallback((value: number) => {
    const loc = locale === 'pt-BR' ? 'pt-BR' : 'en-US';
    return new Intl.NumberFormat(loc).format(value);
  }, [locale]);

  const t = translations[locale];

  return (
    <I18nContext.Provider value={{ locale, setLocale, t, formatCurrency, formatDate, formatDateTime, formatNumber, currency, setCurrency }}>
      {children}
    </I18nContext.Provider>
  );
}

export function useI18n() {
  const ctx = useContext(I18nContext);
  if (!ctx) throw new Error('useI18n must be used within I18nProvider');
  return ctx;
}
