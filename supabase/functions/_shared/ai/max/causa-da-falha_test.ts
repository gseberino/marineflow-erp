// A causa da falha do Claude da assinatura, dita ao dono (pacote 1, C2, 24/11/2026). Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/_shared/ai/max/causa-da-falha_test.ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  avisoDeQueOClaudeNaoRespondeu,
  causaDaFalha,
  CODIGOS_DA_CAUSA,
  duracaoPorExtenso,
  type EstadoDoMax,
  estadoDoMax,
  FRASE_CURTA_DA_CAUSA,
  lerCausaDaFalha,
  lerEstadoDoMax,
  ondeDoTurnoSemResposta,
  type ProgramaDoPc,
  rotuloDaCausaNoLog,
  SEM_SINAL_AGORA_S,
  SEM_SINAL_QUEDA_S,
  TEXTO_PARA_QUEM_NAO_E_O_TITULAR,
  textoDaFalhaParaODono,
  TURNO_SEM_RESPOSTA,
  TURNO_SEM_RESPOSTA_COM_CAUSA,
} from "./causa-da-falha.ts";
import { ERRO_DO_SISTEMA_PARA_O_DONO, respostaDoTurnoNoWhatsApp } from "../whatsapp-resposta.ts";

// terça-feira, 24/11/2026, 09:32 em Brasília
const AGORA = new Date("2026-11-24T12:32:00Z");
const haSegundos = (s: number) => new Date(AGORA.getTime() - s * 1000).toISOString();

/** Os três programas do PC como estão em produção (conferido em 24/11/2026): cada um publica o que atende. */
function programas(p: { assistenteHa?: number | null; claude?: Record<string, unknown>; ativos?: number; max?: number; outrosHa?: number } = {}): ProgramaDoPc[] {
  const assistenteHa = p.assistenteHa === undefined ? 6 : p.assistenteHa;
  return [
    { id: "hbr-pc-doc", last_seen_at: haSegundos(p.outrosHa ?? 14), estado: { providers: { "local-doc": { available: true } }, ativos: 0, max: 1 } },
    {
      id: "hbr-pc-1",
      last_seen_at: assistenteHa === null ? null : haSegundos(assistenteHa),
      estado: { providers: { "claude-local": p.claude ?? { available: true } }, ativos: p.ativos ?? 0, max: p.max ?? 2, em: haSegundos(6) },
    },
    { id: "hbr-pc-print", last_seen_at: haSegundos(p.outrosHa ?? 9), estado: { providers: { "local-print": { available: true } }, ativos: 0, max: 1 } },
  ];
}

const NO_AR: EstadoDoMax = { ultimoSinal: haSegundos(6), semSinal: false, pausa: null, ocupado: false, pcComSinal: true };
const estado = (p: Partial<EstadoDoMax>): EstadoDoMax => ({ ...NO_AR, ...p });

// ─── O estado do programa do assistente ──────────────────────────────────────────────────────────────────────────────

Deno.test("estado: o programa do assistente é o que publica o Claude; no ar, sem pausa e com vaga", () => {
  const e = estadoDoMax(programas(), SEM_SINAL_AGORA_S, AGORA);
  assertEquals(e, { ultimoSinal: haSegundos(6), semSinal: false, pausa: null, ocupado: false, pcComSinal: true });
});

Deno.test("estado: o corte é de quem pergunta — 45 s quer dizer 'agora', 180 s quer dizer 'queda'", () => {
  assertEquals([SEM_SINAL_AGORA_S, SEM_SINAL_QUEDA_S], [45, 180]);
  // um minuto calado: para o turno do dono já é "sem sinal"; para o vigia ainda não é queda
  const umMinuto = programas({ assistenteHa: 60 });
  assertEquals(estadoDoMax(umMinuto, SEM_SINAL_AGORA_S, AGORA).semSinal, true);
  assertEquals(estadoDoMax(umMinuto, SEM_SINAL_QUEDA_S, AGORA).semSinal, false);
  // a borda é a de ai_claude_max_disponivel (last_seen_at > now() - 45 s): 44 s tem sinal, 45 s não
  assertEquals(estadoDoMax(programas({ assistenteHa: 44 }), SEM_SINAL_AGORA_S, AGORA).semSinal, false);
  assertEquals(estadoDoMax(programas({ assistenteHa: 45 }), SEM_SINAL_AGORA_S, AGORA).semSinal, true);
  assertEquals(estadoDoMax(programas({ assistenteHa: 181 }), SEM_SINAL_QUEDA_S, AGORA).semSinal, true);
});

