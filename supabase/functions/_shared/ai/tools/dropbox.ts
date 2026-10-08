// Ferramentas do assistente sobre o Dropbox (Fase 5, 08/10/2026 — plans/marineflow-dropbox-fase2.md).
//
//   buscar_arquivos_do_barco   — lista o que está nas pastas do barco (índice arquivos_dropbox);
//   consultar_pasta_do_barco   — a pasta do barco: número, link e o que tem em cada subpasta;
//   enviar_arquivo_do_dropbox  — manda um PDF do Dropbox para o WhatsApp de QUEM PEDIU.
//
// As duas consultas leem só o índice no banco (nada de chamar o Dropbox): rápidas, e o nome
// "buscar_/consultar_" diz a verdade. O envio baixa do Dropbox, guarda por minutos no bucket
// privado pdf-agente e manda pela URL assinada — o whatsapp-send só aceita arquivo do próprio
// Storage (a Evolution roda no PC da empresa: trava contra SSRF). Só PDF até 25 MB (o bucket e o
// envio de documento da Evolution são de PDF); o resto volta com o link do Dropbox.
// Só administrador: as tabelas do Dropbox são só dele.
import type { ToolCtx, ToolDef } from "./registry.ts";
import { blockTechnician } from "./registry.ts";
import { enviarDocumentoWhatsapp } from "./whatsapp.ts";
import { chaveDeEnvio, liberarEnvio } from "../../whatsapp/idempotencia.ts";
import { desviadoPorTeste } from "../../whatsapp/marcar-enviado.ts";
import { BUCKET_DO_PDF, VALIDADE_DA_URL_S } from "../../pdf/gerar-e-guardar.ts";
import { abrirDropbox, ErroDropbox } from "../../dropbox/cliente.ts";
import { linkNoSite } from "../../dropbox/nucleo.ts";
import { type Candidato, chaveDeNome, escolherBarco } from "../dropbox-busca.ts";

const SO_ADMIN = ["admin"] as const;
const CONTEXTO = "agente_arquivo_dropbox";
const LIMITE_PDF = 25 * 1024 * 1024;

// deno-lint-ignore no-explicit-any
type Admin = any;

function soAdmin(ctx: ToolCtx) {
  const b = blockTechnician(ctx);
  if (b) return b;
  if (ctx.userRole !== "admin") return { error: "Os arquivos do Dropbox são só do administrador." };
  return null;
}

/** O barco a partir do texto (nome do barco ou do dono) ou do id. */
async function acharBarco(admin: Admin, termo: string): Promise<{ ok: true; barco: Candidato } | { error: string; opcoes?: unknown }> {
  const t = (termo ?? "").trim();
  if (!t) return { error: "Diga de qual barco (nome do barco ou do dono)." };
  const { data, error } = await admin.from("vessels").select("id, name, clients(name)").eq("active", true);
  if (error) return { error: `Falha ao ler os barcos: ${error.message}` };
  const candidatos: Candidato[] = (data ?? []).map((v: { id: string; name: string; clients: { name: string } | null }) => ({
    id: v.id,
    nome: v.name,
    cliente: v.clients?.name ?? null,
  }));
  if (/^[0-9a-f-]{36}$/i.test(t)) {
    const c = candidatos.find((x) => x.id === t);
    return c ? { ok: true, barco: c } : { error: "Esse barco não existe (ou está inativo)." };
  }
  const e = escolherBarco(t, candidatos);
  if (e.ok) return { ok: true, barco: e.barco };
  return { error: e.erro, ...(e.opcoes ? { opcoes: e.opcoes.map((o) => `${o.nome} (${o.cliente ?? "sem dono"}) — id ${o.id}`) } : {}) };
}

type Pasta = { id: string; caminho: string; codigo_projeto: string | null; situacao: string };

async function pastasDoBarco(admin: Admin, vesselId: string): Promise<Pasta[]> {
  const { data, error } = await admin.from("pastas_dropbox")
    .select("id, caminho, codigo_projeto, situacao")
    .eq("vessel_id", vesselId)
    .in("situacao", ["vinculada", "arquivo"]);
  if (error) throw new Error(`Falha ao ler as pastas: ${error.message}`);
  return (data ?? []) as Pasta[];
}

