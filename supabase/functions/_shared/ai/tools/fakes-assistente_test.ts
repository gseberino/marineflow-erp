// Fakes do assistente (19/11/2026): tools que respondiam "feito" sem ter feito. Cada teste prova que a
// resposta diz a verdade sobre o que ficou gravado. Banco falso em memória, sem rede; dados inventados.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { bancoFalso, ctxDe, type Linha } from "./banco-falso-fakes_test.ts";
import { anexarNota, BUCKET_DAS_FOTOS_DA_OS, copiarFotoParaAOS, fieldOpsTools } from "./field-ops.ts";

// deno-lint-ignore no-explicit-any
const ferramenta = (lista: any[], nome: string) => lista.find((t) => t.name === nome)!;

const OS = { id: "os-1", service_order_number: "OS-00129", status: "in_progress", technician_notes: "linha antiga" };
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 5]);
const PDF = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d, 1, 2, 3]);

// ─── 3. anexarNota ──────────────────────────────────────────────────────────────────────────

Deno.test("fakes 3a. anexarNota: leitura com erro NÃO sobrescreve as notas", async () => {
  const b = bancoFalso({ service_orders: [{ ...OS }] }, { "select:service_orders": "timeout" });
  const r = await anexarNota(b.db, "os-1", "nova");
  assert("error" in r);
  assertStringIncludes(r.error, "NÃO foi gravada");
  assertEquals(b.tabelas.service_orders[0].technician_notes, "linha antiga");
  assertEquals(b.gravacoes, []);
});

Deno.test("fakes 3b. anexarNota: preserva o que havia; OS sumida vira erro; teto não corta a linha nova calado", async () => {
  const b = bancoFalso({ service_orders: [{ ...OS }] });
  assertEquals(await anexarNota(b.db, "os-1", "nova"), { ok: true });
  assertEquals(b.tabelas.service_orders[0].technician_notes, "linha antiga\nnova");

  assert("error" in await anexarNota(b.db, "sumiu", "x"));

  const cheio = bancoFalso({ service_orders: [{ ...OS, technician_notes: "a".repeat(7999) }] });
  const r = await anexarNota(cheio.db, "os-1", "linha nova");
  assert("error" in r && r.error.includes("limite"));
  assertEquals(cheio.gravacoes, []);
});

Deno.test("fakes 3c. log_service_order_progress devolve erro quando a nota não gravou", async () => {
  const b = bancoFalso({ service_orders: [{ ...OS }] }, { "update:service_orders": "sem permissão" });
  // deno-lint-ignore no-explicit-any
  const r = await ferramenta(fieldOpsTools, "log_service_order_progress").execute({ service_order_id: "os-1", note: "troquei" }, ctxDe(b.db)) as any;
  assertEquals(r.ok, undefined);
  assertStringIncludes(r.error, "NÃO foi gravada");
});

// ─── 2. attach_photo_to_service_order ───────────────────────────────────────────────────────

const MSG = { id: "m-1", message_type: "image", service_order_id: null, raw_payload: { data: { key: { id: "WA1", remoteJid: "5511@s.whatsapp.net" } } } };

Deno.test("fakes 2a. copiarFotoParaAOS: foto vai para o bucket da aba Fotos e para service_order_photos", async () => {
  const b = bancoFalso({ service_order_photos: [] });
  const r = await copiarFotoParaAOS(ctxDe(b.db), MSG, "os-1", {
    photoType: "before", legenda: "antes da troca",
    baixar: () => Promise.resolve({ ok: true, bytes: JPEG, mimeDeclarado: "image/jpeg" }),
  });
  assert(r.ok);
  assert(r.storage_path.startsWith("os-1/") && r.storage_path.endsWith(".jpg"));
  assertEquals(b.armazem[BUCKET_DAS_FOTOS_DA_OS].has(r.storage_path), true);
  const [foto] = b.tabelas.service_order_photos;
  assertEquals([foto.service_order_id, foto.photo_type, foto.caption, foto.uploaded_by], ["os-1", "before", "antes da troca", "dono-1"]);
});

