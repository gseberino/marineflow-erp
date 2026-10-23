// O recibo de um pagamento (leva 8, 22/10/2026): a função única de ReceivablesV2, FinancialPage e do "Recibo deste
// pagamento". Leitura que falha não gera PDF; o CPF/CNPJ do cliente vem do cadastro (o embed das listas não traz);
// "Recebemos de X por conta de Y" só quando um terceiro pagou, com o CPF dele mascarado.
import { describe, it, expect, vi, beforeEach } from 'vitest';

type Resposta = { data: unknown; error: unknown };

const estado = vi.hoisted(() => ({
  respostas: {} as Record<string, { data: unknown; error: unknown }>,
  filtros: [] as Array<[string, string, unknown]>,
  impressos: [] as unknown[],
  toasts: [] as string[],
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: (tabela: string) => {
      const cadeia: Record<string, unknown> = {};
      for (const m of ['select', 'order', 'limit']) cadeia[m] = () => cadeia;
      cadeia.eq = (c: string, v: unknown) => { estado.filtros.push([tabela, c, v]); return cadeia; };
      cadeia.then = (ok: (v: unknown) => unknown, nok: (e: unknown) => unknown) =>
        Promise.resolve(estado.respostas[tabela] ?? { data: [], error: null }).then(ok, nok);
      return cadeia;
    },
  },
}));
vi.mock('@/lib/pdf-print', () => ({ printPDF: (dados: unknown) => { estado.impressos.push(dados); } }));
vi.mock('sonner', () => ({ toast: { error: (m: string) => { estado.toasts.push(m); } } }));

import { generateReceivableReceipt, montarDadosDoRecibo, type ReceivableRow } from './receipt';
import { buildHTMLDocument, buildPDFFilename, DEFAULT_PDF_OPTIONS, type PDFData } from '@/lib/pdf-generator';

const CONTA: ReceivableRow = {
  id: 'r1', description: 'Sinal OS-00900', amount: 3000, paid_amount: 1500, status: 'partially_paid',
  due_date: '2026-10-20', client_id: 'c1',
  // como as listas trazem: sem cpf_cnpj no embed
  clients: { id: 'c1', name: 'Cliente da Lista', phone: '11999990000' },
  service_orders: { id: 'so1', service_order_number: 'OS-00900' },
};

const PAGAMENTO = { id: 'p1', amount: 1500, payment_date: '2026-10-20', payment_method: 'pix', notes: null, status: 'confirmed' };

function respostas(r: Partial<Record<string, Resposta>>) {
  estado.respostas = {
    app_settings: { data: [{ key: 'company_name', value: 'HBR Marine' }, { key: 'cnpj', value: '00.000.000/0001-00' }], error: null },
    payments: { data: [PAGAMENTO], error: null },
    clients: { data: [{ name: 'Cliente Teste', cpf_cnpj: '98.765.432/0001-10', phone: null, email: null }], error: null },
    pagamentos_com_pagador: { data: [{ pagador_nome: 'MARIA SOUZA', pagador_documento: '12345678901', situacao: 'terceiro' }], error: null },
    ...r,
  } as Record<string, Resposta>;
}

beforeEach(() => {
  estado.filtros = [];
  estado.impressos = [];
  estado.toasts = [];
  respostas({});
});

