import { assert, assertEquals, assertNotEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  chaveDoCobrarJuntas, contaVencida, horaEmBrasilia, MAX_COBRAR_JUNTAS, MIN_COBRAR_JUNTAS, mudancaNasContas, osComSaldo,
  osEntraNoCobrarJuntas, pagoDaConta, saldoDaConta, travaDoCobrarJuntas,
} from "./cobrar-juntas.ts";
import { checarConformidade } from "../ai/comms/compliance-guard.ts";
import { MAX_AGRUPAR, MIN_AGRUPAR } from "../ai/tools/agrupar-orcamentos.ts";

// O caso medido em 28/10/2026: MP MOTOR HOMES, OS-00045 (R$ 1.650) + OS-00046 (R$ 20) = R$ 1.670,
// vencido desde 22/07. A mensagem antiga dizia "Pago R$ 0" e "a vencer".
const MP = [
  { id: "s45", service_order_id: "os45", numero_os: "OS-00045", status: "paid", amount: 500, paid_amount: 500, balance_amount: 0, due_date: "2026-06-01" },
  { id: "r45", service_order_id: "os45", numero_os: "OS-00045", status: "pending", amount: 1650, paid_amount: 0, balance_amount: 1650, due_date: "2026-07-22" },
  { id: "r46", service_order_id: "os46", numero_os: "OS-00046", status: "partially_paid", amount: 50, paid_amount: 30, balance_amount: 20, due_date: "2026-07-22" },
  { id: "c46", service_order_id: "os46", numero_os: "OS-00046", status: "cancelled", amount: 999, paid_amount: 0, balance_amount: 999, due_date: "2026-07-01" },
];

Deno.test("saldo e pago seguem a regra da ficha (cancelada e paga = 0; pago parcial conta)", () => {
  assertEquals(saldoDaConta(MP[1]), 1650);
  assertEquals(saldoDaConta(MP[2]), 20);
  assertEquals(saldoDaConta(MP[3]), 0);
  assertEquals(saldoDaConta(MP[0]), 0);
  assertEquals(pagoDaConta(MP[2]), 30);
  // Dado sem paid_amount: deduz.
  assertEquals(pagoDaConta({ status: "paid", amount: 100 }), 100);
  assertEquals(pagoDaConta({ status: "pending", amount: 100, balance_amount: 40 }), 60);
  assertEquals(saldoDaConta({ status: "pending", amount: 100, paid_amount: 100.004 }), 0);
});

Deno.test("vencida é pela data, não pelo status gravado", () => {
  assert(contaVencida(MP[1], "2026-10-28"));
  assert(!contaVencida(MP[1], "2026-07-22"));
  assert(!contaVencida(MP[0], "2026-10-28"));
});

Deno.test("osComSaldo: só OS com saldo, contas abertas, total certo", () => {
  const oss = osComSaldo([...MP, { id: "avulsa", status: "pending", amount: 70, due_date: "2026-01-01" }], "2026-10-28");
  assertEquals(oss.map((o) => o.numero_os), ["OS-00045", "OS-00046"]);
  assertEquals(oss[0].contas.map((c) => c.id), ["r45"]);
  assertEquals(oss[1].contas.map((c) => c.id), ["r46"]);
  assertEquals(oss.reduce((s, o) => s + o.saldo, 0), 1670);
  assert(oss.every((o) => o.vencido));
});

Deno.test("travas: genérico, nada em aberto, piso, Pix esperando, opt-out, telefone — nessa ordem", () => {
  const base = { clienteNome: "MP MOTOR HOMES", totalEmAberto: 1670, telefone: "47999990000" };
  assertEquals(travaDoCobrarJuntas(base), null);
  const generico = travaDoCobrarJuntas({ ...base, clienteNome: "Cliente Final", generico: true, optOut: true });
  assert(generico?.includes('O cadastro Cliente Final é genérico, sem CPF/CNPJ'));
  assert(travaDoCobrarJuntas({ ...base, totalEmAberto: 0 })?.includes("não há o que cobrar"));
  assert(travaDoCobrarJuntas({ ...base, totalEmAberto: 20, piso: 50 })?.includes("abaixo do piso"));
  // Piso compara o TOTAL das OS juntas, não cada conta.
  assertEquals(travaDoCobrarJuntas({ ...base, piso: 50 }), null);
  const pix = travaDoCobrarJuntas({ ...base, optOut: true, pixEsperando: [{ valor: 1670, data: "2026-10-27" }] });
  assert(pix?.includes("Pix esperando no Extrato (R$ 1670.00 de 2026-10-27)"));
  assert(travaDoCobrarJuntas({ ...base, optOut: true })?.includes("opt-out"));
  assert(travaDoCobrarJuntas({ ...base, telefone: "123" })?.includes("Sem telefone"));
});

