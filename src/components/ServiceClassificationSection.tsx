import { useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { Check, ChevronDown, ChevronRight, Loader2, Tags } from 'lucide-react';
import { toast } from 'sonner';
import {
  useServicesToReview, useConfirmClassification, SISTEMAS, VERBOS,
  SYSTEM_LABEL, VERB_LABEL, type ClassifiedService,
} from '@/hooks/use-service-classification';

/**
 * Fila de revisão da classificação do catálogo.
 *
 * Só aparece o que a IA marcou com confiança abaixo de 0.9 — ela dizendo
 * "olha isso". Confirmar sem mudar nada também é resposta: vira
 * classified_by='human' e sai da fila para sempre.
 */
export function ServiceClassificationSection() {
  const { data: servicos = [], isLoading } = useServicesToReview();
  const confirm = useConfirmClassification();

  const [aberto, setAberto] = useState(false);
  const [edicoes, setEdicoes] = useState<Record<string, { system: string | null; verb: string | null }>>({});

  function valor(s: ClassifiedService) {
    return edicoes[s.id] ?? { system: s.service_system, verb: s.service_verb };
  }

  function confirmar(s: ClassifiedService) {
    const v = valor(s);
    confirm.mutate(
      { service: s, system: v.system, verb: v.verb },
      {
        onSuccess: () => toast.success('Classificação confirmada.'),
        onError: (e: any) => toast.error(e?.message || 'Erro ao confirmar'),
      },
    );
  }

  if (isLoading) {
    return (
      <p className="flex items-center gap-2 text-sm text-muted-foreground">
        <Loader2 className="h-4 w-4 animate-spin" /> Carregando classificação…
      </p>
    );
  }

  if (servicos.length === 0) return null;

  return (
    <section className="space-y-3">
      <div className="flex items-start gap-2">
        <Tags className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
        <div className="min-w-0">
          <h2 className="text-sm font-semibold">Classificação a conferir</h2>
          <p className="text-xs text-muted-foreground">
            O sistema decide qual preparação e qual fechamento o serviço recebe; o verbo decide o
            corpo. Estes são os que a IA classificou sem certeza — os demais ela resolveu sozinha.
          </p>
        </div>
      </div>

      <Card className="overflow-hidden">
        <button
          className="flex w-full items-center justify-between gap-3 p-3 text-left transition-colors hover:bg-muted/50"
          onClick={() => setAberto((a) => !a)}
        >
          <div className="flex min-w-0 items-center gap-2">
            {aberto ? <ChevronDown className="h-4 w-4 shrink-0" /> : <ChevronRight className="h-4 w-4 shrink-0" />}
            <span className="truncate text-sm font-medium">
              {servicos.length} serviço(s) para conferir
            </span>
          </div>
          <Badge className="shrink-0 bg-primary text-[10px] text-primary-foreground">
            a revisar
          </Badge>
        </button>

        {aberto && (
          <div className="divide-y border-t">
            {servicos.map((s) => {
              const v = valor(s);
              const conf = s.classification_confidence ?? 0;
              return (
                <div key={s.id} className="space-y-2 p-3">
                  <div className="flex flex-wrap items-center gap-1.5">
                    <span className="text-sm font-medium">{s.name}</span>
                    <Badge
                      variant="outline"
                      className={`text-[10px] ${conf <= 0.3 ? 'border-red-500 text-red-700 dark:text-red-400' : ''}`}
                    >
                      confiança {conf.toFixed(1)}
                    </Badge>
                  </div>

                  <div className="flex flex-wrap items-center gap-2">
                    <Select
                      value={v.system ?? ''}
                      onValueChange={(x) => setEdicoes((e) => ({ ...e, [s.id]: { ...v, system: x } }))}
                    >
                      <SelectTrigger className="h-9 w-full sm:w-56">
                        <SelectValue placeholder="Sistema" />
                      </SelectTrigger>
                      <SelectContent>
                        {SISTEMAS.map((x) => (
                          <SelectItem key={x} value={x}>{SYSTEM_LABEL[x] ?? x}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>

                    <Select
                      value={v.verb ?? ''}
                      onValueChange={(x) => setEdicoes((e) => ({ ...e, [s.id]: { ...v, verb: x } }))}
                    >
                      <SelectTrigger className="h-9 w-full sm:w-52">
                        <SelectValue placeholder="Verbo" />
                      </SelectTrigger>
                      <SelectContent>
                        {VERBOS.map((x) => (
                          <SelectItem key={x} value={x}>{VERB_LABEL[x] ?? x}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>

                    <Button size="sm" disabled={confirm.isPending} onClick={() => confirmar(s)}>
                      <Check className="mr-1.5 h-3.5 w-3.5" /> Confirmar
                    </Button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </Card>
    </section>
  );
}
