// A porta de funções que agem com a chave de serviço (varredura de 03/10/2026).
//
// verify_jwt = true no gateway só exige UM JWT qualquer — e a chave anônima do site é um JWT, pública
// no código de qualquer navegador. Funções que escrevem com a service role e não conferiam quem
// chamava ficavam abertas: send-push-notification mandava notificação com título, texto e link
// arbitrários a qualquer usuário; whatsapp-transcribe-audio gastava a transcrição paga e reescrevia a
// mensagem; whatsapp-reprocess-messages reescrevia mensagens; whatsapp-unread-reminder enfileirava
// WhatsApp. Agora cada uma confere, antes de qualquer I/O:
//   - chamadaInterna: outra função do servidor (Authorization: Bearer <service role>);
//   - usuarioAtivo: usuário logado e ATIVO em app_users (e, se pedido, do cargo certo).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

/** Comparação em tempo constante para não vazar a chave por timing. */
function iguais(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  if (ab.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ab.length; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}

/** Chamada de outra função do servidor, com a chave de serviço. Sem a chave configurada, nunca. */
export function chamadaInterna(req: Request): boolean {
  const chave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!chave) return false;
  return iguais(req.headers.get("Authorization") ?? "", `Bearer ${chave}`);
}

export type Porta =
  | { ok: true; userId: string; role: string }
  | { ok: false; status: 401 | 403; erro: string };

/**
 * Usuário logado e ativo (a chave anônima não tem usuário: 401). `cargos` restringe o papel.
 * Leitura do cadastro que falha recusa (403): porta que abre por erro não é porta.
 */
export async function usuarioAtivo(req: Request, cargos?: string[]): Promise<Porta> {
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return { ok: false, status: 401, erro: "Não autenticado" };
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const doUsuario = createClient(url, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user } } = await doUsuario.auth.getUser();
  if (!user) return { ok: false, status: 401, erro: "Não autenticado" };
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "", {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await admin.from("app_users").select("role, active").eq("id", user.id).maybeSingle();
  const cadastro = data as { role: string; active: boolean } | null;
  if (error || !cadastro?.active) return { ok: false, status: 403, erro: "Usuário sem acesso ativo" };
  if (cargos && !cargos.includes(cadastro.role)) return { ok: false, status: 403, erro: "Seu cargo não pode usar esta função" };
  return { ok: true, userId: user.id, role: cadastro.role };
}

/** A resposta de recusa, no formato JSON das funções. */
export function recusa(p: { status: number; erro: string }, cors: Record<string, string>): Response {
  return new Response(JSON.stringify({ error: p.erro }), {
    status: p.status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
