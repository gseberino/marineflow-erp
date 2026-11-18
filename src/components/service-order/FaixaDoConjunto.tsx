// Faixa no documento que está num conjunto ("Agrupar para o cliente"): cita os outros documentos e oferece enviar ao
// cliente (um PDF só) e desfazer. Desfazer não pede confirmação: nada se perde — os documentos nunca mudaram.
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { toast } from 'sonner';
import { Layers, Loader2, Send, Ungroup } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useDesfazerConjunto } from '@/hooks/use-conjunto';
import { type Conjunto, situacaoDoDocumento } from '@/lib/conjunto';
import { EnviarConjuntoDialog } from './EnviarConjuntoDialog';

interface Props {
  conjunto: Conjunto;
  /** O documento aberto na tela (não vira link). */
  documentoId: string;
  /** Admin/financeiro: enviar e desfazer. */
  podeMexer: boolean;
}

export function FaixaDoConjunto({ conjunto, documentoId, podeMexer }: Props) {
  const desfazer = useDesfazerConjunto();
  const [enviarAberto, setEnviarAberto] = useState(false);
  const docs = conjunto.documentos.filter((d) => d.ativo);

  async function desfazerAgora() {
    try {
      await desfazer.mutateAsync(conjunto.id);
      toast.success(`Conjunto ${conjunto.nome} desfeito. Os documentos seguem como estavam.`);
    } catch (e) {
      toast.error((e as Error).message || 'Não deu para desfazer.');
    }
  }

  return (
    <div className="flex flex-wrap items-start justify-between gap-3 rounded-lg border border-sky-200 bg-sky-50 p-4 dark:border-sky-900 dark:bg-sky-950/40">
      <div className="flex min-w-0 items-start gap-2">
        <Layers className="mt-0.5 h-5 w-5 shrink-0 text-sky-700 dark:text-sky-300" />
        <div className="min-w-0">
          <p className="text-sm font-medium text-sky-900 dark:text-sky-100">Apresentado ao cliente junto com:</p>
          <ul className="mt-1 space-y-0.5 text-sm">
            {docs.filter((d) => d.id !== documentoId).map((d) => (
              <li key={d.id} className="break-words">
                <Link to={`/v2/service-orders/${d.id}`} className="font-medium underline underline-offset-2">{d.numero}</Link>
                <span className="text-muted-foreground"> · {situacaoDoDocumento(d)}</span>
              </li>
            ))}
          </ul>
          <p className="mt-1 text-xs text-muted-foreground">Cada documento continua com a sua execução, sinal, assinatura e nota.</p>
        </div>
      </div>
      {podeMexer && (
        <div className="flex flex-wrap gap-2">
          <Button size="sm" onClick={() => setEnviarAberto(true)} className="gap-1.5">
            <Send className="h-4 w-4" /> Enviar ao cliente
          </Button>
          <Button size="sm" variant="outline" onClick={desfazerAgora} disabled={desfazer.isPending} className="gap-1.5">
            {desfazer.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Ungroup className="h-4 w-4" />} Desfazer
          </Button>
        </div>
      )}
      {enviarAberto && (
        <EnviarConjuntoDialog aberto={enviarAberto} onFechar={() => setEnviarAberto(false)} conjunto={conjunto} />
      )}
    </div>
  );
}
