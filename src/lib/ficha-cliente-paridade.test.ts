// Paridade de faltasParaNota (src/lib/ficha-cliente.ts) com _orcamento_faltas_para_nota (Retorno F5, P6.1 e P6.2 nº 9).
//
// O aceite por texto pede CPF ou CNPJ e endereço só quando falta algo para a nota, e o banco decide isso sozinho
// (_orcamento_faltas_para_nota, migration 20270112100500). A regra tem de ser a mesma da ficha do cliente na OS, que espelha
// os validadores do servidor fiscal. Os casos moram no teste SQL (supabase/tests/retorno_f5_aceite.sql), num JSON entre
// $faltas$ … $faltas$: o banco roda os mesmos casos e confere o mesmo esperado, linha a linha; aqui, o TS confere o esperado.
// Se um dos dois lados mudar, um dos dois testes reprova.
//
// O mesmo vale para o documento lido da resposta do cliente (_orcamento_documento_lido): os casos entre $documentos$ …
// $documentos$ conferem aqui o dígito verificador pela mesma conta de isValidCPF e isValidCNPJ (src/lib/masks.ts).
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { faltasParaNota } from './ficha-cliente';
import { isValidCNPJ, isValidCPF } from './masks';

interface CasoFaltas {
  nome: string;
  cliente: Parameters<typeof faltasParaNota>[0];
  esperado: string[];
}

interface CasoDocumento {
  texto: string;
  esperado: string | null;
}

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const TESTE_SQL = join(RAIZ, 'supabase', 'tests', 'retorno_f5_aceite.sql');
const MIGRATION = join(RAIZ, 'supabase', 'migrations', '20270112100500_retorno_f5_aceite.sql');

/** O JSON entre $marca$[ … ]$marca$ do teste SQL (o mesmo literal que o banco lê; o comentário que cita a marca não conta). */
function blocoJson<T>(texto: string, marca: string): T {
  const abre = `$${marca}$[`;
  const fecha = `]$${marca}$`;
  const ini = texto.indexOf(abre);
  const fim = ini < 0 ? -1 : texto.indexOf(fecha, ini + abre.length);
  if (ini < 0 || fim < 0) throw new Error(`não achei ${abre} … ${fecha} em retorno_f5_aceite.sql`);
  return JSON.parse(texto.slice(ini + abre.length - 1, fim + 1)) as T;
}

const ROTULOS = ['CPF/CNPJ', 'CPF/CNPJ incompleto', 'inscrição estadual', 'rua', 'bairro', 'cidade', 'UF', 'CEP', 'CEP incompleto'];

/** Os trechos com dígitos e pontuação de documento (a mesma regra de _orcamento_documento_lido). */
const trechos = (texto: string) => texto.match(/[0-9][0-9./-]*[0-9]/g) ?? [];
const documentoValido = (d: string) => (d.length === 11 ? isValidCPF(d) : d.length === 14 ? isValidCNPJ(d) : false);

describe('faltasParaNota × _orcamento_faltas_para_nota', () => {
  const sql = readFileSync(TESTE_SQL, 'utf8');
  const casos = blocoJson<CasoFaltas[]>(sql, 'faltas');

  it('os casos têm nomes únicos e cobrem os de ficha-cliente.test.ts', () => {
    expect(casos.length).toBeGreaterThanOrEqual(12);
    expect(new Set(casos.map((c) => c.nome)).size).toBe(casos.length);
    for (const nome of ['cadastro completo', 'lista o que o servidor recusaria', 'documento e CEP pela metade',
      'contribuinte do ICMS sem IE', 'contribuinte do ICMS com IE']) {
      expect(casos.map((c) => c.nome)).toContain(nome);
    }
  });

  it('o TS dá o esperado em cada caso (o banco confere o mesmo esperado)', () => {
    for (const c of casos) {
      expect({ nome: c.nome, faltas: faltasParaNota(c.cliente) }).toEqual({ nome: c.nome, faltas: c.esperado });
    }
  });

  it('todo rótulo do TS aparece nos casos e na função do banco', () => {
    const migration = readFileSync(MIGRATION, 'utf8');
    const usados = new Set(casos.flatMap((c) => c.esperado));
    for (const r of ROTULOS) {
      expect(usados.has(r), `nenhum caso espera "${r}"`).toBe(true);
      expect(migration.includes(`'${r}'`), `a migration não tem o rótulo '${r}'`).toBe(true);
    }
  });
});

describe('_orcamento_documento_lido: o dígito verificador é o de masks.ts', () => {
  const sql = readFileSync(TESTE_SQL, 'utf8');
  const casos = blocoJson<CasoDocumento[]>(sql, 'documentos');

  it('há casos de CPF, CNPJ, dígito errado e telefone', () => {
    expect(casos.some((c) => c.esperado?.length === 11)).toBe(true);
    expect(casos.some((c) => c.esperado?.length === 14)).toBe(true);
    expect(casos.filter((c) => c.esperado === null).length).toBeGreaterThanOrEqual(3);
  });

  it('o esperado é o 1º trecho de 11 ou 14 dígitos com o dígito verificador válido', () => {
    for (const c of casos) {
      const achado = trechos(c.texto).map((t) => t.replace(/[^0-9]/g, '')).find(documentoValido) ?? null;
      expect({ texto: c.texto, documento: achado }).toEqual({ texto: c.texto, documento: c.esperado });
    }
  });
});
