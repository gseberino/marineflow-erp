import { useEffect, useMemo, useState } from 'react';
import { Dialog, DialogContent, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import {
  AlertTriangle, Camera, Check, ChevronRight, Play, ShieldAlert, SkipForward, X, Timer,
} from 'lucide-react';
import { toast } from 'sonner';
import {
  useBlockStep, useCompleteStep, useSkipStep, useStartStep, useStopReasons,
  accumulatedMinutes, formatMinutes, nextStep,
  type ServiceOrderStep,
} from '@/hooks/use-service-steps';

/**
 * Modo Foco do técnico: um passo por vez, botões grandes, relógio correndo.
 * Segue o padrão já validado no produto (agenda/FocusMode.tsx), com três saídas
 * possíveis — feito, não se aplica, travei. Sem a terceira, o técnico honesto
 * trava e o apressado mente.
 */
export function StepFocusMode({
  open, onOpenChange, steps, orderLabel,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  steps: ServiceOrderStep[];
  orderLabel?: string;
}) {
  const current = useMemo(() => nextStep(steps), [steps]);
  const start = useStartStep();
  const complete = useCompleteStep();
  const skip = useSkipStep();
  const block = useBlockStep();
  const { data: reasons = [] } = useStopReasons();

  const [panel, setPanel] = useState<'none' | 'skip' | 'block'>('none');
  const [naReason, setNaReason] = useState('');
  const [blockReason, setBlockReason] = useState('');
  const [blockNote, setBlockNote] = useState('');
  const [measure, setMeasure] = useState('');
  const [tick, setTick] = useState(0);

  // Relógio de parede: só para exibir. O tempo gravado é calculado no fecho,
  // a partir de started_at — assim a aba em segundo plano não distorce nada.
  useEffect(() => {
    if (!open || current?.status !== 'in_progress') return;
    const id = window.setInterval(() => setTick((t) => t + 1), 30_000);
    return () => window.clearInterval(id);
  }, [open, current?.status, current?.id]);

  useEffect(() => {
    setPanel('none');
    setNaReason('');
    setBlockReason('');
    setBlockNote('');
    setMeasure(current?.measure_value != null ? String(current.measure_value) : '');
  }, [current?.id]);

  const position = current ? steps.findIndex((s) => s.id === current.id) + 1 : steps.length;
  const running = current?.status === 'in_progress';
  // Inclui o que já foi acumulado antes de uma pausa — o técnico precisa ver o
  // tempo total do passo, não só o do trecho atual.
  const elapsed = running && current ? (accumulatedMinutes(current) ?? 0) : 0;
  const overrun =
    running && current?.standard_minutes ? elapsed > current.standard_minutes * 1.5 : false;

  function handleComplete() {
    if (!current) return;
    if (current.requires_measure && !measure.trim()) {
      toast.error('Registre a medição antes de concluir este passo.');
      return;
    }
    const value = measure.trim() ? Number(measure.replace(',', '.')) : null;
    if (value !== null && Number.isNaN(value)) {
      toast.error('A medição precisa ser um número.');
      return;
    }
    complete.mutate(
      { step: current, measureValue: value },
      {
        onError: (e: any) => toast.error(e?.message || 'Não deu para concluir o passo'),
        onSuccess: () => setMeasure(''),
      },
    );
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        className="max-w-lg p-0 gap-0 overflow-hidden"
        aria-describedby={undefined}
      >
        {/* Título para leitor de tela: o cabeçalho visual é enxuto de propósito,
            mas o diálogo precisa de nome acessível. */}
        <DialogTitle className="sr-only">
          {current
            ? `Passo ${position} de ${steps.length}: ${current.title}`
            : 'Modo foco — nada pendente no roteiro'}
        </DialogTitle>

        {/* Cabeçalho enxuto: onde estou e quanto falta */}
        <div className="flex items-center justify-between border-b px-4 py-2.5">
          <div className="text-xs text-muted-foreground">
            {orderLabel ? <span className="font-medium text-foreground">{orderLabel}</span> : 'Roteiro'}
            {steps.length > 0 && current && (
              <span className="ml-2 tabular-nums">passo {position} de {steps.length}</span>
            )}
          </div>
          <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => onOpenChange(false)}>
            <X className="h-4 w-4" />
          </Button>
        </div>

        {!current && (
          <div className="px-6 py-12 text-center space-y-2">
            <Check className="h-10 w-10 mx-auto text-emerald-600" />
            <p className="font-semibold">Roteiro concluído</p>
            <p className="text-sm text-muted-foreground">
              Todo passo chegou a um estado final. Pode fechar a OS.
            </p>
            <Button className="mt-3" onClick={() => onOpenChange(false)}>Fechar</Button>
          </div>
        )}

        {current && (
          <div className="px-5 py-5 space-y-4">
            <div className="flex flex-wrap items-center gap-1.5">
              {current.block && (
                <Badge variant="secondary" className="text-[11px]">{current.block}</Badge>
              )}
              {current.kind === 'safety' && (
                <Badge className="bg-red-600 hover:bg-red-600 text-[11px] gap-1">
                  <ShieldAlert className="h-3 w-3" /> Segurança
                </Badge>
              )}
              {current.is_killer && (
                <Badge variant="outline" className="text-[11px] border-amber-500 text-amber-700 dark:text-amber-400">
                  crítico
                </Badge>
              )}
              {current.mode === 'read_do' && (
                <Badge variant="outline" className="text-[11px]">leia e faça</Badge>
              )}
            </div>

            <h2 className="text-xl font-semibold leading-snug">{current.title}</h2>
            {current.detail && (
              <p className="text-sm text-muted-foreground leading-relaxed">{current.detail}</p>
            )}

            <div className="flex items-center gap-3 text-sm">
              {current.standard_minutes != null && (
                <span className="text-muted-foreground">
                  previsto {formatMinutes(current.standard_minutes)}
                </span>
              )}
              {running && (
                <span
                  className={`flex items-center gap-1 tabular-nums font-medium ${
                    overrun ? 'text-amber-600 dark:text-amber-400' : 'text-foreground'
                  }`}
                  data-testid="step-elapsed"
                >
                  <Timer className="h-3.5 w-3.5" /> {formatMinutes(elapsed)}
                  {overrun && <AlertTriangle className="h-3.5 w-3.5" />}
                </span>
              )}
            </div>

            {current.requires_photo && (
              <p className="flex items-center gap-1.5 text-xs text-amber-700 dark:text-amber-400">
                <Camera className="h-3.5 w-3.5" /> Este passo pede foto — tire agora, na aba Fotos da OS.
              </p>
            )}

            {current.requires_measure && (
              <div className="space-y-1">
                <label className="text-xs font-medium" htmlFor="step-measure">
                  Medição {current.measure_unit ? `(${current.measure_unit})` : ''}
                </label>
                <Input
                  id="step-measure"
                  inputMode="decimal"
                  value={measure}
                  onChange={(e) => setMeasure(e.target.value)}
                  placeholder="ex.: 13,1"
                  className="h-11 text-base"
                />
              </div>
            )}

            {panel === 'none' && (
              <div className="space-y-2 pt-1">
                {!running ? (
                  <Button
                    className="w-full h-12 text-base"
                    onClick={() =>
                      start.mutate(
                        { step: current },
                        { onError: (e: any) => toast.error(e?.message || 'Erro ao começar') },
                      )}
                    disabled={start.isPending}
                  >
                    <Play className="h-5 w-5 mr-2" /> Começar
                  </Button>
                ) : (
                  <Button
                    className="w-full h-12 text-base"
                    onClick={handleComplete}
                    disabled={complete.isPending}
                  >
                    <Check className="h-5 w-5 mr-2" /> Feito
                  </Button>
                )}
                <div className="grid grid-cols-2 gap-2">
                  <Button variant="outline" className="h-11" onClick={() => setPanel('skip')}>
                    <SkipForward className="h-4 w-4 mr-1.5" /> Não se aplica
                  </Button>
                  <Button variant="outline" className="h-11" onClick={() => setPanel('block')}>
                    <AlertTriangle className="h-4 w-4 mr-1.5" /> Travei
                  </Button>
                </div>
              </div>
            )}

            {panel === 'skip' && (
              <div className="space-y-2 pt-1">
                <label className="text-xs font-medium" htmlFor="na-reason">
                  Por que não se aplica? (uma linha basta)
                </label>
                <Input
                  id="na-reason"
                  value={naReason}
                  onChange={(e) => setNaReason(e.target.value)}
                  placeholder="ex.: já veio instalado de fábrica"
                  className="h-11"
                  autoFocus
                />
                <div className="grid grid-cols-2 gap-2">
                  <Button variant="ghost" className="h-11" onClick={() => setPanel('none')}>Voltar</Button>
                  <Button
                    className="h-11"
                    disabled={!naReason.trim() || skip.isPending}
                    onClick={() =>
                      skip.mutate(
                        { step: current, reason: naReason },
                        {
                          onError: (e: any) => toast.error(e?.message || 'Erro'),
                          onSuccess: () => setPanel('none'),
                        },
                      )}
                  >
                    Confirmar
                  </Button>
                </div>
              </div>
            )}

            {panel === 'block' && (
              <div className="space-y-2 pt-1">
                <label className="text-xs font-medium">O que travou?</label>
                <Select value={blockReason} onValueChange={setBlockReason}>
                  <SelectTrigger className="h-11">
                    <SelectValue placeholder="Escolha o motivo" />
                  </SelectTrigger>
                  <SelectContent>
                    {reasons.map((r) => (
                      <SelectItem key={r.code} value={r.code}>{r.label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Textarea
                  value={blockNote}
                  onChange={(e) => setBlockNote(e.target.value)}
                  placeholder="Detalhe rápido (opcional) — ajuda quem vai destravar"
                  rows={2}
                />
                <div className="grid grid-cols-2 gap-2">
                  <Button variant="ghost" className="h-11" onClick={() => setPanel('none')}>Voltar</Button>
                  <Button
                    className="h-11"
                    disabled={!blockReason || block.isPending}
                    onClick={() =>
                      block.mutate(
                        { step: current, reasonCode: blockReason, note: blockNote },
                        {
                          onError: (e: any) => toast.error(e?.message || 'Erro'),
                          onSuccess: () => {
                            setPanel('none');
                            toast.success('Escritório avisado. Siga para o próximo passo.');
                          },
                        },
                      )}
                  >
                    Travar passo
                  </Button>
                </div>
              </div>
            )}

            {/* Prévia do que vem depois: reduz a sensação de túnel */}
            {(() => {
              const idx = steps.findIndex((s) => s.id === current.id);
              const upcoming = steps[idx + 1];
              return upcoming ? (
                <p className="flex items-center gap-1 pt-2 text-xs text-muted-foreground border-t">
                  <ChevronRight className="h-3 w-3 mt-2" />
                  <span className="mt-2">a seguir: {upcoming.title}</span>
                </p>
              ) : null;
            })()}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
