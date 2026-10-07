/**
 * Planos de manutenção com lembretes (07/10/2026) — a parte PURA das telas.
 *
 * O banco é quem decide vencimento e situação (view v_maintenance_plans_due, da frente BANCO):
 * a tela só agrupa, formata e propõe. Antes, o painel calculava "próxima" com o relógio do
 * navegador e ignorava advance_days; com a view, o painel, a aba Revisões, o resumo das 07:30
 * e o assistente leem o MESMO número.
 *
 * Puro de propósito: testado sem banco (planos-manutencao.test.ts).
 */
// As datas são as do PDF e do resumo (calendário de Brasília em qualquer máquina): uma regra só.
import { dataBR as dataBRCompartilhada, diaBR, somarDiasAoDia } from '../../supabase/functions/_shared/pdf/datas';

export type SituacaoPlano = 'em_dia' | 'na_janela' | 'vencida' | 'adiada';

/** Uma linha de v_maintenance_plans_due (contrato da spec, 07/10/2026). */
export interface PlanoNaView {
  plan_id: string;
  vessel_id: string;
  vessel_name: string | null;
  client_id: string | null;
  client_name: string | null;
  client_phone: string | null;
  opt_out: boolean | null;
  name: string;
  scope: string | null;
  estimated_value: number | string | null;
  interval_months: number;
  last_service_at: string | null;
  last_service_order_id: string | null;
  next_due_on: string;
  window_opens_on: string | null;
  snoozed_until: string | null;
  dias_para_vencer: number;
  situacao: SituacaoPlano;
  tem_os_agendada: boolean | null;
  ultimo_toque: number | null;
  respondeu_no_ciclo: boolean | null;
}

/** Linha de maintenance_plans com as colunas novas da migration 20261007150000. */
export interface PlanoDeManutencao {
  id: string;
  vessel_id: string;
  name: string;
  interval_months: number;
  scope: string | null;
  estimated_value: number | null;
  last_service_at: string | null;
  advance_days: number;
  active: boolean;
  notes: string | null;
  created_at: string;
  service_system: string | null;
  service_verb: string | null;
  match_keywords: string[] | null;
  last_service_order_id: string | null;
  snoozed_until: string | null;
  client_reminder_enabled: boolean;
  source: 'manual' | 'sugerido';
}

export interface EventoDoPlano {
  id: string;
  plan_id: string;
  due_on: string | null;
  tipo: string;
  toque: number | null;
  service_order_id: string | null;
  detalhe: Record<string, unknown> | null;
  created_at: string;
}

/** "Hoje" no calendário de Brasília (AAAA-MM-DD) — o "Serviço feito" antigo gravava a data UTC. */
export function hojeEmBrasilia(agora: Date = new Date()): string {
  return diaBR(agora);
}

/** Soma dias a uma data AAAA-MM-DD sem passar por fuso. */
export function somarDias(dia: string, n: number): string {
  return somarDiasAoDia(dia, n);
}

/** "05/11/2026" a partir de "2026-11-05" — dia de calendário sai como está (não vira o dia 04 no Brasil). */
export function dataBR(dia: string | null | undefined): string {
  return dia ? dataBRCompartilhada(dia.slice(0, 10)) : '—';
}

export const ROTULO_DA_SITUACAO: Record<SituacaoPlano, string> = {
  em_dia: 'em dia',
  na_janela: 'na janela',
  vencida: 'vencida',
  adiada: 'adiada',
};

export const CLASSE_DA_SITUACAO: Record<SituacaoPlano, string> = {
  em_dia: 'bg-muted text-muted-foreground',
  na_janela: 'bg-amber-500/15 text-amber-700 dark:text-amber-400',
  vencida: 'bg-destructive/15 text-destructive',
  adiada: 'bg-sky-500/15 text-sky-700 dark:text-sky-400',
};

/** "vence em 12 dias", "vence hoje", "venceu há 3 dias". */
export function prazoPorExtenso(dias: number): string {
  if (dias === 0) return 'vence hoje';
  if (dias === 1) return 'vence amanhã';
  if (dias > 1) return `vence em ${dias} dias`;
  if (dias === -1) return 'venceu ontem';
  return `venceu há ${-dias} dias`;
}

