// O rastro por mensagem recebida do dono (pacote 1, C4, 25/11/2026).
// O que se protege: cada saída do tratador do WhatsApp cai na camada certa; o que vai ao banco só leva rótulos e ids
// (nunca o texto da mensagem, o telefone ou o PIN, nem que uma camada devolva texto por engano); a gravação que falha
// não lança, e a resposta do turno não espera por ela.
import { assert, assertEquals, assertFalse } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  CAMADAS_DA_ROTA,
  detalheComCodigo,
  detalheDaEntrega,
  linhaDaRota,
  noFundoDaRota,
  rastrearResposta,
  registrarRota,
  rotaDaResposta,
  rotuloDaRota,
} from "./rota-da-mensagem.ts";

const SESSAO = "aaaaaaaa-0000-4000-8000-000000000001";
const MENSAGEM = "bbbbbbbb-0000-4000-8000-000000000002";
const JOB = "cccccccc-0000-4000-8000-000000000003";

// O que um dono escreveria, o telefone dele e um PIN: nada disto pode aparecer numa linha gravada.
const TEXTO = "manda o orçamento da lancha pro João";
const TELEFONE = "5547999990000";
const PIN = "7391";

type Linha = ReturnType<typeof linhaDaRota>;

/** Banco falso: guarda os inserts; `falha` escolhe como a gravação dá errado. */
function bancoFalso(op: { falha?: "lanca" | "erro" | "rejeita"; segurar?: Promise<void> } = {}) {
  const inserts: Array<{ tabela: string; linha: Linha }> = [];
  const admin = {
    from(tabela: string) {
      if (op.falha === "lanca") throw new Error(`sem banco: ${TEXTO}`);
      return {
        async insert(linha: Linha) {
          await op.segurar;
          if (op.falha === "rejeita") throw new TypeError(`rede caiu: ${TEXTO}`);
          inserts.push({ tabela, linha });
          return op.falha === "erro"
            ? { error: { code: "23514", message: `Failing row contains (${TEXTO})`, details: TELEFONE } }
            : { error: null };
        },
      };
    },
  };
  return { admin, inserts };
}

/** Roda com um EdgeRuntime.waitUntil que guarda as promessas do fundo, e captura o console.error. */
async function comFundo<T>(fn: (fundo: Promise<unknown>[], erros: string[]) => Promise<T> | T): Promise<T> {
  const g = globalThis as unknown as { EdgeRuntime?: unknown };
  const runtimeOriginal = g.EdgeRuntime;
  const erroOriginal = console.error;
  const fundo: Promise<unknown>[] = [];
  const erros: string[] = [];
  g.EdgeRuntime = { waitUntil: (p: Promise<unknown>) => fundo.push(p) };
  console.error = (...a: unknown[]) => { erros.push(a.map(String).join(" ")); };
  try {
    return await fn(fundo, erros);
  } finally {
    await Promise.all(fundo);
    g.EdgeRuntime = runtimeOriginal;
    console.error = erroOriginal;
  }
}

/** A resposta como o jr do ai-agent monta: sempre HTTP 200, com o status de verdade no cabeçalho. */
const jr = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status: 200, headers: { "Content-Type": "application/json", "X-Actual-Status": String(status) } });

// ─── rotaDaResposta: uma camada para cada saída do tratador ─────────────────────────────────────────────────────────────

