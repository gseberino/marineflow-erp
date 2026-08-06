// Caixa de entrada financeira: propostas do sistema aguardando decisão do gestor.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

/** Acima deste valor a proposta sai do lote e exige olhar individual (decisão do usuário). */
export const LIMITE_LOTE = 500;

export interface PropostaFinanceira {
  id: string;
  kind: 'create_payable' | 'create_receivable' | 'internal_transfer' | 'categorize' | 'anomaly';
  status: 'pending' | 'approved' | 'rejected' | 'superseded';
  bank_transaction_id: string | null;
  related_transaction_id: string | null;
  title: string;
  reasoning: string | null;
  confidence: number;
  suggested_amount: number | null;
  suggested_date: string | null;
  suggested_category: string | null;
  suggested_description: string | null;
  suggested_supplier_id: string | null;
  dre_group: string | null;
  /** Regra que classificou esta proposta — permite auditar a regra pelo resultado. */
  applied_rule_id: string | null;
  suggested_payee_id: string | null;
  suggested_service_order_id: string | null;
  suggested_purchase_order_id: string | null;
  created_at: string;
  /** Identificação vinda do extrato, para decidir sem abrir o internet banking. */
  bank_transactions?: {
    counterparty_name: string | null;
    counterparty_document: string | null;
    counterparty_bank: string | null;
    counterparty_branch: string | null;
    counterparty_account: string | null;
    payment_method: string | null;
    payment_reason: string | null;
    merchant_name: string | null;
    merchant_document: string | null;
    installment_label: string | null;
    pix_end_to_end_id: string | null;
    description: string | null;
    /** 'bank' = conta corrente, 'credit_card' = fatura. Muda onde se confere o gasto. */
    source_type: string | null;
    /** Id da transação no provedor — é a chave que impede a mesma entrar duas vezes. */
    bank_ref_id: string | null;
  } | null;
}

export interface Correcao {
  category?: string;
  description?: string;
  amount?: number;
  date?: string;
  /** A quem a despesa pertence, quando não é a um fornecedor (sócio, diarista, prestador). */
  payeeId?: string | null;
  /** OS a que a compra pertence — é o que dá custo e margem reais por serviço. */
  serviceOrderId?: string | null;
  /** OC que este pagamento quita. */
  purchaseOrderId?: string | null;
}

/**
 * Mesma leitura de corpo de erro usada na conciliação: `functions.invoke` devolve só
 * "non-2xx status code", e o motivo real (fornecedor inválido, cliente faltando) fica no
 * corpo. Sem isto o gestor vê "erro" e não sabe o que corrigir.
 */
async function invokeReview<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke('finance-review', { body });

  if (error) {
    const resposta = (error as any)?.context as Response | undefined;

    // 546 é o worker derrubado por limite de recursos: a resposta vem VAZIA, então tentar
    // ler o corpo não devolve nada e o gestor via só "non-2xx status code" — uma mensagem
    // que não diz nem o que aconteceu nem o que fazer.
    if (resposta?.status === 546 || resposta?.status === 504) {
      throw new Error(
        'A varredura passou do limite de processamento da função. O que já foi analisado '
        + 'ficou salvo — repita a ação para continuar de onde parou.',
      );
    }

    if (resposta && typeof resposta.json === 'function') {
      try {
        const corpo = await resposta.json();
        if (corpo?.error) {
          throw new Error(corpo.detail ? `${corpo.error}: ${corpo.detail}` : String(corpo.error));
        }
      } catch (e) {
        if (e instanceof Error && e.message && !e.message.includes('non-2xx')) throw e;
      }
    }
    throw error;
  }
  if ((data as any)?.error) throw new Error((data as any).error);
  return data as T;
}

