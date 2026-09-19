import { describe, it, expect } from 'vitest';
import { chaveDeEnvioDoPainel, hashCurto } from './hash-curto';

describe('chave de idempotência do painel', () => {
  it('hash é determinístico e sensível ao conteúdo', () => {
    expect(hashCurto('abc')).toBe(hashCurto('abc'));
    expect(hashCurto('abc')).not.toBe(hashCurto('abd'));
  });

  it('mesmo envio na mesma janela de 10 min tem a mesma chave; janela seguinte muda', () => {
    const t = Date.UTC(2026, 8, 19, 12, 0, 0);
    const a = chaveDeEnvioDoPainel('5547999990000', 'document:ORC-60.pdf', t);
    const b = chaveDeEnvioDoPainel('5547999990000', 'document:ORC-60.pdf', t + 3 * 60 * 1000);
    const c = chaveDeEnvioDoPainel('5547999990000', 'document:ORC-60.pdf', t + 11 * 60 * 1000);
    expect(a).toBe(b);
    expect(a).not.toBe(c);
    expect(a.startsWith('painel:5547999990000:')).toBe(true);
  });
});
