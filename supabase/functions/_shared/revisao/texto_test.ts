// Lembretes de revisão (07/10/2026): as regras puras — datas de terça a quinta, faixa de valor,
// toque certo por dia, agrupamento por cliente, campanha de setembro/outubro e o texto de cada toque.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  agruparPorCliente,
  dentroDaCampanha,
  diaOferecido,
  diasSugeridos,
  type EventoDoPlano,
  faixaDeValor,
  hojeEmBrasilia,
  mesDaCampanha,
  montarTexto,
  type PlanoDue,
  planoNaFrase,
  primeiroNome,
  resumoDoServico,
  toqueDevido,
} from "./texto.ts";

const plano = (o: Partial<PlanoDue> = {}): PlanoDue => ({
  plan_id: "p1", vessel_id: "v1", vessel_name: "Mar Azul", client_id: "c1", client_name: "Carlos Souza",
  client_phone: "(47) 99915-9654", opt_out: false, plan_name: "Revisão das baterias", estimated_value: 1500,
  last_service_at: "2025-10-28", last_service_order_id: null, next_due_on: "2026-10-28", snoozed_until: null,
  dias_para_vencer: 21, situacao: "na_janela", tem_os_agendada: false, respondeu_no_ciclo: false,
  client_reminder_enabled: true, ...o,
});
const ev = (o: Partial<EventoDoPlano>): EventoDoPlano => ({ plan_id: "p1", due_on: "2026-10-28", tipo: "reminder_sent", toque: 1, ...o });

// ─── Datas ──────────────────────────────────────────────────────────────────────────────────
Deno.test("datas: as duas sugestões são ter–qui da semana do vencimento, nunca antes de hoje + 2", () => {
  // 07/10/2026 é quarta. Vence qua 28/10 → semana de 26/10: ter 27 e qua 28.
  assertEquals(diasSugeridos("2026-10-28", "2026-10-07"), ["2026-10-27", "2026-10-28"]);
  // Vence numa segunda (02/11): a mesma semana, ter 03 e qua 04.
  assertEquals(diasSugeridos("2026-11-02", "2026-10-07"), ["2026-11-03", "2026-11-04"]);
  // Vence amanhã (qui 08/10): a semana já está em cima → a partir de sex 09: ter 13 e qua 14.
  assertEquals(diasSugeridos("2026-10-08", "2026-10-07"), ["2026-10-13", "2026-10-14"]);
  // Já venceu: idem, a partir de hoje + 2.
  assertEquals(diasSugeridos("2026-09-01", "2026-10-07"), ["2026-10-13", "2026-10-14"]);
  // Vence domingo 01/11: a semana é a de seg 26/10 (ter 27, qua 28).
  assertEquals(diasSugeridos("2026-11-01", "2026-10-07"), ["2026-10-27", "2026-10-28"]);
  assertEquals(diaOferecido("2026-11-05", "manhã"), "qui 05/11 de manhã");
  assertEquals(diaOferecido("2026-11-04", "tarde"), "qua 04/11 à tarde");
  assertEquals(hojeEmBrasilia(new Date("2026-10-08T02:30:00Z")), "2026-10-07"); // 23h30 de Brasília
});

Deno.test("valor: faixa de ±15% arredondada à dezena; sem valor, nada", () => {
  assertEquals(faixaDeValor(1500), "R$ 1.280 a R$ 1.730");
  assertEquals(faixaDeValor("2500"), "R$ 2.130 a R$ 2.880");
  assertEquals(faixaDeValor(40), "R$ 30 a R$ 50");
  assertEquals(faixaDeValor(null), null);
  assertEquals(faixaDeValor(0), null);
  assertEquals(faixaDeValor("abc"), null);
});

Deno.test("nomes: primeiro nome, empresa sem nome, plano na frase", () => {
  assertEquals(primeiroNome({ name: "CARLOS ALBERTO SOUZA" }), "Carlos");
  assertEquals(primeiroNome({ name: "Carlos Souza", display_name: "Carlão" }), "Carlão");
  assertEquals(primeiroNome({ name: "Mar Azul Ltda", type: "company" }), null);
  assertEquals(primeiroNome(null), null);
  assertEquals(planoNaFrase("Revisão das baterias"), "revisão das baterias");
  assertEquals(planoNaFrase("Troca de óleo do motor"), "troca de óleo do motor");
  assertEquals(planoNaFrase("Baterias"), "revisão de baterias");
  assertEquals(planoNaFrase("ECU do motor"), "revisão de ECU do motor");
  assertEquals(resumoDoServico(["Troca de 4 baterias AGM", "Teste do carregador", "Limpeza"]), "troca de 4 baterias AGM e teste do carregador");
  assertEquals(resumoDoServico([]), null);
});

