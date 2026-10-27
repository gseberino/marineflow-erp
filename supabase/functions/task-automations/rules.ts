// Regras do motor de automações da Agenda & Tarefas 2.0.
// Cada regra sabe (a) achar entidades em condição e (b) dizer se a condição
// de uma tarefa viva já se resolveu. Dedupe via automation_key (índice único
// parcial agenda_tasks_automation_key_live). Plano: plans/marineflow-agenda-tarefas.md §6.
import { ultimoDiaDaValidade, validadeDoOrcamento, vencimentoDoOrcamento } from '../_shared/pdf/documento.ts';
import { diaBR, somarDiasAoDia } from '../_shared/pdf/datas.ts';
import { nomeDaUnidade, TERMO_GERAL } from '../_shared/unidade.ts';
import { ROTULOS_STATUS_OS, type StatusOS } from '../_shared/service-order-status.ts';
import { MODOS_DESLIGADOS, type ModosDaAgenda, R15_DESLIGADA, r15DesligadaPelaAgenda } from './agenda-modos.ts';

export interface RuleCandidate {
  automation_key: string;
  title: string;
  priority: 'low' | 'normal' | 'high' | 'urgent';
  /** 'admin' | 'financial' → resolvido para o primeiro app_user ativo do cargo (sem financeiro
   *  ativo, cai no admin: responsavel.ts); um uuid → usa direto; null → tarefa sem responsável */
  assignee: 'admin' | 'financial' | string | null;
  due_at: string | null;
  related_entity_type: string | null;
  related_entity_id: string | null;
  client_id?: string | null;
  notes?: string | null;
}

export interface Rule {
  id: string;
  label: string;
  /** app_settings key: `task_rule_<id>_enabled` = 'true'/'false' */
  defaultEnabled: boolean;
  find(db: any): Promise<RuleCandidate[]>;
  /** motivo da resolução se a condição sumiu; null se ainda vale */
  isResolved(db: any, task: { automation_key: string }): Promise<string | null>;
  /**
   * Tarefa que o dono concluiu ou cancelou não volta, sem prazo, enquanto o candidato tiver o
   * MESMO título (ver dispensaSemFatoNovo). Para regra cujo título descreve a condição inteira.
   */
  voltaSoComFatoNovo?: boolean;
  /**
   * Para regra com `voltaSoComFatoNovo`: houve fato novo na entidade da tarefa desde `desdeISO`
   * (quando o dono a fechou), mesmo com o título igual? true = a dispensa não vale e a tarefa volta.
   */
  mudouDesde?(db: any, automationKey: string, desdeISO: string): Promise<boolean>;
  /**
   * Agenda de Produção, Fase 2 (P3, 24/10/2026; decisão d13): a regra sai no mesmo instante em que a substituta entra —
   * pelo MESMO interruptor (agenda_config). Devolve o motivo ("a agenda automática marca as OS") quando a agenda já
   * faz o trabalho desta regra: o motor não procura candidatos e as tarefas vivas dela se resolvem com esse motivo.
   * null = a regra vale como sempre.
   */
  desligadaPelaAgenda?(m: ModosDaAgenda): string | null;
}

export const fmtBRL = (v: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v || 0);

export const fmtDate = (d: string) => {
  const [y, m, day] = String(d).slice(0, 10).split('-');
  return `${day}/${m}/${y}`;
};

/** due_at padrão de tarefa de automação: 08:00 America/Sao_Paulo (11:00Z) do dia. */
export const dueAt = (dateISO: string) => `${String(dateISO).slice(0, 10)}T11:00:00Z`;

export const keyOf = (rule: string, entity: string, id: string, bucket?: string) =>
  bucket ? `${rule}:${entity}:${id}:${bucket}` : `${rule}:${entity}:${id}`;

/** id da entidade a partir da automation_key (3º segmento). */
export const entityIdFromKey = (key: string) => key.split(':')[2] || '';

/**
 * R10: o lembrete ao técnico pelo WhatsApp da equipe. O número da OS já traz o prefixo
 * ("OS-00060", "ORÇ-00112"), então vai como vem: "você tem a OS-00060", nunca "a OS OS-00060".
 * Com o tipo (21/10/2026, decisão 9): "(Motorhome Iveco Daily)", "(Lancha Netuno)".
 */
export function textoDoLembreteDaOs(p: {
  quando: string;
  hora: string;
  numero: string;
  cliente?: string | null;
  barco?: string | null;
  /** O tipo da unidade (vessels.asset_type). */
  tipo?: string | null;
}): string {
  const unidade = p.barco ? nomeDaUnidade({ name: p.barco, asset_type: p.tipo }) : '';
  return `🔧 Lembrete: ${p.quando} às ${p.hora} você tem a ${p.numero}` +
    ` — ${p.cliente || 'cliente'}${unidade ? ` (${unidade})` : ''}.`;
}

/** A unidade no título de uma tarefa: "Lancha Mar Azul", "Motorhome Iveco Daily"; sem nome nem tipo, o termo geral. */
const unidadeNoTitulo = (name: string | null | undefined, tipo: string | null | undefined) =>
  name || tipo ? nomeDaUnidade({ name, asset_type: tipo }) : TERMO_GERAL.toLowerCase();

const daysAgoISO = (days: number) => new Date(Date.now() - days * 86400000).toISOString();

/**
 * Dias ÚTEIS entre duas datas. Usado no prazo de resposta do fornecedor: contar dias
 * corridos faria a cobrança disparar na segunda por causa do fim de semana.
 * Espelha src/lib/quote-comparison.ts#businessDaysSince (a tela mostra o mesmo número).
 */
export function businessDaysBetween(from: string | Date, to: Date): number {
  const start = typeof from === 'string' ? new Date(from) : from;
  if (Number.isNaN(start.getTime())) return 0;
  let days = 0;
  const cursor = new Date(start);
  cursor.setHours(0, 0, 0, 0);
  const end = new Date(to);
  end.setHours(0, 0, 0, 0);
  while (cursor < end) {
    cursor.setDate(cursor.getDate() + 1);
    const dow = cursor.getDay();
    if (dow !== 0 && dow !== 6) days++;
  }
  return days;
}
const todayISO = () => new Date().toISOString().slice(0, 10);
const inDaysISO = (days: number) => new Date(Date.now() + days * 86400000).toISOString().slice(0, 10);

// ---------------------------------------------------------------------------
// OS comprometida com o cliente (Agenda de Produção, Fase 0, 23/10/2026; D10).
//
// A R1 só olhava 'approved', e a R16 deixava 'open' de fora. Mas 'open' é o caminho normal da
// conversão (13 de 19 em 90 dias): OS-00069, 74 e 100, com sinal pago, ficavam sem tarefa de
// agendar e sem tarefa de comprar. O orçamento aprovado e ainda sem sinal (ORÇ-00083) não aparecia
// em nenhuma das duas.
//
// Um predicado por regra, e o MESMO no find e no isResolved. Quando as duas pontas divergem, a
// tarefa nasce numa rodada e morre na seguinte: a OS-00104 gerou 1.142 tarefas assim até 15/10.
// O find pede ao banco o mesmo recorte (FILTRO_PARA_AGENDAR/FILTRO_PARA_COMPRAR, com teste de
// equivalência em rules_test.ts) e, por garantia, passa o predicado sobre as linhas que voltaram.

/** O que os predicados leem de uma linha de service_orders. */
export interface LinhaComprometida {
  status: string;
  quote_status?: string | null;
  merged_into_id?: string | null;
  scheduled_start_at?: string | null;
}

/** OS que a R1 manda agendar. */
export const STATUS_PARA_AGENDAR = ['approved', 'open'] as const;

/** OS que a R16 manda comprar: comprometida e ainda não encerrada. 'awaiting_client' fica fora, como antes. */
export const STATUS_PARA_COMPRAR = ['approved', 'open', 'scheduled', 'in_progress', 'awaiting_parts'] as const;

/**
 * Orçamento que o cliente aprovou e que ainda não virou OS, porque falta o sinal (d08: sinal pago
 * para agendar), e que não foi agrupado em outro. 'awaiting_deposit' fica fora: já tem a R6 e a
 * R19, e o próximo passo dele é o sinal, não a compra nem a data.
 */
export const orcamentoAprovado = (o: LinhaComprometida): boolean =>
  o.status === 'draft' && o.quote_status === 'approved' && !o.merged_into_id;

/**
 * R1: 'os' = OS comprometida e sem data; 'orc' = orçamento aprovado sem sinal; null = nada a agendar.
 * No orçamento a data não decide: com ou sem data, o que falta é o sinal.
 */
