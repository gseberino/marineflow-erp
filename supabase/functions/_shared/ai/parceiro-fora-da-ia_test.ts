// Retorno F4 (P12.4): o que entra pelo número do parceiro não vai ao assistente, pelos 6 caminhos das linhas 1 a 6.
// Banco falso; números e frases inventados (finais 4321 e 7391). Nenhuma mensagem real.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { chavesForaDoAssistente, FRASE_FORA_DO_ASSISTENTE, foraDoAssistente } from "./parceiro-fora-da-ia.ts";
import { whatsappHistoryTools } from "./tools/whatsapp-history.ts";
import { entity360Tools } from "./tools/entity-360.ts";
import { whatsappTools } from "./tools/whatsapp.ts";
import { resumirMensagem, ultimaMensagemRecebida } from "./tools/resposta.ts";

const FONE_MP = "5547999994321";
const FONE_CLIENTE = "5547988887391";
const CHAVE_MP = "99994321";

type Rpc = { data?: unknown; error?: { code?: string; message?: string }; lanca?: boolean };
const COM_CHAVE_FALSA: Rpc = { data: [CHAVE_MP] }; // parceiro_historico_na_ia = false (o padrão): a chave do número confirmado
const COM_CHAVE_VERDADEIRA: Rpc = { data: [] }; // = true: nada fica de fora
const AUSENTE: Rpc = { error: { code: "PGRST202", message: "Could not find the function" } };
const ERRO: Rpc = { error: { code: "57014", message: "tempo esgotado" } };

/** Query encadeável que ignora filtros, mas conta quem leu whatsapp_messages. */
function banco(tabelas: Record<string, unknown[]>, rpc: Rpc) {
  const leituras: string[] = [];
  const cadeia = (tabela: string) => {
    const rows = tabelas[tabela] ?? [];
    const result = { data: rows, error: null, count: rows.length };
    // deno-lint-ignore no-explicit-any
    const proxy: any = new Proxy({}, {
      get(_t, prop) {
        if (prop === "then") return (resolve: (v: unknown) => void) => resolve(result);
        if (prop === "maybeSingle" || prop === "single") return () => Promise.resolve({ data: rows[0] ?? null, error: null });
        return () => proxy;
      },
    });
    return proxy;
  };
  const admin = {
    from(tabela: string) {
      leituras.push(tabela);
      return cadeia(tabela);
    },
    rpc(fn: string) {
      leituras.push(`rpc:${fn}`);
      if (fn === "whatsapp_pending_inbox") return Promise.resolve({ data: tabelas.pending ?? [], error: null });
      if (fn !== "parceiro_numeros_fora_da_ia") return Promise.resolve({ data: null, error: null });
      if (rpc.lanca) return Promise.reject(new Error("rede"));
      return Promise.resolve({ data: rpc.data ?? null, error: rpc.error ?? null });
    },
  };
  return { admin, leituras };
}

const ctx = (b: ReturnType<typeof banco>) => ({ sb: b.admin, admin: b.admin, userId: "u1", userRole: "admin" as const, jwt: "", appOrigin: "", settings: {} });

const msg = (fone: string, body: string) => ({
  direction: "inbound", occurred_at: "2027-01-20T13:00:00Z", created_at: "2027-01-20T13:00:00Z", body, message_type: "text", phone_normalized: fone,
});

// ─── chavesForaDoAssistente ────────────────────────────────────────────────────────────────────────────────────

Deno.test("chavesForaDoAssistente: chave falsa = as chaves; verdadeira = vazio; ausente = vazio; erro e exceção = falhou", async () => {
  assertEquals(await chavesForaDoAssistente(banco({}, COM_CHAVE_FALSA).admin), { chaves: new Set([CHAVE_MP]), falhou: false });
  assertEquals(await chavesForaDoAssistente(banco({}, COM_CHAVE_VERDADEIRA).admin), { chaves: new Set(), falhou: false });
  assertEquals(await chavesForaDoAssistente(banco({}, AUSENTE).admin), { chaves: new Set(), falhou: false });
  assertEquals(await chavesForaDoAssistente(banco({}, { error: { code: "42883" } }).admin), { chaves: new Set(), falhou: false });
  assertEquals((await chavesForaDoAssistente(banco({}, ERRO).admin)).falhou, true);
  assertEquals((await chavesForaDoAssistente(banco({}, { lanca: true }).admin)).falhou, true);
  assertEquals((await chavesForaDoAssistente(banco({}, { data: "x" }).admin)).falhou, true, "forma inesperada fecha");
  assertEquals((await chavesForaDoAssistente(null)).falhou, true);
});

