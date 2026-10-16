// O comando *lote* com um banco de mentira (secretário, Passo 5): a chave desligada não muda nada (segue ao
// assistente), a sombra só mostra, o ligado devolve a confirmação de sempre ("sim <PIN>", risco alto) com os itens
// que AINDA conferem, o recorte, os erros e o lote esquecido "aplicando".
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { executarComandoDoSecretario } from "./executar.ts";
import { lerComandoDoSecretario } from "./comandos.ts";
import { selecionarDoLote } from "./papelada.ts";

const FONE = "5547999990000";
const AGORA = new Date("2026-10-16T21:00:00Z"); // sexta, 18:00 de Brasília
type Linha = Record<string, unknown>;

function falsoAdmin(tabelas: Record<string, Linha[]>, rpcs: Record<string, (p: Record<string, unknown>) => unknown> = {}) {
  const chamadas: Array<{ nome: string; p: Record<string, unknown> }> = [];
  const lidas: string[] = [];
  const admin = {
    from(tabela: string) {
      lidas.push(tabela);
      let linhas = [...(tabelas[tabela] ?? [])];
      const q: Record<string, unknown> = {
        select: () => q,
        eq: (c: string, v: unknown) => ((linhas = linhas.filter((l) => l[c] === v)), q),
        in: (c: string, vs: unknown[]) => ((linhas = linhas.filter((l) => vs.includes(l[c]))), q),
        order: () => q,
        limit: () => q,
        maybeSingle: () => Promise.resolve({ data: linhas[0] ?? null, error: null }),
      };
      return q;
    },
    rpc(nome: string, args: { p: Record<string, unknown> }) {
      chamadas.push({ nome, p: args.p });
      return Promise.resolve({ data: rpcs[nome] ? rpcs[nome](args.p) : null, error: null });
    },
  };
  return { admin, chamadas, lidas };
}

const imp = { kind: "create_payable", valor: 1, categoria: "x", data: "2026-10-10", regra: null, vinculo: false };
const ITENS = [
  { n: 1, id: "11111111-1111-4111-8111-111111111111", grupo: "despesa", titulo: "Eliane U.", valor: 493, categoria: "Alimentação de campo", codigo: "anotacao", motivo: "você anotou em 06/10", impressao: imp },
  { n: 2, id: "22222222-2222-4222-8222-222222222222", grupo: "despesa", titulo: "Fatura C6", valor: 400, categoria: "Pagamento de fatura de cartão", codigo: "categoria", motivo: "15 de 15 sem troca", impressao: imp },
  { n: 3, id: "33333333-3333-4333-8333-333333333333", grupo: "aviso", titulo: "Coremma parou de aparecer (último em 01/08)", valor: 120.5, categoria: null, codigo: "aviso_parou", motivo: "só para saber", impressao: imp },
];
const LOTE = {
  id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", dia: "2026-10-16", phone_normalized: FONE, formato: "ligado", status: "pronto",
  itens: ITENS, excecoes: [{ id: "x", grupo: "despesa", titulo: "Débito sem loja de 05/10", valor: 755, codigo: "sem_loja", motivo: "" }],
  total: 893, contagens: { minutos: 10, regras_guardadas: 103 }, valido_ate: "2026-10-23T20:30:00Z", aplicacao_inicio: null,
};
const banco = (chave: string | null, lote: Linha | null = LOTE) => ({
  app_settings: chave === null ? [] : [{ key: "papelada_lote", value: chave }],
  papelada_lote: lote ? [lote] : [],
});
const CONFERE_TUDO = { papelada_lote_conferir: (p: Record<string, unknown>) => ({ ok: true, validos: p.ids, fora: [] }) };

async function rodar(texto: string, tabelas: Record<string, Linha[]>, rpcs = {}) {
  const f = falsoAdmin(tabelas, rpcs);
  const cmd = lerComandoDoSecretario(texto);
  assert(cmd);
  return { r: await executarComandoDoSecretario(f.admin, cmd, { phone: FONE, agora: AGORA }), ...f };
}

Deno.test("chave desligada (ou ausente): 'lote' segue ao assistente como sempre, sem ler o lote nem chamar nada", async () => {
  for (const chave of ["desligado", null]) {
    const { r, chamadas, lidas } = await rodar("lote", banco(chave), CONFERE_TUDO);
    assertEquals(r, { tipo: "seguir" });
    assertEquals(chamadas.length, 0);
    assertEquals(lidas, ["app_settings"]);
  }
});

Deno.test("sombra: mostra o lote (ensaio) e NÃO abre confirmação", async () => {
  const { r } = await rodar("lote", banco("sombra"), CONFERE_TUDO);
  assertEquals(r.tipo, "resposta");
  assertStringIncludes((r as { texto: string }).texto, "(Ensaio: o lote está guardado para comparar; ainda não aprovo nada por aqui.)");
  // chave ligada com um lote que nasceu sombra (a tarde não saiu): também só mostra
  const { r: r2 } = await rodar("lote", banco("ligado", { ...LOTE, formato: "sombra" }), CONFERE_TUDO);
  assertEquals(r2.tipo, "resposta");
});

