// A via do técnico com a ficha das 19:30: quando vai, quando não vai.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  chaveDoDia,
  decidirAVia,
  FALHAS_ATE_DESISTIR,
  fichasDaEquipe,
  horaEmBrasilia,
  itensPendentes,
  ORIGENS_QUE_ENTREGAM,
  osDasFichas,
  type PecasDaVia,
  rotuloDoDia,
  ultimaViaEntregue,
  viaDaAgenda,
} from "./via-da-agenda.ts";

// A ficha como o banco a grava: SEM alocacao_ids (NOVO-via-11). As OS vêm do plano do dia da pessoa.
const F1 = { id: "f1", payee_id: "alex", dia: "2026-11-26", fila_id: "q1" };
const F2 = { id: "f2", payee_id: "alex", dia: "2026-11-27", fila_id: "q2" };
const OS_DO_DIA = new Map([
  [chaveDoDia("alex", "2026-11-26"), ["os119"]],
  [chaveDoDia("alex", "2026-11-27"), ["os119"]],
]);

Deno.test("só a ficha que a fila ENTREGOU leva a via", () => {
  const { fazer } = itensPendentes([F1, F2], new Set(["q1"]), OS_DO_DIA, []);
  assertEquals(fazer.map((i) => `${i.ficha.id}:${i.os}`), ["f1:os119"]);
});

Deno.test("ficha com via enviada ou pulada não volta; falhou volta até desistir", () => {
  const entregues = new Set(["q1", "q2"]);
  const enviada = [{ ficha_id: "f1", service_order_id: "os119", estado: "enviado" }];
  assertEquals(itensPendentes([F1, F2], entregues, OS_DO_DIA, enviada).fazer.map((i) => i.ficha.id), ["f2"]);
  const pulada = [{ ficha_id: "f1", service_order_id: "os119", estado: "pulado" }];
  assertEquals(itensPendentes([F1], entregues, OS_DO_DIA, pulada).fazer.length, 0);
  const falhou = Array.from({ length: FALHAS_ATE_DESISTIR - 1 }, () => ({ ficha_id: "f1", service_order_id: "os119", estado: "falhou" }));
  assertEquals(itensPendentes([F1], entregues, OS_DO_DIA, falhou).fazer.length, 1);
  const desiste = [...falhou, { ficha_id: "f1", service_order_id: "os119", estado: "falhou" }];
  const r = itensPendentes([F1], entregues, OS_DO_DIA, desiste);
  assertEquals([r.fazer.length, r.desistir.length], [0, 1]);
});

Deno.test("dia sem OS no plano (só reserva, ou tudo cancelado): nenhuma via", () => {
  assertEquals(itensPendentes([F1], new Set(["q1"]), new Map(), []).fazer.length, 0);
});

// A impressão (porte da via v2, F0): v<versão do desenho>.d<versão do dado>.<dado>.<papel>. Só o DADO diz se a OS mudou.
const EM_25_11 = "2026-11-25T22:45:00Z";
const ultima = (impressao: string | null) => ({ impressao, criado_em: EM_25_11 });

Deno.test("1º dia: manda, dizendo para que dia", () => {
  assertEquals(decidirAVia(null, "v2.d1.dado1.papel1", "2026-11-26", false), { acao: "mandar", complemento: "Para qui 26/11, junto da ficha." });
});

Deno.test("mesma versão já recebida (pela agenda ou pelo dono, à equipe): não repete", () => {
  const r = decidirAVia(ultima("v2.d1.dado1.papel1"), "v2.d1.dado1.papel1", "2026-11-27", false);
  assertEquals(r, { acao: "pular", motivo: "já recebeu esta via em 25/11" });
});

Deno.test("a OS mudou (dado e papel diferentes): manda de novo, dizendo que substitui a anterior", () => {
  const r = decidirAVia(ultima("v2.d1.dado1.papel1"), "v2.d1.dado2.papel2", "2026-11-30", true);
  assertEquals(r, {
    acao: "mandar",
    complemento: "A OS mudou desde a via de 25/11: esta substitui a anterior. Só os seus serviços e os sem responsável.",
  });
});