export function paraAgendar(o: LinhaComprometida): 'os' | 'orc' | null {
  if (o.merged_into_id) return null;
  if ((STATUS_PARA_AGENDAR as readonly string[]).includes(o.status)) return o.scheduled_start_at ? null : 'os';
  return orcamentoAprovado(o) ? 'orc' : null;
}

/** R16: 'os' = OS comprometida e não encerrada; 'orc' = orçamento aprovado sem sinal; null = nada a comprar. */
export function paraComprar(o: LinhaComprometida): 'os' | 'orc' | null {
  if (o.merged_into_id) return null;
  if ((STATUS_PARA_COMPRAR as readonly string[]).includes(o.status)) return 'os';
  return orcamentoAprovado(o) ? 'orc' : null;
}

/** O `.or()` do PostgREST com o recorte de paraAgendar (junto com `.is('merged_into_id', null)`). */
export const FILTRO_PARA_AGENDAR =
  `and(status.in.(${STATUS_PARA_AGENDAR.join(',')}),scheduled_start_at.is.null),and(status.eq.draft,quote_status.eq.approved)`;

/** O `.or()` do PostgREST com o recorte de paraComprar (junto com `.is('merged_into_id', null)`). */
export const FILTRO_PARA_COMPRAR =
  `status.in.(${STATUS_PARA_COMPRAR.join(',')}),and(status.eq.draft,quote_status.eq.approved)`;

/** Por que um orçamento deixou de ser "aprovado sem sinal" (R1 orc e R16). */
function motivoDoOrcamento(o: LinhaComprometida): string {
  if (o.merged_into_id) return 'Orçamento agrupado em outro';
  if (o.status === 'cancelled') return 'Orçamento cancelado';
  if (o.status !== 'draft') return `Orçamento virou OS (${ROTULOS_STATUS_OS[o.status as StatusOS] ?? o.status})`;
  return `Orçamento mudou para ${o.quote_status ?? 'sem estado'}`;
}

const r1: Rule = {
  id: 'r1',
  label: 'OS aprovada ou aberta sem agendamento (24h)',
  defaultEnabled: true,
  async find(db) {
    const { data, error } = await db
      .from('service_orders')
      .select('id, service_order_number, status, quote_status, merged_into_id, scheduled_start_at, client_id, clients(name)')
      .or(FILTRO_PARA_AGENDAR)
      .is('merged_into_id', null)
      .lt('updated_at', daysAgoISO(1))
      .limit(50);
    // Erro não pode virar "nenhuma OS para agendar" (era engolido até 23/10/2026).
    if (error) throw error;
    return (data || []).flatMap((o: any) => {
      const tipo = paraAgendar(o);
      if (!tipo) return [];
      const base = {
        priority: 'high' as const,
        assignee: 'admin' as const,
        due_at: dueAt(inDaysISO(1)),
        related_entity_type: 'service_order',
        related_entity_id: o.id,
        client_id: o.client_id,
      };
      // Orçamento: chave própria. Quando ele converte, esta se resolve e nasce a r1:so (24 h depois).
      if (tipo === 'orc') {
        return [{
          ...base,
          automation_key: keyOf('r1', 'orc', o.id),
          title: `${o.service_order_number} aprovado sem sinal — receber o sinal e converter para agendar` +
            (o.clients?.name ? ` (${o.clients.name})` : ''),
        }];
      }
      return [{
        ...base,
        automation_key: keyOf('r1', 'so', o.id),
        title: `Agendar ${o.service_order_number} — ${o.clients?.name || 'sem cliente'}`,
      }];
    });
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    // O 2º segmento da chave diz o que a tarefa pedia: 'so' (agendar a OS) ou 'orc' (receber o sinal).
    const ehOrcamento = task.automation_key.split(':')[1] === 'orc';
    const { data, error } = await db.from('service_orders')
      .select('status, quote_status, merged_into_id, scheduled_start_at').eq('id', id).maybeSingle();
    // Erro não pode virar "não existe mais": a tarefa sumiria com a condição de pé.
    if (error) throw error;
    if (ehOrcamento) {
      if (!data) return 'Orçamento não existe mais';
      return paraAgendar(data) === 'orc' ? null : motivoDoOrcamento(data);
    }
    if (!data) return 'OS não existe mais';
    if (paraAgendar(data) === 'os') return null;
    if (data.scheduled_start_at) return 'OS foi agendada';
    return `OS mudou para ${data.status}`;
  },
  // Com a agenda automática ligada quem marca a OS é a agenda (publica na quinta, encaixa a que ficou pronta).
  desligadaPelaAgenda: (m) => (m.proposta === 'ligado' ? 'a agenda automática marca as OS' : null),
};

const r2: Rule = {
  id: 'r2',
  label: 'OS em andamento parada (3 dias)',
  defaultEnabled: true,
  async find(db) {
    const { data, error } = await db
      .from('service_orders')
      .select('id, service_order_number, client_id, updated_at, clients(name)')
      .eq('status', 'in_progress')
      .lt('updated_at', daysAgoISO(3))
      .limit(50);
    // Erro não pode virar "nenhuma OS parada" (era engolido até 24/10/2026: NOVO-agenda-09).
    if (error) throw error;
    return (data || []).map((o: any) => {
      const dias = Math.floor((Date.now() - new Date(o.updated_at).getTime()) / 86400000);
      return {
        automation_key: keyOf('r2', 'so', o.id),
        title: `Verificar ${o.service_order_number} parada há ${dias} dias — ${o.clients?.name || ''}`.trim(),
        priority: 'normal' as const,
        assignee: 'admin' as const,
        due_at: dueAt(todayISO()),
        related_entity_type: 'service_order',
        related_entity_id: o.id,
        client_id: o.client_id,
      };
    });
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    const { data, error } = await db.from('service_orders')
      .select('status, updated_at').eq('id', id).maybeSingle();
    // Erro não pode virar "OS não existe mais": a tarefa sumiria com a OS parada de pé (NOVO-agenda-09).
    if (error) throw error;
    if (!data) return 'OS não existe mais';
    if (data.status !== 'in_progress') return `OS mudou para ${data.status}`;
    if (new Date(data.updated_at) > new Date(daysAgoISO(3))) return 'OS voltou a andar';
    return null;
  },
  // Com a vigia ligada a pergunta "parou?" é dela (pela última evidência: diária, dia feito ou início), uma vez só.
  desligadaPelaAgenda: (m) => (m.vigia === 'ligado' ? 'a agenda pergunta quando a OS para' : null),
};

/**
 * Cobrança abaixo deste valor não vira tarefa (06/10/2026, inventário): saldo de R$ 20 virava
 * "URGENTE: cliente em atraso" ao lado das cobranças de milhares.
 *
 * O piso é o MESMO da régua de cobrança (app_settings.collection_min_amount, R$ 200 desde 17/09):
 * receivable-reminders, get_delinquency_plan e send_collection_reminder já o liam. Uma regra só para
 * "quanto vale cobrar" — a 1ª versão criou uma chave à parte, e duas chaves para o mesmo padrão
 * divergem em silêncio. Sem a chave (ou valor inválido), sem corte, como nos outros três.
 */
export const CHAVE_DO_PISO_DE_COBRANCA = 'collection_min_amount';

export async function cobrancaMinima(db: any): Promise<number> {
  const { data } = await db.from('app_settings')
    .select('value').eq('key', CHAVE_DO_PISO_DE_COBRANCA).maybeSingle();
  const v = Number(String(data?.value ?? '').replace(',', '.'));
  return Number.isFinite(v) && v > 0 ? v : 0;
}

/** O que falta receber da conta (o saldo, ou o valor cheio quando o saldo não foi gravado). */
export const valorEmAberto = (r: { balance_amount?: number | null; amount?: number | null }) =>
  Number(r.balance_amount ?? r.amount ?? 0);

async function receivableResolved(db: any, key: string): Promise<string | null> {
  const id = entityIdFromKey(key);
  const [{ data }, minimo] = await Promise.all([
    db.from('receivables').select('status, amount, balance_amount').eq('id', id).maybeSingle(),
    cobrancaMinima(db),
  ]);
  if (!data) return 'Recebível não existe mais';
  if (data.status === 'paid') return 'Pagamento registrado';
  if (data.status === 'cancelled') return 'Recebível cancelado';
  if (valorEmAberto(data) < minimo) return 'Saldo abaixo do mínimo de cobrança';
  return null;
}

