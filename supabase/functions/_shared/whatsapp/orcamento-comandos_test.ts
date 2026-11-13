// Retorno rápido, F5 (P10.3, seção 7.2): as palavras do dono sobre o orçamento, rodadas contra os leitores REAIS.
//
// Fica fora de _shared/orcamento/ porque importa _shared/ai/, e o isolamento_test.ts varre aquela pasta, testes inclusive
// (o molde é retorno-comandos_test.ts, F2 e F4). Roda também as linhas da matriz marcadas com † ("a rodar"), que a versão 2
// da spec acrescentou sem rodar: *motivo 151 preco*, *motivo 151 outra empresa*, *motivo 151 desistiu*, *motivo 151 e*,
// *resolvido 1*, *enviado 1* e *dita 1 …*. Todas as frases e números são inventados: nenhuma vem de whatsapp_messages nem
// de ai_operator_messages. O 7391 também é inventado.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { frasesDoOrcamento, lerComandoDoOrcamento } from "../orcamento/comandos.ts";
import { lerComandoDoRetorno } from "../retorno/comandos.ts";
import { lerComandoDaAgenda } from "../agenda/comandos.ts";
import { lerComandoDoParceiro } from "../parceiro/comandos.ts";
import { lerComandoDoSecretario } from "../secretario/comandos.ts";
import { parseConfirmationReply, parseOptionReply } from "../ai/whatsapp-channel.ts";
import { lerComando } from "../comprovantes/respostas.ts";
import { lerPedidoDePdf } from "../ai/atalho-pdf.ts";
import { classificarResposta } from "../ai/comms/reply-router.ts";
import { ehPedidoDeParar } from "./parar.ts";
import { lerNumero, lerSimNao, normalizarResposta, pareceRespostaCurta } from "./pergunta-ativa.ts";

/** Nenhum leitor que não o da F5 lê a frase (as colunas "—" da matriz 7.2). */
function ninguemMaisLe(t: string): void {
  assertEquals(lerComandoDoRetorno(t), null, `retorno: ${t}`);
  assertEquals(lerComandoDoParceiro(t), null, `parceiro: ${t}`);
  assertEquals(lerComandoDaAgenda(t), null, `agenda: ${t}`);
  assertEquals(lerComandoDoSecretario(t), null, `secretário: ${t}`);
  assertEquals(lerComando(t), null, `comprovantes: ${t}`);
  assertEquals(lerPedidoDePdf(t), null, `pdf: ${t}`);
  assertEquals(parseConfirmationReply(t), null, `confirmação: ${t}`);
  assertEquals(parseOptionReply(t, 9), null, `opção: ${t}`);
  const n = normalizarResposta(t);
  assertEquals(lerNumero(n, 99), null, `número: ${t}`);
  assertEquals(lerSimNao(n), null, `sim/não: ${t}`);
  assertEquals(pareceRespostaCurta(t), false, `curta: ${t}`);
  assertEquals(ehPedidoDeParar(t), false, `parar: ${t}`);
}

Deno.test("F5 7.2: as formas do orçamento são lidas só pelo leitor da F5", () => {
  const formas = frasesDoOrcamento();
  for (const f of formas) {
    for (const t of [f, `*${f}*`, `${f[0].toUpperCase()}${f.slice(1)}.`]) {
      assert(lerComandoDoOrcamento(t) !== null, `o próprio leitor: ${t}`);
      ninguemMaisLe(t);
    }
  }
  for (const t of ["segura orç-00151", "Segura ORÇ-00151", "segura orçamentos", "solta orçamentos", "motivo 151 B", "motivo 151 preço"]) {
    assert(lerComandoDoOrcamento(t) !== null, t);
    ninguemMaisLe(t);
  }
});

Deno.test("F5 7.2 †: *motivo 151 preco*, *outra empresa* e *desistiu* — só a F5 lê, e a palavra vale a letra", () => {
  assertEquals(lerComandoDoOrcamento("motivo 151 preco"), { comando: "motivo", numero: 151, letra: "D" });
  assertEquals(lerComandoDoOrcamento("motivo 151 outra empresa"), { comando: "motivo", numero: 151, letra: "B" });
  assertEquals(lerComandoDoOrcamento("motivo 151 desistiu"), { comando: "motivo", numero: 151, letra: "C" });
  for (const t of ["motivo 151 preco", "motivo 151 outra empresa", "motivo 151 desistiu"]) ninguemMaisLe(t);
  // ao cliente nunca chega: mesmo assim, nenhuma dessas frases é "acordo" nem pedido de parar
  for (const t of ["motivo 151 preco", "motivo 151 outra empresa", "motivo 151 desistiu"]) {
    assert(classificarResposta(t).intencao !== "acordo", `reply-router: ${t}`);
  }
});

