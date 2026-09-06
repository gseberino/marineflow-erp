// O teste que impede a lista de `related_entity_type` de divergir do banco — e as duas
// tabelas de divergirem entre si.
//
// A classe de bug: `related_entity_type` é CHECK de lista fechada, e um tipo fora da lista
// falha com 23514 que o catch por regra do task-automations engole. O cron responde 200 e a
// regra nova simplesmente não faz nada (R17, 30/07/2026). Corrigir a lista resolve hoje;
// este teste é o que resolve amanhã: lê os dois CHECKs direto das migrations e cobra.
//
// Mesmo padrão de `service-order-status_test.ts`, que nasceu do MF-AUD-005 pela mesma razão.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dirname, fromFileUrl, join } from "https://deno.land/std@0.224.0/path/mod.ts";
import {
  ehTipoDeEntidadeValido, RELATED_ENTITY_TYPES, ROTULOS_ENTIDADE,
} from "./agenda-entity-types.ts";

const RAIZ = join(dirname(fromFileUrl(import.meta.url)), "..", "..", "..");
const DIR_MIGRATIONS = join(RAIZ, "supabase", "migrations");

/**
 * Lê o CHECK vigente da migration MAIS RECENTE que define a constraint pedida. Buscar a
 * última — e não um arquivo fixo — é o que faz o teste continuar correto quando alguém
 * alterar o CHECK numa migration nova.
 *
 * Tolera as duas sintaxes usadas no repo: `= any (array[...])` (agenda_tasks, minúsculo)
 * e `IN (...)` inline na coluna (agenda_suggestions original), em várias linhas.
 */
function tiposDoCheckNoBanco(constraint: string): string[] {
  const arquivos = [...Deno.readDirSync(DIR_MIGRATIONS)]
    .filter((e) => e.isFile && e.name.endsWith(".sql"))
    .map((e) => e.name)
    .sort(); // nome começa com timestamp, então ordem alfabética = ordem cronológica

  let ultimo: string[] | null = null;
  for (const nome of arquivos) {
    const bruto = Deno.readTextFileSync(join(DIR_MIGRATIONS, nome));
    if (!new RegExp(constraint, "i").test(bruto)) continue;
    // Tirar os comentários ANTES de casar: um `--` que contenha parêntese (o
    // "-- novo: cotação a fornecedor (COT-)" da migration de 30/07) fecha a captura
    // cedo demais e o último valor da lista some — o teste passaria a comparar uma
    // lista truncada e acusaria divergência onde não há.
    const sql = bruto.replace(/--[^\n]*/g, "");
    const m = sql.match(
      /related_entity_type\s*(?:=\s*any\s*\(\s*array\s*\[|in\s*\()([^\])]+)/i,
    );
    if (m) {
      ultimo = m[1]
        .split(",")
        .map((s) => s.trim().replace(/^'|'$/g, "").trim())
        .filter(Boolean);
    }
  }
  if (!ultimo) throw new Error(`Não achei o CHECK ${constraint} em nenhuma migration.`);
  return ultimo;
}

Deno.test("RELATED_ENTITY_TYPES espelha o CHECK de agenda_tasks", () => {
  assertEquals(
    [...RELATED_ENTITY_TYPES].sort(),
    tiposDoCheckNoBanco("agenda_tasks_related_entity_type_check").sort(),
    "A lista divergiu do CHECK de agenda_tasks. Se o CHECK mudou, atualize _shared/agenda-entity-types.ts.",
  );
});

Deno.test("agenda_suggestions aceita os MESMOS tipos que agenda_tasks", () => {
  // As duas tabelas já divergiram uma vez: agenda_tasks ganhou 'quote_request' em
  // 30/07/2026 e agenda_suggestions ficou para trás por quase um mês. Uma sugestão que
  // apontasse para cotação cairia no mesmo 23514 — e o insert de sugestão também engole
  // erro diferente de 23505.
  assertEquals(
    tiposDoCheckNoBanco("agenda_suggestions_related_entity_type_check").sort(),
    tiposDoCheckNoBanco("agenda_tasks_related_entity_type_check").sort(),
    "Os CHECKs das duas tabelas divergiram. Amplie os dois na mesma migration.",
  );
});

Deno.test("todo tipo tem rótulo em pt-BR", () => {
  // O Record é exaustivo, então o compilador já cobra — este teste pega o caso de alguém
  // afrouxar para Partial<Record<...>> e deixar um chip sem legenda na tela.
  for (const t of RELATED_ENTITY_TYPES) {
    assertEquals(typeof ROTULOS_ENTIDADE[t], "string");
    assertEquals(ROTULOS_ENTIDADE[t].length > 0, true, `sem rótulo: ${t}`);
  }
});

Deno.test("ehTipoDeEntidadeValido aceita null e recusa o que o banco recusaria", () => {
  // null é "sem vínculo" e o CHECK aceita — a validação não pode ser mais rígida que a
  // tabela, senão a R11 (nota fiscal, que grava null de propósito) passaria a ser barrada.
  assertEquals(ehTipoDeEntidadeValido(null), true);
  assertEquals(ehTipoDeEntidadeValido(undefined), true);
  assertEquals(ehTipoDeEntidadeValido("service_order"), true);
  assertEquals(ehTipoDeEntidadeValido("quote_request"), true);
  assertEquals(ehTipoDeEntidadeValido("fiscal_note"), false);
  assertEquals(ehTipoDeEntidadeValido(""), false);
  assertEquals(ehTipoDeEntidadeValido(42), false);
});
