// E-mail urgente avisado UMA vez (15/10/2026). O mesmo golpe ("CONTRATO 20037247643 - Advocacia
// Antonio Samuel da Silveira", do mesmo remetente) chegou em 13/10 e 14/10 e foi avisado na hora
// duas vezes. Pelo texto da fonte (importar index.ts subiria o servidor da função).
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

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

// Pacote 1, V2 (24/11/2026). De 12 a 24/11 a triagem falhou em 95 e-mails sem deixar uma linha em app_error_logs. O que
// se protege: o registro vem logo depois da triagem, só quando ela falhou (t.falha), antes de gravar a classe; e o e-mail
// é gravado do mesmo jeito (a falha não pula a gravação nem esconde o e-mail).
Deno.test("V2: a triagem que falhou é registrada logo depois de triageEmail, só com t.falha, e o e-mail é gravado igual", () => {
  const ini = fonte.indexOf("// Triagem só do que é recente");
  assert(ini > 0);
  const bloco = fonte.slice(ini, fonte.indexOf("cursor = uid;", ini));
  const triagem = bloco.indexOf("await triageEmail(email");
  const registro = bloco.indexOf('if (t.falha) await registrarFalhaDeRotina(admin, { rotina: "triagem_email", mensagem: t.falha });');
  const grava = bloco.indexOf("triage_class: t.classe");
  assert(triagem > 0 && registro > triagem && grava > registro, `ordem: ${triagem} ${registro} ${grava}`);
  assertEquals(bloco.split("registrarFalhaDeRotina(").length, 2, "um registro só, o da triagem");
  assertStringIncludes(fonte, 'import { registrarFalhaDeRotina } from "../_shared/ai/falhas-do-assistente.ts";');
  // o registro leva só o erro técnico: nem assunto, nem corpo, nem remetente
  const linha = bloco.slice(registro, bloco.indexOf("\n", registro));
  for (const proibido of ["email.subject", "email.text", "email.from", "body"]) assert(!linha.includes(proibido), proibido);
});

// Pacote 1, F1 (24/11/2026). O alerta de golpe parou em 12/11 porque só saía de e-mail classificado pelo modelo, e o
// provedor ficou sem saldo. O que se protege: a regra fixa (triage.ts) entra pela MESMA triagem e pelo MESMO aviso do
// urgente (teto do dia, "não repetir", portão), sem caminho próprio; e o aviso só vai aos admins, nunca ao remetente.
// (Revisão, 24/11/2026) Sem interruptor: a especificação não pede chave nova, e a rodada não lê app_settings por ela.
Deno.test("F1: a regra fixa do golpe entra pela triagem e usa o aviso do urgente; sem chave para desligar; nada vai ao remetente", () => {
  assertStringIncludes(fonte, 'import { MARCA_DA_REGRA_FIXA, triageEmail, type Triage } from "../_shared/email/triage.ts";');
  // nenhuma chave nova: a única leitura de app_settings do arquivo é a do CNPJ, que já existia
  for (const sumiu of ["CHAVE_DA_REGRA_DO_GOLPE", "regraDoGolpeLigada", "cfgGolpe", "regraDoGolpe"]) assert(!fonte.includes(sumiu), sumiu);
  assertEquals(fonte.split('admin.from("app_settings")').length, 2, "uma leitura de app_settings, a do CNPJ");
  assertStringIncludes(fonte, 'await admin.from("app_settings").select("value").eq("key", "cnpj").maybeSingle();');
  // a triagem é chamada como antes do F1; o remetente silenciado continua sem triagem nenhuma
  const ini = fonte.indexOf("// Triagem só do que é recente");
  const bloco = fonte.slice(ini, fonte.indexOf("cursor = uid;", ini));
  assertStringIncludes(bloco, ": await triageEmail(email);");
  assert(bloco.indexOf('regra === "ignore_always"') < bloco.indexOf("await triageEmail(email"), "silenciado decide antes");
  // um aviso só, o do urgente, com as mesmas travas: nenhum atalho pela regra
  assertEquals(fonte.split("await avisarUrgente(").length, 2, "um ponto de aviso só");
  const inicioDoAviso = bloco.indexOf('if (recente && t.classe === "urgent") {');
  assert(inicioDoAviso > 0, "o bloco do aviso de urgente");
  const aviso = bloco.slice(inicioDoAviso);
  const teto = aviso.indexOf("if (!cabeMaisUmAviso(");
  assert(teto > 0 && teto < aviso.indexOf("await jaAvisadoAntes(") && aviso.indexOf("await jaAvisadoAntes(") < aviso.indexOf("await avisarUrgente("),
    "teto, depois 'não repetir', depois o aviso");
  assertStringIncludes(aviso, "await avisarUrgente(admin, conta.address, remetente, email.subject, t.motivo, t.alertaFraude,");
  for (const atalho of ["deterministica", "golpe_pela_regra"]) assert(!aviso.includes(atalho), `o aviso não olha ${atalho}`);
  // quem recebe: só os admins com o canal ligado (app_users); o endereço do remetente só serve de chave no portão
  const f = fonte.indexOf("async function avisarUrgente(");
  const fn = fonte.slice(f, fonte.indexOf("\n}\n", f));
  assertStringIncludes(fn, 'await admin.from("app_users").select("phone_normalized")');
  assertStringIncludes(fn, "const telefones = ((quem ?? []) as { phone_normalized: string }[]).map((u) => u.phone_normalized);");
  assertEquals(fn.split('admin.from("whatsapp_send_queue")').length, 2, "uma escrita na fila, para os telefones lidos");
  for (const saida of ["email_outbox", "sendEmail", "smtp", "responder"]) assert(!fn.toLowerCase().includes(saida.toLowerCase()), `sem ${saida}`);
});

