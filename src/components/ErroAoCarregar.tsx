import { AlertTriangle } from 'lucide-react';
import { Button } from '@/components/ui/button';

/**
 * Estado de erro de leitura: "Não consegui carregar … — tente de novo."
 *
 * Existe para que leitura que falha NÃO vire zero, lista vazia ou formulário com o padrão
 * (19/11/2026): R$ 0,00 no painel e "Salvar" num formulário que não leu o que estava gravado
 * parecem verdade e não são.
 */
export function ErroAoCarregar({
  oQue,
  onTentarDeNovo,
  tentando = false,
  className = '',
}: {
  /** Complemento de "Não consegui carregar …" (ex.: "as configurações fiscais"). */
  oQue: string;
  onTentarDeNovo?: () => void;
  tentando?: boolean;
  className?: string;
}) {
  return (
    <div
      role="alert"
      className={`flex flex-wrap items-center justify-between gap-2 rounded-xl border border-destructive/40 bg-destructive/5 p-3 text-sm ${className}`}
    >
      <span className="flex min-w-0 items-center gap-2 text-destructive">
        <AlertTriangle className="h-4 w-4 shrink-0" />
        <span className="min-w-0 break-words">Não consegui carregar {oQue} — tente de novo.</span>
      </span>
      {onTentarDeNovo && (
        <Button size="sm" variant="outline" disabled={tentando} onClick={onTentarDeNovo}>
          {tentando ? 'Carregando…' : 'Tentar de novo'}
        </Button>
      )}
    </div>
  );
}
