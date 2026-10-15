// O resumo da manhã com resumo_formato = 'antigo' (o padrão) sai como antes — pelo texto da fonte
// (importar index.ts subiria o servidor da função). O que se protege (secretário, Passo 2, 15/10/2026):
// nada do secretário roda com 'antigo'; o texto enviado e o do histórico só trocam com 'novo' e com o dia
// GRAVADO; a sombra grava depois do envio e nunca muda o que sai.
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

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