const r3: Rule = {
  id: 'r3',
  label: 'Recebível vencendo (D-3)',
  defaultEnabled: true,
  async find(db) {
    const { data } = await db
      .from('receivables')
      .select('id, description, amount, balance_amount, due_date, client_id, clients(name)')
      .in('status', ['pending', 'partially_paid'])
      .gte('due_date', todayISO())
      .lte('due_date', inDaysISO(3))
      .limit(50);
    const minimo = await cobrancaMinima(db);
    return (data || []).filter((r: any) => valorEmAberto(r) >= minimo).map((r: any) => ({
      automation_key: keyOf('r3', 'recv', r.id),
      title: `Cobrar ${r.clients?.name || 'cliente'} — ${fmtBRL(r.balance_amount ?? r.amount)} vence ${fmtDate(r.due_date)}`,
      priority: 'normal' as const,
      assignee: 'financial' as const,
      due_at: dueAt(r.due_date),
      related_entity_type: 'receivable',
      related_entity_id: r.id,
      client_id: r.client_id,
      notes: r.description || null,
    }));
  },
  isResolved: (db, task) => receivableResolved(db, task.automation_key),
};

const r4: Rule = {
  id: 'r4',
  label: 'Recebível VENCIDO',
  defaultEnabled: true,
  async find(db) {
    const { data } = await db
      .from('receivables')
      .select('id, description, amount, balance_amount, due_date, client_id, clients(name)')
      .in('status', ['pending', 'partially_paid'])
      .lt('due_date', todayISO())
      .limit(50);
    const minimo = await cobrancaMinima(db);
    return (data || []).filter((r: any) => valorEmAberto(r) >= minimo).map((r: any) => ({
      automation_key: keyOf('r4', 'recv', r.id),
      title: `URGENTE: ${r.clients?.name || 'cliente'} em atraso — ${fmtBRL(r.balance_amount ?? r.amount)} venceu ${fmtDate(r.due_date)}`,
      priority: 'urgent' as const,
      assignee: 'financial' as const,
      due_at: dueAt(todayISO()),
      related_entity_type: 'receivable',
      related_entity_id: r.id,
      client_id: r.client_id,
      notes: r.description || null,
    }));
  },
  isResolved: (db, task) => receivableResolved(db, task.automation_key),
};

const r5: Rule = {
  id: 'r5',
  label: 'Pagável vencendo (D-1)',
  defaultEnabled: true,
  async find(db) {
    const { data } = await db
      .from('payables')
      .select('id, supplier_name, description, amount, balance_amount, due_date')
      .in('status', ['pending', 'partially_paid'])
      .lte('due_date', inDaysISO(1))
      .limit(50);
    return (data || []).map((p: any) => ({
      automation_key: keyOf('r5', 'pay', p.id),
      title: `Pagar ${p.supplier_name || 'fornecedor'} — ${fmtBRL(p.balance_amount ?? p.amount)} vence ${fmtDate(p.due_date)}`,
      priority: 'high' as const,
      assignee: 'financial' as const,
      due_at: dueAt(p.due_date),
      related_entity_type: 'payable',
      related_entity_id: p.id,
      notes: p.description || null,
    }));
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    const { data } = await db.from('payables').select('status').eq('id', id).maybeSingle();
    if (!data) return 'Pagável não existe mais';
    if (data.status === 'paid') return 'Pagamento registrado';
    if (data.status === 'cancelled') return 'Pagável cancelado';
    return null;
  },
};

const r6: Rule = {
  id: 'r6',
  label: 'Orçamento sem resposta (3 dias)',
  defaultEnabled: true,
  async find(db) {
    // Só orçamento de verdade: rascunho não convertido. Sem este filtro, OS concluída e paga
    // com quote_status 'sent' parado (assinada pelo link, que não mexe no quote_status) virava
    // "orçamento sem resposta" — ORÇ-00070 ficou com tarefa aberta de 03/08 a 26/09/2026.
    const { data } = await db
      .from('service_orders')
      .select('id, service_order_number, client_id, created_by, clients(name)')
      .in('quote_status', ['sent', 'awaiting_approval'])
      .eq('status', 'draft')
      .is('converted_to_os_at', null)
      .lt('updated_at', daysAgoISO(3))
      .limit(50);
    return (data || []).map((o: any) => ({
      automation_key: keyOf('r6', 'quote', o.id),
      title: `Follow-up do orçamento ${o.service_order_number} — ${o.clients?.name || 'cliente'} sem resposta`,
      priority: 'normal' as const,
      assignee: (o.created_by as string) || ('admin' as const),
      due_at: dueAt(todayISO()),
      related_entity_type: 'service_order',
      related_entity_id: o.id,
      client_id: o.client_id,
    }));
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    const { data } = await db.from('service_orders')
      .select('quote_status, status, converted_to_os_at').eq('id', id).maybeSingle();
    if (!data) return 'OS não existe mais';
    if (!['sent', 'awaiting_approval'].includes(data.quote_status)) {
      return `Orçamento mudou para ${data.quote_status}`;
    }
    // O mesmo filtro do find: deixou de ser orçamento (aprovado, em execução, concluído,
    // cancelado ou convertido), não há mais resposta a cobrar.
    if (data.converted_to_os_at) return 'Orçamento convertido em OS';
    if (data.status !== 'draft') return `Deixou de ser orçamento (${data.status})`;
    return null;
  },
};

// R7 (23/10/2026, item 15 da revisão): OC de OS encerrada não se cobra. A OC-00001 (Mercado Pago)
// ficou cobrada desde 23/08 com a OS-00073 já faturada — a peça tinha chegado e a OC nunca foi
// fechada. A OS da OC vem pelo embed com a FK explícita (purchase_orders tem uma só para
// service_orders, mas o nome evita o PGRST201 se aparecer outra).
const OS_ENCERRADAS: readonly string[] = ['completed', 'invoiced', 'cancelled'];
const SELECT_OS_DA_OC = 'service_orders!purchase_orders_service_order_id_fkey(status)';

/** O status da OS ligada à OC, se ela estiver encerrada; null se a OC não tem OS ou a OS segue viva. */
const osDaOcEncerrada = (p: { service_orders?: { status?: string | null } | null }): string | null => {
  const st = p.service_orders?.status ?? null;
  return st && OS_ENCERRADAS.includes(st) ? st : null;
};

/**
 * Agenda de Produção, Fase 4 (P2): as OCs cujo material a agenda já acompanha — a pergunta "chegou?" aberta em ligado,
 * ou tudo na mão — não se cobram (agenda_ocs_com_material_vivo, 20261027100200): {<po_id>: motivo}. A função ausente
 * (a migration ainda não aplicada: PGRST202 do PostgREST, 42883 do Postgres) = nenhuma, como antes; outro erro lança
 * (viraria "cobrar tudo" ou "nada a cobrar" calado).
 */
// deno-lint-ignore no-explicit-any
async function ocsComMaterialVivo(db: any, ids: string[]): Promise<Record<string, string>> {
  if (!ids.length) return {};
  const { data, error } = await db.rpc('agenda_ocs_com_material_vivo', { p_po_ids: ids });
  if (error) {
    const code = String((error as { code?: unknown }).code ?? '');
    if (code === 'PGRST202' || code === '42883') return {};
    throw error;
  }
  return (data ?? {}) as Record<string, string>;
}

const r7: Rule = {
  id: 'r7',
  label: 'OC não recebida no prazo',
  defaultEnabled: true,
  async find(db) {
    const { data, error } = await db
      .from('purchase_orders')
      .select(`id, po_number, expected_date, created_at, suppliers(name), ${SELECT_OS_DA_OC}`)
      .in('status', ['sent', 'partial'])
      .limit(100);
    // Com o embed novo, um erro de consulta viraria "nenhuma OC atrasada" calado: lança.
    if (error) throw error;
    const now = Date.now();
    const atrasadas = (data || [])
      .filter((p: any) => !osDaOcEncerrada(p))
      .filter((p: any) => p.expected_date
        ? p.expected_date < todayISO()
        : new Date(p.created_at).getTime() < now - 7 * 86400000);
    // O material que a agenda já acompanha (Fase 4, P2): ela pergunta ao dono se chegou, ou já registrou a chegada.
    const vivas = await ocsComMaterialVivo(db, atrasadas.map((p: any) => p.id));
    return atrasadas
      .filter((p: any) => !vivas[p.id])
      .map((p: any) => ({
        automation_key: keyOf('r7', 'po', p.id),
        title: `Cobrar entrega da OC ${p.po_number} — ${p.suppliers?.name || 'fornecedor'}`,
        priority: 'normal' as const,
        assignee: 'admin' as const,
        due_at: dueAt(todayISO()),
        related_entity_type: 'purchase_order',
        related_entity_id: p.id,
      }));
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    const { data, error } = await db.from('purchase_orders')
      .select(`status, ${SELECT_OS_DA_OC}`).eq('id', id).maybeSingle();
    // Erro não pode virar "OC não existe mais".
    if (error) throw error;
    if (!data) return 'OC não existe mais';
    if (['received', 'cancelled'].includes(data.status)) return `OC ${data.status === 'received' ? 'recebida' : 'cancelada'}`;
    const encerrada = osDaOcEncerrada(data);
    if (encerrada) return `A OS da OC foi ${ROTULOS_STATUS_OS[encerrada as StatusOS].toLowerCase()}`;
    // Fase 4 (P2): o motivo da agenda ("a agenda já pergunta se chegou" / "a agenda registrou que chegou").
    const vivas = await ocsComMaterialVivo(db, [id]);
    if (vivas[id]) return vivas[id];
    return null;
  },
};

