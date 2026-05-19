import { useMemo, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import { Info, Sparkles, FileText, Save } from 'lucide-react';
import {
  createDraftFromTemplate,
  MARINE_INSPECTION_TEMPLATE,
  type InspectionDraftItem,
} from '@/lib/inspection/marine-template';
import { buildReportPreview, type ReportPreview } from '@/lib/inspection/report-preview';
import type { VoltageDropResult } from '@/lib/inspection/voltage-drop';
import { InspectionChecklist } from './InspectionChecklist';
import { VoltageDropPreview } from './VoltageDropPreview';
import { InspectionReportPreview } from './InspectionReportPreview';

type OrderLike = {
  service_order_number?: string | null;
  status?: string | null;
  created_at?: string | null;
  clients?: { full_name_or_company_name?: string | null } | null;
  vessels?: { boat_name?: string | null; manufacturer?: string | null; model?: string | null } | null;
} | null | undefined;

type Props = {
  order: OrderLike;
};

function formatDate(value?: string | null): string | null {
  if (!value) return null;
  try {
    return new Date(value).toLocaleDateString('pt-BR');
  } catch {
    return null;
  }
}

export function ServiceOrderInspectionTab({ order }: Props) {
  const [items, setItems] = useState<InspectionDraftItem[]>(() =>
    createDraftFromTemplate(MARINE_INSPECTION_TEMPLATE),
  );
  const [generalNotes, setGeneralNotes] = useState('');
  const [voltageDrop, setVoltageDrop] = useState<VoltageDropResult | null>(null);
  const [report, setReport] = useState<ReportPreview | null>(null);

  const ctx = useMemo(() => {
    const vesselName = order?.vessels?.boat_name ?? null;
    const vesselModel =
      [order?.vessels?.manufacturer, order?.vessels?.model].filter(Boolean).join(' ') || null;
    return {
      serviceOrderNumber: order?.service_order_number ?? null,
      clientName: order?.clients?.full_name_or_company_name ?? null,
      vesselName,
      vesselModel,
      status: order?.status ?? null,
      dateLabel: formatDate(order?.created_at),
      technicianName: null,
    };
  }, [order]);

  const handleGenerateDraft = () => {
    const preview = buildReportPreview({
      context: ctx,
      items,
      generalNotes,
      voltageDrop,
    });
    setReport(preview);
  };

  return (
    <TooltipProvider delayDuration={150}>
      <div className="flex flex-col gap-6 max-w-5xl">
        <header className="flex flex-col gap-2">
          <div className="flex items-center gap-2 flex-wrap">
            <h2 className="text-lg font-semibold">Laudos / Inspeção</h2>
            <Badge variant="secondary" className="text-[10px]">
              Preview Fase 1
            </Badge>
            <Badge variant="outline" className="text-[10px] border-amber-400 text-amber-700 dark:text-amber-300">
              Local — não salva no banco
            </Badge>
          </div>
          <p className="text-sm text-muted-foreground">
            Prévia local da nova aba de laudos técnicos. Ainda não há persistência, geração de
            PDF oficial ou chamada de IA real — tudo é simulado para validar o fluxo.
          </p>
        </header>

        <Alert>
          <Info className="h-4 w-4" />
          <AlertTitle>Esta é uma prévia local</AlertTitle>
          <AlertDescription>
            Nada digitado aqui é gravado no banco de dados. Persistência, PDF e envio ao cliente
            serão implementados nas próximas fases.
          </AlertDescription>
        </Alert>

        {/* 1. Dados da OS */}
        <section className="rounded-lg border bg-card p-4">
          <h3 className="text-sm font-semibold mb-3">Dados da OS</h3>
          <dl className="grid grid-cols-2 md:grid-cols-3 gap-3 text-sm">
            <div>
              <dt className="text-xs text-muted-foreground">Número</dt>
              <dd>{ctx.serviceOrderNumber ?? 'Não informado'}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">Cliente</dt>
              <dd>{ctx.clientName ?? 'Não informado'}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">Embarcação</dt>
              <dd>
                {ctx.vesselName ?? 'Não informado'}
                {ctx.vesselModel && (
                  <span className="text-muted-foreground"> — {ctx.vesselModel}</span>
                )}
              </dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">Status da OS</dt>
              <dd>{ctx.status ?? 'Não informado'}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">Data</dt>
              <dd>{ctx.dateLabel ?? 'Não informado'}</dd>
            </div>
          </dl>
        </section>

        {/* 2. Checklist */}
        <section className="flex flex-col gap-2">
          <h3 className="text-sm font-semibold">Checklist técnico náutico</h3>
          <p className="text-xs text-muted-foreground">
            Selecione o status de cada item e registre observações. Itens marcados como
            <em> Crítico </em> tornam o relatório vermelho; <em> Atenção </em> torna amarelo.
          </p>
          <InspectionChecklist items={items} onChange={setItems} />
        </section>

        {/* 3. Voltage drop */}
        <section className="flex flex-col gap-2">
          <h3 className="text-sm font-semibold">Cálculo auxiliar de queda de tensão</h3>
          <p className="text-xs text-muted-foreground">
            Use para apoiar a avaliação do item "Queda de tensão dentro do limite".
          </p>
          <VoltageDropPreview onResultChange={setVoltageDrop} />
        </section>

        {/* 4. Observações gerais */}
        <section className="flex flex-col gap-2">
          <Label htmlFor="general-notes" className="text-sm font-semibold">
            Observações gerais do técnico
          </Label>
          <Textarea
            id="general-notes"
            value={generalNotes}
            onChange={(e) => setGeneralNotes(e.target.value)}
            placeholder="Notas adicionais que entrarão no rascunho do relatório."
            rows={4}
          />
        </section>

        {/* 5. Generate draft */}
        <section className="flex items-center gap-3 flex-wrap">
          <Button type="button" onClick={handleGenerateDraft} className="gap-2">
            <Sparkles className="h-4 w-4" />
            Gerar rascunho com IA
          </Button>
          <span className="text-xs text-muted-foreground">
            Rascunho simulado localmente. Integração Gemini será implementada na Fase 2.
          </span>
        </section>

        {/* 6. Report preview */}
        {report && <InspectionReportPreview report={report} />}

        {/* 7. Future actions */}
        <section className="flex items-center gap-3 flex-wrap pt-2 border-t">
          <Tooltip>
            <TooltipTrigger asChild>
              <span>
                <Button variant="outline" disabled className="gap-2">
                  <Save className="h-4 w-4" />
                  Salvar rascunho
                </Button>
              </span>
            </TooltipTrigger>
            <TooltipContent>Persistência será implementada na Fase 2.</TooltipContent>
          </Tooltip>
          <Tooltip>
            <TooltipTrigger asChild>
              <span>
                <Button variant="outline" disabled className="gap-2">
                  <FileText className="h-4 w-4" />
                  Gerar PDF
                </Button>
              </span>
            </TooltipTrigger>
            <TooltipContent>PDF oficial do laudo será implementado na Fase 3.</TooltipContent>
          </Tooltip>
        </section>
      </div>
    </TooltipProvider>
  );
}
