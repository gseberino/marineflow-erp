// Saldos a cobrar (secretário, Passo 4, 15/10/2026): pelo texto da fonte (importar index.ts subiria o
// servidor da função). O que se protege: o registro no portão (sombra) só acontece DEPOIS que o resumo entrou
// na fila, e só quando entrou (queued > 0); a leitura das chaves fica dentro do caso "há saldo a cobrar" (com
// nada a mandar, nada a mais é lido). Desligado: registrarParaTodos recebe modo null e não chama nada
// (registrar_test.ts). (20/10/2026, P4.5) Ligada de verdade: o dono pergunta ao portão ANTES da fila e, com o
// "acaba", sai da lista; o dono só é lido com a voz ligada; a equipe recebe como sempre.
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("o portão (sombra) vem depois da fila e só quando o resumo entrou nela", () => {
  const caso = fonte.indexOf("if (milestoneItems > 0 && users.length > 0 && !dry) {");
  const leitura = fonte.indexOf("const portao = await lerPortao(admin);");
  const fila = fonte.indexOf('await admin.from("whatsapp_send_queue").insert(rows)');
  const se = fonte.indexOf("if (queued > 0) {");
  const registro = fonte.indexOf("await registrarParaTodos(admin, portao.modo");
  assert(caso > 0 && leitura > caso && fila > leitura && se > fila && registro > se, "ordem: há saldo → chaves → fila → queued > 0 → registro");
  assertStringIncludes(fonte, "const aviso = avisoDosSaldos(emBrasilia(now).dia, milestoneItems, message);");
});

Deno.test("P4.5: com a voz ligada, o dono pergunta ao portão ANTES da fila e o 'acaba' o tira da lista", () => {
  const dono = fonte.indexOf('const dono = portao.modo === "ligado" ? await lerDonoDaVoz(admin) : null;');
  const pergunta = fonte.indexOf("const fala = await perguntarAoPortao(admin, String(doPortao.phone_normalized), aviso, now);");
  const tira = fonte.indexOf("if (!fala.manda) destinatarios = users.filter((u: any) => u !== doPortao);");
  const fila = fonte.indexOf('await admin.from("whatsapp_send_queue").insert(rows)');
  assert(dono > 0 && pergunta > dono && tira > pergunta && fila > tira, `ordem: ${dono} ${pergunta} ${tira} ${fila}`);
  assertStringIncludes(fonte, "const doPortao = users.find((u: any) => falaPeloPortao(portao, dono, String(u.phone_normalized)));");
  assertStringIncludes(fonte, "const rows = destinatarios.map((u: any) => ({");
});