Deno.test("foraDoAssistente: pela chave de 8 dígitos, em qualquer forma do número; falhou = todo número fica de fora", () => {
  const fora = { chaves: new Set([CHAVE_MP]), falhou: false };
  assertEquals(foraDoAssistente(fora, FONE_MP), true);
  assertEquals(foraDoAssistente(fora, "(47) 99999-4321"), true);
  assertEquals(foraDoAssistente(fora, "554799994321"), true, "a forma de 12 dígitos");
  assertEquals(foraDoAssistente(fora, FONE_CLIENTE), false);
  assertEquals(foraDoAssistente(fora, null), false);
  assertEquals(foraDoAssistente({ chaves: new Set(), falhou: true }, FONE_CLIENTE), true);
});

// ─── Linha 1: get_whatsapp_conversation, por contato ───────────────────────────────────────────────────────────

const conversa = whatsappHistoryTools.find((t) => t.name === "get_whatsapp_conversation")!;
const TABELAS = { whatsapp_messages: [msg(FONE_MP, "Mensagem inventada da MP"), msg(FONE_CLIENTE, "Mensagem inventada do cliente")], clients: [], suppliers: [], app_users: [] };

Deno.test("linha 1: número confirmado, com a chave falsa, recusa antes da consulta; com a verdadeira, como hoje", async () => {
  const fechado = banco(TABELAS, COM_CHAVE_FALSA);
  const r = await conversa.execute({ phone: FONE_MP }, ctx(fechado) as never) as Record<string, unknown>;
  assertEquals(r, { error: FRASE_FORA_DO_ASSISTENTE });
  assertEquals(fechado.leituras.includes("whatsapp_messages"), false, "não consultou as mensagens");

  const aberto = banco(TABELAS, COM_CHAVE_VERDADEIRA);
  const hoje = banco(TABELAS, AUSENTE);
  const rAberto = await conversa.execute({ phone: FONE_MP }, ctx(aberto) as never);
  const rHoje = await conversa.execute({ phone: FONE_MP }, ctx(hoje) as never);
  assertEquals(rAberto, rHoje, "verdadeira = função ausente = a saída de hoje");
  assert(Array.isArray((rAberto as Record<string, unknown>).mensagens));
  // outro número segue como sempre, com a chave falsa
  const outro = await conversa.execute({ phone: FONE_CLIENTE }, ctx(banco(TABELAS, COM_CHAVE_FALSA)) as never) as Record<string, unknown>;
  assert(Array.isArray(outro.mensagens));
});

Deno.test("linha 1: erro na leitura das chaves fecha (falha fecha)", async () => {
  const r = await conversa.execute({ phone: FONE_CLIENTE }, ctx(banco(TABELAS, ERRO)) as never);
  assertEquals(r, { error: FRASE_FORA_DO_ASSISTENTE });
});

// ─── Linha 2: a busca em todas as conversas ─────────────────────────────────────────────────────────────────────

Deno.test("linha 2: as linhas de chave confirmada saem do resultado, sem contar quantas; com a verdadeira, como hoje", async () => {
  const fechado = await conversa.execute({ contem: "inventada" }, ctx(banco(TABELAS, COM_CHAVE_FALSA)) as never) as Record<string, any>;
  assertEquals(fechado.total_encontrado, 1);
  assertEquals(fechado.conversas.map((c: { telefone: string }) => c.telefone), [FONE_CLIENTE]);
  assert(!JSON.stringify(fechado).includes("da MP"));
  const aberto = await conversa.execute({ contem: "inventada" }, ctx(banco(TABELAS, COM_CHAVE_VERDADEIRA)) as never);
  const hoje = await conversa.execute({ contem: "inventada" }, ctx(banco(TABELAS, AUSENTE)) as never);
  assertEquals(aberto, hoje);
  assertEquals((aberto as Record<string, number>).total_encontrado, 2);
  const erro = await conversa.execute({ contem: "inventada" }, ctx(banco(TABELAS, ERRO)) as never) as Record<string, unknown>;
  assertEquals(erro.total_encontrado, 0, "falha fecha: nada sai");
});

// ─── Linhas 3 e 4: get_client_360 e get_supplier_360 ────────────────────────────────────────────────────────────

const cliente360 = entity360Tools.find((t) => t.name === "get_client_360")!;
const fornecedor360 = entity360Tools.find((t) => t.name === "get_supplier_360")!;

