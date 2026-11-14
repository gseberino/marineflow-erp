// Achar a pessoa e a linha pelo que o dono diz ("o Alex", "o inversor", "2").
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { escolherLinha, escolherPessoa, TIPOS_DA_EQUIPE } from "./via-do-tecnico.ts";

const EQUIPE = [
  { id: "1", nome: "Alex Gonçalves Machado", telefone: "5547999990001" },
  { id: "2", nome: "Roberto Daniel Rodrigues Correa", telefone: "" },
  { id: "3", nome: "Gustavo Seberino da Silva", telefone: "5547999990003" },
  { id: "4", nome: "Mickael Fernando Gonzaga", telefone: "5547999990004" },
];

Deno.test("pessoa: primeiro nome, nome inteiro, sem acento, com artigo", () => {
  assertEquals(escolherPessoa("Alex", EQUIPE), { pessoa: EQUIPE[0] });
  assertEquals(escolherPessoa("o alex", EQUIPE), { pessoa: EQUIPE[0] });
  assertEquals(escolherPessoa("pro Roberto", EQUIPE), { pessoa: EQUIPE[1] });
  assertEquals(escolherPessoa("alex goncalves machado", EQUIPE), { pessoa: EQUIPE[0] });
  assertEquals(escolherPessoa("Seberino", EQUIPE), { pessoa: EQUIPE[2] });
  assertEquals(escolherPessoa("Fulano", EQUIPE), null);
  assertEquals(escolherPessoa("", EQUIPE), null);
});

Deno.test("pessoa: dois candidatos = pergunta, nunca escolhe sozinho", () => {
  const dois = [...EQUIPE, { id: "5", nome: "Alex Souza", telefone: "" }];
  assertEquals(escolherPessoa("Alex", dois), { opcoes: ["Alex Gonçalves Machado", "Alex Souza"] });
  // nome inteiro desempata
  assertEquals(escolherPessoa("Alex Souza", dois), { pessoa: dois[4] });
});

Deno.test("linha: pelo número (a ordem da via) ou por parte do nome", () => {
  const linhas = [{ id: "a", nome: "Instalação do inversor" }, { id: "b", nome: "Troca das baterias" }, { id: "c", nome: "Teste do inversor" }];
  assertEquals(escolherLinha("2", linhas), { linha: { id: "b", nome: "Troca das baterias", n: 2 } });
  assertEquals(escolherLinha("linha 1", linhas), { linha: { id: "a", nome: "Instalação do inversor", n: 1 } });
  assertEquals(escolherLinha("baterias", linhas), { linha: { id: "b", nome: "Troca das baterias", n: 2 } });
  assertEquals("erro" in escolherLinha("inversor", linhas), true); // casa com 1 e 3: pede o número
  assertEquals("erro" in escolherLinha("9", linhas), true);
  assertEquals("erro" in escolherLinha("pintura", linhas), true);
});

Deno.test("comissionado não é equipe de campo", () => {
  assertEquals((TIPOS_DA_EQUIPE as readonly string[]).includes("comissionado"), false);
});
