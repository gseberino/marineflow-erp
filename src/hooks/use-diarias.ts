// Diárias de freelancers: leitura do saldo e registro do dia, pelas funções do banco
// (migration 20260928190000). A tela não calcula saldo nem grava direto em tabela: a mesma função
// serve a tela e o assistente, com a mesma trava de quem pode.
import { useMutation, useQueries, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import type { EstadoDoSaldo, Jornada } from '@/lib/diarias';
import { CONTA_FALTA_APROVAR, ROTULO_REEMBOLSOS } from '@/lib/extrato-diarias';
import { mensagemDoErro, recarregarFinanceiro } from '@/hooks/use-lancamentos';

export interface FreelancerNoResumo {
  id: string;
  nome: string;
  diaria: number | null;
  desde: string | null;
  dias: number;
  /** Só os dias; os reembolsos vêm à parte. */
  trabalhado: number;
  pago: number;
  /** Despesas da empresa que ele pagou, com comprovante (F2b, 11/10/2026): somam a favor dele. */
  reembolsos: number;
  ultimo_pagamento: string | null;
  saldo_final: number;
  estado: EstadoDoSaldo;
  /** O período desta pessoa (com "em aberto", cada um tem o seu). */
  de: string | null;
  ate: string | null;
  /** Pix anotado à mão que o banco ainda não confirmou — já está no "pago". */
  pago_aguardando_banco: number;
  /** Pix que o banco já trouxe e espera a aprovação na fila — já está no "pago". */
  pago_falta_aprovar: number;
}

export interface ResumoDosFreelancers {
  pessoas: FreelancerNoResumo[];
  trabalhado: number;
  pago: number;
  reembolsos: number;
  dias: number;
  deve: number;
  adiantado: number;
}

export interface OSDoDia { id: string; numero: string }

/**
 * Uma linha da conta corrente. `reembolso` (F2b dos comprovantes, migration 20261011301000): despesa
 * da empresa que ele pagou do bolso, com comprovante — `trabalhado` = o valor, `pago` = 0, `conta` =
 * o código CMP, `categoria`/`os` do comprovante. Só sai cancelando o CMP (não tem ação na tela).
 */
export interface LinhaDaContaCorrente {
  data: string;
  tipo: 'dia' | 'pagamento' | 'reembolso';
  id: string;
  jornada: Jornada | null;
  fracao: number | null;
  valor_diaria: number | null;
  extras: number | null;
  descontos: number | null;
  trabalhado: number;
  pago: number;
  descricao: string | null;
  conta: string | null;
  categoria: string | null;
  observacao: string | null;
  os: OSDoDia[];
  saldo: number;
  /** Pagamento anotado à mão esperando a linha do banco (já desconta; migration 20261006200000). */
  aguardando: boolean;
  criado_em: string | null;
}

export interface ContaCorrente {
  favorecido: { id: string; nome: string; desde: string | null; saldo_inicial: number; diaria: number | null };
  atalho: string | null;
  de: string | null;
  ate: string | null;
  saldo_anterior: number;
  linhas: LinhaDaContaCorrente[];
  dias: number;
  /** Só os dias; saldo_final = saldo_anterior + trabalhado + reembolsos − pago. */
  trabalhado: number;
  pago: number;
  reembolsos: number;
  pago_aguardando_banco: number;
  pago_falta_aprovar: number;
  saldo_final: number;
  estado: EstadoDoSaldo;
}

const num = (v: unknown) => (v == null ? 0 : Number(v));
const numOuNulo = (v: unknown) => (v == null ? null : Number(v));

export function useResumoFreelancers(de: string | null, ate: string | null, atalho: string | null = null) {
  return useQuery({
    queryKey: ['diarias', 'resumo', de, ate, atalho],
    queryFn: async (): Promise<ResumoDosFreelancers> => {
      const { data, error } = await supabase.rpc('resumo_freelancers' as never, { p_de: de, p_ate: ate, p_atalho: atalho } as never);
      if (error) throw error;
      const r = data as unknown as ResumoDosFreelancers;
      return {
        pessoas: (r.pessoas ?? []).map((p) => ({
          ...p, diaria: numOuNulo(p.diaria), dias: num(p.dias), trabalhado: num(p.trabalhado),
          pago: num(p.pago), reembolsos: num(p.reembolsos), saldo_final: num(p.saldo_final),
          pago_aguardando_banco: num(p.pago_aguardando_banco), pago_falta_aprovar: num(p.pago_falta_aprovar),
          de: p.de ?? null, ate: p.ate ?? null,
        })),
        trabalhado: num(r.trabalhado), pago: num(r.pago), reembolsos: num(r.reembolsos), dias: num(r.dias),
        deve: num(r.deve), adiantado: num(r.adiantado),
      };
    },
    staleTime: 30_000,
  });
}

/** Chave única da conta de um freelancer num período — a tela, a grade e os documentos a dividem. */
export const chaveDaConta = (favorecidoId: string, de: string | null, ate: string | null, atalho: string | null = null) =>
  ['diarias', 'conta', favorecidoId, de, ate, atalho] as const;

export async function lerContaCorrente(
  favorecidoId: string, de: string | null, ate: string | null, atalho: string | null = null,
): Promise<ContaCorrente> {
  const { data, error } = await supabase.rpc('conta_corrente_freelancer' as never, {
    p_favorecido_id: favorecidoId, p_de: de, p_ate: ate, p_atalho: atalho,
  } as never);
  if (error) throw error;
  const c = data as unknown as ContaCorrente;
  return {
    ...c,
    atalho: c.atalho ?? null,
    saldo_anterior: num(c.saldo_anterior), dias: num(c.dias), trabalhado: num(c.trabalhado),
    pago: num(c.pago), reembolsos: num(c.reembolsos), saldo_final: num(c.saldo_final),
    pago_aguardando_banco: num(c.pago_aguardando_banco), pago_falta_aprovar: num(c.pago_falta_aprovar),
    favorecido: { ...c.favorecido, saldo_inicial: num(c.favorecido.saldo_inicial), diaria: numOuNulo(c.favorecido.diaria) },
    linhas: (c.linhas ?? []).map((l) => ({
      ...l, trabalhado: num(l.trabalhado), pago: num(l.pago), saldo: num(l.saldo),
      fracao: numOuNulo(l.fracao), valor_diaria: numOuNulo(l.valor_diaria),
      extras: numOuNulo(l.extras), descontos: numOuNulo(l.descontos), os: l.os ?? [],
      aguardando: l.aguardando === true, criado_em: l.criado_em ?? null,
    })),
  };
}

export function useContaCorrente(favorecidoId: string | null, de: string | null, ate: string | null, atalho: string | null = null) {
  return useQuery({
    queryKey: chaveDaConta(favorecidoId ?? '', de, ate, atalho),
    enabled: !!favorecidoId,
    queryFn: () => lerContaCorrente(favorecidoId!, de, ate, atalho),
    staleTime: 30_000,
  });
}

/**
 * A conta de cada freelancer no mesmo intervalo — é o que a grade do mês desenha. Mesma chave da
 * conta de um só: abrir o Extrato depois da grade não busca de novo.
 */
export function useContasDoPeriodo(favorecidoIds: string[], de: string, ate: string) {
  return useQueries({
    queries: favorecidoIds.map((id) => ({
      queryKey: chaveDaConta(id, de, ate),
      queryFn: () => lerContaCorrente(id, de, ate),
      staleTime: 30_000,
    })),
  });
}

/** O dia como o formulário de correção precisa dele. */
export interface DiaParaEditar {
  favorecidoId: string;
  data: string;
  jornada: Jornada;
  valorDiaria: number;
  extras: number;
  descontos: number;
  observacao: string | null;
  os: OSDoDia[];
}

export function diaParaEditar(favorecidoId: string, l: LinhaDaContaCorrente): DiaParaEditar {
  return {
    favorecidoId, data: l.data, jornada: l.jornada ?? 'inteiro',
    valorDiaria: l.valor_diaria ?? 0, extras: l.extras ?? 0, descontos: l.descontos ?? 0,
    observacao: l.observacao, os: l.os,
  };
}

export interface PedidoDeDiaria {
  favorecidoId: string;
  data: string;
  jornada: Jornada;
  /** undefined = não mexe nas OS; [] = tira todas. */
  osIds?: string[];
  /** undefined = não mexe; '' = limpa. */
  observacao?: string;
  extras?: number;
  descontos?: number;
  /** undefined = a do cadastro vigente na data (ou a já gravada no dia). */
  valorDiaria?: number;
}

export interface ResultadoDaDiaria {
  acao: 'criado' | 'atualizado' | 'sem_mudanca';
  diaria_id: string;
  message: string;
}

/** Os argumentos de `registrar_diaria` para um pedido — um lugar só, para um dia e para vários. */
function paramsDoPedido(p: PedidoDeDiaria) {
  return {
    p_favorecido_id: p.favorecidoId,
    p_data: p.data,
    p_jornada: p.jornada,
    p_os_ids: p.osIds ?? null,
    p_observacao: p.observacao ?? null,
    p_extras: p.extras ?? null,
    p_descontos: p.descontos ?? null,
    p_valor_diaria: p.valorDiaria ?? null,
    p_origem: 'painel',
  };
}

export function useRegistrarDiaria() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (p: PedidoDeDiaria): Promise<ResultadoDaDiaria> => {
      const { data, error } = await supabase.rpc('registrar_diaria' as never, paramsDoPedido(p) as never);
      if (error) throw error;
      return data as unknown as ResultadoDaDiaria;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['diarias'] }),
  });
}

