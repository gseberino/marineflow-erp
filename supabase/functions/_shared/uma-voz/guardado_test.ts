// A leitura do guardado (secretário, Passo 4, 16/10/2026). O que se protege: cada fonte vira uma linha curta e sem
// emoji (com os dados novos E com os registros antigos, só com o texto); o que se resolveu some (D8) ou aparece
// marcado ("aparece"); o escritório só sai no fechamento; um contato que já é item com letra não ganha linha; o
// mesmo contato duas vezes = uma linha; acima do máximo o resto ESPERA (não é marcado); a marcação nunca lança e,
// sem fila, não manda fila_id (a sombra).
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type AvisoGuardado, blocoDaFolga, blocoDaManha, blocoDoFechamento, chaveDaFilaDaTarde, foneDoAssunto, idDaFilaPelaChave,
  linhaDoGuardado, marcarNaMensagem, planoDoGuardado, quaisSeResolveram,
} from "./guardado.ts";
import { REGRAS_PADRAO } from "./portao.ts";

const HOJE = "2026-10-15";
let n = 0;
function aviso(o: Partial<AvisoGuardado>): AvisoGuardado {
  return {
    id: `a${++n}`, fonte: "teste", assunto: "x", destino: "proxima_fixa", motivo: "destino", texto: null, dados: {},
    registrado_em: "2026-10-15T12:45:00Z", dia: HOJE, mensagem: "fechamento", reaberto: 0, ...o,
  };
}

// os textos REAIS que as fontes gravam (15/10)
const SALDO = "🏦 Extrato de C6: o saldo do banco (R$ 1.234,56) não bate com a soma das transações importadas (R$ 1.222,26), diferença R$ 12,30. A diferença se repetiu nas duas últimas conferências: confira no app do banco se falta alguma transação no sistema (Financeiro › Conciliação › Fechar o mês).";
const PROMESSA = '🤖 Lembrete de promessa (detectado numa mensagem sua): você escreveu a Eng. Rafael B. (Dometic) (+55 (47) 90000-0000): "Claro, te passo agora!". Leia a conversa…';
const ACOMP = '🤖 Acompanhamento (pedido seu): Miguel (+351900000422) está esperando resposta. Última mensagem dele, há 2h: "…"';

