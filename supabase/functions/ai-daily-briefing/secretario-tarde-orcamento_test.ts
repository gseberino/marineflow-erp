// Retorno rápido, F5 (P10.3): o orçamento enviado na tarde — a linha fixa ("amanhã sai sozinho … · *segura 151*") logo depois
// do "Mandei sozinho", nos três turnos, escapando dos três cortes; as linhas como extras do fechamento, depois das do parceiro;
// e o registro do aviso (orcamento_avisados) só depois de a tarde com a linha fixa ir à fila. Banco falso; nomes e números
// inventados (o falsoAdmin é o molde de secretario-tarde_test.ts).
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type LidoDaTarde, montarTardeDosDados, rodarTurnoDaTarde } from "./secretario-tarde.ts";
import {
  type AgendaDoFechamento,
  type BlocoDaAgenda,
  type DadosDaTarde,
  LIMITE_DA_TARDE,
  type LinhaDoBloco,
  textoDaTarde,
} from "./secretario-tarde-texto.ts";
import type { LinhaComLetra } from "./secretario-tarde-regras.ts";

const FIXA = "Orçamentos: amanhã sai sozinho o lembrete do ORÇ-00151 (Ana) · *segura 151*";
const LINHA_ORC = "Encerrado hoje sem resposta: ORÇ-00140 (Pedro) · para marcar como perdido, use a tela ou o assistente";
const LINHA_PARCEIRO = "Pátio da MP: 4 veículos, 2 mudaram · *parceiro* para liberar";
const MANDEI = "Mandei sozinho hoje: Z) 'aguardando peça' ao Rodrigo · *errado Z*";
const ESPERANDO = "Ainda esperando hoje: Paulo (prometi até 19h).";
const RESUMO = "Retorno hoje: 3 recibos a clientes.";

function ficou(letra: string, texto: string): LinhaComLetra {
  return {
    letra, parte: "ficou", referencia: `ref:${letra}`, tipo: "cobranca_grande", texto, faco: "te mostro o lembrete pronto",
    alternativa: "até segunda", comandoAlternativo: "espera", valor: 100, desde: "2026-10-13",
  } as LinhaComLetra;
}

const ESCRITORIO = { propostas: { saidas: 107, entradas: 10, transferencias: 1, outras: 0 }, alertas: 33, regras: 0, debitosSemLoja: 8, entradas: null };
const BASE = { ficaram: [], fornecedores: [], escritorio: null, parados: [], panorama: null, antigas: null, mesQueFechou: null, faturamento: null, pergunta: false };

/** qua 09/12 (fechamento), seg 07/12 (revisão da semana), ter 01/12 (revisão do mês). */
function turno(t: "fechamento" | "revisao_semana" | "revisao_mes", extra: Partial<DadosDaTarde> = {}): DadosDaTarde {
  const hoje = t === "fechamento" ? "2026-12-09" : t === "revisao_semana" ? "2026-12-07" : "2026-12-01";
  return { ...BASE, hoje, turno: t, amanha: { dia: "2026-12-10", itens: [], carteira: { semData: 2 } }, ...extra } as unknown as DadosDaTarde;
}

/** Um Secretário cheio de produção (~950 letras): 3 que ficaram, fornecedores, o escritório e o "sem resposta". */
const CHEIO: Partial<DadosDaTarde> = {
  ficaram: [
    ficou("A", "OS-00112 Nelson (Santo Inácio 7.8): 4 itens a comprar até seg 26/10"),
    ficou("B", "Marcelo Marco Bertoldi (OS-00038): R$ 16.890,00, venceu 13/10 (16 dias); ainda não entrou"),
    ficou("C", "APOLO INDUSTRIA E COMERCIO DE…: R$ 5.237,99, venceu 16/10 (13 dias); ainda não entrou"),
  ],
  fornecedores: ["SR Contabilidade", "Kamell Distribuidora", "Dometic do Brasil"],
  escritorio: ESCRITORIO as unknown as DadosDaTarde["escritorio"],
  semResposta: [{ nome: "Giancarlo S.", desde: "10:31" }, { nome: "Miguel", desde: "09:02", acordei: "09:45" }] as unknown as DadosDaTarde["semResposta"],
  pergunta: true,
};

