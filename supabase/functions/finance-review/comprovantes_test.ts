// Os comprovantes (CMP) no finance-review (F3, spec-f3.md 5.1): R1 e R2 falhando não derrubam a
// rodada; as linhas reservadas por um CMP saem do "lançar sozinho"; a linha cujo CMP anexou uma
// conta a pagar em aberto não ganha despesa nova. Banco falso, sem rede.
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/finance-review/comprovantes_test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  aprovarDoComprovante,
  aprovarOsDaVarredura,
  type AprovarUma,
  foraDasReservadas,
  linhasDeComprovante,
  mensagemDosComprovantes,
  reavaliarComprovantes,
  recusaDaLinhaDoCmp,
  reservadasDaRodada,
  responderApproveCmp,
} from "./comprovantes.ts";
import { motivoParaNaoLancarSozinho } from "./lancar-sozinho.ts";

const TX_LIGADA = "55555555-0000-4000-8000-000000000001";
const TX_CANDIDATA = "55555555-0000-4000-8000-000000000002";
const TX_LIVRE = "55555555-0000-4000-8000-000000000003";
const TX_CONTA = "55555555-0000-4000-8000-000000000004";
const ANOTACAO = "66666666-0000-4000-8000-000000000001";

// deno-lint-ignore no-explicit-any
type Qualquer = any;

function adminFalso(respostas: Record<string, { data?: unknown; error?: unknown } | Error>) {
  const chamadas: Array<{ nome: string; args: Qualquer }> = [];
  return {
    chamadas,
    admin: {
      rpc(nome: string, args: Qualquer) {
        chamadas.push({ nome, args });
        const r = respostas[nome];
        if (r instanceof Error) return Promise.reject(r);
        if (!r) return Promise.resolve({ data: null, error: { code: "PGRST202", message: `sem dublê para ${nome}` } });
        return Promise.resolve({ data: r.data ?? null, error: r.error ?? null });
      },
    },
  };
}

/** Os logs (console.warn) durante `f`, para provar que só o código do erro vai a eles. */
async function comLogs(f: () => Promise<unknown>): Promise<string> {
  const saida: string[] = [];
  const original = console.warn;
  console.warn = (...a: unknown[]) => { saida.push(a.map(String).join(" ")); };
  try {
    await f();
  } finally {
    console.warn = original;
  }
  return saida.join("\n");
}

const CMP = "77777777-0000-4000-8000-0000000000c1";
const CMP_2 = "77777777-0000-4000-8000-0000000000c2";
const PROPOSTA = "88888888-0000-4000-8000-000000000001";
const PAYABLE = "99999999-0000-4000-8000-000000000001";
const DONO = "aaaaaaaa-0000-4000-8000-00000000d0d0";
const OUTRO = "aaaaaaaa-0000-4000-8000-00000000beef";

/** A Varredura (3.7) que a R1 devolve — sem o "só registro" (ajustes do dono) e com as ligadas a aprovar. */
const VARREDURA = {
  avaliados: 4, ligados: 2, explicadas: 1, desligados: 0, verdes: 1, azuis: 1, cinzas: 2, abandonados: 0, notas: 0,
  perguntar: ["5547999990000"], reservadas: [TX_LIGADA, TX_CANDIDATA, "não-é-uuid"], classificadas: 1,
  aprovar: [
    { cmp_id: CMP, proposta_id: PROPOSTA, autor: DONO },
    { cmp_id: CMP, proposta_id: PROPOSTA, autor: DONO }, // repetido
    { cmp_id: "x", proposta_id: PROPOSTA, autor: DONO }, // malformado
  ],
};

