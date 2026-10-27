// A janela da agenda na hora de enviar — a 3ª trava (Agenda de Produção, Fase 4, P5: a origem do fornecedor).
//
// O que estes testes protegem (o laço do worker está em whatsapp-queue-worker/enviar_test.ts):
//  1. 'agenda-fornecedor' é origem da agenda, com a janela 'fornecedor'; nenhuma outra origem nova ganhou janela;
//  2. a janela do fornecedor: o dia dela, [fornecedor_janela_inicio, fornecedor_janela_fim) de Brasília (início fechado, fim
//     aberto), segunda a sexta — o sábado só com fornecedor_sabado (motivo fim_de_semana), nunca o domingo — e só com
//     modo_fornecedor = 'ligado'; os horários são os do banco;
//  3. a leitura da janela do fornecedor é um SELECT à parte, só das colunas dela (a da equipe continua a mesma, sem coluna
//     nova); erro, sem a linha, horário ilegível ou o sábado que não é sim/não = lança (a linha não sai);
//  4. faltando a janela da origem (a outra foi lida, esta não), a linha não sai; a equipe segue igual (o sábado é dia dela,
//     a resposta direta continua só dela).
//  5. (Fase 5, P2) 'agenda-cliente' é origem da agenda, com a janela 'cliente': [cliente_janela_inicio, cliente_janela_fim)
//     de segunda a sexta, até cliente_sabado_fim no sábado, nunca domingo nem feriado (Finados, o 15/06 de Itajaí, a
//     Sexta-feira Santa: a lista de feriados.ts), só com modo_cliente = 'ligado'; um SELECT à parte, só das colunas dela;
//     a resposta do banco (agenda_cliente_pode_sair) lida por recusaDoBanco; a equipe e o fornecedor não ganham o feriado.
import { assertEquals, assertRejects, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  COLUNAS_DA_JANELA,
  COLUNAS_DA_JANELA_DO_CLIENTE,
  COLUNAS_DA_JANELA_DO_FORNECEDOR,
  ehMensagemAoCliente,
  ehRespostaDireta,
  janelaDaOrigem,
  type JanelasDaAgenda,
  lerJanelasDaAgenda,
  origemComJanelaDaAgenda,
  recusaDoBanco,
  recusaNaHoraDeEnviar,
} from "./janela-da-fila.ts";

/** Brasília é UTC−3 (sem horário de verão desde 2019). */
const brt = (diaHora: string) => new Date(`${diaHora}-03:00`);
const linha = (marcada: string, source = "agenda-fornecedor", extra: Record<string, unknown> = {}) => ({
  source, scheduled_for: brt(marcada).toISOString(), ...extra,
});

/** As janelas do DEFAULT de 20261027100000 (fornecedor) e de 20261026100000 (equipe). */
const FORNECEDOR = { ligado: true, inicio: "08:00:00", fim: "18:00:00", sabado: false };
const EQUIPE = { ligado: true, inicio: "07:30:00", fim: "20:00:00" };
const RD = { inicio: "06:00:00", fim: "22:00:00", prazoSegundos: 600 };
const TODAS: JanelasDaAgenda = { equipe: EQUIPE, respostaDireta: RD, fornecedor: FORNECEDOR };

function bancoDeMentira(respostas: Record<string, { data?: unknown; error?: unknown }>) {
  const leituras: string[] = [];
  const db = {
    from(tabela: string) {
      return {
        select(colunas: string) {
          leituras.push(`${tabela}: ${colunas}`);
          const r = respostas[colunas] ?? { data: null, error: { message: `coluna não esperada: ${colunas}` } };
          return { maybeSingle: async () => ({ data: r.data ?? null, error: r.error ?? null }) };
        },
      };
    },
  };
  return { db, leituras };
}

