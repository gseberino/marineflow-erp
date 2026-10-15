// Os comandos do dono sobre a manhã nova: o que é lido e — o principal — o que NÃO pode colidir com a
// confirmação (1/2/sim/não), com os comandos e as respostas dos comprovantes nem com o registro de
// pergunta ativa. Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-manha.md §6.2.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { diaDoAdiamento, lerComandoDoSecretario } from "./comandos.ts";
import { proximaSegunda, somarDias } from "./base.ts";
import { parseConfirmationReply, parseOptionReply } from "../ai/whatsapp-channel.ts";
import { lerComando } from "../comprovantes/respostas.ts";
import { lerPedidoDePdf } from "../ai/atalho-pdf.ts";
import {
  type EstadoDoTelefone,
  lerNumero,
  lerSimNao,
  normalizarResposta,
  pareceRespostaCurta,
  quemResponde,
  travaDaConfirmacao,
} from "../whatsapp/pergunta-ativa.ts";

const COMANDOS: Array<[string, unknown]> = [
  ["lista", { comando: "lista", filtro: null }],
  ["*Lista*", { comando: "lista", filtro: null }],
  ["lista dinheiro", { comando: "lista", filtro: "dinheiro" }],
  ["Lista de clientes", { comando: "lista", filtro: "clientes" }],
  ["lista orçamentos", { comando: "lista", filtro: "clientes" }],
  ["lista obras", { comando: "lista", filtro: "obras" }],
  ["lista contatos", { comando: "lista", filtro: "contatos" }],
  ["escritório", { comando: "escritorio" }],
  ["Escritorio.", { comando: "escritorio" }],
  ["tudo", { comando: "tudo" }],
  ["Tudo!", { comando: "tudo" }],
  ["detalhe A", { comando: "detalhe", letra: "A" }],
  ["detalhe do b", { comando: "detalhe", letra: "B" }],
  ["detalhes da letra C", { comando: "detalhe", letra: "C" }],
  ["por que o C?", { comando: "porque", letra: "C" }],
  ["Por quê o D subiu?", { comando: "porque", letra: "D" }],
  ["pq o f", { comando: "porque", letra: "F" }],
  ["A feito", { comando: "acao", letra: "A", acao: "feito" }],
  ["b já fiz", { comando: "acao", letra: "B", acao: "feito" }],
  ["C não", { comando: "acao", letra: "C", acao: "nao" }],
  ["tira G", { comando: "acao", letra: "G", acao: "tirado" }],
  ["tira o h", { comando: "acao", letra: "H", acao: "tirado" }],
  ["B amanhã", { comando: "adiar", letra: "B", quando: "amanha" }],
  ["C segunda", { comando: "adiar", letra: "C", quando: "segunda" }],
  ["C segunda-feira", { comando: "adiar", letra: "C", quando: "segunda" }],
  ["D espera", { comando: "adiar", letra: "D", quando: "espera" }],
  ["D espera até 20/10", { comando: "adiar", letra: "D", quando: { dia: 20, mes: 10 } }],
  ["F até dia 5", { comando: "adiar", letra: "F", quando: { dia: 5, mes: null } }],
  ["volta H", { comando: "volta", letra: "H", nome: null }],
  ["volta a", { comando: "volta", letra: "A", nome: null }],
  ["Volta Flávio", { comando: "volta", letra: null, nome: "flavio" }],
  ["volta o João H.", { comando: "volta", letra: null, nome: "joao h" }],
  ["A", { comando: "abrir", letra: "A" }],
  ["b", { comando: "abrir", letra: "B" }],
  ["🎤 C.", { comando: "abrir", letra: "C" }],
  ["letra D", { comando: "abrir", letra: "D" }],
];

Deno.test("lerComandoDoSecretario: lê cada comando do desenho aprovado", () => {
  for (const [texto, esperado] of COMANDOS) assertEquals(lerComandoDoSecretario(texto), esperado, texto);
});

// O que o dono manda hoje e NÃO pode virar comando do secretário.
const NAO_SAO_COMANDO = [
  // confirmação (whatsapp-channel.ts:18-19)
  "1", "2", "3", "sim", "s", "Sim", "SIM 1234", "ok", "confirmar", "não", "nao", "n", "cancelar", "2 não", "1 sim", "sim, pode",
  // a letra que seria sim/não, o "É" e as que parecem número
  "S", "N", "É", "é", "e", "o", "O", "i", "I",
  // comprovantes (comprovantes/respostas.ts:878)
  "pendentes", "pendencias", "comprovantes pendentes", "cmp 12", "CMP-124", "feito cmp 12", "cancela cmp 3 errado", "cancelar esse",
  "pular", "depois", "deixa pra depois", "sair", "pare", "parar", "corrigir valor 70", "corrigir", "obs: compra do Brisa", "lote antigo",
  // respostas a menu e à pergunta do CMP (pergunta-ativa.ts)
  "um", "dois", "opção 2", "a 2", "o terceiro", "segunda opção", "beleza", "valeu", "👍", "isso", "pix", "debito", "estoque", "empresa",
  "pessoal", "OS 12", "62,50", "ontem", "hoje",
  // conversa
  "Ah", "tudo bem", "tudo certo?", "lista de compras", "volta", "detalhe", "feito", "amanhã", "segunda", "me manda o pdf do orçamento 117",
  "cobra esse", "o 2", "quanto devo pro R?", "A e B", "A, B e C feitos",
];

