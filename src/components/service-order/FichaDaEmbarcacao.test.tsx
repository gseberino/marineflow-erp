// Ficha da embarcação na OS: o que o técnico pergunta primeiro e o editar do cadastro (20/10/2026).
import { describe, it, expect, vi } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { Vessel } from '@/hooks/use-vessels';

vi.mock('@/components/VesselFormDialog', () => ({
  VesselFormDialog: ({ open, vessel }: { open: boolean; vessel?: Vessel | null }) =>
    open ? <div role="dialog">editando {vessel?.name}</div> : null,
}));

import { FichaDaEmbarcacao } from './FichaDaEmbarcacao';

type DaLista = Vessel & { marinas?: { name?: string | null } | null };

function embarcacao(p: Partial<DaLista>): DaLista {
  return {
    id: 'v1', client_id: 'c1', name: 'Netuno II', active: true, asset_type: null, manufacturer: null, model: null,
    year: null, length_feet: null, beam_feet: null, draft_feet: null, hull_id_or_registration: null,
    engine_brand: null, engine_model: null, engine_quantity: null, engine_type: null, propulsion_type: null,
    shore_power_type: null, battery_bank_summary: null, inverter_charger_summary: null,
    navigation_electronics_summary: null, electrical_system_notes: null, current_dock_position: null,
    current_marina_name_snapshot: null, marina_id: null, access_notes: null, created_at: '', updated_at: '',
    ...p,
  };
}

/** O valor que está logo abaixo do rótulo (dt → dd). */
const valorDe = (ficha: HTMLElement, rotulo: string) =>
  within(ficha).getByText(rotulo, { selector: 'dt' }).nextElementSibling as HTMLElement;

