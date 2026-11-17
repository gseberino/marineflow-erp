// A fila da impressora (17/11/2026): o que vai a ai_jobs, a espera honesta e as frases. Banco falso, dado sintético.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  fraseDoResultado,
  impressoraNoAr,
  imprimirPelaFila,
  limitarCopias,
  linhaDoJob,
  motivoDoWorker,
  PROVEDOR_DA_IMPRESSORA,
  WORKER_DA_IMPRESSORA,
} from "./fila.ts";
import { bancoFalso } from "./banco-falso-de-teste.ts";

const PEDIDO = {
  url: "https://x.supabase.co/storage/v1/object/sign/pdf-agente/agente/2026/a.pdf?token=t",
  nome: "Via-OS-00136.pdf",
  descricao: "Via do técnico OS-00136",
  pedidoPor: { usuario: "u1" },
  chave: "imprimir-via:os1:os:u1:abc",
};

/** Relógio que anda o que o "dormir" dorme: a espera de 45 s roda em milissegundos. */
function relogio() {
  let t = Date.parse("2026-11-17T10:00:00Z");
  return { agora: () => new Date(t), dormir: (ms: number) => { t += ms; return Promise.resolve(); } };
}

Deno.test("linhaDoJob: o contrato v1 do worker, uma tentativa só e prazo curto", () => {
  const agora = new Date("2026-11-17T10:00:00Z");
  const l = linhaDoJob({ ...PEDIDO, copias: 9, colorido: true }, agora);
  assertEquals(l.provider, PROVEDOR_DA_IMPRESSORA);
  assertEquals(l.max_attempts, 1);
  assertEquals(l.input, { versao: 1, arquivo: { url: PEDIDO.url, nome: PEDIDO.nome }, copias: 5, colorido: true });
  assertEquals(l.metadata.tipo, "impressao");
  assertEquals(l.metadata.chave, PEDIDO.chave);
  assertEquals(l.deadline_at, "2026-11-17T10:02:00.000Z");
});

Deno.test("limitarCopias: 1 a 5", () => {
  assertEquals([limitarCopias(undefined), limitarCopias(0), limitarCopias("3"), limitarCopias(40), limitarCopias(2.7)], [1, 1, 3, 5, 2]);
});

Deno.test("imprimirPelaFila: o PC imprimiu → impresso, com as páginas", async () => {
  let leituras = 0;
  const { admin, chamadas } = bancoFalso((c) => {
    if (c.op === "insert") return { data: { id: "j1" } };
    if (c.filtros.some(([, col]) => col === "metadata->>chave")) return { data: [] };
    leituras++;
    return { data: leituras < 3 ? { status: "processing" } : { status: "completed", response: { data: { situacao: "impresso", paginas: 2 } } } };
  });
  const r = await imprimirPelaFila(admin, PEDIDO, relogio());
  assertEquals(r, { ok: true, situacao: "impresso", paginas: 2 });
  assert(chamadas.some((c) => c.tabela === "ai_jobs" && c.op === "insert"));
});

Deno.test("imprimirPelaFila: o mesmo papel há instantes → repetido, nada novo na fila", async () => {
  const { admin, chamadas } = bancoFalso((c) => (c.filtros.some(([, col]) => col === "metadata->>chave") ? { data: [{ id: "j0" }] } : { data: null }));
  const r = await imprimirPelaFila(admin, PEDIDO, relogio());
  assertEquals(r, { ok: true, repetido: true });
  assertEquals(chamadas.filter((c) => c.op === "insert").length, 0);
});

Deno.test("imprimirPelaFila: ninguém pegou → cancela o pedido (nada sai depois) e diz que não imprimiu", async () => {
  const { admin, chamadas } = bancoFalso((c) => {
    if (c.op === "insert") return { data: { id: "j2" } };
    if (c.op === "update") return { data: [{ id: "j2" }] };
    if (c.filtros.some(([, col]) => col === "metadata->>chave")) return { data: [] };
    return { data: { status: "pending" } };
  });
  const r = await imprimirPelaFila(admin, PEDIDO, { ...relogio(), esperarMs: 10_000 });
  assert(!r.ok);
  assert(!("aindaPodeSair" in r && r.aindaPodeSair));
  const cancelamento = chamadas.find((c) => c.op === "update");
  assertEquals((cancelamento?.valor as { status: string }).status, "cancelled");
  assert(cancelamento!.filtros.some(([n, col, v]) => n === "eq" && col === "status" && v === "pending"));
});

