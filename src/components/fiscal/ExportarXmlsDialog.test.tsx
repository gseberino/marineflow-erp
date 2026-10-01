// "Exportar XMLs para a contadora" (D33, 01/10/2026). O que se protege: período invertido não
// consulta nada; cada nota pede o XML pelo proxy autenticado; o .zip leva os XMLs e o resumo CSV;
// XML que não veio entra na conta de "não baixado" sem derrubar a exportação.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

const banco = vi.hoisted(() => ({
  filtros: [] as unknown[][],
  invocacoes: [] as unknown[],
  zip: [] as Array<{ name: string; content: string }>,
  toasts: [] as string[],
  docs: [] as unknown[],
}));

vi.mock('@/integrations/supabase/client', () => {
  const consulta: Record<string, unknown> = {};
  for (const m of ['select', 'in', 'gte', 'lte']) {
    consulta[m] = (...args: unknown[]) => { banco.filtros.push([m, ...args]); return consulta; };
  }
  consulta.order = async () => ({ data: banco.docs, error: null });
  return {
    supabase: {
      from: () => consulta,
      functions: {
        invoke: async (_nome: string, opts: { body: { document_id: string } }) => {
          banco.invocacoes.push(opts.body);
          return opts.body.document_id === 'sem-xml'
            ? { data: 'não é xml', error: null }
            : { data: `<nfeProc id="${opts.body.document_id}"/>`, error: null };
        },
      },
    },
  };
});
vi.mock('@/lib/zip', () => ({
  createZipBlob: (entradas: Array<{ name: string; content: string }>) => { banco.zip = entradas; return new Blob(['zip']); },
}));
vi.mock('sonner', () => ({
  toast: {
    loading: () => 't1',
    success: (m: string) => banco.toasts.push(m),
    error: (m: string) => banco.toasts.push(`erro: ${m}`),
  },
}));

import { ExportarXmlsDialog } from './ExportarXmlsDialog';

const nota = (id: string, number: number) => ({
  id, series: 2, number, access_key: `chave-${number}`, status: 'authorized', environment: 'producao',
  authorized_at: '2026-09-10T12:00:00-03:00',
  request_payload: { recipient: { name: 'CLIENTE', document: '12345678000199' }, items: [{ quantity: 1, unit_price: 100 }] },
});

beforeEach(() => {
  banco.filtros = [];
  banco.invocacoes = [];
  banco.zip = [];
  banco.toasts = [];
  banco.docs = [];
  URL.createObjectURL = vi.fn(() => 'blob:x');
  URL.revokeObjectURL = vi.fn();
  // o download é um clique num <a>: o jsdom não navega
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
});

describe('ExportarXmlsDialog', () => {
  it('período invertido não consulta nada', () => {
    render(<ExportarXmlsDialog onClose={() => {}} />);
    const [inicio, fim] = screen.getAllByDisplayValue(/\d{4}-\d{2}-\d{2}/) as HTMLInputElement[];
    fireEvent.change(inicio, { target: { value: '2026-09-30' } });
    fireEvent.change(fim, { target: { value: '2026-09-01' } });
    fireEvent.click(screen.getByRole('button', { name: /Exportar .zip/ }));
    expect(banco.toasts).toContain('erro: Informe um período válido (início ≤ fim).');
    expect(banco.filtros).toEqual([]);
  });

  it('autorizadas e canceladas, um XML por nota e o resumo CSV no .zip', async () => {
    banco.docs = [nota('n31', 31), nota('sem-xml', 32)];
    const onClose = vi.fn();
    render(<ExportarXmlsDialog onClose={onClose} />);
    fireEvent.click(screen.getByRole('button', { name: /Exportar .zip/ }));
    await waitFor(() => expect(onClose).toHaveBeenCalled());

    expect(banco.filtros).toContainEqual(['in', 'status', ['authorized', 'cancelled']]);
    expect(banco.invocacoes).toEqual([
      { action: 'artifact', document_id: 'n31', artifact: 'xml_authorized' },
      { action: 'artifact', document_id: 'sem-xml', artifact: 'xml_authorized' },
    ]);
    expect(banco.zip.map((e) => e.name)).toEqual(['NFe-2-000000031-chave-31.xml', '_resumo-livro-saida.csv']);
    expect(banco.zip[1].content.split('\r\n')).toHaveLength(4); // cabeçalho + 2 notas + final
    expect(banco.toasts).toContain('Exportadas 1 nota(s) (1 XML não baixado) + resumo CSV.');
  });

  it('período sem notas avisa e não gera arquivo', async () => {
    render(<ExportarXmlsDialog onClose={() => {}} />);
    fireEvent.click(screen.getByRole('button', { name: /Exportar .zip/ }));
    await waitFor(() => expect(banco.toasts).toContain('erro: Nenhuma NF-e autorizada/cancelada nesse período.'));
    expect(banco.zip).toEqual([]);
  });
});
