import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import type { ReportPreview, ReportStatus } from '@/lib/inspection/report-preview';

type Props = {
  report: ReportPreview;
};

const STATUS_BADGE: Record<ReportStatus, string> = {
  green: 'bg-emerald-100 text-emerald-800 dark:bg-emerald-900/40 dark:text-emerald-200',
  yellow: 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-200',
  red: 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-200',
};

export function InspectionReportPreview({ report }: Props) {
  return (
    <div className="rounded-lg border bg-card">
      <div className="border-b px-4 py-2 flex items-center justify-between flex-wrap gap-2">
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-semibold">Rascunho do relatório</h3>
          <span className={`text-[10px] rounded px-1.5 py-0.5 ${STATUS_BADGE[report.status]}`}>
            {report.statusLabel}
          </span>
        </div>
        <div className="flex items-center gap-3 text-xs text-muted-foreground">
          <span>OK: {report.counts.ok}</span>
          <span>Atenção: {report.counts.attention}</span>
          <span>Crítico: {report.counts.critical}</span>
          <span>N/A: {report.counts.not_applicable}</span>
          <span>Pendente: {report.counts.pending}</span>
        </div>
      </div>
      <Tabs defaultValue="executive" className="px-4 pt-3 pb-4">
        <TabsList>
          <TabsTrigger value="executive">Executivo (cliente)</TabsTrigger>
          <TabsTrigger value="technical">Técnico (interno)</TabsTrigger>
        </TabsList>
        <TabsContent value="executive" className="mt-3">
          <pre className="text-xs whitespace-pre-wrap font-sans leading-relaxed bg-muted/30 rounded p-3 max-h-[480px] overflow-auto">
            {report.executiveMarkdown}
          </pre>
        </TabsContent>
        <TabsContent value="technical" className="mt-3">
          <pre className="text-xs whitespace-pre-wrap font-sans leading-relaxed bg-muted/30 rounded p-3 max-h-[480px] overflow-auto">
            {report.technicalMarkdown}
          </pre>
        </TabsContent>
      </Tabs>
    </div>
  );
}
