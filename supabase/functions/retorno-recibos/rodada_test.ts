// Testes da rodada da edge retorno-recibos (P11, F1, 16/11/2026), com banco e envio falsos que obedecem
// aos contratos C-PEGAR, C-DECISAO e C-ENVIO (spec, seção 6).
//
// O que provam (spec P11.3): na sombra, 3 itens viram 3 "sombra" e nenhuma chamada de envio; o validador
// reprovado (texto com R$) vira recusada/validador com regras = ['dinheiro'], sem envio; ligado, cada
// resposta do whatsapp-send (200, 200 dedup, 409, 422, 503, 502 incerto, 502, 500, rede, 400) vira o
// estado certo; o item reagendado (503) volta com a MESMA dedupe_key; nenhuma resposta leva a um 2º envio
// do mesmo item com outra chave; o laço para no maxItens e no limiteMs (relógio falso); retorno_pegar com
// erro dá resumo.erro e nenhuma outra chamada; a exceção no registrar não derruba a rodada. E mais o que
// a entrega da P11 fechou onde a spec deixou aberto (status fora da tabela, item torto, item repetido) e
// o envio de produção (envioPeloWhatsappSend) com fetch falso.
//
// Telefones de teste da faixa 5547900009 (nunca dado real). Nada aqui toca banco ou rede.
//
// Reverter: apagar este arquivo junto com rodada.ts e index.ts.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type ContextoDoValidador, validarSaida } from "../_shared/retorno/validador.ts";
import {
  type Db,
  type DependenciasDaRodada,
  type Envio,
  type EnvioAoDono,
  envioPeloWhatsappSend,
  estadoDoEnvio,
  type EstadoDoEnvio,
  type RespostaDoBanco,
  type RespostaDoEnvio,
  rodada,
  rodadaDoCartao,
  RPC_CARTAO_ABRIR,
  RPC_CARTAO_DEVIDO,
  RPC_CARTAO_ENVIADO,
  RPC_DECISAO,
  RPC_LOG,
  RPC_PEGAR,
  type ResumoDaRodada,
} from "./rodada.ts";

// ─── Dados de exemplo ────────────────────────────────────────────────────────────────────────────

// T01 (spec P3.1), com o contexto que o retorno_pegar montaria (spec P6.1, passo 8).
const MODELO_T01 = "Oi, {nome}! Já passei sua mensagem ao Gustavo, e ele retorna para você {quando_fala}.";
const TEXTO_BOM = "Oi, Lenine! Já passei sua mensagem ao Gustavo, e ele retorna para você ainda hoje.";
const TEXTO_COM_DINHEIRO = TEXTO_BOM + " Custa R$ 100.";
const CONTEXTO: ContextoDoValidador = {
  audiencia: "cliente",
  datas_permitidas: ["hoje", "ainda hoje"],
  horas_permitidas: ["19h"],
  nome_permitido: "Lenine",
  nomes_de_outros: [],
  os_permitidas: [],
  textos_do_cliente: ["Bom dia, a bateria do motorhome não está segurando carga"],
  trechos_do_modelo: MODELO_T01.split(/\{[a-z_]+\}/).filter((s) => s !== ""),
  marcas: { tem_proposta: false, tem_topo: false, cliente_ouviu: false, conferida: false },
};

const SAIDA = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const CASO = (n: number) => `11111111-1111-4111-8111-${String(n).padStart(12, "0")}`;
const FONE = (n: number) => `55479000091${String(n % 100).padStart(2, "0")}`;

/** Um item como o retorno_pegar devolve (C-PEGAR); `extra` troca campos. */
function item(n: number, extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    saida_id: SAIDA(n),
    tentativa: 1,
    dedupe_key: `retorno:${CASO(n)}:recibo`,
    tipo: "recibo_cliente",
    variante: "T01",
    origem: "retorno_recibo",
    classe: "resposta_imediata",
    modo: "sombra",
    phone: FONE(n),
    texto: TEXTO_BOM,
    validador: structuredClone(CONTEXTO),
    ...extra,
  };
}
const LIGADO = { modo: "ligado" };

// ─── Falsos ──────────────────────────────────────────────────────────────────────────────────────

interface Chamada {
  fn: string;
  args: Record<string, unknown>;
}

type Pegar = (n: number) => RespostaDoBanco | Promise<RespostaDoBanco>;
type AoRegistrar = (args: Record<string, unknown>) => RespostaDoBanco | Promise<RespostaDoBanco>;

/** retorno_pegar devolve os itens na ordem e depois null. */
function daFila(itens: Array<Record<string, unknown> | null>): Pegar {
  const fila = [...itens];
  return () => ({ data: fila.length > 0 ? fila.shift() ?? null : null, error: null });
}

const REGISTRA_OK: AoRegistrar = (args) => ({ data: { ok: true, estado: args.p_estado }, error: null });

