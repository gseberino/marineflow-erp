// A voz única LIGADA de verdade (secretário, Passo 4, P4.5, 20/10/2026), com um banco de mentira. O que se protege:
//   · 'ligado' só vale com a manhã nova E o fechamento ligado (a trava de vozEfetiva); lerPortao lê as 5 chaves num SELECT;
//   · só o telefone do DONO passa pelo portão (falaPeloPortao), e ANTES de mandar (perguntarAoPortao, modo 'ligado');
//   · a fala segue a decisão: acordar/deixar mandam; guardar/acabar/repetido não; sem resposta = manda como sempre;
//   · registrarParaTodos (o registro DEPOIS de mandar) é só da sombra: a equipe não vira guardado;
//   · o acorde vai à fila com a chave aviso:<id>, prioridade 1 e tentativas até as 20h; insert que falha reabre; a chave
//     já na fila (23505) conta como enfileirado; reabrir nunca lança;
//   · o acompanhamento do dono registra em 'ligado' (antes); o de outro telefone, como se a voz estivesse desligada.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  chaveDaFilaDoAcorde, enfileirarAcorde, falaDoPortao, falaPeloPortao, lerPortao, linhaDoAcordeNaFila, modoDoRegistroDoAcompanhamento,
  perguntarAoPortao, portaoDasConfiguracoes, reabrirNoPortao, registrarParaTodos,
} from "./registrar.ts";
import type { AvisoDaFonte } from "./portao.ts";

const AVISO: AvisoDaFonte = { fonte: "email", chave: "golpe:x@y", assunto: "golpe:x@y", destino: "acorde", texto: "t" };
const CONSUMIDORES = [{ key: "resumo_formato", value: "novo" }, { key: "fechamento_formato", value: "ligado" }];

// deno-lint-ignore no-explicit-any
function banco(o: { settings?: Array<{ key: string; value: string }>; erroSettings?: boolean; rpc?: (nome: string, args: any) => any } = {}) {
  // deno-lint-ignore no-explicit-any
  const chamadas: Array<{ nome: string; args: any }> = [];
  // deno-lint-ignore no-explicit-any
  let chaves: any = null;
  const admin = {
    from() {
      return {
        select() {
          return {
            in(_c: string, v: string[]) {
              chaves = v;
              return Promise.resolve(o.erroSettings ? { data: null, error: { message: "falhou" } } : { data: o.settings ?? [], error: null });
            },
          };
        },
      };
    },
    // deno-lint-ignore no-explicit-any
    rpc(nome: string, args: any) {
      chamadas.push({ nome, args });
      return Promise.resolve(o.rpc ? o.rpc(nome, args) : { data: { ok: true, decisao: "acordar", id: "av-1", cartao: true }, error: null });
    },
  };
  return { admin, chamadas, chaves: () => chaves };
}

Deno.test("lerPortao: 'ligado' com a manhã nova e o fechamento ligado = ligado; sem eles = sombra; as 5 chaves num SELECT", async () => {
  const b = banco({ settings: [{ key: "voz_unica", value: "ligado" }, ...CONSUMIDORES] });
  const ligado = await lerPortao(b.admin);
  assertEquals([ligado.voz, ligado.modo], ["ligado", "ligado"]);
  assertEquals(b.chaves(), ["voz_unica", "voz_unica_regras", "acompanhar_freio", "resumo_formato", "fechamento_formato"]);
  const semFechamento = await lerPortao(banco({ settings: [{ key: "voz_unica", value: "ligado" }, { key: "resumo_formato", value: "novo" }] }).admin);
  assertEquals([semFechamento.voz, semFechamento.modo], ["ligado", "sombra"], "sem o fechamento ligado, age como sombra");
  const manhaSombra = await lerPortao(banco({ settings: [{ key: "voz_unica", value: "ligado" }, { key: "resumo_formato", value: "sombra" }, { key: "fechamento_formato", value: "ligado" }] }).admin);
  assertEquals(manhaSombra.modo, "sombra");
  assertEquals((await lerPortao(banco({ settings: [{ key: "voz_unica", value: "sombra" }, ...CONSUMIDORES] }).admin)).modo, "sombra");
  assertEquals((await lerPortao(banco({ erroSettings: true, settings: [{ key: "voz_unica", value: "ligado" }, ...CONSUMIDORES] }).admin)).modo, null, "erro = desligado");
});

