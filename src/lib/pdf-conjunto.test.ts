import { describe, expect, it, vi } from 'vitest';
import { PDFDocument } from 'pdf-lib';
import { normalizarConjunto } from './conjunto';
import type { PDFData } from './pdf-generator';
import { bytesDoBlob, gerarPdfDoConjunto, htmlDaCapa, juntarPdfs } from './pdf-conjunto';

const conjunto = normalizarConjunto({
  id: 'c1', nome: 'OS-00104 + ORÇ-00140', ativo: true, client_id: 'cli', cliente: 'Cliente <Teste>', embarcacao: 'Lancha X',
  principal_id: 'a', total_geral: 6200,
  documentos: [
    { id: 'a', numero: 'OS-00104', tipo: 'os', status: 'scheduled', ativo: true, assinado: true, grand_total: 5000, recebido: 2500, sinal_a_pagar: 0 },
    { id: 'b', numero: 'ORÇ-00140', tipo: 'orcamento', status: 'draft', quote_status: 'draft', ativo: true, grand_total: 1200, sinal_a_pagar: 600 },
  ],
})!;

async function pdfDe(paginas: number): Promise<Blob> {
  const d = await PDFDocument.create();
  for (let i = 0; i < paginas; i++) d.addPage();
  return new Blob([await d.save()], { type: 'application/pdf' });
}

describe('htmlDaCapa', () => {
  const html = htmlDaCapa(conjunto, { name: 'HBR Systems', cnpj: '00.000.000/0001-00' }, '18/11/2026');
  it('diz o que reúne, o cliente escapado e o quadro com já pago e sinal', () => {
    expect(html).toContain('OS-00104 e ORÇ-00140');
    expect(html).toContain('Cliente &lt;Teste&gt;');
    expect(html).toContain('Já pago');
    expect(html).toContain('Sinal a pagar');
    expect(html).toMatch(/R\$\s?6\.200,00/);
    expect(html).toMatch(/R\$\s?3\.100,00/);
  });
  it('sem nada pago e sem sinal: as colunas somem', () => {
    const limpo = { ...conjunto, documentos: conjunto.documentos.map((d) => ({ ...d, recebido: 0, sinal_a_pagar: 0 })) };
    const h = htmlDaCapa(limpo, null, '18/11/2026');
    expect(h).not.toContain('Já pago');
    expect(h).not.toContain('Sinal a pagar');
  });
});

describe('juntarPdfs', () => {
  it('soma as páginas na ordem', async () => {
    const junto = await juntarPdfs([await pdfDe(1), await pdfDe(2), await pdfDe(3)]);
    const doc = await PDFDocument.load(await bytesDoBlob(junto));
    expect(doc.getPageCount()).toBe(6);
  });
});

describe('gerarPdfDoConjunto', () => {
  it('capa + cada documento, com o tipo certo de PDF e o nome do conjunto', async () => {
    const carregar = vi.fn(async (id: string) => ({ company: { name: 'HBR' }, serviceOrder: { id } }) as unknown as PDFData);
    const gerar = vi.fn(async (_d: PDFData) => pdfDe(2));
    const capa = vi.fn(async (_html: string, _nome: string) => pdfDe(1));
    const r = await gerarPdfDoConjunto(conjunto, {}, { carregar, gerar, capa, hoje: () => '18/11/2026' });
    expect(carregar.mock.calls.map((c) => c[0])).toEqual(['a', 'b']);
    expect(gerar.mock.calls.map((c) => c[0].documentType)).toEqual(['service_order', 'quote']);
    expect(capa.mock.calls[0][0]).toContain('HBR');
    expect(r.filename).toBe('OS-00104 + ORÇ-00140.pdf');
    expect((await PDFDocument.load(await bytesDoBlob(r.blob))).getPageCount()).toBe(5);
  });
  it('documento que não carrega: erro com o número, nada sai', async () => {
    const carregar = vi.fn(async (id: string) => (id === 'b' ? null : ({ company: {} } as unknown as PDFData)));
    await expect(gerarPdfDoConjunto(conjunto, {}, { carregar, gerar: async () => pdfDe(1), capa: async () => pdfDe(1) }))
      .rejects.toThrow(/ORÇ-00140/);
  });
});
