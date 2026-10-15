// Os comandos da tarde com um banco de mentira (secretário, Passo 3): o lote vai inteiro numa RPC (tudo ou
// nada), a cobrança antiga vira o turno do assistente (nada sai sem o sim), a pergunta da sexta grava ou segue
// como conversa, e o *escritório* prefere a contagem da tarde.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { acaoParaRpc, executarComandoDoSecretario } from "./executar.ts";
import { lerComandoDoSecretario } from "./comandos.ts";

const FONE = "5547999990000";
const AGORA = new Date("2026-10-19T21:00:00Z"); // segunda, 18:00 de Brasília
const HOJE = "2026-10-19";

type Linha = Record<string, unknown>;

function falsoAdmin(tabelas: Record<string, Linha[]>, rpcs: Record<string, unknown> = {}) {
  const chamadas: Array<{ nome: string; p: unknown }> = [];
  const admin = {
    from(tabela: string) {
      let linhas = [...(tabelas[tabela] ?? [])];
      const q = {
        select: () => q,
        eq: (c: string, v: unknown) => ((linhas = linhas.filter((l) => l[c] === v)), q),
        gte: (c: string, v: string) => ((linhas = linhas.filter((l) => String(l[c]) >= v)), q),
        lt: (c: string, v: string) => ((linhas = linhas.filter((l) => String(l[c]) < v)), q),
        order: () => q,
        limit: () => q,
        maybeSingle: () => Promise.resolve({ data: linhas[0] ?? null, error: null }),
        then: (ok: (r: unknown) => unknown, erro?: (e: unknown) => unknown) => Promise.resolve({ data: linhas, error: null }).then(ok, erro),
      };
      return q;
    },
    rpc(nome: string, args: { p: unknown }) {
      chamadas.push({ nome, p: args.p });
      return Promise.resolve({ data: rpcs[nome] ?? null, error: null });
    },
  };
  return { admin, chamadas };
}

const MANHA = { phone_normalized: FONE, dia: HOJE, modo: "novo", texto_antigo: "antigo", escritorio: "Escritório (contado às 07:30):\n• 6 compras no débito sem loja", sem_letra: 0 };
const COBRANCA_G = {
  phone_normalized: FONE, dia: HOJE, modo: "novo", letra: "G", principal: false, posicao: "lista", ordem: 4, familia: "cobranca", tipo: "cobranca_antiga",
  secao: "dinheiro", referencia: "recv:mp45", nome: "MP MOTOR HOMES", titulo: "t", recomendacao: null, motivo: "m",
  pedido: "Prepare um lembrete de pagamento para o cliente MP MOTOR HOMES sobre \"OS-00045 - Estoque Revenda\" (saldo de R$ 1.650,00, venceu em 22/07/2026). Mostre o texto pronto e peça o meu sim antes de enviar.",
  fato: "1650.00|2026-07-22|lista",
  detalhe: { fatos: [["Cliente", "MP MOTOR HOMES"], ["OS", "OS-00045"], ["Cobrança", "OS-00045 - Estoque Revenda"], ["Saldo", "R$ 1.650,00"], ["Venceu em", "22/07/2026 (89 dias)"]] },
  acao: null, adiado_ate: null,
};
const ORC_G = { ...COBRANCA_G, principal: true, familia: "orcamento", tipo: "orcamento_na_lista", secao: "clientes", referencia: "os:q95", nome: "ORÇ-00095 MP MOTOR HOMES", fato: "awaiting_deposit|14461.00|2026-10-06|lista", detalhe: {} };
const COBRANCA_G2 = { ...COBRANCA_G, referencia: "recv:mp46", fato: "20.00|2026-07-22|lista",
  detalhe: { fatos: [["Cliente", "MP MOTOR HOMES"], ["Cobrança", "OS-00046 - Estoque Revenda"], ["Saldo", "R$ 20,00"], ["Venceu em", "22/07/2026 (89 dias)"]] } };
const JOAO_D = { ...COBRANCA_G, letra: "D", principal: true, referencia: "recv:joao", nome: "João H.", fato: "1710.00|2026-10-13|lista", tipo: "cobranca_fora_do_marco" };
const BANCO = { resumo_manha: [MANHA], resumo_itens: [ORC_G, COBRANCA_G, COBRANCA_G2, JOAO_D] };

async function rodar(texto: string, banco: Record<string, Linha[]> = BANCO, rpcs: Record<string, unknown> = {}) {
  const f = falsoAdmin(banco, rpcs);
  const cmd = lerComandoDoSecretario(texto);
  assert(cmd, `não leu "${texto}"`);
  return { r: await executarComandoDoSecretario(f.admin, cmd, { phone: FONE, agora: AGORA }), chamadas: f.chamadas };
}

Deno.test("acaoParaRpc: semana = a próxima segunda; 15 dias = hoje + 15; amanhã; as outras sem data", () => {
  assertEquals(acaoParaRpc({ letra: "C", acao: "adiar", quando: "semana" }, HOJE), { letra: "C", acao: "adiado", ate: "2026-10-26", resposta: "semana" });
  assertEquals(acaoParaRpc({ letra: "G", acao: "adiar", quando: "15dias" }, HOJE), { letra: "G", acao: "adiado", ate: "2026-11-03", resposta: "15dias" });
  assertEquals(acaoParaRpc({ letra: "D", acao: "adiar", quando: "amanha" }, HOJE), { letra: "D", acao: "adiado", ate: "2026-10-20" });
  assertEquals(acaoParaRpc({ letra: "B", acao: "tirado" }, HOJE), { letra: "B", acao: "tirado" });
});

