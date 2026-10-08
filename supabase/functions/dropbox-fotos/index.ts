// Edge Function: dropbox-fotos (Fase 4, 08/10/2026 — plans/marineflow-dropbox-fase2.md)
//
// A triagem das fotos que o dono manda do celular para "Envio da câmera". Só ADMIN ativo.
//   listar      → as fotos/vídeos/prints da pasta, com o dia e a hora em que foram tirados;
//   miniaturas  → até 25 miniaturas JPEG (base64) para a tela;
//   sugestoes   → para cada dia, as OS mais prováveis e o PORQUÊ (entrada/saída registrada,
//                 diária no barco, mensagens da OS, tarefa na agenda, OS criada/mexida, agenda).
//                 A escolha é sempre do dono: o sistema só ordena;
//   mover       → move as fotos escolhidas para "<pasta do barco>/3- FOTOS/AAAA-MM-DD OS-xxxxx"
//                 (cria a pasta do barco se faltar) e liga cada uma à OS no índice. Mover, não
//                 copiar: a caixa de entrada esvazia. Nada é apagado.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { recusa, usuarioAtivo } from "../_shared/porta.ts";
import { abrirDropbox, Dropbox, ErroDropbox } from "../_shared/dropbox/cliente.ts";
import { garantirPastaDoBarco } from "../_shared/dropbox/pasta.ts";
import {
  dataEmSaoPaulo,
  extensaoDe,
  notaDaOsNoDia,
  pastaDasFotos,
  quandoFoiTirada,
  type SinalDaOs,
  tipoDeMidia,
} from "../_shared/dropbox/nucleo.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

// deno-lint-ignore no-explicit-any
type Admin = any;

const ID = /^id:[A-Za-z0-9_-]+$/;
const DIA = /^\d{4}-\d{2}-\d{2}$/;
const ATIVOS = new Set(["open", "scheduled", "in_progress", "awaiting_parts", "awaiting_client", "approved"]);

async function config(admin: Admin) {
  const { data } = await admin.from("app_settings").select("key, value").in("key", ["dropbox_pasta_camera", "dropbox_pasta_base"]);
  const m = new Map<string, string>((data ?? []).map((r: { key: string; value: string }) => [r.key, r.value]));
  return {
    camera: (m.get("dropbox_pasta_camera") || "/Envio da câmera").normalize("NFC"),
    base: m.get("dropbox_pasta_base") || "/MANAGEMENT/COMMERCIAL/B2C",
  };
}

// ---------------------------------------------------------------------------------------------
// listar
// ---------------------------------------------------------------------------------------------
type Entrada = { ".tag": string; id: string; name: string; size?: number; client_modified?: string };

async function listar(dbx: Dropbox, camera: string) {
  const itens: Array<{ id: string; nome: string; tamanho: number; dia: string | null; hora: string | null; tipo: string }> = [];
  let pagina = await dbx.rpc<{ entries: Entrada[]; cursor: string; has_more: boolean }>("files/list_folder", {
    path: camera, recursive: false, limit: 2000,
  });
  for (let voltas = 0; voltas < 20; voltas++) {
    for (const e of pagina.entries) {
      if (e[".tag"] !== "file") continue;
      const q = quandoFoiTirada(e.name, e.client_modified);
      itens.push({ id: e.id, nome: e.name, tamanho: e.size ?? 0, dia: q?.dia ?? null, hora: q?.hora ?? null, tipo: tipoDeMidia(e.name) });
    }
    if (!pagina.has_more) break;
    pagina = await dbx.rpc("files/list_folder/continue", { cursor: pagina.cursor });
  }
  itens.sort((a, b) => `${b.dia ?? ""} ${b.hora ?? ""}`.localeCompare(`${a.dia ?? ""} ${a.hora ?? ""}`));
  return itens;
}

// ---------------------------------------------------------------------------------------------
// sugestoes
// ---------------------------------------------------------------------------------------------
const diaSP = (iso: string | null | undefined) => (iso ? dataEmSaoPaulo(new Date(iso)) : null);

