import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { caixaTools, dataDita, escolherPorNome, resolverPedidoDeCaixa, resumirPedido } from "./caixa.ts";

/* O assessor pelo WhatsApp: "gastei 50 em dinheiro com almoço", "paguei 100 pro Roberto".
   O que se fixa aqui é a parte que interpreta a fala — nome, data, sócio, categoria — e o
   que vai para a confirmação. O dinheiro em si é das funções do banco. */

Deno.test("escolherPorNome: igual, depois todas as palavras; dúvida vira pergunta", () => {
  const lista = [
    { id: "1", nome: "Roberto Carlos da Silva" },
    { id: "2", nome: "Mickael Souza" },
    { id: "3", nome: "Roberta Lima" },
    { id: "4", nome: "João Silva" }, { id: "5", nome: "João Pedro" },
  ];
  assertEquals(escolherPorNome("roberto", lista), { achado: lista[0] });
  assertEquals(escolherPorNome("Mickael Souza", lista), { achado: lista[1] });
  assertEquals("ambiguo" in escolherPorNome("joão", lista), true);
  assertEquals(escolherPorNome("Fulano", lista), { nenhum: true });
});

Deno.test("dataDita: hoje, ontem, dd/mm e ISO; o resto não passa", () => {
  const agora = new Date("2026-09-25T15:00:00Z");
  assertEquals(dataDita("hoje", agora), "2026-09-25");
  assertEquals(dataDita("ontem", agora), "2026-09-24");
  assertEquals(dataDita("20/09", agora), "2026-09-20");
  assertEquals(dataDita("2026-09-01", agora), "2026-09-01");
  assertEquals(dataDita("semana passada", agora), null);
  assertEquals(dataDita(undefined, agora), null);
});

/** Banco falso: só o que o resolvedor lê. */
function admin() {
  const tabelas: Record<string, any[]> = {
    payees: [
      { id: "p-rob", name: "Roberto Carlos da Silva", default_category: "Serviços de terceiros", kind: "diarista" },
      { id: "p-gus", name: "Gustavo Seberino da Silva", default_category: null, kind: "socio" },
    ],
    suppliers: [{ id: "f-premel", name: "PREMEL MATERIAIS ELETRICOS", trade_name: "Premel" }],
    clients: [{ id: "c-mp", name: "MP MOTOR HOMES" }],
    financial_categories: [
      { name: "Alimentação de campo" }, { name: "Peças e materiais" }, { name: "Serviços de terceiros" }, { name: "Outras despesas" },
    ],
    service_orders: [{ id: "os60", service_order_number: "OS-00060" }],
  };
  const consulta = (nome: string) => {
    const q: any = {
      _rows: tabelas[nome] ?? [],
      select() { return q; }, eq() { return q; }, limit() { return q; },
      ilike(_c: string, padrao: string) {
        const alvo = padrao.replaceAll("%", "");
        q._rows = q._rows.filter((r: any) => String(r.service_order_number ?? "").includes(alvo));
        return q;
      },
      then(res: any) { return Promise.resolve({ data: q._rows, error: null }).then(res); },
    };
    return q;
  };
  return { from: consulta };
}
const ctx = (rpc?: (n: string, a: any) => any) => ({
  sb: { rpc: rpc ?? (() => Promise.resolve({ data: { ok: true }, error: null })) },
  admin: admin(), userId: "u-dono", userRole: "admin" as const, jwt: "", appOrigin: "", settings: {},
});

Deno.test("paguei 100 em dinheiro pro Roberto: favorecido e a categoria padrão dele", async () => {
  const p = await resolverPedidoDeCaixa(ctx() as never, { valor: 100, descricao: "diária", quem: "roberto" });
  if ("error" in p) throw new Error(p.error);
  assertEquals(p.pessoa?.id, "p-rob");
  assertEquals(p.categoria, "Serviços de terceiros");
  assertEquals(p.pagoPor, "caixa");
});

Deno.test("do meu bolso: o único sócio é achado sozinho e vira reembolso", async () => {
  let chamada: any = null;
  const c = ctx((n, a) => { chamada = { n, a }; return Promise.resolve({ data: { ok: true }, error: null }); });
  await caixaTools.find((t) => t.name === "lancar_no_caixa")!.execute(
    { valor: 80, descricao: "peça no balcão", categoria: "peças", pago_por: "bolso_do_socio", os: "60" }, c as never);
  assertEquals(chamada.n, "lancar_no_caixa");
  assertEquals(chamada.a.p_pago_por, "socio");
  assertEquals(chamada.a.p_socio_id, "p-gus");
  assertEquals(chamada.a.p_categoria, "Peças e materiais");
  assertEquals(chamada.a.p_os_id, "os60");
  assertEquals(chamada.a.p_autor, "u-dono");
});

Deno.test("recebimento sem cliente e categoria inexistente viram pergunta, sem gravar", async () => {
  let gravou = false;
  const c = ctx(() => { gravou = true; return Promise.resolve({ data: {}, error: null }); });
  const t = caixaTools.find((x) => x.name === "lancar_no_caixa")!;
  const r1 = await t.execute({ sentido: "recebimento", valor: 300, descricao: "serviço" }, c as never) as { error?: string };
  const r2 = await t.execute({ valor: 50, descricao: "almoço", categoria: "festa" }, c as never) as { error?: string };
  assertStringIncludes(String(r1.error), "de quem veio");
  assertStringIncludes(String(r2.error), "não existe");
  assertEquals(gravou, false);
});

Deno.test("a confirmação mostra o pedido resolvido", async () => {
  // Intl separa "R$" do número com espaço não separável; o que importa é o conteúdo.
  const txt = String(await resumirPedido(ctx() as never, "lancar_no_caixa", { valor: 100, descricao: "diária", quem: "roberto" })).replace(/\u00a0/g, " ");
  assertStringIncludes(String(txt), "R$ 100,00");
  assertStringIncludes(String(txt), "Serviços de terceiros");
  assertStringIncludes(String(txt), "Roberto Carlos da Silva");
  assertStringIncludes(String(txt), "Caixa (dinheiro)");
});

Deno.test("tudo que grava pede confirmação; consulta não", () => {
  for (const n of ["lancar_no_caixa", "ajustar_saldo_do_caixa", "anotar_transacao_do_banco"]) {
    assertEquals(caixaTools.find((t) => t.name === n)!.risk !== "low", true, n);
  }
  assertEquals(caixaTools.find((t) => t.name === "gastos_por_categoria")!.risk, "low");
});