Deno.test("linhas: cada fonte, com os dados novos e com o texto antigo", () => {
  assertEquals(linhaDoGuardado(aviso({ fonte: "acompanhar", assunto: "contato:351900000422", dados: { contato: "Miguel", mensagem_em: "2026-10-15T12:02:00Z" } }), HOJE),
    "Miguel escreveu às 09:02 e espera resposta");
  assertEquals(linhaDoGuardado(aviso({ fonte: "acompanhar", assunto: "contato:351900000422", texto: ACOMP, dados: { n: 1 } }), HOJE),
    "Miguel escreveu e espera resposta", "registro antigo: o nome sai do texto");
  assertEquals(linhaDoGuardado(aviso({ fonte: "cliente", dados: { nome: "Miguel", gatilho: "fechar_hoje", mensagem_em: "2026-10-15T12:02:00Z" } }), HOJE),
    "Miguel quer fechar hoje (09:02)");
  assertEquals(linhaDoGuardado(aviso({ fonte: "promessa", texto: PROMESSA }), HOJE), 'promessa sua a Eng. Rafael B. (Dometic): "Claro, te passo agora!"');
  assertEquals(linhaDoGuardado(aviso({ fonte: "promessa", dados: { contato: "Jorge", promessa: "amanhã te mando" } }), HOJE), 'promessa sua a Jorge: "amanhã te mando"');
  assertEquals(linhaDoGuardado(aviso({ fonte: "vigia_negocio", assunto: "saldo_divergente:c6", destino: "escritorio", texto: SALDO }), HOJE),
    "o saldo do banco C6 não bate com o sistema (R$ 12,30 de diferença)");
  assertEquals(linhaDoGuardado(aviso({ fonte: "conexao", assunto: "sistema", dados: { desde: "2026-10-15T15:45:00Z", ate: "2026-10-15T17:05:00Z" } }), HOJE),
    "o WhatsApp ficou fora das 12:45 às 14:05");
  // (20/10/2026) a queda de outro dia diz o dia; a que atravessou dias diz os dois (16/10 08:45 a 20/10 10:00 era
  // "das 08:45 às 10:00" no fechamento-sombra de 20/10)
  assertEquals(linhaDoGuardado(aviso({ fonte: "conexao", assunto: "sistema", dados: { desde: "2026-10-14T15:45:00Z", ate: "2026-10-14T17:05:00Z" } }), HOJE),
    "o WhatsApp ficou fora das 12:45 às 14:05 de ontem");
  assertEquals(linhaDoGuardado(aviso({ fonte: "conexao", assunto: "sistema", dados: { desde: "2026-10-13T15:45:00Z", ate: "2026-10-13T17:05:00Z" } }), HOJE),
    "o WhatsApp ficou fora das 12:45 às 14:05 de 13/10");
  assertEquals(linhaDoGuardado(aviso({ fonte: "conexao", assunto: "sistema", dados: { desde: "2026-10-16T11:45:01.888+00:00", ate: "2026-10-20T13:00:00Z" } }), "2026-10-20"),
    "o WhatsApp ficou fora de 16/10 08:45 a 20/10 10:00");
  // a manhã que não chegou: pelo WhatsApp fora (o de sempre) ou pela montagem que quebrou antes da fila (20/10/2026)
  assertEquals(linhaDoGuardado(aviso({ fonte: "vigia_negocio", assunto: "sistema", dia: "2026-10-17" }), HOJE), "a manhã de 17/10 não chegou (WhatsApp fora do ar)");
  assertEquals(linhaDoGuardado(aviso({ fonte: "vigia_negocio", assunto: "sistema", dia: "2026-10-17", dados: { motivo: "erro_na_montagem" } }), HOJE),
    "a manhã de 17/10 não chegou (erro ao montar)");
  assertEquals(linhaDoGuardado(aviso({ fonte: "email", assunto: "golpe:atendimento@envios.adv" }), HOJE), "parece golpe no e-mail: atendimento@envios.adv");
  assertEquals(linhaDoGuardado(aviso({ fonte: "vigia_negocio", assunto: "fiscal:cert:2026-11-05", destino: "hoje", dados: { dias: 20, validade: "2026-11-05" } }), HOJE),
    "o certificado A1 vence em 20 dias (05/11)");
  assertEquals(linhaDoGuardado(aviso({ fonte: "vigia_negocio", assunto: "fiscal:nfe_rejeitada", dados: { numero: "321", cliente: "MP MOTOR HOMES" } }), HOJE),
    "a NF-e nº 321 (MP MOTOR HOMES) foi rejeitada");
  assertEquals(linhaDoGuardado(aviso({ fonte: "vigia_negocio", assunto: "fiscal:nfe_rejeitada", texto: "❌ *2* NF-e rejeitada(s) nas últimas 24h." }), HOJE),
    "2 NF-e rejeitadas nas últimas 24 h");
  assertEquals(linhaDoGuardado(aviso({ fonte: "lead_site", texto: "🌐 *Lead do site*: João quer orçamento de lítio.\nTelefone…" }), HOJE),
    "Lead do site: João quer orçamento de lítio");
  for (const a of [aviso({ fonte: "vigia_negocio", assunto: "saldo_divergente:c6", texto: SALDO }), aviso({ fonte: "promessa", texto: PROMESSA })]) {
    assert(!/[\p{Extended_Pictographic}*]/u.test(linhaDoGuardado(a, HOJE)), "sem emoji e sem negrito");
  }
  assertEquals(foneDoAssunto("contato:351900000422"), "351900000422");
  assertEquals(foneDoAssunto("sistema"), null);
});