const comFixa = (d: DadosDaTarde): DadosDaTarde => ({ ...d, orcamento: { fixas: [FIXA] } });

// ─── O texto (secretario-tarde-texto.ts) ───────────────────────────────────────────────────────────────────────────

Deno.test("sem a linha fixa, byte a byte o de antes nos três turnos (orcamento nulo, ausente ou com fixas vazias)", () => {
  for (const t of ["fechamento", "revisao_semana", "revisao_mes"] as const) {
    for (const extra of [{}, CHEIO, { retorno: { esperando: ESPERANDO, resumo: RESUMO, mandei: MANDEI } }]) {
      const d = turno(t, extra);
      const antes = textoDaTarde(d);
      assertEquals(textoDaTarde({ ...d, orcamento: null }), antes, t);
      assertEquals(textoDaTarde({ ...d, orcamento: { fixas: [] } }), antes, t);
    }
  }
});

Deno.test("fechamento: a linha fixa logo depois do 'Ainda esperando hoje' e do 'Mandei sozinho', antes do topo", () => {
  const d = turno("fechamento", { fornecedores: ["SR Contabilidade"], retorno: { esperando: ESPERANDO, resumo: null, mandei: MANDEI } });
  const linhas = textoDaTarde(comFixa(d)).texto!.split("\n");
  assertEquals(linhas.slice(0, 4), [
    "Fechamento de quarta, 09/12: nada ficou de hoje, fora quem espera resposta.", ESPERANDO, MANDEI, FIXA,
  ]);
  // sem "Mandei sozinho", logo depois do "Ainda esperando"
  const semMandei = textoDaTarde(comFixa(turno("fechamento", { retorno: { esperando: ESPERANDO, resumo: null } }))).texto!.split("\n");
  assertEquals(semMandei.slice(1, 3), [ESPERANDO, FIXA]);
});

Deno.test("fechamento: a linha fixa sozinha já é 'há algo' (sem ela, o dia calado e o passo iria ao cartão)", () => {
  assertEquals(textoDaTarde(turno("fechamento")).texto, null);
  const t = textoDaTarde(comFixa(turno("fechamento"))).texto!;
  assertStringIncludes(t, FIXA);
});

Deno.test("fechamento de ~990 letras com a linha fixa: a linha fica, logo depois do 'Mandei sozinho'; as extras saem antes", () => {
  const d = turno("fechamento", { ...CHEIO, retorno: { esperando: null, resumo: RESUMO, mandei: MANDEI, extras: [LINHA_ORC, LINHA_PARCEIRO] } });
  const t = textoDaTarde(comFixa(d)).texto!;
  const linhas = t.split("\n");
  assertEquals(linhas[1], MANDEI);
  assertEquals(linhas[2], FIXA);
  assert(!t.includes(LINHA_ORC) && !t.includes(LINHA_PARCEIRO) && !t.includes(RESUMO), "as extras saíram antes");
  for (const l of ["*A.*", "*B.*", "*C.*"]) assertStringIncludes(t, l);
  assert(!t.endsWith("…"), "sem o corte duro");
});

