// useConfirmacao: o texto de voltar e o aviso de desistência, que não pode disparar ao confirmar.
import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { useConfirmacao } from './Confirmacao';

function Tela({ acao, aoVoltar, voltar, aoFechar }: {
  acao: () => void; aoVoltar?: () => void; voltar?: string; aoFechar?: () => void;
}) {
  const { pedir, dialogo } = useConfirmacao();
  return (
    <>
      <button onClick={() => pedir({ titulo: 'Trocar?', confirmar: 'Trocar', acao, aoVoltar, voltar, aoFechar })}>abrir</button>
      <button>outro</button>
      {dialogo}
    </>
  );
}

describe('useConfirmacao', () => {
  it('sem texto próprio, o botão de desistir continua "Voltar"', async () => {
    const user = userEvent.setup();
    render(<Tela acao={vi.fn()} />);
    await user.click(screen.getByText('abrir'));
    expect(screen.getByRole('button', { name: 'Voltar' })).toBeInTheDocument();
  });

  it('desistir pelo botão chama aoVoltar e não a ação', async () => {
    const user = userEvent.setup();
    const acao = vi.fn();
    const aoVoltar = vi.fn();
    render(<Tela acao={acao} aoVoltar={aoVoltar} voltar="Manter o cliente atual" />);
    await user.click(screen.getByText('abrir'));
    await user.click(screen.getByRole('button', { name: 'Manter o cliente atual' }));
    expect(aoVoltar).toHaveBeenCalledTimes(1);
    expect(acao).not.toHaveBeenCalled();
  });

  it('Esc também é desistir', async () => {
    const user = userEvent.setup();
    const aoVoltar = vi.fn();
    render(<Tela acao={vi.fn()} aoVoltar={aoVoltar} />);
    await user.click(screen.getByText('abrir'));
    await user.keyboard('{Escape}');
    expect(aoVoltar).toHaveBeenCalledTimes(1);
  });

  it('confirmar roda a ação e NÃO chama aoVoltar', async () => {
    const user = userEvent.setup();
    const acao = vi.fn();
    const aoVoltar = vi.fn();
    render(<Tela acao={acao} aoVoltar={aoVoltar} />);
    await user.click(screen.getByText('abrir'));
    await user.click(screen.getByRole('button', { name: 'Trocar' }));
    expect(acao).toHaveBeenCalledTimes(1);
    expect(aoVoltar).not.toHaveBeenCalled();
    // e a próxima desistência continua sendo desistência
    await user.click(screen.getByText('abrir'));
    await user.click(screen.getByRole('button', { name: 'Voltar' }));
    expect(aoVoltar).toHaveBeenCalledTimes(1);
  });

  it('aoFechar roda depois de fechar (confirmando ou não) e decide para onde vai o foco', async () => {
    const user = userEvent.setup();
    const aoFechar = vi.fn(() => screen.getByText('outro').focus());
    render(<Tela acao={vi.fn()} aoFechar={aoFechar} />);
    await user.click(screen.getByText('abrir'));
    await user.click(screen.getByRole('button', { name: 'Trocar' }));
    await waitFor(() => expect(aoFechar).toHaveBeenCalledTimes(1));
    expect(screen.getByText('outro')).toHaveFocus(); // e não o "abrir", que o Radix devolveria
    await user.click(screen.getByText('abrir'));
    await user.click(screen.getByRole('button', { name: 'Voltar' }));
    await waitFor(() => expect(aoFechar).toHaveBeenCalledTimes(2));
  });
});
