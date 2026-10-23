// Pagadores do cliente (leva 8, 22/10/2026): quem costuma pagar por um cliente — a empresa dele, o cônjuge, um
// parente, a marina, a seguradora — e o "Pago por" de cada pagamento.
//
// Tudo passa pelo banco (migration 20261022190000_pagadores_do_cliente):
//   - a tabela pagadores_do_cliente só é LIDA daqui (RLS: admin e financeiro); a escrita é pelas funções
//     guardar_pagadores_do_cliente, decidir_pagador_do_cliente e recusar_pagadores_do_cliente, com auth.uid() — admin
//     grava 'confirmado' (o SIM do dono), financeiro grava 'proposto'; "não é pagador habitual" grava 'recusado' a
//     partir da linha do banco; o documento e o nome saem da linha do banco, nunca da tela;
//   - pagadores_para_conferir() é a lista histórica para o dono conferir (Financeiro → Regras); o par PROPOSTO pelo
//     financeiro continua nela (situacao 'proposto', pagador_id) até o administrador decidir — também o que foi
//     guardado pela fila ou pelo assistente e ainda não paga conta nenhuma (vezes 1, a linha dele);
//   - recusado e pausado são o "não" do dono: o motor da fila nunca sugere aquele cliente para aquele documento;
//   - a view pagamentos_com_pagador dá quem pagou cada pagamento sem o embed payments ↔ bank_transactions (2 FKs:
//     PGRST201).
// CPF de terceiro é dado pessoal: as consultas só saem para admin e financeiro (para os outros a RLS devolveria
// vazio, e "ninguém paga por este cliente" seria falso). Na tela, mostre com documentoMascarado.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import type { Json } from '@/integrations/supabase/types';
import { useOptionalAuth } from '@/hooks/use-auth';
import { mensagemDoErro } from '@/hooks/use-lancamentos';
import {
  documentoMascarado, frasePagoPor, nomeSemCpf, RELACOES_DO_PAGADOR, ROTULO_DA_RELACAO, type RelacaoDoPagador,
} from '../../supabase/functions/_shared/banking/contraparte';

export { documentoMascarado, frasePagoPor, nomeSemCpf, RELACOES_DO_PAGADOR, ROTULO_DA_RELACAO };
export type { RelacaoDoPagador };

export type SituacaoDoPagador = 'proposto' | 'confirmado' | 'recusado' | 'pausado';

export const ROTULO_DA_SITUACAO: Record<SituacaoDoPagador, string> = {
  proposto: 'Proposto — falta o SIM do administrador',
  confirmado: 'Confirmado',
  recusado: 'Recusado',
  pausado: 'Pausado',
};

/**
 * confirmar e reativar: só o administrador (ao confirmar, ele pode trocar a relação proposta). recusar e pausar: o
 * administrador; o financeiro só o PROPOSTO — o confirmado (o SIM do dono) e o pausado só o administrador desfaz.
 */
export type DecisaoSobrePagador = 'confirmar' | 'reativar' | 'recusar' | 'pausar';

export interface PagadorDoCliente {
  id: string;
  client_id: string;
  /** CPF (11) ou CNPJ (14), só dígitos. Para mostrar: documentoMascarado(documento). */
  documento: string;
  nome: string;
  relacao: RelacaoDoPagador;
  situacao: SituacaoDoPagador;
  observacao: string | null;
  origem: 'historico' | 'fila' | 'assistente' | null;
  bank_transaction_id: string | null;
  proposto_por: string | null;
  proposto_em: string;
  confirmado_por: string | null;
  confirmado_em: string | null;
  decidido_motivo: string | null;
  /** Nome de quem propôs/confirmou; nulo quando a RLS de app_users não deixa ler (o financeiro só vê a si). */
  proposto_por_nome: string | null;
  confirmado_por_nome: string | null;
}

/**
 * Por que o par sai do lote e é decidido um a um (pagadores_para_conferir().aviso):
 *   documento_de_outro_cliente — o documento é de outro cliente cadastrado (possível cadastro duplicado);
 *   ligacao_duvidosa           — a única ligação do par é a conciliação de um pagamento que já tem OUTRA linha do
 *                                banco (provável conciliação errada, não um pagador — o caso MUNDO DOCE COLOMBO);
 *   pagou_para_varios_clientes — o mesmo documento pagou por mais de um cliente (marina, seguradora?).
 */
