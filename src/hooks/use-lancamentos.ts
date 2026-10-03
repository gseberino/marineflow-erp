// Corrigir, desfazer, cancelar e casar um lançamento — o caminho único.
//
// Estas quatro ações vivem em funções do banco (migration 20260925200000), e a tela, o
// assistente do painel e o do WhatsApp chamam as mesmas funções. Assim a regra é uma só:
// toda mudança vai para a trilha, mês fechado recusa, valor que veio do banco não muda à
// mão e categoria sensível fica só com o administrador.
//
// Antes, cada tela gravava direto na tabela. Mudar o valor de uma conta em aberto não
// recalculava o saldo, conta paga não abria para edição e desfazer não existia — foi o que
// levou o dono a não confiar no que tinha aprovado.
import { useMutation, useQuery, useQueryClient, type QueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export type TipoDeLancamento = 'payable' | 'receivable';

/** O que se pode corrigir numa conta a pagar. Chave com null limpa o campo. */
export interface CorrecaoDePagavel {
  description?: string;
  notes?: string | null;
  expense_category?: string | null;
  supplier_id?: string | null;
  payee_id?: string | null;
  linked_service_order_id?: string | null;
  cost_center_id?: string | null;
  issue_date?: string;
  due_date?: string;
  amount?: number;
}

/** O que se pode corrigir numa conta a receber. */
export interface CorrecaoDeRecebivel {
  description?: string;
  notes?: string | null;
  category?: string | null;
  client_id?: string;
  service_order_id?: string | null;
  cost_center_id?: string | null;
  issue_date?: string;
  due_date?: string;
  amount?: number;
}

export interface RespostaDoLancamento {
  ok: boolean;
  message: string;
  alterados?: string[];
  acao?: string;
  proposta_voltou?: boolean;
  linha_do_extrato?: 'fora_da_fila' | 'fila' | null;
  pagamento_registrado?: boolean;
  valor_pago?: number;
  /** aplicar_entrada_em_contas */
  aplicado?: number;
  contas?: number;
  /** desfazer_aplicacao: nada mais da entrada ficou aplicado e ela voltou para a fila. */
  entrada_livre?: boolean;
}

/**
 * Tudo que mostra lançamento, saldo ou fila precisa recarregar depois de qualquer uma das
 * quatro ações: um desfazer mexe na conta, na fila do Extrato, na Conciliação, no DRE e na
 * trilha ao mesmo tempo.
 */
export function recarregarFinanceiro(qc: QueryClient) {
  for (const k of [
    ['payables'], ['receivables'], ['payments'], ['financial-summary'], ['cash-flow'],
    ['bank-transactions'], ['bank-transactions-ignoradas'], ['extrato-a-tratar'],
    ['finance-review-queue'], ['finance-review-count'],
    ['conciliacao-sem-extrato'], ['conciliacao-conciliados'], ['conciliacao-extrato-livre'],
    ['trilha-conciliacao'], ['dre'], ['dashboard'], ['aging-report'], ['service-orders'],
    ['extrato-da-conta'], ['lancados-sozinhos'], ['checklist-do-mes'],
    ['dre-lancamentos'], ['saldo-das-contas'], ['despesas'], ['pix-dividido'],
    ['vinculo-com-extrato'], ['entrada-aplicada'], ['contas-em-aberto-do-cliente'], ['pagamentos-sem-pix'],
  ]) qc.invalidateQueries({ queryKey: k });
}

/** Uma parte de um Pix dividido (pró-labore + retirada de sócio, 28/09/2026). */
export interface ParteDoPix {
  id: string;
  amount: number | string;
  expense_category: string | null;
  /** Nulo no lançamento principal; nas partes, o id do principal. */
  divisao_id: string | null;
}

/**
 * As partes do Pix dividido a que a conta pertence, ou null se ela não é de um Pix dividido.
 * Desfazer e cancelar valem para o Pix inteiro (o banco junta as partes antes), então a tela
 * precisa dizer isso antes do clique.
 */
export function usePixDividido(tipo: TipoDeLancamento, id: string | null | undefined) {
  return useQuery({
    queryKey: ['pix-dividido', tipo, id],
    enabled: tipo === 'payable' && !!id,
    staleTime: 30_000,
    queryFn: async (): Promise<ParteDoPix[] | null> => {
      const { data: eu, error } = await supabase.from('payables').select('id, divisao_id').eq('id', id!).maybeSingle();
      if (error) throw error;
      if (!eu) return null;
      const raiz = (eu as { divisao_id: string | null }).divisao_id ?? (eu as { id: string }).id;
      const { data, error: erro } = await supabase.from('payables')
        .select('id, amount, expense_category, divisao_id')
        .or(`id.eq.${raiz},divisao_id.eq.${raiz}`)
        .neq('status', 'cancelled');
      if (erro) throw erro;
      const partes = (data ?? []) as ParteDoPix[];
      return partes.length > 1 ? partes : null;
    },
  });
}

/** "Este Pix está dividido em Pró-labore R$ 1.621,00 + Retirada de sócio R$ 2.379,00. …" */
export function avisoDoPixDividido(
  partes: ParteDoPix[], formatar: (v: number) => string, acao: 'desfazer' | 'cancelar',
): string {
  const ordem = [...partes].sort((a, b) => Number(!!a.divisao_id) - Number(!!b.divisao_id));
  const total = Math.round(ordem.reduce((s, p) => s + Number(p.amount || 0), 0) * 100) / 100;
  return `Este Pix está dividido em ${ordem.map((p) => `${p.expense_category ?? 'sem categoria'} ${formatar(Number(p.amount || 0))}`).join(' + ')}. `
    + `${acao === 'desfazer' ? 'Desfazer' : 'Cancelar'} vale para o pagamento inteiro de ${formatar(total)}. `
    + 'Para mudar só uma parte (um gasto pessoal, por exemplo), use Corrigir.';
}

/** A mensagem do banco já vem em português e diz o que fazer; só tira o prefixo técnico. */
export function mensagemDoErro(e: unknown): string {
  const texto = (e as { message?: string })?.message ?? String(e);
  return texto.replace(/^(ERROR:\s*)?(P0001|42501|23514):\s*/i, '');
}

async function chamar(nome: string, args: Record<string, unknown>): Promise<RespostaDoLancamento> {
  const { data, error } = await supabase.rpc(nome as never, args as never);
  if (error) throw error;
  return data as unknown as RespostaDoLancamento;
}

export function useCorrigirLancamento() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: {
      tipo: TipoDeLancamento;
      id: string;
      campos: CorrecaoDePagavel | CorrecaoDeRecebivel;
      motivo?: string | null;
    }) => chamar('corrigir_lancamento', {
      p_tipo: v.tipo, p_id: v.id, p_campos: v.campos, p_motivo: v.motivo ?? null,
    }),
    onSuccess: (r) => {
      recarregarFinanceiro(qc);
      toast.success(r.alterados && r.alterados.length === 0 ? 'Nada mudou' : 'Lançamento corrigido');
    },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

