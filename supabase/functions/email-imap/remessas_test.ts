// Agenda de Produção, Fase 4 (P3): a remessa da NF-e do e-mail. O que se protege: a RPC é chamada com o id do e-mail; erro
// nunca derruba a leitura (vai para app_error_logs); função ausente é silêncio; a releitura ?remessas=1 respeita o modo, o
// corte de remessa_dias e as notas que já viraram remessa, relê o XML só da extração antiga e não perde os boletos.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  corteDaRemessa, juntarNotasRelidas, LOTE_DA_RELEITURA, notasPendentes, registrarRemessas, relerRemessas, RPC_REMESSAS,
  temNotaParaEmpresa,
} from "./remessas.ts";
import { dvChaveAcesso } from "../_shared/email/nfe-identify.ts";

type Resposta = { data?: unknown; error?: { code?: string; message: string } | null };

/** Um banco de mentira: rpc e from(...) encadeável que grava o que pediram e devolve o que o teste mandou. */
function bancoFalso(opts: {
  rpc?: (nome: string, args: Record<string, unknown>) => Resposta | Promise<Resposta>;
  tabelas?: Record<string, Resposta>;
  arquivos?: Record<string, string>;
}) {
  const rpcs: [string, Record<string, unknown>][] = [];
  const updates: [string, Record<string, unknown>, unknown][] = [];
  const downloads: string[] = [];
  const db = {
    rpcs, updates, downloads,
    rpc: async (nome: string, args: Record<string, unknown>) => {
      rpcs.push([nome, args]);
      if (nome === "log_app_error") return { data: null, error: null };
      return await (opts.rpc?.(nome, args) ?? { data: null, error: null });
    },
    from: (tabela: string) => {
      let atualizar: Record<string, unknown> | null = null;
      const q: Record<string, unknown> = {};
      const fim = () => {
        if (atualizar) return { data: null, error: null };
        return opts.tabelas?.[tabela] ?? { data: [], error: null };
      };
      for (const m of ["select", "not", "gte", "order", "limit", "in", "is"]) q[m] = () => q;
      q.update = (v: Record<string, unknown>) => { atualizar = v; return q; };
      q.eq = (_c: string, valor: unknown) => { if (atualizar) updates.push([tabela, atualizar, valor]); return q; };
      q.maybeSingle = () => Promise.resolve(fim());
      q.then = (ok: (r: unknown) => unknown, erro?: (e: unknown) => unknown) => Promise.resolve(fim()).then(ok, erro);
      return q;
    },
    storage: {
      from: () => ({
        download: (caminho: string) => {
          downloads.push(caminho);
          const txt = opts.arquivos?.[caminho];
          return Promise.resolve(txt === undefined ? { data: null, error: { message: "sumiu" } }
            : { data: new Blob([txt]), error: null });
        },
      }),
    },
  };
  return db;
}

const chave = (base: string) => base.slice(0, 43) + dvChaveAcesso(base.slice(0, 43));
const K1 = chave("32261011222333000144550010000510381000000001");
const K2 = chave("42261044555666000177550010000008121000000009");
const nfe = (k: string, extra: Record<string, unknown> = {}) => ({
  anexo_indice: 0, chave: k, emitente: "X", emitente_cnpj: "11222333000144", numero: "1", serie: "1", valor: 10,
  data: "2026-10-26", para_empresa: true, ...extra,
});

Deno.test("registrarRemessas: chama a RPC com o id do e-mail e devolve o que ela disse", async () => {
  const db = bancoFalso({ rpc: () => ({ data: { criadas: 2, ja_existiam: 0, ignoradas: 0 }, error: null }) });
  assertEquals(await registrarRemessas(db, "e1"), { criadas: 2, ja_existiam: 0, ignoradas: 0 });
  assertEquals(db.rpcs, [[RPC_REMESSAS, { p_email_message_id: "e1" }]]);
});

Deno.test("registrarRemessas: a função ausente (migration não aplicada) é silêncio — nada em app_error_logs", async () => {
  for (const code of ["PGRST202", "42883"]) {
    const db = bancoFalso({ rpc: () => ({ data: null, error: { code, message: "não existe" } }) });
    assertEquals(await registrarRemessas(db, "e1"), null);
    assertEquals(db.rpcs.map((r) => r[0]), [RPC_REMESSAS]);
  }
});

Deno.test("registrarRemessas: erro do banco ou exceção NUNCA lança — vai para app_error_logs (email-imap, agenda:remessas)", async () => {
  const comErro = bancoFalso({ rpc: () => ({ data: null, error: { code: "23514", message: "check" } }) });
  assertEquals(await registrarRemessas(comErro, "e1"), null);
  const log = comErro.rpcs.find((r) => r[0] === "log_app_error")!;
  assertEquals([log[1].p_context, log[1].p_action, log[1].p_level], ["email-imap", "agenda:remessas", "error"]);
  assert(String(log[1].p_message).includes("e1"));

  const explode = bancoFalso({ rpc: () => { throw new Error("rede caiu"); } });
  assertEquals(await registrarRemessas(explode, "e2"), null);
  assert(explode.rpcs.some((r) => r[0] === "log_app_error"));
});

