// Paridade dos feriados: feriados.ts (o Secretário) = supabase/tests/agenda/feriados_2026_2035.json =
// agenda_feriado() no banco (Agenda de Produção, Fase 1, P1).
//
// O JSON é o meio-campo: este teste prova TS = JSON, e a bancada (scripts/bancada-agenda/rodar.mjs,
// supabase/tests/agenda_fase1_base.sql) prova SQL = JSON, dia a dia, nos 3.652 dias de 2026 a 2035.
// O arquivo é GERADO daqui; não edite à mão. Para regerar (só quando feriados.ts mudar de propósito):
//
//   deno run --allow-write=supabase/tests/agenda supabase/functions/_shared/secretario/feriados-paridade_test.ts
//
// e mude agenda_feriado() na mesma leva (nova migration), senão a bancada reprova.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { somarDias } from "./base.ts";
import { feriadoDoDia } from "./feriados.ts";

const ARQUIVO = new URL("../../../tests/agenda/feriados_2026_2035.json", import.meta.url);
const DE = "2026-01-01";
const ATE = "2035-12-31";

export interface ParidadeDeFeriados {
  gerado_de: string;
  de: string;
  ate: string;
  dias: number;
  feriados: Record<string, string>;
}

/** Todos os dias de DE a ATE; só os feriados entram no mapa (dia sem chave = não é feriado). */
export function gerarParidade(): ParidadeDeFeriados {
  const feriados: Record<string, string> = {};
  let dias = 0;
  for (let d = DE; d <= ATE; d = somarDias(d, 1)) {
    dias++;
    const nome = feriadoDoDia(d);
    if (nome) feriados[d] = nome;
  }
  return { gerado_de: "supabase/functions/_shared/secretario/feriados.ts", de: DE, ate: ATE, dias, feriados };
}

Deno.test("feriados.ts de 2026 a 2035 = o JSON de paridade que a bancada compara com agenda_feriado()", async () => {
  const noArquivo = JSON.parse(await Deno.readTextFile(ARQUIVO));
  assertEquals(noArquivo, gerarParidade());
});

Deno.test("o JSON cobre 3.652 dias, 11 feriados por ano, com 15/06 e 20/11 e sem Carnaval nem Corpus Christi", () => {
  const p = gerarParidade();
  assertEquals(p.dias, 3652);
  assertEquals(Object.keys(p.feriados).length, 110);
  for (let ano = 2026; ano <= 2035; ano++) {
    assertEquals(p.feriados[`${ano}-06-15`], "aniversário de Itajaí");
    assertEquals(p.feriados[`${ano}-11-20`], "Consciência Negra");
    assertEquals(Object.keys(p.feriados).filter((d) => d.startsWith(`${ano}-`)).length, 11);
  }
  assertEquals(p.feriados["2026-02-17"], undefined); // Carnaval
  assertEquals(p.feriados["2026-06-04"], undefined); // Corpus Christi
  assertEquals(p.feriados["2026-08-11"], undefined); // SC, transferido para o domingo
  assertEquals(p.feriados["2026-04-03"], "Sexta-feira Santa");
});

if (import.meta.main) {
  await Deno.writeTextFile(ARQUIVO, JSON.stringify(gerarParidade(), null, 2) + "\n");
  console.log(`gravado: ${ARQUIVO.pathname}`);
}
