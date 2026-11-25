// Recebimento baixado pelo boleto na manhã nova (24/11/2026): sem baixa o texto é o de antes, byte a byte; com ela, uma
// linha no fim (depois dos pagamentos, antes da sugestão de imprimir), só em dia útil. O leitor nunca lança e a baixa
// desfeita (sem conta casada) não aparece.
// Revisão de 24/11/2026: a janela conta desde a última manhã útil ENTREGUE; a baixa desfeita e casada de novo à mão não
// sai como "Baixei sozinho" (o registro da linha decide); várias contas do mesmo cliente dizem valor e vencimento de
// cada uma; o nome de chamar não sobra só com o ramo nem termina em "-".
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { montarDosDados } from "./secretario.ts";
import { AGORA_1510, coleta1510, deHoje1510, HOJE_1510 } from "./secretario-fixture.ts";
import {
  baixasDePe, comRecebidosPeloBoleto, contasDaBaixaDePe, desdeAUltimaManha, desdeAUltimaManhaEntregue, lerRecebidosPeloBoleto,
  linhaDosRecebidosPeloBoleto, nomeDeChamar, type RecebidoPeloBoleto,
} from "./secretario-boleto.ts";
import { linhaDasVencidas, pagamentosDaResposta } from "../_shared/pagamentos/semana.ts";
import { lerComandoDoSecretario } from "../_shared/secretario/comandos.ts";

const APOLO = "APOLO INDUSTRIA E COMERCIO DE VEICULOS DE RECREACAO LTDA";

const base = () => ({
  hoje: HOJE_1510, agora: AGORA_1510, coleta: coleta1510(), historico: [],
  naRua: { total: 21026, n: 5 }, deHoje: deHoje1510(),
  escritorio: { propostas: null, alertas: null, regras: null, debitosSemLoja: null, entradas: null },
});

const apolo = (valor: number, vencimento: string): RecebidoPeloBoleto => ({ cliente: "Apolo", clienteId: "c-apolo", valor, vencimento });
const UM = [apolo(5237.99, "2026-10-16")];
const DOIS = [apolo(5237.99, "2026-10-16"), apolo(5238.02, "2026-11-13")];
const HOJE = "2026-11-25";

const FRASE_DE_UM = "Baixei sozinho pelo boleto: Apolo, R$ 5.237,99 (venceu 16/10) — o banco mostrou o crédito no dia do vencimento. " +
  "Não era? Diga *desfaz a baixa de Apolo*.";
const FRASE_DE_DOIS = "Baixei sozinho pelo boleto 2 recebimentos de Apolo: R$ 5.237,99 (venceu 16/10) e R$ 5.238,02 (venceu 13/11) — " +
  "o banco mostrou o crédito no dia do vencimento de cada um. Não era? Diga *desfaz a baixa de Apolo*.";

// ─── O nome de chamar ──────────────────────────────────────────────────────────────────────────

Deno.test("nomeDeChamar: a razão social para no ramo; o apelido do cadastro vale inteiro; sem nome = null", () => {
  assertEquals(nomeDeChamar({ name: APOLO, display_name: null }), "Apolo");
  assertEquals(nomeDeChamar({ name: APOLO, display_name: "Apolo Trailers" }), "Apolo Trailers");
  assertEquals(nomeDeChamar({ name: "MP MOTOR HOMES LTDA" }), "MP Motor Homes");
  assertEquals(nomeDeChamar({ name: "COMERCIAL SILVA E FILHOS LTDA" }), "Comercial Silva e Filhos");
  assertEquals(nomeDeChamar({ name: "SILVA E COMERCIO DE PECAS S/A" }), "Silva");
  assertEquals(nomeDeChamar({ name: "João Luiz Hang" }), "João Luiz Hang");
  // palavras inteiras até 24 caracteres, sem "…" e sem terminar em "de"/"da" (o nome entra num comando)
  assertEquals(nomeDeChamar({ name: "MARCELO MARCO BERTOLDI DE ALBUQUERQUE" }), "Marcelo Marco Bertoldi");
  assertEquals(nomeDeChamar({ name: "  " }), null);
  assertEquals(nomeDeChamar(null), null);
});

