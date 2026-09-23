// O desenho do menu foi uma DECISÃO do dono (23/09/2026), não um acidente de arquivo.
//
// O Financeiro tinha 12 itens no menu e 13 abas dentro de /v2/financial, com cinco
// repetidos nos dois lugares e sete abas que não existiam no menu — dois sistemas de
// navegação concorrentes para o mesmo material, nenhum dos dois completo.
//
// A regra que ficou: MENU é destino (o que vou fazer agora), ABA é recorte do mesmo
// material (de que ângulo eu olho). Nada nos dois. Estes testes guardam essa regra, que
// se desfaz sozinha assim que alguém "só adicionar um item".
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
      'Contas a Receber', 'Contas a Pagar', 'Cobranças',
    ]);
  });

  it('Fiscal é grupo próprio: documento legal não é dinheiro', () => {
    expect(grupo('Fiscal')!.itens).toContain('Notas Fiscais');
    // NF-e e NFS-e estão na mesma lista desde 23/09; duas entradas seriam duas casas.
    expect(grupo('Fiscal')!.itens).toHaveLength(1);
  });

  it('DRE e Aging saíram de aba escondida para Relatórios', () => {
    const rel = grupo('Relatórios')!;
    expect(rel.itens).toContain('DRE');
    expect(rel.itens.some((i) => i.startsWith('Aging'))).toBe(true);
  });

  it('cadastro de pessoa e de banco vive em Cadastros, junto dos outros', () => {
    const cad = grupo('Cadastros')!;
    expect(cad.itens).toContain('Favorecidos');
    expect(cad.itens).toContain('Contas Bancárias');
  });

  it('o que virou aba não fica também no menu — era a duplicação da queixa', () => {
    const todos = grupos.flatMap((g) => g.itens);
    for (const repetido of ['Regras da IA', 'Comissões', 'Notas de Serviço (NFS-e)']) {
      expect(todos, `"${repetido}" voltou ao menu`).not.toContain(repetido);
    }
  });

  it('nenhum rótulo aparece em dois grupos diferentes', () => {
    const todos = grupos.flatMap((g) => g.itens);
    const duplicados = todos.filter((r, i) => todos.indexOf(r) !== i);
    expect(duplicados).toEqual([]);
  });
});