Deno.test("com o bloco da agenda ligado e o Secretário cheio (textoComOBloco), a linha fixa fica", () => {
  const l = (parte: LinhaDoBloco["parte"], texto: string, entra: number, corte: number | null): LinhaDoBloco =>
    ({ parte, texto, pergunta_id: null, acao_ids: [], nivel_entra: entra, nivel_de_corte: corte }) as LinhaDoBloco;
  const bloco: BlocoDaAgenda = {
    modo: "ligado", nivel: 0, nivel_min: 2, chars: 400, nada_mudou: false, incompleto: false,
    linhas: [
      l("veredito", "Agenda: mudei 1 coisa e preciso de 1 resposta sua. Amanhã (qui 10/12): Nelson com Roberto.", 0, null),
      l("decisao", "· Decisão 1: Giancarlo: não cabe tudo até sex 11/12. Recomendo a opção 1: termina ter 15/12 em vez de sex 11/12.", 0, null),
      l("compras", "Compras: Kamell: cabo de Nelson — compre até qui 10/12.", 0, 1),
    ],
  } as unknown as BlocoDaAgenda;
  const agenda = { modo: "ligado", cauda: null, semana: [], linhas: [], vagas_garantidas: 1, bloco } as unknown as AgendaDoFechamento;
  const d = turno("fechamento", { ...CHEIO, amanha: { dia: "2026-12-10", itens: [], carteira: { semData: 2 }, agenda } as unknown as DadosDaTarde["amanha"], retorno: { esperando: null, resumo: null, mandei: MANDEI } });
  const t = textoDaTarde(comFixa(d)).texto!;
  assertStringIncludes(t, FIXA);
  assertEquals(t.split("\n").indexOf(FIXA), t.split("\n").indexOf(MANDEI) + 1);
  assertStringIncludes(t, "Agenda: mudei 1 coisa");
});

Deno.test("tudo cheio e sem 'Ainda esperando hoje': com a linha fixa o texto sai inteiro, acima de 1.000, sem '…' (o corte duro não roda)", () => {
  const longas = ["A", "B", "C"].map((x) => ({
    ...ficou(x, `${x} ${"cobrança longa ".repeat(30)}`), faco: "te mostro o lembrete pronto de novo com a lista inteira", alternativa: "até a semana que vem, sem falta nenhuma",
  }));
  // o "Mandei sozinho" nunca encurta: com ele longo, nem a forma curta cabe
  const mandeiLongo = `Mandei sozinho hoje: ${Array.from({ length: 20 }, (_, i) => `Z) 'aguardando peça' ao Cliente ${i + 1}`).join(" · ")} · *errado Z*`;
  const d = turno("fechamento", { ficaram: longas, retorno: { esperando: null, resumo: null, mandei: mandeiLongo } });
  const sem = textoDaTarde(d).texto!;
  assert(sem.endsWith("…"), "a base: sem a linha fixa, o corte duro de sempre");
  const t = textoDaTarde(comFixa(d)).texto!;
  assert(t.length > LIMITE_DA_TARDE, String(t.length));
  assert(!t.endsWith("…"), t.slice(-40));
  assertStringIncludes(t, FIXA);
  for (const x of ["A", "B", "C"]) assertStringIncludes(t, `*${x}.*`);
});

Deno.test("revisão da semana e do mês: a linha fixa logo depois do 'Mandei sozinho'; as linhas do orçamento não entram", () => {
  for (const t of ["revisao_semana", "revisao_mes"] as const) {
    const d = turno(t, { retorno: { esperando: ESPERANDO, resumo: null, mandei: MANDEI, extras: [] } });
    const linhas = textoDaTarde(comFixa(d)).texto!.split("\n");
    assertEquals(linhas.slice(1, 4), [ESPERANDO, MANDEI, FIXA], t);
    // cheia, a linha também fica
    const cheia = textoDaTarde(comFixa(turno(t, { ...CHEIO, parados: CHEIO.ficaram, retorno: { esperando: null, resumo: null, mandei: MANDEI } }))).texto!;
    assertStringIncludes(cheia, FIXA, t);
  }
});

// ─── A montagem (secretario-tarde.ts, montarTardeDosDados) ─────────────────────────────────────────────────────────

const COLETA_VAZIA = { cobrancas: [], conversas: [], oss: [], compras: [], tarefas: [], orcamentos: [] };

function lido(extra: Partial<LidoDaTarde> = {}): LidoDaTarde {
  return {
    coleta: COLETA_VAZIA as unknown as LidoDaTarde["coleta"], historico: [], esperando: [], recebidas: [], amanha: null,
    escritorio: null, panorama: null, mesQueFechou: null, ...extra,
  };
}
const AGORA = new Date("2026-12-09T20:30:00.000Z");
const P = { hoje: "2026-12-09", agora: AGORA, turno: "fechamento" as const, itens: [], pergunta: false };
const ORC = { fixas: [FIXA], linhas: [LINHA_ORC], avisar: ["8d0c6a3e-1111-4a5b-9c7d-000000000001"] };

