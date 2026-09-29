// Run: deno test supabase/functions/_shared/whatsapp/idempotencia_test.ts
import { assert, assertEquals, assertNotEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  chaveDeEnvio, concluirEnvio, diaLocal, hashCurto, liberarEnvio, reservarEnvio, reservarOuAguardar, situacaoDaReserva,
} from "./idempotencia.ts";

Deno.test("hashCurto é determinístico e muda com o texto", () => {
  assertEquals(hashCurto("Olá, tudo bem?"), hashCurto("Olá, tudo bem?"));
  assertNotEquals(hashCurto("Olá, tudo bem?"), hashCurto("Olá, tudo bem!"));
  assert(/^[0-9a-z]+$/.test(hashCurto("qualquer coisa")));
});

Deno.test("chaveDeEnvio descarta partes vazias, troca espaço por _ e limita o tamanho", () => {
  assertEquals(chaveDeEnvio("cobranca", "abc-1", null, undefined, "", "2026-09-19"), "cobranca:abc-1:2026-09-19");
  assertEquals(chaveDeEnvio("os link", 42), "os_link:42");
  assert(chaveDeEnvio("x".repeat(500)).length <= 200);
});

Deno.test("diaLocal usa o fuso de Brasília (UTC 02:00 ainda é o dia anterior)", () => {
  // 02:00Z de 20/09 = 23:00 de 19/09 em Brasília (UTC-3).
  assertEquals(diaLocal(new Date("2026-09-20T02:00:00Z")), "2026-09-19");
  assertEquals(diaLocal(new Date("2026-09-20T12:00:00Z")), "2026-09-20");
});

// Cliente falso: guarda as chaves num Set e responde 23505 na repetida.
function clienteFalso() {
  const chaves = new Set<string>();
  const tabela = {
    insert: (row: { chave: string }) => {
      if (chaves.has(row.chave)) return Promise.resolve({ error: { code: "23505", message: "dup" } });
      chaves.add(row.chave);
      return Promise.resolve({ error: null });
    },
    delete: () => ({ eq: (_c: string, v: string) => { chaves.delete(v); return Promise.resolve({ error: null }); } }),
  };
  return { chaves, from: (_t: string) => tabela };
}

Deno.test("reservarEnvio: primeira vez é nova, repetida é repetida, liberar reabre", async () => {
  const db = clienteFalso();
  assertEquals(await reservarEnvio(db, "cobranca:1:2026-09-19"), "nova");
  assertEquals(await reservarEnvio(db, "cobranca:1:2026-09-19"), "repetida");
  await liberarEnvio(db, "cobranca:1:2026-09-19");
  assertEquals(await reservarEnvio(db, "cobranca:1:2026-09-19"), "nova");
});

Deno.test("reservarEnvio: erro de banco não bloqueia o envio (fail open)", async () => {
  const db = { from: () => ({ insert: () => Promise.resolve({ error: { code: "57P01", message: "down" } }) }) };
  assertEquals(await reservarEnvio(db, "x"), "erro");
});

// ── Reserva com espera: "já enviado" só quando a outra tentativa TERMINOU ────────────────
// O defeito de 29/09/2026: a repetição depois de um erro de rede achava a chave reservada e
// ouvia "já enviado" enquanto a primeira tentativa ainda esperava a Evolution — e que depois
// falhava. Cliente falso com a tabela inteira: chave → concluido_em. `roteiro` muda a linha
// a cada consulta, fazendo o papel da outra tentativa que termina (ou falha) no meio da espera.
function tabelaFalsa(roteiro: Array<(linhas: Map<string, { concluido_em: string | null }>) => void> = []) {
  const linhas = new Map<string, { concluido_em: string | null }>();
  let consultas = 0;
  let falharLeitura = false;
  const tabela = {
    insert: (row: { chave: string }) => {
      if (linhas.has(row.chave)) return Promise.resolve({ error: { code: "23505", message: "dup" } });
      linhas.set(row.chave, { concluido_em: null });
      return Promise.resolve({ error: null });
    },
    select: (_c: string) => ({
      eq: (_col: string, chave: string) => ({
        maybeSingle: () => {
          roteiro[consultas]?.(linhas);
          consultas++;
          if (falharLeitura) return Promise.resolve({ data: null, error: { message: "down" } });
          const l = linhas.get(chave);
          return Promise.resolve({ data: l ? { ...l } : null, error: null });
        },
      }),
    }),
    update: (v: { concluido_em?: string }) => ({
      eq: (_col: string, chave: string) => {
        const l = linhas.get(chave);
        if (l && v.concluido_em) l.concluido_em = v.concluido_em;
        return Promise.resolve({ error: null });
      },
    }),
    delete: () => ({
      eq: (_c: string, chave: string) => { linhas.delete(chave); return Promise.resolve({ error: null }); },
      lt: () => Promise.resolve({ error: null }),
    }),
  };
  return {
    linhas,
    get consultas() { return consultas; },
    quebrarLeitura() { falharLeitura = true; },
    from: (_t: string) => tabela,
  };
}

