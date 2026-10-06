// CORS com lista de origens (MF-AUD-056). Antes, as 39 edges respondiam
// Access-Control-Allow-Origin: * — qualquer site podia chamar a API pelo navegador de quem
// estivesse logado. Agora só o próprio ERP (produção, previews do Vercel e dev local).
//
// Como funciona: cada edge troca `Deno.serve(` por `servirComCors(`. O invólucro recebe a
// resposta pronta e reescreve o Allow-Origin para a origem do pedido, se ela for permitida;
// se não for, devolve a origem padrão (o navegador bloqueia a leitura). Pedido sem Origin
// (cron, webhook, curl, service role) não é afetado: CORS só existe no navegador.
//
// O bloco `corsHeaders` de cada edge continua existindo (o preflight OPTIONS e o `jr` de
// cada uma usam), só que com ORIGEM_PADRAO no lugar do `*`. O invólucro é quem decide.
//
// Origens extras sem redeploy: segredo CORS_ORIGENS_EXTRA="https://a.com,https://b.com".

import { logEdgeError } from "./log-error.ts";

// O app vivo. hbrmarine.online segue na lista (domínio da empresa), mas hoje serve um build
// antigo; quando o DNS passar a apontar para o Vercel, nada aqui precisa mudar.
export const ORIGEM_PADRAO = "https://marineflow-erp.vercel.app";

const FIXAS = new Set<string>([
  ORIGEM_PADRAO,
  "https://hbrmarine.online",
  "https://www.hbrmarine.online",
]);

// Previews e deploys do Vercel (marineflow-erp-git-main-…, marineflow-abc123-gseberino-s-projects…),
// subdomínios do domínio próprio e o dev local em qualquer porta.
const PADROES: RegExp[] = [
  /^https:\/\/marineflow(-erp)?-[a-z0-9-]+\.vercel\.app$/,
  /^https:\/\/[a-z0-9-]+\.hbrmarine\.online$/,
  /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/,
];

function extrasDoAmbiente(): string[] {
  try {
    return (Deno.env.get("CORS_ORIGENS_EXTRA") || "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
  } catch {
    return [];
  }
}
for (const o of extrasDoAmbiente()) FIXAS.add(o);

/** Devolve a origem a ecoar no Allow-Origin, ou null se a origem não é nossa. */
export function origemPermitida(origin: string | null | undefined): string | null {
  if (!origin) return null;
  const o = origin.trim().replace(/\/$/, "");
  if (FIXAS.has(o)) return o;
  if (PADROES.some((re) => re.test(o))) return o;
  return null;
}

/**
 * Cabeçalhos CORS para um pedido. `req` null = sem contexto (origem padrão).
 * `headersExtra` entra na lista de Allow-Headers (webhooks com assinatura própria).
 */
export function corsHeadersPara(
  req: Request | null,
  opts: { headersExtra?: string[]; methods?: string } = {},
): Record<string, string> {
  const origem = origemPermitida(req?.headers.get("origin")) ?? ORIGEM_PADRAO;
  const headers = ["authorization", "x-client-info", "apikey", "content-type", "x-cron-secret", ...(opts.headersExtra ?? [])];
  return {
    "Access-Control-Allow-Origin": origem,
    "Access-Control-Allow-Headers": headers.join(", "),
    "Access-Control-Allow-Methods": opts.methods ?? "POST, GET, OPTIONS",
    "Vary": "Origin",
  };
}

/** Reescreve o Allow-Origin de uma resposta pronta conforme a origem do pedido. */
export function aplicarCors(req: Request, res: Response): Response {
  const origem = req.headers.get("origin");
  const permitida = origemPermitida(origem);
  if (origem && !permitida) {
    console.warn(`[cors] origem recusada: ${origem} (${req.method} ${new URL(req.url).pathname})`);
  }
  const h = new Headers(res.headers);
  h.set("Access-Control-Allow-Origin", permitida ?? ORIGEM_PADRAO);
  if (!(h.get("Vary") || "").split(",").map((s) => s.trim().toLowerCase()).includes("origin")) {
    h.append("Vary", "Origin");
  }
  return new Response(res.body, { status: res.status, statusText: res.statusText, headers: h });
}

// ── Registro de falha de TODA função (06/10/2026, inventário) ──────────────────────────────
// Só 5 das 40 edges chamavam logEdgeError; nas outras, um 500 ficava só no log do Supabase, que
// nem sempre está à mão — e "deu erro" virava pedir a mensagem a quem viu. Como as 40 passam por
// aqui, o invólucro registra em app_error_logs (RPC log_app_error, que agrupa o mesmo erro numa
// linha só) toda exceção não tratada e toda resposta 5xx, com o nome da função.

export interface FalhaDaFuncao {
  funcao: string;
  mensagem: string;
  status: number;
  metodo: string;
  error?: unknown;
}
export type RegistrarFalha = (falha: FalhaDaFuncao) => Promise<void>;

/** "/functions/v1/banking-sync/x" ou "/banking-sync" → "banking-sync". */
export function nomeDaFuncao(url: string): string {
  const partes = new URL(url).pathname.split("/").filter(Boolean);
  const i = partes.indexOf("v1");
  return (i >= 0 ? partes[i + 1] : partes[0]) ?? "desconhecida";
}

/** Grava pela RPC com a chave de serviço do próprio ambiente da função. Nunca lança. */
const registrarNoBanco: RegistrarFalha = async (f) => {
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const chave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !chave) return;

    const cliente = {
      rpc: (fn: string, args: unknown) =>
        fetch(`${url}/rest/v1/rpc/${fn}`, {
          method: "POST",
          headers: { apikey: chave, Authorization: `Bearer ${chave}`, "Content-Type": "application/json" },
          body: JSON.stringify(args),
        }),
    };
    await logEdgeError(cliente, {
      context: f.funcao,
      message: f.mensagem,
      action: `${f.metodo} → ${f.status}`,
      details: { status: f.status },
      error: f.error,
    });
  } catch {
    /* um log que derruba a função seria pior que não ter log */
  }
};

