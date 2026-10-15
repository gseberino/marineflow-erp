// Vigia de conversas (15/10/2026): pelo texto da fonte (importar index.ts subiria o servidor da
// função). O que se protege: o estado da conversa traz a marca "o contato encerrou", julgada pelas
// últimas recebidas DENTRO da janela (7 dias, nunca antes do acompanhamento nascer) — sem isso o
// acompanhamento do Miguel seguiu avisando o dono por três dias depois de ele fechar com outra.
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("estadoDaConversa lê as últimas recebidas e marca encerrouPeloContato pela janela", () => {
  const ini = fonte.indexOf("async function estadoDaConversa(");
  assert(ini > 0);
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  assertStringIncludes(fn, ".limit(ULTIMAS_RECEBIDAS)");
  assertStringIncludes(fn, "janelaDoEncerramento(a, agora)");
  assertStringIncludes(fn, "encerrouPeloContato: conversaEncerradaPeloContato(");
  assertStringIncludes(fonte, "await estadoDaConversa(admin, a, agora)");
});

// Secretário, Passo 4 (15/10/2026). O que se protege, na ordem do laço de avisos:
//   1. a janela da manhã vem ANTES da contagem do freio e de qualquer leitura do dono (nada é gasto);
//   2. o freio só age com a chave ligada e só depois de contar pelo portão;
//   3. o registro no portão só acontece DEPOIS que o ai-agent aceitou o aviso (o que conta é o que saiu);
//   4. com a voz única e o freio desligados, não há contagem nem registro (modoDoRegistroDoAcompanhamento
//      devolve null — registrar_test.ts) — o laço é o de antes.
Deno.test("laço de avisos: janela da manhã → freio → dono → ai-agent → portão", () => {
  const ini = fonte.indexOf("async function avisar(");
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  const janela = fn.indexOf("if (!podeAvisarNoModo(a.modo, agora))");
  const conta = fn.indexOf("await avisosDestaMensagem(admin, referencia)");
  const freio = fn.indexOf("d = aplicarFreio(d, a, jaAvisados, portao.regras.freio_avisos)");
  const dono = fn.indexOf('from("app_users")');
  const agente = fn.indexOf("/functions/v1/ai-agent");
  const recusou = fn.indexOf("if (!res.ok)");
  const registro = fn.indexOf("await registrarNoPortao(admin, modoRegistro, dono.phone");
  assert(janela > 0 && conta > janela && freio > conta && dono > freio && agente > dono && recusou > agente && registro > recusou,
    `ordem: janela ${janela}, conta ${conta}, freio ${freio}, dono ${dono}, agente ${agente}, recusou ${recusou}, registro ${registro}`);
  assertStringIncludes(fn, "if (portao.freio) {");
  assertStringIncludes(fn, 'a.modo === "acompanhar" && (portao.freio || portao.modo) ? await avisosDestaMensagem');
  assertStringIncludes(fn, "const modoRegistro = modoDoRegistroDoAcompanhamento(portao, a.modo);");
  assertStringIncludes(fonte, "await avisar(admin, agora, conversaDosComprovantesLigada(settings), portaoDasConfiguracoes(settings))");
});

Deno.test("a detecção de promessas e o encerramento seguem das 8h (só o aviso espera as 09:30)", () => {
  assertStringIncludes(fonte, "if (!horaDeAvisar(agora)) return jr({ ok: true, fora_do_horario: true });");
  const ini = fonte.indexOf("async function avisar(");
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  assert(fn.indexOf('d.acao === "encerrar"') < fn.indexOf("podeAvisarNoModo"), "encerrar não espera a janela");
});
