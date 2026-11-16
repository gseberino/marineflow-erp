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
import { temNaOpenSansDoServidor } from "./open-sans-faixas.ts";

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
  // 3 = a via aprovada (porte da via v2, F1). O dado não mudou de lista: VERSAO_DO_DADO continua 1.
  assertEquals(VERSAO_DA_VIA, 3);
  assertEquals(partes(imp).versao, 3);
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
  // Reclassificar o sistema (o caso TV/Sky do ORÇ-00131): o sistema só chega ao papel pelo quadro Atenção. Aqui o
  // sistema novo não muda o quadro (o nome "Instalação do inversor" já dá 127/220 V e 12/24 V): só o dado muda.
  const reclassificada = dados({ linhas: dados().linhas.map((l) => l.id === "l1" ? { ...l, service_system: "audio_video" } : l) });
  const r = partes(impressaoDaVia(reclassificada, { pessoa: ALEX }));
  assertNotEquals(r.dado, base.dado);
  assertEquals(r.papel, base.papel);
  // Um sistema que acrescenta uma energia muda o quadro, e com ele o papel.
  const comGas = dados({ linhas: dados().linhas.map((l) => l.id === "l3" ? { ...l, service_system: "gas" } : l) });
  assertNotEquals(partes(impressaoDaVia(comGas, { pessoa: ALEX })).papel, base.papel);
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
    // F1 (via aprovada): o PAPEL mudou e a versão subiu para 3; o DADO é o mesmo da F0 (a lista não mudou). Revisão da
    // F1 (papel-1, nota dos materiais presa aos itens): só o CSS mudou, ainda na v3 — nenhuma v3 foi entregue.
    ["v3.d1.1uhyv2v.ecrpvx", "v3.d1.1ll802l.1yfwp29", "v3.d1.fuf6ax.1lj2v6o"],
    "a regra do papel (ou a lista do dado) mudou: suba a versão e atualize o valor",
  );
});

// ═══ A via aprovada (porte da via v2, F1): base limpa + rodadas 1, 2 e 3 ═══════════════════════════════════════

/** A parte do HTML antes do fechamento (a folha 1 e os cartões) e o fechamento (chegada/saída, assinaturas, rodapé). */
function partesDaFolha(html: string): { antes: string; fechamento: string } {
  const [antes, fechamento = ""] = html.split('<div class="fechamento">');
  return { antes, fechamento };
}

Deno.test("via: sem 'Segurança por sistema' nem passo nenhum, mesmo com a segurança do banco e roteiro gravado", () => {
  const d = dados({
    passos: [
      passo({ id: "s1", seq: 1, title: "Desligar a chave geral", block: "1 · Antes de mexer — Elétrico DC", block_key: "abertura:eletrico_dc", kind: "safety" }),
      passo({ id: "s2", seq: 2, title: "Passo do inversor", service_order_service_id: "l1", block: "Inversor" }),
    ],
    seguranca: [{
      papel: "abertura", sistema: "eletrico_dc", bloco: "Antes de mexer — Elétrico DC", escopo: "Vale para: Troca das baterias.",
      identificado_por: "cadastro", seq: 1, title: "Isolar o banco", detail: null, kind: "safety", is_killer: true,
      requires_photo: false, requires_measure: null, measure_unit: null, mode: "do_confirm", standard_minutes: 2,
    }],
  });
  for (const pessoa of [null, ALEX]) {
    const m = montarViaDoTecnico(d, { modo: "via", pessoa });
    assertEquals(m.passos, []);
    const html = htmlDaVia(m);
    for (const fora of ["Segurança por sistema", "Roteiro de execução", "Desligar a chave geral", "Isolar o banco", "Passo do inversor"]) {
      assert(!html.includes(fora), `${fora} (${pessoa?.nome ?? "OS inteira"})`);
    }
  }
  // o painel Roteiro (modo roteiro) continua com o roteiro gravado, sem o quadro Atenção
  const roteiro = htmlDaVia(montarViaDoTecnico(d, { modo: "roteiro" }));
  assertStringIncludes(roteiro, "Desligar a chave geral");
  assertStringIncludes(roteiro, "Passo do inversor");
  assert(!roteiro.includes('<div class="secao atencao-box">'));
});

