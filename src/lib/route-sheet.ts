import {
  groupStepsByBlock, formatMinutes,
  type ServiceOrderStep, type RouteMaterial,
} from '@/hooks/use-service-steps';

export interface RouteSheetHeader {
  orderNumber: string;
  clientName?: string | null;
  assetName?: string | null;
  assetType?: string | null;
  marinaName?: string | null;
  technicianName?: string | null;
  scheduledAt?: string | null;
  shareUrl?: string | null;
  /** Identidade da empresa — a mesma do PDF do orçamento. */
  companyName?: string | null;
  companyLogoUrl?: string | null;
  companyAddress?: string | null;
}

/** Azul-marinho da HBR, o mesmo do PDF que o cliente já recebe. */
const BRAND = '#002B5B';

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

/** "2 un · Cabo 16mm² (SKU-123)" — o que o técnico precisa para separar. */
function materialLine(m: RouteMaterial): string {
  const qtd = Number(m.quantity);
  const quantidade = Number.isInteger(qtd) ? String(qtd) : qtd.toFixed(2).replace('.', ',');
  const unidade = m.products?.unit ? ` ${escapeHtml(m.products.unit)}` : '';
  const sku = m.products?.sku ? ` <span class="sku">(${escapeHtml(m.products.sku)})</span>` : '';
  return `<b>${quantidade}${unidade}</b> · ${escapeHtml(m.products?.name || 'Item sem cadastro')}${sku}`;
}

/** Pautas em branco para escrever à mão. */
function ruledLines(n: number): string {
  return `<div class="lines">${'<i></i>'.repeat(n)}</div>`;
}

/**
 * Folha A4 do roteiro — o mesmo conteúdo do Modo Foco, no papel.
 *
 * Continua sendo a ferramenta de quem trabalha com a mão suja, sol na tela e
 * bateria no fim: o miolo é preto e branco, fonte grande, quadradinho para
 * marcar e campo de hora escrito à mão. A marca entra discreta — logo pequeno
 * e um filete azul no topo, sem faixa preenchida (decisão do dono, 31/07:
 * gasta menos tinta e envelhece melhor em fotocópia). A cor nunca carrega
 * informação sozinha: tudo que importa continua legível em impressora P&B.
 *
 * Três espaços de escrita, porque o que não cabe no quadradinho é justamente o
 * que hoje se perde: observação por bloco, achados do serviço e material usado
 * além do previsto. `solution_applied` e `technician_notes` estão vazios em
 * todas as OS — esta folha é a chance de isso mudar.
 */
