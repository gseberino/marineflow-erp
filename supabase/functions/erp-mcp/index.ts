// Edge Function: erp-mcp — as ferramentas do assistente do MarineFlow como servidor MCP (03/10/2026).
//
// Quem chama: o Claude Code no HBR AI Gateway (PC do dono), durante um job 'agente_whatsapp' da
// fila ai_jobs. Cada tools/call roda AQUI, pela mesma executarChamadaDeTool do loop do OpenRouter:
// mesmo perfil, mesma rede de segurança, mesmo risco/autonomia, pendência com PIN e auditoria.
//
// Autenticação (verify_jwt=false — o chamador não é um usuário do app):
//   x-erp-job: <id do job>   +   Authorization: Bearer <token de uso único do turno>
// O banco guarda só o sha256 do token (ai_jobs.metadata.mcp_token_sha256); vale só enquanto o job
// está 'processing' e por no máximo 20 min. O contexto (usuário, cargo, sessão, ferramentas) vem
// do JOB — nunca do corpo da requisição.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { executarChamadaDeTool, interrupcaoDaTool } from "../_shared/ai/agent.ts";
import type { Role } from "../_shared/ai/tools/index.ts";
import { ferramentasDoJob } from "../_shared/ai/max/ferramentas-do-job.ts";
import { responderMcp, type ServidorDoTurno } from "../_shared/ai/max/mcp.ts";
import { sha256Hex, TIPOS_DO_AGENTE } from "../_shared/ai/max/claude-max.ts";
import { timingSafeEqual } from "../_shared/cron-auth.ts";
import { servirComCors } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const VALIDADE_MS = 20 * 60_000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { "content-type": "application/json" } });

const naoAutorizado = () => json({ jsonrpc: "2.0", id: null, error: { code: -32001, message: "Não autorizado" } }, 401);

export async function handler(req: Request): Promise<Response> {
  if (req.method !== "POST") return new Response(null, { status: 405, headers: { allow: "POST" } });

  const jobId = req.headers.get("x-erp-job") ?? "";
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!UUID.test(jobId) || token.length < 32) return naoAutorizado();

  const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: job } = await admin
    .from("ai_jobs")
    .select("id, status, started_at, requested_by, input, metadata")
    .eq("id", jobId)
    .maybeSingle();
  const meta = (job?.metadata ?? {}) as Record<string, any>;
  if (
    !job || job.status !== "processing" || !TIPOS_DO_AGENTE.has(meta.tipo) || typeof meta.mcp_token_sha256 !== "string" ||
    !job.started_at || Date.now() - Date.parse(job.started_at) > VALIDADE_MS ||
    !timingSafeEqual(await sha256Hex(token), meta.mcp_token_sha256)
  ) {
    return naoAutorizado();
  }

  const { data: usuario } = await admin
    .from("app_users")
    .select("id, role, active, ai_whatsapp_enabled")
    .eq("id", job.requested_by)
    .maybeSingle();
  const input = (job.input ?? {}) as Record<string, any>;
  const canal: "panel" | "whatsapp" = input.canal === "panel" ? "panel" : "whatsapp";
  // WhatsApp exige o canal habilitado para o usuário; o painel só exige o usuário ativo.
  if (!usuario?.active || (canal === "whatsapp" && !usuario.ai_whatsapp_enabled)) return naoAutorizado();

  const { data: linhas } = await admin.from("app_settings").select("key, value");
  const settings: Record<string, string> = {};
  (linhas ?? []).forEach((r: any) => {
    if (r.key) settings[r.key] = String(r.value ?? "");
  });

  const cargo = (usuario.role as Role) || ("unknown" as Role);
  const { toolsByName, alcancaveisPelaRede } = ferramentasDoJob(cargo, input.ferramentas?.visiveis, input.ferramentas?.rede, canal);
  const sessionId = String(input.sessao ?? meta.session_id ?? "");
  // Mesmo contexto do canal WhatsApp em ai-agent: sem JWT de usuário, client service-role (no painel
  // só o admin chega aqui pelo Max — ver provedorDoTurno).
  const toolCtx = { sb: admin, admin, userId: usuario.id, userRole: cargo, jwt: "", appOrigin: settings.app_public_url || "", settings, canal };

  const servidor: ServidorDoTurno = {
    listar: () => Object.values(toolsByName).map((t) => ({ name: t.name, description: t.description, input_schema: t.input_schema })),
    async chamar(nome, argumentos) {
      // Pendência ou opções já encerraram o turno: nada mais roda (o usuário ainda vai decidir).
      const { data: atual } = await admin.from("ai_jobs").select("metadata").eq("id", jobId).maybeSingle();
      if ((atual?.metadata as Record<string, any> | null)?.interrupcao) {
        return { resultado: { error: "Turno encerrado: aguardando a decisão do usuário. Não chame mais ferramentas." } };
      }
      const tc = { name: nome, input: argumentos ?? {} };
      const r = await executarChamadaDeTool(tc, { toolsByName, alcancaveisPelaRede, toolCtx, sessionId, channel: canal });
      // Sem desambiguação forçada aqui (trabalhoComposto=true): o MCP recebe uma chamada por vez e
      // não sabe se o modelo disparou várias; pendência e present_options continuam encerrando.
      const interrupcao = interrupcaoDaTool(tc, r, true);
      // Registro atômico no job (duas chamadas em paralelo não apagam a interrupção uma da outra).
      await admin.rpc("ai_job_registrar_ferramenta", { p_job_id: jobId, p_nome: nome, p_interrupcao: interrupcao });
      return { resultado: r.toolResult, interrompe: !!interrupcao };
    },
  };

  const corpo = await req.json().catch(() => null);
  const resposta = await responderMcp(corpo, servidor);
  return resposta ? json(resposta) : new Response(null, { status: 202 });
}

servirComCors(handler);
