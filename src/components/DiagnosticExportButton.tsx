import { useState } from 'react';
import { Bug, Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';
import { useAuth } from '@/hooks/use-auth';
import { buildDiagnosticPackage, downloadDiagnosticFile } from '@/lib/diagnostics';

type Props = {
  variant?: 'header' | 'fallback';
};

export function DiagnosticExportButton({ variant = 'header' }: Props) {
  const { user, session, authReady } = useAuth();
  const [loading, setLoading] = useState(false);

  const handleExport = async () => {
    setLoading(true);
    try {
      const pkg = await buildDiagnosticPackage({ authReady, session, user });
      downloadDiagnosticFile(pkg);
      toast.success('Diagnóstico exportado', {
        description: 'Envie o arquivo JSON ao suporte técnico.',
      });
    } catch (err: any) {
      toast.error('Falha ao exportar diagnóstico', {
        description: err?.message || 'Tente novamente.',
      });
    } finally {
      setLoading(false);
    }
  };

  if (variant === 'fallback') {
    return (
      <button
        onClick={handleExport}
        disabled={loading}
        className="fixed bottom-4 right-4 z-[60] flex items-center gap-2 rounded-full bg-primary px-3 py-2 text-xs font-medium text-primary-foreground shadow-lg hover:opacity-90 disabled:opacity-50"
      >
        {loading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Bug className="h-3.5 w-3.5" />}
        Exportar diagnóstico
      </button>
    );
  }

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          onClick={handleExport}
          disabled={loading}
          aria-label="Exportar diagnóstico"
          className="h-8 w-8"
        >
          {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Bug className="h-4 w-4" />}
        </Button>
      </TooltipTrigger>
      <TooltipContent>Exportar diagnóstico (suporte técnico)</TooltipContent>
    </Tooltip>
  );
}