// (24/11/2026, revisão) Medido nos 566 cadastros: 2 saíam "Industria" (clientes diferentes, o mesmo nome de chamar) e 9
// terminavam em "-" ou "&" — e o nome entra em "desfaz a baixa de …".
Deno.test("nomeDeChamar: razão social que começa pelo ramo sai com a palavra que identifica; nada de '-' ou '&' no fim", () => {
  assertEquals(nomeDeChamar({ name: "INDUSTRIA E COMERCIO SUL PRAIANA LTDA - EPP" }), "Sul Praiana");
  assertEquals(nomeDeChamar({ name: "INDUSTRIA E COMERCIO DE LATICINIOS FORMOSA LTDA" }), "Laticinios Formosa");
  assertEquals(nomeDeChamar({ name: "LUIS MARCONDES MORAES - EPP" }), "Luis Marcondes Moraes");
  assertEquals(nomeDeChamar({ name: "S Jose do Nascimento - ME" }), "S Jose do Nascimento");
  assertEquals(nomeDeChamar({ name: "SCHAEFER & CIA LTDA" }), "Schaefer");
  // o ramo na frente fica quando o nome cabe inteiro
  assertEquals(nomeDeChamar({ name: "COMERCIAL SILVA LTDA" }), "Comercial Silva");
  assertEquals(nomeDeChamar({ name: "ITAJAI INDUSTRIA E COMERCIO DE TINTAS LTDA - ME" }), "Itajai");
  // só ramo e sociedade (nenhuma palavra que identifique): o corte de antes, sem inventar nome
  assertEquals(nomeDeChamar({ name: "COMERCIO E SERVICOS LTDA" }), "Comercio");
  // o apelido do cadastro continua valendo inteiro, só sem o sinal solto no fim
  assertEquals(nomeDeChamar({ name: "X", display_name: "Industria Sul Praiana -" }), "Industria Sul Praiana");
});

// ─── O texto ───────────────────────────────────────────────────────────────────────────────────

Deno.test("linha: 1 recebimento diz o cliente, o valor, o vencimento e como desfazer", () => {
  assertEquals(linhaDosRecebidosPeloBoleto(UM, HOJE), FRASE_DE_UM);
  // baixado no próprio dia do vencimento (a varredura das 06:10 roda antes da manhã)
  assertEquals(
    linhaDosRecebidosPeloBoleto([apolo(100, HOJE)], HOJE),
    "Baixei sozinho pelo boleto: Apolo, R$ 100,00 (vence hoje) — o banco mostrou o crédito no dia do vencimento. Não era? Diga *desfaz a baixa de Apolo*.",
  );
});

Deno.test("linha: vários do mesmo cliente dizem o valor e o vencimento de cada um (até 3); clientes diferentes são nomeados", () => {
  // (24/11/2026, revisão) só "2 recebimentos de Apolo (R$ 10.476,01)" não dizia quais: o cliente tem outra conta paga de
  // R$ 5.237,99 (casada à mão), e o dono não tinha como responder "qual?" ao assistente
  assertEquals(linhaDosRecebidosPeloBoleto(DOIS, HOJE), FRASE_DE_DOIS);
  assertEquals(
    linhaDosRecebidosPeloBoleto([...DOIS, apolo(100, HOJE)], HOJE),
    "Baixei sozinho pelo boleto 3 recebimentos de Apolo: R$ 5.237,99 (venceu 16/10), R$ 5.238,02 (venceu 13/11) e R$ 100,00 (vence hoje) — " +
      "o banco mostrou o crédito no dia do vencimento de cada um. Não era? Diga *desfaz a baixa de Apolo*.",
  );
  // passou de 3: as 3 primeiras, quantas ficaram sem dizer e a soma de todas
  assertEquals(
    linhaDosRecebidosPeloBoleto([...DOIS, apolo(100, HOJE), apolo(200, "2026-11-20"), { ...apolo(300, "2026-11-21"), vencimento: null }], HOJE),
    "Baixei sozinho pelo boleto 5 recebimentos de Apolo (R$ 11.076,01): R$ 5.237,99 (venceu 16/10), R$ 5.238,02 (venceu 13/11), " +
      "R$ 100,00 (vence hoje) e mais 2 — o banco mostrou o crédito no dia do vencimento de cada um. Não era? Diga *desfaz a baixa de Apolo*.",
  );
  // conta sem vencimento legível: só o valor
  assertEquals(
    linhaDosRecebidosPeloBoleto([apolo(100, "2026-11-20"), { ...apolo(300, "2026-11-21"), vencimento: null }], HOJE),
    "Baixei sozinho pelo boleto 2 recebimentos de Apolo: R$ 100,00 (venceu 20/11) e R$ 300,00 — " +
      "o banco mostrou o crédito no dia do vencimento de cada um. Não era? Diga *desfaz a baixa de Apolo*.",
  );
  const beta: RecebidoPeloBoleto = { cliente: "Beta Náutica", clienteId: "c-beta", valor: 1000, vencimento: "2026-11-24" };
  assertEquals(
    linhaDosRecebidosPeloBoleto([...DOIS, beta], HOJE),
    "Baixei sozinho pelo boleto 3 recebimentos (R$ 11.476,01): Apolo, Beta Náutica. Não era? Diga *desfaz a baixa* e o nome.",
  );
  const mais = ["Gama", "Delta", "Zeta"].map((n, i): RecebidoPeloBoleto => ({ cliente: n, clienteId: `c-${i}`, valor: 10, vencimento: "2026-11-24" }));
  assertEquals(
    linhaDosRecebidosPeloBoleto([UM[0], beta, ...mais], HOJE),
    "Baixei sozinho pelo boleto 5 recebimentos (R$ 6.267,99): Apolo, Beta Náutica, Gama e mais 2. Não era? Diga *desfaz a baixa* e o nome.",
  );
});