Deno.test("última no formato antigo (o hash do HTML, 'h1→h2' de antes): manda com a frase neutra, nunca 'a OS mudou'", () => {
  assertEquals(decidirAVia(ultima("772aau"), "v2.d1.dado1.papel1", "2026-11-30", false), {
    acao: "mandar",
    complemento: "Esta via substitui a de 25/11.",
  });
  // registro sem impressão também é legado
  assertEquals(decidirAVia(ultima(null), "v2.d1.dado1.papel1", "2026-11-30", true).acao, "mandar");
});

Deno.test("outro contrato do dado (VERSAO_DO_DADO subiu): manda com a frase neutra", () => {
  assertEquals(decidirAVia(ultima("v2.d1.dado1.papel1"), "v2.d2.dadoX.papel1", "2026-11-30", false), {
    acao: "mandar",
    complemento: "Esta via substitui a de 25/11.",
  });
});

Deno.test("desenho novo (versão diferente) com o dado igual: pula — mudou só a folha, a OS não", () => {
  assertEquals(decidirAVia(ultima("v2.d1.dado1.papel1"), "v3.d1.dado1.papel9", "2026-11-30", false), {
    acao: "pular",
    motivo: "via em formato novo; a OS não mudou desde 25/11",
  });
});

Deno.test("mesma versão, papel diferente e dado igual: pula (a regra do papel mudou, a OS não)", () => {
  assertEquals(decidirAVia(ultima("v2.d1.dado1.papel1"), "v2.d1.dado1.papel2", "2026-11-30", false), {
    acao: "pular",
    motivo: "a regra do papel mudou; a OS não",
  });
});

Deno.test("mesma versão, papel igual e dado diferente: pula (a OS mudou só no que não vai ao papel)", () => {
  assertEquals(decidirAVia(ultima("v2.d1.dado1.papel1"), "v2.d1.dado2.papel1", "2026-11-30", false), {
    acao: "pular",
    motivo: "a OS mudou só no que não vai ao papel",
  });
});

Deno.test("versão diferente e dado diferente: manda 'a OS mudou'", () => {
  assertEquals(decidirAVia(ultima("v2.d1.dado1.papel1"), "v3.d1.dado2.papel1", "2026-11-30", false), {
    acao: "mandar",
    complemento: "A OS mudou desde a via de 25/11: esta substitui a anterior.",
  });
});

// ─── A última via ENTREGUE: o "para si" não conta (F0.1) ─────────────────────────────────────────

/** Banco falso de via_tecnico_envios: aplica eq/in/order/limit e registra a cadeia de chamadas. */
function bancoDeEnvios(linhas: Array<Record<string, unknown>>) {
  const cadeia: string[] = [];
  return {
    cadeia,
    from: (tabela: string) => {
      cadeia.push(`from:${tabela}`);
      let sel = [...linhas];
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q,
        eq: (c: string, v: unknown) => { cadeia.push(`eq:${c}`); sel = sel.filter((l) => l[c] === v); return q; },
        in: (c: string, vs: unknown[]) => { cadeia.push(`in:${c}:${vs.join(",")}`); sel = sel.filter((l) => vs.includes(l[c])); return q; },
        order: (c: string, o: { ascending: boolean }) => {
          sel.sort((a, b) => String(a[c]).localeCompare(String(b[c])) * (o.ascending ? 1 : -1));
          return q;
        },
        limit: (n: number) => { sel = sel.slice(0, n); return q; },
        maybeSingle: () => Promise.resolve({ data: sel[0] ?? null, error: null }),
      };
      return q;
    },
  };
}

const ENVIO = { payee_id: "alex", service_order_id: "os119", estado: "enviado", impressao: "v2.d1.dado1.papel1" };

Deno.test("para si com o payee_id do Alex (o dono pediu a via do Alex para ele mesmo): não conta, a agenda MANDA", async () => {
  const db = bancoDeEnvios([{ ...ENVIO, origem: "para_si", criado_em: "2026-11-25T10:00:00Z" }]);
  const ult = await ultimaViaEntregue(db, "alex", "os119");
  assertEquals(ult, null);
  assertEquals(db.cadeia.includes("in:origem:agenda,assistente"), true);
  // com a mesma impressão, antes do conserto, pulava com "já recebeu"
  assertEquals(decidirAVia(ult, "v2.d1.dado1.papel1", "2026-11-26", false).acao, "mandar");
});

