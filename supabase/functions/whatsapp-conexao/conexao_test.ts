// Run: deno test supabase/functions/whatsapp-conexao/conexao_test.ts
//
// O que se protege: o QR e o código só saem quando a Evolution os entregou; o aviso de queda
// sai uma vez por queda (depois de 10 min, para não alarmar no religamento do túnel) e o de
// volta só quando houve aviso de queda.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  decidirVigia, lerEstado, lerRespostaDoConnect, motivoDaQueda, numeroParaPareamento,
  textoDoAviso, type RegistroDoVigia,
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
