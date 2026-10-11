// O registro único de pergunta ativa: normalização, números, sim/não/ok (inclusive transcrição de
// áudio), as 7 regras de "quem responde" com o empate de 2 min, a citação de linha fechada, a trava
// do ai-agent e as chamadas ao banco (que nunca lançam).
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  encerrarPerguntasExternas,
  type EstadoDoTelefone,
  interromperPergunta,
  lerEstadoDoTelefone,
  lerNumero,
  lerSimNao,
  marcarPerguntaEnviada,
  normalizarResposta,
  pareceRespostaCurta,
  passoLegivel,
  type PerguntaAtiva,
  quemResponde,
  registrarPerguntaExterna,
  telefoneOcupado,
  textoDoDesempate,
  travaDaConfirmacao,
} from "./pergunta-ativa.ts";

// ─── normalização ─────────────────────────────────────────────────────────────────────────

Deno.test("normalizarResposta: 🎤, aspas, acento, maiúsculas, espaços e pontuação final", () => {
  const casos: Array<[string, string]> = [
    ["  Um.  ", "um"],
    ["🎤 Opção dois.", "opcao dois"],
    ['"Sim!"', "sim"],
    ["🎤 “Não, tá errado.”", "nao, ta errado"],
    ["OS-00112", "os-00112"],
    ["R$  62,50 ", "r$ 62,50"],
    ["Isso   mesmo!!!", "isso mesmo"],
    ["1.", "1"],
    ["", ""],
  ];
  for (const [entrada, saida] of casos) assertEquals(normalizarResposta(entrada), saida, entrada);
});

// ─── números ──────────────────────────────────────────────────────────────────────────────

Deno.test("lerNumero: a tabela 3.4 (dígitos, extenso, ordinais, prefixos e sufixos)", () => {
  const casos: Array<[string, number | null]> = [
    ["1", 1], ["01", 1], ["1.", 1], ["1)", 1], ["um", 1], ["uma", 1], ["primeiro", 1], ["primeira", 1],
    ["opcao 2", 2], ["opcao dois", 2], ["numero 3", 3], ["a 2", 2], ["o terceiro", 3], ["dois mesmo", 2],
    ["e a 2", 2], ["a opcao 4", 4], ["item 5", 5], ["n 2", 2], ["1o", 1], ["2ª", 2], ["dez", 10], ["decimo", 10],
    ["a 3 por favor", 3], ["sexta", 6],
    // fora da faixa, vazio ou texto livre
    ["11", null], ["0", null], ["onze", null], ["", null], ["opcao", null], ["2 e 3", null], ["um dois", null],
    ["manda o 2 pro cliente", null],
  ];
  for (const [entrada, n] of casos) assertEquals(lerNumero(normalizarResposta(entrada), 10), n, entrada);
  assertEquals(lerNumero("5", 4), null, "fora do menu de 4");
  assertEquals(lerNumero("1", 0), null, "sem menu");
});

Deno.test("lerNumero: transcrição de áudio ('Um.', 'Opção dois.', 'A terceira.', 'Número 4.')", () => {
  for (const [audio, n] of [["🎤 Um.", 1], ["🎤 Opção dois.", 2], ["🎤 A terceira.", 3], ["🎤 Número 4.", 4], ["🎤 É a dois.", 2]] as const) {
    assertEquals(lerNumero(normalizarResposta(audio), 8), n, audio);
  }
});

// ─── sim / não / ok ───────────────────────────────────────────────────────────────────────

Deno.test("lerSimNao: sim só sem texto a mais; o grupo ok nunca é sim", () => {
  const sim = ["sim", "s", "isso", "isso mesmo", "confirmo", "confirma", "confirmado", "grava", "pode gravar", "sim pode", "sim, grava", "Sim!", "🎤 Sim, pode gravar.",
    // revisão de 11/10/2026: as confirmações reais que davam null
    "pode", "pode sim", "simm", "correto"];
  for (const t of sim) assertEquals(lerSimNao(normalizarResposta(t)), "sim", t);
  const nao = ["nao", "não", "n", "nao grava", "errado", "esta errado", "Tá errado.", "🎤 Não."];
  for (const t of nao) assertEquals(lerSimNao(normalizarResposta(t)), "nao", t);
  const ok = ["ok", "okay", "blz", "beleza", "certo", "ta", "tá bom", "show", "valeu", "obrigado", "pode ser", "👍", "👍🏻", "🙏🙏", "Ok.", "fechado"];
  for (const t of ok) assertEquals(lerSimNao(normalizarResposta(t)), "ok", t);
  const nada = ["sim, mas é da OS 12", "sim mas e da os 12", "não sei", "1", "cmp 124", "62,50", "pode ser que sim", "isso é do Brisa"];
  for (const t of nada) assertEquals(lerSimNao(normalizarResposta(t)), null, t);
});

