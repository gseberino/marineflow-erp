// O Extrato de UMA conta, com saldo dia a dia, e o que o sistema lançou sozinho.
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export interface LinhaDoExtrato {
  id: string;
  data: string;
  descricao: string | null;
  contraparte: string | null;
  documento: string | null;
  tipo: 'credit' | 'debit';
  /** Com sinal: entrada positiva, saída negativa. */
  valor: number;
  /** Saldo depois desta linha; null enquanto a conta não tem linha de base. */
  saldo_apos: number | null;
  situacao: 'nova' | 'lancada' | 'conciliada' | 'fora' | 'sem_rastro';
  pendente: boolean;
  lancamento_tipo: 'payable' | 'receivable' | null;
  lancamento_id: string | null;
  lancamento_descricao: string | null;
  categoria: string | null;
  quem: string | null;
  tipo_fora: string | null;
  motivo_fora: string | null;
  proposta_id: string | null;
}

/**
 * Linhas de uma conta no período, da mais recente para a mais antiga. O saldo é o MESMO
 * cálculo da conferência de saldo (base + soma com sinal), feito no banco — a tela e o
 * alerta não têm como discordar.
 */
export function useExtratoDaConta(conexaoId: string | null, de: string, ate: string) {
  return useQuery({
    queryKey: ['extrato-da-conta', conexaoId, de, ate],
    enabled: !!conexaoId,
    queryFn: async (): Promise<LinhaDoExtrato[]> => {
      const { data, error } = await supabase.rpc('extrato_da_conta' as never, {
        p_conexao: conexaoId, p_de: de, p_ate: ate,
      } as never);
      if (error) throw error;
      return ((data ?? []) as unknown as LinhaDoExtrato[]).map((l) => ({
        ...l, valor: Number(l.valor), saldo_apos: l.saldo_apos == null ? null : Number(l.saldo_apos),
      }));
    },
    staleTime: 30_000,
  });
}

export interface LancadoSozinho {
  id: string;
  title: string;
  suggested_amount: number;
  suggested_category: string | null;
  suggested_date: string | null;
  decided_at: string | null;
  decision_note: string | null;
  /**
   * 'boleto' (22/11/2026): não é lançamento novo — a conta de um boleto conhecido foi baixada pelo pagamento no banco.
   * Desde 24/11/2026 a mesma marca vale para a conta a RECEBER de NF-e com boleto, baixada pelo crédito do boleto.
   */
  automatica: 'regra' | 'confianca' | 'boleto';
  /**
   * O tipo da proposta (24/11/2026). Na baixa pelo boleto, 'create_receivable' é a marca de RECEBER — a mesma leitura
   * da ferramenta do assistente e do resumo do dia; proposta sem kind é conta a pagar, como sempre foi.
   */
  kind?: string | null;
  created_payable_id: string | null;
  created_receivable_id: string | null;
  bank_transaction_id?: string | null;
  /** Baixa pelo boleto: a conta (que já existia) casada com a linha do banco — é ela que se desfaz. */
  conta_baixada_id?: string | null;
  /**
   * De que lado é a conta baixada (24/11/2026): a pagar ou a receber. O Desfazer precisa do lado certo — conta a receber
   * mandada como 'payable' voltava "Lançamento não encontrado" — e o total do cabeçalho não pode somar entrada com saída.
   */
  conta_baixada_tipo?: TipoDaContaBaixada | null;
  bank_transactions?: { bank_connection_id: string | null } | null;
}

export type TipoDaContaBaixada = 'payable' | 'receivable';

/** Conta casada com uma linha do banco, com a tabela de onde veio (payables → 'payable', receivables → 'receivable'). */
export interface ContaCasada {
  id: string;
  bank_transaction_id: string | null;
  tipo: TipoDaContaBaixada;
}

/** Uma linha do registro da conciliação (public.reconciliation_log) de uma linha do banco. */
export interface RegistroDaLinha {
  bank_transaction_id: string | null;
  receivable_id: string | null;
  acao: string;
  detalhe: string | null;
}

/** Como a função do banco marca, no registro da conciliação, a baixa que ela fez sozinha. */
const DETALHE_DA_BAIXA_SOZINHA = 'Baixa automática pelo boleto';