Deno.test("via: quadro Atenção com o ⚠ desenhado (nunca o caractere); só as energias da parte de cada pessoa", () => {
  const html = htmlDaVia(montarViaDoTecnico(dados(), { modo: "via" }));
  assertStringIncludes(html, '<div class="secao atencao-box"><div class="sectitle"><svg class="tri"');
  assertStringIncludes(html, "Atenção</div>");
  assertStringIncludes(html, "<b>127/220 V:</b>");
  // a bateria de lítio é material do serviço do Roberto: na OS inteira, lítio
  assertStringIncludes(html, "<b>Bateria de lítio:</b>");
  assert(!html.includes("⚠"));
  // na via do Alex, o material de lítio (do serviço do Roberto) não entra: 12/24 V
  const doAlex = htmlDaVia(montarViaDoTecnico(dados(), { modo: "via", pessoa: ALEX }));
  assertStringIncludes(doAlex, "<b>12/24 V:</b>");
  assert(!doAlex.includes("Bateria de lítio"));
  // o quadro vem depois dos serviços e antes do fechamento
  const { antes, fechamento } = partesDaFolha(html);
  assert(antes.indexOf('<div class="secao atencao-box">') > antes.indexOf("Serviços desta OS"));
  assert(!fechamento.includes('<div class="secao atencao-box">'));
});

Deno.test("4A: frete, deslocamento e insumos saem dos cartões; os outros mantêm o número (1, 2, 3, 5)", () => {
  const d = dados({
    linhas: [
      { id: "c1", name_snapshot: "Instalação do inversor" },
      { id: "c2", name_snapshot: "Troca das baterias" },
      { id: "c3", name_snapshot: "Teste final" },
      { id: "c4", name_snapshot: "Frete do equipamento" },
      { id: "c5", name_snapshot: "Retirada do carregador — inclui frete de ida e volta" },
    ],
    materiais: [],
  });
  const m = montarViaDoTecnico(d, { modo: "via" });
  assertEquals(m.servicos, 4);
  assertEquals(m.extras.services?.map((s) => s.numero), [1, 2, 3, 5]);
  const html = htmlDaVia(m);
  assertStringIncludes(html, '<div class="svctitle">3 · Teste final');
  assertStringIncludes(html, '<div class="svctitle">5 · Retirada do carregador — inclui frete de ida e volta');
  assert(!html.includes("Frete do equipamento"));
  assert(!html.includes('<div class="svctitle">4 ·'));
});

Deno.test("via de uma pessoa: cartões com o número da OS inteira; cobrança de outra pessoa nem no quadro dela", () => {
  const html = htmlDaVia(montarViaDoTecnico(dados(), { modo: "via", pessoa: ALEX }));
  assertStringIncludes(html, '<div class="svctitle">1 · Instalação do inversor');
  assertStringIncludes(html, '<div class="svctitle">3 · Teste final');
  const comFrete = dados({
    linhas: [...dados().linhas, { id: "l4", name_snapshot: "Deslocamento técnico", responsavel_payee_id: ROBERTO.id }],
  });
  const doAlex = htmlDaVia(montarViaDoTecnico(comFrete, { modo: "via", pessoa: ALEX }));
  assertStringIncludes(doAlex, "· Troca das baterias — Roberto Daniel");
  assert(!doAlex.includes("Deslocamento técnico"), "cobrança não vai ao quadro de outra pessoa");
});

Deno.test("via de uma pessoa: só cobrança na parte dela = via vazia (não se manda); OS só de cobrança, não", () => {
  const d = dados({
    linhas: [
      { id: "l1", name_snapshot: "Instalação do inversor", responsavel_payee_id: ROBERTO.id },
      { id: "l2", name_snapshot: "Deslocamento técnico", responsavel_payee_id: null },
    ],
  });
  const m = montarViaDoTecnico(d, { pessoa: ALEX });
  assertEquals(m.servicos, 0);
  assertEquals(m.semServicoDaPessoa, true);
  const soFrete = dados({ linhas: [{ id: "l1", name_snapshot: "Frete", responsavel_payee_id: null }] });
  assertEquals(montarViaDoTecnico(soFrete, { pessoa: ALEX }).semServicoDaPessoa, false);
});

Deno.test("onde: sem marina, vaga nem acesso, 'Oficina HBR'; com marina, a marina", () => {
  const html = htmlDaVia(montarViaDoTecnico(dados(), {}));
  assertStringIncludes(html, '<span class="lab">Onde</span><b>Oficina HBR</b>');
  assert(!html.includes("Local não informado"));
  const comMarina = htmlDaVia(montarViaDoTecnico(dados({ header: { ...dados().header, marinaName: "Marina Sintética" } }), {}));
  assertStringIncludes(comMarina, "<b>Marina Sintética</b>");
  assert(!comMarina.includes("Oficina HBR"));
});

