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
  assertStringIncludes(fn, "const modoRegistro = modoDoRegistroDoAcompanhamento(portao, a.modo, peloPortao);");
  // (16/10/2026) o portão é lido uma vez (portaoDasConfiguracoes) e vale para os avisos e para o "me acorde se"
  assertStringIncludes(fonte, "const portao = portaoDasConfiguracoes(settings);");
  assertStringIncludes(fonte, "await avisar(admin, agora, conversaDosComprovantesLigada(settings), portao, donoDaVoz)");
});

// (20/10/2026, P4.5) Voz única LIGADA de verdade. O que se protege, no laço de avisos:
//   1. só o aviso ao DONO da manhã (donoDaVoz, lido só com portao.modo === 'ligado') pergunta ao portão, e ANTES do
//      assistente; o de outro telefone segue como se a voz estivesse desligada;
//   2. guardado/acabou/repetido (fala.manda = false) não chama o assistente, mas conta como dado (o intervalo e o "um só"
//      valem) — a rodada seguinte não pede de novo;
//   3. o assistente que recusou reabre o acorde (volta a guardado; a vaga do dia fica livre);
//   4. o registro DEPOIS (sombra/freio) não acontece quando já registrou antes (sem registro duplo).
Deno.test("P4.5: com a voz ligada o dono pergunta ao portão antes do ai-agent; guardado não chama; recusa reabre", () => {
  const ini = fonte.indexOf("async function avisar(");
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  assertStringIncludes(fn, 'const peloPortao = portao.modo === "ligado" && !!donoDaVoz && dono.phone === donoDaVoz.phone;');
  const pergunta = fn.indexOf("fala = await perguntarAoPortao(admin, dono.phone, avisoDoPortao, agora);");
  const naoManda = fn.indexOf("if (!fala.manda) {");
  const agente = fn.indexOf("/functions/v1/ai-agent");
  const reabre = fn.indexOf("if (fala?.acordou && await reabrirNoPortao(admin, fala.acordou, agora)) resultado.reabertos++;");
  const depois = fn.indexOf("if (modoRegistro && !peloPortao) {");
  assert(pergunta > 0 && naoManda > pergunta && agente > naoManda && reabre > agente && depois > reabre,
    `ordem: pergunta ${pergunta}, não manda ${naoManda}, agente ${agente}, reabre ${reabre}, depois ${depois}`);
  // o guardado conta como dado: o mesmo update do aviso que saiu (marcarAvisado) e o laço segue
  const bloco = fn.slice(naoManda, fn.indexOf("}", fn.indexOf("continue;", naoManda)) + 1);
  assertStringIncludes(bloco, "await marcarAvisado();");
  assertStringIncludes(bloco, "resultado.guardados_pelo_portao++;");
  assertStringIncludes(bloco, "continue;");
  // o dono da voz só é lido com a voz ligada (desligada/sombra: nada a mais)
  assertStringIncludes(fonte, 'const donoDaVoz = portao.modo === "ligado" ? await lerDonoDaVoz(admin) : null;');
});

Deno.test("a detecção de promessas e o encerramento seguem das 8h (só o aviso espera as 09:30)", () => {
  // (16/10/2026) a janela agora vem de rodadaDeAgora: avisos/promessas seg–sáb 08–20h; o "me acorde se" todo dia
  assertStringIncludes(fonte, "if (!rodada.avisos && !rodada.acordes) return jr({ ok: true, fora_do_horario: true });");
  const ini = fonte.indexOf("async function avisar(");
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  assert(fn.indexOf('d.acao === "encerrar"') < fn.indexOf("podeAvisarNoModo"), "encerrar não espera a janela");
});