Deno.test("linha: nada baixado, lista ausente ou valor ilegível = null; conta sem cliente não inventa nome", () => {
  assertEquals(linhaDosRecebidosPeloBoleto(null, HOJE), null);
  assertEquals(linhaDosRecebidosPeloBoleto(undefined, HOJE), null);
  assertEquals(linhaDosRecebidosPeloBoleto([], HOJE), null);
  assertEquals(linhaDosRecebidosPeloBoleto([{ cliente: "Apolo", clienteId: "c-apolo", valor: NaN, vencimento: null }], HOJE), null);
  assertEquals(
    linhaDosRecebidosPeloBoleto([{ cliente: null, clienteId: null, valor: 50, vencimento: null }], HOJE),
    "Baixei sozinho pelo boleto: cliente sem nome, R$ 50,00 — o banco mostrou o crédito no dia do vencimento. Não era? Diga *desfaz a baixa* e o valor.",
  );
});

Deno.test("a frase ensinada segue para o assistente: não é comando do secretário (o 'desfaz A' é 'volta A')", () => {
  assertEquals(lerComandoDoSecretario("desfaz a baixa de Apolo"), null);
  assertEquals(lerComandoDoSecretario("*desfaz a baixa de Apolo*"), null);
  assertEquals(lerComandoDoSecretario("desfaz a baixa"), null);
  assertEquals(lerComandoDoSecretario("desfaz a")?.comando, "volta");
});

Deno.test("comRecebidosPeloBoleto: dia útil ganha a linha depois de uma linha em branco; domingo, feriado ou sem linha = igual", () => {
  assertEquals(comRecebidosPeloBoleto("Bom dia!", "util", FRASE_DE_UM), `Bom dia!\n\n${FRASE_DE_UM}`);
  assertEquals(comRecebidosPeloBoleto("Bom dia! Domingo", "domingo", FRASE_DE_UM), "Bom dia! Domingo");
  assertEquals(comRecebidosPeloBoleto("Bom dia! Feriado", "feriado", FRASE_DE_UM), "Bom dia! Feriado");
  assertEquals(comRecebidosPeloBoleto("Bom dia!", "util", null), "Bom dia!");
});

// ─── Na manhã ──────────────────────────────────────────────────────────────────────────────────

Deno.test("montarDosDados: sem baixa (ausente, null ou vazio) o texto é o de antes, byte a byte", () => {
  const antes = montarDosDados(base());
  assertEquals(montarDosDados({ ...base(), recebidosPeloBoleto: null }).texto, antes.texto);
  assertEquals(montarDosDados({ ...base(), recebidosPeloBoleto: [] }).texto, antes.texto);
});

