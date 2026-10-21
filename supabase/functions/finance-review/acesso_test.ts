// A edge finance-review confere o CARGO além do login (spec-papelada-fix.md, A3), e as outras peças da
// papelada que só existem dentro do index.ts (que sobe um servidor ao ser importado) — conferidas pelo
// texto, como o teste de estrutura do ai-agent.
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/finance-review/acesso_test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { conferirCargo, FRASE_SEM_CARGO } from "./acesso.ts";

// deno-lint-ignore no-explicit-any
type Qualquer = any;

function adminComCargo(resposta: { data?: unknown; error?: unknown } | Error) {
  const chamadas: Array<{ nome: string; args: Qualquer }> = [];
  return {
    chamadas,
    admin: {
      rpc(nome: string, args: Qualquer) {
        chamadas.push({ nome, args });
        if (resposta instanceof Error) return Promise.reject(resposta);
        return Promise.resolve({ data: resposta.data ?? null, error: resposta.error ?? null });
      },
    },
  };
}

Deno.test("A3: admin ou financeiro passa — pela MESMA função do banco das RPCs do financeiro", async () => {
  const f = adminComCargo({ data: true });
  assertEquals(await conferirCargo(f.admin, "u-admin"), { ok: true });
  assertEquals(f.chamadas, [{ nome: "is_admin_or_financial", args: { _user_id: "u-admin" } }]);
});

Deno.test("A3: logado sem cargo financeiro (técnico, vendedor, inativo) recebe 403", async () => {
  assertEquals(await conferirCargo(adminComCargo({ data: false }).admin, "u-tecnico"),
    { ok: false, status: 403, erro: FRASE_SEM_CARGO });
});

Deno.test("A3: se não der para conferir, a ação não roda (503) — nunca 'passa na dúvida'", async () => {
  const comErro = await conferirCargo(adminComCargo({ error: { message: "timeout" } }).admin, "u");
  const caiu = await conferirCargo(adminComCargo(new Error("rede")).admin, "u");
  const estranho = await conferirCargo(adminComCargo({ data: "true" }).admin, "u");
  assertEquals([comErro.ok, (comErro as Qualquer).status], [false, 503]);
  assertEquals([caiu.ok, (caiu as Qualquer).status], [false, 503]);
  assertEquals([estranho.ok, (estranho as Qualquer).status], [false, 403]);
});

Deno.test("A3: sem usuário é 401", async () => {
  const f = adminComCargo({ data: true });
  assertEquals((await conferirCargo(f.admin, null) as Qualquer).status, 401);
  assertEquals(f.chamadas.length, 0);
});

const INDEX = Deno.readTextFileSync(new URL("./index.ts", import.meta.url));
const antesDaAcao = INDEX.slice(INDEX.indexOf("servirComCors("), INDEX.indexOf('const action = body.action ?? "generate";'));

Deno.test("estrutura A3: o JWT da tela E a chamada interna com acting_user_id conferem o cargo antes de qualquer ação", () => {
  const jwt = antesDaAcao.slice(antesDaAcao.indexOf("admin.auth.getUser(token)"), antesDaAcao.indexOf("} else if (body.acting_user_id)"));
  const interna = antesDaAcao.slice(antesDaAcao.indexOf("} else if (body.acting_user_id)"));
  assert(/conferirCargo\(admin, userId\)/.test(jwt), "o ramo do JWT não confere o cargo");
  assert(/if \(!cargo\.ok\) return jr\(\{ error: cargo\.erro \}, cargo\.status\)/.test(jwt));
  assert(/conferirCargo\(admin, userId\)/.test(interna), "o ramo interno não confere o cargo");
  // a checagem de antes continua: token vazio e usuário inválido são 401
  assert(antesDaAcao.includes('if (!token) return jr({ error: "unauthorized" }, 401);'));
  assert(antesDaAcao.includes('if (error || !data?.user) return jr({ error: "unauthorized" }, 401);'));
});

Deno.test("estrutura A1: a recusa entra no filtro dos elegíveis, ANTES do corte do mutirão", () => {
  const filtro = INDEX.slice(INDEX.indexOf("const elegiveis = transacoes.filter("), INDEX.indexOf("const ordenados = incluirHistorico"));
  assert(/recusaQueVale\(recusas\.get\(String\(tx\.id\)\), tipoDaProposta\(tx, parPor\.has\(tx\.id\), cnpjEmpresa\), tx\)/.test(filtro));
  assert(INDEX.indexOf("recusas = await lerRecusas(admin") < INDEX.indexOf("const elegiveis = transacoes.filter("));
});

Deno.test("estrutura A2/A4: reject e reopen passam por recusa.ts; o undismiss reabre só a última e sem o aviso do vigia", () => {
  assert(/action === "reject"[\s\S]{0,200}recusarPropostas\(admin/.test(INDEX));
  assert(/action === "reopen"[\s\S]{0,200}reabrirPropostas\(admin/.test(INDEX));
  assert(!/async function recusar\(/.test(INDEX), "a recusa antiga (sem marcar a entrada) ainda existe");
  const undismiss = INDEX.slice(INDEX.indexOf("async function desfazerIgnorada("), INDEX.indexOf("async function classificarComIA("));
  assert(undismiss.includes('.neq("kind", "anomaly")'));
  assert(undismiss.includes("const idsPropostas = propostasAReabrir("));
});
