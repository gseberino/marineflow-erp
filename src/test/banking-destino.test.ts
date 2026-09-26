// "Para onde foi?" do serviço de terceiro — decisão do dono de 26/09/2026: "tem que ter qual
// serviço e para que foi direcionado". A tela e o servidor usam as mesmas funções.
import { describe, it, expect } from 'vitest';
import {
  SERVICO_DE_CLIENTE, SERVICO_DA_EMPRESA, precisaDeDestino, destinoEfetivo, categoriaDoDestino,
  faltaNoDestino, fraseDaFalta, aplicarDestino,
} from '../../supabase/functions/_shared/banking/destino';

describe('o que a aprovação faz com a resposta (finance-review/aprovar)', () => {
  const k = 'create_payable';

  it('para a HBR: troca para a categoria da empresa', () => {
    expect(aplicarDestino(k, SERVICO_DE_CLIENTE, { destino: 'empresa', costCenterId: 'cc', notes: 'pintura da sede' }, undefined))
      .toEqual({ categoria: SERVICO_DA_EMPRESA });
  });

  it('para um cliente com OS: fica no custo do serviço', () => {
    expect(aplicarDestino(k, SERVICO_DE_CLIENTE, { destino: 'cliente', serviceOrderId: 'os60', notes: 'solda' }, 'os60'))
      .toEqual({ categoria: SERVICO_DE_CLIENTE });
  });

  it('a OS anotada pelo WhatsApp vale como resposta (sem nada na tela)', () => {
    expect(aplicarDestino(k, SERVICO_DE_CLIENTE, { notes: 'mão de obra' }, 'os-anotada'))
      .toEqual({ categoria: SERVICO_DE_CLIENTE });
  });

  it('HBR e OS de cliente ao mesmo tempo é contradição: recusa', () => {
    const r = aplicarDestino(k, SERVICO_DE_CLIENTE, { destino: 'empresa', costCenterId: 'cc', notes: 'pintura', serviceOrderId: 'os60' }, 'os60');
    expect('erro' in r && r.erro).toMatch(/escolha um dos dois/);
  });

  it('"Para a HBR" com a OS anotada desfeita na tela ("não é") passa', () => {
    expect(aplicarDestino(k, SERVICO_DE_CLIENTE, { destino: 'empresa', costCenterId: 'cc', notes: 'pintura', serviceOrderId: null }, null))
      .toEqual({ categoria: SERVICO_DA_EMPRESA });
  });

  it('sem resposta: recusa com a frase do que falta', () => {
    const r = aplicarDestino(k, SERVICO_DE_CLIENTE, {}, undefined);
    expect('erro' in r && r.erro).toBe('Serviço de terceiro: diga para onde foi (serviço de um cliente ou para a HBR) e o que foi feito');
  });

  it('outras categorias passam como estão', () => {
    expect(aplicarDestino(k, 'Peças e materiais', {}, undefined)).toEqual({ categoria: 'Peças e materiais' });
    expect(aplicarDestino('create_receivable', 'Serviços prestados', {}, undefined)).toEqual({ categoria: 'Serviços prestados' });
  });
});

describe('quem pergunta para onde foi', () => {
  it('só saída de serviço de terceiro (de cliente ou da empresa)', () => {
    expect(precisaDeDestino('create_payable', SERVICO_DE_CLIENTE)).toBe(true);
    expect(precisaDeDestino('create_payable', SERVICO_DA_EMPRESA)).toBe(true);
    expect(precisaDeDestino('create_payable', 'Peças e materiais')).toBe(false);
    expect(precisaDeDestino('create_receivable', SERVICO_DE_CLIENTE)).toBe(false);
    expect(precisaDeDestino('internal_transfer', SERVICO_DE_CLIENTE)).toBe(false);
    expect(precisaDeDestino('create_payable', null)).toBe(false);
  });
});

