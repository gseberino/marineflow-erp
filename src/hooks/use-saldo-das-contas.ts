// Quanto há em cada conta e no Caixa — o número que todo dono procura primeiro.
//
// Pedido do dono (26/09/2026): "na aba contas bancárias poderia ter o saldo em cada conta".
// O dado já existia: a cada busca (6h e 15h) o banco informa o saldo da conta, e ele fica em
// bank_balance_checks junto com a conferência "base + lançado = banco". O Caixa não tem banco
// que informe: o saldo dele é a base mais as linhas lançadas (mesma conta de saldo_do_caixa).
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { lerEmPaginas } from '@/lib/ler-em-paginas';

export interface SaldoDaConta {
  id: string;
  nome: string;
  ehCaixa: boolean;
  /** Banco: o saldo que o próprio banco informou na última busca. Caixa: base + lançado. */
  saldo: number | null;
  /** Banco: quando o banco informou esse saldo. */
  conferidoEm: string | null;
  /** Banco: o que foi lançado bate com o saldo do banco? null = ainda não conferido. */
  confere: boolean | null;
  diferenca: number | null;
  /** Caixa: já houve uma contagem ("Contei o dinheiro"). Sem ela, o saldo parte de zero. */
  contado: boolean;
}

export interface SaldosDasContas {
  contas: SaldoDaConta[];
  /** Soma das contas com saldo conhecido (banco + Caixa). */
  disponivel: number;
}

interface Conferencia {
  bank_connection_id: string;
  conferido_em: string;
  saldo_do_provedor: number | null;
  diferenca: number | null;
  fecha: boolean | null;
}

/** Monta as fichas a partir dos dados crus — separado para testar sem banco. */
export function montarSaldos(
  conexoes: Array<{ id: string; label: string; provider: string; active: boolean; saldo_base: number | null }>,
  conferencias: Conferencia[],
  linhasDoCaixa: Array<{ amount: number; transaction_type: string; tx_status: string | null; dismissed_kind: string | null }>,
  /** Há registro de contagem na trilha (inclusive a que bateu e não gerou ajuste). */
  contagemRegistrada = false,
): SaldosDasContas {
  const ultima = new Map<string, Conferencia>();
  for (const c of [...conferencias].sort((a, b) => b.conferido_em.localeCompare(a.conferido_em))) {
    if (!ultima.has(c.bank_connection_id)) ultima.set(c.bank_connection_id, c);
  }
  const contas: SaldoDaConta[] = conexoes.filter((c) => c.active).map((c) => {
    if (c.provider === 'caixa') {
      // Mesma conta de saldo_do_caixa(): duplicata e lançamento cancelado (estornada) não contam.
      const validas = linhasDoCaixa.filter((l) => (l.tx_status ?? '') !== 'PENDING' && !['duplicata', 'estornada'].includes(l.dismissed_kind ?? ''));
      const soma = validas.reduce((s, l) => s + (l.transaction_type === 'credit' ? 1 : -1) * Number(l.amount), 0);
      return {
        id: c.id, nome: c.label, ehCaixa: true,
        saldo: Math.round((Number(c.saldo_base ?? 0) + soma) * 100) / 100,
        conferidoEm: null, confere: null, diferenca: null,
        contado: contagemRegistrada || linhasDoCaixa.some((l) => l.dismissed_kind === 'ajuste_caixa'),
      };
    }
    const u = ultima.get(c.id);
    return {
      id: c.id, nome: c.label, ehCaixa: false,
      saldo: u?.saldo_do_provedor != null ? Number(u.saldo_do_provedor) : null,
      conferidoEm: u?.conferido_em ?? null,
      confere: u ? !!u.fecha : null,
      diferenca: u?.diferenca != null ? Number(u.diferenca) : null,
      contado: true,
    };
  });
  // Caixa por último: é a conta que você mesmo alimenta.
  contas.sort((a, b) => Number(a.ehCaixa) - Number(b.ehCaixa));
  const disponivel = contas.reduce((s, c) => s + (c.saldo ?? 0), 0);
  return { contas, disponivel: Math.round(disponivel * 100) / 100 };
}

export function useSaldoDasContas() {
  return useQuery({
    queryKey: ['saldo-das-contas'],
    queryFn: async (): Promise<SaldosDasContas> => {
      const con = await supabase.from('bank_connections').select('id, label, provider, active, saldo_base');
      if (con.error) throw con.error;
      const conexoes = (con.data ?? []) as unknown as Parameters<typeof montarSaldos>[0];
      const caixa = conexoes.find((c) => c.provider === 'caixa' && c.active);
      // A ÚLTIMA conferência de CADA conta, uma consulta por conta: numa janela comum às contas,
      // a que parasse de sincronizar sumiria das fichas e do dinheiro disponível.
      const bancos = conexoes.filter((c) => c.active && c.provider !== 'caixa');
      const [ultimas, linhas, contagem] = await Promise.all([
        Promise.all(bancos.map(async (c) => {
          const { data, error } = await supabase.from('bank_balance_checks')
            .select('bank_connection_id, conferido_em, saldo_do_provedor, diferenca, fecha')
            .eq('bank_connection_id', c.id).order('conferido_em', { ascending: false }).limit(1);
          if (error) throw error;
          return (data ?? []) as unknown as Conferencia[];
        })),
        caixa
          ? lerEmPaginas((de, ate) => supabase.from('bank_transactions')
              .select('id, amount, transaction_type, tx_status, dismissed_kind')
              .eq('bank_connection_id', caixa.id).order('id').range(de, ate))
          : Promise.resolve([]),
        // Contagem que bateu não gera linha de ajuste: vale o registro na trilha.
        caixa
          ? supabase.from('reconciliation_log').select('id').in('acao', ['ajustou_caixa', 'contou_caixa']).limit(1)
          : Promise.resolve({ data: [], error: null }),
      ]);
      if (contagem.error) throw contagem.error;
      return montarSaldos(conexoes, ultimas.flat(), linhas as never, (contagem.data ?? []).length > 0);
    },
    staleTime: 60_000,
  });
}
