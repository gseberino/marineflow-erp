// "Agrupar para o cliente" F2 (decisão 5A do dono): o orçamento complementar aprovado junto vira OS PRÓPRIA, marcada
// "complementa a OS-X" — nunca entra na OS assinada. A faixa mostra a ligação dos dois lados, mesmo depois de o conjunto
// ser desfeito. Sem marca (ou com a migration ainda não aplicada), não aparece.
import { Link } from 'react-router-dom';
import { Link2 } from 'lucide-react';
import { useComplementos } from '@/hooks/use-conjunto';

export function FaixaDoComplemento({ documentoId }: { documentoId: string }) {
  const { data } = useComplementos(documentoId);
  if (!data || (!data.complementa && data.complementadaPor.length === 0)) return null;
  return (
    <div className="flex items-start gap-2 rounded-lg border border-violet-200 bg-violet-50 p-3 text-sm dark:border-violet-900 dark:bg-violet-950/40">
      <Link2 className="mt-0.5 h-4 w-4 shrink-0 text-violet-700 dark:text-violet-300" />
      <div className="min-w-0 space-y-0.5 break-words">
        {data.complementa && (
          <p>
            Complementa a{' '}
            <Link to={`/v2/service-orders/${data.complementa.id}`} className="font-medium underline underline-offset-2">
              {data.complementa.numero}
            </Link>
            <span className="text-muted-foreground">: serviço complementar aprovado junto, com sinal e cobrança próprios.</span>
          </p>
        )}
        {data.complementadaPor.length > 0 && (
          <p>
            Complementada por{' '}
            {data.complementadaPor.map((c, i) => (
              <span key={c.id}>
                {i > 0 && (i === data.complementadaPor.length - 1 ? ' e ' : ', ')}
                <Link to={`/v2/service-orders/${c.id}`} className="font-medium underline underline-offset-2">{c.numero}</Link>
              </span>
            ))}
            <span className="text-muted-foreground"> (cada uma com o próprio sinal e a própria cobrança).</span>
          </p>
        )}
      </div>
    </div>
  );
}
