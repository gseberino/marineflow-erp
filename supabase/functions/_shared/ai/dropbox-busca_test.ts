import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { chaveDeNome, escolherBarco, notaDoBarco, type Candidato } from "./dropbox-busca.ts";

const BARCOS: Candidato[] = [
  { id: "1", nome: "Donna V", cliente: "Acrisio Lopes Cançado Filho" },
  { id: "2", nome: "Bote", cliente: "Juliano Acrisio" },
  { id: "3", nome: "Madu I", cliente: "Edson Luiz Rudek Junior" },
  { id: "4", nome: "XF-06", cliente: "Edson Luiz Rudek Junior" },
  { id: "5", nome: "Motorhome", cliente: "Sandro Poeta" },
  { id: "6", nome: "Motorhome", cliente: "Newton" },
  { id: "7", nome: "Comandante Zepi", cliente: "Ribas" },
];

Deno.test("chave de nome: sem acento, minúsculo, letras repetidas juntadas", () => {
  assertEquals(chaveDeNome("Donna V"), chaveDeNome("Dona V"));
  assertEquals(chaveDeNome("Açaí  ÔNIBUS"), "acai onibus");
});

Deno.test("barco pelo nome, com grafia diferente", () => {
  const r = escolherBarco("dona v", BARCOS);
  assertEquals(r.ok && r.barco.id, "1");
  const r2 = escolherBarco("madu", BARCOS);
  assertEquals(r2.ok && r2.barco.id, "3");
});

Deno.test("'o barco do Ribas' acha pelo dono", () => {
  const r = escolherBarco("o barco do Ribas", BARCOS);
  assertEquals(r.ok && r.barco.id, "7");
});

Deno.test("o tipo na frente sai do termo, para todos os tipos (a pasta existe para motorhome também)", () => {
  for (const termo of ["o trailer do Ribas", "o motorhome do Ribas", "o camper do Ribas", "a lancha do Ribas", "a embarcação do Ribas", "a moto aquática do Ribas", "o jet ski do Ribas", "o veículo do Ribas"]) {
    const r = escolherBarco(termo, BARCOS);
    assertEquals(r.ok && r.barco.id, "7", termo);
  }
  // "motorhome" sozinho continua sendo o termo: há unidades chamadas assim (pergunta qual).
  assertEquals(escolherBarco("motorhome", BARCOS).ok, false);
  assertEquals(notaDoBarco("o motorhome do Sandro", BARCOS[4]), 60);
});

Deno.test("as recusas não dizem 'barco' (o assistente repassa ao dono)", () => {
  const nada = escolherBarco("Titanic", BARCOS);
  assertEquals(!nada.ok && nada.erro, 'Não achei embarcação ou veículo com "Titanic".');
  const dois = escolherBarco("motorhome", BARCOS);
  assertEquals(!dois.ok && dois.erro, 'Há 2 embarcações ou veículos que batem com "motorhome". Pergunte qual.');
});

Deno.test("dono com dois barcos: pergunta", () => {
  const r = escolherBarco("Edson Luiz Rudek Junior", BARCOS);
  assertEquals(r.ok, false);
  assertEquals(!r.ok && r.opcoes?.map((o) => o.id).sort(), ["3", "4"]);
});

Deno.test("nome genérico repetido: pergunta", () => {
  const r = escolherBarco("motorhome", BARCOS);
  assertEquals(r.ok, false);
  assertEquals(!r.ok && r.opcoes?.length, 2);
});

Deno.test("Acrisio: o barco dele não empata com o do Juliano Acrisio", () => {
  // 'Acrisio' é palavra do nome dos DOIS donos: nota igual → pergunta (nome parecido não decide).
  const r = escolherBarco("Acrisio", BARCOS);
  assertEquals(r.ok, false);
});

Deno.test("nada parecido: erro claro, sem chute", () => {
  const r = escolherBarco("Titanic", BARCOS);
  assertEquals(r.ok, false);
  assertEquals(notaDoBarco("Titanic", BARCOS[0]), 0);
});

Deno.test("nome que começa pelo tipo: o nome exato ganha de um parecido (22/10/2026)", () => {
  const darlan: Candidato = { id: "t1", nome: "Trailer Darlan", cliente: "João Silva" };
  const darlanII: Candidato = { id: "t2", nome: "Darlan II", cliente: "Pedro Souza" };
  assertEquals(notaDoBarco("Trailer Darlan", darlan), 100);
  const e = escolherBarco("Trailer Darlan", [darlan, darlanII]);
  assertEquals(e.ok && e.barco.id, "t1");
  // E "o trailer do Darlan" ainda acha pelo nome sem o tipo.
  assert(notaDoBarco("o trailer do Darlan", darlan) >= 70);
});