class BancoFalso implements Db {
  chamadas: Chamada[] = [];
  private pegadas = 0;
  constructor(private pegar: Pegar, private aoRegistrar: AoRegistrar = REGISTRA_OK) {}
  rpc(fn: string, args: Record<string, unknown>): Promise<RespostaDoBanco> {
    this.chamadas.push({ fn, args: structuredClone(args) });
    if (fn === RPC_PEGAR) return Promise.resolve(this.pegar(this.pegadas++));
    if (fn === RPC_DECISAO) return Promise.resolve(this.aoRegistrar(args));
    if (fn === RPC_LOG) return Promise.resolve({ data: "00000000-0000-4000-8000-0000000000ff", error: null });
    return Promise.resolve({ data: null, error: { code: "PGRST202", message: "função desconhecida no falso" } });
  }
  de(fn: string): Array<Record<string, unknown>> {
    return this.chamadas.filter((c) => c.fn === fn).map((c) => c.args);
  }
  decisoes(): Array<Record<string, unknown>> {
    return this.de(RPC_DECISAO);
  }
}

type Responder = (e: Envio, n: number) => RespostaDoEnvio | Promise<RespostaDoEnvio>;

function envioFalso(responder: Responder) {
  const envios: Envio[] = [];
  const enviar = async (e: Envio): Promise<RespostaDoEnvio> => {
    envios.push(structuredClone(e));
    return await responder(e, envios.length);
  };
  return { envios, enviar };
}

const NAO_ENVIA: Responder = () => {
  throw new Error("nenhum envio era esperado neste teste");
};

function relogio(inicio = "2026-11-17T13:00:00.000Z") {
  let t = Date.parse(inicio);
  return { agora: () => new Date(t), avancar: (ms: number) => void (t += ms) };
}

function deps(enviar: DependenciasDaRodada["enviar"], extra: Partial<DependenciasDaRodada> = {}): DependenciasDaRodada {
  return { agora: relogio().agora, enviar, limiteMs: 45_000, maxItens: 20, ...extra };
}

const RESUMO_VAZIO: ResumoDaRodada = { itens: 0, sombra: 0, enviadas: 0, incertas: 0, recusadas: 0, reagendadas: 0 };
const resumo = (r: Partial<ResumoDaRodada>): ResumoDaRodada => ({ ...RESUMO_VAZIO, ...r });

// As respostas do whatsapp-send (index.ts do ramo) e o desfecho de cada uma (spec P11.2).
const TABELA: Array<[string, RespostaDoEnvio, EstadoDoEnvio, Record<string, unknown>]> = [
  ["200", { status: 200, body: { success: true, kind: "text", messageId: "3EB0ABC123" } }, "enviada", {
    http_status: 200,
    provider_message_id: "3EB0ABC123",
  }],
  ["200 dedup", { status: 200, body: { success: true, deduplicated: true, kind: "text", messageId: null } }, "enviada", {
    http_status: 200,
    provider_message_id: null,
    codigo: "deduplicada",
  }],
  ["409", { status: 409, body: { error: "A tentativa anterior…", em_andamento: true } }, "incerta", {
    http_status: 409,
    codigo: "em_andamento",
  }],
  ["422", { status: 422, body: { error: "Contato pediu para não receber.", recusado: true, codigo: "opt_out" } }, "recusada", {
    http_status: 422,
    motivo: "canal",
    codigo: "opt_out",
  }],
  ["503", { status: 503, body: { error: "Envio automático não feito…", reserva_indisponivel: true } }, "reagendar", {
    http_status: 503,
    codigo: "reserva_indisponivel",
  }],
  ["502 incerto", { status: 502, body: { error: "timeout", incerto: true } }, "incerta", { http_status: 502, codigo: "incerto" }],
  ["502", { status: 502, body: { error: "túnel fora do ar" } }, "recusada", { http_status: 502, motivo: "provedor" }],
  ["500", { status: 500, body: { error: "Unknown error" } }, "incerta", { http_status: 500, codigo: "erro_do_servidor" }],
  ["rede", { status: 0, body: null, erroDeRede: true }, "incerta", { codigo: "rede" }],
  ["400", { status: 400, body: { error: { phone: ["muito curto"] } } }, "recusada", { http_status: 400, motivo: "provedor" }],
  ["401", { status: 401, body: { error: "Unauthorized" } }, "recusada", { http_status: 401, motivo: "provedor" }],
];

const CONTADOR: Record<EstadoDoEnvio, keyof ResumoDaRodada> = {
  enviada: "enviadas",
  incerta: "incertas",
  recusada: "recusadas",
  reagendar: "reagendadas",
};

// ─── Premissas dos dados de exemplo ──────────────────────────────────────────────────────────────

Deno.test("premissa: o texto de exemplo passa no validador e o com R$ reprova só por dinheiro", () => {
  assertEquals(validarSaida(TEXTO_BOM, CONTEXTO), { ok: true });
  assertEquals(validarSaida(TEXTO_COM_DINHEIRO, CONTEXTO), { ok: false, regras: ["dinheiro"] });
});

// ─── Sombra ──────────────────────────────────────────────────────────────────────────────────────

