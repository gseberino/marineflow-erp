// Tudo o que saiu, com a categoria e quem classificou — a tela Despesas.
//
// Pedido do dono (26/09/2026): "senti falta de alguma aba para despesas; não sei onde eu vejo o
// que saiu e como foi categorizado". Havia pedaços: o extrato de UMA conta por vez, a aba do
// cartão, o "mostrar as já pagas" (quebrado) e o DRE (só o total da categoria). Aqui é a lista:
// cada despesa do período (pela data do lançamento, como o DRE), de onde saiu e quem decidiu.
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { lerEmPaginas } from '@/lib/ler-em-paginas';
import { historicoSemIdentidade } from '../../supabase/functions/_shared/banking/proposals';

export type QuemClassificou = 'regra' | 'confianca' | 'voce' | 'nota' | 'caixa' | 'mao';

export const ROTULO_QUEM_CLASSIFICOU: Record<QuemClassificou, string> = {
  regra: 'sozinho, pela sua regra',
  confianca: 'sozinho, por confiança alta',
  voce: 'você, no Extrato',
  nota: 'nota fiscal (XML)',
  caixa: 'lançado no Caixa',
  mao: 'lançado à mão',
};

export interface Despesa {
  id: string;
  data: string;
  descricao: string;
  valor: number;
  categoria: string;
  /** Linha do DRE da categoria; "nao_operacional" = fica fora do resultado. */
  grupo: string | null;
  quem: string;
  /** Conta de onde saiu (C6, Nubank, Caixa…), "Cartão de crédito" ou "—". */
  deOnde: string;
  quemClassificou: QuemClassificou;
  os: string | null;
  status: string;
  /** Linha do banco sem ninguém identificado ("DEBITO DE CARTAO", "TRANSF ENVIADA PIX"). */
  semNome: boolean;
  /** Linha crua, para abrir a correção. */
  bruto: Record<string, unknown>;
}

type Linha = {
  id: string; description: string; issue_date: string; amount: number; status: string;
  expense_category: string | null; supplier_name: string | null; origin: string | null;
  suppliers?: { name?: string } | null; payees?: { name?: string } | null;
  service_orders?: { service_order_number?: string } | null;
  bank_transactions?: {
    source_type?: string | null; description?: string | null; counterparty_name?: string | null;
    bank_connections?: { label?: string | null; provider?: string | null } | null;
  } | null;
  finance_review_queue?: Array<{ automatica?: string | null; status?: string | null }> | null;
};

/** Uma despesa como a tela mostra — separado para testar sem banco. */
export function paraDespesa(l: Linha, grupoDe: Map<string, string>): Despesa {
  const bt = l.bank_transactions ?? null;
  const conta = bt?.bank_connections ?? null;
  const fila = (l.finance_review_queue ?? []).find((q) => q.status === 'approved') ?? null;
  const quemClassificou: QuemClassificou = fila?.automatica === 'regra' ? 'regra'
    : fila?.automatica === 'confianca' ? 'confianca'
    : fila ? 'voce'
    : l.origin === 'fiscal_note' ? 'nota'
    : conta?.provider === 'caixa' ? 'caixa'
    : 'mao';
  const deOnde = bt?.source_type === 'credit_card' ? 'Cartão de crédito'
    : conta?.label ?? (bt ? 'Banco' : '—');
  const quem = l.suppliers?.name ?? l.payees?.name ?? l.supplier_name ?? bt?.counterparty_name ?? l.description;
  const categoria = l.expense_category ?? 'Sem categoria';
  return {
    id: l.id, data: l.issue_date, descricao: l.description, valor: Number(l.amount), categoria,
    grupo: grupoDe.get(categoria) ?? null, quem: String(quem ?? '—'), deOnde, quemClassificou,
    os: l.service_orders?.service_order_number ?? null, status: l.status,
    // A mesma lista do motor do Extrato (historicoSemIdentidade): uma fonte só.
    // Só quando há linha do banco: sem ela não há "o banco não informou" (lançamento à mão sem
    // nome é outra coisa, e mostraria o nome na coluna e "sem quem recebeu" ao mesmo tempo).
    semNome: !!bt && !l.suppliers?.name && !l.payees?.name && !bt.counterparty_name && historicoSemIdentidade(String(bt.description ?? '')),
    bruto: l as unknown as Record<string, unknown>,
  };
}

