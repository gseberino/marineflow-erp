// Retorno rápido, F4 (P11.3): a camada do parceiro, com banco falso. Não importa _shared/ai/ (isolamento_test.ts varre
// esta pasta): tudo o que ela precisa chega por parâmetro, como na camada da F2. Frases e números inventados (4321, 7391).
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  camadaDoParceiro,
  type CartaoDoParceiroVivo,
  type DependenciasDoParceiro,
  ehPalavraDoParceiroLigada,
  P13,
  p14,
  R15_PARCEIRO,
} from "./camada.ts";

const CARTAO: CartaoDoParceiroVivo = { id: "cp-1", estado: "vivo", pendencia_id: "pp-1", letras: { "1": ["A", "R"], "2": [], "3": ["C", "P", "R"] } };

type Registro = { rpcs: Array<{ fn: string; args: Record<string, unknown> }>; confirmados: string[]; donos: number };

function deps(
  o: Partial<DependenciasDoParceiro> & {
    cartao?: CartaoDoParceiroVivo | null;
    retornoVivo?: boolean;
    ponteiroAtual?: string | null;
    resposta?: unknown;
    dono?: boolean;
  } = {},
): { d: DependenciasDoParceiro; reg: Registro } {
  const reg: Registro = { rpcs: [], confirmados: [], donos: 0 };
  const d: DependenciasDoParceiro = {
    autor: "dono-1",
    ehDoDono: o.ehDoDono ?? (() => {
      reg.donos++;
      return Promise.resolve(o.dono ?? true);
    }),
    rpc: o.rpc ?? ((fn, args) => {
      reg.rpcs.push({ fn, args });
      return Promise.resolve({ data: o.resposta ?? { ok: true, texto: "feito" }, error: null });
    }),
    cartaoVivo: o.cartaoVivo ?? (() => Promise.resolve(o.cartao === undefined ? CARTAO : o.cartao)),
    cartaoDoRetornoVivo: o.cartaoDoRetornoVivo ?? (() => Promise.resolve(o.retornoVivo ?? false)),
    ponteiro: o.ponteiro ?? (() => Promise.resolve(o.ponteiroAtual === undefined ? "pp-1" : o.ponteiroAtual)),
    tituloDoPonteiro: o.tituloDoPonteiro ?? (() => Promise.resolve("Enviar lembrete")),
    confirmar: o.confirmar ?? ((pin) => {
      reg.confirmados.push(pin);
      return Promise.resolve();
    }),
  };
  return { d, reg };
}

Deno.test("cada palavra chama a RPC certa, uma vez, com o autor só onde a assinatura pede e nunca com o PIN", async () => {
  const casos: Array<[string, string, Record<string, unknown>]> = [
    ["parceiro", "parceiro_cartao_abrir", { p_gatilho: "puxar" }],
    ["ver parceiro", "parceiro_cartao_abrir", { p_gatilho: "puxar" }],
    ["parceiro 74", "parceiro_cartao_abrir_os", { p_sigla: null, p_numero: "74", p_autor: "dono-1" }],
    ["parceiro mp OS-00074", "parceiro_cartao_abrir_os", { p_sigla: "mp", p_numero: "OS-00074", p_autor: "dono-1" }],
    ["1 tira 2", "parceiro_decidir_dito", { p_comando: { comando: "tira_linha", n: 1, linha: 2 }, p_autor: "dono-1" }],
    ["1 sabe 2", "parceiro_decidir_dito", { p_comando: { comando: "sabe", n: 1, linha: 2 }, p_autor: "dono-1" }],
    ["1 a", "parceiro_decidir_dito", { p_comando: { comando: "escolher", n: 1, letra: "A", resto: null }, p_autor: "dono-1" }],
    ["só 1 e 3", "parceiro_decidir_dito", { p_comando: { comando: "so", ns: [1, 3] }, p_autor: "dono-1" }],
    ["sim sem 2", "parceiro_decidir_dito", { p_comando: { comando: "sem", ns: [2] }, p_autor: "dono-1" }],
    ["não 2", "parceiro_decidir_dito", { p_comando: { comando: "tirar", ns: [2] }, p_autor: "dono-1" }],
    ["ver 1", "parceiro_decidir_dito", { p_comando: { comando: "ver", n: 1 }, p_autor: "dono-1" }],
    ["resolvido 3", "parceiro_decidir_dito", { p_comando: { comando: "resolvido", n: 3 }, p_autor: "dono-1" }],
    ["3 r sim 7391", "parceiro_decidir_dito", { p_comando: { comando: "escolher", n: 3, letra: "R", resto: null }, p_autor: "dono-1" }],
    ["só 3 sim 4321", "parceiro_decidir_dito", { p_comando: { comando: "so", ns: [3] }, p_autor: "dono-1" }],
  ];
  for (const [texto, fn, args] of casos) {
    const { d, reg } = deps();
    const r = await camadaDoParceiro(texto, d);
    assert(r !== null, texto);
    assertEquals(reg.rpcs.length, 1, texto);
    assertEquals(reg.rpcs[0].fn, fn, texto);
    assertEquals(reg.rpcs[0].args, args, texto);
    const dito = JSON.stringify(reg.rpcs[0].args);
    assert(!dito.includes("7391") && !dito.includes("4321"), `PIN na RPC: ${texto}`);
  }
});