Deno.test("montarDosDados: com baixa a manhã ganha a linha no fim, depois dos pagamentos e antes da sugestão de imprimir", () => {
  const antes = montarDosDados(base());
  const linha = linhaDosRecebidosPeloBoleto(UM, HOJE_1510)!;
  const com = montarDosDados({ ...base(), recebidosPeloBoleto: UM });
  assertEquals(com.texto, `${antes.texto}\n\n${linha}`);
  // a linha não tem letra: os itens gravados não mudam
  assertEquals(com.itens, antes.itens);
  const pagamentos = pagamentosDaResposta({
    hoje: HOJE_1510, ate: "2026-10-18", saldo_no_banco: 1000, saldo_em: "2026-10-15T09:00:00+00:00",
    contas: [{ id: "c1", nome: "Unifique", valor: 117.18, vencimento: "2026-10-10", vencida: true, grupo: 2, a_definir: false }],
    soma: 0, vencido: { n: 0, total: 0 }, reembolsos: { n: 0, total: 0 },
  });
  assertEquals(
    montarDosDados({ ...base(), recebidosPeloBoleto: DOIS, pagamentos, viasParaImprimir: 2 }).texto,
    `${antes.texto}\n\n${linhaDasVencidas(pagamentos)}\n\n${linhaDosRecebidosPeloBoleto(DOIS, HOJE_1510)}` +
      "\n🖨️ Quer as 2 vias de hoje no papel? Responda: *imprime as vias de hoje*",
  );
});

Deno.test("montarDosDados: domingo não leva a linha (a manhã de folga é uma linha só)", () => {
  const domingo = { ...base(), hoje: "2026-10-18", agora: new Date("2026-10-18T10:30:00Z") };
  assertEquals(montarDosDados({ ...domingo, recebidosPeloBoleto: UM }).texto, montarDosDados(domingo).texto);
});

// ─── O leitor ──────────────────────────────────────────────────────────────────────────────────

type Resposta = { data?: unknown; error?: unknown };
type Consulta = { tabela: string; colunas: string; filtros: Array<[string, string, unknown]> };

/** Um admin de mentira: guarda cada consulta (tabela, colunas e filtros) e responde o que o teste mandar por tabela. */
// deno-lint-ignore no-explicit-any
function falsoAdmin(respostas: Record<string, Resposta>): { admin: any; consultas: Consulta[] } {
  const consultas: Consulta[] = [];
  return {
    consultas,
    admin: {
      from: (tabela: string) => {
        const c: Consulta = { tabela, colunas: "", filtros: [] };
        consultas.push(c);
        const r = respostas[tabela] ?? {};
        // deno-lint-ignore no-explicit-any
        const q: any = {
          select: (colunas: string) => { c.colunas = colunas; return q; },
          eq: (col: string, v: unknown) => { c.filtros.push(["eq", col, v]); return q; },
          gte: (col: string, v: unknown) => { c.filtros.push(["gte", col, v]); return q; },
          lt: (col: string, v: unknown) => { c.filtros.push(["lt", col, v]); return q; },
          in: (col: string, v: unknown) => { c.filtros.push(["in", col, v]); return q; },
          order: () => q,
          limit: () => q,
          then: (ok: (v: unknown) => unknown, falhou?: (e: unknown) => unknown) =>
            Promise.resolve({ data: r.data ?? null, error: r.error ?? null }).then(ok, falhou),
        };
        return q;
      },
    },
  };
}

const FILA = [
  { bank_transaction_id: "t-1", decided_at: "2026-11-24T09:10:00+00:00" },
  { bank_transaction_id: "t-2", decided_at: "2026-11-24T09:10:01+00:00" },
  { bank_transaction_id: "t-3", decided_at: "2026-11-24T18:10:00+00:00" },
];
const CONTAS = [
  { id: "r-2", client_id: "c-apolo", bank_transaction_id: "t-2", amount: "5238.02", due_date: "2026-11-13", clients: { name: APOLO, display_name: null } },
  { id: "r-1", client_id: "c-apolo", bank_transaction_id: "t-1", amount: 5237.99, due_date: "2026-10-16", clients: { name: APOLO, display_name: null } },
];

Deno.test("desdeAUltimaManha: as 07:30 de Brasília da última manhã com itens (na segunda, o sábado)", () => {
  assertEquals(desdeAUltimaManha("2026-11-25"), "2026-11-24T10:30:00.000Z");
  // segunda 23/11: domingo é uma linha só, então a janela vem do sábado — a baixa do fim de semana não se perde
  assertEquals(desdeAUltimaManha("2026-11-23"), "2026-11-21T10:30:00.000Z");
});

