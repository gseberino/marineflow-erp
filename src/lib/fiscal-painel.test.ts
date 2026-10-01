// Lista de notas e painel de saúde fiscal (D33, passo 2, 01/10/2026). Horários ao meio-dia de
// Brasília: o dia local é o mesmo em qualquer fuso razoável de quem roda o teste.
import { describe, it, expect } from 'vitest';
import { naturezasDasNotas, filtrarNotas, estatisticasDoMes, validadeDoCertificado } from './fiscal-painel';

const venda = (o: Record<string, unknown> = {}) => ({
  document_type: 'nfe', status: 'authorized', environment: 'producao', number: 31,
  authorized_at: '2026-09-10T12:00:00-03:00', created_at: '2026-09-10T12:00:00-03:00',
  request_payload: {
    purpose: 1, nature_operation: 'Venda de mercadoria',
    recipient: { name: 'MARINA EXEMPLO LTDA', cpf_cnpj: '12345678000199' },
    items: [{ quantity: 2, unit_price: 250 }],
  },
  ...o,
});
const servico = {
  document_type: 'nfse', status: 'authorized', environment: 'producao', number: 6,
  authorized_at: null, created_at: '2026-09-16T12:00:00-03:00',
  request_payload: {
    taker: { name: 'CLIENTE DO SERVIÇO', document: '65725468020' },
    service: { description: 'Instalação elétrica' }, amounts: { service_amount: 500 },
  },
};
const devolucao = venda({
  number: 32,
  request_payload: {
    purpose: 4, nature_operation: 'Devolução de compra',
    recipient: { name: 'FORNECEDOR EXEMPLO LTDA', cpf_cnpj: '12696968000183' },
    items: [{ quantity: 1, unit_price: 100 }],
  },
});
const homologacao = venda({ environment: 'homologacao', number: 1 });
const rejeitada = venda({ status: 'rejected', authorized_at: null, number: 33 });
const cancelada = venda({ status: 'cancelled', number: 34 });
const deAgosto = venda({ authorized_at: '2026-08-20T12:00:00-03:00', created_at: '2026-08-20T12:00:00-03:00', number: 30 });
const semAmbiente = venda({ environment: undefined, number: 35 });

const todas = [venda(), servico, devolucao, homologacao, rejeitada, cancelada, deAgosto, semAmbiente];

describe('naturezasDasNotas', () => {
  it('as naturezas que existem nas notas, sem repetir, em ordem alfabética', () => {
    expect(naturezasDasNotas(todas)).toEqual(['Devolução de compra', 'Prestação de serviço', 'Venda de mercadoria']);
    expect(naturezasDasNotas(undefined)).toEqual([]);
  });
});

describe('filtrarNotas', () => {
  const nums = (ds: unknown[]) => ds.map((d) => (d as { number: number }).number);

  it('sem filtro, todas', () => {
    expect(filtrarNotas(todas, {})).toHaveLength(todas.length);
  });

  it('por status, tipo e natureza', () => {
    expect(nums(filtrarNotas(todas, { status: ['rejected', 'cancelled'] }))).toEqual([33, 34]);
    expect(nums(filtrarNotas(todas, { tipo: ['NFS-e'] }))).toEqual([6]);
    expect(nums(filtrarNotas(todas, { natureza: ['Devolução de compra'] }))).toEqual([32]);
  });

  it('por ambiente: nota sem ambiente conta como produção', () => {
    expect(nums(filtrarNotas(todas, { ambiente: ['homologacao'] }))).toEqual([1]);
    expect(nums(filtrarNotas(todas, { ambiente: ['producao'] }))).toContain(35);
  });

  it('por período, pelo dia da nota (autorização; sem ela, a criação)', () => {
    expect(nums(filtrarNotas(todas, { dateFrom: '2026-08-01', dateTo: '2026-08-31' }))).toEqual([30]);
    expect(nums(filtrarNotas(todas, { dateFrom: '2026-09-16', dateTo: '2026-09-16' }))).toEqual([6]);
    // Rejeitada não tem autorização: vale a data da tentativa.
    expect(nums(filtrarNotas(todas, { dateFrom: '2026-09-10', dateTo: '2026-09-10' }))).toContain(33);
  });

  it('busca por texto: tomador, documento, número', () => {
    expect(nums(filtrarNotas(todas, { search: 'fornecedor' }))).toEqual([32]);
    expect(nums(filtrarNotas(todas, { search: '  65725468020 ' }))).toEqual([6]);
  });
});

describe('estatisticasDoMes', () => {
  const setembro = new Date(2026, 8, 20, 12, 0, 0);

  it('fatura só o que é autorizado, de produção e não é devolução', () => {
    const s = estatisticasDoMes(todas, setembro);
    // autorizadas em setembro: venda, serviço, devolução, homologação e a sem ambiente
    expect(s.authorized).toBe(5);
    // venda (500) + serviço (500); a sem ambiente fica fora (não é "producao" declarada)
    expect(s.faturaveis).toBe(2);
    expect(s.faturamento).toBe(1000);
    expect(s.foraDoFaturamento).toBe(3);
    expect(s.rejected).toBe(1);
    expect(s.cancelled).toBe(1);
    expect(s.eventos).toBe(7);
  });

  it('agosto fica fora de setembro', () => {
    const s = estatisticasDoMes([deAgosto], setembro);
    expect(s.authorized).toBe(0);
    expect(s.faturamento).toBe(0);
  });
});

describe('validadeDoCertificado', () => {
  const agora = new Date(2026, 9, 1, 10, 0, 0).getTime();

  it('dias até o fim do dia da validade', () => {
    expect(validadeDoCertificado('2026-10-31', agora)).toEqual({ validUntil: '2026-10-31', days: 30 });
    expect(validadeDoCertificado('2026-10-01', agora)?.days).toBe(0);
    expect(validadeDoCertificado('2026-09-30', agora)?.days).toBe(-1);
  });

  it('sem data ou data que não se lê: nada (antes, "NaN dias")', () => {
    expect(validadeDoCertificado(null, agora)).toBeNull();
    expect(validadeDoCertificado('31/12/2026', agora)).toBeNull();
  });
});