export function useDesfazerAprovacao() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { tipo: TipoDeLancamento; id: string; motivo?: string | null }) =>
      chamar('desfazer_aprovacao', { p_tipo: v.tipo, p_id: v.id, p_motivo: v.motivo ?? null }),
    onSuccess: (r) => { recarregarFinanceiro(qc); toast.success(r.message); },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

/**
 * Conta a receber casada com o banco por UM pagamento passa a valer o que entrou no banco
 * (02/10/2026). Banco maior: o cliente pagou a mais. Banco menor: desconto. A função do banco
 * recusa o caso com mais de um pagamento.
 */
export function useAjustarAoValorDoBanco() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { tipo: TipoDeLancamento; id: string; motivo?: string | null }) =>
      chamar('ajustar_ao_valor_do_banco', { p_tipo: v.tipo, p_id: v.id, p_motivo: v.motivo ?? null }),
    onSuccess: (r) => { recarregarFinanceiro(qc); toast.success(r.message); },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

/** A linha do banco ligada ao lançamento, os pagamentos dele e se nasceu do extrato. */
export function useVinculoComExtrato(tipo: TipoDeLancamento, id: string | null | undefined, linhaId: string | null | undefined) {
  return useQuery({
    queryKey: ['vinculo-com-extrato', tipo, id, linhaId],
    enabled: !!id && !!linhaId,
    queryFn: async () => {
      const [linha, pagamentos, origem] = await Promise.all([
        supabase.from('bank_transactions')
          .select('id, transaction_date, description, amount, reconciled_payment_id')
          .eq('id', linhaId!).maybeSingle(),
        supabase.from('payments')
          .select('id, amount, payment_date')
          .eq(tipo === 'payable' ? 'payable_id' : 'receivable_id', id!)
          .eq('status', 'confirmed'),
        supabase.from('conciliacao_lancamentos' as never)
          .select('nasceu_do_extrato')
          .eq('lado', tipo).eq('id', id!).maybeSingle(),
      ]);
      if (linha.error) throw linha.error;
      if (pagamentos.error) throw pagamentos.error;
      if (origem.error) throw origem.error;
      const l = linha.data as { transaction_date: string; description: string | null; amount: number; reconciled_payment_id: string | null } | null;
      if (!l) return null;
      return {
        linha: {
          data: l.transaction_date, descricao: l.description ?? '', valor: Number(l.amount), pagamentoId: l.reconciled_payment_id,
        },
        pagamentos: ((pagamentos.data ?? []) as Array<{ id: string; amount: number; payment_date: string }>)
          .map((x) => ({ id: x.id, valor: Number(x.amount), data: x.payment_date })),
        nasceuDoExtrato: !!(origem.data as { nasceu_do_extrato?: boolean } | null)?.nasceu_do_extrato,
      };
    },
  });
}

