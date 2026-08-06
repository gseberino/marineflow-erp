import { describe, it, expect } from 'vitest';

/**
 * A conta de queda de tensão, replicada aqui para travar o comportamento.
 *
 * O cálculo de verdade mora no banco (dc_cable_min_mm2_by_drop), mas esta
 * fórmula é o coração de uma decisão de segurança: cabo subdimensionado
 * esquenta. Se alguém mexer na constante, no fator de ida e volta ou na
 * conversão para mm², estes testes caem antes de o erro chegar num orçamento.
 *
 *   CM  = (10,75 × I × comprimento_ida_e_volta_pés) / (V × queda%)
 *   mm² = CM / 1973,53
 */
export function minMm2ByDrop(
  amps: number, oneWayMeters: number, volts = 12, maxDropPct = 3,
): number | null {
  if (!(amps > 0) || !(oneWayMeters > 0) || !(volts > 0) || !(maxDropPct > 0)) return null;
  const roundTripFeet = oneWayMeters * 2 * 3.28084;
  const cm = (10.75 * amps * roundTripFeet) / (volts * (maxDropPct / 100));
  return Math.round((cm / 1973.53) * 100) / 100;
}

describe('seção mínima por queda de tensão', () => {
  // O caso real do ORÇ-00074: foi ele que expôs o problema. A regra sugeria
  // 35 mm² e o circuito pedia 62.
  it('o caso que gerou tudo: 250 A, 2,5 m, 12 V, 3%', () => {
    expect(minMm2ByDrop(250, 2.5, 12, 3)).toBeCloseTo(62.05, 1);
  });

  it('35 mm² é insuficiente para esse circuito', () => {
    expect(minMm2ByDrop(250, 2.5, 12, 3)!).toBeGreaterThan(35);
  });

  // O erro clássico do ramo: usar o comprimento simples em vez do de ida e
  // volta subdimensiona pela metade.
  it('o comprimento é de ida e volta, não simples', () => {
    const comIdaEVolta = minMm2ByDrop(100, 10, 12, 3)!;
    const seFosseSimples = (10.75 * 100 * (10 * 3.28084)) / (12 * 0.03) / 1973.53;
    expect(comIdaEVolta).toBeCloseTo(seFosseSimples * 2, 1);
  });

  it('dobrar a tensão corta a bitola pela metade', () => {
    expect(minMm2ByDrop(100, 5, 24, 3)!).toBeCloseTo(minMm2ByDrop(100, 5, 12, 3)! / 2, 1);
  });

  // A diferença entre circuito crítico e não crítico é o que mais muda o
  // resultado — e é a pergunta que ninguém lembra de fazer.
  it('3% pede mais que o triplo de 10%', () => {
    const critico = minMm2ByDrop(150, 4, 12, 3)!;
    const naoCritico = minMm2ByDrop(150, 4, 12, 10)!;
    expect(critico / naoCritico).toBeCloseTo(10 / 3, 1);
  });

  it('sem dado não devolve zero nem chute, devolve nada', () => {
    expect(minMm2ByDrop(0, 5)).toBeNull();
    expect(minMm2ByDrop(100, 0)).toBeNull();
    expect(minMm2ByDrop(-5, 5)).toBeNull();
    expect(minMm2ByDrop(100, 5, 0)).toBeNull();
  });

  // Confere contra a faixa conhecida das tabelas Blue Sea/ABYC: 50 A em ~9 m
  // de ida e volta a 12 V com 3% cai entre AWG 3 e 4 (21 a 27 mm²).
  it('bate com a faixa das tabelas publicadas', () => {
    const r = minMm2ByDrop(50, 4.5, 12, 3)!;
    expect(r).toBeGreaterThan(20);
    expect(r).toBeLessThan(28);
  });
});