Deno.test("montarTardeDosDados: as linhas do orçamento sem linha do parceiro e sem o retorno (doDia nulo) aparecem nas extras do fechamento", () => {
  // (as linhas são extras: como as do parceiro, sozinhas não abrem a tarde; a pergunta da sexta dá o que dizer)
  const comPergunta = { ...P, pergunta: true };
  const t = montarTardeDosDados({ ...comPergunta, lido: lido({ orcamento: { ...ORC, fixas: [], avisar: [] } }) }).texto!;
  assertStringIncludes(t, LINHA_ORC);
  // sozinhas, a tarde calada (extra não conta como "há algo")
  assertEquals(montarTardeDosDados({ ...P, lido: lido({ orcamento: { ...ORC, fixas: [], avisar: [] } }) }).texto, null);
  // com a do parceiro: as do orçamento depois
  const comParceiro = montarTardeDosDados({ ...comPergunta, lido: lido({ parceiro: [LINHA_PARCEIRO], orcamento: { ...ORC, fixas: [], avisar: [] } }) }).texto!;
  assert(comParceiro.indexOf(LINHA_PARCEIRO) < comParceiro.indexOf(LINHA_ORC), comParceiro);
});

Deno.test("montarTardeDosDados: sem linhas do orçamento nem do parceiro, o texto de antes, byte a byte", () => {
  const antes = montarTardeDosDados({ ...P, lido: lido({ escritorio: ESCRITORIO as unknown as LidoDaTarde["escritorio"] }) });
  for (const orcamento of [null, undefined, { fixas: [], linhas: [], avisar: [] }]) {
    const depois = montarTardeDosDados({ ...P, lido: lido({ escritorio: ESCRITORIO as unknown as LidoDaTarde["escritorio"], ...(orcamento === undefined ? {} : { orcamento }) }) });
    assertEquals(depois.texto, antes.texto);
    assertEquals(depois.orcamento, undefined);
  }
});

Deno.test("montarTardeDosDados: a linha fixa vai no texto e leva fixas e avisar; nas revisões, só a fixa (as linhas não)", () => {
  const m = montarTardeDosDados({ ...P, lido: lido({ orcamento: ORC }) });
  assertStringIncludes(m.texto!, FIXA);
  assertStringIncludes(m.texto!, LINHA_ORC);
  assertEquals(m.orcamento, { fixas: ORC.fixas, avisar: ORC.avisar });
  const rev = montarTardeDosDados({ ...P, hoje: "2026-12-07", agora: new Date("2026-12-07T20:30:00.000Z"), turno: "revisao_semana", lido: lido({ orcamento: ORC }) });
  assertStringIncludes(rev.texto!, FIXA);
  assert(!rev.texto!.includes(LINHA_ORC), rev.texto!);
  assertEquals(rev.orcamento, { fixas: ORC.fixas, avisar: ORC.avisar });
});

// ─── O turno (secretario-tarde.ts, rodarTurnoDaTarde) ──────────────────────────────────────────────────────────────

type Linha = Record<string, unknown>;
const DONO = { id: "u-dono", phone: "5547900009901" };
const HOJE = "2026-12-09";

