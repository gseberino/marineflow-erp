// Fakes do assistente (19/11/2026): tools que respondiam "feito" sem ter feito. Cada teste prova que a
// resposta diz a verdade sobre o que ficou gravado. Banco falso em memória, sem rede; dados inventados.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { bancoFalso, ctxDe } from "./banco-falso-fakes_test.ts";
import { anexarNota, BUCKET_DAS_FOTOS_DA_OS, copiarFotoParaAOS, fieldOpsTools } from "./field-ops.ts";
import { contactTools } from "./contacts.ts";
import { autonomiaValeNoPerfil, autonomyTools, perfilDeTools, registrarCatalogoDaAutonomia } from "./autonomy.ts";
import { PERFIL_ADMIN } from "../perfil-operacao.ts";
import { flowMacroTools, resolverCobrancasDoLote } from "./flow-macros.ts";
import { bankingTools } from "./banking.ts";
import { financeRulesTools } from "./finance-rules.ts";
import { serviceOrderTools } from "./service-orders.ts";
import { soOpsTools } from "./so-ops.ts";
import { quoteTools } from "./quotes.ts";
import { commsTools } from "./comms-tools.ts";
import { getConflicts } from "./agenda.ts";
import { whatsappTools } from "./whatsapp.ts";
import { referenceDataTools } from "./reference-data.ts";
import { toquesEnviadosHoje } from "./followups.ts";
import { emailTools } from "./email.ts";
import { learningTools } from "./learning.ts";

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

// ─── 4. link_contact_to_entity ──────────────────────────────────────────────────────────────

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

// Pacote 1 do assistente, S2 (24/11/2026): oito ações deixaram de ser liberáveis (autonomy-policy.ts). A porta de
// entrada recusa ANTES de gravar e diz o critério inteiro: a recusa antiga falava só de "dinheiro ou destrutiva".
const OS_OITO_DE_24_11 = [
  "emit_fiscal_note", "emit_fiscal_service_note", "conciliar_transacao", "cancelar_lancamento",
  "send_supplier_quote_request", "alterar_favorecido", "send_whatsapp_message", "set_tool_autonomy",
];

Deno.test("fakes 5g. set_tool_autonomy recusa liberar o que nunca roda sozinho, com o motivo, e nada é gravado", async () => {
  const { allTools } = await import("./index.ts");
  registrarCatalogoDaAutonomia(allTools);
  for (const nome of OS_OITO_DE_24_11) {
    const b = bancoFalso({ app_settings: [] });
    // deno-lint-ignore no-explicit-any
    const r = await setAuto.execute({ action_name: nome, mode: "auto" }, ctxDe(b.db)) as any;
    assertEquals(
      r.error,
      `"${nome}" fica sempre com a sua confirmação: mexe em dinheiro, em nota fiscal, fala com quem é de fora ou não se desfaz. Essa trava é permanente, por segurança.`,
    );
    assertEquals(r.ok, undefined);
    assertEquals(b.gravacoes, [], `${nome}: a chave não pode ser gravada`);
  }
});

Deno.test("fakes 5h. chave 'auto' de ação que entrou no teto: aparece como sem efeito e pode ser revogada", async () => {
  const { allTools } = await import("./index.ts");
  registrarCatalogoDaAutonomia(allTools);
  const b = bancoFalso({ app_settings: [{ key: "ai_autonomy_send_supplier_quote_request", value: "auto" }] });
  // deno-lint-ignore no-explicit-any
  const lista = await getAuto.execute({}, ctxDe(b.db)) as any;
  assertEquals(lista.agindo_sozinho, []);
  assertEquals(lista.liberadas_sem_efeito, ["send_supplier_quote_request"]);
  assertStringIncludes(lista.explicacao, "mexem em dinheiro, em nota fiscal, falam com quem é de fora ou não se desfazem");
  for (const nome of OS_OITO_DE_24_11) assert(lista.nunca_liberaveis.includes(nome), `${nome} fora de nunca_liberaveis`);

  // deno-lint-ignore no-explicit-any
  const r = await setAuto.execute({ action_name: "send_supplier_quote_request", mode: "confirm" }, ctxDe(b.db)) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(b.tabelas.app_settings[0].value, "confirm");
});

