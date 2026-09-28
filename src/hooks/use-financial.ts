import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { BankTransaction } from '@/lib/bank-parser';
import { writeAuditLog } from '@/hooks/use-audit-log';
import { cancelPaymentCascade } from '@/lib/cascade-updates';
import { lerEmPaginas } from '@/lib/ler-em-paginas';
import { montarAging, type ContaEmAberto } from '@/lib/aging';
import { rotuloDoMes, hojeEmBrasilia, somarDias, type FluxoDeCaixa } from '@/lib/fluxo-de-caixa';
import { carregarFluxoDeCaixa, chaveDoFluxo } from '@/hooks/use-fluxo-de-caixa';
import {
  categoriaNaPrevisao, faturasDoCartao, gastosQueSeRepetem, gastosQueSeRepetemPorDia, mesesDeReferencia,
  type ContaEmAberto as ContaDaPrevisao, type DespesaLancada, type FaturaPrevista, type GastoQueSeRepete, type LinhaDoCartao,
} from '@/lib/previsao-de-caixa';

export function useReceivables() {
  return useQuery({
    queryKey: ['receivables'],
    // Em páginas: o servidor corta em 1.000 linhas sem avisar (ver lerEmPaginas).
    queryFn: () => lerEmPaginas((de, ate) => supabase
      .from('receivables')
      .select('*, clients!receivables_client_id_fkey(id,name,whatsapp,phone), service_orders!receivables_service_order_id_fkey(id,service_order_number,share_token)')
      .order('due_date', { ascending: true })
      .order('id')
      .range(de, ate)),
  });
}

