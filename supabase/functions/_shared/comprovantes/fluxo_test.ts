// A orquestração da edge comprovantes-whatsapp contra um banco falso que devolve exatamente as
// formas das RPCs da spec (seção 4.3). Sem rede: Evolution, Storage, Dropbox, whatsapp-send e
// ai-agent são dublês que registram o que receberam.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  atualizarIndice,
  atualizarIndicePessoal,
  completar,
  consultarCnpj,
  type DependenciasDoFluxo,
  desempatar,
  type DropboxDoFluxo,
  entregar,
  logDoFluxo,
  moverNoDropbox,
  pendentes,
  perguntarBanco,
  perguntarProximo,
  processarArquivo,
  receber,
  repescar,
  responder,
  retomar,
  subirNoDropbox,
  talvezAvisar,
  vigiar,
} from "./fluxo.ts";
import { type DadosDoArquivo, type ItemDoAviso, PASTA_A_CLASSIFICAR } from "./nucleo.ts";
import type { ResultadoDoDownload } from "./midia.ts";
import { ErroDropbox } from "../dropbox/cliente.ts";

// ─── dublês ───────────────────────────────────────────────────────────────────────────────

const DONO = { id: "0d0d0d0d-0000-4000-8000-000000000001", phone: "5547999990000" };
const MSG_ID = "11111111-0000-4000-8000-000000000001";
const CMP_ID = "22222222-0000-4000-8000-000000000001";
const JOB_ID = "33333333-0000-4000-8000-000000000001";
const LEGENDA_SECRETA = "cupom Posto Segredo da Praia";
const CNPJ = "11222333000181";

type Linha = Record<string, unknown>;
// deno-lint-ignore no-explicit-any
type Qualquer = any;

function caminhoJson(l: Linha, coluna: string): unknown {
  return coluna.split("->").reduce<unknown>((v, k) => (v && typeof v === "object" ? (v as Linha)[k] : undefined), l);
}

/** Banco falso: tabelas em memória (select com filtros), inserts registrados, RPCs programadas. */
function bancoFalso(op: {
  rpc?: Record<string, (args: Qualquer) => { data?: unknown; error?: unknown } | unknown>;
  tabelas?: Record<string, Linha[]>;
  falhaNoUpload?: boolean;
  falhaNoRemove?: boolean;
} = {}) {
  const tabelas: Record<string, Linha[]> = {
    app_users: [{ id: DONO.id, phone_normalized: DONO.phone, role: "admin", active: true, ai_whatsapp_enabled: true, created_at: "2025-01-01" }],
    app_settings: [{ key: "comprovante_fluxo", value: "dono" }],
    whatsapp_messages: [],
    ...op.tabelas,
  };
  const inseridos: Record<string, Linha[]> = {};
  const atualizados: Record<string, Array<{ dados: Linha; coluna: string; valor: unknown }>> = {};
  const chamadasRpc: Array<{ nome: string; args: Qualquer }> = [];
  const storage = { uploads: [] as Qualquer[], assinadas: [] as Qualquer[], removidos: [] as string[], baixados: [] as string[] };

  const admin = {
    rpc(nome: string, args: Qualquer) {
      chamadasRpc.push({ nome, args });
      const f = op.rpc?.[nome];
      if (!f) return Promise.resolve({ data: null, error: { code: "PGRST202", message: `sem dublê para ${nome}` } });
      const r = f(args) as Qualquer;
      if (r && typeof r === "object" && ("data" in r || "error" in r)) return Promise.resolve({ data: r.data ?? null, error: r.error ?? null });
      return Promise.resolve({ data: r, error: null });
    },
    from(tabela: string) {
      let linhas = [...(tabelas[tabela] ?? [])];
      const q: Qualquer = {
        select: () => q,
        eq: (c: string, v: unknown) => { linhas = linhas.filter((l) => caminhoJson(l, c) === v); return q; },
        in: (c: string, vs: unknown[]) => { linhas = linhas.filter((l) => vs.includes(caminhoJson(l, c))); return q; },
        gte: (c: string, v: string) => { linhas = linhas.filter((l) => String(caminhoJson(l, c)) >= v); return q; },
        not: (c: string, _op: string, _v: null) => { linhas = linhas.filter((l) => caminhoJson(l, c) != null); return q; },
        order: (c: string, o?: { ascending?: boolean }) => {
          linhas.sort((a, b) => String(a[c]).localeCompare(String(b[c])) * (o?.ascending === false ? -1 : 1));
          return q;
        },
        limit: (n: number) => { linhas = linhas.slice(0, n); return q; },
        maybeSingle: () => Promise.resolve({ data: linhas[0] ?? null, error: null }),
        single: () => Promise.resolve({ data: linhas[0] ?? null, error: null }),
        insert: (novas: Linha | Linha[]) => {
          (inseridos[tabela] ??= []).push(...(Array.isArray(novas) ? novas : [novas]));
          const r: Qualquer = Promise.resolve({ data: null, error: null });
          r.select = () => ({ single: () => Promise.resolve({ data: { id: "nova" }, error: null }) });
          return r;
        },
        update: (dados: Linha) => ({
          eq: (coluna: string, valor: unknown) => {
            (atualizados[tabela] ??= []).push({ dados, coluna, valor });
            for (const l of tabelas[tabela] ?? []) if (l[coluna] === valor) Object.assign(l, dados);
            return Promise.resolve({ data: null, error: null });
          },
        }),
        then: (ok: (v: unknown) => unknown, falha?: (e: unknown) => unknown) => Promise.resolve({ data: linhas, error: null }).then(ok, falha),
      };
      return q;
    },
    storage: {
      from: (bucket: string) => ({
        upload: (path: string, bytes: Uint8Array, opts: Qualquer) => {
          storage.uploads.push({ bucket, path, bytes, opts });
          return Promise.resolve({ data: op.falhaNoUpload ? null : { path }, error: op.falhaNoUpload ? { message: "x" } : null });
        },
        createSignedUrl: (path: string, segundos: number) => {
          storage.assinadas.push({ bucket, path, segundos });
          return Promise.resolve({ data: { signedUrl: `https://ref.supabase.co/storage/v1/object/sign/${bucket}/${path}?token=t` }, error: null });
        },
        download: (path: string) => {
          storage.baixados.push(path);
          return Promise.resolve({ data: new Blob([new TextEncoder().encode("%PDF-1.7 cmp")]), error: null });
        },
        remove: (paths: string[]) => {
          storage.removidos.push(...paths);
          return Promise.resolve({ data: [], error: op.falhaNoRemove ? { message: "x" } : null });
        },
      }),
    },
  };
  return { admin, tabelas, inseridos, atualizados, chamadasRpc, storage };
}

const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 5]);

function depsFalsas(banco: ReturnType<typeof bancoFalso>, op: {
  baixar?: ResultadoDoDownload | ((chave: unknown) => Promise<ResultadoDoDownload>);
  dropbox?: "ok" | "sem_conexao" | "erro";
  envio?: number;
  agora?: () => Date;
} = {}) {
  const reacoes: Array<{ phone: string; id: string; emoji: string }> = [];
  const envios: Array<{ url: string; corpo: Qualquer }> = [];
  const dropboxEnvios: Array<{ caminho: string; bytes: Uint8Array }> = [];
  const logs: Array<{ evento: string; campos?: Qualquer }> = [];
  const fundo: Promise<unknown>[] = [];
  let downloads = 0;
  const chavesBaixadas: unknown[] = [];
  const deps: DependenciasDoFluxo = {
    admin: banco.admin,
    whatsapp: {
      sendReaction: (phone, id, _fromMe, emoji) => {
        reacoes.push({ phone, id, emoji });
        return Promise.resolve({ ok: true });
      },
    },
    dropbox: () => {
      if (op.dropbox === "sem_conexao") return Promise.resolve(null);
      return Promise.resolve({
        enviar: (caminho: string, bytes: Uint8Array) => {
          if (op.dropbox === "erro") return Promise.reject(Object.assign(new Error("x"), { status: 429, resumo: "too_many_write_operations" }));
          dropboxEnvios.push({ caminho, bytes });
          return Promise.resolve({ id: "id:abcDEF_12-3", path_display: caminho, rev: "015f00" });
        },
        // os métodos da F2 (os testes da F1 não chegam a eles; os da F2 usam o dropboxFalso)
        mover: () => Promise.reject(new Error("sem dublê")),
        substituir: () => Promise.reject(new Error("sem dublê")),
        criarPasta: () => Promise.reject(new Error("sem dublê")),
        rpc: () => Promise.reject(new Error("sem dublê")),
      } as DropboxDoFluxo);
    },
    fetch: ((url: string, init?: RequestInit) => {
      envios.push({ url, corpo: JSON.parse(String(init?.body ?? "{}")) });
      const status = url.includes("whatsapp-send") ? (op.envio ?? 200) : 200;
      return Promise.resolve(new Response(JSON.stringify(status === 200 ? { success: true } : { error: "x" }), { status }));
    }) as typeof fetch,
    agora: op.agora ?? (() => new Date("2026-10-10T22:41:00Z")),
    log: (evento, campos) => logs.push({ evento, campos }),
    supabaseUrl: "https://ref.supabase.co",
    serviceRoleKey: "srv",
    internalSecret: "interno",
    waitUntil: (p) => fundo.push(p),
    baixar: (chave) => {
      downloads++;
      chavesBaixadas.push(chave);
      if (typeof op.baixar === "function") return op.baixar(chave);
      return Promise.resolve(op.baixar ?? { ok: true, bytes: JPEG, mimeDeclarado: "image/jpeg" });
    },
    sessaoDoWhatsApp: () => Promise.resolve("sessao-1"),
  };
  return {
    deps, reacoes, envios, dropboxEnvios, logs, chavesBaixadas,
    esperarFundo: async () => { while (fundo.length) await fundo.shift(); },
    downloads: () => downloads,
  };
}

/** A key da Evolution do jeito que o webhook grava (id = wa_message_id, conversa do telefone). */
const chaveDe = (waId: string, phone = DONO.phone, extra: Linha = {}) => ({ id: waId, remoteJid: `${phone}@s.whatsapp.net`, fromMe: false, ...extra });

function mensagem(extra: Linha = {}, message: Linha = { imageMessage: { caption: LEGENDA_SECRETA, mimetype: "image/jpeg", fileLength: 9 } }): Linha {
  const waId = String(extra.wa_message_id ?? "WAID1");
  const phone = String(extra.phone_normalized ?? DONO.phone);
  return {
    id: MSG_ID,
    wa_message_id: waId,
    phone_normalized: DONO.phone,
    message_type: "image",
    direction: "inbound",
    occurred_at: "2026-10-10T22:40:57Z",
    raw_payload: { event: "messages.upsert", data: { key: chaveDe(waId, phone), message } },
    ...extra,
  };
}

/** O item que o receber/vigia passam ao processarArquivo: a key guardada na linha. */
const ITEM = { id: CMP_ID, chave: chaveDe("WAID1"), phone: DONO.phone, wa_message_id: "WAID1", recebido_em: "2026-10-10T22:40:57Z" };

const CORPO_RECEBER = { message_id: MSG_ID, modo: "dono", rota: "comprovante", dono_id: DONO.id };

const GUARDADO = {
  id: CMP_ID, decisao: "na_fila", situacao: "na_fila", codigo: "CMP-00123", job_id: JOB_ID, duplicado: null,
  modo: "dono", rota: "comprovante", forcado: true, phone_normalized: DONO.phone, wa_message_id: "WAID1", apagar_arquivo_agora: false,
};

const DA: DadosDoArquivo = {
  id: CMP_ID, codigo: "CMP-00123", situacao: "lido", tipo: "nfce", valor: "62.00", valor_confianca: "alta",
  data_compra: "2026-10-08", hora_compra: "12:57:56", recebido_em: "2026-10-10T22:40:57Z",
  fornecedor_nome: "Auto Posto Exemplo", arquivo_path: `2026/10/${CMP_ID}.jpg`, arquivo_mime: "image/jpeg",
};

const ITEM_CMP: ItemDoAviso = {
  id: CMP_ID, codigo: "CMP-00123", decisao: "cmp", tipo: "nfce", valor: "62.00", valor_confianca: "alta",
  data_compra: "2026-10-08", fornecedor_nome: "Auto Posto Exemplo", emitente_cnpj: CNPJ, cnpj_confianca: "alta",
  recebido_em: "2026-10-10T22:40:57Z", erro: null, duplicado: null,
};

const rpcs = (b: ReturnType<typeof bancoFalso>, nome: string) => b.chamadasRpc.filter((c) => c.nome === nome);

// ─── receber ──────────────────────────────────────────────────────────────────────────────

Deno.test("receber: entrada inválida é recusada sem tocar o banco", async () => {
  for (const corpo of [{}, { ...CORPO_RECEBER, message_id: "x" }, { ...CORPO_RECEBER, modo: "off" }, { ...CORPO_RECEBER, rota: "agente" }, { ...CORPO_RECEBER, dono_id: null }]) {
    const banco = bancoFalso();
    const { deps } = depsFalsas(banco);
    const r = await receber(corpo as Qualquer, deps);
    assertEquals(r, { status: 422, corpo: { aceito: false, motivo: "entrada_invalida" } });
    assertEquals(banco.chamadasRpc.length, 0);
  }
});

Deno.test("receber: telefone ou dono_id que não é o do dono = 422, sem registrar", async () => {
  const outroTelefone = bancoFalso({ tabelas: { whatsapp_messages: [mensagem({ phone_normalized: "5547988887777" })] } });
  assertEquals((await receber(CORPO_RECEBER, depsFalsas(outroTelefone).deps)).corpo.motivo, "dono_divergente");
  const outroDono = bancoFalso({ tabelas: { whatsapp_messages: [mensagem()] } });
  assertEquals((await receber({ ...CORPO_RECEBER, dono_id: "0d0d0d0d-0000-4000-8000-000000000999" }, depsFalsas(outroDono).deps)).corpo.motivo, "dono_divergente");
  const enviada = bancoFalso({ tabelas: { whatsapp_messages: [mensagem({ direction: "outbound" })] } });
  assertEquals((await receber(CORPO_RECEBER, depsFalsas(enviada).deps)).corpo.motivo, "nao_e_recebida");
  for (const b of [outroTelefone, outroDono, enviada]) assertEquals(rpcs(b, "comprovante_receber").length, 0);
});

Deno.test("receber: key de outra conversa, enviada pelo sistema ou de outra mensagem = 422, sem registrar nem baixar", async () => {
  for (const key of [
    chaveDe("WAID1", "5511988887777"), // a foto de um cliente
    chaveDe("WAID1", DONO.phone, { fromMe: true }),
    chaveDe("OUTRA", DONO.phone),
  ]) {
    const m = mensagem();
    (m.raw_payload as Qualquer).data.key = key;
    const banco = bancoFalso({ tabelas: { whatsapp_messages: [m] } });
    const d = depsFalsas(banco);
    assertEquals((await receber(CORPO_RECEBER, d.deps)).corpo, { aceito: false, motivo: "chave_divergente" });
    assertEquals(rpcs(banco, "comprovante_receber").length, 0);
    assertEquals(d.downloads(), 0);
  }
});

Deno.test("receber: mensagem sem mídia (texto) = 422 sem_midia", async () => {
  const banco = bancoFalso({ tabelas: { whatsapp_messages: [mensagem({ message_type: "text" }, { conversation: "oi" })] } });
  assertEquals((await receber(CORPO_RECEBER, depsFalsas(banco).deps)).corpo, { aceito: false, motivo: "sem_midia" });
});

Deno.test("receber: idempotente — a mesma mensagem (novo=false) responde e para", async () => {
  const banco = bancoFalso({
    tabelas: { whatsapp_messages: [mensagem()] },
    rpc: { comprovante_receber: () => ({ id: CMP_ID, novo: false, situacao: "na_fila" }) },
  });
  const d = depsFalsas(banco);
  const r = await receber(CORPO_RECEBER, d.deps);
  await d.esperarFundo();
  assertEquals(r, { status: 200, corpo: { aceito: true, id: CMP_ID, novo: false } });
  assertEquals(d.downloads(), 0);
  assertEquals(d.reacoes.length, 0);
});

Deno.test("receber: novo no modo dono — ⏳, baixa, guarda no bucket e entrega ao banco", async () => {
  const banco = bancoFalso({
    tabelas: { whatsapp_messages: [mensagem()] },
    rpc: {
      comprovante_receber: () => ({ id: CMP_ID, novo: true, situacao: "recebido" }),
      comprovante_guardar_arquivo: () => GUARDADO,
    },
  });
  const d = depsFalsas(banco);
  const r = await receber(CORPO_RECEBER, d.deps);
  assertEquals(r, { status: 200, corpo: { aceito: true, id: CMP_ID, novo: true } });
  await d.esperarFundo();

  const p = rpcs(banco, "comprovante_receber")[0].args.p;
  assertEquals(p.message_id, MSG_ID);
  assertEquals(p.wa_message_id, "WAID1");
  assertEquals(p.phone_normalized, DONO.phone);
  assertEquals(p.dono_id, DONO.id);
  assertEquals([p.modo, p.rota, p.origem, p.tipo_whatsapp], ["dono", "comprovante", "webhook", "image"]);
  assertEquals(p.forcado, false); // palavra-chave + texto livre: a classificação decide o CMP
  assertEquals(p.legenda, LEGENDA_SECRETA);
  assertEquals(p.dica_da_legenda, "Posto Segredo da Praia");
  assertEquals(p.mime_declarado, "image/jpeg");
  assertEquals(p.recebido_em, "2026-10-10T22:40:57Z");
  // a key conferida vai para a linha, e o download usa essa cópia
  assertEquals(p.wa_key, chaveDe("WAID1"));
  assertEquals(d.chavesBaixadas, [chaveDe("WAID1")]);

  assertEquals(d.reacoes, [{ phone: DONO.phone, id: "WAID1", emoji: "⏳" }]);
  assertEquals(banco.storage.uploads.length, 1);
  assertEquals(banco.storage.uploads[0].bucket, "comprovantes");
  assertEquals(banco.storage.uploads[0].path, `2026/10/${CMP_ID}.jpg`);
  assertEquals(banco.storage.uploads[0].opts, { contentType: "image/jpeg", upsert: true });
  assertEquals(banco.storage.assinadas[0].segundos, 86400);

  const g = rpcs(banco, "comprovante_guardar_arquivo")[0].args;
  assertEquals(g.p_id, CMP_ID);
  assertEquals(g.p_arquivo.path, `2026/10/${CMP_ID}.jpg`);
  assertEquals(g.p_arquivo.mime_real, "image/jpeg");
  assertEquals(g.p_arquivo.bytes, JPEG.length);
  assertEquals(g.p_arquivo.sha256.length, 64);
  assertStringIncludes(g.p_url, "/storage/v1/object/sign/comprovantes/");
  assert(g.p_url.startsWith("https://"));
});

Deno.test("receber: documento sem legenda — o nome do arquivo nunca vira legenda", async () => {
  const banco = bancoFalso({
    tabelas: { whatsapp_messages: [mensagem({ message_type: "document" }, { documentMessage: { fileName: "cupom posto.pdf", mimetype: "application/pdf" } })] },
    rpc: { comprovante_receber: () => ({ id: CMP_ID, novo: false, situacao: "na_fila" }) },
  });
  await receber(CORPO_RECEBER, depsFalsas(banco).deps);
  const p = rpcs(banco, "comprovante_receber")[0].args.p;
  assertEquals(p.legenda, null);
  assertEquals(p.forcado, false);
  assertEquals(p.nome_arquivo, "cupom posto.pdf");
  assertEquals(p.tipo_whatsapp, "document");
});

Deno.test("receber: modo sombra não reage nem fala com o dono", async () => {
  const banco = bancoFalso({
    tabelas: { whatsapp_messages: [mensagem()] },
    rpc: {
      comprovante_receber: () => ({ id: CMP_ID, novo: true, situacao: "recebido" }),
      comprovante_guardar_arquivo: () => ({ ...GUARDADO, modo: "sombra", rota: "ambos" }),
    },
  });
  const d = depsFalsas(banco);
  await receber({ ...CORPO_RECEBER, modo: "sombra", rota: "ambos" }, d.deps);
  await d.esperarFundo();
  assertEquals(d.reacoes.length, 0);
  assertEquals(d.envios.length, 0);
});

// ─── processarArquivo ─────────────────────────────────────────────────────────────────────

Deno.test("duplicado: apaga o próprio objeto, marca apagado, ✅ e tenta o aviso", async () => {
  const banco = bancoFalso({
    tabelas: { whatsapp_messages: [mensagem()] },
    rpc: {
      comprovante_guardar_arquivo: () => ({
        ...GUARDADO, decisao: "duplicado", situacao: "cancelado", codigo: null, job_id: null,
        duplicado: { codigo: "CMP-00098", data_compra: "2026-10-09", valor: "187.40" }, apagar_arquivo_agora: true,
      }),
      comprovante_arquivo_apagado: () => null,
      comprovante_reservar_aviso: () => ({ esperando: 0, itens: [] }),
    },
  });
  const d = depsFalsas(banco);
  assertEquals(await processarArquivo(ITEM, d.deps), "duplicado");
  assertEquals(banco.storage.removidos, [`2026/10/${CMP_ID}.jpg`]);
  assertEquals(rpcs(banco, "comprovante_arquivo_apagado")[0].args, { p_id: CMP_ID });
  assertEquals(d.reacoes, [{ phone: DONO.phone, id: "WAID1", emoji: "✅" }]);
  assertEquals(rpcs(banco, "comprovante_reservar_aviso")[0].args, { p_phone: DONO.phone, p_forcar: false });
});

Deno.test("formato não suportado: falha final; encaminha só porque o banco mandou; remove ⏳ e avisa", async () => {
  const banco = bancoFalso({
    tabelas: { whatsapp_messages: [mensagem()] },
    rpc: {
      comprovante_falhou: () => ({
        id: CMP_ID, final: true, proxima_em: null, situacao: "falhou", encaminhar: true, texto_para_assistente: "[document]",
        modo: "dono", forcado: false, phone_normalized: DONO.phone, wa_message_id: "WAID1", dono_id: DONO.id,
      }),
      comprovante_reservar_aviso: () => ({ esperando: 0, itens: [] }),
    },
  });
  const d = depsFalsas(banco, { baixar: { ok: true, bytes: new Uint8Array([0x50, 0x4b, 3, 4, 0, 0]), mimeDeclarado: null } });
  assertEquals(await processarArquivo(ITEM, d.deps), "falhou");
  await d.esperarFundo();
  assertEquals(rpcs(banco, "comprovante_falhou")[0].args, { p_id: CMP_ID, p_erro: "formato_nao_suportado" });
  assertEquals(banco.storage.uploads.length, 0);
  const agente = d.envios.filter((e) => e.url.endsWith("/functions/v1/ai-agent"));
  assertEquals(agente.length, 1);
  assertEquals(agente[0].corpo, { channel: "whatsapp", phone_normalized: DONO.phone, app_user_id: DONO.id, text: "[document]" });
  assertEquals(d.reacoes, [{ phone: DONO.phone, id: "WAID1", emoji: "" }]);
});

Deno.test("falha que o banco ignorou (linha já tratada): sem reação, aviso nem encaminhamento", async () => {
  const banco = bancoFalso({
    tabelas: { whatsapp_messages: [mensagem()] },
    rpc: {
      comprovante_falhou: () => ({
        id: CMP_ID, final: true, situacao: "falhou", encaminhar: false, texto_para_assistente: null,
        modo: "dono", forcado: true, phone_normalized: DONO.phone, wa_message_id: "WAID1", dono_id: DONO.id, ignorado: true,
      }),
    },
  });
  const d = depsFalsas(banco, { baixar: { ok: true, bytes: new Uint8Array([1, 2, 3, 4, 5]), mimeDeclarado: null } });
  await processarArquivo(ITEM, d.deps);
  await d.esperarFundo();
  assertEquals(d.reacoes.length, 0);
  assertEquals(d.envios.length, 0);
  assertEquals(rpcs(banco, "comprovante_reservar_aviso").length, 0);
});

Deno.test("download com nova tentativa: o banco agenda, nada sai para o dono nem para o assistente", async () => {
  const banco = bancoFalso({
    tabelas: { whatsapp_messages: [mensagem()] },
    rpc: {
      comprovante_download_falhou: () => ({
        id: CMP_ID, final: false, proxima_em: "2026-10-10T22:46:00Z", situacao: "recebido", encaminhar: false,
        texto_para_assistente: null, modo: "dono", forcado: true, phone_normalized: DONO.phone, wa_message_id: "WAID1", dono_id: DONO.id,
      }),
    },
  });
  const d = depsFalsas(banco, { baixar: { ok: false, erro: "evolution_fora" } });
  assertEquals(await processarArquivo(ITEM, d.deps), "tentar_de_novo");
  await d.esperarFundo();
  assertEquals(rpcs(banco, "comprovante_download_falhou")[0].args, { p_id: CMP_ID, p_erro: "evolution_fora" });
  assertEquals(d.envios.length, 0);
  assertEquals(d.reacoes.length, 0);
  assertEquals(rpcs(banco, "comprovante_reservar_aviso").length, 0);
});

Deno.test("arquivo declarado acima de 15 MB: falha sem baixar; sem key = sem_chave", async () => {
  const grande = bancoFalso({ rpc: { comprovante_falhou: () => ({ id: CMP_ID, final: true, encaminhar: false, modo: "sombra" }) } });
  const d = depsFalsas(grande);
  await processarArquivo({ ...ITEM, tamanho_declarado: 99_999_999 }, d.deps);
  assertEquals(d.downloads(), 0);
  assertEquals(rpcs(grande, "comprovante_falhou")[0].args.p_erro, "arquivo_grande");

  const semKey = bancoFalso({ rpc: { comprovante_download_falhou: () => ({ id: CMP_ID, final: true, encaminhar: false, modo: "sombra" }) } });
  const ds = depsFalsas(semKey);
  await processarArquivo({ ...ITEM, chave: null }, ds.deps);
  assertEquals(rpcs(semKey, "comprovante_download_falhou")[0].args.p_erro, "sem_chave");
  assertEquals(ds.downloads(), 0);
});

Deno.test("download só com a key da linha: key de outra conversa/mensagem ou fromMe = sem_chave, sem chamar a Evolution", async () => {
  for (const chave of [chaveDe("WAID1", "5511988887777"), chaveDe("OUTRA"), chaveDe("WAID1", DONO.phone, { fromMe: true })]) {
    const banco = bancoFalso({ rpc: { comprovante_download_falhou: () => ({ id: CMP_ID, final: true, encaminhar: false, modo: "sombra" }) } });
    const d = depsFalsas(banco);
    await processarArquivo({ ...ITEM, chave }, d.deps);
    assertEquals(rpcs(banco, "comprovante_download_falhou")[0].args, { p_id: CMP_ID, p_erro: "sem_chave" });
    assertEquals(d.downloads(), 0);
  }
  // e nunca relê whatsapp_messages (onde a equipe consegue trocar o raw_payload)
  const banco = bancoFalso({ rpc: { comprovante_guardar_arquivo: () => GUARDADO } });
  const lidas: string[] = [];
  const fromOriginal = banco.admin.from.bind(banco.admin);
  banco.admin.from = (t: string) => { lidas.push(t); return fromOriginal(t); };
  await processarArquivo(ITEM, depsFalsas(banco).deps);
  assertEquals(lidas.includes("whatsapp_messages"), false);
});

