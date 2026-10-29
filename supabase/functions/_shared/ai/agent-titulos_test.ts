// O título do cartão de confirmação é o que o dono lê antes do "sim" (15/10/2026). Tool que pede
// confirmação sem entrada em TOOL_LABELS_PT caía no nome técnico humanizado — em produção, desde
// 15/09: "Duplicate Service Order", "Create Purchase Order", "Cadastrar Favorecido".
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { campoTemRotulo, formatFieldValue, humanizeToolName, rotuloDoCampo, tituloDaAcao } from "./agent.ts";
import { allTools } from "./tools/index.ts";
import { ehLeituraPeloNome, PERFIL_ADMIN, rodaDiretoPelaRede, SO_PELA_REDE } from "./perfil-operacao.ts";

/**
 * Pode virar cartão de "sim": risco acima de low, risco por argumento, rede de segurança (SO_PELA_REDE) e — desde o
 * perfil enxuto do admin (05/10/2026) — toda escrita do admin fora do PERFIL_ADMIN, que chega pela ferramenta_extra e
 * sobe para medium (agent.ts, effectiveRisk). Esta última parte faltava: foi assim que o cartão de 28/10 saiu
 * "*Create Service* / - Name / - Billing Unit / - Default Price".
 */
const podeVirarCartao = (t: (typeof allTools)[number]) =>
  t.risk !== "low" || !!t.computeRisk || (SO_PELA_REDE.has(t.name) && !rodaDiretoPelaRede(t)) ||
  ((!t.roles || t.roles.includes("admin")) && !PERFIL_ADMIN.has(t.name) && !rodaDiretoPelaRede(t));

Deno.test("toda tool que pode pedir confirmação tem título em português", () => {
  const semTitulo = allTools
    .filter((t) => t.risk !== "low" || !!t.computeRisk || (SO_PELA_REDE.has(t.name) && !rodaDiretoPelaRede(t)))
    .map((t) => t.name)
    .filter((n) => tituloDaAcao(n) === humanizeToolName(n));
  assertEquals(semTitulo, []);
});

Deno.test("aprovação em lote: toda ação que a rede do admin enxuto transforma em cartão tem título em português", () => {
  const semTitulo = allTools.filter(podeVirarCartao).map((t) => t.name).filter((n) => tituloDaAcao(n) === humanizeToolName(n));
  assertEquals(semTitulo, []);
});

Deno.test("aprovação em lote: toda escrita que roda direto tem título em português (é o que o 'Conferido pelo sistema' mostra)", () => {
  const semTitulo = allTools.filter((t) => !ehLeituraPeloNome(t.name)).map((t) => t.name)
    .filter((n) => tituloDaAcao(n) === humanizeToolName(n));
  assertEquals(semTitulo, []);
});

Deno.test("aprovação em lote: todo campo das ações que podem virar cartão tem rótulo em português", () => {
  const semRotulo: string[] = [];
  for (const t of allTools.filter(podeVirarCartao)) {
    for (const campo of Object.keys((t.input_schema as { properties?: Record<string, unknown> }).properties ?? {})) {
      if (!campoTemRotulo(campo)) semRotulo.push(`${t.name}.${campo}`);
    }
  }
  assertEquals(semRotulo, []);
});

Deno.test("aprovação em lote: o cartão real de 28/10 (create_service) sai em português, com R$ e 'por unidade'", () => {
  assertEquals(tituloDaAcao("create_service"), "Cadastrar serviço");
  // payload real da pendência de 28/10 18:54 (ai_operator_pending_actions)
  const payload = { billing_unit: "unit", default_price: 1135, name: "Realocação do banco de baterias" };
  // o Intl separa "R$" do número com espaço fixo (U+00A0)
  const linhas = Object.entries(payload).map(([k, v]) => `- ${rotuloDoCampo(k)}: ${formatFieldValue(k, v)}`.replace(/ /g, " "));
  assertEquals(linhas, ["- Cobrança: por unidade", "- Preço: R$ 1.135,00", "- Nome: Realocação do banco de baterias"]);
  assertEquals(formatFieldValue("billable", true), "sim");
  assertEquals(formatFieldValue("ativo", false), "não");
  assertEquals(formatFieldValue("percentual_comissao", 10), "10%");
});

Deno.test("os títulos que saíram em inglês em produção", () => {
  assertEquals(tituloDaAcao("duplicate_service_order"), "Duplicar orçamento/OS");
  assertEquals(tituloDaAcao("create_purchase_order"), "Criar ordem de compra");
  assertEquals(tituloDaAcao("cadastrar_favorecido"), "Cadastrar favorecido");
  assertEquals(tituloDaAcao("emit_fiscal_note"), "Emitir NF-e");
});

Deno.test("agenda de produção (Fase 2): os títulos das quatro ferramentas novas em português", () => {
  assertEquals(tituloDaAcao("agenda_propor"), "Montar a agenda");
  assertEquals(tituloDaAcao("agenda_aplicar"), "Publicar na agenda");
  assertEquals(tituloDaAcao("agenda_desfazer"), "Desfazer na agenda");
  assertEquals(tituloDaAcao("os_registrar_andamento"), "Andamento da OS");
  // fora do perfil enxuto do admin, "marca o Lenine pra quinta" chega pela rede como cartão de "sim"
  assertEquals(tituloDaAcao("schedule_service_order"), "Agendar OS");
});
