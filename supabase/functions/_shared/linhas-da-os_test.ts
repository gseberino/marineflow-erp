// A ordem e o número das linhas da OS, e o achador de "serviço N" (F0 do porte da via v2). Os casos moram em
// linhas-da-os-casos.ts (a F2 roda a mesma lista no Postgres).
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  acharLinha,
  chaveDoInstante,
  instantesEmSequencia,
  numeroDito,
  numerarLinhas,
  ordenarLinhas,
} from "./linhas-da-os.ts";
import { CASOS_DE_ORDEM, CASOS_DO_ACHADOR, CASOS_DO_NUMERO_DITO, LINHAS_DO_ACHADOR } from "./linhas-da-os-casos.ts";

for (const c of CASOS_DE_ORDEM) {
  Deno.test(`ordem: ${c.caso}`, () => {
    const ordenadas = ordenarLinhas(c.linhas);
    assertEquals(ordenadas.map((l) => l.id), c.ordem);
    // a ordem recebida não importa
    assertEquals(ordenarLinhas([...c.linhas].reverse()).map((l) => l.id), c.ordem);
    // o número é a posição na ordem canônica
    assertEquals(numerarLinhas(ordenadas).map((l) => l.numero), c.ordem.map((_, i) => i + 1));
  });
}

Deno.test("ordem: sem created_at vai para o fim (NULLS LAST) e o id desempata; a lista de entrada fica intacta", () => {
  const entrada = [
    { id: "b", created_at: null },
    { id: "z", created_at: "2026-11-16T10:00:00+00:00" },
    { id: "a" },
  ];
  assertEquals(ordenarLinhas(entrada).map((l) => l.id), ["z", "a", "b"]);
  assertEquals(entrada.map((l) => l.id), ["b", "z", "a"]);
});

Deno.test("numerarLinhas não reordena: numera na ordem recebida", () => {
  assertEquals(numerarLinhas([{ id: "x" }, { id: "a" }]), [{ id: "x", numero: 1 }, { id: "a", numero: 2 }]);
});

Deno.test("chave do instante: microssegundo preservado; o mesmo instante em dois fusos dá a mesma chave", () => {
  assert(chaveDoInstante("2026-11-16T18:01:02.123456+00:00")! < chaveDoInstante("2026-11-16T18:01:02.123457+00:00")!);
  assertEquals(chaveDoInstante("2026-11-16 15:01:02.5-03"), chaveDoInstante("2026-11-16T18:01:02.500000Z"));
  assertEquals(chaveDoInstante("ontem"), null);
});

Deno.test("instantes em sequência: base + 1 ms, + 2 ms… estritamente depois da base (mesmo com microssegundos)", () => {
  const base = "2026-11-16T18:01:02.123456+00:00";
  const seq = instantesEmSequencia(base, 3);
  assertEquals(seq, ["2026-11-16T18:01:02.124Z", "2026-11-16T18:01:02.125Z", "2026-11-16T18:01:02.126Z"]);
  for (const s of seq) assert(chaveDoInstante(s)! > chaveDoInstante(base)!);
  // sem base (o banco não devolveu): o relógio de quem grava
  assertEquals(instantesEmSequencia(null, 2, () => Date.UTC(2026, 10, 16, 12)), ["2026-11-16T12:00:00.001Z", "2026-11-16T12:00:00.002Z"]);
  assertEquals(instantesEmSequencia(base, 0), []);
});

for (const [texto, numero] of CASOS_DO_NUMERO_DITO) {
  Deno.test(`numeroDito: "${texto}" → ${numero}`, () => {
    assertEquals(numeroDito(texto), numero);
  });
}

for (const [dito, esperado] of CASOS_DO_ACHADOR) {
  Deno.test(`acharLinha: "${dito}" → ${esperado}`, () => {
    const r = acharLinha(LINHAS_DO_ACHADOR, dito);
    if (typeof esperado === "number") {
      assert("linha" in r, JSON.stringify(r));
      assertEquals(r.linha.numero, esperado);
    } else {
      assert(!("linha" in r), JSON.stringify(r));
      assertEquals(r.motivo, esperado);
    }
  });
}

Deno.test("acharLinha: o erro lista 'N · nome' e a ambiguidade pede o número, sem escolher", () => {
  const fora = acharLinha(LINHAS_DO_ACHADOR, "200");
  assert(!("linha" in fora));
  assertEquals(
    fora.erro,
    "A OS tem 5 serviços; não existe o 200. Serviços: 1 · Instalação de bateria LiFePO4 200 Ah; 2 · Serviço de revisão do gerador; " +
      "3 · Troca do inversor 3000 W; 4 · Fita LED externa; 5 · Deslocamento.",
  );
  const duas = [
    { id: "a", numero: 1, nome: "Instalação do inversor" },
    { id: "b", numero: 2, nome: "Troca das baterias" },
    { id: "c", numero: 3, nome: "Teste do inversor" },
  ];
  const r = acharLinha(duas, "inversor");
  assert("motivo" in r && r.motivo === "ambiguo");
  assertEquals(r.opcoes.map((l) => l.id), ["a", "c"]);
  assertEquals(r.erro, '"inversor" casa com mais de um serviço: 1 · Instalação do inversor; 3 · Teste do inversor. Use o número.');
  // id exato ganha de tudo
  assertEquals(acharLinha(duas, "c"), { linha: duas[2] });
});

Deno.test("acharLinha: palavra inteira — '4' não casa com LiFePO4 e 'DC-DC' casa com o conversor", () => {
  const linhas = [
    { id: "s1", numero: 1, nome: "Instalação do conversor DC-DC" },
    { id: "s2", numero: 2, nome: "Bateria LiFePO4" },
  ];
  assertEquals(acharLinha(linhas, "DC-DC"), { linha: linhas[0] });
  assertEquals(acharLinha(linhas, "lifepo4"), { linha: linhas[1] });
  // "4" numa OS de 2: pergunta, nunca vira a bateria
  assertEquals((acharLinha(linhas, "4") as { motivo: string }).motivo, "fora_da_faixa");
  assertEquals((acharLinha(linhas, "lifepo") as { linha: { id: string } }).linha.id, "s2");
});