Deno.test("falha de upload vira nova tentativa de download (upload_falhou)", async () => {
  const banco = bancoFalso({
    falhaNoUpload: true,
    rpc: { comprovante_download_falhou: () => ({ id: CMP_ID, final: false, encaminhar: false, modo: "dono" }) },
  });
  await processarArquivo(ITEM, depsFalsas(banco).deps);
  assertEquals(rpcs(banco, "comprovante_download_falhou")[0].args.p_erro, "upload_falhou");
  assertEquals(rpcs(banco, "comprovante_guardar_arquivo").length, 0);
});

Deno.test("falha inesperada depois do upload: apaga o objeto sem dono e conta a tentativa (upload_falhou)", async () => {
  for (const ignorado of [false, true]) {
    const banco = bancoFalso({
      rpc: {
        comprovante_guardar_arquivo: () => ({ error: { code: "22023", message: "linha recusada" } }),
        comprovante_download_falhou: () => ({
          id: CMP_ID, final: false, encaminhar: false, modo: "dono", ...(ignorado ? { ignorado: true, final: true } : {}),
        }),
      },
    });
    const d = depsFalsas(banco);
    const r = await processarArquivo(ITEM, d.deps);
    assertEquals(rpcs(banco, "comprovante_download_falhou")[0].args, { p_id: CMP_ID, p_erro: "upload_falhou" });
    // linha que já tinha desfecho: o objeto pode ser dela, fica
    assertEquals(banco.storage.removidos, ignorado ? [] : [`2026/10/${CMP_ID}.jpg`]);
    assertEquals(r, ignorado ? "falhou" : "tentar_de_novo");
    assertEquals(d.logs.some((l) => l.evento === "processar_falhou" && l.campos?.codigo === "comprovante_guardar_arquivo:22023"), true);
  }
});

// ─── entrega ──────────────────────────────────────────────────────────────────────────────

const LEITURA_CMP = {
  id: CMP_ID, decisao: "cmp", situacao: "lido", codigo: "CMP-00123", modo: "dono", rota: "comprovante", forcado: false,
  phone_normalized: DONO.phone, wa_message_id: "WAID1", dono_id: DONO.id, encaminhar: false, texto_para_assistente: null,
  subir_dropbox: true, apagar_arquivo_agora: false, arquivo: DA,
  resumo: { tipo: "nfce", confianca: "alta", valor: "62.00", valor_confianca: "alta", alertas: [] },
};

Deno.test("entrega cmp: Dropbox em _A CLASSIFICAR, ✅, aviso por whatsapp-send e par 🤖 no histórico", async () => {
  const banco = bancoFalso({
    rpc: {
      comprovante_aplicar_leitura: () => LEITURA_CMP,
      comprovante_no_dropbox: () => null,
      comprovante_reservar_aviso: () => ({ esperando: 0, itens: [ITEM_CMP] }),
    },
  });
  const d = depsFalsas(banco);
  assertEquals(await entregar(JOB_ID, d.deps), { decisao: "cmp" });
  await d.esperarFundo();

  assertEquals(rpcs(banco, "comprovante_aplicar_leitura")[0].args, { p_job_id: JOB_ID });
  assertEquals(banco.storage.baixados, [DA.arquivo_path]);
  assertEquals(d.dropboxEnvios.length, 1);
  assertEquals(d.dropboxEnvios[0].caminho, `${PASTA_A_CLASSIFICAR}/2026-10-08 12h57 CMP-00123 NFCE R$ 62,00 Auto Posto Exemplo.jpg`);
  assertEquals(rpcs(banco, "comprovante_no_dropbox")[0].args, {
    p_id: CMP_ID, p_dropbox_id: "id:abcDEF_12-3", p_caminho: d.dropboxEnvios[0].caminho, p_rev: "015f00",
  });
  assertEquals(d.reacoes, [{ phone: DONO.phone, id: "WAID1", emoji: "✅" }]);

  const envio = d.envios.find((e) => e.url.endsWith("/functions/v1/whatsapp-send"));
  assert(envio, "o aviso não saiu");
  assertEquals(envio.corpo.phone, DONO.phone);
  assertEquals(envio.corpo.kind, "text");
  assertEquals(envio.corpo.context, "comprovante");
  assert(/^cmp:aviso:[0-9a-f]{16}$/.test(envio.corpo.dedupe_key));
  assertStringIncludes(envio.corpo.message, "CMP-00123 guardado");
  assertEquals(d.envios.some((e) => e.url.endsWith("/ai-agent")), false, "cmp não vai ao assistente");

  const historico = banco.inseridos.ai_operator_messages ?? [];
  assertEquals(historico.map((h) => h.role), ["user", "assistant"]);
  assertStringIncludes(String(historico[0].content), "🤖");
  assertEquals(historico[0].session_id, "sessao-1");
  assertEquals(historico.map((h) => h.source), ["whatsapp", "whatsapp"]);
  assert(String(historico[0].created_at) < String(historico[1].created_at));
  assertStringIncludes(String(historico[1].content), `Referência: CMP-00123 (id ${CMP_ID})`);
});

Deno.test("entrega não comprovante: encaminha ao assistente SÓ quando o banco manda", async () => {
  const base = { ...LEITURA_CMP, decisao: "nao_comprovante", situacao: "nao_comprovante", codigo: null, subir_dropbox: false, arquivo: null, resumo: null };
  for (const encaminhar of [true, false]) {
    const banco = bancoFalso({
      rpc: {
        comprovante_aplicar_leitura: () => ({ ...base, encaminhar, texto_para_assistente: encaminhar ? "[image]" : null }),
        comprovante_reservar_aviso: () => ({ esperando: 0, itens: [] }),
      },
    });
    const d = depsFalsas(banco);
    await entregar(JOB_ID, d.deps);
    await d.esperarFundo();
    const agente = d.envios.filter((e) => e.url.endsWith("/functions/v1/ai-agent"));
    assertEquals(agente.length, encaminhar ? 1 : 0);
    if (encaminhar) assertEquals(agente[0].corpo.text, "[image]");
    assertEquals(d.dropboxEnvios.length, 0);
    assertEquals(d.reacoes, [{ phone: DONO.phone, id: "WAID1", emoji: "" }]);
  }
});

Deno.test("entrega que lança: conta (comprovante_entrega_falhou); antes da 3ª o erro sobe, na 3ª desiste e encaminha", async () => {
  const aplicarLanca = { comprovante_aplicar_leitura: () => ({ error: { code: "XX000", message: "linha recusada" } }) };
  const contando = bancoFalso({ rpc: { ...aplicarLanca, comprovante_entrega_falhou: () => ({ job_id: JOB_ID, tentativas: 1, desistiu: false }) } });
  let erro = "";
  try {
    await entregar(JOB_ID, depsFalsas(contando).deps);
  } catch (e) {
    erro = (e as Error).message;
  }
  assertEquals(erro, "comprovante_aplicar_leitura:XX000");
  assertEquals(rpcs(contando, "comprovante_entrega_falhou")[0].args, { p_job_id: JOB_ID });

  const desistiu = bancoFalso({
    rpc: {
      ...aplicarLanca,
      comprovante_entrega_falhou: () => ({
        job_id: JOB_ID, id: CMP_ID, tentativas: 3, desistiu: true, situacao: "falhou", codigo: null, modo: "dono",
        phone_normalized: DONO.phone, wa_message_id: "WAID1", dono_id: DONO.id, encaminhar: true, texto_para_assistente: "[image]",
      }),
      comprovante_reservar_aviso: () => ({ esperando: 0, itens: [] }),
    },
  });
  const d = depsFalsas(desistiu);
  assertEquals(await entregar(JOB_ID, d.deps), { decisao: "falhou" });
  await d.esperarFundo();
  const agente = d.envios.filter((e) => e.url.endsWith("/functions/v1/ai-agent"));
  assertEquals(agente.map((e) => e.corpo.text), ["[image]"]);
  assertEquals(d.reacoes, [{ phone: DONO.phone, id: "WAID1", emoji: "" }]);
  assertEquals(rpcs(desistiu, "comprovante_reservar_aviso").length, 1);

  // sem conseguir nem contar: vale o erro original
  const semConta = bancoFalso({ rpc: aplicarLanca });
  erro = "";
  try {
    await entregar(JOB_ID, depsFalsas(semConta).deps);
  } catch (e) {
    erro = (e as Error).message;
  }
  assertEquals(erro, "comprovante_aplicar_leitura:XX000");
});

Deno.test("entrega ignorada ou a reenfileirar: nada além da RPC", async () => {
  for (const decisao of ["ignorado", "reenfileirar"]) {
    const banco = bancoFalso({ rpc: { comprovante_aplicar_leitura: () => ({ decisao }) } });
    const d = depsFalsas(banco);
    assertEquals(await entregar(JOB_ID, d.deps), { decisao });
    assertEquals(banco.chamadasRpc.length, 1);
    assertEquals(d.envios.length + d.reacoes.length + d.dropboxEnvios.length, 0);
  }
});

Deno.test("entrega de CMP sem leitura (falhou com número): ✅ e Dropbox 'A LER'", async () => {
  const banco = bancoFalso({
    rpc: {
      comprovante_aplicar_leitura: () => ({
        ...LEITURA_CMP, decisao: "falhou", situacao: "falhou",
        arquivo: { ...DA, situacao: "falhou", tipo: null, valor: null, data_compra: null, hora_compra: null, fornecedor_nome: null },
      }),
      comprovante_no_dropbox: () => null,
      comprovante_reservar_aviso: () => ({ esperando: 1, itens: [] }),
    },
  });
  const d = depsFalsas(banco);
  await entregar(JOB_ID, d.deps);
  assertEquals(d.dropboxEnvios[0].caminho, `${PASTA_A_CLASSIFICAR}/2026-10-10 CMP-00123 A LER.jpg`);
  assertEquals(d.reacoes[0].emoji, "✅");
});

Deno.test("Dropbox com erro ou sem conexão: registra a falha (backoff é do banco), sem marcar enviado", async () => {
  for (const [modo, codigo] of [["erro", "dropbox_429:too_many_write_operations"], ["sem_conexao", "dropbox_sem_conexao"]] as const) {
    const banco = bancoFalso({ rpc: { comprovante_dropbox_falhou: () => ({ tentativas: 1, proxima_em: "x", desistiu: false }) } });
    const d = depsFalsas(banco, { dropbox: modo });
    assertEquals(await subirNoDropbox(DA, d.deps), false);
    assertEquals(rpcs(banco, "comprovante_dropbox_falhou")[0].args, { p_id: CMP_ID, p_erro: codigo });
    assertEquals(rpcs(banco, "comprovante_no_dropbox").length, 0);
  }
});

// ─── aviso ────────────────────────────────────────────────────────────────────────────────

Deno.test("aviso: sem itens reservados não envia nada", async () => {
  const banco = bancoFalso({ rpc: { comprovante_reservar_aviso: () => ({ esperando: 2, itens: [] }) } });
  const d = depsFalsas(banco);
  assertEquals(await talvezAvisar(DONO.phone, false, d.deps), 0);
  assertEquals(d.envios.length, 0);
});

Deno.test("aviso: whatsapp-send fora devolve a reserva ao vigia — sem whatsapp_send_queue e sem histórico", async () => {
  const fora = bancoFalso({
    rpc: {
      comprovante_reservar_aviso: () => ({ esperando: 0, itens: [ITEM_CMP] }),
      comprovante_aviso_falhou: () => ({ liberados: 1, desistiu: 0 }),
    },
  });
  assertEquals(await talvezAvisar(DONO.phone, true, depsFalsas(fora, { envio: 500 }).deps), 0);
  assertEquals(rpcs(fora, "comprovante_aviso_falhou")[0].args, { p_ids: [CMP_ID] });
  assertEquals(fora.inseridos.whatsapp_send_queue, undefined, "a fila é legível e editável por qualquer logado");
  assertEquals(fora.inseridos.ai_operator_messages, undefined, "o aviso não saiu: o assistente não pode achar que saiu");

  // 409 (a mesma chave sem desfecho numa tentativa anterior): não repete, não devolve
  const andamento = bancoFalso({ rpc: { comprovante_reservar_aviso: () => ({ esperando: 0, itens: [ITEM_CMP] }) } });
  assertEquals(await talvezAvisar(DONO.phone, true, depsFalsas(andamento, { envio: 409 }).deps), 1);
  assertEquals(andamento.inseridos.whatsapp_send_queue, undefined);
  assertEquals(rpcs(andamento, "comprovante_aviso_falhou").length, 0);
});

Deno.test("aviso com pendência viva na conversa: marca pendencia_herdada ANTES de enviar (um 'ok' não aprova)", async () => {
  const futuro = "2026-10-11T22:00:00Z";
  const banco = bancoFalso({
    tabelas: {
      ai_operator_sessions: [{ id: "sessao-1", metadata: { pending_confirm_action_id: "p-1", pin_attempts: 0 } }],
      ai_operator_pending_actions: [{ id: "p-1", status: "pending", expires_at: futuro, title: "Lembrete ao cliente", risk_level: "medium" }],
    },
    rpc: { comprovante_reservar_aviso: () => ({ esperando: 0, itens: [ITEM_CMP] }) },
  });
  const d = depsFalsas(banco);
  let marcadoNoEnvio: unknown = null;
  const fetchOriginal = d.deps.fetch;
  d.deps.fetch = ((url: string, init?: RequestInit) => {
    if (String(url).endsWith("/whatsapp-send")) marcadoNoEnvio = banco.tabelas.ai_operator_sessions[0].metadata;
    return fetchOriginal(url, init);
  }) as typeof fetch;
  assertEquals(await talvezAvisar(DONO.phone, false, d.deps), 1);
  assertEquals(banco.tabelas.ai_operator_sessions[0].metadata, { pending_confirm_action_id: "p-1", pin_attempts: 0, pendencia_herdada: true });
  assertEquals((marcadoNoEnvio as Qualquer)?.pendencia_herdada, true, "marcado antes do envio");
  assertEquals(banco.atualizados.ai_operator_sessions?.[0].valor, "sessao-1");

  // sem pendência viva (decidida ou vencida): não mexe na sessão
  for (const pendencia of [{ id: "p-1", status: "approved", expires_at: futuro }, { id: "p-1", status: "pending", expires_at: "2026-10-01T00:00:00Z" }]) {
    const b = bancoFalso({
      tabelas: {
        ai_operator_sessions: [{ id: "sessao-1", metadata: { pending_confirm_action_id: "p-1" } }],
        ai_operator_pending_actions: [pendencia],
      },
      rpc: { comprovante_reservar_aviso: () => ({ esperando: 0, itens: [ITEM_CMP] }) },
    });
    assertEquals(await talvezAvisar(DONO.phone, false, depsFalsas(b).deps), 1);
    assertEquals(b.atualizados.ai_operator_sessions, undefined);
  }
});

Deno.test("aviso: sem conseguir conferir a pendência, não envia — a reserva volta ao vigia", async () => {
  const banco = bancoFalso({
    rpc: {
      comprovante_reservar_aviso: () => ({ esperando: 0, itens: [ITEM_CMP] }),
      comprovante_aviso_falhou: () => ({ liberados: 1, desistiu: 0 }),
    },
  });
  const d = depsFalsas(banco);
  d.deps.sessaoDoWhatsApp = () => Promise.reject(new Error("db"));
  assertEquals(await talvezAvisar(DONO.phone, false, d.deps), 0);
  assertEquals(d.envios.length, 0);
  assertEquals(rpcs(banco, "comprovante_aviso_falhou").length, 1);
});

// ─── vigia ────────────────────────────────────────────────────────────────────────────────

Deno.test("vigia: cada lista vai ao seu destino e a contagem volta", async () => {
  const banco = bancoFalso({
    tabelas: { whatsapp_messages: [mensagem()] },
    rpc: {
      comprovantes_vigia_lote: () => ({
        expurgados: 2,
        sem_desfecho: 1,
        encaminhar: [{ id: "s-1", phone_normalized: DONO.phone, dono_id: DONO.id, texto: "[image]" }],
        baixar: [{
          id: CMP_ID, message_id: MSG_ID, wa_message_id: "WAID1", wa_key: chaveDe("WAID1"), phone_normalized: DONO.phone,
          recebido_em: "2026-10-10T22:40:57Z",
        }],
        entregar: [{ job_id: JOB_ID }],
        reenfileirar: [{ id: "r-1", arquivo_path: "2026/10/r.jpg" }],
        dropbox: [DA],
        apagar: [{ id: "a-1", arquivo_path: "2026/10/a.jpg" }],
        avisar: [DONO.phone],
      }),
      comprovante_guardar_arquivo: () => GUARDADO,
      comprovante_aplicar_leitura: () => ({ decisao: "ignorado" }),
      comprovante_pedir_leitura: () => ({ id: "r-1", ok: true, job_id: "novo" }),
      comprovante_no_dropbox: () => null,
      comprovante_arquivo_apagado: () => null,
      comprovante_reservar_aviso: () => ({ esperando: 0, itens: [ITEM_CMP] }),
    },
  });
  const d = depsFalsas(banco);
  const n = await vigiar(d.deps);
  await d.esperarFundo();
  assertEquals(n, {
    baixados: 1, entregues: 1, reenfileirados: 1, dropbox: 1, apagados: 1, avisos: 1, expurgados: 2, sem_desfecho: 1, encaminhados: 1,
    movidos: 0, indices: 0, cnpj: 0, perguntas: 0,
  });
  assertEquals(rpcs(banco, "comprovantes_vigia_lote")[0].args, { p_limite: 10 });
  // a rede de 1 h do banco mandou encaminhar: vai ao assistente com o texto da linha
  assertEquals(d.envios.filter((e) => e.url.endsWith("/ai-agent")).map((e) => e.corpo.text), ["[image]"]);
  // baixar usa a key que veio do banco (a guardada na chegada)
  assertEquals(d.chavesBaixadas, [chaveDe("WAID1")]);
  // apagar (prazo de privacidade) roda antes dos downloads
  const ordem = banco.chamadasRpc.map((c) => c.nome);
  assert(ordem.indexOf("comprovante_arquivo_apagado") < ordem.indexOf("comprovante_guardar_arquivo"));
  const pedido = rpcs(banco, "comprovante_pedir_leitura")[0].args;
  assertEquals(pedido.p_id, "r-1");
  assertStringIncludes(pedido.p_url, "/storage/v1/object/sign/comprovantes/2026/10/r.jpg");
  assertEquals(banco.storage.assinadas.find((a) => a.path === "2026/10/r.jpg")?.segundos, 86400);
  assert(banco.storage.removidos.includes("2026/10/a.jpg"));
  assertEquals(rpcs(banco, "comprovante_arquivo_apagado")[0].args, { p_id: "a-1" });
  assertEquals(rpcs(banco, "comprovante_reservar_aviso").at(-1)?.args, { p_phone: DONO.phone, p_forcar: true });
});

Deno.test("vigia: remoção que falha não marca apagado; item com erro não derruba os outros", async () => {
  const banco = bancoFalso({
    falhaNoRemove: true,
    rpc: {
      comprovantes_vigia_lote: () => ({ expurgados: 0, apagar: [{ id: "a-1", arquivo_path: "x" }], entregar: [{ job_id: JOB_ID }] }),
      comprovante_aplicar_leitura: () => ({ error: { code: "XX000", message: "linha recusada: dados" } }),
    },
  });
  const d = depsFalsas(banco);
  const n = await vigiar(d.deps);
  assertEquals(n.apagados, 0);
  assertEquals(n.entregues, 0);
  assertEquals(rpcs(banco, "comprovante_arquivo_apagado").length, 0);
  const falhas = d.logs.filter((l) => l.evento === "vigia_item_falhou").map((l) => l.campos);
  assertEquals(falhas, [{ etapa: "apagar", codigo: "storage_remove" }, { etapa: "entregar", codigo: "comprovante_aplicar_leitura:XX000" }]);
});

Deno.test("vigia: respeita o orçamento de tempo", async () => {
  let t = Date.parse("2026-10-10T22:00:00Z");
  const banco = bancoFalso({
    rpc: {
      comprovantes_vigia_lote: () => ({ expurgados: 0, entregar: [{ job_id: "j1" }, { job_id: "j2" }, { job_id: "j3" }] }),
      comprovante_aplicar_leitura: () => { t += 30_000; return { decisao: "ignorado" }; },
    },
  });
  const d = depsFalsas(banco, { agora: () => new Date(t) });
  const n = await vigiar(d.deps, 45_000);
  assertEquals(n.entregues, 2); // o 3º passaria do orçamento
});

// ─── repescagem ───────────────────────────────────────────────────────────────────────────

Deno.test("repescar: com off recusa sem ler mensagem", async () => {
  const banco = bancoFalso({ tabelas: { app_settings: [{ key: "comprovante_fluxo", value: "off" }] } });
  assertEquals(await repescar({ desde: "2026-10-01T00:00:00Z" }, depsFalsas(banco).deps), { ok: false, motivo: "modo_off" });
  assertEquals(banco.chamadasRpc.length, 0);
});

Deno.test("repescar: só o que ainda não tem linha, origem repescagem, sem encaminhar", async () => {
  const antiga = mensagem({ id: "m-antiga", wa_message_id: "W-A", occurred_at: "2026-10-02T10:00:00Z" });
  const nova = mensagem({ id: "m-nova", wa_message_id: "W-N", occurred_at: "2026-10-03T10:00:00Z" });
  const texto = mensagem({ id: "m-texto", wa_message_id: "W-T", message_type: "text", occurred_at: "2026-10-04T10:00:00Z" }, { conversation: "oi" });
  const comLegenda = mensagem(
    { id: "m-env", wa_message_id: "W-E", message_type: "text", occurred_at: "2026-10-05T10:00:00Z" },
    { documentWithCaptionMessage: { message: { documentMessage: { fileName: "a.pdf", caption: "nota" } } } },
  );
  // linha forjada por alguém da equipe: telefone do dono, mas a key é da conversa de um cliente
  const forjada = mensagem({ id: "m-forjada", wa_message_id: "W-F", occurred_at: "2026-10-06T10:00:00Z" });
  (forjada.raw_payload as Qualquer).data.key = chaveDe("W-F", "5511988887777");
  const banco = bancoFalso({
    tabelas: { app_settings: [{ key: "comprovante_fluxo", value: "sombra" }], whatsapp_messages: [nova, texto, comLegenda, antiga, forjada] },
    rpc: {
      comprovante_receber: (a: Qualquer) => ({ id: `c-${a.p.message_id}`, novo: a.p.message_id !== "m-antiga", situacao: "recebido" }),
      comprovante_guardar_arquivo: () => ({ ...GUARDADO, modo: "sombra" }),
    },
  });
  const d = depsFalsas(banco);
  const r = await repescar({ desde: "2026-10-01T00:00:00Z", limite: 50 }, d.deps);
  assertEquals(r, { ok: true, processadas: 2, restantes: 0 });
  const recebidas = rpcs(banco, "comprovante_receber").map((c) => c.args.p);
  // mais antigas primeiro; texto puro fora; a forjada (key de outra conversa) nem é registrada
  assertEquals(recebidas.map((p) => p.message_id), ["m-antiga", "m-nova", "m-env"]);
  assertEquals(d.logs.some((l) => l.evento === "repescagem_chave_divergente" && l.campos?.message_id === "m-forjada"), true);
  for (const p of recebidas) assertEquals([p.origem, p.rota, p.modo], ["repescagem", "comprovante", "sombra"]);
  for (const p of recebidas) assertEquals(p.wa_key?.id, p.wa_message_id);
  assertEquals(rpcs(banco, "comprovante_guardar_arquivo").length, 2);
  assertEquals(d.envios.some((e) => e.url.endsWith("/ai-agent")), false);
});

Deno.test("repescar: limite corta e conta as restantes", async () => {
  const msgs = [1, 2, 3].map((i) => mensagem({ id: `m-${i}`, wa_message_id: `W-${i}`, occurred_at: `2026-10-0${i}T10:00:00Z` }));
  const banco = bancoFalso({
    tabelas: { whatsapp_messages: msgs },
    rpc: {
      comprovante_receber: (a: Qualquer) => ({ id: `c-${a.p.message_id}`, novo: true, situacao: "recebido" }),
      comprovante_guardar_arquivo: () => GUARDADO,
    },
  });
  const r = await repescar({ desde: "2026-10-01T00:00:00Z", limite: 1 }, depsFalsas(banco).deps);
  assertEquals(r, { ok: true, processadas: 1, restantes: 2 });
});

// ─── privacidade dos logs ─────────────────────────────────────────────────────────────────

Deno.test("nenhum console.* com legenda, valor, CNPJ ou nome", async () => {
  const saida: string[] = [];
  const originais = { log: console.log, error: console.error, warn: console.warn, info: console.info };
  for (const k of Object.keys(originais) as Array<keyof typeof originais>) {
    console[k] = (...a: unknown[]) => { saida.push(a.map((x) => typeof x === "string" ? x : JSON.stringify(x)).join(" ")); };
  }
  try {
    const banco = bancoFalso({
      tabelas: { whatsapp_messages: [mensagem()] },
      rpc: {
        comprovante_receber: () => ({ id: CMP_ID, novo: true, situacao: "recebido" }),
        comprovante_guardar_arquivo: () => GUARDADO,
        comprovante_aplicar_leitura: () => ({ ...LEITURA_CMP, encaminhar: true, texto_para_assistente: LEGENDA_SECRETA }),
        comprovante_no_dropbox: () => null,
        comprovante_reservar_aviso: () => ({ esperando: 0, itens: [ITEM_CMP] }),
        comprovante_dropbox_falhou: () => ({ desistiu: false }),
      },
    });
    const d = depsFalsas(banco);
    d.deps.log = logDoFluxo; // o log de verdade da função
    await receber(CORPO_RECEBER, d.deps);
    await entregar(JOB_ID, d.deps);
    await subirNoDropbox(DA, depsFalsas(banco, { dropbox: "erro" }).deps);
    await d.esperarFundo();
  } finally {
    Object.assign(console, originais);
  }
  const tudo = saida.join("\n");
  assert(saida.length > 0, "o fluxo deveria ter registrado alguma coisa");
  for (const proibido of [LEGENDA_SECRETA, "Segredo", "62.00", "62,00", CNPJ, "11.222.333", "Auto Posto"]) {
    assertEquals(tudo.includes(proibido), false, `vazou no log: ${proibido}`);
  }
});

// =============================================================================================
// F2: a conversa (spec-f2.md, 5.8). O banco falso devolve as formas da N3 (comprovante_responder,
// comprovante_comando, comprovante_proxima_pergunta…); Dropbox, whatsapp-send e BrasilAPI são dublês.
// =============================================================================================