Deno.test("estado: só o programa do assistente calado = o PC segue com sinal; os três calados = o PC sem sinal", () => {
  const soOAssistente = estadoDoMax(programas({ assistenteHa: 3600 }), SEM_SINAL_QUEDA_S, AGORA);
  assertEquals([soOAssistente.semSinal, soOAssistente.pcComSinal], [true, true]);
  assertEquals(soOAssistente.ultimoSinal, haSegundos(3600));
  const tudo = estadoDoMax(programas({ assistenteHa: 3600, outrosHa: 3600 }), SEM_SINAL_QUEDA_S, AGORA);
  assertEquals([tudo.semSinal, tudo.pcComSinal], [true, false]);
});

Deno.test("estado: a pausa que o programa publica (motivo e até quando) e as vagas ocupadas", () => {
  const login = estadoDoMax(programas({ claude: { available: false, reason: "auth_failed", until: "2026-11-24T12:42:00.000Z" } }), SEM_SINAL_AGORA_S, AGORA);
  assertEquals(login.pausa, { motivo: "auth_failed", ate: "2026-11-24T12:42:00.000Z" });
  // sem motivo e sem horário: ainda é "não disponível" (o banco só aceita available = true)
  assertEquals(estadoDoMax(programas({ claude: { available: false } }), SEM_SINAL_AGORA_S, AGORA).pausa, { motivo: "", ate: null });
  assertEquals(estadoDoMax(programas({ claude: {} }), SEM_SINAL_AGORA_S, AGORA).pausa, { motivo: "", ate: null });
  assertEquals(estadoDoMax(programas({ claude: { available: false, reason: "rate_limited", until: "lixo" } }), SEM_SINAL_AGORA_S, AGORA).pausa, { motivo: "rate_limited", ate: null });
  assertEquals(estadoDoMax(programas({ ativos: 2, max: 2 }), SEM_SINAL_AGORA_S, AGORA).ocupado, true);
  assertEquals(estadoDoMax(programas({ ativos: 1, max: 2 }), SEM_SINAL_AGORA_S, AGORA).ocupado, false);
});

Deno.test("estado: sem programa do assistente, linha torta ou lista vazia = sem sinal, sem horário, e nunca lança", () => {
  const semOClaude = programas().filter((p) => p.id !== "hbr-pc-1");
  assertEquals(estadoDoMax(semOClaude, SEM_SINAL_AGORA_S, AGORA), { ultimoSinal: null, semSinal: true, pausa: null, ocupado: false, pcComSinal: true });
  for (const torto of [null, undefined, [], [{ id: "x", last_seen_at: null, estado: null }], [{ id: "x", last_seen_at: "lixo", estado: "texto" }]]) {
    const e = estadoDoMax(torto as ProgramaDoPc[] | null, SEM_SINAL_AGORA_S, AGORA);
    assertEquals([e.semSinal, e.ultimoSinal, e.pcComSinal], [true, null, false], JSON.stringify(torto));
  }
  // nunca avisou: sem sinal, sem horário
  const nunca = estadoDoMax(programas({ assistenteHa: null }), SEM_SINAL_AGORA_S, AGORA);
  assertEquals([nunca.semSinal, nunca.ultimoSinal], [true, null]);
  // dois programas do assistente: vale o que avisou por último
  const dois = [...programas({ assistenteHa: 3600 }), { id: "hbr-pc-2", last_seen_at: haSegundos(5), estado: { providers: { "claude-local": { available: true } } } }];
  assertEquals(estadoDoMax(dois, SEM_SINAL_AGORA_S, AGORA).ultimoSinal, haSegundos(5));
});

/** Um banco de mentira que anota o que foi pedido. */
function banco(resposta: { data?: unknown; error?: unknown } | "lanca") {
  const pedido: { tabela?: string; colunas?: string; filtros: Array<[string, unknown]> } = { filtros: [] };
  const admin = {
    from(tabela: string) {
      pedido.tabela = tabela;
      return {
        select(colunas: string) {
          pedido.colunas = colunas;
          return {
            eq(coluna: string, valor: unknown) {
              pedido.filtros.push([coluna, valor]);
              if (resposta === "lanca") return Promise.reject(new Error("rede fora"));
              return Promise.resolve({ data: resposta.data ?? null, error: resposta.error ?? null });
            },
          };
        },
      };
    },
  };
  return { admin, pedido };
}

