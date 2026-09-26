import { describe, it, expect } from 'vitest';
import { readdirSync, readFileSync } from 'node:fs';
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
// A montagem mora em _shared para o assistente do WhatsApp usar a mesma (25/09/2026);
// o hook só delega. As verificações de "uma montagem só" valem para os dois juntos.
const montagem = readFileSync(
  join(process.cwd(), 'supabase', 'functions', '_shared', 'pdf', 'dados.ts'), 'utf8',
);
const portal = readFileSync(
  join(process.cwd(), 'src', 'pages', 'PublicServiceOrderView.tsx'), 'utf8',
);

describe('uma montagem só para o PDF', () => {
  it('existe uma função única e as duas pontas a chamam', () => {
    expect(src).toContain('export async function carregarPDFData');
    // Cada uma chama, e nenhuma monta por conta própria.
    // Sem fixar a assinatura: o que importa é chamar a função única com a ordem.
    // `carregarPDFData` passou a aceitar um cliente (o do token, para o portal).
    expect(src).toMatch(/usePDFData[\s\S]*?carregarPDFData\(serviceOrderId/);
    expect(src).toMatch(/fetchPDFData[\s\S]*?carregarPDFData\(serviceOrderId/);
  });

  /**
   * O PORTAL PÚBLICO é a terceira ponta — e a que mais importa, porque é o
   * documento que sai da empresa.
   *
   * Este teste nomeava o portal no comentário e só lia `use-pdf.ts`. Enquanto
   * isso o portal tinha uma montagem à mão que divergia em doze campos e mandava
   * 31 orçamentos ao cliente intitulados "Ordem de Serviço" (NOVO-lev-14). Um
   * teste que cita o que não verifica dá confiança falsa — agora ele lê o arquivo.
   */
  it('o portal público usa a montagem única, não uma cópia', () => {
    expect(portal).toContain('carregarPDFData');
    // Nenhum PDFData montado à mão lá dentro.
    expect(portal).not.toMatch(/const buildPdfData/);
    expect(portal).not.toMatch(/documentType:\s*'service_order'/);
  });

  /**
   * Rascunho é orçamento. Fixar o tipo faz o cliente baixar um "Ordem de
   * Serviço" sem validade, com a nota técnica interna liberada para sair.
   */
  it('o portal deriva o tipo do documento do status', () => {
    expect(portal).toContain('documentTypeFor(order.status)');
  });

  /**
   * O PDF do portal ia sempre com DEFAULT_PDF_OPTIONS — tudo ligado. Desligar
   * "mostrar dados bancários" escondia da tela e o cliente baixava com eles.
   */
  it('o PDF do portal obedece os toggles da via pública', () => {
    expect(portal).toMatch(/showBankDetails:\s*show\.bankDetails/);
    expect(portal).toMatch(/showTerms:\s*show\.terms/);
  });

  it('o PDFData é montado UMA vez no arquivo', () => {
    const montagens = (src + montagem).match(/const pdfData: PDFData = \{/g) || [];
    expect(montagens).toHaveLength(1);
  });

  it('a query da ordem aparece uma vez só', () => {
    const queries = (src + montagem).match(/from\('service_orders'\)/g) || [];
    expect(queries).toHaveLength(1);
  });

  // O hook delega; se ele voltar a consultar o banco, é uma segunda montagem nascendo.
  it('o hook não consulta o banco por conta própria', () => {
    expect(src).not.toMatch(/\.from\(/);
    expect(src).toMatch(/carregarPDFData as montarPDFData/);
  });

  // O hint do embed é o que impede o PGRST201 que derrubou o PDF inteiro.
  // Com uma montagem só, ele existe num lugar e vale para os dois caminhos.
  it('o hint do levantamento está na montagem única', () => {
    expect(montagem).toContain('service_surveys!service_surveys_service_order_id_fkey');
    expect(((src + montagem).match(/service_surveys!service_surveys_service_order_id_fkey/g) || []))
      .toHaveLength(1);
  });

  // A diferença legítima entre as duas: o fetch devolve null em vez de lançar,
  // porque quem chama está fora de um componente e trata ausência.
  it('o fetch imperativo continua devolvendo null em vez de lançar', () => {
    expect(src).toMatch(/fetchPDFData[\s\S]*?catch[\s\S]*?return null/);
  });

  /**
   * A QUARTA ponta (25/09/2026): o assistente do WhatsApp manda o PDF pela tool
   * send_document_pdf_to_self. Ele roda numa Edge Function e é o lugar mais fácil de nascer
   * uma cópia "só para o servidor" — que divergiria da tela no primeiro ajuste.
   *
   * Desde 26/09/2026 o caminho do servidor mora em _shared/pdf/gerar-e-guardar.ts, porque o
   * assistente passou a mandar o PDF também ao CLIENTE (send_service_order_link, em
   * whatsapp.ts). A guarda segue o código: gerar-e-guardar.ts usa a montagem e o desenho da
   * tela, e as duas tools usam gerar-e-guardar.ts — nenhuma monta o documento por conta própria.
   */
  it('o assistente usa a montagem e o desenho únicos', () => {
    const pastaPdf = join(process.cwd(), 'supabase', 'functions', '_shared', 'pdf');
    const pastaTools = join(process.cwd(), 'supabase', 'functions', '_shared', 'ai', 'tools');
    const comum = readFileSync(join(pastaPdf, 'gerar-e-guardar.ts'), 'utf8');
    expect(comum).toMatch(/import \{[^}]*\bcarregarPDFData\b[^}]*\} from "\.\/dados\.ts"/);
    expect(comum).toMatch(/import \{[^}]*\bbuildOrderHTML\b[^}]*\} from "\.\/documento\.ts"/);
    expect(comum).toMatch(/carregarPDFData\(/);
    expect(comum).toMatch(/buildOrderHTML\(/);
    expect(comum).not.toMatch(/PDFData = \{/);
    expect(comum).not.toMatch(/\.from\("service_orders"\)/);

    for (const nome of ['documentos-pdf.ts', 'whatsapp.ts']) {
      const tool = readFileSync(join(pastaTools, nome), 'utf8');
      // Usa a função comum...
      expect(tool, nome).toMatch(/import \{[^}]*\bmontarDocumentoDaOrdem\b[^}]*\} from "\.\.\/\.\.\/pdf\/gerar-e-guardar\.ts"/);
      expect(tool, nome).toMatch(/montarDocumentoDaOrdem\(admin/);
      // ...e não monta o documento por conta própria: nem PDFData, nem a montagem ou o desenho
      // chamados direto (seria um segundo caminho ao lado do comum).
      expect(tool, nome).not.toMatch(/PDFData = \{/);
      expect(tool, nome).not.toMatch(/\bcarregarPDFData\b/);
      expect(tool, nome).not.toMatch(/\bbuildOrderHTML\b/);
      expect(tool, nome).not.toMatch(/\.from\("service_orders"\)\s*\.select\([^)]*clients\(/);
    }
  });

  it('nenhuma edge monta PDFData por conta própria', () => {
    const raiz = join(process.cwd(), 'supabase', 'functions');
    const copias: string[] = [];
    const varrer = (dir: string) => {
      for (const e of readdirSync(dir, { withFileTypes: true })) {
        const caminho = join(dir, e.name);
        if (e.isDirectory()) { varrer(caminho); continue; }
        if (!e.name.endsWith('.ts') || e.name.endsWith('_test.ts')) continue;
        if (caminho.endsWith(join('_shared', 'pdf', 'dados.ts')) || caminho.endsWith(join('_shared', 'pdf', 'amostras.ts'))) continue;
        if (/const \w+: PDFData = \{/.test(readFileSync(caminho, 'utf8'))) copias.push(caminho.replace(raiz, ''));
      }
    };
    varrer(raiz);
    expect(copias, `montagem de PDFData fora de _shared/pdf/dados.ts: ${copias.join(', ')}`).toEqual([]);
  });
});