/** Fila pendente, mais confiáveis primeiro — o lote começa pelo que é seguro aprovar em bloco. */
export function useFinanceReviewQueue() {
  return useQuery({
    queryKey: ['finance-review-queue'],
    queryFn: async (): Promise<PropostaFinanceira[]> => {
      const { data, error } = await supabase
        .from('finance_review_queue')
        // Traz a identificação da transação junto: sem ela, decidir exige abrir o
        // internet banking em outra aba, que é exatamente o trabalho que esta tela existe
        // para eliminar.
        //
        // A chave estrangeira vai ESCRITA no join. Esta tabela chega a `bank_transactions`
        // por dois caminhos — a transação da proposta e a segunda perna de uma
        // transferência entre contas —, e diante de dois caminhos a API recusa o join
        // inteiro (PGRST201) em vez de escolher um. Sem o nome da chave, a consulta falhava
        // e a fila aparecia VAZIA com 1.178 propostas dentro dela.
        .select(`*, bank_transactions!finance_review_queue_bank_transaction_id_fkey (
          counterparty_name, counterparty_document,
          counterparty_bank, counterparty_branch, counterparty_account, payment_method,
          payment_reason, merchant_name, merchant_document, installment_label,
          pix_end_to_end_id, description, source_type, bank_ref_id )`)
        .eq('status', 'pending')
        .order('confidence', { ascending: false })
        .order('suggested_amount', { ascending: false })
        .limit(500);
      if (error) throw error;
      return (data ?? []) as unknown as PropostaFinanceira[];
    },
    staleTime: 30_000,
  });
}

/**
 * Só a CONTAGEM da fila, para o menu.
 *
 * Consulta separada de propósito: o menu monta em toda tela do sistema e não pode arrastar
 * as 500 linhas da fila junto. `head: true` traz o total sem trazer linha nenhuma.
 */
export function useFinanceReviewCount() {
  return useQuery({
    queryKey: ['finance-review-count'],
    queryFn: async (): Promise<number> => {
      const { count, error } = await supabase
        .from('finance_review_queue')
        .select('id', { count: 'exact', head: true })
        .eq('status', 'pending');
      if (error) throw error;
      return count ?? 0;
    },
    staleTime: 60_000,
  });
}

/**
 * Teto de rodadas do mutirão. Existe como cinto de segurança, não como limite real: com
 * 200 transações por rodada isso cobre 4.000 saídas atrasadas, muito acima do atraso
 * conhecido. O que encerra o mutirão de verdade é `restantes` chegar a zero.
 */
const MAX_RODADAS = 20;

export function useGerarPropostas() {
  const qc = useQueryClient();
  type Resposta = {
    ok: boolean; criadas: number; message: string;
    elegiveis_lote?: number;
    /** Transações antigas que sobraram para a próxima chamada. */
    restantes?: number;
  };

  return useMutation<Resposta, Error, boolean>({
    /**
     * O histórico vem em rodadas porque a função tem orçamento de CPU por chamada, e o
     * atraso acumulado é de mais de mil saídas: pedir tudo de uma vez matava o worker e
     * voltava "non-2xx status code" sem nada feito. Cada rodada resolve um pedaço e o
     * trabalho fica salvo, então parar no meio custa a rodada corrente, não o mutirão.
     */
    mutationFn: async (incluirHistorico: boolean) => {
      const aviso = incluirHistorico ? 'mutirao-historico' : undefined;
      let acumulado = 0;
      let rodadas = 0;
      let r: Resposta;

      do {
        r = await invokeReview<Resposta>({ action: 'generate', incluir_historico: incluirHistorico });
        acumulado += Number(r.criadas ?? 0);
        rodadas += 1;

        // A fila cresce à vista: esperar o fim para mostrar qualquer coisa faria um mutirão
        // de vários minutos parecer travado.
        qc.invalidateQueries({ queryKey: ['finance-review-queue'] });
        qc.invalidateQueries({ queryKey: ['finance-review-count'] });

        if (Number(r.restantes ?? 0) <= 0) break;
        // Rodada sem criar nada com trabalho declarado: algo travou, e repetir só repetiria
        // o travamento.
        if (Number(r.criadas ?? 0) === 0) break;

        toast.loading(`Varrendo o histórico — ${acumulado} prontas, faltam ${r.restantes}`, { id: aviso });
      } while (rodadas < MAX_RODADAS);

      if (aviso) toast.dismiss(aviso);
      return rodadas > 1 ? { ...r, criadas: acumulado, message: `${acumulado} transação(ões) do histórico processada(s)` } : r;
    },
    onSuccess: (r) => {
      toast.success(r.message);
      qc.invalidateQueries({ queryKey: ['finance-review-queue'] });
      qc.invalidateQueries({ queryKey: ['finance-review-count'] });
    },
    onError: (e: Error) => {
      toast.dismiss('mutirao-historico');
      toast.error(e.message || 'Não foi possível gerar as propostas');
    },
  });
}