Deno.test("origens: agenda-fornecedor tem a janela do fornecedor; agenda-equipe a da equipe; as outras, nenhuma", () => {
  assertEquals(origemComJanelaDaAgenda("agenda-fornecedor"), true);
  assertEquals(janelaDaOrigem("agenda-fornecedor"), "fornecedor");
  assertEquals(janelaDaOrigem("agenda-equipe"), "equipe");
  for (const o of [null, undefined, "", "reply-router", "quote-reminders", "Agenda-Cliente", "Agenda-Fornecedor",
                   "agenda-fornecedor ", "fornecedor", "quote-request", 7]) {
    assertEquals(origemComJanelaDaAgenda(o), false, String(o));
    assertEquals(janelaDaOrigem(o), null, String(o));
    assertEquals(recusaNaHoraDeEnviar({ source: o, scheduled_for: "x" }, brt("2026-11-01T23:00:00"), null), null);
  }
  // a do fornecedor não tem resposta direta (a chave nunca a abre)
  assertEquals(ehRespostaDireta({ source: "agenda-fornecedor", dedupe_key: "agenda-equipe:resposta:x:y" }), false);
});

Deno.test("fornecedor: o início fechado e o fim aberto (08:00:00 sai, 18:00:00 não), no dia dela", () => {
  const casos: Array<[string, string, string | null]> = [
    ["2026-10-28T08:00:00", "2026-10-28T08:00:00", null],
    ["2026-10-28T07:59:00", "2026-10-28T07:59:59", "janela"],
    ["2026-10-28T17:59:00", "2026-10-28T17:59:59", null],
    ["2026-10-28T17:59:00", "2026-10-28T18:00:00", "janela"],
    ["2026-10-28T10:00:00", "2026-10-28T22:00:00", "janela"],
    // a linha de ontem (o worker parado) não sai hoje, nem dentro da janela
    ["2026-10-27T17:30:00", "2026-10-28T09:00:00", "janela"],
    // a sexta é dia dele
    ["2026-10-30T10:00:00", "2026-10-30T10:00:00", null],
  ];
  for (const [marcada, agora, motivo] of casos) {
    assertEquals(recusaNaHoraDeEnviar(linha(marcada), brt(agora), TODAS)?.motivo ?? null, motivo, `${marcada} → ${agora}`);
  }
  const r = recusaNaHoraDeEnviar(linha("2026-10-28T10:00:00"), brt("2026-10-28T19:00:00"), TODAS);
  assertEquals(r?.texto, "agenda-fornecedor: fora da janela na hora de enviar (08:00–18:00): não saiu");
  const ontem = recusaNaHoraDeEnviar(linha("2026-10-27T17:30:00"), brt("2026-10-28T09:00:00"), TODAS);
  assertEquals(ontem?.texto, "agenda-fornecedor: era para 27/10 e não saiu no dia dela");
});

Deno.test("fornecedor: sábado = fim_de_semana (com fornecedor_sabado, sai na janela); domingo nunca; os horários do banco", () => {
  const sab = linha("2026-10-31T10:00:00");
  const r = recusaNaHoraDeEnviar(sab, brt("2026-10-31T10:00:00"), TODAS);
  assertEquals(r, { motivo: "fim_de_semana", texto: "agenda-fornecedor: sábado, não sai (só de segunda a sexta)" });
  const comSabado: JanelasDaAgenda = { fornecedor: { ...FORNECEDOR, sabado: true } };
  assertEquals(recusaNaHoraDeEnviar(sab, brt("2026-10-31T10:00:00"), comSabado), null);
  assertEquals(recusaNaHoraDeEnviar(linha("2026-10-31T18:30:00"), brt("2026-10-31T18:30:00"), comSabado)?.motivo, "janela");
  const dom = recusaNaHoraDeEnviar(linha("2026-11-01T10:00:00"), brt("2026-11-01T10:00:00"), comSabado);
  assertEquals(dom, { motivo: "domingo", texto: "agenda-fornecedor: domingo, não sai (nunca no domingo)" });
  // os horários são os do banco: com a janela das 09:00 às 17:00, as 08:30 e as 17:00 não saem, as 16:59 sim
  const outra: JanelasDaAgenda = { fornecedor: { ligado: true, inicio: "09:00", fim: "17:00", sabado: false } };
  assertEquals(recusaNaHoraDeEnviar(linha("2026-10-28T08:30:00"), brt("2026-10-28T08:30:00"), outra)?.motivo, "janela");
  assertEquals(recusaNaHoraDeEnviar(linha("2026-10-28T16:59:00"), brt("2026-10-28T16:59:00"), outra), null);
  assertEquals(recusaNaHoraDeEnviar(linha("2026-10-28T17:00:00"), brt("2026-10-28T17:00:00"), outra)?.motivo, "janela");
});

