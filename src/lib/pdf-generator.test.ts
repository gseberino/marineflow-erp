import { describe, it, expect } from 'vitest';
import { buildPDFFilename, type PDFData } from './pdf-generator';

function makeData(overrides: Partial<PDFData> = {}): PDFData {
  return {
    documentType: 'service_order',
    company: {
      name: '', address: '', city: '', state: '',
      postal_code: '', phone: '', email: '', cnpj: '',
    },
    serviceOrder: {
      service_order_number: 'OS-00123',
      status: 'open',
      created_at: '2026-01-01',
    },
    client: { name: 'João da Silva' },
    vessel: { name: 'Lancha Azul' },
    ...overrides,
  } as PDFData;
}

describe('buildPDFFilename', () => {
  it('monta nome com tipo, número, cliente e embarcação, sem acentos', () => {
    expect(buildPDFFilename(makeData())).toBe('OrdemServico_OS-00123_Joao-da-Silva_Lancha-Azul.pdf');
  });

  it('usa o rótulo correto por tipo de documento', () => {
    expect(buildPDFFilename(makeData({ documentType: 'quote' }))).toMatch(/^Orcamento_/);
    expect(buildPDFFilename(makeData({ documentType: 'invoice' }))).toMatch(/^Fatura_/);
    expect(buildPDFFilename(makeData({ documentType: 'receipt' }))).toMatch(/^Recibo_/);
  });

  it('omite partes ausentes sem deixar separadores soltos', () => {
    const data = makeData({
      client: { name: '' },
      vessel: undefined,
      serviceOrder: { service_order_number: '', status: 'open', created_at: '2026-01-01' },
    });
    expect(buildPDFFilename(data)).toBe('OrdemServico.pdf');
  });

  it('sanitiza caracteres especiais e barras', () => {
    const data = makeData({
      client: { name: 'Empresa A/B & Cia.' },
      vessel: { name: 'Motorhome #1 (2024)' },
    });
    const name = buildPDFFilename(data);
    expect(name.endsWith('.pdf')).toBe(true);
    const base = name.replace(/\.pdf$/, '');
    expect(base).not.toMatch(/[/\\#&()]/);
  });
});
