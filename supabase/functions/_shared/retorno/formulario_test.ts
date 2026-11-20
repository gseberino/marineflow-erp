// rr-f1-11 (20/11/2026): o formulário de cadastro do dono, que o número novo recebe depois do recibo.
//
// 1. O texto do banco (T36 de _retorno_texto, migration 20270214100200) é o mesmo do validador (FORMULARIO_DE_CADASTRO), que é
//    o texto do dono, exato. Se alguém mudar um, este teste lembra de mudar o outro.
// 2. O validador deixa o formulário passar do limite de linhas, só ele e só exato; as outras regras continuam valendo.
//
// Frases e números inventados. Exige --allow-read (o test:edge roda com --allow-all).
// Reverter: apagar este arquivo junto com FORMULARIO_DE_CADASTRO.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dirname, fromFileUrl, resolve } from "https://deno.land/std@0.224.0/path/mod.ts";
import { type ContextoDoValidador, FORMULARIO_DE_CADASTRO, validarSaida } from "./validador.ts";

const AQUI = dirname(fromFileUrl(import.meta.url));
const MIGRATION = resolve(AQUI, "..", "..", "..", "migrations", "20270214100200_retorno_f1_formulario_numero_novo.sql");

/** O texto exato que o dono mandou no cartão rr-f1-11 (respostas/rr-f1-11, 20/11/2026). */
const DO_DONO = [
  "Dados para preenchimento do Orçamento / Ordem de Serviço:",
  "",
  "Nome:",
  "CPF:",
  "Data Nasc.:",
  "Cel/Whats:",
  "Endereço:",
  "CEP:",
  "Email:",
  "Local fixo Lancha/Veículo:",
  "Nome (Embarcação):",
  "Fabricante:",
  "Ano:",
  "Modelo:",
  "Tamanho:",
  "Placa (Veículo):",
  "",
  "É muito importante ter o máximo de informações preenchidas.",
].join("\n");

/** O contexto que o retorno_pegar monta: sem campo, o texto inteiro é trecho do modelo (_retorno_contexto_do_validador). */
function contexto(textosDoCliente: string[] = ["quanto fica para instalar uma bateria?"], texto = FORMULARIO_DE_CADASTRO): ContextoDoValidador {
  return {
    audiencia: "cliente", datas_permitidas: [], horas_permitidas: [], nome_permitido: null, nomes_de_outros: [], os_permitidas: [],
    textos_do_cliente: textosDoCliente, trechos_do_modelo: [texto],
    marcas: { tem_proposta: false, tem_topo: false, cliente_ouviu: false, conferida: false },
  };
}

Deno.test("o formulário do validador é o texto do dono, exato", () => {
  assertEquals(FORMULARIO_DE_CADASTRO, DO_DONO);
});

Deno.test("o T36 do banco (migration 20270214100200) é o mesmo texto do validador", async () => {
  const sql = await Deno.readTextFile(MIGRATION);
  const m = sql.match(/when 'coleta_numero_novo\/formulario' then[^\n]*\n\s*E'((?:[^'\\]|''|\\.)*)'/);
  assert(m, "o T36 sumiu da migration");
  const doBanco = m[1].replace(/''/g, "'").replace(/\\n/g, "\n").replace(/\\\\/g, "\\");
  assertEquals(doBanco, FORMULARIO_DE_CADASTRO);
});

Deno.test("o formulário passa no validador ao cliente, mesmo com 18 linhas", () => {
  assert(FORMULARIO_DE_CADASTRO.split("\n").length > 5);
  assertEquals(validarSaida(FORMULARIO_DE_CADASTRO, contexto()), { ok: true });
  // o cliente que já mandou parte dos dados não faz o formulário virar eco
  assertEquals(validarSaida(FORMULARIO_DE_CADASTRO, contexto(["Nome: Fulano de Tal", "CPF: ainda vou mandar"])), { ok: true });
});

Deno.test("só o texto exato escapa do tamanho: uma letra a mais, ou com dado, reprova", () => {
  const maisUm = FORMULARIO_DE_CADASTRO + " ";
  assertEquals(validarSaida(maisUm, contexto(undefined, maisUm)), { ok: false, regras: ["tamanho"] });
  const outraLinha = FORMULARIO_DE_CADASTRO.replace("Nome:\n", "Nome:\nNome:\n");
  assertEquals(validarSaida(outraLinha, contexto(undefined, outraLinha)), { ok: false, regras: ["tamanho"] });
  const comTelefone = FORMULARIO_DE_CADASTRO.replace("Cel/Whats:", "Cel/Whats: 47 99999-1234");
  const r = validarSaida(comTelefone, contexto(undefined, comTelefone));
  assertEquals(r.ok, false);
  assert(!r.ok && r.regras.includes("dado_pessoal"));
});
