// As chaves do portão e as regras do dono (secretário, Passo 4, 15/10/2026). O que se protege: ausente
// ou estranho = desligado (nada muda); 'ligado' ainda registra como sombra até o P4.5 (senão um guardado
// que ninguém lê seria descartado); o freio ausente = desligado (código antes da migration não muda
// nada); cada regra do dono cai no padrão sozinha quando vem ruim; o pedido ao portão corta os tamanhos.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { lerFreio, lerRegras, lerVozUnica, modoDoRegistro, pedidoAoPortao, REGRAS_PADRAO } from "./portao.ts";

Deno.test("voz_unica: valores aceitos, aspas e caixa; o resto é desligado", () => {
  assertEquals(lerVozUnica("sombra"), "sombra");
  assertEquals(lerVozUnica(" Ligado "), "ligado");
  assertEquals(lerVozUnica('"sombra"'), "sombra");
  for (const v of [undefined, null, "", "on", "off", "true", 1, {}]) assertEquals(lerVozUnica(v), "desligado", String(v));
});

Deno.test("modo do registro: desligado não registra; sombra e ligado registram como sombra (até o P4.5)", () => {
  assertEquals(modoDoRegistro("desligado"), null);
  assertEquals(modoDoRegistro("sombra"), "sombra");
  assertEquals(modoDoRegistro("ligado"), "sombra");
});

Deno.test("freio: ligado/on/true liga; ausente ou qualquer outra coisa desliga", () => {
  assertEquals(lerFreio("ligado"), true);
  assertEquals(lerFreio(" ON "), true);
  assertEquals(lerFreio("true"), true);
  for (const v of [undefined, null, "", "desligado", "off", "false", "sim"]) assertEquals(lerFreio(v), false, String(v));
});

Deno.test("regras: o JSON da migration dá os padrões (D1–D10)", () => {
  const migration = '{"acordes_por_dia":2,"email_sem_golpe":"proxima_fixa","desistencia_acorda_com_orcamento_de":5000,"acompanhar_conta_no_limite":true,"promessa":"proxima_fixa","lead_site":"proxima_fixa","sabado":"domingo","guardado_resolvido":"some","telefone_no_aviso":true,"verificacao_min":15,"freio_avisos":2}';
  assertEquals(lerRegras(migration), { ...REGRAS_PADRAO });
});

Deno.test("regras: ausente, JSON ruim ou array = padrão; campo ruim cai sozinho; números com teto", () => {
  assertEquals(lerRegras(undefined), { ...REGRAS_PADRAO });
  assertEquals(lerRegras("{não é json"), { ...REGRAS_PADRAO });
  assertEquals(lerRegras("[1,2]"), { ...REGRAS_PADRAO });
  const r = lerRegras({ acordes_por_dia: 9, email_sem_golpe: "acorde", promessa: "gritar", sabado: "segunda", freio_avisos: "3", acompanhar_conta_no_limite: "false" });
  assertEquals(r.acordes_por_dia, 5, "teto 5");
  assertEquals(r.email_sem_golpe, "acorde");
  assertEquals(r.promessa, "proxima_fixa", "valor desconhecido = padrão");
  assertEquals(r.sabado, "segunda");
  assertEquals(r.freio_avisos, 3);
  assertEquals(r.acompanhar_conta_no_limite, false);
  assertEquals(r.lead_site, REGRAS_PADRAO.lead_site, "o que não veio fica no padrão");
  assertEquals(lerRegras({ acordes_por_dia: -1 }).acordes_por_dia, 0);
  assertEquals(lerRegras({ acordes_por_dia: "x" }).acordes_por_dia, 2);
});

Deno.test("pedido ao portão: corta chave/assunto em 200 e texto em 4000; agora só quando vem", () => {
  const p = pedidoAoPortao("5547999990001", "sombra", {
    fonte: "email", chave: "k".repeat(300), assunto: "a".repeat(300), destino: "acorde", texto: "t".repeat(5000),
  });
  assertEquals((p.chave as string).length, 200);
  assertEquals((p.assunto as string).length, 200);
  assertEquals((p.texto as string).length, 4000);
  assertEquals(p.novo_fato, false);
  assertEquals(p.dados, {});
  assertEquals("agora" in p, false);
  const q = pedidoAoPortao("5547999990001", "sombra", { fonte: "x_y", chave: "abc", assunto: "abc", destino: "deixar" }, new Date("2026-10-21T13:00:00Z"));
  assertEquals(q.agora, "2026-10-21T13:00:00.000Z");
  assertEquals(q.referencia, null);
});