const P_ID = "44444444-0000-4000-8000-000000000001";
const P_PROX = "44444444-0000-4000-8000-000000000002";
const OS_INFO = { id: "os-1", numero: "OS-00112", barco: "Brisa", cliente: "João", status: "in_progress", faturada: false, assinada: false, pasta_registrada: true };

const CMP_RESUMO = {
  id: CMP_ID, codigo: "CMP-00124", numero: 124, situacao: "perguntando", tipo: "nfce", valor: "62.00", valor_lido: "62.00",
  valor_confianca: "alta", data: "2026-10-10", hora: "12:57:56", forma: "debito", fornecedor: "Auto Posto Exemplo",
  fornecedor_origem: "cadastro", cnpj: CNPJ, cnpj_confianca: "alta", destino: null, os: null, tipo_na_os: null,
  quem_pagou: null, pagador_nome: null, categoria: null, pendencias: [], gravado_em: null,
};

const OPCOES_PARA_QUE = [
  { n: 1, rotulo: "OS-00112 · Brisa", valor: "os:os-1" }, { n: 2, rotulo: "Estoque", valor: "estoque" },
  { n: 3, rotulo: "Insumo", valor: "insumo" }, { n: 4, rotulo: "Empresa (sem OS)", valor: "empresa" }, { n: 5, rotulo: "Pessoal", valor: "pessoal" },
];

function perguntaDoBanco(passo: string, extra: Linha = {}, cmp: Linha = {}): Qualquer {
  const id = String(extra.pergunta_id ?? P_PROX);
  return {
    pergunta_id: id, dedupe_key: `cmp:p:${id}`, cmp: { ...CMP_RESUMO, ...cmp }, passo, opcoes: [], posicao: 1, total: 1,
    primeira_do_lote: null, retomada: false, avisos: [], plano: null, versao: null, pasta: null, ...extra,
  };
}

/** O pergunta_rotear com a conversa ligada e a pergunta do CMP aberta no passo dado. */
function rotear(passo: string | null, extra: Linha = {}): Qualquer {
  return {
    conversa: true, dono: true,
    ativa: passo === null ? null : {
      id: P_ID, origem: "comprovante", tipo: "pergunta", referencia_id: CMP_ID, referencia_codigo: "CMP-00124", passo,
      opcoes: passo === "para_que" ? OPCOES_PARA_QUE : [], wa_message_id: "WA-P", aberta_em: "2026-10-10T22:30:00Z",
    },
    citada: null, pendencia: null, cmp_em_contexto: null, ...extra,
  };
}

const TEXTO_MSG = (texto: string, extra: Linha = {}) =>
  mensagem({ message_type: "text", ...extra }, { conversation: texto });

type DropboxF2 = {
  enviados: Array<{ caminho: string; bytes: Uint8Array }>;
  movidos: Array<{ de: string; para: string }>;
  substituidos: Array<{ caminho: string; bytes: Uint8Array; rev: string | null }>;
  pastas: string[];
  metadados: string[];
};

function dropboxFalso(op: { atual?: string | null | "sumiu"; erroNoMover?: { status: number; resumo: string }; conflito?: boolean } = {}) {
  const r: DropboxF2 = { enviados: [], movidos: [], substituidos: [], pastas: [], metadados: [] };
  const dbx = {
    enviar: (caminho: string, bytes: Uint8Array) => {
      r.enviados.push({ caminho, bytes });
      return Promise.resolve({ id: "id:novo", path_display: caminho, rev: "01a" });
    },
    mover: (de: string, para: string) => {
      if (op.erroNoMover) return Promise.reject(Object.assign(new Error("x"), op.erroNoMover));
      r.movidos.push({ de, para });
      return Promise.resolve({ id: de, path_display: para, rev: "02b" });
    },
    substituir: (caminho: string, bytes: Uint8Array, rev: string | null) => {
      r.substituidos.push({ caminho, bytes, rev });
      const path = op.conflito ? caminho.replace(".csv", " (1).csv") : caminho;
      return Promise.resolve({ id: "id:indice", path_display: path, rev: "03c", conflito: Boolean(op.conflito) });
    },
    criarPasta: (caminho: string) => {
      r.pastas.push(caminho);
      return Promise.resolve({ id: "id:pasta", path_display: caminho });
    },
    rpc: (rota: string, corpo: Qualquer) => {
      r.metadados.push(`${rota}:${corpo?.path}`);
      if (op.atual === "sumiu") return Promise.reject(Object.assign(new Error("x"), { status: 409, resumo: "path/not_found/.." }));
      return Promise.resolve({ id: corpo?.path, path_display: op.atual ?? "/MANAGEMENT/FINANCIALS/COMPROVANTES/_A CLASSIFICAR/x.jpg", rev: "00z" });
    },
  };
  return { dbx, r };
}

/** As dependências da F2: whatsapp-send devolve messageId; BrasilAPI e Dropbox falsos. */
function depsF2(banco: ReturnType<typeof bancoFalso>, op: {
  envio?: number;
  dropbox?: ReturnType<typeof dropboxFalso> | null;
  brasilapi?: number | "rede";
} = {}) {
  const base = depsFalsas(banco);
  const envios: Array<{ url: string; corpo: Qualquer }> = [];
  let n = 0;
  base.deps.fetch = ((url: string, init?: RequestInit) => {
    const corpo = init?.body ? JSON.parse(String(init.body)) : null;
    envios.push({ url, corpo });
    if (url.includes("brasilapi")) {
      if (op.brasilapi === "rede") return Promise.reject(new Error("rede"));
      const status = op.brasilapi ?? 200;
      const b = status === 200 ? { razao_social: "POSTO EXEMPLO LTDA", nome_fantasia: "AUTO POSTO EXEMPLO", descricao_situacao_cadastral: "ATIVA" } : { message: "x" };
      return Promise.resolve(new Response(JSON.stringify(b), { status }));
    }
    const status = url.includes("whatsapp-send") ? (op.envio ?? 200) : 200;
    const b = status === 200 ? { success: true, messageId: `WA-OUT-${++n}` } : { error: "x" };
    return Promise.resolve(new Response(JSON.stringify(b), { status }));
  }) as typeof fetch;
  const dbx = op.dropbox === undefined ? dropboxFalso() : op.dropbox;
  base.deps.dropbox = () => Promise.resolve(dbx ? dbx.dbx as unknown as DropboxDoFluxo : null);
  base.deps.pastaDoBarco = (_d, p) => Promise.resolve({ id: "id:barco", caminho: `/MANAGEMENT/COMMERCIAL/B2C/0021.002.26_${p.barco}`, codigo: "0021.002.26", criada: false });
  const enviosAoDono = () => envios.filter((e) => e.url.endsWith("/functions/v1/whatsapp-send")).map((e) => e.corpo);
  return { ...base, envios, enviosAoDono, dbx };
}

const CORPO_RESPONDER = (texto: string, extra: Linha = {}) => ({ message_id: MSG_ID, phone: DONO.phone, texto, citado: null, destino: "comprovante", ...extra });

// ─── abertura ─────────────────────────────────────────────────────────────────────────────

Deno.test("F2 abertura: com a conversa ligada os CMPs entram na fila, o CNPJ é consultado e a 1ª pergunta sai com o prefixo do lote", async () => {
  const dup = { ...ITEM_CMP, id: "dup-1", codigo: null, decisao: "duplicado" as const, duplicado: { codigo: "CMP-00098", data_compra: null, valor: null } };
  const segundo = { ...ITEM_CMP, id: "c-2", codigo: "CMP-00124" };
  const banco = bancoFalso({
    rpc: {
      comprovante_reservar_aviso: () => ({ esperando: 0, itens: [ITEM_CMP, segundo, dup] }),
      pergunta_rotear: () => rotear(null),
      comprovante_conversa_entrar: (a: Qualquer) => ({ entraram: a.p_ids.map((id: string) => ({ id, codigo: "x" })), fila: 2 }),
      comprovantes_cnpj_a_consultar: () => [CNPJ],
      comprovante_cnpj_cache: () => null,
      comprovante_proxima_pergunta: () => ({
        perguntou: true,
        ...perguntaDoBanco("para_que", { pergunta_id: P_ID, opcoes: OPCOES_PARA_QUE, total: 2, primeira_do_lote: { n: 2, codigos: ["CMP-00123", "CMP-00124"] } }),
      }),
      pergunta_marcar_enviada: () => null,
    },
  });
  const d = depsF2(banco);
  assertEquals(await talvezAvisar(DONO.phone, false, d.deps), 3);
  assertEquals(rpcs(banco, "comprovante_conversa_entrar")[0].args, { p_ids: [CMP_ID, "c-2"] });
  // o aviso da F1 só para o repetido
  const avisos = d.enviosAoDono().filter((c) => String(c.dedupe_key).startsWith("cmp:aviso:"));
  assertEquals(avisos.length, 1);
  assertStringIncludes(avisos[0].message, "CMP-00098");
  assertEquals(avisos[0].message.includes("CMP-00123 guardado"), false);
  // CNPJ pela BrasilAPI (dublê) e o cache no banco
  assertEquals(d.envios.some((e) => e.url === `https://brasilapi.com.br/api/cnpj/v1/${CNPJ}`), true);
  assertEquals(rpcs(banco, "comprovante_cnpj_cache")[0].args.p_dados, {
    encontrado: true, razao_social: "POSTO EXEMPLO LTDA", nome_fantasia: "AUTO POSTO EXEMPLO", situacao_cadastral: "ATIVA",
  });
  // a pergunta: abertura, prefixo do lote, chave cmp:p:<id> e o id do WhatsApp registrado
  // revisão de 11/10/2026: a abertura pergunta o PRIMEIRO que entrou (não o primeiro da fila inteira)
  assertEquals(rpcs(banco, "comprovante_proxima_pergunta")[0].args, { p_phone: DONO.phone, p_motivo: "abertura", p_cmp: CMP_ID });
  const pergunta = d.enviosAoDono().find((c) => c.dedupe_key === `cmp:p:${P_ID}`);
  assert(pergunta, "a pergunta saiu");
  assert(pergunta.message.startsWith("Recebi 2 comprovantes: CMP-00123 e CMP-00124. Vou perguntar um de cada vez (para parar: *sair*).\nCMP-00124 (1 de 2)"));
  assertEquals(pergunta.context, "comprovante");
  assertEquals(rpcs(banco, "pergunta_marcar_enviada")[0].args, { p_id: P_ID, p_wa_message_id: "WA-OUT-2" });
});

Deno.test("F2 abertura: conversa desligada (ou erro ao entrar na fila) = o aviso da F1 de sempre", async () => {
  const cenarios: Array<Record<string, (a: Qualquer) => unknown>> = [{ pergunta_rotear: () => ({ conversa: false, dono: true }) }, {
    pergunta_rotear: () => rotear(null),
    comprovante_conversa_entrar: () => ({ error: { code: "XX000", message: "x" } }),
  }];
  for (const extra of cenarios) {
    const banco = bancoFalso({ rpc: { comprovante_reservar_aviso: () => ({ esperando: 0, itens: [ITEM_CMP] }), ...extra } });
    const d = depsF2(banco);
    assertEquals(await talvezAvisar(DONO.phone, false, d.deps), 1);
    const enviados = d.enviosAoDono();
    assertEquals(enviados.length, 1);
    assertStringIncludes(enviados[0].message, "CMP-00123 guardado");
    assertEquals(rpcs(banco, "comprovante_proxima_pergunta").length, 0);
  }
});

Deno.test("F2 perguntarProximo: modo de teste do whatsapp-send ligado → não abre pergunta", async () => {
  const banco = bancoFalso({
    tabelas: { app_settings: [{ key: "wa_test_mode", value: "true" }, { key: "wa_test_number", value: "5511999990000" }] },
    rpc: { comprovante_proxima_pergunta: () => ({ perguntou: true, ...perguntaDoBanco("valor") }) },
  });
  assertEquals(await perguntarProximo(DONO.phone, "vigia", depsF2(banco).deps), false);
  assertEquals(rpcs(banco, "comprovante_proxima_pergunta").length, 0);
});

Deno.test("F2 perguntarProximo: envio não confirmado devolve a pergunta (o CMP volta à fila); retomada do vigia tem prefixo", async () => {
  const banco = bancoFalso({
    rpc: {
      comprovante_proxima_pergunta: () => ({ perguntou: true, ...perguntaDoBanco("data", { retomada: true }) }),
      comprovante_pergunta_nao_enviada: () => null,
      pergunta_marcar_enviada: () => null,
    },
  });
  const d = depsF2(banco, { envio: 500 });
  assertEquals(await perguntarProximo(DONO.phone, "vigia", d.deps), false);
  assertEquals(rpcs(banco, "comprovante_pergunta_nao_enviada")[0].args, { p_pergunta_id: P_PROX });
  assertEquals(rpcs(banco, "pergunta_marcar_enviada").length, 0);
  assert(d.enviosAoDono()[0].message.startsWith("Ainda falta conferir o CMP-00124.\n"));
});

// ─── responder: a conversa ────────────────────────────────────────────────────────────────

function bancoDaConversa(passo: string, responder: (a: Qualquer) => unknown, extra: Record<string, (a: Qualquer) => unknown> = {}, tabelas: Record<string, Linha[]> = {}) {
  return bancoFalso({
    tabelas: { whatsapp_messages: [TEXTO_MSG("x")], ...tabelas },
    rpc: { pergunta_rotear: () => rotear(passo), comprovante_responder: responder, pergunta_marcar_enviada: () => null, ...extra },
  });
}

Deno.test("F2 responder: '1' no para quê → o banco recebe a opção; a próxima pergunta (nova) sai com a chave dela", async () => {
  const banco = bancoDaConversa("para_que", () => ({
    resultado: "proximo", cmp: { ...CMP_RESUMO, destino: "os", os: OS_INFO }, motivo: null, gravacao: null,
    proxima: perguntaDoBanco("tipo_na_os", {
      opcoes: [
        { n: 1, rotulo: "Peça ou material da OS (não lanço custo: a peça entra pela OS)", valor: "peca" },
        { n: 2, rotulo: "Despesa da OS (combustível, alimentação, frete, ferramenta…): custo interno, não aparece para o cliente", valor: "despesa" },
      ],
    }, { destino: "os", os: OS_INFO }),
  }));
  const d = depsF2(banco);
  const r = await responder(CORPO_RESPONDER("🎤 Um."), d.deps);
  assertEquals(r, { status: 200, corpo: { tratada: true, resultado: "proximo" } });
  assertEquals(rpcs(banco, "comprovante_responder")[0].args, {
    p: { pergunta_id: P_ID, message_id: MSG_ID, interpretacao: { tipo: "opcao", n: 1 }, versao: null },
  });
  const [env] = d.enviosAoDono();
  assertEquals(env.dedupe_key, `cmp:p:${P_PROX}`);
  // ajustes do dono: no lugar do "Cobrar do cliente?", peça ou despesa da OS
  assertStringIncludes(env.message, "Para a OS-00112 · Brisa: o que foi esta compra?\n1 Peça ou material da OS (não lanço custo: a peça entra pela OS)\n2 Despesa da OS");
  assertEquals(/cobr/i.test(env.message), false);
  assertEquals(rpcs(banco, "pergunta_marcar_enviada")[0].args, { p_id: P_PROX, p_wa_message_id: "WA-OUT-1" });
});

Deno.test("F2 responder: o resumo, 'ok' que não aprova, 'sim' que grava → mover, índice e histórico", async () => {
  const plano = { efeitos: [{ tipo: "despesa_os", os_numero: "OS-00112" }, { tipo: "anotar", forma: "debito" }], avisos: [], situacao_final: "gravado", pasta: "barco" };
  // 1) "2" (despesa) no peça ou despesa → o resumo
  const b1 = bancoDaConversa("tipo_na_os", () => ({
    resultado: "resumo", cmp: CMP_RESUMO, motivo: null, gravacao: null,
    proxima: perguntaDoBanco("confirmar", { plano, versao: 3, pasta: "Brisa/1- DOC's/Compras" }, { destino: "os", os: OS_INFO, tipo_na_os: "despesa" }),
  }));
  const d1 = depsF2(b1);
  await responder(CORPO_RESPONDER("2"), d1.deps);
  assertEquals(rpcs(b1, "comprovante_responder")[0].args.p.interpretacao, { tipo: "opcao", n: 2 });
  assertStringIncludes(d1.enviosAoDono()[0].message, "CMP-00124 · confira antes de gravar:");
  assertStringIncludes(d1.enviosAoDono()[0].message, "• Para: OS-00112 Brisa · despesa da OS (custo interno: não aparece para o cliente)");
  assertStringIncludes(d1.enviosAoDono()[0].message, "Responda *sim* para gravar ou *não* para corrigir.");

  // 2) "ok" no confirmar: só pede o sim; nada é gravado nem movido
  const b2 = bancoDaConversa("confirmar", () => ({ resultado: "ok_nao_aprova", cmp: CMP_RESUMO, proxima: null, gravacao: null, motivo: null }));
  const d2 = depsF2(b2);
  assertEquals((await responder(CORPO_RESPONDER("ok"), d2.deps)).corpo.resultado, "ok_nao_aprova");
  assertEquals(rpcs(b2, "comprovante_responder")[0].args.p.interpretacao, { tipo: "ok" });
  assertEquals(d2.enviosAoDono()[0], {
    phone: DONO.phone, kind: "text", message: "Para gravar o CMP-00124, responda *sim* (ou *não* para corrigir).", context: "comprovante", dedupe_key: `cmp:r:${MSG_ID}`,
  });
  assertEquals(rpcs(b2, "comprovante_destino_do_arquivo").length, 0);
  // "1" no confirmar também não aprova (vira "ok")
  const b2b = bancoDaConversa("confirmar", () => ({ resultado: "ok_nao_aprova", cmp: CMP_RESUMO, proxima: null }));
  await responder(CORPO_RESPONDER("1"), depsF2(b2b).deps);
  assertEquals(rpcs(b2b, "comprovante_responder")[0].args.p.interpretacao, { tipo: "ok" });

  // 3) "sim" → gravado
  const gravado = { ...CMP_RESUMO, situacao: "gravado", destino: "os", os: OS_INFO, tipo_na_os: "despesa", gravado_em: "2026-10-10T22:41:00Z" };
  const b3 = bancoDaConversa("confirmar", () => ({
    resultado: "gravado", cmp: gravado, proxima: null, motivo: null,
    gravacao: { situacao: "gravado", efeitos: [{ tipo: "despesa_os", so_expense_id: "e-1", os_id: "os-1" }, { tipo: "anotar", anotacao_id: "a-1", resultado: "aguardando" }], avisos: [], mensagens: [], mes: "2026-10-01", aprovar: null },
  }), {
    comprovante_destino_do_arquivo: () => ({ data: {
      id: CMP_ID, codigo: "CMP-00124", situacao: "gravado", cancelado: false, tipo: "nfce", valor: "62.00", valor_confirmado: true, data: "2026-10-10",
      hora: "12:57:56", fornecedor: "Auto Posto Exemplo", destino: "os",
      os: { numero: "OS-00112", vessel_id: "v-1", client_id: "cl-1", barco: "Brisa", cliente: "João", pasta_registrada: true },
      forma: "debito", conta: "EMPRESA", mes: "2026-10", dropbox_id: "id:abc", dropbox_caminho: "/MANAGEMENT/FINANCIALS/COMPROVANTES/_A CLASSIFICAR/x.jpg",
      dropbox_pendente: "mover", arquivo_path: `2026/10/${CMP_ID}.jpg`, arquivo_mime: "image/jpeg",
    } }),
    comprovante_dropbox_movido: () => null,
    comprovantes_indice_do_mes: () => [{ codigo: "CMP-00124", numero: 124, data: "2026-10-10", valor: "62.00", destino: "os", situacao: "gravado" }],
    comprovante_indice_gravado: () => null,
  }, {
    app_settings: [{ key: "dropbox_pasta_base", value: "/MANAGEMENT/COMMERCIAL/B2C" }],
    comprovantes_indice_mensal: [{ mes: "2026-10-01", caminho: "/MANAGEMENT/FINANCIALS/COMPROVANTES/2026/2026-10/_INDICE 2026-10.csv", rev: "00r" }],
    ai_operator_messages: [],
  });
  const d3 = depsF2(b3);
  const r3 = await responder(CORPO_RESPONDER("sim"), d3.deps);
  await d3.esperarFundo();
  assertEquals(r3.corpo, { tratada: true, resultado: "gravado" });
  assertEquals(rpcs(b3, "comprovante_responder")[0].args.p.interpretacao, { tipo: "sim" });
  const msg = d3.enviosAoDono()[0];
  assertEquals(msg.dedupe_key, `cmp:r:${MSG_ID}`);
  assertEquals(
    msg.message,
    "CMP-00124 gravado: lancei a despesa na OS-00112 como custo interno (não muda o total nem aparece para o cliente; entra no Lucro por OS); anotei o débito para quando o banco trouxer. Arquivo: Brisa/1- DOC's/Compras.\n\nFila vazia: não há mais comprovantes para conferir.",
  );
  // sem `aprovar` na gravação (só anotou), o finance-review não é chamado
  assertEquals(d3.envios.filter((e) => e.url.includes("finance-review")).length, 0);
  // o arquivo: pasta do barco + 1- DOC's/Compras, move_v2 pelo id, com o nome final
  const dbx = d3.dbx!.r;
  assertEquals(dbx.pastas, ["/MANAGEMENT/COMMERCIAL/B2C/0021.002.26_Brisa/1- DOC's/Compras"]);
  assertEquals(dbx.movidos, [{
    de: "id:abc",
    para: "/MANAGEMENT/COMMERCIAL/B2C/0021.002.26_Brisa/1- DOC's/Compras/2026-10-10 12h57 CMP-00124 NFCE R$ 62,00 Auto Posto Exemplo - OS-00112 Brisa - DEBITO EMPRESA.jpg",
  }]);
  assertEquals(dbx.enviados.length, 0, "nunca duas cópias");
  assertEquals(rpcs(b3, "comprovante_dropbox_movido")[0].args.p_id, CMP_ID);
  // o índice do mês, pelo rev guardado
  assertEquals(rpcs(b3, "comprovantes_indice_do_mes")[0].args, { p_mes: "2026-10-01" });
  assertEquals(dbx.substituidos[0].rev, "00r");
  assertEquals(dbx.substituidos[0].caminho, "/MANAGEMENT/FINANCIALS/COMPROVANTES/2026/2026-10/_INDICE 2026-10.csv");
  assertEquals([...dbx.substituidos[0].bytes.slice(0, 3)], [0xef, 0xbb, 0xbf], "UTF-8 com BOM");
  assertEquals(rpcs(b3, "comprovante_indice_gravado")[0].args, {
    p_mes: "2026-10-01", p_dropbox_id: "id:indice", p_caminho: "/MANAGEMENT/FINANCIALS/COMPROVANTES/2026/2026-10/_INDICE 2026-10.csv", p_rev: "03c", p_linhas: 1,
  });
  // o par do histórico (sem a pergunta seguinte)
  const par = b3.inseridos.ai_operator_messages;
  assertEquals(par?.length, 2);
  assertEquals(par?.[0].content, "🤖 Fluxo de comprovantes (respostas do dono pelo menu, não pelo assistente): CMP-00124 gravado.");
  assertStringIncludes(String(par?.[1].content), `Referência: CMP-00124 (id ${CMP_ID}).`);
  assertEquals(String(par?.[1].content).includes("Fila vazia"), false);
});

Deno.test("F2 responder: texto livre com a pergunta aberta vai ao assistente sem tocar o comprovante_responder", async () => {
  for (const texto of ["quanto ficou a OS 123?", "manda o orçamento do Brisa pro cliente", "sim, mas é da OS 12"]) {
    const banco = bancoDaConversa("para_que", () => { throw new Error("não devia chamar"); });
    const r = await responder(CORPO_RESPONDER(texto), depsF2(banco).deps);
    assertEquals(r.corpo.tratada, false, texto);
    assertEquals(rpcs(banco, "comprovante_responder").length, 0);
  }
});

Deno.test("F2 responder: pendência do assistente mais nova → assistente; empate < 2 min → desempate (sem comprovante_responder)", async () => {
  const mais = rotear("para_que", { pendencia: { tipo: "confirmacao", id: "pa-1", titulo: "Enviar PDF", desde: "2026-10-10T22:40:00Z" } });
  const b1 = bancoDaConversa("para_que", () => null, { pergunta_rotear: () => mais });
  assertEquals((await responder(CORPO_RESPONDER("1"), depsF2(b1).deps)).corpo, { tratada: false, resultado: "assistente" });
  const empate = rotear("para_que", { pendencia: { tipo: "confirmacao", id: "pa-1", titulo: "Enviar PDF", desde: "2026-10-10T22:31:00Z" } });
  const b2 = bancoDaConversa("para_que", () => null, { pergunta_rotear: () => empate });
  const d2 = depsF2(b2);
  assertEquals((await responder(CORPO_RESPONDER("1"), d2.deps)).corpo, { tratada: true, resultado: "desempate" });
  assertEquals(rpcs(b2, "comprovante_responder").length, 0);
  assertEquals(d2.enviosAoDono()[0].dedupe_key, `cmp:d:${MSG_ID}`);
  assertStringIncludes(d2.enviosAoDono()[0].message, 'Fiquei na dúvida: essa resposta é para o CMP-00124 (para quê) ou para o pedido "Enviar PDF"?');
});

Deno.test("F2 responder: citação de pergunta já fechada interpreta pelas opções DELA e responde a ela", async () => {
  const citada = { id: "p-velha", origem: "comprovante", tipo: "pergunta", referencia_id: CMP_ID, status: "respondida", passo: "como_pagou" };
  const banco = bancoDaConversa("para_que", () => ({ resultado: "proximo", cmp: CMP_RESUMO, proxima: perguntaDoBanco("tipo_na_os"), motivo: null }), {
    pergunta_rotear: () => rotear("para_que", { citada }),
  }, {
    whatsapp_perguntas: [{ id: "p-velha", passo: "como_pagou", origem: "comprovante", opcoes: [{ n: 1, rotulo: "Pix", valor: "pix" }, { n: 2, rotulo: "Débito", valor: "debito" }] }],
  });
  await responder(CORPO_RESPONDER("2", { citado: "WA-VELHA" }), depsF2(banco).deps);
  assertEquals(rpcs(banco, "pergunta_rotear")[0].args, { p_phone: DONO.phone, p_citado: "WA-VELHA" });
  assertEquals(rpcs(banco, "comprovante_responder")[0].args.p, { pergunta_id: "p-velha", message_id: MSG_ID, interpretacao: { tipo: "opcao", n: 2 }, versao: null });
});

Deno.test("F2 responder: pergunta velha de CMP já gravado responde aqui (um '1' velho nunca vai ao assistente)", async () => {
  const banco = bancoDaConversa("para_que", () => ({ resultado: "ignorada", cmp: { ...CMP_RESUMO, situacao: "gravado" }, proxima: null, motivo: "ja_gravado" }));
  const d = depsF2(banco);
  assertEquals((await responder(CORPO_RESPONDER("1"), d.deps)).corpo, { tratada: true, resultado: "ignorada" });
  assertEquals(d.enviosAoDono()[0].message, "O CMP-00124 já foi gravado. Para mudar: *cancelar cmp 124 motivo* e mande o arquivo de novo.");
});