Deno.test("ligado: o detalhe + a confirmação de sempre (alta: sim <PIN>) só com os itens que ainda conferem", async () => {
  const { r, chamadas } = await rodar("lote", banco("ligado"), {
    papelada_lote_conferir: () => ({ ok: true, validos: [ITENS[0].id, ITENS[2].id], fora: [{ n: 2, id: ITENS[1].id, codigo: "ja_decidido_approved" }] }),
  });
  assertEquals(r.tipo, "confirmar");
  const c = r as { texto: string; pendencia: { action_name: string; risk_level: string; title: string; payload: Record<string, unknown>; minutos: number } };
  assertEquals(c.pendencia.action_name, "aprovar_lote_da_papelada");
  assertEquals(c.pendencia.risk_level, "high");
  assertEquals(c.pendencia.payload, { lote_id: LOTE.id, ids: [ITENS[0].id, ITENS[2].id], numeros: [1, 3] });
  assertEquals(c.pendencia.title, "Aprovar o lote da papelada: 2 itens, R$ 493,00 em despesas");
  assertEquals(c.pendencia.minutos, 720);
  assertStringIncludes(c.texto, "Saíram desde que montei: 2 (você já aprovou).");
  assertStringIncludes(c.texto, "Para aprovar os 2: *sim <seu PIN>*.");
  // a conferência foi SÓ de leitura (sem aplicar)
  assertEquals(chamadas.map((x) => [x.nome, x.p.aplicar ?? false]), [["papelada_lote_conferir", false]]);
});

Deno.test("recorte: 'lote sem avisos' e 'lote sem 2' mudam os escolhidos; número fora do lote avisa sem conferir", async () => {
  const { r } = await rodar("lote sem avisos", banco("ligado"), CONFERE_TUDO);
  assertEquals((r as unknown as { pendencia: { payload: { numeros: number[] } } }).pendencia.payload.numeros, [1, 2]);
  const { r: r2 } = await rodar("lote sem 2", banco("ligado"), CONFERE_TUDO);
  assertEquals((r2 as unknown as { pendencia: { payload: { numeros: number[] } } }).pendencia.payload.numeros, [1, 3]);
  const { r: r3, chamadas } = await rodar("lote sem 9", banco("ligado"), CONFERE_TUDO);
  assertEquals((r3 as { texto: string }).texto, "Não há item 9 no lote (vai de 1 a 3). Escreva *lote* para ver a lista.");
  assertEquals(chamadas.length, 0);
  assertEquals(selecionarDoLote(ITENS as never, { comando: "papelada", sem: [], semGrupos: [], soGrupos: ["transferencia"] }).escolhidos.length, 0);
});

Deno.test("sem lote, lote vencido na conferência, e o lote esquecido 'aplicando' fechado pelo banco", async () => {
  const { r } = await rodar("lote", banco("ligado", null));
  assertStringIncludes((r as { texto: string }).texto, "Não há lote pronto agora.");
  const { r: r2 } = await rodar("lote", banco("ligado"), { papelada_lote_conferir: () => ({ ok: false, erro: "lote_vencido" }) });
  assertStringIncludes((r2 as { texto: string }).texto, "Esse lote venceu.");
  // aplicando há 20 min: o próximo *lote* lê o resultado do banco
  const esquecido = { ...LOTE, status: "aplicando", aplicacao_inicio: "2026-10-16T20:40:00Z" };
  const { r: r3, chamadas } = await rodar("lote", banco("ligado", esquecido), {
    papelada_lote_resultado: () => ({ ok: true, itens: [{ n: 1, id: ITENS[0].id, situacao: "entrou" }, { n: 2, id: ITENS[1].id, situacao: "falhou", motivo: "não entrou" }], entrou: 1, falhou: 1, fora: 0, valor_entrou: 493 }),
  });
  assertEquals(chamadas.map((c) => c.nome), ["papelada_lote_resultado"]);
  assertStringIncludes((r3 as { texto: string }).texto, "Entraram 1 de 2 (despesas: R$ 493,00). Não entraram 1: 2. Fatura C6 (não entrou).");
  // aplicando há 2 min: espera
  const recente = { ...LOTE, status: "aplicando", aplicacao_inicio: "2026-10-16T20:58:00Z" };
  const { r: r4, chamadas: c4 } = await rodar("lote", banco("ligado", recente));
  assertStringIncludes((r4 as { texto: string }).texto, "está sendo aprovado agora");
  assertEquals(c4.length, 0);
});