Deno.test("telefones: na folha 1 só 'telefone no fim da ficha'; os números no fechamento, ao lado de Chegada/Saída", () => {
  const header = {
    ...dados().header,
    clientPhone: "(47) 99999-0000", clientWhatsapp: "47 99999-0000",
    onSiteContact: { name: "Seu João", role: "Marinheiro", phone: "(47) 98888-0000" },
  };
  const html = htmlDaVia(montarViaDoTecnico(dados({ header }), {}));
  const { antes, fechamento } = partesDaFolha(html);
  assertStringIncludes(antes, 'Cliente: <b>Lenine</b> — <span class="vazio">telefone no fim da ficha</span>');
  assertStringIncludes(antes, 'No local: <b>Seu João</b> (Marinheiro) — <span class="vazio">telefone no fim da ficha</span>');
  assert(!antes.includes("99999-0000") && !antes.includes("98888-0000"), "número nenhum na folha 1");
  assertStringIncludes(fechamento, '<div class="contatofim"><b>Cliente:</b> Lenine — <span class="tel">tel./WhatsApp (47) 99999-0000</span>');
  assertStringIncludes(fechamento, '<b>No local:</b> Seu João (Marinheiro) — <span class="tel">tel. (47) 98888-0000</span>');
  // contato no local com o mesmo número do cliente: não repete
  const mesmo = htmlDaVia(montarViaDoTecnico(dados({ header: { ...header, onSiteContact: { name: "Seu João", phone: "47999990000" } } }), {}));
  assertStringIncludes(mesmo, 'No local: <b>Seu João</b> — <span class="vazio">mesmo telefone do cliente</span>');
  assert(!partesDaFolha(mesmo).fechamento.includes("<b>No local:</b>"));
  // sem número nenhum: a folha 1 diz, e o fechamento não ganha a linha
  const semFone = htmlDaVia(montarViaDoTecnico(dados(), {}));
  assertStringIncludes(semFone, 'Cliente: <b>Lenine</b> — <span class="vazio">sem telefone no cadastro</span>');
  assert(!semFone.includes('<div class="contatofim">'));
});

Deno.test("aviso de orçamento em aprovação: só com o status de orçamento (draft)", () => {
  const AVISO = '<div class="aviso orc"><b>Orçamento em aprovação:</b> o técnico só executa com o OK do escritório.</div>';
  const com = (status: string) => htmlDaVia(montarViaDoTecnico(dados({ header: { ...dados().header, status } }), {}));
  assertStringIncludes(com("draft"), AVISO);
  for (const status of ["scheduled", "in_progress", "cancelled", "awaiting_client"]) assert(!com(status).includes("aviso orc"), status);
  // pelo cabeçalho que a tela e o servidor montam
  assertEquals(viaHeaderFromOrder({ status: "draft" }).orcamentoEmAprovacao, true);
  assertEquals(viaHeaderFromOrder({ status: "open" }).orcamentoEmAprovacao, false);
  // a ordem do topo: cabeçalho → veículo → aviso → rosto
  const html = com("draft");
  assert(html.indexOf('<div class="unidade">') < html.indexOf('<div class="aviso orc">'));
  assert(html.indexOf('<div class="aviso orc">') < html.indexOf('<div class="rosto">'));
});

Deno.test("veículo numa linha própria, fora do rosto; número da OS grande", () => {
  const html = htmlDaVia(montarViaDoTecnico(dados(), {}));
  assertStringIncludes(html, '<div class="unidade"><span class="lab">Motorhome</span><div class="uval">Itapoã</div></div>');
  const rosto = html.slice(html.indexOf('<div class="rosto">'), html.indexOf("Serviços desta OS"));
  assert(!rosto.includes('<span class="lab">Motorhome</span>'));
  assertStringIncludes(html, ".doctype .num { font-size: 28pt;");
});

Deno.test("instrução do serviço: o rótulo na mesma linha; duas linhas viram uma, juntas por espaço", () => {
  const d = dados({
    linhas: dados().linhas.map((l) => l.id === "l1" ? { ...l, technician_instructions: "Desligar o banco antes.\nConferir o aperto." } : l),
  });
  const html = htmlDaVia(montarViaDoTecnico(d, {}));
  assertStringIncludes(html, '<div class="instrucao sm"><span class="lab">Instrução</span>Desligar o banco antes. Conferir o aperto.</div>');
});

