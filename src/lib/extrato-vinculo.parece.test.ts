// "Parece pagar" só com um cliente que vale ou que pede o SIM — nunca com o sugerido que ninguém disse ser o da linha
// (situação "escolher": a anotação foi desfeita e o sugerido ficou). Revisão da leva 8, 23/10/2026.
import { describe, it, expect } from 'vitest';
import { clienteDoParecePagar } from './extrato-vinculo';

describe('clienteDoParecePagar', () => {
  it('a escolha da pessoa sempre vale', () => {
    expect(clienteDoParecePagar({ suggested_client_id: 'x' }, { clientId: 'y' })).toBe('y');
  });

  it('prova do motor deste cliente (vale ou pede o SIM): calcula com o sugerido', () => {
    expect(clienteDoParecePagar({ suggested_client_id: 'x', evidencia: { cliente: { id: 'x', nome: 'X', por: 'documento' } } })).toBe('x');
    expect(clienteDoParecePagar({ suggested_client_id: 'x', evidencia: { cliente: { id: 'x', nome: 'X', por: 'pagador_conhecido' } } })).toBe('x');
  });

  it('anotação do dono que trocou o cliente: calcula com o anotado', () => {
    expect(clienteDoParecePagar({
      suggested_client_id: 'tsd', evidencia: { cliente: { id: 'acrisio', nome: 'Acrisio', por: 'historico' }, anotacao: { id: 'a1', os_id: null } },
    })).toBe('tsd');
  });

  it('"escolher" (anotação desfeita: sugerido ≠ prova, sem a marca): nenhum cliente', () => {
    expect(clienteDoParecePagar({
      suggested_client_id: 'tsd', evidencia: { cliente: { id: 'acrisio', nome: 'Acrisio', por: 'historico' } },
    })).toBeNull();
    expect(clienteDoParecePagar({ suggested_client_id: 'tsd', evidencia: {} })).toBeNull();
  });

  it('sem sugestão: nenhum', () => {
    expect(clienteDoParecePagar({ suggested_client_id: null })).toBeNull();
  });
});
