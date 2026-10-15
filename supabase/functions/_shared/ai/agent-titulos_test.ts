// O título do cartão de confirmação é o que o dono lê antes do "sim" (15/10/2026). Tool que pede
// confirmação sem entrada em TOOL_LABELS_PT caía no nome técnico humanizado — em produção, desde
// 15/09: "Duplicate Service Order", "Create Purchase Order", "Cadastrar Favorecido".
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { humanizeToolName, tituloDaAcao } from "./agent.ts";
import { allTools } from "./tools/index.ts";
import { rodaDiretoPelaRede, SO_PELA_REDE } from "./perfil-operacao.ts";

Deno.test("toda tool que pode pedir confirmação tem título em português", () => {
  const semTitulo = allTools
    .filter((t) => t.risk !== "low" || !!t.computeRisk || (SO_PELA_REDE.has(t.name) && !rodaDiretoPelaRede(t)))
    .map((t) => t.name)
    .filter((n) => tituloDaAcao(n) === humanizeToolName(n));
  assertEquals(semTitulo, []);
});

Deno.test("os títulos que saíram em inglês em produção", () => {
  assertEquals(tituloDaAcao("duplicate_service_order"), "Duplicar orçamento/OS");
  assertEquals(tituloDaAcao("create_purchase_order"), "Criar ordem de compra");
  assertEquals(tituloDaAcao("cadastrar_favorecido"), "Cadastrar favorecido");
  assertEquals(tituloDaAcao("emit_fiscal_note"), "Emitir NF-e");
});
