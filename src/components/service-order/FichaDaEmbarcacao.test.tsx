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
  it('cada dado com o rótulo em cima: tipo, modelo, ano, tamanho, inscrição, motores e onde fica', () => {
    render(<FichaDaEmbarcacao embarcacao={embarcacao({
      asset_type: 'Lancha', manufacturer: 'Schaefer', model: '400', year: 2019, length_feet: 40,
      hull_id_or_registration: '441-123', engine_quantity: 2, engine_brand: 'Volvo', engine_model: 'D6',
      marinas: { name: 'Marina Itajaí' }, current_dock_position: 'B12',
    })} />);
    const ficha = screen.getByLabelText('Dados da embarcação');
    expect(valorDe(ficha, 'Tipo')).toHaveTextContent('Lancha');
    expect(valorDe(ficha, 'Fabricante e modelo')).toHaveTextContent('Schaefer 400');
    expect(valorDe(ficha, 'Ano')).toHaveTextContent('2019');
    expect(valorDe(ficha, 'Comprimento')).toHaveTextContent('40 pés');
    expect(valorDe(ficha, 'Inscrição / placa')).toHaveTextContent('441-123');
    expect(valorDe(ficha, 'Motores')).toHaveTextContent('2× Volvo D6');
    expect(valorDe(ficha, 'Onde fica')).toHaveTextContent('Marina Itajaí · vaga B12');
  });

  it('só aparece o que está preenchido (sem colunas de "Não informado")', () => {
    render(<FichaDaEmbarcacao embarcacao={embarcacao({ manufacturer: 'Schaefer', model: '400', year: 2019 })} />);
    const ficha = screen.getByLabelText('Dados da embarcação');
    expect(valorDe(ficha, 'Fabricante e modelo')).toHaveTextContent('Schaefer 400');
    for (const ausente of ['Tipo', 'Comprimento', 'Inscrição / placa', 'Motores', 'Onde fica']) {
      expect(within(ficha).queryByText(ausente)).not.toBeInTheDocument();
    }
    expect(within(ficha).queryByText('Não informado')).not.toBeInTheDocument();
  });

  it('cadastro vazio diz o que falta, e o editar abre o cadastro dela', async () => {
    const user = userEvent.setup();
    render(<FichaDaEmbarcacao embarcacao={embarcacao({})} />);
    expect(screen.getByText(/Cadastro sem detalhes/)).toBeInTheDocument();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Editar cadastro da embarcação' }));
    expect(screen.getByRole('dialog')).toHaveTextContent('editando Netuno II');
  });
});