export function usePayables() {
  return useQuery({
    queryKey: ['payables'],
    // Em páginas: com 1.706 contas, a leitura de uma vez parava na 1.000ª (vencimento em
    // 05/03/2026) e Contas a Pagar aparecia vazia — as 5 em aberto ficavam de fora.
    queryFn: async () => (await lerEmPaginas((de, ate) => supabase
      .from('payables')
      // A linha do banco que pagou diz de qual conta ou cartão saiu (src/lib/origem-do-dinheiro).
      .select('*, suppliers!payables_supplier_id_fkey(name), payees!payables_payee_id_fkey(name), service_orders!payables_linked_service_order_id_fkey(service_order_number), service_order_expenses!service_order_expenses_linked_payable_id_fkey(receipt_url), bank_transactions!payables_bank_transaction_id_fkey(source_type, card_last_digits, bank_connections(label, institution, provider))')
      .order('due_date', { ascending: true })
      .order('id')
      .range(de, ate)))
      // Quem recebeu, num campo só: fornecedor cadastrado, depois favorecido (sócio,
      // diarista), depois o nome gravado. A tela lia `name`, que não existe na tabela, e
      // ~1.200 despesas apareciam com "—", sem agrupar, filtrar nem exportar pelo nome.
      .map((p) => ({
        ...p,
        name: (p as { suppliers?: { name?: string } | null }).suppliers?.name
          ?? (p as { payees?: { name?: string } | null }).payees?.name
          ?? (p as { supplier_name?: string | null }).supplier_name ?? null,
      })),
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
      supplier_id?: string; supplier_name?: string; payee_id?: string;
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

      const [recRes, recOverdue, payRes, payOverdue, collectedRes, paidRes, fluxoDoMes] = await Promise.all([
        supabase.from('receivables').select('balance_amount').not('status', 'in', '("paid","cancelled")'),
        supabase.from('receivables').select('balance_amount').not('status', 'in', '("paid","cancelled")').lt('due_date', today),
        supabase.from('payables').select('balance_amount').not('status', 'in', '("paid","cancelled")'),
        supabase.from('payables').select('balance_amount').not('status', 'in', '("paid","cancelled")').lt('due_date', today),
        supabase.from('payments').select('amount').not('receivable_id', 'is', null).eq('status', 'confirmed').gte('payment_date', firstOfMonth),
        supabase.from('payments').select('amount').not('payable_id', 'is', null).eq('status', 'confirmed').gte('payment_date', firstOfMonth),
        // O mês corrente pelo extrato: é o que de fato entrou e saiu das contas. Um erro aqui apaga
        // só os números do extrato — A receber e A pagar não dependem dele (conferência de
        // 27/09/2026: a falha derrubava o resumo inteiro e Contas a Receber mostrava R$ 0,00).
        carregarFluxoDeCaixa(1).then(
          (fluxo) => ({ fluxo, erro: null as string | null }),
          (e: unknown) => ({ fluxo: null as FluxoDeCaixa | null, erro: (e as Error)?.message ?? String(e) }),
        ),
      ]);

      const sum = (rows: any[] | null) => (rows || []).reduce((s, r) => s + Number(r.balance_amount || r.amount || 0), 0);
      const mes = fluxoDoMes.fluxo?.meses[0];

      return {
        total_receivable: sum(recRes.data),
        overdue_receivable: sum(recOverdue.data),
        total_payable: sum(payRes.data),
        overdue_payable: sum(payOverdue.data),
        // Baixas de contas a receber/pagar registradas no sistema (tabela payments). Não é o
        // dinheiro que passou pelo banco — para isso, os campos do extrato abaixo.
        collected_this_month: sum(collectedRes.data),
        paid_this_month: sum(paidRes.data),
        /** Entrou nas contas no mês, pelo extrato (sem transferência entre contas próprias). null = não deu para ler. */
        entrou_no_mes: mes ? mes.entrou : null,
        /** Saiu das contas no mês, pelo extrato (compra no cartão conta quando a fatura é paga). null = não deu para ler. */
        saiu_no_mes: mes ? mes.saiu : null,
        /** Por que o extrato não pôde ser lido — a tela diz isso em vez de mostrar R$ 0,00. */
        erro_do_extrato: fluxoDoMes.erro,
        /** À parte, sem somar: transferências entre contas próprias no mês. */
        transferencias_no_mes: mes?.transferencias ?? { entrou: 0, saiu: 0 },
        /** À parte, sem somar: crédito do cartão posto na conta corrente (Pix no crédito). */
        credito_do_cartao_no_mes: mes?.creditoDoCartao ?? { entrou: 0, saiu: 0 },
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
  /** Das saídas: contas a pagar lançadas. */
  saidasDasContas?: number;
  /** Das saídas: fatura do cartão (o que já está no cartão). */
  saidasDaFatura?: number;
  /** Das saídas: gastos que se repetem todo mês, pela média. */
  saidasRecorrentes?: number;
}

/** O que a previsão soma além das contas lançadas, para a tela dizer de onde vem cada número. */
export interface ExtrasDaPrevisao {
  faturas: Array<FaturaPrevista & { naPrevisao: boolean }>;
  recorrentes: GastoQueSeRepete[];
  /** O que não deu para ler — a previsão segue sem aquela parte e diz qual. */
  avisos: string[];
}

/**
 * A fatura de cada cartão e os gastos que se repetem (regras em src/lib/previsao-de-caixa.ts).
 * Erro de leitura aqui não derruba a previsão: ela segue só com as contas e diz o que ficou fora.
 */
const reais = (v: number) => v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const diaEMes = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;

async function lerExtrasDaPrevisao(hoje: string): Promise<{
  extras: ExtrasDaPrevisao; linhasDoCartao: Set<string>; pagoNoMes: Map<string, number>;
}> {
  const avisos: string[] = [];
  let faturas: FaturaPrevista[] = [];
  let recorrentes: GastoQueSeRepete[] = [];
  const linhasDoCartao = new Set<string>();
  /** O que já foi pago no mês de hoje, por categoria (fora do cartão): não entra de novo. */
  const pagoNoMes = new Map<string, number>();
  try {
    const [linhas, conexoes] = await Promise.all([
      lerEmPaginas((i, f) => supabase.from('bank_transactions')
        .select('id, bank_connection_id, transaction_date, amount, transaction_type, description, bill_id, dismissed_kind, import_batch_id')
        .eq('source_type', 'credit_card')
        .gte('transaction_date', somarDias(hoje, -200))
        .order('transaction_date').order('id').range(i, f)),
      supabase.from('bank_connections').select('id, label'),
    ]);
    if (conexoes.error) throw conexoes.error;
    const rotulo = new Map((conexoes.data ?? []).map((c: { id: string; label: string | null }) => [c.id, c.label ?? 'Cartão']));
    const porConta = new Map<string, LinhaDoCartao[]>();
    for (const l of linhas as Array<LinhaDoCartao & { id: string; bank_connection_id: string | null }>) {
      linhasDoCartao.add(l.id);
      const conta = l.bank_connection_id ?? 'sem conta';
      porConta.set(conta, [...(porConta.get(conta) ?? []), l]);
    }
    for (const [conta, doCartao] of porConta) {
      const nome = rotulo.get(conta) ?? 'Cartão';
      const r = faturasDoCartao(nome, doCartao, hoje);
      faturas.push(...r.faturas);
      // Cartão em uso cujo ciclo não dá para saber: o banco parou de identificar a fatura das
      // compras (C6 desde julho, Nubank desde agosto/2026). Sem este aviso, ele sumia da previsão.
      if (!r.ciclo && doCartao.some((l) => l.transaction_date >= somarDias(hoje, -60))) {
        avisos.push(`${nome}: não consegui saber em que dia a fatura fecha (o banco não identifica a fatura das compras `
          + 'recentes) — a fatura deste cartão ficou fora da previsão.');
      }
      if (r.pagoAlemDoExtrato > 0) {
        avisos.push(`${nome}: a fatura que fechou em ${diaEMes(r.fechada.fechamento)} foi paga em ${reais(r.fechada.pago)}, `
          + `mas o extrato do cartão mostra só ${reais(r.fechada.compras)} de compras nela. Faltam compras no extrato do `
          + 'cartão — a próxima fatura pode ser maior do que a prevista.');
      }
    }
  } catch (e) {
    avisos.push(`Não consegui ler os cartões (${(e as Error)?.message ?? 'erro'}): a fatura ficou fora da previsão.`);
    faturas = [];
  }
  try {
    const meses = mesesDeReferencia(hoje);
    const inicioDoMes = `${hoje.slice(0, 7)}-01`;
    // Os 4 meses de referência e o mês de hoje (o que já foi pago nele não entra de novo).
    const [despesas, categorias] = await Promise.all([
      lerEmPaginas((i, f) => supabase.from('payables')
        .select('id, amount, issue_date, expense_category, bank_transaction_id, status')
        .neq('status', 'cancelled')
        .gte('issue_date', `${meses[0]}-01`)
        .lte('issue_date', hoje)
        .order('id').range(i, f)),
      supabase.from('financial_categories').select('name, type, dre_group').eq('type', 'payable'),
    ]);
    if (categorias.error) throw categorias.error;
    const grupo = new Map((categorias.data ?? []).map((c: { name: string; dre_group: string | null }) => [c.name, c.dre_group]));
    const lancadas: Array<DespesaLancada & { pago: boolean }> = (despesas as Array<{
      amount: number; issue_date: string; expense_category: string | null; bank_transaction_id: string | null; status: string | null;
    }>)
      .map((d) => ({
        categoria: d.expense_category,
        valor: Number(d.amount) || 0,
        data: d.issue_date,
        grupo: d.expense_category ? grupo.get(d.expense_category) ?? null : null,
        noCartao: !!d.bank_transaction_id && linhasDoCartao.has(d.bank_transaction_id),
        pago: d.status === 'paid',
      }));
    recorrentes = gastosQueSeRepetem(lancadas.filter((d) => d.data < inicioDoMes), hoje);
    for (const d of lancadas) {
      // Pela mesma chave dos gastos que se repetem (pró-labore e retirada de sócio juntos).
      const categoria = categoriaNaPrevisao(d.categoria);
      if (d.data < inicioDoMes || !d.pago || d.noCartao || !categoria) continue;
      pagoNoMes.set(categoria, (pagoNoMes.get(categoria) ?? 0) + d.valor);
    }
  } catch (e) {
    avisos.push(`Não consegui ler as despesas dos últimos meses (${(e as Error)?.message ?? 'erro'}): os gastos que se repetem ficaram fora da previsão.`);
    recorrentes = [];
    pagoNoMes.clear();
  }
  return { extras: { faturas: faturas.map((f) => ({ ...f, naPrevisao: true })), recorrentes, avisos }, linhasDoCartao, pagoNoMes };
}

/**
 * Projeção de caixa das próximas semanas a partir do que está programado.
 *
 * O hook responde quanto entra, quanto sai e o resultado líquido de cada semana (e o
 * acumulado). O saldo de partida não é dele: desde 26/09/2026 o painel (CashForecastPanel)
 * soma o acumulado ao saldo de hoje que os bancos informam (fichas de saldo), e só então
 * mostra "saldo previsto" — sem saldo conhecido, projetar seria inventar número.
 *
 * Contas já vencidas e ainda em aberto entram na primeira semana, porque é quando elas
 * pressionam o caixa de verdade.
 *
 * Desde 27/09/2026 as saídas somam também a fatura de cada cartão (o que já está no cartão, no
 * dia provável de pagamento) e os gastos que se repetem todo mês, pela média — quase todo gasto
 * da HBR é lançado depois que sai, e só com as contas lançadas a previsão dizia que sobrava
 * dinheiro. As regras estão em src/lib/previsao-de-caixa.ts; o que entrou vem em `extras`.
 */
export function useCashForecast(semanas: number = 8) {
  return useQuery({
    queryKey: ['cash-forecast', semanas],
    queryFn: async (): Promise<{ weeks: ForecastWeek[]; totalEntradas: number; totalSaidas: number; semanasNegativas: number; extras: ExtrasDaPrevisao }> => {
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
          .select('balance_amount, due_date, expense_category')
          .not('status', 'in', '("paid","cancelled")')
          .lte('due_date', limiteISO),
      ]);
      const hojeLocal = hojeEmBrasilia();
      const { extras, pagoNoMes } = await lerExtrasDaPrevisao(hojeLocal);

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
          saidasDasContas: 0, saidasDaFatura: 0, saidasRecorrentes: 0,
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
        buckets[i].saidasDasContas! += Number(p.balance_amount || 0);
        if (i === 0 && new Date(`${p.due_date}T12:00:00`) < hoje) buckets[0].contemAtrasados = true;
      }

      // A fatura de cada cartão, no vencimento — a não ser que já esteja lançada como conta a
      // pagar perto dele (aí ela já está nas saídas acima e não conta duas vezes).
      const contasAbertas: ContaDaPrevisao[] = (payRes.data || []).map((p) => ({
        categoria: (p as { expense_category?: string | null }).expense_category ?? null,
        valor: Number(p.balance_amount || 0),
        vencimento: String(p.due_date),
      }));
      const faturaLancadaPerto = (vencimento: string) => contasAbertas.some((c) =>
        c.categoria === 'Pagamento de fatura de cartão'
        && Math.abs(Date.parse(c.vencimento) - Date.parse(vencimento)) <= 5 * 86_400_000);
      for (const f of extras.faturas) {
        if (faturaLancadaPerto(f.vencimento)) { f.naPrevisao = false; continue; }
        const i = f.vencida ? 0 : indiceDe(f.vencimento);
        if (i < 0) { f.naPrevisao = false; continue; }
        buckets[i].saidas += f.valor;
        buckets[i].saidasDaFatura! += f.valor;
        // Fatura vencida vai para esta semana como as contas vencidas: com o mesmo selo.
        if (f.vencida) buckets[0].contemAtrasados = true;
      }

      // Gastos que se repetem, espalhados pelos dias de hoje até o fim da janela.
      const fimDaJanela = somarDias(buckets[buckets.length - 1].inicio, 6);
      for (const [data, valor] of gastosQueSeRepetemPorDia(extras.recorrentes, contasAbertas, hojeLocal, fimDaJanela, pagoNoMes)) {
        const i = indiceDe(data);
        if (i < 0) continue;
        buckets[i].saidas += valor;
        buckets[i].saidasRecorrentes! += valor;
      }
      for (const b of buckets) {
        b.saidas = Number(b.saidas.toFixed(2));
        b.saidasDasContas = Number((b.saidasDasContas ?? 0).toFixed(2));
        b.saidasDaFatura = Number((b.saidasDaFatura ?? 0).toFixed(2));
        b.saidasRecorrentes = Number((b.saidasRecorrentes ?? 0).toFixed(2));
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
        extras,
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

/**
 * Fluxo de caixa mês a mês, PELO EXTRATO (26/09/2026).
 *
 * Lia a tabela `payments` — os 52 pagamentos registrados à mão no sistema inteiro —, e o
 * gráfico mostrava quase nada saindo. Agora é o que entrou e saiu das contas (conta corrente
 * e Caixa), com as regras de src/lib/fluxo-de-caixa.ts: sem cartão de crédito (conta quando a
 * fatura é paga), sem duplicata nem transferência entre contas próprias.
 *
 * O formato de retorno continua `{ month, inflow, outflow, net }`; a mesma entrada de cache
 * serve a quem precisa do fluxo completo (useFluxoDeCaixa), com os baldes à parte.
 */
export function useCashFlow(months: number = 6) {
  return useQuery({
    queryKey: chaveDoFluxo(months),
    queryFn: () => carregarFluxoDeCaixa(months),
    select: (f: FluxoDeCaixa) => f.meses.map((m) => ({
      month: rotuloDoMes(m.mes),
      inflow: m.entrou,
      outflow: m.saiu,
      net: m.liquido,
    })),
    staleTime: 60_000,
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

// Desfazer uma transação ignorada é `useDesfazerIgnorada` (use-finance-review.ts), que passa
// pela action `undismiss` do edge e reverte o EFEITO (proposta/lançamento) e não só as
// colunas. O hook antigo que zerava as colunas direto na tabela foi removido em 15/09/2026
// (item F3 do roteiro Open Finance): ninguém o chamava, e quem o achasse primeiro faria a
// transação voltar à fila com o lançamento que ela gerou ainda de pé.

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

      /**
       * O vínculo de volta, da conta para a transação — sem ele a despesa volta a ser
       * proposta.
       *
       * A varredura da caixa de entrada pergunta "esta transação já virou lançamento?"
       * olhando `payables.bank_transaction_id`. Baixar a conta e marcar a transação como
       * conciliada não respondia essa pergunta, então a mesma despesa era proposta de novo
       * e aprovada de boa-fé. Ver o bloco DUPLICIDADE em BankReconciliation.tsx.
       *
       * Só grava se ainda estiver vazio: uma conta paga em parcelas recebe várias
       * transações, e o índice único só admite uma. A primeira fica com o vínculo; as
       * demais seguem rastreáveis pelos pagamentos, e um conflito aqui não desfaz a baixa
       * que já aconteceu — por isso o erro é registrado, não propagado.
       */
      const alvo = input.receivableId ? 'receivables' : 'payables';
      const alvoId = (input.receivableId || input.payableId) ?? null;
      if (alvoId) {
        const { error: erroVinculo } = await supabase.from(alvo).update({
          bank_transaction_id: input.bankTransactionId,
        } as never).eq('id', alvoId).is('bank_transaction_id', null);
        if (erroVinculo) console.warn('vínculo conta-transação não gravado:', erroVinculo.message);
      }

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
// A régua das faixas mora em src/lib/aging.ts: a mesma para quem me deve e a quem devo.

export type { AgingBucket, AgingReportData } from '@/lib/aging';

/** Quem deve à empresa, por tempo de atraso (contas a receber em aberto). */
export function useAgingReport() {
  return useQuery({
    queryKey: ['aging-report'],
    queryFn: async () => {
      // Em páginas: o servidor corta em 1.000 linhas sem avisar.
      const data = await lerEmPaginas((i, f) => supabase
        .from('receivables')
        .select('id, amount, balance_amount, due_date, status, client_id, clients!receivables_client_id_fkey(id, name)')
        .in('status', ['pending', 'partially_paid', 'overdue'])
        .gt('balance_amount', 0)
        .order('id')
        .range(i, f));

      const contas: ContaEmAberto[] = [];
      for (const r of data) {
        const client = (r as { clients?: { id: string; name: string } | null }).clients;
        if (!client) continue;
        contas.push({ parteId: client.id, parteNome: client.name, vencimento: r.due_date, saldo: Number(r.balance_amount || 0) });
      }
      return montarAging(contas);
    },
    staleTime: 5 * 60 * 1000,
  });
}

/**
 * A quem a empresa deve, por tempo de atraso (contas a pagar em aberto) — as mesmas faixas
 * do lado a receber. O nome vem do fornecedor, depois do favorecido (sócio, diarista),
 * depois do que foi gravado na conta.
 */
export function useAgingAPagar() {
  return useQuery({
    queryKey: ['aging-a-pagar'],
    queryFn: async () => {
      const data = await lerEmPaginas((i, f) => supabase
        .from('payables')
        .select('id, balance_amount, due_date, status, supplier_id, payee_id, supplier_name, suppliers!payables_supplier_id_fkey(name), payees!payables_payee_id_fkey(name)')
        .in('status', ['pending', 'partially_paid', 'overdue'])
        .gt('balance_amount', 0)
        .order('id')
        .range(i, f));

      const contas: ContaEmAberto[] = data.map((p) => {
        const linha = p as typeof p & {
          suppliers?: { name?: string } | null; payees?: { name?: string } | null;
          supplier_name?: string | null; payee_id?: string | null;
        };
        const nome = linha.suppliers?.name ?? linha.payees?.name ?? linha.supplier_name ?? 'Sem fornecedor';
        const id = linha.supplier_id ?? linha.payee_id ?? `nome:${nome.trim().toLowerCase()}`;
        return { parteId: id, parteNome: nome, vencimento: p.due_date, saldo: Number(p.balance_amount || 0) };
      });
      return montarAging(contas);
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
      // Passa pela função do banco, a mesma da tela nova e do assistente: grava na trilha,
      // respeita mês fechado e recalcula o saldo quando o valor muda. O update direto que
      // estava aqui deixava balance_amount com o valor antigo.
      const { data, error } = await supabase.rpc('corrigir_lancamento' as never, {
        p_tipo: 'receivable', p_id: id, p_campos: patch,
      } as never);
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['receivables', 'by-so'] });
      qc.invalidateQueries({ queryKey: ['trilha-conciliacao'] });
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
      // Mesmo caminho único do recebível acima (trilha, mês fechado, saldo recalculado).
      const { data, error } = await supabase.rpc('corrigir_lancamento' as never, {
        p_tipo: 'payable', p_id: id, p_campos: patch,
      } as never);
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['payables'] });
      qc.invalidateQueries({ queryKey: ['trilha-conciliacao'] });
    },
  });
}
