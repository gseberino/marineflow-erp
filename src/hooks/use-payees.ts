// Favorecidos: quem recebe dinheiro da empresa sem ser fornecedor nem usuário do sistema.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { lerEmPaginas } from '@/lib/ler-em-paginas';
import { totaisPorFavorecido, type LancamentoDoFavorecido } from '@/lib/favorecidos-no-ano';
import {
  mudancaDaRegra, regrasDaMudanca, SITUACOES_DA_MUDANCA, type RegraDoExtrato,
} from '../../supabase/functions/_shared/banking/pausa-do-favorecido';

export type TipoFavorecido = 'socio' | 'funcionario' | 'diarista' | 'prestador' | 'comissionado';

export interface Favorecido {
  id: string;
  name: string;
  kind: TipoFavorecido;
  document: string | null;
  phone: string | null;
  email: string | null;
  pix_key: string | null;
  pix_key_type: string | null;
  bank_name: string | null;
  bank_branch: string | null;
  bank_account: string | null;
  account_type: string | null;
  default_category: string | null;
  commission_percentage: number | null;
  notes: string | null;
  active: boolean;
}

export const ROTULO_TIPO: Record<TipoFavorecido, string> = {
  socio: 'Sócio',
  funcionario: 'Funcionário',
  diarista: 'Diarista',
  prestador: 'Prestador de serviço',
  comissionado: 'Comissionado',
};

/**
 * Categorias que pertencem a uma PESSOA, não a um fornecedor.
 *
 * É o que decide quando a tela pergunta "quem recebeu": perguntar sempre viraria ruído em
 * 90% das linhas, e nunca perguntar deixa R$ 36 mil de pró-labore sem dono.
 */
export const CATEGORIAS_COM_FAVORECIDO = [
  // Separados em 26/09/2026: pró-labore é despesa; retirada de lucro fica fora do resultado.
  'Pró-labore',
  'Retirada de sócio',
  'Salários e encargos',
  'Serviços de terceiros',
  // Serviço contratado para a própria HBR (27/09/2026): muitas vezes pago a uma pessoa, por CPF.
  'Serviços de terceiros para a empresa',
  // Diária de freelancer (28/09/2026): o Pix entra no saldo DELE — sem favorecido, some da conta.
  'Diárias de freelancers',
];

/** Categorias em que a compra costuma pertencer a um serviço específico. */
export const CATEGORIAS_COM_OS = [
  'Peças e materiais',
  // Era "Compras de Mercadorias", com M maiúsculo — o plano de contas escreve com m minúsculo,
  // então a pergunta da OS nunca aparecia para compra de mercadoria.
  'Compras de mercadorias',
  'Ferramentas e equipamentos',
  'Frete e importação',
];

export function usePayees(apenasAtivos = true) {
  return useQuery({
    queryKey: ['payees', apenasAtivos],
    queryFn: async (): Promise<Favorecido[]> => {
      let q = supabase.from('payees').select('*').order('name');
      if (apenasAtivos) q = q.eq('active', true);
      const { data, error } = await q;
      if (error) throw error;
      return (data ?? []) as unknown as Favorecido[];
    },
    staleTime: 5 * 60_000,
  });
}

/**
 * O que cada favorecido recebeu num ano, e o que ainda falta pagar (ver favorecidos-no-ano).
 * Lê TODOS os lançamentos do ano, não só os ligados a um favorecido: o que foi pago ao mesmo
 * CPF/CNPJ sem o favorecido ligado também é dele. Em páginas: o servidor corta em 1.000 linhas.
 */
