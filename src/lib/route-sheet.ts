import {
  groupStepsByBlock, isAiDraft,
  type ServiceOrderStep, type RouteMaterial,
} from '@/hooks/use-service-steps';

export interface RouteSheetHeader {
  orderNumber: string;
  clientName?: string | null;
  /** Telefone e WhatsApp do cliente: o técnico não pode depender do escritório para achá-lo. */
  clientPhone?: string | null;
  clientWhatsapp?: string | null;
  /** Quem pediu o serviço, quando não é o próprio cliente (marinheiro, caseiro, gerente). */
  requestedBy?: string | null;
  assetName?: string | null;
  assetType?: string | null;
  assetMaker?: string | null;
  assetModel?: string | null;
  marinaName?: string | null;
  /** Vaga ou píer do barco, do cadastro do ativo. */
  dockPosition?: string | null;
  technicianName?: string | null;
  scheduledAt?: string | null;
  scheduledEndAt?: string | null;
  /** O pedido do cliente (descrição da OS). Linhas com valor em R$ não saem. */
  problemDescription?: string | null;
  /** Identidade da empresa — a mesma do PDF do orçamento. */
  companyName?: string | null;
  companyLogoUrl?: string | null;
  companyAddress?: string | null;
  companyPhone?: string | null;
}