describe('generateReceivableReceipt — leitura que falha não gera PDF', () => {
  it.each([
    ['app_settings', 'Não consegui ler os dados da empresa para o recibo: falhou'],
    ['payments', 'Não consegui ler o pagamento para o recibo: falhou'],
    ['clients', 'Não consegui ler o cadastro do cliente para o recibo: falhou'],
    ['pagamentos_com_pagador', 'Não consegui conferir quem pagou: falhou'],
  ])('erro em %s: avisa e nenhum PDF', async (tabela, aviso) => {
    respostas({ [tabela]: { data: null, error: { message: 'falhou' } } });
    expect(await generateReceivableReceipt(CONTA)).toBe(false);
    expect(estado.impressos).toEqual([]);
    expect(estado.toasts).toEqual([aviso]);
  });

  it('sem pagamento confirmado e sem valor pago: avisa e nenhum PDF', async () => {
    respostas({ payments: { data: [], error: null } });
    expect(await generateReceivableReceipt({ ...CONTA, paid_amount: 0 })).toBe(false);
    expect(estado.impressos).toEqual([]);
    expect(estado.toasts).toEqual(['Não há pagamento confirmado para gerar recibo']);
  });

  it('o pagamento pedido foi estornado: nenhum PDF', async () => {
    respostas({ payments: { data: [{ ...PAGAMENTO, status: 'cancelled' }], error: null } });
    expect(await generateReceivableReceipt(CONTA, 'p1')).toBe(false);
    expect(estado.impressos).toEqual([]);
    expect(estado.toasts[0]).toMatch(/estornado/);
  });
});

