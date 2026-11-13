// Retorno rápido, F5 (P10.3): o orçamento no fechamento das 17:30. Banco falso; números e nomes inventados.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { avisarOrcamentoNaTarde, lerOrcamento, LINHAS_MAX_DO_ORCAMENTO } from "./orcamento.ts";

const AGORA = new Date("2026-12-09T20:30:00.000Z"); // qua 09/12/2026, 17:30 em Brasília
const HOJE = "2026-12-09";
const DONO = "5547900009901";
const P1 = "8d0c6a3e-1111-4a5b-9c7d-000000000001";
const P2 = "8d0c6a3e-1111-4a5b-9c7d-000000000002";
const FILA = "f1f1f1f1-2222-4a5b-9c7d-000000000009";

const FIXA = "Orçamentos: amanhã sai sozinho o lembrete do ORÇ-00151 (Ana) · *segura 151*";
const LINHAS = [
  "Orçamentos: amanhã 1 lembrete espera o seu *sim <PIN>* no *retorno*",
  "Encerrado hoje sem resposta: ORÇ-00140 (Pedro) · para marcar como perdido, use a tela ou o assistente",
  "O 'Fechado' do ORÇ-00152 (João) não saiu: responda você",
  "Enviados vencidos sem desfecho: 2 (ORÇ-00130, ORÇ-00131) · para marcar como perdido, use a tela ou o assistente",
];

type Chamada = { fn: string; args: Record<string, unknown> };

function admin(r: { data?: unknown; error?: unknown; lanca?: boolean; fila?: string | null; filaErro?: boolean; avisadosErro?: unknown } = {}) {
  const rpcs: Chamada[] = [];
  const erros: unknown[] = [];
  const leituras: Array<{ tabela: string; filtro: [string, unknown] }> = [];
  return {
    rpcs,
    erros,
    leituras,
    db: {
      rpc: (fn: string, args: Record<string, unknown>) => {
        if (fn === "log_app_error") {
          erros.push(args);
          return Promise.resolve({ data: null, error: null });
        }
        rpcs.push({ fn, args });
        if (fn === "orcamento_avisados") {
          return Promise.resolve({ data: r.avisadosErro ? null : 1, error: r.avisadosErro ?? null });
        }
        if (r.lanca) return Promise.reject(Object.assign(new Error("rede"), { code: "ECONNRESET" }));
        return Promise.resolve({ data: r.data ?? null, error: r.error ?? null });
      },
      from: (tabela: string) => ({
        select: () => ({
          eq: (col: string, val: unknown) => ({
            maybeSingle: () => {
              leituras.push({ tabela, filtro: [col, val] });
              if (r.filaErro) return Promise.resolve({ data: null, error: { code: "57014" } });
              return Promise.resolve({ data: r.fila === null || r.fila === undefined ? null : { id: r.fila }, error: null });
            },
          }),
        }),
      }),
    },
  };
}

Deno.test("lerOrcamento: chama só orcamento_resumo_fechamento, com a hora, e devolve fixas, linhas e avisar como vieram", async () => {
  const a = admin({ data: { fixas: [FIXA], linhas: LINHAS, avisar: [P1] } });
  assertEquals(await lerOrcamento(a.db, AGORA), { fixas: [FIXA], linhas: LINHAS, avisar: [P1] });
  assertEquals(a.rpcs, [{ fn: "orcamento_resumo_fechamento", args: { p_agora: AGORA.toISOString() } }]);
});

Deno.test("lerOrcamento: o fechamento pede, não abre — nenhuma RPC de cartão, de envio nem de aviso", async () => {
  const a = admin({ data: { fixas: [FIXA], linhas: LINHAS, avisar: [P1] } });
  await lerOrcamento(a.db, AGORA);
  for (const r of a.rpcs) assert(!/cartao|enviar|agendar|abrir|avisados|dito/.test(r.fn), r.fn);
});

Deno.test("lerOrcamento: sem telefone nem documento — a linha com 8 dígitos ou mais (ou e-mail) sai; as outras ficam", async () => {
  const a = admin({
    data: {
      fixas: [FIXA],
      linhas: [
        LINHAS[0], "Ligue para a Ana: 47 90000-9901", "CPF 123.456.789-01 da Ana", "ana@exemplo.com", "ORÇ-00151 (Ana)",
        "Telefone 4790000990",
      ],
      avisar: [P1],
    },
  });
  const r = await lerOrcamento(a.db, AGORA);
  assertEquals(r?.linhas, [LINHAS[0], "ORÇ-00151 (Ana)"]);
  for (const l of [...r!.linhas, ...r!.fixas]) assert(!/\d{8,}/.test(l.replace(/[\s().-]/g, "")), l);
});

