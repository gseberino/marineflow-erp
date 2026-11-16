// O quadro "Atenção" da via do técnico (porte da via v2, F1): uma linha por risco grave, detectado pelo sistema de
// cada linha e por palavras inteiras (a regra da bancada, conferida em 61 + 3 vias reais). Dado sintético.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ATENCAO, type EntradaDaAtencao, energiasDaVia, linhasDeAtencao, ORDEM, VOLANTE } from "./via-atencao.ts";

type Linha = EntradaDaAtencao["linhas"][number];

function via(linhas: Array<Partial<Linha> & { name_snapshot: string }>, over: Partial<EntradaDaAtencao> = {}): EntradaDaAtencao {
  return {
    header: { assetType: "Motorhome", problemDescription: null, ...(over.header ?? {}) },
    linhas: linhas.map((l, i) => ({ id: `l${i + 1}`, ...l })),
    materiais: over.materiais ?? [],
  };
}

const rotulos = (d: EntradaDaAtencao, pessoa: { id: string } | null = null) => linhasDeAtencao(d, pessoa).map((a) => a.rotulo);

Deno.test("lítio: o 12/24 V vira 'Bateria de lítio'; sem lítio, '12/24 V'", () => {
  assertEquals(rotulos(via([{ name_snapshot: "Troca das baterias de chumbo para lítio" }])), ["Bateria de lítio"]);
  assertEquals(rotulos(via([{ name_snapshot: "Instalação do SmartShunt no banco de baterias" }])), ["12/24 V"]);
  const [linha] = linhasDeAtencao(via([{ name_snapshot: "Bateria LiFePO4 200 Ah" }]));
  assertEquals(linha, { rotulo: "Bateria de lítio", texto: ATENCAO.dc });
});

Deno.test("altura: no motorhome é 'Teto'; no barco é 'Altura' (arco, hardtop, mastro)", () => {
  const antena = [{ name_snapshot: "Instalação da antena Starlink" }];
  assertEquals(linhasDeAtencao(via(antena)).find((a) => a.rotulo === "Teto")?.texto, ATENCAO.teto);
  const barco = linhasDeAtencao(via(antena, { header: { assetType: "Lancha" } }));
  assertEquals(barco.find((a) => a.rotulo === "Altura")?.texto, ATENCAO.barco);
  assert(!barco.some((a) => a.rotulo === "Teto"));
  // ar-condicionado de motorhome fica no teto; no barco, não
  assert(rotulos(via([{ name_snapshot: "Troca do ar-condicionado" }])).includes("Teto"));
  assert(!rotulos(via([{ name_snapshot: "Troca do ar-condicionado" }], { header: { assetType: "Lancha" } })).includes("Altura"));
});

Deno.test("volante: linha própria logo depois do 12/24 V", () => {
  const a = linhasDeAtencao(via([{ name_snapshot: "Troca do volante e revisão da buzina" }]));
  const i = a.findIndex((x) => x.rotulo === "12/24 V");
  assert(i >= 0, JSON.stringify(a));
  assertEquals(a[i + 1], { rotulo: "Volante", texto: VOLANTE });
});

Deno.test("'sobre o fogão' é lugar, não gás; trocar o fogão é gás", () => {
  assert(!rotulos(via([{ name_snapshot: "Troca do puxador do móvel aéreo sobre o fogão" }])).includes("Gás"));
  assert(rotulos(via([{ name_snapshot: "Troca do fogão" }])).includes("Gás"));
});

Deno.test("'tanque de água' não é combustível; tanque de diesel é", () => {
  assert(!rotulos(via([{ name_snapshot: "Reparo do tanque de água" }])).includes("Combustível"));
  assert(rotulos(via([{ name_snapshot: "Limpeza do tanque de diesel" }])).includes("Combustível"));
});

Deno.test("'sem inversor' não conta como 127/220 V", () => {
  assert(!rotulos(via([{ name_snapshot: "Geladeira 12 V que funciona sem inversor ou gerador" }])).includes("127/220 V"));
  assert(rotulos(via([{ name_snapshot: "Instalação do inversor" }])).includes("127/220 V"));
});

Deno.test("sistema da linha: o gravado na linha, ou na falta o do cadastro do serviço (decisão 3A)", () => {
  // nome sem palavra nenhuma: só o sistema decide
  assertEquals(rotulos(via([{ name_snapshot: "Serviço A", service_system: "gas" }])), ["Gás"]);
  assertEquals(rotulos(via([{ name_snapshot: "Serviço A", services: { name: null, service_system: "eletrico_ac" } }])), ["127/220 V"]);
  // o da linha manda sobre o do cadastro
  assertEquals(rotulos(via([{ name_snapshot: "Serviço A", service_system: "estrutural", services: { service_system: "gas" } }])), ["Furar ou cortar"]);
});

