// Edge Function: whatsapp-conexao
//
// A conexão do número da HBR com a Evolution, pelo ERP:
//   POST { acao: "estado" }                  admin: conectado ou não, perfil, número, última queda
//   POST { acao: "conectar", numero?, inicio? } admin: QR — e o código de 8 dígitos quando vem
//                                            o número (conectar só com o celular)
//   POST com x-cron-secret                   pg_cron a cada 5 min: o vigia. Guarda o estado em
//                                            whatsapp_conexao_vigia e avisa no sino dos admins
//                                            quando fica 10 min fora do ar (e quando volta)
//
// verify_jwt = false porque o pg_cron chama sem JWT. Quem não traz o segredo do cron precisa de
// JWT de admin ativo — as duas portas são conferidas ANTES de qualquer chamada à Evolution.
// A resposta do fetchInstances traz a chave da instância: daqui só saem os campos escolhidos.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { logEdgeError } from "../_shared/log-error.ts";
import {
  decidirVigia, type EstadoConexao, lerEstado, lerRespostaDoConnect, motivoDaQueda,
  numeroParaPareamento, textoDoAviso,
} from "./conexao.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// deno-lint-ignore no-explicit-any
type Db = any;

const TELA_DA_CONEXAO = "/v2/settings?tab=whatsapp";

interface Evolution {
  url: string;
  chave: string;
  instancia: string;
}

async function chamar(evo: Evolution, caminho: string): Promise<{ ok: boolean; status: number; json: unknown }> {
  try {
    const res = await fetch(`${evo.url}${caminho}`, {
      headers: { apikey: evo.chave },
      signal: AbortSignal.timeout(12000),
    });
    const json = await res.json().catch(() => null);
    return { ok: res.ok, status: res.status, json };
  } catch {
    return { ok: false, status: 0, json: null };
  }
}

function detalheDoErro(status: number): string {
  if (status === 0) return "sem resposta do servidor do WhatsApp no PC";
  if (status === 401 || status === 403) return "o servidor do WhatsApp recusou a chave do ERP";
  if (status === 404) return "a instância do WhatsApp não existe no servidor";
  if (status >= 500) return `o PC não respondeu (HTTP ${status}: túnel ou Docker desligado)`;
  return `HTTP ${status}`;
}

async function estadoAtual(evo: Evolution): Promise<{ estado: EstadoConexao; detalhe: string | null }> {
  const r = await chamar(evo, `/instance/connectionState/${evo.instancia}`);
  if (!r.ok) return { estado: "inacessivel", detalhe: detalheDoErro(r.status) };
  const estado = lerEstado(r.json);
  return estado ? { estado, detalhe: null } : { estado: "inacessivel", detalhe: "resposta inesperada" };
}

interface Detalhes {
  perfil: string | null;
  numero: string | null;
  quedaEm: string | null;
  quedaCodigo: number | null;
}

async function detalhesDaInstancia(evo: Evolution): Promise<Detalhes> {
  const vazio: Detalhes = { perfil: null, numero: null, quedaEm: null, quedaCodigo: null };
  const r = await chamar(evo, `/instance/fetchInstances?instanceName=${encodeURIComponent(evo.instancia)}`);
  if (!r.ok) return vazio;
  const lista = Array.isArray(r.json) ? r.json : [r.json];
  // deno-lint-ignore no-explicit-any
  const i = lista.find((x: any) => x?.name === evo.instancia) as any;
  if (!i) return vazio;
  return {
    perfil: typeof i.profileName === "string" ? i.profileName : null,
    numero: numeroParaPareamento(i.ownerJid),
    quedaEm: typeof i.disconnectionAt === "string" ? i.disconnectionAt : null,
    quedaCodigo: typeof i.disconnectionReasonCode === "number" ? i.disconnectionReasonCode : null,
  };
}

