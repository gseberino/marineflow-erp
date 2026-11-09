// Retorno rápido, F2 (P6.2): todo texto da F2 passa no validador real, com o contexto que a P10 monta.
// Os textos são os literais de retorno_f2_modelos.sql. Nada aqui vem do banco. Sem o contexto certo, o validador reprova.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { validarSaida } from "./validador.ts";

const NOME = "Rodrigo";
const PERGUNTA = "como está o serviço?";

function contexto(texto: string, cortes: string[], extra: Record<string, unknown> = {}) {
  let c = texto;
  for (const v of cortes) c = c.split(v).join("\u001f");
  return {
    audiencia: "cliente" as const,
    datas_permitidas: [] as string[],
    horas_permitidas: [] as string[],
    nome_permitido: NOME,
    nomes_de_outros: [] as string[],
    os_permitidas: [] as string[],
    textos_do_cliente: [PERGUNTA],
    marcas: { tem_proposta: false, tem_topo: false, cliente_ouviu: false, conferida: false },
    trechos_do_modelo: c.split("\u001f").filter((p) => p.trim()),
    ...extra,
  };
}

const MODELOS = [
  "Oi, Rodrigo! O serviço no seu motorhome está aguardando a chegada de uma peça. Assim que ela chegar, o Gustavo avisa você.",
  "Rodrigo, o serviço no seu motorhome está aguardando a chegada de uma peça. Assim que ela chegar, aviso você por aqui.",
  "Oi, Rodrigo! O serviço no seu motorhome está pronto. Qual o melhor dia para você buscar? O Gustavo combina o horário por aqui.",
  "Olá! Aqui é a Claudia, assistente virtual da HBR. O serviço no seu motorhome está em andamento hoje. O Gustavo passa as novidades por aqui.",
  "Rodrigo, pode sim: o serviço está liberado para retirada. É só combinar o horário com o Gustavo por aqui.",
  "Rodrigo, ainda não dá para retirar, porque o serviço não terminou. O Gustavo chama você para combinar.",
];

Deno.test("M01 a M06 passam no validador, sem cortar {no_bem}", () => {
  for (const t of MODELOS) assertEquals(validarSaida(t, contexto(t, [NOME])), { ok: true }, t);
});

Deno.test("M02 e M02b passam com a data na lista, e reprovam com a data fora", () => {
  const m02 = "Rodrigo, a peça chegou sim, no dia 09/12. Agora o Gustavo vai marcar o dia do serviço.";
  const m02b = "Rodrigo, a peça do serviço chegou no dia 09/12. Agora o Gustavo vai marcar o dia do serviço.";
  for (const t of [m02, m02b]) {
    assertEquals(validarSaida(t, contexto(t, [NOME, "09/12"], { datas_permitidas: ["09/12"] })), { ok: true }, t);
    assertEquals(validarSaida(t, contexto(t, [NOME, "09/12"], { datas_permitidas: ["10/12"] })).ok, false, t);
  }
});

const COM_PRAZO = [
  "Oi, Rodrigo! Retirar antes depende de como está o serviço, e quem confirma é o Gustavo. Ele retorna para você ainda hoje.",
  "Anotado, Rodrigo! Passei ao Gustavo como serviço extra: ele avalia e informa o valor antes de fazer qualquer coisa. Ele retorna para você ainda hoje.",
  "Oi, Rodrigo! Vou confirmar com o Gustavo, e ele retorna para você ainda hoje.",
];

Deno.test("T29, T30 e T31 passam com o prazo na lista, e reprovam sem ele", () => {
  for (const t of COM_PRAZO) {
    assertEquals(validarSaida(t, contexto(t, [NOME, "ainda hoje"], { datas_permitidas: ["ainda hoje"] })), { ok: true }, t);
    assertEquals(validarSaida(t, contexto(t, [NOME, "ainda hoje"])).ok, false, t);
  }
});

const EM_PREPARACAO = [
  "Oi, Rodrigo! Seu orçamento já está em preparação com o Gustavo, e ele retorna para você ainda hoje.",
  "Rodrigo, seu orçamento está em preparação e o Gustavo está conferindo os valores. Ele retorna para você ainda hoje.",
  "Seu orçamento está em preparação e o Gustavo está conferindo os valores. Ele retorna para você ainda hoje.",
];

Deno.test("T32, T33 e T34: \"em preparação\" só passa com a marca tem_proposta", () => {
  const com = { tem_proposta: true, tem_topo: false, cliente_ouviu: false, conferida: false };
  for (const t of EM_PREPARACAO) {
    assertEquals(validarSaida(t, contexto(t, [NOME], { marcas: com })), { ok: true }, t);
    assertEquals(validarSaida(t, contexto(t, [NOME])).ok, false, t);
  }
});

Deno.test("T35 passa com a marca tem_proposta", () => {
  const t = "Obrigada! Seu orçamento já está em preparação com o Gustavo. Como posso chamar você?";
  const com = { tem_proposta: true, tem_topo: false, cliente_ouviu: false, conferida: false };
  assertEquals(validarSaida(t, contexto(t, [], { nome_permitido: null, marcas: com })), { ok: true });
});

Deno.test("nenhum texto da F2 passa de 400 caracteres", () => {
  for (const t of [...MODELOS, ...COM_PRAZO, ...EM_PREPARACAO]) assertEquals(t.length <= 400, true, t);
});
