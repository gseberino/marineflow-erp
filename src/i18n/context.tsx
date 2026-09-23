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

/**
 * Inglês por cima do português: o que en não tiver, sai em pt-BR (D31, 17/09/2026). Antes
 * uma chave nova sem tradução aparecia como `undefined` na tela em inglês.
 */
function completar(base: Record<string, unknown>, parcial: Record<string, unknown> | undefined): Record<string, unknown> {
  const saida: Record<string, unknown> = { ...base };
  for (const [k, v] of Object.entries(parcial ?? {})) {
    const b = base[k];
    saida[k] = v !== null && typeof v === 'object' && b !== null && typeof b === 'object'
      ? completar(b as Record<string, unknown>, v as Record<string, unknown>)
      : v;
  }
  return saida;
}

const translations: Record<Locale, TranslationKeys> = {
  en: completar(ptBR as unknown as Record<string, unknown>, en as unknown as Record<string, unknown>) as unknown as TranslationKeys,
  'pt-BR': ptBR,
};

const LOCALE_KEY = 'nautitech-locale';
const CURRENCY_KEY = 'nautitech-currency';

function getStoredLocale(): Locale {
  try {
    const stored = localStorage.getItem(LOCALE_KEY);
    if (stored === 'en' || stored === 'pt-BR') return stored;
  } catch { /* sem localStorage: usa o padrão */ }
  return 'pt-BR';
}

function getStoredCurrency(): CurrencyConfig {
  try {
    const stored = localStorage.getItem(CURRENCY_KEY);
    if (stored) return JSON.parse(stored);
  } catch { /* sem localStorage: usa o padrão */ }
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

  /**
   * O fuso da EMPRESA, não o do aparelho.
   *
   * As datas deste sistema são fatos com hora marcada no Brasil: a autorização de uma
   * NF-e, o vencimento de uma conta, o horário de um atendimento. Sem fixar o fuso, quem
   * abrisse o sistema de um celular configurado em outro fuso — ou num servidor em UTC —
   * veria a data do documento trocada por um dia.
   *
   * Não é hipótese: a NFS-e 1/4 foi emitida 27/08/2026 às 22h22 e é gravada como
   * "2026-08-28T01:22Z". Em UTC ela aparece como 28/08, discordando do próprio XML. Foi
   * assim que o teste da lista de notas quebrou no CI (que roda em UTC) enquanto passava
   * em qualquer máquina no Brasil.
   */
  const FUSO_DA_EMPRESA = 'America/Sao_Paulo';

  /**
   * Um VENCIMENTO não é um instante: é um dia.
   *
   * O banco guarda `due_date` como DATE e o PostgREST devolve "2026-09-18". O JavaScript
   * lê essa string como meia-noite UTC, e qualquer fuso a oeste de Greenwich — o Brasil
   * inteiro — exibe o dia ANTERIOR. Era o "um dia a menos" que aparecia nas parcelas: a
   * NF-e 2/25 tem a primeira duplicata em 18/09/2026 no DANFE e a tela mostrava 17/09.
   *
   * O defeito não vinha do fuso escolhido (sem ele o erro é o mesmo): vinha de tratar um
   * dia do calendário como um ponto no tempo. Datas sem hora são remontadas no fuso local,
   * o que as mantém no dia que está escrito. Instantes de verdade (com hora e zona)
   * continuam convertidos para o fuso da empresa, que é onde os fatos aconteceram.
   */
  const SO_DATA = /^\d{4}-\d{2}-\d{2}$/;
  const comoDiaLocal = (date: string) => {
    if (!SO_DATA.test(date)) return new Date(date);
    const [ano, mes, dia] = date.split('-').map(Number);
    return new Date(ano, mes - 1, dia);
  };
  /** Data sem hora já É o dia: convertê-la de fuso é o que a movia. */
  const fusoDe = (date: string) => (SO_DATA.test(date) ? undefined : FUSO_DA_EMPRESA);

  const formatDate = useCallback((date: string) => {
    const d = comoDiaLocal(date);
    if (locale === 'pt-BR') {
      return d.toLocaleDateString('pt-BR', {
        day: '2-digit', month: '2-digit', year: 'numeric', timeZone: fusoDe(date),
      });
    }
    return d.toLocaleDateString('en-US', {
      month: 'short', day: 'numeric', year: 'numeric', timeZone: fusoDe(date),
    });
  }, [locale]);

  const formatDateTime = useCallback((date: string) => {
    const d = comoDiaLocal(date);
    if (locale === 'pt-BR') {
      return d.toLocaleDateString('pt-BR', {
        day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
        timeZone: fusoDe(date),
      });
    }
    return d.toLocaleDateString('en-US', {
      month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: fusoDe(date),
    });
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
