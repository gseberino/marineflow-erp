import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Nenhum hook depois de um `return` condicional.
 *
 * ═══ POR QUE ESTE TESTE EXISTE ═══
 *
 * A tela de orçamento e de OS parou de abrir com "Minified React error #310 —
 * Rendered more hooks than during the previous render". Eu tinha movido um
 * `useCallback` e um `useEffect` para depois de
 *
 *     if (isLoading) return <Skeleton/>;
 *
 * Enquanto carrega, o componente sai antes e chama dois hooks a MENOS. Quando
 * termina, chama os dois. O React conta os hooks por posição e derruba a tela
 * inteira quando o número muda.
 *
 * O `tsc` não vê isso — é regra do React, não do TypeScript. O build também
 * passa. Só aparece no navegador, e minificado, com um número no lugar da
 * mensagem.
 *
 * Foi a SEGUNDA vez que mexer nesse arquivo derrubou a tela por ordem de
 * declaração: da primeira o tsc pegou (TDZ, variável usada antes de declarar);
 * desta não havia quem pegasse. Este teste é esse "quem".
 */

const RAIZ = join(process.cwd(), 'src');
const HOOKS = /\b(useState|useEffect|useCallback|useMemo|useRef|useReducer|useContext|useLayoutEffect|useQuery|useMutation|useInfiniteQuery)\s*\(/;
/** `return` de saída antecipada no corpo do componente (2 espaços de indentação). */
const EARLY_RETURN = /^ {2}(if\s*\(.+\)\s*)?return[\s(<]/;

function arquivosReact(dir: string, achados: string[] = []): string[] {
  for (const nome of readdirSync(dir)) {
    const caminho = join(dir, nome);
    if (statSync(caminho).isDirectory()) {
      if (nome !== 'node_modules') arquivosReact(caminho, achados);
    } else if (/\.tsx$/.test(nome) && !/\.test\.tsx$/.test(nome)) {
      achados.push(caminho);
    }
  }
  return achados;
}

/**
 * Procura hook chamado depois de um return de primeiro nível.
 *
 * Heurística por indentação: `  return` e `  if (x) return` são saída do
 * componente; hooks legítimos também vivem em dois espaços. Fecha o escopo
 * quando encontra `}` no primeiro nível, para não confundir o corpo de uma
 * função interna com o do componente.
 */
function hooksDepoisDeReturn(src: string): number[] {
  const linhas = src.split('\n');
  const suspeitas: number[] = [];
  let viuReturn = false;

  for (let i = 0; i < linhas.length; i++) {
    const l = linhas[i];
    // Fim do componente (ou de um bloco de topo): zera a marca.
    if (/^}/.test(l)) { viuReturn = false; continue; }
    if (EARLY_RETURN.test(l)) { viuReturn = true; continue; }
    if (viuReturn && /^ {2}(const|let)\s+\w+\s*=\s*/.test(l) && HOOKS.test(l)) {
      suspeitas.push(i + 1);
    }
    if (viuReturn && /^ {2}(useEffect|useLayoutEffect|useMemo|useCallback)\s*\(/.test(l)) {
      suspeitas.push(i + 1);
    }
  }
  return suspeitas;
}

describe('regra dos hooks: nenhum depois de return condicional', () => {
  it('detecta o padrão que derrubou a tela', () => {
    const exemplo = [
      'export function X() {',
      '  const [a, setA] = useState(0);',
      '  if (isLoading) return <Skeleton/>;',
      '  const b = useCallback(() => {}, []);',
      '}',
    ].join('\n');
    expect(hooksDepoisDeReturn(exemplo)).toEqual([4]);
  });

  it('não acusa hook declarado antes do return', () => {
    const ok = [
      'export function X() {',
      '  const b = useCallback(() => {}, []);',
      '  if (isLoading) return <Skeleton/>;',
      '  return <div/>;',
      '}',
    ].join('\n');
    expect(hooksDepoisDeReturn(ok)).toEqual([]);
  });

  it('nenhum componente do projeto quebra a regra', () => {
    const problemas: string[] = [];
    for (const arquivo of arquivosReact(RAIZ)) {
      const linhas = hooksDepoisDeReturn(readFileSync(arquivo, 'utf8'));
      for (const n of linhas) {
        problemas.push(`${arquivo.replace(process.cwd(), '')}:${n}`);
      }
    }
    expect(
      problemas,
      'Hook chamado depois de um return condicional — o número de hooks muda ' +
      'entre renders e o React derruba a tela (erro #310):\n' + problemas.join('\n'),
    ).toEqual([]);
  });
});
