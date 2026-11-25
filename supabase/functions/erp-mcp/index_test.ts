// erp-mcp: quem pode chamar as ferramentas pela assinatura Claude (pacote 1, S5, 24/11/2026) — pelo texto da fonte
// (importar index.ts subiria o servidor). O que se protege: o job de quem não é o assinante é recusado com 401 antes de
// qualquer ferramenta ser listada ou executada, e a conferência usa as settings lidas do banco (é delas que sai a lista
// ai_max_assinantes). A regra em si (pessoa e não cargo, chave ausente, chave vazia) é provada em
// _shared/ai/max/claude-max_test.ts.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
const handler = fonte.slice(fonte.indexOf("export async function handler("), fonte.indexOf("servirComCors(handler);"));

Deno.test("S5: o erp-mcp recusa quem não é o assinante, depois de ler as settings e antes de montar as ferramentas", () => {
  assert(handler.length > 0, "o recorte do handler ficou vazio");
  const guarda = handler.indexOf('if (!assinanteDoMax(settings, usuario.id, String(usuario.role ?? ""))) return naoAutorizado();');
  assert(guarda > 0, "falta a conferência do assinante");
  // depois da leitura das settings: antes dela a lista não existe, e a chave pareceria ausente (regra antiga)
  const leitura = handler.indexOf('await admin.from("app_settings").select("key, value")');
  const preenchidas = handler.indexOf('if (r.key) settings[r.key] = String(r.value ?? "");');
  assert(leitura > 0 && preenchidas > leitura && guarda > preenchidas, "a conferência vem depois de as settings serem lidas e preenchidas");
  // antes de qualquer coisa que liste ou rode ferramenta
  for (const depois of ["ferramentasDoJob(", "const toolCtx =", "const servidor: ServidorDoTurno =", "executarChamadaDeTool(", "await responderMcp("]) {
    const i = handler.indexOf(depois);
    assert(i > guarda, `a conferência do assinante vem antes de ${depois}`);
  }
  // leitura que falhou não é "chave ausente" (que cairia na regra antiga, pelo cargo): recusa antes de conferir a pessoa
  assertStringIncludes(handler, 'const { data: linhas, error: erroDasSettings } = await admin.from("app_settings").select("key, value");');
  const semLeitura = handler.indexOf("if (erroDasSettings) {");
  assert(semLeitura > leitura && semLeitura < guarda, "a leitura que falhou é recusada antes de a lista ser consultada");
  assertStringIncludes(handler.slice(semLeitura, guarda), "return naoAutorizado();");
  // o log da recusa leva só o id do job e a mensagem do erro do banco; nunca o token
  assert(!/console\.(error|warn|log)\([^;]*\btoken\b/.test(handler), "o token do turno nunca vai para o log");
  // a pessoa é a do JOB (requested_by), nunca a do corpo da requisição
  assertStringIncludes(handler, '.eq("id", job.requested_by)');
  assert(handler.indexOf("await req.json()") > guarda, "o corpo da requisição só é lido depois de quem pediu ser conferido");
});

Deno.test("S5: a recusa é a mesma resposta 401 das outras, sem dizer por que", () => {
  assertStringIncludes(fonte, 'const naoAutorizado = () => json({ jsonrpc: "2.0", id: null, error: { code: -32001, message: "Não autorizado" } }, 401);');
  // a conferência de usuário ativo e de canal ligado continua valendo, antes da do assinante
  const ativo = handler.indexOf('if (!usuario?.active || (canal === "whatsapp" && !usuario.ai_whatsapp_enabled)) return naoAutorizado();');
  assert(ativo > 0 && ativo < handler.indexOf("if (!assinanteDoMax("), "usuário ativo primeiro, assinante depois");
  assertEquals((handler.match(/assinanteDoMax\(/g) ?? []).length, 1);
  assertStringIncludes(fonte, 'import { assinanteDoMax, sha256Hex, TIPOS_DO_AGENTE } from "../_shared/ai/max/claude-max.ts";');
});
