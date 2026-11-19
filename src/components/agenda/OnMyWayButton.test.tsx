// "A caminho": a confirmação cita a OS pelo número, que já traz o prefixo ("OS-00060"). Até
// 12/10/2026 dizia "…do atendimento da OS OS-00060." A mensagem ao cliente não cita o número.
//
// 19/11/2026: a leitura do modo de teste do WhatsApp não conferia o erro — leitura que falhava
// virava "não é teste" e a mensagem ia ao cliente de verdade. Agora falha = nada enviado.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

vi.mock('@/integrations/supabase/client', async () => ({ supabase: (await import('@/test/banco-falso')).supabaseFalso }));
const toast = vi.hoisted(() => ({ success: vi.fn(), error: vi.fn() }));
vi.mock('sonner', () => ({ toast }));

import { OnMyWayButton } from './OnMyWayButton';
import { banco, ok, falha, reiniciarBanco, chamadasA } from '@/test/banco-falso';

beforeEach(() => {
  reiniciarBanco();
  toast.success.mockReset();
  toast.error.mockReset();
});

describe('OnMyWayButton — número da OS sem "OS " repetido', () => {
  it('a confirmação diz "do atendimento da OS-00060"', () => {
    render(<OnMyWayButton order={{ id: 'so-1', service_order_number: 'OS-00060', clients: { name: 'Ana' } }} />);
    fireEvent.click(screen.getByRole('button', { name: /A caminho/ }));
    expect(screen.getByText(/do atendimento da OS-00060\./)).toBeInTheDocument();
    expect(screen.queryByText(/OS OS-/)).toBeNull();
  });
});

describe('OnMyWayButton — modo de teste ilegível não envia', () => {
  const os = { id: 'so-1', service_order_number: 'OS-00060', clients: { name: 'Ana', whatsapp: '5521999990000' }, vessels: null };

  it('leitura do modo de teste falha → não enfileira e avisa', async () => {
    banco.respostas['service_orders.select'] = ok(os);
    banco.respostas['app_settings.select'] = falha('timeout');
    render(<OnMyWayButton order={{ id: 'so-1', service_order_number: 'OS-00060', clients: { name: 'Ana' } }} />);
    fireEvent.click(screen.getByRole('button', { name: /A caminho/ }));
    fireEvent.click(screen.getByRole('button', { name: /Enviar/ }));
    await waitFor(() => expect(toast.error).toHaveBeenCalled());
    expect(String(toast.error.mock.calls[0][0])).toMatch(/modo de teste/);
    expect(chamadasA('whatsapp_send_queue.insert')).toHaveLength(0);
    expect(toast.success).not.toHaveBeenCalled();
  });

  it('leitura ok e modo de teste desligado → enfileira para o cliente', async () => {
    banco.respostas['service_orders.select'] = ok(os);
    banco.respostas['app_settings.select'] = ok([{ key: 'wa_test_mode', value: 'false' }]);
    render(<OnMyWayButton order={{ id: 'so-1', service_order_number: 'OS-00060', clients: { name: 'Ana' } }} />);
    fireEvent.click(screen.getByRole('button', { name: /A caminho/ }));
    fireEvent.click(screen.getByRole('button', { name: /Enviar/ }));
    await waitFor(() => expect(toast.success).toHaveBeenCalled());
    const fila = chamadasA('whatsapp_send_queue.insert');
    expect(fila).toHaveLength(1);
    expect((fila[0].valores as { phone_normalized: string }).phone_normalized).toBe('5521999990000');
  });
});
