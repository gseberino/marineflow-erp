// O aviso de comprovantes (F1, 11/10/2026) traz fornecedor e valor do dono, e audit_log é legível
// por qualquer logado (audit_log_select_auth): com context "comprovante", o message_preview guarda
// só a marca. Pelo texto da fonte (importar index.ts subiria o servidor da função).
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("audit_log: o aviso de comprovantes não deixa o texto em message_preview", () => {
  const bloco = fonte.slice(fonte.indexOf('if (body.kind === "text") {'), fonte.indexOf('} else if (body.kind === "link") {'));
  assertStringIncludes(bloco, 'body.context === "comprovante" ? "[aviso de comprovantes]"');
  assertStringIncludes(fonte, "message_preview: messagePreview");
});

// 15/10/2026: 379 envios com sucesso desde 15/09 e nenhum em whatsapp_messages. O registro entra
// depois do sucesso do provedor (nunca antes: falha não é mensagem enviada), passa pela regra de
// deveRegistrarEnvio com o desvio do modo de teste e os telefones de quem fala com o assistente, e
// erro do insert não muda a resposta (o envio já saiu).
Deno.test("registro na conversa: depois do sucesso, fora do modo de teste e da conversa com o assistente", () => {
  const sucesso = fonte.indexOf("if (!success) {");
  const insert = fonte.indexOf('.from("whatsapp_messages").insert(linha)');
  const marcaOrcamento = fonte.indexOf('if (body.context === "quote" && body.service_order_id)');
  assert(sucesso > 0 && insert > sucesso, "o insert vem depois do retorno de falha");
  assert(insert < marcaOrcamento, "e antes da marcação do orçamento (que tem return próprio)");
  const bloco = fonte.slice(sucesso, marcaOrcamento);
  assertStringIncludes(bloco, "deveRegistrarEnvio({ desviadoPorTeste: foiDesviado, telefone: phoneClean, telefonesDoAssistente })");
  assertStringIncludes(bloco, '.eq("ai_whatsapp_enabled", true)');
  assertStringIncludes(bloco, 'regErr.code !== "23505"');
  assertStringIncludes(bloco, "quemEnviou(body.sent_by, isServiceRoleCall, usuarioDoJwt)");
  assertStringIncludes(bloco, "} catch (e) {");
  // O registro não devolve nada: a resposta de sucesso continua a mesma de antes.
  assert(!/return jr\(/.test(bloco.slice(bloco.indexOf("try {"))), "o bloco do registro não responde ao chamador");
});

Deno.test("sent_by e origem não barram o envio: o esquema aceita qualquer texto curto", () => {
  assertStringIncludes(fonte, "sent_by: z.string().max(64).optional()");
  assertStringIncludes(fonte, "origem: z.string().max(20).optional()");
});

// Retorno F0a-1 (05/11/2026): o envio automático a quem é de fora passa pelo portão
// (saida-automatica.ts, testado lá) antes da reserva e do desvio de teste, falhando fechado.
Deno.test("portão do automático: antes da reserva, pelo destino de verdade, recusa com 422", () => {
  const portao = fonte.indexOf("if (ehAutomatica(origem, isServiceRoleCall)) {");
  const desvio = fonte.indexOf("const testNumber = numeroDeTesteAtivo(settingsMap);");
  const reserva = fonte.indexOf("const reserva = await reservarOuAguardar(");
  assert(portao > 0 && portao < desvio && desvio < reserva, "portão → desvio de teste → reserva");
  const bloco = fonte.slice(portao, desvio);
  assertStringIncludes(bloco, "const destino = normalizePhoneNumber(body.phone);");
  assertStringIncludes(bloco, '.rpc("canal_bloqueado", { p_fone: destino })');
  assertStringIncludes(bloco, 'bloqueio: bloqueioErr ? "erro"');
  assertStringIncludes(bloco, "hora: horaDeBrasilia()");
  assertStringIncludes(bloco, "recusado: true, codigo: decisao.codigo }, 422)");
  // A equipe sai do portão; sem saber quem é, segue como de fora.
  assertStringIncludes(bloco.replace(/\s+/g, " "), 'equipeErr ? "erro" as const');
  assertStringIncludes(bloco, "automaticaDeFora = daEquipe !== true;");
});

Deno.test("reserva fechada: banco sem resposta não envia o automático a quem é de fora", () => {
  const checagem = fonte.indexOf("if (reservaImpedeEnvio(reserva, automaticaDeFora)) {");
  const nova = fonte.indexOf('if (reserva === "nova") liberarReservaPendente');
  assert(checagem > 0 && checagem < nova, "a recusa vem antes de a reserva valer como nova");
  assertStringIncludes(fonte.slice(checagem, nova).replace(/\s+/g, " "), "reserva_indisponivel: true, }, 503);");
});

Deno.test("falha incerta: a chave não é liberada (sem reenvio automático)", () => {
  const bloco = fonte.slice(fonte.indexOf("const falhaIncertaMantida"), fonte.indexOf("// Audit log"));
  assertStringIncludes(bloco, "manterReservaNaFalha(!sendResult.ok ? sendResult.incerto : undefined, automaticaDeFora)");
  const mantida = bloco.indexOf("else if (falhaIncertaMantida)");
  const libera = bloco.indexOf("else await liberarEnvio(supabaseAdmin, chave);");
  assert(mantida > 0 && mantida < libera, "a falha incerta é conferida antes de liberar");
});
