// [RATEIO-DESCONTO] Testes com os NÚMEROS REAIS do incidente de 27/08/2026 — a 1ª
// emissão de produção saiu com NFS-e/NF-e BRUTAS enquanto a OS tinha desconto global:
// as notas somavam mais do que o cliente paga. Estes casos travam a correção.
import { describe, it, expect } from 'vitest';
import { ratearDescontoGlobal } from '../../supabase/functions/_shared/fiscal/rateio-desconto';

const r2 = (n: number) => Math.round(n * 100) / 100;

describe('rateio do desconto global da OS', () => {
  it('OS-00060 real: 2.500 serviços + 18.060,67 peças − 560,67 = 20.000 exatos', () => {
    // A nota que saiu errada: NFS-e 2.500,00 (bruta) — deveria ser 2.431,83.
    const pecas = [10260.32, 1605.91, 3484.54, 1099.9, 280, 980, 350]; // qtd×unitário da NF-e 26
    const r = ratearDescontoGlobal(560.67, 2500, pecas);
    expect(r2(r.descontoServicos + r.descontoPecas)).toBe(560.67);
    expect(r2(2500 - r.descontoServicos)).toBe(2431.83);
    const somaItens = r2(r.descontosPorItem.reduce((a, b) => a + b, 0));
    expect(somaItens).toBe(r.descontoPecas);
    const nfeLiquida = r2(pecas.reduce((a, b) => a + b, 0) - r.descontoPecas);
    // NFS-e líquida + NF-e líquida = exatamente o que a OS cobra.
    expect(r2(2431.83 + nfeLiquida)).toBe(20000);
  });

  it('OS-00075 real: 538,33 serviços + 192,01 peças (LÍQUIDAS de desconto de linha) − 230,34 = 500', () => {
    // A NF-e 27 saiu com itens BRUTOS (225,90) ignorando os descontos POR LINHA
    // (13,32 + 5,82 + 14,75 = 33,89) — o rateio do desconto GLOBAL usa as bases
    // LÍQUIDAS de linha, que são o que a OS de fato cobra.
    const pecasLiquidas = [75.46, 32.96, 83.59]; // line_total_sale reais
    expect(r2(pecasLiquidas.reduce((a, b) => a + b, 0))).toBe(192.01);
    const r = ratearDescontoGlobal(230.34, 538.33, pecasLiquidas);
    expect(r2(r.descontoServicos + r.descontoPecas)).toBe(230.34);
    const nfseLiquida = r2(538.33 - r.descontoServicos);
    const nfeLiquida = r2(192.01 - r.descontoPecas);
    expect(r2(nfseLiquida + nfeLiquida)).toBe(500);
  });

  it('sem desconto: tudo zero', () => {
    const r = ratearDescontoGlobal(0, 1000, [500, 500]);
    expect(r.descontoServicos).toBe(0);
    expect(r.descontoPecas).toBe(0);
    expect(r.descontosPorItem).toEqual([0, 0]);
  });

  it('OS só de serviços: desconto inteiro na NFS-e', () => {
    const r = ratearDescontoGlobal(100, 1000, []);
    expect(r.descontoServicos).toBe(100);
    expect(r.descontoPecas).toBe(0);
  });

  it('OS só de peças: desconto inteiro na NF-e, centavo fecha no último item', () => {
    const r = ratearDescontoGlobal(100, 0, [33.33, 33.33, 33.34]);
    expect(r.descontoServicos).toBe(0);
    expect(r2(r.descontosPorItem.reduce((a, b) => a + b, 0))).toBe(100);
  });

  it('desconto maior que a base não produz item negativo (dado quebrado trava no teto)', () => {
    const r = ratearDescontoGlobal(2000, 100, [50, 50]);
    expect(r2(r.descontoServicos + r.descontoPecas)).toBe(200);
    r.descontosPorItem.forEach((d, i) => expect(d).toBeLessThanOrEqual([50, 50][i]));
  });

  it('item zerado no meio não recebe desconto nem quebra o resíduo', () => {
    const r = ratearDescontoGlobal(30, 0, [100, 0, 200]);
    expect(r.descontosPorItem[1]).toBe(0);
    expect(r2(r.descontosPorItem[0] + r.descontosPorItem[2])).toBe(30);
  });
});
