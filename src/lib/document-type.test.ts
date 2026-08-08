import { describe, it, expect } from 'vitest';
import { isQuoteStatus, documentTypeFor, documentLabelFor } from './document-type';

/**
 * A regra que decide o que a tela é.
 *
 * Ela vale porque o par de botões "Orçamento" e "OS" existia lado a lado na
 * mesma tela e cada um gerava o documento errado no lugar errado: dentro de uma
 * ordem, o botão de orçamento produzia um documento com validade e sem
 * apontamento de horas. Trocar dois botões por um só resolve se — e só se — a
 * regra estiver certa, então ela fica travada aqui.
 */
describe('que documento esta ordem é', () => {
  it('rascunho é orçamento', () => {
    expect(isQuoteStatus('draft')).toBe(true);
    expect(documentTypeFor('draft')).toBe('quote');
    expect(documentLabelFor('draft')).toBe('orçamento');
  });

  // Todo status que existe depois do rascunho já é trabalho, não proposta.
  it.each(['approved', 'scheduled', 'in_progress', 'completed', 'invoiced', 'cancelled'])(
    '%s é ordem de serviço',
    (status) => {
      expect(isQuoteStatus(status)).toBe(false);
      expect(documentTypeFor(status)).toBe('service_order');
      expect(documentLabelFor(status)).toBe('OS');
    },
  );

  // Sem status não se inventa orçamento: um documento com validade mandado ao
  // cliente por engano vale mais caro que uma OS a mais.
  it('sem status, trata como ordem de serviço', () => {
    expect(documentTypeFor(null)).toBe('service_order');
    expect(documentTypeFor(undefined)).toBe('service_order');
    expect(documentTypeFor('')).toBe('service_order');
  });

  // Status desconhecido não pode virar orçamento por acidente.
  it('status novo e desconhecido não vira orçamento', () => {
    expect(documentTypeFor('aguardando_peca')).toBe('service_order');
  });
});
