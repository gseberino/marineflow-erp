// Cancelar NF-e e Carta de Correção (D33, 01/10/2026). O que se protege: nada sai com menos de 15
// caracteres; o que vai ao fiscal-emit é o texto aparado; o motivo de uma nota não aparece no
// cancelamento de outra; o prazo de 24 h é mostrado sem "60min".
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { tempoDesdeAAutorizacao } from '@/lib/fiscal-justificativa';

const banco = vi.hoisted(() => ({
  chamadas: [] as Array<{ nome: string; body: unknown }>,
  toasts: [] as string[],
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    functions: {
      invoke: async (nome: string, opts: { body: unknown }) => {
        banco.chamadas.push({ nome, body: opts.body });
        return { data: { ok: true }, error: null };
      },
    },
  },
}));
vi.mock('sonner', () => ({
  toast: { success: (m: string) => banco.toasts.push(m), error: (m: string) => banco.toasts.push(`erro: ${m}`) },
}));

import { CancelarNotaDialog, CartaDeCorrecaoDialog } from './CancelarOuCorrigirNota';

const qc = new QueryClient();
function Cancelar({ alvo, onClose = () => {} }: { alvo: { id: string; authorized_at?: string | null }; onClose?: () => void }) {
  return (
    <QueryClientProvider client={qc}>
      <CancelarNotaDialog key={alvo.id} alvo={alvo} ocupado={false} marcarOcupado={() => {}} onClose={onClose} />
    </QueryClientProvider>
  );
}

beforeEach(() => {
  banco.chamadas = [];
  banco.toasts = [];
});

describe('tempoDesdeAAutorizacao', () => {
  const agora = Date.parse('2026-10-01T15:00:00Z');
  it('horas e minutos inteiros, dentro e fora das 24 h', () => {
    expect(tempoDesdeAAutorizacao('2026-10-01T12:30:00Z', agora)).toMatchObject({ dentroDoPrazo: true, texto: '2h30min' });
    // 23,9995 h: o arredondamento antigo mostrava "23h60min"
    expect(tempoDesdeAAutorizacao(new Date(agora - 23.9995 * 3_600_000).toISOString(), agora)?.texto).toBe('23h59min');
    expect(tempoDesdeAAutorizacao('2026-09-30T09:00:00Z', agora)?.dentroDoPrazo).toBe(false);
    expect(tempoDesdeAAutorizacao(null, agora)).toBeNull();
  });
});

describe('CancelarNotaDialog', () => {
  it('só confirma com 15 caracteres e manda o motivo aparado', async () => {
    const onClose = vi.fn();
    render(<Cancelar alvo={{ id: 'nf-1', authorized_at: new Date(Date.now() - 2 * 3_600_000).toISOString() }} onClose={onClose} />);
    expect(screen.getByText(/Dentro do prazo de 24h/)).toBeTruthy();
    const confirmar = screen.getByRole('button', { name: /Confirmar Cancelamento/ }) as HTMLButtonElement;
    fireEvent.change(screen.getByRole('textbox'), { target: { value: 'curto' } });
    expect(confirmar.disabled).toBe(true);
    fireEvent.change(screen.getByRole('textbox'), { target: { value: '  Erro de digitação no endereço  ' } });
    expect(confirmar.disabled).toBe(false);
    fireEvent.click(confirmar);
    await waitFor(() => expect(onClose).toHaveBeenCalled());
    expect(banco.chamadas).toEqual([{
      nome: 'fiscal-emit', body: { action: 'cancel', document_id: 'nf-1', reason: 'Erro de digitação no endereço' },
    }]);
  });

  it('passadas 24 h, avisa que a SEFAZ pode recusar', () => {
    render(<Cancelar alvo={{ id: 'nf-2', authorized_at: new Date(Date.now() - 30 * 3_600_000).toISOString() }} />);
    expect(screen.getByText(/Já se passaram 30h da autorização/)).toBeTruthy();
  });

  it('o motivo digitado para uma nota não aparece no cancelamento de outra', () => {
    const { rerender } = render(<Cancelar alvo={{ id: 'nota-A' }} />);
    fireEvent.change(screen.getByRole('textbox'), { target: { value: 'Motivo que era da nota A' } });
    fireEvent.click(screen.getByRole('button', { name: 'Voltar' }));
    rerender(<Cancelar alvo={{ id: 'nota-B' }} />);
    expect((screen.getByRole('textbox') as HTMLTextAreaElement).value).toBe('');
  });
});

describe('CartaDeCorrecaoDialog', () => {
  it('envia a correção aparada pelo fiscal-emit', async () => {
    const onClose = vi.fn();
    render(
      <QueryClientProvider client={qc}>
        <CartaDeCorrecaoDialog alvo={{ id: 'nf-3', number: 31, series: 2 }} ocupado={false} marcarOcupado={() => {}} onClose={onClose} />
      </QueryClientProvider>,
    );
    expect(screen.getByText('Carta de Correção — NF-e 2/31')).toBeTruthy();
    fireEvent.change(screen.getByRole('textbox'), { target: { value: ' Onde se lê píer 2, leia-se píer 3. ' } });
    fireEvent.click(screen.getByRole('button', { name: /Enviar Correção/ }));
    await waitFor(() => expect(onClose).toHaveBeenCalled());
    expect(banco.chamadas).toEqual([{
      nome: 'fiscal-emit', body: { action: 'correction', document_id: 'nf-3', text: 'Onde se lê píer 2, leia-se píer 3.' },
    }]);
  });
});
