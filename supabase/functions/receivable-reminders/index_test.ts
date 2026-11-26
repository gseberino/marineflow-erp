// A rotina do lembrete antes do vencimento (dono, 26/11/2026: "2. A"), pelo texto da fonte (importar index.ts subiria o
// servidor da função). O que se protege: a rotina NÃO manda mais nada ao cliente (só pergunta ao dono); antes das 09:30
// volta sem ler o banco (janela da manhã); o dia útil e o interruptor valem; com a voz única, o registro no portão vem
// depois de perguntar; o cabeçalho aponta a migration do horário.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("nada vai ao cliente: a rotina não chama o whatsapp-send nem o envio antigo", () => {
  assertEquals(fonte.includes("whatsapp-send"), false);
  assertEquals(fonte.includes("enviarLembrete"), false);
  assertEquals(fonte.includes('origem: "sistema"'), false);
  assertStringIncludes(fonte, "const ids = await pedirSimAoDono(");
});

Deno.test("antes das 09:30 a rodada volta (fora_da_janela) antes de criar o cliente do banco; dry passa", () => {
  const guarda = fonte.indexOf("if (!dry && !depoisDaJanelaDaManha(agora)) return jr({ ok: true, fora_da_janela: true });");
  assert(guarda > 0, "falta a guarda da janela da manhã");
  assert(guarda < fonte.indexOf("const admin = createClient("), "a guarda vem antes de qualquer leitura");
});

Deno.test("interruptor, modo de teste sem número e dia útil antes de propor", () => {
  const propor = fonte.indexOf("await proporLembretesDeVencimento(");
  for (const trecho of ["if (!ligado(settings.lembrete_vencimento_ativo))", "if (modoDeTesteSemNumero(settings))", 'admin.rpc("agenda_dia_util"']) {
    const i = fonte.indexOf(trecho);
    assert(i > 0 && i < propor, trecho);
  }
});

Deno.test("uma pergunta por vez: dono ocupado adia antes de criar pendência", () => {
  const ocupado = fonte.indexOf("if (ocupado.ocupado)");
  assert(ocupado > 0 && ocupado < fonte.indexOf("const ids = await pedirSimAoDono("));
});

Deno.test("voz única: o registro no portão vem depois de perguntar ao dono, com o modo das configurações", () => {
  const perguntou = fonte.indexOf("const ids = await pedirSimAoDono(");
  const registro = fonte.indexOf("await registrarNoPortao(admin, portaoDasConfiguracoes(settings).modo");
  assert(perguntou > 0 && registro > perguntou, "registra depois de perguntar");
  assertStringIncludes(fonte, "avisoDosLembretesDeVencimento(hoje, agora, ids.length");
});

Deno.test("o cabeçalho diz 10:40 e 15:40 e aponta a migration do cron", () => {
  assertStringIncludes(fonte, "às 10:40 e às 15:40 de Brasília");
  assertStringIncludes(fonte, "20270302100000");
});
