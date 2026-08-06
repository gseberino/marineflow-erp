import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { BankTransaction } from '@/lib/bank-parser';
import { writeAuditLog } from '@/hooks/use-audit-log';
import { cancelPaymentCascade } from '@/lib/cascade-updates';

export function useReceivables() {
  return useQuery({
    queryKey: ['receivables'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('receivables')
        .select('*, clients!receivables_client_id_fkey(id,name,whatsapp,phone), service_orders!receivables_service_order_id_fkey(id,service_order_number,share_token)')
        .order('due_date', { ascending: true });
      if (error) throw error;
      return data;
    },
  });
}

export function usePayables() {
  return useQuery({
    queryKey: ['payables'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('payables')
        .select('*, suppliers!payables_supplier_id_fkey(name), service_orders!payables_linked_service_order_id_fkey(service_order_number), service_order_expenses!service_order_expenses_linked_payable_id_fkey(receipt_url)')
        .order('due_date', { ascending: true });
      if (error) throw error;
      return data;
    },
  });
}

export function useCreateReceivable() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (rec: {
      client_id: string; description: string; issue_date: string;
      due_date: string; amount: number; currency?: string;
      service_order_id?: string; notes?: string;
      cost_center_id?: string; sub_category?: string;
    }) => {
      const { data, error } = await supabase.from('receivables').insert({
        ...rec, balance_amount: rec.amount, paid_amount: 0, status: 'pending',
      }).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['receivables'] }),
  });
}

export function useCreatePayable() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (p: {
      description: string; issue_date: string; due_date: string;
      amount: number; currency?: string; expense_category?: string;
      supplier_id?: string; name?: string;
      linked_service_order_id?: string; notes?: string;
      origin?: string; bank_transaction_id?: string;
      cost_center_id?: string; sub_category?: string;
    }) => {
      const { data, error } = await supabase.from('payables').insert({
        ...p, balance_amount: p.amount, paid_amount: 0, status: 'pending',
      } as any).select().single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['payables'] }),
  });
}

export function usePayments(receivableId?: string, payableId?: string) {
  return useQuery({
    queryKey: ['payments', receivableId, payableId],
    queryFn: async () => {
      let q = supabase.from('payments').select('*').order('payment_date', { ascending: false });
      if (receivableId) q = q.eq('receivable_id', receivableId);
      if (payableId) q = q.eq('payable_id', payableId);
      const { data, error } = await q;
      if (error) throw error;
      return data;
    },
    enabled: !!(receivableId || payableId),
  });
}

export function useRegisterPayment() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      receivable_id?: string; payable_id?: string;
      payment_date: string; amount: number;
      payment_method: string; installments?: number;
      card_fee_percent?: number; net_amount?: number; notes?: string;
    }) => {
      // Usa exclusivamente a RPC atômica — o fallback manual foi removido pois
      // bypassava a verificação de role adicionada em register_payment_and_update_balance.
      // O RPC está deployado desde 20260508 e protegido desde 20260629.
      const { data: rpcData, error: rpcErr } = await supabase.rpc('register_payment_and_update_balance', {
        p_receivable_id:    input.receivable_id || null,
        p_payable_id:       input.payable_id || null,
        p_amount:           input.amount,
        p_payment_date:     input.payment_date.split('T')[0], // garante formato DATE
        p_payment_method:   input.payment_method,
        p_installments:     input.installments || 1,
        p_card_fee_percent: input.card_fee_percent || 0,
        p_net_amount:       input.net_amount || input.amount,
        p_notes:            input.notes || null,
      });

      if (rpcErr) throw rpcErr;
      if (!(rpcData as any)?.payment_id) throw new Error('RPC não retornou payment_id');

      const paymentId = (rpcData as any).payment_id;

      await writeAuditLog({
        table_name: 'payments',
        record_id: paymentId,
        action: 'update',
        new_value: { amount: input.amount, payment_method: input.payment_method },
      });

      return { id: paymentId };
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
      qc.invalidateQueries({ queryKey: ['payments'] });
      qc.invalidateQueries({ queryKey: ['financial-summary'] });
      // Invalida service-orders para refletir o payment_status atualizado pelo trigger
      qc.invalidateQueries({ queryKey: ['service-orders'] });
    },
  });
}

