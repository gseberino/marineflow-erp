// Lembretes de revisão (secretário, Passo 4, 15/10/2026): pelo texto da fonte (importar index.ts subiria
// o servidor da função). O que se protege: das 07:30 às 09:30 só a manhã pergunta — a rodada (sem dry)
// volta antes das 09:30 SEM ler o banco; o ?dry=1 roda a qualquer hora; com a voz única em sombra, a
// rodada que perguntou é registrada no portão DEPOIS de perguntar (desligada: registrarNoPortao recebe
// modo null e não chama nada — registrar_test.ts).
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("antes das 09:30 a rodada volta (fora_da_janela) antes de criar o cliente do banco; dry passa", () => {
  const guarda = fonte.indexOf("if (!dry && !depoisDaJanelaDaManha(agora)) return jr({ ok: true, fora_da_janela: true });");
  assert(guarda > 0, "falta a guarda da janela da manhã");
  assert(guarda < fonte.indexOf("const admin = createClient("), "a guarda vem antes de qualquer leitura");
  assert(guarda > fonte.indexOf("if (!dry && !ehTerAQui(hoje))"), "depois da guarda do dia da semana");
});

Deno.test("o cabeçalho diz 09:35 e aponta a migration do cron", () => {
  assertStringIncludes(fonte, "às 09:35 de Brasília, terça a quinta");
  assertStringIncludes(fonte, "20261016100100");
});

Deno.test("voz única: o registro no portão vem depois de perguntar ao dono, com o modo das configurações", () => {
  const perguntou = fonte.indexOf("const ids = await proporAoDono(");
  const registro = fonte.indexOf("await registrarNoPortao(admin, portaoDasConfiguracoes(settings).modo");
  assert(perguntou > 0 && registro > perguntou, "registra depois de perguntar");
  assertStringIncludes(fonte, "avisoDosLembretesDeRevisao(hoje, ids.length");
});