Deno.test("fakes 2b. copiarFotoParaAOS: PDF, vídeo, mídia expirada e registro recusado dizem que NÃO entrou", async () => {
  const b = bancoFalso({ service_order_photos: [] });
  const pdf = await copiarFotoParaAOS(ctxDe(b.db), MSG, "os-1", { photoType: "progress", baixar: () => Promise.resolve({ ok: true, bytes: PDF, mimeDeclarado: null }) });
  assert(!pdf.ok && pdf.motivo.includes("não é uma foto"));
  const video = await copiarFotoParaAOS(ctxDe(b.db), { ...MSG, message_type: "video" }, "os-1", { photoType: "progress" });
  assert(!video.ok && video.motivo.includes("video"));
  const expirou = await copiarFotoParaAOS(ctxDe(b.db), MSG, "os-1", { photoType: "progress", baixar: () => Promise.resolve({ ok: false, erro: "midia_indisponivel" }) });
  assert(!expirou.ok && expirou.motivo.includes("expira"));
  assertEquals(b.tabelas.service_order_photos, []);

  const recusa = bancoFalso({ service_order_photos: [] }, { "insert:service_order_photos": "RLS" });
  const r = await copiarFotoParaAOS(ctxDe(recusa.db), MSG, "os-1", { photoType: "progress", baixar: () => Promise.resolve({ ok: true, bytes: JPEG, mimeDeclarado: null }) });
  assert(!r.ok && r.motivo.includes("RLS"));
  assertEquals(recusa.armazem[BUCKET_DAS_FOTOS_DA_OS].size, 0, "o arquivo subido é apagado quando o registro falha");
});

Deno.test("fakes 2c. attach_photo_to_service_order: sem download possível responde ok:false e diz que ficou só no histórico", async () => {
  const antes = Deno.env.get("EVOLUTION_API_URL");
  Deno.env.delete("EVOLUTION_API_URL");
  try {
    const b = bancoFalso({ whatsapp_messages: [{ ...MSG }], service_orders: [{ ...OS }], service_order_photos: [] });
    // deno-lint-ignore no-explicit-any
    const r = await ferramenta(fieldOpsTools, "attach_photo_to_service_order").execute({ message_id: "m-1", service_order_id: "os-1", note: "antes" }, ctxDe(b.db)) as any;
    assertEquals(r.ok, false);
    assertStringIncludes(r.error, "NÃO entrou na aba Fotos da OS-00129");
    assertStringIncludes(r.error, "histórico do WhatsApp");
    assertEquals(r.ligada_no_historico_do_whatsapp, true);
    assertEquals(b.tabelas.whatsapp_messages[0].service_order_id, "os-1");
    assertEquals(b.tabelas.service_orders[0].technician_notes, "linha antiga", "sem foto, nada de 'Foto anexada' nas notas");
  } finally {
    if (antes) Deno.env.set("EVOLUTION_API_URL", antes);
  }
});

Deno.test("fakes 2d. attach_photo_to_service_order: a descrição não promete mais 'anexado ao serviço' sem copiar", () => {
  const t = ferramenta(fieldOpsTools, "attach_photo_to_service_order");
  assertStringIncludes(t.description, "aba FOTOS");
  assert(!t.description.includes("Não copia o arquivo"));
  // deno-lint-ignore no-explicit-any
  assertEquals((t.input_schema.properties as any).photo_type.enum, ["before", "progress", "after", "problem"]);
});

// mantém Linha em uso para o lint de import
export type _L = Linha;

// ─── 4. link_contact_to_entity ──────────────────────────────────────────────────────────────
import { contactTools } from "./contacts.ts";

const MSGS_DO_NUMERO = () => [
  { id: "w1", phone_normalized: "5511987654321", client_id: null },
  { id: "w2", phone_normalized: "5511987654321", client_id: null },
  { id: "w3", phone_normalized: "5521911112222", client_id: null },
];

