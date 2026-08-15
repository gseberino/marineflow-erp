/**
 * A folha de levantamento — o papel que vai a campo antes de orçar.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * O QUE ELA É, E POR QUE NÃO É UM QUESTIONÁRIO IMPRESSO
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Imprimir as perguntas do catálogo numa folha já ajudaria, e seria pouco. A
 * pesquisa de por que orçamento estoura aponta três causas que nenhuma lista de
 * perguntas resolve sozinha:
 *
 *  1. O QUE SEMPRE APARECE E NINGUÉM ORÇA. "Se você costuma abrir paredes e
 *     sabe o que costuma achar, ponha isso na estimativa desde o início em vez
 *     de tratar cada ocorrência como surpresa." A folha traz o histórico REAL
 *     daquele serviço — quantas vezes foi feito, o previsto contra o realizado
 *     — na mão de quem está decidindo o preço.
 *
 *  2. O "JÁ QUE VOCÊ ESTÁ AQUI". O cliente pede mais uma coisinha, o técnico
 *     faz, e como não foi registrado no momento aquilo não existe no sistema:
 *     não chega ao faturamento, não chega à precificação. Vira trabalho de
 *     graça. A folha tem um bloco só para isso, com espaço para escrever no
 *     instante em que acontece.
 *
 *  3. A INCERTEZA QUE NÃO É DITA. O que não deu para verificar volta como
 *     surpresa na execução. Declarado no papel, vira contingência no preço.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * COMO ELA É CONSTRUÍDA (Gawande, "The Checklist Manifesto")
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * · DO-CONFIRM, não READ-DO. O técnico é experiente: ele levanta do jeito
 *   dele e a folha serve para conferir se não faltou nada. Por isso o bloco
 *   das perguntas vem depois do bloco de partida, e não como roteiro rígido.
 *
 * · KILLER ITEMS em destaque. As perguntas de impacto ALTO no preço vêm
 *   marcadas e primeiro; o resto vem menor. Checklist bom é curto e cobre o
 *   que é perigoso pular — não o que é fácil listar.
 *
 * · PAUSE POINTS curtos. Cada bloco se resolve em menos de um minuto e meio;
 *   passou disso, quem está em campo começa a pular etapa.
 *
 * · CABE NO BOLSO E ACEITA CANETA. Linhas guia, caixas de marcar, unidade já
 *   impressa ao lado do campo de medida (para não voltar "14" sem saber se é
 *   metro ou centímetro) e um quadriculado para desenhar o percurso, que é
 *   espacial e não cabe em texto.
 */

import { supabase } from '@/integrations/supabase/client';

const BRAND = '#002B5B';

export interface SurveySheetHeader {
  orderNumber: string;
  clientName?: string | null;
  clientPhone?: string | null;
  assetName?: string | null;
  assetType?: string | null;
  marinaName?: string | null;
  serviceName?: string | null;
  technicianName?: string | null;
  companyName?: string | null;
  /** Endereço do serviço, para quem vai dirigindo. */
  address?: string | null;
}

export interface SurveySheetQuestion {
  id: string;
  question: string;
  help_text?: string | null;
  answer_type: string;
  options?: string[] | null;
  price_impact: string;
  /** Resposta que este mesmo ativo deu antes — para conferir em vez de perguntar. */
  previousAnswer?: string | null;
  previousWhen?: string | null;
}

/** O que o histórico sabe sobre este serviço. Vazio quando ainda não há base. */
export interface SurveySheetHistory {
  cases: number;
  p50Minutes?: number | null;
  p80Minutes?: number | null;
  /** Execuções passadas: número da OS e quanto levou de fato. */
  examples?: Array<{ os: string; minutos: number }>;
}