// Revisão do pacote 1 (24/11/2026). Três segundas vias de boleto de manhã gastavam os 3 avisos do dia, e o pedido real de
// troca de conta da tarde ficava urgente no banco, sem aviso e sem contador. O que se protege:
//   · só a regra FORTE (conta, chave Pix) conta como golpe pela regra; a de boleto fica notify e é só contada;
//   · o alerta da regra forte tem a própria cota do dia (cabeMaisUmAviso, digest_test.ts), lida só quando a regra casa;
//   · o que o teto segura fica contado em urgentes_barrados (não avisa, não marca alerted_at);
//   · a cota conta os alertas de hoje com a marca da regra e o alerta de fraude (sem vírgula no filtro).
Deno.test("Revisão F1: a regra forte tem cota própria, a de boleto não avisa, e o que o teto segura é contado", () => {
  assertStringIncludes(fonte, 'import { cabeMaisUmAviso } from "../_shared/email/digest.ts";');
  assert(!fonte.includes("MAX_URGENTES_PADRAO"), "o teto mora em cabeMaisUmAviso");
  const ini = fonte.indexOf("// Triagem só do que é recente");
  const bloco = fonte.slice(ini, fonte.indexOf("cursor = uid;", ini));
  // forte × boleto, decidido pelo que a triagem devolveu (nunca pelo texto do e-mail aqui)
  assertStringIncludes(bloco, "const daRegraDoGolpe = t.golpePelaRegra?.forte === true;");
  assertStringIncludes(bloco, "if (daRegraDoGolpe) r.golpe_pela_regra = Number(r.golpe_pela_regra ?? 0) + 1;");
  assertStringIncludes(bloco, "else if (t.golpePelaRegra) r.boleto_pela_regra = Number(r.boleto_pela_regra ?? 0) + 1;");
  // o aviso só nasce de urgente: a regra de boleto (notify) não chega ao bloco do aviso
  const aviso = bloco.slice(bloco.indexOf('if (recente && t.classe === "urgent") {'));
  assertStringIncludes(aviso, "if (daRegraDoGolpe) golpesDaRegraHoje ??= await golpesDaRegraAvisadosHoje(admin);");
  assertStringIncludes(aviso, "if (!cabeMaisUmAviso({ daRegraDoGolpe, avisados: jaAvisados, golpesDaRegra: golpesDaRegraHoje ?? 0 })) {");
  // barrado: só conta. O aviso, o alerted_at e as duas contas ficam no outro ramo.
  const barrado = aviso.indexOf("r.urgentes_barrados = Number(r.urgentes_barrados ?? 0) + 1;");
  const senao = aviso.indexOf("} else {", barrado);
  assert(barrado > 0 && senao > barrado, "o ramo do barrado vem antes do aviso");
  const ramoDoBarrado = aviso.slice(aviso.indexOf("if (!cabeMaisUmAviso("), senao);
  for (const proibido of ["avisarUrgente", "alerted_at", "jaAvisados++"]) assert(!ramoDoBarrado.includes(proibido), `barrado não faz ${proibido}`);
  const ramoDoAviso = aviso.slice(senao);
  assert(ramoDoAviso.indexOf("jaAvisados++;") > ramoDoAviso.indexOf("await avisarUrgente("), "conta depois de avisar");
  assertStringIncludes(ramoDoAviso, "if (daRegraDoGolpe) golpesDaRegraHoje = (golpesDaRegraHoje ?? 0) + 1;");
  // a cota nasce vazia e só é lida quando a regra casa (nenhuma leitura a mais por rodada)
  assertStringIncludes(fonte, "let golpesDaRegraHoje: number | null = null;");
  assertEquals(fonte.split("await golpesDaRegraAvisadosHoje(admin)").length, 2, "uma leitura só, dentro do bloco do aviso");
  // a conta de hoje: avisados (alerted_at) de hoje, com alerta de fraude e a marca da regra no motivo
  const f = fonte.indexOf("async function golpesDaRegraAvisadosHoje(");
  const fn = fonte.slice(f, fonte.indexOf("return count ?? 0;", f));
  assertStringIncludes(fn, '.gte("alerted_at", inicioDeHojeEmBrasilia()).eq("triage_fraud_alert", true).like("triage_reason", `%${MARCA_DA_REGRA_FIXA}%`);');
});

Deno.test("Fase 4: ?remessas=1 chama a releitura e responde 500 só com erro de leitura (o modo desligado é pulado)", () => {
  assertStringIncludes(fonte, 'if (new URL(req.url).searchParams.get("remessas") === "1") {');
  assertStringIncludes(fonte, "return jr({ ok: true, ...(await relerRemessas(admin, cnpjEmpresa)), ms: Date.now() - inicio });");
  assertStringIncludes(fonte, 'import { registrarRemessas, relerRemessas, temNotaParaEmpresa } from "./remessas.ts";');
});
