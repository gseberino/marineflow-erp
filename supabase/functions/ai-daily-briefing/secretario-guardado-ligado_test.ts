// A manhã com a voz única LIGADA de verdade (secretário, Passo 4, P4.5, 20/10/2026), com um banco de mentira. O que se
// protege:
//   · a manhã nova ENVIADA lê o guardado do modo LIGADO (com qualquer valor da chave: o que ficou guardado não se perde
//     se o dono a voltar); a manhã-sombra lê o da SOMBRA, só com a voz em sombra; a enviada nunca lê o da sombra;
//   · sem linha 'ligado' (o dia de hoje, com a voz em sombra) = o texto de sempre;
//   · marcar: ligado com o id da fila (incluido → entregue quando a fila disser sent); ligado sem o id não marca os
//     mostrados (voltam na próxima); só na 1ª gravação do dia.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { lerGuardadoDaManha, type ManhaNova, marcarGuardadoDaManha, montarDosDados } from "./secretario.ts";
import { AGORA_1510, coleta1510, deHoje1510, HOJE_1510 } from "./secretario-fixture.ts";
import { REGRAS_PADRAO } from "../_shared/uma-voz/portao.ts";
import type { PortaoDaRodada } from "../_shared/uma-voz/registrar.ts";

const DONO = { phone: "5547900009654" };
const ESCRITORIO = { propostas: { saidas: 1, entradas: 0, transferencias: 0, outras: 0 }, alertas: 0, regras: 0, debitosSemLoja: 0, entradas: null };
const portao = (modo: PortaoDaRodada["modo"]): PortaoDaRodada => ({ voz: modo ?? "desligado", modo, regras: { ...REGRAS_PADRAO }, freio: false });

// deno-lint-ignore no-explicit-any
function banco(avisosPorModo: Record<string, any[]>) {
  // deno-lint-ignore no-explicit-any
  const rpcs: Array<{ nome: string; p: any }> = [];
  const admin = {
    // deno-lint-ignore no-explicit-any
    rpc(nome: string, args: any) {
      rpcs.push({ nome, p: args.p });
      if (nome === "avisos_para_a_mensagem") return Promise.resolve({ data: { ok: true, avisos: avisosPorModo[args.p.modo] ?? [] }, error: null });
      return Promise.resolve({ data: { ok: true, incluidos: args.p.ids?.length ?? 0, resolvidos: args.p.ids?.length ?? 0 }, error: null });
    },
    from() {
      // deno-lint-ignore no-explicit-any
      const q: any = { select: () => q, eq: () => q, in: () => q, gte: () => q, order: () => q, limit: () => Promise.resolve({ data: [], error: null }) };
      return q;
    },
  };
  return { admin, rpcs };
}

const GOLPE = {
  id: "g1", fonte: "email", assunto: "golpe:x@y.com", destino: "acorde", motivo: "fora_da_janela", texto: "t", dados: {},
  registrado_em: "2026-10-14T23:30:00Z", dia: "2026-10-14", mensagem: "manha", reaberto: 0,
};

Deno.test("manhã enviada lê o guardado do LIGADO (voz ligada ou sombra; desligada nada); a sombra lê o da sombra", async () => {
  for (const modo of ["ligado", "sombra"] as const) {
    const b = banco({ ligado: [GOLPE], sombra: [{ ...GOLPE, id: "s1" }] });
    const g = await lerGuardadoDaManha(b.admin, { agora: AGORA_1510, dono: DONO, modo: "novo", portao: portao(modo) });
    assertEquals(b.rpcs.map((x) => [x.nome, x.p.modo, x.p.mensagem]), [["avisos_para_a_mensagem", "ligado", "manha"]], String(modo));
    assertEquals([g?.modo, g?.avisos.map((a) => a.id)], ["ligado", ["g1"]], String(modo));
  }
  // a chave 'ligado' que age como sombra (sem a trava) também lê: voz = 'ligado', modo efetivo = 'sombra'
  const trava = banco({ ligado: [GOLPE] });
  assertEquals((await lerGuardadoDaManha(trava.admin, { agora: AGORA_1510, dono: DONO, modo: "novo", portao: { ...portao("sombra"), voz: "ligado" } }))?.modo, "ligado");
  // desligada: nada é lido (como antes)
  const desl = banco({ ligado: [GOLPE] });
  assertEquals(await lerGuardadoDaManha(desl.admin, { agora: AGORA_1510, dono: DONO, modo: "novo", portao: portao(null) }), null);
  assertEquals(desl.rpcs.length, 0);
  const s = banco({ sombra: [{ ...GOLPE, id: "s1" }] });
  const gs = await lerGuardadoDaManha(s.admin, { agora: AGORA_1510, dono: DONO, modo: "sombra", portao: portao("sombra") });
  assertEquals([gs?.modo, gs?.avisos.map((a) => a.id)], ["sombra", ["s1"]]);
  for (const modo of ["ligado", null] as const) {
    const x = banco({ sombra: [GOLPE], ligado: [GOLPE] });
    assertEquals(await lerGuardadoDaManha(x.admin, { agora: AGORA_1510, dono: DONO, modo: "sombra", portao: portao(modo) }), null, `manhã-sombra com a voz ${modo}`);
    assertEquals(x.rpcs.length, 0);
  }
});