/** Resposta de falha: o status real (o ai-agent manda 200 com X-Actual-Status) e um trecho do corpo. */
async function falhaDaResposta(res: Response): Promise<{ status: number; trecho: string } | null> {
  const status = Number(res.headers.get("X-Actual-Status") ?? res.status);
  if (!(status >= 500)) return null;
  const trecho = await res.clone().text().then((t) => t.slice(0, 1500)).catch(() => "");
  return { status, trecho };
}

/** O invólucro em si, separado do Deno.serve para poder ser testado. */
export function comCorsERegistro(
  handler: (req: Request) => Response | Promise<Response>,
  registrar: RegistrarFalha = registrarNoBanco,
): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    const funcao = nomeDaFuncao(req.url);
    let res: Response;
    try {
      res = await handler(req);
    } catch (e) {
      // Antes: o Deno respondia 500 sem CORS (o navegador nem lia o erro) e nada ficava gravado.
      const mensagem = String((e as Error)?.message ?? e) || "exceção sem mensagem";
      console.error(`[${funcao}] exceção não tratada:`, e);
      await registrar({ funcao, mensagem: `Exceção não tratada: ${mensagem}`, status: 500, metodo: req.method, error: e });
      res = new Response(JSON.stringify({ error: `Erro interno em ${funcao}: ${mensagem}` }), {
        status: 500,
        headers: { ...corsHeadersPara(req), "Content-Type": "application/json" },
      });
      return aplicarCors(req, res);
    }
    const falha = await falhaDaResposta(res);
    if (falha) {
      await registrar({ funcao, mensagem: falha.trecho || `HTTP ${falha.status} sem corpo`, status: falha.status, metodo: req.method });
    }
    return aplicarCors(req, res);
  };
}

/** Substituto de `Deno.serve(handler)`: mesma assinatura, resposta passa por aplicarCors e falha é registrada. */
export function servirComCors(handler: (req: Request) => Response | Promise<Response>): void {
  Deno.serve(comCorsERegistro(handler));
}
