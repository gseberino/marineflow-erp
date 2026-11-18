import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

/**
 * A revisão do documento (Rev. N) só sobe quando muda o que o cliente LÊ — e quem decide o que ele lê é uma lista
 * fechada no banco (private.documento_conteudo_impresso, migration 20270123100000_revisao_de_documentos).
 *
 * O risco: alguém passa a imprimir uma coluna nova da ordem (em _shared/pdf/dados.ts) e esquece a lista. O documento
 * muda, a revisão não — e duas folhas diferentes saem com o mesmo "Rev. 3". Esta varredura pega toda coluna da ordem
 * que a montagem do PDF lê e exige que ela esteja na lista do banco, ou aqui, com o motivo de ficar de fora.
 */

const RAIZ = process.cwd();

/** Colunas da ordem que a montagem lê mas que NÃO mudam o que o cliente lê, com o porquê. */
const FORA_DA_REVISAO: Record<string, string> = {
  id: 'identifica a ordem, não é conteúdo',
  status: 'escolhe orçamento × OS (cada tipo tem o seu contador), não é impresso',
  commissioned_person: 'comissão não sai no documento (showCommission saiu do catálogo em 14/11/2026)',
  commission_rate: 'idem',
  commission_amount: 'idem',
  // embeds: entram por seção própria na lista do banco
  clients: 'seção cliente',
  vessels: 'seção unidade',
  marinas: 'seção local',
  service_order_services: 'seção servicos',
  service_order_parts: 'seção pecas',
  service_order_expenses: 'seção despesas',
  service_surveys: 'seção levantamento',
  service_order_photos: 'seção fotos',
  payment_condition_presets: 'seção condicao (+ payment_condition_preset_id no cabeçalho)',
};

function colunasLidasPelaMontagem(): string[] {
  const dados = readFileSync(join(RAIZ, 'supabase', 'functions', '_shared', 'pdf', 'dados.ts'), 'utf8');
  const nomes = new Set<string>();
  for (const m of dados.matchAll(/\(so as any\)\.([a-z_]+)|\bso\.([a-z_]+)|so\?\.([a-z_]+)/g)) {
    nomes.add(m[1] ?? m[2] ?? m[3]);
  }
  return [...nomes].sort();
}

function listaDoBanco(): string {
  const pasta = join(RAIZ, 'supabase', 'migrations');
  const ultima = readdirSync(pasta)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .filter((f) => /function private\.documento_conteudo_impresso/.test(readFileSync(join(pasta, f), 'utf8')))
    .pop();
  expect(ultima, 'nenhuma migration define documento_conteudo_impresso').toBeTruthy();
  const sql = readFileSync(join(pasta, ultima!), 'utf8');
  return sql.slice(sql.indexOf('function private.documento_conteudo_impresso'));
}

describe('a revisão acompanha tudo o que o documento imprime', () => {
  it('toda coluna da ordem lida pela montagem do PDF está na lista do banco ou explicada aqui', () => {
    const lista = listaDoBanco();
    const colunas = colunasLidasPelaMontagem();
    expect(colunas.length).toBeGreaterThan(15);
    const esquecidas = colunas.filter((c) => !(c in FORA_DA_REVISAO) && !lista.includes(`'${c}'`));
    expect(esquecidas, 'coluna impressa fora de private.documento_conteudo_impresso').toEqual([]);
  });

  it('o que muda internamente não está na lista (senão a revisão subiria por nada)', () => {
    const lista = listaDoBanco();
    for (const interna of ["'status'", "'quote_status'", "'internal_notes'", "'priority'", "'updated_at'", "'share_token'"]) {
      expect(lista.includes(interna), interna).toBe(false);
    }
  });
});
