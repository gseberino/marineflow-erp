import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { ChevronUp, ChevronDown } from 'lucide-react';
import { useState } from 'react';

export interface FinancialWaterfallLine {
  label: string;
  value: number;
  negative?: boolean;
}

interface Props {
  grandTotal: number;
  waterfall: FinancialWaterfallLine[];
  balance?: number | null;
  formatCurrency: (n: number) => string;
  onOpenFinancial: () => void;
  // Ação de salvar consolidada aqui (Onda 4) — substitui o antigo botão
  // "Sticky floating Save" que existia separado, evitando duas barras
  // fixas competindo pelo mesmo espaço no rodapé da tela.
  onSave?: () => void;
  saving?: boolean;
  showSave?: boolean;
}

/**
 * Onda 4 — barra de resumo financeiro fixa (sticky no rodapé da tela) para o
 * ServiceOrderForm. Mostra o total ao vivo enquanto a equipe monta a OS, com o
 * mesmo waterfall exibido ao cliente em PublicServiceOrderView, para que o
 * valor final nunca seja surpresa.
 */
export function ServiceOrderFinancialSummary({ grandTotal, waterfall, balance, formatCurrency, onOpenFinancial, onSave, saving, showSave }: Props) {
  const [expanded, setExpanded] = useState(false);
  const visibleLines = waterfall.filter((l) => l.value !== 0);

  return (
    <div className="sticky bottom-0 z-30 border-t bg-card/95 backdrop-blur supports-[backdrop-filter]:bg-card/80 shadow-[0_-2px_8px_rgba(0,0,0,0.06)]">
      {expanded && visibleLines.length > 0 && (
        <div className="px-4 pt-2 pb-1 space-y-0.5 text-xs border-b max-h-40 overflow-y-auto">
          {visibleLines.map((l) => (
            <div key={l.label} className="flex justify-between">
              <span className="text-muted-foreground">{l.label}</span>
              <span className={l.negative ? 'text-destructive' : ''}>
                {l.negative ? '− ' : ''}{formatCurrency(Math.abs(l.value))}
              </span>
            </div>
          ))}
        </div>
      )}
      <div className="flex items-center gap-3 px-4 py-2">
        <button
          type="button"
          onClick={() => setExpanded((v) => !v)}
          className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
          title="Ver composição do total"
        >
          {expanded ? <ChevronDown className="h-3.5 w-3.5" /> : <ChevronUp className="h-3.5 w-3.5" />}
          Composição
        </button>
        <div className="flex-1" />
        {balance != null && balance > 0 && (
          <Badge variant="outline" className="text-amber-700 border-amber-300 bg-amber-50">
            Saldo em aberto: {formatCurrency(balance)}
          </Badge>
        )}
        <button
          type="button"
          onClick={onOpenFinancial}
          className="flex items-baseline gap-2 hover:opacity-80 transition-opacity"
          title="Ir para Composição Financeira"
        >
          <span className="text-xs text-muted-foreground">Total</span>
          <span className="text-lg font-bold text-accent tabular-nums">{formatCurrency(grandTotal)}</span>
        </button>
        {showSave && onSave && (
          <Button
            onClick={onSave}
            disabled={saving}
            size="sm"
            className="bg-accent text-accent-foreground hover:bg-accent/90 shadow-md shadow-accent/30"
          >
            {saving ? 'Salvando...' : 'Salvar'}
          </Button>
        )}
      </div>
    </div>
  );
}