Deno.test("R1: a varredura devolve as reservadas (só uuids), as classificadas, os ligados e as ligadas a aprovar", async () => {
  const b = adminFalso({ comprovantes_reavaliar_banco: { data: VARREDURA } });
  const r = await reavaliarComprovantes(b.admin);
  assertEquals(b.chamadas, [{ nome: "comprovantes_reavaliar_banco", args: { p_origem: "finance_review" } }]);
  assertEquals(r.ok, true);
  assertEquals([...r.reservadas], [TX_LIGADA, TX_CANDIDATA]);
  assertEquals([r.classificadas, r.ligados], [1, 2]);
  assertEquals(r.aprovar, [{ cmp_id: CMP, proposta_id: PROPOSTA, autor: DONO }]);
  // sem a chave (banco de antes): nada a aprovar
  const semChave = await reavaliarComprovantes(adminFalso({ comprovantes_reavaliar_banco: { data: { ligados: 1 } } }).admin);
  assertEquals(semChave.aprovar, []);
});

Deno.test("R1 falhando (erro do banco, função ausente, rede) não derruba: nada reservado e o log só com o código", async () => {
  for (const resposta of [{ error: { code: "42883", message: "function AutoZone 50.98 does not exist" } }, new Error("rede"), undefined]) {
    const b = adminFalso(resposta ? { comprovantes_reavaliar_banco: resposta } : {});
    let r: Awaited<ReturnType<typeof reavaliarComprovantes>> | null = null;
    const logs = await comLogs(async () => { r = await reavaliarComprovantes(b.admin); });
    assertEquals(r, { ok: false, reservadas: new Set(), classificadas: 0, ligados: 0, aprovar: [] });
    assert(logs.includes("reavaliar_falhou"));
    assertEquals(logs.includes("AutoZone"), false);
    assertEquals(logs.includes("50.98"), false);
  }
});

Deno.test("R2: de quem é cada linha; a ligada vale mais que a candidata; só as pedidas, sem repetir", async () => {
  const b = adminFalso({
    comprovantes_linhas_da_conciliacao: {
      data: {
        linhas: [
          { bank_transaction_id: TX_LIGADA, codigo: "CMP-00124", papel: "ligada", conta_aberta_id: null },
          { bank_transaction_id: TX_CANDIDATA, codigo: "CMP-00125", papel: "candidata", conta_aberta_id: null },
          // a mesma linha: ligada a um CMP e candidata de outro → ligada
          { bank_transaction_id: TX_LIGADA, codigo: "CMP-00126", papel: "candidata", conta_aberta_id: null },
          { bank_transaction_id: TX_CONTA, codigo: "CMP-00127", papel: "ligada", conta_aberta_id: "77777777-0000-4000-8000-000000000001" },
          { bank_transaction_id: null, codigo: "CMP-00128", papel: "ligada" },
        ],
        anotacoes: [ANOTACAO, 12],
      },
    },
  });
  const r = await linhasDeComprovante(b.admin, [TX_LIGADA, TX_CANDIDATA, TX_LIGADA, TX_CONTA, "x"]);
  assertEquals(b.chamadas[0].args, { p_transacoes: [TX_LIGADA, TX_CANDIDATA, TX_CONTA] });
  assertEquals(r.linhas.get(TX_LIGADA), { codigo: "CMP-00124", papel: "ligada", conta_aberta_id: null });
  assertEquals(r.linhas.get(TX_CANDIDATA)?.papel, "candidata");
  assertEquals(r.linhas.get(TX_CONTA)?.conta_aberta_id, "77777777-0000-4000-8000-000000000001");
  assertEquals(r.linhas.size, 3);
  assertEquals([...r.anotacoes], [ANOTACAO]);
});

Deno.test("R2 falhando ou sem linhas: Map vazio (quem chama segue como antes da F3); sem linhas nem consulta", async () => {
  const vazio = adminFalso({});
  assertEquals((await linhasDeComprovante(vazio.admin, [])).linhas.size, 0);
  assertEquals(vazio.chamadas.length, 0);
  for (const resposta of [{ error: { code: "42883" } }, new Error("rede")]) {
    const b = adminFalso({ comprovantes_linhas_da_conciliacao: resposta });
    let r: Awaited<ReturnType<typeof linhasDeComprovante>> | null = null;
    const logs = await comLogs(async () => { r = await linhasDeComprovante(b.admin, [TX_LIGADA]); });
    assertEquals(r!.linhas.size, 0);
    assertEquals(r!.anotacoes.size, 0);
    assert(logs.includes("linhas_falhou"));
  }
});