// ─── quem responde ────────────────────────────────────────────────────────────────────────

const AGORA = new Date("2026-10-11T15:00:00Z");
const ABERTA_EM = "2026-10-11T14:50:00Z";

function ativa(extra: Partial<PerguntaAtiva> = {}): PerguntaAtiva {
  return {
    id: "p-cmp", origem: "comprovante", tipo: "pergunta", referencia_id: "c-1", referencia_codigo: "CMP-00124", passo: "para_que",
    opcoes: [{ n: 1, rotulo: "OS-00112 · Brisa", valor: "os:x" }, { n: 2, rotulo: "Estoque", valor: "estoque" }],
    wa_message_id: "WA-P", aberta_em: ABERTA_EM, ...extra,
  };
}

function estado(extra: Partial<EstadoDoTelefone> = {}): EstadoDoTelefone {
  return { conversa: true, dono: true, ativa: ativa(), citada: null, pendencia: null, cmp_em_contexto: null, ...extra };
}

const pendencia = (desde: string) => ({ tipo: "confirmacao" as const, id: "pa-1", titulo: "Enviar PDF ao cliente", desde });

function quem(e: EstadoDoTelefone, o: { texto?: string; citado?: string | null; valida?: boolean; comando?: "pendentes" | "comprovante" | "contexto" | null } = {}) {
  return quemResponde({
    texto: o.texto ?? "1", citado: o.citado ?? null, estado: e, ehRespostaValida: o.valida ?? true, ehComando: o.comando ?? null, agora: AGORA,
  });
}

Deno.test("regra 1: conversa desligada ou não é o dono → assistente (até comando)", () => {
  assertEquals(quem(estado({ conversa: false })).destino, "assistente");
  assertEquals(quem(estado({ dono: false })).destino, "assistente");
  assertEquals(quem(estado({ conversa: false }), { comando: "pendentes" }).destino, "assistente");
});

Deno.test("regra 2: comando explícito vence a pergunta aberta e a citação", () => {
  assertEquals(quem(estado(), { comando: "pendentes" }).destino, "pendentes");
  assertEquals(quem(estado(), { comando: "comprovante" }).destino, "comando");
  assertEquals(quem(estado({ ativa: null }), { comando: "comprovante", citado: "WA-X" }).destino, "comando");
});

Deno.test("regra 3: citação — pergunta de CMP aberta, fechada (reabrir), outra origem, fora do registro", () => {
  const citadaCmp = (status: string) => ({ id: "p-velha", origem: "comprovante" as const, tipo: "pergunta", referencia_id: "c-1", status, passo: "cobrar" });
  assertEquals(quem(estado({ citada: citadaCmp("aberta") }), { citado: "WA-P" }).destino, "comprovante");
  assertEquals(quem(estado({ citada: citadaCmp("respondida") }), { citado: "WA-V" }).destino, "comprovante_reabrir");
  assertEquals(quem(estado({ ativa: null, citada: citadaCmp("expirada") }), { citado: "WA-V", valida: false }).destino, "comprovante_reabrir");
  const citadaAssistente = { id: "p-a", origem: "assistente" as const, tipo: "confirmacao", referencia_id: "pa-1", status: "aberta", passo: null };
  assertEquals(quem(estado({ citada: citadaAssistente }), { citado: "WA-A" }).destino, "assistente");
  const fora = quem(estado(), { citado: "WA-QUALQUER" });
  assertEquals(fora, { destino: "assistente", motivo: "citou_fora_do_registro" });
});

