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
import { useCallback, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { useServiceOrderSteps, useRouteMaterials } from '@/hooks/use-service-steps';
import { useServiceOrderServices } from '@/hooks/use-service-orders';
import { useServiceOrderSurvey } from '@/hooks/use-service-survey';
import { useLinksDasFotos } from '@/lib/fotos-da-os';
import { useAppSettings } from '@/hooks/use-app-settings';
import { VESSEL_CONTACT_ROLES } from '@/hooks/use-vessel-contacts';
import {
  printRouteSheet, faltasDaVia, passosDeSeguranca, segurancaSemRoteiro,
  type RouteSheetHeader, type RouteSheetExtras, type LinhaDeSeguranca,
} from '@/lib/route-sheet';

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
    technicianInstructions: order.technician_instructions ?? null,
    // O local da OS manda; sem ele, vale o padrão do cadastro do veículo.
    siteAccess: order.site_access || order.vessels?.access_notes || null,
    onSiteContact: order.requested_by_contact
      ? {
          name: order.requested_by_contact.full_name ?? null,
          role: VESSEL_CONTACT_ROLES.find((r) => r.value === order.requested_by_contact.role)?.label
            ?? order.requested_by_contact.role ?? null,
          phone: order.requested_by_contact.phone ?? null,
        }
      : null,
    vehicleElectrical: order.vessels
      ? {
          batteryBank: order.vessels.battery_bank_summary ?? null,
          inverterCharger: order.vessels.inverter_charger_summary ?? null,
          shorePower: order.vessels.shore_power_type ?? null,
          notes: order.vessels.electrical_system_notes ?? null,
        }
      : null,
  };
}

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

  /**
   * `via` (menu Ações): a folha do técnico, com só a segurança de cada sistema do roteiro.
   * `roteiro` (painel Roteiro): a mesma folha com o roteiro completo, para testá-lo à parte.
   */
  const imprimir = useCallback((modo: 'via' | 'roteiro' = 'via'): boolean => {
    const cabecalho: RouteSheetHeader = {
      ...header,
      orderNumber: header.orderNumber || 'OS',
      companyName: settings?.company_name || null,
      companyLogoUrl: settings?.company_logo_url || null,
      companyAddress: settings?.company_address || null,
      companyPhone: settings?.phone || null,
    };
    const extras: RouteSheetExtras = {
      roteiro: modo === 'via' ? 'seguranca' : 'completo',
      services: ((services ?? []) as any[]).map((s) => ({
        id: s.id ?? null,
        name: s.name_snapshot || s.services?.name || 'Serviço',
        description: s.description_snapshot || null,
        quantity: s.quantity ?? null,
        unit: s.billing_unit_snapshot || null,
        notes: s.notes || null,
        technicianInstructions: s.technician_instructions || null,
        fieldStatus: s.field_status || null,
        fieldStatusNote: s.field_status_note || null,
      })),
      survey: (((survey as any)?.service_survey_answers ?? []) as any[])
        .slice()
        .sort((a, b) => Number(a.seq ?? 0) - Number(b.seq ?? 0))
        .map((a) => ({
          question: a.question_snapshot || '',
          answer: a.answer_value ?? null,
          skipped: a.skipped_reason ?? null,
          photoUrl: a.photo_path ? linksDasFotos[a.photo_path] ?? null : null,
        })),
    };
    const passos = modo === 'via' && !temSegurancaNoRoteiro && serviceOrderId
      ? [...steps, ...segurancaSemRoteiro(serviceOrderId, linhasDeSeguranca)]
      : steps;
    return printRouteSheet(cabecalho, passos, materials, extras);
  }, [header, settings, services, survey, steps, materials, linksDasFotos, temSegurancaNoRoteiro, linhasDeSeguranca, serviceOrderId]);

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
