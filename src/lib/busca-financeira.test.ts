import { describe, it, expect } from 'vitest';
import { casaComBusca, valorDigitado, normalizar, buscaAtiva } from './busca-financeira';

const pix = {
  textos: ['Pix enviado', 'COREMMA COMERCIO LTDA', '12.345.678/0001-90', 'Peças elétricas'],
  valores: [1250, '1250.00'],
  data: '2026-09-10',
};

describe('valorDigitado', () => {
  it('entende o valor como o brasileiro escreve', () => {
    expect(valorDigitado('150')).toBe(150);
    expect(valorDigitado('150,50')).toBe(150.5);
    expect(valorDigitado('1.250,00')).toBe(1250);
    expect(valorDigitado('1.250')).toBe(1250);
    expect(valorDigitado('R$ 50')).toBe(50);
    expect(valorDigitado('12.5')).toBe(12.5);
  });
  it('texto com letra não é valor', () => {
    expect(valorDigitado('OS-60')).toBeNull();
    expect(valorDigitado('coremma')).toBeNull();
    expect(valorDigitado('')).toBeNull();
  });
});

describe('casaComBusca', () => {
  it('acha por nome sem ligar para acento e caixa', () => {
    expect(casaComBusca(pix, { termo: 'coremma' })).toBe(true);
    expect(casaComBusca(pix, { termo: 'PECAS' })).toBe(true);
    expect(normalizar('Alimentação')).toBe('alimentacao');
  });
  it('acha por CNPJ com ou sem pontuação', () => {
    expect(casaComBusca(pix, { termo: '12345678' })).toBe(true);
    expect(casaComBusca(pix, { termo: '12.345.678/0001' })).toBe(true);
  });
  it('acha por valor digitado, com folga de arredondamento', () => {
    expect(casaComBusca(pix, { termo: '1.250,00' })).toBe(true);
    expect(casaComBusca(pix, { termo: '1250' })).toBe(true);
    expect(casaComBusca(pix, { termo: '1300' })).toBe(false);
  });
  it('período recorta pela data, inclusive nas pontas', () => {
    expect(casaComBusca(pix, { termo: '', de: '2026-09-10', ate: '2026-09-10' })).toBe(true);
    expect(casaComBusca(pix, { termo: '', de: '2026-09-11' })).toBe(false);
    expect(casaComBusca(pix, { termo: 'coremma', ate: '2026-09-01' })).toBe(false);
  });
  it('busca vazia deixa tudo passar', () => {
    expect(casaComBusca(pix, { termo: '  ' })).toBe(true);
    expect(buscaAtiva({ termo: ' ' })).toBe(false);
    expect(buscaAtiva({ termo: '', de: '2026-09-01' })).toBe(true);
  });
});