// ─── 6. send_bulk_collection_reminders ──────────────────────────────────────────────────────

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

// ─── 7. conciliar_transacao ─────────────────────────────────────────────────────────────────

const LINHA = { id: "tx-1", transaction_date: "2026-11-10", description: "PIX RECEBIDO", amount: 1200, reconciled: false, transaction_type: "credit" };

Deno.test("fakes 7a. conta a receber: vai pela conciliar_lancamento (com p_autor) e não registra pagamento à parte", async () => {
  const b = bancoFalso({ bank_transactions: [{ ...LINHA }] }, {}, {
    conciliar_lancamento: () => ({ data: { ok: true, pagamento_registrado: true, valor_pago: 1000, message: "Conciliado. Pagamento de R$ 1.000,00 registrado." }, error: null }),
  });
  // deno-lint-ignore no-explicit-any
  const r = await ferramenta(bankingTools, "conciliar_transacao").execute({ transaction_id: "tx-1", tipo: "receivable", alvo_id: "rec-1" }, ctxDe(b.db, { userRole: "admin" })) as any;
  assertEquals(r.ok, true);
  assertEquals(r.valor_pago, 1000);
  assertStringIncludes(r.aviso, "200.00 a mais");
  assertEquals(b.chamadas.map(([n]) => n), ["conciliar_lancamento"]);
  assertEquals(b.chamadas[0][1], { p_tipo: "receivable", p_id: "rec-1", p_transacao: "tx-1", p_autor: "dono-1" });
  assertEquals(b.gravacoes, [], "a linha do extrato é marcada pela função, não por um update solto");
});

Deno.test("fakes 7b. a recusa do banco (conta já casada, saída x receber) volta como erro, sem 'ok'", async () => {
  const b = bancoFalso({ bank_transactions: [{ ...LINHA }] }, {}, {
    conciliar_lancamento: () => ({ data: null, error: { message: "Este lançamento já está casado com outra linha do extrato. Desfaça o vínculo antes." } }),
  });
  // deno-lint-ignore no-explicit-any
  const r = await ferramenta(bankingTools, "conciliar_transacao").execute({ transaction_id: "tx-1", tipo: "receivable", alvo_id: "rec-1" }, ctxDe(b.db, { userRole: "admin" })) as any;
  assertEquals(r.ok, undefined);
  assertStringIncludes(r.error, "já está casado");
});

Deno.test("fakes 7c. sinal de orçamento: saída do banco é recusada; marcação da linha que não grava é dita", async () => {
  const saida = bancoFalso({ bank_transactions: [{ ...LINHA, transaction_type: "debit" }] });
  // deno-lint-ignore no-explicit-any
  const r1 = await ferramenta(bankingTools, "conciliar_transacao").execute({ transaction_id: "tx-1", tipo: "quote_deposit", alvo_id: "os-1" }, ctxDe(saida.db, { userRole: "admin" })) as any;
  assertStringIncludes(r1.error, "ENTRADA");
  assertEquals(saida.chamadas, []);

  const semMarca = bancoFalso({ bank_transactions: [{ ...LINHA }] }, { "update:bank_transactions": "RLS" }, {
    register_deposit_and_convert: () => ({ data: { payment_id: "pay-1" }, error: null }),
  });
  // deno-lint-ignore no-explicit-any
  const r2 = await ferramenta(bankingTools, "conciliar_transacao").execute({ transaction_id: "tx-1", tipo: "quote_deposit", alvo_id: "os-1" }, ctxDe(semMarca.db, { userRole: "admin" })) as any;
  assertEquals(r2.ok, false);
  assertStringIncludes(r2.error, "NÃO ficou marcada");
});