/**
 * Reavalia as propostas que já estão na fila com as regras de hoje.
 *
 * Sem isto, ensinar uma regra só valia para o futuro: as 40 compras do mesmo fornecedor
 * que já estavam enfileiradas continuavam pedindo correção manual — justamente as linhas
 * que a regra foi criada para resolver.
 */
export function useReaplicarRegras() {
  const qc = useQueryClient();
  type Resposta = { ok: boolean; atualizadas: number; avaliadas: number; por_regra: number; message: string };
  return useMutation<Resposta, Error, { silencioso?: boolean } | void>({
    mutationFn: () => invokeReview<Resposta>({ action: 'reclassify' }),
    onSuccess: (r, v) => {
      // Quando roda sozinha depois de salvar uma regra, só avisa se ALGO mudou: "nenhuma
      // proposta mudou" é ruído logo após o gestor ter feito outra coisa.
      if (!(v && 'silencioso' in v && v.silencioso) || r.atualizadas > 0) {
        toast.success(r.message);
      }
      qc.invalidateQueries({ queryKey: ['finance-review-queue'] });
    },
    onError: (e: Error) => toast.error(e.message || 'Não foi possível reaplicar as regras'),
  });
}

/**
 * Pede à IA que classifique o que nem regra nem memória alcançaram.
 *
 * A memória só sabe o que já foi decidido; o resto são estabelecimentos que aparecem pela
 * primeira vez, e nenhuma regra vai adivinhá-los. Custa uma chamada de modelo para a fila
 * inteira, e a sugestão entra marcada como vinda da IA — para quem revisa saber o peso do
 * que está lendo.
 */
export function useClassificarComIA() {
  const qc = useQueryClient();
  type Resposta = { ok: boolean; sugeridas: number; estabelecimentos: number; message: string };
  return useMutation<Resposta, Error, void>({
    mutationFn: () => invokeReview<Resposta>({ action: 'classify_ai' }),
    onSuccess: (r) => {
      toast.success(r.message);
      qc.invalidateQueries({ queryKey: ['finance-review-queue'] });
    },
    onError: (e: Error) => toast.error(e.message || 'Não foi possível classificar com IA'),
  });
}

/** Um motivo pelo qual transações saíram da fila, com o que ele levou junto. */
export interface GrupoIgnorado {
  kind: string;
  rotulo: string;
  motivo: string;
  transacoes: Array<{
    id: string; transaction_date: string; description: string; amount: number;
    counterparty_name: string | null; dismissed_at: string | null;
  }>;
  total: number;
}

export const ROTULO_DA_IGNORADA: Record<string, string> = {
  duplicata: 'Duplicata da importação',
  fatura_cartao: 'Pagamento de fatura de cartão',
  transferencia: 'Transferência entre contas próprias',
  mecanica_cartao: 'Mecânica do cartão (Pix no Crédito, estorno, ajuste)',
  parcela: 'Parcela de compra parcelada',
  manual: 'Ignorada à mão',
};

