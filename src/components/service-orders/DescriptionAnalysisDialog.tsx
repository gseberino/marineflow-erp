import { useState } from 'react';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { AlertTriangle, ClipboardList, Package, Sparkles } from 'lucide-react';
import type { DescriptionAnalysis } from '@/hooks/use-description-analysis';

/**
 * O que a IA entendeu da descrição, para você confirmar.
 *
 * Tudo aqui é rascunho: os eixos, cada resposta e o que ela achou que são os
 * materiais. A regra que manda é a mesma do resto da ferramenta — a máquina
 * adianta o serviço, a pessoa assina. Por isso cada pré-resposta é editável e
 * as deduzidas vêm marcadas: "alta" é o que o texto diz com todas as letras,
 * "a confirmar" é o que ela deduziu e pode estar errado.
 */
export function DescriptionAnalysisDialog({
  open, onOpenChange, analise, onConfirmar, salvando,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  analise: DescriptionAnalysis | null;
  onConfirmar: (respostas: Array<{ id: string; question: string; answer: string }>) => void;
  salvando?: boolean;
}) {
  const [editadas, setEditadas] = useState<Record<string, string>>({});
  const [descartadas, setDescartadas] = useState<Set<string>>(new Set());

  if (!analise) return null;

  const valor = (id: string, original: string) => editadas[id] ?? original;

  const aceitas = analise.respostas
    .filter((r) => !descartadas.has(r.id))
    .map((r) => ({ id: r.id, question: r.question, answer: valor(r.id, r.answer) }))
    .filter((r) => r.answer.trim());

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[85vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Sparkles className="h-4 w-4 text-primary" /> O que a descrição já respondeu
          </DialogTitle>
          <DialogDescription>
            Confira antes de abrir o levantamento. O que a IA deduziu vem marcado —
            ela lê o texto, mas quem conhece o serviço é você.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <span className="text-muted-foreground">Entendi como:</span>
            {analise.sistema && <Badge variant="secondary">{analise.sistema}</Badge>}
            {analise.verbo && <Badge variant="secondary">{analise.verbo}</Badge>}
            {!analise.sistema && !analise.verbo && (
              <span className="text-muted-foreground">
                não deu para classificar — o levantamento abre do jeito normal
              </span>
            )}
          </div>

          {analise.respostas.length > 0 && (
            <div className="space-y-2">
              <p className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                <ClipboardList className="h-3.5 w-3.5" /> Já respondidas pela descrição
              </p>
              {analise.respostas.map((r) => {
                const fora = descartadas.has(r.id);
                return (
                  <div
                    key={r.id}
                    className={`space-y-1.5 rounded-md border p-2.5 ${
                      fora ? 'opacity-50' : r.certeza === 'media' ? 'border-amber-400 bg-amber-50/50 dark:bg-amber-950/20' : ''
                    }`}
                  >
                    <div className="flex items-start justify-between gap-2">
                      <p className="min-w-0 flex-1 text-xs text-muted-foreground">{r.question}</p>
                      {r.certeza === 'media' && !fora && (
                        <Badge
                          variant="outline"
                          className="shrink-0 gap-1 border-amber-500 text-[10px] text-amber-700 dark:text-amber-400"
                        >
                          <AlertTriangle className="h-3 w-3" /> a confirmar
                        </Badge>
                      )}
                    </div>
                    <Input
                      value={valor(r.id, r.answer)}
                      disabled={fora}
                      onChange={(e) => setEditadas((s) => ({ ...s, [r.id]: e.target.value }))}
                      className="h-8 text-sm"
                    />
                    <button
                      className="text-[11px] text-muted-foreground underline"
                      onClick={() =>
                        setDescartadas((s) => {
                          const n = new Set(s);
                          if (n.has(r.id)) n.delete(r.id); else n.add(r.id);
                          return n;
                        })}
                    >
                      {fora ? 'usar esta resposta' : 'descartar — vou responder no local'}
                    </button>
                  </div>
                );
              })}
            </div>
          )}

          {analise.faltam.length > 0 && (
            <div className="space-y-1 rounded-md border border-dashed p-2.5">
              <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Ainda a responder ({analise.faltam.length})
              </p>
              <ul className="space-y-0.5 text-xs text-muted-foreground">
                {analise.faltam.slice(0, 6).map((q) => <li key={q.id}>· {q.question}</li>)}
              </ul>
            </div>
          )}

          {analise.materiais_citados.length > 0 && (
            <div className="space-y-1.5">
              <p className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                <Package className="h-3.5 w-3.5" /> Materiais que o texto cita
              </p>
              <div className="flex flex-wrap gap-1.5">
                {analise.materiais_citados.map((m) => (
                  <Badge key={m} variant="outline" className="text-[10px]">{m}</Badge>
                ))}
              </div>
              {/* Citação não é lançamento: o texto dizer "dispositivos de
                  proteção" não diz qual, nem quantos. Vira item quando a
                  medida chegar, pelo levantamento. */}
              <p className="text-[11px] text-muted-foreground">
                Servem de lembrete — viram item pelo levantamento, quando houver medida.
              </p>
            </div>
          )}
        </div>

        <div className="flex flex-wrap items-center justify-end gap-2 border-t pt-3">
          <Button variant="ghost" onClick={() => onOpenChange(false)}>Fechar</Button>
          <Button disabled={salvando} onClick={() => onConfirmar(aceitas)}>
            Abrir levantamento com {aceitas.length} resposta(s)
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