Deno.test("lerOrcamento: a linha fixa com dado de contato, forma errada ou sem passo — nenhuma fixa e nenhum aviso (o passo vai ao cartão)", async () => {
  // fixa com telefone: falha fecha, e os passos dela não podem ser marcados
  let r = await lerOrcamento(admin({ data: { fixas: ["Orçamentos: amanhã sai sozinho o lembrete do ORÇ-00151 (Ana 4790000990)"], linhas: [], avisar: [P1] } }).db, AGORA);
  assertEquals(r, { fixas: [], linhas: [], avisar: [] });
  // avisar com id que não é uuid
  r = await lerOrcamento(admin({ data: { fixas: [FIXA], linhas: [], avisar: ["x"] } }).db, AGORA);
  assertEquals(r, { fixas: [], linhas: [], avisar: [] });
  // fixa sem passo: a linha diria "sai sozinho" e nada seria marcado
  r = await lerOrcamento(admin({ data: { fixas: [FIXA], linhas: [], avisar: [] } }).db, AGORA);
  assertEquals(r, { fixas: [], linhas: [], avisar: [] });
  // passo sem fixa: nada a avisar
  r = await lerOrcamento(admin({ data: { fixas: [], linhas: [LINHAS[1]], avisar: [P1] } }).db, AGORA);
  assertEquals(r, { fixas: [], linhas: [LINHAS[1]], avisar: [] });
  // fixa com quebra de linha
  r = await lerOrcamento(admin({ data: { fixas: ["Orçamentos:\namanhã"], linhas: [], avisar: [P1] } }).db, AGORA);
  assertEquals(r, { fixas: [], linhas: [], avisar: [] });
});

Deno.test("lerOrcamento: listas vazias ou nulas = nada; forma inesperada = null e app_error_logs", async () => {
  assertEquals(await lerOrcamento(admin({ data: { fixas: [], linhas: [], avisar: [] } }).db, AGORA), { fixas: [], linhas: [], avisar: [] });
  assertEquals(await lerOrcamento(admin({ data: { fixas: null, linhas: null, avisar: null } }).db, AGORA), { fixas: [], linhas: [], avisar: [] });
  const nulo = admin({ data: null });
  assertEquals(await lerOrcamento(nulo.db, AGORA), null);
  assertEquals(nulo.erros.length, 0, "nulo não é forma inesperada");
  for (const data of [{ fixas: "x", linhas: [], avisar: [] }, { fixas: [], linhas: "x", avisar: [] }, { fixas: [], linhas: [], avisar: "x" }, [1, 2], "texto"]) {
    const f = admin({ data });
    assertEquals(await lerOrcamento(f.db, AGORA), null, JSON.stringify(data));
    assertEquals(f.erros.length, 1, `a forma inesperada vai a app_error_logs: ${JSON.stringify(data)}`);
  }
});

Deno.test("lerOrcamento: no máximo LINHAS_MAX_DO_ORCAMENTO linhas, cada uma numa linha só e curta", async () => {
  const muitas = Array.from({ length: 9 }, (_, i) => `Encerrado hoje sem resposta: ORÇ-0014${i} (Pedro)`);
  const r = await lerOrcamento(admin({ data: { fixas: [], linhas: [...muitas, "duas\nlinhas", "x".repeat(400)], avisar: [] } }).db, AGORA);
  assertEquals(r!.linhas.length, LINHAS_MAX_DO_ORCAMENTO);
  for (const l of r!.linhas) {
    assert(!l.includes("\n"));
    assert(l.length <= 300);
  }
});

Deno.test("lerOrcamento: erro, exceção e função ausente não derrubam — null, e a tarde sai como antes", async () => {
  const comErro = admin({ error: { code: "57014", message: "tempo esgotado" } });
  assertEquals(await lerOrcamento(comErro.db, AGORA), null);
  assertEquals(comErro.erros.length, 1, "o erro vai a app_error_logs");
  const lanca = admin({ lanca: true });
  assertEquals(await lerOrcamento(lanca.db, AGORA), null);
  assertEquals(lanca.erros.length, 1);
  for (const code of ["PGRST202", "42883"]) {
    const ausente = admin({ error: { code, message: "função ausente" } });
    assertEquals(await lerOrcamento(ausente.db, AGORA), null, code);
    assertEquals(ausente.erros.length, 0, `função ausente (antes do deploy) não é erro: ${code}`);
  }
});

