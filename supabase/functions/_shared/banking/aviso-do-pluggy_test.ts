import { assertEquals } from "jsr:@std/assert@1";
import { eventosQueFaltam, itemParaLer, semToken } from "./aviso-do-pluggy.ts";

const URL_DO_AVISO = "https://x.supabase.co/functions/v1/pluggy-webhook?token=segredo";

Deno.test("semToken: tira o token da URL (o que se compara e o que se mostra)", () => {
  assertEquals(semToken(URL_DO_AVISO), "https://x.supabase.co/functions/v1/pluggy-webhook");
});

Deno.test("eventosQueFaltam: cadastra só o que não existe, mesmo que o token tenha mudado", () => {
  assertEquals(eventosQueFaltam([], URL_DO_AVISO), ["item/updated"]);
  assertEquals(eventosQueFaltam([{ id: "1", event: "item/updated", url: "https://x.supabase.co/functions/v1/pluggy-webhook?token=antigo" }], URL_DO_AVISO), []);
  assertEquals(eventosQueFaltam([{ id: "1", event: "all", url: URL_DO_AVISO }], URL_DO_AVISO), []);
  assertEquals(eventosQueFaltam([{ id: "1", event: "item/updated", url: "https://outro.app/hook" }], URL_DO_AVISO), ["item/updated"]);
});

Deno.test("itemParaLer: só item/updated com id válido dispara a leitura", () => {
  const id = "0b7d2f8e-1c9a-4f3e-9a51-6d2e4c7b8a90";
  assertEquals(itemParaLer({ event: "item/updated", itemId: id }), id);
  assertEquals(itemParaLer({ event: "item/error", itemId: id }), null);
  assertEquals(itemParaLer({ event: "transactions/created", itemId: id }), null);
  assertEquals(itemParaLer({ event: "item/updated", itemId: "../x" }), null);
});