Deno.test("imprimirPelaFila: o PC pegou mas não terminou a tempo → 'pode sair em instantes', sem cancelar", async () => {
  const { admin, chamadas } = bancoFalso((c) => {
    if (c.op === "insert") return { data: { id: "j3" } };
    if (c.filtros.some(([, col]) => col === "metadata->>chave")) return { data: [] };
    return { data: { status: "processing" } };
  });
  const r = await imprimirPelaFila(admin, PEDIDO, { ...relogio(), esperarMs: 10_000 });
  assert(!r.ok && r.aindaPodeSair === true);
  assertEquals(chamadas.filter((c) => c.op === "update").length, 0);
});

Deno.test("imprimirPelaFila: falha do PC volta com o motivo dele", async () => {
  const { admin } = bancoFalso((c) => {
    if (c.op === "insert") return { data: { id: "j4" } };
    if (c.filtros.some(([, col]) => col === "metadata->>chave")) return { data: [] };
    return { data: { status: "failed", error: "a impressora está desligada ou fora do Wi-Fi", error_code: "provider_unavailable" } };
  });
  const r = await imprimirPelaFila(admin, PEDIDO, relogio());
  assertEquals(r, { ok: false, motivo: "a impressora está desligada ou fora do Wi-Fi" });
});

Deno.test("impressoraNoAr: sem cadastro, calado há mais de 3 min, impressora fora e no ar", async () => {
  const agora = new Date("2026-11-17T10:00:00Z");
  const com = (data: unknown) => bancoFalso(() => ({ data })).admin;
  assertStringIncludes((await impressoraNoAr(com(null), agora) as { motivo: string }).motivo, "ainda não foi instalado");
  const calado = await impressoraNoAr(com({ enabled: true, last_seen_at: "2026-11-17T09:50:00Z", estado: {} }), agora);
  assertStringIncludes((calado as { motivo: string }).motivo, "fora do ar desde 06:50");
  const fora = await impressoraNoAr(com({
    enabled: true, last_seen_at: "2026-11-17T09:59:30Z",
    estado: { providers: { [PROVEDOR_DA_IMPRESSORA]: { available: false, reason: "provider_unavailable:impressora_offline" } } },
  }), agora);
  assertEquals(fora, { ok: false, motivo: "a impressora está desligada ou fora do Wi-Fi" });
  const ok = await impressoraNoAr(com({ enabled: true, last_seen_at: "2026-11-17T09:59:30Z", estado: { providers: { [PROVEDOR_DA_IMPRESSORA]: { available: true } } } }), agora);
  assertEquals(ok, { ok: true });
  assertEquals(WORKER_DA_IMPRESSORA, "hbr-pc-print");
});

Deno.test("motivoDoWorker: código conhecido em palavras; desconhecido aparece", () => {
  assertEquals(motivoDoWorker("sem_sumatra"), "falta o programa de impressão (SumatraPDF) no PC do escritório");
  assertStringIncludes(motivoDoWorker("xpto"), "xpto");
});

Deno.test("fraseDoResultado: nunca diz que imprimiu o que não saiu", () => {
  assertEquals(fraseDoResultado("a via da OS-00136", { ok: true, situacao: "impresso", paginas: 2 }),
    "🖨️ Impresso: a via da OS-00136 (2 páginas). Está na impressora do escritório.");
  assertStringIncludes(fraseDoResultado("o orçamento", { ok: true, situacao: "impresso", paginas: 1 }, 3), "3 cópias");
  assertEquals(fraseDoResultado("o orçamento", { ok: false, motivo: "a impressora está sem papel" }),
    "Não consegui imprimir o orçamento: a impressora está sem papel.");
  assertStringIncludes(fraseDoResultado("x", { ok: false, motivo: "m", aindaPodeSair: true }), "ainda não confirmou");
  assertStringIncludes(fraseDoResultado("x", { ok: true, repetido: true }), "não repeti");
});