// o registro da linha do banco (reconciliation_log) como a função do banco o deixa: UMA linha, 'conciliou', da conta baixada
const DA_BAIXA = "Baixa automática pelo boleto · Conciliado com o extrato";
const REGISTROS = [
  { bank_transaction_id: "t-1", receivable_id: "r-1", acao: "conciliou", detalhe: DA_BAIXA },
  { bank_transaction_id: "t-2", receivable_id: "r-2", acao: "conciliou", detalhe: DA_BAIXA },
];
const LIDO_DE_DOIS = [
  { cliente: "Apolo", clienteId: "c-apolo", valor: 5237.99, vencimento: "2026-10-16" },
  { cliente: "Apolo", clienteId: "c-apolo", valor: 5238.02, vencimento: "2026-11-13" },
];

Deno.test("lerRecebidosPeloBoleto: lê a fila pela janela, a conta ainda casada e o registro da linha; a baixa desfeita (t-3, sem conta) não aparece", async () => {
  const f = falsoAdmin({ finance_review_queue: { data: FILA }, receivables: { data: CONTAS }, reconciliation_log: { data: REGISTROS } });
  const lido = await lerRecebidosPeloBoleto(f.admin, HOJE);
  assertEquals(lido, LIDO_DE_DOIS);
  // sem o telefone do dono a janela é a do calendário e a fila do WhatsApp nem é lida
  assertEquals(f.consultas.map((c) => c.tabela), ["finance_review_queue", "receivables", "reconciliation_log"]);
  assertEquals(f.consultas[0].filtros, [
    ["eq", "automatica", "boleto"], ["eq", "kind", "create_receivable"], ["eq", "status", "approved"],
    ["gte", "decided_at", "2026-11-24T10:30:00.000Z"],
  ]);
  assertEquals(f.consultas[1].filtros, [["in", "bank_transaction_id", ["t-1", "t-2", "t-3"]]]);
  // o registro só das linhas que ainda têm conta casada; a coluna de data (ocorrido_em) não é precisa
  assertEquals(f.consultas[2].colunas, "bank_transaction_id, receivable_id, acao, detalhe");
  assertEquals(f.consultas[2].filtros, [["in", "bank_transaction_id", ["t-2", "t-1"]]]);
  assertEquals(linhaDosRecebidosPeloBoleto(lido, HOJE), FRASE_DE_DOIS);
});

Deno.test("lerRecebidosPeloBoleto: nada na fila = lista vazia sem ler as contas; todas desfeitas = lista vazia sem ler o registro", async () => {
  const vazio = falsoAdmin({ finance_review_queue: { data: [] } });
  assertEquals(await lerRecebidosPeloBoleto(vazio.admin, HOJE), []);
  assertEquals(vazio.consultas.map((c) => c.tabela), ["finance_review_queue"]);
  const desfeitas = falsoAdmin({ finance_review_queue: { data: FILA }, receivables: { data: [] } });
  assertEquals(await lerRecebidosPeloBoleto(desfeitas.admin, HOJE), []);
  assertEquals(desfeitas.consultas.map((c) => c.tabela), ["finance_review_queue", "receivables"]);
});

Deno.test("lerRecebidosPeloBoleto: leitura que falha = null (nunca lança) e a manhã sai com o texto de antes", async () => {
  const semFila = await lerRecebidosPeloBoleto(falsoAdmin({ finance_review_queue: { error: { code: "42703" } } }).admin, HOJE);
  assertEquals(semFila, null);
  const semContas = await lerRecebidosPeloBoleto(
    falsoAdmin({ finance_review_queue: { data: FILA }, receivables: { error: { code: "PGRST201" } } }).admin, HOJE);
  assertEquals(semContas, null);
  // (24/11/2026, revisão) sem o registro da linha não dá para dizer "baixei sozinho": sem a linha, nunca a lista crua
  const semRegistro = await lerRecebidosPeloBoleto(
    falsoAdmin({ finance_review_queue: { data: FILA }, receivables: { data: CONTAS }, reconciliation_log: { error: { code: "57014" } } }).admin, HOJE);
  assertEquals(semRegistro, null);
  // leitura que bate no teto do PostgREST pode ter vindo cortada: não dá para contar "um só registro"
  const cortado = Array.from({ length: 1000 }, () => REGISTROS[0]);
  assertEquals(
    await lerRecebidosPeloBoleto(
      falsoAdmin({ finance_review_queue: { data: FILA }, receivables: { data: CONTAS }, reconciliation_log: { data: cortado } }).admin, HOJE),
    null,
  );
  const lanca = { from: () => { throw new Error("rede"); } };
  assertEquals(await lerRecebidosPeloBoleto(lanca, HOJE), null);
  assertEquals(await lerRecebidosPeloBoleto(lanca, HOJE, DONO), null);
  const antes = montarDosDados(base()).texto;
  assertEquals(montarDosDados({ ...base(), recebidosPeloBoleto: semContas }).texto, antes);
  assertEquals(montarDosDados({ ...base(), recebidosPeloBoleto: semRegistro }).texto, antes);
});

