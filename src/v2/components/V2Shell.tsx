import { ReactNode, useState } from 'react';
import { Moon, Sun } from 'lucide-react';

type Mode = 'light' | 'dark';
const STORAGE_KEY = 'mf-v2-theme';

/**
 * Casca das páginas v2: aplica o escopo .themev2 (Estaleiro Claro / Ponte de
 * Comando) e oferece o alternador ☀/🌙 persistido em localStorage — interino
 * até o tema migrar para o AppLayout na aposentadoria das telas v1.
 * Limitação conhecida: diálogos v1 portalizados (Radix) ficam fora do escopo
 * e seguem o tema v1 até a migração global.
 */
export function V2Shell({ children }: { children: ReactNode }) {
  const [mode, setMode] = useState<Mode>(() =>
    typeof localStorage !== 'undefined' && localStorage.getItem(STORAGE_KEY) === 'dark' ? 'dark' : 'light',
  );

  const toggle = () =>
    setMode((m) => {
      const next: Mode = m === 'light' ? 'dark' : 'light';
      localStorage.setItem(STORAGE_KEY, next);
      return next;
    });

  return (
    <div className="themev2 -m-4 min-h-full bg-background p-4 text-foreground transition-colors lg:-m-6 lg:p-6" data-mode={mode}>
      {children}
      <button
        type="button"
        onClick={toggle}
        aria-label={mode === 'light' ? 'Mudar para tema escuro' : 'Mudar para tema claro'}
        title={mode === 'light' ? 'Tema escuro (Ponte de Comando)' : 'Tema claro (Estaleiro Claro)'}
        className="fixed bottom-5 left-5 z-40 flex h-11 w-11 items-center justify-center rounded-full border bg-card text-muted-foreground shadow-lg transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      >
        {mode === 'light' ? <Moon className="h-5 w-5" /> : <Sun className="h-5 w-5" />}
      </button>
    </div>
  );
}