export function buildRouteSheetHtml(
  header: RouteSheetHeader,
  steps: ServiceOrderStep[],
  materials: RouteMaterial[] = [],
): string {
  const groups = groupStepsByBlock(steps);
  const totalStandard = steps.reduce((sum, s) => sum + (s.standard_minutes || 0), 0);

  const infoLine = [
    header.clientName && `Cliente: <b>${escapeHtml(header.clientName)}</b>`,
    header.assetName && `${escapeHtml(header.assetType || 'Ativo')}: <b>${escapeHtml(header.assetName)}</b>`,
    header.marinaName && `Local: <b>${escapeHtml(header.marinaName)}</b>`,
  ].filter(Boolean).join(' &nbsp;·&nbsp; ');

  const metaLine = [
    header.technicianName && `Técnico: <b>${escapeHtml(header.technicianName)}</b>`,
    header.scheduledAt && `Agendado: <b>${formatDateBr(header.scheduledAt)}</b>`,
    totalStandard > 0 && `Previsto: <b>${formatMinutes(totalStandard)}</b>`,
  ].filter(Boolean).join(' &nbsp;·&nbsp; ');

  // ── Separação de materiais: conferência antes de sair ────────────────────
  const materiaisHtml = materials.length ? `
    <table class="block">
      <thead>
        <tr><th colspan="2" class="blockname">Separação de materiais</th></tr>
        <tr class="cols"><th></th><th>Confira item por item antes de sair. Falta descoberta no local custa o dia.</th></tr>
      </thead>
      <tbody>
        ${materials.map((m) => `
          <tr>
            <td class="box"><span class="check"></span></td>
            <td class="mat">${materialLine(m)}${
              m.notes ? `<div class="detail">${escapeHtml(m.notes)}</div>` : ''
            }</td>
          </tr>`).join('')}
      </tbody>
    </table>` : '';

  const blocksHtml = groups.map((group) => {
    // Material desta etapa: casa o dono do material com o bloco da linha.
    const doBloco = group.blockKey?.startsWith('linha:')
      ? materials.filter((m) => m.service_order_service_id === group.blockKey!.slice('linha:'.length))
      : [];

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

    const minutos = group.steps.reduce((s, x) => s + (x.standard_minutes || 0), 0);

    return `
      <table class="block">
        <thead>
          <tr>
            <th colspan="4" class="blockname">${escapeHtml(group.block)}</th>
            <th class="blockmin">${minutos ? formatMinutes(minutos) : ''}</th>
          </tr>
          ${group.note ? `<tr><th colspan="5" class="blocknote">${escapeHtml(group.note)}</th></tr>` : ''}
          ${doBloco.length ? `<tr><th colspan="5" class="blockmat">
            <span class="matlabel">Material desta etapa:</span>
            ${doBloco.map((m) => materialLine(m)).join(' &nbsp;·&nbsp; ')}
          </th></tr>` : ''}
          <tr class="cols">
            <th></th><th>#</th><th>Passo</th><th>Prev.</th><th>Início / fim</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
        <tfoot>
          <tr><td colspan="5" class="notes">
            <span class="cap">Observações deste bloco</span>${ruledLines(2)}
          </td></tr>
        </tfoot>
      </table>`;
  }).join('');

  const logoHtml = header.companyLogoUrl
    ? `<img class="logo" src="${escapeHtml(header.companyLogoUrl)}" alt="">`
    : '';

  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>Roteiro ${escapeHtml(header.orderNumber)}</title>
<style>
  @page { size: A4; margin: 11mm 10mm; }
  * { box-sizing: border-box; }
  body { font-family: Arial, Helvetica, sans-serif; color: #000; margin: 0; font-size: 11pt;
         -webkit-print-color-adjust: exact; print-color-adjust: exact; }

  /* Cabeçalho: marca discreta — logo pequeno e um filete, sem faixa cheia. */
  .head { border-bottom: 1.2pt solid ${BRAND}; padding-bottom: 3mm; margin-bottom: 4mm; }
  .brand { display: flex; align-items: center; justify-content: space-between; gap: 6mm;
           margin-bottom: 2.5mm; }
  .brandleft { display: flex; align-items: center; gap: 3mm; min-width: 0; }
  .logo { height: 11mm; width: auto; max-width: 45mm; object-fit: contain; }
  .coname { font-size: 11pt; font-weight: bold; color: ${BRAND}; letter-spacing: .01em; }
  .doctype { text-align: right; white-space: nowrap; }
  .doctype .kind { font-size: 8pt; letter-spacing: .1em; text-transform: uppercase; color: #444; }
  .doctype .num { font-size: 14pt; font-weight: bold; color: ${BRAND}; }
  .info, .meta { font-size: 9.5pt; margin-top: 1.2mm; }

  table.block { width: 100%; border-collapse: collapse; margin-bottom: 5mm; page-break-inside: auto; }
  .blockname { text-align: left; font-size: 11pt; text-transform: uppercase;
               letter-spacing: .06em; padding: 2mm 0 1mm; border-bottom: 1pt solid #000; }
  .blockmin { text-align: right; font-size: 9pt; font-weight: normal; color: #333;
              border-bottom: 1pt solid #000; padding: 2mm 0 1mm; white-space: nowrap; }
  .blocknote { text-align: left; font-size: 9pt; font-weight: normal; color: #222;
               padding: 1.2mm 0 .6mm; border-bottom: .4pt dotted #999; }
  .blockmat { text-align: left; font-size: 9pt; font-weight: normal; color: #000;
              padding: 1.2mm 0 .6mm; border-bottom: .4pt dotted #999; }
  .matlabel { text-transform: uppercase; font-size: 7.5pt; letter-spacing: .08em; color: #444; }
  tr.cols th { font-size: 8pt; font-weight: normal; text-transform: uppercase;
               letter-spacing: .05em; text-align: left; padding: 1mm 1mm; border-bottom: .5pt solid #999; }
  tbody tr { page-break-inside: avoid; }
  td { padding: 2mm 1mm; border-bottom: .5pt dotted #999; vertical-align: top; }
  td.box { width: 8mm; }
  .check { display: block; width: 5mm; height: 5mm; border: 1pt solid #000; }
  td.seq { width: 7mm; font-size: 9pt; color: #444; }
  td.mat { font-size: 10pt; }
  .sku { font-size: 8.5pt; color: #555; }
  .title { font-weight: bold; font-size: 10.5pt; line-height: 1.3; }
  .marks { font-weight: normal; font-size: 7.5pt; letter-spacing: .05em; border: .5pt solid #000;
           padding: 0 1mm; white-space: nowrap; }
  .detail { font-size: 9pt; color: #333; margin-top: .8mm; line-height: 1.35; }
  .measure { font-size: 9pt; margin-top: 1.2mm; }
  td.std { width: 14mm; font-size: 9pt; text-align: right; white-space: nowrap; }
  td.time { width: 32mm; }
  .rule { display: block; border-bottom: .5pt solid #000; height: 4mm; }

  td.notes { border-bottom: none; padding-top: 1.5mm; }
  .cap { font-size: 8pt; text-transform: uppercase; letter-spacing: .07em; color: #444; }
  .lines i { display: block; border-bottom: .4pt solid #bbb; height: 5mm; }

  .write { border: 1pt solid #000; padding: 2.5mm 3mm; margin-bottom: 4mm;
           page-break-inside: avoid; }
  .write .wcap { font-size: 10pt; font-weight: bold; text-transform: uppercase;
                 letter-spacing: .05em; }
  .write .wsub { font-size: 8.5pt; color: #444; margin: .5mm 0 1.5mm; }

  .foot { margin-top: 5mm; border-top: 1.2pt solid ${BRAND}; padding-top: 2.5mm; font-size: 8.5pt;
          color: #333; display: flex; justify-content: space-between; gap: 6mm; flex-wrap: wrap; }
  .sign { margin-top: 7mm; display: flex; gap: 10mm; page-break-inside: avoid; }
  .sign div { flex: 1; border-top: .5pt solid #000; padding-top: 1.5mm; font-size: 8.5pt; }
  .empty { font-size: 10pt; padding: 6mm 0; }
</style>
</head>
<body>
  <div class="head">
    <div class="brand">
      <div class="brandleft">
        ${logoHtml}
        ${header.companyName ? `<span class="coname">${escapeHtml(header.companyName)}</span>` : ''}
      </div>
      <div class="doctype">
        <div class="kind">Roteiro de execução</div>
        <div class="num">${escapeHtml(header.orderNumber)}</div>
      </div>
    </div>
    ${infoLine ? `<div class="info">${infoLine}</div>` : ''}
    ${metaLine ? `<div class="meta">${metaLine}</div>` : ''}
  </div>

  ${materiaisHtml}
  ${steps.length ? blocksHtml : '<p class="empty">Esta OS ainda não tem roteiro gerado.</p>'}

  <div class="write">
    <div class="wcap">O que encontrei · o que ficou pendente</div>
    <div class="wsub">Vai para a OS como registro do serviço. É o que faz o próximo atendimento
      começar informado.</div>
    ${ruledLines(4)}
  </div>

  <div class="write">
    <div class="wcap">Material usado além do previsto</div>
    <div class="wsub">Peça, quantidade e em qual etapa foi aplicada — para entrar na OS e não
      sumir da margem.</div>
    ${ruledLines(3)}
  </div>

  <div class="foot">
    <span>Travou? Anote o motivo ao lado do passo e avise o escritório.</span>
    ${header.shareUrl ? `<span>OS no sistema: ${escapeHtml(header.shareUrl)}</span>` : ''}
  </div>
  <div class="sign">
    <div>Assinatura do técnico</div>
    <div>Assinatura do cliente</div>
  </div>
  ${header.companyAddress || header.companyName ? `
    <div class="foot" style="border-top:none;padding-top:1.5mm">
      <span>${escapeHtml([header.companyName, header.companyAddress].filter(Boolean).join(' · '))}</span>
    </div>` : ''}
</body>
</html>`;
}

/** Abre a folha em nova janela e chama a impressão. */
export function printRouteSheet(
  header: RouteSheetHeader,
  steps: ServiceOrderStep[],
  materials: RouteMaterial[] = [],
): boolean {
  const win = window.open('', '_blank', 'width=900,height=1000');
  if (!win) return false; // bloqueador de pop-up; quem chama avisa o usuário
  win.document.write(buildRouteSheetHtml(header, steps, materials));
  win.document.close();
  win.focus();
  // Deixa o layout (e o logo) assentarem antes de abrir o diálogo de impressão.
  win.setTimeout(() => win.print(), 400);
  return true;
}