Deno.test("lote: UMA chamada com todas as respostas; a confirmação diz o que ficou com o dono", async () => {
  const { r, chamadas } = await rodar("D semana, G 15 dias, B tira", BANCO, {
    resumo_itens_acoes: {
      ok: true, resultado: "feito", itens: [
        { letra: "D", acao: "adiado", ate: "2026-10-26", resposta: "semana" },
        { letra: "G", acao: "adiado", ate: "2026-11-03", resposta: "15dias" },
        { letra: "B", acao: "tirado" },
      ],
    },
  });
  assertEquals(chamadas.length, 1);
  assertEquals(chamadas[0].nome, "resumo_itens_acoes");
  assertEquals((chamadas[0].p as { acoes: unknown[] }).acoes.length, 3);
  assertEquals(r.tipo, "resposta");
  const t = (r as { texto: string }).texto;
  assertStringIncludes(t, "Anotei: D fica com você esta semana · G volta em 15 dias (03/11) · B tirado.");
  assertStringIncludes(t, "*volta D* desfaz.");
});

Deno.test("lote: letra que não existe = nada anotado (a RPC não grava pela metade)", async () => {
  const { r } = await rodar("D semana, Z tira", BANCO, { resumo_itens_acoes: { ok: true, resultado: "nao_achei", letras: ["Z"] } });
  assertEquals((r as { texto: string }).texto, "Não achei Z de hoje; nada foi anotado. *lista* mostra os de hoje.");
  const rep = await rodar("D semana, D tira", BANCO, { resumo_itens_acoes: { ok: false, resultado: "invalido", erro: "letra_repetida", letra: "D" } });
  assertStringIncludes((rep.r as { texto: string }).texto, "A letra D veio duas vezes; nada foi anotado.");
});

Deno.test("cobrança antiga: G cobrar vira o turno do assistente com as duas cobranças do cliente; só 'abriu' é gravado", async () => {
  const { r, chamadas } = await rodar("G cobrar");
  assertEquals(r.tipo, "pedido");
  const t = (r as { texto: string }).texto;
  assertStringIncludes(t, "Prepare um lembrete de pagamento para o cliente MP MOTOR HOMES sobre estas cobranças vencidas:");
  assertStringIncludes(t, "\"OS-00045 - Estoque Revenda\" (saldo de R$ 1.650,00, venceu em 22/07/2026)");
  assertStringIncludes(t, "\"OS-00046 - Estoque Revenda\" (saldo de R$ 20,00, venceu em 22/07/2026)");
  assertStringIncludes(t, "peça o meu sim antes de enviar");
  assertEquals(chamadas, [{ nome: "resumo_item_acao", p: { phone: FONE, modo: "novo", letra: "G", acao: "abriu" } }]);
  const baixa = await rodar("G baixa");
  assertStringIncludes((baixa.r as { texto: string }).texto, "peça o meu sim antes de gravar");
  const neg = await rodar("G negociar");
  assertStringIncludes((neg.r as { texto: string }).texto, "parcelar o saldo ou um desconto para pagar à vista");
});

Deno.test("cobrança antiga: só uma cobrança na letra usa o lembrete pronto; letra sem cobrança de 30+ dias avisa", async () => {
  const umaSo = { resumo_manha: [MANHA], resumo_itens: [{ ...COBRANCA_G, letra: "F", principal: true }] };
  const { r } = await rodar("F cobrar", umaSo);
  assertEquals((r as { texto: string }).texto, COBRANCA_G.pedido);
  const recente = await rodar("D cobrar"); // venceu em 13/10: 6 dias
  assertEquals(recente.r.tipo, "resposta");
  assertStringIncludes((recente.r as { texto: string }).texto, "não tem cobrança vencida há 30 dias ou mais");
  assertEquals(recente.chamadas.length, 0);
});

Deno.test("a pergunta da sexta: grava; sem pergunta aberta (ou erro), segue ao assistente como conversa", async () => {
  const g = await rodar("ajudou", BANCO, { resumo_semana_responder: { ok: true, resultado: "gravado" } });
  assertEquals(g.r, { tipo: "resposta", texto: "Anotei: a semana ajudou." });
  assertEquals(g.chamadas, [{ nome: "resumo_semana_responder", p: { phone: FONE, resposta: "ajudou" } }]);
  const p = await rodar("pouco", BANCO, { resumo_semana_responder: { ok: true, resultado: "trocado" } });
  assertStringIncludes((p.r as { texto: string }).texto, "Anotei: ajudou pouco (troquei a resposta anterior).");
  assertEquals((await rodar("atrapalhou", BANCO, { resumo_semana_responder: { ok: true, resultado: "sem_pergunta" } })).r, { tipo: "seguir" });
  assertEquals((await rodar("pouco", BANCO, {})).r, { tipo: "seguir" });
});

Deno.test("*escritório*: a contagem da tarde, quando existe; senão a da manhã", async () => {
  const daTarde = "Escritório (contado às 17:30):\n• 7 compras no débito sem loja";
  const com = await rodar("escritório", { ...BANCO, resumo_tarde: [{ phone_normalized: FONE, dia: HOJE, modo: "novo", escritorio: daTarde }] });
  assertEquals(com.r, { tipo: "resposta", texto: daTarde });
  const sombra = await rodar("escritório", { ...BANCO, resumo_tarde: [{ phone_normalized: FONE, dia: HOJE, modo: "sombra", escritorio: daTarde }] });
  assertEquals(sombra.r, { tipo: "resposta", texto: MANHA.escritorio });
  assertEquals((await rodar("escritório")).r, { tipo: "resposta", texto: MANHA.escritorio });
});
