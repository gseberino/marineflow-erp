// A via do técnico com a ficha das 19:30: quando vai, quando não vai.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  decidirAVia,
  FALHAS_ATE_DESISTIR,
  horaEmBrasilia,
  itensPendentes,
  ORIGENS_QUE_ENTREGAM,
  rotuloDoDia,
  ultimaViaEntregue,
  viaDaAgenda,
} from "./via-da-agenda.ts";

const F1 = { id: "f1", payee_id: "alex", dia: "2026-11-26", fila_id: "q1", alocacao_ids: ["a1", "a2"] };
const F2 = { id: "f2", payee_id: "alex", dia: "2026-11-27", fila_id: "q2", alocacao_ids: ["a3"] };
const OS = new Map([["a1", "os119"], ["a2", "os119"], ["a3", "os119"], ["r1", "os200"]]);

Deno.test("só a ficha que a fila ENTREGOU leva a via; uma OS por ficha mesmo com manhã e tarde", () => {
  const { fazer } = itensPendentes([F1, F2], new Set(["q1"]), OS, []);
  assertEquals(fazer.map((i) => `${i.ficha.id}:${i.os}`), ["f1:os119"]);
});

Deno.test("ficha com via enviada ou pulada não volta; falhou volta até desistir", () => {
  const entregues = new Set(["q1", "q2"]);
  const enviada = [{ ficha_id: "f1", service_order_id: "os119", estado: "enviado" }];
  assertEquals(itensPendentes([F1, F2], entregues, OS, enviada).fazer.map((i) => i.ficha.id), ["f2"]);
  const pulada = [{ ficha_id: "f1", service_order_id: "os119", estado: "pulado" }];
  assertEquals(itensPendentes([F1], entregues, OS, pulada).fazer.length, 0);
  const falhou = Array.from({ length: FALHAS_ATE_DESISTIR - 1 }, () => ({ ficha_id: "f1", service_order_id: "os119", estado: "falhou" }));
  assertEquals(itensPendentes([F1], entregues, OS, falhou).fazer.length, 1);
  const desiste = [...falhou, { ficha_id: "f1", service_order_id: "os119", estado: "falhou" }];
  const r = itensPendentes([F1], entregues, OS, desiste);
  assertEquals([r.fazer.length, r.desistir.length], [0, 1]);
});

Deno.test("reserva não é dia de trabalho: alocação fora do mapa (reserva) não gera via", () => {
  const soReserva = { ...F1, alocacao_ids: ["reserva-x"] };
  assertEquals(itensPendentes([soReserva], new Set(["q1"]), OS, []).fazer.length, 0);
});

// A impressão (porte da via v2, F0): v<versão do desenho>.d<versão do dado>.<dado>.<papel>. Só o DADO diz se a OS mudou.
const EM_25_11 = "2026-11-25T22:45:00Z";
const ultima = (impressao: string | null) => ({ impressao, criado_em: EM_25_11 });

Deno.test("1º dia: manda, dizendo para que dia", () => {
  assertEquals(decidirAVia(null, "v2.d1.dado1.papel1", "2026-11-26", false), { acao: "mandar", complemento: "Para qui 26/11, junto da ficha." });
});

Deno.test("mesma versão já recebida (pela agenda ou pelo dono, à equipe): não repete", () => {
  const r = decidirAVia(ultima("v2.d1.dado1.papel1"), "v2.d1.dado1.papel1", "2026-11-27", false);
  assertEquals(r, { acao: "pular", motivo: "já recebeu esta via em 25/11" });
});

Deno.test("a OS mudou (dado e papel diferentes): manda de novo, dizendo que substitui a anterior", () => {
  const r = decidirAVia(ultima("v2.d1.dado1.papel1"), "v2.d1.dado2.papel2", "2026-11-30", true);
  assertEquals(r, {
    acao: "mandar",
    complemento: "A OS mudou desde a via de 25/11: esta substitui a anterior. Só os seus serviços e os sem responsável.",
  });
});

Deno.test("última no formato antigo (o hash do HTML, 'h1→h2' de antes): manda com a frase neutra, nunca 'a OS mudou'", () => {
  assertEquals(decidirAVia(ultima("772aau"), "v2.d1.dado1.papel1", "2026-11-30", false), {
    acao: "mandar",
    complemento: "Esta via substitui a de 25/11.",
  });
  // registro sem impressão também é legado
  assertEquals(decidirAVia(ultima(null), "v2.d1.dado1.papel1", "2026-11-30", true).acao, "mandar");
});

Deno.test("outro contrato do dado (VERSAO_DO_DADO subiu): manda com a frase neutra", () => {
  assertEquals(decidirAVia(ultima("v2.d1.dado1.papel1"), "v2.d2.dadoX.papel1", "2026-11-30", false), {
    acao: "mandar",
    complemento: "Esta via substitui a de 25/11.",
  });
});

Deno.test("desenho novo (versão diferente) com o dado igual: pula — mudou só a folha, a OS não", () => {
  assertEquals(decidirAVia(ultima("v2.d1.dado1.papel1"), "v3.d1.dado1.papel9", "2026-11-30", false), {
    acao: "pular",
    motivo: "via em formato novo; a OS não mudou desde 25/11",
  });
});

Deno.test("mesma versão, papel diferente e dado igual: pula (a regra do papel mudou, a OS não)", () => {
  assertEquals(decidirAVia(ultima("v2.d1.dado1.papel1"), "v2.d1.dado1.papel2", "2026-11-30", false), {
    acao: "pular",
    motivo: "a regra do papel mudou; a OS não",
  });
});