/**
 * Vários dias de uma vez (o "+ dias" do app antigo): a mesma função do banco, um dia por vez, e a
 * tela se atualiza uma vez só no fim. Quem chama passa só os dias que ainda não estão lançados —
 * dia já lançado no intervalo fica como está. Um dia recusado não impede os outros; volta na lista.
 */
export function useRegistrarVariosDias() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ pedido, datas }: { pedido: Omit<PedidoDeDiaria, 'data'>; datas: string[] }) => {
      const feitos: string[] = [];
      const falhas: { data: string; erro: string }[] = [];
      for (const data of datas) {
        const { error } = await supabase.rpc('registrar_diaria' as never, paramsDoPedido({ ...pedido, data }) as never);
        if (error) falhas.push({ data, erro: error.message });
        else feitos.push(data);
      }
      return { feitos, falhas };
    },
    onSettled: () => qc.invalidateQueries({ queryKey: ['diarias'] }),
  });
}

export interface DiariaApagada {
  favorecido_id: string;
  data: string;
  jornada: Jornada;
  valor_diaria: number;
  extras: number;
  descontos: number;
  observacao: string | null;
  os_ids: string[];
}

/** Apagar devolve o dia inteiro — é com ele que o "Desfazer" registra de novo. */
export function useApagarDiaria() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (diariaId: string): Promise<{ apagado: DiariaApagada; message: string }> => {
      const { data, error } = await supabase.rpc('apagar_diaria' as never, { p_diaria_id: diariaId } as never);
      if (error) throw error;
      return data as unknown as { apagado: DiariaApagada; message: string };
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['diarias'] }),
  });
}

