// E-mail urgente avisado UMA vez (15/10/2026). O mesmo golpe ("CONTRATO 20037247643 - Advocacia
// Antonio Samuel da Silveira", do mesmo remetente) chegou em 13/10 e 14/10 e foi avisado na hora
// duas vezes. Pelo texto da fonte (importar index.ts subiria o servidor da função).
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("antes de avisar o urgente, procura aviso do mesmo remetente e assunto nos últimos 30 dias", () => {
  const ini = fonte.indexOf('if (recente && t.classe === "urgent"');
  assert(ini > 0, "bloco do aviso de urgente");
  const bloco = fonte.slice(ini, fonte.indexOf("cursor = uid;", ini));
  const consulta = bloco.indexOf("await jaAvisadoAntes(");
  assert(consulta > 0, "o bloco consulta aviso anterior");
  assert(consulta < bloco.indexOf("await avisarUrgente("), "a consulta vem antes do aviso");
  assertStringIncludes(bloco, "if (!repetido)");
});

Deno.test("a consulta compara remetente e assunto como foram gravados e olha alerted_at de 30 dias", () => {
  const ini = fonte.indexOf("async function jaAvisadoAntes(");
  assert(ini > 0);
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  assertStringIncludes(fn, '.eq("from_address", normalizeAddress(endereco))');
  assertStringIncludes(fn, '.gte("alerted_at"');
  assertStringIncludes(fn, "30 * 86400_000");
  assertStringIncludes(fn, '.is("subject", null)');
  // Erro na leitura não cala um urgente: avisa (repetir é melhor que perder um golpe novo).
  assertStringIncludes(fn, "return false;");
});
