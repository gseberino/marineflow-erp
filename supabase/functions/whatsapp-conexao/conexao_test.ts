// Run: deno test supabase/functions/whatsapp-conexao/conexao_test.ts
//
// O que se protege: o QR e o código só saem quando a Evolution os entregou; o aviso de queda
// sai uma vez por queda (depois de 10 min, para não alarmar no religamento do túnel) e o de
// volta só quando houve aviso de queda. A sessão travada (03/10: "open" com o envio do ERP
// parado em PENDING) conta como queda, sem alarmar pelo SERVER_ACK que a API não mostra.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  confirmaTravada, decidirVigia, lerEstado, lerRespostaDoConnect, lerSaidas, motivoDaQueda, numeroParaPareamento,
  type SaidaRecente, suspeitaDeTravada, textoDoAviso, type RegistroDoVigia,
} from "./conexao.ts";

Deno.test("lerEstado: formato do connectionState e valores desconhecidos", () => {
  assertEquals(lerEstado({ instance: { instanceName: "hbr-local", state: "open" } }), "open");
  assertEquals(lerEstado({ instance: { state: "close" } }), "close");
  assertEquals(lerEstado({ state: "connecting" }), "connecting");
  assertEquals(lerEstado({ instance: { state: "refused" } }), null);
  assertEquals(lerEstado(null), null);
});

Deno.test("lerRespostaDoConnect: QR, código e conectado", () => {
  assertEquals(
    lerRespostaDoConnect({ base64: "data:image/png;base64,AAA", code: "2@x", pairingCode: null, count: 1 }),
    { estado: "connecting", qr: "data:image/png;base64,AAA", codigo: null },
  );
  assertEquals(
    lerRespostaDoConnect({ base64: "data:image/png;base64,AAA", pairingCode: " WZYEH1YY " }),
    { estado: "connecting", qr: "data:image/png;base64,AAA", codigo: "WZYEH1YY" },
  );
  assertEquals(
    lerRespostaDoConnect({ instance: { instanceName: "hbr-local", state: "open" } }),
    { estado: "open", qr: null, codigo: null },
  );
  // Primeiros segundos: a Evolution ainda não emitiu o QR.
  assertEquals(lerRespostaDoConnect({ count: 0 }), { estado: "connecting", qr: null, codigo: null });
  // Só imagem de verdade vira <img>.
  assertEquals(lerRespostaDoConnect({ base64: "javascript:alert(1)" }).qr, null);
});

Deno.test("numeroParaPareamento: aceita o que se digita e o ownerJid", () => {
  assertEquals(numeroParaPareamento("(47) 99792-1234"), "5547997921234");
  assertEquals(numeroParaPareamento("+55 47 9792-1234"), "554797921234");
  assertEquals(numeroParaPareamento("554797921234@s.whatsapp.net"), "554797921234");
  assertEquals(numeroParaPareamento("12345"), null);
  assertEquals(numeroParaPareamento("0800 123 4567"), null);
  assertEquals(numeroParaPareamento(""), null);
  assertEquals(numeroParaPareamento(null), null);
});

Deno.test("motivoDaQueda: 401 é o aparelho removido pelo celular", () => {
  assertEquals(motivoDaQueda(401), "o aparelho foi desconectado pelo celular (Dispositivos conectados)");
  assertEquals(motivoDaQueda(999), null);
  assertEquals(motivoDaQueda(null), null);
});

const T0 = new Date("2026-09-29T19:21:00Z");
const min = (m: number) => new Date(T0.getTime() + m * 60000);

Deno.test("vigia: primeira leitura só registra", () => {
  assertEquals(decidirVigia(null, "close", T0), {
    registro: { estado: "close", desde: T0.toISOString(), avisado_em: null },
    aviso: null,
  });
});

Deno.test("vigia: queda curta não avisa; 10 min fora avisa uma vez só", () => {
  let reg: RegistroDoVigia = { estado: "open", desde: min(-60).toISOString(), avisado_em: null };

  let r = decidirVigia(reg, "inacessivel", T0);
  assertEquals(r.aviso, null);
  assertEquals(r.registro.desde, T0.toISOString());
  reg = r.registro;

  // Trocar de close para connecting não zera o relógio.
  r = decidirVigia(reg, "connecting", min(5));
  assertEquals(r.aviso, null);
  assertEquals(r.registro.desde, T0.toISOString());
  reg = r.registro;

  r = decidirVigia(reg, "close", min(10));
  assertEquals(r.aviso, "caiu");
  assertEquals(r.registro.avisado_em, min(10).toISOString());
  reg = r.registro;

  r = decidirVigia(reg, "close", min(15));
  assertEquals(r.aviso, null);
  reg = r.registro;

  r = decidirVigia(reg, "open", min(20));
  assertEquals(r.aviso, "voltou");
  assertEquals(r.registro, { estado: "open", desde: min(20).toISOString(), avisado_em: null });
});

