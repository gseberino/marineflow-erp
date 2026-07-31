import { useMemo, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Progress } from '@/components/ui/progress';
import {
  AlertTriangle, ArrowDown, ArrowUp, Camera, Check, ListChecks, Play, Plus,
  Printer, Ruler, ShieldAlert, Sparkles, Trash2, Undo2, Wand2, X,
} from 'lucide-react';
import { toast } from 'sonner';
import { StepFocusMode } from './StepFocusMode';
import { printRouteSheet } from '@/lib/route-sheet';
import {
  useServiceOrderSteps, useGenerateSteps, useReorderSteps, useDeleteStep,
  useCreateStep, useReopenStep, useStopReasons, useReviewAiStep, useRouteMaterials,
  summarizeRoute, groupStepsByBlock, formatMinutes, isAiDraft,
  type ServiceOrderStep,
} from '@/hooks/use-service-steps';
import { useAppSettings } from '@/hooks/use-app-settings';

const STATUS_LABEL: Record<string, string> = {
  pending: 'a fazer',
  in_progress: 'em execução',
  done: 'feito',
  not_applicable: 'não se aplica',
  blocked: 'travado',
};

function StatusPill({ step }: { step: ServiceOrderStep }) {
  const tone =
    step.status === 'done' ? 'bg-emerald-100 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300'
    : step.status === 'blocked' ? 'bg-red-100 text-red-800 dark:bg-red-950 dark:text-red-300'
    : step.status === 'in_progress' ? 'bg-blue-100 text-blue-800 dark:bg-blue-950 dark:text-blue-300'
    : step.status === 'not_applicable' ? 'bg-muted text-muted-foreground'
    : 'bg-muted text-muted-foreground';
  return (
    <span className={`rounded px-1.5 py-0.5 text-[10px] font-medium whitespace-nowrap ${tone}`}>
      {STATUS_LABEL[step.status] ?? step.status}
    </span>
  );
}

/**
 * Painel do Roteiro na tela da OS — onde o escritório monta e acompanha.
 * O técnico usa o Modo Foco; aqui é a visão de quem planeja e confere.
 */
