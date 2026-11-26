import { afterEach, describe, expect, it, vi } from 'vitest';
import { buildHTMLDocument, carregarFontesDaMarca, DEFAULT_PDF_OPTIONS, type PDFData } from './pdf-generator';
import { htmlDaCapa } from './pdf-conjunto';
import { normalizarConjunto } from './conjunto';
import { AGORA, OS_COM_PAGAMENTO } from '../../supabase/functions/_shared/pdf/amostras';
import { MARCA, SLOGAN } from '../../supabase/functions/_shared/pdf/marca';
import { FAIXAS_DA_OPEN_SANS_DO_SERVIDOR } from '../../supabase/functions/_shared/pdf/open-sans-faixas';
import {
  caracteresForaDaFonteDoServidor,
  coresDeTextoClarasDemais,
} from '../../supabase/functions/_shared/pdf/marca-documento-regras';

/**
 * A marca nos documentos que só a tela gera — fatura, recibo e a capa do "Agrupar para o cliente" (26/11/2026, a
 * opção 4 aprovada pelo dono). Orçamento e OS são travados no Deno (_shared/pdf/marca-documento_test.ts), contra as
 * mesmas regras: nenhum texto mais claro que o azul da marca (o cinza sumia no modo rascunho da impressora) e nenhum
 * caractere que a Open Sans do servidor não desenhe.
 */

afterEach(() => vi.useRealTimers());

function documento(tipo: 'invoice' | 'receipt'): string {
  vi.useFakeTimers();
  vi.setSystemTime(new Date(AGORA));
  const dados = {
    ...OS_COM_PAGAMENTO,
    documentType: tipo,
    serviceOrder: { ...OS_COM_PAGAMENTO.serviceOrder, deposit_paid: 500, financial_notes: 'Pagar até o dia 10.' },
  } as PDFData;
  return buildHTMLDocument(dados, { ...DEFAULT_PDF_OPTIONS });
}

const conjunto = normalizarConjunto({
  id: 'c1', nome: 'OS-00104 + ORÇ-00140', ativo: true, client_id: 'cli', cliente: 'Cliente Teste', embarcacao: 'Lancha X',
  principal_id: 'a', total_geral: 6200,
  documentos: [
    { id: 'a', numero: 'OS-00104', tipo: 'os', status: 'scheduled', ativo: true, assinado: true, grand_total: 5000, recebido: 2500, sinal_a_pagar: 0 },
    { id: 'b', numero: 'ORÇ-00140', tipo: 'orcamento', status: 'draft', quote_status: 'draft', ativo: true, grand_total: 1200, sinal_a_pagar: 600 },
  ],
})!;

describe('fatura e recibo com a marca', () => {
  for (const tipo of ['invoice', 'receipt'] as const) {
    it(`${tipo}: cores da marca, número em caixa, fio, slogan, sem a Inter do Google`, () => {
      const html = documento(tipo);
      expect(html).toContain(`--pdf-primary: ${MARCA.marinho};`);
      expect(html).toContain(`--pdf-text-muted: ${MARCA.azul};`);
      expect(html).toContain('class="doc-numero"');
      expect(html).toContain('<div class="fio"></div>');
      expect(html).toContain(`content: "${SLOGAN}"`);
      expect(html).not.toContain('fonts.googleapis');
    });
    it(`${tipo}: nenhum texto mais claro que o azul da marca`, () => {
      expect(coresDeTextoClarasDemais(documento(tipo))).toEqual([]);
    });
    it(`${tipo}: nenhum caractere fora da fonte do servidor`, () => {
      expect(caracteresForaDaFonteDoServidor(documento(tipo), FAIXAS_DA_OPEN_SANS_DO_SERVIDOR)).toEqual([]);
    });
  }
});

describe('capa do conjunto com a marca', () => {
  it('fio, slogan e as letras da marca; as fontes entram quando vêm', async () => {
    const semFontes = htmlDaCapa(conjunto, { name: 'HBR' }, '18/11/2026');
    expect(semFontes).toContain('<div class="fio"></div>');
    expect(semFontes).toContain(`content: "${SLOGAN}"`);
    expect(semFontes).toContain('"Hanken Grotesk"');
    expect(semFontes).not.toContain('@font-face');
    const comFontes = htmlDaCapa(conjunto, { name: 'HBR' }, '18/11/2026', await carregarFontesDaMarca());
    expect(comFontes.slice(0, comFontes.indexOf('</head>'))).toContain('@font-face');
  });
  it('nenhum texto mais claro que o azul da marca e nenhum caractere fora da fonte do servidor', () => {
    const html = htmlDaCapa(conjunto, { name: 'HBR', cnpj: '00.000.000/0001-00', phone: '(47) 3333-0000' }, '18/11/2026');
    expect(coresDeTextoClarasDemais(html)).toEqual([]);
    expect(caracteresForaDaFonteDoServidor(html, FAIXAS_DA_OPEN_SANS_DO_SERVIDOR)).toEqual([]);
  });
});

describe('fontes da marca sob demanda', () => {
  it('carregarFontesDaMarca traz as duas fontes e guarda para a próxima', async () => {
    const css = await carregarFontesDaMarca();
    expect(css).toContain('font-family: "Archivo"');
    expect(css).toContain('font-family: "Hanken Grotesk"');
    expect(await carregarFontesDaMarca()).toBe(css);
  });
  it('o gerador não importa as fontes de forma estática (elas não pesam nas telas que nunca geram documento)', async () => {
    const { readFileSync } = await import('node:fs');
    const { join } = await import('node:path');
    const ler = (...p: string[]) => readFileSync(join(process.cwd(), ...p), 'utf8');
    const gerador = ler('src', 'lib', 'pdf-generator.ts');
    const molde = ler('supabase', 'functions', '_shared', 'pdf', 'documento.ts');
    expect(gerador).not.toMatch(/^import[^;]*from '[^']*\/(marca|marca-fontes)'/m);
    expect(molde).not.toMatch(/^import[^;]*from '\.\/(marca|marca-fontes)(\.ts)?'/m);
  });
});