export function useCancelPayment() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, reason }: { id: string; reason: string }) => {
      await cancelPaymentCascade(id, reason);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['payments'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
      qc.invalidateQueries({ queryKey: ['financial-summary'] });
      // Invalida service-orders para refletir o payment_status revertido pelo trigger
      qc.invalidateQueries({ queryKey: ['service-orders'] });
    },
  });
}

export function useFinancialSummary() {
  return useQuery({
    queryKey: ['financial-summary'],
    queryFn: async () => {
      const today = new Date().toISOString().split('T')[0];
      const firstOfMonth = `${today.substring(0, 7)}-01`;

      const [recRes, recOverdue, payRes, payOverdue, collectedRes, paidRes] = await Promise.all([
        supabase.from('receivables').select('balance_amount').not('status', 'in', '("paid","cancelled")'),
        supabase.from('receivables').select('balance_amount').not('status', 'in', '("paid","cancelled")').lt('due_date', today),
        supabase.from('payables').select('balance_amount').not('status', 'in', '("paid","cancelled")'),
        supabase.from('payables').select('balance_amount').not('status', 'in', '("paid","cancelled")').lt('due_date', today),
        supabase.from('payments').select('amount').not('receivable_id', 'is', null).eq('status', 'confirmed').gte('payment_date', firstOfMonth),
        supabase.from('payments').select('amount').not('payable_id', 'is', null).eq('status', 'confirmed').gte('payment_date', firstOfMonth),
      ]);

      const sum = (rows: any[] | null) => (rows || []).reduce((s, r) => s + Number(r.balance_amount || r.amount || 0), 0);

      return {
        total_receivable: sum(recRes.data),
        overdue_receivable: sum(recOverdue.data),
        total_payable: sum(payRes.data),
        overdue_payable: sum(payOverdue.data),
        collected_this_month: sum(collectedRes.data),
        paid_this_month: sum(paidRes.data),
      };
    },
  });
}

/**
 * DSO / prazo médio de recebimento: quantos dias, em média, leva para receber — medido sobre os
 * pagamentos REALIZADOS nos últimos `days` dias (emissão → pagamento), ponderado pelo valor.
 * Exclui SINAIS (is_deposit), que são pagos na hora e puxariam o número para ~0, mascarando o
 * prazo real de recebimento do saldo/faturas. É o termômetro de caixa (quanto menor, melhor).
 */
export function useReceivablesDSO(days: number = 90) {
  return useQuery({
    queryKey: ['receivables-dso', days],
    queryFn: async () => {
      const since = new Date(Date.now() - days * 86400000).toISOString().slice(0, 10);
      const { data, error } = await supabase
        .from('payments')
        .select('amount, payment_date, receivable:receivables!inner(issue_date, is_deposit)')
        .eq('status', 'confirmed')
        .gte('payment_date', since);
      if (error) throw error;

      let weightSum = 0;
      let weightedDays = 0;
      let count = 0;
      for (const p of (data as any[]) || []) {
        const rec = p.receivable;
        if (!rec || rec.is_deposit || !rec.issue_date || !p.payment_date) continue;
        const d = Math.max(0, Math.round(
          (new Date(p.payment_date).getTime() - new Date(rec.issue_date).getTime()) / 86400000,
        ));
        const amt = Number(p.amount || 0);
        if (amt <= 0) continue;
        weightSum += amt;
        weightedDays += amt * d;
        count += 1;
      }
      return {
        dso: weightSum > 0 ? Math.round(weightedDays / weightSum) : null,
        count,
        periodDays: days,
      };
    },
    staleTime: 5 * 60 * 1000,
  });
}

export interface ForecastWeek {
  /** Segunda-feira da semana, ISO. */
  inicio: string;
  rotulo: string;
  entradas: number;
  saidas: number;
  liquido: number;
  /** Soma dos líquidos até esta semana. */
  acumulado: number;
  /** Contas vencidas arrastadas para a primeira semana. */
  contemAtrasados: boolean;
}

/**
 * Projeção de caixa das próximas semanas a partir do que está programado.
 *
 * Deliberadamente NÃO projeta saldo bancário absoluto: o sistema não conhece o saldo real
 * da conta (não há integração bancária ativa), e exibir um "saldo previsto" a partir de um
 * saldo inicial desconhecido seria inventar número — justamente o tipo de erro que quebra
 * a confiança num módulo financeiro. O que ela responde é o que dá para responder com
 * honestidade: quanto entra, quanto sai e qual o resultado líquido de cada semana.
 *
 * Contas já vencidas e ainda em aberto entram na primeira semana, porque é quando elas
 * pressionam o caixa de verdade.
 */
