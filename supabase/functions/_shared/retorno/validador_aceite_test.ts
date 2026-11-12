// Retorno rápido, F5 (P4.2 e P4.3): o texto ao cliente não afirma aprovação sem o aceite registrado pelo dono, e os textos
// O01–O22 da F5 passam no validador real em toda forma dos campos.
//
// 1. Um negativo por forma (aprovado, aprovação, fechado, confirmado, aceito), sem a marca aceite_registrado: reprova só em
//    afirmacao_sem_dado. Com a marca, passa. A marca ausente vale falso; marca que não é booleano reprova em 'contexto'.
// 2. O O13 ("Fechado, Ana! Anotei a aprovação…") passa com a marca e reprova sem ela.
// 3. Ao parceiro, "aguardando aprovação" continua passando em validarSaidaAoParceiro: a regra é só da audiência cliente.
// 4. O21 e O22 (a legenda do PDF), com {validade} em hoje, amanhã e "<dia da semana> (dd/mm)" e o contexto de
//    _orcamento_legenda (os_permitidas = [o número do ORÇ]), passam: o número que o banco permitiu não é placa.
// 5. Cada texto O01–O22, copiado literal de _orcamento_texto (20270112100300_retorno_f5_textos.sql, conferido contra a
//    migration), montado com toda forma dos campos e o contexto que _orcamento_contexto_do_validador monta, passa.
// Nomes, datas e números inventados.
//
// Reverter: apagar este arquivo junto com a regra AFIRMA_APROVACAO de validador.ts.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type ContextoAoParceiro,
  type ContextoDoValidador,
  type RegraDoValidador,
  validarSaida,
  validarSaidaAoParceiro,
} from "./validador.ts";

const MIGRATION = new URL("../../../migrations/20270112100300_retorno_f5_textos.sql", import.meta.url);

// ─── Os textos (spec P4.1, literais) ────────────────────────────────────────────────────────────────────────────

const O: Record<string, [string, string]> = {
  O01: ["orc_lembrete/padrao", "Oi, {nome}! Conseguiu ver o orçamento {do_servico}? Se tiver alguma dúvida ou quiser ajustar algo, é só responder por aqui que eu passo ao Gustavo."],
  O02: ["orc_lembrete/padrao_apresentacao", "Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Conseguiu ver o orçamento {do_servico} que o Gustavo te mandou? Se tiver alguma dúvida ou quiser ajustar algo, é só responder por aqui que eu passo a ele."],
  O03: ["orc_lembrete/sem_servico", "Oi, {nome}! Conseguiu ver o orçamento que o Gustavo te mandou? Se tiver alguma dúvida ou quiser ajustar algo, é só responder por aqui que eu passo a ele."],
  O04: ["orc_lembrete/sem_servico_apresentacao", "Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Conseguiu ver o orçamento que o Gustavo te mandou? Se tiver alguma dúvida ou quiser ajustar algo, é só responder por aqui que eu passo a ele."],
  O05: ["orc_vespera/padrao", "Oi, {nome}! O orçamento {do_servico} vale até {validade}. Se quiser seguir ou ajustar algo, é só responder por aqui."],
  O06: ["orc_vespera/padrao_apresentacao", "Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. O orçamento {do_servico} que o Gustavo te mandou vale até {validade}. Se quiser seguir ou ajustar algo, é só responder por aqui."],
  O07: ["orc_vespera/sem_servico", "Oi, {nome}! O orçamento que o Gustavo te mandou vale até {validade}. Se quiser seguir ou ajustar algo, é só responder por aqui."],
  O08: ["orc_vespera/sem_servico_apresentacao", "Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. O orçamento que o Gustavo te mandou vale até {validade}. Se quiser seguir ou ajustar algo, é só responder por aqui."],
  O09: ["orc_encerramento/padrao", "Oi, {nome}! Como não tive retorno, vou encerrar por aqui o orçamento {do_servico}. Se quiser retomar, é só me chamar que o Gustavo atualiza para você."],
  O10: ["orc_encerramento/padrao_apresentacao", "Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Como não tive retorno sobre o orçamento {do_servico} que o Gustavo te mandou, vou encerrar por aqui. Se quiser retomar, é só me chamar que ele atualiza para você."],
  O11: ["orc_encerramento/sem_servico", "Oi, {nome}! Como não tive retorno sobre o orçamento que o Gustavo te mandou, vou encerrar por aqui. Se quiser retomar, é só me chamar que ele atualiza para você."],
  O12: ["orc_encerramento/sem_servico_apresentacao", "Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Como não tive retorno sobre o orçamento que o Gustavo te mandou, vou encerrar por aqui. Se quiser retomar, é só me chamar que ele atualiza para você."],
  O13: ["orc_fechado/padrao", "Fechado, {nome}! Anotei a aprovação do orçamento {do_servico} de {dia_envio}. O Gustavo te passa a data por aqui."],
  O14: ["orc_fechado/padrao_apresentacao", "Fechado, {nome}! Aqui é a Claudia, assistente virtual da HBR. Anotei a aprovação do orçamento {do_servico} de {dia_envio}. O Gustavo te passa a data por aqui."],
  O15: ["orc_fechado/sem_servico", "Fechado, {nome}! Anotei a aprovação do orçamento de {dia_envio}. O Gustavo te passa a data por aqui."],
  O16: ["orc_fechado/sem_servico_apresentacao", "Fechado, {nome}! Aqui é a Claudia, assistente virtual da HBR. Anotei a aprovação do orçamento de {dia_envio}. O Gustavo te passa a data por aqui."],
  O17: ["orc_dados_nota/cpf_endereco", "{nome}, para emitir a nota, me passa o CPF e o endereço completo, com CEP? Pode ser por aqui mesmo."],
  O18: ["orc_dados_nota/cnpj_endereco", "{nome}, para emitir a nota, me passa o CNPJ e o endereço completo, com CEP? Pode ser por aqui mesmo."],
  O19: ["orc_dados_nota/documento", "{nome}, para emitir a nota, me passa o {documento}? Pode ser por aqui mesmo."],
  O20: ["orc_dados_nota/endereco", "{nome}, para emitir a nota, me passa o endereço completo, com CEP? Pode ser por aqui mesmo."],
  O21: ["orc_legenda/padrao", "Segue o {numero}, conforme solicitado. Ele vale até {validade}. Qualquer dúvida, estamos à disposição."],
  O22: ["orc_legenda/linha", "Ele vale até {validade}."],
};

