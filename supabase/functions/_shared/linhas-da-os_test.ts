// A ordem e o número das linhas da OS, e o achador de "serviço N" (F0 do porte da via v2). Os casos moram em
// linhas-da-os-casos.ts (a F2 roda a mesma lista no Postgres).
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  acharLinha,
  chaveDoInstante,
  comecaComAsPalavras,
  instantesEmSequencia,
  numeroDito,
  numerarLinhas,
  ordenarLinhas,
  ordinalDito,
  temAsPalavras,
} from "./linhas-da-os.ts";
import {
  CASOS_DE_ORDEM,
  CASOS_DO_ACHADOR,
  CASOS_DO_NUMERO_DITO,
  CASOS_DO_ORDINAL_DITO,
  LINHAS_DO_ACHADOR,
} from "./linhas-da-os-casos.ts";

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

Deno.test("número solto nunca casa nome por palavra; 'cabo 4' continua achando 'Cabo 4 mm' (revisão da F0, achador-1)", () => {
  assertEquals(temAsPalavras("Cabo flexível 4 mm", "4"), false);
  assertEquals(temAsPalavras("Cabo flexível 4 mm", "4 e 5"), false);
  assertEquals(temAsPalavras("Cabo flexível 4 mm", "serviço #4"), false);
  assertEquals(temAsPalavras("Cabo flexível 4 mm", "cabo 4"), true);
  assertEquals(temAsPalavras("Troca de 4 pneus", "4 pneus"), true);
  const linhas = [
    { id: "a", numero: 1, nome: "Alinhamento" },
    { id: "b", numero: 2, nome: "Troca de 4 pneus" },
    { id: "c", numero: 3, nome: "Balanceamento" },
    { id: "d", numero: 4, nome: "Revisão do freio" },
    { id: "e", numero: 5, nome: "Cabo 4 mm" },
  ];
  // outra grafia do 4 é o serviço 4, nunca a linha que tem a palavra "4"
  for (const dito of ["serviço #4", "No. 4", "(4)", "4️⃣", "item #4", "linha #4", '"4"', "serviço 4)"]) {
    assertEquals(acharLinha(linhas, dito), { linha: linhas[3] }, dito);
  }
  // fora da faixa continua perguntando
  assertEquals((acharLinha(linhas, "serviço #9") as { motivo: string }).motivo, "fora_da_faixa");
  // número sem palavra que não é número de serviço: não acha (pergunta), não casa por palavra
  assertEquals((acharLinha(linhas, "4 e 5") as { motivo: string }).motivo, "nao_achei");
  assertEquals((acharLinha(linhas, "1000") as { motivo: string }).motivo, "nao_achei");
  // com uma palavra junto, o nome acha
  assertEquals(acharLinha(linhas, "cabo 4"), { linha: linhas[4] });
  assertEquals(acharLinha(linhas, "4 pneus"), { linha: linhas[1] });
});

for (const [texto, numero] of CASOS_DO_ORDINAL_DITO) {
  Deno.test(`ordinalDito: "${texto}" → ${numero}`, () => {
    assertEquals(ordinalDito(texto), numero);
  });
}

Deno.test("ordinal por extenso: 'o quarto' é o 4, mas com 'quarto' (o cômodo) no nome de outra linha PERGUNTA (revisão da F0, achador-2)", () => {
  const linhas = [
    { id: "a", numero: 1, nome: "Instalação do inversor" },
    { id: "b", numero: 2, nome: "Ar-condicionado do quarto" },
    { id: "c", numero: 3, nome: "Fita LED" },
    { id: "d", numero: 4, nome: "Troca do disjuntor" },
  ];
  // antes: casava calado com "Ar-condicionado do quarto" (e o dono queria o serviço 4)
  for (const dito of ["o quarto", "quarto", "a quarta", "o quarto serviço"]) {
    const r = acharLinha(linhas, dito);
    assert("motivo" in r && r.motivo === "ambiguo", `${dito}: ${JSON.stringify(r)}`);
    assertEquals(r.opcoes.map((l) => l.id), ["d", "b"], dito);
    assertEquals(
      r.erro,
      `"${dito}" pode ser o serviço 4 (4 · Troca do disjuntor) ou o que tem "quarto" no nome: 2 · Ar-condicionado do quarto. Use o número.`,
    );
  }
  // sem a palavra no nome de ninguém, o ordinal é o número
  assertEquals(acharLinha(linhas, "o terceiro"), { linha: linhas[2] });
  assertEquals(acharLinha(linhas, "a primeira"), { linha: linhas[0] });
  // OS de 2 linhas com o cômodo na 2: não existe o 4º e a linha do quarto não é escolhida sozinha
  const r2 = acharLinha(linhas.slice(0, 2), "o quarto");
  assert("motivo" in r2 && r2.motivo === "ambiguo", JSON.stringify(r2));
  assertEquals(r2.opcoes.map((l) => l.id), ["b"]);
  assertEquals(r2.erro, '"o quarto" pode ser o serviço 4 (a OS tem 2) ou o que tem "quarto" no nome: 2 · Ar-condicionado do quarto. Use o número.');
  // nem a linha nem a palavra: fora da faixa
  assertEquals((acharLinha(linhas, "o sétimo") as { motivo: string }).motivo, "fora_da_faixa");
  // o nome com mais palavras continua pelo nome
  assertEquals(acharLinha(linhas, "ar-condicionado do quarto"), { linha: linhas[1] });
  assertEquals(acharLinha(linhas, "ar do quarto"), { linha: linhas[1] });
});

Deno.test("comecaComAsPalavras: começo de palavra com 4 letras ou mais; curta só inteira; só número nunca (revisão da F0, achador-3)", () => {
  assertEquals(comecaComAsPalavras("Abraçadeiras nylon", "abraçadeira"), true);
  assertEquals(comecaComAsPalavras("Cabos 6 mm", "cabo"), true);
  assertEquals(comecaComAsPalavras("Cabos 6 mm", "cab"), false);
  assertEquals(comecaComAsPalavras("Parametrização do carregador", "parametriz"), true);
  assertEquals(comecaComAsPalavras("Cabos 6 mm", "cabo 6"), true);
  assertEquals(comecaComAsPalavras("Cabos 6 mm", "6"), false);
  assertEquals(comecaComAsPalavras("Cabos 6 mm", "pintura"), false);
  assertEquals(comecaComAsPalavras("Cabos 6 mm", ""), false);
});
