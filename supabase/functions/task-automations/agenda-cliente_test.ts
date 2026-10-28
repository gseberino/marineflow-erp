// A rodada da mensagem ao cliente da Agenda de Produção no motor de 15 min (Fase 5, P3 — 27/10/2026).
//
// O que estes testes protegem:
//  1. chama agenda_cliente_vigiar com o dia de BRASÍLIA (às 22 h ainda é hoje) e a hora, SEMPRE (até com o modo
//     desligado: o passo "fila" do banco é o que faz o "parar tudo" valer no tique seguinte), e devolve o resumo;
//  2. NUNCA lança: erro da RPC (ou a RPC que lança) vira { erro } e uma linha em app_error_logs (task-automations /
//     agenda:cliente-vigia), e as regras seguem;
//  3. NADA vai ao cliente daqui: a mensagem-modelo é registrada e enfileirada pelo banco (o modo, as ondas, a aprovação, a
//     janela, o teto, a revalidação conferidos lá). O TS só leva os acordes ao dono, e só quando o banco os devolve;
//  4. o acorde vai pelo MESMO envio da vigia (chave agenda:<ação>, só das 08 às 20h sem o portão, a ação contada);
//  5. index.ts chama o passo depois da vigia e antes das regras, com try/catch próprio, e o põe no resumo.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { vigiarClienteDaAgenda } from "./agenda-cliente.ts";
import { PORTAO_DESLIGADO } from "../_shared/uma-voz/registrar.ts";

interface Cena {
  rodada?: { data: unknown; error: unknown } | "lança";
  fila?: { code?: string; message?: string } | null;
}