Deno.test("leitura: pede só id, sinal e estado dos programas ligados — nunca o token_hash nem coluna fora dos tipos", async () => {
  const { admin, pedido } = banco({ data: programas({ assistenteHa: 60 }) });
  const e = await lerEstadoDoMax(admin, SEM_SINAL_AGORA_S, AGORA);
  assertEquals(pedido.tabela, "ai_gateway_workers");
  assertEquals(pedido.colunas, "id, last_seen_at, estado");
  assertEquals(pedido.filtros, [["enabled", true]]);
  assertEquals(e?.semSinal, true);
  // o mesmo banco, com o corte do vigia: ainda não é queda
  assertEquals((await lerEstadoDoMax(banco({ data: programas({ assistenteHa: 60 }) }).admin, SEM_SINAL_QUEDA_S, AGORA))?.semSinal, false);
});

Deno.test("leitura: erro do banco ou exceção = null (nunca lança, nunca vira 'está fora')", async () => {
  assertEquals(await lerEstadoDoMax(banco({ error: { message: "permission denied" } }).admin, SEM_SINAL_AGORA_S, AGORA), null);
  assertEquals(await lerEstadoDoMax(banco({ data: null }).admin, SEM_SINAL_AGORA_S, AGORA), null);
  assertEquals(await lerEstadoDoMax(banco("lanca").admin, SEM_SINAL_AGORA_S, AGORA), null);
});

Deno.test("leitura (fonte): a consulta não cita token_hash, allowed_providers nem '*'", async () => {
  const fonte = await Deno.readTextFile(new URL("./causa-da-falha.ts", import.meta.url));
  const selects = [...fonte.matchAll(/\.select\(([^)]*)\)/g)].map((m) => m[1]);
  assertEquals(selects, ['"id, last_seen_at, estado"']);
});

// ─── A causa, uma linha da tabela por vez ────────────────────────────────────────────────────────────────────────────

const PREFIXO = "⚠️ Não consegui responder: ";

Deno.test("login: o pedido falhou no login, ou não houve pedido e o Claude está em pausa por login", () => {
  const texto = "o login do Claude no PC da oficina caiu. É preciso entrar de novo no Claude, no PC. Depois, mande a mensagem de novo.";
  const doPedido = causaDaFalha({ job: { error_code: "auth_failed", error: "Not logged in · Please run /login" }, estado: NO_AR, agora: AGORA });
  assertEquals(doPedido, { codigo: "login", curta: "o login do Claude caiu", texto, cru: "auth_failed" });
  const daPausa = causaDaFalha({ job: null, estado: estado({ pausa: { motivo: "auth_failed", ate: null } }), agora: AGORA });
  assertEquals([daPausa.codigo, daPausa.texto, daPausa.cru], ["login", texto, "auth_failed"]);
  assertEquals(textoDaFalhaParaODono(doPedido), `${PREFIXO}${texto}`);
});

Deno.test("limite: com o horário de liberação em Brasília (outro dia, hoje, sem horário, horário que já passou)", () => {
  const erro = (iso: string) => `Limite de uso da assinatura atingido (seven_day); libera em ${iso}.`;
  const outroDia = causaDaFalha({ job: { error_code: "rate_limited", error: erro("2026-11-26T05:00:00.000Z") }, estado: null, agora: AGORA });
  assertEquals(outroDia.codigo, "limite");
  assertEquals(outroDia.texto, "acabou o limite de uso da assinatura Claude. Libera qui 26/11 às 02:00. Até lá eu não consigo responder.");
  const hoje = causaDaFalha({ job: { error_code: "rate_limited", error: erro("2026-11-24T21:30:00.000Z") }, estado: null, agora: AGORA });
  assertEquals(hoje.texto, "acabou o limite de uso da assinatura Claude. Libera às 18:30. Até lá eu não consigo responder.");
  // o programa repassa o erro com outro começo quando o pedido cai na pausa: o horário ainda é lido
  const naPausa = causaDaFalha({ job: { error_code: "rate_limited", error: `claude-local indisponível: ${erro("2026-11-26T05:00:00.000Z")}.` }, estado: null, agora: AGORA });
  assertStringIncludes(naPausa.texto, "Libera qui 26/11 às 02:00.");
  const semHorario = "acabou o limite de uso da assinatura Claude. Ainda não sei quando libera. Até lá eu não consigo responder.";
  assertEquals(causaDaFalha({ job: { error_code: "rate_limited", error: "limite" }, estado: null, agora: AGORA }).texto, semHorario);
  assertEquals(causaDaFalha({ job: { error_code: "rate_limited", error: erro("2026-11-24T12:00:00.000Z") }, estado: null, agora: AGORA }).texto, semHorario);
  // sem horário no erro, vale o da pausa (só se a pausa for do limite)
  const pausaDoLimite = estado({ pausa: { motivo: "rate_limited", ate: "2026-11-25T02:15:00.000Z" } });
  assertStringIncludes(causaDaFalha({ job: { error_code: "rate_limited" }, estado: pausaDoLimite, agora: AGORA }).texto, "Libera às 23:15.");
  assertStringIncludes(causaDaFalha({ job: null, estado: pausaDoLimite, agora: AGORA }).texto, "Libera às 23:15.");
  const pausaDeOutraCoisa = estado({ pausa: { motivo: "auth_failed", ate: "2026-11-25T02:15:00.000Z" } });
  assertEquals(causaDaFalha({ job: { error_code: "rate_limited" }, estado: pausaDeOutraCoisa, agora: AGORA }).texto, semHorario);
});