export function useTotaisDosFavorecidos(ano: number) {
  return useQuery({
    queryKey: ['payees-totais-do-ano', ano],
    queryFn: async () => {
      const [favorecidos, lancamentos] = await Promise.all([
        supabase.from('payees').select('id, document'),
        lerEmPaginas((de, ate) => supabase
          .from('payables')
          .select(`id, payee_id, amount, paid_amount, status, expense_category, divisao_id,
                   suppliers!payables_supplier_id_fkey(name, cnpj_cpf),
                   bank_transactions!payables_bank_transaction_id_fkey(counterparty_document)`)
          .gte('issue_date', `${ano}-01-01`)
          .lte('issue_date', `${ano}-12-31`)
          .order('id')
          .range(de, ate)),
      ]);
      if (favorecidos.error) throw favorecidos.error;
      type Linha = {
        payee_id: string | null; amount: number; paid_amount: number | null; status: string | null; expense_category: string | null;
        divisao_id: string | null;
        suppliers: { name: string | null; cnpj_cpf: string | null } | null;
        bank_transactions: { counterparty_document: string | null } | null;
      };
      const linhas: LancamentoDoFavorecido[] = (lancamentos as unknown as Linha[]).map((l) => ({
        payee_id: l.payee_id, amount: l.amount, paid_amount: l.paid_amount, status: l.status, expense_category: l.expense_category,
        documento_da_linha: l.bank_transactions?.counterparty_document ?? null,
        documento_do_fornecedor: l.suppliers?.cnpj_cpf ?? null,
        nome_do_fornecedor: l.suppliers?.name ?? null,
        parte_de_divisao: !!l.divisao_id,
      }));
      return totaisPorFavorecido(linhas, (favorecidos.data ?? []) as Array<{ id: string; document: string | null }>);
    },
    staleTime: 5 * 60_000,
  });
}

/**
 * O que vai para o banco ao salvar um favorecido: SÓ os campos enviados (07/10/2026).
 *
 * Antes, `document` ausente virava null — e o botão Desativar/Reativar da lista, que manda só
 * { id, active }, apagava o CPF/CNPJ de quem era desativado. Sem documento o favorecido some do
 * casamento pelo extrato e do "pelo mesmo CPF/CNPJ" dos totais do ano.
 * Documento só com dígitos: é assim que ele casa com o extrato, onde vem sem máscara.
 */
export function camposDoFavorecido(f: Partial<Favorecido> & { id?: string }): Record<string, unknown> {
  const { id: _id, ...campos } = f;
  const linha: Record<string, unknown> = { ...campos };
  if ('document' in f) {
    const digitos = f.document ? f.document.replace(/\D/g, '') : '';
    linha.document = digitos || null;
  }
  return linha;
}

export function useSalvarPayee() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (f: Partial<Favorecido> & { id?: string }) => {
      const linha = camposDoFavorecido(f);
      if (f.id) {
        const { error } = await supabase.from('payees').update(linha as never).eq('id', f.id);
        if (error) throw error;
        return f.id;
      }
      const { data, error } = await supabase
        .from('payees').insert(linha as never).select('id').single();
      if (error) throw error;
      return (data as any).id as string;
    },
    onSuccess: () => {
      toast.success('Favorecido salvo');
      qc.invalidateQueries({ queryKey: ['payees'] });
    },
    onError: (e: Error) => {
      const msg = /payees_documento_unico|duplicate key/i.test(e.message)
        ? 'Já existe um favorecido com este CPF/CNPJ. Edite o existente em vez de criar outro.'
        : e.message || 'Não foi possível salvar';
      toast.error(msg);
    },
  });
}

/** Hoje em Brasília, dd/mm/aaaa — a data que vai na marca da regra pausada. */
function hojeNaMarca(): string {
  return new Date(Date.now() - 3 * 3600_000).toISOString().slice(0, 10).split('-').reverse().join('/');
}

/**
 * Desativar/reativar um favorecido (07/10/2026), como o assistente faz (alterar_favorecido).
 *
 * Regra do dono "Desativar cadastro: pausar as regras dele": senão o próximo Pix volta a entrar
 * classificado no favorecido desativado. Desativar pausa as regras do extrato que apontam para
 * ele (CPF/CNPJ ou nome completo) com a marca na nota; reativar devolve as que foram pausadas por
 * isso, na situação de antes. Marca e escolha são as mesmas do assistente
 * (supabase/functions/_shared/banking/pausa-do-favorecido.ts): o que um pausa, o outro reativa.
 * As regras são lidas ANTES de mudar o cadastro; leitura que falha não mexe em nada.
 * Só `active` vai para o cadastro — o documento e o resto ficam como estão.
 */
