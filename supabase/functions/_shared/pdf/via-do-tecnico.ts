// Via do técnico (job card) — o desenho da folha e a montagem dos dados dela.
//
// Morava em src/lib/route-sheet.ts. Veio para _shared em 13/11/2026 porque o assistente do
// WhatsApp passou a mandar a via em PDF (pedido do dono: a cada responsável pelos serviços da OS,
// e a ele quando pedir) e a agenda a anexa à ficha das 19:30. Uma cópia só: a tela imprime, o
// servidor renderiza, e as duas leem a MESMA folha. src/lib/route-sheet.ts reexporta daqui e
// guarda só o que é de navegador (abrir a janela e imprimir).
//
// Decisão do dono (13/11/2026): cada pessoa recebe só os serviços dela. A linha de serviço tem
// responsável (service_order_services.responsavel_payee_id); a via de uma pessoa leva as linhas
// dela e as sem responsável, e cita pelo nome as que estão com outra pessoa. Sem nenhuma linha
// marcada, todo mundo da OS recebe a via inteira (é o caso de hoje: quase nenhuma OS tem).

import { camposDoTipo, campoDaUnidade, ehFeminino, rotuloDaUnidade } from '../unidade.ts';
import { hashCurto } from '../whatsapp/idempotencia.ts';

// ── O roteiro de execução (tipos e funções puras que moravam em src/hooks/use-service-steps.ts) ──

export type StepStatus = 'pending' | 'in_progress' | 'done' | 'not_applicable' | 'blocked';
export type StepKind = 'do' | 'check' | 'safety' | 'evidence' | 'handoff';
export type StepMode = 'read_do' | 'do_confirm';
/** 'composed' = veio dos blocos (abertura do sistema + corpo do verbo + fechamento). */
export type StepOrigin = 'template' | 'ai' | 'manual' | 'client_request' | 'composed';

export interface ServiceOrderStep {
  id: string;
  service_order_id: string;
  service_order_service_id: string | null;
  template_id: string | null;
  seq: number;
  block: string | null;
  /** Chave estável do bloco: 'abertura:gas', 'linha:<uuid>', 'fechamento:gas'. */
  block_key: string | null;
  /** Escopo do bloco compartilhado: a quais serviços da OS ele se aplica. */
  block_note: string | null;
  title: string;
  detail: string | null;
  kind: StepKind;
  mode: StepMode;
  standard_minutes: number | null;
  is_killer: boolean;
  requires_photo: boolean;
  requires_measure: string | null;
  measure_unit: string | null;
  measure_value: number | null;
  status: StepStatus;
  na_reason: string | null;
  blocked_reason_code: string | null;
  blocked_note: string | null;
  assigned_user_id: string | null;
  started_at: string | null;
  completed_at: string | null;
  actual_minutes: number | null;
  origin: StepOrigin;
  notes: string | null;
  /** Preenchidos só quando origin='ai'. approved_at nulo = ainda é sugestão. */
  ai_confidence?: number | null;
  ai_source?: string | null;
  approved_at?: string | null;
}

/** Agrupa por bloco preservando a ordem de seq. */
export function groupStepsByBlock(
  steps: ServiceOrderStep[],
): Array<{ block: string; blockKey: string | null; note: string | null; steps: ServiceOrderStep[] }> {
  const groups: Array<{ block: string; blockKey: string | null; note: string | null; steps: ServiceOrderStep[] }> = [];
  for (const step of steps) {
    const label = step.block || 'Roteiro';
    const last = groups[groups.length - 1];
    if (last && last.block === label) last.steps.push(step);
    else groups.push({ block: label, blockKey: step.block_key ?? null, note: step.block_note ?? null, steps: [step] });
  }
  return groups;
}

/**
 * Material da OS, para a separação antes de sair e para a lista por etapa.
 *
 * `service_order_service_id` nulo = material da OS inteira (é o caso de todo
 * lançamento manual). Com dono, aparece dentro do bloco daquele serviço.
 */
export interface RouteMaterial {
  id: string;
  quantity: number;
  notes: string | null;
  service_order_service_id: string | null;
  products?: { name: string; sku: string | null; unit: string | null } | null;
}