Deno.test("limites de 2 a 10 OS, como a tool (que usa os mesmos números)", () => {
  assertEquals([MIN_COBRAR_JUNTAS, MAX_COBRAR_JUNTAS], [MIN_AGRUPAR, MAX_AGRUPAR]);
  const base = { clienteNome: "MP", totalEmAberto: 1670, telefone: "47999990000" };
  assert(travaDoCobrarJuntas({ ...base, quantidadeOs: 1 })?.includes("2 OS ou mais"));
  assert(travaDoCobrarJuntas({ ...base, quantidadeOs: 0 })?.includes("2 OS ou mais"));
  assertEquals(travaDoCobrarJuntas({ ...base, quantidadeOs: 2 }), null);
  assertEquals(travaDoCobrarJuntas({ ...base, quantidadeOs: 10 }), null);
  assert(travaDoCobrarJuntas({ ...base, quantidadeOs: 11 })?.includes("no máximo 10 OS"));
  // Genérico vem antes da contagem.
  assert(travaDoCobrarJuntas({ ...base, generico: true, quantidadeOs: 1 })?.includes("genérico"));
});

Deno.test("horário de cobrança: a tela recusa nas MESMAS horas que o portão do assistente (paridade hora a hora)", () => {
  const base = { clienteNome: "MP", totalEmAberto: 1670, telefone: "47999990000" };
  for (let h = 0; h < 24; h++) {
    const tela = travaDoCobrarJuntas({ ...base, horaBrasilia: h });
    const assistente = checarConformidade({ tipo: "cobranca", audiencia: "cliente", canal: "whatsapp", horaBrasilia: h, destinatarioIdentificado: true });
    assertEquals(!!tela, !!assistente, `${h}h: tela ${tela} × assistente ${assistente?.motivo}`);
  }
  assert(travaDoCobrarJuntas({ ...base, horaBrasilia: 22 })?.includes("Fora do horário de cobrança (22h"));
  // Sem a hora (a tool confere no portão do envio), não trava.
  assertEquals(travaDoCobrarJuntas(base), null);
  // O dinheiro e o contato vêm antes do horário (mesma ordem da tool).
  assert(travaDoCobrarJuntas({ ...base, horaBrasilia: 22, optOut: true })?.includes("opt-out"));
});

Deno.test("horaEmBrasilia não depende do fuso da máquina", () => {
  assertEquals(horaEmBrasilia(new Date("2026-10-28T17:00:00Z")), 14);
  assertEquals(horaEmBrasilia(new Date("2026-10-29T01:00:00Z")), 22);
  assertEquals(horaEmBrasilia(new Date("2026-10-28T03:00:00Z")), 0);
});

Deno.test("mudancaNasContas: conta paga, saldo mexido ou conta nova recusam; igual passa", () => {
  const antes = [{ id: "r45", saldo: 1650 }, { id: "r46", saldo: 20 }];
  const agora = MP; // s45 paga e c46 cancelada ficam de fora sozinhas
  assertEquals(mudancaNasContas(antes, agora), null);
  const paga = mudancaNasContas(antes, agora.map((c) => c.id === "r45" ? { ...c, status: "paid", paid_amount: 1650, balance_amount: 0 } : c));
  assert(paga?.includes("As contas em aberto destas OS mudaram"));
  assert(paga?.includes("feche e abra"));
  const mexida = mudancaNasContas(antes, agora.map((c) => c.id === "r46" ? { ...c, paid_amount: 40, balance_amount: 10 } : c));
  assert(mexida?.includes("O saldo das OS mudou"));
  const nova = mudancaNasContas(antes, [...agora, { id: "x", status: "pending", amount: 35, paid_amount: 0, balance_amount: 35 }]);
  assert(nova?.includes("mudaram"));
});

Deno.test("só OS que já começou entra; origem agrupada e orçamento ficam de fora", () => {
  assert(osEntraNoCobrarJuntas({ status: "completed" }));
  assert(osEntraNoCobrarJuntas({ status: "in_progress" }));
  assert(osEntraNoCobrarJuntas({ status: "invoiced" }));
  assert(!osEntraNoCobrarJuntas({ status: "open" }));
  assert(!osEntraNoCobrarJuntas({ status: "draft" }));
  assert(!osEntraNoCobrarJuntas({ status: "completed", merged_into_id: "x" }));
  assert(!osEntraNoCobrarJuntas(null));
});

Deno.test("chave de envio: mesma conta e texto no mesmo dia = mesma chave; mudou algo = outra", () => {
  const a = chaveDoCobrarJuntas("cli", ["r46", "r45"], "2026-10-28", "Olá");
  assertEquals(a, chaveDoCobrarJuntas("cli", ["r45", "r46"], "2026-10-28", "Olá "));
  assertNotEquals(a, chaveDoCobrarJuntas("cli", ["r45"], "2026-10-28", "Olá"));
  assertNotEquals(a, chaveDoCobrarJuntas("cli", ["r45", "r46"], "2026-10-29", "Olá"));
  assert(a.startsWith("cobrar-juntas:cli:2026-10-28:"));
  assert(a.length <= 200);
});

Deno.test("chave de envio desviado pelo modo de teste: só ganha ':teste' (não reserva a chave do cliente)", () => {
  const real = chaveDoCobrarJuntas("cli", ["r45", "r46"], "2026-10-28", "Olá");
  assertEquals(chaveDoCobrarJuntas("cli", ["r45", "r46"], "2026-10-28", "Olá", false), real);
  assertEquals(chaveDoCobrarJuntas("cli", ["r46", "r45"], "2026-10-28", "Olá", true), `${real}:teste`);
});
