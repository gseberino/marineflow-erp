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

export const RULES: Rule[] = [r1, r2, r3, r4, r5, r6, r7, r8, r11, r12];

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
