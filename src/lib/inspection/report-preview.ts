import {
  INSPECTION_STATUS_LABEL,
  type InspectionDraftItem,
  type InspectionItemStatus,
} from './marine-template';
import type { VoltageDropResult } from './voltage-drop';

export type ReportStatus = 'green' | 'yellow' | 'red';

export type ReportContext = {
  serviceOrderNumber?: string | null;
  clientName?: string | null;
  vesselName?: string | null;
  vesselModel?: string | null;
  status?: string | null;
  dateLabel?: string | null;
  technicianName?: string | null;
};

export type ReportInput = {
  context: ReportContext;
  items: InspectionDraftItem[];
  generalNotes?: string;
  voltageDrop?: VoltageDropResult | null;
};

export type ReportPreview = {
  status: ReportStatus;
  statusLabel: string;
  technicalMarkdown: string;
  executiveMarkdown: string;
  counts: Record<InspectionItemStatus, number>;
};

const NA = 'Não informado';

function countByStatus(items: InspectionDraftItem[]): Record<InspectionItemStatus, number> {
  const counts: Record<InspectionItemStatus, number> = {
    pending: 0,
    ok: 0,
    attention: 0,
    critical: 0,
    not_applicable: 0,
  };
  for (const item of items) counts[item.status] += 1;
  return counts;
}

function deriveStatus(counts: Record<InspectionItemStatus, number>): ReportStatus {
  if (counts.critical > 0) return 'red';
  if (counts.attention > 0) return 'yellow';
  return 'green';
}

function statusLabelFromColor(status: ReportStatus): string {
  if (status === 'red') return 'Vermelho — ação imediata recomendada';
  if (status === 'yellow') return 'Amarelo — pontos de atenção identificados';
  return 'Verde — embarcação dentro dos parâmetros avaliados';
}

function formatItemList(
  items: InspectionDraftItem[],
  filter: InspectionItemStatus,
): string {
  const filtered = items.filter((i) => i.status === filter);
  if (filtered.length === 0) return '_Nenhum item nesta categoria._';
  return filtered
    .map((item) => {
      const obs = item.observations?.trim();
      const obsLine = obs ? ` — _${obs}_` : '';
      return `- **${item.systemGroup} / ${item.category}** — ${item.label}${obsLine}`;
    })
    .join('\n');
}

function formatContextBlock(ctx: ReportContext): string {
  return [
    `- **OS:** ${ctx.serviceOrderNumber ?? NA}`,
    `- **Cliente:** ${ctx.clientName ?? NA}`,
    `- **Embarcação:** ${ctx.vesselName ?? NA}${ctx.vesselModel ? ` (${ctx.vesselModel})` : ''}`,
    `- **Status da OS:** ${ctx.status ?? NA}`,
    `- **Data da inspeção:** ${ctx.dateLabel ?? NA}`,
    `- **Técnico responsável:** ${ctx.technicianName ?? NA}`,
  ].join('\n');
}

function formatVoltageDropBlock(vd: VoltageDropResult | null | undefined): string {
  if (!vd || vd.classification === 'invalid') return '';
  const pct = vd.dropPercent.toFixed(2);
  const volts = vd.dropVolts.toFixed(3);
  return [
    '',
    '### Cálculo auxiliar de queda de tensão',
    `- **Queda:** ${volts} V (${pct}%)`,
    `- **Classificação:** ${vd.classification}`,
    `- ${vd.message}`,
    '',
  ].join('\n');
}

export function buildReportPreview(input: ReportInput): ReportPreview {
  const counts = countByStatus(input.items);
  const status = deriveStatus(counts);
  const statusLabel = statusLabelFromColor(status);

  const contextBlock = formatContextBlock(input.context);
  const notes = input.generalNotes?.trim();
  const notesBlock = notes
    ? `\n### Observações gerais do técnico\n\n${notes}\n`
    : '\n### Observações gerais do técnico\n\n_Sem observações registradas._\n';

  const criticalList = formatItemList(input.items, 'critical');
  const attentionList = formatItemList(input.items, 'attention');
  const okList = formatItemList(input.items, 'ok');
  const pendingCount = counts.pending;
  const naCount = counts.not_applicable;

  const totalEvaluated =
    counts.ok + counts.attention + counts.critical + counts.not_applicable;
  const totalItems = input.items.length;

  const vdBlock = formatVoltageDropBlock(input.voltageDrop);

  const technicalMarkdown = [
    '# Relatório técnico (uso interno)',
    '',
    '## Identificação',
    '',
    contextBlock,
    '',
    '## Resumo da inspeção',
    '',
    `- **Itens avaliados:** ${totalEvaluated} de ${totalItems}`,
    `- **${INSPECTION_STATUS_LABEL.ok}:** ${counts.ok}`,
    `- **${INSPECTION_STATUS_LABEL.attention}:** ${counts.attention}`,
    `- **${INSPECTION_STATUS_LABEL.critical}:** ${counts.critical}`,
    `- **${INSPECTION_STATUS_LABEL.not_applicable}:** ${naCount}`,
    `- **${INSPECTION_STATUS_LABEL.pending}:** ${pendingCount}`,
    '',
    '## Itens críticos',
    '',
    criticalList,
    '',
    '## Itens em atenção',
    '',
    attentionList,
    '',
    '## Itens conformes',
    '',
    okList,
    vdBlock,
    notesBlock,
    '## Recomendações internas',
    '',
    counts.critical > 0
      ? '- Tratar itens críticos antes de liberar a embarcação.'
      : counts.attention > 0
        ? '- Programar correção dos itens em atenção na próxima janela de manutenção.'
        : '- Nenhuma ação corretiva imediata identificada nesta inspeção.',
    pendingCount > 0 ? `- ${pendingCount} item(ns) ainda pendente(s) de avaliação.` : '',
  ]
    .filter(Boolean)
    .join('\n');

  const executiveMarkdown = [
    '# Relatório executivo',
    '',
    '## Embarcação avaliada',
    '',
    contextBlock,
    '',
    '## Status geral',
    '',
    `**${statusLabel}**`,
    '',
    '## Principais achados',
    '',
    counts.critical > 0
      ? `- Foram identificados **${counts.critical} ponto(s) crítico(s)** que demandam ação imediata.`
      : '- Não foram identificados pontos críticos nesta inspeção.',
    counts.attention > 0
      ? `- Foram identificados **${counts.attention} ponto(s) de atenção** a serem programados.`
      : '- Não há pontos de atenção pendentes no momento.',
    counts.ok > 0
      ? `- ${counts.ok} item(ns) avaliado(s) estão dentro dos parâmetros esperados.`
      : '',
    pendingCount > 0
      ? `- ${pendingCount} item(ns) ainda não foram avaliados nesta inspeção e serão concluídos em retorno.`
      : '',
    '',
    '## Próximos passos recomendados',
    '',
    counts.critical > 0
      ? '1. Agendar correção imediata dos itens críticos.\n2. Reavaliar a embarcação após os reparos.\n3. Manter monitoramento dos itens em atenção.'
      : counts.attention > 0
        ? '1. Programar manutenção preventiva nos itens em atenção.\n2. Reavaliar na próxima janela técnica.'
        : '1. Manter rotina de inspeções periódicas.\n2. Registrar histórico para próximas comparações.',
    '',
    '_Este relatório é uma síntese executiva. Os detalhes técnicos completos estão no relatório interno._',
  ]
    .filter(Boolean)
    .join('\n');

  return {
    status,
    statusLabel,
    technicalMarkdown,
    executiveMarkdown,
    counts,
  };
}
