// E-mail urgente avisado UMA vez (15/10/2026). O mesmo golpe ("CONTRATO 20037247643 - Advocacia
// Antonio Samuel da Silveira", do mesmo remetente) chegou em 13/10 e 14/10 e foi avisado na hora
// duas vezes. Pelo texto da fonte (importar index.ts subiria o servidor da função).
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("antes de avisar o urgente, procura aviso do mesmo remetente e assunto nos últimos 30 dias", () => {
  const ini = fonte.indexOf('if (recente && t.classe === "urgent"');
  assert(ini > 0, "bloco do aviso de urgente");
  const bloco = fonte.slice(ini, fonte.indexOf("cursor = uid;", ini));
  const consulta = bloco.indexOf("await jaAvisadoAntes(");
  assert(consulta > 0, "o bloco consulta aviso anterior");
  assert(consulta < bloco.indexOf("await avisarUrgente("), "a consulta vem antes do aviso");
  assertStringIncludes(bloco, "if (!repetido)");
});

Deno.test("a consulta compara remetente e assunto como foram gravados e olha alerted_at de 30 dias", () => {
  const ini = fonte.indexOf("async function jaAvisadoAntes(");
  assert(ini > 0);
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  assertStringIncludes(fn, '.eq("from_address", normalizeAddress(endereco))');
  assertStringIncludes(fn, '.gte("alerted_at"');
  assertStringIncludes(fn, "30 * 86400_000");
  assertStringIncludes(fn, '.is("subject", null)');
  // Erro na leitura não cala um urgente: avisa (repetir é melhor que perder um golpe novo).
  assertStringIncludes(fn, "return false;");
});

// Voz única (secretário, Passo 4, 15/10/2026). O que se protege: o registro no portão vem DEPOIS do
// aviso entrar na fila e só com o modo ligado; o diagnóstico não lê as chaves. Desligado: nada é
// registrado (registrar_test.ts) — o aviso é o mesmo de antes.
Deno.test("voz única: o urgente vai ao portão (sombra) depois da fila; diagnóstico não lê as chaves", () => {
  const ini = fonte.indexOf("async function avisarUrgente(");
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  const fila = fn.indexOf('await admin.from("whatsapp_send_queue").insert(rows)');
  const registro = fn.indexOf("await registrarParaTodos(");
  assert(fila > 0 && registro > fila, "fila → registro");
  assertStringIncludes(fn, 'if (rows.length && voz.portao.modo === "sombra")');
  assertStringIncludes(fonte, "const portao = diagnostico ? PORTAO_DESLIGADO : await lerPortao(admin);");
  assertStringIncludes(fonte, "{ emailId: id, endereco: normalizeAddress(email.from.address), portao, dono }");
});

// (16/10/2026, P4.2) O golpe vai ao portão com o texto do acorde; o que entra na fila (o aviso de sempre) não muda.
Deno.test("P4.2: o golpe registra o texto do acorde; a fila continua com o texto de sempre", () => {
  const ini = fonte.indexOf("async function avisarUrgente(");
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  assertStringIncludes(fn, "const doPortao = fraude ? textoDoGolpe({ conta, remetente, assunto }) : texto;");
  assertStringIncludes(fn, "message: texto, source: \"email_urgente\"");
  assertStringIncludes(fn, "voz.portao.regras, doPortao);");
});

// (20/10/2026, P4.5) Voz única LIGADA de verdade. O que se protege: só o dono (lido só com a voz ligada) pergunta ao
// portão, ANTES da fila; o golpe que acorda vai pela fila com a chave aviso:<id> e o texto do ACORDE; guardado (o
// urgente sem golpe, D1) e repetido (o mesmo remetente de golpe) não saem; portão ilegível = o aviso de sempre; os
// outros admins recebem o de sempre.
Deno.test("P4.5: o dono pergunta antes da fila; só o acorde sai (chave aviso:<id>); erro = como sempre", () => {
  const ini = fonte.indexOf("async function avisarUrgente(");
  const fn = fonte.slice(ini, fonte.indexOf("\n}\n", ini));
  const pergunta = fn.indexOf("const fala = await perguntarAoPortao(admin, phone, aviso);");
  const acorde = fn.indexOf('if (fala.acordou) await enfileirarAcorde(admin, { phone, texto: doPortao, avisoId: fala.acordou, agora: new Date(), source: "email_urgente" });');
  const erro = fn.indexOf("else if (fala.manda) comoSempre.push(phone);");
  const fila = fn.indexOf('await admin.from("whatsapp_send_queue").insert(rows)');
  assert(pergunta > 0 && acorde > pergunta && erro > acorde && fila > erro, `ordem: ${pergunta} ${acorde} ${erro} ${fila}`);
  assertStringIncludes(fn, "if (!falaPeloPortao(voz.portao, voz.dono, phone)) {");
  assertStringIncludes(fn, "const rows = comoSempre.map((phone) => ({ phone_normalized: phone, message: texto, source: \"email_urgente\", priority: 2 }));");
  assertStringIncludes(fonte, 'const dono = portao.modo === "ligado" ? await lerDonoDaVoz(admin) : null;');
});

// Agenda de Produção, Fase 4 (P3, 25/10/2026). O que se protege: a remessa da NF-e é registrada DEPOIS de gravar
// dados_extraidos (o banco lê de lá), nos dois caminhos (a leitura da caixa e o ?reextrair=1), e nunca derruba a leitura
// (registrarRemessas não lança: remessas_test.ts); ?remessas=1 é a releitura das notas de antes de 25/10.
Deno.test("Fase 4: a remessa vem depois do update de dados_extraidos, na leitura da caixa e no reextrair", () => {
  const ini = fonte.indexOf("// Etapa 4 (08/10/2026)");
  assert(ini > 0);
  const bloco = fonte.slice(ini, fonte.indexOf("// Triagem só do que é recente", ini));
  const grava = bloco.indexOf('await admin.from("email_messages").update({ dados_extraidos: { ...dados, nfes }, ...ligar }).eq("id", id);');
  const remessa = bloco.indexOf("if (temNotaParaEmpresa(dados)) await registrarRemessas(admin, id);");
  assert(grava > 0 && remessa > grava, `ordem: ${grava} ${remessa}`);

  const r = fonte.indexOf("async function reextrair(");
  const fn = fonte.slice(r, fonte.indexOf("\n}\n", r));
  const g2 = fn.indexOf('await admin.from("email_messages").update({ dados_extraidos: gravar, ...ligar }).eq("id", m.id);');
  const r2 = fn.indexOf("if (temNotaParaEmpresa(dados)) await registrarRemessas(admin, m.id);");
  assert(g2 > 0 && r2 > g2, `reextrair: ${g2} ${r2}`);
});

Deno.test("Fase 4: ?remessas=1 chama a releitura e responde 500 só com erro de leitura (o modo desligado é pulado)", () => {
  assertStringIncludes(fonte, 'if (new URL(req.url).searchParams.get("remessas") === "1") {');
  assertStringIncludes(fonte, "return jr({ ok: true, ...(await relerRemessas(admin, cnpjEmpresa)), ms: Date.now() - inicio });");
  assertStringIncludes(fonte, 'import { registrarRemessas, relerRemessas, temNotaParaEmpresa } from "./remessas.ts";');
});
