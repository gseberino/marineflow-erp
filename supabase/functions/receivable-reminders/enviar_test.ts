// Run: deno test supabase/functions/receivable-reminders/enviar_test.ts
//
// O lembrete de cobrança marcava "enviado" mesmo quando o WhatsApp recusava (o provedor devolve
// { ok: false } em vez de lançar). O que se protege aqui: só marca com confirmação do envio.
// Retorno F0a-1 (05/11/2026): o envio passa pelo whatsapp-send (origem "sistema"), que recusa
// opt-out e "Cliente Final"; recusa e erro não marcam; e o dia útil cobre os dias pulados.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  descricaoDaCobranca,
  diasEntre,
  enviarLembrete,
  type RespostaDoEnvio,
  somarDias,
  textoDoPrazo,
  vencimentosDoDia,
} from "./enviar.ts";

function bancoFalso() {
  const marcados: string[] = [];
  return {
    marcados,
    from(tabela: string) {
      return {
        update: (v: Record<string, unknown>) => ({
          eq: (_c: string, id: string) => {
            if (tabela === "receivables" && v.reminder_sent_at) marcados.push(id);
            return Promise.resolve({ error: null });
          },
        }),
      };
    },
  };
}

function envioFalso(r: RespostaDoEnvio | Error) {
  const pedidos: Array<Record<string, unknown>> = [];
  return {
    pedidos,
    chamarEnvio: (corpo: Record<string, unknown>) => {
      pedidos.push(corpo);
      return r instanceof Error ? Promise.reject(r) : Promise.resolve(r);
    },
  };
}

const base = { chave: "lembrete-recebivel:r1:2026-10-02", phone: "5547999990000", message: "Olá", recebivelId: "r1", ordemId: "os1" };

Deno.test("pede ao whatsapp-send como envio automático, com a chave e o recebível", async () => {
  const db = bancoFalso();
  const envio = envioFalso({ status: 200, corpo: { success: true } });
  await enviarLembrete({ ...base, admin: db, chamarEnvio: envio.chamarEnvio });
  assertEquals(envio.pedidos, [{
    phone: base.phone, kind: "text", message: "Olá", receivable_id: "r1", service_order_id: "os1",
    context: "receivable_reminder", dedupe_key: base.chave, origem: "sistema",
  }]);
});

Deno.test("enviado: marca o recebível", async () => {
  const db = bancoFalso();
  const r = await enviarLembrete({ ...base, admin: db, chamarEnvio: envioFalso({ status: 200, corpo: { success: true } }).chamarEnvio });
  assertEquals(r, { situacao: "enviado" });
  assertEquals(db.marcados, ["r1"]);
});

Deno.test("a mesma chave já tinha saído: marca, sem contar como novo envio", async () => {
  const db = bancoFalso();
  const r = await enviarLembrete({
    ...base, admin: db, chamarEnvio: envioFalso({ status: 200, corpo: { success: true, deduplicated: true } }).chamarEnvio,
  });
  assertEquals(r, { situacao: "ja_enviado" });
  assertEquals(db.marcados, ["r1"]);
});

Deno.test("recusado (opt-out, Cliente Final, horário): não marca", async () => {
  const db = bancoFalso();
  const r = await enviarLembrete({
    ...base, admin: db,
    chamarEnvio: envioFalso({ status: 422, corpo: { error: "Envio automático recusado: o contato pediu…", recusado: true, codigo: "opt_out" } }).chamarEnvio,
  });
  assert(r.situacao === "recusado" && r.motivo.startsWith("Envio automático recusado"));
  assertEquals(db.marcados, []);
});

Deno.test("WhatsApp recusou, falha incerta, em andamento ou rede caída: erro, não marca", async () => {
  for (const resposta of [
    { status: 502, corpo: { error: "number not on WhatsApp" } },
    { status: 502, corpo: { error: "HTTP 504", incerto: true } },
    { status: 409, corpo: { error: "A tentativa anterior…", em_andamento: true } },
    { status: 503, corpo: { error: "Envio automático não feito…", reserva_indisponivel: true } },
    { status: 200, corpo: {} },
    new Error("connection reset"),
  ]) {
    const db = bancoFalso();
    const r = await enviarLembrete({ ...base, admin: db, chamarEnvio: envioFalso(resposta).chamarEnvio });
    assertEquals(r.situacao, "erro", JSON.stringify(resposta instanceof Error ? resposta.message : resposta));
    assertEquals(db.marcados, []);
  }
});

Deno.test("dia útil: sem dia pulado, só o vencimento de hoje + N, como antes", () => {
  // terça 03/11/2026, depois da segunda útil
  assertEquals(vencimentosDoDia("2026-11-03", "2026-11-02", 3), { de: "2026-11-06", ate: "2026-11-06" });
});

Deno.test("dia útil: segunda depois do domingo cobre o vencimento que caiu no domingo", () => {
  // segunda 09/11/2026, último útil sábado 07/11 → quarta 11 e quinta 12
  assertEquals(vencimentosDoDia("2026-11-09", "2026-11-07", 3), { de: "2026-11-11", ate: "2026-11-12" });
  // sem sábado útil: último útil sexta 06/11 → terça 10, quarta 11 e quinta 12
  assertEquals(vencimentosDoDia("2026-11-09", "2026-11-06", 3), { de: "2026-11-10", ate: "2026-11-12" });
});

Deno.test("dia útil: mais dias pulados que N nunca volta antes de hoje (nada de 'vence hoje' com data passada)", () => {
  // recesso: último útil 18/12, hoje 05/01, N = 3 → de 05/01 (não 22/12) a 08/01
  assertEquals(vencimentosDoDia("2027-01-05", "2026-12-18", 3), { de: "2027-01-05", ate: "2027-01-08" });
  // N = 1, segunda depois de sexta útil: de segunda (não domingo) a terça
  assertEquals(vencimentosDoDia("2026-11-09", "2026-11-06", 1), { de: "2026-11-09", ate: "2026-11-10" });
});

Deno.test("prazo: hoje, amanhã ou N dias, pelo vencimento de verdade", () => {
  assertEquals(textoDoPrazo(diasEntre("2026-11-09", "2026-11-12")), "vence em *3 dias*");
  assertEquals(textoDoPrazo(diasEntre("2026-11-09", "2026-11-11")), "vence em *2 dias*");
  assertEquals(textoDoPrazo(1), "vence *amanhã*");
  assertEquals(textoDoPrazo(0), "vence *hoje*");
  assertEquals(somarDias("2026-12-31", 1), "2027-01-01");
  assertEquals(somarDias("2026-03-01", -1), "2026-02-28");
});

// "OS OS-" (12/10/2026): o número da OS já traz o prefixo ("OS-00060"). Sem descrição no
// recebível, a cobrança cita o número como vem, nunca "OS OS-00060".
Deno.test("descricaoDaCobranca: a descrição vence; sem ela, o número; sem os dois, 'cobrança pendente'", () => {
  assertEquals(descricaoDaCobranca("Saldo da OS-00060", "OS-00060"), "Saldo da OS-00060");
  assertEquals(descricaoDaCobranca(null, "OS-00060"), "OS-00060");
  assertEquals(descricaoDaCobranca("", "ORÇ-00112"), "ORÇ-00112");
  assertEquals(descricaoDaCobranca(undefined, ""), "cobrança pendente");
  assertEquals(descricaoDaCobranca(null, null), "cobrança pendente");
});