export function useCashForecast(semanas: number = 8) {
  return useQuery({
    queryKey: ['cash-forecast', semanas],
    queryFn: async (): Promise<{ weeks: ForecastWeek[]; totalEntradas: number; totalSaidas: number; semanasNegativas: number }> => {
      const hoje = new Date();
      hoje.setHours(0, 0, 0, 0);
      const limite = new Date(hoje);
      limite.setDate(limite.getDate() + semanas * 7);
      const limiteISO = limite.toISOString().split('T')[0];

      const [recRes, payRes] = await Promise.all([
        supabase.from('receivables')
          .select('balance_amount, due_date')
          .not('status', 'in', '("paid","cancelled")')
          .lte('due_date', limiteISO),
        supabase.from('payables')
          .select('balance_amount, due_date')
          .not('status', 'in', '("paid","cancelled")')
          .lte('due_date', limiteISO),
      ]);

      // Segunda-feira da semana corrente é a âncora das faixas.
      const inicioSemana = (d: Date) => {
        const c = new Date(d);
        const diaDaSemana = (c.getDay() + 6) % 7; // 0 = segunda
        c.setDate(c.getDate() - diaDaSemana);
        c.setHours(0, 0, 0, 0);
        return c;
      };

      const primeira = inicioSemana(hoje);
      const buckets: ForecastWeek[] = [];
      for (let i = 0; i < semanas; i++) {
        const inicio = new Date(primeira);
        inicio.setDate(inicio.getDate() + i * 7);
        const fim = new Date(inicio);
        fim.setDate(fim.getDate() + 6);
        buckets.push({
          inicio: inicio.toISOString().split('T')[0],
          rotulo: i === 0 ? 'Esta semana' : i === 1 ? 'Próxima semana'
            : `${String(inicio.getDate()).padStart(2, '0')}/${String(inicio.getMonth() + 1).padStart(2, '0')} a ${String(fim.getDate()).padStart(2, '0')}/${String(fim.getMonth() + 1).padStart(2, '0')}`,
          entradas: 0, saidas: 0, liquido: 0, acumulado: 0, contemAtrasados: false,
        });
      }

      const indiceDe = (dueDate: string) => {
        const d = new Date(`${dueDate}T12:00:00`);
        if (d < hoje) return 0; // vencido pressiona o caixa agora
        const diff = Math.floor((inicioSemana(d).getTime() - primeira.getTime()) / (7 * 86400000));
        return diff >= 0 && diff < buckets.length ? diff : -1;
      };

      for (const r of (recRes.data || [])) {
        const i = indiceDe(r.due_date as string);
        if (i < 0) continue;
        buckets[i].entradas += Number(r.balance_amount || 0);
        if (i === 0 && new Date(`${r.due_date}T12:00:00`) < hoje) buckets[0].contemAtrasados = true;
      }
      for (const p of (payRes.data || [])) {
        const i = indiceDe(p.due_date as string);
        if (i < 0) continue;
        buckets[i].saidas += Number(p.balance_amount || 0);
        if (i === 0 && new Date(`${p.due_date}T12:00:00`) < hoje) buckets[0].contemAtrasados = true;
      }

      let acumulado = 0;
      for (const b of buckets) {
        b.liquido = Number((b.entradas - b.saidas).toFixed(2));
        acumulado += b.liquido;
        b.acumulado = Number(acumulado.toFixed(2));
      }

      return {
        weeks: buckets,
        totalEntradas: buckets.reduce((s, b) => s + b.entradas, 0),
        totalSaidas: buckets.reduce((s, b) => s + b.saidas, 0),
        semanasNegativas: buckets.filter(b => b.liquido < 0).length,
      };
    },
  });
}

/**
 * Contas a pagar que parecem lançamento repetido: mesmo fornecedor, mesmo valor e
 * vencimento próximo. Pagar duas vezes o mesmo boleto é um erro caro e silencioso.
 */
