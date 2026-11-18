import { useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { EVENTO_REVISAO_EMITIDA } from '@/lib/pdf-revisao';
import { dataBR } from '../../supabase/functions/_shared/pdf/datas';

/**
 * A revisão do documento na tela (17/11/2026): qual é a atual, qual o cliente RECEBEU, qual ele aprovou, e se o que
 * está na tela já mudou desde a última emitida — o caso que o dono quer ver antes de o cliente aprovar um preço velho.
 *
 * Lê public.documento_revisao_situacao. Falhou (migration ainda não aplicada, rede)? Não mostra nada: a revisão é
 * informação a mais, nunca bloqueio.
 */

export type RevisaoNaSituacao = {
  revisao: number;
  codigo: string;
  emitida_em: string;
  enviada_em: string | null;
  enviada_via: string | null;
  aprovada_em: string | null;
  assinada_em: string | null;
};

export type SituacaoDaRevisao = {
  tipo: 'quote' | 'service_order' | 'invoice';
  atual: RevisaoNaSituacao | null;
  enviada: RevisaoNaSituacao | null;
  aprovada: RevisaoNaSituacao | null;
  mudou_desde_a_ultima: boolean;
};

export function useRevisaoDoDocumento(orderId: string | undefined, versaoDaTela?: string | null) {
  const consulta = useQuery({
    // A "versão da tela" (o carimbo do último salvamento) entra na chave: salvou, o "mudou desde a Rev. N" é relido.
    queryKey: ['documento-revisao', orderId, versaoDaTela ?? null],
    enabled: !!orderId,
    retry: false,
    staleTime: 30_000,
    queryFn: async (): Promise<SituacaoDaRevisao | null> => {
      const { data, error } = await supabase.rpc('documento_revisao_situacao', { p_os: orderId! });
      if (error) {
        console.warn('[revisão] situação indisponível:', error.message);
        return null;
      }
      return (data as unknown as SituacaoDaRevisao) ?? null;
    },
  });

  // Gerou um PDF (Baixar, Imprimir, WhatsApp) desta ordem: a revisão pode ter subido — relê.
  const { refetch } = consulta;
  useEffect(() => {
    if (!orderId) return;
    const ouvir = (e: Event) => {
      if ((e as CustomEvent<string>).detail === orderId) void refetch();
    };
    window.addEventListener(EVENTO_REVISAO_EMITIDA, ouvir);
    return () => window.removeEventListener(EVENTO_REVISAO_EMITIDA, ouvir);
  }, [orderId, refetch]);

  return consulta;
}

/**
 * O que a tela diz da revisão: uma frase CURTA para a linha sob o número ("Rev. 3 · cliente tem a Rev. 2") e a
 * COMPLETA para a dica, com as datas. `alerta` = há algo a fazer (o cliente não tem a revisão atual, ou a tela já
 * mudou desde a última). Sem revisão emitida ainda (nenhum PDF gerado), nada.
 */
export function textoDaRevisao(s: SituacaoDaRevisao | null | undefined): { curto: string; completo: string; alerta: boolean } | null {
  if (!s?.atual) return null;
  const n = s.atual.revisao;
  const curto: string[] = [`Rev. ${n}`];
  const completo: string[] = [`Última revisão emitida: Rev. ${n}, em ${dataBR(s.atual.emitida_em)} (código ${s.atual.codigo}).`];
  let alerta = false;

  if (s.aprovada) {
    const quando = s.aprovada.assinada_em ?? s.aprovada.aprovada_em;
    const verbo = s.aprovada.assinada_em ? 'assinada' : 'aprovada';
    curto.push(s.aprovada.revisao === n ? verbo : `${verbo} na Rev. ${s.aprovada.revisao}`);
    completo.push(`O cliente ${s.aprovada.assinada_em ? 'assinou' : 'aprovou'} a Rev. ${s.aprovada.revisao}${quando ? ` em ${dataBR(quando)}` : ''}.`);
    if (s.aprovada.revisao !== n) alerta = true;
  } else if (s.enviada) {
    if (s.enviada.revisao === n) {
      curto.push('enviada ao cliente');
    } else {
      curto.push(`cliente tem a Rev. ${s.enviada.revisao}`);
      alerta = true;
    }
    completo.push(`O cliente recebeu a Rev. ${s.enviada.revisao}${s.enviada.enviada_em ? ` em ${dataBR(s.enviada.enviada_em)}` : ''}.`);
  } else {
    completo.push('Nenhuma revisão foi registrada como enviada ao cliente.');
  }

  if (s.mudou_desde_a_ultima) {
    curto.push(`alterado depois da Rev. ${n}`);
    completo.push(`O documento mudou depois da Rev. ${n}: o próximo PDF sai como Rev. ${n + 1}.`);
    alerta = true;
  }
  return { curto: curto.join(' · '), completo: completo.join(' '), alerta };
}
