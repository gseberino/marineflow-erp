// A aba WhatsApp de Configurações. O que se protege: com o número desconectado a tela oferece
// QR e código e para sozinha quando conecta; com o servidor do PC fora do ar ela NÃO oferece
// conectar (não resolveria) e diz o que fazer; o código chega formatado para digitar.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const evo = vi.hoisted(() => ({
  estado: {} as Record<string, unknown>,
  conectar: [] as Record<string, unknown>[],
  pedidos: [] as Record<string, unknown>[],
  toasts: [] as string[],
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    functions: {
      invoke: async (_nome: string, { body }: { body: Record<string, unknown> }) => {
        if (body.acao === 'estado') return { data: evo.estado, error: null };
        evo.pedidos.push(body);
        const proxima = evo.conectar.length > 1 ? evo.conectar.shift() : evo.conectar[0];
        // Como na Evolution: quando o connect responde "open", o estado também é "open".
        if (proxima?.estado === 'open') evo.estado = { ...evo.estado, estado: 'open', queda: null };
        return { data: proxima, error: null };
      },
    },
  },
}));
vi.mock('sonner', () => ({
  toast: { success: (m: string) => evo.toasts.push(m), error: (m: string) => evo.toasts.push(m) },
}));

import { WhatsAppConexaoTab, formatarCodigo, formatarTelefone } from './WhatsAppConexaoTab';

function montar() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(<QueryClientProvider client={qc}><WhatsAppConexaoTab intervaloMs={30} /></QueryClientProvider>);
}

const DESCONECTADO = {
  estado: 'close', detalhe: null, perfil: 'HBR Marine', numero: '554797921234',
  queda: { em: '2026-09-29T19:21:07.921Z', motivo: 'o aparelho foi desconectado pelo celular (Dispositivos conectados)' },
  vigia: null,
};

beforeEach(() => {
  evo.estado = DESCONECTADO;
  evo.conectar = [];
  evo.pedidos = [];
  evo.toasts = [];
});

describe('WhatsAppConexaoTab', () => {
  it('desconectado: mostra o motivo, gera o QR e para quando conecta', async () => {
    const lendo = { estado: 'connecting', qr: 'data:image/png;base64,QR1', codigo: null, detalhe: null };
    evo.conectar = [lendo, lendo, lendo, lendo, { estado: 'open', qr: null, codigo: null, detalhe: null }];
    const user = userEvent.setup();
    montar();

    expect(await screen.findByText(/^Desconectado desde/)).toBeTruthy();
    expect(screen.getByText(/aparelho foi desconectado pelo celular/)).toBeTruthy();

    await user.click(screen.getByRole('button', { name: /mostrar qr code/i }));
    const img = await screen.findByRole('img', { name: /qr code para conectar/i });
    expect(img.getAttribute('src')).toBe('data:image/png;base64,QR1');
    expect(evo.pedidos[0]).toEqual({ acao: 'conectar', inicio: true });

    await waitFor(() => expect(evo.toasts).toContain('WhatsApp conectado!'));
    await waitFor(() => expect(screen.queryByRole('img', { name: /qr code/i })).toBeNull());
    expect(await screen.findByText('Conectado')).toBeTruthy();
    // Depois de conectar não pede mais nada.
    const feitos = evo.pedidos.length;
    await new Promise((r) => setTimeout(r, 120));
    expect(evo.pedidos.length).toBe(feitos);
  });

  it('só com o celular: número vem preenchido e o código sai formatado', async () => {
    evo.conectar = [{ estado: 'connecting', qr: 'data:image/png;base64,QR1', codigo: 'WZYEH1YY', detalhe: null }];
    const user = userEvent.setup();
    montar();

    const campo = await screen.findByLabelText(/número do whatsapp da hbr/i) as HTMLInputElement;
    await waitFor(() => expect(campo.value).toBe('(47) 9792-1234'));

    await user.click(screen.getByRole('button', { name: /receber código/i }));
    expect(await screen.findByText('WZYE-H1YY')).toBeTruthy();
    expect(evo.pedidos[0]).toEqual({ acao: 'conectar', numero: '(47) 9792-1234', inicio: true });
    expect(screen.getByText(/conectar com número de telefone/i)).toBeTruthy();
  });

  it('servidor do PC fora do ar: não oferece conectar e diz o que fazer', async () => {
    evo.estado = { ...DESCONECTADO, estado: 'inacessivel', detalhe: 'sem resposta do servidor do WhatsApp no PC', queda: null };
    montar();
    expect(await screen.findByText('Servidor do WhatsApp fora do ar')).toBeTruthy();
    expect(screen.getByText(/religar no PC/i)).toBeTruthy();
    expect(screen.queryByRole('button', { name: /mostrar qr code/i })).toBeNull();
    expect(screen.queryByRole('button', { name: /receber código/i })).toBeNull();
  });

  it('conectado: mostra perfil e número, sem botões de conectar', async () => {
    evo.estado = { ...DESCONECTADO, estado: 'open', queda: null };
    montar();
    expect(await screen.findByText('Conectado')).toBeTruthy();
    expect(screen.getByText('HBR Marine · (47) 9792-1234')).toBeTruthy();
    expect(screen.queryByRole('button', { name: /mostrar qr code/i })).toBeNull();
  });
});

describe('formatos', () => {
  it('telefone e código', () => {
    expect(formatarTelefone('5547997921234')).toBe('(47) 99792-1234');
    expect(formatarTelefone('554797921234')).toBe('(47) 9792-1234');
    expect(formatarCodigo('wzyeh1yy')).toBe('WZYE-H1YY');
  });
});
