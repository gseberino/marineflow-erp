import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  montarSecaoEmail, selecionarUrgentes, taxaDeRuido, MAX_URGENTES_PADRAO,
  type EmailDigestItem,
} from "./digest.ts";
import type { TriageClass } from "./triage.ts";

function item(classe: TriageClass, over: Partial<EmailDigestItem> = {}): EmailDigestItem {
  return {
    classe, remetente: "Fornecedor X", assunto: "assunto qualquer",
    recebidoEm: "2026-07-27T09:00:00Z", ...over,
  };
}

Deno.test("montarSecaoEmail: sem e-mail nenhum, não polui o briefing", () => {
  assertEquals(montarSecaoEmail([]), null);
});

Deno.test("montarSecaoEmail: só ruído vira UMA linha auditável", () => {
  const s = montarSecaoEmail([item("ignore"), item("ignore"), item("ignore")]);
  assertEquals(s, "📧 E-mail: 3 mensagens, tudo ruído.");
});

Deno.test("montarSecaoEmail: singular e plural corretos", () => {
  assertEquals(montarSecaoEmail([item("ignore")]), "📧 E-mail: 1 mensagem, tudo ruído.");
});

Deno.test("montarSecaoEmail: mostra quem espera resposta", () => {
  const s = montarSecaoEmail([
    item("respond", { remetente: "Marina Itajaí", assunto: "prazo do motor" }),
    item("ignore"),
  ])!;
  assert(s.includes("Esperando resposta"));
  assert(s.includes("Marina Itajaí"));
  assert(s.includes("prazo do motor"));
  assert(s.includes("1 filtrado"));
});

Deno.test("montarSecaoEmail: 'informativo' vira número, não vira lista", () => {
  const itens = Array.from({ length: 12 }, (_, i) => item("notify", { remetente: `Banco ${i}` }));
  const s = montarSecaoEmail([...itens, item("respond")])!;
  assert(s.includes("12 informativos"));
  assertEquals(s.includes("Banco 5"), false, "notify não pode virar 12 linhas no briefing");
});

Deno.test("montarSecaoEmail: corta por categoria e mostra o excedente como contagem", () => {
  const itens = Array.from({ length: 7 }, (_, i) =>
    item("respond", { remetente: `Cliente ${i}` }));
  const s = montarSecaoEmail(itens, { maxPorCategoria: 3 })!;
  assert(s.includes("Cliente 0"));
  assert(s.includes("(+4)"));
  assertEquals(s.includes("Cliente 6"), false);
});

Deno.test("montarSecaoEmail: teto de urgentes é respeitado e o resto é contado", () => {
  const itens = Array.from({ length: 6 }, (_, i) =>
    item("urgent", { remetente: `Caso ${i}`, recebidoEm: `2026-07-27T0${i}:00:00Z` }));
  const s = montarSecaoEmail(itens)!;
  const linhasUrgentes = s.split("\n").filter((l) => l.startsWith("· Caso"));
  assertEquals(linhasUrgentes.length, MAX_URGENTES_PADRAO);
  assert(s.includes("(+3 outros urgentes"));
});

Deno.test("montarSecaoEmail: suspeita de fraude vem com instrução explícita", () => {
  const s = montarSecaoEmail([
    item("urgent", { remetente: "Fornecedor Y", assunto: "mudança de conta", alertaFraude: true }),
  ])!;
  assert(s.includes("⚠️"));
  assert(s.includes("confirme por telefone"));
});

Deno.test("montarSecaoEmail: anexo reconhecido aparece na linha", () => {
  const s = montarSecaoEmail([
    item("document", { remetente: "Náutica Sul", resumoAnexo: "NF 4471 de R$ 1.234,56" }),
  ])!;
  assert(s.includes("Documentos recebidos"));
  assert(s.includes("NF 4471 de R$ 1.234,56"));
});

Deno.test("montarSecaoEmail: assunto vazio não gera aspas vazias", () => {
  const s = montarSecaoEmail([item("respond", { assunto: null })])!;
  assert(s.includes("(sem assunto)"));
});

Deno.test("montarSecaoEmail: assunto gigante é truncado", () => {
  const s = montarSecaoEmail([item("respond", { assunto: "x".repeat(300) })])!;
  assert(s.length < 200, `esperado truncado, veio ${s.length}`);
});

Deno.test("selecionarUrgentes: fraude vem antes, depois o mais recente", () => {
  const sel = selecionarUrgentes([
    item("urgent", { remetente: "A", recebidoEm: "2026-07-27T10:00:00Z" }),
    item("urgent", { remetente: "B", recebidoEm: "2026-07-27T08:00:00Z", alertaFraude: true }),
    item("urgent", { remetente: "C", recebidoEm: "2026-07-27T11:00:00Z" }),
  ]);
  assertEquals(sel.map((i) => i.remetente), ["B", "C", "A"]);
});

Deno.test("selecionarUrgentes: teto zero não deixa passar nada", () => {
  assertEquals(selecionarUrgentes([item("urgent")], 0).length, 0);
});

Deno.test("taxaDeRuido: mede quanto foi escondido — é o gate do §8", () => {
  assertEquals(taxaDeRuido([]), 0);
  assertEquals(taxaDeRuido([item("ignore"), item("ignore"), item("respond"), item("notify")]), 0.5);
  assertEquals(taxaDeRuido([item("respond")]), 0);
});
