// Ficha do cliente → "Quem paga por este cliente": só o administrador desfaz o que confirmou (decisão do dono,
// 23/10/2026). O financeiro pausa ou recusa apenas um PROPOSTO — o banco recusa o resto.
//
// Revisão de 23/10/2026: TODA decisão muda o que a fila sugere (o recusado e o pausado são o veto do motor, inclusive
// os de um proposto) — "Revisar a fila" em silêncio sempre que o resultado pede. E o nome que o banco escreve com o CPF
// dentro sai mascarado.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { I18nProvider } from '@/i18n';

const estado = vi.hoisted(() => ({ cargo: 'admin' as string, pagadores: [] as unknown[] }));
const { decidirMock, reaplicarMock } = vi.hoisted(() => ({ decidirMock: vi.fn(), reaplicarMock: vi.fn() }));

vi.mock('@/hooks/use-auth', () => ({ useOptionalAuth: () => ({ user: { id: 'u1', role: estado.cargo } }) }));
vi.mock('@/hooks/use-finance-review', () => ({ useReaplicarRegras: () => ({ mutate: reaplicarMock }) }));
vi.mock('@/hooks/use-pagadores-do-cliente', async (original) => {
  const real = await original<typeof import('@/hooks/use-pagadores-do-cliente')>();
  return {
    ...real,
    usePagadoresDoCliente: () => ({ data: estado.pagadores, isLoading: false, error: null }),
    useDecidirPagador: () => ({ mutate: decidirMock, isPending: false }),
  };
});

beforeEach(() => { decidirMock.mockReset(); reaplicarMock.mockReset(); });

import { PagadoresDoCliente } from './PagadoresDoCliente';

const base = {
  client_id: 'c1', relacao: 'conjuge', observacao: null, origem: 'historico', bank_transaction_id: 'bt-1',
  proposto_por: 'u2', proposto_em: '2026-10-20T12:00:00Z', confirmado_por: null, confirmado_em: null,
  decidido_motivo: null, proposto_por_nome: 'Felipe', confirmado_por_nome: null,
};
const CONFIRMADO = { ...base, id: 'p1', documento: '11122233344', nome: 'MARIA CONFIRMADA', situacao: 'confirmado', confirmado_em: '2026-10-21T12:00:00Z' };
const PROPOSTO = { ...base, id: 'p2', documento: '55566677788', nome: 'JOSE PROPOSTO', situacao: 'proposto' };

function renderizar() {
  return render(<I18nProvider><PagadoresDoCliente clientId="c1" clientName="Ana Souza" /></I18nProvider>);
}

async function opcoesDoMenu(nome: string) {
  const user = userEvent.setup();
  const linha = screen.getByText(nome).closest('li') ?? screen.getByText(nome).parentElement!.parentElement!;
  const botao = within(linha as HTMLElement).queryByRole('button', { name: new RegExp(`Mais ações para pagador ${nome}`) });
  if (!botao) return [];
  await user.click(botao);
  const itens = (await screen.findAllByRole('menuitem')).map((m) => m.textContent?.trim());
  await user.keyboard('{Escape}');
  return itens;
}

describe('PagadoresDoCliente — quem desfaz o quê', () => {
  it('administrador: pausa e recusa o confirmado e o proposto', async () => {
    estado.cargo = 'admin';
    estado.pagadores = [CONFIRMADO, PROPOSTO];
    renderizar();
    expect(await opcoesDoMenu('MARIA CONFIRMADA')).toEqual(expect.arrayContaining(['Pausar', 'Recusar']));
    expect(await opcoesDoMenu('JOSE PROPOSTO')).toEqual(expect.arrayContaining(['Pausar', 'Recusar']));
  });

  it('financeiro: nada no confirmado (só o administrador desfaz); pausa e recusa só o proposto', async () => {
    estado.cargo = 'financial';
    estado.pagadores = [CONFIRMADO, PROPOSTO];
    renderizar();
    expect(await opcoesDoMenu('MARIA CONFIRMADA')).toEqual([]);
    expect(await opcoesDoMenu('JOSE PROPOSTO')).toEqual(expect.arrayContaining(['Pausar', 'Recusar']));
    expect(screen.queryByRole('button', { name: /^Confirmar/ })).not.toBeInTheDocument();
  });
});