Deno.test("sombra: 3 itens viram 3 'sombra', com o validador ok, e nenhuma chamada de envio", async () => {
  const banco = new BancoFalso(daFila([item(1), item(2), item(3)]));
  const { envios, enviar } = envioFalso(NAO_ENVIA);
  const r = await rodada(banco, deps(enviar));
  assertEquals(r, resumo({ itens: 3, sombra: 3 }));
  assertEquals(envios.length, 0);
  assertEquals(banco.decisoes(), [1, 2, 3].map((n) => ({
    p_saida: SAIDA(n),
    p_estado: "sombra",
    p_detalhe: { validador: { ok: true } },
  })));
  // O 4º retorno_pegar devolve null e a rodada para; o p_agora é o do relógio.
  assertEquals(banco.de(RPC_PEGAR).length, 4);
  assertEquals(banco.de(RPC_PEGAR)[0], { p_agora: "2026-11-17T13:00:00.000Z" });
  assertEquals(banco.de(RPC_LOG).length, 0);
});

// ─── Validador ───────────────────────────────────────────────────────────────────────────────────

Deno.test("validador reprovado (texto com R$): recusada/validador com regras ['dinheiro'], sem envio, na sombra e ligado", async () => {
  for (const modo of ["sombra", "ligado"]) {
    const banco = new BancoFalso(daFila([item(1, { modo, texto: TEXTO_COM_DINHEIRO })]));
    const { envios, enviar } = envioFalso(NAO_ENVIA);
    const r = await rodada(banco, deps(enviar));
    assertEquals(r, resumo({ itens: 1, recusadas: 1 }), modo);
    assertEquals(envios.length, 0, modo);
    assertEquals(banco.decisoes(), [{
      p_saida: SAIDA(1),
      p_estado: "recusada",
      p_detalhe: { motivo: "validador", regras: ["dinheiro"] },
    }], modo);
  }
});

Deno.test("validador: contexto ausente reprova com 'contexto' e nada sai", async () => {
  const banco = new BancoFalso(daFila([item(1, { ...LIGADO, validador: null })]));
  const { envios, enviar } = envioFalso(NAO_ENVIA);
  const r = await rodada(banco, deps(enviar));
  assertEquals(r, resumo({ itens: 1, recusadas: 1 }));
  assertEquals(envios.length, 0);
  // Sem contexto, as listas de permissão valem vazias: a data e a hora do texto também reprovam.
  assertEquals(banco.decisoes()[0].p_detalhe, { motivo: "validador", regras: ["contexto", "data_fora"] });
});

Deno.test("validador: texto vazio ou que não é texto reprova, sem envio", async () => {
  for (const texto of ["", "   ", null, 42]) {
    const banco = new BancoFalso(daFila([item(1, { ...LIGADO, texto })]));
    const { envios, enviar } = envioFalso(NAO_ENVIA);
    await rodada(banco, deps(enviar));
    assertEquals(envios.length, 0, String(texto));
    const d = banco.decisoes()[0];
    assertEquals(d.p_estado, "recusada", String(texto));
    assert((d.p_detalhe as { regras: string[] }).regras.includes("vazio"), String(texto));
  }
});

// ─── estadoDoEnvio ───────────────────────────────────────────────────────────────────────────────

Deno.test("estadoDoEnvio: cada resposta da tabela do whatsapp-send vira o estado certo", () => {
  for (const [nome, resposta, estado, detalhe] of TABELA) {
    assertEquals(estadoDoEnvio(resposta), { estado, detalhe }, nome);
  }
});

Deno.test("estadoDoEnvio: o que a tabela não lista fecha (pode ter saído = incerta; não processado = recusada)", () => {
  const casos: Array<[string, RespostaDoEnvio, EstadoDoEnvio]> = [
    ["503 sem reserva_indisponivel (gateway)", { status: 503, body: { code: "BOOT_ERROR", message: "Function failed to start" } }, "incerta"],
    ["503 sem corpo", { status: 503, body: null }, "incerta"],
    ["502 sem corpo do whatsapp-send", { status: 502, body: null }, "incerta"],
    ["504", { status: 504, body: null }, "incerta"],
    ["546", { status: 546, body: { code: "WORKER_LIMIT" } }, "incerta"],
    ["200 sem success", { status: 200, body: { kind: "text" } }, "incerta"],
    ["200 com success que não é true", { status: 200, body: { success: "true" } }, "incerta"],
    ["200 sem corpo", { status: 200, body: null }, "incerta"],
    ["302", { status: 302, body: null }, "incerta"],
    ["rede com status 200", { status: 200, body: { success: true }, erroDeRede: true }, "incerta"],
    ["status NaN", { status: Number.NaN, body: null }, "incerta"],
    ["409 sem em_andamento", { status: 409, body: null }, "incerta"],
    ["404", { status: 404, body: { error: "Function not found" } }, "recusada"],
    ["429", { status: 429, body: null }, "recusada"],
    ["422 sem recusado", { status: 422, body: { error: "?" } }, "recusada"],
  ];
  for (const [nome, resposta, estado] of casos) {
    assertEquals(estadoDoEnvio(resposta).estado, estado, nome);
  }
  // Só a 503 com reserva_indisponivel reagenda.
  assertEquals(
    TABELA.map(([, r]) => r).concat(casos.map(([, r]) => r)).filter((r) => estadoDoEnvio(r).estado === "reagendar").length,
    1,
  );
  // Fora do contrato, nada vira "enviada".
  for (const [nome, resposta] of casos) assert(estadoDoEnvio(resposta).estado !== "enviada", nome);
  // O 404 e o 422 sem recusado são do provedor; o código torto do 422 não vai ao banco.
  assertEquals(estadoDoEnvio({ status: 404, body: null }).detalhe, { http_status: 404, motivo: "provedor" });
  assertEquals(estadoDoEnvio({ status: 422, body: { recusado: true, codigo: "tem espaço e é longo demais" } }).detalhe, {
    http_status: 422,
    motivo: "canal",
    codigo: "recusado",
  });
  // messageId que não é texto não vira provider_message_id.
  assertEquals(estadoDoEnvio({ status: 200, body: { success: true, messageId: 123 } }).detalhe, {
    http_status: 200,
    provider_message_id: null,
  });
});

