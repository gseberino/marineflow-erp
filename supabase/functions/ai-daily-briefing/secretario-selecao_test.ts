import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ASSUNTO_NAO_ENVIADOS, type Candidato, candidatoDeConversa, candidatosDoDia } from "./secretario-candidatos.ts";
import { estadoPeloHistorico, type PassagemDoHistorico, selecionar } from "./secretario-selecao.ts";
import { AGORA_1510, coleta1510, HOJE_1510 } from "./secretario-fixture.ts";

const HOJE = HOJE_1510;

function cand(ref: string, extra: Partial<Candidato> = {}): Candidato {
  return {
    familia: "cobranca", tipo: "cobranca_marco", secao: "dinheiro", referencia: ref, assunto: `cliente:${ref}`, nome: ref,
    fato: "f1", valor: 1000, desde: "2026-10-10", perdeHoje: false, elegivel: true, todoDia: false, porqueNaoSobe: null,
    titulo: `*${ref}*`, curto: ref, rotulo: ref, recomendacao: "Recomendo.", faco: "faço", alternativa: "até segunda",
    comandoAlternativo: "espera", motivo: `Subiu ${ref} ({L}).`, pedido: `pedido ${ref}`, fatos: [], ...extra,
  };
}

function passou(ref: string, extra: Partial<PassagemDoHistorico> = {}): PassagemDoHistorico {
  return {
    referencia: ref, dia: "2026-10-14", posicao: "manha", fato: "f1", acao: null, acao_em: null, adiado_ate: null, voltou_em: null,
    criado_em: "2026-10-14T10:30:00Z", ...extra,
  };
}

Deno.test("15/10: o que se perde hoje primeiro; os rascunhos viram UM item; a cobrança grande é item; letras sem E", () => {
  const sel = selecionar(candidatosDoDia(coleta1510(), AGORA_1510, HOJE), [], HOJE);
  // o pedido de orçamento do Cesar (14/10, 12:23) se perde hoje e é o mais antigo dos dois que se perdem
  // (decisão do dono, 15/10/2026); o pacote dos não enviados, que não se perde hoje, fica logo abaixo
  assertEquals(sel.manha.map((g) => [g.letra, g.pacote, g.membros[0].c.nome]), [
    ["A", false, "Cesar"],
    ["B", false, "Jorge Girardon"],
    ["C", false, "Marcelo Marco Bertoldi"],
  ]);
  assertStringIncludes(sel.manha[0].motivo, "Pode se perder hoje: o pedido chegou depois da última manhã e ninguém respondeu.");
  // um assunto só: os orçamentos montados e não enviados (de clientes diferentes) vão juntos, com a mesma letra;
  // o ORÇ-00116, já mandado ao cliente, não é "não enviado"
  const pacote = sel.lista.find((g) => g.pacote)!;
  assertEquals(pacote.membros.map((m) => m.c.nome), ["ORÇ-00117 EVERTON CARLOS PINHEIRO", "ORÇ-00118 Cliente Final"]);
  assertStringIncludes(pacote.motivo, "são 2 orçamentos de R$ 5 mil ou mais montados e ainda não enviados");
  assertStringIncludes(pacote.motivo, "R$ 141.353,70 no total; o mais antigo montado em 13/10");
  assert(pacote.quaseEntrou);
  // o rascunho pequeno (ORÇ-00115, R$ 453) fica com o cliente, fora do pacote
  assert(!pacote.membros.some((m) => m.c.nome.startsWith("ORÇ-00115")));
  const letras = sel.lista.map((g) => g.letra);
  assert(!letras.includes("E") && !letras.includes("I") && !letras.includes("N") && !letras.includes("O") && !letras.includes("S"));
  assertEquals(sel.lista[0].letra, "D");
  assertEquals(sel.lista[1].letra, "F");
  assertEquals(sel.lista.map((g) => g.membros[0].c.secao), [
    "dinheiro", "dinheiro", "clientes", "clientes", "clientes", "clientes", "clientes", "clientes", "clientes", "obras", "obras",
    "contatos", "contatos", "contatos",
  ]);
  // dentro da seção, quem podia subir pega letra primeiro: o pacote (quase entrou) antes dos outros clientes
  assertEquals(sel.lista.filter((g) => g.membros[0].c.secao === "clientes")[0].pacote, true);
  assertEquals(sel.lista.filter((g) => g.membros[0].c.secao === "contatos").map((g) => [g.letra, g.membros[0].c.tipo]), [
    ["T", "fornecedor"], ["U", "contato_sem_cadastro"], ["V", "contato_sem_cadastro"],
  ]);
  // MP: o orçamento puxa as cobranças antigas (um assunto, uma letra); Flávio: a conversa puxa a OS-00104
  assertEquals(sel.lista.find((g) => g.membros[0].c.nome.startsWith("ORÇ-00095"))!.membros.length, 3);
  assertEquals(sel.lista.find((g) => g.membros[0].c.nome === "Flávio da Igreja")!.membros.map((m) => m.c.tipo), ["cliente_sem_resposta", "os_parada"]);
  // logo abaixo: os que quase entraram, na ordem da manhã
  assertEquals(sel.logoAbaixo.map((g) => g.membros[0].c.nome), ["ORÇ-00117 EVERTON CARLOS PINHEIRO", "ORÇ-00095 MP MOTOR HOMES", "OS-00112 Nelson"]);
  assertEquals(sel.semLetra, 0);
  // o {L} do motivo vira a letra
  assertStringIncludes(sel.manha[2].motivo, "*C espera*");
});
Deno.test("quem quase entrou com fato novo: o motivo diz 'subiria porque' e a novidade, nessa ordem", () => {
  const ontem = [passou("a", { fato: "velho", posicao: "lista" }), passou("a", { fato: "velho", dia: "2026-10-13" })];
  const sel = selecionar([
    cand("g1", { valor: 9000 }), cand("g2", { valor: 8000 }), cand("g3", { valor: 7000 }),
    cand("a", { valor: 10, fato: "novo", motivo: "Subiu porque é teste ({L})." }),
  ], ontem, HOJE);
  const a = sel.lista.find((g) => g.membros[0].c.referencia === "a")!;
  assertEquals(a.motivo, `Ficou na lista: podia subir, mas passou do limite de 3 da manhã. Pela regra, subiria porque é teste (${a.letra}). Há fato novo desde a última vez.`);
});

