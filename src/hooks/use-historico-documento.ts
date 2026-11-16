import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { recalcTotals } from '@/hooks/use-service-orders';
import { logError } from '@/lib/diagnostics';

/**
 * Histórico de documentos (F4, a tela): lê public.documento_historico e restaura por
 * public.documento_restaurar (migrations 20270121100100 e 20270121100200).
 *
 * O banco já devolve tudo em português e formatado (R$, %, datas de Brasília, nomes no lugar
 * de uuid) — a tela só desenha. Leitura que dá erro LANÇA: quem desenha mostra a falha, nunca
 * "nenhuma alteração" (a casa já perdeu meses com leitura que engolia erro e virava "R$ 0").
 */

export type TipoDeDocumento =
  | 'os' | 'compra' | 'cotacao' | 'orcamento_externo' | 'cliente' | 'embarcacao' | 'produto'
  | 'servico' | 'configuracao';

export type ModoDoHistorico = 'alteracoes' | 'versoes' | 'ver_versao' | 'comparar';

export interface DocumentoDoHistorico { tipo: string; numero: string; id: string }

export interface MudancaDoHistorico {
  campo: string;
  antes: string | null;
  depois: string | null;
  /** Campo que o sistema recalcula (total, subtotal…): aparece discreto, como "recalculado". */
  calculado: boolean;
}

export interface ItemDoEvento {
  item: string;
  acao: string;
  mudancas: MudancaDoHistorico[];
  motivo: string | null;
  registro_id: string;
  /**
   * O banco sabe desfazer este item (private.historico_desfazivel): gravado pelo gatilho, de cabeçalho/peça/serviço e com
   * conteúdo. Situação, total recalculado, envio, versão e registro antigo vêm false — mandá-los só viraria "fica como está".
   */
  desfazivel: boolean;
}

export interface EventoDoHistorico {
  quando: string;
  quando_iso: string;
  quem: string;
  por_onde: string;
  /** Algum item do evento é desfazível. */
  desfazivel: boolean;
  itens: ItemDoEvento[];
}

export interface HistoricoAlteracoes {
  documento: DocumentoDoHistorico;
  modo: 'alteracoes';
  total_de_eventos: number;
  aviso: string | null;
  eventos: EventoDoHistorico[];
}

export interface VersaoDoDocumento {
  versao: number;
  marco: string | null;
  quando: string;
  quando_iso: string;
  quem: string;
  situacao: string | null;
  total: string | null;
  pecas: number | null;
  servicos: number | null;
}

export interface HistoricoVersoes {
  documento: DocumentoDoHistorico;
  modo: 'versoes';
  versoes: VersaoDoDocumento[];
}

export interface LinhaDaVersao {
  nome: string;
  quantidade: number | string | null;
  preco_unitario: string | null;
  desconto: string | null;
  total: string | null;
}

export interface ConteudoDaVersao {
  numero: string | null;
  situacao: string | null;
  situacao_do_orcamento: string | null;
  cliente: string | null;
  embarcacao: string | null;
  descricao: string | null;
  relatorio_ao_cliente: string | null;
  condicoes_de_pagamento: string | null;
  validade: string | null;
  pecas: LinhaDaVersao[] | null;
  servicos: LinhaDaVersao[] | null;
  totais: {
    mao_de_obra: string | null; pecas: string | null; deslocamento: string | null;
    desconto: string | null; impostos: string | null; total: string | null;
  } | null;
  parcelas: Array<{ descricao: string | null; vencimento: string | null; valor: string | null; situacao: string | null }> | null;
}

export interface HistoricoVerVersao {
  documento: DocumentoDoHistorico;
  modo: 'ver_versao';
  versao: number;
  marco: string | null;
  quando: string;
  quem: string;
  conteudo: ConteudoDaVersao;
}