Deno.test("faturamento e ferramentas: o detalhe do pedido escolhe a frase; a pausa sem detalhe é a de ferramentas", () => {
  const fat = causaDaFalha({ job: { error_code: "provider_unavailable", error: "Assinatura sem crédito/faturamento disponível: billing_error" }, estado: NO_AR, agora: AGORA });
  assertEquals([fat.codigo, fat.texto], ["faturamento", "a assinatura Claude recusou o pedido por faturamento. Confira a conta da assinatura."]);
  const fer = causaDaFalha({ job: { error_code: "provider_unavailable", error: 'O servidor de ferramentas "erp" não conectou (failed).' }, estado: NO_AR, agora: AGORA });
  assertEquals([fer.codigo, fer.texto], ["ferramentas", "o Claude no PC não conseguiu se ligar às ferramentas do sistema. Tente de novo em 1 minuto."]);
  const daPausa = causaDaFalha({ job: null, estado: estado({ pausa: { motivo: "provider_unavailable", ate: null } }), agora: AGORA });
  assertEquals([daPausa.codigo, daPausa.cru], ["ferramentas", "provider_unavailable"]);
  // sem detalhe conhecido no pedido: erro comum, sem inventar a causa
  assertEquals(causaDaFalha({ job: { error_code: "provider_unavailable", error: "Nenhum provider disponível." }, estado: NO_AR, agora: AGORA }).codigo, "erro");
});

Deno.test("PC fora: não houve pedido (ou o prazo venceu na fila) e o programa do assistente está sem sinal", () => {
  const semSinal = estado({ semSinal: true, ultimoSinal: "2026-11-24T10:27:00Z" });
  const semPedido = causaDaFalha({ job: null, estado: semSinal, agora: AGORA });
  assertEquals(semPedido.codigo, "pc_fora");
  assertEquals(semPedido.texto, "o PC da oficina está sem sinal desde as 07:27 (desligado, sem internet ou com o assistente parado). Confira o PC e mande de novo.");
  assertEquals(semPedido.cru, null);
  const prazo = causaDaFalha({ job: { error_code: "deadline_exceeded" }, estado: semSinal, agora: AGORA });
  assertEquals([prazo.codigo, prazo.cru], ["pc_fora", "deadline_exceeded"]);
  // parado desde a véspera: diz o dia
  const vespera = causaDaFalha({ job: null, estado: estado({ semSinal: true, ultimoSinal: "2026-11-23T20:27:00Z" }), agora: AGORA });
  assertStringIncludes(vespera.texto, "sem sinal desde seg 23/11 às 17:27 (desligado");
  // nunca avisou: sem o "desde"
  const nunca = causaDaFalha({ job: null, estado: estado({ semSinal: true, ultimoSinal: null }), agora: AGORA });
  assertEquals(nunca.texto, "o PC da oficina está sem sinal (desligado, sem internet ou com o assistente parado). Confira o PC e mande de novo.");
});

Deno.test("sem sinal vence a pausa: de quem está calado, a pausa publicada é notícia velha", () => {
  const velho = estado({ semSinal: true, ultimoSinal: "2026-11-24T10:27:00Z", pausa: { motivo: "auth_failed", ate: null } });
  assertEquals(causaDaFalha({ job: null, estado: velho, agora: AGORA }).codigo, "pc_fora");
  assertEquals(causaDaFalha({ job: { error_code: "deadline_exceeded" }, estado: velho, agora: AGORA }).codigo, "pc_fora");
  // o programa avisou que estava saindo e ainda não sumiu do sinal: é o mesmo PC fora
  const saindo = causaDaFalha({ job: null, estado: estado({ pausa: { motivo: "worker_shutdown", ate: null } }), agora: AGORA });
  assertEquals([saindo.codigo, saindo.cru], ["pc_fora", "worker_shutdown"]);
});