Deno.test("vigia: voltou antes do aviso não manda 'voltou'", () => {
  const reg: RegistroDoVigia = { estado: "inacessivel", desde: T0.toISOString(), avisado_em: null };
  assertEquals(decidirVigia(reg, "open", min(5)).aviso, null);
});

Deno.test("vigia: conectado continua conectado mantém o 'desde'", () => {
  const reg: RegistroDoVigia = { estado: "open", desde: T0.toISOString(), avisado_em: null };
  assertEquals(decidirVigia(reg, "open", min(30)).registro.desde, T0.toISOString());
});

Deno.test("textoDoAviso: fora do ar, desconectado e de volta", () => {
  const desde = "2026-09-29T19:21:00Z"; // 16:21 em Brasília
  assertEquals(
    textoDoAviso("caiu", { estado: "close", desde, avisado_em: null }, motivoDaQueda(401)).body,
    "Desde 16:21 nenhuma mensagem entra ou sai: o aparelho foi desconectado pelo celular (Dispositivos conectados). Toque para reconectar.",
  );
  assertEquals(
    textoDoAviso("caiu", { estado: "inacessivel", desde, avisado_em: null }).title,
    "WhatsApp fora do ar",
  );
  assertEquals(textoDoAviso("voltou", { estado: "open", desde, avisado_em: null }).title, "WhatsApp da HBR conectado de novo");
});

// ---------------------------------------------------------------------------------------------
// Sessão travada (03/10/2026): os registros abaixo têm o formato real do /chat/findMessages e do
// /chat/findChats da Evolution 2.3.7 (conteúdo das mensagens omitido).

const DONO = "5547999990000@s.whatsapp.net";
const CLIENTE = "5547988880000@s.whatsapp.net";
const seg = (iso: string) => new Date(iso).getTime() / 1000;

function registro(id: string, iso: string, opts: { jid?: string; source?: string; acks?: string[] } = {}) {
  return {
    id: `row-${id}`,
    key: { id, fromMe: true, remoteJid: opts.jid ?? DONO },
    messageType: "conversation",
    messageTimestamp: seg(iso),
    source: opts.source ?? "web",
    MessageUpdate: (opts.acks ?? []).map((status) => ({ status })),
  };
}

const DIA_03 = {
  messages: {
    total: 3, pages: 1, currentPage: 1,
    records: [
      registro("EXTRATO", "2026-10-03T18:25:05Z"),                              // 15:25, presa
      registro("DIGEST", "2026-10-03T10:35:05Z", { acks: ["DELIVERY_ACK"] }),  // 07:35, saiu
      registro("CELULAR", "2026-10-03T09:00:00Z", { source: "ios" }),          // do próprio celular
    ],
  },
};

Deno.test("lerSaidas: formato do findMessages; ignora o que não é envio", () => {
  const s = lerSaidas(DIA_03);
  assertEquals(s.map((x) => [x.id, x.confirmada, x.peloErp]), [
    ["EXTRATO", false, true], ["DIGEST", true, true], ["CELULAR", false, false],
  ]);
  assertEquals(s[0].quandoMs, Date.parse("2026-10-03T18:25:05Z"));
  assertEquals(lerSaidas({ messages: { records: [{ key: { id: "x", fromMe: false, remoteJid: DONO }, messageTimestamp: 1 }] } }), []);
  assertEquals(lerSaidas(null), []);
  assertEquals(lerSaidas({ error: "x" }), []);
});

Deno.test("suspeitaDeTravada: o envio das 15:25 sem confirmação vira suspeita às 15:35, não antes", () => {
  const saidas = lerSaidas(DIA_03);
  assertEquals(suspeitaDeTravada(saidas, Date.parse("2026-10-03T18:30:00Z")), null);
  assertEquals(suspeitaDeTravada(saidas, Date.parse("2026-10-03T18:35:05Z"))?.id, "EXTRATO");
});