// ─── A marca que revive (24/11/2026, revisão) ──────────────────────────────────────────────────
// Depois do desfazer a proposta fica approved/boleto para sempre. Se o dono casa à mão a mesma linha do banco com outra
// conta, "há conta casada com a linha" voltava a dizer "Baixei sozinho", com o cliente da conta nova.

Deno.test("baixasDePe: só a linha com UM registro, 'conciliou', com o detalhe da baixa automática e com conta", () => {
  assertEquals([...baixasDePe(REGISTROS)], [["t-1", "r-1"], ["t-2", "r-2"]]);
  const linha = (acao: string, detalhe: string | null, conta: string | null = "r-1") => ({ bank_transaction_id: "t-1", receivable_id: conta, acao, detalhe });
  // desfeita: o registro do desfazer fica na linha
  assertEquals(baixasDePe([linha("conciliou", DA_BAIXA), linha("desconciliou", null)]).size, 0);
  // desfeita e casada de novo à mão
  assertEquals(baixasDePe([linha("conciliou", DA_BAIXA), linha("desconciliou", null), linha("conciliou", null, "r-beta")]).size, 0);
  // casada à mão desde o começo (o detalhe não é o da baixa automática) ou outra ação qualquer
  assertEquals(baixasDePe([linha("conciliou", "Conciliado com o extrato")]).size, 0);
  assertEquals(baixasDePe([linha("conciliou", null)]).size, 0);
  assertEquals(baixasDePe([linha("aprovou_proposta", DA_BAIXA)]).size, 0);
  // registro de conta a PAGAR (sem conta a receber) não é baixa de recebimento
  assertEquals(baixasDePe([linha("conciliou", DA_BAIXA, null)]).size, 0);
  // a faxina da varredura na mesma linha não derruba a baixa de pé — e sozinha não faz baixa nenhuma
  assertEquals([...baixasDePe([linha("conciliou", DA_BAIXA), linha("tirou_da_fila_ja_lancada", "Proposta repetida fechada", null)])], [["t-1", "r-1"]]);
  assertEquals(baixasDePe([linha("tirou_da_fila_ja_lancada", null, null)]).size, 0);
  assertEquals(baixasDePe(null).size, 0);
  assertEquals(baixasDePe([]).size, 0);
  assertEquals(baixasDePe([{ bank_transaction_id: null, receivable_id: "r-1", acao: "conciliou", detalhe: DA_BAIXA }]).size, 0);
});

Deno.test("contasDaBaixaDePe: a conta casada tem de ser a do registro (a casada à mão depois do desfazer não é)", () => {
  const dePe = baixasDePe(REGISTROS);
  assertEquals(contasDaBaixaDePe(CONTAS, dePe).map((c) => c.id), ["r-2", "r-1"]);
  assertEquals(contasDaBaixaDePe([{ id: "r-beta", bank_transaction_id: "t-1" }], dePe), []);
  assertEquals(contasDaBaixaDePe([{ id: null, bank_transaction_id: "t-1" }, { id: "r-1", bank_transaction_id: null }], dePe), []);
  assertEquals(contasDaBaixaDePe(null, dePe), []);
});