export function useDuplicatePayables() {
  return useQuery({
    queryKey: ['duplicate-payables'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('payables')
        .select('id, description, amount, due_date, supplier_id, suppliers(name)')
        .not('status', 'in', '("paid","cancelled")')
        .order('due_date');
      if (error) throw error;

      const grupos = new Map<string, any[]>();
      for (const p of data || []) {
        const chave = `${p.supplier_id ?? 'sem-fornecedor'}|${Number(p.amount).toFixed(2)}`;
        grupos.set(chave, [...(grupos.get(chave) || []), p]);
      }

      return Array.from(grupos.values())
        .filter(g => g.length > 1)
        .map(g => ({
          fornecedor: (g[0] as any).suppliers?.name ?? 'Sem fornecedor',
          valor: Number(g[0].amount),
          contas: g,
          // Vencimentos no mesmo mês reforçam a suspeita de duplicidade; espalhados pelo
          // ano são provavelmente parcelas legítimas de um contrato.
          mesmoMes: new Set(g.map((p: any) => String(p.due_date).slice(0, 7))).size === 1,
        }))
        .filter(g => g.mesmoMes);
    },
  });
}

export function useCashFlow(months: number = 6) {
  return useQuery({
    queryKey: ['cash-flow', months],
    queryFn: async () => {
      const now = new Date();
      const start = new Date(now.getFullYear(), now.getMonth() - months + 1, 1);
      const startStr = start.toISOString().split('T')[0];

      const { data } = await supabase
        .from('payments').select('payment_date, amount, receivable_id, payable_id')
        .eq('status', 'confirmed')
        .gte('payment_date', startStr).order('payment_date');

      const monthMap: Record<string, { inflow: number; outflow: number }> = {};
      for (let i = 0; i < months; i++) {
        const d = new Date(now.getFullYear(), now.getMonth() - months + 1 + i, 1);
        const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
        monthMap[key] = { inflow: 0, outflow: 0 };
      }

      for (const p of data || []) {
        const key = p.payment_date.substring(0, 7);
        if (!monthMap[key]) continue;
        if (p.receivable_id) monthMap[key].inflow += Number(p.amount);
        else monthMap[key].outflow += Number(p.amount);
      }

      const monthNames = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
      return Object.entries(monthMap).map(([key, v]) => {
        const [y, m] = key.split('-');
        return {
          month: `${monthNames[parseInt(m) - 1]}/${y.slice(2)}`,
          inflow: v.inflow,
          outflow: v.outflow,
          net: v.inflow - v.outflow,
        };
      });
    },
  });
}

export function useBankTransactions() {
  return useQuery({
    queryKey: ['bank-transactions'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('bank_transactions')
        .select('*, service_orders!bank_transactions_reconciled_service_order_id_fkey(service_order_number)')
        .order('transaction_date', { ascending: false });
      if (error) throw error;
      return data;
    },
  });
}

export function useUnignoreBankTransaction() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      // Limpa também o rastro da ignorada: uma transação de volta na fila que continuasse
      // com motivo gravado apareceria nos dois lugares ao mesmo tempo.
      const { error } = await supabase.from('bank_transactions')
        .update({
          reconciled: false, reconciled_payment_id: null, reconciled_service_order_id: null,
          dismissed_reason: null, dismissed_kind: null, dismissed_at: null, dismissed_by: null,
        } as never)
        .eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
      qc.invalidateQueries({ queryKey: ['bank-transactions-ignoradas'] });
    },
  });
}

export type ImportResult = { imported: number; skipped: number };

/**
 * Importa transações de extrato ignorando as que já entraram antes.
 *
 * O identificador do banco (FITID no OFX) é único e estável por conta, então serve
 * de chave de deduplicação: sem isso, reimportar um período sobreposto — que é o
 * uso normal, já que ninguém acerta o corte exato do extrato — duplicaria todo o
 * histórico e inflaria o financeiro. Transações sem identificador (CSV que não traz
 * um) não têm como ser comparadas e entram sempre.
 */
