// O resumo da manhã com resumo_formato = 'antigo' (o padrão) sai como antes — pelo texto da fonte
// (importar index.ts subiria o servidor da função). O que se protege (secretário, Passo 2, 15/10/2026):
// nada do secretário roda com 'antigo'; o texto enviado e o do histórico só trocam com 'novo' e com o dia
// GRAVADO; a sombra grava depois do envio e nunca muda o que sai.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

function bloco(de: string, ate: string): string {
  const i = fonte.indexOf(de);
  const j = fonte.indexOf(ate, i + de.length);
  assert(i >= 0 && j > i, `bloco "${de}" … "${ate}" não achado`);
  return fonte.slice(i, j);
}

Deno.test("a chave é lida no mesmo SELECT de app_settings; ausente/'antigo' = antigo", () => {
  assertStringIncludes(fonte, '.in("key", ["company_name", "digest_show_low_stock", "quote_validity_days", "resumo_formato"])');
  assertStringIncludes(fonte, 'lerFormatoDoResumo((ehDry ? new URL(req.url).searchParams.get("formato") : null) ?? cfg["resumo_formato"])');
});

Deno.test("com 'antigo' nada do secretário roda: montar e gravar só dentro dos ramos sombra/novo", () => {
  const ramo = bloco('if (formato !== "antigo") {', "// Dry-run (?dry=1)");
  assertStringIncludes(ramo, "montarManhaNova(admin");
  assertStringIncludes(ramo, "donoDoWhatsApp(admin)");
  // fora do ramo, nenhuma chamada de montar/dono
  const semRamo = fonte.replace(ramo, "");
  assert(!semRamo.includes("montarManhaNova(admin"), "montarManhaNova fora do ramo");
  assert(!semRamo.includes("donoDoWhatsApp(admin)"), "donoDoWhatsApp fora do ramo");
  // gravar: só com manhaNova (que só existe fora de 'antigo') e no modo certo
  assertStringIncludes(fonte, 'if (manhaNova && donoDaManha && formato === "novo") {');
  assertStringIncludes(fonte, 'if (manhaNova && donoDaManha && formato === "sombra") {');
  assert((fonte.match(/registrarManha\(admin/g) ?? []).length === 2, "registrarManha só nos dois ramos");
});

Deno.test("o texto de cada destinatário só troca com o dia novo GRAVADO e para o dono", () => {
  assertStringIncludes(fonte, "textoNovoDoDono && donoDaManha && rec?.id === donoDaManha.id ? textoNovoDoDono : messageFor(rec)");
  assertStringIncludes(fonte, "textoNovoDoDono = r.ok ? r.texto : null;");
  // a fila e o histórico usam o mesmo texto
  assertStringIncludes(bloco("const rows = recipients.map(", "}));"), "message: textoPara(rec)");
  assertStringIncludes(fonte, "linhasDoHistorico(sessao, textoPara(rec), agoraHist)");
  // a sombra grava DEPOIS de enfileirar o de sempre
  assert(fonte.indexOf('formato === "sombra"') > fonte.indexOf('from("whatsapp_send_queue").insert(rows)'), "sombra depois do envio");
  assert(fonte.indexOf('formato === "novo") {') < fonte.indexOf('from("whatsapp_send_queue").insert(rows)'), "novo grava antes do envio");
});

Deno.test("dry-run: com 'antigo' a resposta é a de antes (os campos novos só com a manhã montada)", () => {
  const dry = bloco("if (ehDry) {", "// 'novo': grava ANTES");
  assertStringIncludes(dry, "ok: true, dry: true, recipients: recipients.length, preview: messageFor(recipients[0] || {}),");
  assertStringIncludes(dry, "...(manhaNova");
  assertStringIncludes(dry, ": {}),");
});

Deno.test("a montagem antiga não mudou de lugar: o resumo de sempre é montado antes do ramo novo", () => {
  assert(fonte.indexOf('const message = linhas.join("\\n");') < fonte.indexOf('if (formato !== "antigo") {'));
  assert(fonte.indexOf("const messageFor = (rec: any) => {") < fonte.indexOf('if (formato !== "antigo") {'));
});

// Passo 3 (15/10/2026): o turno da tarde é um ramo que SÓ existe com ?turno= na URL. O cron das 07:30 chama sem
// o parâmetro: o ramo não roda e nada do resumo da manhã muda (o git diff do index.ts só tem linhas novas).
Deno.test("a tarde só roda com ?turno=, logo depois do createClient e antes de qualquer leitura da manhã", () => {
  const ramo = bloco('const turnoDaUrl = new URL(req.url).searchParams.get("turno");', 'const { data: cfgRows } = await admin');
  assertStringIncludes(ramo, "if (turnoDaUrl !== null) {");
  assertStringIncludes(ramo, "rodarTurnoDaTarde(admin, { agora: new Date(), pedido: turnoDaUrl,");
  assertStringIncludes(ramo, "return jr(tarde.corpo, tarde.status);");
  // o ramo vem logo depois do createClient (nenhuma leitura antes dele)
  const criar = fonte.indexOf("const admin = createClient(");
  const entre = fonte.slice(criar, fonte.indexOf('const turnoDaUrl = new URL(req.url).searchParams.get("turno");'));
  assert(!entre.includes("await "), "nada é lido antes do ramo da tarde");
  // a tarde não é chamada em nenhum outro lugar
  assertEquals((fonte.match(/rodarTurnoDaTarde\(/g) ?? []).length, 1);
  // e a manhã segue igual depois do ramo: o mesmo SELECT de app_settings
  assert(fonte.indexOf("if (turnoDaUrl !== null) {") < fonte.indexOf('.in("key", ["company_name", "digest_show_low_stock", "quote_validity_days", "resumo_formato"])'));
});

// (16/10/2026) O guardado do portão na manhã: só a manhã-SOMBRA o marca (ela não sai: "incluido", nunca "entregue"), e
// só depois de gravada. O ramo 'novo' e o 'antigo' não o chamam (com a voz única em sombra as fontes já avisaram o dono).
Deno.test("guardado na manhã: só no ramo sombra, depois de registrarManha; nenhum outro lugar", () => {
  const sombra = bloco('if (manhaNova && donoDaManha && formato === "sombra") {', "// O resumo entra no histórico");
  assertStringIncludes(sombra, "const gravada = await registrarManha(admin");
  assertStringIncludes(sombra, "if (gravada.ok) guardadoNaSombra = await marcarGuardadoDaManha(admin, { dono: donoDaManha, manha: manhaNova, novo: gravada.novo });");
  assert(sombra.indexOf("registrarManha(") < sombra.indexOf("marcarGuardadoDaManha("));
  assertEquals((fonte.match(/marcarGuardadoDaManha\(admin/g) ?? []).length, 1);
});