Deno.test("lerRecebidosPeloBoleto: baixa desfeita e casada de novo à mão com outro cliente não sai como 'Baixei sozinho'", async () => {
  // t-1: o sistema baixou r-1 (Apolo) às 15:10; às 16h o dono desfez e casou a mesma linha com a conta de outro cliente
  const contas = [
    { id: "r-beta", client_id: "c-beta", bank_transaction_id: "t-1", amount: 5300, due_date: "2026-11-10", clients: { name: "ESTALEIRO BETA LTDA", display_name: null } },
    CONTAS[0],
  ];
  const registros = [
    REGISTROS[0],
    { bank_transaction_id: "t-1", receivable_id: "r-1", acao: "desconciliou", detalhe: null },
    { bank_transaction_id: "t-1", receivable_id: "r-beta", acao: "conciliou", detalhe: "Conciliado com o extrato" },
    REGISTROS[1],
  ];
  const f = falsoAdmin({ finance_review_queue: { data: FILA }, receivables: { data: contas }, reconciliation_log: { data: registros } });
  const lido = await lerRecebidosPeloBoleto(f.admin, HOJE);
  // só a baixa de t-2, que continua de pé; nada de "Estaleiro Beta"
  assertEquals(lido, [{ cliente: "Apolo", clienteId: "c-apolo", valor: 5238.02, vencimento: "2026-11-13" }]);
  // a mesma linha casada à mão com OUTRA conta, sem o registro do desfazer no meio (um só registro, mas de outra conta)
  const outra = falsoAdmin({
    finance_review_queue: { data: [FILA[0]] }, receivables: { data: [contas[0]] }, reconciliation_log: { data: [REGISTROS[0]] },
  });
  assertEquals(await lerRecebidosPeloBoleto(outra.admin, HOJE), []);
  // todas desfeitas e casadas à mão: lista vazia, e a manhã sai como antes
  const todas = falsoAdmin({
    finance_review_queue: { data: [FILA[0]] }, receivables: { data: [contas[0]] }, reconciliation_log: { data: registros.slice(0, 3) },
  });
  assertEquals(await lerRecebidosPeloBoleto(todas.admin, HOJE), []);
});

// ─── A janela: desde a última manhã útil ENTREGUE (24/11/2026, revisão) ────────────────────────
// Pelo calendário a baixa era dita uma vez só: em 27/10 e 03/11 a fila do WhatsApp desistiu da manhã (10 tentativas,
// 'failed'), e a baixa da véspera nunca mais apareceria. O dia conta como entregue quando a linha da fila diz 'sent'.

const DONO = "5547999990000";
const enviada = (dia: string) => ({ created_at: `${dia}T10:30:07.123+00:00` });

Deno.test("desdeAUltimaManhaEntregue: manhã anterior entregue = a janela de sempre; lê só a data, do dono, das últimas enviadas", async () => {
  const f = falsoAdmin({ whatsapp_send_queue: { data: [enviada("2026-11-24"), enviada("2026-11-23")] } });
  assertEquals(await desdeAUltimaManhaEntregue(f.admin, HOJE, DONO), desdeAUltimaManha(HOJE));
  assertEquals(f.consultas.map((c) => [c.tabela, c.colunas]), [["whatsapp_send_queue", "created_at"]]);
  assertEquals(f.consultas[0].filtros, [
    ["eq", "source", "ai_briefing"], ["eq", "phone_normalized", DONO], ["eq", "status", "sent"],
    ["gte", "created_at", "2026-11-18T03:00:00.000Z"], ["lt", "created_at", "2026-11-25T03:00:00.000Z"],
  ]);
});

Deno.test("desdeAUltimaManhaEntregue: manhã anterior não entregue = a janela volta até a última útil entregue (domingo não conta)", async () => {
  // terça 24/11 a fila desistiu: a última entregue é a de segunda 23/11
  const falhou = falsoAdmin({ whatsapp_send_queue: { data: [enviada("2026-11-23"), enviada("2026-11-22")] } });
  assertEquals(await desdeAUltimaManhaEntregue(falhou.admin, HOJE, DONO), "2026-11-23T10:30:00.000Z");
  // segunda e terça não chegaram; a de domingo chegou, mas é uma linha só (sem esta): vale a de sábado 21/11
  const duas = falsoAdmin({ whatsapp_send_queue: { data: [enviada("2026-11-22"), enviada("2026-11-21")] } });
  assertEquals(await desdeAUltimaManhaEntregue(duas.admin, HOJE, DONO), "2026-11-21T10:30:00.000Z");
  // a ordem em que as linhas vêm não importa: vale o dia útil mais recente
  const foraDeOrdem = falsoAdmin({ whatsapp_send_queue: { data: [enviada("2026-11-20"), enviada("2026-11-23")] } });
  assertEquals(await desdeAUltimaManhaEntregue(foraDeOrdem.admin, HOJE, DONO), "2026-11-23T10:30:00.000Z");
});

