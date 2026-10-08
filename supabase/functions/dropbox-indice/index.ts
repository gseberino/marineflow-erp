// Edge Function: dropbox-indice (Fase 3, 08/10/2026 — plans/marineflow-dropbox-fase2.md)
//
// Mantém o índice arquivos_dropbox com o que existe nas pastas (só a ficha, nunca o conteúdo).
// Segue o cursor do Dropbox ("o que mudou desde a última vez"); na primeira vez — ou se a raiz
// mudar — lê a raiz inteira (app_settings.dropbox_indice_raiz) aos poucos, guardando o cursor a
// cada página para retomar na próxima rodada.
//   arquivo        → ficha ligada à pasta registrada mais funda que o contém;
//   pasta conhecida (pelo id) que mudou de lugar → atualiza o caminho em pastas_dropbox;
//   pasta nova direto em B2C (dropbox_pasta_base) → registra como "dono_a_identificar";
//   apagado        → marca a ficha (e tudo embaixo dela) como apagada.
// Por que não webhook: a doc do Dropbox não garante aviso para mudanças dentro de pasta
// compartilhada montada (a MANAGEMENT). O cron a cada 10 min é a garantia; um webhook pode vir
// depois só para encurtar a espera.
//
// Duas portas (verify_jwt = false): o pg_cron (x-cron-secret) e o botão "Atualizar agora" (admin).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { recusa, usuarioAtivo } from "../_shared/porta.ts";
import { abrirDropbox, anotarUso, Dropbox, ErroDropbox } from "../_shared/dropbox/cliente.ts";
import { codigoNoNome, extensaoDe, filhaDireta, pastaQueContem } from "../_shared/dropbox/nucleo.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

const ORCAMENTO_DE_TEMPO_MS = 40_000;
const POR_PAGINA = 2000;

type Entrada = {
  ".tag": "file" | "folder" | "deleted";
  name: string;
  path_lower?: string;
  path_display?: string;
  id?: string;
  size?: number;
  server_modified?: string;
  content_hash?: string;
};
type Pagina = { entries: Entrada[]; cursor: string; has_more: boolean };
type Pasta = { id: string; dropbox_id: string; caminho: string };

// deno-lint-ignore no-explicit-any
type Admin = any;

async function carregarPastas(admin: Admin) {
  const { data, error } = await admin.from("pastas_dropbox").select("id, dropbox_id, caminho, codigo_projeto");
  if (error) throw new Error(`não consegui ler as pastas (${error.message})`);
  const porCaminho = new Map<string, Pasta>();
  const porId = new Map<string, Pasta>();
  const codigos = new Set<string>();
  for (const p of data ?? []) {
    porCaminho.set(p.caminho.toLowerCase(), p);
    porId.set(p.dropbox_id, p);
    if (p.codigo_projeto) codigos.add(p.codigo_projeto);
  }
  return { porCaminho, porId, codigos };
}

