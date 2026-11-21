// Faturas FAT-N na ficha do cliente (Fechar juntas F1, 20/11/2026): o cartão mostra total, recebido e o que
// falta; "Receber em dinheiro" à vista; "Desfazer a fatura" no menu, com confirmação; recebimento desfeito
// pelo menu da linha.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { I18nProvider } from '@/i18n';
import { FaturasDoCliente } from './FaturasDoCliente';
import type { FaturaResumo, RecebimentoDaFatura } from '@/hooks/use-faturas';

const { estado, receberMock, desfazerMock, desfazerRecebimentoMock } = vi.hoisted(() => ({
  estado: {
    faturas: [] as FaturaResumo[],
    recebimentos: [] as RecebimentoDaFatura[],
    loading: false,
  },
  receberMock: vi.fn(),
  desfazerMock: vi.fn(),
  desfazerRecebimentoMock: vi.fn(),
}));

vi.mock('@/hooks/use-faturas', () => ({
  useFaturasDoCliente: () => ({ data: estado.loading ? undefined : estado.faturas, error: null }),
  useRecebimentosDaFatura: () => ({ data: estado.recebimentos, error: null }),
  useReceberFatura: () => ({ mutate: receberMock, isPending: false }),
  useDesfazerFatura: () => ({ mutate: desfazerMock, isPending: false }),
  useDesfazerRecebimentoDaFatura: () => ({ mutate: desfazerRecebimentoMock, isPending: false }),
}));

const MP: FaturaResumo = {
  id: 'f1', numero: 'FAT-00001', clientId: 'cli', status: 'open', vencimento: '2026-07-22',
  total: 1670, recebido: 0, saldo: 1670, contas: 2, os: ['OS-00045', 'OS-00046'], criadaEm: '2026-11-20T12:00:00Z',
};

function renderizar() {
  return render(<I18nProvider><FaturasDoCliente clienteId="cli" /></I18nProvider>);
}

beforeEach(() => {
  estado.faturas = [MP];
  estado.recebimentos = [];
  estado.loading = false;
  receberMock.mockReset();
  desfazerMock.mockReset();
  desfazerRecebimentoMock.mockReset();
});

describe('FaturasDoCliente', () => {
  it('sem fatura não mostra nada; o carregando → carregado não derruba a tela', () => {
    estado.loading = true;
    const { rerender, container } = renderizar();
    expect(container).toBeEmptyDOMElement();
    estado.loading = false;
    rerender(<I18nProvider><FaturasDoCliente clienteId="cli" /></I18nProvider>);
    expect(screen.getByTestId('fatura-FAT-00001')).toBeInTheDocument();
    estado.faturas = [];
    rerender(<I18nProvider><FaturasDoCliente clienteId="cli" /></I18nProvider>);
    expect(screen.queryByTestId('faturas-do-cliente')).toBeNull();
  });

  it('o cartão mostra número, OS, total, recebido e o que falta', () => {
    renderizar();
    const cartao = screen.getByTestId('fatura-FAT-00001');
    expect(cartao).toHaveTextContent('Fatura FAT-00001');
    expect(cartao).toHaveTextContent('Aberta');
    expect(cartao).toHaveTextContent('OS-00045, OS-00046');
    expect(screen.getByTestId('fatura-FAT-00001-saldo')).toHaveTextContent(/1\.670,00/);
    expect(cartao).toHaveTextContent('Este Pix paga');
  });

  it('receber em dinheiro: abre com o que falta, recusa a mais (troco) e grava pelo hook', async () => {
    const user = userEvent.setup();
    renderizar();
    await user.click(screen.getByRole('button', { name: /Receber em dinheiro/ }));
    const dialogo = screen.getByTestId('receber-em-dinheiro');
    expect(within(dialogo).getByTestId('previa-dinheiro')).toHaveTextContent('Quita a fatura.');
    await user.click(within(dialogo).getByRole('button', { name: 'Registrar recebimento' }));
    expect(receberMock).toHaveBeenCalledTimes(1);
    expect(receberMock.mock.calls[0][0]).toMatchObject({ faturaId: 'f1', valor: 1670 });
    expect(receberMock.mock.calls[0][0].data).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it('desfazer a fatura: fica no menu e pede confirmação; com dinheiro recebido fica desabilitado', async () => {
    const user = userEvent.setup();
    const { unmount } = renderizar();
    await user.click(screen.getByRole('button', { name: /Mais ações para fatura FAT-00001/ }));
    await user.click(await screen.findByRole('menuitem', { name: /Desfazer a fatura/ }));
    expect(await screen.findByText('Desfazer a fatura FAT-00001?')).toBeInTheDocument();
    expect(desfazerMock).not.toHaveBeenCalled();
    await user.click(screen.getByRole('button', { name: 'Desfazer a fatura' }));
    expect(desfazerMock).toHaveBeenCalledWith({ faturaId: 'f1' });
    unmount();

    estado.faturas = [{ ...MP, recebido: 300, saldo: 1370 }];
    estado.recebimentos = [{ pagamentoId: 'p1', valor: 300, data: '2026-11-20', doExtrato: false, descricao: 'Saldo — OS-00045' }];
    renderizar();
    await user.click(screen.getByRole('button', { name: /Mais ações para fatura FAT-00001/ }));
    expect(await screen.findByRole('menuitem', { name: /Desfazer a fatura/ })).toHaveAttribute('aria-disabled', 'true');
  });

  it('desfazer um recebimento: pelo menu da linha, com confirmação que diz o efeito', async () => {
    const user = userEvent.setup();
    estado.faturas = [{ ...MP, recebido: 300, saldo: 1370 }];
    estado.recebimentos = [{ pagamentoId: 'p1', valor: 300, data: '2026-11-20', doExtrato: false, descricao: 'Saldo — OS-00045' }];
    renderizar();
    await user.click(screen.getByRole('button', { name: /Mais ações para recebimento de/ }));
    await user.click(await screen.findByRole('menuitem', { name: /Desfazer este recebimento/ }));
    expect(await screen.findByText(/O pagamento em dinheiro é estornado/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Desfazer o recebimento' }));
    expect(desfazerRecebimentoMock).toHaveBeenCalledWith({ pagamentoId: 'p1' });
  });

  it('quitada: sem "Receber em dinheiro"', () => {
    estado.faturas = [{ ...MP, status: 'paid', recebido: 1670, saldo: 0 }];
    renderizar();
    expect(screen.getByTestId('fatura-FAT-00001')).toHaveTextContent('Quitada');
    expect(screen.queryByRole('button', { name: /Receber em dinheiro/ })).toBeNull();
  });
});
