// Edge Function: dropbox-conectar (Fase 2A, 08/10/2026 — plans/marineflow-dropbox-fase2.md)
//
// Liga o MarineFlow ao Dropbox da HBR. Duas portas, por isso verify_jwt = false no config.toml:
//   POST {acao}            — a tela de Configurações › Integrações; só ADMIN ativo (usuarioAtivo):
//       iniciar     → devolve a URL de autorização do Dropbox, com um state assinado (10 min);
//       status      → conta conectada, último uso, último erro, pasta-base (nunca o token);
//       testar      → renova o token, lê a conta e confere a pasta-base;
//       desconectar → revoga no Dropbox e apaga a linha.
//   GET ?code&state        — a volta do Dropbox depois do "Permitir". Sem login (é o navegador
//       voltando do dropbox.com); quem prova que o pedido foi nosso é o state assinado com o
//       DROPBOX_APP_SECRET. Troca o código, guarda o refresh token CIFRADO e volta para o app.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { recusa, usuarioAtivo } from "../_shared/porta.ts";
import { assinarEstado, conferirEstado, linkNoSite, urlDeAutorizacao } from "../_shared/dropbox/nucleo.ts";
import {
  abrirDropbox,
  anotarUso,
  type ContaAtual,
  credenciaisDoApp,
  Dropbox,
  ErroDropbox,
  guardarConexao,
  trocarCodigo,
} from "../_shared/dropbox/cliente.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

function admin() {
  return createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "", {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** O endereço desta função — é o redirect cadastrado no App Console, tem de bater exatamente. */
function redirectUri(): string {
  return `${Deno.env.get("SUPABASE_URL")}/functions/v1/dropbox-conectar`;
}

async function lerConfig(db: ReturnType<typeof admin>) {
  const { data } = await db.from("app_settings").select("key, value").in("key", ["app_public_url", "dropbox_pasta_base"]);
  const m = new Map((data ?? []).map((r: { key: string; value: string }) => [r.key, r.value]));
  return {
    appUrl: (m.get("app_public_url") || ORIGEM_PADRAO).replace(/\/$/, ""),
    pastaBase: m.get("dropbox_pasta_base") || "/HBR-Testes/B2C",
  };
}

/** Volta para a tela de Integrações com o resultado na URL (a tela mostra o aviso). */
function voltar(appUrl: string, resultado: string): Response {
  const url = `${appUrl}/v2/settings?tab=integracoes&dropbox=${encodeURIComponent(resultado)}`;
  return new Response(null, { status: 302, headers: { Location: url } });
}

async function callback(req: Request): Promise<Response> {
  const db = admin();
  const { appUrl } = await lerConfig(db);
  const u = new URL(req.url);
  if (u.searchParams.get("error")) return voltar(appUrl, "negado");
  const c = credenciaisDoApp();
  if (!c) return voltar(appUrl, "nao_configurado");
  const estado = await conferirEstado(u.searchParams.get("state") ?? "", c.appSecret);
  if (!estado) return voltar(appUrl, "expirou");
  const codigo = u.searchParams.get("code") ?? "";
  if (!codigo) return voltar(appUrl, "sem_codigo");
  try {
    const t = await trocarCodigo(codigo, redirectUri(), c);
    const dbx = new Dropbox(t.refresh, c, t.acesso);
    const conta = await dbx.rpc<ContaAtual>("users/get_current_account", null);
    await guardarConexao(db, { refresh: t.refresh, c, conta, conectadoPor: estado.uid });
    return voltar(appUrl, "ok");
  } catch (e) {
    console.error("[dropbox-conectar] callback falhou:", (e as Error).message);
    return voltar(appUrl, "falhou");
  }
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method === "GET") return await callback(req);
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

  const porta = await usuarioAtivo(req, ["admin"]);
  if (!porta.ok) return recusa(porta, corsHeaders);

  const { acao } = await req.json().catch(() => ({})) as { acao?: string };
  const db = admin();
  const c = credenciaisDoApp();
  const { pastaBase } = await lerConfig(db);

  if (acao === "status") {
    const { data } = await db.from("integracao_dropbox")
      .select("conta_id, email, nome, conectado_em, ultimo_uso_em, ultimo_erro, ultimo_erro_em")
      .eq("id", 1).maybeSingle();
    return jr({
      configurado: !!c,
      conectado: !!data,
      conta: data ?? null,
      pastaBase,
      linkPastaBase: linkNoSite(pastaBase),
      redirectUri: redirectUri(),
    });
  }

  if (!c) return jr({ error: "As chaves do app do Dropbox ainda não foram cadastradas no servidor." }, 400);

  if (acao === "iniciar") {
    const estado = await assinarEstado(porta.userId, c.appSecret);
    return jr({ url: urlDeAutorizacao({ appKey: c.appKey, redirectUri: redirectUri(), estado }) });
  }

  if (acao === "testar") {
    try {
      const dbx = await abrirDropbox(db);
      if (!dbx) return jr({ error: "O Dropbox ainda não foi conectado." }, 400);
      const conta = await dbx.rpc<ContaAtual>("users/get_current_account", null);
      let pasta: { existe: boolean; caminho: string } = { existe: false, caminho: pastaBase };
      try {
        const m = await dbx.rpc<{ path_display: string }>("files/get_metadata", { path: pastaBase });
        pasta = { existe: true, caminho: m.path_display };
      } catch (e) {
        if (!(e instanceof ErroDropbox && e.resumo.startsWith("path/not_found"))) throw e;
      }
      await anotarUso(db);
      return jr({
        ok: true,
        conta: { nome: conta.name?.display_name, email: conta.email, tipo: conta.root_info?.[".tag"] },
        pastaBase: pasta,
      });
    } catch (e) {
      const msg = (e as Error).message;
      await anotarUso(db, msg);
      return jr({ error: msg }, 502);
    }
  }

  if (acao === "desconectar") {
    try {
      const dbx = await abrirDropbox(db);
      if (dbx) await dbx.revogar();
    } catch (e) {
      // Revogar é cortesia: se o token já não valia, apagar a linha basta.
      console.warn("[dropbox-conectar] revogar falhou:", (e as Error).message);
    }
    const { error } = await db.from("integracao_dropbox").delete().eq("id", 1);
    if (error) return jr({ error: `não consegui apagar a conexão (${error.message})` }, 500);
    return jr({ ok: true });
  }

  return jr({ error: "ação desconhecida" }, 400);
});
