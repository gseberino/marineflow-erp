// Os comandos do resumo da manhã no turno do WhatsApp (secretário, Passo 2, 15/10/2026) — pelo texto da
// fonte (importar index.ts subiria o servidor). O que se protege: a camada roda DEPOIS da trava do
// comprovante e da confirmação (o "sim"/"1"/"não"/"2" nunca chega a ela como comando) e ANTES do atalho do
// PDF e do modelo; só com o formato novo; só do dono; a resposta sem modelo volta antes do turno do modelo.
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
const inicio = fonte.indexOf("async function handleWhatsAppTurn(");
const fim = fonte.indexOf("interface TurnoDoModelo");
const turno = fonte.slice(inicio, fim);

Deno.test("a camada do secretário fica depois da trava e da confirmação e antes do atalho do PDF e do modelo", () => {
  const camada = turno.indexOf("comandos do resumo da manhã (secretário");
  assert(camada > 0, "camada ausente");
  assert(turno.indexOf("textoDaTravaDoComprovante(") < camada, "depois da trava do comprovante");
  assert(turno.indexOf("const confirmation = parseConfirmationReply(text);") < camada, "depois da confirmação");
  assert(turno.indexOf("parseOptionReply(text, pendingOptions.length)") < camada, "depois da lista de opções");
  assert(camada < turno.indexOf("lerPedidoDePdf(effectiveText)"), "antes do atalho do PDF (o rascunho abre por ele)");
  assert(camada < turno.indexOf("return await turnoDoModeloNoWhatsApp("), "antes do modelo");
});

Deno.test("só com o formato novo, só se a lista de opções não consumiu o texto, e só do dono", () => {
  assertStringIncludes(turno, 'effectiveText === text && lerFormatoDoResumo(settings.resumo_formato) === "novo"');
  assertStringIncludes(turno, "dono && dono.id === appUser.id && dono.phone === phoneNormalized");
});

Deno.test("resposta sem modelo grava o turno e volta; a letra sozinha só troca o texto do turno", () => {
  const bloco = turno.slice(turno.indexOf("comandos do resumo da manhã (secretário"), turno.indexOf("lerPedidoDePdf(effectiveText)"));
  assertStringIncludes(bloco, 'if (r.tipo === "resposta") {');
  assertStringIncludes(bloco, 'role: "user", content: text, source: "whatsapp"');
  assertStringIncludes(bloco, "return jr({ ok: true, secretario: comandoDoResumo.comando });");
  assertStringIncludes(bloco, 'if (r.tipo === "pedido") effectiveText = r.texto;');
  // nada de aprovar/rejeitar pendência aqui
  assert(!bloco.includes("resolveWhatsAppConfirmation"), "a camada não mexe em pendência");
});

Deno.test("Passo 3: 'seguir' (não era comando) deixa o texto do turno como veio", () => {
  const bloco = turno.slice(turno.indexOf("comandos do resumo da manhã (secretário"), turno.indexOf("lerPedidoDePdf(effectiveText)"));
  // só o pedido troca o texto; nenhuma outra atribuição a effectiveText na camada
  assert((bloco.match(/effectiveText = /g) ?? []).length === 1, "uma única troca do texto do turno");
});

Deno.test("Passo 5: o *lote* abre a confirmação de sempre (pendência + sessão + pergunta ativa) e volta sem o modelo; o 'sim' é da camada de confirmação", () => {
  const bloco = turno.slice(turno.indexOf("comandos do resumo da manhã (secretário"), turno.indexOf("lerPedidoDePdf(effectiveText)"));
  const confirmar = bloco.indexOf('if (r.tipo === "confirmar") {');
  assert(confirmar > 0, "ramo confirmar ausente");
  // dentro da porta do dono e antes da resposta comum
  assert(bloco.indexOf("dono && dono.id === appUser.id && dono.phone === phoneNormalized") < confirmar, "só do dono");
  assert(confirmar < bloco.indexOf('if (r.tipo === "resposta") {'), "antes da resposta comum");
  const ramo = bloco.slice(confirmar, bloco.indexOf('if (r.tipo === "resposta") {'));
  assertStringIncludes(ramo, "abrirConfirmacaoDoSecretario(admin, {");
  assertStringIncludes(ramo, "ligada: conversaLigada");
  assertStringIncludes(ramo, "return jr({ ok: true, secretario: comandoDoResumo.comando });");
  // a camada abre, nunca executa: quem executa é o "sim" lá em cima
  assert(!ramo.includes("approveAndExecutePendingAction") && !ramo.includes("resolveWhatsAppConfirmation"), "o ramo não executa nada");
});
