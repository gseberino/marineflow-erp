// A orquestração da edge comprovantes-whatsapp contra um banco falso que devolve exatamente as
// formas das RPCs da spec (seção 4.3). Sem rede: Evolution, Storage, Dropbox, whatsapp-send e
// ai-agent são dublês que registram o que receberam.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type DependenciasDoFluxo,
  entregar,
  logDoFluxo,
  processarArquivo,
  receber,
  repescar,
  subirNoDropbox,
  talvezAvisar,
  vigiar,
} from "./fluxo.ts";
import { type DadosDoArquivo, type ItemDoAviso, PASTA_A_CLASSIFICAR } from "./nucleo.ts";
import type { ResultadoDoDownload } from "./midia.ts";

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
      });
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
  assertEquals(n, { baixados: 1, entregues: 1, reenfileirados: 1, dropbox: 1, apagados: 1, avisos: 1, expurgados: 2, sem_desfecho: 1, encaminhados: 1 });
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
