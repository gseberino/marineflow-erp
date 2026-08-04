import { useMemo, useState } from 'react';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Camera, ClipboardPen, Loader2, Ruler, ShieldAlert } from 'lucide-react';
import { toast } from 'sonner';
import {
  useServiceOrderSteps, useCompleteStep, groupStepsByBlock, formatMinutes,
  type ServiceOrderStep,
} from '@/hooks/use-service-steps';

/**
 * Lançamento da folha impressa.
 *
 * Quem trabalha com a folha na mão não cronometra no sistema: anota o horário a
 * lápis e volta com o papel preenchido. Marcar passo a passo no Modo Foco
 * depois é lento e — pior — grava tempo ZERO, porque a duração vinha só do
 * cronômetro. Passo sem tempo não vira apontamento de hora nem caso utilizável;
 * o dia de trabalho entrava no sistema pela metade.
 *
 * Aqui a folha é transcrita de uma vez: uma linha por passo, um campo de
 * minutos, e o que ficou em branco continua pendente. Só o que tem minutos é
 * lançado — em branco significa "não fiz", não "fiz em zero minuto".
 */
export function SheetEntryDialog({
  serviceOrderId, orderNumber, open, onOpenChange,
}: {
  serviceOrderId: string;
  orderNumber?: string | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const { data: steps = [], isLoading } = useServiceOrderSteps(open ? serviceOrderId : undefined);
  const complete = useCompleteStep();

  const [minutos, setMinutos] = useState<Record<string, string>>({});
  const [medidas, setMedidas] = useState<Record<string, string>>({});
  const [salvando, setSalvando] = useState(false);

  const pendentes = useMemo(() => steps.filter((s) => s.status === 'pending'), [steps]);
  const grupos = useMemo(() => groupStepsByBlock(pendentes), [pendentes]);

  const preenchidos = useMemo(
    () => pendentes.filter((s) => Number(minutos[s.id]) > 0),
    [pendentes, minutos],
  );
  const totalMinutos = useMemo(
    () => preenchidos.reduce((soma, s) => soma + Number(minutos[s.id] || 0), 0),
    [preenchidos, minutos],
  );

  /** Passo que pede medição só entra com o valor lido — igual ao Modo Foco. */
  function faltaMedida(step: ServiceOrderStep): boolean {
    return !!step.requires_measure && !medidas[step.id];
  }

  const bloqueados = preenchidos.filter(faltaMedida);

  async function lancar() {
    if (bloqueados.length > 0) {
      toast.error(`${bloqueados.length} passo(s) preenchido(s) pedem a medição anotada na folha.`);
      return;
    }
    setSalvando(true);
    let ok = 0;
    try {
      for (const step of preenchidos) {
        await complete.mutateAsync({
          step,
          minutes: Number(minutos[step.id]),
          ...(medidas[step.id] ? { measureValue: Number(medidas[step.id]) } : {}),
        });
        ok++;
      }
      toast.success(`${ok} passo(s) lançados, ${formatMinutes(totalMinutos)} no total.`);
      setMinutos({});
      setMedidas({});
      onOpenChange(false);
    } catch (e: any) {
      toast.error(
        ok > 0
          ? `${ok} lançados e o restante falhou: ${e?.message || 'erro'}`
          : e?.message || 'Erro ao lançar a folha',
      );
    } finally {
      setSalvando(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] max-w-3xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>
            Lançar folha {orderNumber ? `— ${orderNumber}` : ''}
          </DialogTitle>
        </DialogHeader>

        <p className="text-sm text-muted-foreground">
          Copie da folha o tempo de cada passo. O que ficar em branco continua pendente — em branco
          quer dizer “não fiz”, não “fiz em zero minuto”.
        </p>

        {isLoading && (
          <p className="flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" /> Carregando roteiro…
          </p>
        )}

        {!isLoading && pendentes.length === 0 && (
          <p className="text-sm text-muted-foreground">
            Não há passo pendente nesta OS — tudo já foi lançado.
          </p>
        )}

        <div className="space-y-4">
          {grupos.map((g) => (
            <div key={g.block} className="space-y-1.5">
              <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
                {g.block}
              </p>
              {g.steps.map((step) => (
                <div key={step.id} className="flex flex-wrap items-start gap-2 rounded-md border px-2.5 py-2">
                  <span className="mt-1.5 w-5 shrink-0 text-[11px] tabular-nums text-muted-foreground">
                    {step.seq}
                  </span>
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-1.5">
                      <span className="text-sm">{step.title}</span>
                      {step.kind === 'safety' && <ShieldAlert className="h-3.5 w-3.5 text-red-600" />}
                      {step.requires_photo && <Camera className="h-3.5 w-3.5 text-muted-foreground" />}
                      {step.standard_minutes ? (
                        <span className="text-[11px] tabular-nums text-muted-foreground">
                          previsto {formatMinutes(step.standard_minutes)}
                        </span>
                      ) : null}
                    </div>
                    {step.requires_measure && (
                      <div className="mt-1 flex flex-wrap items-center gap-1.5">
                        <Ruler className="h-3.5 w-3.5 text-muted-foreground" />
                        <Input
                          value={medidas[step.id] ?? ''}
                          onChange={(e) => setMedidas((m) => ({ ...m, [step.id]: e.target.value }))}
                          placeholder={`medição ${step.measure_unit || ''}`.trim()}
                          inputMode="decimal"
                          className={`h-7 w-32 text-xs ${
                            faltaMedida(step) && Number(minutos[step.id]) > 0
                              ? 'border-red-500'
                              : ''
                          }`}
                        />
                      </div>
                    )}
                  </div>
                  <Input
                    value={minutos[step.id] ?? ''}
                    onChange={(e) => setMinutos((m) => ({ ...m, [step.id]: e.target.value }))}
                    placeholder="min"
                    inputMode="numeric"
                    className="h-8 w-20 shrink-0 text-sm tabular-nums"
                  />
                </div>
              ))}
            </div>
          ))}
        </div>

        {pendentes.length > 0 && (
          <div className="sticky bottom-0 flex flex-wrap items-center justify-between gap-2 border-t bg-background pt-3">
            <span className="text-sm tabular-nums text-muted-foreground">
              {preenchidos.length} de {pendentes.length} passos ·{' '}
              <strong className="text-foreground">{formatMinutes(totalMinutos)}</strong>
            </span>
            <div className="flex items-center gap-2">
              {bloqueados.length > 0 && (
                <Badge variant="outline" className="border-red-500 text-[10px] text-red-700 dark:text-red-400">
                  {bloqueados.length} sem medição
                </Badge>
              )}
              <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={salvando}>
                Cancelar
              </Button>
              <Button onClick={lancar} disabled={preenchidos.length === 0 || salvando}>
                {salvando ? (
                  <><Loader2 className="mr-1.5 h-4 w-4 animate-spin" /> Lançando…</>
                ) : (
                  <><ClipboardPen className="mr-1.5 h-4 w-4" /> Lançar {preenchidos.length} passo(s)</>
                )}
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