Deno.test("material: em 2 colunas; a nota interna do sistema não vai, a nota escrita por gente vai", () => {
  const d = dados({
    materiais: [
      { id: "m1", quantity: 1, notes: "Cadastrado pelo orçamento — confirmar preço e completar cadastro fiscal.", service_order_service_id: null, products: { name: "Disjuntor 32 A", sku: null, unit: "un" } },
      { id: "m2", quantity: 2, notes: "Levar o vermelho", service_order_service_id: null, products: { name: "Cabo 16 mm²", sku: "CB-16", unit: "m" } },
    ],
  });
  const html = htmlDaVia(montarViaDoTecnico(d, {}));
  assertStringIncludes(html, '<div class="secao materiais">');
  assertStringIncludes(html, '<div class="matitem"><span class="check sm"></span><div><b>1 un</b> · Disjuntor 32 A</div></div>');
  assertStringIncludes(html, '<div class="detail">Levar o vermelho</div>');
  assert(!html.includes("Cadastrado pelo orçamento"));
  // sem material, o aviso de sempre
  assertStringIncludes(htmlDaVia(montarViaDoTecnico(dados({ materiais: [] }), {})), "Nenhum material lançado nesta OS.");
});

Deno.test("material: título e nota nunca sozinhos no pé da folha — a nota fica presa aos itens (revisão da F1, papel-1)", () => {
  // O .sectitle prende o título à nota; sem isto, a nota quebrava antes das colunas e os itens iam sozinhos para a
  // folha seguinte (pedido de 32 linhas e 8 materiais, no Chromium do /api/pdf).
  const html = htmlDaVia(montarViaDoTecnico(dados(), {}));
  assertStringIncludes(html, ".materiais .matnota { break-after: avoid; page-break-after: avoid; }");
  assertStringIncludes(html, '<div class="matnota">Confira item por item antes de sair.');
});

Deno.test("fechamento num bloco só, com a faixa da foto no fim; a seta entre as datas virou 'até'", () => {
  const d = dados({ header: { ...dados().header, scheduledEndAt: "2026-11-27T20:00:00Z" } });
  const html = htmlDaVia(montarViaDoTecnico(d, {}));
  const { fechamento } = partesDaFolha(html);
  for (const parte of ["Chegada:", "O que encontrei", "Material usado além do previsto", "Assinatura do cliente", 'class="foot"']) {
    assertStringIncludes(fechamento, parte);
  }
  assertStringIncludes(fechamento, '<div class="fotofim"><b>No fim:</b> fotografe todas as folhas preenchidas e mande no WhatsApp do escritório, com as fotos do serviço pronto.</div>');
  assertStringIncludes(html, "<b>26/11/2026, 08:00</b> até 27/11/2026, 17:00");
  assert(!html.includes("→"));
  assertStringIncludes(html, 'font-family: "Open Sans", Arial, Helvetica, sans-serif');
});

/** O texto que vai ao papel: o corpo sem marcação (o SVG do ⚠ é desenho) e as strings de `content:` do CSS (rodapé). */
function textoDoPapel(html: string): string {
  const css = (html.match(/<style>[\s\S]*?<\/style>/g) ?? []).join("");
  const conteudo = [...css.matchAll(/content:\s*"([^"]*)"/g)].map((m) => m[1]).join(" ");
  const corpo = html.replace(/<style>[\s\S]*?<\/style>/g, "").replace(/<svg[\s\S]*?<\/svg>/g, "").replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ").replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
  return `${corpo} ${conteudo}`;
}

