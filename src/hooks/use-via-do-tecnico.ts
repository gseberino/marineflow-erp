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
 * 16/11/2026 (porte da via v2, F1): a via aprovada não imprime mais a segurança por sistema — o quadro
 * Atenção sai do sistema de cada linha —, então a RPC seguranca_da_via saiu daqui (E14). E a via só se
 * imprime com os serviços, o material e o cabeçalho já carregados (`carregando`): imprimir antes saía
 * com a folha pela metade.
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
  printRouteSheet, faltasDaVia, montarViaDoTecnico, ehLinhaDeCobranca,
  type RouteSheetHeader, type ViaDoTecnicoHeader, type LinhaDaVia,
} from '@/lib/route-sheet';

export { viaHeaderFromOrder, type ViaDoTecnicoHeader } from '@/lib/route-sheet';

export function useViaDoTecnico(serviceOrderId: string | undefined, header: ViaDoTecnicoHeader) {
  const { data: steps = [], isLoading: carregandoPassos } = useServiceOrderSteps(serviceOrderId);
  const { data: materials = [], isLoading: carregandoMateriais } = useRouteMaterials(serviceOrderId);
  const { data: services, isLoading: carregandoServicos } = useServiceOrderServices(serviceOrderId);
  const { data: survey } = useServiceOrderSurvey(serviceOrderId);
  const { data: settings } = useAppSettings();
  // Fotos do levantamento em bucket privado (04/10/2026): os links temporários vêm ANTES do
  // clique em imprimir — a folha abre numa janela nova e um await no meio a faria ser
  // bloqueada como pop-up. Link que ainda não chegou só deixa a foto de fora do papel.
  const { data: linksDasFotos = {} } = useLinksDasFotos(
    (((survey as any)?.service_survey_answers ?? []) as any[]).map((a) => a.photo_path as string),
  );

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
   * `via` (menu Ações): a via aprovada — sem passo de roteiro, com o quadro Atenção.
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
        nomesDosResponsaveis,
      },
      { modo, linksDasFotos },
    );
    return printRouteSheet(montada.header, montada.passos, montada.materiais, montada.extras);
  }, [header, settings, services, survey, steps, materials, linksDasFotos, serviceOrderId, nomesDosResponsaveis]);

  // O que vai faltar no papel, para o aviso antes de imprimir. Serviços = os que vão ao papel (sem a cobrança, 4A);
  // o cabeçalho é o completo (os telefones saem no fechamento, mas contam aqui).
  const faltas = useMemo(
    () => faltasDaVia(
      header as RouteSheetHeader, materials,
      ((services ?? []) as LinhaDaVia[]).filter((l) => !ehLinhaDeCobranca(l)).length,
    ),
    [header, materials, services],
  );

  // A via só se imprime com o que vai ao papel já carregado: serviços, material e o cabeçalho da OS (e o roteiro, do
  // painel). O menu fica desabilitado com "carregando…" enquanto isso.
  const carregando = !!serviceOrderId
    && (carregandoPassos || carregandoMateriais || carregandoServicos || !header?.orderNumber);

  return { imprimir, carregando, faltas };
}
