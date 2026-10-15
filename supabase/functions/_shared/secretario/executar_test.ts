// executarComandoDoSecretario com um banco de mentira: o que lê, o que manda às RPCs e o que nunca faz.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { executarComandoDoSecretario } from "./executar.ts";
import { lerComandoDoSecretario } from "./comandos.ts";
import { TEXTO_SEM_RESUMO } from "./respostas.ts";

const FONE = "5547999990000";
const AGORA = new Date("2026-10-15T14:00:00Z"); // 11:00 de Brasília
const HOJE = "2026-10-15";

type Linha = Record<string, unknown>;

/** Um PostgREST de mentira: eq/gte/lt/order/limit sobre linhas em memória, rpc gravada. */
function falsoAdmin(tabelas: Record<string, Linha[]>, rpcs: Record<string, unknown> = {}, falhar = false) {
  const chamadas: Array<{ nome: string; p: unknown }> = [];
  const leituras: string[] = [];
  const admin = {
    from(tabela: string) {
      leituras.push(tabela);
      let linhas = [...(tabelas[tabela] ?? [])];
      const q = {
        select: () => q,
        eq: (c: string, v: unknown) => ((linhas = linhas.filter((l) => l[c] === v)), q),
        gte: (c: string, v: string) => ((linhas = linhas.filter((l) => String(l[c]) >= v)), q),
        lt: (c: string, v: string) => ((linhas = linhas.filter((l) => String(l[c]) < v)), q),
        order: () => q,
        limit: () => q,
        maybeSingle: () => Promise.resolve(falhar ? { data: null, error: { code: "XX" } } : { data: linhas[0] ?? null, error: null }),
        then: (ok: (r: unknown) => unknown, erro?: (e: unknown) => unknown) =>
          Promise.resolve(falhar ? { data: null, error: { code: "XX" } } : { data: linhas, error: null }).then(ok, erro),
      };
      return q;
    },
    rpc(nome: string, args: { p: unknown }) {
      chamadas.push({ nome, p: args.p });
      return Promise.resolve({ data: rpcs[nome] ?? null, error: null });
    },
  };
  return { admin, chamadas, leituras };
}

const ITEM_A = {
  phone_normalized: FONE, dia: HOJE, modo: "novo", letra: "A", principal: true, posicao: "manha", ordem: 0, familia: "cobranca",
  tipo: "cobranca_grande", secao: "dinheiro", referencia: "recv:1", nome: "Marcelo Marco Bertoldi", titulo: "*A.* Marcelo…",
  recomendacao: "Recomendo um lembrete educado hoje.", motivo: "Subiu porque é cobrança de R$ 5 mil ou mais…",
  pedido: "Prepare um lembrete de pagamento para o cliente Marcelo…", detalhe: { fatos: [["Saldo", "R$ 16.890,00"]], faco: "te mostro o lembrete pronto", curto: "Marcelo: R$ 16.890,00" },
  acao: null, adiado_ate: null,
};
const ITEM_D = {
  ...ITEM_A, letra: "D", posicao: "lista", ordem: 3, familia: "cliente", tipo: "cliente_recente", secao: "clientes", referencia: "fone:55",
  nome: "Jorge", pedido: null, detalhe: { curto: "Jorge: escreveu há 7 h, sem resposta" },
};
const RESUMO = { phone_normalized: FONE, dia: HOJE, modo: "novo", texto_antigo: "☀️ *Bom dia! Resumo antigo*", escritorio: "Escritório (contado às 07:30):\n• 6 compras no débito sem loja", sem_letra: 0 };
const BANCO = { resumo_itens: [ITEM_A, ITEM_D, { ...ITEM_A, dia: "2026-10-14", acao: "ignorado", acao_em: "2026-10-15T10:30:00Z" }], resumo_manha: [RESUMO] };

async function rodar(texto: string, banco = BANCO, rpcs: Record<string, unknown> = {}, falhar = false) {
  const f = falsoAdmin(banco, rpcs, falhar);
  const cmd = lerComandoDoSecretario(texto);
  assert(cmd, `não leu "${texto}"`);
  const r = await executarComandoDoSecretario(f.admin, cmd, { phone: FONE, agora: AGORA });
  return { r, ...f };
}

Deno.test("lista, escritório e tudo leem o dia de hoje; sem o dia gravado, avisa", async () => {
  const lista = await rodar("lista");
  assertEquals(lista.r.tipo, "resposta");
  assertStringIncludes((lista.r as { texto: string }).texto, "D. Jorge: escreveu há 7 h, sem resposta");
  assertEquals((await rodar("escritório")).r, { tipo: "resposta", texto: RESUMO.escritorio });
  assertEquals((await rodar("tudo")).r, { tipo: "resposta", texto: RESUMO.texto_antigo });
  assertEquals((await rodar("lista", { resumo_itens: [], resumo_manha: [] })).r, { tipo: "resposta", texto: TEXTO_SEM_RESUMO });
});