Deno.test("rotaDaResposta: cada saída do tratador do WhatsApp cai na camada dela, com o comando como detalhe", () => {
  const casos: Array<[Record<string, unknown>, number, string, string | null, string | null]> = [
    [{ ok: true, skipped: "rate_limited" }, 200, "limite_por_minuto", null, null],
    [{ error: "Usuário não autorizado para o canal WhatsApp" }, 403, "nao_autorizado", null, null],
    [{ ok: true, orcamento: "segura" }, 200, "orcamento", "segura", null],
    [{ ok: true, parceiro: "parceiro" }, 200, "parceiro", "parceiro", null],
    [{ ok: true, retorno: "pessoal_desfaz" }, 200, "retorno", "pessoal_desfaz", null],
    [{ ok: true, travado: "comprovante" }, 200, "trava_comprovante", null, null],
    [{ ok: true, travado: "agenda" }, 200, "trava_agenda", null, null],
    [{ ok: true, confirmacao: "recusar_ajuste" }, 200, "confirmacao", "recusar_ajuste", null],
    [{ ok: true, confirmacao: "reapresentada" }, 200, "confirmacao", "reapresentada", null],
    [{ ok: true, confirmacao: "resolvida" }, 200, "confirmacao", "resolvida", null],
    [{ ok: true, confirmacao: "nada_esperando" }, 200, "confirmacao", "nada_esperando", null],
    [{ ok: true, pin_na_frase: true }, 200, "pin_na_frase", null, null],
    [{ ok: true, secretario: "lista" }, 200, "secretario", "lista", null],
    [{ ok: true, agenda: "gravar" }, 200, "agenda", "gravar", null],
    [{ ok: true, atalho: "pdf" }, 200, "atalho_pdf", "pdf", null],
    [{ ok: true, atalho: "impressao" }, 200, "atalho_pdf", "impressao", null],
    // o turno que foi para a fila do Claude devolve a sessão E o pedido: vale o pedido
    [{ ok: true, session_id: SESSAO, claude_max: JOB }, 200, "modelo_max", null, JOB],
    [{ ok: true, entregue: "aviso", causa: "login" }, 200, "aviso_falha", "login", null],
    [{ ok: true, entregue: "aviso", causa: "nao_assinante" }, 200, "aviso_falha", "nao_assinante", null],
    [{ ok: true, session_id: SESSAO }, 200, "modelo_openrouter", null, null],
    [{ error: "internal error" }, 500, "erro", null, null],
    [{ ok: true }, 200, "desconhecida", null, null],
    [{ error: "phone_normalized, app_user_id e text são obrigatórios" }, 400, "desconhecida", "http_400", null],
    // reservadas para o "um turno por vez" (C1, adiado): ninguém devolve ainda
    [{ ok: true, em_espera: 2 }, 200, "em_espera", "posicao_2", null],
    [{ ok: true, espera: "resposta_antiga" }, 200, "resposta_antiga", null, null],
  ];
  for (const [corpo, status, camada, detalhe, jobId] of casos) {
    assertEquals(rotaDaResposta(corpo, status), { camada, detalhe, jobId } as ReturnType<typeof rotaDaResposta>, JSON.stringify(corpo));
  }
  // toda camada devolvida existe na lista fechada
  for (const [corpo, status] of casos) assert((CAMADAS_DA_ROTA as readonly string[]).includes(rotaDaResposta(corpo, status).camada));
});

Deno.test("rotaDaResposta: corpo vazio, nulo ou que não é objeto não lança e sai pelo status", () => {
  assertEquals(rotaDaResposta(null, 200).camada, "desconhecida");
  assertEquals(rotaDaResposta(undefined, 500).camada, "erro");
  assertEquals(rotaDaResposta("texto" as unknown as Record<string, unknown>, 403).camada, "nao_autorizado");
  assertEquals(rotaDaResposta({}, 200), { camada: "desconhecida", detalhe: null, jobId: null });
});

Deno.test("rotaDaResposta: se uma camada devolver texto, telefone ou PIN no lugar do comando, o detalhe fica vazio", () => {
  for (const sujo of [TEXTO, TELEFONE, PIN, `sim ${PIN}`, `sim_${PIN}`, "2 B 7391", "não quero", "", " ", 7391, { comando: "x" }]) {
    for (const chave of ["orcamento", "parceiro", "retorno", "confirmacao", "secretario", "agenda", "atalho"]) {
      const r = rotaDaResposta({ ok: true, [chave]: sujo }, 200);
      assertEquals(r.detalhe, null, `${chave}: ${JSON.stringify(sujo)}`);
    }
    assertEquals(rotaDaResposta({ ok: true, entregue: "aviso", causa: sujo }, 200).detalhe, null);
  }
  // o id do pedido que não é uuid também não passa
  assertEquals(rotaDaResposta({ ok: true, claude_max: TEXTO }, 200), { camada: "modelo_max", detalhe: null, jobId: null });
  assertEquals(rotaDaResposta({ ok: true, em_espera: TELEFONE }, 200).detalhe, null);
});

// ─── rotuloDaRota: só rótulo ────────────────────────────────────────────────────────────────────────────────────────────

Deno.test("rotuloDaRota: rótulo passa; frase, acento, número solto, telefone e número com tamanho de PIN não passam", () => {
  for (const ok of ["segura", "pessoal_desfaz", "fora_ate", "aviso:login", "interrompido:deadline_exceeded", "http_546", "posicao_3", "midia", "nao_entendi"]) {
    assertEquals(rotuloDaRota(ok), ok);
  }
  for (const nao of [
    TEXTO, TELEFONE, PIN, "739", "sim 7391", "sim_7391", "pin:7391", "47 99999-0000", "tel_5547999990000", "orçamento", "a b", "",
    " segura", "_x", "x".repeat(61), null, undefined, 7391, true, {}, ["segura"],
  ]) {
    assertEquals(rotuloDaRota(nao), null, JSON.stringify(nao));
  }
});