describe('o destino que vale', () => {
  it('o dito vence; a categoria da empresa já diz; uma OS respondida diz cliente', () => {
    expect(destinoEfetivo(SERVICO_DE_CLIENTE, { destino: 'empresa' })).toBe('empresa');
    expect(destinoEfetivo(SERVICO_DA_EMPRESA, {})).toBe('empresa');
    expect(destinoEfetivo(SERVICO_DE_CLIENTE, { serviceOrderId: 'os1' })).toBe('cliente');
    expect(destinoEfetivo(SERVICO_DE_CLIENTE, {}, 'os-anotada')).toBe('cliente');
    // "Não é desta OS" (null) não diz para onde foi.
    expect(destinoEfetivo(SERVICO_DE_CLIENTE, { serviceOrderId: null })).toBeNull();
    expect(destinoEfetivo(SERVICO_DE_CLIENTE, {})).toBeNull();
  });

  it('serviço para a HBR vira despesa da empresa, e o contrário volta', () => {
    expect(categoriaDoDestino(SERVICO_DE_CLIENTE, 'empresa')).toBe(SERVICO_DA_EMPRESA);
    expect(categoriaDoDestino(SERVICO_DA_EMPRESA, 'cliente')).toBe(SERVICO_DE_CLIENTE);
    expect(categoriaDoDestino(SERVICO_DE_CLIENTE, 'cliente')).toBe(SERVICO_DE_CLIENTE);
    expect(categoriaDoDestino('Peças e materiais', 'empresa')).toBe('Peças e materiais');
    expect(categoriaDoDestino(SERVICO_DE_CLIENTE, null)).toBe(SERVICO_DE_CLIENTE);
  });
});

describe('o que falta para aprovar', () => {
  const k = 'create_payable';

  it('nada respondido: para onde foi e o que foi feito', () => {
    expect(faltaNoDestino(k, SERVICO_DE_CLIENTE, {})).toEqual(['destino', 'o_que_foi_feito']);
  });

  it('cliente pede a OS (ou "sem OS"); empresa pede o centro de custo', () => {
    expect(faltaNoDestino(k, SERVICO_DE_CLIENTE, { destino: 'cliente', notes: 'solda no casco' })).toEqual(['os']);
    expect(faltaNoDestino(k, SERVICO_DE_CLIENTE, { destino: 'cliente', serviceOrderId: null, notes: 'solda no casco' })).toEqual([]);
    expect(faltaNoDestino(k, SERVICO_DE_CLIENTE, { destino: 'cliente', serviceOrderId: 'os60', notes: 'solda no casco' })).toEqual([]);
    expect(faltaNoDestino(k, SERVICO_DE_CLIENTE, { destino: 'empresa', notes: 'pintura da sede' })).toEqual(['centro']);
    expect(faltaNoDestino(k, SERVICO_DE_CLIENTE, { destino: 'empresa', costCenterId: 'cc', notes: 'pintura da sede' })).toEqual([]);
  });

  it('a OS anotada pelo WhatsApp já responde o destino e a OS', () => {
    expect(faltaNoDestino(k, SERVICO_DE_CLIENTE, { notes: 'mão de obra do eletricista' }, 'os60')).toEqual([]);
  });

  it('"o que foi feito" em branco ou curto demais não vale', () => {
    expect(faltaNoDestino(k, SERVICO_DE_CLIENTE, { destino: 'cliente', serviceOrderId: 'os', notes: '  ' })).toEqual(['o_que_foi_feito']);
    expect(faltaNoDestino(k, SERVICO_DE_CLIENTE, { destino: 'cliente', serviceOrderId: 'os', notes: 'ok' })).toEqual(['o_que_foi_feito']);
  });

  it('outras categorias e entradas não perguntam nada', () => {
    expect(faltaNoDestino(k, 'Peças e materiais', {})).toEqual([]);
    expect(faltaNoDestino('create_receivable', SERVICO_DE_CLIENTE, {})).toEqual([]);
  });

  it('a frase lista o que falta em português', () => {
    expect(fraseDaFalta(['destino', 'o_que_foi_feito'])).toBe(
      'Serviço de terceiro: diga para onde foi (serviço de um cliente ou para a HBR) e o que foi feito',
    );
    expect(fraseDaFalta(['centro'])).toBe('Serviço de terceiro: diga o centro de custo');
  });
});
