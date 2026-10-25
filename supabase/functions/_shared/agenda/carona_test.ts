// A carona da agenda (Fase 3, P6; spec-fase3.md §9.5): de quais OS o turno falou (puro), a RPC que decide (agenda_carona)
// e o texto junto no fim da resposta. O banco é falso aqui: o que ele decide é provado em
// supabase/tests/agenda_fase3_acompanhamento.sql (K).
// Rodar com: deno test --allow-all supabase/functions/_shared/agenda/carona_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { aplicarCarona, caronaDoTurno, comCarona, juntarCarona, osDoJob, osDoTurno, turnoSemCarona } from "./carona.ts";

const CARONA = 'Aproveitando: Nelson (OS-00112): "Painel Touch de…" tinha previsão para ter 03/11. Chegou?';

/** Um banco falso: grava as chamadas e devolve o que o teste mandar (ou lança). */
function banco(resposta: { data?: unknown; error?: unknown } | Error) {
  const chamadas: Array<{ fn: string; params: Record<string, unknown> }> = [];
  return {
    chamadas,
    rpc(fn: string, params: Record<string, unknown>) {
      chamadas.push({ fn, params });
      if (resposta instanceof Error) return Promise.reject(resposta);
      return Promise.resolve({ data: resposta.data ?? null, error: resposta.error ?? null });
    },
  };
}

Deno.test("osDoTurno: nenhuma OS, uma (dita e mostrada, sem repetir) e duas", () => {
  assertEquals(osDoTurno([]), []);
  assertEquals(osDoTurno(null), []);
  assertEquals(osDoTurno([{ name: "agenda_ver", args: { foco: "plano" }, result: { texto: "…" } }]), []);
  assertEquals(
    osDoTurno([
      { name: "agenda_ver", args: { os: "Nelson" }, result: { texto: "Nelson (OS-00112): …" } },
      { name: "agenda_ver", args: { os: "Nelson", foco: "material" }, result: {} },
    ]),
    ["Nelson"],
  );
  assertEquals(
    osDoTurno([
      { name: "get_service_order", args: { service_order_id: "OS-00112" }, result: { os_id: "05000000-0000-4000-8000-000000000112" } },
      { name: "material_informar", args: { os: "Lenine", itens: ["painel"] }, result: { ok: true } },
    ]),
    ["OS-00112", "05000000-0000-4000-8000-000000000112", "Lenine"],
  );
});

Deno.test("osDoTurno: só a lista fechada de ferramentas; listas (registrar_diaria) e números entram; texto vazio não", () => {
  assertEquals(osDoTurno([{ name: "create_task", args: { os: "Nelson" } }, { name: "search_clients", args: { os: "Lenine" } }]), []);
  assertEquals(osDoTurno([{ name: "registrar_diaria", args: { freelancer: "Roberto", os: ["OS-00069", "  "] } }]), ["OS-00069"]);
  assertEquals(osDoTurno([{ name: "os_planejar", args: { os: 112 } }]), ["112"]);
  assertEquals(osDoTurno([{ name: "schedule_service_order", args: { p_os: "Vanderlei" } }]), ["Vanderlei"]);
  // pela ferramenta_extra (perfil enxuto do admin) vale a ferramenta de dentro
  assertEquals(
    osDoTurno([{ name: "ferramenta_extra", args: { nome: "material_informar", argumentos: { os: "Nelson", itens: ["painel"] } }, result: {} }]),
    ["Nelson"],
  );
  assertEquals(osDoTurno([{ name: "ferramenta_extra", args: { nome: "create_task", argumentos: { os: "Nelson" } } }]), []);
});

Deno.test("osDoJob: as OS que o erp-mcp guardou no job do Claude Max", () => {
  assertEquals(osDoJob({ os_do_turno: ["Nelson", "OS-00112"] }), ["Nelson", "OS-00112"]);
  assertEquals(osDoJob({}), []);
  assertEquals(osDoJob(null), []);
  assertEquals(osDoJob({ os_do_turno: "Nelson" }), []);
});

Deno.test("turnoSemCarona: cartão de sim, opções, fluxo ou erro calam a carona", () => {
  assertEquals(turnoSemCarona({}), false);
  assertEquals(turnoSemCarona(null), false);
  assertEquals(turnoSemCarona({ proposal: { title: "Registrar diária" } }), true);
  assertEquals(turnoSemCarona({ options: { question: "Qual?", options: [] } }), true);
  assertEquals(turnoSemCarona({ fluxo: { codigo: "CMP-0001" } }), true);
  assertEquals(turnoSemCarona({ error: "falhou" }), true);
});