Deno.test("cobrança grande tem lugar garantido: entra no lugar do último, e a manhã segue na ordem", () => {
  const sel = selecionar([
    cand("o1", { valor: 90000, tipo: "orcamento_parado", familia: "orcamento", secao: "clientes" }),
    cand("o2", { valor: 80000, tipo: "orcamento_parado", familia: "orcamento", secao: "clientes" }),
    cand("o3", { valor: 70000, tipo: "orcamento_parado", familia: "orcamento", secao: "clientes" }),
    cand("g", { valor: 6000, tipo: "cobranca_grande", todoDia: true }),
    cand("hoje", { valor: 10, perdeHoje: true }),
  ], [], HOJE);
  // o que se perde hoje primeiro, depois o maior valor; a cobrança grande toma o lugar do o2 (o3 nem chega)
  assertEquals(sel.manha.map((g) => g.membros[0].c.referencia), ["hoje", "o1", "g"]);
  assertEquals(sel.lista.filter((g) => g.quaseEntrou).map((g) => g.membros[0].c.referencia), ["o2", "o3"]);
  // adiada (ou "não") ela não força nada: o dono decidiu
  const adiada = selecionar([
    cand("o1", { valor: 90000 }), cand("o2", { valor: 80000 }), cand("o3", { valor: 70000 }),
    cand("g", { valor: 6000, tipo: "cobranca_grande", todoDia: true }),
  ], [passou("g", { acao: "adiado", acao_em: "2026-10-14T12:00:00Z", adiado_ate: "2026-10-19" })], HOJE);
  assertEquals(adiada.manha.map((g) => g.membros[0].c.referencia), ["o1", "o2", "o3"]);
});

Deno.test("pacote dos não enviados: vale a soma na ordem; 1 só é item comum; o que já apareceu vai junto sem fato novo", () => {
  const rasc = (ref: string, valor: number, extra: Partial<Candidato> = {}) => cand(ref, {
    tipo: "orcamento_nao_enviado", familia: "orcamento", secao: "clientes", assunto: ASSUNTO_NAO_ENVIADOS, valor,
    nome: `ORÇ-${ref} Cliente`, ...extra,
  });
  // dois de R$ 6 mil (R$ 12 mil juntos) passam uma cobrança de R$ 10 mil (maior valor, entre grupos)
  const sel = selecionar([rasc("1", 6000), rasc("2", 6000), cand("c", { valor: 10000, tipo: "cobranca_marco" })], [], HOJE);
  assertEquals(sel.manha.map((g) => [g.pacote, g.membros.length]), [[true, 2], [false, 1]]);
  // um rascunho só: item comum (o texto do orçamento e a letra pedem o PDF)
  const um = selecionar([rasc("1", 6000)], [], HOJE);
  assertEquals([um.manha[0].pacote, um.manha[0].membros.length], [false, 1]);
  // ontem os dois apareceram; hoje entrou um terceiro: o pacote volta com os três
  const ontem = [passou("1", { fato: "f1" }), passou("2", { fato: "f1" })];
  const hoje = selecionar([rasc("1", 6000), rasc("2", 6000), rasc("3", 7000)], ontem, HOJE);
  assertEquals(hoje.manha.length, 1);
  assertEquals(hoje.manha[0].membros.map((m) => [m.c.referencia, m.estado.lugar]), [["3", "manha"], ["1", "lista"], ["2", "lista"]]);
  // sem nada novo, o pacote inteiro vai para a lista (uma letra só)
  const igual = selecionar([rasc("1", 6000), rasc("2", 6000)], ontem, HOJE);
  assertEquals([igual.manha.length, igual.lista.length, igual.lista[0].pacote], [0, 1, true]);
});