describe('montarDadosDoRecibo', () => {
  it('terceiro pagou: payer com o CPF mascarado, e o CPF/CNPJ do cliente vem do cadastro', async () => {
    const r = await montarDadosDoRecibo(CONTA);
    expect(r.ok).toBe(true);
    const pdf = (r as { pdf: PDFData }).pdf;
    expect(pdf.receipt?.payer).toEqual({ name: 'MARIA SOUZA', cpf_cnpj: '***.456.789-**' });
    expect(JSON.stringify(pdf)).not.toContain('12345678901');
    expect(pdf.client).toMatchObject({ name: 'Cliente Teste', cpf_cnpj: '98.765.432/0001-10' });
    expect(pdf.receipt).toMatchObject({ amount: 1500, payment_method: 'pix', reference: 'OS-00900' });
    expect(estado.filtros).toContainEqual(['clients', 'id', 'c1']);
    expect(estado.filtros).toContainEqual(['pagamentos_com_pagador', 'payment_id', 'p1']);
  });

  it('nome do banco com o CPF dentro ("12345678901-MARIA", o MEI "MARIA 123.456.789-01"): o payer sai mascarado', async () => {
    for (const nome of ['12345678901-MARIA SOUZA', 'MARIA SOUZA 123.456.789-01']) {
      respostas({ pagamentos_com_pagador: { data: [{ pagador_nome: nome, pagador_documento: '12345678901', situacao: 'terceiro' }], error: null } });
      const r = await montarDadosDoRecibo(CONTA);
      const pdf = (r as { pdf: PDFData }).pdf;
      expect(pdf.receipt?.payer?.name).toMatch(/\*\*\*\.456\.789-\*\*/);
      expect(pdf.receipt?.payer?.name).toMatch(/MARIA SOUZA/);
      expect(JSON.stringify(pdf)).not.toMatch(/12345678901|123\.456\.789-01/);
    }
  });

  it('pagador de CNPJ: inteiro e formatado', async () => {
    respostas({ pagamentos_com_pagador: { data: [{ pagador_nome: 'ACME LTDA', pagador_documento: '04754513000149', situacao: 'terceiro' }], error: null } });
    const r = await montarDadosDoRecibo(CONTA);
    expect((r as { pdf: PDFData }).pdf.receipt?.payer).toEqual({ name: 'ACME LTDA', cpf_cnpj: '04.754.513/0001-49' });
  });

  it.each(['cliente', 'indefinido', 'sem_dado'])('situação %s: sem payer ("nome diferente nunca identifica")', async (situacao) => {
    respostas({ pagamentos_com_pagador: { data: [{ pagador_nome: 'MARIA SOUZA', pagador_documento: '12345678901', situacao }], error: null } });
    const r = await montarDadosDoRecibo(CONTA);
    expect(r.ok).toBe(true);
    expect((r as { pdf: PDFData }).pdf.receipt).not.toHaveProperty('payer');
  });

  it('com paymentId: lê aquele pagamento, da mesma conta', async () => {
    await montarDadosDoRecibo(CONTA, 'p1');
    expect(estado.filtros).toContainEqual(['payments', 'id', 'p1']);
    expect(estado.filtros).toContainEqual(['payments', 'receivable_id', 'r1']);
    expect(estado.filtros).not.toContainEqual(['payments', 'status', 'confirmed']);
  });

  it('conta antiga paga sem pagamento registrado: recibo do valor pago, sem consultar quem pagou', async () => {
    respostas({ payments: { data: [], error: null } });
    const r = await montarDadosDoRecibo(CONTA);
    expect(r.ok).toBe(true);
    expect((r as { pdf: PDFData }).pdf.receipt).toMatchObject({ amount: 1500 });
    expect(estado.filtros.some(([t]) => t === 'pagamentos_com_pagador')).toBe(false);
  });

  // Revisão de 23/10/2026, 4ª rodada: a receita sem OS que nasce da fila do Extrato tem description = o nome que o banco
  // escreveu, às vezes com o CPF de quem pagou dentro. A referência do recibo passa SEMPRE por nomeSemCpf — em qualquer
  // situação de quem pagou (no 'indefinido' não há payer, e o CPF saía inteiro do mesmo jeito).
  it.each(['terceiro', 'indefinido', 'cliente', 'sem_dado'])(
    'conta sem OS com o CPF na descrição (%s): nem a referência, nem o HTML final, nem o nome do arquivo levam o CPF inteiro',
    async (situacao) => {
      respostas({ pagamentos_com_pagador: { data: [{ pagador_nome: '12345678901-MARIA SOUZA', pagador_documento: '12345678901', situacao }], error: null } });
      for (const description of ['12345678901-MARIA SOUZA', 'MARIA SOUZA 123.456.789-01']) {
        const r = await montarDadosDoRecibo({ ...CONTA, description, service_orders: null });
        expect(r.ok).toBe(true);
        const pdf = (r as { pdf: PDFData }).pdf;
        expect(pdf.receipt?.reference).toMatch(/\*\*\*\.456\.789-\*\*/);
        expect(pdf.receipt?.reference).toMatch(/MARIA SOUZA/);
        expect(pdf.serviceOrder.service_order_number).toBe(pdf.receipt?.reference);
        expect(JSON.stringify(pdf)).not.toMatch(/12345678901|123\.456\.789-01/);
        // O HTML final (REC-…, título, "referente ao pagamento de") e o nome do arquivo/título da impressão.
        const html = buildHTMLDocument(pdf, DEFAULT_PDF_OPTIONS);
        expect(html).not.toMatch(/12345678901|123\.456\.789-01/);
        expect(html.replace(/\s+/g, ' ')).toContain(`referente ao pagamento de <strong>${pdf.receipt?.reference}</strong>`);
        expect(buildPDFFilename(pdf, DEFAULT_PDF_OPTIONS)).not.toMatch(/12345678901|123-456-789-01/);
      }
    },
  );

  it('a observação do pagamento também entra sem o CPF inteiro', async () => {
    respostas({ payments: { data: [{ ...PAGAMENTO, notes: 'Pix de 12345678901-MARIA' }], error: null } });
    const r = await montarDadosDoRecibo(CONTA);
    expect((r as { pdf: PDFData }).pdf.receipt?.notes).toBe('Pix de ***.456.789-**-MARIA');
  });

  it('com OS, a referência continua o número dela', async () => {
    const r = await montarDadosDoRecibo({ ...CONTA, description: '12345678901-MARIA SOUZA' });
    const pdf = (r as { pdf: PDFData }).pdf;
    expect(pdf.receipt?.reference).toBe('OS-00900');
    expect(pdf.serviceOrder.service_order_number).toBe('OS-00900');
  });

  it('gera o PDF quando tudo deu certo', async () => {
    expect(await generateReceivableReceipt(CONTA)).toBe(true);
    expect(estado.impressos).toHaveLength(1);
    expect(estado.toasts).toEqual([]);
  });
});
