// Retorno rápido, F3 (P4.2): as legendas L01 a L08 e o M07 da migration passam no validador real, com o contexto que
// retorno_legenda_do_orcamento monta (as 9 chaves de ContextoDoValidador). Os textos são lidos da migration, para o teste
// falhar se o texto gravado no banco mudar. Frases, nomes e datas inventados.
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { validarSaida } from "./validador.ts";

const MIGRATION = new URL("../../../migrations/20261208100300_retorno_f3_textos.sql", import.meta.url);

const NOME = "Rodrigo";
const SERVICO = "das baterias";
const VALIDADE = "terça (15/12)";
const DIA = "15/12";
const PERGUNTA = "quanto fica pra trocar as baterias da lancha?";

const LEGENDAS: Record<string, string> = {
  padrao: "{nome}, segue o orçamento {do_servico}. Ele vale até {validade}. Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.",
  padrao_apresentacao: "Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Segue o orçamento {do_servico}, que vale até {validade}. Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.",
  sem_servico: "{nome}, segue o orçamento que você pediu. Ele vale até {validade}. Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.",
  sem_servico_apresentacao: "Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Segue o orçamento que você pediu, que vale até {validade}. Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.",
  sem_nome: "Olá! Aqui é a Claudia, assistente virtual da HBR. Segue o orçamento {do_servico}, que vale até {validade}. Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.",
  sem_nome_servico: "Olá! Aqui é a Claudia, assistente virtual da HBR. Segue o orçamento que você pediu, que vale até {validade}. Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.",
  sem_nome_ja_apresentada: "Segue o orçamento {do_servico}, que vale até {validade}. Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.",
  sem_nome_servico_ja_apresentada: "Segue o orçamento que você pediu, que vale até {validade}. Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.",
};
const M07 = "para passar o valor certo, o Gustavo precisa ver o serviço no local. Ele combina o melhor dia com você por aqui.";

function preencher(modelo: string) {
  return modelo.replaceAll("{nome}", NOME).replaceAll("{do_servico}", SERVICO).replaceAll("{validade}", VALIDADE);
}

// O mesmo corte da função SQL: os valores dos {campos}, o maior primeiro.
function contexto(texto: string, cortes: string[], extra: Record<string, unknown> = {}) {
  let c = texto;
  for (const v of [...cortes].sort((a, b) => b.length - a.length)) c = c.split(v).join("\u001f");
  return {
    audiencia: "cliente" as const,
    datas_permitidas: [VALIDADE, DIA],
    horas_permitidas: [] as string[],
    nome_permitido: NOME,
    nomes_de_outros: [] as string[],
    os_permitidas: [] as string[],
    textos_do_cliente: [PERGUNTA],
    trechos_do_modelo: c.split("\u001f").filter((p) => p.trim()),
    marcas: { tem_proposta: true, tem_topo: false, cliente_ouviu: false, conferida: false },
    ...extra,
  };
}

const lerMigration = () => Deno.readTextFile(MIGRATION);

Deno.test("L01 a L08 estão na migration, palavra por palavra", async () => {
  const sql = await lerMigration();
  for (const [variante, texto] of Object.entries(LEGENDAS)) {
    assert(sql.includes(`when 'orcamento_pdf/${variante}' then`), `falta a variante ${variante}`);
    assert(sql.includes(`'${texto}'`), `texto divergente em ${variante}`);
  }
  assert(sql.includes(`'${M07}'`), "falta o M07");
});

Deno.test("cada legenda passa no validador real", () => {
  for (const [variante, modelo] of Object.entries(LEGENDAS)) {
    const texto = preencher(modelo);
    const semNome = !modelo.includes("{nome}");
    const cortes = [semNome ? "" : NOME, VALIDADE, modelo.includes("{do_servico}") ? SERVICO : ""].filter(Boolean);
    const r = validarSaida(texto, contexto(texto, cortes, semNome ? { nome_permitido: null } : {}));
    assertEquals(r, { ok: true }, `${variante}: ${texto}`);
  }
});

Deno.test("o cliente que escreveu 'o orçamento das baterias' não reprova a legenda em eco: o {do_servico} é trecho do banco", async () => {
  const sql = await lerMigration();
  const corte = /select x from unnest\(array\[([^\]]+)\]\) as x/.exec(sql)?.[1];
  assertEquals(corte, "v_nome, v_validade", "o corte da legenda não pode tirar o {do_servico} dos trechos");
  const frases = ["e o orçamento das baterias, saiu?", "me passa o orcamento das baterias por favor", "preciso o orçamento das baterias"];
  for (const variante of ["padrao", "padrao_apresentacao", "sem_nome", "sem_nome_ja_apresentada"]) {
    const modelo = LEGENDAS[variante];
    const texto = preencher(modelo);
    const semNome = !modelo.includes("{nome}");
    const cortes = [semNome ? "" : NOME, VALIDADE].filter(Boolean);
    for (const frase of frases) {
      const r = validarSaida(texto, contexto(texto, cortes, { textos_do_cliente: [frase], ...(semNome ? { nome_permitido: null } : {}) }));
      assertEquals(r, { ok: true }, `${variante}: ${frase}`);
    }
  }
});

Deno.test("M07 passa nas aberturas que a saída usa", () => {
  const maior = M07[0].toUpperCase() + M07.slice(1);
  const casos = [
    `${NOME}, ${M07}`,                                                            // apos_recibo
    `Oi, ${NOME}! ${maior}`,                                                      // padrao
    `Oi, ${NOME}! Aqui é a Claudia, assistente virtual da HBR. ${maior}`,          // padrao_apresentacao
    `Olá! Aqui é a Claudia, assistente virtual da HBR. ${maior}`,                  // sem_nome
  ];
  for (const t of casos) {
    const semNome = !t.includes(NOME);
    const r = validarSaida(t, contexto(t, semNome ? [] : [NOME], { datas_permitidas: [], ...(semNome ? { nome_permitido: null } : {}) }));
    assertEquals(r, { ok: true }, t);
  }
});

Deno.test("legenda adulterada reprova: valor, número do ORÇ e data fora", () => {
  const base = preencher(LEGENDAS.padrao);
  const cortes = [NOME, VALIDADE, SERVICO];
  const reprova = (t: string) => {
    const r = validarSaida(t, contexto(base, cortes));   // o contexto é o do texto certo: o adulterado não entra nos trechos do modelo
    assert(!r.ok, `devia reprovar: ${t}`);
    return r.ok ? [] : r.regras;
  };
  assert(reprova(`${base} O total é R$ 1.500,00.`).includes("dinheiro"));
  assert(reprova(`${base} Número ORÇ-00151.`).includes("os_de_outro"));
  assert(reprova(`${base} Até segunda (21/12).`).includes("data_fora"));
});

Deno.test("legenda com a validade errada reprova em data_fora", () => {
  const texto = preencher(LEGENDAS.padrao).replace(VALIDADE, "quinta (17/12)");
  const r = validarSaida(texto, contexto(texto, [NOME, "quinta (17/12)", SERVICO]));
  assert(!r.ok && r.regras.includes("data_fora"), `não reprovou: ${JSON.stringify(r)}`);
});

Deno.test("nenhuma legenda passa de 400 caracteres", () => {
  for (const modelo of Object.values(LEGENDAS)) assert(preencher(modelo).length <= 400, modelo);
});
