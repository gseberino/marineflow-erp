// O vigia com a voz única LIGADA (secretário, Passo 4, P4.5, 20/10/2026), com um banco de mentira. O que se protege:
//   · o dono não recebe o "🔔 Alerta…": cada sinal pergunta ao portão (modo ligado) e só o acorde sai — sozinho, pela
//     fila, com o texto do ACORDE (sem emoji) e a chave aviso:<id>;
//   · "vence hoje"/orçamentos parados acabam, saldo/estoque/cota ficam guardados (nada sai);
//   · portão ilegível num sinal = esse sinal vai como sempre (o "🔔 Alerta…" só com ele) — nunca calar por erro;
//   · a NF-e por nota: a 1ª acorda, a 2ª (mesmo assunto no dia) fica guardada — sai uma mensagem só.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { falarAoDono, planoDoDono, type SinalDoVigia } from "./voz.ts";
import { avisoDaNfe, avisoDoVigia } from "../_shared/uma-voz/fontes.ts";
import type { Fala } from "../_shared/uma-voz/registrar.ts";

const DIA = "2026-10-21";
const AGORA = new Date("2026-10-21T14:05:00Z");
const DONO = "5547900009654";

// deno-lint-ignore no-explicit-any
function banco(decidir: (p: any) => any) {
  // deno-lint-ignore no-explicit-any
  const fila: any[] = [];
  // deno-lint-ignore no-explicit-any
  const portao: any[] = [];
  const admin = {
    from(t: string) {
      return { insert(l: unknown) { fila.push([t, l]); return Promise.resolve({ error: null }); } };
    },
    // deno-lint-ignore no-explicit-any
    rpc(nome: string, args: any) {
      portao.push([nome, args.p]);
      return Promise.resolve(decidir(args.p));
    },
  };
  return { admin, fila, portao };
}

const VENCE: SinalDoVigia = { texto: "💸 *1* recebível(is) vence(m) hoje — total R$ 5.237,99.", avisos: [avisoDoVigia("vence_hoje", DIA, "💸 vence hoje")] };
const SALDO: SinalDoVigia = { texto: "🏦 Extrato de C6: …", avisos: [avisoDoVigia("saldo_divergente", DIA, "🏦 Extrato de C6: …", "c6")] };
const NFES: SinalDoVigia = {
  texto: "❌ *2* NF-e rejeitada(s) nas últimas 24h.",
  avisos: [
    avisoDaNfe({ id: "n1", numero: 321, cliente: "MP MOTOR HOMES" }, "*A NF-e nº 321 (MP MOTOR HOMES) foi rejeitada.* Rejeição 539. Reemita pela OS-00120."),
    avisoDaNfe({ id: "n2", numero: 322, cliente: "Nelson" }, "*A NF-e nº 322 (Nelson) foi rejeitada.* Reemita pela OS."),
  ],
};

// o portão real decide pelo destino (acorde: 1º do assunto acorda; o 2º guarda); aqui o mesmo, à mão
function portaoDeMentira() {
  const acordados = new Set<string>();
  let n = 0;
  // deno-lint-ignore no-explicit-any
  return (p: any) => {
    n++;
    if (p.destino === "acaba") return { data: { ok: true, decisao: "acabar", id: `a${n}` }, error: null };
    if (p.destino !== "acorde") return { data: { ok: true, decisao: "guardar", id: `a${n}` }, error: null };
    if (acordados.has(p.assunto)) return { data: { ok: true, decisao: "guardar", id: `a${n}`, motivo: "assunto_ja_acordou_hoje" }, error: null };
    acordados.add(p.assunto);
    return { data: { ok: true, decisao: "acordar", id: `a${n}`, cartao: true }, error: null };
  };
}

const ALERTA = (linhas: string[]) => ["🔔 *Alerta HBR*", "", ...linhas].join("\n");

Deno.test("ligado: só o acorde sai (sozinho, pela fila, com o texto do acorde e a chave); o resto fica com as mensagens fixas", async () => {
  const b = banco(portaoDeMentira());
  const r = await falarAoDono(b.admin, { phone: DONO, sinais: [VENCE, SALDO, NFES], mensagem: ALERTA, agora: AGORA });
  assertEquals(r, { acordes: 1, como_hoje: 0, guardados: 2, acabados: 1, repetidos: 0, fora_da_fila: 0 });
  assertEquals(b.portao.map((x) => [x[0], x[1].modo, x[1].phone]), Array(4).fill(["aviso_registrar", "ligado", DONO]));
  assertEquals(b.fila.length, 1);
  const [tabela, linha] = b.fila[0];
  assertEquals([tabela, linha.phone_normalized, linha.source, linha.priority, linha.dedupe_key], ["whatsapp_send_queue", DONO, "ai_monitor", 1, "aviso:a3"]);
  assertStringIncludes(linha.message, "*A NF-e nº 321 (MP MOTOR HOMES) foi rejeitada.*");
  assertEquals(linha.message.includes("🔔"), false, "o acorde não é o alerta");
});

Deno.test("portão ilegível num sinal = esse sinal vai como sempre; os outros seguem a decisão", async () => {
  // deno-lint-ignore no-explicit-any
  const b = banco((p: any) => p.chave.startsWith("saldo_divergente") ? { data: null, error: { message: "permission denied" } } : portaoDeMentira()(p));
  const r = await falarAoDono(b.admin, { phone: DONO, sinais: [VENCE, SALDO], mensagem: ALERTA, agora: AGORA });
  assertEquals([r.como_hoje, r.acabados, r.acordes], [1, 1, 0]);
  assertEquals(b.fila.length, 1);
  assertEquals(b.fila[0][1].message, ALERTA(["🏦 Extrato de C6: …"]));
  assertEquals(b.fila[0][1].source, "ai_monitor");
});

Deno.test("planoDoDono (puro): erro e deixar vão como sempre; acordar sem id também; a linha não repete", () => {
  const f = (decisao: Fala["decisao"], acordou: string | null = null): Fala => ({ manda: decisao !== "guardar" && decisao !== "acabar" && decisao !== "repetido", cartao: false, acordou, decisao });
  const a = avisoDoVigia("estoque_divergente", DIA, "📦 estoque");
  const p = planoDoDono([
    { texto: "L1", falas: [{ aviso: a, fala: f("erro") }, { aviso: a, fala: f("erro") }] },
    { texto: "L2", falas: [{ aviso: a, fala: f("deixar") }] },
    { texto: "L3", falas: [{ aviso: { ...a, texto: null }, fala: f("acordar", "x1") }] },
    { texto: "L4", falas: [{ aviso: a, fala: f("acordar") }] },
    { texto: "L5", falas: [{ aviso: a, fala: f("repetido") }] },
  ]);
  assertEquals(p.comoHoje, ["L1", "L2", "L4"]);
  assertEquals(p.acordes, [{ id: "x1", texto: "L3" }], "sem texto do aviso, a linha de sempre");
  assertEquals(p.repetidos, 1);
});
