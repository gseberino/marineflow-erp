// O portão do whatsapp-webhook: o que cada mensagem custa e para onde vai.
// A regra mais importante: texto e áudio de quem não é admin NÃO leem nada novo; do admin (F2), só o
// estado do registro de perguntas (1 RPC); com "off" a mídia lê só a chave.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  avisarFalhaPorHttp,
  chamarComprovantesPorHttp,
  chamarReceberPorHttp,
  type CorpoDoReceber,
  type DependenciasDoRoteador,
  type DependenciasDoTexto,
  PRAZO_DO_RECEBER_MS,
  rotearMidiaDoDono,
  rotearTextoDoDono,
} from "./webhook.ts";
import type { EstadoDoTelefone } from "../whatsapp/pergunta-ativa.ts";
import { TEXTO_FALHA } from "./conversa.ts";
import type { Modo } from "./modo.ts";

const DONO = { id: "dono-1", phone: "5547999990000" };

function deps(opcoes: {
  modo?: Modo | Error;
  dono?: typeof DONO | null | Error;
  receber?: boolean | Error | Promise<boolean>;
  despachoLanca?: boolean;
} = {}) {
  const contagem = { lerModo: 0, dono: 0, receber: 0, despacho: 0 };
  const corpos: CorpoDoReceber[] = [];
  const d: DependenciasDoRoteador = {
    lerModo: () => {
      contagem.lerModo++;
      return opcoes.modo instanceof Error ? Promise.reject(opcoes.modo) : Promise.resolve(opcoes.modo ?? "off");
    },
    dono: () => {
      contagem.dono++;
      return opcoes.dono instanceof Error ? Promise.reject(opcoes.dono) : Promise.resolve(opcoes.dono === undefined ? DONO : opcoes.dono);
    },
    chamarReceber: (corpo) => {
      contagem.receber++;
      corpos.push(corpo);
      if (opcoes.receber instanceof Error) return Promise.reject(opcoes.receber);
      if (opcoes.receber instanceof Promise) return opcoes.receber;
      return Promise.resolve(opcoes.receber ?? true);
    },
    despacharAoAgente: () => {
      contagem.despacho++;
      return opcoes.despachoLanca ? Promise.reject(new Error("caiu")) : Promise.resolve();
    },
  };
  return { d, contagem, corpos };
}

const MIDIA = { msgId: "msg-1", appUserId: DONO.id, appUserRole: "admin", mediaKind: "image" as const, caption: null as string | null };

Deno.test("texto e áudio: zero leitura de app_settings e de dono; despacho de hoje", async () => {
  for (const mediaKind of [null, undefined]) {
    const { d, contagem } = deps({ modo: "dono" });
    assertEquals(await rotearMidiaDoDono({ ...MIDIA, mediaKind }, d), "agente");
    assertEquals(contagem, { lerModo: 0, dono: 0, receber: 0, despacho: 1 });
  }
});

Deno.test("mensagem sem id (insert falhou): zero leitura, despacho de hoje", async () => {
  const { d, contagem } = deps({ modo: "dono" });
  assertEquals(await rotearMidiaDoDono({ ...MIDIA, msgId: null }, d), "agente");
  assertEquals(contagem, { lerModo: 0, dono: 0, receber: 0, despacho: 1 });
});

Deno.test("mídia de funcionário que não é admin: zero leitura, despacho de hoje", async () => {
  for (const appUserRole of ["technician", "financial", null]) {
    const { d, contagem } = deps({ modo: "dono" });
    assertEquals(await rotearMidiaDoDono({ ...MIDIA, appUserRole }, d), "agente");
    assertEquals(contagem, { lerModo: 0, dono: 0, receber: 0, despacho: 1 });
  }
});

Deno.test("mídia com off: só a leitura da chave, e o despacho de hoje", async () => {
  const { d, contagem } = deps({ modo: "off" });
  assertEquals(await rotearMidiaDoDono({ ...MIDIA, caption: "cupom" }, d), "agente");
  assertEquals(contagem, { lerModo: 1, dono: 0, receber: 0, despacho: 1 });
});