export const ROTULO_DO_EVENTO: Record<string, string> = {
  task_created: 'Tarefa criada na Agenda',
  reminder_proposed: 'Lembrete preparado (aguardando seu sim)',
  reminder_sent: 'Lembrete enviado ao cliente',
  reminder_skipped: 'Lembrete não enviado',
  client_replied: 'Cliente respondeu',
  snoozed: 'Adiado',
  scheduled: 'OS agendada',
  serviced: 'Serviço registrado',
  campaign_proposed: 'Campanha de temporada preparada',
  campaign_sent: 'Campanha de temporada enviada',
};

export const DIAS_DO_HORIZONTE = 30;

export interface RevisoesAgrupadas {
  /** Vencem nos próximos 30 dias (e não estão adiadas). */
  vencendo: PlanoNaView[];
  vencidas: PlanoNaView[];
  adiadas: PlanoNaView[];
  /** O cliente respondeu ao lembrete deste ciclo — é a lista de "ligar de volta". */
  responderam: PlanoNaView[];
  /** Soma do valor estimado do que vence em 30 dias + vencidas: o que está na mesa. */
  receitaPrevista: number;
}

const valor = (v: number | string | null | undefined) => {
  const n = Number(v ?? 0);
  return Number.isFinite(n) ? n : 0;
};

export function agruparRevisoes(linhas: PlanoNaView[]): RevisoesAgrupadas {
  const porVencimento = (a: PlanoNaView, b: PlanoNaView) => a.next_due_on.localeCompare(b.next_due_on);
  const vencendo = linhas
    .filter((l) => (l.situacao === 'em_dia' || l.situacao === 'na_janela')
      && l.dias_para_vencer >= 0 && l.dias_para_vencer <= DIAS_DO_HORIZONTE)
    .sort(porVencimento);
  const vencidas = linhas.filter((l) => l.situacao === 'vencida').sort(porVencimento);
  const adiadas = linhas.filter((l) => l.situacao === 'adiada').sort(porVencimento);
  const responderam = linhas.filter((l) => l.respondeu_no_ciclo).sort(porVencimento);
  const receitaPrevista = [...vencendo, ...vencidas].reduce((s, l) => s + valor(l.estimated_value), 0);
  return { vencendo, vencidas, adiadas, responderam, receitaPrevista };
}

// ─────────────────────────────────────────────────────────────────────────────
// "Sugerir planos" (botão do painel da embarcação)
//
// Lê o que JÁ foi feito na embarcação (OS concluídas: serviços e peças) e propõe os planos
// que fazem sentido. É uma proposta para o dono editar no formulário — nada é criado sem ele.
// Medido em 07/10/2026: dos serviços concluídos, a maioria tem service_system NULO, então a
// família se reconhece pelo sistema OU pelas palavras do nome do serviço/peça.
// ─────────────────────────────────────────────────────────────────────────────

export interface FamiliaDePlano {
  chave: string;
  nome: string;
  intervaloMeses: number;
  sistema: string | null;
  palavras: string[];
  escopo: string;
  /**
   * O sistema sozinho identifica a família? Não quando dois planos dividem o sistema (baterias ×
   * carregador, ambos elétrico DC) nem no mecânico, onde a base tem pneu e roda (07/10/2026).
   */
  sistemaBasta: boolean;
}