Deno.test("detalheComCodigo e detalheDaEntrega: o que a entrega mandou, em rótulo", () => {
  assertEquals(detalheComCodigo("aviso", "login"), "aviso:login");
  assertEquals(detalheComCodigo("interrompido", "deadline_exceeded"), "interrompido:deadline_exceeded");
  // código que não é rótulo (um erro cru, por exemplo) não entra
  assertEquals(detalheComCodigo("aviso", `erro em C:/Users/dono: ${TEXTO}`), "aviso:outro");
  assertEquals(detalheComCodigo("interrompido", null), "interrompido:outro");

  assertEquals(detalheDaEntrega({}), "resposta");
  assertEquals(detalheDaEntrega({ interrupcao: {} }), "resposta");
  assertEquals(detalheDaEntrega({ interrupcao: { proposal: { title: TEXTO } } }), "cartao");
  assertEquals(detalheDaEntrega({ interrupcao: { options: { question: TEXTO } } }), "lista");
  assertEquals(detalheDaEntrega({ interrupcao: { fluxo: true } }), "fluxo");
  // a mesma ordem de respostaDoTurnoNoWhatsApp: a lista vence o cartão, o cartão vence o fluxo
  assertEquals(detalheDaEntrega({ interrupcao: { options: {}, proposal: {}, fluxo: true } }), "lista");
  assertEquals(detalheDaEntrega({ interrupcao: { proposal: {}, fluxo: true } }), "cartao");
  // o turno que parou no meio diz o código, tenha ou não deixado cartão
  assertEquals(detalheDaEntrega({ interrompido: true, codigo: "timeout", interrupcao: { proposal: {} } }), "interrompido:timeout");
  // todo detalhe da entrega é rótulo
  for (const d of ["resposta", "cartao", "lista", "fluxo", "reserva", "interrompido:timeout", "aviso:pc_fora"]) assertEquals(rotuloDaRota(d), d);
});

// ─── linhaDaRota: o que vai ao banco ────────────────────────────────────────────────────────────────────────────────────

Deno.test("linhaDaRota: event_type rota:<camada>, ator e categoria 'channel', payload só com ids, canal, detalhe e tempo", () => {
  const linha = linhaDaRota({ sessionId: SESSAO, mensagemId: MENSAGEM, canal: "whatsapp", camada: "retorno", detalhe: "segura", ms: 41.6 });
  assertEquals(linha, {
    session_id: SESSAO,
    actor_kind: "channel",
    event_category: "channel",
    event_type: "rota:retorno",
    payload: { mensagem_id: MENSAGEM, canal: "whatsapp", detalhe: "segura", job_id: null, ms: 42 },
  });
  const entrega = linhaDaRota({ sessionId: SESSAO, mensagemId: null, canal: "whatsapp", camada: "entrega", jobId: JOB, detalhe: "cartao" });
  assertEquals(entrega.event_type, "rota:entrega");
  assertEquals(entrega.payload, { mensagem_id: null, canal: "whatsapp", detalhe: "cartao", job_id: JOB, ms: null });
  // sem sessão (limite por minuto, webhook): a linha existe do mesmo jeito
  assertEquals(linhaDaRota({ sessionId: null, mensagemId: MENSAGEM, canal: "whatsapp", camada: "limite_por_minuto" }).session_id, null);
  // da_espera só quando é verdade (C1, adiado)
  assertEquals(linhaDaRota({ sessionId: SESSAO, mensagemId: MENSAGEM, canal: "whatsapp", camada: "agenda", daEspera: true }).payload.da_espera, true);
  assertFalse("da_espera" in linhaDaRota({ sessionId: SESSAO, mensagemId: MENSAGEM, canal: "whatsapp", camada: "agenda", daEspera: false }).payload);
});

Deno.test("linhaDaRota: o payload nunca tem a chave do texto, do telefone nem a chave `turno`", () => {
  for (const camada of CAMADAS_DA_ROTA) {
    const { payload } = linhaDaRota({ sessionId: SESSAO, mensagemId: MENSAGEM, canal: "whatsapp", camada, detalhe: "x", jobId: JOB, ms: 1, daEspera: true });
    assertEquals(Object.keys(payload).sort(), ["canal", "da_espera", "detalhe", "job_id", "mensagem_id", "ms"], camada);
    for (const proibida of ["texto", "text", "body", "phone", "phone_normalized", "telefone", "pin", "turno", "args"]) {
      assertFalse(proibida in payload, `${camada}: ${proibida}`);
    }
  }
});