Deno.test("a via que a agenda ou o dono mandou À EQUIPE conta; a mais recente vale", async () => {
  const db = bancoDeEnvios([
    { ...ENVIO, origem: "agenda", criado_em: "2026-11-20T22:45:00Z", impressao: "v2.d1.velho.papel0" },
    { ...ENVIO, origem: "assistente", criado_em: "2026-11-25T22:45:00Z" },
    { ...ENVIO, origem: "para_si", criado_em: "2026-11-26T10:00:00Z", impressao: "v2.d1.outro.papel9" },
    { ...ENVIO, origem: "agenda", estado: "falhou", criado_em: "2026-11-27T10:00:00Z" },
  ]);
  const ult = await ultimaViaEntregue(db, "alex", "os119");
  assertEquals(ult?.criado_em, "2026-11-25T22:45:00Z");
  assertEquals(decidirAVia(ult, "v2.d1.dado1.papel1", "2026-11-28", false), { acao: "pular", motivo: "já recebeu esta via em 25/11" });
  assertEquals([...ORIGENS_QUE_ENTREGAM], ["agenda", "assistente"]);
});

Deno.test("leitura da última via que falha lança (viaDaAgenda registra o erro e não manda às cegas)", async () => {
  const quebrado = {
    from: () => {
      // deno-lint-ignore no-explicit-any
      const q: any = { select: () => q, eq: () => q, in: () => q, order: () => q, limit: () => q,
        maybeSingle: () => Promise.resolve({ data: null, error: { message: "timeout" } }) };
      return q;
    },
  };
  let erro = "";
  try { await ultimaViaEntregue(quebrado, "alex", "os119"); } catch (e) { erro = (e as Error).message; }
  assertEquals(erro, "última via: timeout");
});

Deno.test("hora e dia em Brasília", () => {
  assertEquals(horaEmBrasilia(new Date("2026-11-25T22:45:00Z")), 19);
  assertEquals(horaEmBrasilia(new Date("2026-11-25T23:00:00Z")), 20);
  assertEquals(rotuloDoDia("2026-11-28"), "sáb 28/11");
});

Deno.test("desligada pela chave ou fora da janela: nem lê o banco", async () => {
  const semBanco = { from: () => { throw new Error("não devia ler"); } };
  assertEquals(await viaDaAgenda(semBanco, { via_tecnico_na_agenda: "desligado" }, new Date("2026-11-25T22:45:00Z")), { rodou: false, motivo: "desligada" });
  // 21h de Brasília: o whatsapp-send recusaria (janela 8h–20h)
  assertEquals(await viaDaAgenda(semBanco, {}, new Date("2026-11-26T00:00:00Z")), { rodou: false, motivo: "fora da janela" });
  assertEquals(await viaDaAgenda(semBanco, {}, new Date("2026-11-26T10:59:00Z")), { rodou: false, motivo: "fora da janela" });
});

// ─── As OS da ficha pelo plano do dia, e o caminho inteiro (NOVO-via-11 e 12, 17/11) ─────────────────

type Linha = Record<string, unknown>;

/**
 * Banco falso com várias tabelas: select/eq/neq/in/gte/not(is null)/order/limit, await direto ou maybeSingle, e
 * insert (guarda a linha). O suficiente para viaDaAgenda e as leituras dela, com o dado no formato do banco.
 */