Deno.test("suspeitaDeTravada: envio confirmado DEPOIS da suspeita = a sessão funciona", () => {
  const saidas: SaidaRecente[] = [
    ...lerSaidas(DIA_03),
    { id: "RESPOSTA", remoteJid: DONO, quandoMs: Date.parse("2026-10-03T18:48:50Z"), confirmada: true, peloErp: true },
  ];
  assertEquals(suspeitaDeTravada(saidas, Date.parse("2026-10-03T19:30:00Z")), null);
});

Deno.test("suspeitaDeTravada: o que ficou preso antes da reconexão pela tela não conta", () => {
  const saidas = lerSaidas(DIA_03);
  const agora = Date.parse("2026-10-03T19:00:00Z");
  assertEquals(suspeitaDeTravada(saidas, agora, Date.parse("2026-10-03T18:46:00Z")), null);
  assertEquals(suspeitaDeTravada(saidas, agora, Date.parse("2026-10-03T18:00:00Z"))?.id, "EXTRATO");
});

Deno.test("suspeitaDeTravada: mensagem do próprio celular sem confirmação não é suspeita", () => {
  const saidas = lerSaidas({ messages: { records: [registro("CEL", "2026-10-03T12:00:00Z", { source: "android" })] } });
  assertEquals(suspeitaDeTravada(saidas, Date.parse("2026-10-03T18:00:00Z")), null);
});

Deno.test("suspeitaDeTravada: entre várias presas, a mais nova", () => {
  const saidas = lerSaidas({
    messages: {
      records: [
        registro("B", "2026-10-03T18:40:00Z", { jid: CLIENTE }),
        registro("A", "2026-10-03T18:25:05Z"),
        registro("OK", "2026-10-03T18:00:00Z", { acks: ["SERVER_ACK"] }),
      ],
    },
  });
  assertEquals(suspeitaDeTravada(saidas, Date.parse("2026-10-03T18:52:00Z"))?.id, "B");
  // B ainda tem menos de 10 min: a suspeita é A.
  assertEquals(suspeitaDeTravada(saidas, Date.parse("2026-10-03T18:45:00Z"))?.id, "A");
});

Deno.test("confirmaTravada: só PENDING e ainda a última da conversa", () => {
  const conversa = (id: string, status: string, fromMe = true) =>
    [{ remoteJid: DONO, lastMessage: { key: { id, fromMe, remoteJid: DONO }, status } }];
  assertEquals(confirmaTravada(conversa("EXTRATO", "PENDING"), "EXTRATO"), true);
  // 09/09 a 25/09: 18 envios sem MessageUpdate, todos com SERVER_ACK no status. Não é trava.
  assertEquals(confirmaTravada(conversa("EXTRATO", "SERVER_ACK"), "EXTRATO"), false);
  // Alguém respondeu depois: a última mensagem é outra.
  assertEquals(confirmaTravada(conversa("RESPOSTA", "DELIVERY_ACK", false), "EXTRATO"), false);
  assertEquals(confirmaTravada([], "EXTRATO"), false);
  assertEquals(confirmaTravada({ error: "x" }, "EXTRATO"), false);
});

Deno.test("vigia: travado conta como fora do ar — avisa depois de 10 min e avisa a volta", () => {
  let reg: RegistroDoVigia = { estado: "open", desde: min(-60).toISOString(), avisado_em: null };
  let r = decidirVigia(reg, "travado", T0);
  assertEquals(r.aviso, null);
  reg = r.registro;
  r = decidirVigia(reg, "travado", min(10));
  assertEquals(r.aviso, "caiu");
  reg = r.registro;
  // "Desconectar e ler o QR de novo" passa por close: não avisa de novo.
  r = decidirVigia(reg, "close", min(15));
  assertEquals(r.aviso, null);
  reg = r.registro;
  r = decidirVigia(reg, "open", min(20));
  assertEquals(r.aviso, "voltou");
});

Deno.test("textoDoAviso: travado diz que aparece conectado e qual envio parou", () => {
  const t = textoDoAviso(
    "caiu",
    { estado: "travado", desde: "2026-10-03T18:35:05Z", avisado_em: null },
    "a mensagem enviada às 15:25 não foi confirmada pelo WhatsApp",
  );
  assertEquals(t.title, "WhatsApp travado");
  assertEquals(
    t.body,
    "Aparece conectado, mas as mensagens não estão saindo (a mensagem enviada às 15:25 não foi confirmada pelo WhatsApp). Toque para desconectar e ler o QR de novo.",
  );
});
