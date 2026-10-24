// Os modos da equipe e da diária (Fase 3, P4 — 24/10/2026) e a R10 que sai com a ficha da agenda.
//
// O que estes testes protegem:
//  1. modo_equipe e modo_diaria num SELECT à parte: o que falha nele (a coluna que ainda não existe) não toca os modos
//     da Fase 2 (lerModosDaAgenda continua lendo só modo_proposta e modo_vigia);
//  2. ilegível (erro, sem a linha, valor estranho, exceção) = desligado: a R10 continua como hoje;
//  3. a R10 sai SÓ com modo_equipe = 'ligado' (sombra e desligado = ela continua), com o texto do resumo;
//  4. o motor (index.ts): a rotina roda antes da vigia, com try/catch próprio, e a R10 lê os modos da equipe.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { EQUIPE_DESLIGADA, lerModosDaEquipe, R10_DESLIGADA, r10DesligadaPelaAgenda } from "./agenda-modos.ts";

const banco = (resp: unknown) => ({
  from: (t: string) => {
    assertEquals(t, "agenda_config");
    return { select: (c: string) => { assertEquals(c, "modo_equipe, modo_diaria"); return { maybeSingle: async () => resp }; } };
  },
});

Deno.test("modos da equipe: lidos num SELECT à parte; ilegível = desligado (a R10 fica como hoje)", async () => {
  const erro = await lerModosDaEquipe(banco({ data: null, error: { code: "42703", message: "column agenda_config.modo_diaria does not exist" } }));
  assertEquals([erro.equipe, erro.diaria, typeof erro.erro], ["desligado", "desligado", "string"]);
  const semLinha = await lerModosDaEquipe(banco({ data: null, error: null }));
  assertEquals([semLinha.equipe, semLinha.diaria, typeof semLinha.erro], ["desligado", "desligado", "string"]);
  const estranho = await lerModosDaEquipe(banco({ data: { modo_equipe: "LIGADÍSSIMO", modo_diaria: 3 }, error: null }));
  assertEquals(estranho, { equipe: "desligado", diaria: "desligado" });
  const ok = await lerModosDaEquipe(banco({ data: { modo_equipe: " Ligado ", modo_diaria: "sombra" }, error: null }));
  assertEquals(ok, { equipe: "ligado", diaria: "sombra" });
  const lancou = await lerModosDaEquipe({ from: () => { throw new Error("conexão caiu"); } });
  assertEquals([lancou.equipe, lancou.diaria, lancou.erro], ["desligado", "desligado", "conexão caiu"]);
  assertEquals(EQUIPE_DESLIGADA, { equipe: "desligado", diaria: "desligado" });
});

Deno.test("R10: sai só com a ficha da agenda ligada (modo_equipe = 'ligado'); sombra e desligado = continua", () => {
  assertEquals(r10DesligadaPelaAgenda({ equipe: "ligado" }), R10_DESLIGADA);
  assertEquals(R10_DESLIGADA, "desligada: a ficha da agenda substitui");
  assertEquals(r10DesligadaPelaAgenda({ equipe: "sombra" }), null);
  assertEquals(r10DesligadaPelaAgenda({ equipe: "desligado" }), null);
  assertEquals(r10DesligadaPelaAgenda(EQUIPE_DESLIGADA), null);
});

// O motor (index.ts sobe o servidor ao ser importado): pelo texto da fonte.
Deno.test("motor: a rotina roda antes da vigia, com try/catch próprio; a R10 lê os modos da equipe antes de enviar", async () => {
  const fonte = (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\r\n/g, "\n");
  const material = fonte.indexOf("agendaMaterial = await sincronizarMaterialDaAgenda(db);");
  const rotina = fonte.indexOf("agendaRotina = await rodarRotinaDaAgenda(db, new Date());");
  const vigia = fonte.indexOf("agendaVigia = await vigiarAgenda(db, new Date());");
  assertEquals(material > 0 && rotina > material && vigia > rotina, true);
  const bloco = fonte.slice(fonte.lastIndexOf("let agendaRotina", rotina), vigia);
  assertEquals(bloco.includes("try {") && bloco.includes("} catch (e) {"), true);
  assertEquals(fonte.includes("agenda_rotina: agendaRotina"), true);
  // a R10: o interruptor vem antes de qualquer leitura de OS ou da fila
  const r10 = fonte.slice(fonte.indexOf("async function runTechnicianReminders"), fonte.indexOf("async function processReminders"));
  const gate = r10.indexOf("r10DesligadaPelaAgenda(await lerModosDaEquipe(db))");
  assertEquals(gate > 0 && gate < r10.indexOf("service_orders") && gate < r10.indexOf("whatsapp_send_queue"), true);
});