Deno.test("reservadas da rodada: as da R1; com a R1 fora, as da R2 para as linhas novas; as duas fora, nenhuma", async () => {
  const ok = adminFalso({});
  assertEquals([...await reservadasDaRodada(ok.admin, { ok: true, reservadas: new Set([TX_LIGADA]), classificadas: 0, ligados: 0, aprovar: [] }, [TX_LIVRE])], [TX_LIGADA]);
  assertEquals(ok.chamadas.length, 0, "com a R1 de pé, a R2 nem é chamada");

  const fallback = adminFalso({
    comprovantes_linhas_da_conciliacao: { data: { linhas: [{ bank_transaction_id: TX_CANDIDATA, codigo: "CMP-00125", papel: "candidata" }], anotacoes: [] } },
  });
  const falhou = { ok: false, reservadas: new Set<string>(), classificadas: 0, ligados: 0, aprovar: [] };
  assertEquals([...await reservadasDaRodada(fallback.admin, falhou, [TX_CANDIDATA, TX_LIVRE])], [TX_CANDIDATA]);

  const tudoFora = adminFalso({ comprovantes_linhas_da_conciliacao: new Error("rede") });
  const r = await comLogs(async () => {
    assertEquals((await reservadasDaRodada(tudoFora.admin, falhou, [TX_LIVRE])).size, 0);
  });
  assert(r.includes("linhas_falhou"));
});

Deno.test("as reservadas saem do automático: da regra (idsAuto) e da confiança (jaPorRegra)", () => {
  const regra = [{ bank_transaction_id: TX_LIGADA }, { bank_transaction_id: TX_CANDIDATA }, { bank_transaction_id: TX_LIVRE }];
  const anotadasAgora = new Set([TX_CANDIDATA]);
  const reservadas = new Set([TX_LIGADA]);
  assertEquals(foraDasReservadas(regra, anotadasAgora, reservadas), [{ bank_transaction_id: TX_LIVRE }]);
  // por confiança: a reservada entra no jaPorRegra (o mesmo conjunto que o gerar monta) e não vai sozinha
  const linha = {
    kind: "create_payable", bank_transaction_id: TX_LIGADA, confidence: 99, suggested_amount: 50.98,
    suggested_category: "Peças e materiais", dre_group: "custo_servico",
  };
  const criterio = { confiancaMinima: 90, limiteLote: 500, comAlerta: new Set<string>(), jaPorRegra: new Set([...reservadas]) };
  assertEquals(motivoParaNaoLancarSozinho(linha, criterio), "já lançada pela regra");
  assertEquals(motivoParaNaoLancarSozinho({ ...linha, bank_transaction_id: TX_LIVRE }, criterio), null);
});

Deno.test("aprovar: a linha do CMP com conta a pagar em aberto é recusada (case pela Conciliação); as outras seguem", () => {
  assertEquals(
    recusaDaLinhaDoCmp({ codigo: "CMP-00124", papel: "ligada", conta_aberta_id: "77777777-0000-4000-8000-000000000001" }),
    "Esta linha é a do CMP-00124, que anexou uma conta a pagar em aberto: case pela Conciliação em vez de lançar outra",
  );
  assertEquals(recusaDaLinhaDoCmp({ codigo: "CMP-00124", papel: "ligada", conta_aberta_id: null }), null, "ligada e classificada: o dono aprova");
  assertEquals(recusaDaLinhaDoCmp({ codigo: "CMP-00125", papel: "candidata", conta_aberta_id: null }), null);
  // a candidata (forte) de uma pergunta que espera o dono: "pode ser", não "é" — e diz como resolver
  assertEquals(
    recusaDaLinhaDoCmp({ codigo: "CMP-00126", papel: "candidata", conta_aberta_id: "77777777-0000-4000-8000-000000000002" }),
    "Esta linha pode ser a do CMP-00126, que tem uma conta a pagar em aberto: responda a pergunta do extrato no WhatsApp ou case pela Conciliação em vez de lançar outra",
  );
  assertEquals(recusaDaLinhaDoCmp(undefined), null);
  assertEquals(mensagemDosComprovantes(2), "2 comprovante(s) ligado(s) ao extrato");
  assertEquals(mensagemDosComprovantes(0), "");
  assertEquals(mensagemDosComprovantes(2, 1), "2 comprovante(s) ligado(s) ao extrato · 1 linha(s) de comprovante aprovada(s)");
  assertEquals(mensagemDosComprovantes(0, 3), "3 linha(s) de comprovante aprovada(s)");
});