const r8: Rule = {
  id: 'r8',
  label: 'Estoque abaixo do mínimo',
  defaultEnabled: true,
  async find(db) {
    const { data } = await db
      .from('products')
      .select('id, name, stock_quantity, minimum_stock, unit')
      .eq('active', true)
      .gt('minimum_stock', 0)
      .limit(500);
    return (data || [])
      .filter((p: any) => Number(p.stock_quantity) < Number(p.minimum_stock))
      .slice(0, 50)
      .map((p: any) => ({
        automation_key: keyOf('r8', 'prod', p.id),
        title: `Repor ${p.name} (atual: ${p.stock_quantity} ${p.unit || ''}, mín: ${p.minimum_stock})`,
        priority: 'normal' as const,
        assignee: 'admin' as const,
        due_at: null,
        related_entity_type: 'stock_item',
        related_entity_id: p.id,
      }));
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    const { data } = await db.from('products')
      .select('active, stock_quantity, minimum_stock').eq('id', id).maybeSingle();
    if (!data) return 'Produto não existe mais';
    if (!data.active) return 'Produto inativado';
    if (Number(data.stock_quantity) >= Number(data.minimum_stock)) return 'Estoque reposto';
    return null;
  },
};

// R11 (Fase 4): nota fiscal de entrada com problema/rejeitada
const r11: Rule = {
  id: 'r11',
  label: 'Nota fiscal com pendência',
  defaultEnabled: true,
  async find(db) {
    const { data } = await db
      .from('fiscal_notes')
      .select('id, nfe_number, issuer_name, status')
      .in('status', ['error', 'rejected'])
      .limit(50);
    return (data || []).map((n: any) => ({
      automation_key: keyOf('r11', 'nf', n.id),
      title: `Resolver NF ${n.nfe_number || ''} com pendência (${n.status}) — ${n.issuer_name || ''}`.trim(),
      priority: 'high' as const,
      assignee: 'financial' as const,
      due_at: dueAt(todayISO()),
      related_entity_type: null,
      related_entity_id: null,
    }));
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    const { data } = await db.from('fiscal_notes').select('status').eq('id', id).maybeSingle();
    if (!data) return 'Nota não existe mais';
    if (!['error', 'rejected'].includes(data.status)) return `Nota mudou para ${data.status}`;
    return null;
  },
};

// R12 (Fase 4): lead externo sem andamento há 5 dias
const r12: Rule = {
  id: 'r12',
  label: 'Orçamento externo submetido sem análise (2 dias)',
  defaultEnabled: true,
  async find(db) {
    const { data } = await db
      .from('external_quotes')
      .select('id, quote_number, submitted_at')
      .eq('status', 'submitted')
      .lt('submitted_at', daysAgoISO(2))
      .limit(50);
    return (data || []).map((q: any) => ({
      automation_key: keyOf('r12', 'eq', q.id),
      title: `Analisar orçamento externo ${q.quote_number} (aguardando desde ${fmtDate(q.submitted_at)})`,
      priority: 'normal' as const,
      assignee: 'admin' as const,
      due_at: dueAt(todayISO()),
      related_entity_type: 'external_quote',
      related_entity_id: q.id,
    }));
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    const { data } = await db.from('external_quotes').select('status').eq('id', id).maybeSingle();
    if (!data) return 'Orçamento não existe mais';
    if (data.status !== 'submitted') return `Orçamento mudou para ${data.status}`;
    return null;
  },
};

// R14 (Fase 8; reescrita em 07/10/2026 sobre v_maintenance_plans_due): plano entrou na janela →
// propor revisão. Mesmo id e mesma chave de antes (r14:plan:<id>:<last_service_at|first>) para não
// perder a configuração nem duplicar tarefa viva. O vencimento e a janela vêm da VIEW (antes a regra
// calculava o seu, em UTC e com advance_days; a tela calculava outro). A tarefa nasce às 08:00 do
// dia em que a janela abre (21 dias antes, ou o fim do adiamento) e se resolve quando o ciclo muda
// (serviço feito), o plano é adiado, ganha OS agendada ou é desligado.
export interface PlanoDaR14 {
  plan_id: string;
  plan_name: string;
  vessel_id: string;
  vessel_name: string | null;
  /** O tipo da unidade (vessels.asset_type; a view não traz): "Lancha Mar Azul", "Motorhome Iveco Daily". */
  asset_type?: string | null;
  client_id: string | null;
  client_name: string | null;
  scope: string | null;
  estimated_value: number | string | null;
  last_service_at: string | null;
  next_due_on: string;
  window_opens_on: string;
  situacao: string;
  tem_os_agendada: boolean;
}

/** A tarefa da R14 para um plano da view, ou null (adiado, com OS agendada ou fora da janela). */
export function candidatoDaR14(p: PlanoDaR14, hoje: string): RuleCandidate | null {
  if (p.situacao === 'adiada' || p.tem_os_agendada || p.window_opens_on > hoje) return null;
  const notas = [
    `Vence ${fmtDate(p.next_due_on)}${p.situacao === 'vencida' ? ' (VENCIDA)' : ''}.`,
    p.client_name ? `Cliente: ${p.client_name}.` : null,
    p.scope ? `Escopo: ${p.scope}.` : null,
    Number(p.estimated_value) > 0 ? `Valor estimado: ${fmtBRL(Number(p.estimated_value))}.` : null,
    p.last_service_at ? `Último serviço: ${fmtDate(p.last_service_at)}.` : 'Sem serviço anterior registrado.',
    'O lembrete ao cliente (com o seu sim) chega pelo WhatsApp de terça a quinta.',
  ].filter(Boolean).join('\n');
  return {
    automation_key: keyOf('r14', 'plan', p.plan_id, p.last_service_at || 'first'),
    title: `Propor revisão: ${p.plan_name} — ${unidadeNoTitulo(p.vessel_name, p.asset_type)}`,
    priority: p.situacao === 'vencida' ? 'high' : 'normal',
    assignee: 'admin',
    due_at: dueAt(p.window_opens_on),
    related_entity_type: 'vessel',
    related_entity_id: p.vessel_id,
    client_id: p.client_id,
    notes: notas,
  };
}

/** Por que a tarefa da R14 deixou de valer, ou null. */
export function resolucaoDaR14(
  bucket: string,
  plano: { active: boolean } | null,
  daView: { last_service_at: string | null; snoozed_until: string | null; tem_os_agendada: boolean; os_agendada_numero?: string | null } | null,
  hoje: string,
): string | null {
  if (!plano) return 'Plano não existe mais';
  if (!plano.active || !daView) return 'Plano desativado';
  if ((daView.last_service_at || 'first') !== bucket) return 'Serviço registrado no plano';
  if (daView.snoozed_until && daView.snoozed_until > hoje) return `Adiado até ${fmtDate(daView.snoozed_until)}`;
  // O título da tarefa já diz qual unidade ("— Motorhome Iveco Daily"): a nota não repete.
  if (daView.tem_os_agendada) return `${daView.os_agendada_numero || 'OS'} aberta`;
  return null;
}

const r14: Rule = {
  id: 'r14',
  label: 'Plano de manutenção vencendo',
  defaultEnabled: true,
  async find(db) {
    const hoje = diaBR(new Date());
    const { data, error } = await db
      .from('v_maintenance_plans_due')
      .select('plan_id, plan_name, vessel_id, vessel_name, client_id, client_name, scope, estimated_value, last_service_at, next_due_on, window_opens_on, situacao, tem_os_agendada')
      .lte('window_opens_on', hoje)
      .limit(500);
    if (error) throw error;
    const planos = (data as PlanoDaR14[]) || [];
    // O tipo da unidade para o título (21/10/2026, decisão 9): a view não traz. Se a leitura falhar,
    // o título sai só com o nome, como antes — a tarefa não pode deixar de nascer por causa do rótulo.
    const ids = [...new Set(planos.map((p) => p.vessel_id).filter(Boolean))];
    if (ids.length) {
      const { data: tipos, error: eT } = await db.from('vessels').select('id, asset_type').in('id', ids);
      if (eT) console.warn('[task-automations] r14: tipo das unidades não lido:', eT.message);
      const tipoPorId = new Map(((tipos as Array<{ id: string; asset_type: string | null }>) || []).map((v) => [v.id, v.asset_type]));
      for (const p of planos) p.asset_type = tipoPorId.get(p.vessel_id) ?? null;
    }
    return planos
      .map((p) => candidatoDaR14(p, hoje))
      .filter((c): c is RuleCandidate => c !== null);
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    const bucket = task.automation_key.split(':')[3];
    const { data: plano, error } = await db.from('maintenance_plans').select('active').eq('id', id).maybeSingle();
    if (error) throw error;
    const { data: daView, error: eV } = await db.from('v_maintenance_plans_due')
      .select('last_service_at, snoozed_until, tem_os_agendada, os_agendada_numero').eq('plan_id', id).maybeSingle();
    if (eV) throw eV;
    return resolucaoDaR14(bucket, plano, daView, diaBR(new Date()));
  },
};