export async function mudarAtivoDoFavorecido(
  f: Pick<Favorecido, 'id' | 'name' | 'document'>, ativar: boolean,
): Promise<{ regras: number; aviso: string | null }> {
  const { data, error } = await supabase
    .from('finance_rules')
    .select('id, match_type, match_value, set_category, status, note')
    .in('status', SITUACOES_DA_MUDANCA(ativar))
    .limit(1000);
  if (error) throw new Error(`Não consegui ler as regras do extrato (${error.message}). Nada mudou.`);
  const regras = regrasDaMudanca(f, (data ?? []) as unknown as RegraDoExtrato[], ativar);

  const { error: e1 } = await supabase.from('payees').update({ active: ativar } as never).eq('id', f.id);
  if (e1) throw e1;

  let mudadas = 0;
  let aviso: string | null = null;
  const hoje = hojeNaMarca();
  for (const regra of regras) {
    const { error: e2 } = await supabase.from('finance_rules')
      .update(mudancaDaRegra(regra, f, ativar, hoje) as never).eq('id', regra.id);
    if (e2) {
      aviso = `O favorecido foi ${ativar ? 'reativado' : 'desativado'}, mas não consegui ${ativar ? 'reativar' : 'pausar'} todas as regras do extrato dele (${e2.message}): confira em Regras do extrato.`;
    } else mudadas++;
  }
  return { regras: mudadas, aviso };
}

export function useAlternarAtivoDoFavorecido() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ favorecido, ativar }: { favorecido: Pick<Favorecido, 'id' | 'name' | 'document'>; ativar: boolean }) =>
      mudarAtivoDoFavorecido(favorecido, ativar),
    onSuccess: (r, { ativar }) => {
      const regras = r.regras ? ` ${r.regras} regra(s) do extrato ${ativar ? 'voltaram a valer' : 'pausada(s)'}.` : '';
      toast.success(`Favorecido ${ativar ? 'reativado' : 'desativado'}.${regras}`);
      if (r.aviso) toast.warning(r.aviso);
      qc.invalidateQueries({ queryKey: ['payees'] });
      qc.invalidateQueries({ queryKey: ['finance-rules'] });
    },
    onError: (e: Error) => toast.error(e.message || 'Não foi possível mudar o favorecido'),
  });
}

/**
 * Ordens de serviço às quais uma compra pode pertencer.
 *
 * Só as que ainda estão vivas: vincular custo a uma OS já faturada mudaria uma margem que
 * o cliente e a contabilidade já enxergaram.
 */
export function useServiceOrdersVinculaveis(opcoes: { incluirFaturadas?: boolean } = {}) {
  // Exceção (27/09/2026): o serviço de terceiro de um cliente costuma ser pago DEPOIS de a OS
  // ser faturada, e "para qual serviço foi" é justamente a OS dele. Nesse caso a lista inclui
  // as faturadas — a tela marca quais são.
  const incluirFaturadas = !!opcoes.incluirFaturadas;
  return useQuery({
    queryKey: ['service-orders-vinculaveis', incluirFaturadas],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('service_orders')
        .select('id, service_order_number, status, clients(name)')
        .not('status', 'in', incluirFaturadas ? '("cancelled")' : '("cancelled","invoiced")')
        .order('created_at', { ascending: false })
        .limit(200);
      if (error) throw error;
      return (data ?? []) as unknown as Array<{
        id: string; service_order_number: string; status: string;
        clients: { name: string } | null;
      }>;
    },
    staleTime: 2 * 60_000,
  });
}

/**
 * Clientes, só id e nome, para dizer de quem veio uma ENTRADA.
 *
 * `receivables.client_id` é NOT NULL: sem escolher aqui, aprovar a receita falha. E o motor
 * não tem como adivinhar — quem paga por Pix aparece no extrato com o nome da pessoa física
 * que fez a transferência, que raramente é o nome do cliente cadastrado.
 *
 * Existe `useClients()`, mas ele traz `*` de todos. Nesta tela o campo aparece em cada linha
 * de entrada, então vale carregar só o necessário — e só quando há entrada em tela.
 */
export function useClientesParaReceita(ativo = true) {
  return useQuery({
    enabled: ativo,
    queryKey: ['clientes-para-receita'],
    queryFn: async () => {
      // Em páginas: eram .limit(500) com 533 clientes — os 33 últimos em ordem alfabética nunca
      // apareciam para escolher (e o PostgREST corta em 1.000 de qualquer jeito).
      const todos: Array<{ id: string; name: string }> = [];
      for (let de = 0; de < 20000; de += 1000) {
        const { data, error } = await supabase
          .from('clients')
          .select('id, name')
          .order('name', { ascending: true })
          .order('id', { ascending: true })
          .range(de, de + 999);
        if (error) throw error;
        const pagina = (data ?? []) as Array<{ id: string; name: string }>;
        todos.push(...pagina);
        if (pagina.length < 1000) break;
      }
      return todos;
    },
    staleTime: 5 * 60_000,
  });
}