/** Uma OS que passa por tudo o que a via escreve (cobrança, situações, instrução, material ligado, levantamento…). */
function dadosCompletos(): DadosDaVia {
  return dados({
    header: {
      orderNumber: "ORÇ-00999", status: "draft", clientName: "Cliente Sintético", clientPhone: "(47) 99999-0000",
      clientWhatsapp: "(47) 97777-0000", requestedBy: "Marinheiro Sintético",
      onSiteContact: { name: "Contato Sintético", role: "Comandante", phone: "(47) 98888-0000" },
      assetName: "Mar Azul", assetType: "Lancha", assetMaker: "Fabricante X", assetModel: "Modelo 32", assetRegistration: "4410123456",
      marinaName: "Marina Sintética", dockPosition: "Píer 3", siteAccess: "Portão 2 — chave na secretaria",
      technicianName: "Alex Gonçalves Machado", tecnicos: ["Alex Gonçalves Machado"],
      scheduledAt: "2026-11-26T11:00:00Z", scheduledEndAt: "2026-11-28T20:00:00Z",
      problemDescription: "Trocar as baterias por lítio e revisar o gerador.\nSinal: R$ 3.000",
      technicianInstructions: "Não mexer no quadro de 220 V sem avisar.",
      vehicleElectrical: { batteryBank: "4× AGM 105 Ah", inverterCharger: "MultiPlus 12/3000", shorePower: "Cabo de cais 30 A", notes: "Chave geral atrás do banco" },
    },
    linhas: [
      { id: "x1", name_snapshot: "Troca das baterias por LiFePO4 200 Ah", quantity: 4, billing_unit_snapshot: "un", technician_instructions: "Conferir a polaridade.\nApertar a 12 N·m.", responsavel_payee_id: ALEX.id },
      { id: "x2", name_snapshot: "Revisão do gerador Onan", field_status: "parcial", field_status_note: "faltou o filtro", responsavel_payee_id: ROBERTO.id },
      { id: "x3", name_snapshot: "Insumos elétricos" },
      { id: "x4", name_snapshot: "Troca do volante e da buzina", field_status: "so_levantar", description_snapshot: "Volante com folga; medir antes.", notes: "Levar o extrator." },
      { id: "x5", name_snapshot: "Furar o hardtop para a antena", field_status: "feito" },
      { id: "x6", name_snapshot: "Pintura do casco com resina", field_status: "aguarda_peca" },
      { id: "x7", name_snapshot: "Troca do fogão", field_status: "nao_feito" },
    ],
    materiais: [
      { id: "y1", quantity: 4, notes: "Levar os quatro", service_order_service_id: "x1", products: { name: "Bateria LiFePO4 12,8 V 200 Ah", sku: "LFP-200", unit: "un" } },
      { id: "y2", quantity: 1.5, notes: "Cadastrado pelo orçamento — confirmar preço.", service_order_service_id: null, products: { name: "Cabo 35 mm² vermelho", sku: null, unit: "m" } },
      { id: "y3", quantity: 1, notes: null, service_order_service_id: "x2", products: { name: "Filtro de óleo", sku: "FO-1", unit: "un" } },
    ],
    levantamento: [
      { seq: 1, question_snapshot: "Tensão do banco em repouso?", answer_value: "12,6 V", photo_path: "os/banco.jpg" },
      { seq: 2, question_snapshot: "Há espaço para o shunt?", skipped_reason: "não deu para abrir o painel" },
    ],
  });
}

Deno.test("glifos: todo caractere que vai ao papel existe na Open Sans do servidor (⚠ e → não existem lá)", () => {
  assert(!temNaOpenSansDoServidor("⚠".codePointAt(0)!));
  assert(!temNaOpenSansDoServidor("→".codePointAt(0)!));
  assert(temNaOpenSansDoServidor("ç".codePointAt(0)!) && temNaOpenSansDoServidor("—".codePointAt(0)!));
  const d = dadosCompletos();
  const vias = [
    htmlDaVia(montarViaDoTecnico(d, { modo: "via", linksDasFotos: { "os/banco.jpg": "https://x/foto.jpg" } })),
    htmlDaVia(montarViaDoTecnico(d, { modo: "via", pessoa: ALEX, diasNaAgenda: ["2026-11-26", "2026-11-27"] })),
    htmlDaVia(montarViaDoTecnico(d, { modo: "via", pessoa: ROBERTO })),
    htmlDaVia(montarViaDoTecnico(dados(), {})),
  ];
  // a OS completa passa mesmo pelo que a folha escreve (senão o teste não prova nada)
  for (const parte of ['svg class="tri"', "Bateria de lítio:", "Volante:", "Altura:", '<div class="aviso orc">', '<div class="contatofim">', "SÓ LEVANTAR", "PARCIAL", "JÁ FEITO", "AGUARDA PEÇA", "NÃO FEITO", "Material deste serviço:", "pulada:", " até "]) {
    assertStringIncludes(vias[0], parte);
  }
  assertStringIncludes(vias[1], "com outra pessoa");
  for (const html of vias) {
    const fora = [...new Set([...textoDoPapel(html)].filter((ch) => !/[\n\r\t]/.test(ch) && !temNaOpenSansDoServidor(ch.codePointAt(0)!)))];
    assertEquals(fora, [], `fora da Open Sans: ${fora.map((c) => `U+${c.codePointAt(0)!.toString(16).toUpperCase()}`).join(", ")}`);
  }
});
