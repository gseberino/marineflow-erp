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
}

export interface ContaCorrente {
  favorecido: { id: string; nome: string; desde: string | null; saldo_inicial: number; diaria: number | null };
  de: string | null;
  ate: string | null;
  saldo_anterior: number;
  linhas: LinhaDaContaCorrente[];
  dias: number;
  trabalhado: number;
  pago: number;
  saldo_final: number;
  estado: EstadoDoSaldo;
}

const num = (v: unknown) => (v == null ? 0 : Number(v));
const numOuNulo = (v: unknown) => (v == null ? null : Number(v));

export function useResumoFreelancers(de: string | null, ate: string | null) {
  return useQuery({
    queryKey: ['diarias', 'resumo', de, ate],
    queryFn: async (): Promise<ResumoDosFreelancers> => {
      const { data, error } = await supabase.rpc('resumo_freelancers' as never, { p_de: de, p_ate: ate } as never);
      if (error) throw error;
      const r = data as unknown as ResumoDosFreelancers;
      return {
        pessoas: (r.pessoas ?? []).map((p) => ({
          ...p, diaria: numOuNulo(p.diaria), dias: num(p.dias), trabalhado: num(p.trabalhado),
          pago: num(p.pago), saldo_final: num(p.saldo_final),
        })),
        trabalhado: num(r.trabalhado), pago: num(r.pago), dias: num(r.dias), deve: num(r.deve), adiantado: num(r.adiantado),
      };
    },
    staleTime: 30_000,
  });
}

async function lerContaCorrente(favorecidoId: string, de: string | null, ate: string | null): Promise<ContaCorrente> {
  const { data, error } = await supabase.rpc('conta_corrente_freelancer' as never, {
    p_favorecido_id: favorecidoId, p_de: de, p_ate: ate,
  } as never);
  if (error) throw error;
  const c = data as unknown as ContaCorrente;
  return {
    ...c,
    saldo_anterior: num(c.saldo_anterior), dias: num(c.dias), trabalhado: num(c.trabalhado),
    pago: num(c.pago), saldo_final: num(c.saldo_final),
    favorecido: { ...c.favorecido, saldo_inicial: num(c.favorecido.saldo_inicial), diaria: numOuNulo(c.favorecido.diaria) },
    linhas: (c.linhas ?? []).map((l) => ({
      ...l, trabalhado: num(l.trabalhado), pago: num(l.pago), saldo: num(l.saldo),
      fracao: numOuNulo(l.fracao), valor_diaria: numOuNulo(l.valor_diaria),
      extras: numOuNulo(l.extras), descontos: numOuNulo(l.descontos), os: l.os ?? [],
    })),
  };
}

export function useContaCorrente(favorecidoId: string | null, de: string | null, ate: string | null) {
  return useQuery({
    queryKey: ['diarias', 'conta', favorecidoId, de, ate],
    enabled: !!favorecidoId,
    queryFn: () => lerContaCorrente(favorecidoId!, de, ate),
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
      queryKey: ['diarias', 'conta', id, de, ate],
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

export function useRegistrarDiaria() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (p: PedidoDeDiaria): Promise<ResultadoDaDiaria> => {
      const { data, error } = await supabase.rpc('registrar_diaria' as never, {
        p_favorecido_id: p.favorecidoId,
        p_data: p.data,
        p_jornada: p.jornada,
        p_os_ids: p.osIds ?? null,
        p_observacao: p.observacao ?? null,
        p_extras: p.extras ?? null,
        p_descontos: p.descontos ?? null,
        p_valor_diaria: p.valorDiaria ?? null,
        p_origem: 'painel',
      } as never);
      if (error) throw error;
      return data as unknown as ResultadoDaDiaria;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['diarias'] }),
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
