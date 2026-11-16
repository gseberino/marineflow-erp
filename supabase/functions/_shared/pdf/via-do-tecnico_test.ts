// A via de cada pessoa (decisão do dono, 13/11/2026: só os serviços dela) e a impressão digital que a
// agenda usa para não mandar a mesma via duas vezes.
import { assert, assertEquals, assertNotEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type DadosDaVia,
  htmlDaVia,
  impressaoDaVia,
  type LinhaDaVia,
  lerImpressao,
  montarViaDoTecnico,
  nomeDoArquivoDaVia,
  recorteDaPessoa,
  retratoDoDado,
  type ServiceOrderStep,
  VERSAO_DA_VIA,
  VERSAO_DO_DADO,
  viaHeaderFromOrder,
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

// ═══ Impressão por CONTEÚDO + VERSÃO (porte da via v2, F0) ═══════════════════════════════════════

const partes = (s: string) => lerImpressao(s)!;

Deno.test("impressão: formato v<versão>.d<versão do dado>.<dado>.<papel>; o formato antigo (hash do HTML) lê como null", () => {
  const imp = impressaoDaVia(dados(), { pessoa: ALEX });
  assert(new RegExp(`^v${VERSAO_DA_VIA}\\.d${VERSAO_DO_DADO}\\.[0-9a-z]+\\.[0-9a-z]+$`).test(imp), imp);
  assertEquals(VERSAO_DA_VIA, 2);
  assertEquals(partes(imp).versao, 2);
  assertEquals(partes(imp).versaoDoDado, 1);
  assertEquals(lerImpressao("772aau"), null);
  assertEquals(lerImpressao(null), null);
  assertEquals(lerImpressao("v2.d1.abc"), null);
});

Deno.test("impressão: mudar a empresa (nome, logo, endereço, telefone) não muda nada", () => {
  const base = impressaoDaVia(dados(), { pessoa: ALEX });
  const outra = dados({ empresa: { nome: "Outra Ltda", logoUrl: "https://x/logo.png", endereco: "Rua Nova, 1", telefone: "(11) 0000-0000" } });
  assertEquals(impressaoDaVia(outra, { pessoa: ALEX }), base);
  assertEquals(impressaoDaVia(dados({ empresa: {} }), {}), impressaoDaVia(dados(), {}));
});

Deno.test("impressão: a ordem física dos empates não muda nada (serviços, materiais, levantamento, técnicos)", () => {
  const MESMO = "2026-11-14T04:25:59.123456+00:00";
  const linhas: LinhaDaVia[] = dados().linhas.map((l) => ({ ...l, created_at: MESMO }));
  const materiais = dados().materiais.map((m) => ({ ...m, created_at: MESMO }));
  const levantamento = [
    { seq: 1, question_snapshot: "Foto do quadro", answer_value: "ok", photo_path: "os1/quadro.jpg" },
    { seq: 2, question_snapshot: "Tensão do banco", answer_value: "12,8 V", photo_path: "os1/banco.jpg" },
  ];
  const ordem = {
    service_order_number: "OS-00119", status: "scheduled",
    service_order_technicians: [{ app_users: { full_name: "Roberto Daniel" } }, { app_users: { full_name: "Alex Gonçalves Machado" } }],
  };
  const ordemTrocada = { ...ordem, service_order_technicians: [...ordem.service_order_technicians].reverse() };
  const a = dados({ header: viaHeaderFromOrder(ordem), linhas, materiais, levantamento });
  const b = dados({
    header: viaHeaderFromOrder(ordemTrocada),
    linhas: [...linhas].reverse(),
    materiais: [...materiais].reverse(),
    levantamento: [...levantamento].reverse(),
  });
  for (const pessoa of [null, ALEX, ROBERTO]) {
    assertEquals(impressaoDaVia(b, { pessoa }), impressaoDaVia(a, { pessoa }), pessoa?.nome ?? "OS inteira");
  }
});

Deno.test("técnico impresso: o primeiro em ordem alfabética (o embed vem sem ordem); todos entram no dado", () => {
  const h = viaHeaderFromOrder({
    service_order_technicians: [
      { app_users: { full_name: "Roberto Daniel" } }, { app_users: null }, { app_users: { full_name: "Alex Gonçalves Machado" } },
    ],
  });
  assertEquals(h.technicianName, "Alex Gonçalves Machado");
  assertEquals(h.tecnicos, ["Alex Gonçalves Machado", "Roberto Daniel"]);
  const html = htmlDaVia(montarViaDoTecnico(dados({ header: { ...dados().header, ...h } }), {}));
  assertStringIncludes(html, '<span class="lab">Técnico</span><b>Alex Gonçalves Machado</b>');
  // um técnico só: como sempre
  assertEquals(viaHeaderFromOrder({ service_order_technicians: [{ app_users: { full_name: "Mickael" } }] }).technicianName, "Mickael");
  assertEquals(viaHeaderFromOrder({ service_order_technicians: [] }).technicianName, null);
});

Deno.test("dado: nota do material e sistema da linha mudam o dado; preço não muda nada", () => {
  const base = partes(impressaoDaVia(dados(), { pessoa: ALEX }));
  const notaNoMaterial = dados({ materiais: dados().materiais.map((m) => m.id === "m1" ? { ...m, notes: "interno: comprar na Elétrica X" } : m) });
  assertNotEquals(partes(impressaoDaVia(notaNoMaterial, { pessoa: ALEX })).dado, base.dado);
  // Reclassificar o sistema (o caso TV/Sky do ORÇ-00131): na F0 a folha não imprime o sistema, então só o dado muda
  // — a agenda pula ("a OS mudou só no que não vai ao papel"); a segurança que muda vem da RPC, no papel.
  const reclassificada = dados({ linhas: dados().linhas.map((l) => l.id === "l1" ? { ...l, service_system: "audio_video" } : l) });
  const r = partes(impressaoDaVia(reclassificada, { pessoa: ALEX }));
  assertNotEquals(r.dado, base.dado);
  assertEquals(r.papel, base.papel);
  // do catálogo também
  const doCatalogo = dados({ linhas: dados().linhas.map((l) => l.id === "l1" ? { ...l, services: { name: null, service_system: "eletrica_dc" } } : l) });
  assertNotEquals(partes(impressaoDaVia(doCatalogo, { pessoa: ALEX })).dado, base.dado);
  // preço, desconto e total não são lidos pela via
  const comPreco = dados({
    linhas: dados().linhas.map((l) => ({ ...l, unit_price_snapshot: 999, line_total: 999, discount_amount: 10 }) as LinhaDaVia),
  });
  assertEquals(impressaoDaVia(comPreco, { pessoa: ALEX }), impressaoDaVia(dados(), { pessoa: ALEX }));
});

Deno.test("dado: orçamento em aprovação é um booleano (status que não é orçamento não muda; aprovar muda)", () => {
  const com = (status: string) => partes(impressaoDaVia(dados({ header: { ...dados().header, status } }), {})).dado;
  assertEquals(com("scheduled"), com("in_progress"));
  assertNotEquals(com("draft"), com("scheduled"));
});

Deno.test("dado: a linha leva o número dela na OS inteira; da linha de outra pessoa, só número, nome e de quem é", () => {
  const r = retratoDoDado(dados(), { pessoa: ALEX });
  assertEquals(r.linhas.map((l) => l[0]), [1, 3]);
  assertEquals(r.outras, [[2, "Troca das baterias", ROBERTO.id]]);
  assertEquals(r.pessoa, ALEX.id);
});

/** Uma OS com cobrança, técnico, levantamento com foto e orçamento em aprovação. */
function dadosComFrete(): DadosDaVia {
  return dados({
    header: {
      orderNumber: "ORÇ-00136", status: "draft", clientName: "Cliente Teste", clientPhone: "(47) 99999-0000",
      assetName: "Mar Azul", assetType: "Lancha", marinaName: "Marina Sintética", dockPosition: "Píer 3",
      technicianName: "Alex Gonçalves Machado", tecnicos: ["Alex Gonçalves Machado"],
      problemDescription: "Trocar o inversor.\nValor: R$ 3.000", technicianInstructions: "Não mexer no gerador.",
    },
    linhas: [
      { id: "f1", created_at: "2026-11-16T18:00:00.001+00:00", name_snapshot: "Instalação do inversor", quantity: 1, technician_instructions: "Desligar o banco antes." },
      { id: "f2", created_at: "2026-11-16T18:00:00.002+00:00", name_snapshot: "Deslocamento", quantity: 2, billing_unit_snapshot: "visit" },
      { id: "f3", created_at: "2026-11-16T18:00:00.003+00:00", name_snapshot: "Teste final", field_status: "feito" },
    ],
    materiais: [
      {
        id: "fm1", created_at: "2026-11-16T18:00:00.001+00:00", quantity: 1, notes: null, service_order_service_id: "f1",
        products: { name: "Inversor 3000W", sku: "INV-3000", unit: "un" },
      },
    ],
  });
}

Deno.test("TRAVA DE VERSÃO: o papel e o dado de 3 fixtures sintéticas (mudou? suba VERSAO_DA_VIA ou VERSAO_DO_DADO)", () => {
  // Se este teste falhar porque o PAPEL mudou: a regra ou o desenho da folha mudou — suba VERSAO_DA_VIA e atualize os
  // valores (sem subir, a agenda PULA quem já recebeu: "a regra do papel mudou; a OS não"). Se o DADO mudou: a lista
  // de retratoDoDado mudou — suba VERSAO_DO_DADO e atualize (sem subir, toda via pareceria "a OS mudou").
  assertEquals(
    [
      impressaoDaVia(dados(), {}),
      impressaoDaVia(dados(), { pessoa: ALEX }),
      impressaoDaVia(dadosComFrete(), { pessoa: ALEX }),
    ],
    ["v2.d1.1uhyv2v.1pnp11g", "v2.d1.1ll802l.xda7ko", "v2.d1.fuf6ax.1dnm4r0"],
    "a regra do papel (ou a lista do dado) mudou: suba a versão e atualize o valor",
  );
});