/** O que a via do técnico traz além do roteiro: serviços contratados e o levantamento. */
export interface RouteSheetExtras {
  services?: Array<{
    /** Id da linha da OS: liga o material lançado para este serviço ao cartão dele. */
    id?: string | null;
    name: string;
    description?: string | null;
    quantity?: number | null;
    unit?: string | null;
    notes?: string | null;
  }>;
  survey?: Array<{
    question: string;
    answer?: string | null;
    skipped?: string | null;
    photoUrl?: string | null;
  }>;
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

/**
 * Tira do texto toda linha com valor em reais. A descrição da OS também vai para o
 * orçamento do cliente; se um dia alguém escrever condição de pagamento nela, o
 * técnico continua sem ver preço (decisão do dono, 12/08: preço não vai na via).
 */
export function semValores(texto: string | null | undefined): string {
  if (!texto) return '';
  return texto
    .split(/\r?\n/)
    .filter((linha) => !/R\$/i.test(linha))
    .join('\n')
    .trim();
}

/** Texto corrido com quebra de linha preservada, um parágrafo por linha. */
function paragrafos(texto: string): string {
  return texto
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean)
    .map((l) => `<p>${escapeHtml(l)}</p>`)
    .join('');
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

/** Caixa de marcar, já preenchida quando o passo foi feito no sistema. */
function stepBox(step: ServiceOrderStep): string {
  if (step.status === 'done') return '<span class="check done">✓</span>';
  if (step.status === 'not_applicable') return '<span class="check na">—</span>';
  return '<span class="check"></span>';
}

function stepStatusNote(step: ServiceOrderStep): string {
  if (step.status === 'done') return '<div class="stnote">Feito (registrado no sistema)</div>';
  if (step.status === 'not_applicable') {
    return `<div class="stnote">Não se aplica${step.na_reason ? `: ${escapeHtml(step.na_reason)}` : ''}</div>`;
  }
  if (step.status === 'blocked') {
    return `<div class="stnote">Travado${step.blocked_note ? `: ${escapeHtml(step.blocked_note)}` : ''}</div>`;
  }
  return '';
}

/** "Motorhome · Itapoã Sprinter · "Itapoã"" sem repetir o que o nome já diz. */
function vehicleLine(h: RouteSheetHeader): string {
  const marcaModelo = [h.assetMaker, h.assetModel].map((v) => (v || '').trim()).filter(Boolean).join(' ');
  const partes = [h.assetType, marcaModelo].map((v) => (v || '').trim()).filter(Boolean);
  const nome = (h.assetName || '').trim();
  if (nome && !partes.some((p) => p.toLowerCase() === nome.toLowerCase())) partes.push(`"${nome}"`);
  return partes.map(escapeHtml).join(' · ');
}

/** O fim só sai quando é depois do início — um término anterior ao começo só confunde. */
function whenLine(h: RouteSheetHeader): string {
  const inicio = formatDateBr(h.scheduledAt);
  if (!inicio) return '<span class="vazio">A combinar com o escritório</span>';
  const fimValido = h.scheduledEndAt && h.scheduledAt
    && new Date(h.scheduledEndAt).getTime() > new Date(h.scheduledAt).getTime();
  return fimValido ? `<b>${inicio}</b> → ${formatDateBr(h.scheduledEndAt)}` : `<b>${inicio}</b>`;
}

function whereLine(h: RouteSheetHeader): string {
  const partes = [
    h.marinaName && escapeHtml(h.marinaName),
    h.dockPosition && `vaga ${escapeHtml(h.dockPosition)}`,
  ].filter(Boolean);
  return partes.length
    ? `<b>${partes.join(' · ')}</b>`
    : '<span class="vazio">Local não informado na OS. Confirme com o cliente antes de sair.</span>';
}

function contactLines(h: RouteSheetHeader): string {
  const linhas: string[] = [];
  const tel = (h.clientPhone || '').trim();
  const zap = (h.clientWhatsapp || '').trim();
  const numeros = tel && zap && tel.replace(/\D/g, '') === zap.replace(/\D/g, '')
    ? `tel./WhatsApp ${escapeHtml(tel)}`
    : [tel && `tel. ${escapeHtml(tel)}`, zap && `WhatsApp ${escapeHtml(zap)}`].filter(Boolean).join(' · ');
  if (h.clientName) {
    linhas.push(`Cliente: <b>${escapeHtml(h.clientName)}</b>${
      numeros ? ` — ${numeros}` : ' — <span class="vazio">sem telefone no cadastro</span>'}`);
  }
  if (h.requestedBy && h.requestedBy.trim() && h.requestedBy.trim() !== (h.clientName || '').trim()) {
    linhas.push(`Pedido por: <b>${escapeHtml(h.requestedBy)}</b>`);
  }
  if (h.companyPhone) linhas.push(`Escritório: <b>${escapeHtml(h.companyPhone)}</b>`);
  return linhas.map((l) => `<div>${l}</div>`).join('');
}

/**
 * Via do técnico — a folha A4 que o técnico segue no barco ou no motorhome, sem
 * poder ligar para o escritório.
 *
 * Organizada pelas três perguntas de quem está no local, nesta ordem: o que preciso
 * saber antes de sair (veículo, quando, onde, com quem falar, o pedido do cliente,
 * material e limites), o que faço em cada serviço, e o que devolvo ao sair. O
 * roteiro de passos, quando existe, vem depois dos serviços.
 *
 * Preto e branco, fonte grande, quadradinho para marcar — a cor nunca carrega
 * informação sozinha e tudo aguenta fotocópia. Preço não entra (decisão do dono,
 * 12/08), nem o link do portal do cliente, que mostra preço.
 *
 * Avaliação que orientou o desenho (01/10/2026): a via imprimia só o nome dos
 * serviços e deixava de fora o que já estava no sistema (pedido do cliente,
 * telefone, vaga, marca e modelo).
 */
export function buildRouteSheetHtml(
  header: RouteSheetHeader,
  steps: ServiceOrderStep[],
  materials: RouteMaterial[] = [],
  extras: RouteSheetExtras = {},
): string {
  // Sugestão da IA ainda não aprovada não é roteiro: não vai para o papel.
  const passos = steps.filter((s) => !isAiDraft(s));
  const groups = groupStepsByBlock(passos);
  const numero = escapeHtml(header.orderNumber);

  // ── Folha de rosto ──────────────────────────────────────────────────────────
  const veiculo = vehicleLine(header);
  const contatos = contactLines(header);
  const pedido = semValores(header.problemDescription);
  const rostoHtml = `
    <div class="rosto">
      <div class="campo"><span class="lab">Veículo</span>${veiculo || '<span class="vazio">não informado</span>'}</div>
      <div class="campo"><span class="lab">Quando</span>${whenLine(header)}</div>
      <div class="campo"><span class="lab">Onde</span>${whereLine(header)}</div>
      <div class="campo"><span class="lab">Com quem falar</span>${contatos || '<span class="vazio">sem contato no cadastro</span>'}</div>
      ${header.technicianName ? `<div class="campo"><span class="lab">Técnico</span><b>${escapeHtml(header.technicianName)}</b></div>` : ''}
    </div>
    ${pedido ? `
    <div class="secao">
      <div class="sectitle">Pedido do cliente</div>
      <div class="pedido">${paragrafos(pedido)}</div>
    </div>` : ''}`;

  // ── Antes de sair: separação de materiais (ou o aviso de que não há nenhum) ──
  const materiaisHtml = materials.length ? `
    <table class="block">
      <thead>
        <tr><th colspan="2" class="blockname">Antes de sair · separação de materiais</th></tr>
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
    </table>` : `
    <div class="aviso">
      <b>Nenhum material lançado nesta OS.</b> Confirme com o escritório o que levar antes de sair.
    </div>`;

  // ── Limites: o que fazer quando aparece algo fora da lista ───────────────────
  const limitesHtml = `
    <div class="limite">
      <b>Achou outro defeito ou algo fora desta lista?</b> Anote, fotografe e
      <b>não execute</b> sem aprovação do cliente pelo escritório.
    </div>`;

  // ── Serviços: um cartão por serviço, com material e o que devolver ───────────
  const servicos = extras.services ?? [];
  const servicosHtml = servicos.length ? `
    <div class="secao">
      <div class="sectitle">Serviços desta OS</div>
      ${servicos.map((s, i) => {
        const doServico = s.id ? materials.filter((m) => m.service_order_service_id === s.id) : [];
        const qtd = s.quantity && Number(s.quantity) !== 1
          ? ` <span class="sku">× ${escapeHtml(String(s.quantity))}${s.unit ? ` ${escapeHtml(s.unit)}` : ''}</span>` : '';
        const descricao = semValores(s.description);
        const notas = semValores(s.notes);
        return `
        <div class="svc">
          <div class="svctitle">${i + 1} · ${escapeHtml(s.name)}${qtd}</div>
          ${descricao ? `<div class="detail">${paragrafos(descricao)}</div>` : ''}
          ${notas ? `<div class="detail">${paragrafos(notas)}</div>` : ''}
          ${doServico.length ? `<div class="svcmat"><span class="matlabel">Material deste serviço:</span>
            ${doServico.map((m) => materialLine(m)).join(' &nbsp;·&nbsp; ')}</div>` : ''}
          <div class="volta">
            <span class="check sm"></span> feito &nbsp;&nbsp;
            <span class="check sm"></span> parcial &nbsp;&nbsp;
            <span class="check sm"></span> não feito &nbsp;·&nbsp; motivo: <span class="rule inline"></span>
          </div>
        </div>`;
      }).join('')}
    </div>` : '';

  // ── Levantamento: as respostas inteiras, com as fotos marcadas (decisão do dono) ───────
  const respostas = (extras.survey ?? []).filter((r) => r.question);
  const levantamentoHtml = respostas.length ? `
    <table class="block">
      <thead>
        <tr><th colspan="2" class="blockname">Levantamento</th></tr>
        <tr class="cols"><th>Pergunta</th><th>Resposta no local</th></tr>
      </thead>
      <tbody>
        ${respostas.map((r) => `
          <tr>
            <td class="qa">${escapeHtml(r.question)}</td>
            <td class="qa">${
              r.skipped
                ? `<span class="pulada">pulada: ${escapeHtml(r.skipped)}</span>`
                : escapeHtml(r.answer || '—')
            }${r.photoUrl ? `<div><img class="foto" src="${escapeHtml(r.photoUrl)}" alt=""></div>` : ''}</td>
          </tr>`).join('')}
      </tbody>
    </table>` : '';

  // ── Roteiro de passos, quando a OS tem ──────────────────────────────────────
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
          <td class="box">${stepBox(step)}</td>
          <td class="seq">${step.seq}</td>
          <td class="step">
            <div class="title">${escapeHtml(step.title)}${
              marks.length ? ` <span class="marks">${marks.join(' · ')}</span>` : ''
            }</div>
            ${step.detail ? `<div class="detail">${escapeHtml(step.detail)}</div>` : ''}
            ${measure}
            ${stepStatusNote(step)}
          </td>
          <td class="std">${step.standard_minutes ? `${step.standard_minutes}min` : ''}</td>
          <td class="time"><span class="rule"></span></td>
        </tr>`;
    }).join('');

    return `
      <table class="block">
        <thead>
          <tr>
            <th colspan="5" class="blockname">${escapeHtml(group.block)}</th>
          </tr>
          ${group.note ? `<tr><th colspan="5" class="blocknote">${escapeHtml(group.note)}</th></tr>` : ''}
          ${doBloco.length ? `<tr><th colspan="5" class="blockmat">
            <span class="matlabel">Material desta etapa:</span>
            ${doBloco.map((m) => materialLine(m)).join(' &nbsp;·&nbsp; ')}
          </th></tr>` : ''}
          <tr class="cols">
            <th></th><th>#</th><th>Passo</th><th>Ref.</th><th>Início / fim</th>
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

  const roteiroHtml = passos.length ? `
    <div class="secao">
      <div class="sectitle">Roteiro de execução</div>
      <div class="roteironote">Marque cada passo ao terminar, nunca antes. Interrompido? Volte três
        passos e confira antes de seguir. Travou? Anote o motivo ao lado do passo.</div>
    </div>
    ${blocksHtml}` : '';

  const logoHtml = header.companyLogoUrl
    ? `<img class="logo" src="${escapeHtml(header.companyLogoUrl)}" alt="">`
    : '';

  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>Via do técnico ${numero}</title>
<style>
  /* Número da OS e página em toda folha: folha solta continua identificável. */
  @page {
    size: A4; margin: 11mm 10mm 14mm;
    @bottom-right { content: "${numero} · pág. " counter(page) " de " counter(pages);
                    font: 8pt Arial, Helvetica, sans-serif; color: #444; }
  }
  * { box-sizing: border-box; }
  body { font-family: Arial, Helvetica, sans-serif; color: #000; margin: 0; font-size: 11pt;
         -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  p { margin: 0 0 1mm; }

  /* Cabeçalho: marca discreta — logo pequeno e um filete, sem faixa cheia. */
  .head { border-bottom: 1.2pt solid ${BRAND}; padding-bottom: 3mm; margin-bottom: 4mm; }
  .brand { display: flex; align-items: center; justify-content: space-between; gap: 6mm; }
  .brandleft { display: flex; align-items: center; gap: 3mm; min-width: 0; }
  .logo { height: 11mm; width: auto; max-width: 45mm; object-fit: contain; }
  .coname { font-size: 11pt; font-weight: bold; color: ${BRAND}; letter-spacing: .01em; }
  .doctype { text-align: right; white-space: nowrap; }
  .doctype .kind { font-size: 8pt; letter-spacing: .1em; text-transform: uppercase; color: #444; }
  .doctype .num { font-size: 14pt; font-weight: bold; color: ${BRAND}; }

  /* Folha de rosto: o que decide se a viagem vale a pena. */
  .rosto { display: grid; grid-template-columns: 1fr 1fr; gap: 2.5mm 8mm; margin-bottom: 4mm;
           page-break-inside: avoid; }
  .campo { font-size: 10pt; line-height: 1.35; }
  .lab { display: block; font-size: 7.5pt; letter-spacing: .09em; text-transform: uppercase; color: #444; }
  .vazio { font-style: italic; color: #333; }
  .secao { margin-bottom: 4mm; }
  .sectitle { font-size: 11pt; text-transform: uppercase; letter-spacing: .06em; font-weight: bold;
              padding: 2mm 0 1mm; border-bottom: 1pt solid #000; margin-bottom: 2mm; }
  .pedido { font-size: 10pt; line-height: 1.4; }
  .aviso { border: 1.2pt solid #000; padding: 2.5mm 3mm; margin-bottom: 4mm; font-size: 10pt;
           page-break-inside: avoid; }
  .limite { border: 1pt dashed #000; padding: 2.5mm 3mm; margin-bottom: 5mm; font-size: 10pt;
            page-break-inside: avoid; }

  /* Cartão de serviço: o que fazer e o que devolver, juntos. */
  .svc { border: .8pt solid #555; padding: 2.5mm 3mm; margin-bottom: 3mm; page-break-inside: avoid; }
  .svctitle { font-weight: bold; font-size: 10.5pt; line-height: 1.3; }
  .svcmat { font-size: 9pt; margin-top: 1.5mm; }
  .volta { font-size: 9pt; margin-top: 2.5mm; padding-top: 1.5mm; border-top: .4pt dotted #999;
           display: flex; align-items: center; flex-wrap: wrap; gap: 1mm; }
  .rule.inline { display: inline-block; flex: 1; min-width: 40mm; height: 3.5mm; }

  table.block { width: 100%; border-collapse: collapse; margin-bottom: 5mm; page-break-inside: auto; }
  .blockname { text-align: left; font-size: 11pt; text-transform: uppercase;
               letter-spacing: .06em; padding: 2mm 0 1mm; border-bottom: 1pt solid #000; }
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
  .check { display: block; width: 5mm; height: 5mm; border: 1pt solid #000;
           font-size: 9pt; line-height: 4.6mm; text-align: center; font-weight: bold; }
  .check.sm { display: inline-block; width: 3.6mm; height: 3.6mm; vertical-align: -.6mm; }
  .stnote { font-size: 8.5pt; font-style: italic; margin-top: .8mm; }
  td.seq { width: 7mm; font-size: 9pt; color: #444; }
  td.mat { font-size: 10pt; }
  .sku { font-size: 8.5pt; color: #555; }
  .title { font-weight: bold; font-size: 10.5pt; line-height: 1.3; }
  .marks { font-weight: normal; font-size: 7.5pt; letter-spacing: .05em; border: .5pt solid #000;
           padding: 0 1mm; white-space: nowrap; }
  .detail { font-size: 9pt; color: #333; margin-top: .8mm; line-height: 1.35; }
  .measure { font-size: 9pt; margin-top: 1.2mm; }
  .roteironote { font-size: 9pt; color: #222; }
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
  .horas { display: flex; gap: 10mm; font-size: 10pt; margin-bottom: 4mm; page-break-inside: avoid; }
  .horas span { display: inline-block; min-width: 22mm; border-bottom: .5pt solid #000; }

  .foot { margin-top: 4mm; border-top: 1.2pt solid ${BRAND}; padding-top: 2.5mm; font-size: 8.5pt;
          color: #333; display: flex; justify-content: space-between; gap: 6mm; flex-wrap: wrap; }
  .sign { margin-top: 6mm; display: flex; gap: 10mm; page-break-inside: avoid; }
  .sign > div { flex: 1; font-size: 8.5pt; }
  .sign .atesta { font-size: 9pt; min-height: 8mm; }
  .sign .linha { border-top: .5pt solid #000; padding-top: 1.2mm; margin-top: 7mm; }
  td.qa { font-size: 9.5pt; width: 50%; }
  .pulada { color: #666; font-style: italic; }
  .foto { display: block; max-height: 45mm; max-width: 80mm; margin-top: 1.5mm; border: .5pt solid #999; }
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
        <div class="kind">Via do técnico</div>
        <div class="num">${numero}</div>
      </div>
    </div>
  </div>

  ${rostoHtml}
  ${materiaisHtml}
  ${limitesHtml}
  ${servicosHtml}
  ${levantamentoHtml}
  ${roteiroHtml}

  <div class="horas">
    <div>Chegada: <span></span></div>
    <div>Saída: <span></span></div>
  </div>

  <div class="write">
    <div class="wcap">O que encontrei · o que ficou pendente · o que vigiar da próxima vez</div>
    <div class="wsub">Vai para a OS como registro do serviço. É o que faz o próximo atendimento
      começar informado.</div>
    ${ruledLines(4)}
  </div>

  <div class="write">
    <div class="wcap">Material usado além do previsto</div>
    <div class="wsub">Peça, quantidade e em qual serviço foi aplicada — para entrar na OS e não
      sumir da margem.</div>
    ${ruledLines(3)}
  </div>

  <div class="sign">
    <div>
      <div class="atesta">Técnico responsável</div>
      <div class="linha">Nome legível</div>
      <div class="linha">Assinatura do técnico</div>
    </div>
    <div>
      <div class="atesta">Recebi os serviços marcados como feitos acima, testados na minha presença.</div>
      <div class="linha">Nome legível</div>
      <div class="linha">Assinatura do cliente · data ____/____/______ · hora ____:____</div>
    </div>
  </div>

  <div class="foot">
    <span>${header.companyPhone
      ? `Dúvida ou imprevisto: ligue para o escritório — <b>${escapeHtml(header.companyPhone)}</b>`
      : 'Dúvida ou imprevisto: fale com o escritório antes de decidir sozinho.'}</span>
    ${header.companyAddress || header.companyName
      ? `<span>${escapeHtml([header.companyName, header.companyAddress].filter(Boolean).join(' · '))}</span>`
      : ''}
  </div>
</body>
</html>`;
}

/** Abre a folha em nova janela e chama a impressão. */
export function printRouteSheet(
  header: RouteSheetHeader,
  steps: ServiceOrderStep[],
  materials: RouteMaterial[] = [],
  extras: RouteSheetExtras = {},
): boolean {
  const win = window.open('', '_blank', 'width=900,height=1000');
  if (!win) return false; // bloqueador de pop-up; quem chama avisa o usuário
  win.document.write(buildRouteSheetHtml(header, steps, materials, extras));
  win.document.close();
  win.focus();
  // Deixa o layout (e o logo) assentarem antes de abrir o diálogo de impressão.
  win.setTimeout(() => win.print(), 400);
  return true;
}