function esc(v: string | null | undefined): string {
  return String(v ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/** Linhas pautadas para escrever à mão. */
function ruled(n: number, cls = ''): string {
  return Array.from({ length: n }, () => `<div class="rule ${cls}"></div>`).join('');
}

function formatMin(min: number | null | undefined): string {
  if (!min) return '—';
  const h = Math.floor(min / 60);
  const m = Math.round(min % 60);
  return h ? `${h}h${m ? String(m).padStart(2, '0') : ''}` : `${m}min`;
}

/**
 * A unidade vai impressa ao lado do campo.
 *
 * "14" anotado sozinho volta e ninguém sabe se é metro, centímetro ou pé — e
 * quem mediu já foi embora. Deixar a unidade escrita custa um centímetro de
 * papel e economiza uma viagem.
 */
function fieldFor(q: SurveySheetQuestion): string {
  switch (q.answer_type) {
    case 'medida':
      return `<div class="field"><span class="line"></span><span class="unit">m &nbsp;·&nbsp; cm &nbsp;·&nbsp; mm</span></div>`;
    case 'numero':
      return `<div class="field"><span class="line short"></span><span class="unit">unid. / A / Ah / W</span></div>`;
    case 'sim_nao':
      return `<div class="field opts"><span class="box"></span> Sim &nbsp;&nbsp; <span class="box"></span> Não &nbsp;&nbsp; <span class="box"></span> Não deu para ver</div>`;
    case 'escolha':
      return q.options?.length
        ? `<div class="field opts">${q.options
            .map((o) => `<span class="box"></span> ${esc(o)}`)
            .join(' &nbsp;&nbsp; ')}</div>`
        : `<div class="field"><span class="line"></span></div>`;
    case 'foto':
      return `<div class="field opts"><span class="box"></span> Fotografei &nbsp;&nbsp; <span class="box"></span> Não deu — por quê: <span class="line short"></span></div>`;
    default:
      return `<div class="field"><span class="line"></span></div>`;
  }
}

export function buildSurveySheetHtml(
  header: SurveySheetHeader,
  questions: SurveySheetQuestion[],
  history: SurveySheetHistory = { cases: 0 },
): string {
  const altas = questions.filter((q) => q.price_impact === 'alto');
  const demais = questions.filter((q) => q.price_impact !== 'alto');

  const questionBlock = (q: SurveySheetQuestion, destaque: boolean) => `
    <div class="q ${destaque ? 'alta' : ''}">
      <div class="qtop">
        <span class="box big"></span>
        <div class="qtext">
          <div class="qtitle">${esc(q.question)}${
            destaque ? '<span class="tag">muda o preço</span>' : ''
          }${q.answer_type === 'foto' ? '<span class="tag foto">foto</span>' : ''}</div>
          ${q.help_text ? `<div class="qhelp">${esc(q.help_text)}</div>` : ''}
          ${
            q.previousAnswer
              ? `<div class="prev">Da última vez${
                  q.previousWhen ? ` (${esc(q.previousWhen)})` : ''
                }: <b>${esc(q.previousAnswer)}</b> &nbsp;—&nbsp; <span class="box"></span> continua igual</div>`
              : ''
          }
        </div>
      </div>
      ${fieldFor(q)}
    </div>`;

  // ── O que o histórico sabe ────────────────────────────────────────────────
  // Só aparece quando há base. Inventar "média de 2 casos" seria pior que o
  // silêncio: quem lê trata número como fato.
  const historyBlock =
    history.cases >= 3
      ? `
    <div class="hist">
      <div class="histtitle">O que já aconteceu neste serviço — ${history.cases} execuç${
          history.cases > 1 ? 'ões' : 'ão'
        }</div>
      <div class="histbody">
        <span>Costuma levar <b>${formatMin(history.p50Minutes)}</b></span>
        <span>Pior caso: <b>${formatMin(history.p80Minutes)}</b></span>
        ${
          history.examples?.length
            ? `<span class="ex">${history.examples
                .map((e) => `${esc(e.os)} ${formatMin(e.minutos)}`)
                .join(' · ')}</span>`
            : ''
        }
      </div>
      <div class="histnote">Se o que você está vendo indica mais que isso, escreva por quê no fechamento. É a diferença entre orçar o serviço e orçar a esperança.</div>
    </div>`
      : `
    <div class="hist vazio">
      <div class="histtitle">Sem histórico deste serviço ainda</div>
      <div class="histnote">Este levantamento vai formar a base. Anote o tempo que você ACHA que leva — na próxima, o sistema compara.
        &nbsp; Estimativa: <span class="line short"></span> h</div>
    </div>`;

  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8"/>
<title>Levantamento — ${esc(header.orderNumber)}</title>
<style>
  @page { size: A4; margin: 10mm 9mm; }
  * { box-sizing: border-box; }
  body { font-family: Arial, Helvetica, sans-serif; color: #000; margin: 0; font-size: 10pt; line-height: 1.25; }

  .head { border-bottom: 1.2pt solid ${BRAND}; padding-bottom: 2.5mm; margin-bottom: 3mm;
          display: flex; justify-content: space-between; align-items: flex-end; }
  .coname { font-size: 10.5pt; font-weight: bold; color: ${BRAND}; }
  .doctype { text-align: right; }
  .doctype .kind { font-size: 8.5pt; text-transform: uppercase; letter-spacing: .08em; color: #444; }
  .doctype .num { font-size: 13pt; font-weight: bold; color: ${BRAND}; }

  .info { font-size: 9pt; margin-bottom: 3mm; }
  .info b { color: #000; }
  .info .row { margin-bottom: .8mm; }

  /* Bloco de partida: o que se faz ANTES de olhar qualquer pergunta. */
  .start { border: 1pt solid ${BRAND}; padding: 2mm 2.5mm; margin-bottom: 3mm; }
  .starttitle { font-size: 9pt; font-weight: bold; color: ${BRAND}; text-transform: uppercase;
                letter-spacing: .05em; margin-bottom: 1.2mm; }
  .start ul { margin: 0; padding-left: 0; list-style: none; }
  .start li { font-size: 9pt; margin-bottom: 1mm; }

  .sectitle { font-size: 9pt; font-weight: bold; color: ${BRAND}; text-transform: uppercase;
              letter-spacing: .05em; border-bottom: .6pt solid #bbb; padding-bottom: .8mm;
              margin: 3.5mm 0 2mm; }

  .q { margin-bottom: 2.4mm; page-break-inside: avoid; }
  .q.alta { border-left: 2pt solid ${BRAND}; padding-left: 2mm; }
  .qtop { display: flex; gap: 2mm; }
  .qtitle { font-size: 9.5pt; font-weight: bold; }
  .qhelp { font-size: 8pt; color: #555; margin-top: .3mm; }
  .prev { font-size: 8pt; color: #333; margin-top: .6mm; background: #f4f4f4; padding: .6mm 1.2mm; }
  .tag { font-size: 7pt; font-weight: normal; text-transform: uppercase; letter-spacing: .04em;
         border: .5pt solid ${BRAND}; color: ${BRAND}; padding: 0 1mm; margin-left: 1.5mm; }
  .tag.foto { border-color: #a06000; color: #a06000; }

  .box { display: inline-block; width: 3.2mm; height: 3.2mm; border: .8pt solid #333; vertical-align: -.4mm; }
  .box.big { width: 4mm; height: 4mm; flex: 0 0 4mm; margin-top: .5mm; }

  .field { margin: 1mm 0 0 6mm; }
  .field .line { display: inline-block; border-bottom: .6pt solid #333; width: 78%; height: 4.5mm; }
  .field .line.short { width: 28%; }
  .field .unit { font-size: 7.5pt; color: #666; margin-left: 2mm; }
  .field.opts { font-size: 9pt; }

  .rule { border-bottom: .5pt solid #bbb; height: 5.2mm; }
  .rule.tight { height: 4.4mm; }

  .hist { border: .8pt dashed #888; padding: 2mm 2.5mm; margin-bottom: 3mm; background: #fafafa; }
  .hist.vazio { border-style: dotted; }
  .histtitle { font-size: 9pt; font-weight: bold; color: ${BRAND}; }
  .histbody { font-size: 9pt; margin-top: 1mm; display: flex; gap: 5mm; flex-wrap: wrap; }
  .histbody .ex { color: #555; font-size: 8pt; }
  .histnote { font-size: 7.5pt; color: #555; margin-top: 1mm; font-style: italic; }

  .twocol { display: flex; gap: 4mm; }
  .twocol > div { flex: 1; }

  /* Quadriculado para desenhar o percurso — cabo e mangueira são espaciais. */
  .grid { height: 42mm; border: .8pt solid #999;
          background-image: linear-gradient(#e2e2e2 .3pt, transparent .3pt),
                            linear-gradient(90deg, #e2e2e2 .3pt, transparent .3pt);
          background-size: 4mm 4mm; }

  .close { border: 1.2pt solid ${BRAND}; padding: 2.5mm; margin-top: 3.5mm; page-break-inside: avoid; }
  .closerow { display: flex; gap: 4mm; font-size: 9pt; align-items: center; margin-bottom: 1.5mm; }

  .sign { display: flex; gap: 6mm; margin-top: 5mm; }
  .sign > div { flex: 1; text-align: center; }
  .signline { border-top: .8pt solid #333; padding-top: 1mm; font-size: 8pt; color: #444; }

  .foot { margin-top: 4mm; border-top: 1pt solid ${BRAND}; padding-top: 1.5mm;
          font-size: 7.5pt; color: #555; display: flex; justify-content: space-between; }
</style>
</head>
<body>

<div class="head">
  <div>
    <div class="coname">${esc(header.companyName || 'HBR Marine Solutions')}</div>
    <div style="font-size:8pt;color:#555;">Levantamento técnico — preencher no local, antes de orçar</div>
  </div>
  <div class="doctype">
    <div class="kind">Levantamento</div>
    <div class="num">${esc(header.orderNumber)}</div>
  </div>
</div>

<div class="info">
  <div class="row">
    ${header.clientName ? `Cliente: <b>${esc(header.clientName)}</b>` : ''}
    ${header.clientPhone ? ` &nbsp;·&nbsp; Contato: <b>${esc(header.clientPhone)}</b>` : ''}
    ${header.assetName ? ` &nbsp;·&nbsp; ${esc(header.assetType || 'Ativo')}: <b>${esc(header.assetName)}</b>` : ''}
  </div>
  <div class="row">
    ${header.serviceName ? `Serviço: <b>${esc(header.serviceName)}</b>` : ''}
    ${header.marinaName ? ` &nbsp;·&nbsp; Local: <b>${esc(header.marinaName)}</b>` : ''}
    ${header.address ? ` &nbsp;·&nbsp; ${esc(header.address)}` : ''}
  </div>
  <div class="row">
    Técnico: <b>${esc(header.technicianName || '________________________')}</b>
    &nbsp;·&nbsp; Data: ____ / ____ / ______
    &nbsp;·&nbsp; Chegada: ____:____ &nbsp; Saída: ____:____
  </div>
</div>

<div class="start">
  <div class="starttitle">Antes de abrir a trena</div>
  <ul>
    <li><span class="box"></span> <b>Perguntei ao cliente o que ele espera</b> — o problema que ele descreve nem sempre é o que ele quer resolver.</li>
    <li><span class="box"></span> <b>Fotografei o conjunto ANTES de mexer</b> — depois de desmontado não dá para voltar e provar como estava.</li>
    <li><span class="box"></span> <b>Perguntei o que já tentaram antes</b> — serviço que outro já mexeu esconde o dobro do trabalho.</li>
  </ul>
</div>

${historyBlock}

<div class="sectitle">O que muda o preço</div>
${altas.map((q) => questionBlock(q, true)).join('')}

${demais.length ? `<div class="sectitle">Bom saber antes de orçar</div>${demais.map((q) => questionBlock(q, false)).join('')}` : ''}

<div class="twocol">
  <div>
    <div class="sectitle">Enquanto eu estava lá</div>
    <div style="font-size:8pt;color:#555;margin-bottom:1mm;">
      O que o cliente pediu além do combinado, e o que você viu que vai dar problema.
      <b>Escreva na hora</b> — o que não é anotado aqui não chega ao orçamento e vira trabalho de graça.
    </div>
    ${ruled(5)}
  </div>
  <div>
    <div class="sectitle">O que NÃO deu para verificar</div>
    <div style="font-size:8pt;color:#555;margin-bottom:1mm;">
      Cada linha aqui vira gordura no preço, e é honesto que vire.
      Ficar em silêncio é que sai caro depois.
    </div>
    ${ruled(5)}
  </div>
</div>

<div class="sectitle">Croqui — onde passa, onde entra, onde não cabe</div>
<div class="grid"></div>

<div class="close">
  <div class="closerow">
    <b>Dá para orçar com o que eu vi?</b>
    <span><span class="box"></span> Sim, com segurança</span>
    <span><span class="box"></span> Sim, com ressalva</span>
    <span><span class="box"></span> Não — preciso voltar</span>
  </div>
  <div style="font-size:8.5pt;color:#444;margin-bottom:1mm;">
    Em uma linha: o que você já sabe e o que ficou em aberto.
  </div>
  ${ruled(2, 'tight')}
  <div class="closerow" style="margin-top:2mm;">
    <b>Se precisar voltar, levar:</b>
    <span class="rule" style="flex:1;"></span>
  </div>
</div>

<div class="sign">
  <div><div class="signline">Técnico que levantou</div></div>
  <div><div class="signline">Quem acompanhou no local</div></div>
</div>

<div class="foot">
  <span>Lance no sistema em ${esc(header.orderNumber)} → aba Levantamento. O que não for lançado se perde.</span>
  <span>${esc(header.companyName || 'HBR Marine Solutions')}</span>
</div>

</body>
</html>`;
}

/**
 * Abre a folha numa janela e manda imprimir.
 *
 * A janela imprime a si mesma, por script embutido: chamar `print()` de fora
 * atravessa contextos e o Chrome recusa com "The provided callback is no longer
 * runnable" — erro que já apareceu na tela deste ERP.
 */
export function printSurveySheet(
  header: SurveySheetHeader,
  questions: SurveySheetQuestion[],
  history?: SurveySheetHistory,
): void {
  const html = buildSurveySheetHtml(header, questions, history);
  const win = window.open('', '_blank');
  if (!win) {
    throw new Error(
      'O navegador bloqueou a janela de impressão. Libere os pop-ups para este site.',
    );
  }
  const autoPrint =
    '<script>window.addEventListener("load",function(){' +
    'requestAnimationFrame(function(){setTimeout(function(){window.print();},50);});' +
    '});<\/script>';
  win.document.write(html.replace('</body>', `${autoPrint}</body>`));
  win.document.close();
  win.focus();
}

/**
 * Junta o que a folha precisa: perguntas do serviço, memória do ativo e o
 * histórico de execuções. Uma chamada só, para o botão não depender de a tela
 * ter carregado três hooks antes.
 */
export async function fetchSurveySheetData(
  serviceId: string,
  vesselId?: string | null,
  serviceOrderId?: string | null,
): Promise<{ header: Partial<SurveySheetHeader>; questions: SurveySheetQuestion[]; history: SurveySheetHistory }> {
  const [qRes, histRes, prevRes, osRes, cfgRes] = await Promise.all([
    supabase.rpc('compose_survey_for_service', { p_service_id: serviceId, p_mode: 'local' }),
    supabase.rpc('estimate_from_cases', { p_service_id: serviceId }),
    vesselId
      ? supabase.rpc('previous_survey_answers', { p_vessel_id: vesselId })
      : Promise.resolve({ data: [] as any[] }),
    // O cabeçalho da folha sai daqui: quem vai a campo precisa do número da
    // ordem, do contato de quem está no local e do nome do ativo. Sem isso o
    // papel volta sem dono.
    serviceOrderId
      ? supabase
          .from('service_orders')
          .select('service_order_number, clients(name, phone, whatsapp), vessels(name, asset_type), marinas(name)')
          .eq('id', serviceOrderId)
          .maybeSingle()
      : Promise.resolve({ data: null as any }),
    supabase.from('app_settings').select('key, value').in('key', ['company_name']),
  ]);

  const anteriores = new Map<string, { answer: string; when: string | null }>();
  for (const p of ((prevRes as any).data || []) as any[]) {
    anteriores.set(p.template_id, { answer: p.answer, when: p.service_order_number });
  }

  const est = (histRes.data || {}) as any;
  const os = (osRes as any).data as any;
  const cfg = (((cfgRes as any).data || []) as Array<{ key: string; value: string }>)
    .find((r) => r.key === 'company_name');

  // O serviço: o nome vem da linha da ordem, que é o que o cliente contratou.
  let serviceName: string | null = null;
  if (serviceOrderId) {
    const { data: linha } = await supabase
      .from('service_order_services')
      .select('name_snapshot')
      .eq('service_order_id', serviceOrderId)
      .eq('service_id', serviceId)
      .limit(1)
      .maybeSingle();
    serviceName = (linha as any)?.name_snapshot ?? null;
  }

  return {
    header: {
      orderNumber: os?.service_order_number ?? undefined,
      clientName: os?.clients?.name ?? null,
      clientPhone: os?.clients?.whatsapp || os?.clients?.phone || null,
      assetName: os?.vessels?.name ?? null,
      assetType: os?.vessels?.asset_type ?? null,
      marinaName: os?.marinas?.name ?? null,
      serviceName,
      companyName: cfg?.value || null,
    },
    questions: ((qRes.data || []) as any[]).map((q) => ({
      id: q.id,
      question: q.question,
      help_text: q.help_text,
      answer_type: q.answer_type,
      options: q.options,
      price_impact: q.price_impact,
      previousAnswer: anteriores.get(q.id)?.answer ?? null,
      previousWhen: anteriores.get(q.id)?.when ?? null,
    })),
    history: est?.tem_base
      ? {
          cases: est.casos,
          p50Minutes: est.p50_min,
          p80Minutes: est.p80_min,
          examples: (est.baseado_em || []).map((c: any) => ({ os: c.os, minutos: c.minutos })),
        }
      : { cases: est?.casos ?? 0 },
  };
}