Deno.test("regra 4: corrigir/pular/sair só com pergunta de CMP aberta (corrigir também com CMP em contexto)", () => {
  assertEquals(quem(estado(), { texto: "pular", comando: "contexto" }).destino, "comprovante");
  assertEquals(quem(estado({ ativa: null }), { texto: "pular", comando: "contexto" }).destino, "assistente");
  assertEquals(quem(estado({ ativa: null }), { texto: "sair", comando: "contexto" }).destino, "assistente");
  const ctx = { id: "c-1", codigo: "CMP-00124", situacao: "gravado", gravado: true };
  assertEquals(quem(estado({ ativa: null, cmp_em_contexto: ctx }), { texto: "corrigir valor 62,50", comando: "contexto" }).destino, "comprovante");
  assertEquals(quem(estado({ ativa: null, cmp_em_contexto: ctx }), { texto: "pular", comando: "contexto" }).destino, "assistente");
  const outra = ativa({ origem: "assistente", tipo: "confirmacao" });
  assertEquals(quem(estado({ ativa: outra }), { texto: "corrigir valor 1", comando: "contexto" }).destino, "assistente");
});

Deno.test("regra 5: empate em 1 min 59 s → ambíguo; 2 min 01 s depois → assistente; antes → comprovante", () => {
  const mais = (s: number) => new Date(Date.parse(ABERTA_EM) + s * 1000).toISOString();
  assertEquals(quem(estado({ pendencia: pendencia(mais(119)) })).destino, "ambiguo");
  assertEquals(quem(estado({ pendencia: pendencia(mais(-119)) })).destino, "ambiguo");
  assertEquals(quem(estado({ pendencia: pendencia(mais(121)) })).destino, "assistente");
  assertEquals(quem(estado({ pendencia: pendencia(mais(-121)) })).destino, "comprovante");
  assertEquals(quem(estado()).destino, "comprovante");
  assertEquals(quem(estado(), { texto: "ok" }).destino, "comprovante", "o ok também fica com o comprovante");
});

Deno.test("regra 6: pergunta de CMP aberta e texto livre → assistente (a pergunta continua aberta)", () => {
  assertEquals(quem(estado(), { texto: "quanto ficou a OS 123?", valida: false }), { destino: "assistente", motivo: "texto_livre" });
});

Deno.test("regra 7: sem pergunta de CMP (nenhuma, ou do assistente) → assistente", () => {
  assertEquals(quem(estado({ ativa: null })).destino, "assistente");
  assertEquals(quem(estado({ ativa: ativa({ origem: "lembrete_revisao", tipo: "confirmacao" }) })).destino, "assistente");
});

// ─── trava do ai-agent ────────────────────────────────────────────────────────────────────

const META = { pending_confirm_action_id: "pa-1" };

Deno.test("trava: 'sim'/'1' com a pergunta do CMP mais nova não aprova a pendência", () => {
  const e = estado({ pendencia: pendencia("2026-10-11T14:00:00Z") });
  for (const t of ["sim", "1", "ok", "Sim 4321", "sim mas é da OS 12", "não", "2"]) {
    const r = travaDaConfirmacao(e, t, META);
    assertEquals(r.travar, true, t);
    assertStringIncludes(String(r.texto), "CMP-00124 (para quê)");
    assertStringIncludes(String(r.texto), '"Enviar PDF ao cliente"');
  }
  assertEquals(travaDaConfirmacao(e, "1", { pending_options: [{ label: "a", value: "b" }] }).travar, true);
});

Deno.test("trava: não trava quando a pendência é mais nova, sem pendência, desligado, citação do assistente ou texto livre", () => {
  assertEquals(travaDaConfirmacao(estado({ pendencia: pendencia("2026-10-11T14:53:00Z") }), "sim", META).travar, false);
  assertEquals(travaDaConfirmacao(estado({ pendencia: pendencia("2026-10-11T14:51:00Z") }), "sim", META).travar, true, "empate");
  assertEquals(travaDaConfirmacao(estado(), "sim", {}).travar, false);
  assertEquals(travaDaConfirmacao(estado(), "sim", { pending_options: [] }).travar, false);
  assertEquals(travaDaConfirmacao(estado({ conversa: false }), "sim", META).travar, false);
  assertEquals(travaDaConfirmacao(null, "sim", META).travar, false);
  assertEquals(travaDaConfirmacao(estado({ ativa: null }), "sim", META).travar, false);
  const citada = { id: "p-a", origem: "assistente" as const, tipo: "confirmacao", referencia_id: "pa-1", status: "aberta", passo: null };
  assertEquals(travaDaConfirmacao(estado({ citada }), "sim", META).travar, false);
  assertEquals(travaDaConfirmacao(estado(), "manda o orçamento", META).travar, false);
});

