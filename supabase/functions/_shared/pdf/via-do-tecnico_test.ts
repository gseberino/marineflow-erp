// A via de cada pessoa (decisão do dono, 13/11/2026: só os serviços dela) e a impressão digital que a
// agenda usa para não mandar a mesma via duas vezes.
import { assert, assertEquals, assertNotEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type DadosDaVia,
  htmlDaVia,
  impressaoDaVia,
  montarViaDoTecnico,
  nomeDoArquivoDaVia,
  recorteDaPessoa,
  type ServiceOrderStep,
} from "./via-do-tecnico.ts";

const ALEX = { id: "p-alex", nome: "Alex Gonçalves Machado" };
const ROBERTO = { id: "p-roberto", nome: "Roberto Daniel" };

function passo(over: Partial<ServiceOrderStep>): ServiceOrderStep {
  return {
    id: "s", service_order_id: "os1", service_order_service_id: null, template_id: null, seq: 1,
    block: "Bloco", block_key: null, block_note: null, title: "Passo", detail: null, kind: "do", mode: "do_confirm",
    standard_minutes: null, is_killer: false, requires_photo: false, requires_measure: null, measure_unit: null,
    measure_value: null, status: "pending", na_reason: null, blocked_reason_code: null, blocked_note: null,
    assigned_user_id: null, started_at: null, completed_at: null, actual_minutes: null, origin: "manual", notes: null,
    ...over,
  };
}

function dados(over: Partial<DadosDaVia> = {}): DadosDaVia {
  return {
    serviceOrderId: "os1",
    header: { orderNumber: "OS-00119", clientName: "Lenine", assetName: "Itapoã", assetType: "Motorhome", scheduledAt: "2026-11-26T11:00:00Z" },
    empresa: { nome: "HBR", telefone: "(47) 3333-0000" },
    linhas: [
      { id: "l1", name_snapshot: "Instalação do inversor", responsavel_payee_id: ALEX.id },
      { id: "l2", name_snapshot: "Troca das baterias", responsavel_payee_id: ROBERTO.id },
      { id: "l3", name_snapshot: "Teste final", responsavel_payee_id: null },
    ],
    passos: [
      passo({ id: "a", seq: 1, title: "Passo do inversor", service_order_service_id: "l1", block: "Inversor" }),
      passo({ id: "b", seq: 2, title: "Passo das baterias", service_order_service_id: "l2", block: "Baterias" }),
      passo({ id: "c", seq: 3, title: "Passo geral", block: "Geral" }),
    ],
    materiais: [
      { id: "m1", quantity: 1, notes: null, service_order_service_id: "l1", products: { name: "Inversor 3000W", sku: null, unit: "un" } },
      { id: "m2", quantity: 4, notes: null, service_order_service_id: "l2", products: { name: "Bateria lítio", sku: null, unit: "un" } },
      { id: "m3", quantity: 2, notes: null, service_order_service_id: null, products: { name: "Abraçadeira", sku: null, unit: "pc" } },
    ],
    levantamento: [{ seq: 1, question_snapshot: "Foto do quadro", answer_value: "ok", photo_path: "os1/quadro.jpg" }],
    seguranca: [],
    nomesDosResponsaveis: { [ALEX.id]: ALEX.nome, [ROBERTO.id]: ROBERTO.nome },
    ...over,
  };
}

Deno.test("recorte: as linhas da pessoa e as sem responsável; as de outra pessoa ficam de fora", () => {
  const { minhas, outras } = recorteDaPessoa(dados().linhas, ALEX.id);
  assertEquals(minhas.map((l) => l.id), ["l1", "l3"]);
  assertEquals(outras.map((l) => l.id), ["l2"]);
});

Deno.test("via do Alex: só os serviços dele e os sem responsável; material e passo de outra pessoa não vão", () => {
  const m = montarViaDoTecnico(dados(), { modo: "roteiro", pessoa: ALEX });
  assertEquals(m.servicos, 2);
  assertEquals(m.materiais.map((x) => x.id), ["m1", "m3"]);
  assertEquals(m.passos.map((x) => x.id), ["a", "c"]);
  const html = htmlDaVia(m);
  assertStringIncludes(html, "Instalação do inversor");
  assertStringIncludes(html, "Teste final");
  // O serviço do Roberto sai só pelo nome, no quadro "com outra pessoa"
  assertStringIncludes(html, "Nesta OS, com outra pessoa (não é com você):");
  assertStringIncludes(html, "· Troca das baterias — Roberto Daniel");
  assert(!html.includes("Bateria lítio"), "material do serviço de outra pessoa não vai");
  assert(!html.includes("Passo das baterias"), "passo do serviço de outra pessoa não vai");
  assert(!html.includes("Responsável: <b>"), "na via da pessoa o responsável de cada cartão não se repete");
  // De quem é a folha (no modo da via, o que vai pelo WhatsApp)
  const daVia = htmlDaVia(montarViaDoTecnico(dados(), { modo: "via", pessoa: ALEX }));
  assertStringIncludes(daVia, "Via do técnico · Alex Gonçalves Machado</div>");
  assertStringIncludes(daVia, '<span class="lab">Técnico</span><b>Alex Gonçalves Machado</b>');
  assertStringIncludes(html, "Via do técnico · roteiro completo · Alex Gonçalves Machado</div>");
});