Deno.test("prazo vencido na fila: a pausa do Claude explica; senão PC ocupado; senão 'não começou a tempo'", () => {
  const job = { error_code: "deadline_exceeded", error: "Ninguém pegou o job antes do prazo." };
  // o caso de 24/11: o login caiu, o Claude entrou em pausa e ninguém pegou o pedido
  const login = causaDaFalha({ job, estado: estado({ pausa: { motivo: "auth_failed", ate: "2026-11-24T12:42:00Z" } }), agora: AGORA });
  assertEquals([login.codigo, login.cru], ["login", "deadline_exceeded"]);
  assertEquals(causaDaFalha({ job, estado: estado({ pausa: { motivo: "rate_limited", ate: "2026-11-26T05:00:00Z" } }), agora: AGORA }).codigo, "limite");
  const ocupado = causaDaFalha({ job, estado: estado({ ocupado: true }), agora: AGORA });
  assertEquals([ocupado.codigo, ocupado.texto], ["pc_ocupado", "o PC estava ocupado com outros pedidos e não começou o seu a tempo. Mande de novo em instantes."]);
  const normal = causaDaFalha({ job, estado: NO_AR, agora: AGORA });
  assertEquals([normal.codigo, normal.texto], ["prazo", "o PC não começou o pedido a tempo (rede ou relógio do PC). Mande de novo em instantes."]);
  // a leitura do estado falhou: o código do pedido decide
  assertEquals(causaDaFalha({ job, estado: null, agora: AGORA }).codigo, "prazo");
  // "ocupado" só explica prazo vencido: sem pedido e com tudo no ar, não há causa a dizer
  assertEquals(causaDaFalha({ job: null, estado: estado({ ocupado: true }), agora: AGORA }).codigo, "erro");
});

Deno.test("tempo máximo: diz quanto era (2 min e 30 s, 5 min) e sugere mandar em partes", () => {
  const de150 = causaDaFalha({ job: { error_code: "timeout", timeout_seconds: 150 }, estado: NO_AR, agora: AGORA });
  assertEquals([de150.codigo, de150.curta], ["tempo", "passou do tempo máximo"]);
  assertEquals(de150.texto, "o pedido passou do tempo máximo (2 min e 30 s) e foi interrompido. Se era um pedido grande, mande em partes.");
  assertStringIncludes(causaDaFalha({ job: { error_code: "timeout", timeout_seconds: 300 }, estado: NO_AR, agora: AGORA }).texto, "tempo máximo (5 min) e foi");
  assertEquals(causaDaFalha({ job: { error_code: "timeout" }, estado: NO_AR, agora: AGORA }).texto, "o pedido passou do tempo máximo e foi interrompido. Se era um pedido grande, mande em partes.");
  assertEquals([duracaoPorExtenso(150), duracaoPorExtenso(300), duracaoPorExtenso(45), duracaoPorExtenso(110)], ["2 min e 30 s", "5 min", "45 s", "1 min e 50 s"]);
  assertEquals([duracaoPorExtenso(null), duracaoPorExtenso(0), duracaoPorExtenso("x"), duracaoPorExtenso(-5)], [null, null, null, null]);
});

Deno.test("sobrecarga e teto por hora do PC", () => {
  const sob = causaDaFalha({ job: { error_code: "overloaded" }, estado: NO_AR, agora: AGORA });
  assertEquals([sob.codigo, sob.texto], ["sobrecarga", "o Claude está sobrecarregado agora. Tente de novo em 1 minuto."]);
  const pausaDoTeto = estado({ pausa: { motivo: "local_quota", ate: "2026-11-24T13:05:00.000Z" } });
  const teto = causaDaFalha({ job: null, estado: pausaDoTeto, agora: AGORA });
  assertEquals([teto.codigo, teto.texto], ["teto_do_pc", "o PC atingiu o teto de pedidos por hora. Libera às 10:05."]);
  assertEquals(causaDaFalha({ job: { error_code: "local_quota" }, estado: pausaDoTeto, agora: AGORA }).texto, "o PC atingiu o teto de pedidos por hora. Libera às 10:05.");
  assertEquals(causaDaFalha({ job: { error_code: "local_quota" }, estado: null, agora: AGORA }).texto, "o PC atingiu o teto de pedidos por hora. Ainda não sei quando libera.");
});