// As formas de cada campo. {validade}: _orcamento_validade_texto (hoje, amanhã ou "<dia> (dd/mm)", qualquer dia da semana);
// {do_servico}: a tabela fechada de _retorno_familia_rotulo, uma e duas famílias; {nome}: _agenda_nome_curto.
const VALIDADES = ["hoje", "amanhã", "segunda (14/12)", "terça (15/12)", "quarta (16/12)", "quinta (17/12)", "sexta (18/12)",
  "sábado (19/12)", "domingo (20/12)"];
const SERVICOS = ["das baterias", "de energia solar", "do inversor", "do carregador", "do ar-condicionado", "da geladeira",
  "da antena Starlink", "da iluminação", "da parte hidráulica", "do gerador", "do aquecedor", "dos equipamentos de navegação",
  "das baterias e de energia solar", "do ar-condicionado e da geladeira"];
const NOMES = ["Ana", "João", "Pedro"];
const DIAS_ENVIO = ["01/12", "08/12", "31/12"];
const NUMEROS = ["ORÇ-00151", "ORÇ-123", "ORÇ-98765", "ORÇ-12345678"];
const DOCUMENTOS = ["CPF", "CNPJ"];
// O que a cliente escreveu (só para o eco): frases inventadas, inclusive as que repetem palavras do modelo.
const DO_CLIENTE = ["Pode fazer.", "Fechado!", "conseguiu ver o orçamento das baterias?", "me passa o CPF e o endereço por favor",
  "Ele vale até quando?"];

// A marca aceita qualquer valor aqui, para o teste do contexto malformado ("sim" no lugar de booleano).
type Marcas = Omit<ContextoDoValidador["marcas"], "aceite_registrado"> & { aceite_registrado?: unknown };
const SEM_MARCAS: ContextoDoValidador["marcas"] = { tem_proposta: false, tem_topo: false, cliente_ouviu: false, conferida: false };

function compor(modelo: string, d: Record<string, string>): string {
  return modelo.replace(/\{([a-z_]+)\}/g, (_, campo: string) => {
    const v = d[campo];
    if (!v) throw new Error(`teste sem o campo ${campo}`);
    return v;
  });
}

