// O "Vai entrar em" do Caixa na tela: a mesma ordem que o assistente segue.
import { describe, it, expect } from 'vitest';
import { destinoDoGasto } from './destino-do-gasto';

describe('destinoDoGasto', () => {
  it('categoria escolhida vence tudo', () => {
    expect(destinoDoGasto('Peças e materiais', null, 'almoço', 50, [])).toEqual({ categoria: 'Peças e materiais', porque: null });
  });
  it('sem escolha, a padrão de quem recebeu', () => {
    expect(destinoDoGasto('', { nome: 'Roberto', categoria: 'Serviços de terceiros' }, 'almoço', 50, []).categoria).toBe('Serviços de terceiros');
  });
  it('sem padrão, o texto: almoço vira Alimentação de campo', () => {
    const d = destinoDoGasto('', null, 'Almoço meu e do Roberto', 100, []);
    expect(d.categoria).toBe('Alimentação de campo');
    expect(d.porque).toMatch(/pelo texto/);
  });
  it('sem pista, Outras despesas — dizendo que não reconheceu', () => {
    const d = destinoDoGasto('', null, 'coisa diversa', 10, []);
    expect(d.categoria).toBe('Outras despesas');
    expect(d.porque).toMatch(/não reconheci/);
  });
});