Deno.test("o pedido não entrou na fila, e quem pede não é o titular (o código que o S5 usa)", () => {
  const fila = causaDaFalha({ estado: null, agora: AGORA, motivo: "enfileirar" });
  assertEquals(fila, {
    codigo: "enfileirar", curta: "o pedido não entrou na fila",
    texto: "o pedido não entrou na fila do PC (erro do sistema, já anotado). Tente de novo em instantes.", cru: null,
  });
  const titular = causaDaFalha({ estado: null, agora: AGORA, motivo: "nao_assinante" });
  assertEquals(titular.codigo, "nao_assinante");
  assertEquals(TEXTO_PARA_QUEM_NAO_E_O_TITULAR, "Este assistente funciona pela assinatura Claude do dono e atende só o titular. Fale com o administrador.");
  // é a frase inteira: não leva o "Não consegui responder" na frente
  assertEquals(textoDaFalhaParaODono(titular), TEXTO_PARA_QUEM_NAO_E_O_TITULAR);
  // o motivo vence o que o pedido ou o estado digam
  assertEquals(causaDaFalha({ job: { error_code: "timeout" }, estado: estado({ semSinal: true }), agora: AGORA, motivo: "nao_assinante" }).codigo, "nao_assinante");
});

Deno.test("todo o resto: 'deu um erro no assistente do PC', sem o código na frase (ele fica só para o log)", () => {
  const texto = "deu um erro no assistente do PC. Já ficou anotado; tente de novo em instantes.";
  for (const codigo of ["engine_error", "worker_shutdown", "isolation_violation", "invalid_request", "internal", "policy_denied", "cancelled", "server_error"]) {
    const c = causaDaFalha({ job: { error_code: codigo, error: "detalhe do PC" }, estado: NO_AR, agora: AGORA });
    assertEquals([c.codigo, c.curta, c.texto, c.cru], ["erro", "deu um erro no assistente do PC", texto, codigo], codigo);
    assertEquals(rotuloDaCausaNoLog(c), `erro (${codigo})`);
  }
  for (const job of [{ error_code: null }, {}, { error_code: "  " }]) {
    assertEquals(causaDaFalha({ job, estado: NO_AR, agora: AGORA }).cru, null, JSON.stringify(job));
    assertEquals(causaDaFalha({ job, estado: NO_AR, agora: AGORA }).texto, texto);
  }
  // sem pedido: estado ilegível, ou tudo no ar (o estado mudou entre a pergunta e a leitura), ou pausa sem motivo conhecido
  assertEquals(causaDaFalha({ job: null, estado: null, agora: AGORA }).codigo, "erro");
  assertEquals(causaDaFalha({ job: null, estado: NO_AR, agora: AGORA }).codigo, "erro");
  const isolamento = causaDaFalha({ job: null, estado: estado({ pausa: { motivo: "isolation_violation", ate: null } }), agora: AGORA });
  assertEquals([isolamento.codigo, isolamento.cru], ["erro", "isolation_violation"]);
  assertEquals(rotuloDaCausaNoLog(causaDaFalha({ job: null, estado: estado({ semSinal: true }), agora: AGORA })), "pc_fora");
});

// ─── O que o dono lê: sem termo técnico, sem crédito, sem botão ──────────────────────────────────────────────────────

/** Uma amostra de cada frase que este arquivo sabe escrever. */
function todasAsCausas() {
  const segredo = "C:\\Users\\PC\\.claude\\segredo.json token=abc123";
  const pedidos = [
    "auth_failed", "rate_limited", "provider_unavailable", "timeout", "overloaded", "local_quota", "deadline_exceeded",
    "engine_error", "worker_shutdown", "isolation_violation", "invalid_request", "internal", "policy_denied", "",
  ];
  const estados: Array<EstadoDoMax | null> = [
    null, NO_AR, estado({ semSinal: true }), estado({ semSinal: true, ultimoSinal: "2026-11-23T20:27:00Z" }), estado({ ocupado: true }),
    ...["auth_failed", "rate_limited", "provider_unavailable", "local_quota", "worker_shutdown", "isolation_violation", ""]
      .map((motivo) => estado({ pausa: { motivo, ate: "2026-11-26T05:00:00.000Z" } })),
  ];
  const causas = [
    causaDaFalha({ estado: null, agora: AGORA, motivo: "enfileirar" }),
    causaDaFalha({ estado: null, agora: AGORA, motivo: "nao_assinante" }),
  ];
  for (const e of estados) {
    causas.push(causaDaFalha({ job: null, estado: e, agora: AGORA }));
    for (const error_code of pedidos) {
      for (const error of [segredo, `Assinatura sem crédito/faturamento disponível: ${segredo}`, `O servidor de ferramentas "erp" não conectou (${segredo}).`, `libera em 2026-11-26T05:00:00.000Z. ${segredo}`]) {
        causas.push(causaDaFalha({ job: { error_code, error, timeout_seconds: 150 }, estado: e, agora: AGORA }));
      }
    }
  }
  return { causas, segredo };
}

