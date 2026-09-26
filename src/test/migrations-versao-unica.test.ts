// Cada migration tem de ter uma VERSÃO só dela.
//
// O Supabase não usa o nome do arquivo como identidade: usa só o prefixo numérico antes do
// primeiro "_" (a coluna `version` de supabase_migrations.schema_migrations). Duas migrations
// com o mesmo prefixo são, para ele, a MESMA migration: se uma já foi aplicada, a outra é dada
// como aplicada e pulada em silêncio no `db push` — sem erro, sem aviso, e a regra que ela
// criaria simplesmente não existe em produção.
//
// Não é hipótese. Em 26/09/2026 a migration que tira a listagem anônima dos buckets com dado
// de cliente nasceu como 20260926210000_buckets_sem_listagem_anonima.sql, numa branch, enquanto
// a main já tinha 20260926210000_decisoes_do_dono.sql APLICADA em produção. Depois do merge, o
// push acharia a versão 20260926210000 registrada e deixaria a listagem aberta. Ela virou
// 20260927090000 — e este teste existe para a próxima colisão aparecer no merge, não em produção.
//
// Arquivo que nem casa com o padrão `<número>_<nome>.sql` também é ignorado pelo CLI em
// silêncio, então ele entra na mesma cobrança.

import { describe, expect, it } from "vitest";
import { readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const DIR_MIGRATIONS = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "supabase", "migrations");

/** O padrão do CLI: versão numérica, "_", nome. Aqui a versão é sempre o carimbo de 14 dígitos. */
const PADRAO = /^(\d{14})_(.+)\.sql$/;

/**
 * Colisões ANTIGAS, conhecidas e conferidas em produção — congeladas: o teste falha se aparecer
 * outro arquivo com o mesmo prefixo E se a colisão deixar de existir como está aqui (aí a
 * exceção sobra e tem de sair, para não virar buraco permanente).
 *
 * 20260803120000: em schema_migrations a versão pertence a `sugestao_de_sistema_na_linha`
 * (aplicada). `email_espelho_fase_e1` diz no cabeçalho "NÃO APLICADA", mas as tabelas dela
 * (public.email_accounts) existem em produção sem nenhum registro em schema_migrations — foram
 * criadas por fora. Um `db push` nunca a rodaria. Renomeá-la é decisão da frente do e-mail,
 * não desta; até lá ela fica visível aqui.
 */
const COLISOES_CONHECIDAS: Record<string, string[]> = {
  "20260803120000": [
    "20260803120000_email_espelho_fase_e1.sql",
    "20260803120000_sugestao_de_sistema_na_linha.sql",
  ],
};

function arquivosDeMigration(): string[] {
  return readdirSync(DIR_MIGRATIONS).filter((f) => f.endsWith(".sql")).sort();
}

function porVersao(arquivos: string[]): Map<string, string[]> {
  const grupos = new Map<string, string[]>();
  for (const arquivo of arquivos) {
    const versao = PADRAO.exec(arquivo)?.[1];
    if (!versao) continue;
    grupos.set(versao, [...(grupos.get(versao) ?? []), arquivo]);
  }
  return grupos;
}

describe("migrations — versão única por arquivo", () => {
  const arquivos = arquivosDeMigration();

  it("lê a pasta de verdade (senão as cobranças abaixo passariam com a lista vazia)", () => {
    expect(arquivos.length).toBeGreaterThan(400);
  });

  it("todo .sql da pasta segue <14 dígitos>_<nome>.sql (o CLI ignora em silêncio o que não segue)", () => {
    expect(arquivos.filter((f) => !PADRAO.test(f))).toEqual([]);
  });

  it("nenhuma versão é usada por dois arquivos (o Supabase pularia um deles em silêncio)", () => {
    const repetidas = [...porVersao(arquivos)]
      .filter(([, grupo]) => grupo.length > 1)
      .filter(([versao, grupo]) => {
        const conhecida = COLISOES_CONHECIDAS[versao];
        return !conhecida || grupo.join("|") !== [...conhecida].sort().join("|");
      })
      .map(([versao, grupo]) => `${versao}: ${grupo.join(" + ")}`);
    expect(repetidas).toEqual([]);
  });

  it("cada colisão antiga tolerada ainda existe exatamente como registrada (senão, apague a exceção)", () => {
    const grupos = porVersao(arquivos);
    const sobrando = Object.entries(COLISOES_CONHECIDAS)
      .filter(([versao, conhecida]) => (grupos.get(versao) ?? []).join("|") !== [...conhecida].sort().join("|"))
      .map(([versao]) => versao);
    expect(sobrando).toEqual([]);
  });
});