Deno.test("registrarParaTodos é só da sombra: com 'ligado' não registra ninguém (a equipe não vira guardado)", async () => {
  const { admin, chamadas } = banco();
  assertEquals(await registrarParaTodos(admin, "ligado", ["5547999990001", "5547999990002"], [AVISO]), 0);
  assertEquals(chamadas.length, 0);
});

Deno.test("falaDoPortao: acordar/deixar mandam; guardar/acabar/repetido não; sem resposta = manda como sempre", () => {
  assertEquals(falaDoPortao({ ok: true, decisao: "acordar", cartao: true, id: "av-1" }), { manda: true, cartao: true, acordou: "av-1", decisao: "acordar" });
  assertEquals(falaDoPortao({ ok: true, decisao: "acordar", cartao: false, id: "av-2" }).cartao, false);
  assertEquals(falaDoPortao({ ok: true, decisao: "deixar", id: "av-3" }), { manda: true, cartao: false, acordou: null, decisao: "deixar" });
  for (const d of ["guardar", "acabar"] as const) assertEquals(falaDoPortao({ ok: true, decisao: d, id: "x" }).manda, false, d);
  assertEquals(falaDoPortao({ ok: true, decisao: "repetido", antes: "acordar" }).manda, false, "o mesmo golpe de novo não avisa");
  assertEquals(falaDoPortao({ ok: true, decisao: "repetido", antes: "guardar" }).manda, false);
  assertEquals(falaDoPortao({ ok: true, decisao: "repetido", antes: "deixar" }).manda, true, "o alarme do dono com a mesma chave toca");
  for (const r of [null, { ok: false, erro: "x" }, { ok: true }, { ok: true, decisao: "estranha" as never }]) {
    assertEquals(falaDoPortao(r), { manda: true, cartao: false, acordou: null, decisao: "erro" }, JSON.stringify(r));
  }
});

Deno.test("perguntarAoPortao pede em 'ligado'; erro do banco = manda como sempre", async () => {
  const { admin, chamadas } = banco({ rpc: () => ({ data: { ok: true, decisao: "guardar", id: "g1" }, error: null }) });
  const f = await perguntarAoPortao(admin, "5547999990001", AVISO, new Date("2026-10-21T13:00:00Z"));
  assertEquals([f.manda, f.decisao], [false, "guardar"]);
  assertEquals([chamadas[0].nome, chamadas[0].args.p.modo, chamadas[0].args.p.phone, chamadas[0].args.p.agora],
    ["aviso_registrar", "ligado", "5547999990001", "2026-10-21T13:00:00.000Z"]);
  const erro = await perguntarAoPortao(banco({ rpc: () => ({ data: null, error: { message: "permission denied" } }) }).admin, "5547999990001", AVISO);
  assertEquals([erro.manda, erro.decisao], [true, "erro"]);
  const explode = await perguntarAoPortao(banco({ rpc: () => { throw new Error("rede"); } }).admin, "5547999990001", AVISO);
  assertEquals([explode.manda, explode.decisao], [true, "erro"]);
});

Deno.test("falaPeloPortao: só com o modo ligado e só o telefone do dono", () => {
  const dono = { id: "u", phone: "5547999990001" };
  assertEquals(falaPeloPortao({ modo: "ligado" }, dono, "5547999990001"), true);
  assertEquals(falaPeloPortao({ modo: "ligado" }, dono, "5547999990002"), false, "a equipe recebe como sempre");
  assertEquals(falaPeloPortao({ modo: "sombra" }, dono, "5547999990001"), false);
  assertEquals(falaPeloPortao({ modo: null }, dono, "5547999990001"), false);
  assertEquals(falaPeloPortao({ modo: "ligado" }, null, "5547999990001"), false, "dono não lido = ninguém passa pelo portão");
});

Deno.test("a linha do acorde na fila: chave aviso:<id>, prioridade 1, tentativas até as 20h, a referência do aviso", () => {
  const l = linhaDoAcordeNaFila({ phone: "5547999990001", texto: "t", avisoId: "av-1", agora: new Date("2026-10-21T12:05:00Z"), source: "ai_monitor" });
  assertEquals(l, {
    phone_normalized: "5547999990001", message: "t", source: "ai_monitor", priority: 1, max_attempts: 66, dedupe_key: "aviso:av-1", source_ref_id: "av-1",
  });
  assertEquals(chaveDaFilaDoAcorde("av-1"), "aviso:av-1");
  assertEquals(linhaDoAcordeNaFila({ phone: "1", texto: "t", avisoId: "a", agora: new Date("2026-10-21T22:58:00Z"), source: "s" }).max_attempts, 1, "19:58: uma tentativa");
});