export function isAiDraft(step: ServiceOrderStep & { approved_at?: string | null }): boolean {
  return step.origin === 'ai' && !step.approved_at;
}

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
  /** Placa (motorhome, trailer) ou inscrição (barco), do cadastro: ajuda a achar a unidade no pátio. */
  assetRegistration?: string | null;
  marinaName?: string | null;
  /** Vaga ou píer do barco, do cadastro do ativo. */
  dockPosition?: string | null;
  technicianName?: string | null;
  scheduledAt?: string | null;
  scheduledEndAt?: string | null;
  /** Na via de uma pessoa: os dias dela na agenda (aaaa-mm-dd). Vêm antes da data da OS no campo Quando. */
  diasNaAgenda?: string[] | null;
  /** O pedido do cliente (descrição da OS). Linhas com valor em R$ não saem. */
  problemDescription?: string | null;
  /** Instrução do escritório ao técnico (ressalvas, o que não fazer). Só sai aqui. */
  technicianInstructions?: string | null;
  /** Onde o serviço acontece e como entrar — da OS, ou o padrão do veículo. */
  siteAccess?: string | null;
  /** Quem estará no local (contato do veículo escolhido como solicitante). */
  onSiteContact?: { name?: string | null; role?: string | null; phone?: string | null } | null;
  /** O que já se sabe do sistema elétrico do veículo, do cadastro. */
  vehicleElectrical?: {
    batteryBank?: string | null;
    inverterCharger?: string | null;
    shorePower?: string | null;
    notes?: string | null;
  } | null;
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
    /** Instrução do escritório para este serviço. */
    technicianInstructions?: string | null;
    /** a_fazer | so_levantar | aguarda_peca | feito | parcial | nao_feito */
    fieldStatus?: string | null;
    fieldStatusNote?: string | null;
    /** Quem faz este serviço (nome), na via da OS inteira. Na via de uma pessoa não sai. */
    responsavel?: string | null;
  }>;
  /**
   * A via de UMA pessoa (decisão do dono, 13/11/2026: só os serviços dela). Com isto, o cabeçalho
   * diz de quem é a folha e o campo Técnico traz o nome dela.
   */
  pessoa?: { nome: string } | null;
  /** Os serviços desta OS que estão com outra pessoa — só o nome, para ela saber onde termina a parte dela. */
  outrosServicos?: Array<{ name: string; responsavel: string | null }>;
  survey?: Array<{
    question: string;
    answer?: string | null;
    skipped?: string | null;
    photoUrl?: string | null;
  }>;
  /**
   * Quanto do roteiro vai para o papel. `seguranca` (a via do menu Ações) leva só os
   * blocos "antes de mexer" e "antes de entregar" de cada sistema — os passos genéricos de
   * execução ficam de fora (decisão do dono, 01/10/2026). `completo` (o painel Roteiro)
   * imprime todos, para o roteiro continuar sendo testado à parte.
   */
  roteiro?: 'seguranca' | 'completo';
}

/**
 * Os passos de segurança do roteiro: abertura e fechamento de cada sistema. Roteiro antigo,
 * sem chave de bloco, contribui só com os passos marcados como segurança.
 */
export function passosDeSeguranca(steps: ServiceOrderStep[]): ServiceOrderStep[] {
  return steps.filter((s) => {
    const chave = s.block_key ?? '';
    if (chave) return chave.startsWith('abertura:') || chave.startsWith('fechamento:');
    return s.kind === 'safety';
  });
}

/** Uma linha de `seguranca_da_via` (banco): um passo de segurança gerado sem gravar roteiro. */
export interface LinhaDeSeguranca {
  papel: string;
  sistema: string;
  bloco: string;
  escopo: string | null;
  identificado_por: string;
  seq: number;
  title: string;
  detail: string | null;
  kind: string;
  is_killer: boolean;
  requires_photo: boolean;
  requires_measure: string | null;
  measure_unit: string | null;
  mode: string | null;
  standard_minutes: number | null;
}

/**
 * A segurança da via quando a OS NÃO tem roteiro (05/10/2026). Nenhuma OS ganhou roteiro desde
 * 14/08, e a via saía sem os blocos "Antes de mexer" e "Antes de entregar". O banco devolve os
 * mesmos blocos que o gerador gravaria (seguranca_da_via, só leitura); aqui eles viram passos com
 * a mesma chave e o mesmo rótulo numerado, para a via imprimir igual. Quando o sistema saiu do
 * texto do serviço (e não do cadastro), a nota do bloco diz isso.
 */