Deno.test("F5 7.2 †: *motivo 151 e* não é motivo (sem E) e ninguém mais o lê", () => {
  assertEquals(lerComandoDoOrcamento("motivo 151 e"), null);
  ninguemMaisLe("motivo 151 e");
});

Deno.test("F5 7.2 †: *resolvido 1*, *enviado 1* e *dita 1 …* — da F2 (ou de ninguém), nunca da F5", () => {
  assertEquals(lerComandoDoRetorno("resolvido 1"), { comando: "resolvido", n: 1 });
  assertEquals(lerComandoDoOrcamento("resolvido 1"), null);
  // *enviado N* não é palavra de leitor nenhum (corrigido na versão 3 da spec)
  assertEquals(lerComandoDoRetorno("enviado 1"), null);
  assertEquals(lerComandoDoOrcamento("enviado 1"), null);
  ninguemMaisLe("enviado 1");
  const dita = lerComandoDoRetorno("dita 1 pode marcar para quinta");
  assertEquals(dita?.comando, "ditar");
  assertEquals(lerComandoDoOrcamento("dita 1 pode marcar para quinta"), null);
  for (const t of ["resolvido 1", "dita 1 pode marcar para quinta"]) {
    assertEquals(lerComandoDoParceiro(t), null, `parceiro: ${t}`);
    assertEquals(lerComandoDaAgenda(t), null, `agenda: ${t}`);
    assertEquals(lerComandoDoSecretario(t), null, `secretário: ${t}`);
    assertEquals(lerComando(t), null, `comprovantes: ${t}`);
    assertEquals(lerPedidoDePdf(t), null, `pdf: ${t}`);
    assertEquals(parseConfirmationReply(t), null, `confirmação: ${t}`);
  }
});

Deno.test("F5 7.2: as linhas que ficam com outra camada não são da F5", () => {
  // da agenda
  assertEquals(lerComandoDoOrcamento("segura cliente"), null);
  assertEquals(lerComandoDoOrcamento("segura cliente Ana"), null);
  // do retorno (F2, F4)
  for (const t of ["segura recibos", "segura tudo", "segura patio"]) {
    assertEquals(lerComandoDoOrcamento(t), null, t);
    assert(lerComandoDoRetorno(t) !== null, t);
  }
  // as letras do item de aceite são da F2
  for (const t of ["1 a", "1 b", "1 c", "1 d"]) {
    assertEquals(lerComandoDoRetorno(t)?.comando, "escolher", t);
    assertEquals(lerComandoDoOrcamento(t), null, t);
  }
  assertEquals(lerComandoDoRetorno("1 a sim 7391")?.comando, "escolher");
  assertEquals(lerComandoDoOrcamento("1 a sim 7391"), null);
  // *não 1*: o leitor da F2 vem antes da confirmação
  assertEquals(lerComandoDoRetorno("nao 1")?.comando, "tirar");
  assertEquals(parseConfirmationReply("nao 1")?.decision, "reject");
  assertEquals(lerComandoDoOrcamento("nao 1"), null);
  // *lista orcamentos* é do Secretário; *orcamentos* sozinho e *segura a* e *151 b* não são de ninguém novo
  assertEquals(lerComandoDoOrcamento("lista orcamentos"), null);
  for (const t of ["orcamentos", "orçamentos", "segura a", "151 b", "segura 1", "segura"]) assertEquals(lerComandoDoOrcamento(t), null, t);
  assertEquals(lerComandoDoRetorno("errado z")?.comando, "errado");
  assertEquals(lerComandoDoOrcamento("errado z"), null);
});

// ─── A ligação (P10.1): a ordem das camadas no ai-agent e a marca do webhook, lidas da fonte ─────────────────────────

Deno.test("F5 P10.1: no ai-agent a camada do orçamento vem antes das do parceiro e do retorno; o webhook marca a palavra", async () => {
  const agente = await Deno.readTextFile(new URL("../../ai-agent/index.ts", import.meta.url));
  const orc = agente.indexOf("await camadaDoOrcamento(text,");
  const parc = agente.indexOf("await camadaDoParceiro(text,");
  const ret = agente.indexOf("await camadaDoRetorno(text,");
  assert(orc > 0 && parc > 0 && ret > 0, "as três camadas estão no turno do WhatsApp");
  assert(orc < parc && parc < ret, "orçamento → parceiro → retorno");
  const webhook = await Deno.readTextFile(new URL("../../whatsapp-webhook/index.ts", import.meta.url));
  assert(webhook.includes("ehPalavraDoOrcamentoLigada(t)"), "a marca do webhook (o CMP aberto não engole a palavra)");
});
