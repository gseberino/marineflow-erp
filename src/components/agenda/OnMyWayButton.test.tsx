// "A caminho": a confirmação cita a OS pelo número, que já traz o prefixo ("OS-00060"). Até
// 12/10/2026 dizia "…do atendimento da OS OS-00060." A mensagem ao cliente não cita o número.
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';

vi.mock('@/integrations/supabase/client', () => ({ supabase: {} }));
vi.mock('sonner', () => ({ toast: { success: () => {}, error: () => {} } }));

import { OnMyWayButton } from './OnMyWayButton';

describe('OnMyWayButton — número da OS sem "OS " repetido', () => {
  it('a confirmação diz "do atendimento da OS-00060"', () => {
    render(<OnMyWayButton order={{ id: 'so-1', service_order_number: 'OS-00060', clients: { name: 'Ana' } }} />);
    fireEvent.click(screen.getByRole('button', { name: /A caminho/ }));
    expect(screen.getByText(/do atendimento da OS-00060\./)).toBeInTheDocument();
    expect(screen.queryByText(/OS OS-/)).toBeNull();
  });
});
