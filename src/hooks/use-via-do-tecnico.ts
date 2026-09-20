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
 */
import { useCallback } from 'react';
import { useServiceOrderSteps, useRouteMaterials } from '@/hooks/use-service-steps';
import { useServiceOrderServices } from '@/hooks/use-service-orders';
import { useServiceOrderSurvey, surveyPhotoUrl } from '@/hooks/use-service-survey';
import { useAppSettings } from '@/hooks/use-app-settings';
import { printRouteSheet, type RouteSheetHeader, type RouteSheetExtras } from '@/lib/route-sheet';

export interface ViaDoTecnicoHeader {
  orderNumber?: string | null;
  clientName?: string | null;
  assetName?: string | null;
  assetType?: string | null;
  marinaName?: string | null;
  technicianName?: string | null;
  scheduledAt?: string | null;
  shareUrl?: string | null;
}

export function useViaDoTecnico(serviceOrderId: string | undefined, header: ViaDoTecnicoHeader) {
  const { data: steps = [], isLoading: carregandoPassos } = useServiceOrderSteps(serviceOrderId);
  const { data: materials = [] } = useRouteMaterials(serviceOrderId);
  const { data: services } = useServiceOrderServices(serviceOrderId);
  const { data: survey } = useServiceOrderSurvey(serviceOrderId);
  const { data: settings } = useAppSettings();

  const imprimir = useCallback((): boolean => {
    const cabecalho: RouteSheetHeader = {
      orderNumber: header.orderNumber || 'OS',
      clientName: header.clientName,
      assetName: header.assetName,
      assetType: header.assetType,
      marinaName: header.marinaName,
      technicianName: header.technicianName,
      scheduledAt: header.scheduledAt,
      shareUrl: header.shareUrl,
      companyName: settings?.company_name || null,
      companyLogoUrl: settings?.company_logo_url || null,
      companyAddress: settings?.company_address || null,
    };
    const extras: RouteSheetExtras = {
      services: ((services ?? []) as any[]).map((s) => ({
        name: s.name_snapshot || s.services?.name || 'Serviço',
        description: s.description_snapshot || null,
        quantity: s.quantity ?? null,
        unit: s.billing_unit_snapshot || null,
        notes: s.notes || null,
      })),
      survey: (((survey as any)?.service_survey_answers ?? []) as any[])
        .slice()
        .sort((a, b) => Number(a.seq ?? 0) - Number(b.seq ?? 0))
        .map((a) => ({
          question: a.question_snapshot || '',
          answer: a.answer_value ?? null,
          skipped: a.skipped_reason ?? null,
          photoUrl: a.photo_path ? surveyPhotoUrl(a.photo_path) : null,
        })),
    };
    return printRouteSheet(cabecalho, steps, materials, extras);
  }, [header, settings, services, survey, steps, materials]);

  return { imprimir, carregando: carregandoPassos };
}