/** O texto cortado nos valores dados (o maior primeiro), como os trechos do modelo do banco. */
function trechos(texto: string, valores: string[]): string[] {
  let c = texto;
  for (const v of [...valores].filter((x) => x.trim() !== "").sort((a, b) => b.length - a.length)) c = c.split(v).join("\u001f");
  return c.split("\u001f").filter((p) => p.trim() !== "");
}

/** O contexto de _orcamento_contexto_do_validador: datas = {validade} (e o dd/mm dela) e {dia_envio}; cortes no nome e nas datas. */
function ctxDoOrcamento(texto: string, tipo: string, d: Record<string, string>, extra: Partial<ContextoDoValidador> = {}) {
  const ddmm = d.validade?.match(/[0-9]{2}\/[0-9]{2}/)?.[0];
  const datas = [d.validade, ddmm, d.dia_envio].filter((x): x is string => !!x);
  return {
    audiencia: "cliente" as const,
    datas_permitidas: datas,
    horas_permitidas: [] as string[],
    nome_permitido: d.nome ?? null,
    nomes_de_outros: [] as string[],
    os_permitidas: [] as string[],
    textos_do_cliente: DO_CLIENTE,
    trechos_do_modelo: trechos(texto, [d.nome ?? "", d.validade ?? "", d.dia_envio ?? ""]),
    marcas: { ...SEM_MARCAS, aceite_registrado: tipo === "orc_fechado" } as ContextoDoValidador["marcas"],
    ...extra,
  };
}

/** O contexto de _orcamento_legenda: o número do ORÇ permitido, a validade, e O21 e O22 sem os campos. */
function ctxDaLegenda(numero: string, validade: string): ContextoDoValidador {
  return {
    audiencia: "cliente",
    datas_permitidas: [validade],
    horas_permitidas: [],
    nome_permitido: null,
    nomes_de_outros: [],
    os_permitidas: [numero],
    textos_do_cliente: [],
    trechos_do_modelo: [...O.O21[1].split(/\{[a-z_]+\}/), ...O.O22[1].split(/\{[a-z_]+\}/)].filter((p) => p.trim() !== ""),
    marcas: SEM_MARCAS,
  };
}

function ctxSimples(texto: string, marcas: Marcas = SEM_MARCAS): ContextoDoValidador {
  return {
    audiencia: "cliente",
    datas_permitidas: [],
    horas_permitidas: [],
    nome_permitido: "Ana",
    nomes_de_outros: [],
    os_permitidas: [],
    textos_do_cliente: ["Pode fazer."],
    trechos_do_modelo: trechos(texto, ["Ana"]),
    marcas: marcas as ContextoDoValidador["marcas"],
  };
}

function regras(texto: string, ctx: unknown): RegraDoValidador[] {
  const r = validarSaida(texto, ctx as ContextoDoValidador);
  return r.ok ? [] : r.regras;
}

// ─── 1. Um negativo por forma ──────────────────────────────────────────────────────────────────────────────────

const FORMAS = [
  "Oi, Ana! Está aprovado.", "Oi, Ana! Está aprovada.", "Oi, Ana! Ficam aprovados.", "Oi, Ana! Recebi a aprovação.",
  "Oi, Ana! Recebi a APROVAÇÃO.", "Oi, Ana! Recebi a aprovacao.", "Oi, Ana! Está fechado.", "Oi, Ana! Está fechada.",
  "Oi, Ana! Está confirmado.", "Oi, Ana! Está confirmada.", "Oi, Ana! Ficam confirmados.", "Oi, Ana! Está aceito.",
  "Oi, Ana! Está aceita.", "Oi, Ana! Ficam aceitos.", "Fechado, Ana!",
];

Deno.test("aceite: cada forma de 'aprovação' sem a marca reprova só em afirmacao_sem_dado", () => {
  for (const t of FORMAS) assertEquals(regras(t, ctxSimples(t)), ["afirmacao_sem_dado"], t);
});

Deno.test("aceite: com a marca aceite_registrado, as mesmas formas passam", () => {
  for (const t of FORMAS) assertEquals(validarSaida(t, ctxSimples(t, { ...SEM_MARCAS, aceite_registrado: true })), { ok: true }, t);
});

