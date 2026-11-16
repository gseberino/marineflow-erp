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
import { numerarLinhas, ordenarLinhas } from '../linhas-da-os.ts';
import { isQuoteStatus } from './document-type.ts';
import { ehCobranca, notaDoMaterial, semValores } from './via-texto.ts';
import { type LinhaDeAtencao, linhasDeAtencao } from './via-atencao.ts';

// semValores mora em via-texto.ts (porte da via v2, F1); continua saindo daqui para quem já importava.
export { semValores };

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
  /** Para a ordem canônica (created_at, id) na impressão digital; a folha usa a ordem em que o material chega. */
  created_at?: string | null;
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
  /**
   * Orçamento ainda não aprovado (isQuoteStatus): a folha diz no topo que o técnico só executa com o OK do escritório
   * (rodada 1, item c). montarViaDoTecnico preenche pelo status quando o cabeçalho não traz.
   */
  orcamentoEmAprovacao?: boolean | null;
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
    /**
     * O número do serviço na OS INTEIRA (numerarLinhas): o mesmo da tela "Lançar a via" e do "serviço N" do
     * assistente. A linha de cobrança sai do papel e os outros mantêm o número (4A). Sem ele, a posição na lista.
     */
    numero?: number | null;
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
  /**
   * O quadro "Atenção" (via aprovada, 14–16/11/2026): uma linha curta por risco grave, no lugar das páginas de
   * "Segurança por sistema". Só no modo `via` (montarViaDoTecnico, via-atencao.ts). Vazio ou ausente = sem quadro.
   */
  atencao?: LinhaDeAtencao[] | null;
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
 *
 * Desde o porte da via v2 (F1, 16/11/2026) a via NÃO usa mais esta função: no lugar das páginas de
 * segurança por sistema vai o quadro Atenção (via-atencao.ts). Fica exportada até a limpeza à parte.
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

/**
 * A fonte: "Open Sans" primeiro — é a ÚNICA fonte do Chromium do /api/pdf (@sparticuz/chromium); o PDF do WhatsApp
 * sai nela e as contagens de folhas aprovadas foram medidas nela. No navegador do escritório cai na Arial.
 * Ela NÃO tem "⚠" nem "→": o ⚠ é o desenho TRI e a seta entre as datas virou "até".
 */
const FONTE = '"Open Sans", Arial, Helvetica, sans-serif';

/** O ⚠ como desenho (a fonte do servidor não tem o caractere U+26A0). */
const TRI = '<svg class="tri" viewBox="0 0 20 18" role="img" aria-label="perigo"><path d="M10 1 19.3 17H.7Z" fill="#111"/><path d="M10 6.3v5.4" stroke="#fff" stroke-width="2.2" stroke-linecap="round"/><circle cx="10" cy="14.3" r="1.25" fill="#fff"/></svg>';

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
 * O que vai faltar no papel — o aviso antes de imprimir. O escritório decide se completa ou
 * imprime assim; o técnico, sem poder ligar, é quem pagaria pela lacuna.
 *
 * Porte da via v2 (F1, escolha E19): saíram "local e acesso" (sem local, a via diz "Oficina HBR" — o
 * serviço é na oficina quase sempre) e "segurança (nenhum sistema…)" (a via não imprime mais a segurança
 * por sistema; o quadro Atenção vem dos serviços). "Telefone de contato" lê o cabeçalho COMPLETO: a folha
 * leva os números no fechamento, mas o cabeçalho continua com eles.
 */
export function faltasDaVia(
  h: RouteSheetHeader,
  materials: RouteMaterial[],
  /** Quantos serviços vão ao papel (sem as linhas de cobrança). */
  quantidadeDeServicos: number,
): string[] {
  const faltas: string[] = [];
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
  // "até", não a seta: a Open Sans do servidor (a única fonte do PDF do WhatsApp) não tem o "→" — sairia um quadradinho.
  return fimValido ? `<b>${inicio}</b> até ${formatDateBr(h.scheduledEndAt)}` : `<b>${inicio}</b>`;
}

/**
 * Sem marina, vaga nem acesso na OS, o serviço é na oficina (rodada 2, item h: a ficha vai pendurada no veículo e o
 * serviço é na oficina quase 100%). Antes dizia "Local não informado na OS. Confirme com o cliente antes de sair.".
 */
export const ONDE_PADRAO = 'Oficina HBR';