function bancoFalso(tabelas: Record<string, Linha[]>, falhaEm: string | null = null) {
  const inseridas: Record<string, Linha[]> = {};
  return {
    tabelas,
    inseridas,
    from: (tabela: string) => {
      let sel = [...(tabelas[tabela] ?? [])];
      const resultado = () => (falhaEm === tabela ? { data: null, error: { message: "timeout" } } : { data: sel, error: null });
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q,
        eq: (c: string, v: unknown) => { sel = sel.filter((l) => l[c] === v); return q; },
        neq: (c: string, v: unknown) => { sel = sel.filter((l) => l[c] !== v); return q; },
        in: (c: string, vs: unknown[]) => { sel = sel.filter((l) => vs.includes(l[c])); return q; },
        gte: (c: string, v: string) => { sel = sel.filter((l) => l[c] !== null && l[c] !== undefined && String(l[c]) >= v); return q; },
        not: (c: string, op: string, v: unknown) => {
          if (op !== "is" || v !== null) throw new Error(`not(${c}, ${op}) sem suporte no falso`);
          sel = sel.filter((l) => l[c] !== null && l[c] !== undefined);
          return q;
        },
        order: (c: string, o: { ascending: boolean }) => {
          sel.sort((a, b) => String(a[c]).localeCompare(String(b[c])) * (o.ascending ? 1 : -1));
          return q;
        },
        limit: (n: number) => { sel = sel.slice(0, n); return q; },
        maybeSingle: () => {
          const r = resultado();
          return Promise.resolve(r.error ? r : { data: sel[0] ?? null, error: null });
        },
        insert: (linha: Linha) => {
          (inseridas[tabela] ??= []).push(linha);
          (tabelas[tabela] ??= []).push({ ...linha, criado_em: "2026-11-17T22:46:00Z" });
          return Promise.resolve({ error: null });
        },
        then: (ok: (r: unknown) => unknown, erro?: (e: unknown) => unknown) => Promise.resolve(resultado()).then(ok, erro),
      };
      return q;
    },
  };
}

/** O banco de 17/11 19:45, no formato real: a ficha sem alocacao_ids, o replanejamento (cancela e recria), reserva, veto, sombra. */
function banco17de11() {
  const msg = (m: Linha) => ({ alocacao_ids: null, leva_ficha_de: null, modo: "ligado", ...m });
  const aloc = (payee: string, dia: string, os: string, estado: string, tipo = "execucao") => ({ payee_id: payee, dia, service_order_id: os, estado, tipo });
  return bancoFalso({
    agenda_equipe_mensagens: [
      msg({ id: "f-alex", tipo: "ficha", payee_id: "alex", dia: "2026-11-18", fila_id: "q1" }),
      msg({ id: "f-vetada", tipo: "ficha", payee_id: "roberto", dia: "2026-11-18", fila_id: null }),
      msg({ id: "f-sombra", tipo: "ficha", payee_id: "alex", dia: "2026-11-18", fila_id: "q9", modo: "sombra" }),
      msg({ id: "f-velha", tipo: "ficha", payee_id: "alex", dia: "2026-11-16", fila_id: "q8" }),
      // quem trabalhou hoje recebe a ficha de amanhã junto do "como foi" das 17:00 (NOVO-via-12)
      msg({ id: "c-joao", tipo: "como_foi", payee_id: "joao", dia: "2026-11-17", leva_ficha_de: "2026-11-18", fila_id: "q2" }),
      msg({ id: "c-sem-ficha", tipo: "como_foi", payee_id: "roberto", dia: "2026-11-17", fila_id: "q3" }),
    ],
    whatsapp_send_queue: [
      { id: "q1", status: "sent" }, { id: "q2", status: "sent" }, { id: "q3", status: "sent" },
      { id: "q8", status: "sent" }, { id: "q9", status: "sent" },
    ],
    agenda_alocacoes: [
      // manhã e tarde na OS-129: uma via
      aloc("alex", "2026-11-18", "os129", "publicada"),
      aloc("alex", "2026-11-18", "os129", "publicada"),
      // o replanejamento cancelou a OS-112 do dia: não vai
      aloc("alex", "2026-11-18", "os112", "cancelada"),
      aloc("alex", "2026-11-18", "os200", "publicada", "reserva"),
      aloc("alex", "2026-11-19", "os300", "publicada"),
      aloc("joao", "2026-11-18", "os129", "fixada"),
      aloc("roberto", "2026-11-18", "os129", "publicada"),
    ],
    payees: [
      { id: "alex", name: "Alex Teste", phone: "(48) 99999-0001" },
      { id: "joao", name: "João Teste", phone: "48999990002" },
      { id: "roberto", name: "Roberto Teste", phone: "48999990003" },
    ],
    via_tecnico_envios: [],
  });
}