Deno.test("enfileirarAcorde: insert ok = true; chave já na fila (23505) = true; erro = reabre e false", async () => {
  // deno-lint-ignore no-explicit-any
  const fila = (erro: any) => {
    // deno-lint-ignore no-explicit-any
    const feito: { inserts: any[]; rpcs: any[] } = { inserts: [], rpcs: [] };
    const admin = {
      from(t: string) {
        return { insert(l: unknown) { feito.inserts.push([t, l]); return Promise.resolve({ error: erro }); } };
      },
      // deno-lint-ignore no-explicit-any
      rpc(nome: string, args: any) { feito.rpcs.push([nome, args.p]); return Promise.resolve({ data: { ok: true, resultado: "reaberto" }, error: null }); },
    };
    return { admin, feito };
  };
  const p = { phone: "5547999990001", texto: "t", avisoId: "av-1", agora: new Date("2026-10-21T13:00:00Z"), source: "me_acorde" };
  const ok = fila(null);
  assertEquals(await enfileirarAcorde(ok.admin, p), true);
  assertEquals([ok.feito.inserts[0][0], ok.feito.inserts[0][1].dedupe_key, ok.feito.rpcs.length], ["whatsapp_send_queue", "aviso:av-1", 0]);
  const dup = fila({ code: "23505", message: "duplicate" });
  assertEquals(await enfileirarAcorde(dup.admin, p), true);
  assertEquals(dup.feito.rpcs.length, 0);
  const falhou = fila({ code: "XX000", message: "falhou" });
  assertEquals(await enfileirarAcorde(falhou.admin, p), false);
  assertEquals(falhou.feito.rpcs, [["aviso_reabrir", { id: "av-1", agora: "2026-10-21T13:00:00.000Z" }]]);
});

Deno.test("reabrirNoPortao: chama aviso_reabrir; sem id, não reaberto ou erro = false, nunca lança", async () => {
  const { admin, chamadas } = banco({ rpc: () => ({ data: { ok: true, resultado: "reaberto" }, error: null }) });
  assertEquals(await reabrirNoPortao(admin, "av-1"), true);
  assertEquals([chamadas[0].nome, chamadas[0].args.p.id], ["aviso_reabrir", "av-1"]);
  assertEquals(await reabrirNoPortao(admin, null), false);
  assertEquals(await reabrirNoPortao(banco({ rpc: () => ({ data: { ok: true, resultado: "nao_estava_acordado" }, error: null }) }).admin, "x"), false);
  assertEquals(await reabrirNoPortao(banco({ rpc: () => { throw new Error("rede"); } }).admin, "x"), false);
});

Deno.test("acompanhamento com a voz ligada: o do dono registra em 'ligado' (antes); o de outro telefone, como desligada", () => {
  const ligada = portaoDasConfiguracoes({ voz_unica: "ligado", acompanhar_freio: "ligado", resumo_formato: "novo", fechamento_formato: "ligado" });
  assertEquals(ligada.modo, "ligado");
  assertEquals(modoDoRegistroDoAcompanhamento(ligada, "acompanhar", true), "ligado");
  assertEquals(modoDoRegistroDoAcompanhamento(ligada, "promessa", true), "ligado");
  assertEquals(modoDoRegistroDoAcompanhamento(ligada, "acompanhar", false), "sombra", "outro telefone: só a conta do freio");
  assertEquals(modoDoRegistroDoAcompanhamento(ligada, "promessa", false), null);
  const semFreio = portaoDasConfiguracoes({ voz_unica: "ligado", resumo_formato: "novo", fechamento_formato: "ligado" });
  assertEquals(modoDoRegistroDoAcompanhamento(semFreio, "acompanhar", false), null);
  // as configurações montadas à mão SEM as chaves dos consumidores: 'ligado' age como sombra (registra depois)
  const semConsumidores = portaoDasConfiguracoes({ voz_unica: "ligado" });
  assertEquals(semConsumidores.modo, "sombra");
  assertEquals(modoDoRegistroDoAcompanhamento(semConsumidores, "promessa", true), "sombra");
});
