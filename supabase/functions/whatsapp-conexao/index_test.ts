// Vigia da conexão (secretário, Passo 4, 15/10/2026): pelo texto da fonte (importar index.ts subiria o
// servidor da função). O que se protege: o registro da volta do WhatsApp no portão só existe no aviso
// "voltou", depois do sino, dentro de um try (nunca derruba o vigia), e só com a voz única ligada.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("a volta do WhatsApp vai ao portão depois do sino, protegida, só com o modo ligado", () => {
  const ini = fonte.indexOf("async function vigiar(");
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  const sino = fn.indexOf('from("app_notifications").insert(linhas)');
  const bloco = fn.indexOf('if (aviso === "voltou" && anterior?.desde)');
  assert(sino > 0 && bloco > sino, "o registro vem depois do sino");
  const resto = fn.slice(bloco);
  assert(resto.indexOf("try {") < resto.indexOf("await lerPortao(db)"), "dentro do try");
  assertStringIncludes(resto, "if (portao.modo)");
  // (16/10/2026) com o texto do acorde de sistema; (pacote 1, V1) e a causa da queda, quando o vigia do assistente a gravou
  assertStringIncludes(resto, "const doPortao = textoDoSistema({ desde: anterior.desde, ate, manhaNaoChegou: quedaDerrubouAManha(anterior.desde, ate), causa: causaDaQueda });");
  assertStringIncludes(resto, "avisoDaVoltaDoWhatsApp({ desde: anterior.desde, ate }, doPortao)");
  assert(fn.indexOf("await lerPortao(db)") > bloco, "a leitura das chaves só acontece na volta");
});

// (20/10/2026, P4.5) Voz única LIGADA de verdade: só o dono pergunta ao portão; se acordar, o texto do acorde de sistema
// vai pela fila (chave aviso:<id>, até as 20h); guardado/acabou não saem; portão ilegível = como sempre (só o sino). A
// sombra continua registrando todos os admins com o canal (e só ela).
Deno.test("P4.5: a volta acorda o dono pela fila só se o portão acordar; a sombra registra como antes", () => {
  const ini = fonte.indexOf("async function vigiar(");
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  const resto = fn.slice(fn.indexOf('if (aviso === "voltou" && anterior?.desde)'));
  const ligado = resto.indexOf('if (portao.modo === "ligado") {');
  const pergunta = resto.indexOf("const fala = dono ? await perguntarAoPortao(db, dono.phone, avisoDaVolta, agora) : null;");
  const fila = resto.indexOf('await enfileirarAcorde(db, { phone: dono.phone, texto: doPortao, avisoId: fala.acordou, agora, source: "whatsapp_voltou" });');
  const sombra = resto.indexOf("} else if (portao.modo) {");
  assert(ligado > 0 && pergunta > ligado && fila > pergunta && sombra > fila, `ordem: ${ligado} ${pergunta} ${fila} ${sombra}`);
  assertStringIncludes(resto, "if (dono && fala?.acordou) {");
  assertStringIncludes(resto.slice(sombra), "await registrarParaTodos(db, portao.modo,");
});

// Pacote 1, V1 (25/11/2026): o vigia do assistente mora na mesma rodada. O que se protege: ele NUNCA derruba o vigia da
// conexão. As leituras novas de antes da decisão não lançam (olharDoVigia, provado em vigia-do-assistente_test.ts); o
// histórico e o aviso só rodam DEPOIS de o vigia da conexão ter avisado e gravado, dentro de um try, com o erro anotado;
// com a chave "desligado" (ou ausente) nada novo roda; e o que muda texto só vale com a chave "ligado".
function oVigiar(): string {
  // o arquivo pode estar com fim de linha do Windows na pasta: compara-se sempre com "\n"
  const texto = fonte.replace(/\r\n/g, "\n");
  const ini = texto.indexOf("async function vigiar(");
  return texto.slice(ini, texto.indexOf("servirComCors(", ini));
}