Deno.test("só o dono: de outro número, nada é lido e o texto segue", async () => {
  for (const t of ["parceiro", "parceiro 74", "1 tira 2", "1 a", "não 2", "3 r sim 7391"]) {
    const { d, reg } = deps({ dono: false });
    assertEquals(await camadaDoParceiro(t, d), null, t);
    assertEquals(reg.rpcs.length, 0, t);
    assertEquals(reg.confirmados.length, 0, t);
  }
  const { d } = deps({ ehDoDono: () => Promise.reject(new Error("caiu")) });
  assertEquals(await camadaDoParceiro("parceiro", d), null, "erro ao ler o dono = não é o dono");
});

Deno.test("sem cartão do parceiro vivo, as palavras de cartão seguem à camada da F2", async () => {
  for (const t of ["1 a", "só 2", "não 2", "ver 1", "resolvido 1", "1 tira 2", "1 sabe 2", "1 a sim 7391"]) {
    const { d, reg } = deps({ cartao: null });
    assertEquals(await camadaDoParceiro(t, d), null, t);
    assertEquals(reg.rpcs.length, 0, t);
    assertEquals(reg.confirmados.length, 0, t);
  }
});

Deno.test("com o cartão da F2 vivo, o leitor da F2 é dele: a camada do parceiro devolve null", async () => {
  for (const t of ["1 a", "só 2", "não 2", "ver 1", "resolvido 1", "1 a sim 7391"]) {
    const { d, reg } = deps({ retornoVivo: true });
    assertEquals(await camadaDoParceiro(t, d), null, t);
    assertEquals(reg.rpcs.length, 0, t);
  }
});

Deno.test("as palavras próprias e as que não são de cartão não leem o cartão da F2", async () => {
  // *parceiro* e *parceiro 74* abrem com ou sem cartão; a trava de ocupado é do SQL
  for (const cartao of [null, CARTAO]) {
    for (const t of ["parceiro", "parceiro 74"]) {
      const { d, reg } = deps({ cartao, cartaoDoRetornoVivo: () => Promise.reject(new Error("não devia ler")) });
      assert((await camadaDoParceiro(t, d)) !== null, t);
      assertEquals(reg.rpcs.length, 1, t);
    }
  }
  // dita, pessoal, retorno, segura: a F2 continua com elas
  for (const t of ["dita 2 pode buscar", "pessoal 2", "retorno", "segura tudo", "segura pátio", "libera Rodrigo"]) {
    const { d, reg } = deps();
    assertEquals(await camadaDoParceiro(t, d), null, t);
    assertEquals(reg.rpcs.length, 0, t);
  }
});

Deno.test("o PIN vai só ao caminho único da confirmação, e só com o ponteiro no cartão do parceiro", async () => {
  const um = deps({ resposta: { ok: true, precisa_pin: true, texto: "Anotei *3 R*.", cartao_id: "cp-1" } });
  const r = await camadaDoParceiro("3 r sim 7391", um.d);
  assertEquals(um.reg.confirmados, ["7391"]);
  assertEquals(r, { comando: "escolher", texto: "", noHistorico: null, jaEnviado: true });

  const outro = deps({ ponteiroAtual: "outra", resposta: { ok: true, precisa_pin: true, texto: "Anotei", cartao_id: "cp-1" } });
  const r2 = await camadaDoParceiro("3 r sim 7391", outro.d);
  assertEquals(outro.reg.confirmados, []);
  assertEquals(r2?.texto, P13("Enviar lembrete"));
  assert(!r2!.texto.includes("7391"));

  // sem PIN e com o ponteiro em outra pendência: o aviso sai já na escolha
  const semPin = deps({ ponteiroAtual: "outra", resposta: { ok: true, precisa_pin: true, texto: "Anotei *1 A*.", cartao_id: "cp-1" } });
  assertEquals((await camadaDoParceiro("1 a", semPin.d))?.texto, P13("Enviar lembrete"));
  assertEquals(semPin.reg.confirmados, []);
});

