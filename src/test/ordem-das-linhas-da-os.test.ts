import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Onde se NUMERA serviço, a leitura desempata por `id` (porte da via do técnico v2, F0, 16/11/2026).
 *
 * ═══ POR QUE ESTE TESTE EXISTE ═══
 *
 * A ordem das linhas de uma OS era só `created_at`. As linhas gravadas num INSERT só (o orçamento do assistente, a
 * cópia de OS) ganham o mesmo `now()`, e no empate o Postgres devolve a ordem FÍSICA — que um UPDATE troca. Gravar a
 * situação ou a instrução de um serviço podia mudar o número dele na via seguinte: o "3" do papel deixava de ser o "3"
 * da tela e do assistente. 18 documentos em produção tinham empate (95 linhas).
 *
 * A regra é `created_at, id` em todo lugar que numera (ou alimenta o que numera). Pelo PostgREST:
 * `.order('created_at').order('id')`; no embutido (que não ordena), `ordenarLinhas` (_shared/linhas-da-os.ts).
 * Esta varredura trava as leituras da tabela F0.3 do plano: quem tirar o `.order('id')` delas, ou ler a cópia sem
 * `ordenarLinhas`, quebra aqui.
 */

const RAIZ = process.cwd();
const ler = (arquivo: string) => readFileSync(join(RAIZ, arquivo), 'utf8').replace(/\r\n/g, '\n');