Deno.test("a letra sozinha devolve o PEDIDO (vira o turno do assistente) e só anota 'abriu' no histórico", async () => {
  const { r, chamadas } = await rodar("a");
  assertEquals(r, { tipo: "pedido", texto: ITEM_A.pedido, letra: "A" });
  assertEquals(chamadas, [{ nome: "resumo_item_acao", p: { phone: FONE, modo: "novo", letra: "A", acao: "abriu" } }]);
  const semPedido = await rodar("D");
  assertEquals(semPedido.r.tipo, "resposta");
  assertEquals(semPedido.chamadas.length, 0);
  assertStringIncludes((semPedido.r as { texto: string }).texto, "não tem cartão pronto");
  assertStringIncludes(((await rodar("Z")).r as { texto: string }).texto, "Não achei o item Z de hoje");
});

Deno.test("a letra do pacote dos não enviados lista os orçamentos sem o modelo (e anota 'abriu')", async () => {
  const rasc = (letra: string, numero: string, principal: boolean, ordem: number) => ({
    ...ITEM_A, letra, principal, ordem, familia: "orcamento", tipo: "orcamento_nao_enviado", secao: "clientes", referencia: `os:${numero}`,
    nome: numero, pedido: `me manda o pdf do ${numero}`,
    detalhe: { fatos: [["Orçamento", numero], ["Valor", "R$ 70.050,00"], ["Montado em", "09/10/2026"]], faco: "te mostro os 2", curto: numero },
  });
  const banco = { ...BANCO, resumo_itens: [rasc("B", "ORÇ-00116", true, 1), rasc("B", "ORÇ-00118", false, 1)] };
  const { r, chamadas } = await rodar("B", banco);
  assertEquals(r.tipo, "resposta");
  const t = (r as { texto: string }).texto;
  assertStringIncludes(t, "B. 2 orçamentos montados e ainda não enviados:");
  assertStringIncludes(t, "• ORÇ-00118, R$ 70.050,00, montado em 09/10");
  assertStringIncludes(t, "*pdf 116*");
  assertEquals(chamadas, [{ nome: "resumo_item_acao", p: { phone: FONE, modo: "novo", letra: "B", acao: "abriu" } }]);
});

Deno.test("detalhe junta o histórico da mesma referência (sem o dia de hoje)", async () => {
  const { r } = await rodar("detalhe A");
  const t = (r as { texto: string }).texto;
  assertStringIncludes(t, "Saldo: R$ 16.890,00");
  assertStringIncludes(t, "De manhã antes: 1 vez em 30 dias (última em 14/10).");
});

Deno.test("ações vão à RPC com telefone, modo novo e letra; o adiar calcula a data pelo tipo", async () => {
  const feito = await rodar("A feito", BANCO, { resumo_item_acao: { ok: true, resultado: "feito", acao: "feito", item: { nome: "Marcelo", tipo: "cobranca_grande" } } });
  assertEquals(feito.chamadas, [{ nome: "resumo_item_acao", p: { phone: FONE, modo: "novo", letra: "A", acao: "feito" } }]);
  assertStringIncludes((feito.r as { texto: string }).texto, "cobrança grande");

  // cobrança: "espera" = segunda; cliente: "espera" = amanhã
  const esperaA = await rodar("A espera", BANCO, { resumo_item_acao: { ok: true, resultado: "feito", acao: "adiado", ate: "2026-10-19", item: {} } });
  assertEquals((esperaA.chamadas[0].p as { ate: string }).ate, "2026-10-19");
  const esperaD = await rodar("D espera", BANCO, { resumo_item_acao: { ok: true, resultado: "feito", acao: "adiado", ate: "2026-10-16", item: {} } });
  assertEquals((esperaD.chamadas[0].p as { ate: string }).ate, "2026-10-16");
  const ate = await rodar("A até 20/10", BANCO, { resumo_item_acao: { ok: true, resultado: "feito", acao: "adiado", ate: "2026-10-20", item: {} } });
  assertEquals(ate.chamadas[0].p, { phone: FONE, modo: "novo", letra: "A", acao: "adiado", ate: "2026-10-20" });
  // data que não serve: nada vai ao banco
  const ruim = await rodar("A até 10/10");
  assertEquals(ruim.chamadas.length, 0);
  assertStringIncludes((ruim.r as { texto: string }).texto, "Não entendi a data");
});

Deno.test("volta pela letra e pelo nome vai à resumo_item_voltar", async () => {
  const l = await rodar("volta A", BANCO, { resumo_item_voltar: { ok: true, resultado: "voltou", desfeita: "tirado", item: { nome: "Marcelo" } } });
  assertEquals(l.chamadas, [{ nome: "resumo_item_voltar", p: { phone: FONE, modo: "novo", letra: "A", nome: "" } }]);
  const n = await rodar("volta Flávio", BANCO, { resumo_item_voltar: { ok: true, resultado: "nao_achei" } });
  assertEquals(n.chamadas[0].p, { phone: FONE, modo: "novo", letra: "", nome: "flavio" });
});

Deno.test("erro de leitura vira frase ao dono (nunca lança, nada gravado)", async () => {
  const { r, chamadas } = await rodar("lista", BANCO, {}, true);
  assertEquals(r, { tipo: "resposta", texto: "Não consegui ler o resumo de hoje agora. Tente de novo em instantes." });
  assertEquals(chamadas.length, 0);
});
