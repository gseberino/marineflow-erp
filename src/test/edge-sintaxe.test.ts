// O código das edge functions precisa ao menos PARSEAR.
//
// Buraco real, fechado aqui: em 24/09/2026 uma crase dentro do prompt do agente
// (`contem`, escrito com acento grave num arquivo que é um template literal gigante)
// fechou a string no meio e quebrou o módulo. Isso passou por TODOS os portões:
//
//   tsc -b        → não olha supabase/functions (o tsconfig do projeto não os inclui)
//   npm test      → vitest não importa esses arquivos
//   npm run build → idem
//   npm run test:edge → roda com `--no-check`, e o arquivo não é importado por teste algum
//
// Só apareceu no `supabase functions deploy`, depois do push — ou seja, no último lugar
// possível, e num comando que ninguém roda em CI.
//
// Por que PARSE e não `deno check`: checagem de tipos exige resolver as dependências npm
// de cada função (a fiscal-email usa nodemailer), o que amarra o portão à rede e ao
// node_modules. Parse não resolve import nenhum, roda em milissegundos e pega a classe de
// erro que de fato escapou: string não fechada, parêntese faltando, chave sobrando.
import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';

const RAIZ = process.cwd();
const PASTA = path.join(RAIZ, 'supabase', 'functions');

function arquivosTs(dir: string): string[] {
  const saida: string[] = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) saida.push(...arquivosTs(p));
    else if (/\.tsx?$/.test(e.name)) saida.push(p);
  }
  return saida;
}

/** Erros de sintaxe do arquivo. Sem resolver import, sem checar tipo. */
export function errosDeSintaxe(codigo: string, nome: string): string[] {
  const saida = ts.transpileModule(codigo, {
    reportDiagnostics: true,
    fileName: nome,
    compilerOptions: { target: ts.ScriptTarget.ESNext, module: ts.ModuleKind.ESNext, isolatedModules: true },
  });
  return (saida.diagnostics ?? [])
    // `category` Error basta: transpileModule só emite diagnóstico de sintaxe/emissão,
    // e é justamente esse o alvo.
    .filter((d) => d.category === ts.DiagnosticCategory.Error)
    .map((d) => {
      const msg = ts.flattenDiagnosticMessageText(d.messageText, ' ');
      if (d.file && typeof d.start === 'number') {
        const { line } = d.file.getLineAndCharacterOfPosition(d.start);
        return `linha ${line + 1}: ${msg}`;
      }
      return msg;
    });
}

describe('edge functions parseiam', () => {
  // Timeout explícito: a varredura transpila todos os arquivos de supabase/functions e passa dos
  // 5 s padrão com a máquina ocupada (suíte completa em paralelo) — falhava por tempo, não por
  // sintaxe.
  it('nenhum arquivo de supabase/functions tem erro de sintaxe', { timeout: 60_000 }, () => {
    expect(fs.existsSync(PASTA), 'a pasta supabase/functions sumiu — a varredura ficaria cega').toBe(true);
    const arquivos = arquivosTs(PASTA);
    expect(arquivos.length, 'não achei arquivo nenhum para checar').toBeGreaterThan(50);

    const quebrados: string[] = [];
    for (const arquivo of arquivos) {
      const erros = errosDeSintaxe(fs.readFileSync(arquivo, 'utf8'), path.basename(arquivo));
      if (erros.length > 0) {
        quebrados.push(`  ${path.relative(RAIZ, arquivo)}\n    ${erros.slice(0, 3).join('\n    ')}`);
      }
    }

    expect(quebrados, `Edge function que não parseia (o deploy vai falhar):\n${quebrados.join('\n')}\n\n` +
      'Erro comum neste repo: acento grave dentro de prompt.ts, que é um template literal\n' +
      'inteiro — a crase fecha a string no meio e derruba o módulo.').toEqual([]);
    // Prazo próprio: são ~230 arquivos e ~50 mil linhas transpiladas uma a uma. Sozinho o
    // teste leva ~5 s — o limite padrão do vitest —, e na suíte completa, com os outros
    // arquivos rodando em paralelo, estourava o prazo e ficava vermelho sem erro de sintaxe
    // nenhum (duas rodadas seguidas em 26/09/2026). Timeout não é falha de parse.
  }, 60_000);

  // Uma varredura que não sabe acusar nada é um teste que sempre passa.
  it('a varredura sabe reconhecer código quebrado', () => {
    const crase = String.fromCharCode(96);
    const quebrado = `export const p = ${crase}texto com ${crase}crase${crase} no meio${crase};`;
    expect(errosDeSintaxe(quebrado, 'falso.ts').length).toBeGreaterThan(0);
    expect(errosDeSintaxe(`export const p = "ok";`, 'bom.ts')).toEqual([]);
  });
});
