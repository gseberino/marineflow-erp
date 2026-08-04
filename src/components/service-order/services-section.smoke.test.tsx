// Regressão de layout: o nome do serviço sumia quando a linha tinha o aviso de
// classificação.
//
// A linha é um flex horizontal e o nome vive num `flex-1 min-w-0` com truncate.
// O aviso foi colocado no meio da linha, entre os valores e os botões, com
// largura própria — o flex espremeu o nome até zero e ele desapareceu da tela
// (visto pelo dono em 03/08, em OS de motorhome). Bloco largo agora vai no slot
// `below`, com a largura toda embaixo da linha.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { I18nProvider } from '@/i18n';
import { ServicesSection } from './services-section';

const { linhaPendente } = vi.hoisted(() => ({
  linhaPendente: {
    line_id: 'l1',
    service_name: 'Cabo elétrico 16mm²',
    service_verb: null,
    sistema_sugerido: 'eletrico_dc',
    verbo_sugerido: null,
    origem_sistema: 'linha' as const,
    origem_verbo: null,
  },
}));

vi.mock('@/hooks/use-service-steps', async (orig) => ({
  ...(await orig<any>()),
  useServiceOrderSteps: () => ({ data: [], isLoading: false }),
}));

vi.mock('@/hooks/use-service-systems', async (orig) => ({
  ...(await orig<any>()),
  useLinesMissingSystem: () => ({ data: [linhaPendente], isLoading: false }),
  useServiceSystems: () => ({ data: [{ slug: 'eletrico_dc', name: 'Elétrico DC (12/24V)', short_name: 'Elétrico DC', is_physical: true, sort: 10, active: true }] }),
  useServiceVerbs: () => ({ data: [{ slug: 'instalacao', name: 'Instalação', intervem_no_sistema: true, sort: 10, active: true }] }),
  useSetLineClassification: () => ({ mutate: () => {}, isPending: false }),
}));

vi.mock('@/components/ServiceTimer', () => ({ ServiceTimer: () => <span>timer</span> }));

const noop = () => {};

function renderSection() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <ServicesSection
          isNew={false}
          orderId="os1"
          services={[]}
          soServices={[{
            id: 'l1',
            name_snapshot: 'Cabo elétrico 16mm²',
            description_snapshot: null,
            billing_unit_snapshot: 'unit',
            quantity: 1,
            unit_price_snapshot: 980,
            line_total: 980,
            discount_pct: 0,
            discount_amount: 0,
            started_at: null,
            finished_at: null,
            elapsed_minutes: 0,
          }]}
          appUsers={[]}
          servicesItemCount={1}
          laborCost={980}
          billableHours={0}
          draftServices={[]}
          setDraftServices={noop}
          editingSvc={{}}
          setEditingSvc={noop}
          openNewSvcCards={[]}
          setOpenNewSvcCards={noop}
          setShowNewServiceDialog={noop}
          addNewSvcCard={noop}
          cancelSvcCard={noop}
          handleConfirmNewSvcCard={noop}
          handleConfirmEditSvc={noop}
          startEditPersisted={noop}
          applyQuickDiscountToService={noop}
          updateSvcLine={{ isPending: false }}
          removeService={{ mutate: noop }}
          addService={{ mutate: noop }}
        />
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('ServicesSection — linha com aviso de classificação', () => {
  it('renderiza o nome do serviço e o aviso', () => {
    renderSection();
    expect(screen.getByText('Cabo elétrico 16mm²')).toBeTruthy();
    expect(screen.getByText(/não entra no roteiro/)).toBeTruthy();
    expect(screen.getAllByText(/980/).length).toBeGreaterThan(0);
  });

  it('o aviso fica FORA da linha horizontal — é isso que devolve o espaço ao nome', () => {
    renderSection();

    // jsdom não calcula layout, então verificar "o nome está visível" não pegaria
    // a regressão: com truncate ele continuava no DOM, apenas espremido a zero.
    // O que se verifica aqui é a estrutura: o aviso não pode ser descendente do
    // mesmo flex que disputa largura com o nome.
    const nome = screen.getByText('Cabo elétrico 16mm²');
    const aviso = screen.getByText(/não entra no roteiro/);

    const linhaFlex = nome.closest('div.flex.items-center');
    expect(linhaFlex).toBeTruthy();
    expect(linhaFlex!.contains(aviso)).toBe(false);
  });
});