// ─── Toque certo por dia ────────────────────────────────────────────────────────────────────
Deno.test("toque: D-21 é o 1º, D-7 o 2º só se o 1º foi ENVIADO, D+14 o último", () => {
  assertEquals(toqueDevido(plano({ dias_para_vencer: 22, situacao: "em_dia" }), []), null);
  assertEquals(toqueDevido(plano({ dias_para_vencer: 21 }), []), { toque: 1 });
  assertEquals(toqueDevido(plano({ dias_para_vencer: 10 }), []), { toque: 1 });
  assertEquals(toqueDevido(plano({ dias_para_vencer: 10 }), [ev({ tipo: "reminder_proposed" })]), null, "não propõe de novo o mesmo toque");
  assertEquals(toqueDevido(plano({ dias_para_vencer: 7 }), [ev({})]), { toque: 2 });
  // Primeiro contato nunca é o "só lembrando": sem o 1º enviado, em D-7 ainda é o 1º.
  assertEquals(toqueDevido(plano({ dias_para_vencer: 5 }), []), { toque: 1 });
  // O 1º foi proposto e o dono recusou: em D-7 não insiste.
  assertEquals(toqueDevido(plano({ dias_para_vencer: 5 }), [ev({ tipo: "reminder_proposed" })]), null);
  assertEquals(toqueDevido(plano({ dias_para_vencer: 7 }), [ev({}), ev({ tipo: "reminder_proposed", toque: 2 })]), null);
  // Vencido há menos de 14 dias: espera. Há 14+: o último.
  assertEquals(toqueDevido(plano({ dias_para_vencer: -5, situacao: "vencida" }), [ev({})]), null);
  assertEquals(toqueDevido(plano({ dias_para_vencer: -14, situacao: "vencida" }), [ev({}), ev({ toque: 2 })]), { toque: 3 });
  assertEquals(toqueDevido(plano({ dias_para_vencer: -40, situacao: "vencida" }), [ev({ toque: 3 })]), null, "depois do 3º, nada ao cliente");
  // Evento de OUTRO ciclo não conta.
  assertEquals(toqueDevido(plano({ dias_para_vencer: 21 }), [ev({ due_on: "2025-10-28" })]), { toque: 1 });
});

Deno.test("toque: respondeu ou adiado → nada; barreiras viram 'pular' uma vez só", () => {
  assertEquals(toqueDevido(plano({ respondeu_no_ciclo: true }), []), null);
  assertEquals(toqueDevido(plano({ dias_para_vencer: 7 }), [ev({}), ev({ tipo: "client_replied", toque: null })]), null);
  assertEquals(toqueDevido(plano({ situacao: "adiada" }), []), null);
  assertEquals(toqueDevido(plano({ opt_out: true }), []), { toque: 1, pular: "opt_out" });
  assertEquals(toqueDevido(plano({ client_phone: null }), []), { toque: 1, pular: "sem_telefone" });
  assertEquals(toqueDevido(plano({ client_reminder_enabled: false }), []), { toque: 1, pular: "lembrete_desligado" });
  assertEquals(toqueDevido(plano({ tem_os_agendada: true }), []), { toque: 1, pular: "os_agendada" });
  assertEquals(toqueDevido(plano({ opt_out: true }), [ev({ tipo: "reminder_skipped" })]), null, "pulado já registrado não repete");
});

// ─── Agrupamento ────────────────────────────────────────────────────────────────────────────
Deno.test("agrupar: um cliente, vencimentos até 30 dias um do outro, UMA mensagem (e antecipa o que vence logo depois)", () => {
  const p1 = plano();
  const p2 = plano({ plan_id: "p2", plan_name: "Revisão do motor", next_due_on: "2026-11-20", dias_para_vencer: 44, situacao: "em_dia", estimated_value: 1000 });
  const p3 = plano({ plan_id: "p3", plan_name: "Revisão do inversor", next_due_on: "2026-12-30", dias_para_vencer: 84, situacao: "em_dia" });
  const p4 = plano({ plan_id: "p4", client_id: "c2", client_name: "Ana", vessel_id: "v2", vessel_name: "Brisa", next_due_on: "2026-10-25", dias_para_vencer: 18 });
  const p5 = plano({ plan_id: "p5", vessel_id: "v3", vessel_name: "Lua", next_due_on: "2026-10-30", dias_para_vencer: 23, situacao: "em_dia" });
  const grupos = agruparPorCliente(
    [{ plano: p1, toque: 1 }, { plano: p4, toque: 1 }],
    [p1, p2, p3, p4, p5],
    [],
  );
  assertEquals(grupos.map((g) => [g.client_id, g.planos.map((p) => p.plan_id)]), [
    ["c1", ["p1", "p5", "p2"]],
    ["c2", ["p4"]],
  ]);
  // Toques diferentes do mesmo cliente não se juntam; plano com evento no ciclo não é antecipado.
  const g2 = agruparPorCliente(
    [{ plano: p1, toque: 1 }, { plano: plano({ plan_id: "p6", next_due_on: "2026-10-12", dias_para_vencer: 5 }), toque: 2 }],
    [p1, p2],
    [ev({ plan_id: "p2", due_on: "2026-11-20", tipo: "reminder_skipped" })],
  );
  assertEquals(g2.map((g) => [g.toque, g.planos.map((p) => p.plan_id)]), [[1, ["p1"]], [2, ["p6"]]]);
});