/** A marca de RECEBER da baixa pelo boleto: a proposta é de entrada. Sem kind (dado antigo) é conta a pagar. */
const ehMarcaDeReceber = (l: LancadoSozinho) => l.automatica === 'boleto' && l.kind === 'create_receivable';

/**
 * A baixa pelo boleto não cria conta: a que foi baixada é a que está casada com a linha do banco. A baixa já desfeita
 * (por aqui, em Contas a pagar, em Contas a receber ou pelo assistente) não tem mais conta casada e sai da lista.
 * 24/11/2026: a conta casada pode ser a pagar ou a receber, e o lado vai junto com o id.
 *
 * 24/11/2026 (revisão) — a marca que revivia: o desfazer não toca na proposta, que fica aprovada com 'boleto' para
 * sempre. Se o dono casasse à mão a mesma linha do banco com uma conta (ou a lançasse como receita nova), a marca
 * antiga voltava para cá dizendo "recebimento baixado sozinho", com o cliente da nota antiga e um Desfazer de um
 * clique em cima de uma decisão dele. Por isso a marca de RECEBER só vale quando o registro da linha do banco tem
 * EXATAMENTE UMA linha, e ela é a da própria baixa: 'conciliou', detalhe "Baixa automática pelo boleto…" e a conta a
 * receber igual à casada. É exato porque a função do banco nunca baixa linha que já tenha qualquer registro: um
 * segundo registro (desfez, casou de novo, cancelou) quer dizer que alguém mexeu depois. O mesmo critério vale na
 * ferramenta do assistente e no resumo do dia. A marca de conta a PAGAR não muda: continua valendo pela conta casada.
 */
export function comContaBaixada(linhas: LancadoSozinho[], casadas: ContaCasada[], registros: RegistroDaLinha[] = []): LancadoSozinho[] {
  const contaDaLinha = new Map(casadas.filter((c) => c.bank_transaction_id).map((c) => [String(c.bank_transaction_id), c]));
  const registrosDaLinha = new Map<string, RegistroDaLinha[]>();
  for (const r of registros) {
    // A faxina da própria varredura ('tirou_da_fila_ja_lancada': duas rodadas quase juntas propõem a mesma linha e a segunda
    // fecha a proposta que sobrou) não é mão de ninguém: não conta, senão a baixa viva sumia daqui sem o dono mexer.
    if (!r.bank_transaction_id || r.acao === 'tirou_da_fila_ja_lancada') continue;
    const linha = String(r.bank_transaction_id);
    registrosDaLinha.set(linha, [...(registrosDaLinha.get(linha) ?? []), r]);
  }
  const contaDoRecebimento = (linha: string): ContaCasada | undefined => {
    const doRegistro = registrosDaLinha.get(linha) ?? [];
    if (doRegistro.length !== 1) return undefined;
    const [r] = doRegistro;
    if (r.acao !== 'conciliou' || !(r.detalhe ?? '').startsWith(DETALHE_DA_BAIXA_SOZINHA) || !r.receivable_id) return undefined;
    return casadas.find((c) => c.tipo === 'receivable' && c.id === r.receivable_id
      && c.bank_transaction_id != null && String(c.bank_transaction_id) === linha);
  };
  const contaDa = (l: LancadoSozinho): ContaCasada | undefined =>
    (ehMarcaDeReceber(l) ? contaDoRecebimento(String(l.bank_transaction_id)) : contaDaLinha.get(String(l.bank_transaction_id)));
  return linhas
    .filter((l) => l.automatica !== 'boleto' || contaDa(l) !== undefined)
    .map((l) => {
      if (l.automatica !== 'boleto') return l;
      const conta = contaDa(l);
      return { ...l, conta_baixada_id: conta?.id ?? null, conta_baixada_tipo: conta?.tipo ?? null };
    });
}

/**
 * As contas casadas com estas linhas do banco, dos DOIS lados (24/11/2026). Antes só se procurava em payables, e o
 * recebimento baixado pelo boleto sumia da lista — baixa feita sem clique tem de ficar à vista e com Desfazer.
 * O erro das duas leituras é conferido: leitura que falha calada faria a baixa parecer desfeita.
 */
