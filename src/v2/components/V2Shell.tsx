import { ReactNode, useEffect, useState } from 'react';
import { Moon, Search, Sun } from 'lucide-react';
import { V2CommandPalette } from './V2CommandPalette';
import { getThemeMode, THEME_EVENT, toggleThemeMode, type ThemeMode } from '@/v2/theme';

/**
 * Casca das páginas v2. O tema agora é GLOBAL (classe .themev2 no <html>,
 * ver src/v2/theme.ts) — esta casca só cuida do layout, dos botões flutuantes
 * (busca ⌘K e alternador ☀/🌙) e da paleta de comandos. Vários alternadores
 * (aqui e no header do AppLayout) ficam em sincronia via THEME_EVENT.
 */
export function V2Shell({ children, standalone = false }: { children: ReactNode; standalone?: boolean }) {
  const [mode, setMode] = useState<ThemeMode>(getThemeMode);

  useEffect(() => {
    const onChange = (e: Event) => setMode((e as CustomEvent<ThemeMode>).detail);
    window.addEventListener(THEME_EVENT, onChange);
    return () => window.removeEventListener(THEME_EVENT, onChange);
  }, []);

  const toggle = () => toggleThemeMode();

  return (
    <div
      className={
        standalone
          ? 'min-h-screen bg-background p-4 text-foreground transition-colors lg:p-6'
          : '-m-4 min-h-full bg-background p-4 text-foreground transition-colors lg:-m-6 lg:p-6'
      }
    >
      {children}
      <div className="fixed bottom-5 left-5 z-40 flex flex-col gap-2">
        <button
          type="button"
          onClick={() => document.dispatchEvent(new KeyboardEvent('keydown', { key: 'k', ctrlKey: true }))}
          aria-label="Abrir busca e navegação (Ctrl+K)"
          title="Buscar e navegar (Ctrl+K)"
          className="flex h-11 w-11 items-center justify-center rounded-full border bg-card text-muted-foreground shadow-lg transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <Search className="h-5 w-5" />
        </button>
        <button
          type="button"
          onClick={toggle}
          aria-label={mode === 'light' ? 'Mudar para tema escuro' : 'Mudar para tema claro'}
          title={mode === 'light' ? 'Tema escuro (Ponte de Comando)' : 'Tema claro (Estaleiro Claro)'}
          className="flex h-11 w-11 items-center justify-center rounded-full border bg-card text-muted-foreground shadow-lg transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          {mode === 'light' ? <Moon className="h-5 w-5" /> : <Sun className="h-5 w-5" />}
        </button>
      </div>
      <V2CommandPalette onToggleTheme={toggle} mode={mode} />
    </div>
  );
}