Deno.test("fornecedor: com modo_fornecedor fora de ligado, nada sai (motivo modo, com o nome do modo dele)", () => {
  const r = recusaNaHoraDeEnviar(linha("2026-10-28T10:00:00"), brt("2026-10-28T10:00:00"),
    { fornecedor: { ...FORNECEDOR, ligado: false } });
  assertEquals(r, { motivo: "modo", texto: "agenda-fornecedor: modo_fornecedor saiu de ligado" });
  // a equipe continua dizendo o dela
  const e = recusaNaHoraDeEnviar(linha("2026-10-28T10:00:00", "agenda-equipe"), brt("2026-10-28T10:00:00"),
    { equipe: { ...EQUIPE, ligado: false }, respostaDireta: RD });
  assertEquals(e, { motivo: "modo", texto: "agenda-equipe: modo_equipe saiu de ligado" });
});

Deno.test("faltando a janela da origem (só a outra foi lida, ou a leitura falhou), a linha não sai", () => {
  const soEquipe: JanelasDaAgenda = { equipe: EQUIPE, respostaDireta: RD };
  const r = recusaNaHoraDeEnviar(linha("2026-10-28T10:00:00"), brt("2026-10-28T10:00:00"), soEquipe);
  assertEquals(r?.motivo, "janela");
  assertStringIncludes(String(r?.texto), "não consegui ler a janela da agenda (sem a janela fornecedor)");
  const soFornecedor: JanelasDaAgenda = { fornecedor: FORNECEDOR };
  const e = recusaNaHoraDeEnviar(linha("2026-10-28T10:00:00", "agenda-equipe"), brt("2026-10-28T10:00:00"), soFornecedor);
  assertEquals(e?.motivo, "janela");
  const falhou = recusaNaHoraDeEnviar(linha("2026-10-28T10:00:00"), brt("2026-10-28T10:00:00"), null, "timeout");
  assertEquals(falhou?.texto, "agenda-fornecedor: não consegui ler a janela da agenda (timeout): não saiu");
});

Deno.test("equipe igual: o sábado é dia dela, a janela 07:30–20:00, a resposta direta só dela", () => {
  const sab = linha("2026-10-31T08:00:00", "agenda-equipe");
  assertEquals(recusaNaHoraDeEnviar(sab, brt("2026-10-31T08:00:00"), TODAS), null);
  assertEquals(recusaNaHoraDeEnviar(linha("2026-10-28T19:59:00", "agenda-equipe"), brt("2026-10-28T19:59:59"), TODAS), null);
  assertEquals(recusaNaHoraDeEnviar(linha("2026-10-28T19:59:00", "agenda-equipe"), brt("2026-10-28T20:00:00"), TODAS)?.motivo, "janela");
  const resp = linha("2026-10-28T21:00:00", "agenda-equipe", { dedupe_key: "agenda-equipe:resposta:p:wa" });
  assertEquals(recusaNaHoraDeEnviar(resp, brt("2026-10-28T21:05:00"), TODAS), null);
  // a mesma chave numa linha do fornecedor não ganha a janela da resposta direta
  const forn = linha("2026-10-28T21:00:00", "agenda-fornecedor", { dedupe_key: "agenda-equipe:resposta:p:wa" });
  assertEquals(recusaNaHoraDeEnviar(forn, brt("2026-10-28T21:05:00"), TODAS)?.motivo, "janela");
});