/**
 * Excluir não pergunta: apaga e oferece Desfazer, que registra o dia de novo exatamente como era.
 * Um só lugar para o Extrato e a ficha do dia se comportarem igual.
 */
export function useExcluirDiaComDesfazer() {
  const apagar = useApagarDiaria();
  const registrar = useRegistrarDiaria();
  const excluir = async (diariaId: string) => {
    try {
      const r = await apagar.mutateAsync(diariaId);
      toast(r.message, {
        duration: 9000,
        action: {
          label: 'Desfazer',
          onClick: () => {
            registrar.mutateAsync(pedidoParaDesfazer(r.apagado))
              .then(() => toast.success('Dia restaurado.'))
              .catch((e: Error) => toast.error(e.message || 'Não deu para restaurar o dia.'));
          },
        },
      });
    } catch (e) {
      toast.error((e as Error).message || 'Não deu para excluir o dia.');
    }
  };
  return { excluir, excluindo: apagar.isPending };
}

// ── Freelancer novo (botão "Novo freelancer", pedido do dono 03/10/2026) ─────────────────────────
// A mesma função do assistente (cadastrar_freelancer, migration 20261001183918): ela decide se cria
// ou usa o favorecido que já existe, deduz o tipo da chave Pix e cria a regra por CPF. A tela primeiro
// SIMULA (nada é gravado) e mostra o resultado; só então grava — o mesmo "sim" do WhatsApp.

