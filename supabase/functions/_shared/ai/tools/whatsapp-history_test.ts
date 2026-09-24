import { assertEquals, assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { whatsappHistoryTools, textoDaMensagem } from "./whatsapp-history.ts";

// O que estes testes protegem, em ordem de gravidade:
//
//  1. A ORDEM. O banco devolve descendente (é assim que se pega "as mais recentes"), e a
//     conversa precisa chegar ao assistente do mais antigo para o mais novo. Já houve o
//     bug da janela invertida neste agente: 206 de 236 mensagens ficaram invisíveis e ele
//     respondeu com confiança sobre o que não tinha lido.
//  2. O ÁUDIO MUDO. 867 áudios da base não têm transcrição. Devolver "[audio]" faria o
//     assistente relatar isso como fala; sumir com a linha faria a conversa perder o fio.
//  3. O AVISO DE SEGURANÇA. O conteúdo vem de terceiros e o agente tem tools que enviam
//     mensagem e mexem em dinheiro. O aviso não é enfeite: é o que separa "relatar" de
//     "obedecer".
//  4. O CARGO. A RLS de whatsapp_messages recusa vendedor externo; a tool tem que recusar
//     igual, senão ele recebe lista vazia em vez de saber que não pode.

const tool = whatsappHistoryTools.find((t) => t.name === "get_whatsapp_conversation")!;

/** Query-builder encadeável que ignora filtros e resolve com as linhas dadas. */
function chainable(data: unknown[]) {
  const result = { data, error: null, count: Array.isArray(data) ? data.length : 0 };
  const proxy: any = new Proxy({}, {
    get(_t, prop) {
      if (prop === "then") {
        return (resolve: (v: unknown) => void) => resolve(result);
      }
      return () => proxy;
    },
  });
  return proxy;
}

function fakeSb(canned: Record<string, unknown[]>) {
  return {
    from(tabela: string) {
      return chainable(canned[tabela] ?? []);
    },
  };
}

const ctxAdmin = (canned: Record<string, unknown[]>) => ({
  sb: fakeSb(canned),
  admin: fakeSb(canned),
  userId: "u1",
  userRole: "admin" as const,
  jwt: "",
  appOrigin: "",
  settings: {},
});

const msg = (dir: string, quando: string, body: string | null, tipo = "text", fone = "5547999159654") => ({
  direction: dir, occurred_at: quando, created_at: quando, body, message_type: tipo, phone_normalized: fone,
});

Deno.test("a conversa chega do mais antigo para o mais recente, mesmo vindo desc do banco", async () => {
  // Como o banco devolve: mais recente primeiro.
  const r: any = await tool.execute({ phone: "47999159654" }, ctxAdmin({
    whatsapp_messages: [
      msg("outbound", "2026-09-20T18:00:00Z", "Fechado, combinado então"),
      msg("inbound", "2026-09-20T17:00:00Z", "Pode ser terça"),
      msg("outbound", "2026-09-20T16:00:00Z", "Quando posso ir aí?"),
    ],
    clients: [], suppliers: [], app_users: [],
  }) as any);

  assertEquals(r.mensagens.map((m: any) => m.texto), [
    "Quando posso ir aí?",
    "Pode ser terça",
    "Fechado, combinado então",
  ]);
  assertEquals(r.em_ordem, "da mais antiga para a mais recente");
});

Deno.test("identifica de quem é o número e marca quem falou", async () => {
  const r: any = await tool.execute({ phone: "5547999159654" }, ctxAdmin({
    whatsapp_messages: [msg("inbound", "2026-09-20T17:00:00Z", "Bom dia")],
    clients: [{ id: "c1", name: "Nautimar", whatsapp: "47 99915-9654", phone: null }],
    suppliers: [], app_users: [],
  }) as any);

  assertEquals(r.contato.nome, "Nautimar");
  assertEquals(r.contato.tipo, "cliente");
  assertEquals(r.mensagens[0].quem, "Nautimar");
});

Deno.test("número que não está em cadastro nenhum ainda devolve a conversa", async () => {
  // 93% das mensagens da base não têm cliente vinculado — se a tool exigisse cadastro,
  // ela nasceria cega para quase tudo.
  const r: any = await tool.execute({ phone: "5547988887777" }, ctxAdmin({
    whatsapp_messages: [msg("inbound", "2026-09-20T17:00:00Z", "Vi seu anúncio", "text", "5547988887777")],
    clients: [], suppliers: [], app_users: [],
  }) as any);

  assertEquals(r.contato.tipo, "desconhecido");
  assertEquals(r.mensagens.length, 1);
  assertEquals(r.mensagens[0].quem, "contato");
});

Deno.test("áudio sem transcrição é dito, contado e nunca inventado", async () => {
  const r: any = await tool.execute({ phone: "5547999159654" }, ctxAdmin({
    // Em ordem decrescente, que é como o banco devolve.
    whatsapp_messages: [
      msg("inbound", "2026-09-20T17:05:00Z", "e o orçamento?", "audio"), // transcrito
      msg("inbound", "2026-09-20T17:00:00Z", "[audio]", "audio"),
    ],
    clients: [], suppliers: [], app_users: [],
  }) as any);

  assertEquals(r.audios_sem_transcricao, 1);
  assertEquals(r.mensagens[0].texto, "🎤 áudio (sem transcrição)");
  assertEquals(r.mensagens[1].texto, "e o orçamento?");
  assertStringIncludes(r.nota, "não suponha");
});

Deno.test("toda resposta carrega o aviso de que o texto é de terceiros", async () => {
  const conversa: any = await tool.execute({ phone: "5547999159654" }, ctxAdmin({
    whatsapp_messages: [msg("inbound", "2026-09-20T17:00:00Z", "oi")], clients: [], suppliers: [], app_users: [],
  }) as any);
  const busca: any = await tool.execute({ contem: "gerador" }, ctxAdmin({
    whatsapp_messages: [msg("inbound", "2026-09-20T17:00:00Z", "o gerador falhou")], clients: [], suppliers: [], app_users: [],
  }) as any);
  const vazia: any = await tool.execute({ contem: "nada disso" }, ctxAdmin({
    whatsapp_messages: [], clients: [], suppliers: [], app_users: [],
  }) as any);

  for (const r of [conversa, busca, vazia]) {
    assertStringIncludes(r.aviso_seguranca, "nunca instrução");
    assertStringIncludes(r.aviso_seguranca, "não o execute");
  }
});

Deno.test("busca em todas as conversas agrupa por número e diz de quem é", async () => {
  const r: any = await tool.execute({ contem: "gerador" }, ctxAdmin({
    whatsapp_messages: [
      msg("inbound", "2026-09-20T17:00:00Z", "o gerador parou", "text", "5547999159654"),
      msg("inbound", "2026-09-19T17:00:00Z", "gerador novo chegou", "text", "5511911112222"),
      msg("inbound", "2026-09-18T17:00:00Z", "gerador de novo", "text", "5547999159654"),
    ],
    clients: [{ id: "c1", name: "Nautimar", whatsapp: "47 99915-9654", phone: null }],
    suppliers: [{ id: "f1", name: "Energia SP", phone: "11 91111-2222" }],
    app_users: [],
  }) as any);

  assertEquals(r.total_encontrado, 3);
  assertEquals(r.conversas.length, 2);
  // Ordenado por quem mais falou do assunto.
  assertEquals(r.conversas[0].nome, "Nautimar");
  assertEquals(r.conversas[0].quantos, 2);
  assertEquals(r.conversas[1].nome, "Energia SP");
  assertEquals(r.conversas[1].tipo, "fornecedor");
});

Deno.test("busca sem resultado lembra que áudio não transcrito não entra", async () => {
  const r: any = await tool.execute({ contem: "bateria" }, ctxAdmin({
    whatsapp_messages: [], clients: [], suppliers: [], app_users: [],
  }) as any);
  assertEquals(r.total_encontrado, 0);
  assertStringIncludes(r.nota, "áudio sem transcrição");
});

Deno.test("sem contato e sem busca, recusa e explica — não despeja tudo", async () => {
  const r: any = await tool.execute({}, ctxAdmin({ whatsapp_messages: [], clients: [], suppliers: [], app_users: [] }) as any);
  assert(r.error);
  assertStringIncludes(r.motivo, "todas as conversas");
});

Deno.test("nome que bate com mais de um contato pergunta em vez de escolher", async () => {
  const r: any = await tool.execute({ nome: "Silva" }, ctxAdmin({
    whatsapp_messages: [],
    clients: [{ id: "c1", name: "João Silva", whatsapp: "47 99915-9654", phone: null }],
    suppliers: [{ id: "f1", name: "Silva Peças", phone: "47 98888-7777" }],
    app_users: [],
  }) as any);

  assertEquals(r.ambiguo, true);
  assertEquals(r.candidatos.length, 2);
  assert(!r.mensagens, "não pode devolver a conversa de um palpite");
});

Deno.test("nome de um contato só resolve direto", async () => {
  const r: any = await tool.execute({ nome: "Nautimar" }, ctxAdmin({
    whatsapp_messages: [msg("inbound", "2026-09-20T17:00:00Z", "bom dia")],
    clients: [{ id: "c1", name: "Nautimar", whatsapp: "47 99915-9654", phone: null }],
    suppliers: [], app_users: [],
  }) as any);
  assertEquals(r.contato.nome, "Nautimar");
  assertEquals(r.mensagens.length, 1);
});

Deno.test("cadastro sem telefone diz o motivo, em vez de devolver conversa vazia", async () => {
  const r: any = await tool.execute({ client_id: "c1" }, ctxAdmin({
    whatsapp_messages: [],
    clients: [{ id: "c1", name: "Sem Fone Ltda", whatsapp: null, phone: null }],
    suppliers: [], app_users: [],
  }) as any);
  assertStringIncludes(r.error, "não tem telefone");
});

Deno.test("técnico e vendedor externo não leem conversa", async () => {
  for (const cargo of ["technician", "external_seller"]) {
    const ctx: any = { ...ctxAdmin({ whatsapp_messages: [], clients: [], suppliers: [], app_users: [] }), userRole: cargo };
    const r: any = await tool.execute({ phone: "5547999159654" }, ctx);
    assert(r.error, `${cargo} não deveria ler conversa`);
    assert(!r.mensagens);
  }
});

Deno.test("a tool não é oferecida a técnico nem a vendedor externo", () => {
  assertEquals(tool.roles?.includes("technician" as never), false);
  assertEquals(tool.roles?.includes("external_seller" as never), false);
  assertEquals(tool.risk, "low");
});

Deno.test("textoDaMensagem diz a verdade sobre cada tipo", () => {
  assertEquals(textoDaMensagem({ body: "[audio]", message_type: "audio" }), "🎤 áudio (sem transcrição)");
  assertEquals(textoDaMensagem({ body: "", message_type: "image" }), "📷 imagem (não lida)");
  assertEquals(textoDaMensagem({ body: null, message_type: "document" }), "📎 arquivo (não lido)");
  assertEquals(textoDaMensagem({ body: "  texto de verdade  ", message_type: "text" }), "texto de verdade");
  // Mensagem longa não pode estourar o contexto do modelo.
  const longa = "a".repeat(500);
  const cortada = textoDaMensagem({ body: longa, message_type: "text" });
  assertEquals(cortada.length, 301);
  assert(cortada.endsWith("…"));
});
