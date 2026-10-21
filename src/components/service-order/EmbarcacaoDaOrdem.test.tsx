// Embarcação/veículo da OS com a mesma proteção do cliente, nos casos específicos (21/10/2026).
import { describe, it, expect, vi } from 'vitest';
import { render, screen, within, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

vi.mock('@/components/VesselFormDialog', () => ({
  VesselFormDialog: ({ open }: { open: boolean }) => (open ? <div role="dialog">cadastro de embarcação</div> : null),
}));

import { EmbarcacaoDaOrdem } from './EmbarcacaoDaOrdem';

const netuno = { id: 'v1', client_id: 'c1', name: 'Netuno II', active: true, asset_type: 'Lancha', manufacturer: 'Schaefer', model: '400' };
const brisa = { id: 'v2', client_id: 'c1', name: 'Brisa', active: true, asset_type: 'Veleiro', manufacturer: null, model: null };
const barcos = [netuno, brisa];

type Props = Parameters<typeof EmbarcacaoDaOrdem>[0];
function renderiza(p: Partial<Props> = {}) {
  const onChange = vi.fn();
  const motivosDaTroca = p.motivosDaTroca ?? vi.fn(() => [] as string[]);
  const utils = render(
    <EmbarcacaoDaOrdem
      rotulo="Embarcação *" value="v1" clientId="c1" vessels={barcos} embarcacao={netuno as never}
      motivosDaTroca={motivosDaTroca} onChange={onChange} onVesselCreated={vi.fn()} {...p}
    />,
  );
  return { ...utils, onChange, motivosDaTroca };
}

const trocar = () => screen.getByRole('button', { name: /^Trocar embarcação ou veículo/ });

describe('EmbarcacaoDaOrdem', () => {
  it('escolhida: só a ficha e o "Trocar" (sem lista aberta à toa)', () => {
    renderiza();
    expect(screen.getByLabelText('Dados da embarcação')).toBeInTheDocument();
    expect(screen.queryByRole('combobox')).not.toBeInTheDocument();
    expect(trocar()).toBeInTheDocument();
  });

  it('sem nenhuma escolhida: a lista, sem "Trocar"', () => {
    renderiza({ value: '', embarcacao: undefined });
    expect(screen.getByRole('combobox', { name: /Embarcação/ })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Trocar embarcação/ })).not.toBeInTheDocument();
  });

  it('"Trocar" abre a lista já aberta; sem motivos, troca direto', async () => {
    const user = userEvent.setup();
    const { onChange } = renderiza();
    await user.click(trocar());
    expect(screen.getByText(/por:/)).toHaveTextContent('Trocar Lancha Netuno II por:');
    await user.click(await screen.findByRole('option', { name: /Brisa/ }));
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument();
    expect(onChange).toHaveBeenCalledWith('v2');
  });

  it('com motivos: a confirmação diz de qual para qual e o que acontece; "Manter a atual" não troca', async () => {
    const user = userEvent.setup();
    const { onChange } = renderiza({ motivosDaTroca: () => ['Sai o solicitante Carlos, que é contato da antiga.'], documento: 'orçamento' });
    await user.click(trocar());
    await user.click(await screen.findByRole('option', { name: /Brisa/ }));
    const dialogo = await screen.findByRole('alertdialog');
    expect(within(dialogo).getByText('Trocar a embarcação ou veículo deste orçamento?')).toBeInTheDocument();
    expect(within(dialogo).getByText(
      'De Lancha Netuno II para Veleiro Brisa. Sai o solicitante Carlos, que é contato da antiga.',
    )).toBeInTheDocument();
    await user.click(within(dialogo).getByRole('button', { name: 'Manter a atual' }));
    expect(onChange).not.toHaveBeenCalled();
    await waitFor(() => expect(trocar()).toHaveFocus());
  });

  it('… e "Trocar" troca', async () => {
    const user = userEvent.setup();
    const { onChange } = renderiza({ motivosDaTroca: () => ['Motivo.'] });
    await user.click(trocar());
    await user.click(await screen.findByRole('option', { name: /Brisa/ }));
    await user.click(within(await screen.findByRole('alertdialog')).getByRole('button', { name: 'Trocar' }));
    expect(onChange).toHaveBeenCalledWith('v2');
  });

  it('a mesma de novo não é troca', async () => {
    const user = userEvent.setup();
    const { onChange, motivosDaTroca } = renderiza({ motivosDaTroca: vi.fn(() => ['Motivo.']) });
    await user.click(trocar());
    await user.click(await screen.findByRole('option', { name: /Netuno II/ }));
    expect(onChange).not.toHaveBeenCalled();
    expect(motivosDaTroca).not.toHaveBeenCalled();
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument();
  });

  it('cadastrar uma nova com motivos pergunta ANTES de abrir o cadastro', async () => {
    const user = userEvent.setup();
    renderiza({ motivosDaTroca: () => ['Motivo.'] });
    await user.click(trocar());
    await user.click(await screen.findByRole('option', { name: /Nova embarcação para este cliente/ }));
    const dialogo = await screen.findByRole('alertdialog');
    expect(within(dialogo).getByText(/para um cadastro novo/)).toBeInTheDocument();
    expect(screen.queryByText('cadastro de embarcação')).not.toBeInTheDocument();
    await user.click(within(dialogo).getByRole('button', { name: 'Trocar' }));
    expect(await screen.findByText('cadastro de embarcação')).toBeInTheDocument();
  });

  it('bloqueio com motivo (OS concluída, agrupamento): sem "Trocar", com o motivo', () => {
    renderiza({ semTroca: 'OS concluída: para trocar a embarcação ou veículo, volte a OS para Em andamento.' });
    expect(screen.queryByRole('button', { name: /^Trocar embarcação/ })).not.toBeInTheDocument();
    expect(screen.getByText(/OS concluída/)).toBeInTheDocument();
  });

  it('ainda conferindo (semTroca = true): sem "Trocar" e sem mensagem', () => {
    renderiza({ semTroca: true });
    expect(screen.queryByRole('button', { name: /^Trocar embarcação/ })).not.toBeInTheDocument();
    expect(screen.getByLabelText('Dados da embarcação')).toBeInTheDocument();
  });

  it('OS travada: ficha sem "Trocar"; o "Editar" do cadastro continua', () => {
    renderiza({ disabled: true });
    expect(screen.queryByRole('button', { name: /^Trocar embarcação/ })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Editar cadastro da embarcação' })).toBeInTheDocument();
  });

  it('a ficha mostra o nome: é nela que se confere "é esta?"', () => {
    renderiza();
    expect(within(screen.getByLabelText('Dados da embarcação')).getByText('Netuno II')).toBeInTheDocument();
  });

  it('trava que chega com a troca aberta fecha a troca (e não volta aberta quando a trava sai)', async () => {
    const user = userEvent.setup();
    const props = {
      rotulo: 'Embarcação *', value: 'v1', clientId: 'c1', vessels: barcos, embarcacao: netuno as never,
      motivosDaTroca: () => [] as string[], onChange: vi.fn(), onVesselCreated: vi.fn(),
    };
    const { rerender } = render(<EmbarcacaoDaOrdem {...props} />);
    await user.click(trocar());
    expect(document.getElementById('os-embarcacao')).not.toBeNull();
    rerender(<EmbarcacaoDaOrdem {...props} semTroca="OS concluída: para trocar a embarcação ou veículo, volte a OS para Em andamento." />);
    expect(document.getElementById('os-embarcacao')).toBeNull();
    rerender(<EmbarcacaoDaOrdem {...props} />);
    expect(document.getElementById('os-embarcacao')).toBeNull();
    expect(trocar()).toBeInTheDocument();
  });

  it('a trava que chega com a confirmação aberta vale: confirmar não troca', async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    const props = {
      rotulo: 'Embarcação *', value: 'v1', clientId: 'c1', vessels: barcos, embarcacao: netuno as never,
      motivosDaTroca: () => ['Motivo.'], onChange, onVesselCreated: vi.fn(),
    };
    const { rerender } = render(<EmbarcacaoDaOrdem {...props} />);
    await user.click(trocar());
    await user.click(await screen.findByRole('option', { name: /Brisa/ }));
    const dialogo = await screen.findByRole('alertdialog');
    rerender(<EmbarcacaoDaOrdem {...props} semTroca="OS concluída: para trocar a embarcação ou veículo, volte a OS para Em andamento." />);
    await user.click(within(dialogo).getByRole('button', { name: 'Trocar' }));
    expect(onChange).not.toHaveBeenCalled();
  });

  it('Esc com a troca aberta desiste: volta a ficha e o foco no "Trocar"', async () => {
    const user = userEvent.setup();
    const { onChange } = renderiza();
    await user.click(trocar());
    expect(await screen.findByRole('option', { name: /Brisa/ })).toBeInTheDocument();
    await user.keyboard('{Escape}');
    expect(document.getElementById('os-embarcacao')).toBeNull();
    expect(screen.getByLabelText('Dados da embarcação')).toBeInTheDocument();
    await waitFor(() => expect(trocar()).toHaveFocus());
    expect(onChange).not.toHaveBeenCalled();
  });

  it('clique fora com a troca aberta também desiste', async () => {
    const user = userEvent.setup();
    renderiza();
    await user.click(trocar());
    expect(await screen.findByRole('option', { name: /Brisa/ })).toBeInTheDocument();
    await user.click(document.body);
    await waitFor(() => expect(document.getElementById('os-embarcacao')).toBeNull());
    expect(screen.getByLabelText('Dados da embarcação')).toBeInTheDocument();
  });

  it('escolher com motivos NÃO conta como desistir: a confirmação fica, e "Trocar" troca', async () => {
    const user = userEvent.setup();
    const { onChange } = renderiza({ motivosDaTroca: () => ['Motivo.'] });
    await user.click(trocar());
    await user.click(await screen.findByRole('option', { name: /Brisa/ }));
    const dialogo = await screen.findByRole('alertdialog');
    expect(screen.getByText(/por:/)).toBeInTheDocument();
    await user.click(within(dialogo).getByRole('button', { name: 'Trocar' }));
    expect(onChange).toHaveBeenCalledWith('v2');
  });

  it('o rótulo só aponta para a lista quando ela existe', () => {
    const { unmount } = renderiza();
    expect(screen.getByText('Embarcação *')).not.toHaveAttribute('for');
    unmount();
    renderiza({ value: '', embarcacao: undefined });
    expect(screen.getByText('Embarcação *')).toHaveAttribute('for', 'os-embarcacao');
  });

  it('fora da lista do cliente: diz "deste orçamento" no orçamento', () => {
    renderiza({ value: 'v9', embarcacao: undefined, documento: 'orçamento' });
    expect(screen.getByText('A embarcação ou veículo deste orçamento não está na lista do cliente.')).toBeInTheDocument();
  });
});