// ─── ajustes do dono: o sim aprova a linha no Extrato (R11 → aprovar → R12) ───────────────────

/** Um aprovar falso que registra as chamadas. */
function aprovarFalso(resposta: Awaited<ReturnType<AprovarUma>> | Error) {
  const chamadas: Array<[string, string]> = [];
  const fn: AprovarUma = (proposta, autor) => {
    chamadas.push([proposta, autor]);
    return resposta instanceof Error ? Promise.reject(resposta) : Promise.resolve(resposta);
  };
  return { chamadas, fn };
}

const R11 = { data: { cmp_id: CMP, proposta_id: PROPOSTA, autor: DONO } };

Deno.test("approve_cmp: só a chamada interna (segredo + o dono); sem eles 401; cmp malformado 400", async () => {
  const b = adminFalso({ comprovante_a_aprovar: R11, comprovante_aprovado: { data: { ok: true } } });
  const ap = aprovarFalso({ ok: true, payable_id: PAYABLE });
  for (const p of [
    { isCron: false, actingUserId: DONO, cmpId: CMP }, // sem o segredo (o JWT de um usuário não basta)
    { isCron: true, actingUserId: null, cmpId: CMP }, // sem quem decide
    { isCron: true, actingUserId: "não-é-uuid", cmpId: CMP },
  ]) {
    const r = await responderApproveCmp(b.admin, p, ap.fn);
    assertEquals(r, { status: 401, corpo: { error: "unauthorized" } });
  }
  assertEquals((await responderApproveCmp(b.admin, { isCron: true, actingUserId: DONO, cmpId: "x" }, ap.fn)).status, 400);
  assertEquals(b.chamadas.length, 0, "nada chega ao banco sem a autorização");
  assertEquals(ap.chamadas.length, 0);
  const ok = await responderApproveCmp(b.admin, { isCron: true, actingUserId: DONO, cmpId: CMP }, ap.fn);
  assertEquals(ok, { status: 200, corpo: { ok: true, proposta_id: PROPOSTA, payable_id: PAYABLE, registrado: true } });
});

Deno.test("aprovarDoComprovante: R11 → aprovar (o dono decide) → R12 com o lançamento criado", async () => {
  const b = adminFalso({ comprovante_a_aprovar: R11, comprovante_aprovado: { data: { ok: true } } });
  const ap = aprovarFalso({ ok: true, payable_id: PAYABLE });
  const r = await aprovarDoComprovante(b.admin, CMP, DONO, ap.fn);
  assertEquals(r, { ok: true, proposta_id: PROPOSTA, payable_id: PAYABLE, registrado: true });
  assertEquals(ap.chamadas, [[PROPOSTA, DONO]]);
  assertEquals(b.chamadas, [
    { nome: "comprovante_a_aprovar", args: { p_cmp: CMP } },
    { nome: "comprovante_aprovado", args: { p_cmp: CMP, p_proposta: PROPOSTA, p_payable: PAYABLE } },
  ]);
});

Deno.test("aprovarDoComprovante: nada a aprovar (linha já lançada, proposta ainda fora da fila) não aprova nada", async () => {
  const b = adminFalso({ comprovante_a_aprovar: { data: null } });
  const ap = aprovarFalso({ ok: true, payable_id: PAYABLE });
  assertEquals(await aprovarDoComprovante(b.admin, CMP, DONO, ap.fn), { ok: true, nada: true });
  assertEquals(ap.chamadas.length, 0);
});