function falsoAdmin(tabelas: Record<string, Linha[]>, rpcs: Record<string, unknown> = {}) {
  const chamadas: Array<{ nome: string; args: unknown }> = [];
  const admin = {
    from(tabela: string) {
      let linhas = [...(tabelas[tabela] ?? [])];
      let soContagem = false;
      const resultado = () => soContagem ? { data: null, error: null, count: linhas.length } : { data: linhas, error: null };
      const q: Record<string, unknown> = {
        select: (_c?: string, o?: { head?: boolean }) => ((soContagem = !!o?.head), q),
        eq: (c: string, v: unknown) => ((linhas = linhas.filter((l) => l[c] === v)), q),
        neq: (c: string, v: unknown) => ((linhas = linhas.filter((l) => l[c] !== v)), q),
        in: (c: string, vs: unknown[]) => ((linhas = linhas.filter((l) => vs.includes(l[c]))), q),
        is: (c: string, v: unknown) => ((linhas = linhas.filter((l) => (l[c] ?? null) === v)), q),
        not: (c: string, op: string, v: unknown) => ((linhas = linhas.filter((l) => !(op === "is" && (l[c] ?? null) === v))), q),
        lt: (c: string, v: string) => ((linhas = linhas.filter((l) => l[c] != null && String(l[c]) < v)), q),
        lte: (c: string, v: string) => ((linhas = linhas.filter((l) => l[c] != null && String(l[c]) <= v)), q),
        gte: (c: string, v: string) => ((linhas = linhas.filter((l) => l[c] != null && String(l[c]) >= v)), q),
        gt: (c: string, v: string) => ((linhas = linhas.filter((l) => l[c] != null && String(l[c]) > v)), q),
        like: () => q,
        or: () => q,
        order: () => q,
        limit: () => q,
        insert: () => Promise.resolve({ data: null, error: null }),
        update: () => ({ eq: () => Promise.resolve({ data: null, error: null }) }),
        maybeSingle: () => Promise.resolve({ data: linhas[0] ?? null, error: null }),
        then: (ok: (r: unknown) => unknown, erro?: (e: unknown) => unknown) => Promise.resolve(resultado()).then(ok, erro),
      };
      return q;
    },
    rpc(nome: string, args: unknown) {
      chamadas.push({ nome, args });
      const r = rpcs[nome];
      return Promise.resolve({ data: r ?? null, error: null });
    },
  };
  return { admin, chamadas };
}

function banco(p: { formato?: string; modo?: "sombra" | "novo"; fila?: boolean; dia?: string } = {}) {
  const dia = p.dia ?? HOJE;
  return {
    app_settings: [{ key: "fechamento_formato", value: p.formato ?? "ligado" }, { key: "quote_validity_days", value: "3" }],
    app_users: [{ id: DONO.id, phone_normalized: DONO.phone, role: "admin", active: true, ai_whatsapp_enabled: true }],
    resumo_tarde: [],
    resumo_manha: [{ id: "m-1", dia, phone_normalized: DONO.phone, modo: p.modo ?? "novo" }],
    resumo_itens: [],
    whatsapp_messages: [],
    whatsapp_perguntas: [],
    ai_operator_sessions: [{ id: "s-1", channel: "whatsapp", external_thread_key: DONO.phone, status: "open", last_activity_at: new Date().toISOString(), metadata: {} }],
    whatsapp_send_queue: p.fila === false ? [] : [{ id: "fila-tarde", dedupe_key: `secretario_tarde:${dia}:${DONO.phone}` }],
  };
}

function rpcs(enviado: boolean, novo = true, orcamento: unknown = ORC): Record<string, unknown> {
  return {
    resumo_tarde_registrar: { ok: true, novo, enviado, calado: false },
    orcamento_resumo_fechamento: orcamento,
    orcamento_avisados: 1,
  };
}

const textoGravado = (ch: Array<{ nome: string; args: unknown }>) =>
  String((ch.find((c) => c.nome === "resumo_tarde_registrar")?.args as { p: { texto: string } } | undefined)?.p.texto ?? "");

Deno.test("rodarTurnoDaTarde: tarde ENVIADA com a linha fixa → orcamento_avisados com os passos e o id da fila da tarde, depois de gravar", async () => {
  const f = falsoAdmin(banco(), rpcs(true));
  const r = await rodarTurnoDaTarde(f.admin, { agora: AGORA, pedido: "tarde", dry: false });
  assertEquals(r.status, 200);
  assertStringIncludes(textoGravado(f.chamadas), FIXA);
  assertEquals(f.chamadas.filter((c) => c.nome === "orcamento_resumo_fechamento").map((c) => c.args), [{ p_agora: AGORA.toISOString() }]);
  const av = f.chamadas.filter((c) => c.nome === "orcamento_avisados");
  assertEquals(av.map((c) => c.args), [{ p_passos: ORC.avisar, p_fila: "fila-tarde", p_agora: AGORA.toISOString() }]);
  assert(f.chamadas.findIndex((c) => c.nome === "resumo_tarde_registrar") < f.chamadas.findIndex((c) => c.nome === "orcamento_avisados"), "avisa DEPOIS de gravar e enfileirar");
  assertEquals(r.corpo.orcamento_aviso, "avisado");
});