Deno.test("temNotaParaEmpresa: só NF-e destinada à HBR conta", () => {
  assertEquals(temNotaParaEmpresa(null), false);
  assertEquals(temNotaParaEmpresa({ nfes: [] }), false);
  assertEquals(temNotaParaEmpresa({ nfes: [nfe(K1, { para_empresa: false })] }), false);
  assertEquals(temNotaParaEmpresa({ nfes: [nfe(K1, { para_empresa: false }), nfe(K2)] }), true);
});

Deno.test("corteDaRemessa: o dia de Brasília menos remessa_dias (00:30 UTC de 31/10 ainda é 30/10 em Brasília)", () => {
  assertEquals(corteDaRemessa(new Date("2026-10-30T15:00:00Z"), 30), "2026-09-30");
  assertEquals(corteDaRemessa(new Date("2026-10-31T00:30:00Z"), 30), "2026-09-30");
  assertEquals(corteDaRemessa(new Date("2026-10-31T03:30:00Z"), 30), "2026-10-01");
});

Deno.test("notasPendentes: para a HBR, dentro do corte e sem remessa", () => {
  const m = {
    id: "m", received_at: "2026-10-26T12:00:00Z", subject: null, body_text: null,
    dados_extraidos: { nfes: [nfe(K1), nfe(K2), nfe(chave("1".repeat(43)), { para_empresa: false }),
                              nfe(chave("2".repeat(43)), { data: "2026-09-01" })] },
  };
  assertEquals(notasPendentes(m, new Set([K2]), "2026-09-30").map((n) => n.chave), [K1]);
});

const xmlDaKamell = `<nfeProc><NFe><infNFe versao="4.00" Id="NFe${K1}"><ide><nNF>51038</nNF><dhEmi>2026-10-26T09:00:00-03:00</dhEmi>` +
  `<dhSaiEnt>2026-10-26T15:00:00-03:00</dhSaiEnt></ide><emit><CNPJ>11222333000144</CNPJ><xNome>KAMELL</xNome>` +
  `<enderEmit><xMun>Vila Velha</xMun><UF>ES</UF></enderEmit></emit><dest><CNPJ>50057049000159</CNPJ></dest>` +
  `<det nItem="1"><prod><cProd>1</cProd><xProd>CERBO GX</xProd><uCom>UN</uCom><qCom>1</qCom></prod></det>` +
  `<total><ICMSTot><vNF>3054.44</vNF></ICMSTot></total><transp><modFrete>0</modFrete></transp></infNFe></NFe></nfeProc>`;

Deno.test("relerRemessas: desligado (ou sem a Fase 4 no banco) não faz nada", async () => {
  const desl = bancoFalso({ tabelas: { agenda_config: { data: { modo_material: "desligado", remessa_dias: 30 }, error: null } } });
  assertEquals((await relerRemessas(desl, null)).pulado, true);
  assertEquals(desl.rpcs.length, 0);
  const sem = bancoFalso({ tabelas: { agenda_config: { data: null, error: { code: "42703", message: "coluna não existe" } } } });
  assertEquals((await relerRemessas(sem, null)).pulado, true);
});

Deno.test("relerRemessas: a extração antiga relê o XML e regrava as NF-e (os boletos ficam); a que já tem remessa fica de fora", async () => {
  const antiga = {
    id: "m1", received_at: "2026-10-26T12:00:00Z", subject: "NF", body_text: null,
    dados_extraidos: { nfes: [{ ...nfe(K1), anexo_id: "a1" }].map(({ ...n }) => { return n; }), boletos: [{ linha: "123" }] },
    email_attachments: [{ id: "a1", filename: "nfe.xml", mime_type: "application/xml", storage_path: "m1/0-nfe.xml" },
                        { id: "a2", filename: "boleto.pdf", mime_type: "application/pdf", storage_path: "m1/1-boleto.pdf" }],
  };
  const pronta = {
    id: "m2", received_at: "2026-10-29T12:00:00Z", subject: "NF", body_text: null,
    dados_extraidos: { nfes: [nfe(K2, { itens: [] })] }, email_attachments: [],
  };
  const db = bancoFalso({
    tabelas: {
      agenda_config: { data: { modo_material: "sombra", remessa_dias: 30 }, error: null },
      email_messages: { data: [antiga, pronta], error: null },
      material_remessas: { data: [{ nfe_chave: K2 }], error: null },
    },
    arquivos: { "m1/0-nfe.xml": xmlDaKamell },
    rpc: () => ({ data: { criadas: 1 }, error: null }),
  });
  const r = await relerRemessas(db, "50057049000159", new Date("2026-10-30T15:00:00Z"));
  assertEquals([r.relidas, r.registradas, r.faltam, r.texto], [1, 1, 0, "nada a reler"]);
  assertEquals(db.downloads, ["m1/0-nfe.xml"]);   // só o XML; o PDF do boleto não é baixado
  const [tabela, gravado, id] = db.updates[0];
  assertEquals([tabela, id], ["email_messages", "m1"]);
  const dados = gravado.dados_extraidos as { nfes: Record<string, unknown>[]; boletos: unknown[] };
  assertEquals(dados.boletos, [{ linha: "123" }]);
  assertEquals([dados.nfes[0].saida, dados.nfes[0].uf, dados.nfes[0].anexo_id], ["2026-10-26", "ES", "a1"]);
  assertEquals((dados.nfes[0].itens as unknown[]).length, 1);
  assertEquals(db.rpcs.filter((x) => x[0] === RPC_REMESSAS).map((x) => x[1]), [{ p_email_message_id: "m1" }]);
});