// ─── Ligado ──────────────────────────────────────────────────────────────────────────────────────

Deno.test("ligado: o envio leva o telefone, o texto, a origem, o contexto retorno:<saída> e a chave do banco", async () => {
  const banco = new BancoFalso(daFila([item(1, { ...LIGADO, origem: "retorno_coleta", dedupe_key: `retorno:${CASO(1)}:coleta` })]));
  const { envios, enviar } = envioFalso(() => TABELA[0][1]);
  const r = await rodada(banco, deps(enviar));
  assertEquals(r, resumo({ itens: 1, enviadas: 1 }));
  assertEquals(envios, [{
    phone: FONE(1),
    message: TEXTO_BOM,
    origem: "retorno_coleta",
    context: "retorno:" + SAIDA(1),
    dedupe_key: `retorno:${CASO(1)}:coleta`,
  }]);
  // O whatsapp-send aceita context até 64 caracteres.
  assert(envios[0].context.length <= 64);
});

Deno.test("ligado: cada resposta da tabela vira o estado certo no registro, com um envio só por item", async () => {
  for (const [nome, resposta, estado, detalhe] of TABELA) {
    const banco = new BancoFalso(daFila([item(1, LIGADO)]));
    const { envios, enviar } = envioFalso(() => resposta);
    const r = await rodada(banco, deps(enviar));
    assertEquals(envios.length, 1, nome);
    assertEquals(envios[0].dedupe_key, item(1).dedupe_key, nome);
    assertEquals(banco.decisoes(), [{
      p_saida: SAIDA(1),
      p_estado: estado,
      p_detalhe: { validador: { ok: true }, ...detalhe },
    }], nome);
    assertEquals(r, resumo({ itens: 1, [CONTADOR[estado]]: 1 }), nome);
  }
});

Deno.test("ligado: o enviar que lança vira incerta (pode ter saído), sem 2ª tentativa", async () => {
  const banco = new BancoFalso(daFila([item(1, LIGADO)]));
  const { envios, enviar } = envioFalso(() => {
    throw new TypeError("conexão caiu no meio");
  });
  const r = await rodada(banco, deps(enviar));
  assertEquals(r, resumo({ itens: 1, incertas: 1 }));
  assertEquals(envios.length, 1);
  assertEquals(banco.decisoes()[0].p_estado, "incerta");
  assertEquals(banco.decisoes()[0].p_detalhe, { validador: { ok: true }, codigo: "rede" });
});

// ─── A mesma chave sempre ────────────────────────────────────────────────────────────────────────

Deno.test("503: o item reagendado volta com a MESMA dedupe_key (e o mesmo contexto)", async () => {
  const banco = new BancoFalso(daFila([item(1, LIGADO), item(1, { ...LIGADO, tentativa: 2 })]));
  const { envios, enviar } = envioFalso((_e, n) => (n === 1 ? TABELA[4][1] : TABELA[0][1]));
  const r = await rodada(banco, deps(enviar));
  assertEquals(r, resumo({ itens: 2, reagendadas: 1, enviadas: 1 }));
  assertEquals(envios.length, 2);
  assertEquals(envios[0], envios[1]);
  assertEquals(envios[1].dedupe_key, item(1).dedupe_key);
  assertEquals(banco.decisoes().map((d) => d.p_estado), ["reagendar", "enviada"]);
});