export function useImportBankTransactions() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (args: { transactions: BankTransaction[]; source_type?: 'bank' | 'credit_card' }): Promise<ImportResult> => {
      const source_type = args.source_type || 'bank';
      const refs = args.transactions.map(t => t.bank_ref_id).filter((r): r is string => !!r);

      const existing = new Set<string>();
      // Fatiado porque a consulta vai na URL: um extrato anual passaria do limite.
      for (let i = 0; i < refs.length; i += 200) {
        const chunk = refs.slice(i, i + 200);
        const { data, error } = await supabase
          .from('bank_transactions')
          .select('bank_ref_id')
          .eq('source_type', source_type)
          .in('bank_ref_id', chunk);
        if (error) throw error;
        for (const row of data || []) if (row.bank_ref_id) existing.add(row.bank_ref_id);
      }

      const novas = args.transactions.filter(t => !t.bank_ref_id || !existing.has(t.bank_ref_id));
      const skipped = args.transactions.length - novas.length;
      if (novas.length === 0) return { imported: 0, skipped };

      const batch_id = crypto.randomUUID();
      const rows = novas.map(t => ({
        transaction_date: t.transaction_date,
        description: t.description,
        amount: t.amount,
        transaction_type: t.transaction_type,
        bank_ref_id: t.bank_ref_id ?? null,
        pix_end_to_end_id: t.pix_end_to_end_id ?? null,
        counterparty_name: t.counterparty_name ?? null,
        counterparty_document: t.counterparty_document ?? null,
        import_batch_id: batch_id,
        reconciled: false,
        source_type,
      }));

      const { data, error } = await supabase.from('bank_transactions').insert(rows).select('id');
      if (error) throw error;
      return { imported: data?.length ?? 0, skipped };
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['bank-transactions'] }),
  });
}

export function useReconcile() {
  const qc = useQueryClient();
  const registerPayment = useRegisterPayment();

  return useMutation({
    mutationFn: async (input: {
      bankTransactionId: string; receivableId?: string; payableId?: string;
      amount: number; paymentMethod?: string;
    }) => {
      // Validate amount against the open balance before registering
      if (input.receivableId || input.payableId) {
        const table = input.receivableId ? 'receivables' : 'payables';
        const parentId = (input.receivableId || input.payableId)!;
        const { data: parent } = await supabase.from(table).select('balance_amount').eq('id', parentId).single();
        const openBalance = Number(parent?.balance_amount || 0);
        if (input.amount > openBalance + 0.005) {
          throw new Error(`Valor R$ ${input.amount.toFixed(2)} excede o saldo em aberto de R$ ${openBalance.toFixed(2)}`);
        }
      }

      const payment = await registerPayment.mutateAsync({
        receivable_id: input.receivableId,
        payable_id: input.payableId,
        payment_date: new Date().toISOString().split('T')[0],
        amount: input.amount,
        payment_method: input.paymentMethod || 'bank_transfer',
      });

      await supabase.from('bank_transactions').update({
        reconciled: true, reconciled_payment_id: payment.id,
      }).eq('id', input.bankTransactionId);

      return payment;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['payables'] });
    },
  });
}

/**
 * Tira uma transação da fila, deixando rastro.
 *
 * Gravava só `reconciled: true` — sem motivo, sem tipo, sem data. A linha virava
 * indistinguível de uma conciliada de verdade e nem aparecia no livro das ignoradas, que
 * filtra por motivo. Era o mesmo sumiço que fez 380 transações virarem desconfiança, só
 * que pela porta da frente.
 */
export function useDismissBankTransaction() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: string | { id: string; reason?: string }) => {
      const id = typeof v === 'string' ? v : v.id;
      const motivo = (typeof v === 'string' ? '' : v.reason)?.trim()
        || 'Tirada da fila pelo gestor, sem motivo informado';
      const { error } = await supabase.from('bank_transactions').update({
        reconciled: true,
        dismissed_reason: motivo,
        dismissed_kind: 'manual',
        dismissed_at: new Date().toISOString(),
      } as never).eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
      qc.invalidateQueries({ queryKey: ['bank-transactions-ignoradas'] });
    },
  });
}

// ─── Aging Report ──────────────────────────────────────────────────────────────

export interface AgingBucket {
  client_id: string;
  client_name: string;
  future: number;     // A vencer (due_date > hoje)
  days_1_30: number;  // 1–30 dias em atraso
  days_31_60: number;
  days_61_90: number;
  over_90: number;
  total: number;
}

export interface AgingReportData {
  buckets: AgingBucket[];
  totals: { future: number; days_1_30: number; days_31_60: number; days_61_90: number; over_90: number; total: number };
  generated_at: string;
}