Deno.test("fakes 4a. cadastro sem número: liga as antigas E grava o número (as próximas chegam ligadas)", async () => {
  const b = bancoFalso({ whatsapp_messages: MSGS_DO_NUMERO(), clients: [{ id: "c-1", name: "Maria Teste", phone: null, whatsapp: "", active: true }], suppliers: [], app_users: [] });
  // deno-lint-ignore no-explicit-any
  const r = await ferramenta(contactTools, "link_contact_to_entity").execute({ phone: "(11) 98765-4321", client_id: "c-1" }, ctxDe(b.db)) as any;
  assertEquals(r.ok, true);
  assertEquals(r.mensagens_atualizadas, 2);
  assertEquals(b.tabelas.clients[0].whatsapp, "5511987654321");
  assertStringIncludes(r.proximas_mensagens, "chegam ligadas");
});

Deno.test("fakes 4b. cadastro com OUTRO número: não troca e diz a verdade sobre as próximas", async () => {
  const b = bancoFalso({ whatsapp_messages: MSGS_DO_NUMERO(), clients: [{ id: "c-1", name: "Maria Teste", phone: "5511900001111", whatsapp: null, active: true }], suppliers: [], app_users: [] });
  // deno-lint-ignore no-explicit-any
  const r = await ferramenta(contactTools, "link_contact_to_entity").execute({ phone: "11987654321", client_id: "c-1" }, ctxDe(b.db)) as any;
  assertEquals(r.ok, true);
  assertEquals(r.numero_no_cadastro, "nao_trocado");
  assertEquals(b.tabelas.clients[0].phone, "5511900001111");
  assertEquals(b.tabelas.clients[0].whatsapp, null);
  assertStringIncludes(r.proximas_mensagens, "Pergunte ao usuário se quer trocar");
  assert(!JSON.stringify(r).includes("Vale para as próximas"));
});

Deno.test("fakes 4c. número já no cadastro: nada é gravado no cadastro; outro cliente com o número: não grava e avisa", async () => {
  const ja = bancoFalso({ whatsapp_messages: MSGS_DO_NUMERO(), clients: [{ id: "c-1", name: "Maria Teste", phone: null, whatsapp: "11 98765-4321", active: true }], suppliers: [], app_users: [] });
  // deno-lint-ignore no-explicit-any
  const r = await ferramenta(contactTools, "link_contact_to_entity").execute({ phone: "5511987654321", client_id: "c-1" }, ctxDe(ja.db)) as any;
  assertEquals(r.numero_no_cadastro, "ja_estava");
  assertEquals(ja.gravacoes.filter((g) => g.tabela === "clients"), []);

  const dois = bancoFalso({
    whatsapp_messages: MSGS_DO_NUMERO(),
    clients: [{ id: "c-1", name: "Maria Teste", phone: null, whatsapp: null, active: true }, { id: "c-2", name: "José Outro", phone: "11987654321", whatsapp: null, active: true }],
    suppliers: [], app_users: [],
  });
  // deno-lint-ignore no-explicit-any
  const r2 = await ferramenta(contactTools, "link_contact_to_entity").execute({ phone: "5511987654321", client_id: "c-1" }, ctxDe(dois.db)) as any;
  assertEquals(r2.numero_no_cadastro, "nao_gravado");
  assertStringIncludes(r2.proximas_mensagens, "José Outro");
  assertEquals(dois.tabelas.clients[0].whatsapp, null);
});

Deno.test("fakes 4d. identify_contact: leitura com erro não vira 'número desconhecido'", async () => {
  const b = bancoFalso({ clients: [], suppliers: [], app_users: [], whatsapp_messages: [] }, { "select:clients": "timeout" });
  let erro = "";
  try {
    await ferramenta(contactTools, "identify_contact").execute({ phone: "5511987654321" }, ctxDe(b.db));
  } catch (e) {
    erro = (e as Error).message;
  }
  assertStringIncludes(erro, "Não consegui ler os clientes");
});

