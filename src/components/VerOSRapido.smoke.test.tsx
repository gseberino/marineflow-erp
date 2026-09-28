// "Ver OS" na fila do Extrato (pedido do dono, 28/09/2026): o mesmo cliente com mais de uma OS,
// e a despesa tem de ir para a certa. A janela mostra o que distingue uma OS da outra e é SÓ DE
// LEITURA — mudar é na tela da OS.
import { describe, it, expect, vi } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { I18nProvider } from '@/i18n';
import { BotaoVerOS } from './VerOSRapido';

const { osPorId } = vi.hoisted(() => ({
  osPorId: {
    os60: {
      service_order_number: 'OS-00060', status: 'in_progress', created_at: '2026-09-10T12:00:00Z',
      problem_description: 'Trocar o carregador de baterias', grand_total: 4800,
      clients: { name: 'João da Silva' },
      vessels: { name: 'Mar Azul', manufacturer: 'Schaefer', model: '400' },
      marinas: { name: 'Marina Itajaí' },
      service_order_services: [{ id: 's1', quantity: 1, name_snapshot: 'Instalação elétrica', services: null }],
      service_order_parts: [{ id: 'pc1', quantity: 2, notes: null, products: { name: 'Carregador 40A' } }],
      service_order_technicians: [{ id: 't1', app_users: { full_name: 'Roberto' } }],
    },
    // Como o técnico lê (a view sem valores): a OS vem sem grand_total.
    os61: {
      service_order_number: 'OS-00061', status: 'in_progress', clients: { name: 'João da Silva' },
      vessels: { name: 'Mar Azul' }, service_order_services: [], service_order_parts: [],
    },
  } as Record<string, unknown>,
}));

vi.mock('@/hooks/use-service-orders', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/use-service-orders')>()),
  useServiceOrder: (id: string | undefined) => ({ data: id ? osPorId[id] ?? null : null, isLoading: false, error: null }),
}));

function renderBotao(osId: string | null) {
  return render(
    <MemoryRouter>
      <I18nProvider>
        <BotaoVerOS osId={osId} />
      </I18nProvider>
    </MemoryRouter>,
  );
}

async function abrir(osId: string) {
  const user = userEvent.setup();
  renderBotao(osId);
  await user.click(screen.getByRole('button', { name: 'Ver OS (só leitura)' }));
  return screen.findByRole('dialog');
}

describe('Ver OS sem sair da fila', () => {
  it('sem OS escolhida, o botão não aparece', () => {
    renderBotao(null);
    expect(screen.queryByRole('button')).not.toBeInTheDocument();
  });

  it('mostra o que distingue uma OS da outra: cliente, barco, o pedido, serviços e peças', async () => {
    const janela = await abrir('os60');
    expect(within(janela).getByText('OS-00060')).toBeInTheDocument();
    expect(within(janela).getByText('João da Silva')).toBeInTheDocument();
    expect(within(janela).getByText('Mar Azul · Schaefer · 400')).toBeInTheDocument();
    expect(within(janela).getByText('Marina Itajaí')).toBeInTheDocument();
    expect(within(janela).getByText('Trocar o carregador de baterias')).toBeInTheDocument();
    expect(within(janela).getByText('Instalação elétrica')).toBeInTheDocument();
    expect(within(janela).getByText('2× Carregador 40A')).toBeInTheDocument();
    expect(within(janela).getByText('Roberto')).toBeInTheDocument();
    expect(within(janela).getByText('Valor da OS')).toBeInTheDocument();
  });

  it('é só de leitura: nenhum campo, e mudar é na tela da OS, em outra aba', async () => {
    const janela = await abrir('os60');
    expect(within(janela).queryAllByRole('textbox')).toHaveLength(0);
    expect(within(janela).queryAllByRole('combobox')).toHaveLength(0);
    const link = within(janela).getByRole('link', { name: /Abrir a OS em outra aba/ });
    expect(link).toHaveAttribute('href', '/v2/service-orders/os60');
    expect(link).toHaveAttribute('target', '_blank');
  });

  it('OS lida sem valores (técnico) não mostra a linha do valor', async () => {
    const janela = await abrir('os61');
    expect(within(janela).getByText('OS-00061')).toBeInTheDocument();
    expect(within(janela).queryByText('Valor da OS')).not.toBeInTheDocument();
  });

  it('OS que não abre diz isso, em vez de uma janela vazia', async () => {
    const janela = await abrir('os-que-sumiu');
    expect(within(janela).getByText(/Não consegui abrir esta OS agora/)).toBeInTheDocument();
  });
});
