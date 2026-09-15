// Smoke de render do painel "IA acompanhando" — a tela nova do "Deixar a IA acompanhar".
// Protege o que só o render mostra: o cartão da missão com status legível, a trilha
// abrindo, o estado vazio que ensina onde o botão fica, e o kill switch presente.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import { I18nProvider } from '@/i18n';
import FollowupMissionsV2 from './FollowupMissionsV2';

const { estado } = vi.hoisted(() => ({ estado: { missoes: [] as any[] } }));

vi.mock('@/hooks/use-followup-missions', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/hooks/use-followup-missions')>();
  return {
    ...real,
    useFollowupMissions: () => ({ data: estado.missoes, isLoading: false, error: null }),
    useFollowupEvents: () => ({
      data: [
        { id: 'e1', mission_id: 'm1', tipo: 'created', conteudo: 'confirmar a entrega das baterias', created_at: '2026-09-14T12:00:00Z' },
        { id: 'e2', mission_id: 'm1', tipo: 'draft', conteudo: 'Olá Vanderlei, aqui é o assistente da HBR…', created_at: '2026-09-15T12:15:00Z' },
      ],
      isLoading: false,
    }),
    useCancelFollowupMission: () => ({ mutateAsync: vi.fn(), isPending: false }),
    useFollowupSwitch: () => ({ ligado: true, isLoading: false, alternar: vi.fn(), isPending: false }),
    useFollowupMissionDaOrigem: () => ({ data: null, isLoading: false }),
    useCreateFollowupMission: () => ({ mutateAsync: vi.fn(), isPending: false }),
  };
});

// "Depende deles": um fio solto de fornecedor sem missão vira candidato com o botão ao lado.
vi.mock('@/hooks/use-agenda', () => ({
  useOpenLoops: () => ({
    data: [{
      id: 'loop1', kind: 'entrega', source: 'conversation', title: 'Entrega das baterias LiFePO4',
      detail: 'Vanderlei prometeu para a próxima semana', due_at: '2026-09-22T12:00:00Z', priority: 'high',
      service_order_id: null, service_order_number: null, mentions: 2, evidence: null,
      opened_at: '2026-09-10T12:00:00Z', last_seen_at: '2026-09-14T12:00:00Z', atrasado: false,
      direction: 'theirs', entity_type: 'supplier', entity_id: 's1', entity_name: 'Vanderlei Andrade',
    }],
    isLoading: false,
  }),
}));
vi.mock('@/hooks/use-suppliers', () => ({ useSuppliers: () => ({ data: [] }) }));

function renderPainel() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <I18nProvider>
        <MemoryRouter initialEntries={['/v2/agenda/acompanhamentos']}>
          <FollowupMissionsV2 />
        </MemoryRouter>
      </I18nProvider>
    </QueryClientProvider>,
  );
}

describe('FollowupMissionsV2 — IA acompanhando', () => {
  it('vazio ensina onde o botão fica, mostra o kill switch e lista o que depende deles', () => {
    estado.missoes = [];
    renderPainel();
    expect(screen.getByRole('heading', { name: /IA acompanhando/ })).toBeInTheDocument();
    expect(screen.getByText(/clique em "Deixar a IA acompanhar"/)).toBeInTheDocument();
    expect(screen.getByRole('switch', { name: /Acompanhamento pela IA/ })).toBeInTheDocument();
    // o fio solto do fornecedor aparece como candidato, com o botão de acompanhar
    expect(screen.getByText(/Depende deles/)).toBeInTheDocument();
    expect(screen.getByText('Entrega das baterias LiFePO4')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Deixar a IA acompanhar/ })).toBeInTheDocument();
  });

  it('mostra a missão com status legível e abre a trilha', async () => {
    estado.missoes = [{
      id: 'm1', objetivo: 'confirmar a entrega das baterias', contraparte_tipo: 'supplier', contraparte_id: 's1',
      contraparte_phone: '5547999990000', contraparte_label: 'Vanderlei Andrade', origem_tipo: 'agenda_task', origem_id: 't1',
      service_order_id: null, criterio_erp: 'task_done', prazo_final: '2026-10-01T12:00:00Z', max_toques: 3, toques_feitos: 1,
      proximo_toque_em: '2026-09-28T12:00:00Z', ultimo_toque_em: '2026-09-15T13:00:00Z', status: 'active',
      resolucao: null, resolucao_evidencia: null, resolvida_em: null, created_at: '2026-09-14T12:00:00Z',
    }];
    renderPainel();
    // O nome aparece no cartão da missão E no candidato "depende deles" (fio de outra origem).
    expect(screen.getAllByText('Vanderlei Andrade').length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText('Cobrando')).toBeInTheDocument();
    expect(screen.getByText(/Toques 1\/3/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /Trilha/ }));
    expect(await screen.findByText(/Rascunho para sua aprovação/)).toBeInTheDocument();
    expect(screen.getByText(/assistente da HBR/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Encerrar/ })).toBeInTheDocument();
  });
});