export async function contasCasadasComAsLinhas(linhasDoBanco: string[]): Promise<ContaCasada[]> {
  const [aPagar, aReceber] = await Promise.all([
    supabase.from('payables').select('id, bank_transaction_id').in('bank_transaction_id', linhasDoBanco),
    supabase.from('receivables').select('id, bank_transaction_id').in('bank_transaction_id', linhasDoBanco),
  ]);
  if (aPagar.error) throw aPagar.error;
  if (aReceber.error) throw aReceber.error;
  const comTipo = (contas: Array<{ id: string; bank_transaction_id: string | null }> | null, tipo: TipoDaContaBaixada): ContaCasada[] =>
    (contas ?? []).map((c) => ({ id: c.id, bank_transaction_id: c.bank_transaction_id, tipo }));
  // A conta a pagar por último: se uma linha aparecer casada dos dois lados, vale a conta a pagar, como era antes.
  return [...comTipo(aReceber.data, 'receivable'), ...comTipo(aPagar.data, 'payable')];
}

/** Acima disto o PostgREST corta a resposta (max-rows), e registro cortado não prova "exatamente um". */
const TETO_DE_LINHAS_DA_LEITURA = 1000;

/**
 * O registro da conciliação destas linhas do banco, INTEIRO — sem filtro de ação, porque a pergunta é "esta linha tem
 * um registro só?" (24/11/2026, a marca que revivia: ver comContaBaixada). Admin e financeiro leem a tabela pela
 * policy "financeiro le a trilha", a mesma régua da fila. O erro é conferido, e leitura cortada no teto também é erro:
 * lida pela metade, a linha desfeita e casada à mão pareceria ter só o registro da baixa.
 */
export async function registrosDasLinhas(linhasDoBanco: string[]): Promise<RegistroDaLinha[]> {
  const { data, error } = await supabase.from('reconciliation_log')
    .select('bank_transaction_id, receivable_id, acao, detalhe').in('bank_transaction_id', linhasDoBanco);
  if (error) throw error;
  const registros = (data ?? []) as RegistroDaLinha[];
  if (registros.length >= TETO_DE_LINHAS_DA_LEITURA) {
    throw new Error('O registro da conciliação veio cortado: não dá para dizer quais recebimentos continuam baixados pelo boleto.');
  }
  return registros;
}

/** O que foi lançado sem clique nos últimos 30 dias — para conferir e desfazer. */
export function useLancadosSozinhos() {
  return useQuery({
    queryKey: ['lancados-sozinhos'],
    queryFn: async (): Promise<LancadoSozinho[]> => {
      const desde = new Date(Date.now() - 30 * 86_400_000).toISOString();
      const { data, error } = await supabase
        .from('finance_review_queue')
        .select(`id, title, suggested_amount, suggested_category, suggested_date, decided_at, decision_note,
                 automatica, kind, created_payable_id, created_receivable_id, bank_transaction_id,
                 bank_transactions!finance_review_queue_bank_transaction_id_fkey (bank_connection_id)`)
        .not('automatica', 'is', null)
        .eq('status', 'approved')
        .gte('decided_at', desde)
        .order('decided_at', { ascending: false })
        .limit(200);
      if (error) throw error;
      const linhas = (data ?? []) as unknown as LancadoSozinho[];
      const doBoleto = linhas.filter((l) => l.automatica === 'boleto' && l.bank_transaction_id).map((l) => String(l.bank_transaction_id));
      if (doBoleto.length === 0) return linhas;
      // O registro só é lido para as marcas de RECEBER (24/11/2026): sem nenhuma, a leitura sai como sempre saiu.
      const deReceber = linhas.filter((l) => ehMarcaDeReceber(l) && l.bank_transaction_id).map((l) => String(l.bank_transaction_id));
      const [casadas, registros] = await Promise.all([
        contasCasadasComAsLinhas(doBoleto),
        deReceber.length > 0 ? registrosDasLinhas(deReceber) : Promise.resolve([] as RegistroDaLinha[]),
      ]);
      return comContaBaixada(linhas, casadas, registros);
    },
    staleTime: 30_000,
  });
}