/** `.order('created_at'[, { ascending: true }]).order('id'`: o par da regra. */
const CREATED_AT_E_ID = /\.order\(\s*['"]created_at['"](?:\s*,\s*\{\s*ascending:\s*true\s*\})?\s*\)\s*\.order\(\s*['"]id['"]/;
/** O mesmo par, mas a partir do 1º `.order(` da cadeia: um `.order()` antes dele muda a ordem primária (revisão final, c-6). */
const CREATED_AT_E_ID_PRIMEIRO = new RegExp('^' + CREATED_AT_E_ID.source);

/** Cada `.from('<tabela>')` de LEITURA (select sem insert/update/delete, e não a de uma linha só pelo id). */
export function leiturasSemDesempate(codigo: string, tabela: string): { leituras: number; semId: string[] } {
  const re = new RegExp(`\\.from\\(\\s*['"]${tabela}['"]\\s*\\)`, 'g');
  let leituras = 0;
  const semId: string[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(codigo))) {
    const resto = codigo.slice(m.index + m[0].length);
    const fim = Math.min(...[resto.indexOf(';'), resto.indexOf('.from(')].filter((i) => i >= 0), resto.length);
    const cadeia = resto.slice(0, fim);
    if (!/\.select\(/.test(cadeia) || /\.(insert|update|upsert|delete)\(/.test(cadeia)) continue;
    if (/\.eq\(\s*['"]id['"]/.test(cadeia)) continue;
    leituras++;
    // `created_at` ascendente SEGUIDO de `id`, e nada descendente na cadeia: só "tem um .order('id')" deixava passar
    // `.order('id')` sozinho (a ordem vira a do uuid), `id` antes de `created_at` e os dois descendentes (ordem-3).
    // E o par vem PRIMEIRO: achar o par em qualquer ponto deixava passar `.order('name_snapshot')` antes dele, e a
    // numeração passava a seguir o nome (revisão final, c-6).
    const i = cadeia.indexOf('.order(');
    const emOrdem = i >= 0 && CREATED_AT_E_ID_PRIMEIRO.test(cadeia.slice(i));
    if (!emOrdem || /ascending:\s*false/.test(cadeia)) {
      const linha = codigo.slice(0, m.index).split('\n').length;
      semId.push(`linha ${linha}: ${cadeia.replace(/\s+/g, ' ').slice(0, 140)}`);
    }
  }
  return { leituras, semId };
}

/** As leituras da tabela F0.3 (e da F0.2) do plano, arquivo a arquivo. */
const LEITURAS: Array<{ arquivo: string; tabela: string; motivo: string }> = [
  { arquivo: 'supabase/functions/_shared/pdf/via-do-tecnico-dados.ts', tabela: 'service_order_services', motivo: 'via no servidor (assistente e agenda)' },
  { arquivo: 'supabase/functions/_shared/pdf/via-do-tecnico-dados.ts', tabela: 'service_order_parts', motivo: 'material da via no servidor' },
  { arquivo: 'src/hooks/use-service-orders.ts', tabela: 'service_order_services', motivo: 'via na tela, lista da OS e "Lançar a via"' },
  { arquivo: 'src/hooks/use-service-steps.ts', tabela: 'service_order_parts', motivo: 'material da via na tela' },
  { arquivo: 'supabase/functions/_shared/ai/tools/field-ops.ts', tabela: 'service_order_services', motivo: 'update_service_order_via' },
  { arquivo: 'supabase/functions/_shared/ai/tools/via-do-tecnico.ts', tabela: 'service_order_services', motivo: 'responsável de cada serviço' },
  { arquivo: 'supabase/functions/_shared/ai/tools/service-orders.ts', tabela: 'service_order_services', motivo: 'get_service_order e remover/editar item' },
];

/** A cópia de OS lê pelo embutido (sem ordem): tem de passar por ordenarLinhas. */
const COPIAS = ['supabase/functions/_shared/ai/tools/so-ops.ts', 'src/hooks/use-service-orders.ts'];

describe('ordem das linhas da OS: created_at, id onde se numera', () => {
  it.each(LEITURAS)('$arquivo — $tabela ($motivo) desempata por id', ({ arquivo, tabela }) => {
    const r = leiturasSemDesempate(ler(arquivo), tabela);
    // Sem nenhuma leitura achada, o teste não estaria vigiando nada.
    expect(r.leituras).toBeGreaterThan(0);
    expect(r.semId).toEqual([]);
  });

  it.each(COPIAS)('%s — a cópia de OS ordena a origem com ordenarLinhas', (arquivo) => {
    const codigo = ler(arquivo);
    expect(codigo).toMatch(/ordenarLinhas\(\s*(Array\.isArray\(pecas\)|source\.service_order_parts)/);
    expect(codigo).toMatch(/ordenarLinhas\(\s*(Array\.isArray\(servicos\)|source\.service_order_services)/);
  });

  it('a varredura pega a leitura sem desempate (e ignora escrita e a linha única pelo id)', () => {
    const codigo = `
      const a = await sb.from('service_order_services').select('*').eq('service_order_id', x).order('created_at');
      const b = await sb.from("service_order_services").select("id").eq("service_order_id", x).order("created_at").order("id");
      const c = await sb.from('service_order_services').insert(linhas).select();
      const d = await sb.from('service_order_services').select('*').eq('id', id).single();`;
    const r = leiturasSemDesempate(codigo, 'service_order_services');
    expect(r.leituras).toBe(2);
    expect(r.semId).toHaveLength(1);
    expect(r.semId[0]).toContain('linha 2');
  });

  it('a varredura exige created_at ASCENDENTE seguido de id, como 1ª ordem: id sozinho, id antes, descendente e outro .order() antes do par não passam (ordem-3, c-6)', () => {
    const codigo = `
      const e = await sb.from('service_order_services').select('*').eq('service_order_id', x).order('id');
      const f = await sb.from('service_order_services').select('*').eq('service_order_id', x).order('id').order('created_at');
      const g = await sb.from('service_order_services').select('*').eq('service_order_id', x).order('created_at', { ascending: false }).order('id', { ascending: false });
      const h = await sb.from("service_order_services").select("*").eq("service_order_id", x)
        .order("created_at", { ascending: true }).order("id", { ascending: true });
      const i = await sb.from('service_order_services').select('*').eq('service_order_id', x).order('created_at').order('id', { ascending: false });
      const j = await sb.from('service_order_services').select('*').eq('service_order_id', x).order('name_snapshot').order('created_at', { ascending: true }).order('id', { ascending: true });
      const k = await sb.from('service_order_services').select('*').eq('service_order_id', x).order('id').order('created_at').order('id');`;
    const r = leiturasSemDesempate(codigo, 'service_order_services');
    expect(r.leituras).toBe(7);
    // j e k têm o par created_at → id, mas depois de outro .order(): a ordem primária é a do nome / do uuid (c-6)
    expect(r.semId.map((s) => s.slice(0, s.indexOf(':')))).toEqual(['linha 2', 'linha 3', 'linha 4', 'linha 7', 'linha 8', 'linha 9']);
  });
});