Deno.test("F2 responder: inválida → aviso + a mesma pergunta de novo (chave da resposta; o reenvio é registrado)", async () => {
  const banco = bancoDaConversa("para_que", () => ({
    resultado: "invalida", cmp: CMP_RESUMO, motivo: "os_nao_existe", gravacao: null,
    proxima: perguntaDoBanco("para_que", { pergunta_id: P_ID, opcoes: OPCOES_PARA_QUE }),
  }));
  const d = depsF2(banco);
  await responder(CORPO_RESPONDER("os 98"), d.deps);
  assertEquals(rpcs(banco, "comprovante_responder")[0].args.p.interpretacao, { tipo: "os", numero: 98 });
  const [env] = d.enviosAoDono();
  assert(env.message.startsWith("Não achei a OS-00098.\nCMP-00124 · cupom NFC-e"));
  assertEquals(env.dedupe_key, `cmp:r:${MSG_ID}`);
  // revisão de 11/10/2026: o id do reenvio entra na pergunta — citar a mensagem reenviada acha a pergunta
  const marcadas = rpcs(banco, "pergunta_marcar_enviada");
  assertEquals(marcadas.length, 1);
  assertEquals(marcadas[0].args.p_id, P_ID);
  assertStringIncludes(String(marcadas[0].args.p_wa_message_id), "WA-OUT");
});

Deno.test("F2 responder: não gravado (rota recusou) e ocupado (pendência viva)", async () => {
  const b1 = bancoDaConversa("confirmar", () => ({ resultado: "nao_gravado", cmp: CMP_RESUMO, proxima: null, motivo: "o mês está fechado" }));
  const d1 = depsF2(b1);
  await responder(CORPO_RESPONDER("sim"), d1.deps);
  assertEquals(
    d1.enviosAoDono()[0].message,
    "Não gravei o CMP-00124: o mês está fechado no financeiro: reabra o mês ou *cancelar cmp 124 motivo*. Nada mudou. Responda *não* para corrigir.",
  );
  assertEquals(rpcs(b1, "log_app_error").length, 0, "erro conhecido não vai ao app_error_logs");
  const b2 = bancoDaConversa("valor", () => ({ resultado: "proximo", cmp: CMP_RESUMO, proxima: null, motivo: "ocupado", ocupado_por: { origem: "assistente", titulo: "Enviar PDF", desde: "x" } }));
  const d2 = depsF2(b2);
  await responder(CORPO_RESPONDER("62,50"), d2.deps);
  assertEquals(rpcs(b2, "comprovante_responder")[0].args.p.interpretacao, { tipo: "valor", valor: "62.50" });
  assertEquals(d2.enviosAoDono()[0].message, 'Anotei para o CMP-00124. Continuo depois que você responder: "Enviar PDF".');
});

Deno.test("F2 responder: envio da próxima pergunta não confirmado → comprovante_pergunta_nao_enviada", async () => {
  const banco = bancoDaConversa("para_que", () => ({ resultado: "proximo", cmp: CMP_RESUMO, proxima: perguntaDoBanco("tipo_na_os"), motivo: null }), {
    comprovante_pergunta_nao_enviada: () => null,
  });
  await responder(CORPO_RESPONDER("2"), depsF2(banco, { envio: 502 }).deps);
  assertEquals(rpcs(banco, "comprovante_pergunta_nao_enviada")[0].args, { p_pergunta_id: P_PROX });
  assertEquals(rpcs(banco, "pergunta_marcar_enviada").length, 0);
});

Deno.test("F2 responder: o edge reconfere — mensagem enviada, de outro telefone, id inválido = 422; desligada = tratada false", async () => {
  const casos: Array<[Linha, Linha, string]> = [
    [{}, { direction: "outbound" }, "nao_e_recebida"],
    [{ phone: "5547988887777" }, {}, "telefone_divergente"],
    [{ message_id: "x" }, {}, "entrada_invalida"],
    [{ texto: "" }, {}, "entrada_invalida"],
  ];
  for (const [corpo, msg, motivo] of casos) {
    const banco = bancoFalso({ tabelas: { whatsapp_messages: [TEXTO_MSG("1", msg)] }, rpc: { pergunta_rotear: () => rotear("para_que") } });
    const r = await responder({ ...CORPO_RESPONDER("1"), ...corpo } as Qualquer, depsF2(banco).deps);
    assertEquals(r, { status: 422, corpo: { tratada: false, motivo } }, motivo);
    assertEquals(rpcs(banco, "comprovante_responder").length, 0);
  }
  const desligada = bancoFalso({ tabelas: { whatsapp_messages: [TEXTO_MSG("1")] }, rpc: { pergunta_rotear: () => ({ conversa: false, dono: true }) } });
  assertEquals((await responder(CORPO_RESPONDER("1"), depsF2(desligada).deps)).corpo, { tratada: false, resultado: "desligada" });
});

// ─── comandos ─────────────────────────────────────────────────────────────────────────────

function bancoDoComando(resposta: (a: Qualquer) => unknown, extra: Record<string, (a: Qualquer) => unknown> = {}, tabelas: Record<string, Linha[]> = {}) {
  return bancoFalso({
    tabelas: { whatsapp_messages: [TEXTO_MSG("x")], ...tabelas },
    rpc: { pergunta_rotear: () => rotear("para_que"), comprovante_comando: resposta, pergunta_marcar_enviada: () => null, ...extra },
  });
}

Deno.test("F2 comandos: pular, sair, cmp N (cartão), lote antigo, feito, corrigir valor", async () => {
  const pular = bancoDoComando(() => ({ resultado: "pulado", codigo: "CMP-00124", pergunta: perguntaDoBanco("valor", {}, { codigo: "CMP-00125", numero: 125 }), fila: 2 }));
  const dp = depsF2(pular);
  await responder(CORPO_RESPONDER("pular"), dp.deps);
  assertEquals(rpcs(pular, "comprovante_comando")[0].args, { p: { phone: DONO.phone, message_id: MSG_ID, comando: "pular" } });
  assert(dp.enviosAoDono()[0].message.startsWith("CMP-00124 fica para depois (foi para o fim da fila).\n\nCMP-00125"));
  assertEquals(dp.enviosAoDono()[0].dedupe_key, `cmp:p:${P_PROX}`);

  const sair = bancoDoComando(() => ({ resultado: "pausado", fila: 3 }));
  const ds = depsF2(sair);
  await responder(CORPO_RESPONDER("sair"), ds.deps);
  assertEquals(
    ds.enviosAoDono()[0].message,
    "Ok, parei. Faltam 3 comprovantes. Volto a perguntar em até 12 h; para continuar antes: *cmp N* (ou *pendentes* para ver a lista).",
  );

  const cartao = bancoDoComando(() => ({ resultado: "cartao", cmp: { ...CMP_RESUMO, situacao: "gravado", destino: "empresa", categoria: "Outras despesas" }, efeitos: [{ tipo: "caixa", payable_id: "x" }] }));
  const dc = depsF2(cartao);
  await responder(CORPO_RESPONDER("cmp 124"), dc.deps);
  assertEquals(rpcs(cartao, "comprovante_comando")[0].args.p, { phone: DONO.phone, message_id: MSG_ID, comando: "cmp", numero: 124 });
  assertEquals(
    dc.enviosAoDono()[0].message,
    "CMP-00124 (gravado): R$ 62,00 em 10/10 · Auto Posto Exemplo · empresa (sem OS) · Outras despesas. Feito: lancei a saída de R$ 62,00 no Caixa. Para cancelar: *cancelar cmp 124 motivo*.",
  );

  const lote = bancoDoComando(() => ({ resultado: "lote", entraram: [{ id: "a", codigo: "CMP-00012" }, { id: "b", codigo: "CMP-00013" }, { id: "c", codigo: "CMP-00014" }], restam: 0, pergunta: perguntaDoBanco("valor") }));
  const dl = depsF2(lote);
  await responder(CORPO_RESPONDER("lote antigo"), dl.deps);
  assert(dl.enviosAoDono()[0].message.startsWith("Coloquei 3 comprovantes antigos na fila (CMP-00012 a CMP-00014).\n\nCMP-00124"));

  const feito = bancoDoComando(() => ({ resultado: "feito", codigo: "CMP-00119", resolvidas: ["dar_entrada"] }));
  const df = depsF2(feito);
  await responder(CORPO_RESPONDER("feito cmp 119"), df.deps);
  assertEquals(df.enviosAoDono()[0].message, 'CMP-00119: pendência "dar entrada no estoque" marcada como resolvida.');

  const corrigir = bancoDoComando(() => ({ resultado: "pergunta", codigo: "CMP-00124", pergunta: perguntaDoBanco("confirmar", { plano: { efeitos: [] } }) }));
  const dco = depsF2(corrigir);
  await responder(CORPO_RESPONDER("corrigir valor 62,50"), dco.deps);
  assertEquals(rpcs(corrigir, "comprovante_comando")[0].args.p, { phone: DONO.phone, message_id: MSG_ID, comando: "corrigir", campo: "valor", valor: "62.50" });
  assertStringIncludes(dco.enviosAoDono()[0].message, "confira antes de gravar");
});

Deno.test("F2 comandos: cancelar sem motivo não chama o banco; com motivo cancela e leva o arquivo a _CANCELADOS", async () => {
  const sem = bancoDoComando(() => { throw new Error("não devia chamar"); });
  const ds = depsF2(sem);
  await responder(CORPO_RESPONDER("cancelar cmp 124"), ds.deps);
  assertEquals(rpcs(sem, "comprovante_comando").length, 0);
  assertEquals(ds.enviosAoDono()[0].message, "Para cancelar, diga o motivo: *cancelar cmp 124 comprei em dobro*.");

  const banco = bancoDoComando(() => ({
    resultado: "cancelado", cancelamento: { ok: true, codigo: "CMP-00124", desfeitos: [{ tipo: "despesa_os" }, { tipo: "anotar" }], avisos: [] }, pergunta: null,
  }), {
    comprovante_destino_do_arquivo: () => ({ data: {
      id: CMP_ID, codigo: "CMP-00124", situacao: "cancelado", cancelado: true, tipo: "nfce", valor: "62.00", data: "2026-10-10", hora: null,
      fornecedor: null, destino: "os", os: null, forma: "debito", conta: "EMPRESA", mes: "2026-10", dropbox_id: "id:abc",
      dropbox_caminho: "/B2C/0021_Brisa/1- DOC's/Compras/2026-10-10 CMP-00124 NFCE R$ 62,00 - OS-00112 Brisa - DEBITO EMPRESA.jpg",
      dropbox_pendente: "cancelar", arquivo_path: `2026/10/${CMP_ID}.jpg`, arquivo_mime: "image/jpeg",
    } }),
    comprovante_dropbox_movido: () => null,
    comprovantes_indice_do_mes: () => [],
    comprovante_indice_gravado: () => null,
  }, { comprovantes: [{ id: CMP_ID, numero: 124, phone_normalized: DONO.phone }], comprovantes_indice_mensal: [], ai_operator_messages: [] });
  const d = depsF2(banco);
  await responder(CORPO_RESPONDER("cancelar cmp 124 comprei em dobro"), d.deps);
  await d.esperarFundo();
  assertEquals(rpcs(banco, "comprovante_comando")[0].args.p, { phone: DONO.phone, message_id: MSG_ID, comando: "cancelar", numero: 124, motivo: "comprei em dobro" });
  assertEquals(
    d.enviosAoDono()[0].message,
    "CMP-00124 cancelado (comprei em dobro). Desfeito: a despesa interna da OS, a anotação do extrato. Arquivo em COMPROVANTES/_CANCELADOS.",
  );
  assertEquals(d.dbx!.r.movidos, [{
    de: "id:abc",
    para: "/MANAGEMENT/FINANCIALS/COMPROVANTES/_CANCELADOS/2026-10-10 CMP-00124 NFCE R$ 62,00 - OS-00112 Brisa - DEBITO EMPRESA CANCELADO.jpg",
  }]);
  assertEquals(rpcs(banco, "comprovantes_indice_do_mes")[0].args, { p_mes: "2026-10-01" });
  assertEquals(d.dbx!.r.substituidos[0].rev, null, "primeira vez: add");

  const recusado = bancoDoComando(() => ({
    resultado: "cancelamento_recusado", pergunta: null,
    cancelamento: { ok: false, codigo: "CMP-00124", bloqueios: [{ efeito: "caixa", motivo: "mes_fechado", como_destravar: "x" }] },
  }));
  const dr = depsF2(recusado);
  await responder(CORPO_RESPONDER("cancelar cmp 124 errado"), dr.deps);
  assertEquals(dr.enviosAoDono()[0].message, "Não cancelei o CMP-00124: o mês está fechado no financeiro; reabra o mês e cancele de novo. Nada mudou.");
  assertEquals(dr.dbx!.r.movidos.length, 0);
});

// ─── pendentes e desempate ────────────────────────────────────────────────────────────────

Deno.test("F2 pendentes: a lista com a chave cmp:pend e o histórico; nada em aberto = não manda", async () => {
  const banco = bancoFalso({
    tabelas: { whatsapp_messages: [TEXTO_MSG("pendentes")], ai_operator_messages: [] },
    rpc: {
      pergunta_rotear: () => rotear(null),
      comprovantes_pendentes: () => ({ abertos: [{ codigo: "CMP-00124", numero: 124, data: "2026-10-10", valor: "62.00", fornecedor: null, situacao: "aguardando_vez", falta: "para_que", pendencias: [] }], total: 1, antigos: 0 }),
    },
  });
  const d = depsF2(banco);
  assertEquals(await pendentes({ message_id: MSG_ID, phone: DONO.phone }, d.deps), { enviada: true, itens: 1 });
  assertEquals(d.enviosAoDono()[0].dedupe_key, `cmp:pend:${MSG_ID}`);
  assertEquals(d.enviosAoDono()[0].message, "Comprovantes em aberto (1):\n1. CMP-00124 · 10/10 · R$ 62,00 — falta: para quê\nPara continuar um: *cmp 124*.");
  assertEquals(banco.inseridos.ai_operator_messages?.length, 2);

  const vazio = bancoFalso({ tabelas: { whatsapp_messages: [TEXTO_MSG("pendentes")] }, rpc: { pergunta_rotear: () => rotear(null), comprovantes_pendentes: () => ({ abertos: [], total: 0, antigos: 0 }) } });
  const dv = depsF2(vazio);
  assertEquals(await pendentes({ message_id: MSG_ID, phone: DONO.phone }, dv.deps), { enviada: false, itens: 0 });
  assertEquals(dv.enviosAoDono().length, 0);
});

Deno.test("F2 histórico: o par recente deste fluxo (< 2 h) ganha a linha nova em vez de outro par", async () => {
  const banco = bancoFalso({
    tabelas: {
      whatsapp_messages: [TEXTO_MSG("pendentes")],
      ai_operator_messages: [
        { id: "m-u", session_id: "sessao-1", role: "user", created_at: "2026-10-10T22:00:00.000Z", content: "🤖 Fluxo de comprovantes (respostas do dono pelo menu, não pelo assistente): CMP-00123 gravado." },
        { id: "m-a", session_id: "sessao-1", role: "assistant", created_at: "2026-10-10T22:00:00.001Z", content: "CMP-00123 gravado: …" },
      ],
    },
    rpc: { pergunta_rotear: () => rotear(null), comprovantes_pendentes: () => ({ abertos: [{ codigo: "CMP-00124", situacao: "aguardando_vez", falta: "valor" }], total: 1, antigos: 0 }) },
  });
  await pendentes({ message_id: MSG_ID, phone: DONO.phone }, depsF2(banco).deps);
  assertEquals(banco.inseridos.ai_operator_messages, undefined);
  assertStringIncludes(String(banco.tabelas.ai_operator_messages[1].content), "CMP-00123 gravado: …\n\nComprovantes em aberto (1):");
});

Deno.test("F2 desempatar: só com pergunta de CMP aberta, chave cmp:d", async () => {
  const banco = bancoFalso({
    tabelas: { whatsapp_messages: [TEXTO_MSG("1")] },
    rpc: { pergunta_rotear: () => rotear("tipo_na_os", { pendencia: { tipo: "confirmacao", id: "pa-1", titulo: "Lembrete ao cliente", desde: "2026-10-10T22:30:30Z" } }) },
  });
  const d = depsF2(banco);
  assertEquals(await desempatar({ message_id: MSG_ID, phone: DONO.phone, citado: null }, d.deps), { enviada: true });
  assertEquals(d.enviosAoDono()[0].dedupe_key, `cmp:d:${MSG_ID}`);
  assertStringIncludes(d.enviosAoDono()[0].message, "CMP-00124 (se é peça ou despesa da OS)");
  const sem = bancoFalso({ tabelas: { whatsapp_messages: [TEXTO_MSG("1")] }, rpc: { pergunta_rotear: () => rotear(null) } });
  assertEquals(await desempatar({ message_id: MSG_ID, phone: DONO.phone }, depsF2(sem).deps), { enviada: false });
});

// ─── Dropbox: mover e índice ──────────────────────────────────────────────────────────────

function destinoDoArquivo(extra: Linha = {}): Linha {
  return {
    id: CMP_ID, codigo: "CMP-00124", situacao: "gravado", cancelado: false, tipo: "nfce", valor: "62.00", valor_confirmado: true, data: "2026-10-10",
    hora: null, fornecedor: "Auto Posto Exemplo", destino: "empresa", os: null, forma: "pix", conta: "NUBANK", mes: "2026-10", dropbox_id: "id:abc",
    dropbox_caminho: "/MANAGEMENT/FINANCIALS/COMPROVANTES/_A CLASSIFICAR/x.jpg", dropbox_pendente: "mover", arquivo_path: `2026/10/${CMP_ID}.jpg`,
    arquivo_mime: "image/jpeg", ...extra,
  };
}

function bancoDoMover(d: Linha, tabelas: Record<string, Linha[]> = {}) {
  return bancoFalso({
    tabelas,
    rpc: {
      // { data } explícito: a linha tem o campo "data" (a data da compra) e o dublê o leria como envelope
      comprovante_destino_do_arquivo: () => ({ data: d }),
      comprovante_dropbox_movido: () => null,
      comprovante_dropbox_mover_falhou: () => ({ tentativas: 1, desistiu: false }),
    },
  });
}

Deno.test("F2 moverNoDropbox: empresa/pessoal no mês; OS sem pasta e sem pasta-base no mês (nunca /HBR-Testes)", async () => {
  const empresa = bancoDoMover(destinoDoArquivo());
  const de = depsF2(empresa);
  const ok = await moverNoDropbox(CMP_ID, de.deps);
  assertEquals(ok, true);
  assertEquals(de.dbx!.r.movidos[0].para, "/MANAGEMENT/FINANCIALS/COMPROVANTES/2026/2026-10/2026-10-10 CMP-00124 NFCE R$ 62,00 Auto Posto Exemplo - EMPRESA - PIX NUBANK.jpg");
  assertEquals(rpcs(empresa, "comprovante_dropbox_movido")[0].args, {
    p_id: CMP_ID, p_dropbox_id: "id:abc", p_caminho: de.dbx!.r.movidos[0].para, p_rev: "02b", p_pendente: "mover",
  });

  const pessoal = bancoDoMover(destinoDoArquivo({ destino: "pessoal", forma: null, conta: null }));
  const dp = depsF2(pessoal);
  await moverNoDropbox(CMP_ID, dp.deps);
  assertEquals(dp.dbx!.r.movidos[0].para, "/MANAGEMENT/FINANCIALS/COMPROVANTES/PESSOAL/2026-10/2026-10-10 CMP-00124 NFCE R$ 62,00 Auto Posto Exemplo - PESSOAL.jpg");

  const os = { numero: "OS-00112", vessel_id: "v-1", client_id: "cl-1", barco: "Brisa", cliente: "João", pasta_registrada: false };
  const semPasta = bancoDoMover(destinoDoArquivo({ destino: "os", os }));
  const ds = depsF2(semPasta);
  let pediuPasta = 0;
  ds.deps.pastaDoBarco = () => { pediuPasta++; return Promise.reject(new Error("não devia")); };
  await moverNoDropbox(CMP_ID, ds.deps);
  assertEquals(pediuPasta, 0);
  assert(ds.dbx!.r.movidos[0].para.startsWith("/MANAGEMENT/FINANCIALS/COMPROVANTES/2026/2026-10/"));
  assertEquals(ds.dbx!.r.pastas.length, 0);
});

Deno.test("F2 moverNoDropbox: sem cópia no Dropbox (ou o dono apagou) sobe do bucket direto no destino; já no destino só registra", async () => {
  const semId = bancoDoMover(destinoDoArquivo({ dropbox_id: null, dropbox_caminho: null }));
  const d1 = depsF2(semId);
  assertEquals(await moverNoDropbox(CMP_ID, d1.deps), true);
  assertEquals(d1.dbx!.r.movidos.length, 0);
  assertEquals(d1.dbx!.r.enviados.map((e) => e.caminho), ["/MANAGEMENT/FINANCIALS/COMPROVANTES/2026/2026-10/2026-10-10 CMP-00124 NFCE R$ 62,00 Auto Posto Exemplo - EMPRESA - PIX NUBANK.jpg"]);
  assertEquals(semId.storage.baixados, [`2026/10/${CMP_ID}.jpg`]);

  const apagado = bancoDoMover(destinoDoArquivo());
  const d2 = depsF2(apagado, { dropbox: dropboxFalso({ atual: "sumiu" }) });
  assertEquals(await moverNoDropbox(CMP_ID, d2.deps), true);
  assertEquals(d2.dbx!.r.enviados.length, 1);

  const destino = "/MANAGEMENT/FINANCIALS/COMPROVANTES/2026/2026-10/2026-10-10 CMP-00124 NFCE R$ 62,00 Auto Posto Exemplo - EMPRESA - PIX NUBANK.jpg";
  const jaLa = bancoDoMover(destinoDoArquivo());
  const d3 = depsF2(jaLa, { dropbox: dropboxFalso({ atual: destino.toUpperCase() }) });
  assertEquals(await moverNoDropbox(CMP_ID, d3.deps), true);
  assertEquals(d3.dbx!.r.movidos.length + d3.dbx!.r.enviados.length, 0, "não move de novo");
  assertEquals(rpcs(jaLa, "comprovante_dropbox_movido").length, 1);
});

Deno.test("F2 moverNoDropbox: erro do Dropbox, sem conexão, nada pendente", async () => {
  const erro = bancoDoMover(destinoDoArquivo());
  assertEquals(await moverNoDropbox(CMP_ID, depsF2(erro, { dropbox: dropboxFalso({ erroNoMover: { status: 409, resumo: "to/conflict/file/.." } }) }).deps), false);
  assertEquals(rpcs(erro, "comprovante_dropbox_mover_falhou")[0].args, { p_id: CMP_ID, p_erro: "dropbox_409:to/conflict/file/..", p_pendente: "mover" });
  assertEquals(rpcs(erro, "comprovante_dropbox_movido").length, 0);

  const semConexao = bancoDoMover(destinoDoArquivo());
  assertEquals(await moverNoDropbox(CMP_ID, depsF2(semConexao, { dropbox: null }).deps), false);
  assertEquals(rpcs(semConexao, "comprovante_dropbox_mover_falhou")[0].args.p_erro, "dropbox_sem_conexao");

  const nada = bancoDoMover(destinoDoArquivo({ dropbox_pendente: null }));
  const dn = depsF2(nada);
  assertEquals(await moverNoDropbox(CMP_ID, dn.deps), false);
  assertEquals(dn.dbx!.r.metadados.length, 0);
});

Deno.test("F2 atualizarIndice: conflito de rev (o dono editou) grava num arquivo novo; Dropbox fora → backoff", async () => {
  const banco = bancoFalso({
    tabelas: { comprovantes_indice_mensal: [{ mes: "2026-10-01", caminho: "/MANAGEMENT/FINANCIALS/COMPROVANTES/2026/2026-10/_INDICE 2026-10.csv", rev: "00r" }] },
    rpc: { comprovantes_indice_do_mes: () => ({ linhas: [] }), comprovante_indice_gravado: () => null, comprovante_indice_falhou: () => ({ desistiu: false }) },
  });
  const d = depsF2(banco, { dropbox: dropboxFalso({ conflito: true }) });
  assertEquals(await atualizarIndice("2026-10", d.deps), true);
  assertEquals(rpcs(banco, "comprovante_indice_gravado")[0].args.p_caminho, "/MANAGEMENT/FINANCIALS/COMPROVANTES/2026/2026-10/_INDICE 2026-10 (1).csv");
  assertEquals(d.logs.find((l) => l.evento === "indice_gravado")?.campos, { mes: "2026-10", linhas: 0, conflito: true });

  const fora = depsF2(banco, { dropbox: null });
  assertEquals(await atualizarIndice("2026-10-01", fora.deps), false);
  assertEquals(rpcs(banco, "comprovante_indice_falhou")[0].args, { p_mes: "2026-10-01", p_erro: "dropbox_sem_conexao" });
  assertEquals(await atualizarIndice("outubro", fora.deps), false);
});

// ─── CNPJ ─────────────────────────────────────────────────────────────────────────────────

Deno.test("F2 consultarCnpj: 404 = não encontrado no cache; 5xx e rede = nada; CNPJ inválido nem consulta", async () => {
  const b404 = bancoFalso({ rpc: { comprovante_cnpj_cache: () => null } });
  await consultarCnpj(CNPJ, depsF2(b404, { brasilapi: 404 }).deps);
  assertEquals(rpcs(b404, "comprovante_cnpj_cache")[0].args, { p_cnpj: CNPJ, p_dados: { encontrado: false } });
  for (const brasilapi of [503, "rede"] as const) {
    const b = bancoFalso({ rpc: { comprovante_cnpj_cache: () => null } });
    await consultarCnpj(CNPJ, depsF2(b, { brasilapi }).deps);
    assertEquals(rpcs(b, "comprovante_cnpj_cache").length, 0);
  }
  const bInv = bancoFalso();
  const dInv = depsF2(bInv);
  await consultarCnpj("12345678901", dInv.deps);
  assertEquals(dInv.envios.length, 0);
});

// ─── vigia ────────────────────────────────────────────────────────────────────────────────

