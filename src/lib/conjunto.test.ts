import { describe, expect, it } from 'vitest';
import {
  type CandidatoAoConjunto,
  type Conjunto,
  alvosDoEnvio,
  decidirComoAgrupar,
  listaNatural,
  mensagemPadraoDoConjunto,
  nomeDoArquivoDoConjunto,
  normalizarConjunto,
  normalizarLeitura,
  quadroDeValores,
  situacaoDoDocumento,
} from './conjunto';

const cand = (p: Partial<CandidatoAoConjunto>): CandidatoAoConjunto => ({
  id: 'x', numero: 'OS-1', tipo: 'os', status: 'approved', quote_status: 'approved', grand_total: 0, criado_em: '',
  motivo: null, motivo_juntar: null, ...p,
});

// O exemplo da conversa com o dono: OS-00104 (R$ 5.000, sinal de 2.500 pago, assinada) + ORÇ-00140 (R$ 1.200, sinal 600).
const exemplo: Conjunto = normalizarConjunto({
  id: 'c1', nome: 'OS-00104 + ORÇ-00140', ativo: true, criado_em: '2026-11-18', client_id: 'cli', cliente: 'Giancarlo',
  vessel_id: 'v', embarcacao: 'Lancha X', principal_id: 'a', total_geral: '6200.00',
  documentos: [
    { id: 'a', numero: 'OS-00104', tipo: 'os', status: 'scheduled', quote_status: 'approved', principal: true, ativo: true,
      assinado: true, grand_total: '5000.00', recebido: '2500', sinal_a_pagar: 0, em_aberto: 0 },
    { id: 'b', numero: 'ORÇ-00140', tipo: 'orcamento', status: 'draft', quote_status: 'draft', principal: false, ativo: true,
      assinado: false, grand_total: '1200.00', recebido: 0, sinal_a_pagar: '600', em_aberto: '600' },
  ],
})!;

describe('decidirComoAgrupar (decisão 4B)', () => {
  it('menos de 2 ou mais de 10: não agrupa', () => {
    expect(decidirComoAgrupar([cand({})]).podeConjunto).toBe(false);
    expect(decidirComoAgrupar(Array.from({ length: 11 }, (_, i) => cand({ id: String(i) }))).podeConjunto).toBe(false);
  });
  it('documento barrado: diz o motivo do banco', () => {
    const r = decidirComoAgrupar([cand({ id: '1' }), cand({ id: '2', motivo: 'OS-2 está cancelado.' })]);
    expect(r).toMatchObject({ podeConjunto: false, motivoConjunto: 'OS-2 está cancelado.' });
  });
  it('ORÇ + OS: só apresentar junto, com o porquê', () => {
    const r = decidirComoAgrupar([cand({ id: '1' }), cand({ id: '2', tipo: 'orcamento' })]);
    expect(r.podeConjunto).toBe(true);
    expect(r.fusao).toBeNull();
    expect(r.porQueNaoFunde).toMatch(/mesmo tipo/);
  });
  it('OS que já começou: só apresentar junto, com a frase do banco', () => {
    const r = decidirComoAgrupar([cand({ id: '1' }), cand({ id: '2', motivo_juntar: 'OS-2 já começou a ser executada.' })]);
    expect(r).toMatchObject({ podeConjunto: true, fusao: null, porQueNaoFunde: 'OS-2 já começou a ser executada.' });
  });
  it('todos fundíveis e do mesmo tipo: oferece as duas', () => {
    expect(decidirComoAgrupar([cand({ id: '1' }), cand({ id: '2' })]).fusao).toBe('os');
    expect(decidirComoAgrupar([cand({ id: '1', tipo: 'orcamento' }), cand({ id: '2', tipo: 'orcamento' })]).fusao).toBe('orcamentos');
  });
});

describe('quadro de valores (decisão 3A: cada um com o seu sinal)', () => {
  it('o exemplo: já pago 2.500, pagar agora 600, saldo 3.100', () => {
    const q = quadroDeValores(exemplo);
    expect(q).toMatchObject({ total: 6200, recebido: 2500, aPagarAgora: 600, saldo: 3100 });
    expect(q.linhas.map((l) => [l.numero, l.saldo])).toEqual([['OS-00104', 2500], ['ORÇ-00140', 600]]);
  });
  it('documento que saiu do conjunto não conta', () => {
    const c = { ...exemplo, documentos: exemplo.documentos.map((d, i) => (i === 1 ? { ...d, ativo: false } : d)) };
    expect(quadroDeValores(c).total).toBe(5000);
  });
  it('saldo nunca fica negativo', () => {
    const c = { documentos: [{ ...exemplo.documentos[0], recebido: 6000 }] };
    expect(quadroDeValores(c).saldo).toBe(0);
  });
});

describe('textos', () => {
  it('situação em palavras do cliente', () => {
    expect(situacaoDoDocumento(exemplo.documentos[0])).toBe('agendada, assinada');
    expect(situacaoDoDocumento(exemplo.documentos[1])).toBe('em elaboração');
  });
  it('lista natural, nome do arquivo e mensagem', () => {
    expect(listaNatural(['A', 'B', 'C'])).toBe('A, B e C');
    expect(nomeDoArquivoDoConjunto(exemplo)).toBe('OS-00104 + ORÇ-00140.pdf');
    expect(mensagemPadraoDoConjunto(exemplo)).toBe(
      'Segue OS-00104 e ORÇ-00140 num documento só, conforme solicitado. Qualquer dúvida, estamos à disposição.',
    );
  });
});

describe('alvosDoEnvio', () => {
  it('com orçamento: contexto de orçamento no 1º, os outros orçamentos vão junto', () => {
    const c = { ...exemplo, documentos: [...exemplo.documentos, { ...exemplo.documentos[1], id: 'c', numero: 'ORÇ-00141' }] };
    expect(alvosDoEnvio(c)).toEqual({ context: 'quote', serviceOrderId: 'b', outrosOrcamentos: ['c'] });
  });
  it('só OS: contexto de OS no principal', () => {
    const c = { ...exemplo, documentos: [exemplo.documentos[0], { ...exemplo.documentos[0], id: 'z', principal: false }] };
    expect(alvosDoEnvio(c)).toEqual({ context: 'service_order', serviceOrderId: 'a', outrosOrcamentos: [] });
  });
});

describe('normalização', () => {
  it('numeric em texto vira número; nulo vira null', () => {
    expect(exemplo.total_geral).toBe(6200);
    expect(exemplo.documentos[1].sinal_a_pagar).toBe(600);
    expect(normalizarConjunto(null)).toBeNull();
  });
  it('leitura de candidatos', () => {
    const l = normalizarLeitura({ documento: { id: 'a', numero: 'OS-1', tipo: 'os', motivo_juntar: 'x' }, candidatos: [{ id: 'b', tipo: 'orcamento' }] });
    expect(l?.documento.motivo_juntar).toBe('x');
    expect(l?.candidatos[0].tipo).toBe('orcamento');
    expect(normalizarLeitura({})).toBeNull();
  });
});
