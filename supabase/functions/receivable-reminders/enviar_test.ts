// Run: deno test supabase/functions/receivable-reminders/enviar_test.ts
//
// O lembrete de cobrança marcava "enviado" mesmo quando o WhatsApp recusava (o provedor devolve
// { ok: false } em vez de lançar). O que se protege aqui: só marca com confirmação do provedor, e
// a falha libera a chave para a próxima rodada tentar de novo.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { enviarLembrete } from "./enviar.ts";
import type { SendResult } from "../_shared/whatsapp/types.ts";

function bancoFalso() {
  const marcados: string[] = [];
  const liberadas: string[] = [];
  const concluidas: string[] = [];
  return {
    marcados, liberadas, concluidas,
    from(tabela: string) {
      return {
        update: (v: Record<string, unknown>) => ({
          eq: (_c: string, id: string) => {
            if (tabela === "receivables" && v.reminder_sent_at) marcados.push(id);
            if (tabela === "whatsapp_send_idempotencia" && v.concluido_em) concluidas.push(id);
            return Promise.resolve({ error: null });
          },
        }),
        delete: () => ({
          eq: (_c: string, chave: string) => { liberadas.push(chave); return Promise.resolve({ error: null }); },
          lt: () => Promise.resolve({ error: null }),
        }),
      };
    },
  };
}

const provedor = (r: SendResult | Error) => ({
  sendText: () => (r instanceof Error ? Promise.reject(r) : Promise.resolve(r)),
});

const base = { chave: "lembrete-recebivel:r1:2026-10-02", phone: "5547999990000", message: "Olá", recebivelId: "r1" };

Deno.test("WhatsApp recusou (ok: false): não marca enviado e libera a chave", async () => {
  const db = bancoFalso();
  const r = await enviarLembrete({ ...base, admin: db, provider: provedor({ ok: false, error: "number not on WhatsApp", retryable: false }) });
  assertEquals(r, { ok: false, erro: "number not on WhatsApp" });
  assertEquals(db.marcados, []);
  assertEquals(db.liberadas, [base.chave]);
});

Deno.test("provedor lançou exceção (rede): não marca enviado e libera a chave", async () => {
  const db = bancoFalso();
  const r = await enviarLembrete({ ...base, admin: db, provider: provedor(new Error("timeout")) });
  assertEquals(r.ok, false);
  assertEquals(db.marcados, []);
  assertEquals(db.liberadas, [base.chave]);
});

Deno.test("WhatsApp confirmou: marca o recebível e conclui a reserva", async () => {
  const db = bancoFalso();
  const r = await enviarLembrete({ ...base, admin: db, provider: provedor({ ok: true, providerMessageId: "ABC" }) });
  assertEquals(r, { ok: true });
  assertEquals(db.marcados, ["r1"]);
  assertEquals(db.concluidas, [base.chave]);
  assertEquals(db.liberadas, []);
});
