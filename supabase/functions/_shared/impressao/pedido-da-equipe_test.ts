// O pedido do técnico pelo WhatsApp (17/11/2026): o que é pedido de impressão e o que segue como sempre.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { lerPedidoDaEquipe, pedidoDeImpressaoDaEquipe, TIPOS_DA_EQUIPE_NA_IMPRESSAO } from "./pedido-da-equipe.ts";
import { TIPOS_DA_EQUIPE } from "../ai/tools/via-do-tecnico.ts";
import { bancoFalso } from "./banco-falso-de-teste.ts";

Deno.test("lerPedidoDaEquipe: os pedidos", () => {
  assertEquals(lerPedidoDaEquipe("imprime minha via"), { documento: null });
  assertEquals(lerPedidoDaEquipe("Imprimir a via, por favor"), { documento: null });
  assertEquals(lerPedidoDaEquipe("pode imprimir a OS 136?"), { documento: "136" });
  assertEquals(lerPedidoDaEquipe("imprime a OS-00136"), { documento: "136" });
  assertEquals(lerPedidoDaEquipe("impressão da 87"), { documento: "87" });
});

Deno.test("lerPedidoDaEquipe: o que NÃO é pedido segue como sempre (a agenda lê)", () => {
  for (const t of ["ok", "sim", "chego às 8", "não precisa imprimir", "já imprimi", "imprime a 136 e a 137", "", null]) {
    assertEquals(lerPedidoDaEquipe(t as string), null, String(t));
  }
  assertEquals(lerPedidoDaEquipe(`imprime ${"a".repeat(130)}`), null);
});

Deno.test("a lista da equipe é a mesma da via do técnico", () => {
  assertEquals([...TIPOS_DA_EQUIPE_NA_IMPRESSAO], [...TIPOS_DA_EQUIPE]);
});

Deno.test("pedidoDeImpressaoDaEquipe: número de fora da equipe não é consumido (segue como sempre)", async () => {
  const { admin } = bancoFalso((c) => (c.tabela === "payees" ? { data: [{ id: "p1", name: "Alex", phone: "(47) 99999-1111" }] } : { data: [] }));
  let noFundo = 0;
  const r = await pedidoDeImpressaoDaEquipe(admin, { phone: "5547988887777", body: "imprime minha via", noFundo: () => { noFundo++; } });
  assertEquals([r, noFundo], [false, 0]);
});

Deno.test("pedidoDeImpressaoDaEquipe: da equipe = consumido e despachado no fundo; desligado = não", async () => {
  const banco = (desligado: boolean) =>
    bancoFalso((c) => {
      if (c.tabela === "payees") return { data: [{ id: "p1", name: "Alex", phone: "(47) 99999-1111" }] };
      if (c.tabela === "app_settings") return { data: desligado ? [{ key: "impressao_equipe", value: "off" }] : [] };
      return { data: [] };
    }).admin;
  const fundo: Promise<unknown>[] = [];
  const r = await pedidoDeImpressaoDaEquipe(banco(false), { phone: "554799991111", body: "imprime minha via", noFundo: (p) => { fundo.push(p.catch(() => null)); } });
  assertEquals([r, fundo.length], [true, 1]);
  const r2 = await pedidoDeImpressaoDaEquipe(banco(true), { phone: "554799991111", body: "imprime minha via", noFundo: () => {} });
  assertEquals(r2, false);
  // não deixa a promessa do fundo solta no teste (ela tenta o PDF e a resposta; o banco falso responde vazio)
  await Promise.all(fundo);
});