Deno.test("textoDoDesempate: o código, o passo legível e o título, sem quebra de linha no título", () => {
  const t = textoDoDesempate(estado({ ativa: ativa({ passo: "confirmar" }), pendencia: { ...pendencia(ABERTA_EM), titulo: 'Mandar "PDF"\nao cliente' } }));
  assertEquals(
    t,
    'Fiquei na dúvida: essa resposta é para o CMP-00124 (gravar ou não) ou para o pedido "Mandar PDF ao cliente"? Responda de novo citando a mensagem certa (segure a mensagem e toque em Responder). Ou mande *cmp 124* que eu repito a pergunta do comprovante.',
  );
});

// ─── banco ────────────────────────────────────────────────────────────────────────────────

function adminFalso(respostas: Record<string, { data?: unknown; error?: unknown } | Error>) {
  const chamadas: Array<{ nome: string; args: unknown }> = [];
  return {
    chamadas,
    admin: {
      rpc(nome: string, args: unknown) {
        chamadas.push({ nome, args });
        const r = respostas[nome];
        if (r instanceof Error) return Promise.reject(r);
        return Promise.resolve({ data: r?.data ?? null, error: r?.error ?? null });
      },
    },
  };
}

function silenciar<T>(f: () => Promise<T>): Promise<T> {
  const original = console.warn;
  console.warn = () => {};
  return f().finally(() => { console.warn = original; });
}

Deno.test("lerEstadoDoTelefone: lê a forma do pergunta_rotear; erro ou desligada → conversa false", async () => {
  const rotear = {
    conversa: true, dono: true,
    ativa: { ...ativa(), opcoes: [{ n: 1, rotulo: "Pix", valor: "pix" }, { lixo: true }] },
    citada: null,
    pendencia: { tipo: "opcoes", id: null, titulo: "escolha da lista do assistente", desde: "2026-10-11T14:00:00Z" },
    cmp_em_contexto: { id: "c-1", codigo: "CMP-00124", situacao: "perguntando", gravado: false },
  };
  const ok = adminFalso({ pergunta_rotear: { data: rotear } });
  const e = await lerEstadoDoTelefone(ok.admin, "5547999990000", "WA-1");
  assertEquals(ok.chamadas[0], { nome: "pergunta_rotear", args: { p_phone: "5547999990000", p_citado: "WA-1" } });
  assertEquals(e.conversa, true);
  assertEquals(e.ativa?.opcoes, [{ n: 1, rotulo: "Pix", valor: "pix" }]);
  assertEquals(e.pendencia?.tipo, "opcoes");
  assertEquals(e.cmp_em_contexto?.codigo, "CMP-00124");

  const desligada = await lerEstadoDoTelefone(adminFalso({ pergunta_rotear: { data: { conversa: false, dono: true } } }).admin, "5547999990000", null);
  assertEquals(desligada, { conversa: false, dono: true, ativa: null, citada: null, pendencia: null, cmp_em_contexto: null });
  for (const r of [{ error: { code: "22023" } }, new Error("rede")]) {
    const x = await silenciar(() => lerEstadoDoTelefone(adminFalso({ pergunta_rotear: r }).admin, "5547999990000", null));
    assertEquals(x.conversa, false);
    assertEquals(x.dono, false);
  }
});

Deno.test("telefoneOcupado: livre, ocupado; erro → ocupado com origem 'erro' (quem chama adia)", async () => {
  assertEquals(await telefoneOcupado(adminFalso({ pergunta_ocupado: { data: { ocupado: false, por: null } } }).admin, "5547999990000"), { ocupado: false, por: null });
  const por = { origem: "comprovante", titulo: "CMP-00124", desde: ABERTA_EM };
  assertEquals(await telefoneOcupado(adminFalso({ pergunta_ocupado: { data: { ocupado: true, por } } }).admin, "5547999990000"), { ocupado: true, por });
  for (const r of [{ error: { code: "XX000" } }, new Error("rede"), { data: null }]) {
    const x = await silenciar(() => telefoneOcupado(adminFalso({ pergunta_ocupado: r }).admin, "5547999990000"));
    assertEquals(x.ocupado, true);
    assertEquals(x.por?.origem, "erro");
  }
});

