// Roteiro e levantamento escondidos por padrão (05/10/2026): a chave roteiro_execucao_visivel em
// app_settings decide. Sem a chave, a OS mostra Detalhes, Histórico e Tarefas; ligada, volta tudo.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { I18nProvider } from '@/i18n';

const estado = vi.hoisted(() => ({ settings: {} as Record<string, string> }));

vi.mock('@/hooks/use-app-settings', () => ({
  useAppSettings: () => ({ data: estado.settings }),
  useAppSetting: (key: string, fallback = '') => estado.settings[key] || fallback,
}));
vi.mock('@/hooks/use-service-orders', () => ({
  useServiceOrder: () => ({
    data: { id: 'os1', status: 'draft', service_order_number: 'ORÇ-00100', service_order_services: [] },
    isLoading: false, error: null,
  }),
}));
vi.mock('@/hooks/use-audit-log', () => ({ useRecordHistory: () => ({ data: [] }) }));
vi.mock('@/components/ServiceOrderForm', () => ({ ServiceOrderForm: () => <div>formulário</div> }));
vi.mock('@/components/ServiceOrderTimeline', () => ({ ServiceOrderTimeline: () => null }));
vi.mock('@/components/agenda/EntityTasksPanel', () => ({ EntityTasksPanel: () => null }));
vi.mock('@/components/service-orders/ServiceRoutePanel', () => ({ ServiceRoutePanel: () => null }));
vi.mock('@/components/service-orders/SurveyPanel', () => ({ SurveyPanel: () => null }));

import ServiceOrderDetail from './ServiceOrderDetail';

function renderOs() {
  return render(
    <I18nProvider>
      <MemoryRouter initialEntries={['/service-orders/os1']}>
        <Routes><Route path="/service-orders/:id" element={<ServiceOrderDetail />} /></Routes>
      </MemoryRouter>
    </I18nProvider>,
  );
}

describe('OS — roteiro e levantamento atrás da chave', () => {
  it('sem a chave, as abas Roteiro e Levantamento não aparecem', () => {
    estado.settings = {};
    renderOs();
    expect(screen.getByRole('tab', { name: /Detalhes da OS/ })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: /Tarefas/ })).toBeInTheDocument();
    expect(screen.queryByRole('tab', { name: /Roteiro/ })).not.toBeInTheDocument();
    expect(screen.queryByRole('tab', { name: /Levantamento/ })).not.toBeInTheDocument();
  });

  it('com a chave ligada, voltam (o levantamento só em orçamento)', () => {
    estado.settings = { roteiro_execucao_visivel: 'true' };
    renderOs();
    expect(screen.getByRole('tab', { name: /Roteiro/ })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: /Levantamento/ })).toBeInTheDocument();
  });
});
