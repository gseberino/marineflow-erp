// O prazo do fornecedor no acompanhar-conversas (Agenda de Produção, Fase 4, P4). O que se protege, com um banco e um
// modelo de mentira:
//   · desligado (a RPC devolve a lista vazia) não chama mais nada: nem o parser registra, nem o modelo;
//   · com UMA compra viva, ela é a escolhida (unico) e o modelo NÃO é chamado; com mais, o modelo escolhe (modelo) ou não
//     (nenhum) — e quem manda a data é o banco: o TS passa só a expressão dita;
//   · a mensagem sem prazo não é registrada;
//   · nunca lança: a RPC que falha vira { erro } e app_error_logs (agenda:fornecedor); a mensagem que falha sozinha não
//     derruba as outras; a função ausente (migration não aplicada) é silêncio ({ pulado }).
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type MensagemDeFornecedor, vigiarPrazosDosFornecedores } from "./fornecedores.ts";

const AGORA = new Date("2026-10-13T21:00:00.000Z"); // ter 13/10, 18:00 em Brasília

interface Chamada { fn: string; args: Record<string, unknown> }

function banco(lista: MensagemDeFornecedor[] | { error: { code?: string; message: string } }, falhaNo?: string) {
  const chamadas: Chamada[] = [];
  return {
    chamadas,
    rpc(fn: string, args: Record<string, unknown>) {
      chamadas.push({ fn, args });
      if (fn === "agenda_mensagens_de_fornecedor") {
        return Promise.resolve(Array.isArray(lista) ? { data: lista, error: null } : { data: null, error: lista.error });
      }
      if (fn === "material_sinal_registrar") {
        if (falhaNo && args.p_msg === falhaNo) return Promise.resolve({ data: null, error: { message: "boom" } });
        return Promise.resolve({ data: { id: "s1" }, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };
}

const COMPRESSOR = { n: 1, os: "os104", os_material_id: "m104", rotulo: "Flávio: Compressor 12V de… (comprado 13/10)" };
const PAINEL = { n: 2, os: "os112", os_material_id: "m112", rotulo: "Nelson: Painel Touch de… (comprado 15/10)" };
const msg = (id: string, texto: string, compras = [COMPRESSOR], direcao: "recebida" | "enviada" = "recebida"): MensagemDeFornecedor => ({
  msg_id: id, fornecedor_id: "dd04", fornecedor: "Mateus", direcao, texto, em: "2026-10-13T20:19:00.000Z", compras,
});

function deps() {
  const escolhas: string[] = [];
  const logs: Array<Record<string, unknown>> = [];
  return {
    escolhas,
    logs,
    escolher: (trecho: string) => {
      escolhas.push(trecho);
      return Promise.resolve({ n: 2, confianca: 0.8 });
    },
    // deno-lint-ignore no-explicit-any
    log: (_db: any, input: Record<string, unknown>) => {
      logs.push(input);
      return Promise.resolve();
    },
  };
}

Deno.test("desligado (lista vazia): só a leitura, nada registrado, nenhum modelo", async () => {
  const db = banco([]);
  const d = deps();
  const r = await vigiarPrazosDosFornecedores(db, AGORA, d);
  assertEquals(r, { lidas: 0, sinais: 0, modelo: 0 });
  assertEquals(db.chamadas.map((c) => c.fn), ["agenda_mensagens_de_fornecedor"]);
  assertEquals(db.chamadas[0].args, { p_hoje: "2026-10-13", p_agora: AGORA.toISOString() });
  assertEquals(d.escolhas.length, 0);
});

Deno.test("uma compra viva: unico, sem o modelo; a expressão vai crua para o banco", async () => {
  const db = banco([
    msg("w403", "chega aqui amanha se eles retirarem hoje", [COMPRESSOR], "enviada"),
    msg("w405", "Tenho disponivel"),
    msg("w409", "Já foi coletado"),
  ]);
  const d = deps();
  const r = await vigiarPrazosDosFornecedores(db, AGORA, d);
  assertEquals(r, { lidas: 3, sinais: 2, modelo: 0 });
  assertEquals(d.escolhas.length, 0);
  const regs = db.chamadas.filter((c) => c.fn === "material_sinal_registrar").map((c) => c.args);
  assertEquals(regs.map((a) => [a.p_msg, a.p_tipo, a.p_expressao, a.p_condicional, a.p_casou_por, a.p_os_material]), [
    ["w403", "chegada", "amanhã", true, "unico", "m104"],
    ["w409", "despacho", null, false, "unico", "m104"],
  ]);
  assertEquals(regs[1].p_trecho, "Já foi coletado");
  assertEquals(regs[1].p_candidatos, [{ n: 1, os: "os104", os_material_id: "m104", rotulo: COMPRESSOR.rotulo }]);
  assert(!("p_data_ate" in regs[1]) && !("p_data" in regs[1]), "nenhuma data sai do TS");
});

Deno.test("mais de uma compra: o modelo escolhe (modelo); sem compra nenhuma: nenhum", async () => {
  const db = banco([msg("w1", "O painel foi postado hoje", [COMPRESSOR, PAINEL]), msg("w2", "Despachado!", [])]);
  const d = deps();
  const r = await vigiarPrazosDosFornecedores(db, AGORA, d);
  assertEquals(r, { lidas: 2, sinais: 2, modelo: 1 });
  assertEquals(d.escolhas, ["O painel foi postado hoje"]);
  const regs = db.chamadas.filter((c) => c.fn === "material_sinal_registrar").map((c) => c.args);
  assertEquals([regs[0].p_casou_por, regs[0].p_os_material, regs[0].p_confianca], ["modelo", "m112", 0.8]);
  assertEquals([regs[1].p_casou_por, regs[1].p_os_material], ["nenhum", null]);
  // o modelo que não escolhe = nenhum, com a confiança dele
  const db2 = banco([msg("w3", "Coletaram hoje", [COMPRESSOR, PAINEL])]);
  await vigiarPrazosDosFornecedores(db2, AGORA, { ...d, escolher: () => Promise.resolve({ n: null, confianca: 0.3 }) });
  const r2 = db2.chamadas.find((c) => c.fn === "material_sinal_registrar")!.args;
  assertEquals([r2.p_casou_por, r2.p_os_material, r2.p_confianca], ["nenhum", null, 0.3]);
});

Deno.test("nunca lança: a leitura que falha, a mensagem que falha sozinha, a função ausente", async () => {
  const d = deps();
  const r = await vigiarPrazosDosFornecedores(banco({ error: { code: "XX000", message: "caiu" } }), AGORA, d);
  assertEquals(r.erro, "caiu");
  assertEquals(d.logs.length, 1);
  assertEquals([d.logs[0].context, d.logs[0].action], ["acompanhar-conversas", "agenda:fornecedor"]);

  const d2 = deps();
  const db = banco([msg("w1", "Já foi coletado"), msg("w2", "Chega amanhã")], "w1");
  const r2 = await vigiarPrazosDosFornecedores(db, AGORA, d2);
  assertEquals([r2.lidas, r2.sinais, r2.erros], [2, 1, 1]);
  assertEquals(d2.logs.length, 1);
  assertEquals(d2.logs[0].action, "agenda:fornecedor");

  const d3 = deps();
  const r3 = await vigiarPrazosDosFornecedores(banco({ error: { code: "PGRST202", message: "não existe" } }), AGORA, d3);
  assertEquals(r3.pulado, "agenda_mensagens_de_fornecedor ausente");
  assertEquals(d3.logs.length, 0);
});