export function useCancelarLancamento() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { tipo: TipoDeLancamento; id: string; motivo: string }) =>
      chamar('cancelar_lancamento', { p_tipo: v.tipo, p_id: v.id, p_motivo: v.motivo }),
    onSuccess: (r) => { recarregarFinanceiro(qc); toast.success(r.message); },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

// ── "Este Pix paga…" (forma A, F2 — 02/10/2026) ──────────────────────────────────────────
// Uma entrada do banco pode pagar várias contas e uma conta pode receber de várias entradas.
// A regra é a da função do banco aplicar_entrada_em_contas (src/lib/este-pix-paga.ts a repete
// para a tela dizer antes do clique).

/** Uma conta que esta entrada já pagou. */
export interface AplicacaoDaEntrada {
  pagamentoId: string;
  contaId: string;
  descricao: string;
  valor: number;
}

/** A entrada como recebimento: o valor, o que já foi aplicado (e em quais contas) e a sobra. */
export function useEntradaAplicada(linhaId: string | null | undefined) {
  return useQuery({
    queryKey: ['entrada-aplicada', linhaId],
    enabled: !!linhaId,
    queryFn: async () => {
      const [entrada, aplicacoes] = await Promise.all([
        supabase.from('recebimentos_do_extrato' as never)
          .select('bank_transaction_id, data, valor, quem, aplicado, sobra, contas')
          .eq('bank_transaction_id', linhaId!).maybeSingle(),
        supabase.from('payments')
          .select('id, amount, receivable_id, receivables!inner(description)')
          .eq('bank_transaction_id', linhaId!)
          .eq('status', 'confirmed')
          .not('receivable_id', 'is', null),
      ]);
      if (entrada.error) throw entrada.error;
      if (aplicacoes.error) throw aplicacoes.error;
      const e = entrada.data as { data: string; valor: number; quem: string | null; aplicado: number; sobra: number } | null;
      if (!e) return null;
      return {
        data: e.data,
        valor: Number(e.valor),
        quem: e.quem ?? '',
        aplicado: Number(e.aplicado),
        sobra: Number(e.sobra),
        aplicacoes: ((aplicacoes.data ?? []) as unknown as Array<{ id: string; amount: number; receivable_id: string; receivables: { description: string } | null }>)
          .map((p): AplicacaoDaEntrada => ({
            pagamentoId: p.id, contaId: p.receivable_id, descricao: p.receivables?.description ?? 'Conta a receber', valor: Number(p.amount),
          })),
      };
    },
  });
}