/**
 * O livro das ignoradas.
 *
 * Sem esta lista, sair da fila era sumir: 380 transações (R$ 370 mil) saíram de vista com
 * um texto solto e nada mais — sem quem, sem quando, sem como voltar. Cada caso estava
 * certo e o conjunto era inauditável, o que dá no mesmo que estar errado para quem precisa
 * confiar no número.
 */
export function useIgnoradas() {
  return useQuery({
    queryKey: ['bank-transactions-ignoradas'],
    queryFn: async (): Promise<GrupoIgnorado[]> => {
      const { data, error } = await supabase
        .from('bank_transactions')
        .select('id, transaction_date, description, amount, counterparty_name, dismissed_reason, dismissed_kind, dismissed_at')
        .not('dismissed_reason', 'is', null)
        .order('transaction_date', { ascending: false })
        .limit(1000);
      if (error) throw error;

      const porTipo = new Map<string, GrupoIgnorado>();
      for (const t of (data ?? []) as any[]) {
        const kind = t.dismissed_kind ?? 'manual';
        const g = porTipo.get(kind) ?? {
          kind,
          rotulo: ROTULO_DA_IGNORADA[kind] ?? kind,
          motivo: t.dismissed_reason ?? '',
          transacoes: [],
          total: 0,
        };
        g.transacoes.push({
          id: t.id, transaction_date: t.transaction_date, description: t.description,
          amount: Number(t.amount), counterparty_name: t.counterparty_name,
          dismissed_at: t.dismissed_at,
        });
        g.total += Number(t.amount);
        porTipo.set(kind, g);
      }
      return [...porTipo.values()].sort((a, b) => b.transacoes.length - a.transacoes.length);
    },
    staleTime: 30_000,
  });
}

/**
 * Devolve à fila o que tinha sido ignorado, desfazendo o efeito.
 *
 * Não é só remarcar a linha: aprovar uma compra em 10x tirou nove pernas de vista E criou
 * um lançamento pela compra inteira. Devolver a perna sem desfazer o lançamento contaria o
 * mesmo dinheiro duas vezes — por isso o alcance é calculado no servidor.
 */
export function useDesfazerIgnorada() {
  const qc = useQueryClient();
  type Resposta = {
    ok: boolean; transacoes: number; lancamentos_apagados: number;
    propostas_reabertas: number; lancamentos_preservados: string[]; message: string;
  };
  return useMutation<Resposta, Error, string[]>({
    mutationFn: (ids) => invokeReview<Resposta>({ action: 'undismiss', ids }),
    onSuccess: (r) => {
      if (r.lancamentos_preservados?.length) {
        toast.warning(r.message, { description: r.lancamentos_preservados.slice(0, 3).join(' · ') });
      } else toast.success(r.message);
      for (const k of [['bank-transactions-ignoradas'], ['bank-transactions'], ['finance-review-queue'],
        ['finance-review-count'], ['payables'], ['receivables'], ['financial-summary']]) {
        qc.invalidateQueries({ queryKey: k });
      }
    },
    onError: (e: Error) => toast.error(e.message || 'Não foi possível desfazer'),
  });
}

