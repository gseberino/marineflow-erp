import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { avisoDoLeadDoSite, faltaPedir, lerMensagemDoSite } from "./lead-do-site.ts";

// Mensagem exatamente como o formulário do site monta (hbr-site/src/pages/orcamento.astro).
const COMPLETA = [
  "Olá, sou Carlos Souza e vim pelo site da HBR Systems.",
  "Tipo: Embarcação",
  "Modelo: Fibrafort 275",
  "Local: Marina Itajaí",
  "Serviço: Energia: lítio, solar e Victron",
  "Detalhes: Quero trocar as baterias por lítio",
].join("\n");

Deno.test("mensagem completa do site → todos os campos", () => {
  const d = lerMensagemDoSite(COMPLETA)!;
  assertEquals(d.nome, "Carlos Souza");
  assertEquals(d.tipo, "Embarcação");
  assertEquals(d.modelo, "Fibrafort 275");
  assertEquals(d.local, "Marina Itajaí");
  assertEquals(d.servico, "Energia: lítio, solar e Victron");
  assertEquals(d.detalhes, "Quero trocar as baterias por lítio");
});

Deno.test("mensagem mínima (só tipo e nome) e 'quero orientação' → serviço vazio", () => {
  const d = lerMensagemDoSite("Olá, sou Ana e vim pelo site da HBR Systems.\nTipo: Motorhome / trailer\nServiço: quero orientação")!;
  assertEquals(d.nome, "Ana");
  assertEquals(d.tipo, "Motorhome / trailer");
  assertEquals(d.modelo, null);
  assertEquals(d.servico, null);
  assertEquals(faltaPedir(d), ["modelo e ano", "cidade ou marina", "o que precisa resolver", "fotos do painel, das baterias e do porão ou bagageiro"]);
});

Deno.test("estaleiro pede volume de produção em vez de ano", () => {
  const d = lerMensagemDoSite("Olá, sou Pedro e vim pelo site da HBR Systems.\nTipo: Estaleiro / fábrica\nServiço: quero orientação")!;
  assertEquals(faltaPedir(d)[0], "modelo e volume de produção");
});

Deno.test("botão do WhatsApp do site (só a frase) também conta como site", () => {
  const d = lerMensagemDoSite("Olá, vim pelo site da HBR Systems.")!;
  assertEquals(d.nome, null);
  assertEquals(d.tipo, null);
});

Deno.test("mensagem comum não é do site", () => {
  assertEquals(lerMensagemDoSite("Bom dia, quanto custa uma revisão elétrica?"), null);
  assertEquals(lerMensagemDoSite(""), null);
  assertEquals(lerMensagemDoSite(null), null);
});

Deno.test("aviso ao dono traz os dados e o que falta, sem campos vazios", () => {
  const d = lerMensagemDoSite(COMPLETA)!;
  const t = avisoDoLeadDoSite(d, "5547999990000", false);
  assertStringIncludes(t, "Contato novo pelo site");
  assertStringIncludes(t, "Carlos Souza (+5547999990000)");
  assertStringIncludes(t, "Modelo: Fibrafort 275");
  assertStringIncludes(t, "Falta pedir: fotos do painel");
  assertEquals(t.includes("undefined") || t.includes("null"), false);
  assertStringIncludes(avisoDoLeadDoSite(d, "5547999990000", true), "já é cliente cadastrado");
});