Deno.test("letra que o item não tem: com PIN, nada é confirmado; sem PIN, o banco explica as letras", async () => {
  const comPin = deps();
  const r = await camadaDoParceiro("1 c sim 7391", comPin.d);
  assertEquals(r?.texto, p14(1, "C"));
  assertEquals(comPin.reg.rpcs.length, 0);
  assertEquals(comPin.reg.confirmados, []);

  const semPin = deps({ resposta: { ok: true, texto: "O 1 não tem a letra C. Letras: A, R." } });
  assertEquals((await camadaDoParceiro("1 c", semPin.d))?.texto, "O 1 não tem a letra C. Letras: A, R.");
  assertEquals(semPin.reg.confirmados, []);
});

Deno.test("escolher com data ou texto depois da letra não é palavra do parceiro", async () => {
  const { d, reg } = deps();
  assertEquals(await camadaDoParceiro("3 c dia 14", d), null);
  assertEquals(reg.rpcs.length, 0);
});

Deno.test("*parceiro*: cartão, reapresenta, ocupado e vazio com texto respondem; vazio sem texto (desligado) segue ao modelo", async () => {
  for (const resposta of [
    { acao: "cartao", cartao_id: "cp-9", texto: "Cartão do parceiro …" },
    { acao: "reapresenta", cartao_id: "cp-9", texto: "Cartão do parceiro …" },
  ]) {
    const { d } = deps({ resposta });
    assertEquals(await camadaDoParceiro("parceiro", d), { comando: "parceiro", texto: "Cartão do parceiro …", noHistorico: null, cartaoId: "cp-9" });
  }
  const ocupado = deps({ resposta: { acao: "ocupado", texto: "Tem um pedido aberto antes deste." } });
  assertEquals((await camadaDoParceiro("parceiro", ocupado.d))?.texto, "Tem um pedido aberto antes deste.");
  const vazio = deps({ resposta: { acao: "vazio", texto: "Nada do parceiro agora." } });
  assertEquals((await camadaDoParceiro("parceiro", vazio.d))?.texto, "Nada do parceiro agora.");
  const desligado = deps({ resposta: { acao: "vazio" } });
  assertEquals(await camadaDoParceiro("parceiro", desligado.d), null);
  const naoDono = deps({ resposta: { acao: "vazio", motivo: "nao_e_o_dono" } });
  assertEquals(await camadaDoParceiro("parceiro 74", naoDono.d), null);
});

Deno.test("falha fecha: erro de RPC responde R15 e nada vai ao modelo; função ausente segue como sempre", async () => {
  const erro = deps({ rpc: () => Promise.resolve({ data: null, error: { code: "57014" } }) });
  assertEquals((await camadaDoParceiro("parceiro", erro.d))?.texto, R15_PARCEIRO);
  const lanca = deps({ rpc: () => Promise.reject(new Error("rede")) });
  assertEquals((await camadaDoParceiro("1 a sim 7391", lanca.d))?.texto, R15_PARCEIRO);
  assertEquals(lanca.reg.confirmados, []);
  for (const code of ["PGRST202", "42883"]) {
    const ausente = deps({ rpc: () => Promise.resolve({ data: null, error: { code } }) });
    assertEquals(await camadaDoParceiro("parceiro", ausente.d), null, code);
    const vivoAusente = deps({ cartaoVivo: () => Promise.reject({ code }) });
    assertEquals(await camadaDoParceiro("1 a", vivoAusente.d), null, code);
  }
  const vivoErro = deps({ cartaoVivo: () => Promise.reject({ code: "57014" }) });
  assertEquals((await camadaDoParceiro("1 a sim 7391", vivoErro.d))?.texto, R15_PARCEIRO);
  assertEquals(vivoErro.reg.confirmados, []);
  const semTexto = deps({ resposta: { ok: true } });
  assertEquals((await camadaDoParceiro("ver 1", semTexto.d))?.texto, R15_PARCEIRO);
  const confirmarFalha = deps({
    resposta: { ok: true, precisa_pin: true, texto: "Anotei", cartao_id: "cp-1" },
    confirmar: () => Promise.reject(new Error("pin")),
  });
  assertEquals((await camadaDoParceiro("1 a sim 7391", confirmarFalha.d))?.texto, R15_PARCEIRO);
});

