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

// Voz única (secretário, Passo 4, 15/10/2026). O que se protege: o registro no portão vem DEPOIS do
// aviso entrar na fila e só com o modo ligado; o diagnóstico não lê as chaves. Desligado: nada é
// registrado (registrar_test.ts) — o aviso é o mesmo de antes.
Deno.test("voz única: o urgente vai ao portão depois da fila, só com o modo ligado; diagnóstico não lê as chaves", () => {
  const ini = fonte.indexOf("async function avisarUrgente(");
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  const fila = fn.indexOf('await admin.from("whatsapp_send_queue").insert(rows)');
  const registro = fn.indexOf("await registrarParaTodos(");
  assert(fila > 0 && registro > fila, "fila → registro");
  assertStringIncludes(fn, "if (rows.length && voz.portao.modo)");
  assertStringIncludes(fonte, "const portao = diagnostico ? PORTAO_DESLIGADO : await lerPortao(admin);");
  assertStringIncludes(fonte, "{ emailId: id, endereco: normalizeAddress(email.from.address), portao }");
});