Deno.test("F2 vigia: subir, mover, índices, CNPJ (antes) e perguntar; erro na reserva da conversa não derruba a F1", async () => {
  const banco = bancoFalso({
    tabelas: { comprovantes_indice_mensal: [] },
    rpc: {
      comprovantes_vigia_lote: () => ({ expurgados: 0 }),
      comprovantes_vigia_conversa: () => ({ subir: [DA], mover: [CMP_ID], indices: ["2026-10-01"], perguntar: [DONO.phone], cnpj: [CNPJ, "1", "2", "3"] }),
      comprovante_no_dropbox: () => null,
      comprovante_destino_do_arquivo: () => ({ data: destinoDoArquivo() }),
      comprovante_dropbox_movido: () => null,
      comprovantes_indice_do_mes: () => [],
      comprovante_indice_gravado: () => null,
      comprovante_cnpj_cache: () => null,
      comprovante_proxima_pergunta: () => ({ perguntou: true, ...perguntaDoBanco("valor", { retomada: true }) }),
      pergunta_marcar_enviada: () => null,
    },
  });
  const d = depsF2(banco);
  const n = await vigiar(d.deps);
  assertEquals([n.dropbox, n.movidos, n.indices, n.cnpj, n.perguntas], [1, 1, 1, 3, 1]);
  assertEquals(rpcs(banco, "comprovantes_vigia_conversa")[0].args, { p_limite: 10 });
  assertEquals(rpcs(banco, "comprovante_proxima_pergunta")[0].args.p_motivo, "vigia");
  const ordem = banco.chamadasRpc.map((c) => c.nome);
  assert(ordem.indexOf("comprovante_cnpj_cache") < ordem.indexOf("comprovante_proxima_pergunta"), "o CNPJ antes da pergunta");

  const quebrada = bancoFalso({ rpc: { comprovantes_vigia_lote: () => ({ expurgados: 0 }), comprovantes_vigia_conversa: () => ({ error: { code: "42883", message: "x" } }) } });
  const dq = depsF2(quebrada);
  const nq = await vigiar(dq.deps);
  assertEquals(nq.movidos, 0);
  assertEquals(dq.logs.some((l) => l.evento === "vigia_conversa_falhou" && l.campos?.codigo === "comprovantes_vigia_conversa:42883"), true);
});

// ─── privacidade ──────────────────────────────────────────────────────────────────────────

Deno.test("F2: nenhum console.* com texto do dono, valor, CNPJ, nome ou caminho do arquivo", async () => {
  const saida: string[] = [];
  const originais = { log: console.log, error: console.error, warn: console.warn, info: console.info };
  for (const k of Object.keys(originais) as Array<keyof typeof originais>) {
    console[k] = (...a: unknown[]) => { saida.push(a.map((x) => typeof x === "string" ? x : JSON.stringify(x)).join(" ")); };
  }
  try {
    const gravado = { ...CMP_RESUMO, situacao: "gravado", destino: "empresa" };
    const banco = bancoDaConversa("confirmar", () => ({
      resultado: "gravado", cmp: gravado, proxima: null, motivo: null, gravacao: { situacao: "gravado", efeitos: [{ tipo: "caixa" }], mes: "2026-10-01" },
    }), {
      comprovante_destino_do_arquivo: () => ({ data: destinoDoArquivo() }),
      comprovante_dropbox_movido: () => ({ error: { code: "XX000", message: "Auto Posto Exemplo 62.00" } }),
      comprovantes_indice_do_mes: () => [{ codigo: "CMP-00124", fornecedor: "Auto Posto Exemplo", valor: "62.00", cnpj: CNPJ }],
      comprovante_indice_gravado: () => null,
      comprovante_cnpj_cache: () => null,
    }, { comprovantes_indice_mensal: [], ai_operator_messages: [] });
    const d = depsF2(banco, { brasilapi: 503 });
    d.deps.log = logDoFluxo;
    await responder(CORPO_RESPONDER("sim pode gravar Auto Posto Exemplo 62,00"), d.deps); // texto livre
    await responder(CORPO_RESPONDER("sim"), d.deps);
    await d.esperarFundo();
    await atualizarIndice("2026-10", d.deps);
    await consultarCnpj(CNPJ, d.deps);
    // a rota recusou com uma mensagem que traz dado: nem ao dono (texto fixo, revisão de 11/10/2026)
    // nem ao log; o app_error_logs recebe só o código do erro e o id do CMP
    const recusa = bancoDaConversa("confirmar", () => ({
      resultado: "nao_gravado", cmp: CMP_RESUMO, proxima: null, motivo: "categoria Auto Posto Exemplo inválida para 62.00", codigo_erro: "P0001",
    }));
    const dr = depsF2(recusa);
    dr.deps.log = logDoFluxo;
    await responder(CORPO_RESPONDER("sim"), dr.deps);
    const aoDono = dr.enviosAoDono()[0].message;
    assertStringIncludes(aoDono, "deu um erro no sistema (código P0001)");
    assertEquals(aoDono.includes("Auto Posto"), false);
    const erros = JSON.stringify(rpcs(recusa, "log_app_error").map((c) => c.args));
    assertStringIncludes(erros, "nao_gravado:P0001");
    for (const proibido of ["Auto Posto", "62.00"]) assertEquals(erros.includes(proibido), false, `vazou no app_error_logs: ${proibido}`);
  } finally {
    Object.assign(console, originais);
  }
  const tudo = saida.join("\n");
  assert(saida.length > 0);
  for (const proibido of ["Auto Posto", "62.00", "62,00", CNPJ, "11.222.333", "NUBANK", "_A CLASSIFICAR", "sim pode gravar", "Brisa"]) {
    assertEquals(tudo.includes(proibido), false, `vazou no log: ${proibido}`);
  }
});

Deno.test("F2 moverNoDropbox sem pasta-base: a pasta registrada viva vale; apagada → pasta do mês, sem criar nada na raiz", async () => {
  const os = { numero: "OS-00112", vessel_id: "v-1", client_id: "cl-1", barco: "Brisa", cliente: "João", pasta_registrada: true };
  for (const viva of [true, false]) {
    const banco = bancoFalso({
      tabelas: {
        app_settings: [],
        pastas_dropbox: [{ id: "pd-1", dropbox_id: "id:pasta-brisa", caminho: "/B2C/0021_Brisa", vessel_id: "v-1", situacao: "vinculada", codigo_projeto: "0021.002.26", created_at: "2026-01-01" }],
      },
      rpc: {
        comprovante_destino_do_arquivo: () => ({ data: destinoDoArquivo({ destino: "os", os, forma: "debito", conta: "EMPRESA" }) }),
        comprovante_dropbox_movido: () => null,
        proximo_codigo_projeto: () => "0099.001.26",
      },
    });
    const { dbx, r } = dropboxFalso();
    dbx.rpc = (rota: string, corpo: Qualquer) => {
      r.metadados.push(`${rota}:${corpo?.path}`);
      if (corpo?.path === "id:pasta-brisa") {
        return viva ? Promise.resolve({ id: "id:pasta-brisa", path_display: "/B2C/0021_Brisa", rev: "" })
          : Promise.reject(new ErroDropbox("x", 409, "path/not_found/..", false));
      }
      return Promise.resolve({ id: "id:abc", path_display: "/MANAGEMENT/FINANCIALS/COMPROVANTES/_A CLASSIFICAR/x.jpg", rev: "00z" });
    };
    const d = depsF2(banco, { dropbox: { dbx, r } });
    delete d.deps.pastaDoBarco; // o caminho de verdade (pastas_dropbox + get_metadata)
    assertEquals(await moverNoDropbox(CMP_ID, d.deps), true);
    assertEquals(rpcs(banco, "proximo_codigo_projeto").length, 0, "nunca cria pasta de barco sem a pasta-base");
    const para = r.movidos[0].para;
    if (viva) {
      assert(para.startsWith("/B2C/0021_Brisa/1- DOC's/Compras/2026-10-10 CMP-00124 "), para);
      assertEquals(r.pastas, ["/B2C/0021_Brisa/1- DOC's/Compras"]);
    } else {
      assert(para.startsWith("/MANAGEMENT/FINANCIALS/COMPROVANTES/2026/2026-10/"), para);
      assertEquals(r.pastas, []);
    }
  }
});

// ─── revisão de 11/10/2026: dica, foto citada, não entendi, corrigir, retomar ──────────────

Deno.test("F2 responder: texto logo depois da foto vira dica do CMP que chegou (não vai ao assistente)", async () => {
  const banco = bancoFalso({
    tabelas: { whatsapp_messages: [TEXTO_MSG("x")] },
    rpc: {
      pergunta_rotear: () => rotear(null, { cmp_chegando: { id: "c-2", codigo: "CMP-00125" } }),
      comprovante_acrescentar_dica: () => ({ ok: true, codigo: "CMP-00125", destino: "os" }),
    },
  });
  const d = depsF2(banco);
  const r = await responder(CORPO_RESPONDER("essa é da OS do Brisa", { destino: "dica" }), d.deps);
  assertEquals(r.corpo, { tratada: true, resultado: "dica" });
  assertEquals(rpcs(banco, "comprovante_acrescentar_dica")[0].args, { p_id: "c-2", p_texto: "essa é da OS do Brisa", p_message_id: MSG_ID });
  assertEquals(d.enviosAoDono()[0].message, "Anotei para o CMP-00125.");

  // o banco recusou (o CMP já foi perguntado, conversa desligou): vai ao assistente
  const recusou = bancoFalso({
    tabelas: { whatsapp_messages: [TEXTO_MSG("x")] },
    rpc: {
      pergunta_rotear: () => rotear(null, { cmp_chegando: { id: "c-2", codigo: "CMP-00125" } }),
      comprovante_acrescentar_dica: () => ({ ok: false, codigo: "CMP-00125" }),
    },
  });
  const d2 = depsF2(recusou);
  assertEquals((await responder(CORPO_RESPONDER("essa é da OS do Brisa", { destino: "dica" }), d2.deps)).corpo, { tratada: false, resultado: "assistente" });
  assertEquals(d2.enviosAoDono().length, 0);
});

Deno.test("F2 responder: citou a FOTO de um CMP gravado → o cartão dele; não gravado → a resposta vale para a última pergunta dele", async () => {
  const gravado = bancoFalso({
    tabelas: { whatsapp_messages: [TEXTO_MSG("x")] },
    rpc: {
      pergunta_rotear: () => rotear(null, { citado_cmp: { id: CMP_ID, codigo: "CMP-00124", situacao: "gravado", gravado: true } }),
      comprovante_comando: () => ({ resultado: "cartao", cmp: { ...CMP_RESUMO, situacao: "gravado", destino: "empresa" }, efeitos: [] }),
    },
  });
  await responder(CORPO_RESPONDER("e essa?", { citado: "WA-FOTO", destino: "foto_do_cmp" }), depsF2(gravado).deps);
  assertEquals(rpcs(gravado, "comprovante_comando")[0].args.p, { phone: DONO.phone, message_id: MSG_ID, comando: "cmp", numero: 124 });

  const aberto = bancoFalso({
    tabelas: {
      whatsapp_messages: [TEXTO_MSG("x")],
      whatsapp_perguntas: [{ id: P_ID, referencia_id: CMP_ID, origem: "comprovante", passo: "para_que", opcoes: OPCOES_PARA_QUE, aberta_em: "2026-10-10T22:30:00Z" }],
    },
    rpc: {
      pergunta_rotear: () => rotear(null, { citado_cmp: { id: CMP_ID, codigo: "CMP-00124", situacao: "aguardando_vez", gravado: false } }),
      comprovante_responder: () => ({ resultado: "proximo", cmp: CMP_RESUMO, proxima: null, motivo: null }),
      pergunta_marcar_enviada: () => null,
    },
  });
  await responder(CORPO_RESPONDER("estoque", { citado: "WA-FOTO", destino: "foto_do_cmp" }), depsF2(aberto).deps);
  const resposta = rpcs(aberto, "comprovante_responder")[0].args.p;
  assertEquals(resposta.pergunta_id, P_ID);
  assertEquals(resposta.interpretacao, { tipo: "palavra", valor: "estoque" });
});

Deno.test("F2 responder: mensagem curta não entendida → 'Não entendi para o CMP' + a pergunta de novo (não vai ao assistente)", async () => {
  const comoPagou = rotear("como_pagou");
  comoPagou.ativa.opcoes = [{ n: 1, rotulo: "Pix", valor: "pix" }, { n: 2, rotulo: "Débito", valor: "debito" }, { n: 3, rotulo: "Crédito", valor: "credito" }];
  const banco = bancoFalso({
    tabelas: { whatsapp_messages: [TEXTO_MSG("x")] },
    rpc: {
      pergunta_rotear: () => comoPagou,
      comprovante_proxima_pergunta: () => ({ perguntou: true, ...perguntaDoBanco("como_pagou", { pergunta_id: P_ID, opcoes: comoPagou.ativa.opcoes }) }),
      pergunta_marcar_enviada: () => null,
    },
  });
  const d = depsF2(banco);
  assertEquals((await responder(CORPO_RESPONDER("cartão", { destino: "nao_entendi" }), d.deps)).corpo, { tratada: true, resultado: "nao_entendi" });
  assertEquals(rpcs(banco, "comprovante_proxima_pergunta")[0].args, { p_phone: DONO.phone, p_motivo: "reabrir", p_cmp: CMP_ID });
  assert(d.enviosAoDono()[0].message.startsWith("Não entendi para o CMP-00124."));
  assertStringIncludes(d.enviosAoDono()[0].message, "Como foi pago?");
});

Deno.test("F2 comandos: 'corrigir' sozinho no resumo = não; fora dele ensina; corrigido diz o que mudou; qual dos dois", async () => {
  // no resumo: vira o "não" (o menu do corrigir)
  const resumo = bancoFalso({
    tabelas: { whatsapp_messages: [TEXTO_MSG("x")] },
    rpc: {
      pergunta_rotear: () => rotear("confirmar"),
      comprovante_responder: () => ({ resultado: "proximo", cmp: CMP_RESUMO, proxima: null, motivo: null }),
      pergunta_marcar_enviada: () => null,
    },
  });
  await responder(CORPO_RESPONDER("corrigir"), depsF2(resumo).deps);
  assertEquals(rpcs(resumo, "comprovante_responder")[0].args.p.interpretacao, { tipo: "nao" });

  // com a pergunta de outro passo aberta: o jeito de mandar
  const fora = bancoDoComando(() => { throw new Error("não devia chamar"); });
  const df = depsF2(fora);
  await responder(CORPO_RESPONDER("corrigir"), df.deps);
  assertStringIncludes(df.enviosAoDono()[0].message, "*corrigir valor 62,50*");
  assertEquals(rpcs(fora, "comprovante_comando").length, 0);

  // corrigido: a linha do que mudou antes da pergunta seguinte
  const corrigido = bancoDoComando(() => ({
    resultado: "pergunta", codigo: "CMP-00124", corrigido: { campo: "valor", valor: "70.00" }, pergunta: perguntaDoBanco("confirmar", { plano: { efeitos: [] } }),
  }));
  const dc = depsF2(corrigido);
  await responder(CORPO_RESPONDER("corrigir valor 70"), dc.deps);
  assert(dc.enviosAoDono()[0].message.replace(/ /g, " ").startsWith("CMP-00124: valor corrigido para R$ 70,00.\n\n"));

  // logo depois de gravar um e abrir o próximo: qual dos dois?
  const qual = bancoDoComando(() => ({ resultado: "qual_cmp", gravado: "CMP-00124", aberto: "CMP-00125" }));
  const dq = depsF2(qual);
  await responder(CORPO_RESPONDER("corrigir valor 70"), dq.deps);
  assertStringIncludes(dq.enviosAoDono()[0].message, "*corrigir cmp 125 valor 70*");
  assertStringIncludes(dq.enviosAoDono()[0].message, "*cancelar cmp 124 motivo*");

  // com o número explícito, vai ao banco com ele
  const comNumero = bancoDoComando(() => ({ resultado: "pergunta", codigo: "CMP-00125", pergunta: null, corrigido: { campo: "valor", valor: "70.00" } }));
  await responder(CORPO_RESPONDER("corrigir cmp 125 valor 70"), depsF2(comNumero).deps);
  assertEquals(rpcs(comNumero, "comprovante_comando")[0].args.p, {
    phone: DONO.phone, message_id: MSG_ID, comando: "corrigir", campo: "valor", valor: "70.00", cmp: 125,
  });
});

Deno.test("F2 retomar: só para o telefone do dono; pergunta com o motivo 'retomar'", async () => {
  const banco = bancoFalso({
    rpc: {
      comprovante_proxima_pergunta: () => ({ perguntou: true, ...perguntaDoBanco("valor", { pergunta_id: P_ID }) }),
      pergunta_marcar_enviada: () => null,
    },
  });
  const d = depsF2(banco);
  assertEquals(await retomar({ phone: DONO.phone }, d.deps), { perguntou: true });
  assertEquals(rpcs(banco, "comprovante_proxima_pergunta")[0].args, { p_phone: DONO.phone, p_motivo: "retomar", p_cmp: null });
  assertEquals(await retomar({ phone: "5547988887777" }, d.deps), { perguntou: false });
  assertEquals(await retomar({ phone: "x" } as never, d.deps), { perguntou: false });
  assertEquals(rpcs(banco, "comprovante_proxima_pergunta").length, 1);
});

Deno.test("F2 abertura sem perguntar agora (pendência do assistente aberta): uma linha diz que o CMP está na fila", async () => {
  const banco = bancoFalso({
    rpc: {
      comprovante_reservar_aviso: () => ({ esperando: 0, itens: [ITEM_CMP] }),
      pergunta_rotear: () => rotear(null),
      comprovante_conversa_entrar: () => ({ entraram: [{ id: CMP_ID, codigo: "CMP-00123" }], fila: 1 }),
      comprovantes_cnpj_a_consultar: () => [],
      comprovante_proxima_pergunta: () => ({ perguntou: false, motivo: "ocupado", ocupado_por: { origem: "assistente", titulo: "Enviar PDF", desde: "x" } }),
    },
  });
  const d = depsF2(banco);
  assertEquals(await talvezAvisar(DONO.phone, false, d.deps), 1);
  const [linha] = d.enviosAoDono();
  assertEquals(linha.message, 'Recebi o CMP-00123; está na fila: pergunto depois do pedido "Enviar PDF". Para conferir agora: *cmp 123*.');
  assertEquals(linha.dedupe_key, `cmp:fila:${CMP_ID}`);
  assertEquals(d.enviosAoDono().some((c) => String(c.message).includes("guardado")), false, "não repete o aviso da F1");
});

Deno.test("F3 abertura: a pergunta do extrato aberta pelo vigia cede a vez ao comprovante novo (R10) e a F2 pergunta já", async () => {
  let aberturas = 0;
  const banco = bancoFalso({
    rpc: {
      comprovante_reservar_aviso: () => ({ esperando: 0, itens: [ITEM_CMP] }),
      pergunta_rotear: () => rotear(null),
      comprovante_conversa_entrar: () => ({ entraram: [{ id: CMP_ID, codigo: "CMP-00123" }], fila: 1 }),
      comprovantes_cnpj_a_consultar: () => [],
      // 1ª: ocupado com a pergunta do extrato do CMP-00120; depois de ceder, abre a do comprovante novo
      comprovante_proxima_pergunta: () => (++aberturas === 1
        ? { perguntou: false, motivo: "ocupado", ocupado_por: { origem: "comprovante", titulo: "CMP-00120", desde: "x" } }
        : { perguntou: true, ...perguntaDoBanco("para_que", { pergunta_id: P_ID, opcoes: OPCOES_PARA_QUE }) }),
      comprovante_banco_ceder: () => ({ cedeu: true, codigo: "CMP-00120" }),
      pergunta_marcar_enviada: () => null,
    },
  });
  const d = depsF2(banco);
  assertEquals(await talvezAvisar(DONO.phone, false, d.deps), 1);
  assertEquals(rpcs(banco, "comprovante_banco_ceder").map((c) => c.args), [{ p_phone: DONO.phone }]);
  assertEquals(rpcs(banco, "comprovante_proxima_pergunta").length, 2);
  assertEquals(d.enviosAoDono().some((c) => String(c.message).includes("está na fila")), false, "não manda o \"na fila\"");
  assertEquals(d.enviosAoDono().length, 1, "só a pergunta da F2");

  // ocupado com outra coisa (pergunta da F2 ou pendência do assistente): não cede; a linha da fila sai
  let n2 = 0;
  const banco2 = bancoFalso({
    rpc: {
      comprovante_reservar_aviso: () => ({ esperando: 0, itens: [ITEM_CMP] }),
      pergunta_rotear: () => rotear(null),
      comprovante_conversa_entrar: () => ({ entraram: [{ id: CMP_ID, codigo: "CMP-00123" }], fila: 1 }),
      comprovantes_cnpj_a_consultar: () => [],
      comprovante_proxima_pergunta: () => {
        n2 += 1;
        return { perguntou: false, motivo: "ocupado", ocupado_por: { origem: "assistente", titulo: "Enviar PDF", desde: "x" } };
      },
      comprovante_banco_ceder: () => ({ cedeu: false, codigo: null }),
    },
  });
  const d2 = depsF2(banco2);
  assertEquals(await talvezAvisar(DONO.phone, false, d2.deps), 1);
  assertEquals(n2, 1, "sem ceder, não tenta de novo");
  assertStringIncludes(String(d2.enviosAoDono()[0].message), "está na fila");
});

// =============================================================================================
// F3: a pergunta do extrato (spec-f3.md, 4.4). O banco falso devolve as formas da 3.7: R3
// (comprovante_banco_proxima), R4 (comprovante_banco_responder), R6 (comprovantes_vigia_banco) e
// R7-R9 (índice da pasta PESSOAL). Nenhuma rede.
// =============================================================================================

const TX_1 = "55555555-0000-4000-8000-000000000001";
const TX_2 = "55555555-0000-4000-8000-000000000002";
const P_EXTRATO = "44444444-0000-4000-8000-000000000003";

const LINHA_DEBITO = {
  n: 1, id: TX_1, data: "2026-10-08", valor: "50.98", descricao: "DEBITO DE CARTAO", nome: null, conta: "C6 - Conta PJ HBR",
  cartao: false, parcela: null, total_da_compra: null, pendente: false, acao: "classificar", lancamento: null, conta_aberta: null,
  motivos: ["valor_exato", "sem_nome", "dias:0"], forte: true,
};

/** O CMP da AutoZone (débito de R$ 50,98 em 08/10) gravado na OS-00112 e esperando o banco. */
const CMP_NO_BANCO = {
  ...CMP_RESUMO, situacao: "aguardando_banco", fornecedor: "AutoZone", valor: "50.98", valor_lido: "50.98", data: "2026-10-08",
  destino: "os", os: OS_INFO, tipo_na_os: "despesa", categoria: "Peças e materiais", quem_pagou: "empresa", gravado_em: "2026-10-10T22:41:00Z",
  banco: { estado: "pergunta_aberta", nivel: "verde", desde: "2026-10-10", ate: "2026-11-09", linha: null, candidatos: 1 },
};

const OPCOES_VERDE = [{ n: 1, rotulo: "C6 - Conta PJ HBR · 08/10 · DEBITO DE CARTAO · R$ 50,98", valor: `tx:${TX_1}` }];
const OPCOES_AZUL = [
  { n: 1, rotulo: "C6 - Conta PJ HBR · 08/10 · DEBITO DE CARTAO · R$ 50,98", valor: `tx:${TX_1}` },
  { n: 2, rotulo: "C6 - Conta PJ HBR · 09/10 · DEBITO DE CARTAO · R$ 50,98", valor: `tx:${TX_2}` },
  { n: 0, rotulo: "Nenhuma destas", valor: "nenhum" },
];

/** PerguntaDoBancoF3 (3.7): verde = uma linha; azul = duas + "0 Nenhuma destas". */
function perguntaDoExtrato(nivel: "verde" | "azul", extra: Linha = {}): Qualquer {
  const id = String(extra.pergunta_id ?? P_EXTRATO);
  const linhas = nivel === "verde" ? [LINHA_DEBITO] : [LINHA_DEBITO, { ...LINHA_DEBITO, n: 2, id: TX_2, data: "2026-10-09", forte: false }];
  return {
    pergunta_id: id, dedupe_key: `cmp:p:${id}`, cmp: CMP_NO_BANCO, passo: "banco", opcoes: nivel === "verde" ? OPCOES_VERDE : OPCOES_AZUL,
    retomada: false, banco: { regra: "debito", nivel, linhas, mais: 0, hash: "h1" }, ...extra,
  };
}

/** O pergunta_rotear com a pergunta do extrato aberta (passo "banco"). */
function rotearBanco(opcoes: Qualquer[], extra: Linha = {}): Qualquer {
  return rotear("banco", {
    ativa: {
      id: P_ID, origem: "comprovante", tipo: "pergunta", referencia_id: CMP_ID, referencia_codigo: "CMP-00124", passo: "banco",
      opcoes, wa_message_id: "WA-P", aberta_em: "2026-10-10T22:30:00Z",
    },
    ...extra,
  });
}

function bancoDoExtrato(texto: string, opcoes: Qualquer[], responder: (a: Qualquer) => unknown, extra: Record<string, (a: Qualquer) => unknown> = {}, tabelas: Record<string, Linha[]> = {}) {
  return bancoFalso({
    tabelas: { whatsapp_messages: [TEXTO_MSG(texto)], ai_operator_messages: [], ...tabelas },
    rpc: { pergunta_rotear: () => rotearBanco(opcoes), comprovante_banco_responder: responder, pergunta_marcar_enviada: () => null, ...extra },
  });
}

const LIGADO = {
  ...CMP_NO_BANCO, situacao: "conciliado",
  banco: { estado: "ligado", nivel: "verde", desde: "2026-10-10", ate: null, candidatos: 1,
    linha: { data: "2026-10-08", valor: "50.98", descricao: "DEBITO DE CARTAO", conta: "C6 - Conta PJ HBR", como: "classificou" } },
};
const LIGACAO = {
  tipo: "ligar_linha", bank_transaction_id: TX_1, origem: "sim", nivel: "verde", em: "2026-10-11T12:00:00Z", como: "classificou",
  proposta_id: "q-1", anotacao_id: "a-1", anotacao_criada: true, payable_id: null, corrigido: {}, mensagens: [],
};

