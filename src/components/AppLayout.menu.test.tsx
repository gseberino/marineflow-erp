// O desenho do menu foi uma DECISÃO do dono (23/09/2026), não um acidente de arquivo.
//
// O Financeiro tinha 12 itens no menu e 13 abas dentro de /v2/financial, com cinco
// repetidos nos dois lugares e sete abas que não existiam no menu — dois sistemas de
// navegação concorrentes para o mesmo material, nenhum dos dois completo.
//
// A regra que ficou: MENU é destino (o que vou fazer agora), ABA é recorte do mesmo
// material (de que ângulo eu olho). Nada nos dois. Estes testes guardam essa regra, que
// se desfaz sozinha assim que alguém "só adicionar um item".
//
// 26/09/2026: a barra de 14 abas do Financeiro acabou — cada item do menu abre só o seu
// assunto, e os relatórios viraram uma porta só (Central de relatórios).
import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';

const fonte = fs.readFileSync(
  path.join(process.cwd(), 'src/components/AppLayout.tsx'),
  'utf8',
);

/** Os grupos do menu e os rótulos de cada um, lidos do próprio arquivo. */
function lerGrupos(): Array<{ label: string; itens: string[] }> {
  const re = /id: '([a-z-]+)',\s*\n\s*label: '([^']+)'/g;
  const achados: Array<{ label: string; pos: number }> = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(fonte))) achados.push({ label: m[2], pos: m.index });

  return achados.map((g, i) => {
    const fim = i + 1 < achados.length ? achados[i + 1].pos : fonte.length;
    const trecho = fonte.slice(g.pos, fim);
    const itens = [...trecho.matchAll(/\{ label: '([^']+)'/g)].map((x) => x[1]);
    return { label: g.label, itens };
  });
}

const grupos = lerGrupos();
const grupo = (nome: string) => grupos.find((g) => g.label === nome);

describe('menu lateral', () => {
  it('nenhum grupo vira uma lista longa demais para ser lida', () => {
    // Oito é o limite prático de uma lista que se varre de relance. Acima disso o olho
    // desiste e a pessoa usa a busca — que é o sintoma que abriu esta reorganização.
    for (const g of grupos) {
      expect(g.itens.length, `grupo "${g.label}" tem ${g.itens.length} itens`).toBeLessThanOrEqual(8);
    }
  });

  it('Financeiro guarda só o trabalho de dinheiro do dia a dia', () => {
    const fin = grupo('Financeiro')!;
    expect(fin.itens).toEqual([
      'Visão Geral', 'Extrato', 'Conciliação',
      // Despesas (26/09/2026): o que JÁ saiu e em que categoria entrou; Contas a Pagar é o que se deve.
      // Cobranças saiu em 26/09/2026: virou aba de Contas a Receber (é a mesma conversa).
      'Contas a Receber', 'Contas a Pagar', 'Despesas',
      // Diárias (28/09/2026): os dias dos freelancers e o saldo com cada um.
      'Diárias',
    ]);
  });

  it('Fiscal é grupo próprio: documento legal não é dinheiro', () => {
    expect(grupo('Fiscal')!.itens).toContain('Notas Fiscais');
    // NF-e e NFS-e estão na mesma lista desde 23/09; duas entradas seriam duas casas.
    expect(grupo('Fiscal')!.itens).toHaveLength(1);
  });

  it('Relatórios é uma porta só: a Central de relatórios', () => {
    // Pedido do dono (26/09/2026): "tudo que é demonstrativo ou relatório deveria estar em uma
    // só aba". DRE, Aging, Gerenciais e Programação vivem DENTRO da Central, como abas.
    expect(grupo('Relatórios')!.itens).toEqual(['Central de relatórios']);
  });

  it('cadastro de pessoa e de banco vive em Cadastros, junto dos outros', () => {
    const cad = grupo('Cadastros')!;
    expect(cad.itens).toContain('Favorecidos');
    expect(cad.itens).toContain('Contas Bancárias');
  });

  it('o que virou aba não fica também no menu — era a duplicação da queixa', () => {
    const todos = grupos.flatMap((g) => g.itens);
    for (const repetido of [
      'Regras da IA', 'Regras', 'Comissões', 'Reembolsos', 'Notas de Serviço (NFS-e)',
      // 26/09/2026: abas das telas novas — Cobranças (Contas a Receber), Cartões e Regras
      // (Extrato), Fechamento (Conciliação), Saúde do cadastro (Fornecedores) e os relatórios
      // (Central de relatórios).
      'Cobranças', 'Cartões', 'Fechamento', 'Saúde do cadastro',
      'DRE', 'Aging', 'Aging (idade das contas)', 'Gerenciais', 'Programação', 'Fluxo de caixa',
    ]) {
      expect(todos, `"${repetido}" voltou ao menu`).not.toContain(repetido);
    }
  });

  it('cada item do Financeiro é uma tela de assunto único, sem ?tab=', () => {
    const trecho = fonte.slice(fonte.indexOf("id: 'financeiro'"), fonte.indexOf("id: 'fiscal'"));
    const caminhos = [...trecho.matchAll(/path: '([^']+)'/g)].map((m) => m[1]);
    expect(caminhos.length).toBeGreaterThan(0);
    for (const c of caminhos) expect(c, c).not.toContain('?');
  });

  it('nenhum rótulo aparece em dois grupos diferentes', () => {
    const todos = grupos.flatMap((g) => g.itens);
    const duplicados = todos.filter((r, i) => todos.indexOf(r) !== i);
    expect(duplicados).toEqual([]);
  });
});
