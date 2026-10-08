// A pasta do barco no Dropbox (Fase 2B, 08/10/2026 — plans/marineflow-dropbox-fase2.md).
//
// Barco que já tem pasta registrada (pastas_dropbox, vinculada): usa ESSA, pelo id do Dropbox —
// o dono pode ter renomeado ou movido; o caminho é atualizado, nada é renomeado do nosso lado.
// Barco sem pasta: reserva o próximo número (proximo_codigo_projeto), cria
// <pasta-base>/<NNNN.SSS.AA>_<Barco> com as subpastas do modelo do dono e registra.
import { Dropbox, ErroDropbox } from "./cliente.ts";
import { nomeDaPasta, SUBPASTAS } from "./nucleo.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

export type PastaDoBarco = { id: string; caminho: string; codigo: string | null; criada: boolean };

type Metadados = { id: string; path_display: string };

async function metadadosPorId(dbx: Dropbox, id: string): Promise<Metadados | null> {
  try {
    return await dbx.rpc<Metadados>("files/get_metadata", { path: id });
  } catch (e) {
    if (e instanceof ErroDropbox && e.resumo.startsWith("path/not_found")) return null;
    throw e;
  }
}

/** Cria a pasta; se já existir uma com o mesmo nome, devolve a existente. */
async function criarOuAchar(dbx: Dropbox, caminho: string): Promise<Metadados> {
  try {
    const r = await dbx.rpc<{ metadata: Metadados }>("files/create_folder_v2", { path: caminho.normalize("NFC"), autorename: false });
    return r.metadata;
  } catch (e) {
    if (e instanceof ErroDropbox && e.resumo.startsWith("path/conflict/folder")) {
      return await dbx.rpc<Metadados>("files/get_metadata", { path: caminho.normalize("NFC") });
    }
    throw e;
  }
}

export async function garantirPastaDoBarco(admin: Admin, dbx: Dropbox, p: {
  vesselId: string;
  clientId: string;
  barco: string | null;
  cliente: string | null;
  pastaBase: string;
}): Promise<PastaDoBarco> {
  const { data: existentes, error } = await admin
    .from("pastas_dropbox")
    .select("id, dropbox_id, caminho, codigo_projeto")
    .eq("vessel_id", p.vesselId)
    .eq("situacao", "vinculada")
    .order("codigo_projeto", { ascending: false, nullsFirst: false })
    .order("created_at", { ascending: true });
  if (error) throw new Error(`não consegui ler as pastas do barco (${error.message})`);

  for (const reg of existentes ?? []) {
    const m = await metadadosPorId(dbx, reg.dropbox_id);
    if (!m) continue; // apagada no Dropbox: tenta a próxima registrada
    if (m.path_display !== reg.caminho) {
      await admin.from("pastas_dropbox").update({ caminho: m.path_display }).eq("id", reg.id);
    }
    return { id: reg.dropbox_id, caminho: m.path_display, codigo: reg.codigo_projeto, criada: false };
  }

  // Sem pasta: número novo.
  const { data: codigo, error: eCod } = await admin.rpc("proximo_codigo_projeto");
  if (eCod || !codigo) throw new Error(`não consegui o próximo número de projeto (${eCod?.message ?? "vazio"})`);
  const base = p.pastaBase.replace(/\/+$/, "");
  const raiz = await criarOuAchar(dbx, `${base}/${nomeDaPasta(String(codigo), p.barco, p.cliente)}`);

  // Subpastas em lote (um pedido só; se o Dropbox responder "em andamento", elas aparecem sozinhas).
  try {
    await dbx.rpc("files/create_folder_batch", {
      paths: SUBPASTAS.map((s) => `${raiz.path_display}/${s}`.normalize("NFC")),
      autorename: false,
      force_async: false,
    });
  } catch (e) {
    console.warn("[dropbox] subpastas:", (e as Error).message);
  }

  const { error: eIns } = await admin.from("pastas_dropbox").insert({
    dropbox_id: raiz.id,
    caminho: raiz.path_display,
    client_id: p.clientId,
    vessel_id: p.vesselId,
    codigo_projeto: String(codigo),
    situacao: "vinculada",
    observacao: `Criada pelo sistema em ${new Date().toISOString().slice(0, 10)}.`,
  });
  if (eIns) {
    // Número já usado por outra (corrida) ou pasta já registrada: a próxima rodada resolve.
    throw new ErroDropbox(`não consegui registrar a pasta (${eIns.message})`, 409, "registro", true);
  }
  return { id: raiz.id, caminho: raiz.path_display, codigo: String(codigo), criada: true };
}