export interface PedidoDeCadastro {
  nome: string;
  valorDiaria: number;
  /** Primeiro dia de trabalho, 'AAAA-MM-DD'; vazio = hoje. */
  desde?: string;
  chavePix?: string;
  /** Vazio = o banco deduz do formato (e-mail, CNPJ, chave aleatória). */
  tipoChave?: string;
  cpf?: string;
  telefone?: string;
  observacao?: string;
}

export interface ResultadoDoCadastro {
  acao: 'criado' | 'diaria_no_cadastro_existente';
  favorecido_id: string | null;
  nome: string;
  valor_diaria: number;
  desde: string;
  chave_pix: string | null;
  tipo_chave: string | null;
  regra: 'criada' | 'ja_existia' | 'sem_cpf';
  regra_categoria?: string | null;
  message?: string;
}

const vazioNulo = (v?: string) => (v && v.trim() ? v.trim() : null);

export function paramsDoCadastro(p: PedidoDeCadastro, simular: boolean) {
  return {
    p_nome: p.nome.trim(),
    p_valor_diaria: p.valorDiaria,
    p_desde: vazioNulo(p.desde),
    p_chave_pix: vazioNulo(p.chavePix),
    p_tipo_chave: vazioNulo(p.tipoChave),
    p_documento: vazioNulo(p.cpf),
    p_telefone: vazioNulo(p.telefone),
    p_observacao: vazioNulo(p.observacao),
    p_simular: simular,
  };
}

async function chamarCadastro(p: PedidoDeCadastro, simular: boolean): Promise<ResultadoDoCadastro> {
  const { data, error } = await supabase.rpc('cadastrar_freelancer' as never, paramsDoCadastro(p, simular) as never);
  if (error) throw error;
  const r = data as unknown as ResultadoDoCadastro;
  return { ...r, valor_diaria: num(r.valor_diaria) };
}

/** O que o cadastro FARIA — nada é gravado. A recusa (já tem diária, chave ambígua) vem como erro. */
export const simularCadastro = (p: PedidoDeCadastro) => chamarCadastro(p, true);

export function useCadastrarFreelancer() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (p: PedidoDeCadastro) => chamarCadastro(p, false),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['diarias'] }),
  });
}

// ── Acerto: fechar o período ao pagar (pedido do dono 06/10/2026; migration 20261006220000) ──────
// O acerto é a FOTO do período (dias, vales já pagos, a pagar), gera o recibo nº e trava os dias até
// a data. As mesmas funções do assistente (fechar_acerto_freelancer / reabrir_acerto_freelancer).

export interface Acerto {
  id: string;
  numero: number;
  favorecido_id: string;
  de: string;
  ate: string;
  saldo_anterior: number;
  dias: number;
  trabalhado: number;
  pago_no_periodo: number;
  valor_do_acerto: number;
  /** Reembolsos de comprovantes do período, na foto do acerto (F2b). */
  reembolsos: number;
  status: 'fechado' | 'reaberto';
  criado_em: string;
  reaberto_em: string | null;
  motivo_reabertura: string | null;
  enviado_ao_freelancer_em: string | null;
  conferido_em: string | null;
  conferido_texto: string | null;
}

