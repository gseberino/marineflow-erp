import { useMemo, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import {
  Camera, Check, ChevronDown, ChevronRight, Loader2, Pencil, Ruler,
  ShieldAlert, Sparkles, X,
} from 'lucide-react';
import { toast } from 'sonner';
import {
  useStepTemplates, useApproveTemplate, useRejectTemplate, useUpdateTemplate,
  pendingApproval, groupTemplatesByService, type StepTemplate,
} from '@/hooks/use-step-templates';
import { StepBlocksSection } from '@/components/StepBlocksSection';
import { SurveyQuestionsSection } from '@/components/SurveyQuestionsSection';
import { ServiceClassificationSection } from '@/components/ServiceClassificationSection';
import { formatMinutes } from '@/hooks/use-service-steps';

/**
 * Roteiros padrão do catálogo — onde os rascunhos da IA são revisados e assinados.
 *
 * Um passo por decisão, com o texto editável antes de aprovar. Editar e aprovar
 * é o sinal mais informativo que existe para o aprendizado: quer dizer "a ideia
 * servia, a redação não". Por isso não há "aprovar todos" — aprovação em lote é
 * o mesmo que não revisar, e é assim que passo errado entra no roteiro de todo
 * mundo.
 */
export default function StepTemplatesPage() {
  const { data: templates = [], isLoading } = useStepTemplates();
  const approve = useApproveTemplate();
  const reject = useRejectTemplate();
  const update = useUpdateTemplate();

  const [aberto, setAberto] = useState<Record<string, boolean>>({});
  const [editando, setEditando] = useState<string | null>(null);
  const [rascunho, setRascunho] = useState<{ title: string; detail: string; minutes: string }>({
    title: '', detail: '', minutes: '',
  });

  const grupos = useMemo(() => groupTemplatesByService(templates), [templates]);
  const totalPendente = useMemo(() => templates.filter(pendingApproval).length, [templates]);

  function abrirEdicao(t: StepTemplate) {
    setEditando(t.id);
    setRascunho({
      title: t.title,
      detail: t.detail || '',
      minutes: t.standard_minutes != null ? String(t.standard_minutes) : '',
    });
  }

  function salvarEAprovar(t: StepTemplate) {
    const minutos = rascunho.minutes.trim() ? Number(rascunho.minutes) : null;
    if (minutos !== null && (Number.isNaN(minutos) || minutos <= 0)) {
      toast.error('O tempo precisa ser um número de minutos maior que zero.');
      return;
    }
    const mudou =
      rascunho.title.trim() !== t.title ||
      (rascunho.detail.trim() || null) !== t.detail ||
      minutos !== t.standard_minutes;

    update.mutate(
      {
        id: t.id,
        patch: {
          title: rascunho.title.trim(),
          detail: rascunho.detail.trim() || null,
          standard_minutes: minutos,
        },
      },
      {
        onSuccess: () => {
          approve.mutate(
            { template: { ...t, title: rascunho.title.trim(), standard_minutes: minutos }, edited: mudou },
            {
              onSuccess: () => { setEditando(null); toast.success('Passo aprovado.'); },
              onError: (e: any) => toast.error(e?.message || 'Erro ao aprovar'),
            },
          );
        },
        onError: (e: any) => toast.error(e?.message || 'Erro ao salvar'),
      },
    );
  }

  return (
    <div className="p-4 lg:p-6 space-y-4">
      <div>
        <h1 className="text-lg font-semibold">Moldes do catálogo</h1>
        <p className="text-sm text-muted-foreground">
          O que se pergunta antes de orçar e o passo a passo de quem executa. É daqui que
          nascem o levantamento e o roteiro de cada OS — nada entra em uso sem a sua assinatura.
        </p>
      </div>

      <ServiceClassificationSection />

      <StepBlocksSection />

      <SurveyQuestionsSection />

      <div className="pt-2">
        <h2 className="text-sm font-semibold">Roteiros escritos por serviço</h2>
        <p className="text-xs text-muted-foreground">
          Passos específicos de um serviço, para quando a composição por blocos não basta.
        </p>
      </div>

      {isLoading && (
        <p className="flex items-center gap-2 text-sm text-muted-foreground">
          <Loader2 className="h-4 w-4 animate-spin" /> Carregando…
        </p>
      )}

      {!isLoading && templates.length === 0 && (
        <Card className="p-4 text-sm text-muted-foreground">
          Nenhum roteiro padrão cadastrado ainda. Peça à IA para rascunhar um, ou escreva à mão
          na tela do serviço.
        </Card>
      )}

      {totalPendente > 0 && (
        <Card className="flex items-start gap-2 border-primary/40 bg-primary/5 p-3 text-sm">
          <Sparkles className="h-4 w-4 mt-0.5 text-primary shrink-0" />
          <span>
            <strong>{totalPendente} passo(s) rascunhado(s) pela IA aguardando sua revisão.</strong>{' '}
            Nada disso entra em uso enquanto você não aprovar. Editar antes de aprovar é bem-vindo —
            é o que ensina a IA a escrever do seu jeito.
          </span>
        </Card>
      )}

      <div className="space-y-3">
        {grupos.map((g) => {
          const expandido = aberto[g.serviceId] ?? g.pendentes > 0;
          return (
            <Card key={g.serviceId} className="overflow-hidden">
              <button
                className="flex w-full items-center justify-between gap-3 p-3 text-left hover:bg-muted/50 transition-colors"
                onClick={() => setAberto((s) => ({ ...s, [g.serviceId]: !expandido }))}
              >
                <div className="flex min-w-0 items-center gap-2">
                  {expandido ? <ChevronDown className="h-4 w-4 shrink-0" /> : <ChevronRight className="h-4 w-4 shrink-0" />}
                  <span className="truncate text-sm font-medium">{g.serviceName}</span>
                </div>
                <div className="flex shrink-0 items-center gap-2 text-xs text-muted-foreground tabular-nums">
                  <span>{g.steps.length} passos</span>
                  <span>{formatMinutes(g.minutosTotais)}</span>
                  {g.pendentes > 0 && (
                    <Badge className="bg-primary text-primary-foreground text-[10px]">
                      {g.pendentes} a revisar
                    </Badge>
                  )}
                </div>
              </button>

              {expandido && (
                <div className="border-t divide-y">
                  {g.steps.map((t) => {
                    const pendente = pendingApproval(t);
                    const emEdicao = editando === t.id;
                    return (
                      <div key={t.id} className={`p-3 ${pendente ? 'bg-primary/5' : ''}`}>
                        {emEdicao ? (
                          <div className="space-y-2">
                            <Input
                              value={rascunho.title}
                              onChange={(e) => setRascunho((r) => ({ ...r, title: e.target.value }))}
                              placeholder="Título do passo (verbo no imperativo)"
                              className="h-9"
                            />
                            <Textarea
                              value={rascunho.detail}
                              onChange={(e) => setRascunho((r) => ({ ...r, detail: e.target.value }))}
                              placeholder="Detalhe — o 'como'. Opcional."
                              rows={2}
                            />
                            <div className="flex items-center gap-2">
                              <Input
                                value={rascunho.minutes}
                                onChange={(e) => setRascunho((r) => ({ ...r, minutes: e.target.value }))}
                                placeholder="minutos"
                                inputMode="numeric"
                                className="h-9 w-28"
                              />
                              <Button size="sm" variant="ghost" onClick={() => setEditando(null)}>
                                Cancelar
                              </Button>
                              <Button
                                size="sm"
                                disabled={!rascunho.title.trim() || update.isPending || approve.isPending}
                                onClick={() => salvarEAprovar(t)}
                              >
                                Salvar e aprovar
                              </Button>
                            </div>
                          </div>
                        ) : (
                          <div className="flex items-start gap-3">
                            <span className="mt-0.5 w-5 shrink-0 text-[11px] text-muted-foreground tabular-nums">
                              {t.seq}
                            </span>
                            <div className="min-w-0 flex-1 space-y-1">
                              <div className="flex flex-wrap items-center gap-1.5">
                                <span className="text-sm font-medium">{t.title}</span>
                                {t.block && <Badge variant="secondary" className="text-[10px]">{t.block}</Badge>}
                                {t.kind === 'safety' && <ShieldAlert className="h-3.5 w-3.5 text-red-600" />}
                                {t.is_killer && (
                                  <Badge variant="outline" className="border-amber-500 text-amber-700 dark:text-amber-400 text-[10px]">
                                    crítico
                                  </Badge>
                                )}
                                {t.requires_photo && <Camera className="h-3.5 w-3.5 text-muted-foreground" />}
                                {t.requires_measure && <Ruler className="h-3.5 w-3.5 text-muted-foreground" />}
                                {t.mode === 'read_do' && (
                                  <Badge variant="outline" className="text-[10px]">leia e faça</Badge>
                                )}
                              </div>
                              {t.detail && (
                                <p className="text-xs text-muted-foreground leading-snug">{t.detail}</p>
                              )}
                              <div className="flex flex-wrap items-center gap-2 text-[11px] text-muted-foreground tabular-nums">
                                <span>{formatMinutes(t.standard_minutes)}</span>
                                {pendente ? (
                                  <span className="text-primary">rascunho da IA — aguarda sua decisão</span>
                                ) : t.active ? (
                                  <span className="text-emerald-700 dark:text-emerald-400">em uso</span>
                                ) : (
                                  <span>inativo</span>
                                )}
                              </div>
                            </div>

                            {pendente && (
                              <div className="flex shrink-0 gap-1">
                                <Button
                                  size="sm" variant="ghost" className="h-7 px-2 text-destructive"
                                  title="Descartar este passo"
                                  onClick={() => reject.mutate(t, {
                                    onError: (e: any) => toast.error(e?.message || 'Erro'),
                                  })}
                                >
                                  <X className="h-3.5 w-3.5" />
                                </Button>
                                <Button
                                  size="sm" variant="outline" className="h-7 px-2"
                                  title="Editar antes de aprovar"
                                  onClick={() => abrirEdicao(t)}
                                >
                                  <Pencil className="h-3.5 w-3.5" />
                                </Button>
                                <Button
                                  size="sm" className="h-7 px-2"
                                  title="Aprovar como está"
                                  onClick={() => approve.mutate({ template: t }, {
                                    onSuccess: () => toast.success('Passo aprovado.'),
                                    onError: (e: any) => toast.error(e?.message || 'Erro'),
                                  })}
                                >
                                  <Check className="h-3.5 w-3.5" />
                                </Button>
                              </div>
                            )}
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </Card>
          );
        })}
      </div>
    </div>
  );
}
