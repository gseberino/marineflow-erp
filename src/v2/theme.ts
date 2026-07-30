/* ── Tema global v2 (Estaleiro Claro / Ponte de Comando) ─────────────────────
   O redesign vale para o ERP inteiro: a classe .themev2 + data-mode vivem no
   <html>, então TODAS as telas (v1 e v2) e os diálogos portalizados (Radix em
   <body>) herdam os tokens. O modo persiste na mesma chave que o V2Shell já
   usava (mf-v2-theme), preservando a escolha de quem já alternou o tema. */

export type ThemeMode = 'light' | 'dark';

const STORAGE_KEY = 'mf-v2-theme';
export const THEME_EVENT = 'mf-theme-change';

export function getThemeMode(): ThemeMode {
  try {
    return localStorage.getItem(STORAGE_KEY) === 'dark' ? 'dark' : 'light';
  } catch {
    return 'light';
  }
}

export function applyThemeMode(mode: ThemeMode): void {
  const el = document.documentElement;
  el.classList.add('themev2');
  el.setAttribute('data-mode', mode);
  try {
    localStorage.setItem(STORAGE_KEY, mode);
  } catch {
    /* modo privado sem storage: tema vale só para a sessão */
  }
  window.dispatchEvent(new CustomEvent<ThemeMode>(THEME_EVENT, { detail: mode }));
}

export function toggleThemeMode(): ThemeMode {
  const next: ThemeMode = getThemeMode() === 'light' ? 'dark' : 'light';
  applyThemeMode(next);
  return next;
}

/** Chamar uma vez no boot (main.tsx), antes do primeiro render. */
export function initGlobalTheme(): void {
  const el = document.documentElement;
  el.classList.add('themev2');
  el.setAttribute('data-mode', getThemeMode());
}