// Revisão da Fase 4, C2 (R2): a mensagem com duas NF-e, uma cujo XML sumiu do bucket. Antes, a releitura regravava só a que
// leu e apagava a outra calada (NotasRecebidasPorEmail e a conciliação de comprovantes leem dados_extraidos.nfes).
Deno.test("relerRemessas: só a nota relida muda; a que não baixou fica como estava (não some)", async () => {
  const K3 = chave("42261044555666000177550010000009991000000003");
  const duas = {
    id: "m3", received_at: "2026-10-26T12:00:00Z", subject: "NFs", body_text: null,
    dados_extraidos: {
      nfes: [{ ...nfe(K3, { numero: "999" }), anexo_id: "b2", conferida: true }, { ...nfe(K1), anexo_id: "b1" }],
      boletos: [],
    },
    email_attachments: [{ id: "b1", filename: "kamell.xml", mime_type: "application/xml", storage_path: "m3/0-kamell.xml" },
                        { id: "b2", filename: "correa.xml", mime_type: "application/xml", storage_path: "m3/1-correa.xml" }],
  };
  const db = bancoFalso({
    tabelas: {
      agenda_config: { data: { modo_material: "sombra", remessa_dias: 30 }, error: null },
      email_messages: { data: [duas], error: null },
      material_remessas: { data: [], error: null },
    },
    arquivos: { "m3/0-kamell.xml": xmlDaKamell },   // o da Correa sumiu do bucket
    rpc: () => ({ data: { criadas: 1 }, error: null }),
  });
  const r = await relerRemessas(db, "50057049000159", new Date("2026-10-30T15:00:00Z"));
  assertEquals(r.relidas, 1);
  assertEquals(db.downloads, ["m3/0-kamell.xml", "m3/1-correa.xml"]);
  const nfes = (db.updates[0][1].dados_extraidos as { nfes: Record<string, unknown>[] }).nfes;
  assertEquals(nfes.map((n) => n.chave), [K3, K1]);   // a ordem de antes; nenhuma some
  assertEquals([nfes[0].numero, nfes[0].anexo_id, nfes[0].conferida, "itens" in nfes[0]], ["999", "b2", true, false]);
  assertEquals([nfes[1].uf, nfes[1].anexo_id, (nfes[1].itens as unknown[]).length], ["ES", "b1", 1]);
});

Deno.test("juntarNotasRelidas: troca pela chave, mantém a não relida, acrescenta a nova no fim, a relida repetida conta uma vez", () => {
  const a = nfe(K1, { numero: "1" });
  const b = nfe(K2, { numero: "2" });
  const novaK1 = nfe(K1, { numero: "1", uf: "ES", itens: [] });
  const K4 = chave("42261044555666000177550010000004441000000004");
  const nova = nfe(K4, { numero: "4", itens: [] });
  // deno-lint-ignore no-explicit-any
  const r = juntarNotasRelidas([a, b] as any, [novaK1, nova, { ...novaK1, numero: "repetida" }] as any);
  assertEquals(r.map((n) => [n.chave, n.numero, n.uf ?? null]), [[K1, "1", "ES"], [K2, "2", null], [K4, "4", null]]);
  // deno-lint-ignore no-explicit-any
  assertEquals(juntarNotasRelidas([a, b] as any, []), [a, b]);
});

Deno.test("relerRemessas: no máximo LOTE_DA_RELEITURA mensagens por chamada, e diz quantas faltam", async () => {
  const msgs = Array.from({ length: LOTE_DA_RELEITURA + 3 }, (_, i) => ({
    id: `m${i}`, received_at: "2026-10-26T12:00:00Z", subject: null, body_text: null,
    dados_extraidos: { nfes: [nfe(chave(String(i).padStart(43, "7")), { itens: [] })] }, email_attachments: [],
  }));
  const db = bancoFalso({
    tabelas: { agenda_config: { data: { modo_material: "ligado", remessa_dias: 30 }, error: null },
               email_messages: { data: msgs, error: null }, material_remessas: { data: [], error: null } },
    rpc: () => ({ data: { criadas: 1 }, error: null }),
  });
  const r = await relerRemessas(db, null, new Date("2026-10-30T15:00:00Z"));
  assertEquals([r.registradas, r.faltam], [LOTE_DA_RELEITURA, 3]);
  assertEquals(db.updates.length, 0);   // todas já tinham itens: nada relido
});
