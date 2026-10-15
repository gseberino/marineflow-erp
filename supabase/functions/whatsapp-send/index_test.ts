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
