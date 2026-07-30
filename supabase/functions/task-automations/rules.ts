// Regras do motor de automações da Agenda & Tarefas 2.0.
// Cada regra sabe (a) achar entidades em condição e (b) dizer se a condição
// de uma tarefa viva já se resolveu. Dedupe via automation_key (índice único
// parcial agenda_tasks_automation_key_live). Plano: plans/marineflow-agenda-tarefas.md §6.

export interface RuleCandidate {
  automation_key: string;
  title: string;
  priority: 'low' | 'normal' | 'high' | 'urgent';
  /** 'admin' | 'financial' → resolvido para o primeiro app_user ativo do cargo;
   *  um uuid → usa direto; null → tarefa sem responsável */
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

const r1: Rule = {
  id: 'r1',
  label: 'OS aprovada sem agendamento (24h)',
  defaultEnabled: true,
  async find(db) {
    const { data } = await db
      .from('service_orders')
      .select('id, service_order_number, client_id, clients(name)')
      .eq('status', 'approved')
      .is('scheduled_start_at', null)
      .lt('updated_at', daysAgoISO(1))
      .limit(50);
    return (data || []).map((o: any) => ({
      automation_key: keyOf('r1', 'so', o.id),
      title: `Agendar OS ${o.service_order_number} — ${o.clients?.name || 'sem cliente'}`,
      priority: 'high' as const,
      assignee: 'admin' as const,
      due_at: dueAt(inDaysISO(1)),
      related_entity_type: 'service_order',
      related_entity_id: o.id,
      client_id: o.client_id,
    }));
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    const { data } = await db.from('service_orders')
      .select('status, scheduled_start_at').eq('id', id).maybeSingle();
    if (!data) return 'OS não existe mais';
    if (data.scheduled_start_at) return 'OS foi agendada';
    if (data.status !== 'approved') return `OS mudou para ${data.status}`;
    return null;
  },
};

const r2: Rule = {
  id: 'r2',
  label: 'OS em andamento parada (3 dias)',
  defaultEnabled: true,
  async find(db) {
    const { data } = await db
      .from('service_orders')
      .select('id, service_order_number, client_id, updated_at, clients(name)')
      .eq('status', 'in_progress')
      .lt('updated_at', daysAgoISO(3))
      .limit(50);
    return (data || []).map((o: any) => {
      const dias = Math.floor((Date.now() - new Date(o.updated_at).getTime()) / 86400000);
      return {
        automation_key: keyOf('r2', 'so', o.id),
        title: `Verificar OS ${o.service_order_number} parada há ${dias} dias — ${o.clients?.name || ''}`.trim(),
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
    const { data } = await db.from('service_orders')
      .select('status, updated_at').eq('id', id).maybeSingle();
    if (!data) return 'OS não existe mais';
    if (data.status !== 'in_progress') return `OS mudou para ${data.status}`;
    if (new Date(data.updated_at) > new Date(daysAgoISO(3))) return 'OS voltou a andar';
    return null;
  },
};

async function receivableResolved(db: any, key: string): Promise<string | null> {
  const id = entityIdFromKey(key);
  const { data } = await db.from('receivables')
    .select('status, balance_amount').eq('id', id).maybeSingle();
  if (!data) return 'Recebível não existe mais';
  if (data.status === 'paid') return 'Pagamento registrado';
  if (data.status === 'cancelled') return 'Recebível cancelado';
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
    return (data || []).map((r: any) => ({
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
    return (data || []).map((r: any) => ({
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
    const { data } = await db
      .from('service_orders')
      .select('id, service_order_number, client_id, created_by, clients(name)')
      .in('quote_status', ['sent', 'awaiting_approval'])
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
      .select('quote_status').eq('id', id).maybeSingle();
    if (!data) return 'OS não existe mais';
    if (!['sent', 'awaiting_approval'].includes(data.quote_status)) {
      return `Orçamento mudou para ${data.quote_status}`;
    }
    return null;
  },
};

const r7: Rule = {
  id: 'r7',
  label: 'OC não recebida no prazo',
  defaultEnabled: true,
  async find(db) {
    const { data } = await db
      .from('purchase_orders')
      .select('id, po_number, expected_date, created_at, suppliers(name)')
      .in('status', ['sent', 'partial'])
      .limit(100);
    const now = Date.now();
    return (data || [])
      .filter((p: any) => p.expected_date
        ? p.expected_date < todayISO()
        : new Date(p.created_at).getTime() < now - 7 * 86400000)
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
    const { data } = await db.from('purchase_orders').select('status').eq('id', id).maybeSingle();
    if (!data) return 'OC não existe mais';
    if (['received', 'cancelled'].includes(data.status)) return `OC ${data.status === 'received' ? 'recebida' : 'cancelada'}`;
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

// R14 (Fase 8): plano de manutenção entrou na janela → propor revisão
const r14: Rule = {
  id: 'r14',
  label: 'Plano de manutenção vencendo',
  defaultEnabled: true,
  async find(db) {
    const { data } = await db
      .from('maintenance_plans')
      .select('id, name, interval_months, advance_days, last_service_at, estimated_value, created_at, vessels(id, name, client_id, clients(name))')
      .eq('active', true)
      .limit(200);
    const today = new Date();
    return ((data as any[]) || [])
      .filter((p) => {
        const base = p.last_service_at ? new Date(p.last_service_at) : new Date(p.created_at);
        const due = new Date(base);
        due.setMonth(due.getMonth() + Number(p.interval_months));
        due.setDate(due.getDate() - Number(p.advance_days || 0));
        return due <= today;
      })
      .map((p) => ({
        automation_key: keyOf('r14', 'plan', p.id, p.last_service_at || 'first'),
        title: `Propor revisão: ${p.name} — ${p.vessels?.name || 'embarcação'} (${p.vessels?.clients?.name || 'cliente'})` +
          (p.estimated_value ? ` · ~${fmtBRL(Number(p.estimated_value))}` : ''),
        priority: 'high' as const,
        assignee: 'admin' as const,
        due_at: dueAt(todayISO()),
        related_entity_type: 'vessel',
        related_entity_id: p.vessels?.id || null,
        client_id: p.vessels?.client_id || null,
      }));
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    const bucket = task.automation_key.split(':')[3];
    const { data } = await db.from('maintenance_plans')
      .select('active, last_service_at').eq('id', id).maybeSingle();
    if (!data) return 'Plano não existe mais';
    if (!data.active) return 'Plano desativado';
    // last_service_at mudou desde a criação da tarefa = serviço registrado
    if ((data.last_service_at || 'first') !== bucket) return 'Serviço registrado no plano';
    return null;
  },
};

// R15: a alternativa ESCOLHIDA no lugar do envio automático ao cliente (R9).
// Em vez de o sistema mandar WhatsApp sozinho na véspera, ele cria uma TAREFA sua:
// "confirmar com fulano o atendimento de amanhã". Você abre a agenda, vê a lista do dia e
// dispara pelo botão, um a um. Nada sai daqui — esta regra não envia nada a ninguém.
//
// Por que assim: disparo automático para quem não escreveu primeiro é o principal motivo de
// bloqueio do número no WhatsApp, e o número da HBR carrega todo o histórico de conversa.
// Volume baixo e humano decidindo é o que reduz o risco — não o texto da mensagem.
const r15: Rule = {
  id: 'r15',
  label: 'Confirmar agendamento com o cliente (tarefa, não envio)',
  defaultEnabled: true,
  async find(db) {
    // Janela: OS agendadas para as próximas 48h. A chave inclui o DIA do atendimento, então
    // remarcar para outra data gera uma tarefa nova em vez de reaproveitar a antiga.
    const agora = new Date();
    const limite = new Date(Date.now() + 48 * 3600000);
    const { data } = await db
      .from('service_orders')
      .select('id, service_order_number, scheduled_start_at, client_id, clients(name, phone, whatsapp, opt_out_whatsapp)')
      .eq('status', 'scheduled')
      .gte('scheduled_start_at', agora.toISOString())
      .lte('scheduled_start_at', limite.toISOString())
      .limit(50);
    return (data || [])
      // Sem telefone não há o que confirmar — a tarefa só geraria ruído.
      .filter((o: any) => String(o.clients?.whatsapp || o.clients?.phone || '').replace(/\D/g, '').length >= 10)
      .map((o: any) => {
        const dia = String(o.scheduled_start_at).slice(0, 10);
        const hora = new Date(o.scheduled_start_at).toLocaleTimeString('pt-BR', {
          hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo',
        });
        return {
          automation_key: keyOf('r15', 'so', o.id, dia),
          title: `Confirmar com ${o.clients?.name || 'o cliente'} a OS ${o.service_order_number} (${fmtDate(dia)} às ${hora})`,
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
            : 'Use o botão de confirmação na Agenda para mandar a mensagem — nada é enviado sozinho.',
        };
      });
  },
  async isResolved(db, task) {
    const id = entityIdFromKey(task.automation_key);
    const dia = task.automation_key.split(':')[3];
    const { data } = await db.from('service_orders')
      .select('status, scheduled_start_at').eq('id', id).maybeSingle();
    if (!data) return 'OS não existe mais';
    if (data.status !== 'scheduled') return `OS mudou para ${data.status}`;
    if (!data.scheduled_start_at) return 'OS perdeu o agendamento';
    if (String(data.scheduled_start_at).slice(0, 10) !== dia) return 'Atendimento foi remarcado';
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
// Rascunho fica fora de propósito: orçamento não aprovado não gera compra.
const r16: Rule = {
  id: 'r16',
  label: 'OS comprometida com item a comprar',
  defaultEnabled: true,
  async find(db) {
    const { data: orders } = await db
      .from('service_orders')
      .select('id, service_order_number, status, client_id, clients(name)')
      .in('status', ['approved', 'scheduled', 'in_progress', 'awaiting_parts'])
      .limit(80);
    const list = orders || [];
    if (!list.length) return [];

    const ids = list.map((o: any) => o.id);
    const [{ data: parts }, { data: avail }, { data: poItems }] = await Promise.all([
      db.from('service_order_parts')
        .select('service_order_id, product_id, quantity')
        .in('service_order_id', ids),
      db.from('product_availability').select('id, stock_quantity, reserved_quantity'),
      db.from('purchase_order_items')
        .select('product_id, quantity, received_qty, purchase_orders!inner(status)')
        .in('purchase_orders.status', ['draft', 'sent', 'partial']),
    ]);

    const availById = new Map<string, number>();
    for (const a of avail || []) {
      availById.set(a.id, Number(a.stock_quantity || 0) - Number(a.reserved_quantity || 0));
    }
    const onOrderById = new Map<string, number>();
    for (const i of poItems || []) {
      const pending = Math.max(0, Number(i.quantity || 0) - Number(i.received_qty || 0));
      onOrderById.set(i.product_id, (onOrderById.get(i.product_id) || 0) + pending);
    }

    const shortageByOrder = new Map<string, number>();
    for (const p of parts || []) {
      const available = Math.max(0, availById.get(p.product_id) || 0);
      const onOrder = onOrderById.get(p.product_id) || 0;
      if (Math.max(0, Number(p.quantity || 0) - available - onOrder) > 0) {
        shortageByOrder.set(p.service_order_id, (shortageByOrder.get(p.service_order_id) || 0) + 1);
      }
    }

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
    const { data: so } = await db.from('service_orders').select('status').eq('id', id).maybeSingle();
    if (!so) return 'OS não existe mais';
    if (['completed', 'invoiced', 'cancelled', 'draft'].includes(so.status)) {
      return `OS mudou para ${so.status}`;
    }

    const { data: parts } = await db
      .from('service_order_parts')
      .select('product_id, quantity')
      .eq('service_order_id', id);
    if (!parts?.length) return 'OS não tem mais peças lançadas';

    const productIds = parts.map((p: any) => p.product_id);
    const [{ data: avail }, { data: poItems }] = await Promise.all([
      db.from('product_availability')
        .select('id, stock_quantity, reserved_quantity')
        .in('id', productIds),
      db.from('purchase_order_items')
        .select('product_id, quantity, received_qty, purchase_orders!inner(status)')
        .in('product_id', productIds)
        .in('purchase_orders.status', ['draft', 'sent', 'partial']),
    ]);

    const availById = new Map<string, number>();
    for (const a of avail || []) {
      availById.set(a.id, Number(a.stock_quantity || 0) - Number(a.reserved_quantity || 0));
    }
    const onOrderById = new Map<string, number>();
    for (const i of poItems || []) {
      const pending = Math.max(0, Number(i.quantity || 0) - Number(i.received_qty || 0));
      onOrderById.set(i.product_id, (onOrderById.get(i.product_id) || 0) + pending);
    }

    const stillShort = parts.some((p: any) => {
      const available = Math.max(0, availById.get(p.product_id) || 0);
      const onOrder = onOrderById.get(p.product_id) || 0;
      return Math.max(0, Number(p.quantity || 0) - available - onOrder) > 0;
    });

    // Gerar a OC já resolve: o item passa a contar como "a caminho".
    return stillShort ? null : 'Compra resolvida (em estoque ou já pedida)';
  },
};

// R17: cotação enviada sem nenhuma resposta.
//
// A janela praticada no mercado para o fornecedor responder é de 3 a 5 dias úteis, e a
// recomendação é lembrete em vez de caçar no inbox. Este é o caso que de fato aconteceu
// aqui: 3 cotações enviadas em 23/07 e nenhuma resposta registrada até 29/07.
//
// Conta em dias ÚTEIS: contar corridos dispararia na segunda-feira por causa do fim de
// semana. A tarefa é interna — nada é enviado ao fornecedor sem você mandar.
const r17: Rule = {
  id: 'r17',
  label: 'Cotação sem resposta do fornecedor',
  defaultEnabled: true,
  async find(db) {
    const { data, error } = await db
      .from('quote_requests')
      .select('id, code, created_at, service_orders(service_order_number), quote_responses(unit_price)')
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
        return businessDaysBetween(q.created_at, new Date()) >= 3;
      })
      .map((q: any) => {
        const dias = businessDaysBetween(q.created_at, new Date());
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

export const RULES: Rule[] = [r1, r2, r3, r4, r5, r6, r7, r8, r11, r12, r14, r15, r16, r17];

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

export function dismissCooldownDays(settings: Record<string, string>): number {
  const n = parseInt(settings['task_rule_dismiss_cooldown_days'] || '', 10);
  return Number.isFinite(n) && n >= 0 ? n : 7;
}
