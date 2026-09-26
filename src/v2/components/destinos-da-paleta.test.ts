// Toda entrada da busca Ctrl+K leva a uma tela de verdade — inclusive os apelidos com os
// nomes antigos das abas do Financeiro (26/09/2026), que precisam chegar ao lugar NOVO.
import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { matchPath } from 'react-router-dom';
import { NAV } from './destinos-da-paleta';
import { resolverFinanceiro } from '@/v2/pages/financeiro/rotas';
import { resolverCentral } from '@/v2/pages/relatorios/secoes';

const app = fs.readFileSync(path.join(process.cwd(), 'src/App.tsx'), 'utf8');
const rotasDoApp = [...app.matchAll(/<Route path="([^"]+)"/g)].map((m) => m[1]).filter((p) => p !== '*' && p !== '/*');
const todos = NAV.flatMap((g) => g.items.map((i) => ({ ...i, grupo: g.group })));

describe('destinos da busca Ctrl+K', () => {
  it('leu as rotas do App', () => {
    expect(rotasDoApp).toContain('/v2/financial/:secao?/:aba?');
  });

  it.each(todos.map((i) => [`${i.grupo} › ${i.label}`, i.to]))('%s (%s) é uma rota do App', (_nome, destino) => {
    const semQuery = destino.split('?')[0];
    const casou = rotasDoApp.some((padrao) => matchPath({ path: padrao, end: true }, semQuery));
    expect(casou, `${destino} não casa com nenhuma rota do App`).toBe(true);
  });

  it('destinos do Financeiro e da Central abrem uma tela, não um redirecionamento', () => {
    for (const { to } of todos) {
      const partes = to.split('?')[0].split('/');
      if (to.startsWith('/v2/financial')) {
        expect(resolverFinanceiro(partes[3], partes[4], null).tipo, to).toBe('comodo');
      }
      if (to.startsWith('/v2/reports')) {
        expect(resolverCentral(partes[3], null).tipo, to).toBe('secao');
      }
    }
  });

  it('os nomes antigos continuam achando o lugar novo', () => {
    const antigos = NAV.find((g) => g.group === 'Nomes antigos')!.items;
    const destinoDe = (nome: string) => antigos.find((i) => i.label === nome)?.to;
    expect(destinoDe('DRE')).toBe('/v2/reports/dre');
    expect(destinoDe('Aging')).toBe('/v2/reports/aging');
    expect(destinoDe('Programação')).toBe('/v2/reports/fluxo');
    expect(destinoDe('Gerenciais')).toBe('/v2/reports/operacao');
    expect(destinoDe('Cartões')).toBe('/v2/financial/inbox/cartao');
    expect(destinoDe('Regras')).toBe('/v2/financial/inbox/regras');
    expect(destinoDe('Fechamento')).toBe('/v2/financial/reconciliation/fechar');
    expect(destinoDe('Saúde do cadastro')).toBe('/v2/suppliers/saude');
    expect(destinoDe('Cobranças')).toBe('/v2/receivables/cobrancas');
    expect(destinoDe('Comissões')).toBe('/v2/financial/payables/comissoes');
    // E cada apelido diz onde a coisa mora agora.
    for (const a of antigos) expect(a.onde, a.label).toBeTruthy();
  });

  it('nenhuma entrada aponta para as rotas que viraram aba (/v2/collections, /v2/commissions)', () => {
    for (const { to } of todos) {
      expect(to).not.toBe('/v2/collections');
      expect(to).not.toBe('/v2/commissions');
    }
  });
});