Deno.test("desdeAUltimaManhaEntregue: sem telefone ou com erro = a do calendário; leitura boa sem manhã útil entregue = o piso de 7 dias (nunca lança)", async () => {
  const calendario = desdeAUltimaManha(HOJE);
  const semFone = falsoAdmin({ whatsapp_send_queue: { data: [enviada("2026-11-20")] } });
  assertEquals(await desdeAUltimaManhaEntregue(semFone.admin, HOJE), calendario);
  assertEquals(await desdeAUltimaManhaEntregue(semFone.admin, HOJE, null), calendario);
  assertEquals(semFone.consultas, []);
  // WhatsApp fora do ar a semana inteira: nada foi dito em 7 dias, a janela fica no piso (não encolhe para "desde ontem")
  const piso = "2026-11-18T10:30:00.000Z";
  assertEquals(piso < calendario, true);
  assertEquals(await desdeAUltimaManhaEntregue(falsoAdmin({ whatsapp_send_queue: { data: [] } }).admin, HOJE, DONO), piso);
  assertEquals(await desdeAUltimaManhaEntregue(falsoAdmin({}).admin, HOJE, DONO), piso);
  // só domingo entregue na semana, linha de hoje (a manhã que está sendo montada) e data ilegível não mudam a janela
  const nada = falsoAdmin({ whatsapp_send_queue: { data: [enviada("2026-11-22"), enviada("2026-11-25"), { created_at: "ontem" }, { created_at: null }] } });
  assertEquals(await desdeAUltimaManhaEntregue(nada.admin, HOJE, DONO), piso);
  assertEquals(await desdeAUltimaManhaEntregue(falsoAdmin({ whatsapp_send_queue: { error: { code: "57014" } } }).admin, HOJE, DONO), calendario);
  assertEquals(await desdeAUltimaManhaEntregue({ from: () => { throw new Error("rede"); } }, HOJE, DONO), calendario);
});

Deno.test("lerRecebidosPeloBoleto: a manhã de ontem não foi entregue = a baixa da antevéspera aparece na de hoje", async () => {
  // a baixa de segunda 23/11 às 15:10 ia na manhã de terça 24/11, que a fila não entregou
  const f = falsoAdmin({
    whatsapp_send_queue: { data: [enviada("2026-11-23")] },
    finance_review_queue: { data: [{ bank_transaction_id: "t-1", decided_at: "2026-11-23T18:10:00+00:00" }] },
    receivables: { data: [CONTAS[1]] }, reconciliation_log: { data: [REGISTROS[0]] },
  });
  const lido = await lerRecebidosPeloBoleto(f.admin, HOJE, DONO);
  assertEquals(lido, [LIDO_DE_DOIS[0]]);
  assertEquals(f.consultas.map((c) => c.tabela), ["whatsapp_send_queue", "finance_review_queue", "receivables", "reconciliation_log"]);
  assertEquals(f.consultas[1].filtros[3], ["gte", "decided_at", "2026-11-23T10:30:00.000Z"]);
  assertEquals(linhaDosRecebidosPeloBoleto(lido, HOJE), FRASE_DE_UM);
});

Deno.test("lerRecebidosPeloBoleto: a manhã de ontem foi entregue = a janela de hoje; a fila do WhatsApp que falha não derruba a linha", async () => {
  const banco = { finance_review_queue: { data: FILA }, receivables: { data: CONTAS }, reconciliation_log: { data: REGISTROS } };
  const entregue = falsoAdmin({ ...banco, whatsapp_send_queue: { data: [enviada("2026-11-24")] } });
  assertEquals(await lerRecebidosPeloBoleto(entregue.admin, HOJE, DONO), LIDO_DE_DOIS);
  assertEquals(entregue.consultas[1].filtros[3], ["gte", "decided_at", "2026-11-24T10:30:00.000Z"]);
  const semFila = falsoAdmin({ ...banco, whatsapp_send_queue: { error: { code: "57014" } } });
  assertEquals(await lerRecebidosPeloBoleto(semFila.admin, HOJE, DONO), LIDO_DE_DOIS);
  assertEquals(semFila.consultas[1].filtros[3], ["gte", "decided_at", "2026-11-24T10:30:00.000Z"]);
});
