// O aviso de comprovantes (F1, 11/10/2026) traz fornecedor e valor do dono, e audit_log é legível
// por qualquer logado (audit_log_select_auth): com context "comprovante", o message_preview guarda
// só a marca. Pelo texto da fonte (importar index.ts subiria o servidor da função).
import { assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.test("audit_log: o aviso de comprovantes não deixa o texto em message_preview", async () => {
  const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const bloco = fonte.slice(fonte.indexOf('if (body.kind === "text") {'), fonte.indexOf('} else if (body.kind === "link") {'));
  assertStringIncludes(bloco, 'body.context === "comprovante" ? "[aviso de comprovantes]"');
  assertStringIncludes(fonte, "message_preview: messagePreview");
});