export function useAgingReport() {
  return useQuery({
    queryKey: ['aging-report'],
    queryFn: async (): Promise<AgingReportData> => {
      const today = new Date();
      today.setHours(0, 0, 0, 0);

      const { data, error } = await supabase
        .from('receivables')
        .select('id, amount, balance_amount, due_date, status, client_id, clients!receivables_client_id_fkey(id, name)')
        .in('status', ['pending', 'partially_paid', 'overdue'])
        .gt('balance_amount', 0);
      if (error) throw error;

      const map = new Map<string, AgingBucket>();
      for (const r of data || []) {
        const client = (r as any).clients;
        if (!client) continue;
        const clientId = client.id as string;
        if (!map.has(clientId)) {
          map.set(clientId, {
            client_id: clientId,
            client_name: client.name as string,
            future: 0, days_1_30: 0, days_31_60: 0, days_61_90: 0, over_90: 0, total: 0,
          });
        }
        const bucket = map.get(clientId)!;
        const balance = Number(r.balance_amount || 0);
        // Normaliza due_date para meia-noite local, evitando drift de timezone
        const due = new Date(r.due_date + 'T00:00:00');
        const diffDays = Math.round((today.getTime() - due.getTime()) / 86_400_000);

        bucket.total += balance;
        if (diffDays < 0)         bucket.future     += balance;  // A vencer
        else if (diffDays <= 30)  bucket.days_1_30  += balance;  // 1–30d em atraso
        else if (diffDays <= 60)  bucket.days_31_60 += balance;
        else if (diffDays <= 90)  bucket.days_61_90 += balance;
        else                      bucket.over_90    += balance;
      }

      const buckets = Array.from(map.values()).sort((a, b) => b.over_90 - a.over_90);
      const totals = buckets.reduce(
        (acc, b) => ({
          future:     acc.future     + b.future,
          days_1_30:  acc.days_1_30  + b.days_1_30,
          days_31_60: acc.days_31_60 + b.days_31_60,
          days_61_90: acc.days_61_90 + b.days_61_90,
          over_90:    acc.over_90    + b.over_90,
          total:      acc.total      + b.total,
        }),
        { future: 0, days_1_30: 0, days_31_60: 0, days_61_90: 0, over_90: 0, total: 0 },
      );

      return { buckets, totals, generated_at: new Date().toISOString() };
    },
    staleTime: 5 * 60 * 1000,
  });
}

// ─── Hooks por OS ─────────────────────────────────────────────────────────────

/** Todos os recebíveis não-cancelados de uma OS específica. */
export function useReceivablesByServiceOrder(serviceOrderId?: string) {
  return useQuery({
    queryKey: ['receivables', 'by-so', serviceOrderId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('receivables')
        .select('id, amount, paid_amount, balance_amount, status, due_date, description, is_deposit')
        .eq('service_order_id', serviceOrderId!)
        .neq('status', 'cancelled')
        .order('due_date', { ascending: true });
      if (error) throw error;
      return data ?? [];
    },
    enabled: !!serviceOrderId,
  });
}

/** Histórico de pagamentos confirmados de uma OS (via seus recebíveis). */
export function usePaymentsByServiceOrder(serviceOrderId?: string) {
  return useQuery({
    queryKey: ['payments', 'by-so', serviceOrderId],
    queryFn: async () => {
      // Busca IDs dos recebíveis da OS
      const { data: recs, error: recErr } = await supabase
        .from('receivables')
        .select('id')
        .eq('service_order_id', serviceOrderId!)
        .neq('status', 'cancelled');
      if (recErr) throw recErr;
      if (!recs || recs.length === 0) return [];

      const recIds = recs.map((r) => r.id);
      const { data: payments, error: payErr } = await supabase
        .from('payments')
        .select('id, payment_date, amount, payment_method, installments, net_amount, notes, status')
        .in('receivable_id', recIds)
        .eq('status', 'confirmed')
        .order('payment_date', { ascending: false });
      if (payErr) throw payErr;
      return payments ?? [];
    },
    enabled: !!serviceOrderId,
  });
}

// ─── Update hooks ─────────────────────────────────────────────────────────────

export function useUpdateReceivable() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...patch }: {
      id: string;
      description?: string;
      due_date?: string;
      amount?: number;
      notes?: string;
      cost_center_id?: string;
    }) => {
      const { data, error } = await supabase
        .from('receivables')
        .update(patch)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['receivables', 'by-so'] });
    },
  });
}

export function useUpdatePayable() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...patch }: {
      id: string;
      description?: string;
      due_date?: string;
      amount?: number;
      expense_category?: string;
      cost_center_id?: string;
      notes?: string;
    }) => {
      const { data, error } = await supabase
        .from('payables')
        .update(patch)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['payables'] }),
  });
}