export type AvisoDaLista = 'documento_de_outro_cliente' | 'ligacao_duvidosa' | 'pagou_para_varios_clientes';

/** Uma linha de pagadores_para_conferir(): um par cliente × quem pagou, ainda sem decisão do administrador. */
export interface PagadorParaConferir {
  client_id: string;
  cliente_nome: string;
  cliente_tem_documento: boolean;
  /** Só dígitos. Para mostrar: documentoMascarado. */
  pagador_documento: string;
  pagador_nome: string | null;
  tipo_documento: 'CPF' | 'CNPJ';
  vezes: number;
  total: number;
  primeira: string;
  ultima: string;
  /** As linhas do banco que provam; qualquer uma serve para guardar. */
  bank_transaction_ids: string[];
  grupo: 'documento_diferente' | 'cliente_sem_documento';
  /** Com aviso, o item fica FORA do lote e é decidido um a um. */
  aviso: AvisoDaLista | null;
  /*
   * O par que o financeiro já guardou ('proposto') continua na lista até o administrador decidir (confirmar ou
   * recusar por decidir_pagador_do_cliente, com pagador_id). Sem proposto, tudo nulo. O banco sempre manda as cinco
   * colunas; opcionais aqui só para quem monta a linha à mão (testes). O proposto que veio da fila ou do assistente e
   * não paga conta nenhuma também vem, com vezes 1 e a linha que ele guardou.
   */
  pagador_id?: string | null;
  situacao?: 'proposto' | null;
  relacao_proposta?: RelacaoDoPagador | null;
  /** Nulo quando a RLS de app_users não deixa ler (o financeiro só vê a si mesmo). */
  proposto_por_nome?: string | null;
  proposto_em?: string | null;
}

/** A regra antiga de entrada do mesmo documento que aponta OUTRO cliente (fica como está; as entradas perguntam). */
export interface RegraDeOutroCliente {
  finance_rule_id: string;
  client_id: string;
  cliente: string;
}

/** O que a tela manda para guardar: o documento e o nome NÃO vão — saem da linha do banco. */
export interface ItemParaGuardar {
  client_id: string;
  bank_transaction_id: string;
  relacao: RelacaoDoPagador;
  observacao?: string | null;
  origem?: 'historico' | 'fila' | 'assistente';
}

/** O retorno de guardar_pagadores_do_cliente e de recusar_pagadores_do_cliente (o mesmo formato). */
export interface ResultadoDeGuardar {
  ok: boolean;
  gravados: Array<{
    id: string; client_id: string; cliente: string; nome: string; relacao: RelacaoDoPagador;
    situacao: SituacaoDoPagador; ja_existia: boolean; regras_consolidadas: string[];
    /** A situação antes deste pedido (nulo = o par não estava na tabela). */
    situacao_anterior?: SituacaoDoPagador | null;
    /** Só no guardar: a regra antiga do mesmo documento que aponta outro cliente. */
    regra_de_outro_cliente?: RegraDeOutroCliente | null;
  }>;
  /** `indice` é a posição (1, 2, …) do item no pedido. */
  recusados: Array<{ indice: number; client_id: string | null; bank_transaction_id: string | null; motivo: string }>;
  regras_consolidadas: string[];
  /** "Atenção: uma regra antiga diz que este CPF/CNPJ é do cliente Y…" — já repetido no fim de `message`. */
  avisos?: string[];
  message: string;
}

export interface ResultadoDaDecisao {
  ok: boolean;
  id: string;
  situacao: SituacaoDoPagador;
  /** A relação depois da decisão (a trocada pelo administrador ao confirmar, ou a de antes). */
  relacao?: RelacaoDoPagador;
  regras_consolidadas: string[];
  /** Ao confirmar/reativar: a regra antiga do mesmo documento que aponta outro cliente (o aviso já vem em `message`). */
  regra_de_outro_cliente?: RegraDeOutroCliente | null;
  message: string;
}

