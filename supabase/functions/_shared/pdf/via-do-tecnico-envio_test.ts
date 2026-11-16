// Por que a via de uma pessoa não vai (revisão da F1, consumidores-2): desde a F1, semServicoDaPessoa também vale quando a
// parte dela é só cobrança (frete, deslocamento — fora do papel, 4A). O cartão do SIM, o envio e a agenda diziam
// "todos os serviços estão com outra pessoa", o que é falso nesse caso. A decisão de pular não muda. Dado sintético.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { mandarVia } from "./via-do-tecnico-envio.ts";
import { motivoSemPapelDaPessoa } from "./via-do-tecnico-dados.ts";
import type { DadosDaVia } from "./via-do-tecnico.ts";

const ALEX = { id: "p-alex", nome: "Alex Sintético" };
const BETO = { id: "p-beto", nome: "Beto Sintético" };

/** O Beto é responsável só pela linha de deslocamento; o serviço é do Alex. */
function dados(): DadosDaVia {
  return {
    serviceOrderId: "os1",
    header: { orderNumber: "OS-00950", status: "scheduled" },
    empresa: {},
    linhas: [
      { id: "l1", created_at: "2026-11-16T18:00:00.001+00:00", name_snapshot: "Instalação do inversor", responsavel_payee_id: ALEX.id },
      { id: "l2", created_at: "2026-11-16T18:00:00.002+00:00", name_snapshot: "Deslocamento técnico", responsavel_payee_id: BETO.id },
    ],
    passos: [],
    materiais: [],
    levantamento: [],
    nomesDosResponsaveis: { [ALEX.id]: ALEX.nome, [BETO.id]: BETO.nome },
  };
}

Deno.test("o motivo vale nos dois casos: serviços com outra pessoa ou só cobrança", () => {
  assertEquals(motivoSemPapelDaPessoa(), "nada desta OS vai ao papel dele (serviços com outra pessoa ou só cobrança)");
  assertEquals(motivoSemPapelDaPessoa("da OS-00950"), "nada da OS-00950 vai ao papel dele (serviços com outra pessoa ou só cobrança)");
});

Deno.test("envio: o Beto só com o deslocamento não recebe, e o motivo é verdadeiro; nada é enviado", async () => {
  let enviados = 0;
  const r = await mandarVia({
    admin: null,
    settings: {},
    jwt: "",
    dados: dados(),
    ordem: { id: "os1", numero: "OS-00950", status: "scheduled", shareToken: "token-sintetico", cliente: "Cliente Sintético", unidade: null },
    pessoa: BETO,
    telefone: "47999990000",
    contexto: "teste",
    chave: (impressao) => impressao,
    enviar: () => { enviados++; return Promise.resolve({ ok: true }); },
    linksDasFotos: {},
  });
  assertEquals(r, { ok: false, pulado: true, motivo: "nada da OS-00950 vai ao papel dele (serviços com outra pessoa ou só cobrança)" });
  assertEquals(enviados, 0);
});

Deno.test("o cartão do SIM, o envio e a agenda usam o mesmo motivo — nunca 'todos os serviços … estão com outra pessoa'", async () => {
  for (const arquivo of ["../ai/tools/via-do-tecnico.ts", "./via-do-tecnico-envio.ts", "../../task-automations/via-da-agenda.ts"]) {
    const codigo = await Deno.readTextFile(new URL(arquivo, import.meta.url));
    assert(!/estão com outra pessoa/.test(codigo), `${arquivo} ainda diz "estão com outra pessoa"`);
    assertStringIncludes(codigo, "motivoSemPapelDaPessoa(", arquivo);
  }
});