Deno.test("linhas 3 e 4: mensagens vazias e a nota, com a chave falsa; com a verdadeira, como hoje", async () => {
  const tabelas = {
    clients: [{ id: "c1", name: "MP Inventada", whatsapp: FONE_MP, phone: null }],
    suppliers: [{ id: "f1", name: "Fornecedor Inventado", phone: FONE_MP }],
    whatsapp_messages: [msg(FONE_MP, "Mensagem inventada")],
  };
  for (const [tool, args, chave] of [[cliente360, { client_id: "c1" }, "cliente"], [fornecedor360, { supplier_id: "f1" }, "fornecedor"]] as const) {
    const fechado = await tool.execute(args, ctx(banco(tabelas, COM_CHAVE_FALSA)) as never) as Record<string, any>;
    assertEquals(fechado.conversa_recente, [], chave);
    assertEquals(fechado.nota, FRASE_FORA_DO_ASSISTENTE, chave);
    const aberto = await tool.execute(args, ctx(banco(tabelas, COM_CHAVE_VERDADEIRA)) as never) as Record<string, any>;
    const hoje = await tool.execute(args, ctx(banco(tabelas, AUSENTE)) as never);
    assertEquals(aberto, hoje, chave);
    assertEquals("nota" in aberto, false, chave);
    assertEquals(aberto.conversa_recente.length, 1, chave);
    const erro = await tool.execute(args, ctx(banco(tabelas, ERRO)) as never) as Record<string, any>;
    assertEquals(erro.conversa_recente, [], `${chave}: falha fecha`);
  }
});

// ─── Linha 5: list_unanswered_messages ──────────────────────────────────────────────────────────────────────────

const caixa = whatsappTools.find((t) => t.name === "list_unanswered_messages")!;

Deno.test("linha 5: previa nula para a chave confirmada; contato e hora ficam; com a verdadeira, como hoje", async () => {
  const pending = [
    { phone: FONE_MP, contato: "MP Inventada", is_client: false, last_inbound_at: "2027-01-20T13:00:00Z", unread_count: 2, last_body: "Mensagem inventada da MP" },
    { phone: FONE_CLIENTE, contato: "João", is_client: true, last_inbound_at: "2027-01-20T13:00:00Z", unread_count: 1, last_body: "Mensagem inventada do cliente" },
  ];
  const fechado = await caixa.execute({}, ctx(banco({ pending }, COM_CHAVE_FALSA)) as never) as Record<string, any>;
  assertEquals(fechado.pendentes[0].previa, null);
  assertEquals(fechado.pendentes[0].contato, "MP Inventada");
  assertEquals(fechado.pendentes[0].nao_lidas, 2);
  assert(fechado.pendentes[1].previa);
  const aberto = await caixa.execute({}, ctx(banco({ pending }, COM_CHAVE_VERDADEIRA)) as never) as Record<string, any>;
  const hoje = await caixa.execute({}, ctx(banco({ pending }, AUSENTE)) as never) as Record<string, any>;
  assertEquals(JSON.stringify(aberto.pendentes.map((p: Record<string, unknown>) => p.previa)), JSON.stringify(hoje.pendentes.map((p: Record<string, unknown>) => p.previa)));
  assert(aberto.pendentes[0].previa);
  const erro = await caixa.execute({}, ctx(banco({ pending }, ERRO)) as never) as Record<string, any>;
  assertEquals(erro.pendentes.map((p: Record<string, unknown>) => p.previa), [null, null]);
});

// ─── Linha 6: o resumo da confirmação de send_whatsapp_message ──────────────────────────────────────────────────

Deno.test("linha 6: sem a linha 'Última mensagem dele' para a chave confirmada; com a verdadeira, como hoje", async () => {
  const tabelas = { whatsapp_messages: [{ body: "Mensagem inventada da MP", occurred_at: "2027-01-20T13:00:00Z" }], whatsapp_leads: [{ name: "MP Inventada" }] };
  assertEquals(await ultimaMensagemRecebida(banco(tabelas, COM_CHAVE_FALSA).admin, FONE_MP), null);
  const fechado = await resumirMensagem(banco(tabelas, COM_CHAVE_FALSA).admin, { to_phone: FONE_MP, message: "Oi" });
  assert(!fechado.includes("Última mensagem"), fechado);
  const aberto = await resumirMensagem(banco(tabelas, COM_CHAVE_VERDADEIRA).admin, { to_phone: FONE_MP, message: "Oi" });
  const hoje = await resumirMensagem(banco(tabelas, AUSENTE).admin, { to_phone: FONE_MP, message: "Oi" });
  assertEquals(aberto, hoje);
  assert(aberto.includes("Última mensagem dele"), aberto);
  const erro = await resumirMensagem(banco(tabelas, ERRO).admin, { to_phone: FONE_MP, message: "Oi" });
  assert(!erro.includes("Última mensagem"), "falha fecha");
});