Deno.test("nenhuma resposta leva a um 2º envio do mesmo item com outra chave", async () => {
  const OUTRA_CHAVE = `retorno:${CASO(9)}:recibo`;
  for (const [nome, resposta, estado] of TABELA) {
    // (a) o banco devolve o mesmo item de novo, com a mesma chave: só o reagendado é enviado de novo.
    {
      const banco = new BancoFalso(daFila([item(1, LIGADO), item(1, { ...LIGADO, tentativa: 2 })]));
      const { envios, enviar } = envioFalso(() => resposta);
      await rodada(banco, deps(enviar));
      assertEquals(envios.length, estado === "reagendar" ? 2 : 1, nome);
      assertEquals([...new Set(envios.map((e) => e.dedupe_key))], [item(1).dedupe_key], nome);
    }
    // (b) o banco devolve o mesmo item com OUTRA chave (defeito): nunca sai com ela.
    {
      const banco = new BancoFalso(daFila([item(1, LIGADO), item(1, { ...LIGADO, tentativa: 2, dedupe_key: OUTRA_CHAVE })]));
      const { envios, enviar } = envioFalso(() => resposta);
      const r = await rodada(banco, deps(enviar));
      assertEquals(envios.length, 1, nome);
      assertEquals(envios[0].dedupe_key, item(1).dedupe_key, nome);
      if (estado === "reagendar") {
        // depois do 503 nada saiu: a volta com a chave trocada é recusada, sem envio
        assertEquals(banco.decisoes()[1], {
          p_saida: SAIDA(1),
          p_estado: "recusada",
          p_detalhe: { motivo: "validador", regras: ["contexto"], codigo: "chave_trocada" },
        }, nome);
        assertEquals(r.erro, undefined, nome);
      } else {
        // depois de outro desfecho a rodada para, sem registrar por cima do que já foi registrado
        assertEquals(banco.decisoes().length, 1, nome);
        assertEquals(r.erro, "item_repetido", nome);
      }
    }
  }
});

Deno.test("item repetido na mesma rodada sem reagendar: não reenvia, não registra de novo e para", async () => {
  const banco = new BancoFalso(daFila([item(1, LIGADO), item(1, LIGADO), item(2, LIGADO)]));
  const { envios, enviar } = envioFalso(() => TABELA[0][1]);
  const r = await rodada(banco, deps(enviar));
  assertEquals(r, resumo({ itens: 2, enviadas: 1, erro: "item_repetido" }));
  assertEquals(envios.length, 1);
  assertEquals(banco.decisoes().length, 1);
  assertEquals(banco.de(RPC_PEGAR).length, 2);
});

// ─── Item torto: nada sai ────────────────────────────────────────────────────────────────────────

Deno.test("item torto (modo, origem, telefone, chave): recusada/validador com 'contexto' e o código, sem envio", async () => {
  const casos: Array<[Record<string, unknown>, string]> = [
    [{ modo: "talvez" }, "modo_desconhecido"],
    [{ modo: undefined }, "modo_desconhecido"],
    [{ ...LIGADO, origem: undefined }, "origem_invalida"],
    [{ ...LIGADO, origem: "sistema" }, "origem_invalida"],
    [{ ...LIGADO, phone: "" }, "telefone_invalido"],
    [{ ...LIGADO, phone: "+55 47 90000-9101" }, "telefone_invalido"],
    [{ ...LIGADO, dedupe_key: "comprovante:abc" }, "chave_invalida"],
    [{ ...LIGADO, dedupe_key: null }, "chave_invalida"],
    // na sombra também: a sombra registra o que o ligado faria
    [{ origem: "sistema" }, "origem_invalida"],
  ];
  for (const [extra, codigo] of casos) {
    const banco = new BancoFalso(daFila([item(1, extra)]));
    const { envios, enviar } = envioFalso(NAO_ENVIA);
    const r = await rodada(banco, deps(enviar));
    assertEquals(envios.length, 0, codigo);
    assertEquals(r, resumo({ itens: 1, recusadas: 1 }), codigo);
    assertEquals(banco.decisoes(), [{
      p_saida: SAIDA(1),
      p_estado: "recusada",
      p_detalhe: { motivo: "validador", regras: ["contexto"], codigo },
    }], codigo);
  }
});

Deno.test("item sem id de saída legível: não envia, não registra e a rodada para com erro", async () => {
  for (const dado of [{ ...item(1, LIGADO), saida_id: undefined }, { ...item(1, LIGADO), saida_id: "abc" }, "texto", [1, 2]]) {
    const banco = new BancoFalso(() => ({ data: dado, error: null }));
    const { envios, enviar } = envioFalso(NAO_ENVIA);
    const r = await rodada(banco, deps(enviar));
    assertEquals(r, resumo({ itens: 1, erro: "item_malformado" }), JSON.stringify(dado));
    assertEquals(envios.length, 0);
    assertEquals(banco.decisoes().length, 0);
    assertEquals(banco.de(RPC_PEGAR).length, 1);
  }
});

// ─── O laço ──────────────────────────────────────────────────────────────────────────────────────

Deno.test("o laço para no maxItens", async () => {
  const banco = new BancoFalso((n) => ({ data: item(n + 1), error: null })); // nunca acaba
  const { enviar } = envioFalso(NAO_ENVIA);
  const r = await rodada(banco, deps(enviar, { maxItens: 4 }));
  assertEquals(r, resumo({ itens: 4, sombra: 4 }));
  assertEquals(banco.de(RPC_PEGAR).length, 4);
});