export interface DiferencasDoDocumento {
  cabecalho: MudancaDoHistorico[];
  itens_incluidos: Array<{ item: string; quantidade: number | string | null; total: string | null }>;
  itens_removidos: Array<{ item: string; quantidade: number | string | null; total: string | null }>;
  itens_alterados: Array<{ item: string; mudancas: MudancaDoHistorico[] }>;
  sem_diferenca: boolean;
}

export interface HistoricoComparar {
  documento: DocumentoDoHistorico;
  modo: 'comparar';
  de: string;
  para: string;
  diferencas: DiferencasDoDocumento;
}

interface RetornoPorModo {
  alteracoes: HistoricoAlteracoes;
  versoes: HistoricoVersoes;
  ver_versao: HistoricoVerVersao;
  comparar: HistoricoComparar;
}

export const CHAVE_DO_HISTORICO = 'historico-documento';

/** O erro de cargo da RPC (técnico, vendedor): a tela troca por uma frase, não mostra o erro cru. */
export function ehHistoricoSemPermissao(erro: unknown): boolean {
  return (erro as { code?: string } | null)?.code === '42501';
}

/** A mensagem do banco sem o prefixo de código que às vezes vem junto. */
export function mensagemDoErro(erro: unknown): string {
  const msg = String((erro as { message?: string } | null)?.message || erro || 'erro desconhecido');
  return msg.replace(/^(ERROR:\s*)?(P0001|P0002|42501|22023):\s*/i, '');
}

export function useHistoricoDocumento<M extends ModoDoHistorico = 'alteracoes'>(p: {
  tipo: TipoDeDocumento;
  ref: string | undefined;
  modo?: M;
  versao?: number | null;
  versaoB?: number | null;
  limite?: number;
  desde?: string | null;
  ate?: string | null;
  /** Desliga a leitura (diálogo fechado, cargo que não lê). */
  enabled?: boolean;
  /** Mantém a lista na tela enquanto busca a próxima página ("mostrar mais"). */
  manterAnterior?: boolean;
}) {
  const modo = (p.modo ?? 'alteracoes') as M;
  return useQuery({
    queryKey: [CHAVE_DO_HISTORICO, p.tipo, p.ref, modo, p.versao ?? null, p.versaoB ?? null, p.limite ?? 20, p.desde ?? null, p.ate ?? null],
    queryFn: async (): Promise<RetornoPorModo[M]> => {
      const { data, error } = await supabase.rpc('documento_historico', {
        p_tipo: p.tipo,
        p_ref: p.ref!,
        p_modo: modo,
        ...(p.versao != null ? { p_versao: p.versao } : {}),
        ...(p.versaoB != null ? { p_versao_b: p.versaoB } : {}),
        ...(p.desde ? { p_desde: p.desde } : {}),
        ...(p.ate ? { p_ate: p.ate } : {}),
        p_limite: p.limite ?? 20,
      });
      if (error) throw error;
      if (!data) throw new Error('O histórico voltou vazio do banco.');
      return data as unknown as RetornoPorModo[M];
    },
    enabled: !!p.ref && (p.enabled ?? true),
    // Erro com código do banco (cargo, documento não achado, argumento) não melhora repetindo;
    // só a falha sem código (rede) tenta mais uma vez.
    retry: (falhas, erro) => !(erro as { code?: string } | null)?.code && falhas < 1,
    placeholderData: p.manterAnterior ? (anterior) => anterior : undefined,
  });
}