Deno.test("leitura do fornecedor: um SELECT só das colunas dele; a da equipe continua a mesma (nenhuma coluna nova)", async () => {
  assertEquals(COLUNAS_DA_JANELA_DO_FORNECEDOR, "modo_fornecedor, fornecedor_janela_inicio, fornecedor_janela_fim, fornecedor_sabado");
  assertEquals(COLUNAS_DA_JANELA.includes("fornecedor"), false);
  const { db, leituras } = bancoDeMentira({
    [COLUNAS_DA_JANELA_DO_FORNECEDOR]: {
      data: { modo_fornecedor: "ligado", fornecedor_janela_inicio: "08:00:00", fornecedor_janela_fim: "18:00:00", fornecedor_sabado: false },
    },
  });
  assertEquals(await lerJanelasDaAgenda(db, "fornecedor"), { fornecedor: FORNECEDOR });
  assertEquals(leituras, [`agenda_config: ${COLUNAS_DA_JANELA_DO_FORNECEDOR}`]);
  // " Sombra " e qualquer coisa que não seja ligado = desligado
  for (const modo of [" Sombra ", "desligado", null, "LIGADO "]) {
    const { db: d } = bancoDeMentira({
      [COLUNAS_DA_JANELA_DO_FORNECEDOR]: {
        data: { modo_fornecedor: modo, fornecedor_janela_inicio: "08:00", fornecedor_janela_fim: "18:00", fornecedor_sabado: true },
      },
    });
    assertEquals((await lerJanelasDaAgenda(d, "fornecedor")).fornecedor?.ligado, modo === "LIGADO ", String(modo));
  }
  // a da equipe: o mesmo SELECT de antes
  const eq = bancoDeMentira({
    [COLUNAS_DA_JANELA]: {
      data: { modo_equipe: "ligado", equipe_janela_inicio: "07:30:00", equipe_janela_fim: "20:00:00",
              equipe_resposta_direta_inicio: "06:00:00", equipe_resposta_direta_fim: "22:00:00", equipe_resposta_direta_prazo: "00:10:00" },
    },
  });
  assertEquals(await lerJanelasDaAgenda(eq.db), { equipe: EQUIPE, respostaDireta: RD });
  assertEquals(eq.leituras, [`agenda_config: ${COLUNAS_DA_JANELA}`]);
});

Deno.test("leitura do fornecedor: erro, sem a linha, horário ilegível e o sábado que não é sim/não lançam", async () => {
  const ok = { modo_fornecedor: "ligado", fornecedor_janela_inicio: "08:00", fornecedor_janela_fim: "18:00", fornecedor_sabado: false };
  const casos: Array<[{ data?: unknown; error?: unknown }, string]> = [
    [{ error: { message: "column agenda_config.modo_fornecedor does not exist", code: "42703" } }, "modo_fornecedor does not exist"],
    [{ data: null }, "sem a linha de parâmetros"],
    [{ data: { ...ok, fornecedor_janela_inicio: "oito horas" } }, "a janela do fornecedor está ilegível"],
    [{ data: { ...ok, fornecedor_janela_fim: null } }, "a janela do fornecedor está ilegível"],
    [{ data: { ...ok, fornecedor_sabado: "false" } }, "o sábado do fornecedor está ilegível"],
    [{ data: { ...ok, fornecedor_sabado: null } }, "o sábado do fornecedor está ilegível"],
  ];
  for (const [resp, trecho] of casos) {
    const { db } = bancoDeMentira({ [COLUNAS_DA_JANELA_DO_FORNECEDOR]: resp });
    await assertRejects(() => lerJanelasDaAgenda(db, "fornecedor"), Error, trecho);
  }
});

// ── 5. (Fase 5, P2) A mensagem ao cliente ───────────────────────────────────────────────────────────────
/** A janela do cliente do DEFAULT de 20261028100000. */
const CLIENTE = { ligado: true, inicio: "08:00:00", fim: "19:00:00", sabadoFim: "13:00:00" };
const COM_CLIENTE: JanelasDaAgenda = { ...TODAS, cliente: CLIENTE };
const cli = (marcada: string) => linha(marcada, "agenda-cliente");

Deno.test("P2 origens: agenda-cliente tem a janela do cliente; só ela é mensagem ao cliente; sem resposta direta", () => {
  assertEquals(origemComJanelaDaAgenda("agenda-cliente"), true);
  assertEquals(janelaDaOrigem("agenda-cliente"), "cliente");
  assertEquals(ehMensagemAoCliente("agenda-cliente"), true);
  for (const o of ["agenda-equipe", "agenda-fornecedor", "agenda-confirmacao", "Agenda-Cliente", "agenda-cliente ", null, 7]) {
    assertEquals(ehMensagemAoCliente(o), false, String(o));
  }
  assertEquals(ehRespostaDireta({ source: "agenda-cliente", dedupe_key: "agenda-equipe:resposta:x:y" }), false);
  // o botão antigo (agenda-confirmacao) continua fora da janela da agenda, como antes
  assertEquals(origemComJanelaDaAgenda("agenda-confirmacao"), false);
});