/**
 * O cliente confirmou ESTE horário? (registrar_confirmacao_do_cliente grava o scheduled_start_at
 * confirmado; remarcou → a confirmação antiga não vale para a data nova.) 30/09/2026.
 */
export function confirmadoParaAData(confirmadoPara: string | null | undefined, agendadoPara: string | null | undefined): boolean {
  if (!confirmadoPara || !agendadoPara) return false;
  return new Date(confirmadoPara).getTime() === new Date(agendadoPara).getTime();
}

// R15: a alternativa ESCOLHIDA no lugar do envio automático ao cliente (R9, aposentada em 23/10/2026).
// Em vez de o sistema mandar WhatsApp sozinho na véspera, ele cria uma TAREFA sua:
// "confirmar com fulano o atendimento de amanhã". Você abre a agenda, vê a lista do dia e
// dispara pelo botão, um a um. Nada sai daqui — esta regra não envia nada a ninguém.
//
// Por que assim: disparo automático para quem não escreveu primeiro é o principal motivo de
// bloqueio do número no WhatsApp, e o número da HBR carrega todo o histórico de conversa.
// Volume baixo e humano decidindo é o que reduz o risco — não o texto da mensagem.
//
// Agenda de Produção, Fase 5 (P3, 27/10/2026): quando a onda 2 liga (modo_cliente = 'ligado' com 'confirmar' em
// cliente_tipos_ligados), a confirmação com o cliente passa a ser a mensagem-modelo da agenda (D-3 e a véspera, só a quem
// já escreveu para a HBR, na janela e no teto, com a aprovação dos 3 primeiros dias). A R15 sai no mesmo instante, pelo
// mesmo interruptor (o molde da R1/R16): não procura nada e as tarefas vivas se resolvem com o motivo da agenda.
const r15: Rule = {
  id: 'r15',
  label: 'Confirmar agendamento com o cliente (tarefa, não envio)',
  defaultEnabled: true,
  desligadaPelaAgenda: (m) => (r15DesligadaPelaAgenda(m.cliente) ? R15_DESLIGADA : null),
  async find(db) {
    // Janela: OS agendadas para as próximas 48h. A chave inclui o DIA do atendimento, então
    // remarcar para outra data gera uma tarefa nova em vez de reaproveitar a antiga.
    const agora = new Date();
    const limite = new Date(Date.now() + 48 * 3600000);
    const { data } = await db
      .from('service_orders')
      .select('id, service_order_number, scheduled_start_at, client_id, client_confirmed_for, clients(name, phone, whatsapp, opt_out_whatsapp)')
      .eq('status', 'scheduled')
      .gte('scheduled_start_at', agora.toISOString())
      .lte('scheduled_start_at', limite.toISOString())
      .limit(50);
    return (data || [])
      // Sem telefone não há o que confirmar — a tarefa só geraria ruído.
      .filter((o: any) => String(o.clients?.whatsapp || o.clients?.phone || '').replace(/\D/g, '').length >= 10)
      // Já confirmado para ESTA data (respondeu SIM): não há o que pedir.
      .filter((o: any) => !confirmadoParaAData(o.client_confirmed_for, o.scheduled_start_at))
      .map((o: any) => {
        const dia = String(o.scheduled_start_at).slice(0, 10);
        const hora = new Date(o.scheduled_start_at).toLocaleTimeString('pt-BR', {
          hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo',
        });
        return {
          automation_key: keyOf('r15', 'so', o.id, dia),
          title: `Confirmar com ${o.clients?.name || 'o cliente'} a ${o.service_order_number} (${fmtDate(dia)} às ${hora})`,
          priority: 'high' as const,
          assignee: 'admin' as const,
          due_at: dueAt(todayISO()),
          related_entity_type: 'service_order',
          related_entity_id: o.id,
          client_id: o.client_id,
          // Opt-out não cancela a tarefa: confirmar por telefone continua valendo. Só muda
          // o aviso, para você não tentar o WhatsApp e esbarrar no bloqueio.
          notes: o.clients?.opt_out_whatsapp
            ? '⚠️ Este cliente pediu para não receber WhatsApp — confirme por telefone.'
            : 'Use "Pedir confirmação" neste cartão: o cliente recebe a mensagem pedindo SIM e, quando '
              + 'responde, a OS fica confirmada e esta tarefa se fecha sozinha. Nada é enviado sem o seu clique.',
        };
      });
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    const dia = task.automation_key.split(':')[3];
    const { data } = await db.from('service_orders')
      .select('status, scheduled_start_at, client_confirmed_for').eq('id', id).maybeSingle();
    if (!data) return 'OS não existe mais';
    if (data.status !== 'scheduled') return `OS mudou para ${data.status}`;
    if (!data.scheduled_start_at) return 'OS perdeu o agendamento';
    if (String(data.scheduled_start_at).slice(0, 10) !== dia) return 'Atendimento foi remarcado';
    if (confirmadoParaAData(data.client_confirmed_for, data.scheduled_start_at)) return 'Cliente confirmou pelo WhatsApp';
    // Passou a hora: confirmar depois não serve para nada.
    if (new Date(data.scheduled_start_at) < new Date()) return 'Atendimento já aconteceu';
    return null;
  },
};