Deno.test("rodarTurnoDaTarde: sem o id da fila, ou na 2ª corrida (novo = false), orcamento_avisados não é chamado", async () => {
  const sem = falsoAdmin(banco({ fila: false }), rpcs(true));
  await rodarTurnoDaTarde(sem.admin, { agora: AGORA, pedido: "tarde", dry: false });
  assertEquals(sem.chamadas.some((c) => c.nome === "orcamento_avisados"), false);
  const segunda = falsoAdmin(banco(), rpcs(true, false));
  await rodarTurnoDaTarde(segunda.admin, { agora: AGORA, pedido: "tarde", dry: false });
  assertEquals(segunda.chamadas.some((c) => c.nome === "orcamento_avisados"), false);
});

Deno.test("rodarTurnoDaTarde: na sombra, rebaixada ou no dry-run, nada do orçamento é lido nem avisado (o fechamento grava o 'não saiu' ao montar)", async () => {
  for (const [b, dry] of [[banco({ formato: "sombra" }), false], [banco({ formato: "ligado", modo: "sombra" }), false], [banco(), true]] as const) {
    const f = falsoAdmin(b, rpcs(false));
    await rodarTurnoDaTarde(f.admin, { agora: AGORA, pedido: dry ? "fechamento" : "tarde", dry });
    assertEquals(f.chamadas.some((c) => c.nome === "orcamento_resumo_fechamento"), false, JSON.stringify({ dry }));
    assertEquals(f.chamadas.some((c) => c.nome === "orcamento_avisados"), false);
  }
});

Deno.test("rodarTurnoDaTarde: o registro mandou e o texto não tem a linha fixa (só linhas), nada é avisado; a revisão da semana também lê e avisa", async () => {
  // um fornecedor esperando desde segunda: a tarde tem o que dizer (as linhas do orçamento sozinhas não abrem o fechamento)
  const soLinhas = falsoAdmin(banco(), {
    ...rpcs(true, true, { fixas: [], linhas: [LINHA_ORC], avisar: [] }),
    whatsapp_esperando_resposta: [
      { phone: "5547900009907", contato: "SR Contabilidade", categoria: "fornecedor", last_inbound_at: "2026-12-07T17:02:03Z", last_body: "extrato", encerrada: false },
    ],
  });
  await rodarTurnoDaTarde(soLinhas.admin, { agora: AGORA, pedido: "tarde", dry: false });
  assertStringIncludes(textoGravado(soLinhas.chamadas), LINHA_ORC);
  assertEquals(soLinhas.chamadas.some((c) => c.nome === "orcamento_avisados"), false);
  // seg 07/12: a revisão da semana (o 1º dia útil da semana) lê o orçamento e avisa pela fixa
  const agoraSeg = new Date("2026-12-07T20:30:00.000Z");
  const seg = falsoAdmin(banco({ dia: "2026-12-07" }), rpcs(true));
  const r = await rodarTurnoDaTarde(seg.admin, { agora: agoraSeg, pedido: "tarde", dry: false });
  assertEquals(r.corpo.turno, "revisao_semana");
  const texto = textoGravado(seg.chamadas);
  assertStringIncludes(texto, FIXA);
  assert(!texto.includes(LINHA_ORC), texto);
  assertEquals(seg.chamadas.filter((c) => c.nome === "orcamento_avisados").length, 1);
});

Deno.test("rodarTurnoDaTarde: a função ausente ou com erro não derruba a tarde — sai como antes, sem aviso", async () => {
  const f = falsoAdmin(banco(), rpcs(true, true, null));
  const r = await rodarTurnoDaTarde(f.admin, { agora: AGORA, pedido: "tarde", dry: false });
  assertEquals(r.status, 200);
  assertEquals(f.chamadas.some((c) => c.nome === "orcamento_avisados"), false);
});
