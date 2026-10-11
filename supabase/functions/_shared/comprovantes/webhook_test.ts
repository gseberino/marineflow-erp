// O portão do whatsapp-webhook: o que cada mensagem custa e para onde vai.
// A regra mais importante: texto e áudio NÃO leem nada novo, e com "off" a mídia lê só a chave.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { chamarReceberPorHttp, type CorpoDoReceber, type DependenciasDoRoteador, PRAZO_DO_RECEBER_MS, rotearMidiaDoDono } from "./webhook.ts";
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