function whereLine(h: RouteSheetHeader): string {
  const partes = [
    h.marinaName && escapeHtml(h.marinaName),
    camposDoTipo(h.assetType).nauticos && h.dockPosition && `vaga ${escapeHtml(h.dockPosition)}`,
  ].filter(Boolean);
  const acesso = semValores(h.siteAccess);
  if (!partes.length && !acesso) return `<b>${ONDE_PADRAO}</b>`;
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

/** Os telefones do cliente e do contato no local, já decididos: o que vai ao fechamento e o que a folha 1 diz. */
function telefonesDoContato(h: RouteSheetHeader) {
  const tel = (h.clientPhone || '').trim();
  const zap = (h.clientWhatsapp || '').trim();
  const digitos = (s: string) => s.replace(/\D/g, '');
  const span = (rotulo: string, n: string) => `<span class="tel">${rotulo} ${escapeHtml(n)}</span>`;
  // Mesmo número no telefone e no WhatsApp sai uma vez só.
  const numerosDoCliente = tel && zap && digitos(tel) === digitos(zap)
    ? span('tel./WhatsApp', tel)
    : [tel && span('tel.', tel), zap && span('WhatsApp', zap)].filter(Boolean).join(' · ');
  const telDoLocal = (h.onSiteContact?.phone || '').trim();
  // Contato no local com o mesmo número do cliente não repete o número.
  const localRepete = !!telDoLocal && [tel, zap].some((n) => n && digitos(n) === digitos(telDoLocal));
  return { numerosDoCliente, telDoLocal, localRepete, span };
}

/**
 * "Com quem falar", na folha 1 (rodada 2, item g): quem é, sem os números — a ficha vai pendurada no veículo do
 * cliente. No lugar do número, onde ele está ("telefone no fim da ficha"); sem número, "sem telefone no cadastro".
 */
function contactLines(h: RouteSheetHeader): string {
  const linhas: string[] = [];
  const { numerosDoCliente, telDoLocal, localRepete } = telefonesDoContato(h);
  const noFim = '<span class="vazio">telefone no fim da ficha</span>';
  if (h.clientName) {
    linhas.push(`Cliente: <b>${escapeHtml(h.clientName)}</b> — ${
      numerosDoCliente ? noFim : '<span class="vazio">sem telefone no cadastro</span>'}`);
  }
  const contato = h.onSiteContact;
  if (contato?.name) {
    linhas.push(`No local: <b>${escapeHtml(contato.name)}</b>${
      contato.role ? ` (${escapeHtml(contato.role)})` : ''}${
      telDoLocal ? ` — ${localRepete ? '<span class="vazio">mesmo telefone do cliente</span>' : noFim}` : ''}`);
  } else if (h.requestedBy && h.requestedBy.trim() && h.requestedBy.trim() !== (h.clientName || '').trim()) {
    linhas.push(`Pedido por: <b>${escapeHtml(h.requestedBy)}</b>`);
  }
  if (h.companyPhone) linhas.push(`Escritório: <b>${escapeHtml(h.companyPhone)}</b>`);
  return linhas.map((l) => `<div>${l}</div>`).join('');
}

/**
 * Os números do cliente e do contato no local, no fechamento, ao lado de Chegada/Saída (rodada 2, item g). Só o
 * número que a folha 1 indicaria: cliente com nome e número; contato no local com nome, número e que não repete o
 * do cliente. Cada um numa linha. Vazio = nada a mostrar.
 */
export function contatoDoFechamento(h: RouteSheetHeader): string {
  const { numerosDoCliente, telDoLocal, localRepete, span } = telefonesDoContato(h);
  const contato = h.onSiteContact;
  return [
    h.clientName && numerosDoCliente && `<b>Cliente:</b> ${escapeHtml(h.clientName)} — ${numerosDoCliente}`,
    contato?.name && telDoLocal && !localRepete && `<b>No local:</b> ${escapeHtml(contato.name)}${
      contato.role ? ` (${escapeHtml(contato.role)})` : ''} — ${span('tel.', telDoLocal)}`,
  ].filter(Boolean).join('<br>');
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
 *
 * A via aprovada pelo dono (14–16/11/2026; porte da via v2, F1 — a referência é a bancada
 * render-r3.ts): a ficha vai PENDURADA no veículo. Número da OS grande, o veículo numa linha
 * própria, o aviso de orçamento em aprovação, o rosto numa linha (quando · onde · com quem
 * falar, sem os números do cliente — eles vão para o fechamento), a separação de materiais em
 * 2 colunas, cartões mais baixos com o número da OS inteira (a cobrança não vai), o quadro
 * Atenção no lugar das páginas de segurança por sistema e o fechamento inteiro num bloco que não
 * se parte, terminando no "No fim: fotografe…". Nenhum caractere fora da Open Sans do servidor.
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
  // A ficha vai PENDURADA no veículo (rodada 2, item f): o veículo numa linha grande logo abaixo do cabeçalho, e o
  // rosto numa linha só (quando · onde · com quem falar), com o técnico embaixo.
  const unidadeHtml = `<div class="unidade"><span class="lab">${escapeHtml(veiculo.rotulo)}</span><div class="uval">${
    veiculo.valor ? escapeHtml(veiculo.valor) : '<span class="vazio">não informado</span>'}</div></div>`;
  // Orçamento ainda não aprovado pelo cliente (rodada 1, item c): o papel diz antes de tudo.
  const avisoOrcamentoHtml = header.orcamentoEmAprovacao
    ? `
    <div class="aviso orc"><b>Orçamento em aprovação:</b> o técnico só executa com o OK do escritório.</div>`
    : '';
  const rostoHtml = `
    <div class="rosto">
      <div class="campo"><span class="lab">Quando</span>${whenLine(header)}</div>
      <div class="campo"><span class="lab">Onde</span>${whereLine(header)}</div>
      <div class="campo contato"><span class="lab">Com quem falar</span>${contatos || '<span class="vazio">sem contato no cadastro</span>'}</div>
      ${tecnico ? `<div class="campo tecnico"><span class="lab">Técnico</span><b>${escapeHtml(tecnico)}</b></div>` : ''}
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
  // Em 2 colunas, linhas baixas (rodada 1, item b). A nota interna do sistema ("Cadastrado pelo orçamento —
  // confirmar preço…") não vai ao papel; a escrita por gente vai (rodada 3, item j).
  const materiaisHtml = materials.length ? `
    <div class="secao materiais">
      <div class="sectitle">Antes de sair · separação de materiais</div>
      <div class="matnota">Confira item por item antes de sair. Falta descoberta no local custa o dia.</div>
      <div class="matcols">${materials.map((m) => {
        const nota = notaDoMaterial(m.notes);
        return `
        <div class="matitem"><span class="check sm"></span><div>${materialLine(m)}${
          nota ? `<div class="detail">${escapeHtml(nota)}</div>` : ''}</div></div>`;
      }).join('')}
      </div>
    </div>` : `
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
        // O rótulo "Instrução" na mesma linha do texto (rodada 3, item k); 2 linhas viram uma, juntas por espaço.
        const instrucaoNaLinha = instrucao.split(/\r?\n/).map((l) => l.trim()).filter(Boolean).map(escapeHtml).join(' ');
        return `
        <div class="svc">
          <div class="svctitle">${s.numero ?? i + 1} · ${escapeHtml(s.name)}${qtd}${
            situacao ? ` <span class="selo">${situacao.selo}</span>` : ''}</div>
          ${!pessoa && s.responsavel ? `<div class="resp">Responsável: <b>${escapeHtml(s.responsavel)}</b></div>` : ''}
          ${situacao?.frase ? `<div class="situacao">${situacao.frase}</div>` : ''}
          ${notaSituacao ? `<div class="situacao">${escapeHtml(notaSituacao)}</div>` : ''}
          ${instrucaoNaLinha ? `<div class="instrucao sm"><span class="lab">Instrução</span>${instrucaoNaLinha}</div>` : ''}
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

  // ── Atenção: uma linha curta por risco grave (no lugar das páginas de segurança por sistema) ───
  // O ⚠ é desenho (TRI): a Open Sans do servidor não tem o caractere U+26A0 — no PDF sairia um quadradinho.
  const atencao = (extras.atencao ?? []).filter((a) => a.rotulo && a.texto);
  const atencaoHtml = atencao.length ? `
    <div class="secao atencao-box"><div class="sectitle">${TRI}Atenção</div>${
      atencao.map((a) => `<div class="at"><b>${escapeHtml(a.rotulo)}:</b> ${escapeHtml(a.texto)}</div>`).join('')}</div>` : '';

  // ── Fechamento: os números do cliente ao lado de Chegada/Saída (a folha 1 não os mostra) ───
  const contatoFim = contatoDoFechamento(header);

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
                    font: 8pt ${FONTE}; color: #444; }
  }
  * { box-sizing: border-box; }
  body { font-family: ${FONTE}; color: #000; margin: 0; font-size: 11pt;
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
  /* Para pendurar: número da OS e veículo legíveis de longe (rodada 2, f). */
  .doctype .num { font-size: 28pt; font-weight: bold; color: ${BRAND}; line-height: 1.05; letter-spacing: .01em; }
  .unidade { margin: 0 0 3.5mm; page-break-inside: avoid; }
  .unidade .uval { font-size: 16pt; font-weight: bold; line-height: 1.2; }
  .unidade .uval .vazio { font-size: 11pt; font-weight: normal; }

  /* Folha de rosto numa linha: quando · onde · com quem falar; o técnico embaixo. */
  .rosto { display: grid; grid-template-columns: fit-content(66mm) fit-content(47mm) minmax(0, 1fr); gap: 2.5mm 7mm;
           margin-bottom: 4mm; page-break-inside: avoid; }
  .rosto > .campo.contato .vazio { white-space: nowrap; }
  .rosto > .campo.tecnico { grid-column: span 2; }
  .campo { font-size: 10pt; line-height: 1.35; }
  .lab { display: block; font-size: 7.5pt; letter-spacing: .09em; text-transform: uppercase; color: #444; }
  .vazio { font-style: italic; color: #333; }
  .secao { margin-bottom: 4mm; }
  /* Título de seção nunca sozinho no pé da folha. */
  .sectitle { font-size: 11pt; text-transform: uppercase; letter-spacing: .06em; font-weight: bold;
              padding: 2mm 0 1mm; border-bottom: 1pt solid #000; margin-bottom: 2mm;
              break-after: avoid; page-break-after: avoid; }
  .pedido { font-size: 10pt; line-height: 1.4; }
  .acesso { font-size: 9.5pt; margin-top: .8mm; }
  .instrucao { border-left: 2.5pt solid #000; padding: 1.5mm 0 1.5mm 3mm; margin-bottom: 4mm;
               font-size: 10pt; line-height: 1.4; page-break-inside: avoid; }
  .instrucao.sm { font-size: 9pt; margin: 1mm 0 .5mm; border-left-width: 1.8pt; }
  /* O rótulo "Instrução" na mesma linha do texto (rodada 3, k). */
  .instrucao.sm .lab { display: inline; margin-right: 1.5mm; }
  .selo { font-size: 7.5pt; font-weight: bold; letter-spacing: .05em; border: 1pt solid #000;
          padding: 0 1.2mm; white-space: nowrap; vertical-align: 1px; }
  .situacao { font-size: 9pt; font-weight: bold; margin-top: .8mm; }
  .aviso { border: 1.2pt solid #000; padding: 2.5mm 3mm; margin-bottom: 4mm; font-size: 10pt;
           page-break-inside: avoid; }
  /* Orçamento em aprovação (rodada 1, c). */
  .aviso.orc { border-width: 1.6pt; font-size: 13pt; margin-bottom: 3.5mm; }
  .limite { border: 1pt dashed #000; padding: 2.5mm 3mm; margin-bottom: 5mm; font-size: 10pt;
            page-break-inside: avoid; }

  /* Separação de materiais em 2 colunas (rodada 1, b). */
  .materiais .matnota { font-size: 8.5pt; color: #333; margin: -1mm 0 1mm; }
  .matcols { columns: 2; column-gap: 7mm; }
  .matitem { display: flex; gap: 2mm; align-items: flex-start; break-inside: avoid; page-break-inside: avoid;
             padding: 1mm 0; border-bottom: .4pt dotted #999; font-size: 9.5pt; line-height: 1.3; }

  /* Cartão de serviço: o que fazer e o que devolver, juntos (mais baixo, rodada 1, a). */
  .svc { border: .8pt solid #555; padding: 1.6mm 2.5mm 1.8mm; margin-bottom: 2mm; page-break-inside: avoid; }
  .svctitle { font-weight: bold; font-size: 10.5pt; line-height: 1.25; }
  .svcmat { font-size: 9pt; margin-top: 1.5mm; }
  .resp { font-size: 9pt; margin-top: .8mm; }
  .outros { border: 1pt dashed #000; padding: 2.5mm 3mm; margin-bottom: 4mm; font-size: 9.5pt;
            line-height: 1.4; page-break-inside: avoid; }
  .volta { font-size: 9pt; margin-top: 1.2mm; padding-top: 0; border-top: 0;
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
  .matitem .check.sm { flex: none; margin-top: .5mm; }
  .stnote { font-size: 8.5pt; font-style: italic; margin-top: .8mm; }
  td.seq { width: 7mm; font-size: 9pt; color: #444; }
  td.mat { font-size: 10pt; }
  .sku { font-size: 8.5pt; color: #555; }
  .title { font-weight: bold; font-size: 10.5pt; line-height: 1.3; }
  .marks { font-weight: normal; font-size: 7.5pt; letter-spacing: .05em; border: .5pt solid #000;
           padding: 0 1mm; white-space: nowrap; }
  .detail { font-size: 9pt; color: #333; margin-top: .8mm; line-height: 1.35; }
  .svc .detail { margin-top: .5mm; }
  .matitem .detail { margin-top: .3mm; }
  .measure { font-size: 9pt; margin-top: 1.2mm; }
  .roteironote { font-size: 9pt; color: #222; }
  td.std { width: 14mm; font-size: 9pt; text-align: right; white-space: nowrap; }
  td.time { width: 32mm; }
  .rule { display: block; border-bottom: .5pt solid #000; height: 4mm; }

  td.notes { border-bottom: none; padding-top: 1.5mm; }
  .cap { font-size: 8pt; text-transform: uppercase; letter-spacing: .07em; color: #444; }
  .lines i { display: block; border-bottom: .4pt solid #bbb; height: 5mm; }

  /* Atenção: uma linha curta por risco grave; o triângulo é desenho (a fonte do servidor não tem o caractere). */
  .atencao-box { border: 1pt solid #000; border-left-width: 3pt; padding: 2mm 3mm 2.5mm; page-break-inside: avoid; }
  .atencao-box .sectitle { border-bottom: 0; margin-bottom: 1mm; }
  .atencao-box .at { font-size: 10pt; margin: .9mm 0; line-height: 1.3; }
  .tri { display: inline-block; width: 1.05em; height: .95em; vertical-align: -.13em; margin-right: .3em; }

  /* O fechamento (chegada/saída, relato, material, assinaturas, foto e rodapé) nunca se parte. */
  .fechamento { break-inside: avoid; page-break-inside: avoid; }
  .write { border: 1pt solid #000; padding: 2mm 3mm; margin-bottom: 3mm;
           page-break-inside: avoid; }
  .write .wcap { font-size: 10pt; font-weight: bold; text-transform: uppercase;
                 letter-spacing: .05em; }
  .write .wsub { font-size: 8.5pt; color: #444; margin: .5mm 0 1.5mm; }
  .horas { display: flex; align-items: baseline; gap: 7mm; font-size: 10pt; margin-bottom: 3mm; page-break-inside: avoid; }
  .horas > div { flex: none; white-space: nowrap; }
  .horas span { display: inline-block; min-width: 22mm; border-bottom: .5pt solid #000; }
  /* Os números do cliente, no espaço livre ao lado de chegada/saída (rodada 2, g). */
  .horas > div.contatofim { flex: 1 1 0; min-width: 0; white-space: normal; text-align: right;
                            font-size: 8.5pt; line-height: 1.3; }
  .horas .contatofim span.tel { white-space: nowrap; display: inline; min-width: 0; border-bottom: 0; }
  /* A volta por foto, numa faixa de 1 linha (rodada 1, d). */
  .fotofim { border: 1pt solid #000; padding: 1.3mm 2.5mm; margin-top: 4mm; font-size: 9.5pt; line-height: 1.3; }

  .foot { margin-top: 3mm; border-top: 1.2pt solid ${BRAND}; padding-top: 2mm; font-size: 8.5pt;
          color: #333; display: flex; justify-content: space-between; gap: .8mm 6mm; flex-wrap: wrap; }
  .sign { margin-top: 4mm; display: flex; gap: 10mm; page-break-inside: avoid; }
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

  ${unidadeHtml}${avisoOrcamentoHtml}
  ${rostoHtml}
  ${materiaisHtml}
  ${limitesHtml}
  ${servicosHtml}
  ${outrosHtml}
  ${levantamentoHtml}
  ${roteiroHtml}
  ${atencaoHtml}

  <div class="fechamento">
  <div class="horas">
    <div>Chegada: <span></span></div>
    <div>Saída: <span></span></div>${contatoFim ? `
    <div class="contatofim">${contatoFim}</div>` : ''}
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

  <div class="fotofim"><b>No fim:</b> fotografe todas as folhas preenchidas e mande no WhatsApp do escritório, com as fotos do serviço pronto.</div>
  <div class="foot">
    <span>${header.companyPhone
      ? `Dúvida ou imprevisto: ligue para o escritório — <b>${escapeHtml(header.companyPhone)}</b>`
      : 'Dúvida ou imprevisto: fale com o escritório antes de decidir sozinho.'}</span>
    ${header.companyAddress || header.companyName
      ? `<span>${escapeHtml([header.companyName, header.companyAddress].filter(Boolean).join(' · '))}</span>`
      : ''}
  </div>
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
> & {
  orderNumber?: string | null;
  /** O status da OS: orçamento em aprovação (isQuoteStatus) sai no topo da folha e entra na impressão. */
  status?: string | null;
  /** Todos os técnicos da OS, em ordem alfabética (o primeiro é o technicianName). Na F0 só entra na impressão. */
  tecnicos?: string[] | null;
};

/** Ordem alfabética de nomes que não depende do embed (o banco devolve os técnicos sem ordem). */
function compararNomes(a: string, b: string): number {
  return a.localeCompare(b, 'pt-BR') || (a < b ? -1 : a > b ? 1 : 0);
}

/**
 * Cabeçalho da via a partir do detalhe da OS (o mesmo objeto que a tela de OS carrega, e o que
 * o servidor lê com o mesmo embed). Um só lugar: o menu Ações, o painel de Roteiro e o PDF do
 * WhatsApp não podem sair com folhas diferentes.
 */
// deno-lint-ignore no-explicit-any
export function viaHeaderFromOrder(order: any): ViaDoTecnicoHeader {
  if (!order) return {};
  // service_order_technicians vem embutido sem ordem: com 2 ou mais técnicos, o [0] mudava de uma leitura para a
  // outra. O nome impresso é o primeiro em ordem alfabética (porte da via v2, F0).
  const tecnicos = ((order.service_order_technicians ?? []) as Array<{ app_users?: { full_name?: string | null } | null } | null>)
    .map((t) => t?.app_users?.full_name ?? null)
    .filter((n): n is string => !!n)
    .sort(compararNomes);
  return {
    orderNumber: order.service_order_number ?? null,
    status: order.status ?? null,
    orcamentoEmAprovacao: isQuoteStatus(order.status),
    tecnicos,
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
    technicianName: tecnicos[0] ?? null,
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

/** Uma linha de service_order_services como a via a lê (select '*, services(name, service_system)'). */
export interface LinhaDaVia {
  id: string;
  /** Para a ordem canônica (created_at, id): quem lê do banco já ordena; a impressão digital confere. */
  created_at?: string | null;
  name_snapshot?: string | null;
  services?: { name?: string | null; service_system?: string | null } | null;
  /**
   * O sistema e o verbo da linha: reclassificar muda o dado da via. O sistema (o da linha ou, na falta, o do cadastro
   * do serviço — decisão 3A) entra no quadro Atenção (via-atencao.ts).
   */
  service_system?: string | null;
  service_verb?: string | null;
  service_id?: string | null;
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
  /**
   * seguranca_da_via (banco). IGNORADO desde o porte da via v2 (F1, escolha E14): a via não imprime mais a segurança por
   * sistema — o quadro Atenção lê o sistema de cada linha. A função do banco fica (a agenda usa); quem lê a via não a
   * chama mais. Fica opcional só para não quebrar quem ainda passa.
   */
  seguranca?: LinhaDeSeguranca[];
  /** Nome de cada responsável citado nas linhas (payees.id → nome). */
  nomesDosResponsaveis: Record<string, string>;
}

export interface OpcoesDaVia {
  /**
   * `via` (menu Ações, WhatsApp, agenda): a via aprovada — sem passo de roteiro nenhum, com o quadro Atenção.
   * `roteiro` (painel Roteiro, escondido): o roteiro completo gravado, como sempre, sem o quadro.
   */
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

/**
 * Linha de COBRANÇA (frete, deslocamento, insumos no título curto — resposta 4A do dono): não vai aos cartões da via
 * nem à tela "Lançar a via"; os outros serviços mantêm o número. Ela continua contando para o quadro Atenção.
 */
export function ehLinhaDeCobranca(l: { name_snapshot?: string | null; services?: { name?: string | null } | null }): boolean {
  return ehCobranca(l.name_snapshot || l.services?.name || '');
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
  /** Quantos serviços vão no papel (sem as linhas de cobrança). */
  servicos: number;
  /** A pessoa não tem serviço nesta OS: todos os da OS estão com outra pessoa. Não se manda via vazia. */
  semServicoDaPessoa: boolean;
}

/** Dos dados do banco à folha. A tela imprime o resultado; o servidor o renderiza em PDF. */
export function montarViaDoTecnico(d: DadosDaVia, o: OpcoesDaVia = {}): ViaMontada {
  const modo = o.modo ?? 'via';
  const pessoa = o.pessoa ?? null;
  // O número de cada serviço é a posição dele na OS INTEIRA, na ordem em que as linhas chegam (quem lê do banco já
  // ordenou por created_at, id): o mesmo da tela "Lançar a via" e do "serviço N" do assistente — também na via de uma
  // pessoa (os cartões dela podem sair 2, 5, 7).
  const numeradas = numerarLinhas(d.linhas);
  const { minhas, outras } = pessoa ? recorteDaPessoa(numeradas, pessoa.id) : { minhas: numeradas, outras: [] as typeof numeradas };
  const idsMeus = new Set(minhas.map((l) => l.id));
  // Na via de uma pessoa, material e passo de serviço de outra pessoa ficam de fora; o que é da OS
  // inteira (sem serviço) vai para todo mundo.
  const daParte = (id: string | null | undefined) => !pessoa || !id || idsMeus.has(id);
  // 4A: a cobrança (frete, deslocamento, insumos) sai do papel DEPOIS de numerar — os outros mantêm o número.
  const noPapel = minhas.filter((l) => !ehLinhaDeCobranca(l));

  const header: RouteSheetHeader = {
    ...d.header,
    ...(o.diasNaAgenda?.length ? { diasNaAgenda: o.diasNaAgenda } : {}),
    orderNumber: d.header.orderNumber || 'OS',
    orcamentoEmAprovacao: d.header.orcamentoEmAprovacao ?? isQuoteStatus(d.header.status),
    companyName: d.empresa.nome || null,
    companyLogoUrl: d.empresa.logoUrl || null,
    companyAddress: d.empresa.endereco || null,
    companyPhone: d.empresa.telefone || null,
  };
  const links = o.linksDasFotos ?? {};
  const extras: RouteSheetExtras = {
    roteiro: modo === 'via' ? 'seguranca' : 'completo',
    services: noPapel.map((l) => ({ ...servicoDaVia(l, d.nomesDosResponsaveis), numero: l.numero })),
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
          outrosServicos: outras.filter((l) => !ehLinhaDeCobranca(l)).map((l) => ({
            name: nomeDaLinha(l),
            responsavel: l.responsavel_payee_id ? d.nomesDosResponsaveis[l.responsavel_payee_id] ?? null : null,
          })),
        }
      : {}),
    // O quadro Atenção (só na via): as energias das linhas da parte, a de cobrança inclusive (via-atencao.ts).
    ...(modo === 'via' ? { atencao: linhasDeAtencao(d, pessoa) } : {}),
  };
  // Na via (base "limpa" aprovada em 14/11), nenhum passo: nem a segurança por sistema gerada sem roteiro, nem o
  // roteiro gravado — no lugar, o quadro Atenção. O painel Roteiro (modo `roteiro`) continua com o roteiro completo.
  const passos = modo === 'via' ? [] : d.passos.filter((p) => daParte(p.service_order_service_id));
  return {
    header,
    passos,
    materiais: d.materiais.filter((m) => daParte(m.service_order_service_id)),
    extras,
    servicos: noPapel.length,
    // OS só de cobrança é como OS sem serviço: a via sai com o aviso de sempre, não "vazia de pessoa".
    semServicoDaPessoa: !!pessoa && d.linhas.some((l) => !ehLinhaDeCobranca(l)) && noPapel.length === 0,
  };
}

/** A folha pronta, em HTML. */
export function htmlDaVia(m: ViaMontada): string {
  return buildRouteSheetHtml(m.header, m.passos, m.materiais, m.extras);
}

// ═══ A impressão digital: DADO + PAPEL + VERSÃO (porte da via v2, F0, 16/11/2026) ═══════════════════

/**
 * Sobe quando a REGRA ou o DESENHO do papel muda (o que o técnico lê ou como lê). Sozinha, não reenvia nada: a agenda
 * só manda de novo quando o DADO muda (decidirAVia). 1 = hash do HTML, sem prefixo (até 16/11/2026); 2 = desenho de
 * produção com a impressão por conteúdo (F0); 3 = a via aprovada pelo dono (base limpa + rodadas 1, 2 e 3: quadro
 * Atenção, cartões numerados pela OS inteira sem a cobrança, veículo em linha própria, telefones no fechamento…).
 * O teste-trava de via-do-tecnico_test.ts fixa o papel de fixtures: mudou a regra sem subir esta versão, ele falha.
 */
export const VERSAO_DA_VIA = 3;
/** Sobe só quando muda a LISTA de campos de retratoDoDado (é contrato). Raro: subir faz a próxima via sair com o aviso neutro. */
export const VERSAO_DO_DADO = 1;

/** As respostas do levantamento na ordem do papel (seq), com desempate fixo para a impressão não oscilar. */
function levantamentoNaOrdem(respostas: RespostaDaVia[]): RespostaDaVia[] {
  const texto = (a: RespostaDaVia) => `${a.question_snapshot ?? ''}\u0000${a.answer_value ?? ''}\u0000${a.skipped_reason ?? ''}\u0000${a.photo_path ?? ''}`;
  return respostas.slice().sort((a, b) => {
    const s = Number(a.seq ?? 0) - Number(b.seq ?? 0);
    if (s) return s;
    const ta = texto(a);
    const tb = texto(b);
    return ta < tb ? -1 : ta > tb ? 1 : 0;
  });
}

/**
 * O DADO da via de uma pessoa: os campos crus da OS que a via lê. A lista é FECHADA e é contrato (mudar a lista pede
 * subir VERSAO_DO_DADO). Fica de fora o que a via não lê (preço, desconto, total: editar preço não reenvia nada), o que
 * muda sem a OS mudar (data e hora, dias da agenda, links das fotos) e a empresa. Tudo na ordem canônica (linhas e
 * materiais por created_at, id; levantamento por seq; técnicos em ordem alfabética), e cada linha com o NÚMERO dela na
 * OS inteira — a mesma conta da via e da tela. Das linhas de outra pessoa, só o que a via dela cita (número, nome, de quem).
 */
export function retratoDoDado(d: DadosDaVia, o: OpcoesDaVia = {}) {
  const pessoa = o.pessoa ?? null;
  const numeradas = numerarLinhas(ordenarLinhas(d.linhas));
  const { minhas, outras } = pessoa ? recorteDaPessoa(numeradas, pessoa.id) : { minhas: numeradas, outras: [] as typeof numeradas };
  const numeroDe = new Map(numeradas.map((l) => [l.id, l.numero]));
  const idsMeus = new Set(minhas.map((l) => l.id));
  const daParte = (id: string | null | undefined) => !pessoa || !id || idsMeus.has(id);
  const linhaDe = (id: string | null | undefined) => (id ? numeroDe.get(id) ?? id : null);
  const h = d.header;
  const contato = h.onSiteContact;
  const eletrico = h.vehicleElectrical;
  return {
    pessoa: pessoa?.id ?? null,
    cabecalho: [
      h.orderNumber ?? null,
      isQuoteStatus(h.status),
      h.assetType ?? null, h.assetName ?? null, h.assetMaker ?? null, h.assetModel ?? null, h.assetRegistration ?? null,
      h.dockPosition ?? null, h.marinaName ?? null, h.siteAccess ?? null,
      h.clientName ?? null, h.clientPhone ?? null, h.clientWhatsapp ?? null, h.requestedBy ?? null,
      contato ? [contato.name ?? null, contato.role ?? null, contato.phone ?? null] : null,
      h.problemDescription ?? null, h.technicianInstructions ?? null,
      eletrico ? [eletrico.batteryBank ?? null, eletrico.inverterCharger ?? null, eletrico.shorePower ?? null, eletrico.notes ?? null] : null,
      [...(h.tecnicos ?? (h.technicianName ? [h.technicianName] : []))].sort(compararNomes),
    ],
    linhas: minhas.map((l) => [
      l.numero, l.name_snapshot || l.services?.name || null, l.description_snapshot ?? null, l.notes ?? null,
      l.quantity ?? null, l.billing_unit_snapshot ?? null, l.technician_instructions ?? null,
      l.field_status ?? null, l.field_status_note ?? null, l.responsavel_payee_id ?? null,
      l.service_system ?? null, l.service_verb ?? null, l.service_id ?? null, l.services?.service_system ?? null,
    ]),
    outras: outras.map((l) => [l.numero, l.name_snapshot || l.services?.name || null, l.responsavel_payee_id ?? null]),
    materiais: ordenarLinhas(d.materiais.filter((m) => daParte(m.service_order_service_id))).map((m) => [
      m.products?.name ?? null, m.products?.sku ?? null, m.products?.unit ?? null, m.quantity ?? null, m.notes ?? null,
      linhaDe(m.service_order_service_id),
    ]),
    levantamento: levantamentoNaOrdem(d.levantamento).map((a) => [
      a.seq ?? null, a.question_snapshot ?? null, a.answer_value ?? null, a.skipped_reason ?? null, a.photo_path ?? null,
    ]),
    passos: d.passos.filter((p) => daParte(p.service_order_service_id)).map((p) => [
      p.seq, p.block ?? null, p.block_key ?? null, p.block_note ?? null, p.title, p.detail ?? null, p.kind, p.mode,
      p.is_killer, p.requires_photo, p.requires_measure ?? null, p.measure_unit ?? null, p.measure_value ?? null,
      p.status, p.na_reason ?? null, p.blocked_note ?? null, isAiDraft(p), linhaDe(p.service_order_service_id),
    ]),
  };
}

/**
 * Impressão digital da via de uma pessoa — para a agenda saber se a OS mudou desde a última via que ela recebeu
 * (decisão do dono: manda no 1º dia e de novo só se a OS mudar). Formato `v<VERSAO_DA_VIA>.d<VERSAO_DO_DADO>.<dado>.<papel>`:
 *   · `dado`  = hash do retratoDoDado (a OS mudou?);
 *   · `papel` = hash da folha montada com a entrada na ordem canônica e sem o que muda sem a OS mudar: data e hora (a
 *     ficha das 19:30 já diz o dia, e a agenda remarca sem ser mudança do serviço), dias da agenda, links das fotos
 *     (assinados a cada leitura) e a empresa (trocar o telefone da empresa não é "a OS mudou"). As fotos entram pelo
 *     caminho, na ordem do levantamento.
 * Trocar o desenho da folha muda o papel e a versão, nunca o dado: a via não volta com "A OS mudou".
 */
export function impressaoDaVia(d: DadosDaVia, o: OpcoesDaVia = {}): string {
  const dado = hashCurto(JSON.stringify(retratoDoDado(d, o)));
  const levantamento = levantamentoNaOrdem(d.levantamento);
  const m = montarViaDoTecnico(
    {
      ...d,
      header: { ...d.header, scheduledAt: null, scheduledEndAt: null },
      empresa: {},
      linhas: ordenarLinhas(d.linhas),
      materiais: ordenarLinhas(d.materiais),
      levantamento,
    },
    { ...o, linksDasFotos: {}, diasNaAgenda: null },
  );
  const fotos = levantamento.map((a) => a.photo_path || '').join('|');
  const papel = hashCurto(`${htmlDaVia(m)}\n${fotos}`);
  return `v${VERSAO_DA_VIA}.d${VERSAO_DO_DADO}.${dado}.${papel}`;
}

/** As partes da impressão; `null` = formato antigo (o hash do HTML inteiro, sem prefixo) ou vazio. */
export function lerImpressao(s: string | null | undefined): { versao: number; versaoDoDado: number; dado: string; papel: string } | null {
  const m = /^v(\d+)\.d(\d+)\.([0-9a-z]+)\.([0-9a-z]+)$/.exec(s ?? '');
  return m ? { versao: Number(m[1]), versaoDoDado: Number(m[2]), dado: m[3], papel: m[4] } : null;
}

/** Nome do arquivo: "Via-tecnico-OS-00119-Alex.pdf" (sem acento e sem espaço). */
export function nomeDoArquivoDaVia(numero: string | null | undefined, pessoa?: string | null): string {
  const limpar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^A-Za-z0-9-]+/g, '-')
    .replace(/-+/g, '-').replace(/^-|-$/g, '');
  const primeiro = pessoa ? limpar(pessoa.trim().split(/\s+/)[0] ?? '') : '';
  return `Via-tecnico-${limpar(numero || 'OS')}${primeiro ? `-${primeiro}` : ''}.pdf`;
}
