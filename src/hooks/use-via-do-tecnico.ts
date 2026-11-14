/**
 * Via do técnico (job card) da OS: a folha de roteiro terminada.
 *
 * Reúne o que a folha precisa — passos, separação de materiais, serviços contratados e o
 * levantamento respondido (com fotos) — e imprime pela mesma função de sempre
 * (`printRouteSheet`). É um hook para que o painel de Roteiro e o menu Ações da OS chamem
 * exatamente a mesma folha, sem duplicar consulta nenhuma.
 *
 * Decisões do dono (12/08/2026): a via técnica leva o levantamento inteiro com as fotos;
 * preço não vai na via do técnico; assinatura de técnico e cliente no papel.
 * Decisões de 01/10/2026: o pedido do cliente (descrição da OS) sai na via; o link do
 * portal do cliente não sai (mostra preço).
 * 13/11/2026: a montagem (dados → folha) é a mesma do PDF que o assistente e a agenda mandam pelo
 * WhatsApp (montarViaDoTecnico, em supabase/functions/_shared/pdf/via-do-tecnico.ts). A tela
 * imprime a via da OS inteira, com o responsável de cada serviço.
 */
import { useCallback, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { useServiceOrderSteps, useRouteMaterials } from '@/hooks/use-service-steps';
import { useServiceOrderServices } from '@/hooks/use-service-orders';
import { useServiceOrderSurvey } from '@/hooks/use-service-survey';
import { useLinksDasFotos } from '@/lib/fotos-da-os';
import { useAppSettings } from '@/hooks/use-app-settings';
import {
  printRouteSheet, faltasDaVia, passosDeSeguranca, montarViaDoTecnico,
  type RouteSheetHeader, type LinhaDeSeguranca, type ViaDoTecnicoHeader, type LinhaDaVia,
} from '@/lib/route-sheet';

export { viaHeaderFromOrder, type ViaDoTecnicoHeader } from '@/lib/route-sheet';

export function useViaDoTecnico(serviceOrderId: string | undefined, header: ViaDoTecnicoHeader) {
  const { data: steps = [], isLoading: carregandoPassos } = useServiceOrderSteps(serviceOrderId);
  const { data: materials = [] } = useRouteMaterials(serviceOrderId);
  const { data: services } = useServiceOrderServices(serviceOrderId);
  const { data: survey } = useServiceOrderSurvey(serviceOrderId);
  const { data: settings } = useAppSettings();
  // Fotos do levantamento em bucket privado (04/10/2026): os links temporários vêm ANTES do
  // clique em imprimir — a folha abre numa janela nova e um await no meio a faria ser
  // bloqueada como pop-up. Link que ainda não chegou só deixa a foto de fora do papel.
  const { data: linksDasFotos = {} } = useLinksDasFotos(
    (((survey as any)?.service_survey_answers ?? []) as any[]).map((a) => a.photo_path as string),
  );

  // Segurança sem roteiro (05/10/2026): nenhuma OS ganhou roteiro desde 14/08 e a via saía sem os
  // blocos de segurança. O banco devolve os blocos de cada sistema da OS SEM gravar roteiro
  // (seguranca_da_via); vêm antes do clique, porque imprimir abre janela e não pode esperar.
  const { data: linhasDeSeguranca = [], isSuccess: segurancaCarregada } = useQuery({
    queryKey: ['seguranca-da-via', serviceOrderId],
    enabled: !!serviceOrderId,
    queryFn: async (): Promise<LinhaDeSeguranca[]> => {
      const { data, error } = await supabase.rpc('seguranca_da_via', { p_service_order_id: serviceOrderId! });
      if (error) throw error;
      return (data ?? []) as LinhaDeSeguranca[];
    },
  });
  const temSegurancaNoRoteiro = passosDeSeguranca(steps).length > 0;

  // O nome de quem faz cada serviço (13/11/2026): a via da OS inteira diz o responsável de cada um.
  const idsDosResponsaveis = useMemo(
    () => [...new Set(((services ?? []) as LinhaDaVia[]).map((s) => s.responsavel_payee_id).filter((id): id is string => !!id))].sort(),
    [services],
  );
  const { data: nomesDosResponsaveis = {} } = useQuery({
    queryKey: ['via-responsaveis', idsDosResponsaveis],
    enabled: idsDosResponsaveis.length > 0,
    queryFn: async (): Promise<Record<string, string>> => {
      const { data, error } = await supabase.from('payees').select('id, name').in('id', idsDosResponsaveis);
      if (error) throw error;
      return Object.fromEntries(((data ?? []) as Array<{ id: string; name: string }>).map((p) => [p.id, p.name]));
    },
  });

  /**
   * `via` (menu Ações): a folha do técnico, com só a segurança de cada sistema do roteiro.
   * `roteiro` (painel Roteiro): a mesma folha com o roteiro completo, para testá-lo à parte.
   */
  const imprimir = useCallback((modo: 'via' | 'roteiro' = 'via'): boolean => {
    const montada = montarViaDoTecnico(
      {
        serviceOrderId: serviceOrderId ?? '',
        header,
        empresa: {
          nome: settings?.company_name || null,
          logoUrl: settings?.company_logo_url || null,
          endereco: settings?.company_address || null,
          telefone: settings?.phone || null,
        },
        linhas: (services ?? []) as LinhaDaVia[],
        passos: steps,
        materiais: materials,
        levantamento: ((survey as any)?.service_survey_answers ?? []) as any[],
        // Sem o id da OS a segurança não entra (como antes: o hook só a somava com o id).
        seguranca: serviceOrderId ? linhasDeSeguranca : [],
        nomesDosResponsaveis,
      },
      { modo, linksDasFotos },
    );
    return printRouteSheet(montada.header, montada.passos, montada.materiais, montada.extras);
  }, [header, settings, services, survey, steps, materials, linksDasFotos, linhasDeSeguranca, serviceOrderId, nomesDosResponsaveis]);

  // O que vai faltar no papel, para o aviso antes de imprimir.
  const faltas = useMemo(
    () => faltasDaVia(
      header as RouteSheetHeader, materials, (services ?? []).length,
      segurancaCarregada && !temSegurancaNoRoteiro && linhasDeSeguranca.length === 0,
    ),
    [header, materials, services, temSegurancaNoRoteiro, linhasDeSeguranca, segurancaCarregada],
  );

  return { imprimir, carregando: carregandoPassos, faltas };
}