Deno.test("o laço para no limiteMs (relógio falso)", async () => {
  // Sombra: cada registro leva 20 s; com 45 s, entram os itens que começam em 0, 20 e 40 s.
  {
    const r0 = relogio();
    const banco = new BancoFalso((n) => ({ data: item(n + 1), error: null }), (args) => {
      r0.avancar(20_000);
      return REGISTRA_OK(args);
    });
    const { enviar } = envioFalso(NAO_ENVIA);
    const r = await rodada(banco, deps(enviar, { agora: r0.agora }));
    assertEquals(r, resumo({ itens: 3, sombra: 3 }));
    assertEquals(banco.de(RPC_PEGAR).length, 3);
    // cada retorno_pegar recebe a hora do relógio naquele momento
    assertEquals(banco.de(RPC_PEGAR).map((a) => a.p_agora), [
      "2026-11-17T13:00:00.000Z",
      "2026-11-17T13:00:20.000Z",
      "2026-11-17T13:00:40.000Z",
    ]);
  }
  // Ligado: cada envio leva 25 s (o tempo máximo); com 45 s, saem 2.
  {
    const r0 = relogio();
    const banco = new BancoFalso((n) => ({ data: item(n + 1, LIGADO), error: null }));
    const { envios, enviar } = envioFalso(() => {
      r0.avancar(25_000);
      return TABELA[0][1];
    });
    const r = await rodada(banco, deps(enviar, { agora: r0.agora }));
    assertEquals(r, resumo({ itens: 2, enviadas: 2 }));
    assertEquals(envios.length, 2);
  }
  // Limite zero ou inválido: nenhuma chamada.
  for (const limiteMs of [0, Number.NaN]) {
    const banco = new BancoFalso(daFila([item(1)]));
    const { enviar } = envioFalso(NAO_ENVIA);
    assertEquals(await rodada(banco, deps(enviar, { limiteMs })), RESUMO_VAZIO);
    assertEquals(banco.chamadas.length, 0);
  }
});

// ─── Erros ───────────────────────────────────────────────────────────────────────────────────────

Deno.test("retorno_pegar com erro: resumo.erro = code e nenhuma outra chamada", async () => {
  const banco = new BancoFalso(() => ({ data: null, error: { code: "PGRST202", message: "Could not find the function" } }));
  const { envios, enviar } = envioFalso(NAO_ENVIA);
  const r = await rodada(banco, deps(enviar));
  assertEquals(r, resumo({ erro: "PGRST202" }));
  assertEquals(banco.chamadas.length, 1);
  assertEquals(banco.chamadas[0].fn, RPC_PEGAR);
  assertEquals(envios.length, 0);
});

Deno.test("retorno_pegar com erro sem código, que lança ou que rejeita: erro e a rodada não lança", async () => {
  const casos: Array<[Pegar, string]> = [
    [() => ({ data: null, error: { code: "", message: "TypeError: fetch failed" } }), "erro"],
    [() => {
      throw new TypeError("rede");
    }, "TypeError"],
    [() => Promise.reject(new RangeError("x")), "RangeError"],
  ];
  for (const [pegar, erro] of casos) {
    const banco = new BancoFalso(pegar);
    const { envios, enviar } = envioFalso(NAO_ENVIA);
    const r = await rodada(banco, deps(enviar));
    assertEquals(r, resumo({ erro }), erro);
    assertEquals(banco.chamadas.length, 1);
    assertEquals(envios.length, 0);
  }
  // O erro no meio da rodada para ali, sem perder a contagem do que já foi decidido.
  const banco = new BancoFalso((n) =>
    n === 0 ? { data: item(1), error: null } : { data: null, error: { code: "57014", message: "statement timeout" } }
  );
  const { enviar } = envioFalso(NAO_ENVIA);
  assertEquals(await rodada(banco, deps(enviar)), resumo({ itens: 1, sombra: 1, erro: "57014" }));
});

Deno.test("exceção no registrar não derruba a rodada: vai ao log (sem telefone nem texto) e o próximo item segue", async () => {
  const banco = new BancoFalso(daFila([item(1, LIGADO), item(2), item(3)]), (args) => {
    if (args.p_saida === SAIDA(1)) throw new Error("banco caiu bem agora");
    if (args.p_saida === SAIDA(2)) return { data: { ok: false, erro: "estado" }, error: null };
    return REGISTRA_OK(args);
  });
  const { envios, enviar } = envioFalso(() => TABELA[0][1]);
  const r = await rodada(banco, deps(enviar));
  // A contagem é do que a edge decidiu; a saída 1 fica 'enviando' e o vigia a passa a incerta.
  assertEquals(r, resumo({ itens: 3, enviadas: 1, sombra: 2 }));
  assertEquals(envios.length, 1, "nunca reenvia por causa do registro que falhou");
  assertEquals(banco.decisoes().map((d) => d.p_saida), [SAIDA(1), SAIDA(2), SAIDA(3)]);
  const logs = banco.de(RPC_LOG);
  assertEquals(logs.length, 2);
  assertEquals(logs.map((l) => (l.p_details as Record<string, unknown>).codigo), ["Error", "estado"]);
  for (const l of logs) {
    assertEquals(l.p_context, "retorno-recibos");
    assertEquals(l.p_source, "edge");
    const texto = JSON.stringify(l);
    assert(!texto.includes(FONE(1)) && !texto.includes(FONE(2)), "o log não leva telefone");
    assert(!texto.includes("Lenine") && !texto.includes("Gustavo"), "o log não leva o texto");
  }
});