/** Um reembolso que entra no acerto (a linha `reembolso` da conta corrente, F2b). */
export interface ReembolsoNoAcerto {
  data: string;
  valor: number;
  descricao: string | null;
  /** O código do comprovante, "CMP-00124". */
  codigo: string | null;
}

export interface SimulacaoDoAcerto {
  favorecido: string;
  de: string;
  ate: string;
  saldo_anterior: number;
  dias: number;
  trabalhado: number;
  pago_no_periodo: number;
  valor_do_acerto: number;
  pago_aguardando_banco: number;
  reembolsos: number;
  reembolsos_itens: ReembolsoNoAcerto[];
  resumo: string;
}

export function useAcertos(favorecidoId: string | null) {
  return useQuery({
    queryKey: ['diarias', 'acertos', favorecidoId],
    enabled: !!favorecidoId,
    queryFn: async (): Promise<Acerto[]> => {
      const { data, error } = await supabase.from('acertos_diarias' as never)
        .select('id, numero, favorecido_id, de, ate, saldo_anterior, dias, trabalhado, pago_no_periodo, valor_do_acerto, reembolsos, status, criado_em, reaberto_em, motivo_reabertura, enviado_ao_freelancer_em, conferido_em, conferido_texto')
        .eq('favorecido_id', favorecidoId!)
        .order('numero', { ascending: false });
      if (error) throw error;
      return ((data ?? []) as unknown as Acerto[]).map((a) => ({
        ...a, saldo_anterior: num(a.saldo_anterior), dias: num(a.dias), trabalhado: num(a.trabalhado),
        pago_no_periodo: num(a.pago_no_periodo), valor_do_acerto: num(a.valor_do_acerto), reembolsos: num(a.reembolsos),
      }));
    },
    staleTime: 30_000,
  });
}

/** O dia está dentro de um acerto fechado? Devolve o acerto (para dizer qual) ou nada. */
export function acertoQueTrava(acertos: Acerto[] | undefined, data: string): Acerto | null {
  return (acertos ?? []).find((a) => a.status === 'fechado' && a.de <= data && data <= a.ate) ?? null;
}

/**
 * Como tirar um reembolso de comprovante (F2b), em texto visível (o `title` não aparece no celular): ele
 * não se apaga na tela, sai cancelando o CMP pelo WhatsApp — o comando de verdade é "cancelar cmp 124
 * motivo". Dentro de um acerto fechado o cancelamento é recusado: reabra o acerto antes.
 */
export function comoTirarOReembolso(codigo: string | null | undefined, acerto: Acerto | null): string {
  const cmp = codigo || 'comprovante';
  if (acerto) return `Travado no acerto nº ${String(acerto.numero).padStart(4, '0')} (reabra o acerto para cancelar o ${cmp}).`;
  const numero = Number(/(\d+)$/.exec(codigo ?? '')?.[1] ?? '') || null;
  return `Reembolso vem do comprovante: para tirar, mande "cancelar cmp ${numero ?? 'N'} motivo" no WhatsApp.`;
}

/** O que o acerto FARIA — nada é gravado. A recusa ("nada a fechar") vem como erro. */
export async function simularAcerto(favorecidoId: string, ate: string | null): Promise<SimulacaoDoAcerto> {
  const { data, error } = await supabase.rpc('fechar_acerto_diarias' as never, {
    p_favorecido_id: favorecidoId, p_ate: ate, p_simular: true,
  } as never);
  if (error) throw error;
  const s = data as unknown as SimulacaoDoAcerto;
  return { ...s, saldo_anterior: num(s.saldo_anterior), dias: num(s.dias), trabalhado: num(s.trabalhado),
    pago_no_periodo: num(s.pago_no_periodo), valor_do_acerto: num(s.valor_do_acerto), pago_aguardando_banco: num(s.pago_aguardando_banco),
    reembolsos: num(s.reembolsos),
    reembolsos_itens: (s.reembolsos_itens ?? []).map((r) => ({
      data: r.data, valor: num(r.valor), descricao: r.descricao ?? null, codigo: r.codigo ?? null,
    })) };
}

