import { groupStepsByBlock, formatMinutes, type ServiceOrderStep } from '@/hooks/use-service-steps';

export interface RouteSheetHeader {
  orderNumber: string;
  clientName?: string | null;
  assetName?: string | null;
  assetType?: string | null;
  marinaName?: string | null;
  technicianName?: string | null;
  scheduledAt?: string | null;
  shareUrl?: string | null;
}

function escapeHtml(value: string | null | undefined): string {
  if (!value) return '';
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function formatDateBr(iso: string | null | undefined): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleString('pt-BR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
}

/**
 * Folha A4 do roteiro — o mesmo conteúdo do Modo Foco, no papel.
 *
 * Não é um relatório do sistema: é a ferramenta de quem trabalha com a mão suja,
 * sol na tela e bateria no fim. Por isso preto e branco, fonte grande, quadradinho
 * para marcar e campo de hora escrito à mão. Quem usa o papel devolve a folha;
 * quem usa o app não imprime. O dado entra igual pelos dois caminhos.
 */
export function buildRouteSheetHtml(header: RouteSheetHeader, steps: ServiceOrderStep[]): string {
  const groups = groupStepsByBlock(steps);
  const totalStandard = steps.reduce((sum, s) => sum + (s.standard_minutes || 0), 0);

  const infoLine = [
    header.clientName && `Cliente: ${escapeHtml(header.clientName)}`,
    header.assetName && `${escapeHtml(header.assetType || 'Ativo')}: ${escapeHtml(header.assetName)}`,
    header.marinaName && `Local: ${escapeHtml(header.marinaName)}`,
  ].filter(Boolean).join(' &nbsp;·&nbsp; ');

  const metaLine = [
    header.technicianName && `Técnico: ${escapeHtml(header.technicianName)}`,
    header.scheduledAt && `Agendado: ${formatDateBr(header.scheduledAt)}`,
    totalStandard > 0 && `Previsto: ${formatMinutes(totalStandard)}`,
  ].filter(Boolean).join(' &nbsp;·&nbsp; ');

  const blocksHtml = groups.map((group) => {
    const rows = group.steps.map((step) => {
      const marks: string[] = [];
      if (step.kind === 'safety') marks.push('SEGURANÇA');
      if (step.is_killer) marks.push('CRÍTICO');
      if (step.requires_photo) marks.push('FOTO');
      const measure = step.requires_measure
        ? `<div class="measure">Medição (${escapeHtml(step.measure_unit || '')}): _______________</div>`
        : '';
      return `
        <tr>
          <td class="box"><span class="check"></span></td>
          <td class="seq">${step.seq}</td>
          <td class="step">
            <div class="title">${escapeHtml(step.title)}${
              marks.length ? ` <span class="marks">${marks.join(' · ')}</span>` : ''
            }</div>
            ${step.detail ? `<div class="detail">${escapeHtml(step.detail)}</div>` : ''}
            ${measure}
          </td>
          <td class="std">${step.standard_minutes ? `${step.standard_minutes}min` : ''}</td>
          <td class="time"><span class="rule"></span></td>
        </tr>`;
    }).join('');

    return `
      <table class="block">
        <thead>
          <tr><th colspan="5" class="blockname">${escapeHtml(group.block)}</th></tr>
          <tr class="cols">
            <th></th><th>#</th><th>Passo</th><th>Prev.</th><th>Início / fim</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>`;
  }).join('');

  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>Roteiro ${escapeHtml(header.orderNumber)}</title>
<style>
  @page { size: A4; margin: 12mm 10mm; }
  * { box-sizing: border-box; }
  body { font-family: Arial, Helvetica, sans-serif; color: #000; margin: 0; font-size: 11pt; }
  h1 { font-size: 15pt; margin: 0 0 2mm; }
  .info, .meta { font-size: 9.5pt; margin-bottom: 1.5mm; }
  .head { border-bottom: 1.5pt solid #000; padding-bottom: 3mm; margin-bottom: 4mm; }
  table.block { width: 100%; border-collapse: collapse; margin-bottom: 5mm; page-break-inside: auto; }
  .blockname { text-align: left; font-size: 11pt; text-transform: uppercase;
               letter-spacing: .06em; padding: 2mm 0 1mm; border-bottom: 1pt solid #000; }
  tr.cols th { font-size: 8pt; font-weight: normal; text-transform: uppercase;
               letter-spacing: .05em; text-align: left; padding: 1mm 1mm; border-bottom: .5pt solid #999; }
  tbody tr { page-break-inside: avoid; }
  td { padding: 2mm 1mm; border-bottom: .5pt dotted #999; vertical-align: top; }
  td.box { width: 8mm; }
  .check { display: block; width: 5mm; height: 5mm; border: 1pt solid #000; }
  td.seq { width: 7mm; font-size: 9pt; color: #444; }
  .title { font-weight: bold; font-size: 10.5pt; line-height: 1.3; }
  .marks { font-weight: normal; font-size: 7.5pt; letter-spacing: .05em; border: .5pt solid #000;
           padding: 0 1mm; white-space: nowrap; }
  .detail { font-size: 9pt; color: #333; margin-top: .8mm; line-height: 1.35; }
  .measure { font-size: 9pt; margin-top: 1.2mm; }
  td.std { width: 14mm; font-size: 9pt; text-align: right; white-space: nowrap; }
  td.time { width: 32mm; }
  .rule { display: block; border-bottom: .5pt solid #000; height: 4mm; }
  .foot { margin-top: 6mm; border-top: 1pt solid #000; padding-top: 3mm; font-size: 9pt; }
  .sign { margin-top: 8mm; display: flex; gap: 10mm; }
  .sign div { flex: 1; border-top: .5pt solid #000; padding-top: 1.5mm; font-size: 8.5pt; }
  .empty { font-size: 10pt; padding: 6mm 0; }
</style>
</head>
<body>
  <div class="head">
    <h1>Roteiro de execução — ${escapeHtml(header.orderNumber)}</h1>
    ${infoLine ? `<div class="info">${infoLine}</div>` : ''}
    ${metaLine ? `<div class="meta">${metaLine}</div>` : ''}
  </div>
  ${steps.length ? blocksHtml : '<p class="empty">Esta OS ainda não tem roteiro gerado.</p>'}
  <div class="foot">
    Travou? Anote o motivo ao lado do passo e avise o escritório.
    ${header.shareUrl ? `<br>OS no sistema: ${escapeHtml(header.shareUrl)}` : ''}
  </div>
  <div class="sign">
    <div>Assinatura do técnico</div>
    <div>Assinatura do cliente</div>
  </div>
</body>
</html>`;
}

/** Abre a folha em nova janela e chama a impressão. */
export function printRouteSheet(header: RouteSheetHeader, steps: ServiceOrderStep[]): boolean {
  const win = window.open('', '_blank', 'width=900,height=1000');
  if (!win) return false; // bloqueador de pop-up; quem chama avisa o usuário
  win.document.write(buildRouteSheetHtml(header, steps));
  win.document.close();
  win.focus();
  // Deixa o layout assentar antes de abrir o diálogo de impressão.
  win.setTimeout(() => win.print(), 250);
  return true;
}
