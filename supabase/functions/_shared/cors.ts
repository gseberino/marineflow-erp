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

export const ORIGEM_PADRAO = "https://hbrmarine.online";

const FIXAS = new Set<string>([
  ORIGEM_PADRAO,
  "https://www.hbrmarine.online",
  "https://marineflow-erp.vercel.app",
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

/** Substituto de `Deno.serve(handler)`: mesma assinatura, resposta passa por aplicarCors. */
export function servirComCors(handler: (req: Request) => Response | Promise<Response>): void {
  Deno.serve(async (req: Request) => aplicarCors(req, await handler(req)));
}
