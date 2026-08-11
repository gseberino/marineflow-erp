// [MF-AUD-020] Guarda estática das políticas do financeiro.
//
// A decisão #3 do dono (09/08/2026) é: o cargo técnico não enxerga NADA financeiro. A
// migration `20260810113036_tecnico_nao_ve_financeiro` cumpriu isso apertando o predicado das
// cinco tabelas do dinheiro.
//
// ═══ POR QUE UMA GUARDA ESTÁTICA, E NÃO SÓ O TESTE DE VERDADE ═══
//
// O teste que realmente prova a RLS precisa de um banco: está em
// `supabase/tests/rls_tecnico_financeiro.sql`, e alguém tem que rodá-lo. O CI deste repo não
// tem banco nem secrets — então, se a proteção dependesse só dele, uma migration futura
// poderia reescrever `authenticated_all_payments` sem o predicado e nada acusaria.
//
// É um risco concreto, não hipotético: `ALTER POLICY` substitui o predicado inteiro. Quem
// mexer nessas políticas por outro motivo (acrescentar uma regra de vendedor, por exemplo) e
// escrever o USING do zero apaga a barreira do técnico sem perceber. Este teste lê as
// migrations e falha nesse caso.
//
// O que ele NÃO faz, dito claramente: não conecta em banco nenhum e não prova que a política
// está ATIVA em produção. Prova que o repositório, aplicado do zero, produz a barreira.

import { describe, expect, it } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const raizDoRepo = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const DIR_MIGRATIONS = join(raizDoRepo, "supabase", "migrations");

/** As cinco tabelas do dinheiro, conforme a decisão #3. */
const TABELAS_FINANCEIRAS = [
  "payments",
  "receivables",
  "payables",
  "invoices",
  "bank_transactions",
] as const;

/** Migrations em ordem cronológica — o nome começa com o timestamp. */
function migrationsEmOrdem(): { arquivo: string; sql: string }[] {
  return readdirSync(DIR_MIGRATIONS)
    .filter((f) => f.endsWith(".sql"))
    .sort()
    .map((arquivo) => ({
      arquivo,
      sql: readFileSync(join(DIR_MIGRATIONS, arquivo), "utf8"),
    }));
}

/**
 * O ÚLTIMO trecho que define ou altera política sobre a tabela dada.
 *
 * "Último" é o que importa: uma migration posterior que reescreva a política é a que vale no
 * banco, e é justamente essa que pode ter perdido o predicado.
 */
function ultimaDefinicaoDePolitica(tabela: string): { arquivo: string; trecho: string } | null {
  let achado: { arquivo: string; trecho: string } | null = null;

  for (const { arquivo, sql } of migrationsEmOrdem()) {
    // `create policy ... on public.<tabela>` ou `alter policy ... on public.<tabela>`,
    // capturando até o ponto e vírgula que fecha o comando.
    const re = new RegExp(
      `(?:create|alter)\\s+policy[\\s\\S]*?\\son\\s+(?:public\\.)?${tabela}\\b[\\s\\S]*?;`,
      "gi",
    );
    const ocorrencias = [...sql.matchAll(re)];
    if (ocorrencias.length > 0) {
      achado = { arquivo, trecho: ocorrencias.map((m) => m[0]).join("\n") };
    }
  }

  return achado;
}

describe("MF-AUD-020 — o técnico não enxerga o financeiro", () => {
  it("a função is_technician existe e está fechada para anon", () => {
    const todas = migrationsEmOrdem().map((m) => m.sql).join("\n");

    expect(todas).toMatch(/create\s+or\s+replace\s+function\s+public\.is_technician\(/i);

    // Função nova nasce com EXECUTE para PUBLIC. Sem o revoke, o predicado continuaria certo
    // e a função viraria superfície de consulta para anônimo (MF-AUD-025).
    expect(todas).toMatch(/revoke\s+execute\s+on\s+function\s+public\.is_technician\(uuid\)\s+from\s+public,\s*anon/i);

    // SECURITY DEFINER com search_path fixo: sem isso, um schema no caminho de busca do
    // chamador poderia sequestrar a resolução de `app_users`.
    const corpo = todas.slice(todas.search(/create\s+or\s+replace\s+function\s+public\.is_technician\(/i));
    expect(corpo.slice(0, 400)).toMatch(/security\s+definer/i);
    expect(corpo.slice(0, 400)).toMatch(/set\s+search_path\s*=\s*public/i);
  });

  for (const tabela of TABELAS_FINANCEIRAS) {
    it(`a política vigente de ${tabela} carrega a barreira do técnico`, () => {
      const definicao = ultimaDefinicaoDePolitica(tabela);
      expect(definicao, `nenhuma política encontrada para ${tabela}`).not.toBeNull();

      const trecho = definicao!.trecho.toLowerCase();
      expect(
        trecho,
        `A última migration a mexer nas políticas de "${tabela}" foi `
        + `"${definicao!.arquivo}", e o predicado resultante não menciona is_technician. `
        + `Se a intenção era reescrever a política, ela precisa manter `
        + `"NOT public.is_technician(auth.uid())" — decisão #3 do dono, 09/08/2026.`,
      ).toContain("is_technician");

      // Negado, não permitido: `NOT is_technician`. Uma política que dissesse
      // `USING (is_technician(...))` mencionaria a função e faria exatamente o oposto.
      expect(trecho).toMatch(/not\s+public\.is_technician\s*\(/);
    });
  }

  it("payables mantém a regra de categoria sensível junto com a do técnico", () => {
    // A T1.4 (MF-AUD-023) fechou UPDATE/DELETE de payables de categoria sensível. A migration
    // do técnico veio depois e usou ALTER para somar, não substituir. Se alguém reescrever a
    // política do zero, uma das duas regras cai — e este teste diz qual.
    const definicao = ultimaDefinicaoDePolitica("payables");
    const trecho = definicao!.trecho.toLowerCase();

    expect(trecho).toContain("is_technician");
    expect(
      trecho.includes("sensitive") || trecho.includes("sensivel") || trecho.includes("categoria"),
      `A política de payables em "${definicao!.arquivo}" perdeu a referência à categoria `
      + `sensível (MF-AUD-023). As duas regras precisam coexistir.`,
    ).toBe(true);
  });
});
