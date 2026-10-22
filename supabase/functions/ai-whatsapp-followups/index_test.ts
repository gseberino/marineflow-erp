// Mensagens desta função vão a CLIENTE (está no ar). Pedido do dono, 22/10/2026: "para motorhome use
// seu motorhome, para trailer seu trailer e assim por diante" — e nada de barquinho para motorhome.
// Pelo texto da fonte (importar index.ts subiria o servidor), mais a regra única de unidade.ts.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { emojiDaUnidade, suaUnidade } from "../_shared/unidade.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
const mensagens = fonte.split(/\r?\n/).filter((l) => l.includes("const msg = `"));

Deno.test("as duas mensagens ao cliente não têm emoji de barco fixo", () => {
  assertEquals(mensagens.length, 2);
  for (const m of mensagens) {
    assert(!m.includes("🛥"), m);
    assert(!m.includes("⚓"), m);
    assertStringIncludes(m, "${companyName}${emoji}.");
  }
});

Deno.test("o emoji e o possessivo vêm do tipo da unidade da OS", () => {
  assertStringIncludes(fonte, 'select("id, service_order_number, client_id, check_out_at, vessel_id")');
  assertStringIncludes(fonte, "comEspaco(emojiDaUnidade(unidade?.asset_type))");
  assertStringIncludes(fonte, 'const daUnidade = suaUnidade(v, "de", { comNome: true });');
  assertStringIncludes(fonte, "comEspaco(emojiDaUnidade(v?.asset_type))");
  assert(!/da sua embarca/.test(fonte.replace(/\/\/.*$/gm, "")), "texto fixo 'da sua embarcação' voltou");
});

Deno.test("o que o cliente lê, por tipo", () => {
  const reativacao = (u: { name?: string; asset_type?: string | null } | null) =>
    `Faz um tempo que não cuidamos ${suaUnidade(u, "de", { comNome: true })} por aqui.`;
  // Com o nome: cliente com duas lanchas precisa saber qual (revisão de 22/10/2026).
  assertEquals(reativacao({ name: "Iveco Daily", asset_type: "Motorhome" }), "Faz um tempo que não cuidamos do seu motorhome Iveco Daily por aqui.");
  assertEquals(reativacao({ name: "Netuno II", asset_type: "Lancha" }), "Faz um tempo que não cuidamos da sua lancha Netuno II por aqui.");
  assertEquals(reativacao({ name: "Turiscar", asset_type: "Trailer" }), "Faz um tempo que não cuidamos do seu trailer Turiscar por aqui.");
  assertEquals(reativacao({ name: "Motorhome", asset_type: "Motorhome" }), "Faz um tempo que não cuidamos do seu motorhome por aqui.");
  assertEquals(reativacao(null), "Faz um tempo que não cuidamos da sua embarcação ou veículo por aqui.");
  assertEquals(emojiDaUnidade("Motorhome"), "🚐");
  assertEquals(emojiDaUnidade("Lancha"), "🛥️");
  assertEquals(emojiDaUnidade(null), "");
});

Deno.test("reativação só diz 'sua lancha' se a unidade ainda é do cliente (vendida = termo geral)", () => {
  assertStringIncludes(fonte, 'select("name, asset_type, client_id")');
  assertStringIncludes(fonte, "clienteId && v.client_id !== clienteId");
  assertStringIncludes(fonte, "unidadeDaOs(lastVesselByClient.get(cid) ?? null, cid)");
});
