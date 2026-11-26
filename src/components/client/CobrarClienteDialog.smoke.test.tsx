// "Cobrar o cliente" pela tela (dono, 26/11/2026: "1. A"): lê o cadastro e as contas e abre a conferência da ficha no modo
// cobrança; enquanto lê, mostra que está conferindo; leitura que falha ou cliente sumido = nada sai.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { CobrarClienteDialog } from './CobrarClienteDialog';

const { estado, recebido } = vi.hoisted(() => ({
  estado: {
    cadastro: { data: undefined as unknown, error: null as Error | null, isSuccess: false },
    contas: { data: undefined as unknown, error: null as Error | null },
  },
  recebido: { props: null as null | Record<string, unknown> },
}));

vi.mock('@/hooks/use-contas-do-cliente', () => ({
  useCadastroParaCobrar: () => estado.cadastro,
  useContasDoCliente: () => estado.contas,
}));
vi.mock('@/components/ClientStatementDialog', () => ({
  ClientStatementDialog: (p: Record<string, unknown>) => {
    recebido.props = p;
    return <div data-testid="conferencia">conferência de {(p.cliente as { name: string }).name} ({String(p.modo)})</div>;
  },
}));

const MP = { id: 'cli', name: 'MP MOTOR HOMES', whatsapp: '47999990000', generico: false, opt_out_whatsapp: false };

beforeEach(() => {
  estado.cadastro = { data: undefined, error: null, isSuccess: false };
  estado.contas = { data: undefined, error: null };
  recebido.props = null;
});

describe('CobrarClienteDialog', () => {
  it('fechado (sem cliente) não mostra nada', () => {
    const { container } = render(<CobrarClienteDialog clienteId={null} onFechar={() => {}} />);
    expect(container).toBeEmptyDOMElement();
  });

  it('lendo: avisa que está conferindo, sem botão de enviar', () => {
    render(<CobrarClienteDialog clienteId="cli" onFechar={() => {}} />);
    expect(screen.getByText(/Conferindo o cadastro e as contas do cliente/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Enviar/ })).toBeNull();
  });

  it('lido: abre a conferência da ficha no modo cobrança, com o cadastro e as contas lidos', () => {
    estado.cadastro = { data: MP, error: null, isSuccess: true };
    estado.contas = { data: [{ id: 'r45', amount: 1650, balance_amount: 1650 }], error: null };
    render(<CobrarClienteDialog clienteId="cli" onFechar={() => {}} />);
    expect(screen.getByTestId('conferencia')).toHaveTextContent('conferência de MP MOTOR HOMES (cobranca)');
    expect(recebido.props?.items).toEqual([{ id: 'r45', amount: 1650, balance_amount: 1650 }]);
    expect(recebido.props?.open).toBe(true);
  });

  it('leitura que falha e cliente que não existe mais: o motivo aparece e nada sai', () => {
    estado.cadastro = { data: undefined, error: new Error('Não consegui ler o cadastro do cliente: timeout'), isSuccess: false };
    const r = render(<CobrarClienteDialog clienteId="cli" onFechar={() => {}} />);
    expect(screen.getByRole('alert')).toHaveTextContent('Não consegui ler o cadastro do cliente: timeout Nada foi enviado; tente de novo.');
    r.unmount();
    estado.cadastro = { data: null, error: null, isSuccess: true };
    estado.contas = { data: [], error: null };
    render(<CobrarClienteDialog clienteId="cli" onFechar={() => {}} />);
    expect(screen.getByRole('alert')).toHaveTextContent('Este cliente não foi encontrado no cadastro. Nada foi enviado.');
    expect(screen.queryByTestId('conferencia')).toBeNull();
  });
});