Deno.test("aceite: a marca ausente ou falsa vale falso; marca que não é booleano reprova em 'contexto'", () => {
  const t = "Oi, Ana! Está aprovado.";
  assertEquals(regras(t, ctxSimples(t, { ...SEM_MARCAS, aceite_registrado: false })), ["afirmacao_sem_dado"]);
  assertEquals(regras(t, ctxSimples(t, { ...SEM_MARCAS, aceite_registrado: "sim" })), ["contexto", "afirmacao_sem_dado"]);
  // Sem a marca no contexto, os textos de antes passam como antes (a F1 a F4 não mandam a marca).
  const t2 = "Oi, Ana! O Gustavo retorna para você.";
  assertEquals(validarSaida(t2, ctxSimples(t2)), { ok: true });
});

Deno.test("aceite: o verbo e as palavras parecidas não são afirmação", () => {
  for (const t of ["Oi, Ana! Vou confirmar com o Gustavo.", "Oi, Ana! Quem confirma é o Gustavo.", "Oi, Ana! Para aprovar, é só responder.",
    "Oi, Ana! Ele vai fechar a agenda.", "Oi, Ana! Pode aceitar quando quiser.", "Oi, Ana! A fechadura chegou.",
    "Oi, Ana! O aceite é seu."]) {
    assertEquals(validarSaida(t, ctxSimples(t)), { ok: true }, t);
  }
});

// ─── 2. O O13 ───────────────────────────────────────────────────────────────────────────────────────────────────

Deno.test("aceite: o O13 passa com a marca e reprova sem ela", () => {
  const d = { nome: "Ana", do_servico: "de energia solar", dia_envio: "08/12" };
  const t = compor(O.O13[1], d);
  assertEquals(t, "Fechado, Ana! Anotei a aprovação do orçamento de energia solar de 08/12. O Gustavo te passa a data por aqui.");
  assertEquals(validarSaida(t, ctxDoOrcamento(t, "orc_fechado", d)), { ok: true });
  assertEquals(regras(t, ctxDoOrcamento(t, "orc_lembrete", d)), ["afirmacao_sem_dado"]);
  const semMarca = ctxDoOrcamento(t, "orc_fechado", d);
  delete (semMarca.marcas as Marcas).aceite_registrado;
  assertEquals(regras(t, semMarca), ["afirmacao_sem_dado"]);
});

// ─── 3. Ao parceiro ─────────────────────────────────────────────────────────────────────────────────────────────

Deno.test("aceite: ao parceiro, 'aguardando aprovação' continua passando", () => {
  const t = "Pátio HBR: o motorhome de João S. está aguardando aprovação do orçamento.";
  const ctx: ContextoAoParceiro = {
    audiencia: "parceiro",
    datas_permitidas: [],
    horas_permitidas: [],
    nome_permitido: null,
    nomes_de_outros: [],
    nomes_da_lista: ["João S."],
    papel_do_parceiro: "contratante",
    os_permitidas: [],
    textos_do_cliente: [],
    trechos_do_modelo: trechos(t, ["João S.", "motorhome"]),
    marcas: SEM_MARCAS,
  };
  assertEquals(validarSaidaAoParceiro(t, ctx), { ok: true });
});

// ─── 4. A legenda do PDF ────────────────────────────────────────────────────────────────────────────────────────

Deno.test("legenda: O21 e O22 passam em toda forma de {validade}, com o número do ORÇ permitido", () => {
  for (const numero of NUMEROS) {
    for (const validade of VALIDADES) {
      const ctx = ctxDaLegenda(numero, validade);
      const o21 = compor(O.O21[1], { numero, validade });
      const o22 = compor(O.O22[1], { validade });
      assertEquals(validarSaida(o21, ctx), { ok: true }, o21);
      assertEquals(validarSaida(o22, ctx), { ok: true }, o22);
    }
  }
});

Deno.test("legenda: o O21 é a legenda padrão de legendaDoPdf com o trecho 'Ele vale até {validade}.' da L01", () => {
  const padrao = "Segue o ORÇ-00151, conforme solicitado. Qualquer dúvida, estamos à disposição.";   // legendaDoPdf (whatsapp.ts)
  const trechoL01 = "Ele vale até {validade}.";                                                    // L01 (20261208100300)
  const [antes, depois] = padrao.split(" Qualquer dúvida");
  assertEquals(compor(O.O21[1], { numero: "ORÇ-00151", validade: "terça (15/12)" }),
    `${antes} ${compor(trechoL01, { validade: "terça (15/12)" })} Qualquer dúvida${depois}`);
  assertEquals(O.O22[1], trechoL01);
});