// ─── Campanha ───────────────────────────────────────────────────────────────────────────────
Deno.test("campanha: só de 15/09 a 31/10; o mês oferecido vira o próximo depois do dia 20", () => {
  assertEquals(dentroDaCampanha("2026-09-14"), false);
  assertEquals(dentroDaCampanha("2026-09-15"), true);
  assertEquals(dentroDaCampanha("2026-10-31"), true);
  assertEquals(dentroDaCampanha("2026-11-01"), false);
  assertEquals(mesDaCampanha("2026-09-15"), "setembro");
  assertEquals(mesDaCampanha("2026-10-07"), "outubro");
  assertEquals(mesDaCampanha("2026-10-25"), "novembro");
});

// ─── Texto de cada toque ────────────────────────────────────────────────────────────────────
const item = { plano: "Revisão das baterias", embarcacao: "Mar Azul", vence: "2026-10-28", ultimoServicoEm: "2025-10-28", resumoUltimo: "troca de 4 baterias AGM", valor: 1500 };

Deno.test("texto: D-21 com último serviço, duas datas, faixa de valor e a saída PARAR", () => {
  assertEquals(
    montarTexto({ toque: 1, nome: "Carlos", hoje: "2026-10-07", itens: [item] }),
    "Oi, Carlos! Aqui é da HBR Marine. A revisão das baterias da Mar Azul vence dia 28/10 (a última foi em 28/10/2025: troca de 4 baterias AGM). " +
      "Tenho ter 27/10 de manhã ou qua 28/10 à tarde, em torno de R$ 1.280 a R$ 1.730. Qual fica melhor? " +
      "Se preferir não receber esses lembretes, responda PARAR.",
  );
  // Sem valor: a frase do valor some. Sem nome (empresa): "Oi!". Sem último serviço: sem parênteses.
  assertEquals(
    montarTexto({ toque: 1, nome: null, hoje: "2026-10-07", itens: [{ ...item, valor: null, ultimoServicoEm: null }] }),
    "Oi! Aqui é da HBR Marine. A revisão das baterias da Mar Azul vence dia 28/10. Tenho ter 27/10 de manhã ou qua 28/10 à tarde. Qual fica melhor? " +
      "Se preferir não receber esses lembretes, responda PARAR.",
  );
});

Deno.test("texto: dois planos do mesmo cliente numa mensagem, valor somado", () => {
  const t = montarTexto({
    toque: 1, nome: "Carlos", hoje: "2026-10-07",
    itens: [{ ...item, plano: "Revisão do motor", vence: "2026-11-20", valor: 1000 }, item],
  });
  assertEquals(
    t,
    "Oi, Carlos! Aqui é da HBR Marine. Estão chegando duas revisões: a revisão das baterias da Mar Azul (vence 28/10) e a revisão do motor da Mar Azul (vence 20/11). " +
      "Tenho ter 27/10 de manhã ou qua 28/10 à tarde para fazer as duas juntas, em torno de R$ 2.130 a R$ 2.880. Qual fica melhor? " +
      "Se preferir não receber esses lembretes, responda PARAR.",
  );
  // Um deles sem valor: não chuta a soma.
  const sem = montarTexto({ toque: 1, nome: "Carlos", hoje: "2026-10-07", itens: [item, { ...item, plano: "Revisão do motor", valor: null }] });
  assertEquals(sem.includes("R$"), false);
});

Deno.test("texto: D-7, D+14 e campanha seguem os modelos", () => {
  assertEquals(
    montarTexto({ toque: 2, nome: "Carlos", hoje: "2026-10-21", itens: [item] }),
    "Carlos, só lembrando da revisão das baterias da Mar Azul (vence 28/10). Quer que eu reserve ter 27/10 de manhã? Responda SIM ou sugira outro dia.",
  );
  assertEquals(
    montarTexto({ toque: 3, nome: "Carlos", hoje: "2026-11-11", itens: [item] }),
    "Carlos, a revisão das baterias da Mar Azul venceu em 28/10. Ainda faz sentido agendar ou prefere que eu tire do calendário?",
  );
  assertEquals(
    montarTexto({ toque: 3, nome: null, hoje: "2026-11-11", itens: [item] }),
    "A revisão das baterias da Mar Azul venceu em 28/10. Ainda faz sentido agendar ou prefere que eu tire do calendário?",
  );
  assertEquals(
    montarTexto({ toque: 0, nome: "Carlos", hoje: "2026-10-07", itens: [], embarcacoes: ["Mar Azul", "Brisa"] }),
    "Oi, Carlos! Aqui é da HBR Marine. Antes do verão a agenda lota. Quer deixar a parte elétrica da Mar Azul e da Brisa conferida ainda em outubro " +
      "(baterias, carregador e inversor)? Me diz uma semana que eu encaixo. Se preferir não receber esses lembretes, responda PARAR.",
  );
  assertStringIncludes(montarTexto({ toque: 0, nome: null, hoje: "2026-10-25", itens: [], embarcacoes: ["Lua"] }), "ainda em novembro");
});
