// Edge Function: dropbox-worker (Fase 2B/2C, 08/10/2026 — plans/marineflow-dropbox-fase2.md)
//
// Processa a fila dropbox_envios, UM item de cada vez (escritas paralelas na pasta compartilhada
// dão 429 too_many_write_operations no Dropbox):
//   pasta                          → garante a pasta do barco (cria com número novo se não tiver);
//   enviado/aprovado/concluido/manual → garante a pasta e guarda o PDF do orçamento/OS, igual ao
//                                    "Baixar" da tela, como "AAAA-MM-DD ORÇ-00112 vN.pdf" em
//                                    "1- DOC's/Orçamentos e OS". Conteúdo igual ao último guardado:
//                                    não sobe de novo (impressão digital sem o carimbo de emissão);
//   assinado                       → guarda o PDF assinado do portal (bucket signatures).
// Nunca apaga nem sobrescreve nada no Dropbox (upload em modo "add").
//
// Duas portas (verify_jwt = false): o pg_cron a cada 5 min (x-cron-secret) e o botão "Salvar no
// Dropbox agora" da tela (admin ativo).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { recusa, usuarioAtivo } from "../_shared/porta.ts";
import { abrirDropbox, anotarUso, Dropbox, ErroDropbox } from "../_shared/dropbox/cliente.ts";
import { garantirPastaDoBarco } from "../_shared/dropbox/pasta.ts";
import {
  clienteGenerico,
  dataEmSaoPaulo,
  nomeDoPdf,
  nomeDoPdfAssinado,
  PASTA_DOS_PDFS,
} from "../_shared/dropbox/nucleo.ts";
import { impressaoDigitalDoDocumento, montarDocumentoDaOrdem } from "../_shared/pdf/gerar-e-guardar.ts";
import { renderizarPdf } from "../_shared/pdf/renderizar.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

/** Espera antes da próxima tentativa (a 1ª tentativa já contou ao pegar o item). */
const ESPERA_MIN = [5, 15, 60, 180];
const MAX_TENTATIVAS = 5;
/** Folga para a função terminar antes do limite do gateway. */
const ORCAMENTO_DE_TEMPO_MS = 45_000;

type Envio = {
  id: string;
  order_id: string | null;
  vessel_id: string | null;
  motivo: string;
  referencia: string | null;
  tentativas: number;
};

type Resultado =
  | { status: "feito"; resultado: string; dropbox_id?: string; caminho?: string; versao?: number; impressao_digital?: string }
  | { status: "ignorado"; resultado: string };

class Repetir extends Error {}

// deno-lint-ignore no-explicit-any
type Admin = any;

async function lerSettings(admin: Admin): Promise<Record<string, string>> {
  const { data, error } = await admin.from("app_settings").select("key, value");
  if (error) throw new Error(`não consegui ler as configurações (${error.message})`);
  return Object.fromEntries((data ?? []).map((r: { key: string; value: string }) => [r.key, r.value]));
}