Deno.test("sombra: ambos — o despacho de hoje e o receber", async () => {
  const { d, contagem, corpos } = deps({ modo: "sombra" });
  assertEquals(await rotearMidiaDoDono(MIDIA, d), "ambos");
  assertEquals(contagem, { lerModo: 1, dono: 1, receber: 1, despacho: 1 });
  assertEquals(corpos, [{ message_id: "msg-1", modo: "sombra", rota: "ambos", dono_id: DONO.id }]);
});

Deno.test("dono sem legenda ou só a palavra-chave: comprovante, sem despacho", async () => {
  for (const caption of [null, "", "cupom", "Pix", "NF-e"]) {
    const { d, contagem, corpos } = deps({ modo: "dono" });
    assertEquals(await rotearMidiaDoDono({ ...MIDIA, caption, mediaKind: "document" }, d), "comprovante", String(caption));
    assertEquals(contagem.despacho, 0);
    assertEquals(corpos[0].rota, "comprovante");
    assertEquals(corpos[0].modo, "dono");
  }
});

Deno.test("dono com legenda comum, palavra-chave + texto ou 'os 123': ambos (o assistente recebe)", async () => {
  for (const caption of ["cupom OS 123 Brisa", "lança na OS do Brisa", "os 123", "c viu isso?"]) {
    const { d, contagem, corpos } = deps({ modo: "dono" });
    assertEquals(await rotearMidiaDoDono({ ...MIDIA, caption }, d), "ambos");
    assertEquals(contagem.despacho, 1);
    assertEquals(corpos[0].rota, "ambos");
  }
});

Deno.test("rota comprovante: receber recusado ou com erro cai no despacho de hoje", async () => {
  for (const receber of [false, new Error("timeout")]) {
    const { d, contagem } = deps({ modo: "dono", receber });
    assertEquals(await rotearMidiaDoDono(MIDIA, d), "agente");
    assertEquals(contagem.receber, 1);
    assertEquals(contagem.despacho, 1);
  }
});

Deno.test("rota comprovante que caiu no despacho: marca a linha como já encaminhada (antes de despachar)", async () => {
  const ordem: string[] = [];
  const { d } = deps({ modo: "dono", receber: false });
  const despachoOriginal = d.despacharAoAgente;
  d.despacharAoAgente = () => { ordem.push("despacho"); return despachoOriginal(); };
  d.marcarEncaminhado = (id) => { ordem.push(`marca:${id}`); return Promise.resolve(); };
  assertEquals(await rotearMidiaDoDono(MIDIA, d), "agente");
  assertEquals(ordem, ["marca:msg-1", "despacho"]);

  // a marca que falha não impede o despacho; receber aceito não marca nada
  const falha = deps({ modo: "dono", receber: false });
  falha.d.marcarEncaminhado = () => Promise.reject(new Error("db"));
  assertEquals(await rotearMidiaDoDono(MIDIA, falha.d), "agente");
  assertEquals(falha.contagem.despacho, 1);
  const aceito = deps({ modo: "dono" });
  let marcou = 0;
  aceito.d.marcarEncaminhado = () => { marcou++; return Promise.resolve(); };
  assertEquals(await rotearMidiaDoDono(MIDIA, aceito.d), "comprovante");
  assertEquals(marcou, 0);
});