Deno.test("registrar/marcar/encerrar: argumentos do contrato e nunca lançam", async () => {
  const b = adminFalso({ pergunta_registrar_externa: { data: { id: "p-novo", substituiu: null } } });
  const id = await registrarPerguntaExterna(b.admin, { phone: "5547999990000", origem: "assistente", tipo: "confirmacao", referencia_id: "pa-1", titulo: "Enviar PDF" });
  assertEquals(id, "p-novo");
  assertEquals(b.chamadas[0].args, { p: { phone: "5547999990000", origem: "assistente", tipo: "confirmacao", referencia_id: "pa-1", titulo: "Enviar PDF" } });
  assertEquals(await registrarPerguntaExterna(adminFalso({ pergunta_registrar_externa: { data: { id: null, desligada: true } } }).admin, {
    phone: "5547999990000", origem: "lembrete_revisao", tipo: "confirmacao", referencia_id: "x", titulo: "t",
  }), null);
  assertEquals(await silenciar(() => registrarPerguntaExterna(adminFalso({ pergunta_registrar_externa: new Error("x") }).admin, {
    phone: "5547999990000", origem: "assistente", tipo: "opcoes", referencia_id: "s", titulo: "t",
  })), null);

  const m = adminFalso({ pergunta_marcar_enviada: { data: null } });
  await marcarPerguntaEnviada(m.admin, "p-1", "WA-1");
  await marcarPerguntaEnviada(m.admin, null, "WA-1");
  await marcarPerguntaEnviada(m.admin, "p-1", null);
  // sem pergunta não chama; sem o id do WhatsApp chama assim mesmo (revisão de 11/10/2026): marca
  // enviada_em, que separa a resposta à pergunta da mensagem que chegou antes dela
  assertEquals(m.chamadas, [
    { nome: "pergunta_marcar_enviada", args: { p_id: "p-1", p_wa_message_id: "WA-1" } },
    { nome: "pergunta_marcar_enviada", args: { p_id: "p-1", p_wa_message_id: null } },
  ]);
  await silenciar(() => marcarPerguntaEnviada(adminFalso({ pergunta_marcar_enviada: new Error("x") }).admin, "p-1", "WA-1"));

  const f = adminFalso({ pergunta_encerrar_externa: { data: 1 } });
  await encerrarPerguntasExternas(f.admin, "5547999990000", "respondida");
  assertEquals(f.chamadas[0].args, { p_phone: "5547999990000", p_status: "respondida" });
  await silenciar(() => encerrarPerguntasExternas(adminFalso({ pergunta_encerrar_externa: { error: { code: "x" } } }).admin, "5547999990000", "cancelada"));
});

Deno.test("logs do registro: só o código, nunca o texto do dono", async () => {
  const saida: string[] = [];
  const original = console.warn;
  console.warn = (...a: unknown[]) => { saida.push(a.join(" ")); };
  try {
    await lerEstadoDoTelefone(adminFalso({ pergunta_rotear: { error: { code: "XX000", message: "texto segredo do dono" } } }).admin, "5547999990000", "WA-1");
  } finally {
    console.warn = original;
  }
  assertEquals(saida.length, 1);
  assertEquals(saida[0].includes("segredo"), false);
  assertEquals(saida[0].includes("5547999990000"), false);
});

// ─── revisão de 11/10/2026: as regras novas do "quem responde" ─────────────────────────────

function quemComFlags(
  e: EstadoDoTelefone,
  o: { texto?: string; citado?: string | null; valida?: boolean; ultima?: boolean; dica?: boolean; naoEntendida?: boolean } = {},
) {
  return quemResponde({
    texto: o.texto ?? "1", citado: o.citado ?? null, estado: e, ehRespostaValida: o.valida ?? false, ehComando: null, agora: AGORA,
    ehRespostaAUltima: o.ultima, ehDica: o.dica, ehNaoEntendida: o.naoEntendida,
  });
}