export function useFecharAcerto() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ favorecidoId, ate }: { favorecidoId: string; ate: string | null }) => {
      const { data, error } = await supabase.rpc('fechar_acerto_diarias' as never, {
        p_favorecido_id: favorecidoId, p_ate: ate, p_simular: false,
      } as never);
      if (error) throw error;
      return data as unknown as { id: string; numero: number; message: string };
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['diarias'] }),
  });
}

export function useReabrirAcerto() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ acertoId, motivo }: { acertoId: string; motivo: string }) => {
      const { data, error } = await supabase.rpc('reabrir_acerto_diarias' as never, { p_acerto_id: acertoId, p_motivo: motivo } as never);
      if (error) throw error;
      return data as unknown as { message: string };
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['diarias'] }),
  });
}

// ── Pagamento dividido entre diárias e reembolso (resposta 4 do dono, 11/10/2026; 20261011301000) ──
// Ao pagar o técnico, o banco PROPÕE a divisão pelos reembolsos em aberto dele (os do acerto primeiro,
// por data, somando enquanto cabe no valor) e o dono confirma ou desmarca ("eu sempre vou sinalizar
// o que é o que"). A parte do reembolso vai para a categoria de cada comprovante (sem categoria,
// "Outras despesas"); o resto fica em "Diárias de freelancers" — o resultado não lê o reembolso como
// mão de obra. O saldo com ele não muda: o pagamento inteiro continua descontando. As mesmas funções
// do assistente (registrar_pagamento_freelancer e dividir_pagamento_freelancer).

export const CATEGORIA_DIARIAS = 'Diárias de freelancers';
/** Para onde vai o reembolso de um comprovante sem categoria ("Reembolso de despesas de campo" não existe). */
export const CATEGORIA_DO_REEMBOLSO_SEM_CATEGORIA = 'Outras despesas';

export type FormaDoPagamento = 'pix' | 'dinheiro' | 'socio';

/** Um reembolso de comprovante que nenhum pagamento quitou ainda. */
export interface ReembolsoEmAberto {
  id: string;
  /** "CMP-00124". */
  codigo: string | null;
  data: string;
  valor: number;
  categoria: string | null;
  descricao: string | null;
  /** O número do acerto em que ele entrou (fechado), ou nada. */
  acerto: number | null;
}

export interface ParteDaDivisao { categoria: string; valor: number }

export interface PropostaDeDivisao {
  favorecido: { id: string; nome: string };
  valor: number;
  em_aberto: ReembolsoEmAberto[];
  /** Os ids que o banco marcaria (cabem no valor). */
  propostos: string[];
  reembolsos: number;
  diarias: number;
  partes: ParteDaDivisao[];
}

export interface DivisaoDoPagamento {
  id: string | null;
  /** pendente = Pix anotado (divide quando a linha do banco for aprovada); aplicada = já dividido. */
  status: 'pendente' | 'aplicada' | 'nenhuma' | 'desfeita';
  diarias: number;
  reembolsos: number;
  partes: ParteDaDivisao[];
}

export interface ResultadoDoPagamento {
  ok: boolean;
  forma?: FormaDoPagamento;
  anotacao_id?: string | null;
  payable_id?: string | null;
  divisao?: DivisaoDoPagamento | null;
  message: string;
  /** Pix anotado: quantas anotações iguais (mesma pessoa, valor e dias) esta substituiu (anotar_transacao). */
  substituidas?: number;
}

const partesNumericas = (p: ParteDaDivisao[] | null | undefined): ParteDaDivisao[] =>
  (p ?? []).map((x) => ({ categoria: x.categoria, valor: num(x.valor) }));

