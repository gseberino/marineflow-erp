import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * O PDF individual e o PDF em lote têm que sair da MESMA montagem.
 *
 * `usePDFData` (tela) e `fetchPDFData` (lote, anexo de WhatsApp, portal
 * público) duplicavam ~150 linhas: as mesmas queries, os mesmos ~40 campos,
 * copiados. Corrigir uma e esquecer a outra faz o documento em lote divergir do
 * que estava na tela — e ninguém percebe até um cliente receber o diferente.
 *
 * Já aconteceu aqui: a seção de levantamento entrou só no hook.
 */
const src = readFileSync(join(process.cwd(), 'src', 'hooks', 'use-pdf.ts'), 'utf8');

describe('uma montagem só para o PDF', () => {
  it('existe uma função única e as duas pontas a chamam', () => {
    expect(src).toContain('export async function carregarPDFData');
    // Cada uma chama, e nenhuma monta por conta própria.
    expect(src).toMatch(/usePDFData[\s\S]*?carregarPDFData\(serviceOrderId\)/);
    expect(src).toMatch(/fetchPDFData[\s\S]*?carregarPDFData\(serviceOrderId\)/);
  });

  it('o PDFData é montado UMA vez no arquivo', () => {
    const montagens = src.match(/const pdfData: PDFData = \{/g) || [];
    expect(montagens).toHaveLength(1);
  });

  it('a query da ordem aparece uma vez só', () => {
    const queries = src.match(/from\('service_orders'\)/g) || [];
    expect(queries).toHaveLength(1);
  });

  // O hint do embed é o que impede o PGRST201 que derrubou o PDF inteiro.
  // Com uma montagem só, ele existe num lugar e vale para os dois caminhos.
  it('o hint do levantamento está na montagem única', () => {
    expect(src).toContain('service_surveys!service_surveys_service_order_id_fkey');
    expect((src.match(/service_surveys!service_surveys_service_order_id_fkey/g) || []))
      .toHaveLength(1);
  });

  // A diferença legítima entre as duas: o fetch devolve null em vez de lançar,
  // porque quem chama está fora de um componente e trata ausência.
  it('o fetch imperativo continua devolvendo null em vez de lançar', () => {
    expect(src).toMatch(/fetchPDFData[\s\S]*?catch[\s\S]*?return null/);
  });
});