async function processar(admin: Admin, dbx: Dropbox, e: Envio, settings: Record<string, string>): Promise<Resultado> {
  const pastaBase = settings.dropbox_pasta_base || "/HBR-Testes/B2C";

  // O alvo: a ordem (e dela o barco e o cliente) ou só o barco.
  let ordem: { id: string; service_order_number: string; status: string | null; share_token: string | null; vessel_id: string; client_id: string } | null = null;
  if (e.order_id) {
    const { data, error } = await admin.from("service_orders")
      .select("id, service_order_number, status, share_token, vessel_id, client_id")
      .eq("id", e.order_id).maybeSingle();
    if (error) throw new Repetir(`não consegui ler a ordem (${error.message})`);
    if (!data) return { status: "ignorado", resultado: "a ordem não existe mais" };
    ordem = data;
  }
  const vesselId = ordem?.vessel_id ?? e.vessel_id;
  const { data: barco, error: eBarco } = await admin.from("vessels")
    .select("id, name, client_id, clients(name)").eq("id", vesselId).maybeSingle();
  if (eBarco) throw new Repetir(`não consegui ler a embarcação (${eBarco.message})`);
  if (!barco) return { status: "ignorado", resultado: "a embarcação não existe mais" };
  const nomeCliente: string | null = barco.clients?.name ?? null;
  if (clienteGenerico(nomeCliente)) return { status: "ignorado", resultado: "cliente genérico não ganha pasta" };

  const pasta = await garantirPastaDoBarco(admin, dbx, {
    vesselId: barco.id,
    clientId: barco.client_id,
    barco: barco.name,
    cliente: nomeCliente,
    pastaBase,
  });
  if (e.motivo === "pasta" || !ordem) {
    return { status: "feito", resultado: pasta.criada ? "pasta criada" : "pasta já existia", dropbox_id: pasta.id, caminho: pasta.caminho };
  }

  const destino = `${pasta.caminho}/${PASTA_DOS_PDFS}`;
  const hoje = dataEmSaoPaulo();

  if (e.motivo === "assinado") {
    if (!e.referencia) return { status: "ignorado", resultado: "assinatura sem PDF" };
    const { data: arquivo, error } = await admin.storage.from("signatures").download(e.referencia);
    if (error || !arquivo) throw new Repetir(`não consegui ler o PDF assinado (${error?.message ?? "vazio"})`);
    const bytes = new Uint8Array(await arquivo.arrayBuffer());
    const m = await dbx.enviar(`${destino}/${nomeDoPdfAssinado(hoje, ordem.service_order_number)}`, bytes);
    return { status: "feito", resultado: "PDF assinado guardado", dropbox_id: m.id, caminho: m.path_display };
  }

  // O PDF do orçamento/OS, igual ao "Baixar" da tela.
  const montado = await montarDocumentoDaOrdem(admin, { id: ordem.id, status: ordem.status }, settings);
  if (!montado.ok) throw new Repetir(montado.motivo);
  const impressao = impressaoDigitalDoDocumento(montado.doc.html);

  const { data: anteriores, error: eAnt } = await admin.from("dropbox_envios")
    .select("impressao_digital, versao")
    .eq("order_id", ordem.id).eq("status", "feito").not("impressao_digital", "is", null)
    .order("created_at", { ascending: false });
  if (eAnt) throw new Repetir(`não consegui ler as versões anteriores (${eAnt.message})`);
  if (anteriores?.[0]?.impressao_digital === impressao) {
    return { status: "ignorado", resultado: `sem mudança desde a v${anteriores[0].versao ?? "?"}` };
  }
  const versao = Math.max(0, ...(anteriores ?? []).map((a: { versao: number | null }) => a.versao ?? 0)) + 1;

  const render = await renderizarPdf({
    baseUrl: settings.app_public_url || "",
    html: montado.doc.html,
    filename: montado.doc.nomeDoArquivo,
    shareToken: ordem.share_token ?? undefined,
  });
  if (!render.ok) throw new Repetir(render.motivo);

  const m = await dbx.enviar(`${destino}/${nomeDoPdf(hoje, ordem.service_order_number, versao)}`, new Uint8Array(render.pdf));
  return {
    status: "feito",
    resultado: `${montado.doc.rotulo} v${versao} guardado`,
    dropbox_id: m.id,
    caminho: m.path_display,
    versao,
    impressao_digital: impressao,
  };
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

  // Porta: o cron (x-cron-secret) ou um admin ativo (botão da tela).
  if (req.headers.get("x-cron-secret") !== null) {
    const negado = verificarCronSecret(req, corsHeaders, "dropbox-worker");
    if (negado) return negado;
  } else {
    const porta = await usuarioAtivo(req, ["admin"]);
    if (!porta.ok) return recusa(porta, corsHeaders);
  }

  const admin = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "", {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let dbx: Dropbox | null;
  try {
    dbx = await abrirDropbox(admin);
  } catch (e) {
    return jr({ error: (e as Error).message }, 500);
  }
  // Não conectado: a fila espera (nada se perde).
  if (!dbx) return jr({ ok: true, processados: 0, motivo: "Dropbox não conectado" });

  const settings = await lerSettings(admin);
  const { data: lote, error } = await admin.rpc("dropbox_pegar_envios", { _limite: 5 });
  if (error) return jr({ error: `não consegui pegar a fila (${error.message})` }, 500);

  const inicio = Date.now();
  const relatorio: Array<{ id: string; status: string; resultado: string }> = [];
  let ultimoErro: string | null = null;

  for (const e of (lote ?? []) as Envio[]) {
    // Sem tempo para mais um: devolve à fila sem gastar tentativa.
    if (Date.now() - inicio > ORCAMENTO_DE_TEMPO_MS) {
      await admin.from("dropbox_envios").update({
        status: "pendente", processando_desde: null, tentativas: Math.max(0, e.tentativas - 1),
      }).eq("id", e.id);
      continue;
    }
    try {
      const r = await processar(admin, dbx, e, settings);
      await admin.from("dropbox_envios").update({ ...r, processando_desde: null }).eq("id", e.id);
      relatorio.push({ id: e.id, status: r.status, resultado: r.resultado });
    } catch (err) {
      const msg = (err as Error).message.slice(0, 500);
      const repetivel = err instanceof Repetir || (err instanceof ErroDropbox && err.repetivel);
      const desiste = !repetivel || e.tentativas >= MAX_TENTATIVAS;
      const espera = ESPERA_MIN[Math.min(e.tentativas - 1, ESPERA_MIN.length - 1)] ?? 60;
      await admin.from("dropbox_envios").update({
        status: desiste ? "falhou" : "pendente",
        processando_desde: null,
        resultado: msg,
        proxima_em: new Date(Date.now() + espera * 60_000).toISOString(),
      }).eq("id", e.id);
      relatorio.push({ id: e.id, status: desiste ? "falhou" : "pendente", resultado: msg });
      ultimoErro = msg;
      console.error("[dropbox-worker]", e.id, e.motivo, msg);
    }
  }

  if (relatorio.length) await anotarUso(admin, ultimoErro ?? undefined);
  return jr({ ok: true, processados: relatorio.length, relatorio });
});
