// Vigia de conversas (15/10/2026): pelo texto da fonte (importar index.ts subiria o servidor da
// função). O que se protege: o estado da conversa traz a marca "o contato encerrou", julgada pelas
// últimas recebidas DENTRO da janela (7 dias, nunca antes do acompanhamento nascer) — sem isso o
// acompanhamento do Miguel seguiu avisando o dono por três dias depois de ele fechar com outra.
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("estadoDaConversa lê as últimas recebidas e marca encerrouPeloContato pela janela", () => {
  const ini = fonte.indexOf("async function estadoDaConversa(");
  assert(ini > 0);
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  assertStringIncludes(fn, ".limit(ULTIMAS_RECEBIDAS)");
  assertStringIncludes(fn, "janelaDoEncerramento(a, agora)");
  assertStringIncludes(fn, "encerrouPeloContato: conversaEncerradaPeloContato(");
  assertStringIncludes(fonte, "await estadoDaConversa(admin, a, agora)");
});
