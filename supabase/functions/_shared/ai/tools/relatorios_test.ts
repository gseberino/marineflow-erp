import { assertEquals } from "jsr:@std/assert@1";
import { hojeBrasilia, periodoPedido, relatorioTools } from "./relatorios.ts";

const AGORA = new Date("2026-10-06T14:00:00Z"); // 11h em Brasília

Deno.test("periodoPedido: hoje, de/ate, mês e o padrão de cada relatório", () => {
  assertEquals(hojeBrasilia(new Date("2026-10-07T02:00:00Z")), "2026-10-06"); // 23h de 06/10 em Brasília
  assertEquals(periodoPedido({ hoje: true }, "mes", AGORA), { de: "2026-10-06", ate: "2026-10-06", rotulo: "Hoje, 06/10/2026" });
  assertEquals(periodoPedido({ de: "2026-09-01", ate: "2026-09-15" }, "mes", AGORA), { de: "2026-09-01", ate: "2026-09-15", rotulo: "01/09/2026 a 15/09/2026" });
  assertEquals(periodoPedido({ mes: 9, ano: 2026 }, "mes", AGORA), { de: "2026-09-01", ate: "2026-09-30", rotulo: "Setembro de 2026" });
  assertEquals(periodoPedido({}, "mes", AGORA), { de: "2026-10-01", ate: "2026-10-31", rotulo: "Outubro de 2026" });
  assertEquals(periodoPedido({}, "tudo", AGORA), { de: null, ate: null, rotulo: "Desde o início da conta corrente" });
  assertEquals("error" in periodoPedido({ de: "2026-09-10", ate: "2026-09-01" }, "mes", AGORA), true);
  assertEquals("error" in periodoPedido({ de: "10/09/2026" }, "mes", AGORA), true);
});

const tool = (nome: string) => relatorioTools.find((t) => t.name === nome)!;

Deno.test("só administrador e financeiro; técnico é barrado antes de qualquer leitura", async () => {
  for (const nome of ["atualizar_extrato", "enviar_relatorio_pdf"]) {
    assertEquals(tool(nome).roles, ["admin", "financial"]);
    // deno-lint-ignore no-explicit-any
    const r = await tool(nome).execute({ relatorio: "despesas" }, { userRole: "technician", admin: {} as any, sb: {} as any, settings: {}, userId: "u", jwt: "" } as any);
    assertEquals("error" in (r as object), true);
  }
});

Deno.test("enviar_relatorio_pdf: sem WhatsApp no cadastro, diz onde cadastrar e não gera nada", async () => {
  const admin = { from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { phone_normalized: null }, error: null }) }) }) }) };
  // deno-lint-ignore no-explicit-any
  const r = await tool("enviar_relatorio_pdf").execute({ relatorio: "despesas" }, { userRole: "admin", admin, sb: {} as any, settings: {}, userId: "u", jwt: "" } as any) as { error: string };
  assertEquals(r.error.includes("Configurações"), true);
});

Deno.test("nomes que não parecem leitura (senão a rede trataria como consulta e rodaria direto)", () => {
  for (const t of relatorioTools) assertEquals(/^(get_|list_|read_|check_|search_)/.test(t.name), false);
});