export function useDespesas(de: string, ate: string) {
  return useQuery({
    queryKey: ['despesas', de, ate],
    queryFn: async (): Promise<Despesa[]> => {
      const [cats, linhas] = await Promise.all([
        supabase.from('financial_categories').select('name, dre_group').eq('type', 'payable'),
        lerEmPaginas((i, f) => supabase.from('payables')
          .select(`id, description, issue_date, amount, status, expense_category, supplier_name, origin, payee_id, supplier_id,
                   bank_transaction_id, linked_service_order_id, paid_amount, balance_amount, due_date, notes, cost_center_id,
                   suppliers!payables_supplier_id_fkey(name), payees!payables_payee_id_fkey(name),
                   service_orders!payables_linked_service_order_id_fkey(service_order_number),
                   bank_transactions!payables_bank_transaction_id_fkey(source_type, description, counterparty_name, bank_connections(label, provider))`)
          .neq('status', 'cancelled')
          .gte('issue_date', de).lte('issue_date', ate)
          .order('issue_date', { ascending: false }).order('id')
          .range(i, f)),
      ]);
      if (cats.error) throw cats.error;
      const grupoDe = new Map<string, string>();
      for (const c of (cats.data ?? []) as Array<{ name: string; dre_group: string | null }>) {
        if (c.dre_group) grupoDe.set(c.name, c.dre_group);
      }
      // Quem aprovou cada uma (a proposta da fila que a criou): em consulta à parte, por lotes.
      const ids = (linhas as unknown as Linha[]).map((l) => l.id);
      const filaPor = new Map<string, Array<{ automatica?: string | null; status?: string | null }>>();
      for (let i = 0; i < ids.length; i += 150) {
        const { data: fila, error: eFila } = await supabase.from('finance_review_queue' as never)
          .select('created_payable_id, automatica, status').in('created_payable_id', ids.slice(i, i + 150));
        if (eFila) throw eFila;
        for (const q of (fila ?? []) as Array<{ created_payable_id: string; automatica: string | null; status: string | null }>) {
          filaPor.set(q.created_payable_id, [...(filaPor.get(q.created_payable_id) ?? []), q]);
        }
      }
      return (linhas as unknown as Linha[]).map((l) => paraDespesa({ ...l, finance_review_queue: filaPor.get(l.id) ?? [] }, grupoDe));
    },
    staleTime: 30_000,
  });
}

export interface TotalDaCategoria {
  categoria: string;
  grupo: string | null;
  valor: number;
  quantidade: number;
}

/** Total por categoria, do maior para o menor. */
export function totaisPorCategoria(despesas: Despesa[]): TotalDaCategoria[] {
  const m = new Map<string, TotalDaCategoria>();
  for (const d of despesas) {
    const t = m.get(d.categoria) ?? { categoria: d.categoria, grupo: d.grupo, valor: 0, quantidade: 0 };
    t.valor += d.valor;
    t.quantidade += 1;
    m.set(d.categoria, t);
  }
  return [...m.values()].map((t) => ({ ...t, valor: Math.round(t.valor * 100) / 100 })).sort((a, b) => b.valor - a.valor);
}

export const ROTULO_DO_GRUPO: Record<string, string> = {
  custo_direto: 'custo do serviço',
  despesa_operacional: 'despesa para manter a empresa',
  financeiro: 'juros, tarifas e impostos',
  nao_operacional: 'fora do resultado',
  receita: 'receita',
};
