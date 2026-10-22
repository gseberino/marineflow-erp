// Busca da embarcação ou veículo na OS: o tipo e os sinônimos dele também acham (decisão do dono,
// 22/10/2026 — "Jet Ski" virou "Moto aquática", mas quem digita "jet ski" tem de achar).
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

vi.mock('@/components/VesselFormDialog', () => ({ VesselFormDialog: () => null }));

import { VesselSelect } from './VesselSelect';

const frota = [
  { id: 'l', name: 'Netuno II', asset_type: 'Lancha', manufacturer: 'Schaefer', model: '400', active: true },
  { id: 'm', name: 'Vitória Star', asset_type: 'Motorhome', manufacturer: 'Iveco', model: 'Daily', active: true },
  { id: 'j', name: 'Azul', asset_type: 'Moto aquática', active: true },
  { id: 'k', name: 'Verde', asset_type: 'Jet Ski', active: true },
  { id: 'o', name: 'Bote do Zé', asset_type: 'Outra embarcação', active: true },
];

async function buscar(texto: string) {
  const user = userEvent.setup();
  render(<VesselSelect value="" onChange={() => {}} vessels={frota} clientId="c1" />);
  await user.click(screen.getByRole('combobox'));
  await user.type(screen.getByPlaceholderText(/Buscar embarcação ou veículo/), texto);
  return screen.getAllByRole('option').map((o) => o.textContent ?? '');
}

const tem = (opcoes: string[], nome: string) => opcoes.some((o) => o.startsWith(nome));

describe('VesselSelect — busca pelo tipo e pelos sinônimos', () => {
  it('"jet ski" acha a moto aquática nova e o cadastro antigo "Jet Ski"', async () => {
    const opcoes = await buscar('jet ski');
    expect(tem(opcoes, 'Azul')).toBe(true);
    expect(tem(opcoes, 'Verde')).toBe(true);
    expect(tem(opcoes, 'Netuno II')).toBe(false);
    expect(tem(opcoes, 'Vitória Star')).toBe(false);
  });

  it('"motorhome" acha o motorhome', async () => {
    const opcoes = await buscar('motorhome');
    expect(tem(opcoes, 'Vitória Star')).toBe(true);
    expect(tem(opcoes, 'Netuno II')).toBe(false);
  });

  it('"van" (van convertida) acha o motorhome', async () => {
    const opcoes = await buscar('van');
    expect(tem(opcoes, 'Vitória Star')).toBe(true);
    expect(tem(opcoes, 'Netuno II')).toBe(false);
  });

  it('o tipo como gravado também acha ("outra embarcação")', async () => {
    const opcoes = await buscar('outra emb');
    expect(tem(opcoes, 'Bote do Zé')).toBe(true);
    expect(tem(opcoes, 'Netuno II')).toBe(false);
  });

  it('a opção mostra o tipo; o "Jet Ski" antigo aparece como Moto aquática', async () => {
    const opcoes = await buscar('verde');
    expect(opcoes.find((o) => o.startsWith('Verde'))).toContain('Moto aquática');
  });
});