Deno.test("ordem: o que se perde hoje vem antes do maior valor; depois o mais antigo", () => {
  const sel = selecionar([
    cand("grande", { valor: 90000 }),
    cand("hoje", { valor: 10, perdeHoje: true }),
    cand("velho", { valor: 500, desde: "2026-09-01" }),
    cand("novo", { valor: 500, desde: "2026-10-12" }),
  ], [], HOJE);
  assertEquals(sel.manha.map((g) => g.membros[0].c.referencia), ["hoje", "grande", "velho"]);
  assertEquals(sel.lista.map((g) => g.membros[0].c.referencia), ["novo"]);
});

Deno.test("repetição: 2º dia só com fato novo; sem fato novo vai para a lista", () => {
  const ontem = [passou("x")];
  const igual = estadoPeloHistorico(cand("x"), ontem, HOJE);
  assertEquals(igual.lugar, "lista");
  assertStringIncludes(igual.motivo!, "já apareceu de manhã em 14/10 e não há fato novo");
  const novo = estadoPeloHistorico(cand("x", { fato: "f2" }), ontem, HOJE);
  assertEquals([novo.lugar, novo.fatoNovo], ["manha", true]);
  // na lista ontem (não de manhã): não conta como mostrado
  assertEquals(estadoPeloHistorico(cand("x"), [passou("x", { posicao: "lista" })], HOJE).lugar, "manha");
  // a passagem de HOJE (um segundo disparo) não conta
  assertEquals(estadoPeloHistorico(cand("x"), [passou("x", { dia: HOJE })], HOJE).lugar, "manha");
  // nunca 3 manhãs seguidas sem fato novo
  const tres = [passou("x", { dia: "2026-10-13" }), passou("x", { dia: "2026-10-14", posicao: "lista" })];
  assertEquals(estadoPeloHistorico(cand("x"), tres, HOJE).lugar, "lista");
});

Deno.test("cobrança grande fica toda manhã (sem fato novo e até depois do 'feito')", () => {
  const grande = cand("g", { tipo: "cobranca_grande", todoDia: true });
  assertEquals(estadoPeloHistorico(grande, [passou("g"), passou("g", { dia: "2026-10-13" })], HOJE).lugar, "manha");
  assertEquals(estadoPeloHistorico(grande, [passou("g", { acao: "feito", acao_em: "2026-10-14T12:00:00Z" })], HOJE).lugar, "manha");
  // "não" e "tira" valem também para ela (o dono decidiu)
  assertEquals(estadoPeloHistorico(grande, [passou("g", { acao: "nao", acao_em: "2026-10-14T12:00:00Z" })], HOJE).lugar, "lista");
  assertEquals(estadoPeloHistorico(grande, [passou("g", { acao: "tirado", acao_em: "2026-10-14T12:00:00Z" })], HOJE).lugar, "fora");
});

Deno.test("ações: tirado e feito somem até o fato mudar; não fica na lista; adiado espera a data", () => {
  const em = "2026-10-14T12:00:00Z";
  assertEquals(estadoPeloHistorico(cand("x"), [passou("x", { acao: "tirado", acao_em: em })], HOJE).lugar, "fora");
  assertEquals(estadoPeloHistorico(cand("x", { fato: "f2" }), [passou("x", { acao: "tirado", acao_em: em })], HOJE).lugar, "manha");
  assertEquals(estadoPeloHistorico(cand("x"), [passou("x", { acao: "feito", acao_em: em })], HOJE).lugar, "fora");
  const nao = estadoPeloHistorico(cand("x"), [passou("x", { acao: "nao", acao_em: em })], HOJE);
  assertEquals(nao.lugar, "lista");
  assertStringIncludes(nao.motivo!, 'você respondeu "não" em 14/10');
  const adiado = estadoPeloHistorico(cand("x"), [passou("x", { acao: "adiado", acao_em: em, adiado_ate: "2026-10-19" })], HOJE);
  assertEquals([adiado.lugar, adiado.adiadoAte], ["lista", "2026-10-19"]);
  assertStringIncludes(adiado.motivo!, "adiado até segunda (19/10)");
  // o adiamento venceu: volta como novo, mesmo tendo aparecido de manhã antes
  const venceu = estadoPeloHistorico(cand("x"), [
    passou("x", { dia: "2026-10-13", acao: "adiado", acao_em: "2026-10-13T12:00:00Z", adiado_ate: HOJE, criado_em: "2026-10-13T10:30:00Z" }),
    passou("x", { dia: "2026-10-14", posicao: "lista" }),
  ], HOJE);
  assertEquals([venceu.lugar, venceu.fatoNovo], ["manha", false]);
  // "ignorado" não é ação do dono: vale a regra da repetição
  assertEquals(estadoPeloHistorico(cand("x"), [passou("x", { acao: "ignorado", acao_em: em })], HOJE).lugar, "lista");
});