const CMP_CURTO = { id: "c-1", codigo: "CMP-00124", situacao: "perguntando", gravado: false };
const PERGUNTA_VELHA = {
  id: "p-velha", referencia_id: "c-1", referencia_codigo: "CMP-00124", passo: "para_que",
  opcoes: [{ n: 1, rotulo: "Estoque", valor: "estoque" }], aberta_em: ABERTA_EM,
};

Deno.test("citou a FOTO de um CMP (não uma pergunta) → foto_do_cmp; citação de pergunta continua valendo antes", () => {
  assertEquals(quemComFlags(estado({ ativa: null, citado_cmp: CMP_CURTO }), { citado: "WA-FOTO", texto: "OS 112" }), {
    destino: "foto_do_cmp", motivo: "citou_a_foto",
  });
  const citadaCmp = { id: "p-v", origem: "comprovante" as const, tipo: "pergunta", referencia_id: "c-1", status: "aberta", passo: "valor" };
  assertEquals(quemComFlags(estado({ citada: citadaCmp, citado_cmp: CMP_CURTO }), { citado: "WA-P" }).destino, "comprovante");
});

Deno.test("pergunta do CMP interrompida (o dono falou com o assistente depois) → o '1' seguinte é ambíguo", () => {
  const e = estado({ ativa: ativa({ interrompida_em: "2026-10-11T14:55:00Z" }) });
  assertEquals(quemComFlags(e, { valida: true }), { destino: "ambiguo", motivo: "interrompida" });
  assertStringIncludes(textoDoDesempate(e), "a conversa com o assistente");
  assertStringIncludes(textoDoDesempate(e), "*cmp 124*");
});

Deno.test("a pendência do assistente acabou de substituir a pergunta do CMP: '1'/'sim' em < 2 min → ambíguo", () => {
  const doAssistente = ativa({ id: "p-a", origem: "assistente", tipo: "confirmacao", referencia_codigo: null, aberta_em: "2026-10-11T14:51:00Z" });
  const e = estado({ ativa: doAssistente, cmp_substituido: PERGUNTA_VELHA });
  assertEquals(quemComFlags(e, { texto: "1" }), { destino: "ambiguo", motivo: "substituido" });
  assertEquals(quemComFlags(e, { texto: "sim" }).destino, "ambiguo");
  assertEquals(quemComFlags(e, { texto: "manda o orçamento do Brisa" }).destino, "assistente", "texto livre segue ao assistente");
  // 2 min ou mais entre as duas: a pendência é a pergunta da vez
  const longe = estado({ ativa: { ...doAssistente, aberta_em: "2026-10-11T14:53:00Z" }, cmp_substituido: PERGUNTA_VELHA });
  assertEquals(quemComFlags(longe, { texto: "1" }).destino, "assistente");
  // a trava do ai-agent diz o mesmo
  assertEquals(travaDaConfirmacao(e, "sim", META).travar, true);
  assertStringIncludes(String(travaDaConfirmacao(e, "sim", META).texto), "CMP-00124 (para quê)");
  assertEquals(travaDaConfirmacao(longe, "sim", META).travar, false);
});

Deno.test("sem pergunta aberta: resposta de dado à última pergunta do CMP (< 24 h) → comprovante_reabrir", () => {
  const e = estado({ ativa: null, ultima_do_cmp: PERGUNTA_VELHA });
  assertEquals(quemComFlags(e, { texto: "estoque", ultima: true }), { destino: "comprovante_reabrir", motivo: "resposta_atrasada" });
  assertEquals(quemComFlags(e, { texto: "quanto ficou a OS 123?", ultima: false }).destino, "assistente");
  // com outra pergunta aberta, a última do CMP não vale
  assertEquals(quemComFlags(estado({ ativa: ativa({ origem: "assistente", tipo: "confirmacao" }), ultima_do_cmp: PERGUNTA_VELHA }), { ultima: true }).destino, "assistente");
});

Deno.test("texto solto logo depois da foto → dica do CMP que chegou; com a pergunta aberta, resposta válida vence", () => {
  const chegando = { id: "c-2", codigo: "CMP-00125" };
  assertEquals(quemComFlags(estado({ ativa: null, cmp_chegando: chegando }), { texto: "essa é da OS do Brisa", dica: true }), {
    destino: "dica", motivo: "dica_depois_da_foto",
  });
  assertEquals(quemComFlags(estado({ cmp_chegando: chegando }), { texto: "2", valida: true, dica: true }).destino, "comprovante");
  assertEquals(quemComFlags(estado({ ativa: null, cmp_chegando: chegando }), { texto: "bom dia", dica: false }).destino, "assistente");
});

