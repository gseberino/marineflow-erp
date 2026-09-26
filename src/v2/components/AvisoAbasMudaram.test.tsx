// O aviso "As abas mudaram de lugar": discreto, fecha com um clique, lembra que foi fechado e
// some sozinho depois de 10/10/2026. Sem armazenamento (navegação privada), continua funcionando.
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { AvisoAbasMudaram, avisoAindaVale, MAPA_ANTES_AGORA, AVISO_VALE_ATE } from './AvisoAbasMudaram';

vi.mock('@/lib/fluxo-de-caixa', () => ({ hojeEmBrasilia: () => '2026-09-26' }));

beforeEach(() => { window.localStorage.clear(); });
afterEach(() => { vi.restoreAllMocks(); });

describe('AvisoAbasMudaram', () => {
  it('vale até 10/10/2026, inclusive', () => {
    expect(AVISO_VALE_ATE).toBe('2026-10-10');
    expect(avisoAindaVale('2026-09-26')).toBe(true);
    expect(avisoAindaVale('2026-10-10')).toBe(true);
    expect(avisoAindaVale('2026-10-11')).toBe(false);
  });

  it('o mapa diz para onde foi cada aba antiga', () => {
    const mapa = Object.fromEntries(MAPA_ANTES_AGORA);
    expect(mapa['DRE e Aging']).toBe('Central de relatórios');
    expect(mapa['Cartões e Regras']).toBe('Extrato');
    expect(mapa['Fechamento']).toBe('Conciliação');
    expect(mapa['Comissões e Reembolsos']).toBe('Contas a Pagar');
    expect(mapa['Cobranças']).toBe('Contas a Receber');
    expect(mapa['Saúde do cadastro']).toBe('Fornecedores');
    expect(mapa['Programação']).toBe('Central de relatórios › Fluxo de caixa');
  });

  it('mostra o mapa ao pedir e fecha lembrando que foi fechado', async () => {
    const user = userEvent.setup();
    const { unmount } = render(<AvisoAbasMudaram />);
    expect(screen.getByText('As abas mudaram de lugar.')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: /Ver o que foi para onde/ }));
    expect(screen.getByText('DRE e Aging')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: /Fechar o aviso/ }));
    expect(screen.queryByText('As abas mudaram de lugar.')).not.toBeInTheDocument();
    unmount();
    // Voltando à tela, continua fechado.
    render(<AvisoAbasMudaram />);
    expect(screen.queryByText('As abas mudaram de lugar.')).not.toBeInTheDocument();
  });

  it('sem armazenamento no navegador, aparece e fecha do mesmo jeito', async () => {
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => { throw new Error('bloqueado'); });
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new Error('bloqueado'); });
    const user = userEvent.setup();
    render(<AvisoAbasMudaram />);
    expect(screen.getByText('As abas mudaram de lugar.')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: /Fechar o aviso/ }));
    expect(screen.queryByText('As abas mudaram de lugar.')).not.toBeInTheDocument();
  });
});