/** Quem pagou um pagamento (view pagamentos_com_pagador). */
export interface PagamentoComPagador {
  payment_id: string;
  receivable_id: string;
  client_id: string;
  bank_transaction_id: string | null;
  pagador_nome: string | null;
  /** Só dígitos; nulo para quem não lê o extrato. Para mostrar: documentoMascarado. */
  pagador_documento: string | null;
  /** Só quando há pagador CONFIRMADO do cliente com este documento. */
  relacao: RelacaoDoPagador | null;
  /**
   * cliente — o próprio cliente pagou; terceiro — pagador confirmado, ou documentos diferentes;
   * indefinido — o cliente não tem documento e não há pagador confirmado ("nome diferente nunca identifica");
   * sem_dado — sem linha do banco, ou o banco não disse quem pagou.
   */
  situacao: 'cliente' | 'terceiro' | 'indefinido' | 'sem_dado';
}

/** Prefixo de todas as consultas deste arquivo: guardar ou decidir invalida as listas de uma vez. */
export const CHAVE_DOS_PAGADORES = ['pagadores-do-cliente'] as const;
/** Sob ['payments']: registrar ou estornar pagamento já invalida o "Pago por". */
export const CHAVE_DO_PAGO_POR = ['payments', 'com-pagador'] as const;

const ORDEM_DA_SITUACAO: Record<SituacaoDoPagador, number> = { confirmado: 0, proposto: 1, pausado: 2, recusado: 3 };

/** Admin e financeiro leem; para os outros cargos a consulta nem sai. */
export function podeVerPagadores(cargo: string | null | undefined): boolean {
  return cargo === 'admin' || cargo === 'financial';
}

function usePodeVer(): boolean {
  return podeVerPagadores(useOptionalAuth()?.user?.role);
}

/** Os pagadores de um cliente (todas as situações): confirmados primeiro, depois propostos, pausados e recusados. */
export function usePagadoresDoCliente(clientId: string | null | undefined) {
  const podeVer = usePodeVer();
  return useQuery({
    queryKey: [...CHAVE_DOS_PAGADORES, 'cliente', clientId],
    enabled: podeVer && !!clientId,
    queryFn: async (): Promise<PagadorDoCliente[]> => {
      const { data, error } = await supabase
        .from('pagadores_do_cliente')
        .select(`id, client_id, documento, nome, relacao, situacao, observacao, origem, bank_transaction_id,
                 proposto_por, proposto_em, confirmado_por, confirmado_em, decidido_motivo,
                 proposto:app_users!pagadores_do_cliente_proposto_por_fkey(full_name),
                 confirmado:app_users!pagadores_do_cliente_confirmado_por_fkey(full_name)`)
        .eq('client_id', clientId!)
        .order('proposto_em', { ascending: false });
      // Erro não vira "ninguém paga por este cliente": lança, e a tela mostra o erro.
      if (error) throw error;
      return ((data ?? []) as unknown as Array<Record<string, unknown> & {
        proposto?: { full_name?: string | null } | null; confirmado?: { full_name?: string | null } | null;
      }>).map(({ proposto, confirmado, ...p }) => ({
        ...(p as unknown as Omit<PagadorDoCliente, 'proposto_por_nome' | 'confirmado_por_nome'>),
        proposto_por_nome: proposto?.full_name ?? null,
        confirmado_por_nome: confirmado?.full_name ?? null,
      })).sort((a, b) => ORDEM_DA_SITUACAO[a.situacao] - ORDEM_DA_SITUACAO[b.situacao] || a.nome.localeCompare(b.nome, 'pt-BR'));
    },
    staleTime: 60 * 1000,
  });
}

/** A lista para o dono conferir (pagadores_para_conferir): pares ainda não decididos, documento diferente primeiro. */
export function usePagadoresParaConferir() {
  const podeVer = usePodeVer();
  return useQuery({
    queryKey: [...CHAVE_DOS_PAGADORES, 'para-conferir'],
    enabled: podeVer,
    queryFn: async (): Promise<PagadorParaConferir[]> => {
      const { data, error } = await supabase.rpc('pagadores_para_conferir');
      if (error) throw error;
      return ((data ?? []) as unknown as PagadorParaConferir[]).map((l) => ({
        ...l,
        vezes: Number(l.vezes),
        total: Number(l.total),
        aviso: (l.aviso ?? null) as PagadorParaConferir['aviso'],
        pagador_id: l.pagador_id ?? null,
        situacao: (l.situacao === 'proposto' ? 'proposto' : null) as PagadorParaConferir['situacao'],
        relacao_proposta: l.relacao_proposta ?? null,
        proposto_por_nome: l.proposto_por_nome ?? null,
        proposto_em: l.proposto_em ?? null,
      }));
    },
    staleTime: 60 * 1000,
  });
}