Deno.test("seguir_ao_modelo e nao_e_o_dono devolvem null", async () => {
  for (const resposta of [{ ok: false, seguir_ao_modelo: true }, { ok: false, motivo: "nao_e_o_dono" }]) {
    const { d } = deps({ resposta });
    assertEquals(await camadaDoParceiro("ver 1", d), null);
  }
});

Deno.test("nada vai ao histórico do assistente: o par da conversa é do SQL, só com a contagem", async () => {
  for (const t of ["parceiro", "1 a", "ver 1", "1 tira 2"]) {
    const { d } = deps({ resposta: { ok: true, acao: "cartao", texto: "trecho que a MP escreveu", historico: { user: "x", assistant: "y" } } });
    assertEquals((await camadaDoParceiro(t, d))?.noHistorico, null, t);
  }
});

// ─── ehPalavraDoParceiroLigada (a marca do webhook) ─────────────────────────────────────────────────────────────

function adminFalso(r: { data?: unknown; error?: unknown; lanca?: boolean }) {
  const chamadas: string[] = [];
  return {
    chamadas,
    admin: {
      rpc: (fn: string) => {
        chamadas.push(fn);
        if (r.lanca) throw new Error("rede");
        return Promise.resolve({ data: r.data ?? null, error: r.error ?? null });
      },
    },
  };
}

Deno.test("ehPalavraDoParceiroLigada: *parceiro* e *parceiro 74* com e sem cartão", async () => {
  for (const data of [null, CARTAO]) {
    for (const t of ["parceiro", "ver parceiro", "parceiro 74", "parceiro mp os-00074"]) {
      assertEquals(await ehPalavraDoParceiroLigada(adminFalso({ data }).admin, t), true, t);
    }
  }
});

Deno.test("ehPalavraDoParceiroLigada: as de cartão só com o cartão do parceiro vivo", async () => {
  for (const t of ["1 a", "só 2", "não 2", "ver 1", "resolvido 1", "1 tira 2", "1 sabe 2", "1 a sim 7391"]) {
    assertEquals(await ehPalavraDoParceiroLigada(adminFalso({ data: CARTAO }).admin, t), true, t);
    assertEquals(await ehPalavraDoParceiroLigada(adminFalso({ data: null }).admin, t), false, t);
  }
});

Deno.test("ehPalavraDoParceiroLigada: conversa nem lê o banco; erro, função ausente e exceção dão falso", async () => {
  for (const t of ["oi", "parceiro?", "segura pátio", "retorno", "pessoal", "como está o motorhome"]) {
    const a = adminFalso({ data: CARTAO });
    assertEquals(await ehPalavraDoParceiroLigada(a.admin, t), false, t);
    assertEquals(a.chamadas, [], t);
  }
  for (const r of [{ error: { code: "PGRST202" } }, { error: { code: "42883" } }, { error: { code: "57014" } }, { lanca: true }]) {
    assertEquals(await ehPalavraDoParceiroLigada(adminFalso(r).admin, "parceiro"), false, JSON.stringify(r));
    assertEquals(await ehPalavraDoParceiroLigada(adminFalso(r).admin, "1 a"), false, JSON.stringify(r));
  }
  assertEquals(await ehPalavraDoParceiroLigada(null, "parceiro"), false, "nunca lança");
});

// ─── A ordem no ai-agent e a marca no webhook (âncoras de texto, sem importar) ─────────────────────────────────

Deno.test("ai-agent: a camada do parceiro vem antes da do retorno, e o PIN segue o caminho único", async () => {
  const fonte = await Deno.readTextFile(new URL("../../ai-agent/index.ts", import.meta.url));
  const parceiro = fonte.indexOf("await camadaDoParceiro(text,");
  const retorno = fonte.indexOf("await camadaDoRetorno(text,");
  assert(parceiro > 0 && retorno > 0, "as duas chamadas existem");
  assert(parceiro < retorno, "a do parceiro vem antes");
  assert(/confirmar: depsRetorno\.confirmar/.test(fonte), "o PIN do parceiro usa o mesmo confirmar da F2 (resolveWhatsAppConfirmation)");
});

Deno.test("webhook: a marca da palavra do parceiro entra ao lado da do retorno", async () => {
  const fonte = await Deno.readTextFile(new URL("../../whatsapp-webhook/index.ts", import.meta.url));
  assert(/\(await ehPalavraDoRetornoLigada\(admin, t\)\) \|\|(?:\s*\/\/[^\n]*)*\s*\(await ehPalavraDoParceiroLigada\(admin, t\)\)/.test(fonte));
});
