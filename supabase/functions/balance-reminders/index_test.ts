// Saldos a cobrar (secretário, Passo 4, 15/10/2026): pelo texto da fonte (importar index.ts subiria o
// servidor da função). O que se protege: o registro no portão só acontece DEPOIS que o resumo entrou na
// fila, e só quando entrou (queued > 0); a leitura das chaves fica dentro desse caso (com nada a mandar,
// nada a mais é lido). Desligado: registrarParaTodos recebe modo null e não chama nada (registrar_test.ts).
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("o portão vem depois da fila e só quando o resumo entrou nela", () => {
  const fila = fonte.indexOf('await admin.from("whatsapp_send_queue").insert(rows)');
  const se = fonte.indexOf("if (queued > 0) {");
  const leitura = fonte.indexOf("await lerPortao(admin)");
  const registro = fonte.indexOf("await registrarParaTodos(admin, portao.modo");
  assert(fila > 0 && se > fila && leitura > se && registro > leitura, "ordem: fila → queued > 0 → chaves → registro");
  assertStringIncludes(fonte, "avisoDosSaldos(emBrasilia(now).dia, milestoneItems, message)");
});