/** O que o banco proporia para um pagamento deste valor — nada é gravado. */
export async function lerPropostaDeDivisao(favorecidoId: string, valor: number): Promise<PropostaDeDivisao> {
  const { data, error } = await supabase.rpc('proposta_de_divisao_do_pagamento' as never, {
    p_favorecido_id: favorecidoId, p_valor: valor,
  } as never);
  if (error) throw error;
  const p = data as unknown as PropostaDeDivisao;
  return {
    favorecido: p.favorecido,
    valor: num(p.valor),
    em_aberto: (p.em_aberto ?? []).map((r) => ({
      id: r.id, codigo: r.codigo ?? null, data: r.data, valor: num(r.valor), categoria: r.categoria ?? null,
      descricao: r.descricao ?? null, acerto: r.acerto == null ? null : Number(r.acerto),
    })),
    propostos: p.propostos ?? [],
    reembolsos: num(p.reembolsos),
    diarias: num(p.diarias),
    partes: partesNumericas(p.partes),
  };
}

/** A proposta para um valor: só quando há freelancer e valor. */
export function usePropostaDeDivisao(favorecidoId: string | null | undefined, valor: number) {
  return useQuery({
    queryKey: ['diarias', 'proposta-de-divisao', favorecidoId ?? '', valor],
    enabled: !!favorecidoId && valor > 0,
    queryFn: () => lerPropostaDeDivisao(favorecidoId!, valor),
    staleTime: 30_000,
  });
}

const centavos = (v: number) => Math.round(v * 100) / 100;

/**
 * A divisão com os reembolsos MARCADOS na tela (o banco refaz a conta e recusa o que não cabe): a parte
 * das diárias primeiro, depois uma por categoria, na ordem dos comprovantes.
 */
export function divisaoEscolhida(emAberto: ReembolsoEmAberto[], ids: readonly string[], valor: number) {
  const marcados = emAberto.filter((r) => ids.includes(r.id));
  const reembolsos = centavos(marcados.reduce((s, r) => s + r.valor, 0));
  const diarias = centavos(valor - reembolsos);
  const porCategoria = new Map<string, number>();
  for (const r of marcados) {
    const c = r.categoria?.trim() || CATEGORIA_DO_REEMBOLSO_SEM_CATEGORIA;
    porCategoria.set(c, centavos((porCategoria.get(c) ?? 0) + r.valor));
  }
  const partes: ParteDaDivisao[] = [
    ...(diarias > 0 ? [{ categoria: CATEGORIA_DIARIAS, valor: diarias }] : []),
    ...[...porCategoria].map(([categoria, v]) => ({ categoria, valor: v })),
  ];
  return { marcados, reembolsos, diarias, partes, passou: reembolsos > valor + 0.005 };
}

/** O sufixo que o banco põe no pagamento já dividido ("… (inclui reembolso de despesas pagas pelo técnico: R$ 92,00)"). */
const SUFIXO_DA_DIVISAO = `(inclui ${ROTULO_REEMBOLSOS.toLowerCase()}`;

/**
 * O Pix que já saiu do banco para ele e espera a aprovação na fila de lançamentos (27/10/2026): já desconta,
 * como o anotado, mas não está "aguardando o banco". O banco devolve esta frase na coluna "conta".
 */
export const pagamentoNaFila = (l: Pick<LinhaDaContaCorrente, 'tipo' | 'aguardando' | 'conta'>) =>
  l.tipo === 'pagamento' && l.aguardando && l.conta === CONTA_FALTA_APROVAR;

/** O pagamento da conta corrente já foi dividido entre diárias e reembolso? */
export const pagamentoDividido = (l: Pick<LinhaDaContaCorrente, 'tipo' | 'aguardando' | 'descricao'>) =>
  l.tipo === 'pagamento' && !l.aguardando && (l.descricao ?? '').toLowerCase().includes(SUFIXO_DA_DIVISAO);

