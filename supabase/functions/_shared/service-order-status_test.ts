// MF-AUD-005/006/007/008 — o teste que impede a lista de status de divergir do banco.
//
// A classe de bug que originou isto: quatro cópias manuais da lista, todas com quatro
// status inexistentes e sem `open`. Corrigir os quatro pontos resolve hoje; este teste
// é o que resolve amanhã — ele lê o CHECK direto da migration e cobra a igualdade.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dirname, fromFileUrl, join } from "https://deno.land/std@0.224.0/path/mod.ts";
import { ROTULOS_STATUS_OS, STATUS_OS, STATUS_OS_AGENDAVEIS, STATUS_OS_ATIVAS } from "./service-order-status.ts";

const RAIZ = join(dirname(fromFileUrl(import.meta.url)), "..", "..", "..");
const DIR_MIGRATIONS = join(RAIZ, "supabase", "migrations");

/**
 * Lê o CHECK vigente da migration MAIS RECENTE que o define. Buscar a última — e não um
 * arquivo fixo — é o que faz o teste continuar correto quando alguém alterar o CHECK.
 */
function statusDoCheckNoBanco(): string[] {
  const arquivos = [...Deno.readDirSync(DIR_MIGRATIONS)]
    .filter((e) => e.isFile && e.name.endsWith(".sql"))
    .map((e) => e.name)
    .sort(); // nome começa com timestamp, então ordem alfabética = ordem cronológica

  let ultimo: string[] | null = null;
  for (const nome of arquivos) {
    const sql = Deno.readTextFileSync(join(DIR_MIGRATIONS, nome));
    if (!/service_orders_status_check/i.test(sql)) continue;
    // Aceita as duas formas usadas no repo: `status IN (...)` e `status = ANY (ARRAY[...])`.
    const m = sql.match(/CHECK\s*\(\s*status\s*(?:=\s*ANY\s*\(\s*ARRAY\s*\[|IN\s*\()([^\])]+)/i);
    if (m) ultimo = m[1].split(",").map((s) => s.trim().replace(/^'|'$/g, "")).filter(Boolean);
  }
  if (!ultimo) throw new Error("Não achei o CHECK de service_orders.status em nenhuma migration.");
  return ultimo;
}

Deno.test("STATUS_OS espelha exatamente o CHECK da tabela", () => {
  assertEquals(
    [...STATUS_OS].sort(),
    statusDoCheckNoBanco().sort(),
    "A lista de status divergiu do banco. Se o CHECK mudou, atualize _shared/service-order-status.ts.",
  );
});

Deno.test("os recortes só contêm status que existem", () => {
  const validos = new Set<string>(STATUS_OS);
  for (const s of STATUS_OS_ATIVAS) assertEquals(validos.has(s), true, `STATUS_OS_ATIVAS tem '${s}', que não existe`);
  for (const s of STATUS_OS_AGENDAVEIS) assertEquals(validos.has(s), true, `STATUS_OS_AGENDAVEIS tem '${s}', que não existe`);
});

Deno.test("agendáveis incluem 'open' — foi a omissão que esvaziou o dropdown da Agenda", () => {
  assertEquals(STATUS_OS_AGENDAVEIS.includes("open"), true);
  // E não incluem o que já acabou: reagendar OS concluída/cancelada não faz sentido.
  for (const encerrado of ["completed", "invoiced", "cancelled"] as const) {
    assertEquals(STATUS_OS_AGENDAVEIS.includes(encerrado), false, `'${encerrado}' não deveria ser agendável`);
  }
});

Deno.test("todo status tem rótulo, e todo rótulo tem status", () => {
  assertEquals(Object.keys(ROTULOS_STATUS_OS).sort(), [...STATUS_OS].sort());
});
