import { describe, it, expect } from 'vitest';
import { calculateVoltageDrop } from './voltage-drop';

describe('calculateVoltageDrop', () => {
  it('classifica como conforme para circuito curto e bem dimensionado', () => {
    const result = calculateVoltageDrop({
      systemVoltage: 12,
      currentAmps: 10,
      lengthMeters: 2,
      crossSectionMm2: 6,
    });
    // V_drop = (2 * 2 * 10 * 0.017) / 6 = 0.1133...
    expect(result.dropVolts).toBeCloseTo(0.113, 2);
    expect(result.dropPercent).toBeLessThanOrEqual(3);
    expect(result.classification).toBe('ok');
  });

  it('classifica como atenção entre 3% e 10%', () => {
    const result = calculateVoltageDrop({
      systemVoltage: 12,
      currentAmps: 30,
      lengthMeters: 8,
      crossSectionMm2: 10,
    });
    // V_drop = (2 * 8 * 30 * 0.017) / 10 = 0.816 -> 6.8%
    expect(result.dropPercent).toBeGreaterThan(3);
    expect(result.dropPercent).toBeLessThanOrEqual(10);
    expect(result.classification).toBe('attention');
  });

  it('classifica como crítico acima de 10%', () => {
    const result = calculateVoltageDrop({
      systemVoltage: 12,
      currentAmps: 50,
      lengthMeters: 12,
      crossSectionMm2: 6,
    });
    // V_drop = (2 * 12 * 50 * 0.017) / 6 = 3.4 -> ~28%
    expect(result.dropPercent).toBeGreaterThan(10);
    expect(result.classification).toBe('critical');
  });

  it('retorna invalid quando entradas são inválidas', () => {
    expect(calculateVoltageDrop({ systemVoltage: 0, currentAmps: 10, lengthMeters: 5, crossSectionMm2: 4 }).classification).toBe('invalid');
    expect(calculateVoltageDrop({ systemVoltage: 12, currentAmps: 10, lengthMeters: 5, crossSectionMm2: 0 }).classification).toBe('invalid');
    expect(calculateVoltageDrop({ systemVoltage: NaN, currentAmps: 10, lengthMeters: 5, crossSectionMm2: 4 }).classification).toBe('invalid');
  });
});
