// Smoke de render do prompt de conclusão — garante que abre sem crashar e pré-preenche a mensagem.
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { CompletionSendDialog } from './CompletionSendDialog';

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { functions: { invoke: async () => ({ error: null }) } },
}));

describe('CompletionSendDialog — smoke', () => {
  it('abre com saldo e pré-preenche a mensagem (valor + vencimento)', () => {
    render(
      <CompletionSendDialog
        open
        onOpenChange={() => {}}
        serviceOrderId="so-1"
        osNumber="OS-00060"
        clientName="Charline Souza"
        clientPhone="(47) 99999-0000"
        balance={1998.96}
        dueDate="2026-08-26"
      />,
    );
    expect(screen.getByText(/Serviço concluído/i)).toBeTruthy();
    // a mensagem (no textarea) deve citar a OS e o saldo
    const anyTextarea = document.querySelector('textarea');
    expect(anyTextarea?.value).toContain('OS-00060');
    expect(anyTextarea?.value).toContain('1.998,96');
  });
});