Deno.test("F3 gravado com linhas parecidas (azul): a pergunta do extrato sai na MESMA mensagem ('No extrato:'), com a chave dela", async () => {
  const gravado = { ...CMP_NO_BANCO, banco: { ...CMP_NO_BANCO.banco, estado: "perguntar", nivel: "azul" } };
  const banco = bancoDaConversa("confirmar", () => ({
    resultado: "gravado", cmp: gravado, proxima: null, motivo: null,
    gravacao: {
      situacao: "aguardando_banco", avisos: [], mensagens: [], mes: "2026-10-01", banco: { nivel: "azul", perguntar: true },
      efeitos: [{ tipo: "despesa_os" }, { tipo: "aguardar_banco", regra: "debito", nivel: "azul" }],
    },
  }), {
    comprovante_banco_proxima: () => ({ perguntou: true, ...perguntaDoExtrato("azul") }),
    comprovante_destino_do_arquivo: () => ({ data: null }),
    comprovantes_indice_do_mes: () => [],
    comprovante_indice_gravado: () => null,
  }, { comprovantes_indice_mensal: [], ai_operator_messages: [] });
  const d = depsF2(banco);
  const r = await responder(CORPO_RESPONDER("sim"), d.deps);
  await d.esperarFundo();
  assertEquals(r.corpo, { tratada: true, resultado: "gravado" });
  assertEquals(rpcs(banco, "comprovante_banco_proxima")[0].args, { p_phone: DONO.phone, p_motivo: "depois_de_gravar", p_cmp: CMP_ID });
  const [msg] = d.enviosAoDono();
  assertEquals(msg.dedupe_key, `cmp:p:${P_EXTRATO}`, "a chave é a da pergunta que a mensagem abre");
  assertStringIncludes(msg.message, "CMP-00124 gravado: lancei a despesa na OS-00112 como custo interno (não muda o total nem aparece para o cliente; entra no Lucro por OS); já há linhas parecidas no extrato: pergunto qual é.");
  assertStringIncludes(
    msg.message,
    "\n\nNo extrato: CMP-00124 · cupom NFC-e · AutoZone · 08/10 · R$ 50,98\nApareceram no extrato linhas que podem ser deste comprovante:\n" +
      "1 C6 - Conta PJ HBR · 08/10 · DEBITO DE CARTAO · R$ 50,98\n2 C6 - Conta PJ HBR · 09/10 · DEBITO DE CARTAO · R$ 50,98\n0 Nenhuma destas",
  );
  assertEquals(msg.message.includes("Fila vazia"), false);
  assertEquals(rpcs(banco, "pergunta_marcar_enviada")[0].args, { p_id: P_EXTRATO, p_wa_message_id: "WA-OUT-1" });
  // o par do histórico só com a gravação (sem a pergunta)
  assertEquals(String(banco.inseridos.ai_operator_messages?.[1].content).includes("Apareceram"), false);

  // verde ou cinza (perguntar = false): nada de R3, "Fila vazia" como na F2
  const b2 = bancoDaConversa("confirmar", () => ({
    resultado: "gravado", cmp: CMP_NO_BANCO, proxima: null, motivo: null,
    gravacao: { situacao: "aguardando_banco", efeitos: [{ tipo: "aguardar_banco", regra: "debito", nivel: "cinza" }], banco: { nivel: "cinza", perguntar: false } },
  }), { comprovante_destino_do_arquivo: () => ({ data: null }) });
  const d2 = depsF2(b2);
  await responder(CORPO_RESPONDER("sim"), d2.deps);
  assertEquals(rpcs(b2, "comprovante_banco_proxima").length, 0);
  assertStringIncludes(d2.enviosAoDono()[0].message, "quando o débito aparecer no extrato, pergunto se é este. Arquivo: Brisa/1- DOC's/Compras.\n\nFila vazia");
});

/** O aprovarNoExtrato falso: registra as chamadas e devolve o resultado dado. */
function aprovacaoFalsa(d: ReturnType<typeof depsF2>, resultado: { ok: boolean; nada?: boolean; motivo?: string | null } | Error) {
  const chamadas: Array<[string, string]> = [];
  d.deps.aprovarNoExtrato = (cmpId, donoId) => {
    chamadas.push([cmpId, donoId]);
    return resultado instanceof Error ? Promise.reject(resultado) : Promise.resolve(resultado);
  };
  return chamadas;
}

Deno.test("F3 responder: 'sim' ao verde → R4 com o autor = o dono → 'ligado' + a aprovação no Extrato (uma vez), a próxima da fila da F2 e o par do histórico", async () => {
  const banco = bancoDoExtrato("sim", OPCOES_VERDE, () => ({
    resultado: "ligado", cmp: LIGADO, ligacao: LIGACAO, proxima: null, motivo: null, ate: null, aprovar: { proposta_id: "q-1" },
  }), {
    comprovante_proxima_pergunta: () => ({ perguntou: true, ...perguntaDoBanco("para_que", { opcoes: OPCOES_PARA_QUE }, { codigo: "CMP-00125", numero: 125 }) }),
  });
  const d = depsF2(banco);
  const aprovacoes = aprovacaoFalsa(d, { ok: true });
  const r = await responder(CORPO_RESPONDER("sim"), d.deps);
  await d.esperarFundo();
  assertEquals(r.corpo, { tratada: true, resultado: "ligado" });
  assertEquals(rpcs(banco, "comprovante_banco_responder")[0].args, {
    p: { pergunta_id: P_ID, message_id: MSG_ID, interpretacao: { tipo: "sim" }, autor: DONO.id },
  });
  assertEquals(rpcs(banco, "comprovante_responder").length, 0, "a pergunta do extrato nunca vai à RPC da F2");
  // ajustes do dono: o sim já aprova a linha — uma vez, com o dono como quem decide
  assertEquals(aprovacoes, [[CMP_ID, DONO.id]]);
  const [msg] = d.enviosAoDono();
  assert(msg.message.startsWith(
    "CMP-00124 ligado à linha de 08/10 do C6 - Conta PJ HBR (R$ 50,98): lancei no Extrato como Peças e materiais, OS-00112.\n\nPróximo: CMP-00125",
  ));
  assertEquals(msg.dedupe_key, `cmp:p:${P_PROX}`);
  assertEquals(rpcs(banco, "comprovante_proxima_pergunta")[0].args, { p_phone: DONO.phone, p_motivo: "depois_de_gravar", p_cmp: null });
  assertEquals(rpcs(banco, "comprovante_banco_proxima").length, 0, "a fila da F2 vem primeiro");
  const par = banco.inseridos.ai_operator_messages;
  assertEquals(par?.[0].content, "🤖 Fluxo de comprovantes (respostas do dono pelo menu, não pelo assistente): CMP-00124 ligado ao extrato.");
  assertStringIncludes(String(par?.[1].content), `Referência: CMP-00124 (id ${CMP_ID}).`);

  // fila da F2 vazia: outra do extrato; nenhuma das duas: só a ligação, com a chave da resposta
  const outra = bancoDoExtrato("sim", OPCOES_VERDE, () => ({ resultado: "ligado", cmp: LIGADO, ligacao: LIGACAO, proxima: null }), {
    comprovante_proxima_pergunta: () => ({ perguntou: false, motivo: "fila_vazia" }),
    comprovante_banco_proxima: () => ({ perguntou: true, ...perguntaDoExtrato("verde", { pergunta_id: P_PROX }) }),
  });
  const d2 = depsF2(outra);
  await responder(CORPO_RESPONDER("sim"), d2.deps);
  assertEquals(rpcs(outra, "comprovante_banco_proxima")[0].args, { p_phone: DONO.phone, p_motivo: "depois_de_gravar", p_cmp: null });
  assertStringIncludes(d2.enviosAoDono()[0].message, "\n\nPróximo: CMP-00124 · cupom NFC-e · AutoZone");
  const nada = bancoDoExtrato("sim", OPCOES_VERDE, () => ({ resultado: "ligado", cmp: LIGADO, ligacao: LIGACAO, proxima: null }), {
    comprovante_proxima_pergunta: () => ({ perguntou: false }),
    comprovante_banco_proxima: () => ({ perguntou: false, motivo: "cinza" }),
  });
  const d3 = depsF2(nada);
  await responder(CORPO_RESPONDER("sim"), d3.deps);
  assertEquals(d3.enviosAoDono()[0].dedupe_key, `cmp:r:${MSG_ID}`);
  assertEquals(d3.enviosAoDono()[0].message.includes("Próximo"), false);
});

Deno.test("ajustes do dono: a aprovação que falha vira 'tento de novo'; sem `aprovar` não chama; ok/número no verde não aprovam", async () => {
  const semProxima = { comprovante_proxima_pergunta: () => ({ perguntou: false }), comprovante_banco_proxima: () => ({ perguntou: false }) };
  // falhou: o texto diz que classificou e que tenta de novo na próxima rodada do Extrato
  const falha = bancoDoExtrato("sim", OPCOES_VERDE, () => ({ resultado: "ligado", cmp: LIGADO, ligacao: LIGACAO, proxima: null, aprovar: { proposta_id: "q-1" } }), semProxima);
  const df = depsF2(falha);
  const chamadasDaFalha = aprovacaoFalsa(df, { ok: false, motivo: "Esta linha acabou de ser lançada por outro caminho — revise a fila" });
  await responder(CORPO_RESPONDER("sim"), df.deps);
  assertEquals(chamadasDaFalha.length, 1);
  assertEquals(
    df.enviosAoDono()[0].message,
    "CMP-00124 ligado à linha de 08/10 do C6 - Conta PJ HBR (R$ 50,98): classifiquei a linha como Peças e materiais, OS-00112, mas não consegui aprovar agora " +
      "(Esta linha acabou de ser lançada por outro caminho — revise a fila): tento de novo na próxima rodada do Extrato.",
  );
  // a dependência que lança também vira "tento de novo" (nunca derruba a resposta)
  const lanca = bancoDoExtrato("sim", OPCOES_VERDE, () => ({ resultado: "ligado", cmp: LIGADO, ligacao: LIGACAO, proxima: null, aprovar: { proposta_id: "q-1" } }), semProxima);
  const dl = depsF2(lanca);
  aprovacaoFalsa(dl, new Error("rede"));
  assertEquals((await responder(CORPO_RESPONDER("sim"), dl.deps)).corpo, { tratada: true, resultado: "ligado" });
  assertStringIncludes(dl.enviosAoDono()[0].message, "não consegui aprovar agora (o Extrato não respondeu): tento de novo na próxima rodada do Extrato.");

  // sem `aprovar` (a proposta ainda não está na fila): não chama; o "gerar" aprova quando ela entrar
  const sem = bancoDoExtrato("sim", OPCOES_VERDE, () => ({ resultado: "ligado", cmp: LIGADO, ligacao: LIGACAO, proxima: null, aprovar: null }), semProxima);
  const ds = depsF2(sem);
  const chamadasSem = aprovacaoFalsa(ds, { ok: true });
  await responder(CORPO_RESPONDER("sim"), ds.deps);
  assertEquals(chamadasSem.length, 0);
  assertStringIncludes(ds.enviosAoDono()[0].message, ": classifiquei como Peças e materiais, OS-00112 (lanço no Extrato na próxima rodada).");

  // "ok" e número no verde: a R4 não liga (ok_nao_aprova) e nada é aprovado
  for (const texto of ["ok", "1"]) {
    const ok = bancoDoExtrato(texto, OPCOES_VERDE, () => ({ resultado: "ok_nao_aprova", cmp: CMP_NO_BANCO, proxima: null }));
    const dok = depsF2(ok);
    const chamadasOk = aprovacaoFalsa(dok, { ok: true });
    await responder(CORPO_RESPONDER(texto), dok.deps);
    assertEquals(chamadasOk.length, 0, texto);
    assertEquals(dok.enviosAoDono()[0].message.includes("lancei"), false);
  }
});

Deno.test("ajustes do dono: o padrão do aprovarNoExtrato é o POST interno ao finance-review (approve_cmp, x-cron-secret, o dono)", async () => {
  const semProxima = { comprovante_proxima_pergunta: () => ({ perguntou: false }), comprovante_banco_proxima: () => ({ perguntou: false }) };
  const banco = bancoDoExtrato("sim", OPCOES_VERDE, () => ({ resultado: "ligado", cmp: LIGADO, ligacao: LIGACAO, proxima: null, aprovar: { proposta_id: "q-1" } }), semProxima);
  const d = depsF2(banco);
  d.deps.cronSecret = "segredo-do-cron";
  const fetchDoEnvio = d.deps.fetch;
  const pedidos: Array<{ headers: Record<string, string>; corpo: Qualquer }> = [];
  d.deps.fetch = ((url: string, init?: RequestInit) => {
    if (String(url).endsWith("/functions/v1/finance-review")) {
      pedidos.push({ headers: init?.headers as Record<string, string>, corpo: JSON.parse(String(init?.body)) });
      return Promise.resolve(new Response(JSON.stringify({ ok: true, proposta_id: "q-1", payable_id: "pay-1", registrado: true }), { status: 200 }));
    }
    return fetchDoEnvio(url, init);
  }) as typeof fetch;
  await responder(CORPO_RESPONDER("sim"), d.deps);
  assertEquals(pedidos.length, 1);
  assertEquals(pedidos[0].corpo, { action: "approve_cmp", cmp_id: CMP_ID, acting_user_id: DONO.id });
  assertEquals(pedidos[0].headers["x-cron-secret"], "segredo-do-cron");
  assertStringIncludes(d.enviosAoDono()[0].message, ": lancei no Extrato como Peças e materiais, OS-00112.");
  assertEquals(d.logs.some((l) => JSON.stringify(l).includes("segredo-do-cron")), false, "o segredo nunca vai ao log");
  // sem o segredo: não chama e o texto diz que tenta de novo
  const sem = bancoDoExtrato("sim", OPCOES_VERDE, () => ({ resultado: "ligado", cmp: LIGADO, ligacao: LIGACAO, proxima: null, aprovar: { proposta_id: "q-1" } }), semProxima);
  const ds = depsF2(sem);
  await responder(CORPO_RESPONDER("sim"), ds.deps);
  assertEquals(ds.envios.some((e) => e.url.includes("finance-review")), false);
  assertStringIncludes(ds.enviosAoDono()[0].message, "não consegui aprovar agora (o Extrato não respondeu): tento de novo na próxima rodada do Extrato.");
});

Deno.test("ajustes do dono: o sim do resumo que grava e liga (verde) aprova a linha antes do texto", async () => {
  const banco = bancoDaConversa("confirmar", () => ({
    resultado: "gravado", cmp: LIGADO, proxima: null, motivo: null,
    gravacao: {
      situacao: "conciliado", avisos: [], mensagens: [], mes: "2026-10-01", aprovar: { proposta_id: "q-1" },
      efeitos: [{ tipo: "despesa_os" }, { ...LIGACAO, origem: "gravacao" }],
    },
  }), { comprovante_destino_do_arquivo: () => ({ data: null }) });
  const d = depsF2(banco);
  const chamadas = aprovacaoFalsa(d, { ok: true });
  await responder(CORPO_RESPONDER("sim"), d.deps);
  await d.esperarFundo();
  assertEquals(chamadas, [[CMP_ID, DONO.id]]);
  assertStringIncludes(d.enviosAoDono()[0].message, "; liguei à linha do banco de 08/10 e lancei no Extrato como Peças e materiais, OS-00112.");
});

// ─── regra E (ajustes do dono): "quem pagou?" depois de 5 dias sem aparecer em conta da empresa ──

const OPCOES_QUEM = [
  { n: 1, rotulo: "A empresa (ainda vai aparecer no extrato: continuo esperando até 09/11)", valor: "empresa" },
  { n: 2, rotulo: "Eu, do meu bolso ou do meu cartão pessoal (fica como reembolso para você)", valor: "socio" },
  { n: 3, rotulo: "O Roberto (técnico: reembolso nas Diárias)", valor: "payee:p-rob" },
  { n: 4, rotulo: "Foi gasto pessoal, no meu cartão (só guardo o arquivo)", valor: "pessoal" },
];

function bancoDoQuem(texto: string, responder: (a: Qualquer) => unknown, extra: Record<string, (a: Qualquer) => unknown> = {}) {
  return bancoFalso({
    tabelas: { whatsapp_messages: [TEXTO_MSG(texto)], ai_operator_messages: [], comprovantes_indice_mensal: [] },
    rpc: {
      pergunta_rotear: () => rotear("banco_quem", {
        ativa: {
          id: P_ID, origem: "comprovante", tipo: "pergunta", referencia_id: CMP_ID, referencia_codigo: "CMP-00124", passo: "banco_quem",
          opcoes: OPCOES_QUEM, wa_message_id: "WA-P", aberta_em: "2026-10-10T22:30:00Z",
        },
      }),
      comprovante_banco_responder: responder, pergunta_marcar_enviada: () => null, ...extra,
    },
  });
}

Deno.test("regra E: o 'quem pagou?' vai à R4 só com o número da opção (palavra e nome do técnico viram o número)", async () => {
  for (const [texto, n] of [["3", 3], ["o Roberto", 3], ["do meu bolso", 2], ["a empresa", 1], ["gasto pessoal", 4]] as Array<[string, number]>) {
    const banco = bancoDoQuem(texto, () => ({ resultado: "esperando", cmp: CMP_NO_BANCO, proxima: null, ate: "2026-11-09" }));
    await responder(CORPO_RESPONDER(texto), depsF2(banco).deps);
    assertEquals(rpcs(banco, "comprovante_banco_responder")[0].args.p, { pergunta_id: P_ID, message_id: MSG_ID, interpretacao: { tipo: "opcao", n }, autor: DONO.id }, texto);
    assertEquals(rpcs(banco, "comprovante_responder").length, 0, "nunca vai à RPC da F2");
  }
  // pergunta ao assistente: não vai à R4
  const livre = bancoDoQuem("quanto deu o extrato do C6?", () => { throw new Error("não devia chamar"); });
  assertEquals((await responder(CORPO_RESPONDER("quanto deu o extrato do C6?"), depsF2(livre).deps)).corpo.tratada, false);
});

Deno.test("regra E: os três resultados — esperando, regravado (move o arquivo e o histórico) e não trocado", async () => {
  // a empresa: continua esperando
  const esperando = bancoDoQuem("1", () => ({ resultado: "esperando", cmp: CMP_NO_BANCO, proxima: null, ate: "2026-11-09" }));
  const de = depsF2(esperando);
  assertEquals((await responder(CORPO_RESPONDER("1"), de.deps)).corpo, { tratada: true, resultado: "esperando" });
  assertEquals(de.enviosAoDono()[0].message, "Ok: o CMP-00124 continua esperando o extrato (até 09/11).");

  // o técnico: desfez e gravou de novo (reembolso nas Diárias), com o aviso do almoço
  const regravadoCmp = { ...CMP_NO_BANCO, situacao: "gravado", quem_pagou: "tecnico", pagador_nome: "Roberto", categoria: "Alimentação de campo" };
  const regravado = bancoDoQuem("3", () => ({
    resultado: "regravado", cmp: regravadoCmp, proxima: null,
    gravacao: {
      situacao: "gravado", mes: "2026-10-01", avisos: ["almoco_ja_no_extra"], mensagens: [],
      efeitos: [{ tipo: "despesa_os", paid_by: "technician" }, { tipo: "reembolso_tecnico", favorecido_nome: "Roberto", valor: "50.98", extra_do_dia: { valor: "20.00", data: "2026-10-08" } }],
    },
  }), {
    comprovante_destino_do_arquivo: () => ({ data: null }),
    comprovantes_indice_do_mes: () => [],
    comprovante_indice_gravado: () => null,
  });
  const dr = depsF2(regravado);
  assertEquals((await responder(CORPO_RESPONDER("3"), dr.deps)).corpo, { tratada: true, resultado: "regravado" });
  await dr.esperarFundo();
  const texto = dr.enviosAoDono()[0].message.replace(/ /g, " ");
  assert(texto.startsWith("CMP-00124 corrigido: pago pelo Roberto. Feito: lancei a despesa na OS-00112 como custo interno"));
  assertStringIncludes(texto, "lancei R$ 50,98 nas Diárias do Roberto como reembolso de despesa paga pelo técnico.");
  assertStringIncludes(texto, "O Roberto já tinha recebido R$ 20,00 de almoço (extra da diária de 08/10): confira se o reembolso não ficou em dobro.");
  // o arquivo muda de nome/pasta pelo destino de agora; o assistente fica sabendo
  assertEquals(rpcs(regravado, "comprovante_destino_do_arquivo")[0].args, { p_id: CMP_ID });
  assertStringIncludes(String(regravado.inseridos.ai_operator_messages?.[0].content), "CMP-00124 corrigido (quem pagou)");

  // bloqueado: nada mudou, com o caminho para destravar
  const bloqueado = bancoDoQuem("2", () => ({
    resultado: "nao_trocado", cmp: CMP_NO_BANCO, proxima: null, bloqueios: [{ efeito: "anotar", motivo: "anotacao_aplicada" }],
  }));
  const db = depsF2(bloqueado);
  assertEquals((await responder(CORPO_RESPONDER("2"), db.deps)).corpo, { tratada: true, resultado: "nao_trocado" });
  assertEquals(db.enviosAoDono()[0].message, "Não troquei quem pagou o CMP-00124: a linha do banco já recebeu a classificação; corrija pelo Extrato. Nada mudou.");
  // erro cru da rota: texto fixo + só o código no app_error_logs
  const cru = bancoDoQuem("2", () => ({ resultado: "nao_trocado", cmp: CMP_NO_BANCO, proxima: null, motivo: 'violates check constraint "AutoZone"', codigo_erro: "23514" }));
  const dc = depsF2(cru);
  await responder(CORPO_RESPONDER("2"), dc.deps);
  assertEquals(dc.enviosAoDono()[0].message, "Não troquei quem pagou o CMP-00124: deu um erro no sistema (código 23514). Nada mudou.");
  const erros = JSON.stringify(rpcs(cru, "log_app_error").map((c) => c.args));
  assertStringIncludes(erros, "nao_trocado:23514");
  assertEquals(erros.includes("AutoZone"), false);

  // número fora do menu: a R4 devolve inválida; o texto pede o número de quem pagou
  const fora = bancoDoQuem("9", () => ({ resultado: "invalida", cmp: CMP_NO_BANCO, proxima: null, motivo: "opcao_fora" }));
  const dfo = depsF2(fora);
  await responder(CORPO_RESPONDER("9"), dfo.deps);
  assertEquals(rpcs(fora, "comprovante_banco_responder")[0].args.p.interpretacao, { tipo: "ok" });
  assertEquals(dfo.enviosAoDono()[0].message, "Para o CMP-00124, responda o número de quem pagou (1 a 4).");
});

Deno.test("regra E: o vigia abre o 'quem pagou?' (R3 com passo banco_quem) com a retomada; o cmp N com a pergunta pendente", async () => {
  const pergunta = {
    perguntou: true, pergunta_id: P_EXTRATO, dedupe_key: `cmp:p:${P_EXTRATO}`, cmp: { ...CMP_NO_BANCO, data: "2026-10-03" }, passo: "banco_quem",
    opcoes: OPCOES_QUEM, retomada: true, banco: { nivel: "cinza", linhas: [], hash: "h" },
  };
  const banco = bancoFalso({ rpc: { comprovante_banco_proxima: () => pergunta, pergunta_marcar_enviada: () => null } });
  const d = depsF2(banco);
  assertEquals(await perguntarBanco(DONO.phone, "vigia", d.deps), true);
  const [msg] = d.enviosAoDono();
  assertEquals(msg.dedupe_key, `cmp:p:${P_EXTRATO}`);
  assertEquals(
    msg.message,
    "Ainda falta saber quem pagou o CMP-00124.\nCMP-00124 · cupom NFC-e · AutoZone · 03/10 · R$ 50,98\n" +
      "Esta compra de 03/10 ainda não apareceu em nenhuma conta da empresa. Quem pagou?\n" +
      OPCOES_QUEM.map((o) => `${o.n} ${o.rotulo}`).join("\n"),
  );

  const cartao = bancoDoComando(() => ({ resultado: "cartao", cmp: { ...CMP_NO_BANCO, banco: { estado: "banco_quem" } }, efeitos: [{ tipo: "aguardar_banco", regra: "debito", nivel: "cinza" }] }), {
    comprovante_banco_proxima: () => ({ ...pergunta, retomada: false }),
  });
  const dc = depsF2(cartao);
  await responder(CORPO_RESPONDER("cmp 124"), dc.deps);
  assertStringIncludes(dc.enviosAoDono()[0].message, "No extrato: falta saber quem pagou (não apareceu em conta da empresa: *cmp 124* para responder).");
  assertEquals(rpcs(cartao, "comprovante_banco_proxima")[0].args, { p_phone: DONO.phone, p_motivo: "cmp", p_cmp: CMP_ID });
  assertStringIncludes(dc.enviosAoDono()[1].message, "Quem pagou?\n1 A empresa");
});

Deno.test("F3 responder: número no verde vira 'ok' (nunca liga); azul: '2' escolhe, '0' e 'nenhuma destas' recusam", async () => {
  const verde = bancoDoExtrato("1", OPCOES_VERDE, () => ({ resultado: "ok_nao_aprova", cmp: CMP_NO_BANCO, proxima: null }));
  const dv = depsF2(verde);
  await responder(CORPO_RESPONDER("1"), dv.deps);
  assertEquals(rpcs(verde, "comprovante_banco_responder")[0].args.p.interpretacao, { tipo: "ok" });
  assertEquals(dv.enviosAoDono()[0].message, "Responda *sim* se essa linha é do CMP-00124, ou *não*.");

  const dois = bancoDoExtrato("2", OPCOES_AZUL, () => ({ resultado: "ligado", cmp: LIGADO, ligacao: { ...LIGACAO, origem: "escolha", nivel: "azul" }, proxima: null }), {
    comprovante_proxima_pergunta: () => ({ perguntou: false }), comprovante_banco_proxima: () => ({ perguntou: false }),
  });
  await responder(CORPO_RESPONDER("2"), depsF2(dois).deps);
  assertEquals(rpcs(dois, "comprovante_banco_responder")[0].args.p.interpretacao, { tipo: "opcao", n: 2 });

  for (const texto of ["0", "Nenhuma destas.", "não"]) {
    const zero = bancoDoExtrato(texto, OPCOES_AZUL, () => ({ resultado: "recusado", cmp: CMP_NO_BANCO, proxima: null, ate: "2026-11-09" }));
    const dz = depsF2(zero);
    const r = await responder(CORPO_RESPONDER(texto), dz.deps);
    assertEquals(r.corpo, { tratada: true, resultado: "recusado" });
    assertEquals(rpcs(zero, "comprovante_banco_responder")[0].args.p.interpretacao, { tipo: "nao" }, texto);
    assertEquals(dz.enviosAoDono()[0].message, "Ok, nenhuma destas. O CMP-00124 continua esperando a linha certa no extrato (até 09/11).");
  }
  const naoVerde = bancoDoExtrato("não", OPCOES_VERDE, () => ({ resultado: "recusado", cmp: CMP_NO_BANCO, proxima: null, ate: "2026-11-09" }));
  const dn = depsF2(naoVerde);
  await responder(CORPO_RESPONDER("não"), dn.deps);
  assertEquals(dn.enviosAoDono()[0].message, "Ok, não é essa. O CMP-00124 continua esperando a linha certa no extrato (até 09/11).");

  // azul com "sim": o banco devolve inválida e o texto pede o número
  const sim = bancoDoExtrato("sim", OPCOES_AZUL, () => ({ resultado: "invalida", cmp: CMP_NO_BANCO, proxima: null, motivo: "pede_o_numero" }));
  const ds = depsF2(sim);
  await responder(CORPO_RESPONDER("sim"), ds.deps);
  assertEquals(ds.enviosAoDono()[0].message, "Responda o número da linha (1 a 2) ou 0 se não for nenhuma.");
});

