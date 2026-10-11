// As portas e as ações da edge comprovantes-whatsapp (F1, 11/10/2026 — spec-f1-final.md, 6.1/6.2).
// Separado do index.ts para os testes exercitarem as portas sem subir servidor.
//
// A porta é escolhida PELO CABEÇALHO, antes de qualquer I/O (padrão do ai-agent):
//   - com x-cron-secret → verificarCronSecret; aceita só entrega, vigiar e repescar
//     (o gatilho de ai_jobs, o pg_cron comprovantes-vigia e a repescagem com OK);
//   - sem ele → chamadaInterna (Bearer service role); aceita só receber (o whatsapp-webhook).
import { ORIGEM_PADRAO } from "../_shared/cors.ts";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { chamadaInterna } from "../_shared/porta.ts";
import { logEdgeError } from "../_shared/log-error.ts";
import { codigoDoErro, type DependenciasDoFluxo, entregar, receber, repescar, vigiar } from "../_shared/comprovantes/fluxo.ts";

export const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ACOES_DO_CRON = ["entrega", "vigiar", "repescar"];
const ACOES_INTERNAS = ["receber"];

/** `montarDeps` só é chamado DEPOIS da porta: requisição recusada não cria cliente nem toca o banco. */
export function criarHandler(montarDeps: () => DependenciasDoFluxo): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

    const pelaPortaDoCron = req.headers.has("x-cron-secret");
    if (pelaPortaDoCron) {
      const negado = verificarCronSecret(req, corsHeaders, "comprovantes-whatsapp");
      if (negado) return negado;
    } else if (!chamadaInterna(req)) {
      return jr({ error: "unauthorized" }, 401);
    }
    if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

    // deno-lint-ignore no-explicit-any
    const corpo: any = await req.json().catch(() => null);
    const acao = typeof corpo?.acao === "string" ? corpo.acao : "";
    if (!(pelaPortaDoCron ? ACOES_DO_CRON : ACOES_INTERNAS).includes(acao)) {
      return jr({ error: "acao_nao_permitida_nesta_porta" }, 400);
    }

    const deps = montarDeps();
    try {
      if (acao === "receber") {
        const r = await receber(corpo, deps);
        return jr(r.corpo, r.status);
      }
      if (acao === "entrega") {
        if (typeof corpo.job_id !== "string" || !UUID.test(corpo.job_id)) return jr({ ok: false, erro: "job_id_invalido" }, 400);
        const r = await entregar(corpo.job_id, deps);
        return jr({ ok: true, decisao: r.decisao });
      }
      if (acao === "vigiar") {
        const n = await vigiar(deps);
        return jr({ ok: true, ...n });
      }
      const r = await repescar({ desde: corpo.desde, limite: corpo.limite }, deps);
      if (!r.ok) return jr({ ok: false, motivo: r.motivo }, r.motivo === "desde_invalido" ? 400 : 409);
      return jr({ ok: true, processadas: r.processadas, restantes: r.restantes });
    } catch (e) {
      // Só o código (nunca a mensagem do banco, que pode trazer a linha recusada).
      const codigo = codigoDoErro(e);
      console.error(`[comprovantes-whatsapp] ${acao} falhou: ${codigo}`);
      await logEdgeError(deps.admin, { context: "comprovantes-whatsapp", message: codigo, action: acao });
      return jr({ ok: false, erro: codigo }, 500);
    }
  };
}
