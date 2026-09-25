import { describe, it, expect, vi, afterEach } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildHTMLDocument, DEFAULT_PDF_OPTIONS, type PDFData, type PDFOptions } from './pdf-generator';
import { ORCAMENTO, OS_COM_PAGAMENTO, AGORA } from '../../supabase/functions/_shared/pdf/amostras';

/**
 * O documento da ordem sai IGUAL na tela e no assistente do WhatsApp.
 *
 * ═══ POR QUE ESTE TESTE EXISTE ═══
 *
 * Desde 25/09/2026 o assistente gera o PDF numa Edge Function, que roda em UTC — três horas
 * à frente de Brasília. O desenho do documento é o mesmo arquivo para os dois, mas data
 * formatada sem fuso depende do relógio de quem gera: um orçamento criado às 23h30 sairia
 * "emitido" no dia seguinte quando pedido pelo WhatsApp, e diferente do baixado na tela.
 *
 * As referências em _shared/pdf/__referencia__ foram geradas com o código ANTERIOR à mudança
 * de pasta, no fuso de Brasília, e conferidas linha a linha: o orçamento saiu idêntico e a OS
 * difere numa linha só — "Pago em", que a tela imprimia um dia antes (coluna `date` lida como
 * meia-noite UTC). O teste Deno (_shared/pdf/documento_test.ts) compara com os MESMOS
 * arquivos: se os dois passam, o navegador e o servidor produzem o mesmo documento.
 *
 * Os fusos cobrem os dois lados de Brasília; o que importa é o resultado não depender dele.
 */

const REFERENCIA = join(process.cwd(), 'supabase', 'functions', '_shared', 'pdf', '__referencia__');
const ler = (arquivo: string) => readFileSync(join(REFERENCIA, arquivo), 'utf8').replace(/\r\n/g, '\n');

const CASOS: Array<{ arquivo: string; dados: PDFData; opcoes: PDFOptions }> = [
  { arquivo: 'orcamento.html', dados: ORCAMENTO, opcoes: { ...DEFAULT_PDF_OPTIONS, validity: { mode: 'days', days: 7 } } },
  { arquivo: 'os-com-pagamento.html', dados: OS_COM_PAGAMENTO, opcoes: { ...DEFAULT_PDF_OPTIONS } },
];
const FUSOS = ['America/Sao_Paulo', 'UTC', 'Asia/Tokyo', 'America/Los_Angeles'];
const FUSO_ORIGINAL = process.env.TZ;

afterEach(() => {
  vi.useRealTimers();
  process.env.TZ = FUSO_ORIGINAL;
});

describe('o documento não depende do fuso de quem gera', () => {
  for (const fuso of FUSOS) {
    for (const caso of CASOS) {
      it(`${caso.arquivo} em ${fuso} é igual à referência`, () => {
        process.env.TZ = fuso;
        vi.useFakeTimers();
        vi.setSystemTime(new Date(AGORA));
        expect(buildHTMLDocument(caso.dados, caso.opcoes)).toBe(ler(caso.arquivo));
      });
    }
  }

  // As datas que motivaram o teste, explícitas: quem vier mexer entende o que está em jogo.
  it('as datas saem no calendário de Brasília', () => {
    const orc = ler('orcamento.html');
    expect(orc).toContain('Emissão: 24/09/2026');                // criado às 23h30 do dia 24
    expect(orc).toContain('Válido por 7 dias (até 01/10/2026)'); // conta do dia 24, não do 25
    expect(orc).toContain('Emitido em 25/09/2026, 23:45:00');
    const os = ler('os-com-pagamento.html');
    expect(os).toContain('Agendado para: 25/09/2026 21:30');
    expect(os).toContain('Pago em 20/09/2026');                  // coluna date: dia como está
  });
});

describe('o desenho do documento continua importável pelo servidor', () => {
  const documento = readFileSync(
    join(process.cwd(), 'supabase', 'functions', '_shared', 'pdf', 'documento.ts'), 'utf8',
  );

  // Toda data passa por ./datas.ts. Um toLocaleDateString novo, sem fuso, reabriria a
  // diferença entre a tela e o WhatsApp sem nenhum outro teste perceber.
  it('nenhuma data é formatada sem fuso', () => {
    expect(documento).not.toMatch(/\.toLocale(Date|Time)?String\(/);
  });

  it('nada de navegador no desenho', () => {
    expect(documento).not.toMatch(/\b(window|document|localStorage|sessionStorage)\./);
  });
});