Deno.test("F3 responder: as linhas mudaram → a pergunta nova (com a chave dela) ou 'continua esperando'; ignorada não manda nada", async () => {
  const mudou = bancoDoExtrato("sim", OPCOES_VERDE, () => ({
    resultado: "mudou", cmp: CMP_NO_BANCO, proxima: perguntaDoExtrato("azul", { pergunta_id: P_PROX }), ate: "2026-11-09",
  }));
  const dm = depsF2(mudou);
  assertEquals((await responder(CORPO_RESPONDER("sim"), dm.deps)).corpo.resultado, "mudou");
  const [m] = dm.enviosAoDono();
  assert(m.message.startsWith("As linhas do extrato mudaram desde a pergunta.\n\nCMP-00124 · cupom NFC-e · AutoZone"));
  assertEquals(m.dedupe_key, `cmp:p:${P_PROX}`);
  assertEquals(rpcs(mudou, "pergunta_marcar_enviada")[0].args.p_id, P_PROX);

  const semLinha = bancoDoExtrato("sim", OPCOES_VERDE, () => ({ resultado: "mudou", cmp: CMP_NO_BANCO, proxima: null, ate: "2026-11-09" }));
  const ds = depsF2(semLinha);
  await responder(CORPO_RESPONDER("sim"), ds.deps);
  assertEquals(
    ds.enviosAoDono()[0].message,
    "As linhas do extrato mudaram desde a pergunta. Não há mais linha que sirva: o CMP-00124 continua esperando o extrato (até 09/11).",
  );

  const ignorada = bancoDoExtrato("sim", OPCOES_VERDE, () => ({ resultado: "ignorada", cmp: { ...CMP_NO_BANCO, situacao: "cancelado" }, proxima: null }));
  const di = depsF2(ignorada);
  assertEquals((await responder(CORPO_RESPONDER("sim"), di.deps)).corpo, { tratada: true, resultado: "ignorada" });
  assertEquals(di.enviosAoDono().length, 0);
});

Deno.test("F3 responder: resposta anterior à pergunta reapresenta; não ligado com erro cru vira texto fixo e só o código no app_error_logs", async () => {
  const anterior = bancoDoExtrato("sim", OPCOES_VERDE, () => ({ resultado: "invalida", cmp: CMP_NO_BANCO, proxima: null, motivo: "resposta_anterior_a_pergunta" }));
  const da = depsF2(anterior);
  await responder(CORPO_RESPONDER("sim"), da.deps);
  assert(da.enviosAoDono()[0].message.startsWith("Essa resposta chegou antes desta pergunta; responda de novo a ela:\nCMP-00124 · cupom NFC-e"));
  assertStringIncludes(da.enviosAoDono()[0].message, "Apareceu no extrato: C6 - Conta PJ HBR · 08/10 · DEBITO DE CARTAO · R$ 50,98.");
  assertEquals(rpcs(anterior, "pergunta_marcar_enviada")[0].args.p_id, P_ID, "o reenvio fica registrado na pergunta");

  const cru = bancoDoExtrato("sim", OPCOES_VERDE, () => ({
    resultado: "nao_ligado", cmp: CMP_NO_BANCO, proxima: null, motivo: 'new row for relation "payables" violates check constraint "AutoZone 50.98"', codigo_erro: "23514",
  }));
  const dc = depsF2(cru);
  await responder(CORPO_RESPONDER("sim"), dc.deps);
  assertEquals(dc.enviosAoDono()[0].message, "Não liguei o CMP-00124: deu um erro no sistema (código 23514). Nada mudou. Responda de novo para tentar outra vez.");
  const erros = JSON.stringify(rpcs(cru, "log_app_error").map((c) => c.args));
  assertStringIncludes(erros, "nao_ligado:23514");
  assertEquals(erros.includes("AutoZone"), false);

  const conhecido = bancoDoExtrato("sim", OPCOES_VERDE, () => ({ resultado: "nao_ligado", cmp: CMP_NO_BANCO, proxima: null, motivo: "O mês 09/2026 está fechado" }));
  const dk = depsF2(conhecido);
  await responder(CORPO_RESPONDER("sim"), dk.deps);
  assertStringIncludes(dk.enviosAoDono()[0].message, "Não liguei o CMP-00124: o mês (09/2026) está fechado no financeiro");
  assertEquals(rpcs(conhecido, "log_app_error").length, 0);
});

Deno.test("F3 responder (formas da O3): aviso no 'ligado', pergunta fechada → a de agora, 'nao_ligado' por código", async () => {
  // o motivo do ligado é o aviso da ligação
  const aviso = bancoDoExtrato("sim", OPCOES_VERDE, () => ({
    resultado: "ligado", cmp: LIGADO, ligacao: LIGACAO, proxima: null, motivo: "linha_lancada_em_outro", ate: null,
  }), { comprovante_proxima_pergunta: () => ({ perguntou: false }), comprovante_banco_proxima: () => ({ perguntou: false }) });
  const da = depsF2(aviso);
  await responder(CORPO_RESPONDER("sim"), da.deps);
  assertStringIncludes(da.enviosAoDono()[0].message, ").\nA linha do banco já foi lançada em outro registro: confira no Extrato.");

  // a pergunta tinha fechado (venceu): o banco abre a de agora (outro id) e ela sai com a chave dela
  const fechada = bancoDoExtrato("sim", OPCOES_VERDE, () => ({
    resultado: "invalida", cmp: CMP_NO_BANCO, proxima: perguntaDoExtrato("verde", { pergunta_id: P_PROX }), motivo: "pergunta_fechada", ate: "2026-11-09",
  }));
  const df = depsF2(fechada);
  await responder(CORPO_RESPONDER("sim"), df.deps);
  assert(df.enviosAoDono()[0].message.startsWith("Essa pergunta já tinha fechado; esta é a de agora:\nCMP-00124 · cupom NFC-e"));
  assertEquals(df.enviosAoDono()[0].dedupe_key, `cmp:p:${P_PROX}`);

  // número fora da lista (azul): a MESMA pergunta de volta, com o pedido do número (reenvio registrado)
  const fora = bancoDoExtrato("ok", OPCOES_AZUL, () => ({
    resultado: "invalida", cmp: CMP_NO_BANCO, proxima: perguntaDoExtrato("azul", { pergunta_id: P_ID }), motivo: "pede_numero", ate: "2026-11-09",
  }));
  const dfo = depsF2(fora);
  await responder(CORPO_RESPONDER("ok"), dfo.deps);
  assert(dfo.enviosAoDono()[0].message.startsWith("Responda o número da linha (1 a 2) ou 0 se não for nenhuma.\nCMP-00124 · "));
  assertEquals(dfo.enviosAoDono()[0].dedupe_key, `cmp:r:${MSG_ID}`);
  assertEquals(rpcs(fora, "pergunta_marcar_enviada")[0].args.p_id, P_ID);

  // nao_ligado com o código da ligação: texto fixo, sem app_error_logs
  const outro = bancoDoExtrato("sim", OPCOES_VERDE, () => ({ resultado: "nao_ligado", cmp: CMP_NO_BANCO, proxima: null, motivo: "linha_de_outro_cmp" }));
  const dout = depsF2(outro);
  await responder(CORPO_RESPONDER("sim"), dout.deps);
  assertEquals(
    dout.enviosAoDono()[0].message,
    "Não liguei o CMP-00124: essa linha do extrato já está ligada a outro comprovante. Nada mudou. Responda de novo para tentar outra vez.",
  );
  assertEquals(rpcs(outro, "log_app_error").length, 0);

  // recusado: o motivo do banco decide o texto ("nao_e_essa" no verde)
  const verde = bancoDoExtrato("não", OPCOES_VERDE, () => ({ resultado: "recusado", cmp: CMP_NO_BANCO, proxima: null, motivo: "nao_e_essa", ate: "2026-11-09" }));
  const dv = depsF2(verde);
  await responder(CORPO_RESPONDER("não"), dv.deps);
  assert(dv.enviosAoDono()[0].message.startsWith("Ok, não é essa."));
});

Deno.test("F3 responder: R4 que falha → 'mande de novo' com a chave do webhook (cmp:f) e o erro sobe; texto livre vai ao assistente", async () => {
  const quebrada = bancoDoExtrato("sim", OPCOES_VERDE, () => ({ error: { code: "XX000", message: "x" } }));
  const dq = depsF2(quebrada);
  let lancou = false;
  try {
    await responder(CORPO_RESPONDER("sim"), dq.deps);
  } catch {
    lancou = true;
  }
  assert(lancou);
  assertEquals(dq.enviosAoDono()[0].dedupe_key, `cmp:f:${MSG_ID}`);

  for (const texto of ["quanto deu o extrato do C6?", "manda o orçamento do Brisa pro cliente"]) {
    const livre = bancoDoExtrato(texto, OPCOES_VERDE, () => { throw new Error("não devia chamar"); });
    const r = await responder(CORPO_RESPONDER(texto), depsF2(livre).deps);
    assertEquals(r.corpo.tratada, false, texto);
    assertEquals(rpcs(livre, "comprovante_banco_responder").length, 0);
  }
});

Deno.test("F3 responder: mensagem curta não entendida com a pergunta do extrato aberta → R3 'reabrir' (não a fila da F2)", async () => {
  const banco = bancoDoExtrato("hmm", OPCOES_VERDE, () => null, {
    comprovante_banco_proxima: () => ({ perguntou: true, ...perguntaDoExtrato("verde", { pergunta_id: P_PROX }) }),
  });
  const d = depsF2(banco);
  assertEquals((await responder(CORPO_RESPONDER("hmm"), d.deps)).corpo.resultado, "nao_entendi");
  assertEquals(rpcs(banco, "comprovante_banco_proxima")[0].args, { p_phone: DONO.phone, p_motivo: "reabrir", p_cmp: CMP_ID });
  assertEquals(rpcs(banco, "comprovante_proxima_pergunta").length, 0);
  assert(d.enviosAoDono()[0].message.startsWith("Não entendi para o CMP-00124."));
  assertStringIncludes(d.enviosAoDono()[0].message, "\n\nCMP-00124 · cupom NFC-e · AutoZone");
});

Deno.test("F3 cmp N: CMP gravado com a pergunta do extrato pendente → o cartão e, em seguida, a pergunta (R3 'cmp')", async () => {
  const pendente = { ...CMP_NO_BANCO, banco: { ...CMP_NO_BANCO.banco, estado: "perguntar" } };
  const banco = bancoDoComando(() => ({
    resultado: "cartao", cmp: pendente, efeitos: [{ tipo: "despesa_os" }, { tipo: "aguardar_banco", regra: "debito", nivel: "cinza" }],
  }), { comprovante_banco_proxima: () => ({ perguntou: true, ...perguntaDoExtrato("verde") }) });
  const d = depsF2(banco);
  await responder(CORPO_RESPONDER("cmp 124"), d.deps);
  const [cartao, pergunta] = d.enviosAoDono();
  assertEquals(
    cartao.message,
    "CMP-00124 (esperando o banco): R$ 50,98 em 08/10 · AutoZone · OS-00112 Brisa · despesa da OS (custo interno: não aparece para o cliente) · Peças e materiais. " +
      "Feito: lancei a despesa na OS-00112 como custo interno (não muda o total nem aparece para o cliente; entra no Lucro por OS); quando o débito aparecer no extrato, pergunto se é este. " +
      "No extrato: pergunta pendente (*cmp 124* para responder). Para cancelar: *cancelar cmp 124 motivo*.",
  );
  assertEquals(rpcs(banco, "comprovante_banco_proxima")[0].args, { p_phone: DONO.phone, p_motivo: "cmp", p_cmp: CMP_ID });
  assertEquals(pergunta.dedupe_key, `cmp:p:${P_EXTRATO}`);
  assertStringIncludes(pergunta.message, "Responda *sim* para ligar ou *não* se não for essa.");

  // sem pergunta pendente (ligado): só o cartão
  const ligado = bancoDoComando(() => ({ resultado: "cartao", cmp: LIGADO, efeitos: [{ ...LIGACAO }] }));
  const dl = depsF2(ligado);
  await responder(CORPO_RESPONDER("cmp 124"), dl.deps);
  assertEquals(dl.enviosAoDono().length, 1);
  assertStringIncludes(dl.enviosAoDono()[0].message, "Feito: liguei à linha do banco de 08/10 e a classifiquei como Peças e materiais, OS-00112 (lanço no Extrato na próxima rodada). No extrato: ligado à linha de 08/10 do C6 - Conta PJ HBR (R$ 50,98).");
  // a linha que o sim aprovou (R12 gravou `aprovado` no efeito): o cartão diz que lançou
  const aprovada = bancoDoComando(() => ({ resultado: "cartao", cmp: LIGADO, efeitos: [{ ...LIGACAO, aprovado: { payable_id: "pay-1", proposta_id: "q-1" } }] }));
  const dap = depsF2(aprovada);
  await responder(CORPO_RESPONDER("cmp 124"), dap.deps);
  assertStringIncludes(dap.enviosAoDono()[0].message, "Feito: liguei à linha do banco de 08/10 e lancei no Extrato como Peças e materiais, OS-00112.");
  assertEquals(rpcs(ligado, "comprovante_banco_proxima").length, 0);
});

Deno.test("F3 vigia: a fila da F2 primeiro, depois a pergunta do extrato (R6 + R3 'vigia', com a retomada) e o índice da pasta PESSOAL", async () => {
  const banco = bancoFalso({
    tabelas: { comprovantes_indice_pessoal: [] },
    rpc: {
      comprovantes_vigia_lote: () => ({ expurgados: 0 }),
      comprovantes_vigia_conversa: () => ({ perguntar: [DONO.phone], indices_pessoais: ["2026-10-01"] }),
      comprovante_proxima_pergunta: () => ({ perguntou: true, ...perguntaDoBanco("valor", { retomada: true }) }),
      comprovantes_indice_pessoal_do_mes: () => [{ codigo: "CMP-00130", numero: 130, data: "2026-10-01", valor: "44.95", destino: "pessoal", situacao: "gravado" }],
      comprovante_indice_pessoal_gravado: () => null,
      comprovantes_vigia_banco: () => ({ perguntar: [DONO.phone] }),
      comprovante_banco_proxima: () => ({ perguntou: true, ...perguntaDoExtrato("verde", { retomada: true }) }),
      pergunta_marcar_enviada: () => null,
    },
  });
  const d = depsF2(banco);
  const n = await vigiar(d.deps);
  // a forma da contagem não muda (a porta do cron responde ela): as do extrato somam em perguntas,
  // o índice PESSOAL em indices; o log traz os números à parte
  assertEquals([n.perguntas, n.indices], [2, 1]);
  assertEquals(d.logs.find((l) => l.evento === "vigia")?.campos, {
    ...n, indices_pessoais: 1, perguntas_banco: 1, ms: 0,
  });
  const ordem = banco.chamadasRpc.map((c) => c.nome);
  assert(ordem.indexOf("comprovante_proxima_pergunta") < ordem.indexOf("comprovantes_vigia_banco"), "a fila da F2 primeiro");
  assertEquals(rpcs(banco, "comprovantes_vigia_banco")[0].args, { p_limite: 5 });
  assertEquals(rpcs(banco, "comprovante_banco_proxima")[0].args, { p_phone: DONO.phone, p_motivo: "vigia", p_cmp: null });
  const doExtrato = d.enviosAoDono().find((m) => m.dedupe_key === `cmp:p:${P_EXTRATO}`);
  assert(doExtrato, "a pergunta do extrato saiu");
  assert(doExtrato.message.startsWith("Ainda falta ligar o CMP-00124 ao extrato.\nCMP-00124 · cupom NFC-e · AutoZone · 08/10 · R$ 50,98\n"));
  assertStringIncludes(doExtrato.message, "É deste comprovante? Se for, ligo e lanço a linha no Extrato como Peças e materiais, OS-00112 Brisa (aprovada no seu sim).");
  // o índice PESSOAL: na pasta PESSOAL do mês, com nome próprio, e o registro pela R8
  const caminho = "/MANAGEMENT/FINANCIALS/COMPROVANTES/PESSOAL/2026-10/_INDICE PESSOAL 2026-10.csv";
  assertEquals(d.dbx!.r.substituidos[0].caminho, caminho);
  assertEquals(d.dbx!.r.substituidos[0].rev, null, "primeira vez: add");
  assertEquals(rpcs(banco, "comprovante_indice_pessoal_gravado")[0].args, {
    p_mes: "2026-10-01", p_dropbox_id: "id:indice", p_caminho: caminho, p_rev: "03c", p_linhas: 1,
  });
  assertEquals(rpcs(banco, "comprovante_indice_gravado").length, 0, "o índice da contadora não é regravado por isso");
});

Deno.test("F3 vigia: modo de teste do whatsapp-send não pergunta; R6 quebrada só registra; envio não confirmado devolve a pergunta", async () => {
  const teste = bancoFalso({
    tabelas: { app_settings: [{ key: "wa_test_mode", value: "true" }, { key: "wa_test_number", value: "5511999990000" }] },
    rpc: {
      comprovantes_vigia_lote: () => ({ expurgados: 0 }),
      comprovantes_vigia_conversa: () => ({}),
      comprovantes_vigia_banco: () => ({ perguntar: [DONO.phone] }),
      comprovante_banco_proxima: () => ({ perguntou: true, ...perguntaDoExtrato("verde") }),
    },
  });
  const dt = depsF2(teste);
  assertEquals((await vigiar(dt.deps)).perguntas, 0);
  assertEquals(rpcs(teste, "comprovante_banco_proxima").length, 0);
  assertEquals(dt.enviosAoDono().length, 0);

  const quebrada = bancoFalso({
    rpc: { comprovantes_vigia_lote: () => ({ expurgados: 0 }), comprovantes_vigia_conversa: () => ({}), comprovantes_vigia_banco: () => ({ error: { code: "42883", message: "x" } }) },
  });
  const dq = depsF2(quebrada);
  assertEquals((await vigiar(dq.deps)).perguntas, 0);
  assertEquals(dq.logs.some((l) => l.evento === "vigia_banco_falhou" && l.campos?.codigo === "comprovantes_vigia_banco:42883"), true);

  const semEnvio = bancoFalso({
    rpc: {
      comprovante_banco_proxima: () => ({ perguntou: true, ...perguntaDoExtrato("verde") }),
      comprovante_pergunta_nao_enviada: () => null,
      pergunta_marcar_enviada: () => null,
    },
  });
  const ds = depsF2(semEnvio, { envio: 500 });
  assertEquals(await perguntarBanco(DONO.phone, "vigia", ds.deps), false);
  assertEquals(rpcs(semEnvio, "comprovante_pergunta_nao_enviada")[0].args, { p_pergunta_id: P_EXTRATO });
  assertEquals(rpcs(semEnvio, "pergunta_marcar_enviada").length, 0);

  // cinza, ocupado, desligada: o banco não abre e nada é enviado
  const cinza = bancoFalso({ rpc: { comprovante_banco_proxima: () => ({ perguntou: false, motivo: "cinza" }) } });
  const dc = depsF2(cinza);
  assertEquals(await perguntarBanco(DONO.phone, "cmp", dc.deps, CMP_ID), false);
  assertEquals(dc.enviosAoDono().length, 0);
});

Deno.test("F3 atualizarIndicePessoal: conflito de rev grava num arquivo novo; Dropbox fora → backoff pela R9", async () => {
  const registrado = "/MANAGEMENT/FINANCIALS/COMPROVANTES/PESSOAL/2026-10/_INDICE PESSOAL 2026-10.csv";
  // a forma da R7 (O5): o registro do índice vem junto das linhas
  const banco = bancoFalso({
    rpc: {
      comprovantes_indice_pessoal_do_mes: () => ({ mes: "2026-10", dropbox_id: "id:velho", caminho: registrado, rev: "07a", linhas: [] }),
      comprovante_indice_pessoal_gravado: () => null,
    },
  });
  const d = depsF2(banco, { dropbox: dropboxFalso({ conflito: true }) });
  assertEquals(await atualizarIndicePessoal("2026-10", d.deps), true);
  assertEquals(d.dbx!.r.substituidos[0].rev, "07a");
  assertEquals(rpcs(banco, "comprovante_indice_pessoal_gravado")[0].args.p_caminho, registrado.replace(".csv", " (1).csv"));

  const fora = bancoFalso({ rpc: { comprovantes_indice_pessoal_do_mes: () => [], comprovante_indice_pessoal_falhou: () => ({ desistiu: false }) }, tabelas: { comprovantes_indice_pessoal: [] } });
  const df = depsF2(fora, { dropbox: null });
  assertEquals(await atualizarIndicePessoal("2026-10-01", df.deps), false);
  assertEquals(rpcs(fora, "comprovante_indice_pessoal_falhou")[0].args, { p_mes: "2026-10-01", p_erro: "dropbox_sem_conexao" });
  assertEquals(df.logs.some((l) => l.evento === "indice_pessoal_falhou"), true);
});

Deno.test("F3: nenhum console.* com valor, CNPJ, descrição da linha do banco, loja ou texto do dono", async () => {
  const saida: string[] = [];
  const originais = { log: console.log, error: console.error, warn: console.warn, info: console.info };
  for (const k of Object.keys(originais) as Array<keyof typeof originais>) {
    console[k] = (...a: unknown[]) => { saida.push(a.map((x) => typeof x === "string" ? x : JSON.stringify(x)).join(" ")); };
  }
  try {
    const ligado = bancoDoExtrato("sim", OPCOES_VERDE, () => ({ resultado: "ligado", cmp: LIGADO, ligacao: LIGACAO, proxima: null }), {
      comprovante_proxima_pergunta: () => ({ perguntou: false }),
      comprovante_banco_proxima: () => ({ perguntou: true, ...perguntaDoExtrato("azul", { pergunta_id: P_PROX }) }),
    });
    const d1 = depsF2(ligado);
    d1.deps.log = logDoFluxo;
    await responder(CORPO_RESPONDER("sim"), d1.deps);
    await d1.esperarFundo();
    const naoLigado = bancoDoExtrato("sim", OPCOES_VERDE, () => ({
      resultado: "nao_ligado", cmp: CMP_NO_BANCO, proxima: null, motivo: "linha DEBITO DE CARTAO de AutoZone 50.98 recusada",
    }));
    const d2 = depsF2(naoLigado);
    d2.deps.log = logDoFluxo;
    await responder(CORPO_RESPONDER("sim"), d2.deps);
    const vigia = bancoFalso({
      rpc: {
        comprovantes_vigia_lote: () => ({ expurgados: 0 }), comprovantes_vigia_conversa: () => ({}),
        comprovantes_vigia_banco: () => ({ perguntar: [DONO.phone] }),
        comprovante_banco_proxima: () => ({ perguntou: true, ...perguntaDoExtrato("verde", { retomada: true }) }),
        pergunta_marcar_enviada: () => null,
      },
    });
    const d3 = depsF2(vigia);
    d3.deps.log = logDoFluxo;
    await vigiar(d3.deps);
  } finally {
    Object.assign(console, originais);
  }
  const tudo = saida.join("\n");
  assert(saida.length > 0);
  for (const proibido of ["AutoZone", "50.98", "50,98", "DEBITO DE CARTAO", "C6 - Conta", CNPJ, "Peças e materiais", "Brisa", "recusada"]) {
    assertEquals(tudo.includes(proibido), false, `vazou no log: ${proibido}`);
  }
});

// =============================================================================================
// O assistente opera o CMP (11/10/2026 — spec-assistente-opera-cmp.md): a ação `completar` (A) e a
// categoria como dica no "para quê" (B). O banco falso devolve as formas de comprovante_comando e
// comprovante_responder; whatsapp-send é dublê.
// =============================================================================================

const P_CAT = "44444444-0000-4000-8000-000000000011";
const P_VALOR = "44444444-0000-4000-8000-000000000012";
const P_QUEM = "44444444-0000-4000-8000-000000000013";
const P_RESUMO = "44444444-0000-4000-8000-000000000014";
const semNbsp = (s: unknown) => String(s).replace(/ /g, " ");

/** O menu do "para quê" do caso real: 5 OS, Estoque, Insumo, Empresa e Pessoal. */
const OPCOES_9 = [
  { n: 1, rotulo: "OS-00112 · Brisa", valor: "os:os-1" }, { n: 2, rotulo: "OS-00118 · Dona V", valor: "os:os-2" },
  { n: 3, rotulo: "OS-00120 · Madu", valor: "os:os-3" }, { n: 4, rotulo: "OS-00121 · Bora", valor: "os:os-4" },
  { n: 5, rotulo: "OS-00122 · Lua", valor: "os:os-5" }, { n: 6, rotulo: "Estoque", valor: "estoque" },
  { n: 7, rotulo: "Insumo", valor: "insumo" }, { n: 8, rotulo: "Empresa (sem OS)", valor: "empresa" }, { n: 9, rotulo: "Pessoal", valor: "pessoal" },
];

/** A linha do CMP-00001 como estava em produção (11/10, depois da pergunta expirar): na fila, valor lido 204,87. */
const CMP_00001 = {
  id: CMP_ID, codigo: "CMP-00001", numero: 1, phone_normalized: DONO.phone, situacao: "aguardando_vez", modo: "dono", gravado_em: null,
  valor: 204.87, valor_confirmado: 204.87, data_confirmada: "2026-10-11", destino: null, destino_os_id: null, categoria: null,
  forma_confirmada: null, quem_pagou: null, tipo_na_os: null,
};
const RESUMO_00001 = { ...CMP_RESUMO, codigo: "CMP-00001", numero: 1, valor: "204.87", valor_lido: "204.87", data: "2026-10-11", forma: null };
const LIGADA_NO_BANCO = [{ key: "comprovante_fluxo", value: "dono" }, { key: "comprovante_conversa", value: "on" }];

const CORPO_COMPLETAR = (extra: Linha = {}) => ({ phone: DONO.phone, autor: DONO.id, cmp: 1, ...extra });

function bancoDoCompletar(
  rpc: Record<string, (a: Qualquer) => unknown>,
  op: { cmp?: Linha | null; settings?: Linha[] } = {},
) {
  return bancoFalso({
    tabelas: {
      app_settings: op.settings ?? LIGADA_NO_BANCO,
      comprovantes: op.cmp === null ? [] : [{ ...CMP_00001, ...(op.cmp ?? {}) }],
    },
    rpc: { pergunta_marcar_enviada: () => null, comprovante_pergunta_nao_enviada: () => null, ...rpc },
  });
}

/** O comprovante_comando do banco: cada campo do corrigir (ou o "cmp") devolve o que o `_comprovante_proxima` abriria. */
function comandoQueCorrige(respostas: Record<string, Qualquer>) {
  return (a: Qualquer) => {
    const r = respostas[a.p.campo ?? a.p.comando];
    if (!r) throw new Error(`campo inesperado: ${a.p.campo ?? a.p.comando}`);
    return r;
  };
}

const RPCS_QUE_GRAVAM = ["comprovante_responder", "_comprovante_gravar", "comprovante_cancelar", "lancar_no_caixa", "so_expense_add"];