Deno.test("registrar com erro do banco e log que também falha: a rodada segue e não lança", async () => {
  const banco = new BancoFalso(daFila([item(1), item(2)]), () => ({ data: null, error: { code: "42501", message: "permission denied" } }));
  const rpcOriginal = banco.rpc.bind(banco);
  banco.rpc = (fn, args) => {
    if (fn === RPC_LOG) throw new Error("o log também caiu");
    return rpcOriginal(fn, args);
  };
  const { enviar } = envioFalso(NAO_ENVIA);
  const r = await rodada(banco, deps(enviar));
  assertEquals(r, resumo({ itens: 2, sombra: 2 }));
  assertEquals(banco.decisoes().length, 2);
});

Deno.test("rodada nunca lança: relógio que lança vira erro", async () => {
  const banco = new BancoFalso(daFila([item(1)]));
  const { enviar } = envioFalso(NAO_ENVIA);
  const r = await rodada(banco, deps(enviar, {
    agora: () => {
      throw new RangeError("relógio quebrado");
    },
  }));
  assertEquals(r, resumo({ erro: "RangeError" }));
  assertEquals(banco.chamadas.length, 0);
});

// ─── envioPeloWhatsappSend (o enviar de produção) ────────────────────────────────────────────────

const ENVIO: Envio = {
  phone: FONE(1),
  message: TEXTO_BOM,
  origem: "retorno_recibo",
  context: "retorno:" + SAIDA(1),
  dedupe_key: `retorno:${CASO(1)}:recibo`,
};

Deno.test("envioPeloWhatsappSend: POST no whatsapp-send com a chave de serviço e o corpo do contrato C-ENVIO", async () => {
  const pedidos: Array<{ url: string; init: RequestInit }> = [];
  const buscar: typeof fetch = (url, init) => {
    pedidos.push({ url: String(url), init: init ?? {} });
    return Promise.resolve(new Response(JSON.stringify({ success: true, kind: "text", messageId: "X1" }), { status: 200 }));
  };
  const enviar = envioPeloWhatsappSend("https://exemplo.supabase.co/", "chave-de-servico-falsa", buscar, 1_000);
  assertEquals(await enviar(ENVIO), { status: 200, body: { success: true, kind: "text", messageId: "X1" } });
  assertEquals(pedidos.length, 1);
  assertEquals(pedidos[0].url, "https://exemplo.supabase.co/functions/v1/whatsapp-send");
  assertEquals(pedidos[0].init.method, "POST");
  assertEquals(pedidos[0].init.headers, {
    Authorization: "Bearer chave-de-servico-falsa",
    "Content-Type": "application/json",
  });
  assertEquals(JSON.parse(String(pedidos[0].init.body)), { ...ENVIO, kind: "text" });
  assert(pedidos[0].init.signal instanceof AbortSignal, "com tempo máximo");
});

Deno.test("envioPeloWhatsappSend: corpo que não é objeto JSON vira null, com o status de verdade", async () => {
  for (const [corpo, status] of [["<html>Bad Gateway</html>", 502], ["[1,2]", 200], ["", 204]] as const) {
    const buscar: typeof fetch = () => Promise.resolve(new Response(status === 204 ? null : corpo, { status }));
    const enviar = envioPeloWhatsappSend("https://exemplo.supabase.co", "k", buscar, 1_000);
    assertEquals(await enviar(ENVIO), { status, body: null }, corpo);
  }
});

Deno.test("envioPeloWhatsappSend: rede caída e tempo esgotado viram erroDeRede (incerta), sem lançar", async () => {
  const caiu: typeof fetch = () => Promise.reject(new TypeError("error sending request"));
  assertEquals(await envioPeloWhatsappSend("https://exemplo.supabase.co", "k", caiu, 1_000)(ENVIO), {
    status: 0,
    body: null,
    erroDeRede: true,
  });
  // Espera o sinal de tempo esgotado, como o fetch de verdade.
  const lento: typeof fetch = (_url, init) =>
    new Promise((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () => reject(init.signal?.reason));
    });
  const r = await envioPeloWhatsappSend("https://exemplo.supabase.co", "k", lento, 10)(ENVIO);
  assertEquals(r, { status: 0, body: null, erroDeRede: true });
  assertEquals(estadoDoEnvio(r).estado, "incerta");
});

// ─── rodadaDoCartao (F2, P10.5) ───────────────────────────────────────────────────────────────────────────────────────

function bancoDoCartao(respostas: Record<string, RespostaDoBanco>) {
  const chamadas: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const db: Db = {
    rpc: (fn, args) => {
      chamadas.push({ fn, args });
      return Promise.resolve(respostas[fn] ?? { data: null, error: null });
    },
  };
  return { db, chamadas };
}

const RELOGIO = () => new Date("2026-11-24T15:30:00.000Z");
const CARTAO_ABERTO = { data: { acao: "cartao", cartao_id: SAIDA(7), phone: FONE(7), texto: "Retorno · 1 esperando" }, error: null };

