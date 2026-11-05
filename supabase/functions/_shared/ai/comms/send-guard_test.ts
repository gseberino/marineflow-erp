// A guarda de envio falha FECHADA para quem é de fora (Retorno F0a-2, 05/11/2026). Antes a exceção do
// checador virava "tudo certo" e a hora que não dava para saber virava 12h: a trava sumia justamente
// quando não dava para conferir. A conversa interna segue aberta: ali não há o que proteger.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { guardaDeEnvio } from "./send-guard.ts";
import { checarConformidade, type ComplianceCtx, ehDeFora, RECUSA_CLIENTE_FINAL } from "./compliance-guard.ts";

/** Um contexto cuja hora estoura ao ser lida: força a exceção dentro de checarConformidade. */
function ctxQueQuebra(audiencia: ComplianceCtx["audiencia"]): ComplianceCtx {
  return {
    tipo: "generico",
    audiencia,
    canal: "whatsapp",
    get horaBrasilia(): number {
      throw new Error("relógio quebrado");
    },
  };
}

function semHoraDoSistema<T>(fn: () => T): T {
  const original = Date.prototype.toLocaleString;
  Date.prototype.toLocaleString = () => {
    throw new Error("sem fuso");
  };
  try {
    return fn();
  } finally {
    Date.prototype.toLocaleString = original;
  }
}

Deno.test("exceção na checagem: cliente e fornecedor ficam bloqueados", () => {
  for (const audiencia of ["cliente", "fornecedor"] as const) {
    const d = guardaDeEnvio("Olá, tudo bem?", ctxQueQuebra(audiencia));
    assertEquals(d.bloqueado, true, audiencia);
    assertEquals(d.codigoBloqueio, "guarda_indisponivel", audiencia);
    assertStringIncludes(d.motivo ?? "", "nada foi enviado");
  }
});

Deno.test("exceção na checagem: sem saber quem recebe, conta como de fora", () => {
  const ctx = {
    tipo: "generico",
    canal: "whatsapp",
    get audiencia(): "cliente" {
      throw new Error("sem audiência");
    },
  } as ComplianceCtx;
  const d = guardaDeEnvio("Olá", ctx);
  assertEquals(d.bloqueado, true);
  assertEquals(d.codigoBloqueio, "guarda_indisponivel");
});

Deno.test("hora que não se sabe: quem é de fora fica bloqueado, sem virar 12h", () => {
  const v = semHoraDoSistema(() =>
    checarConformidade({ tipo: "cobranca", audiencia: "cliente", canal: "whatsapp", destinatarioIdentificado: true })
  );
  assertEquals(v?.codigo, "hora_indisponivel");
  const d = semHoraDoSistema(() => guardaDeEnvio("Olá", { tipo: "cotacao", audiencia: "fornecedor", canal: "whatsapp" }));
  assertEquals(d.bloqueado, true);
  assertEquals(d.codigoBloqueio, "hora_indisponivel");
});

Deno.test("hora que não se sabe: o dono e o painel seguem sem trava", () => {
  assertEquals(semHoraDoSistema(() => checarConformidade({ tipo: "generico", audiencia: "dono", canal: "whatsapp" })), null);
  assertEquals(semHoraDoSistema(() => checarConformidade({ tipo: "generico", audiencia: "cliente", canal: "panel" })), null);
});

Deno.test("hora dita pelo chamador vale mesmo sem a hora do sistema", () => {
  const v = semHoraDoSistema(() => checarConformidade({ tipo: "generico", audiencia: "cliente", canal: "whatsapp", horaBrasilia: 10 }));
  assertEquals(v, null);
});

Deno.test("sem exceção, o caminho de sempre: passa no horário e bloqueia fora dele", () => {
  assertEquals(guardaDeEnvio("Olá", { tipo: "generico", audiencia: "cliente", canal: "whatsapp", horaBrasilia: 10 }).bloqueado, false);
  const d = guardaDeEnvio("Olá", { tipo: "generico", audiencia: "cliente", canal: "whatsapp", horaBrasilia: 22 });
  assertEquals(d.bloqueado, true);
  assertEquals(d.codigoBloqueio, "fora_de_horario");
});

Deno.test("ehDeFora: só cliente e fornecedor, só no WhatsApp", () => {
  assertEquals(ehDeFora({ canal: "whatsapp", audiencia: "cliente" }), true);
  assertEquals(ehDeFora({ canal: "whatsapp", audiencia: "fornecedor" }), true);
  assertEquals(ehDeFora({ canal: "whatsapp", audiencia: "dono" }), false);
  assertEquals(ehDeFora({ canal: "whatsapp", audiencia: "tecnico" }), false);
  assertEquals(ehDeFora({ canal: "panel", audiencia: "cliente" }), false);
});

Deno.test("a recusa do Cliente Final diz que nada saiu e o que fazer", () => {
  assertStringIncludes(RECUSA_CLIENTE_FINAL, "Nada foi enviado");
  assertStringIncludes(RECUSA_CLIENTE_FINAL, "Cliente Final");
});