Deno.test("lerComandoDoSecretario: nada da confirmação, dos comprovantes, de menu ou de conversa vira comando", () => {
  for (const t of NAO_SAO_COMANDO) assertEquals(lerComandoDoSecretario(t), null, t);
});

Deno.test("nenhum comando aprova, recusa ou escolhe opção na confirmação do assistente", () => {
  for (const [texto] of COMANDOS) {
    assertEquals(parseConfirmationReply(texto), null, `confirmação: ${texto}`);
    assertEquals(parseOptionReply(texto, 9), null, `opção: ${texto}`);
  }
});

Deno.test("nenhum comando é comando dos comprovantes nem resposta curta do registro de pergunta ativa", () => {
  for (const [texto] of COMANDOS) {
    assertEquals(lerComando(texto), null, `comprovantes: ${texto}`);
    const n = normalizarResposta(texto);
    assertEquals(lerSimNao(n), null, `sim/não/ok: ${texto}`);
    assertEquals(lerNumero(n, 99), null, `número: ${texto}`);
    assertEquals(pareceRespostaCurta(texto), false, `resposta curta: ${texto}`);
  }
});

const AGORA = new Date("2026-10-15T12:00:00Z");
function estadoComCmpNoConfirmar(): EstadoDoTelefone {
  return {
    conversa: true, dono: true,
    ativa: {
      id: "p-1", origem: "comprovante", tipo: "pergunta", referencia_id: "c-1", referencia_codigo: "CMP-00124", passo: "confirmar",
      opcoes: [], wa_message_id: "WA-P", aberta_em: "2026-10-15T11:59:00Z",
    },
    citada: null,
    pendencia: { tipo: "confirmacao", id: "pend-1", titulo: "Enviar lembrete", desde: "2026-10-15T11:00:00Z" },
    cmp_em_contexto: null,
  };
}

Deno.test("a trava do 'sim' do comprovante não segura nenhum comando (não parece confirmação)", () => {
  for (const [texto] of COMANDOS) {
    const t = travaDaConfirmacao(estadoComCmpNoConfirmar(), texto, { pending_confirm_action_id: "pend-1" });
    assertEquals(t.travar, false, texto);
  }
});

Deno.test("quemResponde: com a pergunta do CMP no 'confirmar', o comando vai ao assistente (e só com a marca)", () => {
  const base = { citado: null, estado: estadoComCmpNoConfirmar(), ehRespostaValida: true, ehComando: null, agora: AGORA };
  // sem a marca (formato antigo): o caminho de hoje — "A" seria o "ok" do CMP
  assertEquals(quemResponde({ ...base, texto: "A" }).destino, "comprovante");
  // com a marca: assistente
  for (const texto of ["A", "lista", "B feito", "tudo"]) {
    const r = quemResponde({ ...base, texto, ehComandoDoSecretario: true });
    assertEquals(r, { destino: "assistente", motivo: "comando_do_secretario" }, texto);
  }
  // citar a pergunta do CMP decide: vai ao comprovante mesmo sendo comando
  const citando = quemResponde({
    ...base, texto: "A", citado: "WA-P", ehComandoDoSecretario: true,
    estado: { ...estadoComCmpNoConfirmar(), citada: { id: "p-1", origem: "comprovante", tipo: "pergunta", referencia_id: "c-1", status: "aberta", passo: "confirmar" } },
  });
  assertEquals(citando.destino, "comprovante");
  // "pendentes" segue dos comprovantes
  assertEquals(quemResponde({ ...base, texto: "pendentes", ehComando: "pendentes", ehComandoDoSecretario: false }).destino, "pendentes");
});

Deno.test("o rascunho de orçamento abre pelo atalho do PDF (o PDF para o dono, sem o modelo)", () => {
  assertEquals(lerPedidoDePdf("me manda o pdf do ORÇ-00117"), { documento: "117", tipo: "orcamento" });
});

Deno.test("diaDoAdiamento: amanhã, segunda, espera pelo tipo e 'até dd/mm' até 90 dias", () => {
  const h = "2026-10-15"; // quinta
  const d = (q: Parameters<typeof diaDoAdiamento>[0], padrao: "amanha" | "segunda" = "segunda") =>
    diaDoAdiamento(q, h, padrao, proximaSegunda, somarDias);
  assertEquals(d("amanha"), "2026-10-16");
  assertEquals(d("segunda"), "2026-10-19");
  assertEquals(d("espera", "amanha"), "2026-10-16");
  assertEquals(d("espera", "segunda"), "2026-10-19");
  assertEquals(d({ dia: 20, mes: 10 }), "2026-10-20");
  assertEquals(d({ dia: 20, mes: null }), "2026-10-20");
  assertEquals(d({ dia: 5, mes: null }), "2026-11-05"); // o próximo dia 5
  assertEquals(d({ dia: 15, mes: 10 }), null); // hoje não é adiar (e o do ano que vem passa de 90 dias)
  assertEquals(d({ dia: 10, mes: 10 }), null); // passou: o de 2027 passa de 90 dias
  assertEquals(d({ dia: 31, mes: 11 }), null); // não existe
  assertEquals(d({ dia: 10, mes: 1 }), "2027-01-10"); // virada do ano, dentro de 90 dias
  assert(d({ dia: 20, mes: 2 }) === null, "fevereiro de 2027 passa de 90 dias");
});
