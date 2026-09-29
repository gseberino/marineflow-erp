// Run: deno test supabase/functions/_shared/arquivo-privado_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { caminhoNoBucket, linkExterno } from "./arquivo-privado.ts";

const base = "https://okurngvcodmljjicopdp.supabase.co/storage/v1/object";

Deno.test("caminho novo passa como está (sem barra inicial)", () => {
  assertEquals(caminhoNoBucket("abc/1727.png", "signatures"), "abc/1727.png");
  assertEquals(caminhoNoBucket("/abc/1727.png", "signatures"), "abc/1727.png");
});

Deno.test("link público antigo vira caminho", () => {
  assertEquals(caminhoNoBucket(`${base}/public/signatures/abc/1727.png`, "signatures"), "abc/1727.png");
  assertEquals(caminhoNoBucket(`${base}/public/expense-receipts/expenses/os1/x.pdf`, "expense-receipts"), "expenses/os1/x.pdf");
});

Deno.test("link assinado antigo vira caminho (sem o token)", () => {
  assertEquals(caminhoNoBucket(`${base}/sign/signatures/abc/signed-1.pdf?token=eyJ`, "signatures"), "abc/signed-1.pdf");
});

Deno.test("link de outro bucket ou de fora não vira caminho deste bucket", () => {
  assertEquals(caminhoNoBucket(`${base}/public/documents/x.pdf`, "signatures"), null);
  assertEquals(caminhoNoBucket("https://exemplo.com/recibo.jpg", "expense-receipts"), null);
  assertEquals(caminhoNoBucket("", "signatures"), null);
  assertEquals(caminhoNoBucket(null, "signatures"), null);
});

Deno.test("linkExterno só reconhece link de fora do nosso Storage", () => {
  assertEquals(linkExterno("https://exemplo.com/recibo.jpg"), "https://exemplo.com/recibo.jpg");
  assertEquals(linkExterno(`${base}/public/signatures/a.png`), null);
  assertEquals(linkExterno("abc/1.png"), null);
});