Deno.test("P2 cliente de segunda a sexta: 07:59 não, 08:00 sim, 18:59 sim, 19:00 não; só no dia dela", () => {
  const casos: Array<[string, string, string | null]> = [
    ["2026-10-30T07:59:00", "2026-10-30T07:59:59", "janela"],
    ["2026-10-30T08:00:00", "2026-10-30T08:00:00", null],
    ["2026-10-30T18:59:00", "2026-10-30T18:59:59", null],
    ["2026-10-30T18:59:00", "2026-10-30T19:00:00", "janela"],
    ["2026-10-29T18:00:00", "2026-10-30T09:00:00", "janela"],
  ];
  for (const [marcada, agora, motivo] of casos) {
    assertEquals(recusaNaHoraDeEnviar(cli(marcada), brt(agora), COM_CLIENTE)?.motivo ?? null, motivo, `${marcada} → ${agora}`);
  }
  assertEquals(recusaNaHoraDeEnviar(cli("2026-10-30T10:00:00"), brt("2026-10-30T19:30:00"), COM_CLIENTE)?.texto,
    "agenda-cliente: fora da janela na hora de enviar (08:00–19:00): não saiu");
});

Deno.test("P2 cliente no sábado: até cliente_sabado_fim (12:59 sim, 13:00 não); domingo nunca", () => {
  assertEquals(recusaNaHoraDeEnviar(cli("2026-10-31T09:00:00"), brt("2026-10-31T09:00:00"), COM_CLIENTE), null);
  assertEquals(recusaNaHoraDeEnviar(cli("2026-10-31T12:59:00"), brt("2026-10-31T12:59:59"), COM_CLIENTE), null);
  const r = recusaNaHoraDeEnviar(cli("2026-10-31T12:59:00"), brt("2026-10-31T13:00:00"), COM_CLIENTE);
  assertEquals(r, { motivo: "janela", texto: "agenda-cliente: fora da janela na hora de enviar (08:00–13:00): não saiu" });
  assertEquals(recusaNaHoraDeEnviar(cli("2026-11-01T10:00:00"), brt("2026-11-01T10:00:00"), COM_CLIENTE),
    { motivo: "domingo", texto: "agenda-cliente: domingo, não sai (nunca no domingo)" });
  // o fim do sábado é o do banco: até 14:00, as 13:30 saem
  const outra: JanelasDaAgenda = { cliente: { ...CLIENTE, sabadoFim: "14:00" } };
  assertEquals(recusaNaHoraDeEnviar(cli("2026-10-31T13:30:00"), brt("2026-10-31T13:30:00"), outra), null);
});

Deno.test("P2 cliente: nunca em feriado (Finados, o 15/06 de Itajaí, a Sexta-feira Santa); a equipe e o fornecedor não ganham o feriado", () => {
  for (const [dia, nome] of [["2026-11-02", "Finados"], ["2027-06-15", "aniversário de Itajaí"], ["2027-03-26", "Sexta-feira Santa"]]) {
    const r = recusaNaHoraDeEnviar(cli(`${dia}T10:00:00`), brt(`${dia}T10:00:00`), COM_CLIENTE);
    assertEquals(r, { motivo: "feriado", texto: `agenda-cliente: feriado (${nome}), não sai` }, dia);
  }
  // a equipe e o fornecedor seguem iguais no feriado (quem marca a hora deles nunca a põe num feriado)
  assertEquals(recusaNaHoraDeEnviar(linha("2026-11-02T10:00:00", "agenda-equipe"), brt("2026-11-02T10:00:00"), COM_CLIENTE), null);
  assertEquals(recusaNaHoraDeEnviar(linha("2026-11-02T10:00:00"), brt("2026-11-02T10:00:00"), COM_CLIENTE), null);
});

Deno.test("P2 cliente: modo_cliente fora de ligado = modo; sem a janela do cliente (só as outras lidas) = não sai", () => {
  assertEquals(recusaNaHoraDeEnviar(cli("2026-10-30T10:00:00"), brt("2026-10-30T10:00:00"), { cliente: { ...CLIENTE, ligado: false } }),
    { motivo: "modo", texto: "agenda-cliente: modo_cliente saiu de ligado" });
  const r = recusaNaHoraDeEnviar(cli("2026-10-30T10:00:00"), brt("2026-10-30T10:00:00"), TODAS);
  assertEquals(r?.motivo, "janela");
  assertStringIncludes(String(r?.texto), "não consegui ler a janela da agenda (sem a janela cliente)");
});