async function sugestoes(admin: Admin, dias: string[]) {
  const ordenados = [...dias].sort();
  const de = new Date(`${ordenados[0]}T00:00:00-03:00`);
  de.setDate(de.getDate() - 2);
  const ate = new Date(`${ordenados[ordenados.length - 1]}T23:59:59-03:00`);
  ate.setDate(ate.getDate() + 2);
  const deIso = de.toISOString();
  const ateIso = ate.toISOString();

  const { data: ordens, error } = await admin.from("service_orders")
    .select("id, service_order_number, status, created_at, updated_at, scheduled_start_at, scheduled_end_at, check_in_at, check_out_at, vessels(name), clients(name)")
    .neq("status", "cancelled");
  if (error) throw new Error(`não consegui ler as OS (${error.message})`);

  const sinais = new Map<string, SinalDaOs>();
  const evento = (id: string, dia: string | null, peso: number, motivo: string) => {
    if (!dia) return;
    const s = sinais.get(id);
    if (s) s.eventos.push({ dia, peso, motivo });
  };
  for (const o of ordens ?? []) {
    sinais.set(o.id, {
      id: o.id,
      eventos: [],
      agendado: o.scheduled_start_at ? [diaSP(o.scheduled_start_at)!, diaSP(o.scheduled_end_at ?? o.scheduled_start_at)!] : null,
    });
    evento(o.id, diaSP(o.check_in_at), 3, "entrada no barco registrada");
    evento(o.id, diaSP(o.check_out_at), 3, "saída do barco registrada");
    evento(o.id, diaSP(o.created_at), 1, "criada nesse dia");
    evento(o.id, diaSP(o.updated_at), 1, "mexida no sistema nesse dia");
  }

  const [turnos, mensagens, tarefas] = await Promise.all([
    admin.from("work_shifts").select("id, data, service_order_id").gte("data", deIso.slice(0, 10)).lte("data", ateIso.slice(0, 10)),
    admin.from("whatsapp_messages").select("service_order_id, occurred_at").not("service_order_id", "is", null).gte("occurred_at", deIso).lte("occurred_at", ateIso).limit(5000),
    admin.from("agenda_tasks").select("related_entity_id, scheduled_start_at, completed_at").eq("related_entity_type", "service_order").or(`and(scheduled_start_at.gte.${deIso},scheduled_start_at.lte.${ateIso}),and(completed_at.gte.${deIso},completed_at.lte.${ateIso})`),
  ]);
  for (const [nome, r] of [["diárias", turnos], ["mensagens", mensagens], ["agenda", tarefas]] as const) {
    if (r.error) throw new Error(`não consegui ler ${nome} (${r.error.message})`);
  }
  const idsDeTurno = (turnos.data ?? []).map((t: { id: string }) => t.id);
  const extras = idsDeTurno.length
    ? await admin.from("work_shift_os").select("shift_id, service_order_id").in("shift_id", idsDeTurno)
    : { data: [] };
  const diaDoTurno = new Map<string, string>((turnos.data ?? []).map((t: { id: string; data: string }) => [t.id, t.data]));
  for (const t of turnos.data ?? []) if (t.service_order_id) evento(t.service_order_id, t.data, 3, "diária no barco");
  for (const x of extras.data ?? []) evento(x.service_order_id, diaDoTurno.get(x.shift_id) ?? null, 3, "diária no barco");
  const msgPorOsDia = new Set<string>();
  for (const m of mensagens.data ?? []) {
    const chave = `${m.service_order_id}|${diaSP(m.occurred_at)}`;
    if (msgPorOsDia.has(chave)) continue;
    msgPorOsDia.add(chave);
    evento(m.service_order_id, diaSP(m.occurred_at), 2, "mensagens da OS no WhatsApp");
  }
  for (const t of tarefas.data ?? []) {
    evento(t.related_entity_id, diaSP(t.scheduled_start_at), 2, "tarefa da OS na agenda");
    evento(t.related_entity_id, diaSP(t.completed_at), 2, "tarefa da OS concluída");
  }

  const porId = new Map((ordens ?? []).map((o: { id: string }) => [o.id, o]));
  const resposta: Record<string, unknown[]> = {};
  for (const dia of dias) {
    const lista = [];
    for (const s of sinais.values()) {
      const o = porId.get(s.id) as { service_order_number: string; status: string; vessels?: { name: string }; clients?: { name: string } };
      const { nota, motivos } = notaDaOsNoDia(dia, s);
      // Sem sinal no dia: a OS em andamento entra lá embaixo, para o dono não ter de procurar.
      const base = ATIVOS.has(o.status) ? 0.5 : 0;
      const total = nota + base;
      if (total <= 0) continue;
      lista.push({
        id: s.id,
        numero: o.service_order_number,
        barco: o.vessels?.name ?? null,
        cliente: o.clients?.name ?? null,
        status: o.status,
        nota: total,
        motivos: nota > 0 ? motivos : ["em andamento"],
      });
    }
    lista.sort((a, b) => b.nota - a.nota);
    resposta[dia] = lista.slice(0, 6);
  }
  return resposta;
}