Deno.test("via da OS inteira (o dono): todos os serviços, com o responsável de cada um", () => {
  const html = htmlDaVia(montarViaDoTecnico(dados(), { modo: "via" }));
  for (const nome of ["Instalação do inversor", "Troca das baterias", "Teste final", "Bateria lítio"]) assertStringIncludes(html, nome);
  assertStringIncludes(html, "Responsável: <b>Alex Gonçalves Machado</b>");
  assertStringIncludes(html, "Responsável: <b>Roberto Daniel</b>");
  assert(!html.includes("com outra pessoa"), "a OS inteira não tem o quadro de outra pessoa");
});

Deno.test("sem nenhuma linha marcada, a via de cada pessoa é a OS inteira (o caso de hoje)", () => {
  const d = dados({ linhas: dados().linhas.map((l) => ({ ...l, responsavel_payee_id: null })) });
  const m = montarViaDoTecnico(d, { pessoa: ALEX });
  assertEquals(m.servicos, 3);
  assertEquals(m.semServicoDaPessoa, false);
  assert(!htmlDaVia(m).includes("com outra pessoa"));
});

Deno.test("todos os serviços com outra pessoa: a via dela fica vazia e não se manda", () => {
  const d = dados({ linhas: dados().linhas.map((l) => ({ ...l, responsavel_payee_id: ROBERTO.id })) });
  assertEquals(montarViaDoTecnico(d, { pessoa: ALEX }).semServicoDaPessoa, true);
  assertEquals(montarViaDoTecnico(d, { pessoa: ROBERTO }).semServicoDaPessoa, false);
  // OS sem serviço nenhum não é "vazia de pessoa" (a via sai com o aviso de sempre)
  assertEquals(montarViaDoTecnico(dados({ linhas: [] }), { pessoa: ALEX }).semServicoDaPessoa, false);
});

Deno.test("impressão digital: não muda com data, hora ou link da foto; muda quando o serviço da pessoa muda", () => {
  const base = impressaoDaVia(dados(), { pessoa: ALEX });
  const remarcada = dados({ header: { ...dados().header, scheduledAt: "2026-12-01T11:00:00Z", scheduledEndAt: "2026-12-02T20:00:00Z" } });
  assertEquals(impressaoDaVia(remarcada, { pessoa: ALEX }), base);
  assertEquals(impressaoDaVia(dados(), { pessoa: ALEX, linksDasFotos: { "os1/quadro.jpg": "https://x/assinada?token=1" } }), base);
  const mudou = dados({ linhas: dados().linhas.map((l) => l.id === "l1" ? { ...l, technician_instructions: "Não mexer no quadro" } : l) });
  assertNotEquals(impressaoDaVia(mudou, { pessoa: ALEX }), base);
  // Serviço do Roberto que muda só pelo detalhe não mexe na via do Alex (lá ele só aparece pelo nome)
  const doRoberto = dados({ linhas: dados().linhas.map((l) => l.id === "l2" ? { ...l, notes: "levar escada" } : l) });
  assertEquals(impressaoDaVia(doRoberto, { pessoa: ALEX }), base);
  assertNotEquals(impressaoDaVia(doRoberto, { pessoa: ROBERTO }), impressaoDaVia(dados(), { pessoa: ROBERTO }));
  // Foto trocada no levantamento muda a via
  const outraFoto = dados({ levantamento: [{ seq: 1, question_snapshot: "Foto do quadro", answer_value: "ok", photo_path: "os1/quadro2.jpg" }] });
  assertNotEquals(impressaoDaVia(outraFoto, { pessoa: ALEX }), base);
});

Deno.test("data e hora da via no fuso de Brasília, escrito (na edge o relógio é UTC)", () => {
  const html = htmlDaVia(montarViaDoTecnico(dados(), {}));
  // 11:00 UTC = 08:00 em Brasília
  assertStringIncludes(html, "<b>26/11/2026, 08:00</b>");
});

Deno.test("nome do arquivo sem acento nem espaço, com o primeiro nome da pessoa", () => {
  assertEquals(nomeDoArquivoDaVia("OS-00119", "Alex Gonçalves Machado"), "Via-tecnico-OS-00119-Alex.pdf");
  assertEquals(nomeDoArquivoDaVia("OS-00119", null), "Via-tecnico-OS-00119.pdf");
  assertEquals(nomeDoArquivoDaVia("ORÇ-00095", "João"), "Via-tecnico-ORC-00095-Joao.pdf");
});

Deno.test("Quando da via de uma pessoa: os dias dela na agenda (a OS-00119 dizia 'a combinar' com 11 dias marcados)", () => {
  const semData = dados({ header: { ...dados().header, scheduledAt: null } });
  const dias = ["2026-11-26", "2026-11-27", "2026-12-04"];
  const html = htmlDaVia(montarViaDoTecnico(semData, { pessoa: ALEX, diasNaAgenda: dias }));
  assertStringIncludes(html, "<b>qui 26/11 a sex 04/12 · 3 dias na agenda</b>");
  assert(!html.includes("A combinar com o escritório"));
  // um dia só, e a data da OS embaixo quando ela existe
  const umDia = htmlDaVia(montarViaDoTecnico(dados(), { pessoa: ALEX, diasNaAgenda: ["2026-11-26"] }));
  assertStringIncludes(umDia, "<b>qui 26/11</b><div class=\"acesso\">Início marcado na OS: 26/11/2026, 08:00</div>");
  // sem dias, como sempre
  assertStringIncludes(htmlDaVia(montarViaDoTecnico(semData, { pessoa: ALEX })), "A combinar com o escritório");
  // os dias não mudam a impressão digital (a agenda remarca sem a OS mudar)
  assertEquals(impressaoDaVia(semData, { pessoa: ALEX, diasNaAgenda: dias }), impressaoDaVia(semData, { pessoa: ALEX }));
});