Deno.test("plano: D8 some (padrão) ou aparece marcado; escritório só no fechamento; coberto vai junto sem linha", () => {
  const a1 = aviso({ fonte: "acompanhar", assunto: "contato:351900000422", dados: { contato: "Miguel", mensagem_em: "2026-10-15T12:02:00Z" } });
  const a2 = aviso({ fonte: "promessa", assunto: "contato:5547900000001", texto: PROMESSA });
  const a3 = aviso({ fonte: "vigia_negocio", assunto: "saldo_divergente:c6", destino: "escritorio", texto: SALDO });
  const a4 = aviso({ fonte: "cliente", assunto: "contato:351900000422", dados: { nome: "Miguel", gatilho: "desistencia", mensagem_em: "2026-10-15T17:15:00Z" } });
  const f = planoDoGuardado({ avisos: [a1, a2, a3, a4], mensagem: "fechamento", hoje: HOJE, resolvidosAgora: new Set([a2.id]), regras: REGRAS_PADRAO });
  assertEquals(f.resolvidos, [a2.id]);
  assertEquals(f.linhas, ["Miguel escreveu às 09:02 e espera resposta"], "o 2º do Miguel vai junto (um contato, uma linha)");
  assertEquals(f.mostrados, [a1.id, a4.id]);
  assertEquals([f.escritorio, f.doEscritorio], [["o saldo do banco C6 não bate com o sistema (R$ 12,30 de diferença)"], [a3.id]]);
  const m = planoDoGuardado({ avisos: [a1, a3], mensagem: "manha", hoje: HOJE, resolvidosAgora: new Set(), regras: REGRAS_PADRAO });
  assertEquals([m.escritorio, m.doEscritorio, m.mostrados], [[], [], [a1.id]], "a manhã não leva o escritório");
  const ap = planoDoGuardado({ avisos: [a2], mensagem: "fechamento", hoje: HOJE, resolvidosAgora: new Set([a2.id]), regras: { guardado_resolvido: "aparece" } });
  assertEquals(ap.linhas, ['promessa sua a Eng. Rafael B. (Dometic): "Claro, te passo agora!" (já se resolveu)']);
  const cob = planoDoGuardado({ avisos: [a1], mensagem: "manha", hoje: HOJE, resolvidosAgora: new Set(), regras: REGRAS_PADRAO, cobertos: new Set(["351900000422"]) });
  assertEquals([cob.linhas, cob.mostrados], [[], [a1.id]], "o Miguel já é item com letra: o aviso vai junto, sem linha");
});

Deno.test("plano: acima do máximo o resto espera a próxima (não é marcado); os blocos dizem quantos", () => {
  // (20/10/2026) quatro golpes de remetentes diferentes (os avisos de sistema agora viram uma linha só: teste abaixo)
  const vs = ["a@x.com", "b@x.com", "c@x.com", "d@x.com"].map((e) => aviso({ fonte: "email", assunto: `golpe:${e}` }));
  const p = planoDoGuardado({ avisos: vs, mensagem: "manha", hoje: HOJE, resolvidosAgora: new Set(), regras: REGRAS_PADRAO, max: 3 });
  assertEquals([p.linhas.length, p.mostrados.length, p.restantes], [3, 3, 1]);
  assertEquals(blocoDaManha(p), "Guardei 4 avisos para não te interromper: parece golpe no e-mail: a@x.com; parece golpe no e-mail: b@x.com; parece golpe no e-mail: c@x.com; e mais 1 na próxima mensagem.");
  assertEquals(blocoDaManha({ ...p, restantes: 0 }, true), "Guardei 3 avisos para não te interromper: parece golpe no e-mail: a@x.com; e mais 2 na próxima mensagem.");
  assertEquals(blocoDoFechamento({ ...p, linhas: p.linhas.slice(0, 1), restantes: 0 }), "Não te interrompi com: parece golpe no e-mail: a@x.com.");
  assertEquals(blocoDaFolga({ ...p, linhas: p.linhas.slice(0, 1), restantes: 0 }), "1 coisa ficou de ontem: parece golpe no e-mail: a@x.com.");
  const vazio = planoDoGuardado({ avisos: [], mensagem: "manha", hoje: HOJE, resolvidosAgora: new Set(), regras: REGRAS_PADRAO });
  assertEquals([blocoDaManha(vazio), blocoDoFechamento(vazio), blocoDaFolga(vazio)], [null, null, null]);
});