export const FAMILIAS_DE_PLANO: FamiliaDePlano[] = [
  { chave: 'baterias', nome: 'Revisão do banco de baterias', intervaloMeses: 12, sistema: 'eletrico_dc',
    palavras: ['bateria'], escopo: 'teste de carga, terminais, nível/estado das células', sistemaBasta: false },
  { chave: 'carregador', nome: 'Revisão de inversor e carregador', intervaloMeses: 12, sistema: 'eletrico_dc',
    palavras: ['inversor', 'carregador', 'conversor'], escopo: 'conexões, ventilação, parâmetros de carga', sistemaBasta: false },
  { chave: 'motor', nome: 'Revisão de motor', intervaloMeses: 12, sistema: 'mecanico',
    palavras: ['motor', 'óleo', 'oleo'], escopo: 'óleo, filtros, correias, rotor', sistemaBasta: false },
  { chave: 'gas', nome: 'Inspeção do sistema de gás', intervaloMeses: 12, sistema: 'gas',
    palavras: ['gás', 'gas', 'glp'], escopo: 'estanqueidade, mangueiras, regulador, sensor', sistemaBasta: true },
  { chave: 'refrigeracao', nome: 'Revisão de refrigeração / ar-condicionado', intervaloMeses: 12, sistema: 'refrigeracao',
    palavras: ['geladeira', 'refrigerador', 'ar condicionado', 'ar-condicionado'], escopo: 'limpeza, carga, vedação', sistemaBasta: true },
];

/** Uma linha do histórico da embarcação: um serviço ou uma peça de OS concluída. */
export interface ItemDoHistorico {
  dia: string;              // data do serviço (AAAA-MM-DD, Brasília)
  osId: string;
  osNumero: string | null;
  sistema: string | null;
  texto: string;            // name_snapshot do serviço ou nome do produto
  valor: number;
}

export interface SugestaoDePlano {
  familia: FamiliaDePlano;
  ultimoServico: string;
  ultimaOsId: string;
  ultimaOsNumero: string | null;
  valorEstimado: number | null;
  evidencias: string[];
}

const semAcento = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

function casaComFamilia(item: ItemDoHistorico, f: FamiliaDePlano): boolean {
  if (f.sistemaBasta && f.sistema && item.sistema === f.sistema) return true;
  const texto = semAcento(item.texto);
  // Palavra inteira no começo: "gas" não pode casar com "gasolina" nem "motor" com "motorhome".
  return f.palavras.some((p) => new RegExp(`(^|[^a-z])${semAcento(p)}(s|es)?($|[^a-z])`).test(texto));
}

/** Plano existente já cobre a família (mesmo sistema+palavra, ou nome parecido). */
function jaCoberta(f: FamiliaDePlano, existentes: Pick<PlanoDeManutencao, 'name' | 'match_keywords'>[]): boolean {
  return existentes.some((p) => {
    const nome = semAcento(p.name);
    const palavras = (p.match_keywords ?? []).map(semAcento);
    return f.palavras.some((w) => nome.includes(semAcento(w)) || palavras.includes(semAcento(w)));
  });
}

export function sugerirPlanos(
  historico: ItemDoHistorico[],
  existentes: Pick<PlanoDeManutencao, 'name' | 'match_keywords'>[],
): SugestaoDePlano[] {
  const saida: SugestaoDePlano[] = [];
  for (const f of FAMILIAS_DE_PLANO) {
    if (jaCoberta(f, existentes)) continue;
    const itens = historico.filter((i) => casaComFamilia(i, f));
    if (itens.length === 0) continue;
    const ultimoDia = itens.reduce((m, i) => (i.dia > m ? i.dia : m), itens[0].dia);
    const daUltima = itens.filter((i) => i.dia === ultimoDia);
    const total = daUltima.reduce((s, i) => s + (Number.isFinite(i.valor) ? i.valor : 0), 0);
    saida.push({
      familia: f,
      ultimoServico: ultimoDia,
      ultimaOsId: daUltima[0].osId,
      ultimaOsNumero: daUltima[0].osNumero,
      // Arredonda à dezena: é estimativa para a mensagem ("em torno de"), não preço.
      valorEstimado: total > 0 ? Math.round(total / 10) * 10 : null,
      evidencias: [...new Set(itens.map((i) => i.texto))].slice(0, 3),
    });
  }
  return saida;
}

/** "bateria, inversor" → ['bateria','inversor'] (minúsculas, sem vazios nem repetidos). */
export function lerPalavras(texto: string): string[] {
  return [...new Set(texto.split(/[,;]/).map((s) => s.trim().toLowerCase()).filter(Boolean))];
}