// ─── 5. set_tool_autonomy ───────────────────────────────────────────────────────────────────
import { autonomiaValeNoPerfil, autonomyTools, perfilDeTools, registrarCatalogoDaAutonomia } from "./autonomy.ts";
import { PERFIL_ADMIN } from "../perfil-operacao.ts";

const FALSA = (name: string, risk: "low" | "medium" | "high") => ({ name, risk, description: "", input_schema: {}, execute: () => Promise.resolve({}) });
// deno-lint-ignore no-explicit-any
const catalogoDeTeste = () => registrarCatalogoDaAutonomia([FALSA("duplicate_service_order", "medium"), FALSA("adjust_inventory", "medium"), FALSA("search_clients", "low")] as any);
const setAuto = ferramenta(autonomyTools, "set_tool_autonomy");
const getAuto = ferramenta(autonomyTools, "get_autonomy_settings");

Deno.test("fakes 5a. nome inexistente: recusa e nada é gravado", async () => {
  catalogoDeTeste();
  const b = bancoFalso({ app_settings: [{ key: "ai_tool_profile", value: "admin_enxuto" }] });
  // deno-lint-ignore no-explicit-any
  const r = await setAuto.execute({ action_name: "enviar_tudo_sozinho", mode: "auto" }, ctxDe(b.db)) as any;
  assertStringIncludes(r.error, "Não existe ação");
  assertEquals(b.gravacoes, []);
});

Deno.test("fakes 5b. admin_enxuto: fora do PERFIL_ADMIN recusa com a explicação; dentro grava", async () => {
  catalogoDeTeste();
  assert(!PERFIL_ADMIN.has("adjust_inventory"));
  const b = bancoFalso({ app_settings: [{ key: "ai_tool_profile", value: "admin_enxuto" }] });
  // deno-lint-ignore no-explicit-any
  const fora = await setAuto.execute({ action_name: "adjust_inventory", mode: "auto" }, ctxDe(b.db)) as any;
  assertEquals(fora.fora_do_perfil, true);
  assertStringIncludes(fora.error, "não teria efeito");
  assertEquals(b.gravacoes, []);

  // deno-lint-ignore no-explicit-any
  const dentro = await setAuto.execute({ action_name: "duplicate_service_order", mode: "auto" }, ctxDe(b.db)) as any;
  assertEquals(dentro.ok, true);
  assertEquals(b.tabelas.app_settings.find((l) => l.key === "ai_autonomy_duplicate_service_order")?.value, "auto");
});

Deno.test("fakes 5c. revogar chave antiga de ferramenta que sumiu é aceito; risco baixo não grava", async () => {
  catalogoDeTeste();
  const b = bancoFalso({ app_settings: [{ key: "ai_tool_profile", value: "admin_enxuto" }, { key: "ai_autonomy_tool_antiga", value: "auto" }] });
  // deno-lint-ignore no-explicit-any
  const r = await setAuto.execute({ action_name: "tool_antiga", mode: "confirm" }, ctxDe(b.db)) as any;
  assertEquals(r.ok, true);
  assertEquals(b.tabelas.app_settings[1].value, "confirm");
  // deno-lint-ignore no-explicit-any
  const baixo = await setAuto.execute({ action_name: "search_clients", mode: "auto" }, ctxDe(bancoFalso({ app_settings: [] }).db)) as any;
  assertEquals(baixo.alterado, false);
});

Deno.test("fakes 5d. get_autonomy_settings separa o 'auto' sem efeito", async () => {
  catalogoDeTeste();
  const b = bancoFalso({
    app_settings: [
      { key: "ai_tool_profile", value: "admin_enxuto" },
      { key: "ai_autonomy_duplicate_service_order", value: "auto" },
      { key: "ai_autonomy_adjust_inventory", value: "auto" },
    ],
  });
  // deno-lint-ignore no-explicit-any
  const r = await getAuto.execute({}, ctxDe(b.db)) as any;
  assertEquals(r.agindo_sozinho, ["duplicate_service_order"]);
  assertEquals(r.liberadas_sem_efeito, ["adjust_inventory"]);
});