export function ServiceRoutePanel({
  serviceOrderId, orderNumber, clientName, assetName, assetType, marinaName,
  technicianName, scheduledAt, shareUrl,
}: {
  serviceOrderId: string | undefined;
  orderNumber?: string;
  clientName?: string | null;
  assetName?: string | null;
  assetType?: string | null;
  marinaName?: string | null;
  technicianName?: string | null;
  scheduledAt?: string | null;
  shareUrl?: string | null;
}) {
  const { data: steps = [], isLoading } = useServiceOrderSteps(serviceOrderId);
  const { data: reasons = [] } = useStopReasons();
  const { data: materials = [] } = useRouteMaterials(serviceOrderId);
  const { data: settings } = useAppSettings();
  const generate = useGenerateSteps();
  const reorder = useReorderSteps();
  const remove = useDeleteStep();
  const create = useCreateStep();
  const reopen = useReopenStep();

  const [focusOpen, setFocusOpen] = useState(false);
  const [newTitle, setNewTitle] = useState('');

  const review = useReviewAiStep();

  // Sugestão da IA não conta como roteiro: fica separada até alguém decidir.
  const drafts = useMemo(() => steps.filter(isAiDraft), [steps]);
  const aprovados = useMemo(() => steps.filter((s) => !isAiDraft(s)), [steps]);

  const summary = useMemo(() => summarizeRoute(aprovados), [aprovados]);
  const groups = useMemo(() => groupStepsByBlock(aprovados), [aprovados]);
  const reasonLabel = useMemo(
    () => Object.fromEntries(reasons.map((r) => [r.code, r.label])),
    [reasons],
  );

  if (!serviceOrderId) return null;

  const progress = summary.total > 0
    ? Math.round(((summary.done + summary.notApplicable) / summary.total) * 100)
    : 0;

  function handleGenerate() {
    generate.mutate(serviceOrderId!, {
      onSuccess: (created) => {
        if (created > 0) toast.success(`${created} passo(s) gerado(s) a partir do catálogo.`);
        else if (steps.length > 0) toast.info('O roteiro já estava gerado.');
        else toast.warning('Nenhum serviço desta OS tem roteiro padrão cadastrado ainda.');
      },
      onError: (e: any) => toast.error(e?.message || 'Não deu para gerar o roteiro'),
    });
  }

  function handleAdd() {
    const title = newTitle.trim();
    if (!title) return;
    const maxSeq = steps.reduce((m, s) => Math.max(m, s.seq), 0);
    create.mutate(
      { service_order_id: serviceOrderId!, title, seq: maxSeq + 1, block: 'Extra', origin: 'manual' },
      {
        onSuccess: () => setNewTitle(''),
        onError: (e: any) => toast.error(e?.message || 'Erro ao adicionar passo'),
      },
    );
  }

  function handlePrint() {
    const ok = printRouteSheet(
      { orderNumber: orderNumber || 'OS', clientName, assetName, assetType, marinaName,
        technicianName, scheduledAt, shareUrl,
        companyName: settings?.company_name || null,
        companyLogoUrl: settings?.company_logo_url || null,
        companyAddress: settings?.company_address || null },
      steps,
      materials,
    );
    if (!ok) toast.error('O navegador bloqueou a janela de impressão. Libere o pop-up e tente de novo.');
  }

  function move(index: number, direction: -1 | 1) {
    const a = steps[index];
    const b = steps[index + direction];
    if (!a || !b) return;
    reorder.mutate({ a, b }, { onError: (e: any) => toast.error(e?.message || 'Erro ao reordenar') });
  }

  return (
    <Card className="p-4 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2 text-sm font-semibold">
          <ListChecks className="h-4 w-4 text-primary" /> Roteiro de execução
          {summary.total > 0 && (
            <span className="rounded-full bg-primary/10 text-primary px-2 py-0.5 text-[11px] font-medium tabular-nums">
              {summary.done + summary.notApplicable}/{summary.total}
            </span>
          )}
        </div>
        <div className="flex flex-wrap gap-2">
          <Button size="sm" variant="outline" onClick={handleGenerate} disabled={generate.isPending}>
            <Wand2 className="h-4 w-4 mr-1.5" /> Gerar do catálogo
          </Button>
          <Button size="sm" variant="outline" onClick={handlePrint} disabled={steps.length === 0}>
            <Printer className="h-4 w-4 mr-1.5" /> Imprimir folha
          </Button>
          <Button size="sm" onClick={() => setFocusOpen(true)} disabled={steps.length === 0}>
            <Play className="h-4 w-4 mr-1.5" /> Modo foco
          </Button>
        </div>
      </div>

      {isLoading && <p className="text-sm text-muted-foreground">Carregando roteiro…</p>}

      {/* Sugestões da IA: separadas, e cada uma exige uma decisão. Aceitar em
          lote seria o mesmo que não revisar — e é assim que passo errado entra. */}
      {drafts.length > 0 && (
        <div className="rounded-md border border-dashed border-primary/40 bg-primary/5 p-3 space-y-2">
          <div className="flex items-center gap-1.5 text-sm font-medium">
            <Sparkles className="h-4 w-4 text-primary" />
            {drafts.length} passo(s) sugerido(s) pela IA
            {drafts[0]?.ai_confidence != null && (
              <Badge variant="outline" className="text-[10px]">
                confiança {Math.round(Number(drafts[0].ai_confidence) * 100)}%
              </Badge>
            )}
          </div>
          {drafts[0]?.ai_source && (
            <p className="text-xs text-muted-foreground">baseado em: {drafts[0].ai_source}</p>
          )}
          <p className="text-xs text-muted-foreground">
            Nada disso vale até você aprovar. Descartar também ensina — o que você recusa não volta.
          </p>

          <div className="space-y-1.5">
            {drafts.map((step) => (
              <div key={step.id} className="flex items-start gap-2 rounded border bg-background px-2.5 py-2 text-sm">
                <div className="min-w-0 flex-1 space-y-0.5">
                  <div className="flex flex-wrap items-center gap-1.5">
                    <span className="font-medium">{step.title}</span>
                    {step.kind === 'safety' && <ShieldAlert className="h-3.5 w-3.5 text-red-600" />}
                    {step.requires_photo && <Camera className="h-3.5 w-3.5 text-muted-foreground" />}
                    {step.standard_minutes != null && (
                      <span className="text-[11px] text-muted-foreground tabular-nums">
                        {formatMinutes(step.standard_minutes)}
                      </span>
                    )}
                  </div>
                  {step.detail && <p className="text-xs text-muted-foreground">{step.detail}</p>}
                </div>
                <div className="flex shrink-0 gap-1">
                  <Button
                    size="sm" variant="ghost" className="h-7 px-2 text-destructive"
                    title="Descartar"
                    onClick={() => review.mutate(
                      { step, verdict: 'rejected' },
                      { onError: (e: any) => toast.error(e?.message || 'Erro') },
                    )}
                  >
                    <X className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    size="sm" className="h-7 px-2"
                    title="Aprovar"
                    onClick={() => review.mutate(
                      { step, verdict: 'accepted' },
                      { onError: (e: any) => toast.error(e?.message || 'Erro') },
                    )}
                  >
                    <Check className="h-3.5 w-3.5" />
                  </Button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {!isLoading && steps.length === 0 && (
        <div className="rounded-md border border-dashed p-4 text-sm text-muted-foreground space-y-1">
          <p className="font-medium text-foreground">Esta OS ainda não tem roteiro.</p>
          <p>
            Use <strong>Gerar do catálogo</strong> para trazer os passos padrão dos serviços lançados,
            ou acrescente um passo à mão abaixo.
          </p>
        </div>
      )}

      {summary.total > 0 && (
        <div className="space-y-2">
          <Progress value={progress} className="h-1.5" />
          <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground tabular-nums">
            <span>previsto <strong className="text-foreground">{formatMinutes(summary.standardMinutes)}</strong></span>
            <span>real <strong className="text-foreground">{formatMinutes(summary.actualMinutes)}</strong></span>
            {summary.variancePct !== null && summary.actualMinutes > 0 && (
              <span className={summary.variancePct > 0 ? 'text-amber-600 dark:text-amber-400' : 'text-emerald-700 dark:text-emerald-400'}>
                {summary.variancePct > 0 ? '+' : ''}{summary.variancePct}%
              </span>
            )}
            {summary.blocked > 0 && (
              <span className="text-red-600 dark:text-red-400">{summary.blocked} travado(s)</span>
            )}
          </div>
        </div>
      )}

      <div className="space-y-4">
        {groups.map((group) => (
          <div key={group.block} className="space-y-1.5">
            <p className="text-[11px] uppercase tracking-wide text-muted-foreground font-medium">
              {group.block}
            </p>
            {/* Bloco compartilhado precisa dizer a que serviços se aplica —
                sem isso ele parece órfão no meio do roteiro. */}
            {group.note && (
              <p className="text-[11px] leading-snug text-muted-foreground">{group.note}</p>
            )}
            {group.steps.map((step) => {
              const index = steps.findIndex((s) => s.id === step.id);
              return (
                <div
                  key={step.id}
                  className="flex items-start gap-2 rounded-md border px-2.5 py-2 text-sm"
                >
                  <span className="mt-0.5 w-5 shrink-0 text-[11px] text-muted-foreground tabular-nums">
                    {step.seq}
                  </span>
                  <div className="min-w-0 flex-1 space-y-1">
                    <div className="flex flex-wrap items-center gap-1.5">
                      <span className={step.status === 'done' ? 'line-through text-muted-foreground' : 'font-medium'}>
                        {step.title}
                      </span>
                      <StatusPill step={step} />
                      {step.kind === 'safety' && <ShieldAlert className="h-3.5 w-3.5 text-red-600" />}
                      {step.requires_photo && <Camera className="h-3.5 w-3.5 text-muted-foreground" />}
                      {step.requires_measure && <Ruler className="h-3.5 w-3.5 text-muted-foreground" />}
                      {step.origin === 'client_request' && (
                        <Badge variant="outline" className="text-[10px]">pedido do cliente</Badge>
                      )}
                    </div>
                    {step.detail && (
                      <p className="text-xs text-muted-foreground leading-snug">{step.detail}</p>
                    )}
                    {step.status === 'blocked' && (
                      <p className="flex items-center gap-1 text-xs text-red-600 dark:text-red-400">
                        <AlertTriangle className="h-3 w-3" />
                        {reasonLabel[step.blocked_reason_code || ''] || step.blocked_reason_code}
                        {step.blocked_note ? ` — ${step.blocked_note}` : ''}
                      </p>
                    )}
                    {step.status === 'not_applicable' && step.na_reason && (
                      <p className="text-xs text-muted-foreground">motivo: {step.na_reason}</p>
                    )}
                    {step.measure_value != null && (
                      <p className="text-xs text-muted-foreground tabular-nums">
                        medido: {step.measure_value} {step.measure_unit || ''}
                      </p>
                    )}
                    <div className="flex gap-2 text-[11px] text-muted-foreground tabular-nums">
                      {step.standard_minutes != null && <span>prev. {formatMinutes(step.standard_minutes)}</span>}
                      {step.actual_minutes != null && (
                        <span className={
                          step.standard_minutes && step.actual_minutes > step.standard_minutes * 1.5
                            ? 'text-amber-600 dark:text-amber-400' : ''
                        }>
                          real {formatMinutes(step.actual_minutes)}
                        </span>
                      )}
                    </div>
                  </div>
                  <div className="flex shrink-0 items-center gap-0.5">
                    {step.status !== 'pending' && (
                      <Button
                        variant="ghost" size="icon" className="h-7 w-7"
                        title="Voltar para pendente"
                        onClick={() => reopen.mutate(step, {
                          onError: (e: any) => toast.error(e?.message || 'Erro'),
                        })}
                      >
                        <Undo2 className="h-3.5 w-3.5" />
                      </Button>
                    )}
                    <Button
                      variant="ghost" size="icon" className="h-7 w-7"
                      title="Subir" disabled={index <= 0}
                      onClick={() => move(index, -1)}
                    >
                      <ArrowUp className="h-3.5 w-3.5" />
                    </Button>
                    <Button
                      variant="ghost" size="icon" className="h-7 w-7"
                      title="Descer" disabled={index >= steps.length - 1}
                      onClick={() => move(index, 1)}
                    >
                      <ArrowDown className="h-3.5 w-3.5" />
                    </Button>
                    <Button
                      variant="ghost" size="icon" className="h-7 w-7"
                      title="Remover passo"
                      onClick={() => remove.mutate(
                        { id: step.id, serviceOrderId: serviceOrderId! },
                        { onError: (e: any) => toast.error(e?.message || 'Erro') },
                      )}
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </Button>
                  </div>
                </div>
              );
            })}
          </div>
        ))}
      </div>

      <div className="flex gap-2 pt-1">
        <Input
          value={newTitle}
          onChange={(e) => setNewTitle(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') handleAdd(); }}
          placeholder="Acrescentar um passo (ex.: conferir aperto dos terminais)"
          className="h-9"
        />
        <Button size="sm" variant="outline" onClick={handleAdd} disabled={!newTitle.trim() || create.isPending}>
          <Plus className="h-4 w-4" />
        </Button>
      </div>

      {summary.finished && (
        <p className="flex items-center gap-1.5 text-xs text-emerald-700 dark:text-emerald-400">
          <Check className="h-3.5 w-3.5" /> Roteiro concluído — todo passo chegou a um estado final.
        </p>
      )}

      <StepFocusMode
        open={focusOpen}
        onOpenChange={setFocusOpen}
        steps={steps}
        orderLabel={orderNumber}
      />
    </Card>
  );
}