/** Quem pagou cada pagamento de uma conta a receber (o "Pago por" do recebimento e do recibo). */
export function usePagamentosComPagador(receivableId: string | null | undefined) {
  const podeVer = usePodeVer();
  return useQuery({
    queryKey: [...CHAVE_DO_PAGO_POR, receivableId],
    enabled: podeVer && !!receivableId,
    queryFn: async (): Promise<PagamentoComPagador[]> => {
      const { data, error } = await supabase
        .from('pagamentos_com_pagador')
        .select('payment_id, receivable_id, client_id, bank_transaction_id, pagador_nome, pagador_documento, relacao, situacao')
        .eq('receivable_id', receivableId!);
      if (error) throw error;
      return (data ?? []) as unknown as PagamentoComPagador[];
    },
    staleTime: 60 * 1000,
  });
}

/**
 * O "Pago por" de um pagamento recebido, pela linha do banco (view pagamentos_com_pagador):
 *   terceiro   — "Pago por X (cônjuge) · pelo extrato" (a relação só quando o pagador foi confirmado);
 *   indefinido — o cliente não tem CPF/CNPJ no cadastro, então quem pagou pode ser ele ou outra pessoa: "confira";
 *   cliente / sem_dado / sem linha — nada.
 * Sem nome no extrato, o documento MASCARADO (CPF de terceiro nunca inteiro na tela) — e o nome sai sem o CPF que o
 * banco escreve nele ("12345678901-MARIA", nomeSemCpf).
 */
export function fraseDoPagoPor(x: PagamentoComPagador | null | undefined): { texto: string; confira: boolean } | null {
  if (!x) return null;
  const quem = nomeSemCpf(x.pagador_nome?.trim()) || documentoMascarado(x.pagador_documento);
  if (!quem) return null;
  if (x.situacao === 'terceiro') {
    const relacao = x.relacao ? ROTULO_DA_RELACAO[x.relacao]?.toLowerCase() : null;
    return { texto: `Pago por ${quem}${relacao ? ` (${relacao})` : ''} · pelo extrato`, confira: false };
  }
  if (x.situacao === 'indefinido') {
    return { texto: `Pago por ${quem} · cliente sem CPF/CNPJ no cadastro, confira`, confira: true };
  }
  return null;
}

/** Tudo que muda quando um pagador é guardado ou decidido. */
function invalidar(qc: ReturnType<typeof useQueryClient>) {
  for (const k of [CHAVE_DOS_PAGADORES, CHAVE_DO_PAGO_POR, ['finance-rules'], ['trilha-conciliacao']]) {
    qc.invalidateQueries({ queryKey: [...k] });
  }
}

/**
 * O resultado muda o que a fila do Extrato sugere (um pagador passou a valer, ou deixou de valer)? Então a tela chama
 * "Revisar a fila" em silêncio — useReaplicarRegras().mutate({ silencioso: true }), ação reclassify — para as linhas
 * pendentes desse documento serem refeitas agora, e não só na varredura diária. Proposto pelo financeiro não muda nada.
 * Recusar muda sempre que o par passa a recusado (revisão de 23/10/2026): o recusado é o VETO do motor — o histórico e
 * o nome idêntico deixam de sugerir aquele cliente —, mesmo quando o par nem estava guardado. Repetir uma recusa não.
 * Toda decisão (confirmar, reativar, recusar, pausar) muda.
 */
export function pedeRevisarFila(r: ResultadoDeGuardar | ResultadoDaDecisao): boolean {
  return 'gravados' in r
    ? r.gravados.some((g) => g.situacao === 'confirmado' || g.situacao_anterior === 'confirmado'
      || (g.situacao === 'recusado' && g.situacao_anterior !== 'recusado'))
    : true;
}

/**
 * A mensagem do resultado, com o motivo de cada recusa quando são poucas. O banco escreve o nome de quem pagou como
 * está na linha do banco — às vezes com o CPF dentro ("12345678901-MARIA"): sai mascarado (nomeSemCpf).
 */
export function mensagemDeGuardar(r: ResultadoDeGuardar): string {
  if (r.recusados.length > 1 && r.recusados.length <= 3) {
    return nomeSemCpf(`${r.message} ${r.recusados.map((x) => x.motivo).join(' · ')}`);
  }
  return nomeSemCpf(r.message);
}