// R16: OS comprometida com item faltando para executar.
//
// É a rede do aviso que aparece na aprovação do orçamento: quem clica em "Depois" no
// diálogo não perde a pendência, ela volta como tarefa. Uma tarefa POR OS (não por
// item) — cinco peças faltando é uma ida ao fornecedor, não cinco tarefas.
//
// A conta é a necessidade LÍQUIDA, igual à da tela (src/lib/purchase-needs.ts):
// falta = necessário − (físico − reservado) − saldo de OC aberta. Sem descontar a
// reserva, duas OS enxergariam a mesma peça; sem descontar a OC, a tarefa reapareceria
// para algo que já está a caminho.
//
// Rascunho fica fora de propósito: orçamento não aprovado não gera compra. O orçamento APROVADO
// ainda sem sinal entra (23/10/2026, paraComprar): o cliente já disse sim, e a peça que demora é o
// que segura a data. 'open' também entra: é o caminho normal da conversão.
const r16: Rule = {
  id: 'r16',
  label: 'OS comprometida com item a comprar',
  defaultEnabled: true,
  // O título traz o número de itens e o cliente: mudou o que falta, é fato novo. Concluída à mão
  // com a mesma falta (ex.: comprou e não registrou), não volta a cada 15 min.
  voltaSoComFatoNovo: true,
  async find(db) {
    const { data: orders, error } = await db
      .from('service_orders')
      .select('id, service_order_number, status, quote_status, merged_into_id, client_id, clients(name)')
      .or(FILTRO_PARA_COMPRAR)
      .is('merged_into_id', null)
      .limit(80);
    // Erro não pode virar "nenhuma OS precisa comprar" (era engolido até 23/10/2026).
    if (error) throw error;
    // O mesmo predicado do isResolved, sobre o que o banco devolveu.
    const list = ((orders as LinhaComprometida[] | null) || []).filter((o) => paraComprar(o) !== null) as any[];
    if (!list.length) return [];

    const ids = list.map((o: any) => o.id);

    /* A conta vem do banco, não daqui. Até 05/08/2026 esta regra reimplementava em
       Deno a mesma fórmula que já existia em src/lib/purchase-needs.ts e em
       compute_purchase_needs — três cópias que divergem em silêncio, porque quem
       corrige uma não tem como saber das outras.

       Dois ganhos além de eliminar a cópia: passa a enxergar MATERIAL de texto livre
       (a versão em Deno só olhava service_order_parts, então uma OS cujo item
       faltando fosse "Cabo 16mm²" digitado à mão não gerava tarefa), e herda o filtro
       que mantém mão de obra fora — instalação não se compra de fornecedor de peça. */
    const { data: faltas, error: faltasErr } = await db.rpc('count_purchase_shortages', {
      p_so_ids: ids,
    });
    // Erro aqui não pode virar "nenhuma OS precisa comprar": seria indistinguível do
    // caso legítimo e a pendência sumiria calada. Levantar faz o motor logar com o id
    // da regra, que é o que permite achar a causa.
    if (faltasErr) throw faltasErr;

    const shortageByOrder = new Map<string, number>(
      Object.entries((faltas ?? {}) as Record<string, number>),
    );

    return list
      .filter((o: any) => shortageByOrder.has(o.id))
      .map((o: any) => {
        const n = shortageByOrder.get(o.id) || 0;
        return {
          automation_key: keyOf('r16', 'so', o.id),
          // Sem o prefixo "da OS": existem registros comprometidos cujo número ainda é
          // ORÇ- (o status andou por fora da conversão), e "da OS ORÇ-00070" fica errado.
          // O próprio número já diz o que é.
          title: `Comprar ${n} ${n === 1 ? 'item' : 'itens'} — ${o.service_order_number}` +
            (o.clients?.name ? ` (${o.clients.name})` : ''),
          // Aguardando peças é o caso em que a OS já está parada esperando.
          priority: (o.status === 'awaiting_parts' ? 'urgent' : 'high') as 'urgent' | 'high',
          assignee: 'admin' as const,
          due_at: dueAt(todayISO()),
          related_entity_type: 'service_order',
          related_entity_id: o.id,
          client_id: o.client_id,
          notes: 'Abra a OS e use "Resolver" na faixa de compras: dá para cotar com fornecedores ou gerar a ordem de compra.',
        };
      });
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    const { data: so, error: soErr } = await db.from('service_orders')
      .select('status, quote_status, merged_into_id').eq('id', id).maybeSingle();
    if (soErr) throw soErr;
    if (!so) return 'OS não existe mais';
    // O MESMO predicado do find (23/10/2026). Antes daqui saía "resolvida" para todo 'draft': com o
    // orçamento aprovado no find, a tarefa dele nasceria e morreria a cada rodada.
    if (!paraComprar(so)) {
      return so.status === 'draft' || so.merged_into_id ? motivoDoOrcamento(so) : `OS mudou para ${so.status}`;
    }

    // A MESMA conta do find (15/10/2026). Antes daqui saía um recálculo só pelas peças do
    // catálogo: a OS-00104, com 0 peças e 1 material de texto livre faltando, era criada pelo
    // find e fechada aqui na mesma rodada ("OS não tem mais peças lançadas") — 1.142 vezes desde
    // 03/10. A RPC já desconta reserva e OC aberta: gerar a OC resolve (o item está a caminho).
    const { data: faltas, error } = await db.rpc('count_purchase_shortages', { p_so_ids: [id] });
    // Erro não pode virar "resolvida": a tarefa sumiria com a falta de pé. Lançar faz o motor
    // logar e manter a tarefa viva.
    if (error) throw error;
    const aindaFalta = Object.prototype.hasOwnProperty.call((faltas ?? {}) as Record<string, number>, id);
    return aindaFalta ? null : 'Compra resolvida (em estoque ou já pedida)';
  },
  // Fato novo com o título igual (revisão de 15/10/2026): o título só traz a CONTAGEM — "Comprar 1
  // item" de hoje pode ser outro item que o de quando o dono concluiu à mão. Peça ou material da OS
  // lançado ou mudado depois do "já tratei" = a tarefa volta. As mesmas tabelas que a conta do banco
  // lê (get_os_purchase_needs: service_order_parts, service_order_services e, desde a Agenda de Produção
  // Fase 1 (P2), os_material — o que o dono disse da linha: "não chegou, preciso comprar de novo" ou a
  // quantidade que subiu derrubando o "na mão"). Da os_material conta só a linha INFORMADA (fonte dono,
  // fornecedor, nfe ou pix — a mesma lista de aplicar_os_material e de FONTES_INFORMADAS em
  // src/lib/purchase-needs.ts): a que a sincronização cria ou refaz sozinha (fonte nula, estoque ou oc,
  // inclusive a previsão da OC que mudou) é espelho da conta bruta e não é fato novo — sem o filtro, a 1ª
  // passada depois do deploy (todas as linhas nascem com atualizado_em = agora) ressuscitaria toda R16
  // dispensada à mão. Erro = lança: o motor falha a regra na rodada (não recria às cegas nem esconde para
  // sempre).
  async mudouDesde(db, automationKey, desdeISO) {
    const id = entityIdFromKey(automationKey);
    const depois = `created_at.gt.${desdeISO},updated_at.gt.${desdeISO}`;
    const [pecas, materiais, informado] = await Promise.all([
      db.from('service_order_parts').select('id').eq('service_order_id', id).or(depois).limit(1),
      db.from('service_order_services').select('id').eq('service_order_id', id).or(depois).limit(1),
      db.from('os_material').select('id').eq('service_order_id', id).gt('atualizado_em', desdeISO)
        .in('fonte', [...FONTES_INFORMADAS_DO_MATERIAL]).limit(1),
    ]);
    if (pecas.error) throw pecas.error;
    if (materiais.error) throw materiais.error;
    if (informado.error) throw informado.error;
    return (pecas.data?.length ?? 0) > 0 || (materiais.data?.length ?? 0) > 0 || (informado.data?.length ?? 0) > 0;
  },
  // Com a agenda automática ligada o que comprar e até quando sai do plano (o "compre até" da reserva condicionada).
  desligadaPelaAgenda: (m) => (m.proposta === 'ligado' ? 'a agenda automática diz o que comprar e até quando' : null),
};

/** De onde vem o fato de os_material que conta (o mesmo where de aplicar_os_material, 20261024160300). */
export const FONTES_INFORMADAS_DO_MATERIAL = ['dono', 'fornecedor', 'nfe', 'pix'] as const;

/** Data do primeiro envio da cotação — é dela que corre o prazo do fornecedor. */
function primeiroEnvio(q: any): string {
  const datas = (q.quote_request_sends || []).map((s: any) => s.created_at).filter(Boolean).sort();
  return datas[0] || q.created_at;
}

// R18: cotação criada e NUNCA enviada — a pendência é nossa, não do fornecedor.
//
// Descoberto em 03/08/2026: as três cotações de produção (COT-00001 a 00003, de 23/07)
// apareciam como enviadas a dois fornecedores cada e não tinham saído. Nenhuma mensagem
// de WhatsApp citava "COT-", e a fila de envio nunca teve uma linha de cotação. A causa
// era `sent_supplier_ids` ser preenchido na CRIAÇÃO com quem foi apenas selecionado.
//
// Enquanto isso, a R17 abaixo cobrava "fornecedor não respondeu" — de quem nunca foi
// perguntado. Esta regra separa as duas situações: aqui a ação é NOSSA (enviar).
const r18: Rule = {
  id: 'r18',
  label: 'Cotação criada e não enviada',
  defaultEnabled: true,
  async find(db) {
    const { data, error } = await db
      .from('quote_requests')
      .select('id, code, created_at, sent_supplier_ids, service_orders(service_order_number), quote_request_sends(id)')
      .eq('status', 'open')
      .limit(100);
    if (error) throw error;

    return (data || [])
      .filter((q: any) => {
        // Sem fornecedor escolhido não há o que enviar — é rascunho, não pendência.
        if (!(q.sent_supplier_ids || []).length) return false;
        if ((q.quote_request_sends || []).length > 0) return false;
        // Um dia útil de tolerância: criar e enviar em seguida é o fluxo normal.
        return businessDaysBetween(q.created_at, new Date()) >= 1;
      })
      .map((q: any) => {
        const dias = businessDaysBetween(q.created_at, new Date());
        return {
          automation_key: keyOf('r18', 'quote', q.id),
          title: `Enviar a cotação ${q.code} ao fornecedor` +
            (q.service_orders?.service_order_number ? ` (${q.service_orders.service_order_number})` : ''),
          priority: (dias >= 3 ? 'urgent' : 'high') as 'urgent' | 'high',
          assignee: 'admin' as const,
          due_at: dueAt(todayISO()),
          related_entity_type: 'quote_request',
          related_entity_id: q.id,
          notes: `Criada há ${dias} dia(s) útil(eis) com ${(q.sent_supplier_ids || []).length} fornecedor(es) escolhido(s), ` +
            `mas o pedido nunca saiu. Abra a cotação e use "Enviar aos fornecedores".`,
        };
      });
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    const { data } = await db
      .from('quote_requests')
      .select('status, quote_request_sends(id)')
      .eq('id', id)
      .maybeSingle();
    if (!data) return 'Cotação não existe mais';
    if (data.status !== 'open') return `Cotação ${data.status === 'closed' ? 'fechada' : 'cancelada'}`;
    return (data.quote_request_sends || []).length > 0 ? 'Cotação enviada' : null;
  },
};