Deno.test("as frases: toda causa da lista aparece, com a frase curta do mapa exportado (a que o vigia reusa)", () => {
  const { causas } = todasAsCausas();
  assertEquals([...new Set(causas.map((c) => c.codigo))].sort(), [...CODIGOS_DA_CAUSA].sort());
  assertEquals(Object.keys(FRASE_CURTA_DA_CAUSA).sort(), [...CODIGOS_DA_CAUSA].sort());
  for (const c of causas) assertEquals(c.curta, FRASE_CURTA_DA_CAUSA[c.codigo], c.codigo);
  // meia frase que cabe entre parênteses: começa minúscula, sem ponto no fim
  for (const [codigo, curta] of Object.entries(FRASE_CURTA_DA_CAUSA)) {
    assert(/^[a-zà-ú]/.test(curta) && !/[.!?:]$/.test(curta) && curta.length <= 40, `${codigo}: ${curta}`);
  }
  assertEquals(avisoDeQueOClaudeNaoRespondeu(causaDaFalha({ job: { error_code: "timeout" }, estado: null, agora: AGORA })), "⚠️ O Claude não respondeu (passou do tempo máximo).");
});

Deno.test("as frases: nada de crédito, recarga, saldo ou reserva (decisão do dono de 24/11/2026)", () => {
  const { causas } = todasAsCausas();
  const proibido = /cr[eé]dito|recarg|saldo|reserva|openrouter|configur/i;
  for (const c of causas) {
    for (const frase of [c.curta, c.texto, textoDaFalhaParaODono(c), avisoDeQueOClaudeNaoRespondeu(c)]) {
      assert(!proibido.test(frase), `${c.codigo}: ${frase}`);
    }
  }
});

Deno.test("as frases: sem termo técnico, sem código cru, sem o texto do erro do PC e sem botão", () => {
  const { causas, segredo } = todasAsCausas();
  const tecnico = /gateway|\bjobs?\b|worker|provider|provedor|claude-local|\bmcp\b|\bapi\b|deadline|timeout|[a-z]_[a-z]/i;
  for (const c of causas) {
    for (const frase of [c.curta, c.texto, textoDaFalhaParaODono(c), avisoDeQueOClaudeNaoRespondeu(c)]) {
      assert(!tecnico.test(frase), `termo técnico em ${c.codigo}: ${frase}`);
      assert(!frase.includes("segredo") && !frase.includes("abc123") && !frase.includes(segredo), `texto do erro em ${c.codigo}: ${frase}`);
      assert(!/\[|\]|responda|toque|clique|bot[aã]o/i.test(frase), `convite a botão ou resposta em ${c.codigo}: ${frase}`);
    }
    // curto: cabe numa tela do WhatsApp
    assert(textoDaFalhaParaODono(c).length <= 200, `${c.codigo}: ${textoDaFalhaParaODono(c).length} caracteres`);
  }
});

// ─── A causa de uma falha de agora (o que o ai-agent chama) ──────────────────────────────────────────────────────────

Deno.test("causa de agora: lê o estado com o corte de 45 s; com motivo dado, nem lê o banco", async () => {
  // um minuto sem sinal: para o turno do dono, o PC está fora
  const fora = await lerCausaDaFalha(banco({ data: programas({ assistenteHa: 60 }) }).admin, { agora: AGORA });
  assertEquals(fora.codigo, "pc_fora");
  assertStringIncludes(textoDaFalhaParaODono(fora), "⚠️ Não consegui responder: o PC da oficina está sem sinal desde as 09:31 (");
  // com sinal e em pausa por login
  const login = await lerCausaDaFalha(banco({ data: programas({ claude: { available: false, reason: "auth_failed", until: "2026-11-24T12:42:00.000Z" } }) }).admin, { agora: AGORA });
  assertEquals(login.codigo, "login");
  // o pedido que falhou decide antes do estado
  const tempo = await lerCausaDaFalha(banco({ data: programas({ assistenteHa: 60 }) }).admin, { job: { error_code: "timeout", timeout_seconds: 150 }, agora: AGORA });
  assertEquals(tempo.codigo, "tempo");
  // a leitura falhou: cai na frase do código do pedido, sem lançar
  assertEquals((await lerCausaDaFalha(banco("lanca").admin, { job: { error_code: "deadline_exceeded" }, agora: AGORA })).codigo, "prazo");
  assertEquals((await lerCausaDaFalha(banco({ error: { message: "x" } }).admin, { agora: AGORA })).codigo, "erro");
  // motivo dado: o banco não é consultado
  const semBanco = { from() { throw new Error("não era para ler"); } };
  assertEquals((await lerCausaDaFalha(semBanco, { motivo: "enfileirar", agora: AGORA })).codigo, "enfileirar");
  assertEquals((await lerCausaDaFalha(semBanco, { motivo: "nao_assinante", agora: AGORA })).codigo, "nao_assinante");
});

