import { describe, it, expect } from 'vitest';
import { comoDiaLocal, diasAte, hojeLocal } from './dia';

describe('dia do calendário', () => {
  it('lê AAAA-MM-DD no dia escrito, não na véspera', () => {
    const d = comoDiaLocal('2026-10-01');
    expect([d.getFullYear(), d.getMonth() + 1, d.getDate()]).toEqual([2026, 10, 1]);
    expect(d.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' })).toBe('outubro de 2026');
  });

  it('conta que vence hoje não está em atraso, nem de manhã nem à noite', () => {
    expect(diasAte('2026-09-26', new Date(2026, 8, 26, 8, 0))).toBe(0);
    expect(diasAte('2026-09-26', new Date(2026, 8, 26, 23, 30))).toBe(0);
    expect(diasAte('2026-09-25', new Date(2026, 8, 26, 0, 5))).toBe(-1);
    expect(diasAte('2026-10-03', new Date(2026, 8, 26, 12, 0))).toBe(7);
  });

  it('hoje local no formato do banco', () => {
    expect(hojeLocal(new Date(2026, 0, 5, 23, 59))).toBe('2026-01-05');
  });
});