Deno.test("pergunta do CMP aberta e mensagem curta não entendida → nao_entendi (a pergunta de novo)", () => {
  assertEquals(quemComFlags(estado(), { texto: "hmm", naoEntendida: true }), { destino: "nao_entendi", motivo: "nao_entendi" });
  assertEquals(quemComFlags(estado({ ativa: null }), { texto: "hmm", naoEntendida: true }).destino, "assistente");
});

Deno.test("lerEstadoDoTelefone: lê citado_cmp, cmp_substituido, ultima_do_cmp, cmp_chegando, enviada_em e interrompida_em", async () => {
  const rotear = {
    conversa: true, dono: true,
    ativa: { ...ativa(), enviada_em: "2026-10-11T14:50:02Z", interrompida_em: "2026-10-11T14:55:00Z" },
    citada: null, pendencia: null, cmp_em_contexto: null,
    citado_cmp: { id: "c-1", codigo: "CMP-00124", situacao: "lido", gravado: false },
    cmp_substituido: { ...PERGUNTA_VELHA, opcoes: [{ n: 1, rotulo: "Estoque", valor: "estoque" }, { lixo: true }] },
    ultima_do_cmp: { id: "sem-referencia" },
    cmp_chegando: { id: "c-2", codigo: "CMP-00125" },
  };
  const e = await lerEstadoDoTelefone(adminFalso({ pergunta_rotear: { data: rotear } }).admin, "5547999990000", null);
  assertEquals(e.ativa?.enviada_em, "2026-10-11T14:50:02Z");
  assertEquals(e.ativa?.interrompida_em, "2026-10-11T14:55:00Z");
  assertEquals(e.citado_cmp?.codigo, "CMP-00124");
  assertEquals(e.cmp_substituido?.opcoes, [{ n: 1, rotulo: "Estoque", valor: "estoque" }]);
  assertEquals(e.ultima_do_cmp, null, "sem referencia_id não vale");
  assertEquals(e.cmp_chegando, { id: "c-2", codigo: "CMP-00125" });
});

Deno.test("interromperPergunta: chama pergunta_interromper e nunca lança", async () => {
  const b = adminFalso({ pergunta_interromper: { data: true } });
  await interromperPergunta(b.admin, "5547999990000");
  assertEquals(b.chamadas, [{ nome: "pergunta_interromper", args: { p_phone: "5547999990000" } }]);
  await silenciar(() => interromperPergunta(adminFalso({ pergunta_interromper: new Error("rede") }).admin, "5547999990000"));
  await silenciar(() => interromperPergunta(adminFalso({ pergunta_interromper: { error: { code: "XX000" } } }).admin, "5547999990000"));
});

Deno.test("F3: o passo 'banco' (pergunta do extrato) tem nome legível e segue as mesmas regras de quem responde", () => {
  assertEquals(passoLegivel("banco"), "a linha do extrato");
  const banco = ativa({ passo: "banco" });
  assertEquals(quem(estado({ ativa: banco })).destino, "comprovante");
  // empate com a pendência do assistente vale igual (nunca liga uma linha que o dono não estava respondendo)
  assertEquals(quem(estado({ ativa: banco, pendencia: pendencia(ABERTA_EM) })).destino, "ambiguo");
  assertEquals(quem(estado({ ativa: { ...banco, interrompida_em: ABERTA_EM } })).destino, "ambiguo");
  assertStringIncludes(textoDoDesempate(estado({ ativa: banco, pendencia: pendencia(ABERTA_EM) })), "CMP-00124 (a linha do extrato)");
});

Deno.test("pareceRespostaCurta: sim/não/ok ou só número; frase não", () => {
  for (const t of ["1", "sim", "não", "ok", "🎤 Dois.", "12"]) assertEquals(pareceRespostaCurta(t), true, t);
  for (const t of ["manda o orçamento", "", "quanto ficou?"]) assertEquals(pareceRespostaCurta(t), false, t);
});