Deno.test("rodadaDoCartao: nada devido, nada acontece", async () => {
  const { db, chamadas } = bancoDoCartao({});
  let envios = 0;
  const r = await rodadaDoCartao(db, { agora: RELOGIO, enviarAoDono: () => { envios++; return Promise.resolve({ status: 200, body: null }); } });
  assertEquals(r, { acao: null });
  assertEquals(chamadas.map((c) => c.fn), [RPC_CARTAO_DEVIDO]);
  assertEquals(envios, 0);
});

Deno.test("rodadaDoCartao: devido, abre, envia e registra, com a chave do dia no meio-dia", async () => {
  const { db, chamadas } = bancoDoCartao({
    [RPC_CARTAO_DEVIDO]: { data: { gatilho: "meio_dia" }, error: null },
    [RPC_CARTAO_ABRIR]: CARTAO_ABERTO,
  });
  const enviados: EnvioAoDono[] = [];
  const r = await rodadaDoCartao(db, {
    agora: RELOGIO,
    enviarAoDono: (e) => { enviados.push(e); return Promise.resolve({ status: 200, body: { success: true, messageId: "wa-9" } }); },
  });
  assertEquals(r, { acao: "cartao" });
  assertEquals(enviados, [{ phone: FONE(7), message: "Retorno · 1 esperando", dedupe_key: "retorno-cartao:meio_dia:2026-11-24" }]);
  assertEquals(chamadas.map((c) => c.fn), [RPC_CARTAO_DEVIDO, RPC_CARTAO_ABRIR, RPC_CARTAO_ENVIADO]);
  assertEquals(chamadas[2].args.p_ok, true);
  assertEquals(chamadas[2].args.p_wa_id, "wa-9");
});

Deno.test("rodadaDoCartao: o acorde usa a chave do cartão e passa o aviso", async () => {
  const { db, chamadas } = bancoDoCartao({
    [RPC_CARTAO_DEVIDO]: { data: { gatilho: "acorde", aviso_id: "a-1" }, error: null },
    [RPC_CARTAO_ABRIR]: CARTAO_ABERTO,
  });
  const enviados: EnvioAoDono[] = [];
  await rodadaDoCartao(db, {
    agora: RELOGIO,
    enviarAoDono: (e) => { enviados.push(e); return Promise.resolve({ status: 200, body: { success: true } }); },
  });
  assertEquals(enviados[0].dedupe_key, `retorno-cartao:${SAIDA(7)}`);
  assertEquals(chamadas[1].args.p_aviso, "a-1");
});

Deno.test("rodadaDoCartao: ocupado, ja_vivo e vazio não enviam", async () => {
  for (const acao of ["ocupado", "ja_vivo", "vazio"]) {
    const { db, chamadas } = bancoDoCartao({
      [RPC_CARTAO_DEVIDO]: { data: { gatilho: "acorde" }, error: null },
      [RPC_CARTAO_ABRIR]: { data: { acao }, error: null },
    });
    let envios = 0;
    assertEquals(await rodadaDoCartao(db, { agora: RELOGIO, enviarAoDono: () => { envios++; return Promise.resolve({ status: 200, body: null }); } }), { acao });
    assertEquals(envios, 0, acao);
    assertEquals(chamadas.length, 2, acao);
  }
});

Deno.test("rodadaDoCartao: envio que falha registra p_ok falso; exceção e erro do banco não derrubam", async () => {
  const { db, chamadas } = bancoDoCartao({
    [RPC_CARTAO_DEVIDO]: { data: { gatilho: "meio_dia" }, error: null },
    [RPC_CARTAO_ABRIR]: CARTAO_ABERTO,
  });
  const r = await rodadaDoCartao(db, { agora: RELOGIO, enviarAoDono: () => Promise.resolve({ status: 500, body: null }) });
  assertEquals(r, { acao: "cartao", erro: "envio_falhou" });
  assertEquals(chamadas[2].args.p_ok, false);
  const quebra: Db = { rpc: () => { throw new Error("rede"); } };
  assertEquals((await rodadaDoCartao(quebra, { agora: RELOGIO, enviarAoDono: () => Promise.resolve({ status: 200, body: null }) })).acao, null);
  const erro = bancoDoCartao({ [RPC_CARTAO_DEVIDO]: { data: null, error: { code: "PGRST202" } } });
  assertEquals(await rodadaDoCartao(erro.db, { agora: RELOGIO, enviarAoDono: () => Promise.resolve({ status: 200, body: null }) }), { acao: null, erro: "PGRST202" });
});

Deno.test("as duas listas de origens do retorno são iguais", async () => {
  const { ORIGENS_DO_RETORNO } = await import("../_shared/whatsapp/registro-do-envio.ts");
  const fonte = await Deno.readTextFile(new URL("./rodada.ts", import.meta.url));
  const lista = /const ORIGENS_DO_RETORNO: ReadonlySet<string> = new Set\(\[([^\]]*)\]\)/.exec(fonte);
  assert(lista, "a lista sumiu de rodada.ts");
  assertEquals([...lista[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]), [...ORIGENS_DO_RETORNO]);
});