/**
 * O pagamento que se pode dividir pela tela: o lançamento das Diárias numa linha do BANCO (Pix
 * aprovado, venha da tela, do assistente ou da regra por CPF). Anotado ainda não tem lançamento (a
 * divisão dele nasce no "Registrar pagamento"); Caixa e bolso de sócio dividem na hora de registrar.
 * O banco confere de novo (mês fechado, outro favorecido) e recusa com o motivo.
 */
export function pagamentoQueSeDivide(l: LinhaDaContaCorrente): boolean {
  if (l.tipo !== 'pagamento' || l.aguardando || !l.conta) return false;
  if (l.conta === 'Caixa (dinheiro)' || l.conta === 'Sem conta ligada' || l.conta.startsWith('Bolso de ')) return false;
  return l.categoria === CATEGORIA_DIARIAS || pagamentoDividido(l);
}

export interface PedidoDePagamento {
  favorecidoId: string;
  valor: number;
  data: string;
  forma: FormaDoPagamento;
  socioId?: string | null;
  /** Os reembolsos que este pagamento quita ([] = tudo em Diárias). */
  reembolsos: string[];
  descricao: string;
}

/**
 * O aviso depois de registrar/dividir. A mesma regra do useAcaoDoCaixa: o Pix que TROCOU uma anotação igual
 * (mesma pessoa, valor e dias) não pode passar como sucesso de 4 segundos — se eram dois pagamentos, um
 * sumiu (caso do dono de 06/10/2026: dois "R$ 100 ao Roberto").
 */
export function avisarDoResultado(r: ResultadoDoPagamento | null | undefined) {
  if (r?.ok === false) toast.warning(r.message);
  else if ((r?.substituidas ?? 0) > 0) toast.warning(r?.message ?? 'Feito', { duration: 15_000 });
  else toast.success(r?.message ?? 'Feito');
}

/** Registrar o pagamento ao freelancer já com a divisão (Pix anotado, Caixa ou bolso de sócio). */
export function useRegistrarPagamentoDoFreelancer() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (p: PedidoDePagamento): Promise<ResultadoDoPagamento> => {
      const { data, error } = await supabase.rpc('registrar_pagamento_do_freelancer' as never, {
        p_favorecido_id: p.favorecidoId, p_valor: p.valor, p_data: p.data, p_forma: p.forma,
        p_socio_id: p.forma === 'socio' ? p.socioId ?? null : null, p_reembolsos: p.reembolsos, p_descricao: p.descricao,
      } as never);
      if (error) throw error;
      return data as unknown as ResultadoDoPagamento;
    },
    onSuccess: (r) => {
      recarregarFinanceiro(qc);
      qc.invalidateQueries({ queryKey: ['anotacoes-do-extrato'] });
      qc.invalidateQueries({ queryKey: ['diarias'] });
      avisarDoResultado(r);
    },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

/** Dividir (ou, com [] , juntar de volta) o pagamento das Diárias que já veio do banco. */
export function useDividirPagamentoDoFreelancer() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ payableId, reembolsos }: { payableId: string; reembolsos: string[] }): Promise<ResultadoDoPagamento> => {
      const { data, error } = await supabase.rpc('dividir_pagamento_do_freelancer' as never, {
        p_payable_id: payableId, p_reembolsos: reembolsos,
      } as never);
      if (error) throw error;
      return data as unknown as ResultadoDoPagamento;
    },
    onSuccess: (r) => {
      recarregarFinanceiro(qc);
      qc.invalidateQueries({ queryKey: ['diarias'] });
      avisarDoResultado(r);
    },
    onError: (e) => toast.error(mensagemDoErro(e)),
  });
}

/** O pedido que reconstrói um dia apagado, exatamente como era. */
export function pedidoParaDesfazer(a: DiariaApagada): PedidoDeDiaria {
  return {
    favorecidoId: a.favorecido_id,
    data: a.data,
    jornada: a.jornada,
    osIds: a.os_ids ?? [],
    observacao: a.observacao ?? '',
    extras: Number(a.extras) || 0,
    descontos: Number(a.descontos) || 0,
    valorDiaria: Number(a.valor_diaria),
  };
}
