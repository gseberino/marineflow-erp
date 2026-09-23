// O padrão de ações de linha: poucas à vista, o resto no menu de três pontos.
// O que se testa aqui é o que protege o usuário — a ação destrutiva nunca fica solta na
// linha, e nunca encostada nas outras dentro do menu.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Trash2, Eye, Send } from 'lucide-react';
import { AcoesDaLinha } from './AcoesDaLinha';

describe('AcoesDaLinha', () => {
  it('mostra as rápidas na linha e esconde o resto até abrirem o menu', async () => {
    const user = userEvent.setup();
    render(
      <AcoesDaLinha
        rotulo="lead de João"
        rapidas={[{ texto: 'Ver mensagens', onClick: vi.fn(), icone: Eye }]}
        menu={[{ texto: 'Vincular a cliente', onClick: vi.fn() }]}
      />,
    );
    expect(screen.getByText('Ver mensagens')).toBeInTheDocument();
    expect(screen.queryByText('Vincular a cliente')).not.toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /mais ações para lead de joão/i }));
    expect(await screen.findByText('Vincular a cliente')).toBeInTheDocument();
  });

  it('o botão do menu diz de qual linha é — trinta linhas não podem ter trinta "mais ações"', () => {
    render(<AcoesDaLinha rotulo="nota 2/25" menu={[{ texto: 'Cancelar', onClick: vi.fn() }]} />);
    expect(screen.getByRole('button', { name: /mais ações para nota 2\/25/i })).toBeInTheDocument();
  });

  it('a ação destrutiva não fica solta na linha, mesmo que a peçam como rápida', async () => {
    const user = userEvent.setup();
    const apagar = vi.fn();
    render(
      <AcoesDaLinha
        rotulo="lead"
        rapidas={[{ texto: 'Ver', onClick: vi.fn() }]}
        menu={[{ texto: 'Descartar', onClick: apagar, perigo: true, icone: Trash2 }]}
      />,
    );
    // Fora do menu só existe o que é seguro clicar por engano.
    expect(screen.queryByText('Descartar')).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: /mais ações/i }));
    expect(await screen.findByText('Descartar')).toBeInTheDocument();
  });

  it('a destrutiva desce para o fim mesmo declarada no meio da lista', async () => {
    const user = userEvent.setup();
    render(
      <AcoesDaLinha
        rotulo="x"
        menu={[
          { texto: 'Primeira', onClick: vi.fn() },
          { texto: 'Bloquear', onClick: vi.fn(), perigo: true },
          { texto: 'Ultima comum', onClick: vi.fn() },
        ]}
      />,
    );
    await user.click(screen.getByRole('button', { name: /mais ações/i }));
    const itens = await screen.findAllByRole('menuitem');
    const textos = itens.map((i) => i.textContent);
    // Quem escreve a lista pensa na ordem lógica; a ordem de risco é a que protege.
    expect(textos.indexOf('Bloquear')).toBe(textos.length - 1);
  });

  it('chama a ação escolhida, e só ela', async () => {
    const user = userEvent.setup();
    const enviar = vi.fn();
    const outra = vi.fn();
    render(
      <AcoesDaLinha
        rotulo="x"
        menu={[{ texto: 'Enviar', onClick: enviar, icone: Send }, { texto: 'Outra', onClick: outra }]}
      />,
    );
    await user.click(screen.getByRole('button', { name: /mais ações/i }));
    await user.click(await screen.findByText('Enviar'));
    expect(enviar).toHaveBeenCalledTimes(1);
    expect(outra).not.toHaveBeenCalled();
  });

  it('sem ação nenhuma não sobra um menu vazio para clicar', () => {
    const { container } = render(<AcoesDaLinha rotulo="x" menu={[]} />);
    expect(container).toBeEmptyDOMElement();
  });

  it('linha ocupada trava as ações, para o clique repetido não duplicar o efeito', () => {
    render(
      <AcoesDaLinha
        rotulo="x"
        ocupada
        rapidas={[{ texto: 'Ver', onClick: vi.fn() }]}
        menu={[{ texto: 'Outra', onClick: vi.fn() }]}
      />,
    );
    expect(screen.getByRole('button', { name: 'Ver' })).toBeDisabled();
    expect(screen.getByRole('button', { name: /mais ações/i })).toBeDisabled();
  });
});