// ─── O registro do aviso (orcamento_avisados) ──────────────────────────────────────────────────────────────────────

const TEXTO_COM_A_FIXA = `Fechamento de quarta, 09/12: nada ficou de hoje.\n${FIXA}\n\nAmanhã: nada marcado.`;

Deno.test("avisarOrcamentoNaTarde: o texto enviado tem cada linha fixa → orcamento_avisados com os passos, a fila da tarde e a hora", async () => {
  const a = admin({ fila: FILA });
  const r = await avisarOrcamentoNaTarde(a.db, { texto: TEXTO_COM_A_FIXA, fixas: [FIXA], avisar: [P1, P2], hoje: HOJE, phone: DONO, agora: AGORA });
  assertEquals(r, "avisado");
  assertEquals(a.leituras, [{ tabela: "whatsapp_send_queue", filtro: ["dedupe_key", `secretario_tarde:${HOJE}:${DONO}`] }]);
  assertEquals(a.rpcs, [{ fn: "orcamento_avisados", args: { p_passos: [P1, P2], p_fila: FILA, p_agora: AGORA.toISOString() } }]);
});

Deno.test("avisarOrcamentoNaTarde: o texto sem a linha fixa (cortada, ou outra) não avisa nada", async () => {
  for (const texto of ["Fechamento de quarta, 09/12: nada ficou de hoje.", FIXA.slice(0, 40), null, ""]) {
    const a = admin({ fila: FILA });
    assertEquals(await avisarOrcamentoNaTarde(a.db, { texto, fixas: [FIXA], avisar: [P1], hoje: HOJE, phone: DONO, agora: AGORA }), "sem_linha");
    assertEquals(a.rpcs.length, 0, String(texto));
    assertEquals(a.leituras.length, 0, String(texto));
  }
  // duas fixas: as duas têm de estar no texto
  const a = admin({ fila: FILA });
  const outra = "Orçamentos: amanhã sai sozinho o encerramento do ORÇ-00140 (Pedro) · *segura 140*";
  assertEquals(await avisarOrcamentoNaTarde(a.db, { texto: TEXTO_COM_A_FIXA, fixas: [FIXA, outra], avisar: [P1], hoje: HOJE, phone: DONO, agora: AGORA }), "sem_linha");
  assertEquals(a.rpcs.length, 0);
});

Deno.test("avisarOrcamentoNaTarde: sem fixa, sem passo ou sem o id da fila — não chama orcamento_avisados", async () => {
  let a = admin({ fila: FILA });
  assertEquals(await avisarOrcamentoNaTarde(a.db, { texto: TEXTO_COM_A_FIXA, fixas: [], avisar: [P1], hoje: HOJE, phone: DONO, agora: AGORA }), "nada");
  assertEquals(a.rpcs.length, 0);
  a = admin({ fila: FILA });
  assertEquals(await avisarOrcamentoNaTarde(a.db, { texto: TEXTO_COM_A_FIXA, fixas: [FIXA], avisar: [], hoje: HOJE, phone: DONO, agora: AGORA }), "nada");
  assertEquals(a.rpcs.length, 0);
  a = admin({ fila: null });
  assertEquals(await avisarOrcamentoNaTarde(a.db, { texto: TEXTO_COM_A_FIXA, fixas: [FIXA], avisar: [P1], hoje: HOJE, phone: DONO, agora: AGORA }), "sem_fila");
  assertEquals(a.rpcs.length, 0);
  a = admin({ filaErro: true, fila: FILA });
  assertEquals(await avisarOrcamentoNaTarde(a.db, { texto: TEXTO_COM_A_FIXA, fixas: [FIXA], avisar: [P1], hoje: HOJE, phone: DONO, agora: AGORA }), "sem_fila");
  assertEquals(a.rpcs.length, 0);
});

Deno.test("avisarOrcamentoNaTarde: erro na chamada vai a app_error_logs e não lança (o passo vai ao cartão)", async () => {
  const a = admin({ fila: FILA, avisadosErro: { code: "57014", message: "tempo esgotado" } });
  assertEquals(await avisarOrcamentoNaTarde(a.db, { texto: TEXTO_COM_A_FIXA, fixas: [FIXA], avisar: [P1], hoje: HOJE, phone: DONO, agora: AGORA }), "erro");
  assertEquals(a.erros.length, 1);
  // o log não leva telefone
  assert(!JSON.stringify(a.erros).includes(DONO));
});