export function segurancaSemRoteiro(serviceOrderId: string, linhas: LinhaDeSeguranca[]): ServiceOrderStep[] {
  const numeroDoBloco = new Map<string, number>();
  return linhas.map((l, i) => {
    const chave = `${l.papel}:${l.sistema}`;
    if (!numeroDoBloco.has(chave)) numeroDoBloco.set(chave, numeroDoBloco.size + 1);
    const nota = l.identificado_por === 'texto da linha'
      ? `${l.escopo ?? ''} (sistema identificado pelo texto do serviço)`.trim()
      : l.escopo;
    return {
      id: `seguranca-${i}`,
      service_order_id: serviceOrderId,
      service_order_service_id: null,
      template_id: null,
      seq: i + 1,
      block: `${numeroDoBloco.get(chave)} · ${l.bloco}`,
      block_key: chave,
      block_note: nota,
      title: l.title,
      detail: l.detail,
      kind: l.kind as ServiceOrderStep['kind'],
      mode: (l.mode ?? 'read_do') as ServiceOrderStep['mode'],
      standard_minutes: l.standard_minutes,
      is_killer: l.is_killer,
      requires_photo: l.requires_photo,
      requires_measure: l.requires_measure,
      measure_unit: l.measure_unit,
      measure_value: null,
      status: 'pending',
      na_reason: null,
      blocked_reason_code: null,
      blocked_note: null,
      assigned_user_id: null,
      started_at: null,
      completed_at: null,
      actual_minutes: null,
      origin: 'composed',
      notes: null,
    } as ServiceOrderStep;
  });
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
  // Fuso de Brasília escrito: no navegador do escritório dá o mesmo de sempre, e no servidor
  // (Edge Function em UTC) a via não sai com a hora três adiantada.
  return d.toLocaleString('pt-BR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
    timeZone: 'America/Sao_Paulo',
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

/**
 * O que vai faltar no papel — o aviso antes de imprimir. O escritório decide se completa ou
 * imprime assim; o técnico, sem poder ligar, é quem pagaria pela lacuna.
 */
export function faltasDaVia(
  h: RouteSheetHeader,
  materials: RouteMaterial[],
  quantidadeDeServicos: number,
  /** A via não terá a parte de segurança: nem roteiro, nem sistema identificado nos serviços. */
  semSeguranca = false,
): string[] {
  const faltas: string[] = [];
  if (semSeguranca && quantidadeDeServicos > 0) faltas.push('segurança (nenhum sistema identificado nos serviços)');
  // Vaga é de barco: no veículo o campo nem aparece no cadastro (22/10/2026).
  const vaga = camposDoTipo(h.assetType).nauticos ? h.dockPosition : null;
  if (!h.marinaName && !vaga && !(h.siteAccess || '').trim()) faltas.push('local e acesso');
  const temTelefone = (h.clientPhone || h.clientWhatsapp || h.onSiteContact?.phone || '').trim();
  if (!temTelefone) faltas.push('telefone de contato');
  if (!h.scheduledAt) faltas.push('data e hora');
  if (quantidadeDeServicos === 0) faltas.push('serviços');
  if (!materials.length) faltas.push('material (nenhum lançado)');
  return faltas;
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

/**
 * A unidade da OS como rótulo e valor, pela regra única (src/lib/unidade.ts, decisão 9 de
 * 21/10/2026): o rótulo é o próprio tipo — "Motorhome" / "Itapoã · Itapoã Sprinter · placa
 * ABC1D23" —, e sem unidade nenhuma, o termo geral "Embarcação ou veículo".
 */
function vehicleLine(h: RouteSheetHeader): { rotulo: string; valor: string } {
  return campoDaUnidade({
    name: h.assetName,
    asset_type: h.assetType,
    manufacturer: h.assetMaker,
    model: h.assetModel,
    hull_id_or_registration: h.assetRegistration,
  });
}

const DIAS_DA_SEMANA = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
/** "qui 26/11" para aaaa-mm-dd. */
function diaCurto(dia: string): string {
  const [a, m, d] = dia.split('-').map(Number);
  return `${DIAS_DA_SEMANA[new Date(Date.UTC(a, m - 1, d)).getUTCDay()]} ${String(d).padStart(2, '0')}/${String(m).padStart(2, '0')}`;
}

/** O fim só sai quando é depois do início — um término anterior ao começo só confunde. */
function whenLine(h: RouteSheetHeader): string {
  const inicio = formatDateBr(h.scheduledAt);
  // Na via de uma pessoa, os dias DELA na agenda vêm primeiro (13/11/2026): a OS-00119 não tinha data própria e
  // a via dizia "a combinar" para quem tinha 11 dias marcados.
  const dias = (h.diasNaAgenda ?? []).filter((d) => /^\d{4}-\d{2}-\d{2}$/.test(d)).sort();
  if (dias.length) {
    const quando = dias.length === 1
      ? diaCurto(dias[0])
      : `${diaCurto(dias[0])} a ${diaCurto(dias[dias.length - 1])} · ${dias.length} dias na agenda`;
    return `<b>${quando}</b>${inicio ? `<div class="acesso">Início marcado na OS: ${inicio}</div>` : ''}`;
  }
  if (!inicio) return '<span class="vazio">A combinar com o escritório</span>';
  const fimValido = h.scheduledEndAt && h.scheduledAt
    && new Date(h.scheduledEndAt).getTime() > new Date(h.scheduledAt).getTime();
  return fimValido ? `<b>${inicio}</b> → ${formatDateBr(h.scheduledEndAt)}` : `<b>${inicio}</b>`;
}

function whereLine(h: RouteSheetHeader): string {
  const partes = [
    h.marinaName && escapeHtml(h.marinaName),
    camposDoTipo(h.assetType).nauticos && h.dockPosition && `vaga ${escapeHtml(h.dockPosition)}`,
  ].filter(Boolean);
  const acesso = semValores(h.siteAccess);
  if (!partes.length && !acesso) {
    return '<span class="vazio">Local não informado na OS. Confirme com o cliente antes de sair.</span>';
  }
  return [
    partes.length ? `<b>${partes.join(' · ')}</b>` : '',
    acesso ? `<div class="acesso">${paragrafos(acesso)}</div>` : '',
  ].join('');
}

/** Rótulo e frase de cada situação do serviço na via. */
const SITUACAO: Record<string, { selo: string; frase?: string; pede_volta: boolean }> = {
  so_levantar: { selo: 'SÓ LEVANTAR', frase: 'Medir, fotografar e anotar. Não executar.', pede_volta: true },
  aguarda_peca: { selo: 'AGUARDA PEÇA', frase: 'Peça ainda não chegou: só execute se ela estiver com você.', pede_volta: true },
  feito: { selo: 'JÁ FEITO', frase: 'Registrado como feito. Não precisa refazer.', pede_volta: false },
  parcial: { selo: 'PARCIAL', frase: 'Começado numa visita anterior: continuar.', pede_volta: true },
  nao_feito: { selo: 'NÃO FEITO NA ÚLTIMA VISITA', pede_volta: true },
};

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
  const contato = h.onSiteContact;
  if (contato?.name) {
    linhas.push(`No local: <b>${escapeHtml(contato.name)}</b>${
      contato.role ? ` (${escapeHtml(contato.role)})` : ''}${
      contato.phone ? ` — tel. ${escapeHtml(contato.phone)}` : ''}`);
  } else if (h.requestedBy && h.requestedBy.trim() && h.requestedBy.trim() !== (h.clientName || '').trim()) {
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
  const aprovados = steps.filter((s) => !isAiDraft(s));
  const soSeguranca = extras.roteiro === 'seguranca';
  const passos = soSeguranca ? passosDeSeguranca(aprovados) : aprovados;
  const groups = groupStepsByBlock(passos);
  const numero = escapeHtml(header.orderNumber);
  // A via de uma pessoa diz de quem é: o nome no campo Técnico e no cabeçalho.
  const pessoa = (extras.pessoa?.nome || '').trim();
  const tecnico = pessoa || header.technicianName || '';

  // ── Folha de rosto ──────────────────────────────────────────────────────────
  const veiculo = vehicleLine(header);
  const contatos = contactLines(header);
  const pedido = semValores(header.problemDescription);
  const instrucoes = semValores(header.technicianInstructions);
  const eletrico = header.vehicleElectrical;
  const linhasEletricas = [
    eletrico?.batteryBank && `Banco de baterias: ${escapeHtml(eletrico.batteryBank)}`,
    eletrico?.inverterCharger && `Inversor/carregador: ${escapeHtml(eletrico.inverterCharger)}`,
    eletrico?.shorePower && `Energia de terra/tomada: ${escapeHtml(eletrico.shorePower)}`,
    eletrico?.notes && semValores(eletrico.notes) && `Observações: ${escapeHtml(semValores(eletrico.notes))}`,
  ].filter(Boolean);
  // O que já se sabe do sistema elétrico chega ao técnico antes de ele abrir o quadro.
  // "deste motorhome" / "desta lancha"; sem tipo, "desta embarcação ou veículo".
  const desteTipo = `${ehFeminino(header.assetType) ? 'desta' : 'deste'} ${rotuloDaUnidade(header.assetType).toLowerCase()}`;
  const eletricoHtml = linhasEletricas.length ? `
    <div class="secao">
      <div class="sectitle">O que já sabemos do sistema elétrico ${escapeHtml(desteTipo)}</div>
      <div class="pedido">${linhasEletricas.map((l) => `<p>${l}</p>`).join('')}</div>
    </div>` : '';
  const rostoHtml = `
    <div class="rosto">
      <div class="campo"><span class="lab">${escapeHtml(veiculo.rotulo)}</span>${veiculo.valor ? escapeHtml(veiculo.valor) : '<span class="vazio">não informado</span>'}</div>
      <div class="campo"><span class="lab">Quando</span>${whenLine(header)}</div>
      <div class="campo"><span class="lab">Onde</span>${whereLine(header)}</div>
      <div class="campo"><span class="lab">Com quem falar</span>${contatos || '<span class="vazio">sem contato no cadastro</span>'}</div>
      ${tecnico ? `<div class="campo"><span class="lab">Técnico</span><b>${escapeHtml(tecnico)}</b></div>` : ''}
    </div>
    ${pedido ? `
    <div class="secao">
      <div class="sectitle">Pedido do cliente</div>
      <div class="pedido">${paragrafos(pedido)}</div>
    </div>` : ''}
    ${instrucoes ? `
    <div class="instrucao">
      <div class="lab">Instruções do escritório</div>
      ${paragrafos(instrucoes)}
    </div>` : ''}
    ${eletricoHtml}`;

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
        const instrucao = semValores(s.technicianInstructions);
        const situacao = SITUACAO[s.fieldStatus || ''];
        const notaSituacao = semValores(s.fieldStatusNote);
        return `
        <div class="svc">
          <div class="svctitle">${i + 1} · ${escapeHtml(s.name)}${qtd}${
            situacao ? ` <span class="selo">${situacao.selo}</span>` : ''}</div>
          ${!pessoa && s.responsavel ? `<div class="resp">Responsável: <b>${escapeHtml(s.responsavel)}</b></div>` : ''}
          ${situacao?.frase ? `<div class="situacao">${situacao.frase}</div>` : ''}
          ${notaSituacao ? `<div class="situacao">${escapeHtml(notaSituacao)}</div>` : ''}
          ${instrucao ? `<div class="instrucao sm"><span class="lab">Instrução</span>${paragrafos(instrucao)}</div>` : ''}
          ${descricao ? `<div class="detail">${paragrafos(descricao)}</div>` : ''}
          ${notas ? `<div class="detail">${paragrafos(notas)}</div>` : ''}
          ${doServico.length ? `<div class="svcmat"><span class="matlabel">Material deste serviço:</span>
            ${doServico.map((m) => materialLine(m)).join(' &nbsp;·&nbsp; ')}</div>` : ''}
          ${situacao && !situacao.pede_volta ? '' : `<div class="volta">
            <span class="check sm"></span> feito &nbsp;&nbsp;
            <span class="check sm"></span> parcial &nbsp;&nbsp;
            <span class="check sm"></span> não feito &nbsp;·&nbsp; motivo: <span class="rule inline"></span>
          </div>`}
        </div>`;
      }).join('')}
    </div>` : '';

  // ── Na via de uma pessoa: o que está com outra (só o nome — onde termina a parte dela) ───
  const outros = (extras.outrosServicos ?? []).filter((o) => o.name);
  const outrosHtml = pessoa && outros.length ? `
    <div class="outros">
      <b>Nesta OS, com outra pessoa (não é com você):</b>
      ${outros.map((o) => `<div>· ${escapeHtml(o.name)}${o.responsavel ? ` — ${escapeHtml(o.responsavel)}` : ''}</div>`).join('')}
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
      <div class="sectitle">${soSeguranca ? 'Segurança por sistema' : 'Roteiro de execução'}</div>
      <div class="roteironote">${soSeguranca
        ? 'Antes de mexer e antes de entregar, em cada sistema tocado. '
        : ''}Marque cada passo ao terminar, nunca antes. Interrompido? Volte três
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
  .acesso { font-size: 9.5pt; margin-top: .8mm; }
  .instrucao { border-left: 2.5pt solid #000; padding: 1.5mm 0 1.5mm 3mm; margin-bottom: 4mm;
               font-size: 10pt; line-height: 1.4; page-break-inside: avoid; }
  .instrucao.sm { font-size: 9pt; margin: 1.5mm 0; border-left-width: 1.8pt; }
  .selo { font-size: 7.5pt; font-weight: bold; letter-spacing: .05em; border: 1pt solid #000;
          padding: 0 1.2mm; white-space: nowrap; vertical-align: 1px; }
  .situacao { font-size: 9pt; font-weight: bold; margin-top: .8mm; }
  .aviso { border: 1.2pt solid #000; padding: 2.5mm 3mm; margin-bottom: 4mm; font-size: 10pt;
           page-break-inside: avoid; }
  .limite { border: 1pt dashed #000; padding: 2.5mm 3mm; margin-bottom: 5mm; font-size: 10pt;
            page-break-inside: avoid; }

  /* Cartão de serviço: o que fazer e o que devolver, juntos. */
  .svc { border: .8pt solid #555; padding: 2.5mm 3mm; margin-bottom: 3mm; page-break-inside: avoid; }
  .svctitle { font-weight: bold; font-size: 10.5pt; line-height: 1.3; }
  .svcmat { font-size: 9pt; margin-top: 1.5mm; }
  .resp { font-size: 9pt; margin-top: .8mm; }
  .outros { border: 1pt dashed #000; padding: 2.5mm 3mm; margin-bottom: 4mm; font-size: 9.5pt;
            line-height: 1.4; page-break-inside: avoid; }
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
        <div class="kind">${soSeguranca || !passos.length ? 'Via do técnico' : 'Via do técnico · roteiro completo'}${
          pessoa ? ` · ${escapeHtml(pessoa)}` : ''}</div>
        <div class="num">${numero}</div>
      </div>
    </div>
  </div>

  ${rostoHtml}
  ${materiaisHtml}
  ${limitesHtml}
  ${servicosHtml}
  ${outrosHtml}
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

// ═══ A montagem: dos dados do banco à folha (a tela e o servidor passam por aqui) ═══════════

/** Papéis do contato do veículo — o mesmo rótulo do cadastro (use-vessel-contacts reexporta daqui). */
export const VESSEL_CONTACT_ROLES = [
  { value: 'owner', label: 'Proprietário' },
  { value: 'captain', label: 'Comandante' },
  { value: 'sailor', label: 'Marinheiro' },
  { value: 'manager', label: 'Administrador' },
  { value: 'mechanic', label: 'Mecânico responsável' },
  { value: 'contact', label: 'Contato geral' },
];

/** O que a via precisa saber da OS — tudo já está no detalhe que a tela carrega. */
export type ViaDoTecnicoHeader = Omit<
  RouteSheetHeader,
  'orderNumber' | 'companyName' | 'companyLogoUrl' | 'companyAddress' | 'companyPhone'
> & { orderNumber?: string | null };

/**
 * Cabeçalho da via a partir do detalhe da OS (o mesmo objeto que a tela de OS carrega, e o que
 * o servidor lê com o mesmo embed). Um só lugar: o menu Ações, o painel de Roteiro e o PDF do
 * WhatsApp não podem sair com folhas diferentes.
 */
// deno-lint-ignore no-explicit-any
export function viaHeaderFromOrder(order: any): ViaDoTecnicoHeader {
  if (!order) return {};
  return {
    orderNumber: order.service_order_number ?? null,
    clientName: order.clients?.name ?? null,
    clientPhone: order.clients?.phone ?? null,
    clientWhatsapp: order.clients?.whatsapp ?? null,
    requestedBy: order.requested_by_name ?? null,
    assetName: order.vessels?.name ?? null,
    assetType: order.vessels?.asset_type ?? null,
    assetMaker: order.vessels?.manufacturer ?? null,
    assetModel: order.vessels?.model ?? null,
    // Placa ou inscrição: só aparece quando o detalhe da OS a traz (SO_DETAIL_SELECT*).
    assetRegistration: order.vessels?.hull_id_or_registration ?? null,
    marinaName: order.marinas?.name ?? null,
    dockPosition: order.vessels?.current_dock_position ?? null,
    technicianName: order.service_order_technicians?.[0]?.app_users?.full_name ?? null,
    scheduledAt: order.scheduled_start_at ?? null,
    scheduledEndAt: order.scheduled_end_at ?? null,
    problemDescription: order.problem_description ?? null,
    technicianInstructions: order.technician_instructions ?? null,
    // O local da OS manda; sem ele, vale o padrão do cadastro do veículo.
    siteAccess: order.site_access || order.vessels?.access_notes || null,
    onSiteContact: order.requested_by_contact
      ? {
          name: order.requested_by_contact.full_name ?? null,
          role: VESSEL_CONTACT_ROLES.find((r) => r.value === order.requested_by_contact.role)?.label
            ?? order.requested_by_contact.role ?? null,
          phone: order.requested_by_contact.phone ?? null,
        }
      : null,
    vehicleElectrical: order.vessels
      ? {
          batteryBank: order.vessels.battery_bank_summary ?? null,
          inverterCharger: order.vessels.inverter_charger_summary ?? null,
          shorePower: order.vessels.shore_power_type ?? null,
          notes: order.vessels.electrical_system_notes ?? null,
        }
      : null,
  };
}

/** Uma linha de service_order_services como a via a lê (select '*, services(name)'). */
export interface LinhaDaVia {
  id: string;
  name_snapshot?: string | null;
  services?: { name?: string | null } | null;
  description_snapshot?: string | null;
  quantity?: number | null;
  billing_unit_snapshot?: string | null;
  notes?: string | null;
  technician_instructions?: string | null;
  field_status?: string | null;
  field_status_note?: string | null;
  /** Quem faz este serviço (payees.id). Nulo = sem responsável marcado. */
  responsavel_payee_id?: string | null;
}

/** Uma resposta do levantamento (service_survey_answers). */
export interface RespostaDaVia {
  seq?: number | null;
  question_snapshot?: string | null;
  answer_value?: string | null;
  skipped_reason?: string | null;
  photo_path?: string | null;
}

/** Tudo o que a via lê do banco. A tela junta das consultas dela; o servidor, de uma leitura só. */
export interface DadosDaVia {
  serviceOrderId: string;
  header: ViaDoTecnicoHeader;
  empresa: { nome?: string | null; logoUrl?: string | null; endereco?: string | null; telefone?: string | null };
  linhas: LinhaDaVia[];
  passos: ServiceOrderStep[];
  materiais: RouteMaterial[];
  levantamento: RespostaDaVia[];
  /** seguranca_da_via (banco): a segurança por sistema quando a OS não tem roteiro. */
  seguranca: LinhaDeSeguranca[];
  /** Nome de cada responsável citado nas linhas (payees.id → nome). */
  nomesDosResponsaveis: Record<string, string>;
}

export interface OpcoesDaVia {
  /** `via` (menu Ações, WhatsApp): só a segurança do roteiro. `roteiro` (painel Roteiro): o roteiro completo. */
  modo?: 'via' | 'roteiro';
  /** A via de uma pessoa (payees.id e nome). Ausente = a OS inteira, com o responsável de cada serviço. */
  pessoa?: { id: string; nome: string } | null;
  /** Caminho da foto → link temporário (a tela e o servidor assinam cada um do seu jeito). */
  linksDasFotos?: Record<string, string>;
  /** Os dias da pessoa na agenda (aaaa-mm-dd): o campo Quando da via dela. */
  diasNaAgenda?: string[] | null;
}

/**
 * A parte de uma pessoa na OS (decisão do dono, 13/11/2026): as linhas marcadas para ela e as sem
 * responsável. As marcadas para outra pessoa ficam de fora (e saem na via só pelo nome).
 */
export function recorteDaPessoa<T extends { responsavel_payee_id?: string | null }>(
  linhas: T[],
  pessoaId: string,
): { minhas: T[]; outras: T[] } {
  const minhas: T[] = [];
  const outras: T[] = [];
  for (const l of linhas) {
    if (!l.responsavel_payee_id || l.responsavel_payee_id === pessoaId) minhas.push(l);
    else outras.push(l);
  }
  return { minhas, outras };
}

function nomeDaLinha(l: LinhaDaVia): string {
  return l.name_snapshot || l.services?.name || 'Serviço';
}

/** A linha da OS como cartão de serviço da via. */
export function servicoDaVia(
  l: LinhaDaVia,
  nomesDosResponsaveis: Record<string, string> = {},
): NonNullable<RouteSheetExtras['services']>[number] {
  return {
    id: l.id ?? null,
    name: nomeDaLinha(l),
    description: l.description_snapshot || null,
    quantity: l.quantity ?? null,
    unit: l.billing_unit_snapshot || null,
    notes: l.notes || null,
    technicianInstructions: l.technician_instructions || null,
    fieldStatus: l.field_status || null,
    fieldStatusNote: l.field_status_note || null,
    responsavel: l.responsavel_payee_id ? nomesDosResponsaveis[l.responsavel_payee_id] ?? null : null,
  };
}

/** O que buildRouteSheetHtml recebe, pronto — e se a via da pessoa ficou sem serviço nenhum dela. */
export interface ViaMontada {
  header: RouteSheetHeader;
  passos: ServiceOrderStep[];
  materiais: RouteMaterial[];
  extras: RouteSheetExtras;
  /** Quantos serviços vão no papel. */
  servicos: number;
  /** A pessoa não tem serviço nesta OS: todos os da OS estão com outra pessoa. Não se manda via vazia. */
  semServicoDaPessoa: boolean;
}

/** Dos dados do banco à folha. A tela imprime o resultado; o servidor o renderiza em PDF. */
export function montarViaDoTecnico(d: DadosDaVia, o: OpcoesDaVia = {}): ViaMontada {
  const modo = o.modo ?? 'via';
  const pessoa = o.pessoa ?? null;
  const { minhas, outras } = pessoa ? recorteDaPessoa(d.linhas, pessoa.id) : { minhas: d.linhas, outras: [] as LinhaDaVia[] };
  const idsMeus = new Set(minhas.map((l) => l.id));
  // Na via de uma pessoa, material e passo de serviço de outra pessoa ficam de fora; o que é da OS
  // inteira (sem serviço) vai para todo mundo.
  const daParte = (id: string | null | undefined) => !pessoa || !id || idsMeus.has(id);

  const header: RouteSheetHeader = {
    ...d.header,
    ...(o.diasNaAgenda?.length ? { diasNaAgenda: o.diasNaAgenda } : {}),
    orderNumber: d.header.orderNumber || 'OS',
    companyName: d.empresa.nome || null,
    companyLogoUrl: d.empresa.logoUrl || null,
    companyAddress: d.empresa.endereco || null,
    companyPhone: d.empresa.telefone || null,
  };
  const links = o.linksDasFotos ?? {};
  const extras: RouteSheetExtras = {
    roteiro: modo === 'via' ? 'seguranca' : 'completo',
    services: minhas.map((l) => servicoDaVia(l, d.nomesDosResponsaveis)),
    survey: d.levantamento
      .slice()
      .sort((a, b) => Number(a.seq ?? 0) - Number(b.seq ?? 0))
      .map((a) => ({
        question: a.question_snapshot || '',
        answer: a.answer_value ?? null,
        skipped: a.skipped_reason ?? null,
        photoUrl: a.photo_path ? links[a.photo_path] ?? null : null,
      })),
    ...(pessoa
      ? {
          pessoa: { nome: pessoa.nome },
          outrosServicos: outras.map((l) => ({
            name: nomeDaLinha(l),
            responsavel: l.responsavel_payee_id ? d.nomesDosResponsaveis[l.responsavel_payee_id] ?? null : null,
          })),
        }
      : {}),
  };
  const temSegurancaNoRoteiro = passosDeSeguranca(d.passos).length > 0;
  const passosDaParte = d.passos.filter((p) => daParte(p.service_order_service_id));
  const passos = modo === 'via' && !temSegurancaNoRoteiro
    ? [...passosDaParte, ...segurancaSemRoteiro(d.serviceOrderId, d.seguranca)]
    : passosDaParte;
  return {
    header,
    passos,
    materiais: d.materiais.filter((m) => daParte(m.service_order_service_id)),
    extras,
    servicos: minhas.length,
    semServicoDaPessoa: !!pessoa && d.linhas.length > 0 && minhas.length === 0,
  };
}

/** A folha pronta, em HTML. */
export function htmlDaVia(m: ViaMontada): string {
  return buildRouteSheetHtml(m.header, m.passos, m.materiais, m.extras);
}

/**
 * Impressão digital do CONTEÚDO da via de uma pessoa — para a agenda saber se a OS mudou desde
 * a última via que ela recebeu (decisão do dono: manda no 1º dia e de novo só se a OS mudar).
 *
 * Fica de fora o que muda sem a OS mudar: a data e a hora (a ficha das 19:30 já diz o dia, e a
 * agenda remarca sem ser mudança do serviço) e o link da foto (assinado a cada leitura).
 */
export function impressaoDaVia(d: DadosDaVia, o: OpcoesDaVia = {}): string {
  const m = montarViaDoTecnico(
    { ...d, header: { ...d.header, scheduledAt: null, scheduledEndAt: null } },
    { ...o, linksDasFotos: {}, diasNaAgenda: null },
  );
  const fotos = d.levantamento.map((a) => a.photo_path || '').join('|');
  return hashCurto(`${htmlDaVia(m)}\n${fotos}`);
}

/** Nome do arquivo: "Via-tecnico-OS-00119-Alex.pdf" (sem acento e sem espaço). */
export function nomeDoArquivoDaVia(numero: string | null | undefined, pessoa?: string | null): string {
  const limpar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^A-Za-z0-9-]+/g, '-')
    .replace(/-+/g, '-').replace(/^-|-$/g, '');
  const primeiro = pessoa ? limpar(pessoa.trim().split(/\s+/)[0] ?? '') : '';
  return `Via-tecnico-${limpar(numero || 'OS')}${primeiro ? `-${primeiro}` : ''}.pdf`;
}
