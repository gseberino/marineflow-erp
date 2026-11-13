// Retorno rápido, F5 (P10.3): a camada do orçamento, com banco falso. Não importa _shared/ai/ (isolamento_test.ts varre
// esta pasta): tudo o que ela precisa chega por parâmetro, como nas camadas da F2 e da F4. Frases e números inventados.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { camadaDoOrcamento, type DependenciasDoOrcamento, ehPalavraDoOrcamentoLigada, R_ORCAMENTO } from "./camada.ts";

type Registro = { rpcs: Array<{ fn: string; args: Record<string, unknown> }>; donos: number };

function deps(
  o: Partial<DependenciasDoOrcamento> & { resposta?: unknown; erro?: unknown; dono?: boolean } = {},
): { d: DependenciasDoOrcamento; reg: Registro } {
  const reg: Registro = { rpcs: [], donos: 0 };
  const d: DependenciasDoOrcamento = {
    autor: "dono-1",
    ehDoDono: o.ehDoDono ?? (() => {
      reg.donos++;
      return Promise.resolve(o.dono ?? true);
    }),
    rpc: o.rpc ?? ((fn, args) => {
      reg.rpcs.push({ fn, args });
      return Promise.resolve({
        data: o.erro
          ? null
          : ("resposta" in o ? o.resposta : { ok: true, texto: "Segurei os lembretes do ORÇ-00151 (Ana). Para voltar: *solta 151*." }),
        error: (o.erro ?? null) as { code?: string } | null,
      });
    }),
  };
  return { d, reg };
}

Deno.test("cada palavra vai a orcamento_dito, uma vez, com o comando lido e o autor, e a resposta volta como texto", async () => {
  const casos: Array<[string, Record<string, unknown>]> = [
    ["segura 151", { comando: "segura", numero: 151 }],
    ["Segura ORÇ-00151.", { comando: "segura", numero: 151 }],
    ["solta 151", { comando: "solta", numero: 151 }],
    ["segura orçamentos", { comando: "segura_todos" }],
    ["solta orcamentos", { comando: "solta_todos" }],
    ["motivo 151 B", { comando: "motivo", numero: 151, letra: "B" }],
    ["motivo 151 preço", { comando: "motivo", numero: 151, letra: "D" }],
    ["motivo orc 151 outra empresa", { comando: "motivo", numero: 151, letra: "B" }],
  ];
  for (const [texto, comando] of casos) {
    const { d, reg } = deps();
    const r = await camadaDoOrcamento(texto, d);
    assert(r !== null, texto);
    assertEquals(reg.rpcs, [{ fn: "orcamento_dito", args: { p_comando: comando, p_autor: "dono-1" } }], texto);
    assertEquals(r.texto, "Segurei os lembretes do ORÇ-00151 (Ana). Para voltar: *solta 151*.", texto);
    assertEquals(r.comando, comando.comando, texto);
    // nada vai ao histórico do assistente por aqui
    assertEquals(r.noHistorico, null, texto);
  }
});

Deno.test("o que não é palavra do orçamento segue como sempre: null, sem banco e sem perguntar o dono", async () => {
  for (const t of ["segura", "segura 1", "segura 151?", "1 b", "nao 1", "retorno", "parceiro 74", "segura tudo", "motivo 151 e", "bom dia"]) {
    const { d, reg } = deps();
    assertEquals(await camadaDoOrcamento(t, d), null, t);
    assertEquals(reg.rpcs.length, 0, t);
    assertEquals(reg.donos, 0, t);
  }
});

Deno.test("só o dono: de outro número, nada é lido e o texto segue; ehDoDono que lança conta como não", async () => {
  for (const t of ["segura 151", "solta 151", "segura orcamentos", "motivo 151 b"]) {
    const { d, reg } = deps({ dono: false });
    assertEquals(await camadaDoOrcamento(t, d), null, t);
    assertEquals(reg.rpcs.length, 0, t);
  }
  const { d, reg } = deps({ ehDoDono: () => Promise.reject(new Error("rede")) });
  assertEquals(await camadaDoOrcamento("segura 151", d), null);
  assertEquals(reg.rpcs.length, 0);
  // o banco confere de novo (is_admin_or_financial): nao_e_o_dono também segue como sempre
  const outro = deps({ resposta: { ok: false, motivo: "nao_e_o_dono" } });
  assertEquals(await camadaDoOrcamento("segura 151", outro.d), null);
});

Deno.test("o PIN nunca vai ao banco: a camada não lê PIN, e nenhuma frase com sim <PIN> é palavra do orçamento", async () => {
  for (const t of ["segura 151 sim 7391", "motivo 151 b sim 7391", "sim 7391", "solta 151 7391"]) {
    const { d, reg } = deps();
    assertEquals(await camadaDoOrcamento(t, d), null, t);
    assertEquals(reg.rpcs.length, 0, t);
  }
  const { d, reg } = deps();
  await camadaDoOrcamento("motivo 151 b", d);
  assert(!JSON.stringify(reg.rpcs).includes("7391"));
  assert(!JSON.stringify(reg.rpcs).includes("pin"));
});

Deno.test("erro, exceção, função ausente e resposta sem texto: a frase fixa, e nada lança", async () => {
  const erros: Array<Partial<DependenciasDoOrcamento> & { resposta?: unknown; erro?: unknown }> = [
    { erro: { code: "57014", message: "tempo esgotado" } },
    { erro: { code: "PGRST202", message: "função ausente" } },
    { erro: { code: "42883", message: "função ausente" } },
    { rpc: () => Promise.reject(new Error("rede")) },
    { resposta: { ok: false } },
    { resposta: { ok: false, texto: "" } },
    { resposta: null },
    { resposta: "texto solto" },
    { resposta: [1, 2] },
  ];
  for (const o of erros) {
    const { d } = deps(o);
    const r = await camadaDoOrcamento("segura 151", d);
    assertEquals(r?.texto, R_ORCAMENTO, JSON.stringify(o));
    assertEquals(r?.noHistorico, null);
  }
  assertEquals(R_ORCAMENTO, "Não consegui agora; tente pela tela.");
  // o texto de erro que o banco devolve (o c_erro de orcamento_dito) passa como veio
  const { d } = deps({ resposta: { ok: false, texto: "Não consegui agora; tente pela tela." } });
  assertEquals((await camadaDoOrcamento("motivo 151 b", d))?.texto, "Não consegui agora; tente pela tela.");
});

Deno.test("ehPalavraDoOrcamentoLigada: verdadeira para *segura 151* e as outras formas; falsa para segura, segura 1 e conversa", () => {
  for (const t of ["segura 151", "*segura 151*", "Segura ORÇ-00151.", "solta 151", "segura orcamentos", "solta orçamentos", "motivo 151 b", "motivo 151 preco"]) {
    assertEquals(ehPalavraDoOrcamentoLigada(t), true, t);
  }
  for (const t of ["segura", "segura 1", "segura 151?", "1 b", "segura tudo", "segura cliente", "sim 7391", "", "bom dia"]) {
    assertEquals(ehPalavraDoOrcamentoLigada(t), false, t);
  }
});