Deno.test("linhaDaRota: texto, telefone ou PIN em QUALQUER campo não chega à linha", () => {
  for (const sujo of [TEXTO, TELEFONE, PIN, `sim ${PIN}`]) {
    const linha = linhaDaRota({
      sessionId: sujo, mensagemId: sujo, canal: "whatsapp", camada: sujo as never, detalhe: sujo, jobId: sujo,
      ms: sujo as unknown as number,
    });
    const gravado = JSON.stringify(linha);
    assertFalse(gravado.includes(TEXTO), gravado);
    assertFalse(gravado.includes(TELEFONE), gravado);
    assertFalse(gravado.includes(PIN), gravado);
    assertEquals(linha, {
      session_id: null, actor_kind: "channel", event_category: "channel", event_type: "rota:desconhecida",
      payload: { mensagem_id: null, canal: "whatsapp", detalhe: null, job_id: null, ms: null },
    });
  }
  // tempo negativo, infinito ou que não é número fica nulo
  for (const ms of [-1, Infinity, NaN]) {
    assertEquals(linhaDaRota({ sessionId: SESSAO, mensagemId: MENSAGEM, canal: "whatsapp", camada: "erro", ms }).payload.ms, null);
  }
});

// ─── registrarRota: grava uma linha e nunca lança ───────────────────────────────────────────────────────────────────────

Deno.test("registrarRota: uma linha em ai_operator_audit", async () => {
  const { admin, inserts } = bancoFalso();
  await registrarRota(admin, { sessionId: SESSAO, mensagemId: MENSAGEM, canal: "whatsapp", camada: "modelo_max", jobId: JOB, ms: 310 });
  assertEquals(inserts.length, 1);
  assertEquals(inserts[0].tabela, "ai_operator_audit");
  assertEquals(inserts[0].linha.event_type, "rota:modelo_max");
  assertEquals(inserts[0].linha.payload, { mensagem_id: MENSAGEM, canal: "whatsapp", detalhe: null, job_id: JOB, ms: 310 });
});

Deno.test("registrarRota: banco que lança, que rejeita ou que devolve erro não derruba nada, e o console só leva o código", async () => {
  await comFundo(async (_fundo, erros) => {
    for (const falha of ["lanca", "rejeita", "erro"] as const) {
      const { admin } = bancoFalso({ falha });
      // não lança: se lançasse, o teste quebraria aqui
      await registrarRota(admin, { sessionId: SESSAO, mensagemId: MENSAGEM, canal: "whatsapp", camada: "retorno", detalhe: "segura" });
    }
    await registrarRota(null, { sessionId: SESSAO, mensagemId: MENSAGEM, canal: "whatsapp", camada: "retorno" });
    assertEquals(erros.length, 4, "cada falha deixa uma linha no console");
    for (const linha of erros) {
      assert(linha.startsWith("[rota] rota:retorno não foi gravada: "), linha);
      // a mensagem do erro (que aqui carrega o texto e o telefone) nunca vai ao console
      assertFalse(linha.includes(TEXTO) || linha.includes(TELEFONE) || linha.includes("Failing row"), linha);
    }
    assert(erros[2].endsWith(": 23514"), "do erro do banco, só o código");
  });
});

// ─── rastrearResposta: lê a rota da resposta do tratador, no fundo ─────────────────────────────────────────────────────

Deno.test("rastrearResposta: a rota sai da própria resposta (corpo + status de verdade) e a resposta segue inteira", async () => {
  const { admin, inserts } = bancoFalso();
  await comFundo(async (fundo) => {
    const res = jr({ ok: true, retorno: "segura" });
    rastrearResposta(admin, res, { sessionId: SESSAO, mensagemId: MENSAGEM, ms: 12, status: 200 });
    assertEquals(fundo.length, 1, "a gravação foi entregue ao waitUntil");
    // quem responde ainda consegue ler o corpo: a rota leu uma cópia
    assertEquals(await res.json(), { ok: true, retorno: "segura" });
    await Promise.all(fundo);
    assertEquals(inserts.map((i) => [i.linha.event_type, i.linha.payload.detalhe, i.linha.payload.mensagem_id, i.linha.payload.ms, i.linha.session_id]), [
      ["rota:retorno", "segura", MENSAGEM, 12, SESSAO],
    ]);
  });
});

