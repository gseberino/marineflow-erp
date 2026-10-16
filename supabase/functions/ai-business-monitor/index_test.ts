// Vigia do negócio (15/10/2026): pelo texto da fonte (importar index.ts subiria o servidor da
// função). O que se protege: o horário é checado ANTES de qualquer reivindicação de chave (senão a
// chave do dia se gastaria à noite e o aviso não sairia de manhã); nenhuma conta de dia em UTC; o
// resumo entregue segura o aviso de orçamentos parados; o "resumo não chegou" para às 20h.
import { assert, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("fora das 8h–20h volta antes de ler o banco e de reivindicar qualquer chave", () => {
  const corte = fonte.indexOf("if (!podeAvisarAgora(now))");
  assert(corte > 0, "falta o corte de horário");
  assert(corte < fonte.indexOf("await claim("), "o corte vem antes do primeiro claim");
  assert(corte < fonte.indexOf('.from("app_settings")'), "o corte vem antes da primeira leitura");
});

Deno.test("o dia e o mês são os de Brasília (nada de toISOString().slice(0, 10) nem new Date(ano, mês, 1))", () => {
  assert(!fonte.includes("toISOString().slice(0, 10)"), "dia UTC");
  assert(!fonte.includes("now.getFullYear()"), "mês pelo relógio do servidor");
  assertStringIncludes(fonte, "const todayISO = diaDoAviso(now)");
  assertStringIncludes(fonte, "const monthStart = inicioDoMesBR(now)");
});

Deno.test("orçamentos parados: só reivindica a chave quando o resumo de hoje não cobre", () => {
  const bloco = fonte.slice(fonte.indexOf("// (2) Orçamentos parados"), fonte.indexOf("// ── Sinais FISCAIS"));
  assertStringIncludes(bloco, "!resumoDeHojeCobre(resumosDeHoje)");
  assert(bloco.indexOf("!resumoDeHojeCobre(resumosDeHoje)") < bloco.indexOf("claim(`stale_quotes:"), "o resumo é conferido antes do claim");
});

Deno.test("resumo que não chegou: chave por telefone e dia, fila com tentativas até as 20h", () => {
  assertStringIncludes(fonte, "claim(`resumo_nao_chegou:${phone}:${todayISO}`");
  assertStringIncludes(fonte, 'source: "resumo_nao_chegou"');
  assertStringIncludes(fonte, "max_attempts: tentativasAteAs20h(now)");
});

// Voz única (secretário, Passo 4, 15/10/2026). O que se protege: cada sinal que sai leva o pedido ao
// portão junto (alertar), o registro só acontece DEPOIS que o alerta entrou na fila, e o "resumo não
// chegou" registra depois do insert dele. Desligado: registrarParaTodos/registrarNoPortao recebem modo
// null e não chamam nada (registrar_test.ts) — o que sai é o mesmo de antes.
Deno.test("voz única: todo sinal passa por alertar (texto + pedido ao portão), sem alerts.push solto", () => {
  const usos = fonte.split("alertar(t, ").length - 1;
  assert(usos === 8, `8 sinais com pedido ao portão (achei ${usos})`);
  assert(fonte.split("alerts.push(").length - 1 === 1, "o único alerts.push é o de dentro de alertar");
});

Deno.test("voz única: o registro dos sinais vem depois da fila; o do resumo que não chegou depois do insert dele", () => {
  const fila = fonte.indexOf('await admin.from("whatsapp_send_queue").insert(rows).select("id")');
  const erro = fonte.indexOf("if (qErr) throw qErr;");
  const registro = fonte.indexOf("await registrarParaTodos(admin, portao.modo");
  assert(fila > 0 && erro > fila && registro > erro, "fila → erro → registro");
  const resumo = fonte.indexOf("if (nErr) throw nErr;");
  const registroResumo = fonte.indexOf("await registrarNoPortao(admin, portao.modo, phone, avisoResumoNaoChegou(");
  assert(resumo > 0 && registroResumo > resumo, "o resumo que não chegou registra depois do insert");
  assert(fonte.indexOf("const portao = await lerPortao(admin)") > fonte.indexOf("if (!podeAvisarAgora(now))"), "as chaves só são lidas dentro do horário");
});

// (16/10/2026, P4.2) O que se protege: a mensagem que sai para a equipe NÃO muda (a contagem de NF-e do dia e o texto
// do certificado continuam os de sempre); só o registro no portão muda — o acorde do certificado de 7 dias ou menos e
// uma NF-e por nota. Com a voz única desligada nada a mais é lido (a leitura das notas fica atrás de portao.modo).
Deno.test("P4.2: NF-e por nota só com portao.modo; o texto da fila não muda; certificado ≤ 7 dias com o texto do acorde", () => {
  assertStringIncludes(fonte, "const porNota = portao.modo ? await avisosDasNotasRejeitadas(admin, d1) : null;");
  assertStringIncludes(fonte, 'alertar(t, ...(porNota && porNota.length ? porNota : [avisoDoVigia("nfe_rejeitada", todayISO, t)]));');
  assertStringIncludes(fonte, "const t = `❌ *${rejectedNfe}* NF-e rejeitada(s) nas últimas 24h. Confira o motivo no histórico e reemita.`;");
  assertStringIncludes(fonte, "alertar(t, avisoDoCertificado(String(vu), days, todayISO, days <= 7 ? textoDoCertificado(days, String(vu)) : t));");
  const ini = fonte.indexOf("async function avisosDasNotasRejeitadas(");
  const fn = fonte.slice(ini, fonte.indexOf("servirComCors(", ini));
  assert(!/\.(insert|update|upsert|delete)\(/.test(fn), "a leitura das notas só lê");
});