async function processarPagina(
  admin: Admin,
  entradas: Entrada[],
  pastas: Awaited<ReturnType<typeof carregarPastas>>,
  baseB2cLower: string,
) {
  let novasPastas = 0;
  let movidas = 0;

  // 1. Pastas primeiro: o caminho novo de uma pasta conhecida vale para os arquivos da mesma página.
  for (const e of entradas) {
    if (e[".tag"] !== "folder" || !e.id || !e.path_display || !e.path_lower) continue;
    const conhecida = pastas.porId.get(e.id);
    if (conhecida) {
      if (conhecida.caminho !== e.path_display) {
        await admin.from("pastas_dropbox").update({ caminho: e.path_display }).eq("id", conhecida.id);
        pastas.porCaminho.delete(conhecida.caminho.toLowerCase());
        conhecida.caminho = e.path_display;
        pastas.porCaminho.set(e.path_lower, conhecida);
        movidas++;
      }
      continue;
    }
    if (!filhaDireta(e.path_lower, baseB2cLower)) continue;
    const codigo = codigoNoNome(e.name);
    const codigoLivre = codigo && !pastas.codigos.has(codigo) ? codigo : null;
    const { data, error } = await admin.from("pastas_dropbox").insert({
      dropbox_id: e.id,
      caminho: e.path_display,
      codigo_projeto: codigoLivre,
      situacao: "dono_a_identificar",
      nome_na_pasta: e.name,
      observacao: `Pasta criada no Dropbox pelo dono; achada pelo índice em ${new Date().toISOString().slice(0, 10)}.`
        + (codigo && !codigoLivre ? ` O número ${codigo} já era de outra pasta.` : ""),
    }).select("id, dropbox_id, caminho").maybeSingle();
    if (error) {
      console.warn("[dropbox-indice] pasta nova não registrada:", e.path_display, error.message);
      continue;
    }
    if (data) {
      pastas.porId.set(data.dropbox_id, data);
      pastas.porCaminho.set(e.path_lower, data);
      if (codigoLivre) pastas.codigos.add(codigoLivre);
      novasPastas++;
    }
  }

  // 2. Arquivos (em lote).
  const arquivos = entradas.filter((e) => e[".tag"] === "file" && e.id && e.path_lower && e.path_display);
  let gravados = 0;
  if (arquivos.length) {
    const ids = arquivos.map((a) => a.id!);
    const { data: doSistema } = await admin.from("dropbox_envios").select("dropbox_id").in("dropbox_id", ids);
    const subidosPeloSistema = new Set((doSistema ?? []).map((r: { dropbox_id: string }) => r.dropbox_id));
    const linhas = arquivos.map((a) => ({
      dropbox_id: a.id!,
      caminho: a.path_display!,
      caminho_lower: a.path_lower!,
      nome: a.name,
      extensao: extensaoDe(a.name),
      tamanho: a.size ?? null,
      modificado_em: a.server_modified ?? null,
      content_hash: a.content_hash ?? null,
      pasta_id: pastaQueContem(a.path_lower!, pastas.porCaminho)?.id ?? null,
      origem: subidosPeloSistema.has(a.id!) ? "sistema" : "dono",
      apagado: false,
      apagado_em: null,
    }));
    for (let i = 0; i < linhas.length; i += 500) {
      const { error } = await admin.from("arquivos_dropbox").upsert(linhas.slice(i, i + 500), { onConflict: "dropbox_id" });
      if (error) throw new Error(`não consegui gravar o índice (${error.message})`);
    }
    gravados = linhas.length;
  }

  // 3. Apagados (a entrada só traz o caminho).
  const apagados = entradas.filter((e) => e[".tag"] === "deleted" && e.path_lower).map((e) => e.path_lower!);
  let marcados = 0;
  if (apagados.length) {
    const { data, error } = await admin.rpc("dropbox_marcar_apagados", { _caminhos: apagados });
    if (error) throw new Error(`não consegui marcar os apagados (${error.message})`);
    marcados = Number(data) || 0;
  }

  return { gravados, novasPastas, movidas, marcados };
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

  if (req.headers.get("x-cron-secret") !== null) {
    const negado = verificarCronSecret(req, corsHeaders, "dropbox-indice");
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
  if (!dbx) return jr({ ok: true, motivo: "Dropbox não conectado" });

  const { data: cfg } = await admin.from("app_settings").select("key, value").in("key", ["dropbox_indice_raiz", "dropbox_pasta_base"]);
  const m = new Map((cfg ?? []).map((r: { key: string; value: string }) => [r.key, r.value]));
  const raiz = (m.get("dropbox_indice_raiz") || "/MANAGEMENT/COMMERCIAL").replace(/\/+$/, "");
  const baseB2cLower = (m.get("dropbox_pasta_base") || "/MANAGEMENT/COMMERCIAL/B2C").replace(/\/+$/, "").toLowerCase();

  const { data: estado } = await admin.from("integracao_dropbox").select("indice_cursor, indice_raiz, indice_carga_inicial").eq("id", 1).maybeSingle();
  let cursor: string | null = estado?.indice_raiz === raiz ? estado?.indice_cursor ?? null : null;
  const carga = !cursor;

  const inicio = Date.now();
  const total = { paginas: 0, gravados: 0, novasPastas: 0, movidas: 0, marcados: 0 };
  let terminou = false;
  try {
    const pastas = await carregarPastas(admin);
    while (Date.now() - inicio < ORCAMENTO_DE_TEMPO_MS) {
      let pagina: Pagina;
      try {
        pagina = cursor
          ? await dbx.rpc<Pagina>("files/list_folder/continue", { cursor })
          : await dbx.rpc<Pagina>("files/list_folder", {
            path: raiz,
            recursive: true,
            include_deleted: false,
            include_mounted_folders: true,
            limit: POR_PAGINA,
          });
      } catch (e) {
        // O Dropbox invalidou o cursor: recomeça a leitura completa na próxima rodada.
        if (e instanceof ErroDropbox && e.resumo.startsWith("reset")) {
          await admin.from("integracao_dropbox").update({ indice_cursor: null, indice_carga_inicial: true }).eq("id", 1);
          return jr({ ok: true, motivo: "o Dropbox pediu para recomeçar a leitura" });
        }
        throw e;
      }
      const r = await processarPagina(admin, pagina.entries, pastas, baseB2cLower);
      total.paginas++;
      total.gravados += r.gravados;
      total.novasPastas += r.novasPastas;
      total.movidas += r.movidas;
      total.marcados += r.marcados;
      cursor = pagina.cursor;
      // Guarda a cada página: a próxima rodada retoma daqui.
      await admin.from("integracao_dropbox").update({
        indice_cursor: cursor,
        indice_raiz: raiz,
        // Primeira leitura: liga ao começar sem cursor, desliga na última página.
        indice_carga_inicial: pagina.has_more ? (carga || !!estado?.indice_carga_inicial) : false,
        indice_atualizado_em: new Date().toISOString(),
      }).eq("id", 1);
      if (!pagina.has_more) {
        terminou = true;
        break;
      }
    }
    await anotarUso(admin);
  } catch (e) {
    const msg = (e as Error).message;
    await anotarUso(admin, `índice: ${msg}`);
    console.error("[dropbox-indice]", msg);
    return jr({ error: msg, ...total }, 502);
  }

  return jr({ ok: true, cargaInicial: carga, emDia: terminou, ...total });
});