// ─── 8. mudar_situacao_da_regra ─────────────────────────────────────────────────────────────

Deno.test("fakes 8. mudar_situacao_da_regra: id errado não responde ok", async () => {
  const b = bancoFalso({ finance_rules: [{ id: "regra-1", status: "active" }] });
  const t = ferramenta(financeRulesTools, "mudar_situacao_da_regra");
  // deno-lint-ignore no-explicit-any
  const errado = await t.execute({ regra_id: "nao-existe", nova_situacao: "pausada" }, ctxDe(b.db)) as any;
  assertStringIncludes(errado.error, "Regra não encontrada");
  // deno-lint-ignore no-explicit-any
  const certo = await t.execute({ regra_id: "regra-1", nova_situacao: "pausada" }, ctxDe(b.db)) as any;
  assertEquals(certo.ok, true);
  assertEquals(b.tabelas.finance_rules[0].status, "paused");
});

// ─── 9. get_service_order traz os ids de despesa e hora ─────────────────────────────────────

const OS_COMPLETA = () => ({
  service_orders: [{ id: "os-1", service_order_number: "OS-00129", status: "in_progress" }],
  service_order_parts: [], service_order_services: [], service_order_steps: [],
  service_order_expenses: [{ id: "desp-1", service_order_id: "os-1", description: "Pedágio", amount: 12.5, expense_date: "2026-11-18", origem_codigo: null }],
  time_entries: [{ id: "hora-1", service_order_id: "os-1", started_at: "2026-11-18T12:00:00Z", duration_minutes: 90, billable: true }],
});

Deno.test("fakes 9a. get_service_order devolve expense_id e time_entry_id; técnico não vê despesa", async () => {
  const t = ferramenta(serviceOrderTools, "get_service_order");
  // deno-lint-ignore no-explicit-any
  const r = await t.execute({ id: "os-1" }, ctxDe(bancoFalso(OS_COMPLETA()).db)) as any;
  assertEquals(r.despesas, [{ expense_id: "desp-1", descricao: "Pedágio", valor: 12.5, data: "2026-11-18" }]);
  assertEquals(r.horas, [{ time_entry_id: "hora-1", inicio: "2026-11-18T12:00:00Z", minutos: 90, cobravel: true }]);
  // deno-lint-ignore no-explicit-any
  const tec = await t.execute({ id: "os-1" }, ctxDe(bancoFalso(OS_COMPLETA()).db, { userRole: "technician" })) as any;
  assertEquals(tec.despesas, undefined);
  assertEquals(tec.horas.length, 1);
  // leitura das horas com erro não derruba a OS: vira aviso
  // deno-lint-ignore no-explicit-any
  const comErro = await t.execute({ id: "os-1" }, ctxDe(bancoFalso(OS_COMPLETA(), { "select:time_entries": "timeout" }).db)) as any;
  assertEquals(comErro.service_order.service_order_number, "OS-00129");
  assertStringIncludes(comErro.aviso, "apontamentos de hora");
});

Deno.test("fakes 9b. remove_service_order_hours: delete que não apaga linha (permissão) não diz que removeu", async () => {
  const banco = bancoFalso(OS_COMPLETA());
  const de = banco.db.from;
  // A linha some entre a leitura e o delete: é o que a RLS faz (lê, mas não apaga).
  // deno-lint-ignore no-explicit-any
  (banco.db as any).from = (tabela: string) => {
    const q = de(tabela);
    if (tabela !== "time_entries") return q;
    const apagarOriginal = q.delete;
    q.delete = () => { banco.tabelas.time_entries = []; return apagarOriginal(); };
    return q;
  };
  // deno-lint-ignore no-explicit-any
  const r = await ferramenta(soOpsTools, "remove_service_order_hours").execute({ time_entry_id: "hora-1" }, ctxDe(banco.db)) as any;
  assertStringIncludes(r.error, "NÃO foi removido");
});

// ─── 10. apply_quote_price ──────────────────────────────────────────────────────────────────