Deno.test("V1: a rodada do assistente vem depois do upsert do vigia da conexão, dentro de try, com o erro anotado", () => {
  const fn = oVigiar();
  const upsert = fn.indexOf('await db.from("whatsapp_conexao_vigia").upsert(');
  const gravou = fn.indexOf("if (error) throw new Error(`gravar vigia: ${error.message}`);");
  const guarda = fn.indexOf('if (olhar.modo !== "desligado") {');
  const rodada = fn.indexOf("assistente = await rodadaDoVigia(db, { modo: olhar.modo, pc: olhar.pc, aviso, registro, agora });");
  assert(upsert > 0 && gravou > upsert && guarda > gravou && rodada > guarda, `ordem: ${upsert} ${gravou} ${guarda} ${rodada}`);
  const bloco = fn.slice(guarda);
  assert(bloco.indexOf("try {") < bloco.indexOf("await rodadaDoVigia("), "dentro do try");
  assertStringIncludes(bloco, '} catch (e) {\n      await logEdgeError(db, { context: "whatsapp-conexao", action: "vigiar_assistente",');
  assertEquals(fn.split("rodadaDoVigia(").length - 1, 1, "uma chamada só, e ela é a guardada");
  // o sino da queda do WhatsApp e o registro da volta no portão continuam ANTES (a parte de hoje não espera a nova)
  assert(fn.indexOf('from("app_notifications").insert(linhas)') < upsert && fn.indexOf('if (aviso === "voltou" && anterior?.desde)') < upsert);
  // a resposta de sempre, com o resumo novo só quando ele existe
  assertStringIncludes(fn, "return jr({ ok: true, estado, aviso, ...(assistente ? { assistente } : {}) });");
});

Deno.test("V1: antes da decisão do vigia da conexão só entra a leitura que não lança; nada mais foi mexido na decisão", () => {
  const fn = oVigiar();
  const olhar = fn.indexOf("const olhar = await olharDoVigia(db, agora);");
  const decisao = fn.indexOf("const { registro, aviso } = decidirVigia(");
  assert(olhar > 0 && decisao > olhar, "a leitura vem antes da decisão");
  assertEquals(fn.split("olharDoVigia(").length - 1, 1);
  // a decisão do vigia da conexão não recebe nada do vigia novo
  const chamada = fn.slice(decisao, fn.indexOf(");", decisao));
  assert(!chamada.includes("olhar"), "decidirVigia não depende do vigia do assistente");
  // a leitura do estado anterior e a gravação de sempre continuam lançando como antes (o cron vê o erro)
  assertStringIncludes(fn, "if (erroLeitura) throw new Error(`ler vigia: ${erroLeitura.message}`);");
  assertStringIncludes(fn, "if (error) throw new Error(`aviso no sino: ${error.message}`);");
});

Deno.test("V1: o texto do aviso e o da volta só mudam com a chave 'ligado'; em sombra e desligado são os de sempre", () => {
  const fn = oVigiar();
  assertStringIncludes(fn, 'const causaNoAviso = olhar.modo === "ligado" ? causaQueOAvisoDiz(causaDoWhatsApp(registro.estado, olhar.pc)) : null;');
  assertStringIncludes(fn, "const texto = textoDoAviso(aviso, registro, motivo, causaNoAviso, !!olhar.pc && !olhar.pc.semSinal && !olhar.pc.pausa);");
  assertStringIncludes(fn, 'const causaDaQueda = olhar.modo === "ligado" ? await lerCausaDaQuedaDoWhatsApp(db) : null;');
  // a leitura da causa fica dentro do try que já protegia o registro da volta no portão
  const volta = fn.slice(fn.indexOf('if (aviso === "voltou" && anterior?.desde)'));
  assert(volta.indexOf("try {") < volta.indexOf("await lerCausaDaQuedaDoWhatsApp(db)"), "dentro do try");
});

Deno.test("V1: o vigia da conexão não manda nada novo por conta própria — sino e fila do assistente moram só no módulo dele", () => {
  const fn = oVigiar();
  for (const proibido of ["assistente_caiu", "assistente_voltou", "avisoDaQuedaDoAssistente", "textoDaQuedaDoAssistente", "assistente_quedas", "token_hash"]) {
    assert(!fn.includes(proibido), `${proibido} não aparece no vigiar`);
  }
  assertEquals(fn.split("enfileirarAcorde(").length - 1, 1, "a única linha na fila continua sendo a da volta do WhatsApp");
});