/** Contas a receber em aberto de um cliente, da que vence primeiro para a última. */
export function useContasEmAbertoDoCliente(clienteId: string | null | undefined) {
  return useQuery({
    queryKey: ['contas-em-aberto-do-cliente', clienteId],
    enabled: !!clienteId,
    queryFn: async () => {
      const { data, error } = await supabase.from('receivables')
        .select('id, description, due_date, amount, paid_amount, service_orders!receivables_service_order_id_fkey(service_order_number)')
        .eq('client_id', clienteId!)
        .in('status', ['pending', 'overdue', 'partially_paid'])
        .order('due_date', { ascending: true });
      if (error) throw error;
      return ((data ?? []) as unknown as Array<{
        id: string; description: string; due_date: string; amount: number; paid_amount: number | null;
        service_orders: { service_order_number: string } | null;
      }>).map((x) => ({
        id: x.id,
        descricao: x.description,
        documento: x.service_orders?.service_order_number ?? null,
        vencimento: x.due_date,
        valor: Number(x.amount),
        pago: Number(x.paid_amount ?? 0),
        saldo: Math.round((Number(x.amount) - Number(x.paid_amount ?? 0)) * 100) / 100,
      })).filter((x) => x.saldo > 0);
    },
  });
}

/**
 * Pagamentos do cliente lançados à mão e ainda sem entrada do banco (o "Receber sinal" antes do
 * Pix aparecer no extrato). Dinheiro em espécie fica de fora: não pode ser um Pix.
 */
export function usePagamentosSemPixDoCliente(clienteId: string | null | undefined) {
  return useQuery({
    queryKey: ['pagamentos-sem-pix', clienteId],
    enabled: !!clienteId,
    queryFn: async () => {
      const { data, error } = await supabase.from('payments')
        .select('id, amount, payment_date, receivable_id, receivables!inner(description, client_id, status, service_orders!receivables_service_order_id_fkey(service_order_number))')
        .eq('receivables.client_id', clienteId!)
        .neq('receivables.status', 'cancelled')
        .eq('status', 'confirmed')
        .is('bank_transaction_id', null)
        .neq('payment_method', 'cash')
        .order('payment_date', { ascending: false })
        .limit(50);
      if (error) throw error;
      return ((data ?? []) as unknown as Array<{
        id: string; amount: number; payment_date: string; receivable_id: string;
        receivables: { description: string; service_orders: { service_order_number: string } | null } | null;
      }>).map((p) => ({
        id: p.id,
        contaId: p.receivable_id,
        descricao: p.receivables?.description ?? 'Conta a receber',
        documento: p.receivables?.service_orders?.service_order_number ?? null,
        data: p.payment_date,
        valor: Number(p.amount),
      }));
    },
  });
}

export function useAplicarEntradaEmContas() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: {
      bankTransactionId: string;
      aplicacoes: Array<{ receivable_id: string; valor: number; quitar: boolean } | { pagamento_id: string }>;
      motivo?: string | null;
    }) => chamar('aplicar_entrada_em_contas', {
      p_transacao: v.bankTransactionId, p_aplicacoes: v.aplicacoes, p_motivo: v.motivo ?? null,
    }),
    onSuccess: (r) => { recarregarFinanceiro(qc); toast.success(r.message); },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

/** Estorna o pagamento que a aplicação criou (ou desliga o já lançado) e, se nada mais da entrada ficou aplicado, ela volta para a fila. */
export function useDesfazerAplicacao() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { pagamentoId: string; motivo?: string | null }) =>
      chamar('desfazer_aplicacao', { p_pagamento: v.pagamentoId, p_motivo: v.motivo ?? null }),
    onSuccess: (r) => { recarregarFinanceiro(qc); toast.success(r.message); },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

/**
 * Casa um lançamento com uma linha do extrato. Se a conta está em aberto, o pagamento é
 * registrado na data do extrato — casar é dizer que ela foi paga.
 */
export function useCasarComExtrato() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { tipo: TipoDeLancamento; id: string; bankTransactionId: string }) =>
      chamar('conciliar_lancamento', { p_tipo: v.tipo, p_id: v.id, p_transacao: v.bankTransactionId }),
    onSuccess: (r) => { recarregarFinanceiro(qc); toast.success(r.message); },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}