Deno.test("aprovarDoComprovante: autor diferente do dono recusa; falhas viram { ok: false } e o log só leva o código", async () => {
  const outro = adminFalso({ comprovante_a_aprovar: R11 });
  const ap = aprovarFalso({ ok: true, payable_id: PAYABLE });
  let r: Awaited<ReturnType<typeof aprovarDoComprovante>> | null = null;
  await comLogs(async () => { r = await aprovarDoComprovante(outro.admin, CMP, OUTRO, ap.fn); });
  assertEquals(r, { ok: false, motivo: "autor_diferente" });
  assertEquals(ap.chamadas.length, 0, "nunca aprova em nome de outro");

  // R11 fora do ar
  const r11 = adminFalso({ comprovante_a_aprovar: { error: { code: "42883", message: "AutoZone 50.98" } } });
  const logs = await comLogs(async () => { r = await aprovarDoComprovante(r11.admin, CMP, DONO, ap.fn); });
  assertEquals(r, { ok: false, motivo: "sem_resposta" });
  assert(logs.includes("r11:42883"));
  assertEquals(logs.includes("AutoZone"), false);

  // o aprovar recusou (a linha acabou de ser lançada por outro caminho) ou caiu
  const recusou = aprovarFalso({ ok: false, motivo: "Esta linha acabou de ser lançada por outro caminho — revise a fila" });
  await comLogs(async () => { r = await aprovarDoComprovante(adminFalso({ comprovante_a_aprovar: R11 }).admin, CMP, DONO, recusou.fn); });
  assertEquals(r, { ok: false, motivo: "Esta linha acabou de ser lançada por outro caminho — revise a fila", proposta_id: PROPOSTA });
  await comLogs(async () => { r = await aprovarDoComprovante(adminFalso({ comprovante_a_aprovar: R11 }).admin, CMP, DONO, aprovarFalso(new Error("rede")).fn); });
  assertEquals(r, { ok: false, motivo: "nao_aprovada" });

  // R12 falhando duas vezes: a linha está lançada (ok), só o CMP não guardou
  const r12 = adminFalso({ comprovante_a_aprovar: R11, comprovante_aprovado: { error: { code: "40001" } } });
  await comLogs(async () => { r = await aprovarDoComprovante(r12.admin, CMP, DONO, ap.fn); });
  assertEquals(r, { ok: true, proposta_id: PROPOSTA, payable_id: PAYABLE, registrado: false });
  assertEquals(r12.chamadas.filter((c) => c.nome === "comprovante_aprovado").length, 2);
});

Deno.test("gerar: as ligadas a aprovar vão uma por vez; a falha de uma não derruba as outras nem a rodada", async () => {
  const respostas: Record<string, unknown> = {
    [CMP]: R11.data,
    [CMP_2]: { cmp_id: CMP_2, proposta_id: "88888888-0000-4000-8000-000000000002", autor: DONO },
  };
  const chamadas: string[] = [];
  const admin = {
    rpc(nome: string, args: Qualquer) {
      chamadas.push(nome);
      if (nome === "comprovante_a_aprovar") return Promise.resolve({ data: respostas[args.p_cmp] ?? null, error: null });
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  let vez = 0;
  const umaFalha: AprovarUma = () => (++vez === 1 ? Promise.reject(new Error("rede")) : Promise.resolve({ ok: true, payable_id: PAYABLE }));
  let r: Awaited<ReturnType<typeof aprovarOsDaVarredura>> | null = null;
  await comLogs(async () => {
    r = await aprovarOsDaVarredura(admin, [
      { cmp_id: CMP, proposta_id: PROPOSTA, autor: DONO },
      { cmp_id: CMP_2, proposta_id: "88888888-0000-4000-8000-000000000002", autor: DONO },
    ], umaFalha);
  });
  assertEquals(r, { aprovadas: 1, falhas: 1 });
  assertEquals(chamadas, ["comprovante_a_aprovar", "comprovante_a_aprovar", "comprovante_aprovado"]);
});