/** O resultado de decidir_pagador_do_cliente, como o banco devolve. */
function resultado(id: string, situacao: string) {
  return { ok: true, id, situacao, regras_consolidadas: [], message: `Pagador ${situacao}.` };
}

async function escolherNoMenu(user: ReturnType<typeof userEvent.setup>, nome: string, item: string) {
  await user.click(screen.getByRole('button', { name: new RegExp(`Mais ações para pagador ${nome}`) }));
  await user.click(await screen.findByRole('menuitem', { name: item }));
}

describe('PagadoresDoCliente — toda decisão revisa a fila (o veto do motor)', () => {
  it('financeiro PAUSA um proposto: o pausado é veto — "Revisar a fila" em silêncio', async () => {
    estado.cargo = 'financial';
    estado.pagadores = [CONFIRMADO, PROPOSTO];
    const user = userEvent.setup();
    renderizar();
    await escolherNoMenu(user, 'JOSE PROPOSTO', 'Pausar');
    expect(decidirMock).toHaveBeenCalledWith({ id: 'p2', decisao: 'pausar' }, expect.anything());
    expect(reaplicarMock).not.toHaveBeenCalled();
    decidirMock.mock.calls[0][1].onSuccess(resultado('p2', 'pausado'));
    expect(reaplicarMock).toHaveBeenCalledWith({ silencioso: true });
  });

  it('administrador RECUSA um proposto (depois de confirmar no diálogo): também revisa a fila', async () => {
    estado.cargo = 'admin';
    estado.pagadores = [PROPOSTO];
    const user = userEvent.setup();
    renderizar();
    await escolherNoMenu(user, 'JOSE PROPOSTO', 'Recusar');
    // Recusar pede confirmação: nada sai antes do "Recusar" do diálogo.
    expect(decidirMock).not.toHaveBeenCalled();
    await user.click(within(await screen.findByRole('alertdialog')).getByRole('button', { name: 'Recusar' }));
    expect(decidirMock).toHaveBeenCalledWith({ id: 'p2', decisao: 'recusar' }, expect.anything());
    decidirMock.mock.calls[0][1].onSuccess(resultado('p2', 'recusado'));
    expect(reaplicarMock).toHaveBeenCalledTimes(1);
    expect(reaplicarMock).toHaveBeenCalledWith({ silencioso: true });
  });

  it('confirmar e reativar continuam revisando a fila', async () => {
    estado.cargo = 'admin';
    const PAUSADO = { ...base, id: 'p3', documento: '99988877766', nome: 'RITA PAUSADA', situacao: 'pausado' };
    estado.pagadores = [PROPOSTO, PAUSADO];
    const user = userEvent.setup();
    renderizar();
    await user.click(screen.getByRole('button', { name: 'Confirmar' }));
    decidirMock.mock.calls[0][1].onSuccess(resultado('p2', 'confirmado'));
    await user.click(screen.getByRole('button', { name: 'Reativar' }));
    expect(decidirMock.mock.calls[1][0]).toEqual({ id: 'p3', decisao: 'reativar' });
    decidirMock.mock.calls[1][1].onSuccess(resultado('p3', 'confirmado'));
    expect(reaplicarMock).toHaveBeenCalledTimes(2);
  });
});

describe('PagadoresDoCliente — CPF dentro do nome (LGPD)', () => {
  it('o nome que o banco escreveu com o CPF, a observação e o motivo saem mascarados', async () => {
    estado.cargo = 'admin';
    estado.pagadores = [{
      ...CONFIRMADO, nome: '12345678901-MARIA DA SILVA',
      observacao: 'paga pelo CPF 123.456.789-01', decidido_motivo: 'conferido no extrato 12345678901',
    }];
    const { container } = renderizar();
    expect(screen.getByText('***.456.789-**-MARIA DA SILVA')).toBeInTheDocument();
    expect(screen.getByText('paga pelo CPF ***.456.789-**')).toBeInTheDocument();
    expect(screen.getByText(/Motivo: conferido no extrato \*\*\*\.456\.789-\*\*/)).toBeInTheDocument();
    // O CPF inteiro não aparece em lugar nenhum — nem no rótulo do menu de ações.
    expect(container.textContent).not.toMatch(/12345678901|123\.456\.789-01/);
    expect(screen.getByRole('button', { name: /Mais ações para pagador \*\*\*\.456\.789-\*\*-MARIA DA SILVA/ })).toBeInTheDocument();
  });
});