// R17: cotação enviada sem nenhuma resposta.
//
// A janela praticada no mercado para o fornecedor responder é de 3 a 5 dias úteis, e a
// recomendação é lembrete em vez de caçar no inbox.
//
// Conta em dias ÚTEIS: contar corridos dispararia na segunda-feira por causa do fim de
// semana. A tarefa é interna — nada é enviado ao fornecedor sem você mandar.
//
// EXIGE ENVIO REGISTRADO (03/08/2026). Antes, a regra presumia que toda cotação aberta
// havia sido enviada e cobrava resposta de fornecedor que nunca recebeu nada. O prazo
// agora corre do ENVIO, não da criação — que é o momento em que o fornecedor de fato
// passou a dever resposta. Cotação sem envio é assunto da R18.
const r17: Rule = {
  id: 'r17',
  label: 'Cotação sem resposta do fornecedor',
  defaultEnabled: true,
  async find(db) {
    const { data, error } = await db
      .from('quote_requests')
      .select('id, code, created_at, service_orders(service_order_number), quote_responses(unit_price), quote_request_sends(created_at)')
      .eq('status', 'open')
      .limit(100);

    // Sem isto, um erro de consulta viraria `data = null` e a regra devolveria lista
    // vazia — indistinguível de "não há cotação parada". Levantar faz o motor logar
    // com o id da regra, que é o que permite descobrir a causa sem adivinhação.
    if (error) throw error;

    return (data || [])
      .filter((q: any) => {
        // Alguém já mandou preço? Então não é falta de resposta — é falta de decisão,
        // e isso a Central de Compras mostra sem precisar de tarefa.
        const hasPrice = (q.quote_responses || []).some((r: any) => Number(r.unit_price) > 0);
        if (hasPrice) return false;
        // Sem envio registrado o fornecedor não deve nada: é caso da R18.
        if (!(q.quote_request_sends || []).length) return false;
        return businessDaysBetween(primeiroEnvio(q), new Date()) >= 3;
      })
      .map((q: any) => {
        const dias = businessDaysBetween(primeiroEnvio(q), new Date());
        return {
          automation_key: keyOf('r17', 'quote', q.id),
          title: `Cobrar resposta da cotação ${q.code}` +
            (q.service_orders?.service_order_number ? ` (${q.service_orders.service_order_number})` : ''),
          priority: (dias >= 5 ? 'urgent' : 'high') as 'urgent' | 'high',
          assignee: 'admin' as const,
          due_at: dueAt(todayISO()),
          related_entity_type: 'quote_request',
          related_entity_id: q.id,
            notes: `Enviada há ${dias} dias úteis sem nenhum preço. A janela normal é de 3 a 5 dias úteis.`,
        };
      });
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    const { data } = await db
      .from('quote_requests')
      .select('status, quote_responses(unit_price)')
      .eq('id', id)
      .maybeSingle();
    if (!data) return 'Cotação não existe mais';
    if (data.status !== 'open') return `Cotação ${data.status === 'closed' ? 'fechada' : 'cancelada'}`;
    const hasPrice = (data.quote_responses || []).some((r: any) => Number(r.unit_price) > 0);
    return hasPrice ? 'Fornecedor respondeu' : null;
  },
};

// R19: o orçamento passou da validade — AVISO, nunca rejeição.
//
// Decisão do dono (26/09/2026). Até ali a rotina quote-reminders rejeitava em silêncio, sem
// audit_log, todo orçamento com 7 dias de CRIAÇÃO (app_settings.quote_expiry_days, que não é
// a validade escrita no PDF), inclusive os já aprovados aguardando sinal: foram R$ 133 mil
// em 23-24/09, e o cron foi pausado. Agora o vencimento vira uma tarefa e quem decide é o
// dono: renovar a validade (a tarefa fecha sozinha) ou rejeitar. Esta regra não mexe no
// orçamento e não manda nada ao cliente.
//
// O vencimento é o MESMO "até" que o cliente lê no PDF (ultimoDiaDaValidade, em
// _shared/pdf/documento.ts): validade do próprio orçamento, senão o padrão da empresa,
// contada do dia de Brasília da emissão. Avisar num dia e o documento dizer outro seria o
// erro de antes pelo avesso.
//
// 'awaiting_deposit' (aprovado, aguardando sinal) fica de fora de propósito: o cliente já
// disse sim, e a validade já cumpriu o papel dela. Era exatamente o caso do ORÇ-00095.
//
// A chave leva o último dia da validade: renovar e vencer de novo é uma decisão NOVA e
// precisa de tarefa nova. Com a chave só do orçamento, a dispensa manual da primeira
// silenciaria a segunda por uma semana (isManualDismissal).

/** Status comerciais em que o orçamento ainda espera resposta do cliente. */
const AGUARDANDO_CLIENTE = ['sent', 'awaiting_approval'];

/** Padrão da empresa para a validade. `find` só recebe o db, então a regra lê aqui. */
async function ajustesDeValidade(db: any): Promise<Record<string, unknown>> {
  const { data } = await db.from('app_settings')
    .select('value').eq('key', 'quote_validity_days').maybeSingle();
  return { quote_validity_days: data?.value };
}

// vencimentoDoOrcamento mora em _shared/pdf/documento.ts desde a revisão final (26/09/2026):
// o panorama do assistente, o resumo matinal e a confirmação de envio ao cliente fazem a mesma
// pergunta. Reexportada aqui para quem já a importava desta regra.
export { vencimentoDoOrcamento };

/** Dias de calendário de `de` até `ate` (aaaa-mm-dd), sem fuso. */
const diasEntre = (de: string, ate: string) => {
  const utc = (dia: string) => {
    const [a, m, d] = dia.slice(0, 10).split('-').map(Number);
    return Date.UTC(a, m - 1, d);
  };
  return Math.round((utc(ate) - utc(de)) / 86_400_000);
};

/**
 * A nota da tarefa R19, com a conta da renovação já feita.
 *
 * "Aumente a validade" sozinho induz ao erro: a validade conta da EMISSÃO (D13), não do dia
 * em que se mexe nela. Um orçamento de 3 dias emitido em 24/09 e renovado em 28/09 com
 * "3 dias" continua vencido (vale até 27/09). A nota diz a data de emissão e dá o número
 * certo para valer mais o mesmo prazo a partir de hoje: até 01/10, ponha 7 dias.
 *
 * Três casos, que até 26/09/2026 eram dois (e o terceiro saía com o texto do segundo):
 *
 *   · validade em dias, com emissão legível → a conta pronta, acima;
 *   · DATA FIXA (quote_validity_date) → os dias não mandam (validadeDoOrcamento usa a data), e
 *     NENHUMA tela edita essa coluna (MF-AUD-016: só a conversão de orçamento externo a grava).
 *     A nota antiga mandava "trocar a data" sem dizer onde; agora diz que ela foi gravada fora
 *     da tela e que renovar pede ajuste técnico;
 *   · sem data fixa e sem emissão legível → era chamado de "data fixa", o que não era. Não há
 *     de onde contar os dias, e a nota diz isso.
 */
export function notaDoVencimento(
  orcamento: {
    created_at?: string | null;
    quote_validity_date?: string | null;
    quote_validity_days?: unknown;
    grand_total?: unknown;
  },
  settings: Record<string, unknown>,
  agora: Date = new Date(),
): string {
  const fim = ultimoDiaDaValidade(orcamento, settings);
  const abertura = `Valia até ${fim ? fmtDate(fim) : '—'} (${fmtBRL(Number(orcamento.grand_total))}). ` +
    'O orçamento NÃO foi rejeitado. ';
  const fecho = 'Se o cliente desistiu, marque como rejeitado. Nada foi enviado ao cliente.';

  // A mesma pergunta que ultimoDiaDaValidade faz: data fixa é só a que validadeDoOrcamento
  // aceita como dia de calendário.
  const validade = validadeDoOrcamento(orcamento.quote_validity_days, settings, orcamento.quote_validity_date);
  if (validade.mode === 'date') {
    return abertura + 'A validade deste orçamento é uma DATA FIXA, gravada fora da tela do ' +
      'orçamento: não há campo na tela para trocá-la, e mudar os dias não a altera enquanto ela ' +
      'existir. Para renovar, a data fixa precisa ser trocada ou apagada no banco (ajuste ' +
      'técnico, peça ao suporte do sistema); feito isso, esta tarefa fecha sozinha. ' + fecho;
  }

  const emitidoEm = orcamento.created_at ? new Date(orcamento.created_at) : null;
  if (!emitidoEm || Number.isNaN(emitidoEm.getTime())) {
    return abertura + 'Este orçamento não tem data de emissão legível, e a validade em dias conta ' +
      'da emissão: não dá para calcular até quando ele vale nem quantos dias pôr para renová-lo. ' +
      'Confira o orçamento antes de decidir. ' + fecho;
  }

  const emissao = diaBR(emitidoEm);
  const hoje = diaBR(agora);
  const prazo = validade.days;
  const alvo = somarDiasAoDia(hoje, prazo);
  const dd = (dia: string) => fmtDate(dia).slice(0, 5);
  return abertura +
    'Para renovar, aumente a validade no orçamento (esta tarefa fecha sozinha). ' +
    `A validade conta da emissão (${dd(emissao)}), não de hoje: para valer até ${dd(alvo)} ` +
    `(${prazo} ${prazo === 1 ? 'dia' : 'dias'} a partir de hoje, ${dd(hoje)}), ` +
    `ponha ${diasEntre(emissao, alvo)} dias. ` + fecho;
}

