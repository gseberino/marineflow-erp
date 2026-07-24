import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { produtoFiscalCompleto, produtoFiscalPendencias } from "./product-fiscal.ts";

Deno.test("completo: NCM 8 díg + CFOP 4 díg com fiscal global", () => {
  const p = { ncm: "8501.10.19", cfop: "5102", use_global_fiscal: true };
  assertEquals(produtoFiscalPendencias(p), []);
  assertEquals(produtoFiscalCompleto(p), true);
});

Deno.test("pendente: sem NCM", () => {
  const p = { ncm: null, cfop: "5102", use_global_fiscal: true };
  assertEquals(produtoFiscalPendencias(p), ["NCM (8 dígitos)"]);
  assertEquals(produtoFiscalCompleto(p), false);
});

Deno.test("pendente: NCM incompleto (menos de 8 díg)", () => {
  assertEquals(produtoFiscalCompleto({ ncm: "8501", cfop: "5102", use_global_fiscal: true }), false);
});

Deno.test("pendente: CFOP inválido", () => {
  assertEquals(produtoFiscalPendencias({ ncm: "85011019", cfop: "51", use_global_fiscal: true }), ["CFOP (4 dígitos)"]);
});

Deno.test("sem fiscal global exige CSOSN e origem próprios", () => {
  const semNada = { ncm: "85011019", cfop: "5102", use_global_fiscal: false, csosn: null, fiscal_origin: null };
  assertEquals(produtoFiscalPendencias(semNada), ["CSOSN", "origem"]);
  const completo = { ncm: "85011019", cfop: "5102", use_global_fiscal: false, csosn: "102", fiscal_origin: 0 };
  assertEquals(produtoFiscalCompleto(completo), true);
});

Deno.test("origem 0 (nacional) conta como preenchida", () => {
  const p = { ncm: "85011019", cfop: "5102", use_global_fiscal: false, csosn: "400", fiscal_origin: 0 };
  assertEquals(produtoFiscalCompleto(p), true);
});