Deno.test("legenda: outro ORÇ, outra data ou valor na legenda reprovam", () => {
  const ctx = ctxDaLegenda("ORÇ-00151", "terça (15/12)");
  assert(regras(compor(O.O21[1], { numero: "ORÇ-00152", validade: "terça (15/12)" }), ctx).includes("os_de_outro"));
  assert(regras(compor(O.O21[1], { numero: "ORÇ-00151", validade: "quarta (16/12)" }), ctx).includes("data_fora"));
  assert(regras(`${compor(O.O21[1], { numero: "ORÇ-00151", validade: "terça (15/12)" })} Total R$ 1.500,00.`, ctx).includes("dinheiro"));
  // A placa de verdade continua dado pessoal, mesmo com um ORÇ permitido.
  assert(regras(`${compor(O.O21[1], { numero: "ORÇ-00151", validade: "terça (15/12)" })} Placa ABC1D23.`, ctx).includes("dado_pessoal"));
  // O número permitido não libera a placa colada a ele: só o trecho coberto pelo número.
  assertEquals(regras("Segue o ORC-0015, conforme solicitado.", ctxDaLegenda("ORÇ-00151", "hoje")).includes("dado_pessoal"), true);
});

// ─── 5. Os 22 textos ────────────────────────────────────────────────────────────────────────────────────────────

Deno.test("textos: O01–O22 estão na migration, palavra por palavra, com o par tipo/variante", async () => {
  const sql = (await Deno.readTextFile(MIGRATION)).replace(/\r\n/g, "\n");
  for (const [id, [par, texto]] of Object.entries(O)) {
    assert(sql.includes(`when '${par}' then -- ${id}\n      '${texto}'`), `${id}: texto ou par divergente da migration`);
  }
});

Deno.test("textos: cada O01–O22 passa no validador em toda forma dos campos", () => {
  let n = 0;
  for (const [id, [par, modelo]] of Object.entries(O)) {
    const tipo = par.split("/")[0];
    const campos = new Set([...modelo.matchAll(/\{([a-z_]+)\}/g)].map((m) => m[1]));
    const opcoes: Record<string, string[]> = {
      nome: campos.has("nome") ? NOMES : [""],
      do_servico: campos.has("do_servico") ? SERVICOS : [""],
      validade: campos.has("validade") ? VALIDADES : [""],
      dia_envio: campos.has("dia_envio") ? DIAS_ENVIO : [""],
      numero: campos.has("numero") ? NUMEROS : [""],
      documento: campos.has("documento") ? DOCUMENTOS : [""],
    };
    for (const nome of opcoes.nome) for (const do_servico of opcoes.do_servico) for (const validade of opcoes.validade) {
      for (const dia_envio of opcoes.dia_envio) for (const numero of opcoes.numero) for (const documento of opcoes.documento) {
        const d = { nome, do_servico, validade, dia_envio, numero, documento };
        const t = compor(modelo, d);
        const ctx = tipo === "orc_legenda" ? ctxDaLegenda(numero || "ORÇ-00151", validade) : ctxDoOrcamento(t, tipo, d);
        assertEquals(validarSaida(t, ctx), { ok: true }, `${id}: ${t}`);
        assert(t.length <= 400 && t.split("\n").length <= 5, `${id}: tamanho`);
        n++;
      }
    }
  }
  assert(n > 1000, `poucas combinações (${n})`);
});

Deno.test("textos: só o 'Fechado' (O13–O16) afirma aprovação; os outros passam sem a marca", () => {
  for (const [id, [par, modelo]] of Object.entries(O)) {
    const tipo = par.split("/")[0];
    const d = { nome: "Ana", do_servico: "das baterias", validade: "terça (15/12)", dia_envio: "08/12", numero: "ORÇ-00151", documento: "CPF" };
    const t = compor(modelo, d);
    const ctx = tipo === "orc_legenda" ? ctxDaLegenda("ORÇ-00151", "terça (15/12)") : ctxDoOrcamento(t, "orc_lembrete", d);
    if (tipo === "orc_fechado") assertEquals(regras(t, ctx), ["afirmacao_sem_dado"], id);
    else assertEquals(validarSaida(t, ctx), { ok: true }, id);
  }
});