function subpastaDe(caminho: string, nome: string, base: string): string {
  const dir = caminho.slice(0, caminho.length - nome.length - 1);
  return dir.toLowerCase().startsWith(base.toLowerCase()) ? dir.slice(base.length).replace(/^\/+/, "") || "(pasta principal)" : dir;
}

function tamanhoLegivel(b: number | null): string {
  if (!b) return "—";
  return b < 1048576 ? `${Math.max(1, Math.round(b / 1024))} KB` : `${(b / 1048576).toFixed(1).replace(".", ",")} MB`;
}

export const dropboxTools: ToolDef[] = [
  {
    name: "buscar_arquivos_do_barco",
    description:
      "Lista os arquivos que estão nas pastas do Dropbox de um barco (orçamentos, propostas, desenhos DWG, diagramas, fotos, planilhas). Use para 'tem desenho do painel do Madu I?', 'quais arquivos do Donna V', 'o último orçamento do barco do Acrisio no Dropbox'. Aceita o nome do barco ou do dono. Filtra por texto no nome/subpasta e por extensão. Devolve o id de cada arquivo para enviar_arquivo_do_dropbox.",
    input_schema: {
      type: "object",
      properties: {
        barco: { type: "string", description: "Nome do barco ou do dono (ou o id do barco)." },
        busca: { type: "string", description: "Texto no nome do arquivo ou da subpasta (ex.: 'painel', 'orçamento', 'DWG')." },
        extensao: { type: "string", description: "Só esta extensão (pdf, dwg, jpg, xlsx...)." },
        limite: { type: "number", description: "Máximo de arquivos (padrão 15, máximo 50)." },
      },
      required: ["barco"],
    },
    risk: "low",
    roles: [...SO_ADMIN],
    async execute(args, ctx) {
      const negado = soAdmin(ctx);
      if (negado) return negado;
      const achado = await acharBarco(ctx.admin, String(args.barco ?? ""));
      if (!("ok" in achado)) return achado;
      const { barco } = achado;
      const pastas = await pastasDoBarco(ctx.admin, barco.id);
      if (!pastas.length) {
        return { barco: barco.nome, dono: barco.cliente, arquivos: [], aviso: "Esse barco ainda não tem pasta no Dropbox (ela nasce no primeiro orçamento ou OS)." };
      }
      const base = new Map(pastas.map((p) => [p.id, p.caminho]));
      const limite = Math.min(Math.max(Number(args.limite) || 15, 1), 50);
      let q = ctx.admin.from("arquivos_dropbox")
        .select("id, nome, caminho, extensao, tamanho, modificado_em, pasta_id")
        .in("pasta_id", [...base.keys()])
        .eq("apagado", false)
        .order("modificado_em", { ascending: false })
        .limit(500);
      const ext = String(args.extensao ?? "").replace(/^\./, "").toLowerCase().trim();
      if (ext) q = q.eq("extensao", ext);
      const { data, error } = await q;
      if (error) return { error: `Falha ao ler os arquivos: ${error.message}` };
      const busca = chaveDeNome(String(args.busca ?? ""));
      type Linha = { id: string; nome: string; subpasta: string; data: string | null; tamanho: string; extensao: string | null };
      const todos: Linha[] = (data ?? []).map((a: { id: string; nome: string; caminho: string; extensao: string | null; tamanho: number | null; modificado_em: string | null; pasta_id: string }) => ({
        id: a.id,
        nome: a.nome,
        subpasta: subpastaDe(a.caminho, a.nome, base.get(a.pasta_id) ?? ""),
        data: a.modificado_em ? a.modificado_em.slice(0, 10) : null,
        tamanho: tamanhoLegivel(a.tamanho),
        extensao: a.extensao,
      }));
      const achados = busca ? todos.filter((a: Linha) => chaveDeNome(`${a.nome} ${a.subpasta}`).includes(busca)) : todos;
      return {
        barco: barco.nome,
        dono: barco.cliente,
        total: achados.length,
        arquivos: achados.slice(0, limite),
        ...(achados.length > limite ? { aviso: `Mostrando ${limite} de ${achados.length}, do mais recente.` } : {}),
        dica: "Para mandar um PDF para o WhatsApp de quem pediu, use enviar_arquivo_do_dropbox com o id.",
      };
    },
  },
  {
    name: "consultar_pasta_do_barco",
    description:
      "A pasta do barco no Dropbox: o número do projeto (0016.013.25), o link para abrir (só abre logado na conta da HBR) e quantos arquivos há em cada subpasta, com os mais recentes. Use para 'qual a pasta do Donna V', 'me manda o link da pasta do Madu I', 'o que tem na pasta do barco do Ribas'.",
    input_schema: {
      type: "object",
      properties: { barco: { type: "string", description: "Nome do barco ou do dono (ou o id do barco)." } },
      required: ["barco"],
    },
    risk: "low",
    roles: [...SO_ADMIN],
    async execute(args, ctx) {
      const negado = soAdmin(ctx);
      if (negado) return negado;
      const achado = await acharBarco(ctx.admin, String(args.barco ?? ""));
      if (!("ok" in achado)) return achado;
      const { barco } = achado;
      const pastas = await pastasDoBarco(ctx.admin, barco.id);
      if (!pastas.length) {
        return { barco: barco.nome, dono: barco.cliente, pasta: null, aviso: "Esse barco ainda não tem pasta no Dropbox (ela nasce no primeiro orçamento ou OS)." };
      }
      const principal = pastas.filter((p) => p.situacao === "vinculada")
        .sort((a, b) => (b.codigo_projeto ?? "").localeCompare(a.codigo_projeto ?? ""))[0] ?? pastas[0];
      const { data, error } = await ctx.admin.from("arquivos_dropbox")
        .select("nome, caminho, modificado_em")
        .eq("pasta_id", principal.id)
        .eq("apagado", false)
        .order("modificado_em", { ascending: false })
        .limit(2000);
      if (error) return { error: `Falha ao ler os arquivos: ${error.message}` };
      const porSubpasta = new Map<string, number>();
      for (const a of data ?? []) {
        const sub = subpastaDe(a.caminho, a.nome, principal.caminho).split("/")[0];
        porSubpasta.set(sub, (porSubpasta.get(sub) ?? 0) + 1);
      }
      return {
        barco: barco.nome,
        dono: barco.cliente,
        numero_do_projeto: principal.codigo_projeto,
        caminho: principal.caminho,
        link: linkNoSite(principal.caminho),
        total_de_arquivos: data?.length ?? 0,
        por_subpasta: Object.fromEntries(porSubpasta),
        mais_recentes: (data ?? []).slice(0, 5).map((a: { nome: string; modificado_em: string | null }) => `${a.nome} (${a.modificado_em?.slice(0, 10) ?? "—"})`),
        ...(pastas.length > 1 ? { outras_pastas: pastas.filter((p) => p.id !== principal.id).map((p) => p.caminho) } : {}),
        observacao: "O link abre no site do Dropbox e exige estar logado na conta da HBR.",
      };
    },
  },
  {
    name: "enviar_arquivo_do_dropbox",
    description:
      "Manda um arquivo PDF do Dropbox para o WhatsApp de QUEM ESTÁ PEDINDO (nunca para cliente). Use o id que veio de buscar_arquivos_do_barco. Só PDF até 25 MB; outro tipo (DWG, foto, planilha) volta com o link do Dropbox para abrir. No painel, devolve o link em vez de mandar.",
    input_schema: {
      type: "object",
      properties: { arquivo_id: { type: "string", description: "O id do arquivo (de buscar_arquivos_do_barco)." } },
      required: ["arquivo_id"],
    },
    // Vai só para quem pede, e é arquivo dele: nada a confirmar (como send_document_pdf_to_self).
    risk: "low",
    roles: [...SO_ADMIN],
    async execute(args, ctx) {
      const negado = soAdmin(ctx);
      if (negado) return negado;
      const { admin } = ctx;
      const id = String(args.arquivo_id ?? "").trim();
      if (!/^[0-9a-f-]{36}$/i.test(id)) return { error: "Preciso do id do arquivo (use buscar_arquivos_do_barco antes)." };
      const { data: arq, error } = await admin.from("arquivos_dropbox")
        .select("id, dropbox_id, nome, caminho, extensao, tamanho, modificado_em, apagado").eq("id", id).maybeSingle();
      if (error) return { error: `Falha ao ler o arquivo: ${error.message}` };
      if (!arq || arq.apagado) return { error: "Esse arquivo não está mais no Dropbox." };
      const dir = arq.caminho.slice(0, arq.caminho.length - arq.nome.length - 1);
      const link = `${linkNoSite(dir)}?preview=${encodeURIComponent(arq.nome)}`;

      if (ctx.canal === "panel") return { arquivo: arq.nome, link, observacao: "No painel: abra pelo link (exige login na conta da HBR)." };
      if (arq.extensao !== "pdf") {
        return { arquivo: arq.nome, link, observacao: `Só mando PDF pelo WhatsApp; este é ${arq.extensao ?? "sem extensão"}. Mande o link (abre logado na conta da HBR).` };
      }
      if ((arq.tamanho ?? 0) > LIMITE_PDF) return { arquivo: arq.nome, link, observacao: "O PDF passa de 25 MB: mande o link." };

      const { data: u, error: uErr } = await admin.from("app_users").select("phone_normalized").eq("id", ctx.userId).maybeSingle();
      if (uErr) return { error: `Falha ao ler o seu cadastro: ${uErr.message}` };
      const telefone = String(u?.phone_normalized ?? "").replace(/\D/g, "");
      if (!telefone) return { error: "Você não tem um WhatsApp cadastrado para receber o arquivo.", link };

      const dbx = await abrirDropbox(admin);
      if (!dbx) return { error: "O Dropbox não está conectado (Configurações › Integrações).", link };
      let bytes: Uint8Array<ArrayBuffer>;
      try {
        bytes = (await dbx.baixar(arq.dropbox_id, LIMITE_PDF)).bytes;
      } catch (e) {
        const msg = e instanceof ErroDropbox ? e.message : String(e);
        return { error: `Não consegui baixar do Dropbox: ${msg}`, link };
      }

      const chave = chaveDeEnvio("agente-dropbox", arq.id, telefone, arq.modificado_em ?? "", Math.floor(Date.now() / 120_000));
      const caminho = `agente/${new Date().getUTCFullYear()}/${crypto.randomUUID()}.pdf`;
      const armazem = admin.storage.from(BUCKET_DO_PDF);
      const { error: upErr } = await armazem.upload(caminho, bytes, { contentType: "application/pdf", upsert: false });
      if (upErr) return { error: `Não consegui preparar o arquivo (${upErr.message}).`, link };
      try {
        const { data: assinada, error: urlErr } = await armazem.createSignedUrl(caminho, VALIDADE_DA_URL_S);
        if (urlErr || !assinada?.signedUrl) return { error: "Não consegui gerar o endereço do arquivo.", link };
        const envio = await enviarDocumentoWhatsapp({
          phone: telefone,
          url: assinada.signedUrl,
          filename: arq.nome.slice(0, 120),
          caption: `📁 ${arq.nome}`.slice(0, 1000),
          context: CONTEXTO,
          jwt: ctx.jwt,
          dedupeKey: chave,
        });
        if (!envio.ok) {
          if (envio.semResposta) await liberarEnvio(admin, chave).catch(() => {});
          return { error: `Não consegui mandar: ${envio.error}`, link };
        }
        if (envio.deduplicated) return { ok: true, deduplicated: true, aviso: "Esse arquivo já foi mandado há instantes; não reenviei." };
        const teste = desviadoPorTeste(ctx.settings);
        return {
          ok: true,
          arquivo: arq.nome,
          enviado_para: teste ? "o número de TESTE do WhatsApp (modo de teste ligado)" : "o WhatsApp de quem pediu",
        };
      } finally {
        await armazem.remove([caminho]).catch(() => {});
      }
    },
  },
];
