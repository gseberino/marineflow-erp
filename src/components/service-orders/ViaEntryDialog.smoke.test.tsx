// Smoke da tela "Lançar a via": o escritório passa o papel para o sistema.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ViaEntryDialog } from './ViaEntryDialog';

const { chamadas } = vi.hoisted(() => ({ chamadas: [] as any[] }));

vi.mock('@/hooks/use-lancar-via', () => ({
  useLancarVia: () => ({
    mutateAsync: async (args: any) => { chamadas.push(args); return { servicos: 1, technicianNotes: 'notas novas', internalNotes: undefined }; },
    isPending: false,
  }),
}));

function renderDialog(onSaved = vi.fn()) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={qc}>
      <ViaEntryDialog
        open
        onOpenChange={() => {}}
        orderId="os1"
        orderNumber="OS-00104"
        services={[
          { id: 'l1', name_snapshot: 'Conversão da geladeira para 12V', field_status: 'a_fazer' },
          { id: 'l2', name_snapshot: 'Tampa da boia', field_status: 'so_levantar' },
        ]}
        notasAtuais="antes"
        onSaved={onSaved}
      />
    </QueryClientProvider>,
  );
  return onSaved;
}

describe('ViaEntryDialog — Lançar a via', () => {
  it('mostra os serviços da OS na ordem da folha', () => {
    renderDialog();
    expect(screen.getByText(/Lançar a via · OS-00104/)).toBeTruthy();
    expect(screen.getByText('1 · Conversão da geladeira para 12V')).toBeTruthy();
    expect(screen.getByText('2 · Tampa da boia')).toBeTruthy();
  });

  it('sem nada preenchido, o botão Lançar fica apagado', () => {
    renderDialog();
    expect((screen.getByRole('button', { name: 'Lançar' }) as HTMLButtonElement).disabled).toBe(true);
  });

  it('não feito pede o motivo e grava a situação da linha', async () => {
    const user = userEvent.setup();
    const onSaved = renderDialog();
    const grupo = screen.getByRole('group', { name: /Conversão da geladeira/ });
    await user.click(grupo.querySelectorAll('button')[2]); // Não feito
    await user.type(screen.getByLabelText(/Motivo — Conversão/), 'faltou o filtro secador');
    await user.click(screen.getByRole('button', { name: 'Lançar' }));
    expect(chamadas.length).toBe(1);
    expect(chamadas[0].orderId).toBe('os1');
    expect(chamadas[0].notasAtuais).toBe('antes');
    expect(chamadas[0].lancamento.servicos.l1).toEqual({ situacao: 'nao_feito', motivo: 'faltou o filtro secador' });
    // A tela da OS recebe as notas novas, para o salvamento automático não desfazê-las.
    expect(onSaved).toHaveBeenCalledWith({ technicianNotes: 'notas novas', internalNotes: undefined });
  });
});