Deno.test("causa de agora: nunca lança (roda também quando a reserva ainda vai responder) — o que der errado vira o erro comum", async () => {
  const torto = { get error_code(): string { throw new Error("bum"); } };
  const c = await lerCausaDaFalha(banco({ data: programas() }).admin, { job: torto, agora: AGORA });
  assertEquals([c.codigo, c.cru], ["erro", null]);
  assertEquals(textoDaFalhaParaODono(c), "⚠️ Não consegui responder: deu um erro no assistente do PC. Já ficou anotado; tente de novo em instantes.");
  // relógio inválido também não derruba
  const semRelogio = await lerCausaDaFalha(banco({ data: programas({ assistenteHa: 3600 }) }).admin, { agora: new Date("lixo") });
  assert(CODIGOS_DA_CAUSA.includes(semRelogio.codigo));
});

// ─── Revisão da leva B (25/11/2026): o Claude já estava fora ANTES do pedido, com a reserva ligada ───────────────────
// O caso: o login do Claude cai no PC, o WhatsApp segue de pé e o dono manda "oi". O turno nem vira pedido (o Claude está
// em pausa), cai no laço da reserva e a reserva falha. Até aqui o dono lia só "erro do sistema"; o registro saía com o
// mesmo nome do turno que leva a causa, e o vigia de queda concluía que ele já sabia.

Deno.test("revisão B: Claude em pausa por login, reserva ligada e também falhando — a resposta começa pela causa do Claude", async () => {
  // o que o ai-agent faz no ramo "Max fora": lê a causa do estado do PC, sem pedido nenhum
  const emPausa = programas({ claude: { available: false, reason: "auth_failed", until: "2026-11-24T12:42:00.000Z" } });
  const causa = await lerCausaDaFalha(banco({ data: emPausa }).admin, { agora: AGORA });
  assertEquals([causa.codigo, causa.cru], ["login", "auth_failed"]);
  const r = respostaDoTurnoNoWhatsApp(
    { texto: "", error: "OpenRouter 402 (créditos insuficientes na conta)", aviso: avisoDeQueOClaudeNaoRespondeu(causa) },
    {},
  );
  assert(r.replyText.startsWith("⚠️ O Claude não respondeu (o login do Claude caiu)."), r.replyText);
  assertEquals(r.replyText, `⚠️ O Claude não respondeu (o login do Claude caiu).\n\n⚠️ ${ERRO_DO_SISTEMA_PARA_O_DONO}`);
  // nada de crédito, reserva ou código cru (decisão do dono de 24/11/2026)
  assert(!/cr[eé]dito|recarg|saldo|reserva|openrouter|auth_failed/i.test(r.replyText), r.replyText);
  // o PC sem sinal e o pedido que não entrou na fila saem do mesmo jeito
  const semSinal = await lerCausaDaFalha(banco({ data: programas({ assistenteHa: 60 }) }).admin, { agora: AGORA });
  assertEquals(avisoDeQueOClaudeNaoRespondeu(semSinal), "⚠️ O Claude não respondeu (o PC da oficina está sem sinal).");
  const fila = await lerCausaDaFalha(banco("lanca").admin, { motivo: "enfileirar", agora: AGORA });
  assertEquals(avisoDeQueOClaudeNaoRespondeu(fila), "⚠️ O Claude não respondeu (o pedido não entrou na fila).");
});

Deno.test("revisão B: o registro do turno sem resposta tem dois nomes — com a causa do Claude na resposta e sem ela", () => {
  assertEquals([TURNO_SEM_RESPOSTA, TURNO_SEM_RESPOSTA_COM_CAUSA], ["turno_whatsapp", "turno_whatsapp_com_causa"]);
  const causa = causaDaFalha({ job: null, estado: estado({ pausa: { motivo: "auth_failed", ate: null } }), agora: AGORA });
  assertEquals(ondeDoTurnoSemResposta(causa), "turno_whatsapp_com_causa");
  // o turno que nem passou pelo Claude (o canal não está nele, ou quem pede não é o titular): o dono leu só o erro comum
  assertEquals(ondeDoTurnoSemResposta(undefined), "turno_whatsapp");
  assertEquals(ondeDoTurnoSemResposta(null), "turno_whatsapp");
  // a causa que não se sabe dizer melhor ainda é causa dita ("deu um erro no assistente do PC")
  assertEquals(ondeDoTurnoSemResposta(causaDaFalha({ job: null, estado: null, agora: AGORA })), "turno_whatsapp_com_causa");
});