/**
 * Guarda quem pagou como pagador do cliente (um ou o lote marcado, até 50). Admin: confirmado; financeiro: proposto.
 * Item recusado volta com o motivo (o resto é gravado). Depois de guardar, a tela da fila chama "Revisar a fila"
 * (useReaplicarRegras, ação reclassify) para as linhas pendentes desse documento serem refeitas.
 */
export function useGuardarPagadores() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (itens: ItemParaGuardar[]): Promise<ResultadoDeGuardar> => {
      const { data, error } = await supabase.rpc('guardar_pagadores_do_cliente', {
        p_itens: itens as unknown as Json,
      });
      if (error) throw error;
      return data as unknown as ResultadoDeGuardar;
    },
    onSuccess: (r) => avisarDoResultado(qc, r),
    onError: (e) => toast.error(nomeSemCpf(mensagemDoErro(e))),
  });
}

/** Invalida tudo e diz o resultado: nada gravado é erro; parte recusada ou aviso de regra antiga é atenção. */
function avisarDoResultado(qc: ReturnType<typeof useQueryClient>, r: ResultadoDeGuardar) {
  invalidar(qc);
  const msg = mensagemDeGuardar(r);
  if (r.gravados.length === 0) toast.error(msg);
  else if (r.recusados.length > 0 || (r.avisos?.length ?? 0) > 0) toast.warning(msg);
  else toast.success(msg);
}

/** Um par para recusar: o documento e o nome NÃO vão — saem da linha do banco. */
export interface ItemParaRecusar {
  client_id: string;
  bank_transaction_id: string;
  relacao?: RelacaoDoPagador;
  origem?: 'historico' | 'fila' | 'assistente';
}

/**
 * "Não é pagador habitual": grava o par (cliente × quem pagou na linha do banco) como RECUSADO — não volta à lista para
 * conferir nem vira sugestão (o motor lê o recusado como veto). Serve para o par que ainda não está na tabela (a lista,
 * a fila); o que já está nela se decide por useDecidirPagador. Admin ou financeiro; o financeiro não desfaz um
 * confirmado nem um pausado (volta com o motivo).
 * Aceita o documento de outro cliente (o possível cadastro duplicado também precisa sair da lista). Até 50.
 */
export function useRecusarPagadores() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: { itens: ItemParaRecusar[]; motivo?: string | null }): Promise<ResultadoDeGuardar> => {
      const { data, error } = await supabase.rpc('recusar_pagadores_do_cliente', {
        p_itens: v.itens as unknown as Json,
        p_motivo: v.motivo ?? undefined,
      });
      if (error) throw error;
      return data as unknown as ResultadoDeGuardar;
    },
    onSuccess: (r) => avisarDoResultado(qc, r),
    onError: (e) => toast.error(nomeSemCpf(mensagemDoErro(e))),
  });
}

/**
 * Confirmar ou reativar (só o administrador), recusar ou pausar (o administrador; o financeiro só o proposto — o banco
 * recusa o resto com o motivo). `relacao` só no confirmar: o administrador troca a relação que o financeiro propôs (o
 * banco valida e recusa fora do confirmar).
 */
export function useDecidirPagador() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: {
      id: string; decisao: DecisaoSobrePagador; motivo?: string | null; relacao?: RelacaoDoPagador | null;
    }): Promise<ResultadoDaDecisao> => {
      const { data, error } = await supabase.rpc('decidir_pagador_do_cliente', {
        p_id: v.id, p_decisao: v.decisao, p_motivo: v.motivo ?? undefined, p_relacao: v.relacao ?? undefined,
      });
      if (error) throw error;
      return data as unknown as ResultadoDaDecisao;
    },
    onSuccess: (r) => {
      invalidar(qc);
      // Confirmado com regra antiga de outro cliente: deu certo, mas o dono precisa ler o aviso. O nome de quem pagou
      // vem do banco como a linha do banco escreveu: sem o CPF dentro.
      if (r.regra_de_outro_cliente) toast.warning(nomeSemCpf(r.message));
      else toast.success(nomeSemCpf(r.message));
    },
    onError: (e) => toast.error(nomeSemCpf(mensagemDoErro(e))),
  });
}