export interface ResultadoDaRestauracao {
  documento: string;
  /** O id do orçamento/OS (a cascata das parcelas usa este, não o número). */
  documento_id?: string;
  o_que_muda: DiferencasDoDocumento;
  nao_desfeito: Array<{ item: string; campo?: string; motivo: string }>;
  /** O que a restauração arrasta junto e não volta depois ("sai do documento e leva junto: item de pedido de compra…"). */
  avisos?: Array<{ item: string; aviso: string }>;
  total_antes: string | null;
  total_depois: string | null;
  pede_nova_assinatura: boolean;
  hash_do_documento: string;
  simulacao: boolean;
  restaurado: boolean;
  versao_nova?: number;
  mensagem?: string;
  /**
   * Preenchido só pela tela, quando a restauração GRAVOU mas a redistribuição das parcelas
   * (recalcTotals) falhou: o documento já mudou, então não é erro da restauração — é aviso.
   */
  aviso_das_parcelas?: string;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** O id do documento restaurado: o que a função devolveu; senão o que a tela passou; senão o ref, se for uuid. */
function idDaRestauracao(r: ResultadoDaRestauracao, v: { ref: string; idDoDocumento?: string | null }): string | null {
  if (r.documento_id && UUID.test(r.documento_id)) return r.documento_id;
  return v.idDoDocumento ?? (UUID.test(v.ref) ? v.ref : null);
}

export function useRestaurarDocumento() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (v: {
      /** uuid ou número do documento (ORÇ-00112 / OS-00045). */
      ref: string;
      /** Voltar para esta versão… */
      versao?: number | null;
      /** …ou desfazer estes registros (registro_id dos itens de um evento). */
      eventos?: string[] | null;
      motivo?: string | null;
      simular: boolean;
      /** O hash_do_documento da simulação: o banco recusa se o documento mudou no meio. */
      conferirHash?: string | null;
      /** O id da OS, quando `ref` é o número — para a cascata das parcelas depois de gravar. */
      idDoDocumento?: string | null;
    }): Promise<ResultadoDaRestauracao> => {
      const { data, error } = await supabase.rpc('documento_restaurar', {
        p_ref: v.ref,
        ...(v.versao != null ? { p_versao: v.versao } : {}),
        ...(v.eventos && v.eventos.length > 0 ? { p_eventos: v.eventos } : {}),
        ...(v.motivo?.trim() ? { p_motivo: v.motivo.trim() } : {}),
        p_simular: v.simular,
        ...(v.conferirHash ? { p_conferir_hash: v.conferirHash } : {}),
      });
      if (error) throw error;
      if (!data) throw new Error('A restauração voltou vazia do banco.');
      const resultado = data as unknown as ResultadoDaRestauracao;

      // A RPC recalcula o total (recalc_so_totals) mas NÃO redistribui as parcelas: a cascata
      // dos recebíveis mora em TS (recalcTotals), a mesma que roda depois de editar um item.
      if (!v.simular && resultado.restaurado) {
        const id = idDaRestauracao(resultado, v);
        if (id) {
          try {
            await recalcTotals(id);
          } catch (e) {
            resultado.aviso_das_parcelas = mensagemDoErro(e);
            void logError({
              message: `Restauração gravada, mas as parcelas não foram redistribuídas (${resultado.documento})`,
              action: 'documento_restaurar', level: 'warn', error: e,
            });
          }
        }
      }
      return resultado;
    },
    onSuccess: (resultado, v) => {
      if (v.simular || !resultado.restaurado) return;
      const id = idDaRestauracao(resultado, v);
      qc.invalidateQueries({ queryKey: ['service-orders'] });
      qc.invalidateQueries({ queryKey: id ? ['so-parts', id] : ['so-parts'] });
      qc.invalidateQueries({ queryKey: id ? ['so-services', id] : ['so-services'] });
      qc.invalidateQueries({ queryKey: id ? ['pdf-data', id] : ['pdf-data'] });
      // Restaurar documento assinado volta a pedir assinatura (requires_resignature): o quadro de assinaturas relê.
      qc.invalidateQueries({ queryKey: id ? ['so-signatures', id] : ['so-signatures'] });
      qc.invalidateQueries({ queryKey: ['receivables'] });
      qc.invalidateQueries({ queryKey: ['audit-log'] });
      qc.invalidateQueries({ queryKey: [CHAVE_DO_HISTORICO] });
    },
  });
}