Deno.test("volta X: o que veio antes não conta (o assunto sobe de novo)", () => {
  const hist = [passou("x", { acao: null, voltou_em: "2026-10-14T15:00:00Z" })];
  assertEquals(estadoPeloHistorico(cand("x"), hist, HOJE).lugar, "manha");
  // uma passagem DEPOIS do volta (numa manhã seguinte) volta a contar
  const depois = [...hist, passou("x", { dia: "2026-10-14", criado_em: "2026-10-14T16:00:00Z" })];
  assertEquals(estadoPeloHistorico(cand("x"), depois, HOJE).lugar, "lista");
});

Deno.test("um assunto, uma letra: o principal é o que pode subir, os outros vão junto", () => {
  const sel = selecionar([
    cand("conversa", { assunto: "cliente:1", valor: 0, elegivel: true, familia: "cliente" }),
    cand("cobranca", { assunto: "cliente:1", valor: 3000, elegivel: false, porqueNaoSobe: "Ficou na lista: x." }),
  ], [], HOJE);
  assertEquals(sel.manha.length, 1);
  assertEquals(sel.manha[0].membros.map((m) => m.c.referencia), ["conversa", "cobranca"]);
  assertEquals(sel.lista.length, 0);
});

Deno.test("domingo e feriado (max 0): nada sobe; quem podia subir vai para a lista com o motivo do dia", () => {
  const sel = selecionar([cand("a"), cand("b", { elegivel: false, porqueNaoSobe: "Ficou na lista: y." })], [], HOJE, 0, "Ficou na lista: domingo, nada sobe de manhã.");
  assertEquals(sel.manha.length, 0);
  assertEquals(sel.lista.map((g) => g.letra), ["A", "B"]);
  assertStringIncludes(sel.lista[0].motivo, "domingo, nada sobe de manhã");
});

Deno.test("passou das 21 letras: o resto fica sem letra e é contado", () => {
  const muitos = Array.from({ length: 25 }, (_, i) => cand(`r${String(i).padStart(2, "0")}`, { valor: 1000 + i }));
  const sel = selecionar(muitos, [], HOJE);
  assertEquals(sel.manha.length, 3);
  assertEquals(sel.lista.filter((g) => g.letra).length, 18);
  assertEquals(sel.semLetra, 4);
});

Deno.test("dois pedidos de orçamento do dia: só o mais antigo vai na frente; o outro segue a ordem comum, sem a frase", () => {
  const pedido = (fone: string, em: string) => candidatoDeConversa({
    phone: fone, contato: fone, categoria: "contato", client_id: null, last_inbound_at: em, last_body: "Qual o valor?",
    recebidas: [{ body: "Qual o valor?", em }], diasComMensagemSua: 0,
  }, AGORA_1510, 0);
  const sel = selecionar([
    pedido("5547900000011", "2026-10-15T09:00:00Z"), pedido("5547900000012", "2026-10-14T20:00:00Z"),
    cand("g1", { valor: 9000 }), cand("g2", { valor: 8000 }),
  ], [], HOJE);
  // no pior caso, o pedido do dia ocupa 1 dos 3 lugares
  assertEquals(sel.manha.map((g) => g.membros[0].c.nome), ["5547900000012", "g1", "g2"]);
  assertStringIncludes(sel.manha[0].motivo, "Pode se perder hoje: o pedido chegou depois da última manhã");
  const outro = sel.lista.find((g) => g.membros[0].c.nome === "5547900000011")!;
  assertEquals([outro.quaseEntrou, outro.membros[0].c.perdeHoje], [true, false]);
  assert(!outro.motivo.includes("o pedido chegou depois da última manhã"), outro.motivo);
  // o pedido que já apareceu de manhã com a mesma mensagem não ocupa o lugar: vai para a lista (repetição)
  const ontem = [passou("fone:5547900000012", { fato: "2026-10-14T20:00:00.000Z" })];
  const sel2 = selecionar([
    pedido("5547900000011", "2026-10-15T09:00:00Z"), pedido("5547900000012", "2026-10-14T20:00:00Z"),
    cand("g1", { valor: 9000 }), cand("g2", { valor: 8000 }),
  ], ontem, HOJE);
  assertEquals(sel2.manha.map((g) => g.membros[0].c.nome), ["5547900000011", "g1", "g2"]);
});
