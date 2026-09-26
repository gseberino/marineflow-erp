// O mapa de rotas do Financeiro: cada link antigo tem um lugar novo, e cada destino do menu é
// um cômodo que a tela sabe abrir.
import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import {
  ANTIGAS, COMODOS, resolverFinanceiro, rotaDoComodo, paraQueServeDe, type Comodo,
} from './rotas';

describe('resolverFinanceiro', () => {
  it('a raiz é a Visão Geral', () => {
    expect(resolverFinanceiro(undefined, undefined, null)).toEqual({ tipo: 'comodo', comodo: 'visao', aba: null });
  });

  it('cada cômodo abre na aba padrão, e cada aba conhecida abre a si mesma', () => {
    for (const def of Object.values(COMODOS)) {
      if (!def.secao) continue;
      const padrao = resolverFinanceiro(def.secao, undefined, null);
      expect(padrao).toEqual({ tipo: 'comodo', comodo: def.comodo, aba: def.abas[0]?.aba ?? null });
      for (const a of def.abas) {
        expect(resolverFinanceiro(def.secao, a.aba, null)).toEqual({ tipo: 'comodo', comodo: def.comodo, aba: a.aba });
      }
    }
  });

  it('aba desconhecida volta para a raiz do cômodo; cômodo sem abas não aceita aba', () => {
    expect(resolverFinanceiro('inbox', 'xyz', null)).toEqual({ tipo: 'redirecionar', para: '/v2/financial/inbox' });
    expect(resolverFinanceiro('despesas', 'xyz', null)).toEqual({ tipo: 'redirecionar', para: '/v2/financial/despesas' });
  });

  it('seção desconhecida leva à Visão Geral, nunca a uma tela em branco', () => {
    expect(resolverFinanceiro('nao-existe', undefined, null)).toEqual({ tipo: 'redirecionar', para: '/v2/financial' });
    expect(resolverFinanceiro(undefined, undefined, 'nao-existe')).toEqual({ tipo: 'redirecionar', para: '/v2/financial' });
  });

  it('cada seção antiga leva ao lugar novo — por rota e por ?tab=', () => {
    for (const [antiga, destino] of Object.entries(ANTIGAS)) {
      expect(resolverFinanceiro(antiga, undefined, null), antiga).toEqual({ tipo: 'redirecionar', para: destino });
      expect(resolverFinanceiro(undefined, undefined, antiga), `?tab=${antiga}`).toEqual({ tipo: 'redirecionar', para: destino });
    }
  });

  it('?tab= de um cômodo que existe vira a rota dele', () => {
    expect(resolverFinanceiro(undefined, undefined, 'inbox')).toEqual({ tipo: 'redirecionar', para: '/v2/financial/inbox' });
    expect(resolverFinanceiro(undefined, undefined, 'banks')).toEqual({ tipo: 'redirecionar', para: '/v2/financial/banks' });
  });

  it('o mapa pedido pelo dono: DRE, Aging e Programação na Central; Cartões e Regras no Extrato…', () => {
    expect(ANTIGAS.dre).toBe('/v2/reports/dre');
    expect(ANTIGAS.aging).toBe('/v2/reports/aging');
    expect(ANTIGAS.forecast).toBe('/v2/reports/fluxo');
    expect(ANTIGAS.cartoes).toBe('/v2/financial/inbox/cartao');
    expect(ANTIGAS.rules).toBe('/v2/financial/inbox/regras');
    expect(ANTIGAS.ignoradas).toBe('/v2/financial/inbox/fora');
    expect(ANTIGAS.fechamento).toBe('/v2/financial/reconciliation/fechar');
    expect(ANTIGAS.comissoes).toBe('/v2/financial/payables/comissoes');
  });

  it('todo destino antigo dentro do Financeiro abre um cômodo de verdade', () => {
    for (const destino of Object.values(ANTIGAS)) {
      if (!destino.startsWith('/v2/financial')) continue;
      const [, , , secao, aba] = destino.split('/');
      const r = resolverFinanceiro(secao, aba, null);
      expect(r.tipo, destino).toBe('comodo');
    }
  });
});

describe('rotaDoComodo', () => {
  it('a aba padrão não aparece no endereço', () => {
    expect(rotaDoComodo('visao')).toBe('/v2/financial');
    expect(rotaDoComodo('extrato', 'revisar')).toBe('/v2/financial/inbox');
    expect(rotaDoComodo('extrato', 'cartao')).toBe('/v2/financial/inbox/cartao');
    expect(rotaDoComodo('pagar', 'reembolsos')).toBe('/v2/financial/payables/reembolsos');
    expect(rotaDoComodo('despesas', 'qualquer')).toBe('/v2/financial/despesas');
  });
});

describe('para que serve', () => {
  it('toda tela e toda aba têm a sua frase', () => {
    for (const def of Object.values(COMODOS)) {
      expect(def.paraQueServe.length, def.nome).toBeGreaterThan(20);
      for (const a of def.abas) expect(paraQueServeDe(def.comodo as Comodo, a.aba).length, a.rotulo).toBeGreaterThan(20);
    }
  });

  it('no máximo um nível de abas, com poucas abas por tela', () => {
    for (const def of Object.values(COMODOS)) expect(def.abas.length, def.nome).toBeLessThanOrEqual(5);
  });
});

describe('o menu aponta para cômodos que a tela sabe abrir', () => {
  // Lido do próprio AppLayout: um item novo de /v2/financial que a tela não conhece cairia
  // na Visão Geral sem ninguém perceber.
  const fonte = fs.readFileSync(path.join(process.cwd(), 'src/components/AppLayout.tsx'), 'utf8');
  const caminhos = [...fonte.matchAll(/path: '(\/v2\/financial[^']*)'/g)].map((m) => m[1]);

  it('achou os itens do Financeiro no menu', () => {
    expect(caminhos).toContain('/v2/financial/inbox');
  });

  it.each(caminhos)('%s é um cômodo', (caminho) => {
    const [, , , secao, aba] = caminho.split('/');
    expect(resolverFinanceiro(secao, aba, null).tipo).toBe('comodo');
  });
});
