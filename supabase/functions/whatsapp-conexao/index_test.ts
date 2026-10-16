// Vigia da conexão (secretário, Passo 4, 15/10/2026): pelo texto da fonte (importar index.ts subiria o
// servidor da função). O que se protege: o registro da volta do WhatsApp no portão só existe no aviso
// "voltou", depois do sino, dentro de um try (nunca derruba o vigia), e só com a voz única ligada.
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

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
  // (16/10/2026) com o texto do acorde de sistema
  assertStringIncludes(resto, "const doPortao = textoDoSistema({ desde: anterior.desde, ate, manhaNaoChegou: quedaDerrubouAManha(anterior.desde, ate) });");
  assertStringIncludes(resto, "avisoDaVoltaDoWhatsApp({ desde: anterior.desde, ate }, doPortao)");
  assert(fn.indexOf("await lerPortao(db)") > bloco, "a leitura das chaves só acontece na volta");
});