// Secretário, Passo 4, P4.2 (16/10/2026). O que se protege:
//   1. o "me acorde se" só roda com a voz única em sombra/ligado (portao.modo) e com o dono — desligada, a rodada é a
//      de antes (nenhuma leitura nova);
//   2. ele vem DEPOIS dos avisos (não atrasa o acompanhamento) e o resultado só entra na resposta quando rodou;
//   3. D11: o fato novo só é pedido no 1º aviso do modo acompanhar, com a regra ligada, e depois de ler os acordes de
//      hoje do mesmo contato (erro de leitura = sem fato novo).
Deno.test("me acorde se: só com portao.modo e dono, depois dos avisos; D11 lê os acordes de hoje antes de registrar", () => {
  const avisos = fonte.indexOf("const avisos = rodada.avisos ? await avisar(admin, agora, conversaDosComprovantesLigada(settings), portao, donoDaVoz) : null;");
  const acordes = fonte.indexOf("const acordes = rodada.acordes && doAcorde && portao.modo");
  assert(avisos > 0 && acordes > avisos, `ordem avisos ${avisos} → acordes ${acordes}`);
  assertStringIncludes(fonte, "? await vigiarAcordes(admin, { agora, dono: doAcorde, portao, settings, internos,");
  // (20/10/2026) ligada, o acorde vai ao dono da manhã (donoDoWhatsApp); sombra, ao de sempre
  assertStringIncludes(fonte, 'const doAcorde = portao.modo === "ligado" ? donoDaVoz : dono ? { id: dono.id, phone: dono.phone_normalized } : null;');
  assertStringIncludes(fonte, "...(acordes ? { acordes } : {})");
  const ini = fonte.indexOf("async function avisar(");
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  assertStringIncludes(fn, 'if (modoRegistro && a.modo === "acompanhar" && ordem === 1 && portao.regras.mensagem_nova_e_fato_novo) {');
  assertStringIncludes(fn, "novoFato = acordes !== null && mensagemNovaEFatoNovo(portao.regras, ultimaEm, acordes);");
  assert(fn.indexOf("await acordesDeHojeDoAssunto(") < fn.indexOf("await registrarNoPortao(admin, modoRegistro, dono.phone"));
});

// (16/10/2026, decisão do dono) Domingo: só o "me acorde se". O que se protege, na ordem do handler:
//   1. fora das duas janelas não lê nada (nem cria o cliente do banco);
//   2. no domingo, com a voz única desligada, responde como antes ("fora_do_horario") ANTES de qualquer escrita;
//   3. a detecção de promessas (que move o cursor) e os avisos só rodam na janela de seg–sáb (rodada.avisos);
//   4. o detector só roda na janela dele (rodada.acordes).
Deno.test("domingo: só o detector; promessas e avisos seguem seg–sáb; voz desligada = a resposta de antes", () => {
  const ini = fonte.indexOf("servirComCors(");
  const h = fonte.slice(ini);
  const fora = h.indexOf("if (!rodada.avisos && !rodada.acordes) return jr({ ok: true, fora_do_horario: true });");
  const criar = h.indexOf("createClient(");
  assert(fora > 0 && criar > fora, "fora das janelas não cria o cliente");
  const desligada = h.indexOf("if (!rodada.avisos && !portao.modo) return jr({ ok: true, fora_do_horario: true });");
  const promessas = h.indexOf("await detectarPromessas(");
  const avisos = h.indexOf("await avisar(");
  assert(desligada > 0 && promessas > desligada && avisos > desligada, "domingo com a voz desligada sai antes de escrever");
  assertStringIncludes(h, "const promessas = !rodada.avisos ? null");
  assertStringIncludes(h, "const avisos = rodada.avisos ? await avisar(");
  assertStringIncludes(h, "const acordes = rodada.acordes && doAcorde && portao.modo");
});

// (25/10/2026, Agenda de Produção, Fase 4, P4) O prazo do fornecedor. O que se protege, na ordem do handler:
//   1. só na rodada de avisos (seg–sáb 08–20h), por ÚLTIMO (C1 da revisão da Fase 4, R5): depois das promessas, dos avisos
//      ao dono e do "me acorde se" — o dono vem primeiro;
//   2. fora de qualquer try próprio: o passo nunca lança (fornecedores_test.ts), então não derruba a rodada;
//   3. o resumo da rodada leva o resultado ({ lidas, sinais, modelo }).
Deno.test("prazo do fornecedor: na rodada de avisos, por último (depois dos avisos ao dono e do 'me acorde se')", () => {
  const ini = fonte.indexOf("servirComCors(");
  const h = fonte.slice(ini);
  const promessas = h.indexOf("await detectarPromessas(");
  const fornecedores = h.indexOf("await vigiarPrazosDosFornecedores(admin, agora)");
  const avisos = h.indexOf("await avisar(");
  const acordes = h.indexOf("await vigiarAcordes(");
  assert(promessas > 0 && avisos > promessas && acordes > avisos && fornecedores > acordes,
    `ordem: promessas ${promessas}, avisos ${avisos}, acordes ${acordes}, fornecedores ${fornecedores}`);
  assertStringIncludes(h, "const fornecedores = rodada.avisos ? await vigiarPrazosDosFornecedores(admin, agora) : null;");
  assertStringIncludes(h, "...(fornecedores ? { fornecedores } : {})");
  assertStringIncludes(fonte, 'import { vigiarPrazosDosFornecedores } from "./fornecedores.ts";');
});