const semEspera = { dormir: () => Promise.resolve() };

Deno.test("reservarOuAguardar: chave livre reserva e envia", async () => {
  const db = tabelaFalsa();
  assertEquals(await reservarOuAguardar(db, "painel:1", {}, semEspera), "nova");
});

Deno.test("reservarOuAguardar: a outra tentativa já concluiu → já enviada, sem esperar", async () => {
  const db = tabelaFalsa();
  await reservarEnvio(db, "painel:1");
  await concluirEnvio(db, "painel:1", null); // sem id do provedor: ainda assim concluída
  let esperas = 0;
  assertEquals(await reservarOuAguardar(db, "painel:1", {}, { dormir: () => { esperas++; return Promise.resolve(); } }), "ja_enviada");
  assertEquals(esperas, 0);
});

Deno.test("reservarOuAguardar: a outra termina durante a espera → já enviada", async () => {
  const db = tabelaFalsa([
    () => {}, // 1ª consulta: ainda na Evolution
    (l) => { l.get("painel:1")!.concluido_em = "2026-09-29T15:00:00Z"; }, // 2ª: saiu
  ]);
  await reservarEnvio(db, "painel:1");
  assertEquals(await reservarOuAguardar(db, "painel:1", {}, semEspera), "ja_enviada");
});

Deno.test("reservarOuAguardar: a outra FALHA durante a espera → esta reserva e envia (o defeito de 29/09)", async () => {
  const db = tabelaFalsa([
    () => {}, // ainda na Evolution
    (l) => { l.delete("painel:1"); }, // a Evolution falhou e a outra liberou a chave
  ]);
  await reservarEnvio(db, "painel:1");
  assertEquals(await reservarOuAguardar(db, "painel:1", {}, semEspera), "nova");
  assert(db.linhas.has("painel:1"), "a chave é desta tentativa agora");
});

Deno.test("reservarOuAguardar: sem desfecho depois da espera → em andamento, nunca 'enviado'", async () => {
  const db = tabelaFalsa();
  await reservarEnvio(db, "painel:1"); // a outra morreu no meio: reserva sem conclusão, para sempre
  let esperas = 0;
  const r = await reservarOuAguardar(db, "painel:1", {}, { consultas: 5, dormir: () => { esperas++; return Promise.resolve(); } });
  assertEquals(r, "em_andamento");
  assertEquals(esperas, 5, "espera o orçamento inteiro, nem mais nem menos");
});

Deno.test("reservarOuAguardar: banco não responde a consulta → em andamento (não afirma nada)", async () => {
  const db = tabelaFalsa();
  await reservarEnvio(db, "painel:1");
  db.quebrarLeitura();
  assertEquals(await reservarOuAguardar(db, "painel:1", {}, semEspera), "em_andamento");
});

Deno.test("reservarOuAguardar: chave que vive sendo liberada e retomada não prende a função", async () => {
  // Corrida patológica: a cada consulta alguém libera e alguém retoma. O orçamento acaba.
  const roteiro = Array.from({ length: 50 }, () => (l: Map<string, { concluido_em: string | null }>) => { l.delete("painel:1"); });
  const db = tabelaFalsa(roteiro);
  const tabela = db.from("x");
  const insertOriginal = tabela.insert;
  let inserts = 0;
  tabela.insert = (row: { chave: string }) => {
    inserts++;
    if (inserts === 1) return insertOriginal(row);
    db.linhas.set(row.chave, { concluido_em: null }); // outro chegou antes
    return Promise.resolve({ error: { code: "23505", message: "dup" } });
  };
  await tabela.insert({ chave: "painel:1" });
  const r = await reservarOuAguardar(db, "painel:1", {}, { consultas: 3, dormir: () => Promise.resolve() });
  assertEquals(r, "em_andamento");
  assert(inserts <= 5, `tentou reservar ${inserts} vezes`);
});

Deno.test("situacaoDaReserva: livre, em andamento e concluída", async () => {
  const db = tabelaFalsa();
  assertEquals(await situacaoDaReserva(db, "k"), "livre");
  await reservarEnvio(db, "k");
  assertEquals(await situacaoDaReserva(db, "k"), "em_andamento");
  await concluirEnvio(db, "k", "ABC123");
  assertEquals(await situacaoDaReserva(db, "k"), "concluida");
});