// (20/10/2026) A queda de 16 a 20/10: com a voz ligada, as manhãs de 17, 18 e 19/10 não chegaram (cada uma vira um aviso
// guardado quando a fila desiste) e a volta do WhatsApp foi guardada — quatro avisos do MESMO fato. Uma linha só, no lugar
// do primeiro; todos ficam marcados (mostrados); os outros avisos continuam com a linha deles.
Deno.test("plano: os avisos de sistema (quedas e manhãs perdidas) viram uma linha só", () => {
  const h = "2026-10-20";
  const m17 = aviso({ fonte: "vigia_negocio", assunto: "sistema", destino: "acorde", dia: "2026-10-17", registrado_em: "2026-10-17T12:05:00Z" });
  const m18 = aviso({ fonte: "vigia_negocio", assunto: "sistema", destino: "acorde", dia: "2026-10-18", registrado_em: "2026-10-18T12:05:00Z" });
  const m19 = aviso({ fonte: "vigia_negocio", assunto: "sistema", destino: "acorde", dia: "2026-10-19", registrado_em: "2026-10-19T12:05:00Z" });
  const promessa = aviso({ fonte: "promessa", assunto: "contato:5547900000001", dados: { contato: "Nelson", promessa: "vou ver o display" }, registrado_em: "2026-10-19T13:00:00Z" });
  const volta = aviso({ fonte: "conexao", assunto: "sistema", destino: "acorde", dia: h, registrado_em: "2026-10-20T13:00:00Z", dados: { desde: "2026-10-16T11:45:00Z", ate: "2026-10-20T13:00:00Z" } });
  const volta2 = aviso({ fonte: "conexao", assunto: "sistema", destino: "acorde", dia: h, registrado_em: "2026-10-20T15:05:00Z", dados: { desde: "2026-10-20T14:30:00Z", ate: "2026-10-20T15:05:00Z" } });
  const p = planoDoGuardado({ avisos: [m17, m18, m19, promessa, volta, volta2], mensagem: "fechamento", hoje: h, resolvidosAgora: new Set(), regras: REGRAS_PADRAO });
  assertEquals(p.linhas, [
    "o WhatsApp ficou fora do ar de 16/10 08:45 a 20/10 10:00 e das 11:30 às 12:05; as manhãs de 17/10, 18/10 e 19/10 não chegaram",
    'promessa sua a Nelson: "vou ver o display"',
  ]);
  assertEquals(p.mostrados.sort(), [m17.id, m18.id, m19.id, promessa.id, volta.id, volta2.id].sort(), "todos vão (nenhum espera)");
  assertEquals(p.restantes, 0);
  // acima do máximo, a linha do sistema que espera conta UMA vez (não três), e nenhum dos avisos dela é marcado
  const cheio = planoDoGuardado({ avisos: [promessa, m17, m18, m19], mensagem: "fechamento", hoje: h, resolvidosAgora: new Set(), regras: REGRAS_PADRAO, max: 1 });
  assertEquals([cheio.linhas.length, cheio.restantes, cheio.mostrados], [1, 1, [promessa.id]]);
  // um aviso de sistema sozinho = a linha de sempre
  const so = planoDoGuardado({ avisos: [m17], mensagem: "manha", hoje: h, resolvidosAgora: new Set(), regras: REGRAS_PADRAO });
  assertEquals(so.linhas, ["a manhã de 17/10 não chegou (WhatsApp fora do ar)"]);
  // só manhãs perdidas pela montagem
  const erro = planoDoGuardado({
    avisos: [{ ...m17, dados: { motivo: "erro_na_montagem" } }, { ...m18, dados: { motivo: "erro_na_montagem" } }], mensagem: "manha", hoje: h,
    resolvidosAgora: new Set(), regras: REGRAS_PADRAO,
  });
  assertEquals(erro.linhas, ["as manhãs de 17/10 e 18/10 não chegaram (erro ao montar)"]);
});

// deno-lint-ignore no-explicit-any
function banco(o: { saidas?: Array<{ phone_normalized: string; occurred_at: string }>; notas?: Array<{ id: string; status: string }>; erro?: boolean; rpcErro?: boolean } = {}) {
  // deno-lint-ignore no-explicit-any
  const rpcs: Array<{ nome: string; p: any }> = [];
  const admin = {
    from(t: string) {
      const q = {
        select() { return q; }, eq() { return q; }, in() { return t === "issued_fiscal_documents" ? Promise.resolve({ data: o.notas ?? [], error: null }) : q; },
        gte() { return q; }, order() { return q; },
        limit() { return Promise.resolve(o.erro ? { data: null, error: { message: "x" } } : { data: o.saidas ?? [], error: null }); },
      };
      return q;
    },
    // deno-lint-ignore no-explicit-any
    rpc(nome: string, args: any) {
      rpcs.push({ nome, p: args.p });
      return Promise.resolve(o.rpcErro ? { data: null, error: { message: "x" } } : { data: { ok: true, incluidos: args.p.ids?.length ?? 0, resolvidos: args.p.ids?.length ?? 0 }, error: null });
    },
  };
  return { admin, rpcs };
}