/** Ligado por padrão: só 'off'/'false'/'0'/'não' desligam (padrão 'on' da spec). */
export function interruptorLigado(valor: string | null | undefined): boolean {
  const v = String(valor ?? '').trim().toLowerCase();
  return !['off', 'false', '0', 'nao', 'não', 'desligado'].includes(v);
}

// ─────────────────────────────────────────────────────────────────────────────
// Prospecção › Revisões preventivas: embarcações SEM plano (07/10/2026)
//
// A aba antiga escolhia "última revisão" pelo created_at da OS (a data em que o ORÇAMENTO foi
// aberto, não a do serviço), não olhava se já havia OS mais nova, ignorava o opt-out e mandava a
// mensagem pelo whatsapp-send-text cru. Agora: data do serviço = saída ?? fim agendado ?? última
// alteração (a mesma do resumo das 07:30), fora quem tem OS mais nova, quem pediu PARAR e quem já
// tem plano — esses aparecem na lista dos planos, com o lembrete pelo fluxo do "sim".
// ─────────────────────────────────────────────────────────────────────────────

export interface OrdemDaEmbarcacao {
  vessel_id: string | null;
  status: string;
  created_at: string;
  check_out_at: string | null;
  scheduled_end_at: string | null;
  updated_at: string | null;
  vessel_name: string | null;
  client_name: string | null;
  opt_out: boolean | null;
}

export interface AlvoSemPlano {
  vesselId: string;
  embarcacao: string;
  cliente: string | null;
  ultimoServico: string;   // AAAA-MM-DD (Brasília)
  meses: number;
}

const CONCLUIDA = new Set(['completed', 'invoiced']);
const DESCARTADA = new Set(['cancelled', 'rejected']);

export function alvosSemPlano(
  ordens: OrdemDaEmbarcacao[],
  embarcacoesComPlano: Set<string>,
  agora: Date = new Date(),
  mesesMinimos = 6,
): AlvoSemPlano[] {
  const porEmbarcacao = new Map<string, OrdemDaEmbarcacao[]>();
  for (const o of ordens) {
    if (!o.vessel_id || DESCARTADA.has(o.status)) continue;
    const lista = porEmbarcacao.get(o.vessel_id) ?? [];
    lista.push(o);
    porEmbarcacao.set(o.vessel_id, lista);
  }
  const hoje = hojeEmBrasilia(agora);
  const saida: AlvoSemPlano[] = [];
  for (const [vesselId, lista] of porEmbarcacao) {
    if (embarcacoesComPlano.has(vesselId)) continue;
    const feitas = lista.filter((o) => CONCLUIDA.has(o.status));
    if (feitas.length === 0) continue;
    const quando = (o: OrdemDaEmbarcacao) => o.check_out_at ?? o.scheduled_end_at ?? o.updated_at ?? o.created_at;
    const ms = (s: string) => Date.parse(s);
    const ultima = feitas.reduce((m, o) => (ms(quando(o)) > ms(quando(m)) ? o : m), feitas[0]);
    const momento = quando(ultima);
    // OS aberta (orçamento, agendada, em andamento) criada depois do último serviço: a conversa já
    // está acontecendo — oferecer revisão por cima seria ruído.
    if (lista.some((o) => !CONCLUIDA.has(o.status) && ms(o.created_at) > ms(momento))) continue;
    if (ultima.opt_out || lista.some((o) => o.opt_out)) continue;
    const dia = hojeEmBrasilia(new Date(momento));
    const [a1, m1] = dia.split('-').map(Number);
    const [a2, m2, d2] = hoje.split('-').map(Number);
    const meses = (a2 - a1) * 12 + (m2 - m1) - (d2 < Number(dia.slice(8, 10)) ? 1 : 0);
    if (meses < mesesMinimos) continue;
    saida.push({
      vesselId, embarcacao: ultima.vessel_name ?? 'Embarcação', cliente: ultima.client_name, ultimoServico: dia, meses,
    });
  }
  return saida.sort((a, b) => b.meses - a.meses);
}
