// Retorno rápido, F4 (P11.3): a linha do parceiro no fechamento das 17:30. Banco falso; números e nomes inventados.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { lerParceiro, LINHAS_MAX_DO_PARCEIRO } from "./parceiro.ts";

const AGORA = new Date("2027-01-13T20:30:00.000Z"); // qua 13/01/2027, 17:30 em Brasília

function admin(r: { data?: unknown; error?: unknown; lanca?: boolean }) {
  const rpcs: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const erros: unknown[] = [];
  return {
    rpcs,
    erros,
    db: {
      rpc: (fn: string, args: Record<string, unknown>) => {
        // logEdgeError grava por log_app_error
        if (fn === "log_app_error") {
          erros.push(args);
          return Promise.resolve({ data: null, error: null });
        }
        rpcs.push({ fn, args });
        if (r.lanca) return Promise.reject(Object.assign(new Error("rede"), { code: "ECONNRESET" }));
        return Promise.resolve({ data: r.data ?? null, error: r.error ?? null });
      },
    },
  };
}

const LINHAS = [
  "Pátio da MP: 4 veículos, 2 mudaram · *parceiro* para liberar",
  "NÃO MP: 1 cliente hoje",
  "Vínculos sem aviso: 2",
  "Respostas ao aviso para decidir: 1 · *parceiro*",
  "MP: 2 perguntas esperando · *parceiro*",
];

Deno.test("lerParceiro: chama só parceiro_resumo_fechamento, com a hora, e devolve as linhas como vieram", async () => {
  const a = admin({ data: { linhas: LINHAS } });
  assertEquals(await lerParceiro(a.db, AGORA), LINHAS);
  assertEquals(a.rpcs, [{ fn: "parceiro_resumo_fechamento", args: { p_agora: AGORA.toISOString() } }]);
});

Deno.test("lerParceiro: a linha do pátio pede, não abre — nenhuma RPC de cartão nem de envio", async () => {
  const a = admin({ data: { linhas: LINHAS } });
  await lerParceiro(a.db, AGORA);
  for (const r of a.rpcs) {
    assert(!/cartao|enviar|agendar|abrir/.test(r.fn), r.fn);
  }
});

Deno.test("lerParceiro: sem telefone nem e-mail — a linha que traz um sai (falha fecha), as outras ficam", async () => {
  const a = admin({ data: { linhas: ["Pátio da MP: 4 veículos", "MP (47 99999-4321) espera", "ligar 4799994321", "mp@exemplo.com", "NÃO MP: 1 cliente hoje"] } });
  assertEquals(await lerParceiro(a.db, AGORA), ["Pátio da MP: 4 veículos", "NÃO MP: 1 cliente hoje"]);
});

Deno.test("lerParceiro: lista vazia, nula ou sem linhas = nada; forma inesperada = null", async () => {
  assertEquals(await lerParceiro(admin({ data: { linhas: [] } }).db, AGORA), []);
  assertEquals(await lerParceiro(admin({ data: { linhas: null } }).db, AGORA), []);
  const nulo = admin({ data: null });
  assertEquals(await lerParceiro(nulo.db, AGORA), null);
  assertEquals(nulo.erros.length, 0, "nulo não é forma inesperada");
  const forma = admin({ data: { linhas: "Pátio" } });
  assertEquals(await lerParceiro(forma.db, AGORA), null);
  assertEquals(forma.erros.length, 1, "a forma inesperada vai a app_error_logs");
  assertEquals(await lerParceiro(admin({ data: [1, 2] }).db, AGORA), null);
  // itens que não são texto, ou vazios, saem
  assertEquals(await lerParceiro(admin({ data: { linhas: ["", 3, null, "  ", "Vínculos sem aviso: 2"] } }).db, AGORA), ["Vínculos sem aviso: 2"]);
});

Deno.test("lerParceiro: no máximo LINHAS_MAX_DO_PARCEIRO linhas, cada uma numa linha só e curta", async () => {
  const muitas = Array.from({ length: 12 }, (_, i) => `Linha ${i + 1} do parceiro`);
  const r = await lerParceiro(admin({ data: { linhas: [...muitas, "duas\nlinhas", "x".repeat(400)] } }).db, AGORA);
  assertEquals(r!.length, LINHAS_MAX_DO_PARCEIRO);
  for (const l of r!) {
    assert(!l.includes("\n"));
    assert(l.length <= 200);
  }
});

Deno.test("lerParceiro: erro e exceção não derrubam — null, e a tarde sai como antes", async () => {
  const comErro = admin({ error: { code: "57014", message: "tempo esgotado" } });
  assertEquals(await lerParceiro(comErro.db, AGORA), null);
  assertEquals(comErro.erros.length, 1, "o erro vai a app_error_logs");
  const lanca = admin({ lanca: true });
  assertEquals(await lerParceiro(lanca.db, AGORA), null);
});

Deno.test("lerParceiro: função ausente (antes do deploy) = null, sem gravar ruído", async () => {
  for (const code of ["PGRST202", "42883"]) {
    const a = admin({ error: { code } });
    assertEquals(await lerParceiro(a.db, AGORA), null, code);
    assertEquals(a.erros.length, 0, code);
  }
});

Deno.test("o fechamento junta as linhas do parceiro aos extras do retorno, só no turno fechamento", async () => {
  const fonte = await Deno.readTextFile(new URL("./secretario-tarde.ts", import.meta.url));
  assert(fonte.includes("parceiro: await lerParceiro(admin, p.agora)"), "a tarde lê o parceiro");
  assert(/turno === "fechamento" \? \(lido\.parceiro \?\? \[\]\) : \[\]/.test(fonte), "só no fechamento");
});