const r19: Rule = {
  id: 'r19',
  label: 'Orçamento vencido: renovar ou rejeitar?',
  defaultEnabled: true,
  async find(db) {
    const [{ data, error }, settings] = await Promise.all([
      db.from('service_orders')
        .select('id, service_order_number, client_id, grand_total, created_at, quote_validity_days, quote_validity_date, clients(name)')
        .eq('status', 'draft')
        .is('converted_to_os_at', null)
        .in('quote_status', AGUARDANDO_CLIENTE)
        .limit(500),
      ajustesDeValidade(db),
    ]);
    // Erro de consulta não pode virar "nenhum orçamento vencido" (ver R17): levantar faz o
    // motor registrar a falha com o id da regra.
    if (error) throw error;
    const agora = new Date();
    return (data || []).flatMap((o: any) => {
      // Um orçamento por vez: um dado que a conta de datas não aceita cala só o aviso DELE.
      // Até 26/09/2026 uma validade de 1e9 dias fazia `toISOString` lançar RangeError, o erro
      // saía do find e o motor perdia a R19 inteira — nenhum orçamento vencido era avisado por
      // causa de um. O teto de 3650 dias (dias-de-validade.ts) fecha esse caso; este catch é a
      // defesa para o próximo. Fica registrado no log com o id, para consertar o dado.
      try {
        const fim = vencimentoDoOrcamento(o, settings, agora);
        if (!fim) return [];
        const cliente = o.clients?.name;
        return [{
          automation_key: keyOf('r19', 'quote', o.id, fim),
          title: `Orçamento ${o.service_order_number} venceu em ${fmtDate(fim).slice(0, 5)} — renovar ou rejeitar?` +
            (cliente ? ` (${cliente})` : ''),
          priority: 'high' as const,
          // A decisão é comercial e é do dono, não de quem digitou o orçamento.
          assignee: 'admin' as const,
          due_at: dueAt(diaBR(agora)),
          related_entity_type: 'service_order',
          related_entity_id: o.id,
          client_id: o.client_id,
          notes: notaDoVencimento(o, settings, agora),
        }];
      } catch (e) {
        console.error(`r19: orçamento ${o?.id ?? '?'} (${o?.service_order_number ?? '?'}) ficou sem aviso:`, e);
        return [];
      }
    });
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    const venceuEm = task.automation_key.split(':')[3];
    const [{ data }, settings] = await Promise.all([
      db.from('service_orders')
        .select('status, quote_status, converted_to_os_at, created_at, quote_validity_days, quote_validity_date')
        .eq('id', id).maybeSingle(),
      ajustesDeValidade(db),
    ]);
    if (!data) return 'Orçamento não existe mais';
    // O mesmo filtro do find, na mesma ordem da R6.
    if (!AGUARDANDO_CLIENTE.includes(data.quote_status)) return `Orçamento mudou para ${data.quote_status}`;
    if (data.converted_to_os_at) return 'Orçamento convertido em OS';
    if (data.status !== 'draft') return `Deixou de ser orçamento (${data.status})`;
    const fim = ultimoDiaDaValidade(data, settings);
    if (!fim) return null;
    if (!vencimentoDoOrcamento(data, settings)) return `Validade renovada até ${fmtDate(fim)}`;
    // Mexeram na validade e ela continua vencida: fecha esta, e o find abre a nova com a
    // data certa no título (senão ficariam duas tarefas vivas para o mesmo orçamento).
    if (fim !== venceuEm) return `Validade alterada (agora até ${fmtDate(fim)})`;
    return null;
  },
};

export const RULES: Rule[] = [r1, r2, r3, r4, r5, r6, r7, r8, r11, r12, r14, r15, r16, r17, r18, r19];

export function ruleById(id: string): Rule | undefined {
  return RULES.find((r) => r.id === id);
}

/** Extrai o id da regra a partir da automation_key ('r4:recv:...' → 'r4'). */
export function ruleIdFromKey(key: string): string {
  return key.split(':')[0] || '';
}

export function isRuleEnabled(settings: Record<string, string>, rule: Rule): boolean {
  const v = settings[`task_rule_${rule.id}_enabled`];
  if (v === undefined || v === null || v === '') return rule.defaultEnabled;
  return v === 'true';
}

/**
 * Agenda de Produção, Fase 2 (P3): por que a agenda desligou esta regra agora (o motivo vai para o notes da tarefa que
 * se resolve), ou null quando a regra vale como sempre. Modos ilegíveis chegam como 'desligado' (agenda-modos.ts): a
 * regra antiga continua.
 */
export function motivoDaAgenda(rule: Rule, modos: ModosDaAgenda = MODOS_DESLIGADOS): string | null {
  return rule.desligadaPelaAgenda?.(modos) ?? null;
}

/** Os candidatos da regra nesta rodada: nenhum quando a agenda faz o trabalho dela; senão o find de sempre. */
export async function candidatosDaRegra(db: any, rule: Rule, modos: ModosDaAgenda = MODOS_DESLIGADOS): Promise<RuleCandidate[]> {
  if (motivoDaAgenda(rule, modos)) return [];
  return await rule.find(db);
}

/**
 * Se a tarefa viva da regra se resolveu: com a agenda fazendo o trabalho dela, sim, com o motivo da agenda (as tarefas
 * antigas não ficam penduradas); senão o isResolved de sempre (que lança no erro de leitura).
 */
export async function resolucaoDaTarefa(
  db: any, rule: Rule, task: { automation_key: string }, modos: ModosDaAgenda = MODOS_DESLIGADOS,
): Promise<string | null> {
  return motivoDaAgenda(rule, modos) ?? await rule.isResolved(db, task);
}

/**
 * Dispensa manual: se um humano concluiu (completed_by preenchido) ou cancelou uma
 * tarefa de automação e a CONDIÇÃO ainda vale, o motor NÃO recria dentro do cooldown —
 * concluir na mão significa "já tratei disso". Auto-resolução (completed_by null) não
 * bloqueia: ali a condição sumiu, então se voltar é uma ocorrência genuinamente nova.
 */
export function isManualDismissal(
  row: { status: string; completed_by: string | null; completed_at: string | null; updated_at: string | null },
  cutoffISO: string,
): boolean {
  const when = row.completed_at || row.updated_at;
  if (!when || when < cutoffISO) return false;
  if (row.status === 'cancelled') return true;
  return row.status === 'done' && row.completed_by !== null;
}

/**
 * Dispensa sem prazo, para regra com `voltaSoComFatoNovo`: o dono concluiu (completed_by
 * preenchido) ou cancelou, e o candidato de agora tem o MESMO título — nada mudou desde que ele
 * disse "já tratei". Título diferente (outro número de itens, outro cliente) é fato novo e
 * recria. Fechada sozinha não conta (a condição tinha sumido; se voltou, é ocorrência nova).
 * `mudouDepois` = a regra viu fato novo desde o fechamento (Rule.mudouDesde): título igual não basta.
 */
export function dispensaSemFatoNovo(
  row: { status: string; completed_by: string | null; title: string | null },
  tituloDoCandidato: string,
  mudouDepois = false,
): boolean {
  const aMao = row.status === 'cancelled' || (row.status === 'done' && row.completed_by !== null);
  return aMao && row.title === tituloDoCandidato && !mudouDepois;
}

export function dismissCooldownDays(settings: Record<string, string>): number {
  const n = parseInt(settings['task_rule_dismiss_cooldown_days'] || '', 10);
  return Number.isFinite(n) && n >= 0 ? n : 7;
}