Deno.test("completar — o caso real do CMP-00001: categoria + valor do cartão + o porquê → duas correções, UMA mensagem com o 'Para quê?', nada gravado", async () => {
  const cmpComCategoria = { ...RESUMO_00001, categoria: "Combustível e deslocamento" };
  const banco = bancoDoCompletar({
    comprovante_comando: comandoQueCorrige({
      categoria: {
        resultado: "pergunta", codigo: "CMP-00001", corrigido: { campo: "categoria", valor: "Combustível e deslocamento" },
        pergunta: perguntaDoBanco("para_que", { pergunta_id: P_CAT, opcoes: OPCOES_9 }, cmpComCategoria),
      },
      valor: {
        resultado: "pergunta", codigo: "CMP-00001", corrigido: { campo: "valor", valor: "235.97" },
        pergunta: perguntaDoBanco("para_que", { pergunta_id: P_VALOR, opcoes: OPCOES_9 }, { ...cmpComCategoria, valor: "235.97" }),
      },
    }),
  });
  const d = depsF2(banco);
  const r = await completar(CORPO_COMPLETAR({
    categoria: "combustível", valor: "235.97", observacao: "cupom sem o gasto complementar de R$ 31,10; vale o valor do cartão",
  }), d.deps);

  assertEquals(r.status, 200);
  assertEquals(r.corpo.ok, true);
  assertEquals(r.corpo.enviada, true);
  assertEquals(r.corpo.passo, "para_que");
  assertEquals(r.corpo.aplicados, ["categoria", "valor"]);
  assertEquals(r.corpo.ignorados, []);
  assertEquals(r.corpo.cmp?.valor, "235.97");
  assertEquals(r.corpo.cmp?.categoria, "Combustível e deslocamento");
  // duas correções pelo comando, com o número do CMP e sem mensagem do dono; nenhuma resposta
  assertEquals(rpcs(banco, "comprovante_comando").map((c) => c.args.p), [
    { phone: DONO.phone, message_id: null, comando: "corrigir", cmp: 1, campo: "categoria", categoria: "Combustível e deslocamento" },
    { phone: DONO.phone, message_id: null, comando: "corrigir", cmp: 1, campo: "valor", valor: "235.97" },
  ]);
  // nada é gravado antes do SIM: nenhuma rota de gravação, nenhuma linha nova
  for (const nome of RPCS_QUE_GRAVAM) assertEquals(rpcs(banco, nome).length, 0, nome);
  assertEquals(Object.keys(banco.inseridos), []);
  // UMA mensagem: a linha "anotei" e o "Para quê?" com o menu inteiro, com a chave da última pergunta
  const enviados = d.enviosAoDono();
  assertEquals(enviados.length, 1);
  assertEquals(enviados[0].dedupe_key, `cmp:p:${P_VALOR}`);
  const msg = semNbsp(enviados[0].message);
  assert(
    msg.startsWith(
      "CMP-00001: anotei o que você disse na conversa: categoria Combustível e deslocamento, valor R$ 235,97 (no comprovante: R$ 204,87). " +
        "Motivo: cupom sem o gasto complementar de R$ 31,10; vale o valor do cartão.\n\nCMP-00001",
    ),
    msg,
  );
  assertStringIncludes(msg, "· R$ 235,97\nPara quê?\n1 OS-00112 · Brisa");
  assertStringIncludes(msg, "8 Empresa (sem OS)\n9 Pessoal\nResponda o número, o nome do barco ou *os N*.");
  // só a última foi enviada (a primeira fechou sem envio, no banco)
  assertEquals(rpcs(banco, "pergunta_marcar_enviada").map((c) => c.args), [{ p_id: P_VALOR, p_wa_message_id: "WA-OUT-1" }]);
  // o log não leva valor, categoria nem o porquê
  const log = JSON.stringify(d.logs);
  for (const proibido of ["235", "204", "Combust", "cupom", "cartão"]) assertEquals(log.includes(proibido), false, proibido);
  assertEquals(d.logs.find((l) => l.evento === "completar")?.campos, {
    id: CMP_ID, aplicados: 2, ignorados: 0, passo: "para_que", enviada: true, recusado: null,
  });
});

Deno.test("completar — a ordem fixa (categoria, os, para, valor, data, forma) e o campo igual ao do CMP não vai", async () => {
  const pergunta = (id: string) => ({ resultado: "pergunta", codigo: "CMP-00001", corrigido: null, pergunta: perguntaDoBanco("tipo_na_os", { pergunta_id: id }) });
  const banco = bancoDoCompletar({
    comprovante_comando: comandoQueCorrige({
      categoria: pergunta("p-1"), os: pergunta("p-2"), valor: pergunta("p-3"), data: pergunta("p-4"), forma: pergunta("p-5"),
    }),
  });
  await completar(CORPO_COMPLETAR({
    forma: "debito", data: "2026-10-09", valor: "70.00", observacao: "o do cartão", os: 112, categoria: "almoço",
  }), depsF2(banco).deps);
  assertEquals(rpcs(banco, "comprovante_comando").map((c) => c.args.p.campo), ["categoria", "os", "valor", "data", "forma"]);
  assertEquals(rpcs(banco, "comprovante_comando")[1].args.p.numero, 112);
  assertEquals(rpcs(banco, "comprovante_comando")[0].args.p.categoria, "Alimentação de campo");

  // igual ao que já está: nem versão nem pergunta à toa (só o "para" muda)
  const igual = bancoDoCompletar({
    comprovante_comando: comandoQueCorrige({
      para: { resultado: "pergunta", codigo: "CMP-00001", corrigido: { campo: "para", valor: "estoque" }, pergunta: perguntaDoBanco("categoria") },
    }),
  }, { cmp: { categoria: "Combustível e deslocamento", valor_confirmado: 62, valor: 62, data_confirmada: "2026-10-10", forma_confirmada: "pix" } });
  const r = await completar(CORPO_COMPLETAR({ categoria: "Combustível", destino: "estoque", valor: "62.00", data: "2026-10-10", forma: "pix" }), depsF2(igual).deps);
  assertEquals(rpcs(igual, "comprovante_comando").map((c) => c.args.p), [
    { phone: DONO.phone, message_id: null, comando: "corrigir", cmp: 1, campo: "para", destino: "estoque" },
  ]);
  assertEquals(r.corpo.aplicados, ["para"]);
  assertEquals(r.corpo.ignorados, []);
});

Deno.test("completar — OS inválida para tudo depois dela (e a linha 'Não usei'); categoria não achada para antes de tudo", async () => {
  const banco = bancoDoCompletar({
    comprovante_comando: comandoQueCorrige({
      categoria: {
        resultado: "pergunta", codigo: "CMP-00001", corrigido: { campo: "categoria", valor: "Alimentação de campo" },
        pergunta: perguntaDoBanco("para_que", { pergunta_id: P_CAT, opcoes: OPCOES_9 }, RESUMO_00001),
      },
      os: { resultado: "invalida", codigo: "CMP-00001", motivo: "os_nao_existe" },
    }),
  });
  const d = depsF2(banco);
  const r = await completar(CORPO_COMPLETAR({ categoria: "almoço", os: 999, valor: "210.00", observacao: "taxa" }), d.deps);
  assertEquals(rpcs(banco, "comprovante_comando").map((c) => c.args.p.campo), ["categoria", "os"]);
  assertEquals(r.corpo.recusado, { campo: "os", motivo: "os_nao_existe", texto: "OS-00999 (não achei essa OS)" });
  assertEquals(r.corpo.aplicados, ["categoria"]);
  assertEquals(r.corpo.ignorados, ["valor"]);
  const [msg] = d.enviosAoDono();
  assertStringIncludes(msg.message, "anotei o que você disse na conversa: categoria Alimentação de campo. Motivo: taxa. Não usei: OS-00999 (não achei essa OS).");
  assertEquals(msg.dedupe_key, `cmp:p:${P_CAT}`);

  const nada = bancoDoCompletar({
    comprovante_comando: comandoQueCorrige({ categoria: { resultado: "invalida", codigo: "CMP-00001", motivo: "categoria_nao_achada" } }),
  });
  const dn = depsF2(nada);
  const rn = await completar(CORPO_COMPLETAR({ categoria: "material de limpeza", destino: "empresa" }), dn.deps);
  assertEquals(rpcs(nada, "comprovante_comando").length, 1);
  assertEquals(rn.corpo, {
    ok: true, codigo: "CMP-00001", aplicados: [], ignorados: ["para"], anotado: [],
    recusado: { campo: "categoria", motivo: "categoria_nao_achada", texto: 'categoria "material de limpeza" (não achei essa categoria)' },
    passo: null, enviada: false, ocupado: false, ocupado_por: null, valor_lido: "204.87", cmp: null,
  });
  assertEquals(dn.enviosAoDono().length, 0);
});

Deno.test("completar — dinheiro + sócio: o comando da forma e a resposta ao 'quem pagou?' sem mensagem do dono; o resumo vai com a linha 'anotei'", async () => {
  const banco = bancoDoCompletar({
    comprovante_comando: comandoQueCorrige({
      forma: { resultado: "pergunta", codigo: "CMP-00001", corrigido: { campo: "forma", valor: "dinheiro" }, pergunta: perguntaDoBanco("quem_pagou", { pergunta_id: P_QUEM }) },
    }),
    comprovante_responder: () => ({
      resultado: "resumo", cmp: { ...RESUMO_00001, quem_pagou: "socio" }, motivo: null,
      proxima: perguntaDoBanco("confirmar", { pergunta_id: P_RESUMO, plano: { efeitos: [] } }, {
        ...RESUMO_00001, destino: "empresa", forma: "dinheiro", quem_pagou: "socio", categoria: "Outras despesas",
      }),
    }),
  }, { cmp: { destino: "empresa" } });
  const d = depsF2(banco);
  const r = await completar(CORPO_COMPLETAR({ forma: "dinheiro", quem_pagou: "socio" }), d.deps);
  assertEquals(rpcs(banco, "comprovante_responder").map((c) => c.args.p), [
    { pergunta_id: P_QUEM, message_id: null, interpretacao: { tipo: "palavra", valor: "socio" }, versao: null },
  ]);
  assertEquals(r.corpo.aplicados, ["forma", "quem_pagou"]);
  assertEquals(r.corpo.passo, "confirmar");
  const [msg] = d.enviosAoDono();
  assertEquals(msg.dedupe_key, `cmp:p:${P_RESUMO}`);
  assert(
    msg.message.startsWith("CMP-00001: anotei o que você disse na conversa: em dinheiro, pago por você (reembolso).\n\nCMP-00001 · confira antes de gravar:"),
    msg.message,
  );
  assertStringIncludes(msg.message, "Responda *sim* para gravar ou *não* para corrigir.");
  // o resumo nunca é respondido pelo completar (o sim é do dono)
  assertEquals(rpcs(banco, "comprovante_responder").some((c) => c.args.p.interpretacao.tipo === "sim"), false);
});

Deno.test("completar — o passo que veio antes (como pagou) deixa o 'peça ou despesa' para depois; nunca responde confirmar nem mesma_compra", async () => {
  const banco = bancoDoCompletar({
    comprovante_comando: comandoQueCorrige({
      os: { resultado: "pergunta", codigo: "CMP-00001", corrigido: { campo: "os", valor: "OS-00112" }, pergunta: perguntaDoBanco("como_pagou", { pergunta_id: P_QUEM }) },
    }),
    comprovante_responder: () => {
      throw new Error("não devia responder");
    },
  });
  const d = depsF2(banco);
  const r = await completar(CORPO_COMPLETAR({ os: "112", tipo_na_os: "despesa", quem_pagou: "empresa" }), d.deps);
  assertEquals(r.corpo.aplicados, ["os"]);
  assertEquals(r.corpo.ignorados, ["quem_pagou", "tipo_na_os"]);
  assertEquals(r.corpo.passo, "como_pagou");
  assertStringIncludes(d.enviosAoDono()[0].message, "anotei o que você disse na conversa: para a OS-00112.\n\n");
  assertStringIncludes(d.enviosAoDono()[0].message, "Como foi pago?");

  for (const passo of ["mesma_compra", "confirmar"]) {
    const b = bancoDoCompletar({
      comprovante_comando: comandoQueCorrige({
        forma: { resultado: "pergunta", codigo: "CMP-00001", corrigido: null, pergunta: perguntaDoBanco(passo, { plano: { efeitos: [] } }) },
      }),
      comprovante_responder: () => {
        throw new Error("não devia responder");
      },
    });
    await completar(CORPO_COMPLETAR({ forma: "pix", quem_pagou: "socio", tipo_na_os: "peca" }), depsF2(b).deps);
    assertEquals(rpcs(b, "comprovante_responder").length, 0, passo);
  }
});

Deno.test("completar — recusas ANTES de qualquer escrita (o porquê do valor, dono, telefone, modo de teste, gravado, cancelado, inexistente, data futura)", async () => {
  const casos: Array<[string, Linha, { cmp?: Linha | null; settings?: Linha[] }, string]> = [
    ["valor diferente do lido sem o porquê", { valor: "235.97" }, {}, "observacao_obrigatoria"],
    ["autor que não é o dono", { autor: "0d0d0d0d-0000-4000-8000-000000000099" }, {}, "nao_e_o_dono"],
    ["telefone que não é o do dono", { phone: "5547988887777" }, {}, "nao_e_o_dono"],
    ["conversa desligada", { categoria: "x" }, { settings: [{ key: "comprovante_fluxo", value: "dono" }] }, "desligada"],
    ["modo de teste", { categoria: "x" }, {
      settings: [...LIGADA_NO_BANCO, { key: "wa_test_mode", value: "true" }, { key: "wa_test_number", value: "5511999990000" }],
    }, "modo_de_teste"],
    ["já gravado", { categoria: "x" }, { cmp: { gravado_em: "2026-10-11T22:00:00Z", situacao: "gravado" } }, "ja_gravado"],
    ["cancelado", { categoria: "x" }, { cmp: { situacao: "cancelado" } }, "ja_cancelado"],
    ["não existe", { categoria: "x" }, { cmp: null }, "nao_existe"],
    // revisão de 11/10/2026: com legenda-chave o número nasce em 'na_fila' (ainda lendo)
    ["ainda sendo lido", { categoria: "x" }, { cmp: { situacao: "na_fila" } }, "fora_da_conversa"],
    ["recebido", { categoria: "x" }, { cmp: { situacao: "recebido" } }, "fora_da_conversa"],
    ["abandonado", { categoria: "x" }, { cmp: { situacao: "abandonado" } }, "fora_da_conversa"],
    ["de outro fluxo (sombra)", { categoria: "x" }, { cmp: { modo: "sombra" } }, "nao_existe"],
    ["data futura", { data: "2026-10-12" }, {}, "data_futura"],
  ];
  for (const [caso, extra, op, motivo] of casos) {
    const banco = bancoDoCompletar({
      comprovante_comando: () => {
        throw new Error("não devia corrigir");
      },
    }, op);
    const d = depsF2(banco);
    d.deps.agora = () => new Date("2026-10-11T21:46:00Z");
    const r = await completar(CORPO_COMPLETAR(extra), d.deps);
    assertEquals(r.status, 200, caso);
    assertEquals(r.corpo.ok, false, caso);
    assertEquals(r.corpo.motivo, motivo, caso);
    assertEquals(rpcs(banco, "comprovante_comando").length + rpcs(banco, "comprovante_responder").length, 0, caso);
    assertEquals(d.enviosAoDono().length, 0, caso);
  }
  // o valor lido vai junto da recusa (o assistente diz qual é)
  const b = bancoDoCompletar({});
  assertEquals((await completar(CORPO_COMPLETAR({ valor: "235.97" }), depsF2(b).deps)).corpo.valor_lido, "204.87");
  // o mesmo valor do confirmado (já corrigido antes) não pede o porquê de novo
  const jaCorrigido = bancoDoCompletar({
    comprovante_comando: comandoQueCorrige({
      cmp: { resultado: "pergunta", pergunta: perguntaDoBanco("para_que", { pergunta_id: P_CAT, opcoes: OPCOES_9 }, RESUMO_00001) },
    }),
  }, { cmp: { valor_confirmado: 235.97 } });
  const rj = await completar(CORPO_COMPLETAR({ valor: "235.97" }), depsF2(jaCorrigido).deps);
  assertEquals(rj.corpo.ok, true);
  assertEquals(rpcs(jaCorrigido, "comprovante_comando")[0].args.p, { phone: DONO.phone, message_id: null, comando: "cmp", numero: 1 });
  // entrada fora do formato: 422 sem tocar o banco
  const ruins: Linha[] = [
    { cmp: 0 }, { cmp: "abc" }, { valor: "235,97" }, { data: "2026-02-31" }, { destino: "outro" }, { os: 112, destino: "estoque" },
    { categoria: "x".repeat(81) }, { autor: "x" },
  ];
  for (const ruim of ruins) {
    const bx = bancoDoCompletar({});
    const r = await completar(CORPO_COMPLETAR(ruim), depsF2(bx).deps);
    assertEquals(r.status, 422, JSON.stringify(ruim));
    assertEquals(r.corpo.motivo, "entrada_invalida");
    assertEquals(bx.chamadasRpc.length, 0);
  }
});

Deno.test("completar — ocupado: anota e não manda nada; envio não confirmado devolve a pergunta (o CMP volta à fila)", async () => {
  const ocupado = bancoDoCompletar({
    comprovante_comando: comandoQueCorrige({
      categoria: { resultado: "pergunta", codigo: "CMP-00001", corrigido: { campo: "categoria", valor: "Combustível e deslocamento" }, pergunta: null, motivo: "ocupado" },
    }),
  });
  const d = depsF2(ocupado);
  const r = await completar(CORPO_COMPLETAR({ categoria: "combustível" }), d.deps);
  assertEquals(r.corpo.ok, true);
  assertEquals(r.corpo.enviada, false);
  assertEquals(r.corpo.ocupado, true);
  assertEquals(r.corpo.aplicados, ["categoria"]);
  assertEquals(d.enviosAoDono().length, 0);

  const falhou = bancoDoCompletar({
    comprovante_comando: comandoQueCorrige({
      categoria: {
        resultado: "pergunta", codigo: "CMP-00001", corrigido: { campo: "categoria", valor: "Combustível e deslocamento" },
        pergunta: perguntaDoBanco("para_que", { pergunta_id: P_CAT, opcoes: OPCOES_9 }),
      },
    }),
  });
  const df = depsF2(falhou, { envio: 502 });
  const rf = await completar(CORPO_COMPLETAR({ categoria: "combustível" }), df.deps);
  assertEquals(rf.corpo.enviada, false);
  assertEquals(rf.corpo.ocupado, false);
  assertEquals(rpcs(falhou, "comprovante_pergunta_nao_enviada")[0].args, { p_pergunta_id: P_CAT });
  assertEquals(rpcs(falhou, "pergunta_marcar_enviada").length, 0);
});

Deno.test("completar — nada a mudar (tudo igual): a pergunta do CMP como o *cmp N* abre, enviada", async () => {
  const banco = bancoDoCompletar({
    comprovante_comando: comandoQueCorrige({
      cmp: { resultado: "pergunta", pergunta: perguntaDoBanco("para_que", { pergunta_id: P_CAT, opcoes: OPCOES_9 }, RESUMO_00001) },
    }),
  }, { cmp: { categoria: "Combustível e deslocamento" } });
  const d = depsF2(banco);
  const r = await completar(CORPO_COMPLETAR({ categoria: "gasolina" }), d.deps);
  assertEquals(rpcs(banco, "comprovante_comando").map((c) => c.args.p), [{ phone: DONO.phone, message_id: null, comando: "cmp", numero: 1 }]);
  assertEquals(r.corpo.enviada, true);
  assertEquals(r.corpo.aplicados, []);
  assert(d.enviosAoDono()[0].message.startsWith("CMP-00001: o que você disse na conversa já estava anotado.\n\nCMP-00001"));

  // revisão de 11/10/2026: nada anotado, mas o que o dono disse ficou para o passo dele ("é despesa da
  // OS" no "para quê?") — a linha não pode dizer "já estava anotado" (o fluxo vai perguntar)
  const ignorado = bancoDoCompletar({
    comprovante_comando: comandoQueCorrige({
      cmp: { resultado: "pergunta", pergunta: perguntaDoBanco("para_que", { pergunta_id: P_CAT, opcoes: OPCOES_9 }, RESUMO_00001) },
    }),
    comprovante_responder: () => {
      throw new Error("não devia responder");
    },
  });
  const di = depsF2(ignorado);
  const ri = await completar(CORPO_COMPLETAR({ destino: "os", tipo_na_os: "despesa" }), di.deps);
  assertEquals(ri.corpo.aplicados, []);
  assertEquals(ri.corpo.ignorados, ["tipo_na_os", "destino"]);
  const msgi = di.enviosAoDono()[0].message;
  assert(msgi.startsWith("CMP-00001: o que você disse na conversa eu pergunto na sequência, um passo por vez.\n\nCMP-00001"), msgi);
  assertEquals(msgi.includes("já estava anotado"), false);
});

Deno.test("completar — a pergunta que o banco abriu é de OUTRO CMP: o laço não responde o passo dele com o que o dono disse deste", async () => {
  const OUTRO = "22222222-0000-4000-8000-000000000099";
  const banco = bancoDoCompletar({
    comprovante_comando: comandoQueCorrige({
      categoria: {
        resultado: "pergunta", codigo: "CMP-00001", corrigido: { campo: "categoria", valor: "Combustível e deslocamento" },
        pergunta: perguntaDoBanco("quem_pagou", { pergunta_id: P_QUEM }, { id: OUTRO, codigo: "CMP-00002", numero: 2 }),
      },
    }),
    comprovante_responder: () => {
      throw new Error("não devia responder o passo de outro CMP");
    },
  });
  const d = depsF2(banco);
  const r = await completar(CORPO_COMPLETAR({ categoria: "combustível", quem_pagou: "socio" }), d.deps);
  assertEquals(rpcs(banco, "comprovante_responder").length, 0);
  assertEquals(r.corpo.aplicados, ["categoria"]);
  assertEquals(r.corpo.ignorados, ["quem_pagou"]);
});

// ─── B: a categoria como dica no "para quê" ───────────────────────────────────────────────

Deno.test("B: 'combustível' na pergunta do 'para quê' → o comando corrige a categoria do CMP (sem responder) e repergunta o destino com o mesmo menu", async () => {
  const banco = bancoDaConversa("para_que", () => {
    throw new Error("não devia responder");
  }, {
    comprovante_comando: () => ({
      resultado: "pergunta", codigo: "CMP-00124", corrigido: { campo: "categoria", valor: "Combustível e deslocamento" },
      pergunta: perguntaDoBanco("para_que", { pergunta_id: P_CAT, opcoes: OPCOES_PARA_QUE }, { categoria: "Combustível e deslocamento" }),
    }),
  });
  const d = depsF2(banco);
  const r = await responder(CORPO_RESPONDER("Combustível"), d.deps);
  assertEquals(r.corpo, { tratada: true, resultado: "pergunta" });
  assertEquals(rpcs(banco, "comprovante_comando")[0].args.p, {
    phone: DONO.phone, message_id: MSG_ID, comando: "corrigir", campo: "categoria", categoria: "Combustível e deslocamento", cmp: 124,
  });
  assertEquals(rpcs(banco, "comprovante_responder").length, 0);
  assertEquals(d.enviosAoDono().length, 1);
  const [msg] = d.enviosAoDono();
  assertEquals(msg.dedupe_key, `cmp:p:${P_CAT}`);
  assert(msg.message.startsWith("Categoria anotada: Combustível e deslocamento. Foi para qual OS ou para a empresa?\n\nCMP-00124"), msg.message);
  assertStringIncludes(msg.message, "Para quê?\n1 OS-00112 · Brisa\n2 Estoque");
});

Deno.test("B: 'combustível da empresa' → responde 'empresa' (sem a categoria no payload) e grava a categoria pelo comando; UMA mensagem, a 1ª pergunta nunca sai", async () => {
  const banco = bancoDaConversa("para_que", () => ({
    resultado: "proximo", cmp: { ...CMP_RESUMO, destino: "empresa" }, motivo: null,
    proxima: perguntaDoBanco("categoria", { pergunta_id: P_PROX }, { destino: "empresa" }),
  }), {
    comprovante_comando: () => ({
      resultado: "pergunta", codigo: "CMP-00124", corrigido: { campo: "categoria", valor: "Combustível e deslocamento" },
      pergunta: perguntaDoBanco("como_pagou", { pergunta_id: P_CAT }, { destino: "empresa", categoria: "Combustível e deslocamento" }),
    }),
  });
  const d = depsF2(banco);
  await responder(CORPO_RESPONDER("combustível da empresa"), d.deps);
  assertEquals(rpcs(banco, "comprovante_responder")[0].args.p, {
    pergunta_id: P_ID, message_id: MSG_ID, interpretacao: { tipo: "palavra", valor: "empresa" }, versao: null,
  });
  assertEquals(rpcs(banco, "comprovante_comando")[0].args.p, {
    phone: DONO.phone, message_id: MSG_ID, comando: "corrigir", campo: "categoria", categoria: "Combustível e deslocamento", cmp: 124,
  });
  assertEquals(d.enviosAoDono().length, 1);
  assertEquals(d.enviosAoDono()[0].dedupe_key, `cmp:p:${P_CAT}`);
  assert(d.enviosAoDono()[0].message.startsWith("Categoria anotada: Combustível e deslocamento.\n\nCMP-00124"));
  assertEquals(rpcs(banco, "pergunta_marcar_enviada").map((c) => c.args.p_id), [P_CAT], "a pergunta que a resposta abriu nunca é enviada");
});

Deno.test("B: categoria recusada pelo banco (desativada) → 'Não entendi' + a pergunta de novo; 'corrigir cmp 1 valor 235,97' sem pergunta aberta vai ao fluxo", async () => {
  const banco = bancoDaConversa("para_que", () => {
    throw new Error("não devia responder");
  }, {
    comprovante_comando: () => ({ resultado: "invalida", codigo: "CMP-00124", motivo: "categoria_nao_achada" }),
    comprovante_proxima_pergunta: () => ({ perguntou: true, ...perguntaDoBanco("para_que", { pergunta_id: P_ID, opcoes: OPCOES_PARA_QUE }) }),
  });
  const d = depsF2(banco);
  assertEquals((await responder(CORPO_RESPONDER("pedágio"), d.deps)).corpo, { tratada: true, resultado: "nao_entendi" });
  assert(d.enviosAoDono()[0].message.startsWith("Não entendi para o CMP-00124."));
  assertStringIncludes(d.enviosAoDono()[0].message, "Para quê?");

  // B.5: sem pergunta aberta nem CMP em contexto, o corrigir com o número dito não vai ao assistente
  const semPergunta = bancoFalso({
    tabelas: { whatsapp_messages: [TEXTO_MSG("x")] },
    rpc: {
      pergunta_rotear: () => rotear(null),
      comprovante_comando: () => ({
        resultado: "pergunta", codigo: "CMP-00001", corrigido: { campo: "valor", valor: "235.97" },
        pergunta: perguntaDoBanco("para_que", { pergunta_id: P_VALOR, opcoes: OPCOES_9 }, { ...RESUMO_00001, valor: "235.97" }),
      }),
      pergunta_marcar_enviada: () => null,
    },
  });
  const ds = depsF2(semPergunta);
  const r = await responder(CORPO_RESPONDER("corrigir cmp 1 valor 235,97"), ds.deps);
  assertEquals(r.corpo.tratada, true);
  assertEquals(rpcs(semPergunta, "comprovante_comando")[0].args.p, {
    phone: DONO.phone, message_id: MSG_ID, comando: "corrigir", campo: "valor", valor: "235.97", cmp: 1,
  });
  assert(semNbsp(ds.enviosAoDono()[0].message).startsWith("CMP-00001: valor corrigido para R$ 235,97.\n\nCMP-00001"));
});
