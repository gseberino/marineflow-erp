// Paridade dos feriados municipais: FERIADOS_MUNICIPAIS (feriados.ts) = supabase/tests/agenda/feriados_municipais_2026_2035.json =
// agenda_feriado_municipal() no banco (Agenda de Produção, Fase 7d, P2).
//
// O JSON é o meio-campo, como em feriados-paridade_test.ts: este teste prova TS = JSON, e a bancada (scripts/bancada-agenda/rodar.mjs,
// supabase/tests/agenda_fase7d_feriados.sql) prova SQL = JSON, dia a dia, nos 3.652 dias de 2026 a 2035. O arquivo é GERADO daqui; não
// edite à mão. Para regerar (só quando FERIADOS_MUNICIPAIS mudar de propósito, com fonte conferida):
//
//   deno run --allow-write=supabase/tests/agenda supabase/functions/_shared/secretario/feriados-municipais-paridade_test.ts
//
// e mude agenda_feriado_municipal() na mesma leva (nova migration), senão a bancada reprova.
// O feriados_2026_2035.json é outro arquivo, do calendário da HBR, e não muda com os municipais.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { somarDias } from "./base.ts";
import {
  feriadoDoDia,
  feriadoDoLocal,
  feriadoMunicipal,
  FERIADOS_MUNICIPAIS,
  normalizarMunicipio,
  tipoDoDia,
} from "./feriados.ts";

const ARQUIVO = new URL("../../../tests/agenda/feriados_municipais_2026_2035.json", import.meta.url);
const ARQUIVO_HBR = new URL("../../../tests/agenda/feriados_2026_2035.json", import.meta.url);
const DE = "2026-01-01";
const ATE = "2035-12-31";
const BC = "aniversário de Balneário Camboriú";

export interface ParidadeDeMunicipais {
  gerado_de: string;
  de: string;
  ate: string;
  dias: number;
  municipios: Record<string, Record<string, string>>;
}

/** Todos os dias de DE a ATE × os municípios da lista; só os feriados entram no mapa (dia sem chave = não é feriado). */
export function gerarParidade(): ParidadeDeMunicipais {
  const municipios: Record<string, Record<string, string>> = {};
  let dias = 0;
  for (let d = DE; d <= ATE; d = somarDias(d, 1)) {
    dias++;
    for (const m of Object.keys(FERIADOS_MUNICIPAIS)) {
      const nome = feriadoMunicipal(d, m);
      if (nome) (municipios[m] ??= {})[d] = nome;
    }
  }
  return { gerado_de: "supabase/functions/_shared/secretario/feriados.ts", de: DE, ate: ATE, dias, municipios };
}

Deno.test("FERIADOS_MUNICIPAIS de 2026 a 2035 = o JSON de paridade que a bancada compara com agenda_feriado_municipal()", async () => {
  const noArquivo = JSON.parse(await Deno.readTextFile(ARQUIVO));
  assertEquals(noArquivo, gerarParidade());
});

Deno.test("o JSON cobre 3.652 dias e 10 entradas, uma por ano, todas em 20/07", () => {
  const p = gerarParidade();
  assertEquals(p.dias, 3652);
  assertEquals(Object.keys(p.municipios), ["balneario camboriu"]);
  const dias = Object.keys(p.municipios["balneario camboriu"]);
  assertEquals(dias.length, 10);
  for (let ano = 2026; ano <= 2035; ano++) {
    assertEquals(p.municipios["balneario camboriu"][`${ano}-07-20`], BC);
  }
});

Deno.test("feriadoDoLocal nos 3.652 dias = o da HBR e, se não houver, o do município: o F1c de agenda_fase7d_feriados.sql", async () => {
  const hbr = JSON.parse(await Deno.readTextFile(ARQUIVO_HBR)).feriados;
  const bc = JSON.parse(await Deno.readTextFile(ARQUIVO)).municipios["balneario camboriu"];
  let feriados = 0;
  for (let d = DE; d <= ATE; d = somarDias(d, 1)) {
    const esperado = hbr[d] ?? bc[d] ?? null;
    assertEquals(feriadoDoLocal(d, "Balneário Camboriú"), esperado, d);
    assertEquals(feriadoDoLocal(d, "Itajaí"), hbr[d] ?? null, d);
    if (esperado) feriados++;
  }
  assertEquals(feriados, 120);
});

Deno.test("o 11/08 de SC fica fora", () => {
  assertEquals(feriadoMunicipal("2026-08-11", "Itajaí"), null);
  assertEquals(feriadoDoLocal("2026-08-11", "Florianópolis"), null);
});

Deno.test("Carnaval, Corpus Christi e o 28/05 ficam fora em Balneário Camboriú", () => {
  assertEquals(feriadoDoLocal("2026-02-17", "Balneário Camboriú"), null);
  assertEquals(feriadoDoLocal("2026-06-04", "Balneário Camboriú"), null);
  assertEquals(feriadoDoLocal("2026-05-28", "Balneário Camboriú"), null);
});

Deno.test("o da HBR vale em qualquer lugar e vem primeiro", () => {
  assertEquals(feriadoDoLocal("2026-06-15", "Balneário Camboriú"), "aniversário de Itajaí");
  assertEquals(feriadoDoLocal("2026-06-15", "Florianópolis"), "aniversário de Itajaí");
  assertEquals(feriadoDoLocal("2026-06-15", null), "aniversário de Itajaí");
  assertEquals(feriadoMunicipal("2026-06-15", "Balneário Camboriú"), null);
});

Deno.test("20/07 só existe para o local: o calendário da HBR não muda", () => {
  assertEquals(feriadoDoLocal("2027-07-20", "Balneário Camboriú"), BC);
  assertEquals(feriadoDoLocal("2027-07-20", "Itajaí"), null);
  assertEquals(feriadoDoDia("2027-07-20"), null);
  assertEquals(tipoDoDia("2027-07-20"), "util");
});

Deno.test("as grafias: a mesma lista do F2 de agenda_fase7d_feriados.sql", () => {
  assertEquals(normalizarMunicipio("BALNEÁRIO  CAMBORIÚ"), "balneario camboriu");
  const casam = [
    "Balneário Camboriú",
    "Balneario Camboriu",
    "BALNEÁRIO CAMBORIÚ",
    "balneário  camboriú",
    "  Balneario-Camboriu. ",
    "Balneário Camboriú".normalize("NFD"),
  ];
  for (const g of casam) assertEquals(feriadoMunicipal("2027-07-20", g), BC, g);
  // Camboriú é OUTRO município (10 clientes em produção, wf7dd_p2_grafias).
  const naoCasam = [
    "Camboriú",
    "Camboriu",
    "CAMBORIÚ",
    "Balneário",
    "Balneário Camboriú/SC",
    "Balneário/Camboriú",
    "Balneário Camboriú SC",
    "Camboriú Balneário",
    "BC",
    "",
    "   ",
  ];
  for (const g of naoCasam) assertEquals(feriadoMunicipal("2027-07-20", g), null, g);
});

Deno.test("município nulo ou que é nome de propriedade do objeto: null, sem erro", () => {
  assertEquals(feriadoMunicipal("2027-07-20", null), null);
  assertEquals(feriadoMunicipal("2027-07-20", undefined), null);
  assertEquals(feriadoMunicipal("2027-07-20", "constructor"), null);
  assertEquals(feriadoMunicipal("2027-07-20", "__proto__"), null);
});

if (import.meta.main) {
  await Deno.writeTextFile(ARQUIVO, JSON.stringify(gerarParidade(), null, 2) + "\n");
  console.log(`gravado: ${ARQUIVO.pathname}`);
}