export function useAprovarPropostas() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { ids: string[]; overrides?: Record<string, Correcao> }) =>
      invokeReview<{ ok: boolean; aprovadas: number; falhas: string[]; message: string }>({
        action: 'approve', ids: v.ids, overrides: v.overrides ?? {},
      }),

    /**
     * O que foi aprovado sai da lista NA HORA, sem esperar o servidor.
     *
     * Aprovar um grupo de 23 são 23 lançamentos criados um a um lá atrás, e a tela ficava
     * parada até o último terminar. Mas a decisão é do gestor e já foi tomada no clique:
     * o que falta é trabalho de escrita, não dúvida sobre o resultado. Fazer a fila
     * esperar por isso transforma uma decisão instantânea numa espera de segundos, a cada
     * grupo, dezenas de vezes.
     *
     * Se o servidor recusar, a lista volta exatamente como estava e o erro aparece — o
     * otimismo é sobre o TEMPO da resposta, não sobre ignorar o que ela diz.
     */
    onMutate: async (v) => {
      await qc.cancelQueries({ queryKey: ['finance-review-queue'] });
      const anterior = qc.getQueryData<PropostaFinanceira[]>(['finance-review-queue']);
      if (anterior) {
        const saindo = new Set(v.ids);
        qc.setQueryData<PropostaFinanceira[]>(
          ['finance-review-queue'],
          anterior.filter((p) => !saindo.has(p.id)),
        );
      }
      return { anterior };
    },

    onSuccess: (r) => {
      if (r.falhas?.length) toast.warning(r.message, { description: r.falhas.slice(0, 3).join(' · ') });
      else toast.success(r.message);
      // Aprovar cria despesa e baixa a transação: as outras listas mudam também.
      for (const k of [['payables'], ['receivables'], ['bank-transactions'], ['financial-summary'], ['finance-review-count']]) {
        qc.invalidateQueries({ queryKey: k });
      }
    },

    onError: (e: Error, _v, ctx) => {
      if (ctx?.anterior) qc.setQueryData(['finance-review-queue'], ctx.anterior);
      toast.error(e.message || 'Não foi possível aprovar');
    },

    // A verdade vem do servidor no fim, inclusive quando algumas linhas falharam e
    // continuam pendentes: sem isto elas sumiriam da tela sem terem sido lançadas.
    onSettled: () => qc.invalidateQueries({ queryKey: ['finance-review-queue'] }),
  });
}

/**
 * Cria uma categoria de despesa sem sair da tela onde ela fez falta.
 *
 * Nasce no mesmo grupo do DRE que a proposta deduziu: uma categoria sem grupo fica fora do
 * resultado, e o gestor não teria como perceber que o número parou de fechar.
 */
export function useCriarCategoriaDespesa() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { name: string; dre_group: string | null; type?: 'payable' | 'receivable' }) => {
      const { data, error } = await supabase
        .from('financial_categories')
        .insert({
          name: v.name,
          type: v.type ?? 'payable',
          dre_group: v.dre_group ?? 'despesa_operacional',
          active: true,
          sort_order: 900,   // no fim da lista: o que é novo ainda não provou seu lugar
        } as never)
        .select('name')
        .single();
      if (error) throw error;
      return (data as any).name as string;
    },
    onSuccess: (nome) => {
      toast.success(`Categoria "${nome}" criada`);
      qc.invalidateQueries({ queryKey: ['financial-categories'] });
    },
    onError: (e: Error) => {
      const msg = /duplicate key|financial_categories_nome_tipo/i.test(e.message)
        ? 'Já existe uma categoria de despesa com esse nome.'
        : e.message || 'Não foi possível criar a categoria';
      toast.error(msg);
    },
  });
}

/** Uma regra que o gestor ensinou — ou que a IA propôs e aguarda o aceite dele. */
export interface RegraFinanceira {
  id: string;
  match_type: 'document' | 'supplier' | 'counterparty' | 'text';
  match_value: string;
  direction: 'debit' | 'credit' | 'any';
  min_amount: number | null;
  max_amount: number | null;
  set_category: string | null;
  set_dre_group: string | null;
  set_supplier_id: string | null;
  autonomy: 'suggest' | 'apply';
  origin: 'user' | 'ai';
  status: 'active' | 'paused' | 'proposed' | 'rejected';
  reasoning: string | null;
  note: string | null;
  times_applied: number;
  last_applied_at: string | null;
  created_at: string;
}