Deno.test("documento que nunca é comprovante (xlsx/zip): despacho de hoje, sem receber", async () => {
  for (const mimetype of ["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "application/zip"]) {
    const { d, contagem } = deps({ modo: "dono" });
    assertEquals(await rotearMidiaDoDono({ ...MIDIA, mediaKind: "document", mimetype }, d), "agente");
    assertEquals(contagem.receber, 0);
    assertEquals(contagem.despacho, 1);
  }
});

Deno.test("chamarReceberPorHttp: o prazo padrão é de 20 s", () => {
  assertEquals(PRAZO_DO_RECEBER_MS, 20_000);
});

Deno.test("erro ao ler o modo ou o dono: despacho de hoje, sem receber", async () => {
  for (const o of [{ modo: new Error("db") }, { modo: "dono" as Modo, dono: new Error("db") }]) {
    const { d, contagem } = deps(o);
    assertEquals(await rotearMidiaDoDono(MIDIA, d), "agente");
    assertEquals(contagem.receber, 0);
    assertEquals(contagem.despacho, 1);
  }
});

Deno.test("sem dono cadastrado, ou outro admin: despacho de hoje", async () => {
  const semDono = deps({ modo: "dono", dono: null });
  assertEquals(await rotearMidiaDoDono(MIDIA, semDono.d), "agente");
  assertEquals(semDono.contagem.receber, 0);
  const outro = deps({ modo: "sombra" });
  assertEquals(await rotearMidiaDoDono({ ...MIDIA, appUserId: "outro-admin" }, outro.d), "agente");
  assertEquals(outro.contagem, { lerModo: 1, dono: 1, receber: 0, despacho: 1 });
});

Deno.test("ambos com receber falhando: despacho uma vez só, e o roteador não lança", async () => {
  const { d, contagem } = deps({ modo: "dono", receber: new Error("x") });
  assertEquals(await rotearMidiaDoDono({ ...MIDIA, caption: "lança isso" }, d), "ambos");
  assertEquals(contagem.despacho, 1);
});

Deno.test("despacho que lança não derruba o roteador", async () => {
  const { d } = deps({ modo: "off", despachoLanca: true });
  assertEquals(await rotearMidiaDoDono(MIDIA, d), "agente");
});

// ─── chamarReceberPorHttp ─────────────────────────────────────────────────────────────────

const CORPO: CorpoDoReceber = { message_id: "m-1", modo: "dono", rota: "comprovante", dono_id: DONO.id };

Deno.test("chamarReceberPorHttp: POST com a chave de serviço, acao receber, true só com 200 + aceito", async () => {
  const chamadas: Array<{ url: string; init?: RequestInit }> = [];
  const f = ((url: string, init?: RequestInit) => {
    chamadas.push({ url, init });
    return Promise.resolve(new Response(JSON.stringify({ aceito: true, id: "c-1", novo: true }), { status: 200 }));
  }) as typeof fetch;
  assertEquals(await chamarReceberPorHttp(CORPO, { url: "https://x.supabase.co", chave: "srv", fetch: f }), true);
  assertEquals(chamadas[0].url, "https://x.supabase.co/functions/v1/comprovantes-whatsapp");
  assertEquals((chamadas[0].init?.headers as Record<string, string>).Authorization, "Bearer srv");
  assertEquals(JSON.parse(String(chamadas[0].init?.body)), { acao: "receber", ...CORPO });
});

Deno.test("chamarReceberPorHttp: 422, 500, aceito=false, rede e tempo = false", async () => {
  const com = (r: () => Promise<Response>) => ({ url: "https://x", chave: "k", fetch: r as unknown as typeof fetch, timeoutMs: 20 });
  assertEquals(await chamarReceberPorHttp(CORPO, com(() => Promise.resolve(new Response('{"aceito":false}', { status: 422 })))), false);
  assertEquals(await chamarReceberPorHttp(CORPO, com(() => Promise.resolve(new Response("x", { status: 500 })))), false);
  assertEquals(await chamarReceberPorHttp(CORPO, com(() => Promise.resolve(new Response('{"aceito":false}', { status: 200 })))), false);
  assertEquals(await chamarReceberPorHttp(CORPO, com(() => Promise.resolve(new Response("não é json", { status: 200 })))), false);
  assertEquals(await chamarReceberPorHttp(CORPO, com(() => Promise.reject(new Error("rede")))), false);
  const preso = ((_u: string, init?: RequestInit) =>
    new Promise<Response>((_ok, falha) => init?.signal?.addEventListener("abort", () => falha(new DOMException("t", "TimeoutError"))))) as typeof fetch;
  assertEquals(await chamarReceberPorHttp(CORPO, { url: "https://x", chave: "k", fetch: preso, timeoutMs: 20 }), false);
});

Deno.test("ambos: o despacho não espera o receber (em paralelo)", async () => {
  let soltar: (v: boolean) => void = () => {};
  const pendente = new Promise<boolean>((ok) => { soltar = ok; });
  const { d, contagem } = deps({ modo: "sombra", receber: pendente });
  const rodando = rotearMidiaDoDono(MIDIA, d);
  await new Promise((ok) => setTimeout(ok, 0));
  assertEquals(contagem.despacho, 1); // já despachou com o receber ainda pendente
  soltar(true);
  assertEquals(await rodando, "ambos");
});

// ─── F2: texto e áudio do dono (rotearTextoDoDono) ────────────────────────────────────────

const ABERTA = "2026-10-10T22:30:00Z";

function estadoLigado(extra: Partial<EstadoDoTelefone> = {}): EstadoDoTelefone {
  return {
    conversa: true, dono: true,
    ativa: {
      id: "p-1", origem: "comprovante", tipo: "pergunta", referencia_id: "c-1", referencia_codigo: "CMP-00124", passo: "para_que",
      opcoes: [{ n: 1, rotulo: "OS-00112 · Brisa", valor: "os:1" }, { n: 2, rotulo: "Estoque", valor: "estoque" }], wa_message_id: "WA-P", aberta_em: ABERTA,
    },
    citada: null, pendencia: null, cmp_em_contexto: null, ...extra,
  };
}
const DESLIGADO: EstadoDoTelefone = { conversa: false, dono: false, ativa: null, citada: null, pendencia: null, cmp_em_contexto: null };

function depsTexto(op: {
  estado?: EstadoDoTelefone | Error;
  transcricao?: string | null;
  resposta?: { status: number; tratada?: boolean } | Error;
} = {}) {
  const c = { estado: 0, transcrever: 0, chamar: [] as Array<Record<string, unknown>>, despachos: [] as Array<string | undefined>, avisos: 0 };
  const d: DependenciasDoTexto = {
    estado: () => {
      c.estado++;
      return op.estado instanceof Error ? Promise.reject(op.estado) : Promise.resolve(op.estado ?? estadoLigado());
    },
    transcrever: () => {
      c.transcrever++;
      return Promise.resolve(op.transcricao === undefined ? "Um." : op.transcricao);
    },
    chamarComprovantes: (corpo) => {
      c.chamar.push(corpo);
      if (op.resposta instanceof Error) return Promise.reject(op.resposta);
      return Promise.resolve(op.resposta ?? { status: 200, tratada: true });
    },
    despacharAoAgente: (texto) => {
      c.despachos.push(texto);
      return Promise.resolve();
    },
    avisarFalha: () => {
      c.avisos++;
      return Promise.resolve();
    },
  };
  return { d, c };
}

const TEXTO = (texto: string, extra: Partial<{ tipo: string; citado: string | null }> = {}) =>
  ({ msgId: "msg-1", phone: DONO.phone, tipo: "text", texto, citado: null, ...extra });

Deno.test("F2 texto: conversa desligada = 1 leitura (o estado) e o despacho de hoje, sem texto pronto (o áudio transcreve lá)", async () => {
  for (const tipo of ["text", "audio"]) {
    const { d, c } = depsTexto({ estado: DESLIGADO });
    assertEquals(await rotearTextoDoDono(TEXTO("1", { tipo }), d), "assistente");
    assertEquals(c.estado, 1);
    assertEquals(c.transcrever, 0);
    assertEquals(c.chamar.length, 0);
    assertEquals(c.despachos, [undefined]);
  }
  const erro = depsTexto({ estado: new Error("db") });
  assertEquals(await rotearTextoDoDono(TEXTO("1"), erro.d), "assistente");
  assertEquals(erro.c.despachos, [undefined]);
});

Deno.test("F2 texto: '1' com a pergunta do CMP aberta vai ao responder e NÃO ao assistente", async () => {
  const { d, c } = depsTexto();
  assertEquals(await rotearTextoDoDono(TEXTO("1"), d), "comprovante");
  assertEquals(c.chamar, [{ acao: "responder", message_id: "msg-1", phone: DONO.phone, texto: "1", citado: null, destino: "comprovante" }]);
  assertEquals(c.despachos.length, 0);
});

Deno.test("F2 texto: o responder diz que é do assistente (tratada:false) → despacha com o texto", async () => {
  const { d, c } = depsTexto({ resposta: { status: 200, tratada: false } });
  assertEquals(await rotearTextoDoDono(TEXTO("2"), d), "assistente");
  assertEquals(c.despachos, ["2"]);
});

// Revisão de 11/10/2026: só a recusa DEFINITIVA antes de processar pede para repetir.
Deno.test("F2 texto: 5xx do responder → aviso ao dono e NENHUM despacho", async () => {
  const { d, c } = depsTexto({ resposta: { status: 500 } });
  await rotearTextoDoDono(TEXTO("1"), d);
  assertEquals(c.avisos, 1);
  assertEquals(c.despachos.length, 0, "um '1' de menu nunca cai no assistente por falha");
});

Deno.test("F2 texto: 422 (a edge recusou antes de processar) → despacha com o texto, sem aviso", async () => {
  const { d, c } = depsTexto({ resposta: { status: 422, tratada: false } });
  assertEquals(await rotearTextoDoDono(TEXTO("1"), d), "assistente");
  assertEquals(c.despachos, ["1"]);
  assertEquals(c.avisos, 0);
});

Deno.test("F2 texto: sem resposta (rede, tempo) → NADA: o responder pode ter gravado e mandado o 'Próximo:'", async () => {
  const { d, c } = depsTexto({ resposta: new Error("rede") });
  await rotearTextoDoDono(TEXTO("1"), d);
  assertEquals(c.avisos, 0, "pedir para repetir faria o '1' cair na pergunta seguinte");
  assertEquals(c.despachos.length, 0);
});

Deno.test("F2 áudio: transcreve UMA vez e o texto transcrito passa pelo mesmo parser; falhou → '[audio]' ao assistente", async () => {
  const { d, c } = depsTexto({ transcricao: "🎤 Opção dois." });
  assertEquals(await rotearTextoDoDono(TEXTO("[audio]", { tipo: "audio" }), d), "comprovante");
  assertEquals(c.transcrever, 1);
  assertEquals(c.chamar[0].texto, "🎤 Opção dois.");
  assertEquals(c.despachos.length, 0);

  const livre = depsTexto({ transcricao: "manda o orçamento do Brisa pro cliente" });
  assertEquals(await rotearTextoDoDono(TEXTO("[audio]", { tipo: "audio" }), livre.d), "assistente");
  assertEquals(livre.c.transcrever, 1);
  assertEquals(livre.c.despachos, ["manda o orçamento do Brisa pro cliente"], "o assistente recebe o texto já transcrito (sem transcrever de novo)");

  const falhou = depsTexto({ transcricao: null });
  assertEquals(await rotearTextoDoDono(TEXTO("[audio]", { tipo: "audio" }), falhou.d), "assistente");
  assertEquals(falhou.c.despachos, ["[audio]"]);
  assertEquals(falhou.c.chamar.length, 0);
});

Deno.test("F2 texto: texto livre com a pergunta aberta → assistente; pendentes → a lista e depois o assistente", async () => {
  const livre = depsTexto();
  assertEquals(await rotearTextoDoDono(TEXTO("quanto ficou a OS 123?"), livre.d), "assistente");
  assertEquals(livre.c.chamar.length, 0);
  assertEquals(livre.c.despachos, ["quanto ficou a OS 123?"]);

  const pend = depsTexto();
  assertEquals(await rotearTextoDoDono(TEXTO("pendentes"), pend.d), "pendentes");
  assertEquals(pend.c.chamar, [{ acao: "pendentes", message_id: "msg-1", phone: DONO.phone }]);
  assertEquals(pend.c.despachos, ["pendentes"]);
});

Deno.test("F2 texto: empate com a pendência (< 2 min) → desempate, sem despacho; comando sem pergunta aberta → responder", async () => {
  const empate = depsTexto({ estado: estadoLigado({ pendencia: { tipo: "confirmacao", id: "pa", titulo: "x", desde: "2026-10-10T22:31:00Z" } }) });
  assertEquals(await rotearTextoDoDono(TEXTO("sim"), empate.d), "ambiguo");
  assertEquals(empate.c.chamar, [{ acao: "desempatar", message_id: "msg-1", phone: DONO.phone, citado: null }]);
  assertEquals(empate.c.despachos.length, 0);

  const cmd = depsTexto({ estado: estadoLigado({ ativa: null }) });
  assertEquals(await rotearTextoDoDono(TEXTO("cmp 124"), cmd.d), "comando");
  assertEquals(cmd.c.chamar[0].destino, "comando");

  const semPergunta = depsTexto({ estado: estadoLigado({ ativa: null }) });
  assertEquals(await rotearTextoDoDono(TEXTO("1"), semPergunta.d), "assistente");
  assertEquals(semPergunta.c.despachos, ["1"]);
});

Deno.test("F2 texto: o despacho que lança não derruba o roteador e acontece uma vez só", async () => {
  const { d, c } = depsTexto({ estado: DESLIGADO });
  d.despacharAoAgente = () => { c.despachos.push("x"); return Promise.reject(new Error("caiu")); };
  assertEquals(await rotearTextoDoDono(TEXTO("oi"), d), "assistente");
  assertEquals(c.despachos.length, 1);
});

Deno.test("chamarComprovantesPorHttp e avisarFalhaPorHttp: corpo, chave de serviço, status/tratada, rede = 0", async () => {
  const chamadas: Array<{ url: string; init?: RequestInit }> = [];
  const f = ((url: string, init?: RequestInit) => {
    chamadas.push({ url, init });
    return Promise.resolve(new Response(JSON.stringify({ tratada: false, resultado: "assistente" }), { status: 200 }));
  }) as typeof fetch;
  assertEquals(await chamarComprovantesPorHttp({ acao: "responder", message_id: "m" }, { url: "https://x.supabase.co", chave: "srv", fetch: f }), { status: 200, tratada: false });
  assertEquals(chamadas[0].url, "https://x.supabase.co/functions/v1/comprovantes-whatsapp");
  assertEquals((chamadas[0].init?.headers as Record<string, string>).Authorization, "Bearer srv");
  assertEquals(JSON.parse(String(chamadas[0].init?.body)), { acao: "responder", message_id: "m" });
  const rede = (() => Promise.reject(new Error("rede"))) as unknown as typeof fetch;
  assertEquals(await chamarComprovantesPorHttp({}, { url: "https://x", chave: "k", fetch: rede }), { status: 0 });

  await avisarFalhaPorHttp({ phone: DONO.phone, msgId: "m-9" }, { url: "https://x.supabase.co", chave: "srv", fetch: f });
  assertEquals(chamadas[1].url, "https://x.supabase.co/functions/v1/whatsapp-send");
  assertEquals(JSON.parse(String(chamadas[1].init?.body)), {
    phone: DONO.phone, kind: "text", message: TEXTO_FALHA, context: "comprovante", dedupe_key: "cmp:f:m-9",
  });
  await avisarFalhaPorHttp({ phone: DONO.phone, msgId: "m-9" }, { url: "https://x", chave: "k", fetch: rede }); // não lança
});

// ─── revisão de 11/10/2026: interrupção, dica, foto citada, não entendi, resposta atrasada ───

function comInterromper(op: Parameters<typeof depsTexto>[0] = {}) {
  const r = depsTexto(op);
  const ordem: string[] = [];
  r.d.interromper = () => { ordem.push("interromper"); return Promise.resolve(); };
  const despachar = r.d.despacharAoAgente;
  r.d.despacharAoAgente = (texto) => { ordem.push("despacho"); return despachar(texto); };
  return { ...r, ordem };
}

Deno.test("F2 texto livre com a pergunta do CMP aberta: marca 'interrompida' ANTES de despachar; sem ela, não marca", async () => {
  const aberta = comInterromper();
  assertEquals(await rotearTextoDoDono(TEXTO("quanto ficou a OS 123?"), aberta.d), "assistente");
  assertEquals(aberta.ordem, ["interromper", "despacho"]);

  const semPergunta = comInterromper({ estado: estadoLigado({ ativa: null }) });
  await rotearTextoDoDono(TEXTO("quanto ficou a OS 123?"), semPergunta.d);
  assertEquals(semPergunta.ordem, ["despacho"]);

  // interromper que falha não segura o despacho
  const falha = depsTexto();
  falha.d.interromper = () => Promise.reject(new Error("rede"));
  await rotearTextoDoDono(TEXTO("quanto ficou a OS 123?"), falha.d);
  assertEquals(falha.c.despachos, ["quanto ficou a OS 123?"]);
});

Deno.test("F2 texto: dica logo depois da foto, foto citada e mensagem não entendida vão ao responder com o destino", async () => {
  const dica = depsTexto({ estado: estadoLigado({ ativa: null, cmp_chegando: { id: "c-2", codigo: "CMP-00125" } }) });
  assertEquals(await rotearTextoDoDono(TEXTO("essa é da OS do Brisa"), dica.d), "dica");
  assertEquals(dica.c.chamar[0].destino, "dica");
  assertEquals(dica.c.despachos.length, 0);

  const foto = depsTexto({ estado: estadoLigado({ ativa: null, citado_cmp: { id: "c-1", codigo: "CMP-00124", situacao: "lido", gravado: false } }) });
  assertEquals(await rotearTextoDoDono(TEXTO("OS 112", { citado: "WA-FOTO" }), foto.d), "foto_do_cmp");
  assertEquals(foto.c.chamar[0], { acao: "responder", message_id: "msg-1", phone: DONO.phone, texto: "OS 112", citado: "WA-FOTO", destino: "foto_do_cmp" });

  // "cartão" no como pagou: débito ou crédito? não é resposta, e não é conversa
  const comoPagou = estadoLigado();
  comoPagou.ativa = { ...comoPagou.ativa!, passo: "como_pagou", opcoes: [{ n: 1, rotulo: "Pix", valor: "pix" }, { n: 2, rotulo: "Débito", valor: "debito" }, { n: 3, rotulo: "Crédito", valor: "credito" }] };
  const naoEntendi = depsTexto({ estado: comoPagou });
  assertEquals(await rotearTextoDoDono(TEXTO("cartão"), naoEntendi.d), "nao_entendi");
  assertEquals(naoEntendi.c.chamar[0].destino, "nao_entendi");
  assertEquals(naoEntendi.c.despachos.length, 0);
});

Deno.test("F2 texto: resposta atrasada à última pergunta do CMP (sem pergunta aberta) reabre; sim/não não reabrem", async () => {
  const ultima = {
    id: "p-velha", referencia_id: "c-1", referencia_codigo: "CMP-00124", passo: "para_que",
    opcoes: [{ n: 1, rotulo: "OS-00112 · Brisa", valor: "os:1" }, { n: 2, rotulo: "Estoque", valor: "estoque" }], aberta_em: ABERTA,
  };
  const atrasada = depsTexto({ estado: estadoLigado({ ativa: null, ultima_do_cmp: ultima }) });
  assertEquals(await rotearTextoDoDono(TEXTO("estoque"), atrasada.d), "comprovante_reabrir");
  assertEquals(atrasada.c.chamar[0].destino, "comprovante_reabrir");
  const sim = depsTexto({ estado: estadoLigado({ ativa: null, ultima_do_cmp: ultima }) });
  assertEquals(await rotearTextoDoDono(TEXTO("sim"), sim.d), "assistente", "um 'sim' solto não reabre a pergunta velha");
});