Deno.test("mesma versão, papel igual e dado diferente: pula (a OS mudou só no que não vai ao papel)", () => {
  assertEquals(decidirAVia(ultima("v2.d1.dado1.papel1"), "v2.d1.dado2.papel1", "2026-11-30", false), {
    acao: "pular",
    motivo: "a OS mudou só no que não vai ao papel",
  });
});

Deno.test("versão diferente e dado diferente: manda 'a OS mudou'", () => {
  assertEquals(decidirAVia(ultima("v2.d1.dado1.papel1"), "v3.d1.dado2.papel1", "2026-11-30", false), {
    acao: "mandar",
    complemento: "A OS mudou desde a via de 25/11: esta substitui a anterior.",
  });
});

// ─── A última via ENTREGUE: o "para si" não conta (F0.1) ─────────────────────────────────────────

/** Banco falso de via_tecnico_envios: aplica eq/in/order/limit e registra a cadeia de chamadas. */
function bancoDeEnvios(linhas: Array<Record<string, unknown>>) {
  const cadeia: string[] = [];
  return {
    cadeia,
    from: (tabela: string) => {
      cadeia.push(`from:${tabela}`);
      let sel = [...linhas];
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q,
        eq: (c: string, v: unknown) => { cadeia.push(`eq:${c}`); sel = sel.filter((l) => l[c] === v); return q; },
        in: (c: string, vs: unknown[]) => { cadeia.push(`in:${c}:${vs.join(",")}`); sel = sel.filter((l) => vs.includes(l[c])); return q; },
        order: (c: string, o: { ascending: boolean }) => {
          sel.sort((a, b) => String(a[c]).localeCompare(String(b[c])) * (o.ascending ? 1 : -1));
          return q;
        },
        limit: (n: number) => { sel = sel.slice(0, n); return q; },
        maybeSingle: () => Promise.resolve({ data: sel[0] ?? null, error: null }),
      };
      return q;
    },
  };
}

const ENVIO = { payee_id: "alex", service_order_id: "os119", estado: "enviado", impressao: "v2.d1.dado1.papel1" };

Deno.test("para si com o payee_id do Alex (o dono pediu a via do Alex para ele mesmo): não conta, a agenda MANDA", async () => {
  const db = bancoDeEnvios([{ ...ENVIO, origem: "para_si", criado_em: "2026-11-25T10:00:00Z" }]);
  const ult = await ultimaViaEntregue(db, "alex", "os119");
  assertEquals(ult, null);
  assertEquals(db.cadeia.includes("in:origem:agenda,assistente"), true);
  // com a mesma impressão, antes do conserto, pulava com "já recebeu"
  assertEquals(decidirAVia(ult, "v2.d1.dado1.papel1", "2026-11-26", false).acao, "mandar");
});

Deno.test("a via que a agenda ou o dono mandou À EQUIPE conta; a mais recente vale", async () => {
  const db = bancoDeEnvios([
    { ...ENVIO, origem: "agenda", criado_em: "2026-11-20T22:45:00Z", impressao: "v2.d1.velho.papel0" },
    { ...ENVIO, origem: "assistente", criado_em: "2026-11-25T22:45:00Z" },
    { ...ENVIO, origem: "para_si", criado_em: "2026-11-26T10:00:00Z", impressao: "v2.d1.outro.papel9" },
    { ...ENVIO, origem: "agenda", estado: "falhou", criado_em: "2026-11-27T10:00:00Z" },
  ]);
  const ult = await ultimaViaEntregue(db, "alex", "os119");
  assertEquals(ult?.criado_em, "2026-11-25T22:45:00Z");
  assertEquals(decidirAVia(ult, "v2.d1.dado1.papel1", "2026-11-28", false), { acao: "pular", motivo: "já recebeu esta via em 25/11" });
  assertEquals([...ORIGENS_QUE_ENTREGAM], ["agenda", "assistente"]);
});

Deno.test("leitura da última via que falha lança (viaDaAgenda registra o erro e não manda às cegas)", async () => {
  const quebrado = {
    from: () => {
      // deno-lint-ignore no-explicit-any
      const q: any = { select: () => q, eq: () => q, in: () => q, order: () => q, limit: () => q,
        maybeSingle: () => Promise.resolve({ data: null, error: { message: "timeout" } }) };
      return q;
    },
  };
  let erro = "";
  try { await ultimaViaEntregue(quebrado, "alex", "os119"); } catch (e) { erro = (e as Error).message; }
  assertEquals(erro, "última via: timeout");
});

Deno.test("hora e dia em Brasília", () => {
  assertEquals(horaEmBrasilia(new Date("2026-11-25T22:45:00Z")), 19);
  assertEquals(horaEmBrasilia(new Date("2026-11-25T23:00:00Z")), 20);
  assertEquals(rotuloDoDia("2026-11-28"), "sáb 28/11");
});

Deno.test("desligada pela chave ou fora da janela: nem lê o banco", async () => {
  const semBanco = { from: () => { throw new Error("não devia ler"); } };
  assertEquals(await viaDaAgenda(semBanco, { via_tecnico_na_agenda: "desligado" }, new Date("2026-11-25T22:45:00Z")), { rodou: false, motivo: "desligada" });
  // 21h de Brasília: o whatsapp-send recusaria (janela 8h–20h)
  assertEquals(await viaDaAgenda(semBanco, {}, new Date("2026-11-26T00:00:00Z")), { rodou: false, motivo: "fora da janela" });
  assertEquals(await viaDaAgenda(semBanco, {}, new Date("2026-11-26T10:59:00Z")), { rodou: false, motivo: "fora da janela" });
});