Deno.test("fakes 5e. perfis: o mesmo filtro do agent.ts para o admin", () => {
  assertEquals(perfilDeTools("admin_enxuto"), "admin_enxuto");
  assertEquals(perfilDeTools(null), "todas");
  assertEquals(autonomiaValeNoPerfil({ name: "qualquer", risk: "medium" }, "todas"), true);
  assertEquals(autonomiaValeNoPerfil({ name: "adjust_inventory", risk: "high" }, "operacao"), true);
  assertEquals(autonomiaValeNoPerfil({ name: "adjust_inventory", risk: "medium" }, "operacao"), false);
});

Deno.test("fakes 5f. tools/index.ts registra o catálogo real (set_tool_autonomy reconhece as tools de verdade)", async () => {
  const { allTools } = await import("./index.ts");
  registrarCatalogoDaAutonomia(allTools);
  const b = bancoFalso({ app_settings: [{ key: "ai_tool_profile", value: "admin_enxuto" }] });
  // deno-lint-ignore no-explicit-any
  const r = await setAuto.execute({ action_name: "duplicate_service_order", mode: "auto" }, ctxDe(b.db)) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
});

// ─── 6. send_bulk_collection_reminders ──────────────────────────────────────────────────────
import { flowMacroTools, resolverCobrancasDoLote } from "./flow-macros.ts";

const COBRANCAS = () => [
  { id: "col-1", receivable_id: "rec-1", status: "pending", amount: 500, due_date: "2026-11-01", contact_name: "Ana", contact_whatsapp: null, phone: null, client_id: null, created_at: "2026-11-01" },
  { id: "col-2", receivable_id: "rec-2", status: "paid", amount: 300, due_date: "2026-11-01", contact_name: "Bia", contact_whatsapp: "5511999990000", client_id: null, created_at: "2026-11-01" },
];

Deno.test("fakes 6a. o lote aceita receivable_id (de get_delinquency_plan) e acha a cobrança aberta da conta", async () => {
  const b = bancoFalso({ collections: COBRANCAS(), receivables: [{ id: "rec-1" }, { id: "rec-2" }, { id: "rec-3" }] });
  const lote = await resolverCobrancasDoLote(b.db, ["rec-1", "col-1", "rec-2", "rec-3", "nada"]);
  assertEquals(lote.map((i) => [i.pedido, i.cobranca?.id ?? null, i.motivo ?? null]), [
    ["rec-1", "col-1", null],
    ["col-1", null, "mesma cobrança repetida no lote"],
    // rec-2 só tem cobrança paga: não é cobrança aberta
    ["rec-2", null, "conta a receber sem cobrança aberta (crie com criar_cobranca antes de mandar o lembrete)"],
    ["rec-3", null, "conta a receber sem cobrança aberta (crie com criar_cobranca antes de mandar o lembrete)"],
    ["nada", null, "cobrança não encontrada"],
  ]);
});

Deno.test("fakes 6b. nenhum envio: ok:false com o motivo (antes: ok:true com 0 enviados)", async () => {
  const b = bancoFalso({ collections: COBRANCAS(), receivables: [], clients: [] });
  // deno-lint-ignore no-explicit-any
  const r = await ferramenta(flowMacroTools, "send_bulk_collection_reminders").execute({ collection_ids: ["rec-1", "zzz"] }, ctxDe(b.db)) as any;
  assertEquals(r.ok, false);
  assertStringIncludes(r.error, "Nenhum lembrete foi enviado");
  assertStringIncludes(r.error, "sem telefone");
  assertStringIncludes(r.error, "cobrança não encontrada");
});

Deno.test("fakes 6c. leitura das cobranças com erro não vira 'não encontrada'", async () => {
  const b = bancoFalso({ collections: COBRANCAS() }, { "select:collections": "timeout" });
  let erro = "";
  try { await resolverCobrancasDoLote(b.db, ["col-1"]); } catch (e) { erro = (e as Error).message; }
  assertStringIncludes(erro, "Não consegui ler as cobranças");
});