export function useFinanceRules() {
  return useQuery({
    queryKey: ['finance-rules'],
    queryFn: async (): Promise<RegraFinanceira[]> => {
      const { data, error } = await supabase
        .from('finance_rules')
        .select('*')
        .in('status', ['active', 'paused', 'proposed'])
        // Propostas primeiro: são as que pedem uma decisão, não as que já trabalham.
        .order('status', { ascending: true })
        .order('times_applied', { ascending: false })
        .limit(300);
      if (error) throw error;
      return (data ?? []) as unknown as RegraFinanceira[];
    },
    staleTime: 60_000,
  });
}

/** Um lançamento que embasa a regra — o que faz aceitar deixar de ser aposta. */
export interface LancamentoDaRegra {
  id: string;
  description: string;
  amount: number;
  issue_date: string;
  expense_category: string | null;
  supplier_name: string | null;
  fornecedor: string | null;
  contraparte: string | null;
  documento: string | null;
  banco: string | null;
  meio: string | null;
}

/**
 * As despesas que a regra usou como evidência.
 *
 * A sugestão diz "as últimas 5 foram lançadas como Ferramentas, sem exceção" — mas sem ver
 * QUAIS, quanto e para quem, aceitar é confiar num resumo. E o resumo esconde justamente o
 * que muda a decisão: um dos cinco pode ser de outro fornecedor com nome parecido, ou de
 * valor tão diferente que denuncia uma classificação apressada.
 */
export function useLancamentosDaRegra(regra: RegraFinanceira | null) {
  return useQuery({
    queryKey: ['lancamentos-da-regra', regra?.id, regra?.match_type, regra?.match_value],
    enabled: !!regra,
    queryFn: async (): Promise<LancamentoDaRegra[]> => {
      if (!regra) return [];

      let q = supabase
        .from('payables')
        .select(`id, description, amount, issue_date, expense_category, supplier_name,
                 suppliers ( name ),
                 bank_transactions ( counterparty_name, counterparty_document,
                                     counterparty_bank, payment_method )`)
        .order('issue_date', { ascending: false })
        .limit(25);

      // Cada tipo de regra procura por um caminho diferente — o mesmo caminho que ela usa
      // para reconhecer, senão o histórico mostraria coisa que a regra não pegaria.
      if (regra.match_type === 'supplier') {
        q = q.eq('supplier_id', regra.match_value);
      } else if (regra.match_type === 'counterparty') {
        q = q.ilike('supplier_name', `%${regra.match_value}%`);
      } else if (regra.match_type === 'text') {
        q = q.ilike('description', `%${regra.match_value}%`);
      } else {
        // Por documento: o vínculo está na transação bancária, não no lançamento.
        const { data: txs } = await supabase
          .from('bank_transactions')
          .select('id')
          .eq('counterparty_document', regra.match_value.replace(/\D/g, ''))
          .limit(50);
        const ids = (txs ?? []).map((t: any) => t.id);
        if (ids.length === 0) return [];
        q = q.in('bank_transaction_id', ids);
      }

      const { data, error } = await q;
      if (error) throw error;

      return ((data ?? []) as any[]).map((p) => ({
        id: p.id,
        description: p.description,
        amount: Number(p.amount),
        issue_date: p.issue_date,
        expense_category: p.expense_category,
        supplier_name: p.supplier_name,
        fornecedor: p.suppliers?.name ?? null,
        contraparte: p.bank_transactions?.counterparty_name ?? null,
        documento: p.bank_transactions?.counterparty_document ?? null,
        banco: p.bank_transactions?.counterparty_bank ?? null,
        meio: p.bank_transactions?.payment_method ?? null,
      }));
    },
    staleTime: 60_000,
  });
}