function mkDb(cena: Cena) {
  const rpcs: Array<{ nome: string; args: Record<string, unknown> }> = [];
  const fila: Array<Record<string, unknown>> = [];
  const db = {
    from: (tabela: string) => {
      // só o acorde ao dono (source agenda) entra na fila por aqui
      if (tabela !== "whatsapp_send_queue") throw new Error(`tabela inesperada: ${tabela}`);
      return {
        insert: (linha: Record<string, unknown>) => {
          fila.push(linha);
          return Promise.resolve({ error: cena.fila ?? null });
        },
      };
    },
    rpc: (nome: string, args: Record<string, unknown>) => {
      rpcs.push({ nome, args });
      if (nome === "agenda_cliente_vigiar") {
        if (cena.rodada === "lança") return Promise.reject(new Error("conexão caiu"));
        return Promise.resolve(cena.rodada ?? { data: { rodou: false, modo: "desligado", fila: { canceladas: 0 }, acordes: [] }, error: null });
      }
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  const chamadas = (nome: string) => rpcs.filter((r) => r.nome === nome).map((r) => r.args);
  return { db, rpcs, fila, chamadas };
}

const DONO = { id: "u-dono", phone: "5547999990000" };
// a voz única desligada: o acorde vai "como sempre" (fila direta, 08–20h)
const deps = (dono: typeof DONO | null = DONO) => ({
  lerPortao: () => Promise.resolve({ ...PORTAO_DESLIGADO }),
  lerDono: () => Promise.resolve(dono),
});

const ACORDE = {
  chave: "agenda:acao-5", assunto: "cliente:os-112", acao_id: "acao-5", os: "os-112", perda_em: "2026-11-03",
  texto: "O aviso de atraso do Nelson precisa de você hoje (ter 03/11 → qui 12 a sex 13/11): recomendo ligar.",
};

// sex 30/10/2026 22:30 de Brasília = 31/10 01:30 UTC: o dia ainda é 30/10.
const AS_22H30_BR = new Date("2026-10-31T01:30:00Z");
// sex 30/10/2026 10:00 de Brasília (dentro da janela de acordar).
const AS_10H_BR = new Date("2026-10-30T13:00:00Z");

Deno.test("cliente: chama agenda_cliente_vigiar com o dia de Brasília e a hora, e devolve o resumo", async () => {
  const { db, chamadas, fila } = mkDb({
    rodada: { data: { rodou: true, modo: "sombra", tipos_ligados: [], erros: 0, falhas: [],
                      contagens: { fila: { enfileiradas: 0 }, confirmar: { unico: 1 } }, acordes: [] }, error: null },
  });
  const r = await vigiarClienteDaAgenda(db, AS_22H30_BR, deps());
  assertEquals(chamadas("agenda_cliente_vigiar"), [{ p_hoje: "2026-10-30", p_agora: "2026-10-31T01:30:00.000Z" }]);
  assertEquals(r, {
    rodou: true, modo: "sombra", tipos_ligados: [], erros: 0, falhas: [],
    contagens: { fila: { enfileiradas: 0 }, confirmar: { unico: 1 } },
  });
  // em sombra a mensagem fica só registrada no banco: o TS não põe nada na fila
  assertEquals(fila, []);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("cliente: com o modo desligado o banco ainda é chamado (o passo fila roda sempre) e nada mais acontece", async () => {
  const { db, rpcs, fila } = mkDb({});
  const r = await vigiarClienteDaAgenda(db, AS_10H_BR, deps());
  assertEquals([r.rodou, r.modo, r.contagens], [false, "desligado", { fila: { canceladas: 0 } }]);
  assertEquals(rpcs.map((x) => x.nome), ["agenda_cliente_vigiar"]);
  assertEquals(fila, []);
});

Deno.test("cliente: erro da RPC nunca lança — vira { erro } e app_error_logs (task-automations / agenda:cliente-vigia)", async () => {
  for (const rodada of [{ data: null, error: { code: "57014", message: "canceling statement due to statement timeout" } },
                        "lança" as const]) {
    const { db, chamadas, fila } = mkDb({ rodada });
    const r = await vigiarClienteDaAgenda(db, AS_10H_BR, deps());
    assertEquals(typeof r.erro, "string");
    const logs = chamadas("log_app_error");
    assertEquals(logs.length, 1);
    assertEquals([logs[0].p_context, logs[0].p_action], ["task-automations", "agenda:cliente-vigia"]);
    assertStringIncludes(String(logs[0].p_message), "rodada do cliente:");
    assertEquals(fila, []);
  }
});

// Correção C2 da Fase 5 (regressão B2): o código publicado antes da migration 20261028100300 não enche app_error_logs a
// cada 15 min (eram 96 linhas por dia): a função ausente (PGRST202 do PostgREST, 42883 do Postgres) cala, como o passo do
// material sem a Fase 4.
Deno.test("cliente: sem a função no banco (PGRST202/42883), o passo é pulado calado — sem app_error_logs e sem nada na fila", async () => {
  for (const code of ["PGRST202", "42883"]) {
    const { db, chamadas, fila } = mkDb({ rodada: { data: null, error: { code, message: "Could not find the function agenda_cliente_vigiar" } } });
    const r = await vigiarClienteDaAgenda(db, AS_10H_BR, deps());
    assertEquals(r, { pulado: "a migration 20261028100300 ainda não está no banco" });
    assertEquals(chamadas("agenda_cliente_vigiar").length, 1);
    assertEquals(chamadas("log_app_error"), []);
    assertEquals(fila, []);
  }
});

Deno.test("cliente: o passo que falhou no banco volta em erros/falhas (o banco já registrou) e não gera outra linha aqui", async () => {
  const { db, chamadas } = mkDb({
    rodada: { data: { rodou: true, modo: "ligado", erros: 1, falhas: [{ passo: "atraso", sqlstate: "22023" }], contagens: {}, acordes: [] },
              error: null },
  });
  const r = await vigiarClienteDaAgenda(db, AS_10H_BR, deps());
  assertEquals([r.erros, r.falhas], [1, [{ passo: "atraso", sqlstate: "22023" }]]);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("cliente: o acorde que o banco devolve vai ao dono pelo envio da vigia (chave agenda:<ação>) e a ação fica contada", async () => {
  const { db, chamadas, fila } = mkDb({ rodada: { data: { rodou: true, modo: "ligado", erros: 0, falhas: [], acordes: [ACORDE] }, error: null } });
  const r = await vigiarClienteDaAgenda(db, AS_10H_BR, deps());
  assertEquals(r.acordes, { enviados: 1, guardados: 0, fora_da_janela: 0, nao_saiu: 0 });
  assertEquals(fila.length, 1);
  assertEquals([fila[0].phone_normalized, fila[0].dedupe_key, fila[0].source, fila[0].message],
               [DONO.phone, "agenda:acao-5", "agenda", ACORDE.texto]);
  assertEquals(chamadas("agenda_acorde_registrado").map((a) => a.p_acao), ["acao-5"]);
});

Deno.test("cliente: o acorde fora das 08–20h não sai (o fechamento conta); sem dono com WhatsApp, nada sai", async () => {
  const { db, fila } = mkDb({ rodada: { data: { rodou: true, erros: 0, acordes: [ACORDE] }, error: null } });
  const r = await vigiarClienteDaAgenda(db, AS_22H30_BR, deps());
  assertEquals(r.acordes, { enviados: 0, guardados: 0, fora_da_janela: 1, nao_saiu: 0 });
  assertEquals(fila, []);
  const semDono = mkDb({ rodada: { data: { rodou: true, erros: 0, acordes: [ACORDE] }, error: null } });
  const r2 = await vigiarClienteDaAgenda(semDono.db, AS_10H_BR, deps(null));
  assertEquals(r2.acordes, { enviados: 0, guardados: 0, fora_da_janela: 0, nao_saiu: 1 });
  assertEquals(semDono.fila, []);
});

Deno.test("cliente: o TS nunca enfileira mensagem ao cliente (source agenda-cliente é só do banco)", async () => {
  const fonte = await Deno.readTextFile(new URL("./agenda-cliente.ts", import.meta.url));
  // sem os comentários (// e /** */): o que conta é o código
  const codigo = fonte.replace(/\/\*[\s\S]*?\*\//g, "").split(/\r?\n/).filter((l) => !l.trim().startsWith("//")).join("\n");
  assertEquals(codigo.includes("agenda-cliente"), false);
  assertEquals(/from\(["']whatsapp_send_queue["']\)/.test(codigo), false);
  // e não lê o modo antes de chamar (o banco decide; o passo "fila" roda até desligado)
  assertEquals(codigo.includes("agenda_config"), false);
});

// O motor (index.ts sobe o servidor ao ser importado): pelo texto da fonte.
Deno.test("motor: a rodada do cliente roda depois da vigia e antes das regras, com try/catch próprio, e vai ao resumo", async () => {
  const fonte = (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\r\n/g, "\n");
  const vigia = fonte.indexOf("agendaVigia = await vigiarAgenda(db, new Date());");
  const cliente = fonte.indexOf("agendaClienteVigia = await vigiarClienteDaAgenda(db, new Date());");
  const regras = fonte.indexOf("const rules = await runRules(db, settings);");
  assertEquals(vigia > 0 && cliente > vigia && regras > cliente, true);
  const bloco = fonte.slice(fonte.lastIndexOf("let agendaClienteVigia", cliente), regras);
  assertEquals(bloco.includes("try {") && bloco.includes("} catch (e) {"), true);
  assertEquals(fonte.includes("agenda_cliente_vigia: agendaClienteVigia"), true);
  // a R15 lê o modo do cliente antes das regras (o mesmo objeto de modos)
  const runRules = fonte.slice(fonte.indexOf("async function runRules"), fonte.indexOf("for (const rule of RULES)"));
  assertEquals(runRules.includes("modos.cliente = await lerModosDoCliente(db);"), true);
});