const COTACAO = () => ({
  quote_responses: [{ id: "resp-1", quote_request_id: "qr-1", supplier_id: "sup-1", quote_request_item_id: "qi-1", unit_price: 100, confirmed: false }],
  quote_request_items: [{ id: "qi-1", description: "Bomba de porão", service_order_part_id: "part-1", service_order_service_id: null }],
  quote_requests: [{ id: "qr-1", code: "COT-00007", service_order_id: "os-1" }],
  service_orders: [{ id: "os-1", status: "draft", grand_total: 300 }],
  service_order_parts: [{ id: "part-1", service_order_id: "os-1", quantity: 2, unit_cost_snapshot: 80, unit_sale_snapshot: 150, line_total_cost: 160 }],
  suppliers: [{ id: "sup-1", name: "Fornecedor Teste" }],
  receivables: [],
});

Deno.test("fakes 10. apply_quote_price: recálculo e marca da escolhida com erro viram avisos, total null", async () => {
  const b = bancoFalso(COTACAO(), { "update:quote_responses": "RLS" }, { recalc_so_totals: () => ({ data: null, error: { message: "deadlock" } }) });
  // deno-lint-ignore no-explicit-any
  const r = await ferramenta(quoteTools, "apply_quote_price").execute({ response_id: "resp-1" }, ctxDe(b.db)) as any;
  assertEquals(r.ok, true);
  assertEquals(r.total_orcamento, null);
  assertEquals(r.margem_bruta_pct, null);
  assert(r.avisos.some((a: string) => a.includes("NÃO ficou marcada")));
  assert(r.avisos.some((a: string) => a.includes("NÃO foi recalculado")));
  assertEquals(b.tabelas.service_order_parts[0].unit_cost_snapshot, 100, "o preço foi aplicado de verdade");

  const ok = bancoFalso(COTACAO());
  // deno-lint-ignore no-explicit-any
  const r2 = await ferramenta(quoteTools, "apply_quote_price").execute({ response_id: "resp-1" }, ctxDe(ok.db)) as any;
  assertEquals(r2.avisos, undefined);
  assertEquals(r2.total_orcamento, 300);
  assertEquals(ok.tabelas.quote_responses[0].confirmed, true);
});

// ─── 11. check_followup_cadence / get_comms_metrics ─────────────────────────────────────────

Deno.test("fakes 11. check_followup_cadence: erro de leitura BLOQUEIA; get_comms_metrics pagina além de 1000", async () => {
  const b = bancoFalso({ ai_comms_log: [] }, { "select:ai_comms_log": "timeout" });
  // deno-lint-ignore no-explicit-any
  const r = await ferramenta(commsTools, "check_followup_cadence").execute({ entity_id: "c-1", tipo: "cobranca" }, ctxDe(b.db)) as any;
  assertEquals(r.pode_tocar_agora, false);
  assertStringIncludes(r.error, "NÃO mande");
  const muitas = Array.from({ length: 1500 }, (_, i) => ({ id: `l${i}`, created_at: "2026-11-18T10:00:00Z", tipo: "cobranca", status: "sent", responded_at: null }));
  // deno-lint-ignore no-explicit-any
  const m = await ferramenta(commsTools, "get_comms_metrics").execute({ days: 3650 }, ctxDe(bancoFalso({ ai_comms_log: muitas }).db)) as any;
  assertEquals(m.enviados, 1500);
});

// ─── 12. getConflicts ───────────────────────────────────────────────────────────────────────

Deno.test("fakes 12. getConflicts: erro da RPC lança (não vira 'sem conflito')", async () => {
  const b = bancoFalso({}, {}, { get_agenda_conflicts: () => ({ data: null, error: { message: "timeout" } }) });
  let erro = "";
  try {
    await getConflicts(b.db, "u-1", "2026-11-20T12:00:00Z", "2026-11-20T13:00:00Z");
  } catch (e) {
    erro = (e as Error).message;
  }
  assertStringIncludes(erro, "nada foi gravado");
});

