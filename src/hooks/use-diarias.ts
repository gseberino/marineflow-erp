// Diárias de freelancers: leitura do saldo e registro do dia, pelas funções do banco
// (migration 20260928190000). A tela não calcula saldo nem grava direto em tabela: a mesma função
// serve a tela e o assistente, com a mesma trava de quem pode.
import { useMutation, useQueries, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import type { EstadoDoSaldo, Jornada } from '@/lib/diarias';

export interface FreelancerNoResumo {
  id: string;
  nome: string;
  diaria: number | null;
  desde: string | null;
  dias: number;
  trabalhado: number;
  pago: number;
  ultimo_pagamento: string | null;
  saldo_final: number;
  estado: EstadoDoSaldo;
  /** O período desta pessoa (com "em aberto", cada um tem o seu). */
  de: string | null;
  ate: string | null;
  /** Pix anotado à mão que o banco ainda não confirmou — já está no "pago". */
  pago_aguardando_banco: number;
}

export interface ResumoDosFreelancers {
  pessoas: FreelancerNoResumo[];
  trabalhado: number;
  pago: number;
  dias: number;
  deve: number;
  adiantado: number;
}

export interface OSDoDia { id: string; numero: string }

export interface LinhaDaContaCorrente {
  data: string;
  tipo: 'dia' | 'pagamento';
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
  trabalhado: number;
  pago: number;
  pago_aguardando_banco: number;
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
          pago: num(p.pago), saldo_final: num(p.saldo_final), pago_aguardando_banco: num(p.pago_aguardando_banco),
          de: p.de ?? null, ate: p.ate ?? null,
        })),
        trabalhado: num(r.trabalhado), pago: num(r.pago), dias: num(r.dias), deve: num(r.deve), adiantado: num(r.adiantado),
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
    pago: num(c.pago), saldo_final: num(c.saldo_final), pago_aguardando_banco: num(c.pago_aguardando_banco),
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