describe('FichaDaEmbarcacao', () => {
  it('nome em destaque e o tipo embaixo dele, como na ficha do cliente', () => {
    render(<FichaDaEmbarcacao embarcacao={embarcacao({ asset_type: 'Motorhome', name: 'Iveco Daily' })} />);
    const ficha = screen.getByLabelText('Dados da embarcação ou veículo');
    expect(within(ficha).getByText('Iveco Daily')).toHaveClass('font-semibold');
    expect(within(ficha).getByText('Motorhome')).toBeInTheDocument();
    // O tipo está no cabeçalho: não se repete como dado, e não conta como "detalhe" do cadastro.
    expect(within(ficha).queryByText('Tipo', { selector: 'dt' })).not.toBeInTheDocument();
    expect(within(ficha).getByText(/Cadastro sem detalhes/)).toBeInTheDocument();
  });

  it('sem tipo cadastrado (ou "Outro"), o cabeçalho diz "Embarcação ou veículo"', () => {
    const { unmount } = render(<FichaDaEmbarcacao embarcacao={embarcacao({})} />);
    expect(within(screen.getByLabelText('Dados da embarcação ou veículo')).getByText('Embarcação ou veículo')).toBeInTheDocument();
    unmount();
    render(<FichaDaEmbarcacao embarcacao={embarcacao({ asset_type: 'Outro', name: 'HOMEBUS' })} />);
    expect(within(screen.getByLabelText('Dados da embarcação ou veículo')).getByText('Embarcação ou veículo')).toBeInTheDocument();
  });

  it('cada dado com o rótulo em cima: modelo, ano, tamanho, inscrição, motores e onde fica', () => {
    render(<FichaDaEmbarcacao embarcacao={embarcacao({
      asset_type: 'Lancha', manufacturer: 'Schaefer', model: '400', year: 2019, length_feet: 40,
      hull_id_or_registration: '441-123', engine_quantity: 2, engine_brand: 'Volvo', engine_model: 'D6',
      marinas: { name: 'Marina Itajaí' }, current_dock_position: 'B12',
    })} />);
    const ficha = screen.getByLabelText('Dados da embarcação ou veículo');
    expect(valorDe(ficha, 'Fabricante e modelo')).toHaveTextContent('Schaefer 400');
    expect(valorDe(ficha, 'Ano')).toHaveTextContent('2019');
    expect(valorDe(ficha, 'Comprimento')).toHaveTextContent('40 pés');
    expect(valorDe(ficha, 'Inscrição')).toHaveTextContent('441-123');
    expect(valorDe(ficha, 'Motores')).toHaveTextContent('2× Volvo D6');
    expect(valorDe(ficha, 'Onde fica')).toHaveTextContent('Marina Itajaí · vaga B12');
  });

  it('a identificação pelo tipo (decisão 9): placa no motorhome, nº de série no equipamento', () => {
    const { unmount } = render(<FichaDaEmbarcacao embarcacao={embarcacao({
      asset_type: 'Motorhome', name: 'Iveco Daily', hull_id_or_registration: 'ABC1D23',
    })} />);
    let ficha = screen.getByLabelText('Dados da embarcação ou veículo');
    expect(valorDe(ficha, 'Placa')).toHaveTextContent('ABC1D23');
    expect(within(ficha).queryByText('Inscrição / placa')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Editar cadastro do motorhome' })).toBeInTheDocument();
    unmount();
    render(<FichaDaEmbarcacao embarcacao={embarcacao({ asset_type: 'Equipamento', name: 'Bancada', hull_id_or_registration: 'SN-77' })} />);
    ficha = screen.getByLabelText('Dados da embarcação ou veículo');
    expect(valorDe(ficha, 'Nº de série')).toHaveTextContent('SN-77');
  });

  it('sem tipo, a identificação fica "Inscrição / placa"', () => {
    render(<FichaDaEmbarcacao embarcacao={embarcacao({ hull_id_or_registration: '441-123' })} />);
    expect(valorDe(screen.getByLabelText('Dados da embarcação ou veículo'), 'Inscrição / placa')).toHaveTextContent('441-123');
  });

  it('só aparece o que está preenchido (sem colunas de "Não informado")', () => {
    render(<FichaDaEmbarcacao embarcacao={embarcacao({ manufacturer: 'Schaefer', model: '400', year: 2019 })} />);
    const ficha = screen.getByLabelText('Dados da embarcação ou veículo');
    expect(valorDe(ficha, 'Fabricante e modelo')).toHaveTextContent('Schaefer 400');
    for (const ausente of ['Tipo', 'Comprimento', 'Inscrição / placa', 'Motores', 'Onde fica']) {
      expect(within(ficha).queryByText(ausente)).not.toBeInTheDocument();
    }
    expect(within(ficha).queryByText('Não informado')).not.toBeInTheDocument();
  });

  it('veículo (dono, 22/10/2026): comprimento em metros, sem vaga de píer, ícone de motorhome', () => {
    render(<FichaDaEmbarcacao embarcacao={embarcacao({
      asset_type: 'Motorhome', name: 'Vitória Star', length_feet: 40, engine_brand: 'Iveco', engine_model: 'F1C',
      marinas: { name: 'Pátio HBR' }, current_dock_position: 'Rua A, 01',
    })} />);
    const ficha = screen.getByLabelText('Dados da embarcação ou veículo');
    expect(valorDe(ficha, 'Comprimento')).toHaveTextContent('12,2 m');
    expect(within(ficha).queryByText(/pés/)).not.toBeInTheDocument();
    expect(valorDe(ficha, 'Motores')).toHaveTextContent('Iveco F1C');
    // A posição no píer é campo de barco: fica gravada, mas não aparece no motorhome.
    expect(valorDe(ficha, 'Onde fica')).toHaveTextContent(/^Pátio HBR$/);
    expect(ficha.querySelector('.lucide-caravan')).toBeTruthy();
    expect(ficha.querySelector('.lucide-ship')).toBeNull();
  });

  it('equipamento: sem comprimento e sem motores, com o ícone da bancada', () => {
    render(<FichaDaEmbarcacao embarcacao={embarcacao({
      asset_type: 'Equipamento', name: 'Inversor', length_feet: 3, engine_brand: 'Volvo', engine_model: 'D6',
    })} />);
    const ficha = screen.getByLabelText('Dados da embarcação ou veículo');
    expect(within(ficha).queryByText('Comprimento')).not.toBeInTheDocument();
    expect(within(ficha).queryByText('Motores')).not.toBeInTheDocument();
    // Nada do tipo dele preenchido: é cadastro sem detalhes.
    expect(within(ficha).getByText(/Cadastro sem detalhes/)).toBeInTheDocument();
    expect(ficha.querySelector('.lucide-wrench')).toBeTruthy();
  });

  it('barco (ou sem tipo) segue com o navio e a vaga', () => {
    render(<FichaDaEmbarcacao embarcacao={embarcacao({ asset_type: 'Lancha', current_dock_position: 'B12' })} />);
    const ficha = screen.getByLabelText('Dados da embarcação ou veículo');
    expect(valorDe(ficha, 'Onde fica')).toHaveTextContent('vaga B12');
    expect(ficha.querySelector('.lucide-ship')).toBeTruthy();
  });

  it('cadastro vazio diz o que falta, e o editar abre o cadastro dela', async () => {
    const user = userEvent.setup();
    render(<FichaDaEmbarcacao embarcacao={embarcacao({})} />);
    expect(screen.getByText(/Cadastro sem detalhes/)).toBeInTheDocument();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Editar cadastro da embarcação ou veículo' }));
    expect(screen.getByRole('dialog')).toHaveTextContent('editando Netuno II');
  });
});