Deno.test("rastrearResposta: 403 pelo status do cabeçalho, turno que lançou = erro, corpo que não é JSON sai pelo status", async () => {
  const { admin, inserts } = bancoFalso();
  await comFundo(async (fundo) => {
    rastrearResposta(admin, jr({ error: "Usuário não autorizado para o canal WhatsApp" }, 403), { sessionId: null, mensagemId: MENSAGEM, status: 403 });
    rastrearResposta(admin, null, { sessionId: SESSAO, mensagemId: MENSAGEM, ms: 5 });
    rastrearResposta(admin, new Response("<html>502</html>", { status: 502 }), { sessionId: SESSAO, mensagemId: null });
    rastrearResposta(admin, jr({ ok: true, skipped: "rate_limited" }), { sessionId: null, mensagemId: null, status: 200 });
    await Promise.all(fundo);
    assertEquals(inserts.map((i) => i.linha.event_type).sort(), ["rota:erro", "rota:erro", "rota:limite_por_minuto", "rota:nao_autorizado"]);
    // quem chama sem o id da mensagem (o acompanhamento de conversas) deixa a linha sem mensagem_id
    assertEquals(inserts.find((i) => i.linha.event_type === "rota:limite_por_minuto")?.linha.payload.mensagem_id, null);
  });
});

Deno.test("rastrearResposta: não espera a gravação (volta na hora com o banco parado) e a gravação que falha não lança", async () => {
  let soltar: () => void = () => {};
  const segurar = new Promise<void>((ok) => { soltar = ok; });
  const parado = bancoFalso({ segurar });
  await comFundo(async (fundo, erros) => {
    const antes = Date.now();
    // síncrona: não devolve promessa para quem responde esperar
    const devolvido: void = rastrearResposta(parado.admin, jr({ ok: true, agenda: "ver" }), { sessionId: SESSAO, mensagemId: MENSAGEM, status: 200 });
    assertEquals(devolvido, undefined);
    assert(Date.now() - antes < 50, "voltou sem esperar o banco");
    await new Promise((ok) => setTimeout(ok, 20));
    assertEquals(parado.inserts.length, 0, "a gravação ainda está parada, e o turno já seguiu");
    soltar();
    await Promise.all(fundo);
    assertEquals(parado.inserts.length, 1);

    // o banco que lança, rejeita ou devolve erro: nada sobe, nem como rejeição solta
    for (const falha of ["lanca", "rejeita", "erro"] as const) {
      rastrearResposta(bancoFalso({ falha }).admin, jr({ ok: true, agenda: "ver" }), { sessionId: SESSAO, mensagemId: MENSAGEM, status: 200 });
    }
    rastrearResposta(null, jr({ ok: true }), { sessionId: SESSAO, mensagemId: MENSAGEM });
    await Promise.all(fundo);
    assertEquals(erros.length, 4);
    for (const linha of erros) assertFalse(linha.includes(TEXTO) || linha.includes(TELEFONE), linha);
  });
});

Deno.test("rastrearResposta: resposta cujo corpo já foi lido não derruba o turno, e a linha sai só pelo status", async () => {
  const { admin, inserts } = bancoFalso();
  await comFundo(async (fundo, erros) => {
    const res = jr({ ok: true, agenda: "ver" });
    await res.text(); // corpo consumido: clone() lança
    rastrearResposta(admin, res, { sessionId: SESSAO, mensagemId: MENSAGEM, status: 200 });
    const quebrada = { get status(): number { throw new Error(`não é resposta: ${TEXTO}`); } } as unknown as Response;
    rastrearResposta(admin, quebrada, { sessionId: SESSAO, mensagemId: MENSAGEM });
    await Promise.all(fundo);
    assertEquals(inserts.map((i) => [i.linha.event_type, i.linha.payload.mensagem_id]), [["rota:desconhecida", MENSAGEM]]);
    assertEquals(erros, ["[rota] a resposta do turno não pôde ser lida: Error"]);
  });
});

Deno.test("noFundoDaRota: com waitUntil a promessa vai para ele; sem ele segue sozinha; a que rejeita não vira erro solto", async () => {
  await comFundo(async (fundo) => {
    noFundoDaRota(Promise.resolve("ok"));
    noFundoDaRota(Promise.reject(new Error("falhou")));
    assertEquals(fundo.length, 2);
    assertEquals(await Promise.all(fundo), ["ok", null]);
  });
  const g = globalThis as unknown as { EdgeRuntime?: unknown };
  const original = g.EdgeRuntime;
  try {
    g.EdgeRuntime = undefined;
    noFundoDaRota(Promise.reject(new Error("falhou sem runtime")));
    g.EdgeRuntime = { waitUntil: () => { throw new Error("runtime quebrado"); } };
    noFundoDaRota(Promise.resolve());
    await new Promise((ok) => setTimeout(ok, 5));
  } finally {
    g.EdgeRuntime = original;
  }
});
