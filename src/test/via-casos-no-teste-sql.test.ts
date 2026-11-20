// Guarda de paridade da via v2, F2 (E12 e E17 do plano): a regra de COBRANÇA e o NÚMERO do serviço moram em duas linguagens
// (TypeScript na via, na tela e nas ferramentas; SQL nas funções via_instrucao_* e no canal automático). Uma lista de casos só,
// rodada nas duas: este teste confere que cada caso do TypeScript está no teste SQL (supabase/tests/via_instrucao_rascunhos.sql)
// com a MESMA resposta — o título curto e a cobrança que o TypeScript calcula, e o número que a ordem canônica dá. Caso novo na
// lista sem a linha no teste SQL = vermelho aqui.
//
// E a regra "só o aprovado sai no papel": o caminho da via nunca lê a tabela das sugestões.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { CASOS_DE_COBRANCA } from '../../supabase/functions/_shared/pdf/via-cobranca-casos';
import { CASOS_DE_ORDEM } from '../../supabase/functions/_shared/linhas-da-os-casos';
import { ehCobranca, tituloDoServico } from '../../supabase/functions/_shared/pdf/via-texto';
import { numerarLinhas, ordenarLinhas } from '../../supabase/functions/_shared/linhas-da-os';

const raiz = resolve(__dirname, '../..');
const testeSql = readFileSync(resolve(raiz, 'supabase/tests/via_instrucao_rascunhos.sql'), 'utf8');

describe('casos da via no teste SQL da F2', () => {
  it.each(CASOS_DE_COBRANCA.map((c) => [c.caso, c] as const))('cobrança: %s', (_caso, c) => {
    // a resposta da lista é a do TypeScript (o Deno já prova isto em via-texto_test.ts; aqui, que a linha SQL leva o mesmo)
    expect(ehCobranca(c.nome)).toBe(c.cobranca);
    const linha = `($c$${c.caso}$c$, $n$${c.nome}$n$, $t$${tituloDoServico(c.nome)}$t$, ${c.cobranca})`;
    expect(testeSql).toContain(linha);
  });

  it.each(CASOS_DE_ORDEM.map((c, i) => [c.caso, c, i + 1] as const))('ordem: %s', (_caso, c, n) => {
    const numeradas = numerarLinhas(ordenarLinhas(c.linhas));
    expect(numeradas.map((l) => l.id)).toEqual(c.ordem);
    for (const l of numeradas) {
      expect(testeSql).toContain(`(${n}, '${l.id}', '${l.created_at}', ${l.numero})`);
    }
  });

  it('o teste SQL não tem caso a mais do que as listas (cobrança e ordem)', () => {
    const cobrancas = testeSql.match(/^\s+\(\$c\$/gm) ?? [];
    expect(cobrancas).toHaveLength(CASOS_DE_COBRANCA.length);
    const ordens = testeSql.match(/^\s+\(\d+, '[0-9a-f-]{36}', '[^']+', \d+\)/gm) ?? [];
    expect(ordens).toHaveLength(CASOS_DE_ORDEM.reduce((s, c) => s + c.linhas.length, 0));
  });
});

describe('só o aprovado sai no papel: a via não lê as sugestões', () => {
  const caminhoDaVia = [
    'supabase/functions/_shared/pdf/via-do-tecnico.ts',
    'supabase/functions/_shared/pdf/via-do-tecnico-dados.ts',
    'supabase/functions/_shared/pdf/via-do-tecnico-envio.ts',
    'supabase/functions/task-automations/via-da-agenda.ts',
    'src/hooks/use-via-do-tecnico.ts',
    'src/lib/route-sheet.ts',
  ];
  it.each(caminhoDaVia)('%s não cita via_instrucao_rascunhos', (arquivo) => {
    expect(readFileSync(resolve(raiz, arquivo), 'utf8')).not.toMatch(/via_instrucao/);
  });
});