// ---------------------------------------------------------------------------------------------
// mover
// ---------------------------------------------------------------------------------------------
type Item = { id: string; nome: string; dia: string };
type Resultado = { ".tag": "success" | "failure"; success?: { metadata: Meta }; failure?: unknown };
type Meta = { ".tag": string; id: string; name: string; path_display: string; path_lower: string; size?: number; server_modified?: string; content_hash?: string };

async function mover(admin: Admin, dbx: Dropbox, base: string, p: { itens: Item[]; orderId?: string; vesselId?: string }) {
  let ordem: { id: string; service_order_number: string; vessel_id: string } | null = null;
  let vesselId = p.vesselId ?? null;
  if (p.orderId) {
    const { data, error } = await admin.from("service_orders").select("id, service_order_number, vessel_id").eq("id", p.orderId).maybeSingle();
    if (error || !data) throw new Error("OS não encontrada");
    ordem = data;
    vesselId = data.vessel_id;
  }
  if (!vesselId) throw new Error("Escolha a OS ou o barco.");
  const { data: barco } = await admin.from("vessels").select("id, name, client_id, clients(name)").eq("id", vesselId).maybeSingle();
  if (!barco) throw new Error("Barco não encontrado");

  const pasta = await garantirPastaDoBarco(admin, dbx, {
    vesselId: barco.id, clientId: barco.client_id, barco: barco.name, cliente: barco.clients?.name ?? null, pastaBase: base,
  });
  const { data: registro } = await admin.from("pastas_dropbox").select("id").eq("dropbox_id", pasta.id).maybeSingle();

  const entradas = p.itens.map((i) => ({
    from_path: i.id,
    to_path: `${pastaDasFotos(pasta.caminho, i.dia, ordem?.service_order_number)}/${i.nome}`.normalize("NFC"),
  }));
  type Lote = { ".tag": string; async_job_id?: string; entries?: Resultado[] };
  let r = await dbx.rpc<Lote>("files/move_batch_v2", { entries: entradas, autorename: true });
  const trabalho = r[".tag"] === "async_job_id" ? r.async_job_id : null;
  if (trabalho) {
    for (let i = 0; ; i++) {
      if (i >= 25) return { pendente: true, pasta: pasta.caminho, aviso: "O Dropbox ainda está movendo; atualize a lista daqui a pouco." };
      await new Promise((ok) => setTimeout(ok, 1000));
      r = await dbx.rpc<Lote>("files/move_batch/check_v2", { async_job_id: trabalho });
      if (r[".tag"] !== "in_progress") break;
    }
  }
  if (r[".tag"] === "failed") throw new ErroDropbox("O Dropbox recusou mover as fotos.", 409, "move_failed", false);

  const movidas = (r.entries ?? []).filter((e) => e[".tag"] === "success" && e.success?.metadata).map((e) => e.success!.metadata);
  if (movidas.length) {
    const linhas = movidas.map((m) => ({
      dropbox_id: m.id,
      caminho: m.path_display,
      caminho_lower: m.path_lower,
      nome: m.name,
      extensao: extensaoDe(m.name),
      tamanho: m.size ?? null,
      modificado_em: m.server_modified ?? null,
      content_hash: m.content_hash ?? null,
      pasta_id: registro?.id ?? null,
      order_id: ordem?.id ?? null,
      origem: "dono",
      apagado: false,
    }));
    const { error } = await admin.from("arquivos_dropbox").upsert(linhas, { onConflict: "dropbox_id" });
    if (error) console.warn("[dropbox-fotos] índice:", error.message);
  }
  return {
    movidas: movidas.length,
    falharam: (r.entries ?? []).length - movidas.length,
    pasta: pasta.caminho,
    destino: pastaDasFotos(pasta.caminho, p.itens[0]?.dia ?? "", ordem?.service_order_number),
  };
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);
  const porta = await usuarioAtivo(req, ["admin"]);
  if (!porta.ok) return recusa(porta, corsHeaders);

  const corpo = await req.json().catch(() => ({})) as Record<string, unknown>;
  const admin = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "", {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    if (corpo.acao === "sugestoes") {
      const dias = (Array.isArray(corpo.dias) ? corpo.dias : []).map(String).filter((d) => DIA.test(d)).slice(0, 60);
      if (!dias.length) return jr({ error: "Informe os dias." }, 400);
      return jr({ sugestoes: await sugestoes(admin, dias) });
    }

    const dbx = await abrirDropbox(admin);
    if (!dbx) return jr({ error: "O Dropbox não está conectado (Configurações › Integrações)." }, 400);
    const cfg = await config(admin);

    if (corpo.acao === "listar") return jr({ pasta: cfg.camera, itens: await listar(dbx, cfg.camera) });

    if (corpo.acao === "miniaturas") {
      const ids = (Array.isArray(corpo.ids) ? corpo.ids : []).map(String).filter((i) => ID.test(i)).slice(0, 25);
      if (!ids.length) return jr({ miniaturas: {} });
      const r = await dbx.rpcConteudo<{ entries: Array<{ ".tag": string; metadata?: { id: string }; thumbnail?: string }> }>(
        "files/get_thumbnail_batch",
        { entries: ids.map((path) => ({ path, format: { ".tag": "jpeg" }, size: { ".tag": "w256h256" }, mode: { ".tag": "bestfit" } })) },
      );
      const miniaturas: Record<string, string> = {};
      r.entries.forEach((e, i) => {
        if (e[".tag"] === "success" && e.thumbnail) miniaturas[e.metadata?.id ?? ids[i]] = e.thumbnail;
      });
      return jr({ miniaturas });
    }

    if (corpo.acao === "mover") {
      const itens = (Array.isArray(corpo.itens) ? corpo.itens : [])
        .map((x) => x as Item)
        .filter((x) => x && ID.test(String(x.id)) && DIA.test(String(x.dia)) && typeof x.nome === "string" && x.nome && !/[\\/]/.test(x.nome))
        .slice(0, 200);
      if (!itens.length) return jr({ error: "Nenhuma foto válida para mover." }, 400);
      const orderId = typeof corpo.order_id === "string" ? corpo.order_id : undefined;
      const vesselId = typeof corpo.vessel_id === "string" ? corpo.vessel_id : undefined;
      return jr(await mover(admin, dbx, cfg.base, { itens, orderId, vesselId }));
    }

    return jr({ error: "ação desconhecida" }, 400);
  } catch (e) {
    const msg = (e as Error).message;
    console.error("[dropbox-fotos]", corpo.acao, msg);
    return jr({ error: msg }, e instanceof ErroDropbox && !e.repetivel ? 409 : 502);
  }
});