const AS_19_45_DE_17 = new Date("2026-11-17T22:45:00Z");

/** Render e envio falsos: o resto (fichas, fila, plano, registro, decisão) é o código de verdade. */
function pecasFalsas() {
  const mandadas: Array<{ telefone: string; os: string; complemento: string; chave: string; pessoa: string }> = [];
  const trocas: Partial<PecasDaVia> = {
    carregar: (async (_db: unknown, os: string) => ({
      ok: true,
      dados: { linhas: [{ responsavel_payee_id: null }] },
      ordem: { numero: os.toUpperCase(), shareToken: "t" },
    })) as unknown as PecasDaVia["carregar"],
    fotos: (async () => ({})) as unknown as PecasDaVia["fotos"],
    equipe: (async () => [{ id: "alex", dias: ["2026-11-18"] }, { id: "joao", dias: ["2026-11-18"] }]) as unknown as PecasDaVia["equipe"],
    preparar: (() => ({ semServicoDaPessoa: false, impressao: "v3.d1.dado1.papel1", servicos: 2, html: "", nomeDoArquivo: "via.pdf" })) as unknown as PecasDaVia["preparar"],
    mandar: (async (p: { telefone: string; ordem: { numero: string }; complementoDaLegenda?: string | null; chave: (i: string) => string; pessoa: { id: string } | null }) => {
      mandadas.push({
        telefone: p.telefone,
        os: p.ordem.numero,
        complemento: p.complementoDaLegenda ?? "",
        chave: p.chave("v3.d1.dado1.papel1"),
        pessoa: p.pessoa?.id ?? "",
      });
      return { ok: true, servicos: 2, impressao: "v3.d1.dado1.papel1" };
    }) as unknown as PecasDaVia["mandar"],
  };
  return { mandadas, trocas };
}

Deno.test("fichasDaEquipe: a das 19:30 e a do 'como foi' (dia = leva_ficha_de); vetada, sombra, velha e 'como foi' sem ficha ficam fora", async () => {
  const fichas = await fichasDaEquipe(banco17de11(), "2026-11-17");
  assertEquals(fichas.map((f) => `${f.id}:${f.payee_id}:${f.dia}:${f.fila_id}`).sort(), [
    "c-joao:joao:2026-11-18:q2",
    "f-alex:alex:2026-11-18:q1",
  ]);
});

Deno.test("osDasFichas: pelo critério da ficha — publicada/fixada do dia, sem reserva, sem cancelada; manhã e tarde = uma OS", async () => {
  const db = banco17de11();
  const porDia = await osDasFichas(db, await fichasDaEquipe(db, "2026-11-17"));
  assertEquals(porDia.get(chaveDoDia("alex", "2026-11-18")), ["os129"]);
  assertEquals(porDia.get(chaveDoDia("joao", "2026-11-18")), ["os129"]);
  assertEquals(porDia.has(chaveDoDia("alex", "2026-11-19")), false);
});

Deno.test("replanejamento entre a ficha e a via (cancela e recria a mesma OS): a OS continua no dia e a via vai", async () => {
  const db = banco17de11();
  db.tabelas.agenda_alocacoes = [
    { payee_id: "alex", dia: "2026-11-18", service_order_id: "os129", estado: "cancelada", tipo: "execucao" },
    { payee_id: "alex", dia: "2026-11-18", service_order_id: "os129", estado: "publicada", tipo: "execucao" },
  ];
  const porDia = await osDasFichas(db, [{ id: "f-alex", payee_id: "alex", dia: "2026-11-18", fila_id: "q1" }]);
  assertEquals(porDia.get(chaveDoDia("alex", "2026-11-18")), ["os129"]);
});

Deno.test("leitura das alocações ou das fichas que falha lança (viaDaAgenda registra e não manda às cegas)", async () => {
  let erro = "";
  try {
    await osDasFichas(bancoFalso({}, "agenda_alocacoes"), [{ id: "f", payee_id: "alex", dia: "2026-11-18", fila_id: "q1" }]);
  } catch (e) { erro = (e as Error).message; }
  assertEquals(erro, "alocações: timeout");
  const r = await viaDaAgenda(bancoFalso({}, "agenda_equipe_mensagens"), {}, AS_19_45_DE_17, undefined, pecasFalsas().trocas);
  assertEquals([r.rodou, r.erro], [false, "fichas: timeout"]);
});