Deno.test("P2 leitura do cliente: um SELECT só das colunas dele; erro, sem a linha e horário ilegível lançam", async () => {
  assertEquals(COLUNAS_DA_JANELA_DO_CLIENTE, "modo_cliente, cliente_janela_inicio, cliente_janela_fim, cliente_sabado_fim");
  assertEquals(COLUNAS_DA_JANELA.includes("cliente"), false);
  assertEquals(COLUNAS_DA_JANELA_DO_FORNECEDOR.includes("cliente"), false);
  const ok = { modo_cliente: "ligado", cliente_janela_inicio: "08:00:00", cliente_janela_fim: "19:00:00", cliente_sabado_fim: "13:00:00" };
  const { db, leituras } = bancoDeMentira({ [COLUNAS_DA_JANELA_DO_CLIENTE]: { data: ok } });
  assertEquals(await lerJanelasDaAgenda(db, "cliente"), { cliente: CLIENTE });
  assertEquals(leituras, [`agenda_config: ${COLUNAS_DA_JANELA_DO_CLIENTE}`]);
  const { db: sombra } = bancoDeMentira({ [COLUNAS_DA_JANELA_DO_CLIENTE]: { data: { ...ok, modo_cliente: "sombra" } } });
  assertEquals((await lerJanelasDaAgenda(sombra, "cliente")).cliente?.ligado, false);
  const casos: Array<[{ data?: unknown; error?: unknown }, string]> = [
    [{ error: { message: "column agenda_config.modo_cliente does not exist", code: "42703" } }, "modo_cliente does not exist"],
    [{ data: null }, "sem a linha de parâmetros"],
    [{ data: { ...ok, cliente_janela_inicio: "oito" } }, "a janela do cliente está ilegível"],
    [{ data: { ...ok, cliente_sabado_fim: null } }, "a janela do cliente está ilegível"],
  ];
  for (const [resp, trecho] of casos) {
    const { db: d } = bancoDeMentira({ [COLUNAS_DA_JANELA_DO_CLIENTE]: resp });
    await assertRejects(() => lerJanelasDaAgenda(d, "cliente"), Error, trecho);
  }
});

Deno.test("P2 recusaDoBanco: {pode: true} sai; o motivo do banco vira a recusa; erro, resposta estranha ou motivo que não é nome = janela", () => {
  assertEquals(recusaDoBanco({ data: { pode: true, motivo: null } }), null);
  assertEquals(recusaDoBanco({ data: { pode: false, motivo: "status" } }),
    { motivo: "status", texto: "agenda-cliente: o banco diz que não sai mais (status): não saiu" });
  for (const m of ["tipo_em_teste", "vencida", "opt_out", "data_mudou", "material", "passou_da_data", "mesmo_tipo_24h",
                   "desatualizada", "feriado", "domingo", "modo"]) {
    assertEquals(recusaDoBanco({ data: { pode: false, motivo: m } })?.motivo, m, m);
  }
  assertEquals(recusaDoBanco({ data: { pode: false, motivo: "outra coisa" } })?.motivo, "janela");
  assertEquals(recusaDoBanco({ data: { pode: false, motivo: "Status" } })?.motivo, "janela");
  assertEquals(recusaDoBanco({ data: { pode: false, motivo: 7 } })?.motivo, "janela");
  assertEquals(recusaDoBanco({ data: { pode: "true" } })?.motivo, "janela");
  assertEquals(recusaDoBanco({ data: null })?.motivo, "janela");
  assertEquals(recusaDoBanco({}), { motivo: "janela", texto: "agenda-cliente: o banco diz que não sai mais (sem resposta): não saiu" });
  assertEquals(recusaDoBanco({ error: { message: "function agenda_cliente_pode_sair does not exist", code: "42883" } }), {
    motivo: "janela",
    texto: "agenda-cliente: não consegui perguntar ao banco se ainda vale (function agenda_cliente_pode_sair does not exist): não saiu",
  });
});