export function useSalvarRegra() {
  const qc = useQueryClient();
  const reaplicar = useReaplicarRegras();
  return useMutation({
    mutationFn: async (r: Partial<RegraFinanceira> & { id?: string }) => {
      if (r.id) {
        const { error } = await supabase.from('finance_rules').update(r as never).eq('id', r.id);
        if (error) throw error;
        return r.id;
      }
      const { data, error } = await supabase
        .from('finance_rules').insert(r as never).select('id').single();
      if (error) throw error;
      return (data as any).id as string;
    },
    onSuccess: () => {
      toast.success('Regra salva');
      qc.invalidateQueries({ queryKey: ['finance-rules'] });
      // Ensinar a regra e ver a fila obedecer é o mesmo ato. Deixar isso para um botão
      // separado é pedir que o gestor descubra sozinho que a regra existe mas não valeu
      // para nada do que está na tela dele.
      reaplicar.mutate({ silencioso: true });
    },
    onError: (e: Error) => {
      // Violação do índice de alvo único vira a explicação real do problema: já existe
      // uma regra viva para o mesmo alvo, e duas instruções para o mesmo fato dariam
      // resultado imprevisível.
      const msg = /finance_rules_uma_por_alvo|duplicate key/i.test(e.message)
        ? 'Já existe uma regra para este mesmo alvo. Edite a existente em vez de criar outra.'
        : e.message || 'Não foi possível salvar a regra';
      toast.error(msg);
    },
  });
}

export function useMudarStatusRegra() {
  const qc = useQueryClient();
  const reaplicar = useReaplicarRegras();
  return useMutation({
    mutationFn: async (v: { id: string; status: RegraFinanceira['status'] }) => {
      const { error } = await supabase
        .from('finance_rules').update({ status: v.status } as never).eq('id', v.id);
      if (error) throw error;
      return v;
    },
    onSuccess: (v) => {
      qc.invalidateQueries({ queryKey: ['finance-rules'] });
      // Aceitar uma regra proposta é o momento em que ela passa a valer — inclusive para o
      // que já está na fila. Pausar também reavalia: a fila deve parar de refletir uma
      // regra que o gestor acabou de desligar.
      if (v.status === 'active' || v.status === 'paused') reaplicar.mutate({ silencioso: true });
    },
    onError: (e: Error) => toast.error(e.message),
  });
}

/** Pede ao sistema que olhe as decisões já tomadas e proponha regras. */
export function useProporRegras() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () => invokeReview<{ ok: boolean; propostas: number; message: string }>({ action: 'suggest_rules' }),
    onSuccess: (r) => {
      toast.success(r.message);
      qc.invalidateQueries({ queryKey: ['finance-rules'] });
    },
    onError: (e: Error) => toast.error(e.message),
  });
}

/**
 * Marca a transação como duplicata e descarta a proposta que nasceu dela.
 *
 * As duas coisas juntas de propósito: só recusar a proposta deixaria a transação na fila
 * para ser proposta de novo na próxima varredura.
 */
export function useMarcarDuplicata() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { propostaId: string; bankTransactionId: string | null }) => {
      if (v.bankTransactionId) {
        const { error } = await supabase.from('bank_transactions')
          .update({ reconciled: true, dismissed_reason: 'Duplicata' } as never)
          .eq('id', v.bankTransactionId);
        if (error) throw error;
      }
      const { error: e2 } = await supabase.from('finance_review_queue')
        .update({ status: 'rejected', decision_note: 'Duplicata' } as never)
        .eq('id', v.propostaId);
      if (e2) throw e2;
    },
    onSuccess: () => {
      toast.success('Marcada como duplicata');
      qc.invalidateQueries({ queryKey: ['finance-review-queue'] });
      qc.invalidateQueries({ queryKey: ['bank-transactions'] });
    },
    onError: (e: Error) => toast.error(e.message),
  });
}

export function useRecusarPropostas() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { ids: string[]; note?: string }) =>
      invokeReview<{ ok: boolean; message: string }>({ action: 'reject', ids: v.ids, note: v.note }),
    onSuccess: (r) => {
      toast.success(r.message);
      qc.invalidateQueries({ queryKey: ['finance-review-queue'] });
    },
    onError: (e: Error) => toast.error(e.message || 'Não foi possível recusar'),
  });
}