// ─── 13. cancel_scheduled_whatsapp ──────────────────────────────────────────────────────────

Deno.test("fakes 13. cancel_scheduled_whatsapp: id errado e envio já feito não respondem ok; pendente cancela", async () => {
  const b = bancoFalso({ whatsapp_scheduled_sends: [{ id: "ag-1", status: "sent" }, { id: "ag-2", status: "pending" }] });
  const t = ferramenta(whatsappTools, "cancel_scheduled_whatsapp");
  // deno-lint-ignore no-explicit-any
  const errado = await t.execute({ scheduled_id: "zzz" }, ctxDe(b.db)) as any;
  assertStringIncludes(errado.error, "não encontrado");
  // deno-lint-ignore no-explicit-any
  const enviado = await t.execute({ scheduled_id: "ag-1" }, ctxDe(b.db)) as any;
  assertStringIncludes(enviado.error, "já foi ENVIADO");
  assertEquals(b.tabelas.whatsapp_scheduled_sends[0].status, "sent");
  // deno-lint-ignore no-explicit-any
  const pendente = await t.execute({ scheduled_id: "ag-2" }, ctxDe(b.db)) as any;
  assertEquals(pendente.ok, true);
  assertEquals(b.tabelas.whatsapp_scheduled_sends[1].status, "cancelled");
});

// ─── 14. leituras sem error ─────────────────────────────────────────────────────────────────

Deno.test("fakes 14a. list_reference_data: lista não lida não vira lista vazia", async () => {
  const b = bancoFalso({ financial_categories: [], cost_centers: [{ id: "cc-1", name: "Oficina", type: "x", active: true }] }, { "select:financial_categories": "timeout" });
  // deno-lint-ignore no-explicit-any
  const r = await ferramenta(referenceDataTools, "list_reference_data").execute({ which: ["financial_categories", "cost_centers"] }, ctxDe(b.db)) as any;
  assertEquals(r.categorias_financeiras, undefined);
  assertEquals(r.centros_de_custo.length, 1);
  assertStringIncludes(r.nao_consegui_ler[0], "categorias financeiras");
});

Deno.test("fakes 14b. followup: contagem do teto com erro fecha (não vira 0)", async () => {
  const b = bancoFalso({ ai_followup_events: [] }, { "select:ai_followup_events": "timeout" });
  let erro = "";
  try { await toquesEnviadosHoje(b.db); } catch (e) { erro = (e as Error).message; }
  assertStringIncludes(erro, "nada foi enviado");
});

Deno.test("fakes 14c. listar_emails: caixa que não existe não lista todas as caixas", async () => {
  const b = bancoFalso({ email_accounts: [], email_messages: [{ id: "e-1" }] });
  // deno-lint-ignore no-explicit-any
  const r = await ferramenta(emailTools, "listar_emails").execute({ caixa: "gustavo" }, ctxDe(b.db)) as any;
  assertStringIncludes(r.error, "Não existe caixa");
});

Deno.test("fakes 14d. link_contact_identity: cadastro com outro número não é trocado e a resposta diz isso", async () => {
  const b = bancoFalso({
    clients: [{ id: "c-1", name: "Maria Teste", whatsapp: "5511900001111" }],
    whatsapp_messages: [{ id: "w1", phone_normalized: "5511987654321", client_id: null }],
    agenda_suggestions: [],
  });
  // deno-lint-ignore no-explicit-any
  const r = await ferramenta(learningTools, "link_contact_identity").execute({ phone: "5511987654321", entity_type: "client", entity_id: "c-1" }, ctxDe(b.db)) as any;
  assertEquals(r.ok, true);
  assertEquals(r.mensagens_vinculadas, 1);
  assertStringIncludes(r.numero_no_cadastro, "NÃO foi trocado");
  assertEquals(b.tabelas.clients[0].whatsapp, "5511900001111");
});