async function vigiar(db: Db, evo: Evolution): Promise<Response> {
  const { estado, detalhe } = await estadoAtual(evo);
  const { data: anterior } = await db.from("whatsapp_conexao_vigia")
    .select("estado, desde, avisado_em").eq("id", 1).maybeSingle();
  const agora = new Date();
  const { registro, aviso } = decidirVigia(anterior ?? null, estado, agora);

  // Avisa ANTES de gravar: se a gravação falhar, a próxima rodada avisa de novo (repetir é
  // melhor que calar — o dono passou 4 horas sem saber em 29/09).
  if (aviso) {
    let motivo: string | null = null;
    if (aviso === "caiu" && estado !== "inacessivel") {
      const d = await detalhesDaInstancia(evo);
      const daQuedaAtual = d.quedaEm &&
        new Date(d.quedaEm).getTime() >= new Date(registro.desde).getTime() - 15 * 60000;
      if (daQuedaAtual) motivo = motivoDaQueda(d.quedaCodigo);
    }
    const texto = textoDoAviso(aviso, registro, motivo);
    const { data: admins } = await db.from("app_users").select("id").eq("role", "admin").eq("active", true);
    const linhas = (admins ?? []).map((a: { id: string }) => ({
      user_id: a.id, type: aviso === "caiu" ? "whatsapp_caiu" : "whatsapp_voltou", title: texto.title, body: texto.body, navigate_to: TELA_DA_CONEXAO,
    }));
    if (linhas.length) {
      const { error } = await db.from("app_notifications").insert(linhas);
      if (error) throw new Error(`aviso no sino: ${error.message}`);
    }
  }

  const { error } = await db.from("whatsapp_conexao_vigia").upsert({
    id: 1, ...registro, verificado_em: agora.toISOString(), detalhe,
  });
  if (error) throw new Error(`gravar vigia: ${error.message}`);
  return jr({ ok: true, estado, aviso });
}

servirComCors(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "Use POST" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
  const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const doCron = req.headers.has("x-cron-secret");

  // Porta 1: pg_cron (segredo). Porta 2: admin ativo (JWT). Nada acontece antes disso.
  let userId: string | null = null;
  if (doCron) {
    const recusa = verificarCronSecret(req, corsHeaders, "whatsapp-conexao");
    if (recusa) return recusa;
  } else {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jr({ error: "Não autenticado" }, 401);
    const userClient = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authHeader } } });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return jr({ error: "Não autenticado" }, 401);
    const adminDb = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: appUser } = await adminDb.from("app_users").select("role, active").eq("id", user.id).maybeSingle();
    if (!appUser?.active || appUser.role !== "admin") return jr({ error: "Só o administrador conecta o WhatsApp." }, 403);
    userId = user.id;
  }

  const db = createClient(SUPABASE_URL, SERVICE_ROLE);
  const evo: Evolution = {
    url: (Deno.env.get("EVOLUTION_API_URL") ?? "").replace(/\/$/, ""),
    chave: Deno.env.get("EVOLUTION_API_KEY") ?? "",
    instancia: Deno.env.get("EVOLUTION_INSTANCE") ?? "",
  };
  if (!evo.url || !evo.chave || !evo.instancia) {
    return jr({ error: "Servidor do WhatsApp não configurado no ERP (EVOLUTION_API_URL/KEY/INSTANCE)." }, 500);
  }

  try {
    if (doCron) return await vigiar(db, evo);

    const body = await req.json().catch(() => ({})) as { acao?: string; numero?: string; inicio?: boolean };

    if (body.acao === "estado") {
      const { estado, detalhe } = await estadoAtual(evo);
      const d = estado === "inacessivel" ? null : await detalhesDaInstancia(evo);
      const { data: vigia } = await db.from("whatsapp_conexao_vigia")
        .select("estado, desde, verificado_em").eq("id", 1).maybeSingle();
      return jr({
        estado,
        detalhe,
        perfil: d?.perfil ?? null,
        numero: d?.numero ?? null,
        queda: estado !== "open" && d?.quedaEm ? { em: d.quedaEm, motivo: motivoDaQueda(d.quedaCodigo) } : null,
        vigia: vigia ?? null,
      });
    }

    if (body.acao === "conectar") {
      let numero: string | null = null;
      if (body.numero) {
        numero = numeroParaPareamento(body.numero);
        if (!numero) return jr({ error: "Número inválido. Use DDD + número, ex.: (47) 99999-0000." }, 400);
      }
      const r = await chamar(evo, `/instance/connect/${evo.instancia}${numero ? `?number=${numero}` : ""}`);
      if (!r.ok) return jr({ estado: "inacessivel", detalhe: detalheDoErro(r.status), qr: null, codigo: null });
      if (body.inicio) {
        // Quem pediu o QR fica registrado: ler o QR com outro celular entregaria o canal a ele.
        await db.from("whatsapp_conexao_vigia")
          .update({ pedido_por: userId, pedido_em: new Date().toISOString() }).eq("id", 1);
      }
      return jr({ ...lerRespostaDoConnect(r.json), detalhe: null });
    }

    return jr({ error: "acao deve ser 'estado' ou 'conectar'" }, 400);
  } catch (err) {
    await logEdgeError(db, {
      context: "whatsapp-conexao",
      message: (err as Error)?.message || "erro interno",
      action: doCron ? "vigiar" : "tela",
      error: err,
    });
    return jr({ error: "Falha ao consultar o WhatsApp. Tente de novo." }, 500);
  }
});
