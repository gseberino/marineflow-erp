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
 */
import { useCallback } from 'react';
import { useServiceOrderSteps, useRouteMaterials } from '@/hooks/use-service-steps';
import { useServiceOrderServices } from '@/hooks/use-service-orders';
import { useServiceOrderSurvey, surveyPhotoUrl } from '@/hooks/use-service-survey';
import { useAppSettings } from '@/hooks/use-app-settings';
import { printRouteSheet, type RouteSheetHeader, type RouteSheetExtras } from '@/lib/route-sheet';

/** O que a via precisa saber da OS — tudo já está no detalhe que a tela carrega. */
export type ViaDoTecnicoHeader = Omit<
  RouteSheetHeader,
  'orderNumber' | 'companyName' | 'companyLogoUrl' | 'companyAddress' | 'companyPhone'
> & { orderNumber?: string | null };

/**
 * Cabeçalho da via a partir do detalhe da OS (o mesmo objeto que a tela de OS carrega).
 * Um só lugar: o menu Ações e o painel de Roteiro não podem imprimir folhas diferentes.
 */
export function viaHeaderFromOrder(order: any): ViaDoTecnicoHeader {
  if (!order) return {};
  return {
    orderNumber: order.service_order_number ?? null,
    clientName: order.clients?.name ?? null,
    clientPhone: order.clients?.phone ?? null,
    clientWhatsapp: order.clients?.whatsapp ?? null,
    requestedBy: order.requested_by_name ?? null,
    assetName: order.vessels?.name ?? null,
    assetType: order.vessels?.asset_type ?? null,
    assetMaker: order.vessels?.manufacturer ?? null,
    assetModel: order.vessels?.model ?? null,
    marinaName: order.marinas?.name ?? null,
    dockPosition: order.vessels?.current_dock_position ?? null,
    technicianName: order.service_order_technicians?.[0]?.app_users?.full_name ?? null,
    scheduledAt: order.scheduled_start_at ?? null,
    scheduledEndAt: order.scheduled_end_at ?? null,
    problemDescription: order.problem_description ?? null,
  };
}

export function useViaDoTecnico(serviceOrderId: string | undefined, header: ViaDoTecnicoHeader) {
  const { data: steps = [], isLoading: carregandoPassos } = useServiceOrderSteps(serviceOrderId);
  const { data: materials = [] } = useRouteMaterials(serviceOrderId);
  const { data: services } = useServiceOrderServices(serviceOrderId);
  const { data: survey } = useServiceOrderSurvey(serviceOrderId);
  const { data: settings } = useAppSettings();

  const imprimir = useCallback((): boolean => {
    const cabecalho: RouteSheetHeader = {
      ...header,
      orderNumber: header.orderNumber || 'OS',
      companyName: settings?.company_name || null,
      companyLogoUrl: settings?.company_logo_url || null,
      companyAddress: settings?.company_address || null,
      companyPhone: settings?.phone || null,
    };
    const extras: RouteSheetExtras = {
      services: ((services ?? []) as any[]).map((s) => ({
        id: s.id ?? null,
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
