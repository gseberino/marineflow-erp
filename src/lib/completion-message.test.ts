import { describe, it, expect } from 'vitest';
import { buildCompletionMessage } from './completion-message';

describe('buildCompletionMessage', () => {
  it('com saldo: cita valor e vencimento', () => {
    const msg = buildCompletionMessage({
      clientName: 'Charline Souza', osNumber: 'OS-00060', balance: 1998.96, dueDate: '2026-08-26',
    });
    expect(msg).toContain('Charline'); // só o primeiro nome
    expect(msg).not.toContain('Souza');
    expect(msg).toContain('OS-00060');
    expect(msg).toContain('1.998,96');
    expect(msg).toContain('26/08/2026');
    expect(msg.toLowerCase()).toContain('conclu');
  });

  it('sem saldo: mensagem de quitado, sem valor', () => {
    const msg = buildCompletionMessage({ clientName: 'João', osNumber: 'OS-00051', balance: 0 });
    expect(msg).toContain('João');
    expect(msg).toContain('OS-00051');
    expect(msg).not.toMatch(/R\$/);
    expect(msg.toLowerCase()).toMatch(/quitad|tudo certo/);
  });

  it('sem vencimento: cita o saldo, sem a frase de vencimento', () => {
    const msg = buildCompletionMessage({ clientName: 'Ana', osNumber: 'OS-1', balance: 500 });
    expect(msg).toContain('500,00');
    expect(msg).not.toContain('vencimento');
  });

  it('sem nome: usa "Cliente"', () => {
    const msg = buildCompletionMessage({ osNumber: 'OS-1', balance: 0 });
    expect(msg).toContain('Cliente');
  });
});
