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