Deno.test("manhã enviada sem guardado do ligado (hoje, voz em sombra) = o texto de sempre; com ele, o bloco", async () => {
  const base = { hoje: HOJE_1510, agora: AGORA_1510, coleta: coleta1510(), historico: [], naRua: { total: 21026, n: 5 }, deHoje: deHoje1510(), escritorio: ESCRITORIO };
  const antes = montarDosDados(base);
  const vazio = await lerGuardadoDaManha(banco({ sombra: [GOLPE] }).admin, { agora: AGORA_1510, dono: DONO, modo: "novo", portao: portao("sombra") });
  assertEquals(montarDosDados({ ...base, guardado: vazio }).texto, antes.texto);
  const com = await lerGuardadoDaManha(banco({ ligado: [GOLPE] }).admin, { agora: AGORA_1510, dono: DONO, modo: "novo", portao: portao("ligado") });
  const m = montarDosDados({ ...base, guardado: com });
  assert(m.texto.includes("Guardei 1 aviso para não te interromper: parece golpe no e-mail: x@y.com."), m.texto);
  assertEquals([m.guardado?.modo, m.guardado?.plano.mostrados], ["ligado", ["g1"]]);
});

Deno.test("marcar a manhã enviada: ligado com o id da fila; sem o id, só o resolvido; só na 1ª gravação", async () => {
  const manha = (modo: "ligado" | "sombra"): ManhaNova => ({
    texto: "x", tipoDoDia: "util", itens: [], escritorio: "", itensManha: 0, itensLista: 0, semLetra: 0,
    guardado: { modo, plano: { linhas: ["l"], escritorio: [], mostrados: ["g1"], doEscritorio: [], resolvidos: ["r1"], restantes: 0 } },
  });
  const comFila = banco({});
  assertEquals(await marcarGuardadoDaManha(comFila.admin, { dono: DONO, manha: manha("ligado"), novo: true, filaId: "fila-1" }), 1);
  assertEquals(comFila.rpcs.map((x) => [x.nome, x.p.modo, x.p.fila_id ?? null]), [["aviso_resolver", "ligado", null], ["avisos_incluir_na_mensagem", "ligado", "fila-1"]]);
  const semFila = banco({});
  assertEquals(await marcarGuardadoDaManha(semFila.admin, { dono: DONO, manha: manha("ligado"), novo: true, filaId: null }), 0);
  assertEquals(semFila.rpcs.map((x) => x.nome), ["aviso_resolver"], "sem o id, os mostrados voltam na próxima");
  const segunda = banco({});
  assertEquals(await marcarGuardadoDaManha(segunda.admin, { dono: DONO, manha: manha("ligado"), novo: false, filaId: "fila-1" }), 0);
  assertEquals(segunda.rpcs.length, 0);
  // a sombra continua sem fila (incluido, nunca entregue)
  const sombra = banco({});
  await marcarGuardadoDaManha(sombra.admin, { dono: DONO, manha: manha("sombra"), novo: true });
  assertEquals(sombra.rpcs.map((x) => [x.nome, "fila_id" in x.p]), [["aviso_resolver", false], ["avisos_incluir_na_mensagem", false]]);
});