Deno.test("caronaDoTurno: chama agenda_carona com o autor, as OS como vieram e o canal; devolve o texto do banco", async () => {
  const b = banco({ data: { pergunta_id: "p1", texto: CARONA } });
  const c = await caronaDoTurno(b, "aa01", ["Nelson"], {}, { canal: "painel", hoje: "2026-11-04", agora: "2026-11-04T10:00:00-03:00" });
  assertEquals(c, CARONA);
  assertEquals(b.chamadas, [{
    fn: "agenda_carona",
    params: { p_autor: "aa01", p_os: ["Nelson"], p_canal: "painel", p_hoje: "2026-11-04", p_agora: "2026-11-04T10:00:00-03:00" },
  }]);
});

Deno.test("caronaDoTurno: com cartão de sim não chama o banco; sem OS também não", async () => {
  const b = banco({ data: { texto: CARONA } });
  assertEquals(await caronaDoTurno(b, "aa01", ["Nelson"], { proposal: { title: "x" } }), null);
  assertEquals(await caronaDoTurno(b, "aa01", [], {}), null);
  assertEquals(await caronaDoTurno(b, "", ["Nelson"], {}), null);
  assertEquals(b.chamadas.length, 0);
});

Deno.test("caronaDoTurno: o banco diz null, erra ou lança = sem carona (a resposta sai igual)", async () => {
  assertEquals(await caronaDoTurno(banco({ data: null }), "aa01", ["Nelson"], {}), null);
  assertEquals(await caronaDoTurno(banco({ error: { message: "function agenda_carona does not exist" } }), "aa01", ["Nelson"], {}), null);
  assertEquals(await caronaDoTurno(banco(new Error("rede")), "aa01", ["Nelson"], {}), null);
  // texto que não é da carona não entra
  assertEquals(await caronaDoTurno(banco({ data: { texto: "Outra coisa" } }), "aa01", ["Nelson"], {}), null);
});

Deno.test("comCarona: o texto do turno ganha a carona no fim, num parágrafo; erro da RPC devolve o texto igual", async () => {
  const t = "O Nelson está esperando o painel.";
  assertEquals(await comCarona(banco({ data: { texto: CARONA } }), "aa01", ["Nelson"], t, {}), `${t}\n\n${CARONA}`);
  assertEquals(await comCarona(banco({ error: { message: "x" } }), "aa01", ["Nelson"], t, {}), t);
  assertEquals(await comCarona(banco(new Error("rede")), "aa01", ["Nelson"], t, {}), t);
  assertEquals(await comCarona(banco({ data: { texto: CARONA } }), "aa01", ["Nelson"], t, { options: {} }), t);
});

Deno.test("juntarCarona e aplicarCarona: no fim da resposta e na última mensagem do assistente, uma vez", () => {
  assertEquals(juntarCarona("Oi.  \n", CARONA), `Oi.\n\n${CARONA}`);
  assertEquals(juntarCarona("", CARONA), CARONA);
  const turno = {
    message: { content: "O Nelson está esperando o painel." },
    messages: [
      { role: "user", content: [{ type: "text", text: "e o Nelson?" }] },
      { role: "assistant", content: [{ type: "tool_use", id: "t1" }] },
      { role: "user", content: [{ type: "tool_result", tool_use_id: "t1" }] },
      { role: "assistant", content: [{ type: "text", text: "O Nelson está esperando o painel." }] },
    ],
  };
  aplicarCarona(turno, CARONA);
  assertEquals(turno.message.content, `O Nelson está esperando o painel.\n\n${CARONA}`);
  assertEquals((turno.messages[3].content as Array<{ text: string }>)[0].text, `O Nelson está esperando o painel.\n\n${CARONA}`);
  // as outras mensagens ficam como estavam
  assertEquals(turno.messages[1].content, [{ type: "tool_use", id: "t1" }]);
  const soTexto = { message: { content: "x" }, messages: [{ role: "assistant", content: "x" }] };
  aplicarCarona(soTexto, CARONA);
  assertEquals(soTexto.messages[0].content, `x\n\n${CARONA}`);
});