Deno.test("caminho inteiro, 17/11 19:45: a ficha sem alocacao_ids e a do 'como foi' levam a via; o tique seguinte não repete", async () => {
  const db = banco17de11();
  const { mandadas, trocas } = pecasFalsas();
  const r = await viaDaAgenda(db, {}, AS_19_45_DE_17, undefined, trocas);
  assertEquals(r, { rodou: true, enviadas: 2, puladas: 0, falhas: 0, restantes: 0 });
  assertEquals(mandadas.sort((a, b) => a.pessoa.localeCompare(b.pessoa)), [
    { pessoa: "alex", telefone: "48999990001", os: "OS129", complemento: "Para qua 18/11, junto da ficha.", chave: "agenda-via:f-alex:os129:v3.d1.dado1.papel1" },
    { pessoa: "joao", telefone: "48999990002", os: "OS129", complemento: "Para qua 18/11, junto da ficha.", chave: "agenda-via:c-joao:os129:v3.d1.dado1.papel1" },
  ]);
  assertEquals(
    (db.inseridas.via_tecnico_envios ?? [])
      .map((l) => `${l.ficha_id}:${l.service_order_id}:${l.payee_id}:${l.origem}:${l.estado}:${l.dia}:${l.destino}`).sort(),
    [
      "c-joao:os129:joao:agenda:enviado:2026-11-18:48999990002",
      "f-alex:os129:alex:agenda:enviado:2026-11-18:48999990001",
    ],
  );
  // o próximo tique: já registrado, nada sai de novo
  const r2 = await viaDaAgenda(db, {}, new Date("2026-11-17T22:59:00Z"), undefined, trocas);
  assertEquals(r2, { rodou: true, enviadas: 0, puladas: 0, falhas: 0, restantes: 0 });
  assertEquals(mandadas.length, 2);
});

Deno.test("caminho inteiro: ficha ainda na fila (não 'sent') espera; quem não tem telefone é pulado com o motivo", async () => {
  const db = banco17de11();
  db.tabelas.whatsapp_send_queue = [{ id: "q1", status: "pending" }, { id: "q2", status: "sent" }];
  db.tabelas.payees = [{ id: "alex", name: "Alex Teste", phone: "48999990001" }, { id: "joao", name: "João Teste", phone: null }];
  const { mandadas, trocas } = pecasFalsas();
  const r = await viaDaAgenda(db, {}, AS_19_45_DE_17, undefined, trocas);
  assertEquals(r, { rodou: true, enviadas: 0, puladas: 1, falhas: 0, restantes: 0 });
  assertEquals(mandadas.length, 0);
  assertEquals((db.inseridas.via_tecnico_envios ?? []).map((l) => `${l.ficha_id}:${l.estado}:${l.motivo}`), ["c-joao:pulado:sem telefone no cadastro"]);
});

Deno.test("caminho inteiro: a pessoa já recebeu esta via pelo dono (assistente) — a agenda não repete", async () => {
  const db = banco17de11();
  db.tabelas.via_tecnico_envios = [{
    payee_id: "alex", service_order_id: "os129", origem: "assistente", estado: "enviado", impressao: "v3.d1.dado1.papel1",
    criado_em: "2026-11-17T15:00:00Z", ficha_id: null,
  }];
  const { mandadas, trocas } = pecasFalsas();
  const r = await viaDaAgenda(db, {}, AS_19_45_DE_17, undefined, trocas);
  assertEquals(r, { rodou: true, enviadas: 1, puladas: 1, falhas: 0, restantes: 0 });
  assertEquals(mandadas.map((m) => m.pessoa), ["joao"]);
  assertEquals((db.inseridas.via_tecnico_envios ?? []).find((l) => l.ficha_id === "f-alex")?.motivo, "já recebeu esta via em 17/11");
});