Deno.test("na dúvida, 12/24 V; linha de água ou de sistema 'nenhum' não vira 12/24 V", () => {
  assertEquals(rotulos(via([{ name_snapshot: "Serviço A" }])), ["12/24 V"]);
  assertEquals(rotulos(via([{ name_snapshot: "Troca da torneira da pia" }])), []);
  assertEquals(rotulos(via([{ name_snapshot: "Serviço A", service_system: "hidraulico" }])), []);
  assertEquals(rotulos(via([{ name_snapshot: "Serviço A", service_system: "nenhum" }])), []);
});

Deno.test("a linha de cobrança conta para o quadro (como na bancada)", () => {
  assertEquals(rotulos(via([{ name_snapshot: "Insumos elétricos" }])), ["12/24 V"]);
});

Deno.test("material da parte: inversor na separação dá 127/220 V; 'tomada' no nome de peça não", () => {
  const comInversor = via([{ name_snapshot: "Troca da torneira" }], {
    materiais: [{ service_order_service_id: null, products: { name: "Inversor 2000 W" } }],
  });
  assertEquals(rotulos(comInversor), ["127/220 V"]);
  const comTomada = via([{ name_snapshot: "Troca da torneira" }], {
    materiais: [{ service_order_service_id: null, products: { name: "Adaptador de tomada veicular" } }],
  });
  assertEquals(rotulos(comTomada), []);
});

Deno.test("cadastro do veículo: inversor cadastrado entra quando o serviço mexe no banco", () => {
  const header = { assetType: "Motorhome", vehicleElectrical: { inverterCharger: "MultiPlus 12/3000" } };
  assert(rotulos(via([{ name_snapshot: "Troca das baterias" }], { header })).includes("127/220 V"));
  assert(!rotulos(via([{ name_snapshot: "Troca do LED da cabine" }], { header })).includes("127/220 V"));
});

Deno.test("pedido da OS: entra na via da OS inteira; na via de quem não tem todos os serviços, não", () => {
  const d = via(
    [
      { name_snapshot: "Troca da torneira", responsavel_payee_id: "p-alex" },
      { name_snapshot: "Troca do ralo", responsavel_payee_id: "p-roberto" },
    ],
    { header: { assetType: "Motorhome", problemDescription: "Cliente pede revisar o gás do fogão." } },
  );
  assert(rotulos(d).includes("Gás"));
  assert(!rotulos(d, { id: "p-alex" }).includes("Gás"));
});

Deno.test("via de uma pessoa: só as linhas dela (e as sem responsável)", () => {
  const d = via([
    { name_snapshot: "Instalação do inversor", responsavel_payee_id: "p-alex" },
    { name_snapshot: "Troca do fogão", responsavel_payee_id: "p-roberto" },
    { name_snapshot: "Troca da torneira", responsavel_payee_id: null },
  ]);
  const doAlex = rotulos(d, { id: "p-alex" });
  assert(doAlex.includes("127/220 V"));
  assert(!doAlex.includes("Gás"));
  assert(rotulos(d, { id: "p-roberto" }).includes("Gás"));
});

Deno.test("trecho do pedido que é de um serviço vai com ele (kit)", () => {
  const d = via(
    [{ name_snapshot: "Kit 3 — Sistema de energia", responsavel_payee_id: "p-alex" }, { name_snapshot: "Troca da torneira", responsavel_payee_id: "p-roberto" }],
    { header: { assetType: "Motorhome", problemDescription: "Kit 3 — Sistema de energia: substituição do inversor e do carregador." } },
  );
  // o trecho do kit é do serviço do Alex: entra na via dele mesmo sem o pedido da OS
  assert(rotulos(d, { id: "p-alex" }).includes("127/220 V"));
});

Deno.test("ordem do quadro: a da bancada (127/220 V, gás, …, 12/24 V, casco, furar, resina)", () => {
  const d = via([
    { name_snapshot: "Pintura do painel com resina" },
    { name_snapshot: "Furar o piso para o passa-cabos" },
    { name_snapshot: "Instalação do inversor" },
    { name_snapshot: "Troca do fogão" },
  ]);
  const a = rotulos(d);
  const ordem = ["127/220 V", "Gás", "12/24 V", "Furar ou cortar", "Resina ou esmerilhadeira"];
  assertEquals(a.filter((r) => ordem.includes(r)), ordem);
  // toda energia detectada tem texto e rótulo
  const { energias } = energiasDaVia(d);
  for (const e of energias) assert(ORDEM.includes(e), e);
});

Deno.test("sem serviço nenhum e sem pedido: quadro vazio", () => {
  assertEquals(linhasDeAtencao(via([])), []);
});
