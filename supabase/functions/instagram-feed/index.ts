// Edge Function: instagram-feed (08/10/2026)
//
// Últimos posts do @hbrsystems para o site público (hbrmarine.com.br). Duas portas,
// verify_jwt = false:
//   - GET  público, só leitura: devolve os posts guardados (dados que já são públicos no
//          Instagram). CORS aberto (*) porque quem chama é o site, não o ERP; sem cookies.
//   - POST só do pg_cron (x-cron-secret): renova o token antes de vencer e busca os posts.
//
// O token mora em instagram_conexao (só service role). Na primeira rodada ele vem do segredo
// INSTAGRAM_TOKEN_INICIAL (gravado pelo dono com hbr-ops/instagram-chave.ps1); dali em diante a
// tabela é a fonte. Sem token, tudo fica inerte e o site simplesmente não mostra a seção.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { comCorsERegistro, corsHeadersPara } from "../_shared/cors.ts";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import {
  CAMPOS_DA_MIDIA,
  GRAPH,
  limiteDoPedido,
  paraGuardar,
  POSTS_GUARDADOS,
  precisaRenovar,
  type PostDaApi,
  type PostGuardado,
} from "../_shared/instagram/feed.ts";

const CORS_PUBLICO = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
};

function admin() {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
}

async function listarPublico(req: Request): Promise<Response> {
  const limite = limiteDoPedido(new URL(req.url).searchParams.get("limite"));
  const { data, error } = await admin()
    .from("instagram_posts")
    .select("id, tipo, imagem, permalink, legenda, publicado_em")
    .order("publicado_em", { ascending: false, nullsFirst: false })
    .limit(limite);
  if (error) {
    console.error("[instagram-feed] leitura falhou:", error.message);
    return new Response(JSON.stringify({ posts: [] }), { status: 200, headers: { ...CORS_PUBLICO, "Content-Type": "application/json" } });
  }
  return new Response(JSON.stringify({ posts: data ?? [] }), {
    status: 200,
    headers: { ...CORS_PUBLICO, "Content-Type": "application/json", "Cache-Control": "public, max-age=600, s-maxage=600" },
  });
}

async function atualizar(req: Request): Promise<Response> {
  const cors = corsHeadersPara(req);
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

  const recusa = verificarCronSecret(req, cors, "instagram-feed");
  if (recusa) return recusa;

  const db = admin();
  const agora = new Date();
  const { data: conexao, error: erroLeitura } = await db.from("instagram_conexao").select("*").eq("id", 1).maybeSingle();
  if (erroLeitura) throw new Error(`instagram_conexao: ${erroLeitura.message}`);

  let token: string | null = conexao?.access_token ?? null;
  if (!token) {
    token = (Deno.env.get("INSTAGRAM_TOKEN_INICIAL") ?? "").trim() || null;
    if (!token) return json({ ok: false, motivo: "sem_token" });
    const { error } = await db.from("instagram_conexao").upsert({ id: 1, access_token: token, atualizado_em: agora.toISOString() });
    if (error) throw new Error(`gravar token inicial: ${error.message}`);
  }

  const relatorio: Record<string, unknown> = { ok: true };
  const expiraEm = conexao?.expira_em ? new Date(conexao.expira_em) : null;
  const renovadoEm = conexao?.renovado_em ? new Date(conexao.renovado_em) : null;

  if (precisaRenovar(expiraEm, renovadoEm, agora)) {
    const r = await fetch(`${GRAPH}/refresh_access_token?grant_type=ig_refresh_token&access_token=${encodeURIComponent(token)}`);
    const corpo = await r.json().catch(() => ({}));
    if (r.ok && corpo.access_token) {
      token = String(corpo.access_token);
      const novaExpiracao = new Date(agora.getTime() + Number(corpo.expires_in ?? 5184000) * 1000);
      await db.from("instagram_conexao").update({
        access_token: token,
        expira_em: novaExpiracao.toISOString(),
        renovado_em: agora.toISOString(),
        atualizado_em: agora.toISOString(),
        ultimo_erro: null,
      }).eq("id", 1);
      relatorio.renovado = true;
    } else {
      // Token com menos de 24 h também cai aqui; a próxima rodada tenta de novo.
      const msg = corpo?.error?.message ?? `HTTP ${r.status}`;
      await db.from("instagram_conexao").update({ ultimo_erro: `renovar: ${msg}`, atualizado_em: agora.toISOString() }).eq("id", 1);
      relatorio.renovado = false;
      relatorio.erro_renovacao = msg;
    }
  }

  const r = await fetch(`${GRAPH}/me/media?fields=${CAMPOS_DA_MIDIA}&limit=${POSTS_GUARDADOS}&access_token=${encodeURIComponent(token)}`);
  const corpo = await r.json().catch(() => ({}));
  if (!r.ok || !Array.isArray(corpo.data)) {
    const msg = corpo?.error?.message ?? `HTTP ${r.status}`;
    await db.from("instagram_conexao").update({ ultimo_erro: `buscar posts: ${msg}`, atualizado_em: agora.toISOString() }).eq("id", 1);
    return json({ ...relatorio, ok: false, erro: msg });
  }

  const posts = (corpo.data as PostDaApi[]).map(paraGuardar).filter((p): p is PostGuardado => p !== null);
  if (posts.length > 0) {
    const { error } = await db.from("instagram_posts").upsert(posts.map((p) => ({ ...p, buscado_em: agora.toISOString() })));
    if (error) throw new Error(`gravar posts: ${error.message}`);
    // Fica só o que o Instagram devolveu agora: post apagado lá some do site.
    const ids = posts.map((p) => p.id);
    await db.from("instagram_posts").delete().not("id", "in", `(${ids.map((i) => `"${i}"`).join(",")})`);
  }
  await db.from("instagram_conexao").update({
    ultima_busca: agora.toISOString(),
    atualizado_em: agora.toISOString(),
    ...(relatorio.erro_renovacao ? {} : { ultimo_erro: null }),
  }).eq("id", 1);

  return json({ ...relatorio, posts: posts.length });
}

const comRegistro = comCorsERegistro(atualizar);

Deno.serve((req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_PUBLICO });
  if (req.method === "GET") return listarPublico(req);
  return comRegistro(req);
});