Deno.test("D8 no banco: contato respondido depois da mensagem = resolvido; nota que saiu de rejeitada = resolvida; erro = nenhum", async () => {
  const a1 = aviso({ assunto: "contato:351900000422", dados: { mensagem_em: "2026-10-15T12:02:00Z" } });
  const a2 = aviso({ assunto: "contato:5547900000001", registrado_em: "2026-10-15T12:45:00Z" });
  const a3 = aviso({ assunto: "fiscal:nfe_rejeitada", dados: { nota_id: "n1" } });
  const { admin } = banco({
    saidas: [{ phone_normalized: "351900000422", occurred_at: "2026-10-15T13:00:00Z" }, { phone_normalized: "5547900000001", occurred_at: "2026-10-15T11:00:00Z" }],
    notas: [{ id: "n1", status: "authorized" }],
  });
  const r = await quaisSeResolveram(admin, [a1, a2, a3]);
  assertEquals([...r].sort(), [a1.id, a3.id].sort(), "a2 teve saída ANTES do aviso: não resolve");
  const erro = await quaisSeResolveram(banco({ erro: true }).admin, [a1]);
  assertEquals(erro.size, 0);
});

Deno.test("marcar: resolver e incluir; sem fila não manda fila_id (a sombra); erro não lança", async () => {
  const { admin, rpcs } = banco();
  const r = await marcarNaMensagem(admin, { phone: "5547900000009", modo: "sombra", mostrados: ["a", "b"], resolvidos: ["c"] });
  assertEquals(r, { incluidos: 2, resolvidos: 1 });
  assertEquals(rpcs.map((x) => x.nome), ["aviso_resolver", "avisos_incluir_na_mensagem"]);
  assertEquals("fila_id" in rpcs[1].p, false);
  const comFila = banco();
  await marcarNaMensagem(comFila.admin, { phone: "5547900000009", modo: "ligado", mostrados: ["a"], resolvidos: [], filaId: "f1" });
  assertEquals(comFila.rpcs.map((x) => [x.nome, x.p.fila_id]), [["avisos_incluir_na_mensagem", "f1"]]);
  const nada = banco();
  await marcarNaMensagem(nada.admin, { phone: "5547900000009", modo: "sombra", mostrados: [], resolvidos: [] });
  assertEquals(nada.rpcs.length, 0, "nada a marcar = nenhuma chamada");
  assertEquals(await marcarNaMensagem(banco({ rpcErro: true }).admin, { phone: "x", modo: "sombra", mostrados: ["a"], resolvidos: ["b"] }), { incluidos: 0, resolvidos: 0 });
  // (20/10/2026) ligado SEM o id da fila: o resolvido some, os mostrados NÃO são marcados (voltam na próxima mensagem)
  const semFila = banco();
  const rs = await marcarNaMensagem(semFila.admin, { phone: "5547900000009", modo: "ligado", mostrados: ["a"], resolvidos: ["c"], filaId: null });
  assertEquals(semFila.rpcs.map((x) => x.nome), ["aviso_resolver"]);
  assertEquals(rs, { incluidos: 0, resolvidos: 1 });
});

Deno.test("fila da tarde (20/10/2026): a chave é a de resumo_tarde_registrar; o id vem pela chave; erro = null", async () => {
  assertEquals(chaveDaFilaDaTarde("2026-10-21", "5547900000009"), "secretario_tarde:2026-10-21:5547900000009");
  // deno-lint-ignore no-explicit-any
  const filtros: any[] = [];
  const db = (resposta: unknown) => ({
    from(t: string) {
      const q = {
        select(c: string) { filtros.push(["select", t, c]); return q; },
        eq(c: string, v: string) { filtros.push(["eq", c, v]); return q; },
        maybeSingle() { return Promise.resolve(resposta); },
      };
      return q;
    },
  });
  assertEquals(await idDaFilaPelaChave(db({ data: { id: "f-1" }, error: null }), "secretario_tarde:2026-10-21:5547900000009"), "f-1");
  assertEquals(filtros, [["select", "whatsapp_send_queue", "id"], ["eq", "dedupe_key", "secretario_tarde:2026-10-21:5547900000009"]]);
  assertEquals(await idDaFilaPelaChave(db({ data: null, error: null }), "x"), null);
  assertEquals(await idDaFilaPelaChave(db({ data: null, error: { message: "falhou" } }), "x"), null);
  assertEquals(await idDaFilaPelaChave({ from() { throw new Error("rede"); } }, "x"), null);
});
