// O que cada fonte pede ao portão (secretário, Passo 4, 15/10/2026) — a tabela da spec §2 em código.
// O que se protege: o que a manhã já mostra acaba; papelada vai ao escritório; golpe e NF-e acordam;
// o certificado e o consentimento pela faixa de dias, com chave semanal; as decisões do dono (D1, D3,
// D5, D6) mudam o destino sem publicar código; todo aviso de sistema é o mesmo assunto; o acompanhamento
// leva a referência do freio (acomp:<id>:<última recebida>).
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  avisoDaNfe, avisoDaVoltaDoWhatsApp, avisoDoAcompanhamento, avisoDoCertificado, avisoDoConsentimento, avisoDoEmail, avisoDoLeadDoSite,
  avisoDosLembretesDeRevisao, avisoDosSaldos, avisoDoVigia, avisoResumoNaoChegou, DESTINO_DO_VIGIA, pedeHojeOuUrgente,
  referenciaDoAcompanhamento,
} from "./fontes.ts";
import { REGRAS_PADRAO } from "./portao.ts";

const DIA = "2026-10-21"; // quarta

Deno.test("vigia: vence hoje e orçamentos parados acabam; saldo/estoque/cota no escritório; NF-e acorda", () => {
  assertEquals(DESTINO_DO_VIGIA, {
    vence_hoje: "acaba", orcamentos_parados: "acaba", saldo_divergente: "escritorio", estoque_divergente: "escritorio",
    cota_fiscal: "escritorio", nfe_rejeitada: "acorde",
  });
  const s = avisoDoVigia("saldo_divergente", DIA, "texto", "conexao-1");
  assertEquals([s.chave, s.assunto, s.destino], ["saldo_divergente:conexao-1:2026-10-21", "saldo_divergente:conexao-1", "escritorio"]);
  const n = avisoDoVigia("nfe_rejeitada", DIA, "texto");
  assertEquals([n.chave, n.assunto, n.destino], ["nfe_rejeitada:2026-10-21", "fiscal:nfe_rejeitada", "acorde"]);
});

Deno.test("certificado: ≤ 7 dias acorda uma vez por validade; 8–30 dias vai à linha Hoje uma vez por semana", () => {
  const sete = avisoDoCertificado("2026-10-28", 7, DIA, "t");
  assertEquals([sete.chave, sete.destino], ["cert:2026-10-28:7d", "acorde"]);
  assertEquals(avisoDoCertificado("2026-10-28", 3, "2026-10-25", "t").chave, "cert:2026-10-28:7d", "a mesma chave nos dias seguintes = repetido");
  const vinte = avisoDoCertificado("2026-11-10", 20, DIA, "t");
  assertEquals([vinte.chave, vinte.destino], ["cert:2026-11-10:2026-10-19", "hoje"]);
  assertEquals(avisoDoCertificado("2026-11-10", 19, "2026-10-22", "t").chave, vinte.chave, "na mesma semana = repetido");
  assert(avisoDoCertificado("2026-10-20", -1, DIA, "t").destino === "acorde", "vencido acorda");
});

Deno.test("consentimento do banco: ≤ 7 dias na linha Hoje (todo dia); 8–30 no escritório (semana)", () => {
  assertEquals(avisoDoConsentimento("c1", 5, DIA, "t").destino, "hoje");
  assertEquals(avisoDoConsentimento("c1", 5, DIA, "t").chave, "consent:c1:2026-10-21");
  assertEquals(avisoDoConsentimento("c1", 20, DIA, "t").destino, "escritorio");
  assertEquals(avisoDoConsentimento("c1", 20, DIA, "t").chave, "consent:c1:2026-10-19");
});

Deno.test("sistema: a manhã que não chegou e a volta longa do WhatsApp são o MESMO assunto (um acorde por dia)", () => {
  const manha = avisoResumoNaoChegou(DIA, "t");
  const volta = avisoDaVoltaDoWhatsApp({ desde: "2026-10-21T05:45:00.000Z", ate: "2026-10-21T11:45:00.000Z" }, "t");
  // (20/10/2026) o motivo vai nos dados (a linha do guardado diz qual); a chave é a mesma (um aviso por dia, qualquer motivo)
  assertEquals(manha.dados, { motivo: "whatsapp_fora" });
  const quebrou = avisoResumoNaoChegou(DIA, "t", "erro_na_montagem");
  assertEquals([quebrou.chave, quebrou.assunto, quebrou.dados], [manha.chave, "sistema", { motivo: "erro_na_montagem" }]);
  assertEquals(manha.assunto, "sistema");
  assertEquals(volta.assunto, "sistema");
  assertEquals([manha.destino, volta.destino], ["acorde", "acorde"]);
  assertEquals(volta.dados?.minutos_fora, 360);
  // queda curta (menos de 30 min): fica só no sino
  assertEquals(avisoDaVoltaDoWhatsApp({ desde: "2026-10-21T15:00:00.000Z", ate: "2026-10-21T15:20:00.000Z" }, "t").destino, "acaba");
  assertEquals(avisoDaVoltaDoWhatsApp({ desde: "2026-10-21T15:00:00.000Z", ate: "2026-10-21T15:30:00.000Z" }, "t").destino, "acorde");
});

Deno.test("saldos a cobrar acabam (a manhã cobre); lembretes de revisão ficam como estão", () => {
  assertEquals(avisoDosSaldos(DIA, 3, "t").destino, "acaba");
  assertEquals(avisoDosLembretesDeRevisao(DIA, 2, "t").destino, "deixar");
});

Deno.test("e-mail: golpe acorda por remetente (para sempre); sem golpe segue D1 (padrão: próxima fixa)", () => {
  const golpe = avisoDoEmail({ emailId: "e1", endereco: "Atendimento@Envios.ADV", fraude: true }, REGRAS_PADRAO, "t");
  assertEquals([golpe.chave, golpe.assunto, golpe.destino], ["golpe:atendimento@envios.adv", "golpe:atendimento@envios.adv", "acorde"]);
  // o mesmo golpe no dia seguinte, outro e-mail: mesma chave (repetido)
  assertEquals(avisoDoEmail({ emailId: "e2", endereco: "atendimento@envios.adv", fraude: true }, REGRAS_PADRAO, "t").chave, golpe.chave);
  const urgente = avisoDoEmail({ emailId: "e3", endereco: "cliente@x.com", fraude: false }, REGRAS_PADRAO, "t");
  assertEquals([urgente.chave, urgente.destino], ["email:e3", "proxima_fixa"]);
  assertEquals(avisoDoEmail({ emailId: "e3", endereco: "cliente@x.com", fraude: false }, { email_sem_golpe: "acorde" }, "t").destino, "acorde", "D1 trocada");
});

Deno.test("lead do site: próxima fixa (D6), salvo se pede hoje/urgente", () => {
  const calmo = avisoDoLeadDoSite({ phone: "5547999990000", dia: DIA, mensagem: "Energia: lítio e solar" }, REGRAS_PADRAO, "t");
  assertEquals([calmo.chave, calmo.assunto, calmo.destino], ["lead_site:5547999990000:2026-10-21", "contato:5547999990000", "proxima_fixa"]);
  assertEquals(avisoDoLeadDoSite({ phone: "5547999990000", dia: DIA, mensagem: "Preciso URGENTE, o barco não liga" }, REGRAS_PADRAO, "t").destino, "acorde");
  assertEquals(avisoDoLeadDoSite({ phone: "5547999990000", dia: DIA, mensagem: null }, { lead_site: "acorde" }, "t").destino, "acorde", "D6 trocada");
  assert(pedeHojeOuUrgente("consegue vir hoje?"));
  assert(pedeHojeOuUrgente("é urgência"));
  assert(!pedeHojeOuUrgente("hojeiro"), "palavra inteira");
  assert(!pedeHojeOuUrgente("quero orientação"));
});

Deno.test("acompanhamento: acorde com a referência do freio; promessa D5; lembrete pedido fica de fora (D3)", () => {
  const a = { id: "a1", phone_normalized: "351966776422", modo: "acompanhar" as const };
  const ultima = "2026-10-07T17:58:00.000Z";
  const aviso = avisoDoAcompanhamento(a, ultima, 2, REGRAS_PADRAO, "t");
  assertEquals(aviso.referencia, referenciaDoAcompanhamento("a1", ultima));
  assertEquals(aviso.referencia, "acomp:a1:2026-10-07T17:58:00.000Z");
  assertEquals(aviso.chave, "acomp:a1:2026-10-07T17:58:00.000Z:2");
  assertEquals([aviso.fonte, aviso.assunto, aviso.destino], ["acompanhar", "contato:351966776422", "acorde"]);
  assertEquals(avisoDoAcompanhamento(a, ultima, 1, { ...REGRAS_PADRAO, acompanhar_conta_no_limite: false }, "t").destino, "deixar", "D3 trocada");
  const p = avisoDoAcompanhamento({ ...a, modo: "promessa" }, null, 1, REGRAS_PADRAO, "t");
  assertEquals([p.fonte, p.chave, p.destino], ["promessa", "promessa:a1", "proxima_fixa"]);
  const l = avisoDoAcompanhamento({ ...a, modo: "lembrar_em" }, null, 1, REGRAS_PADRAO, "t");
  assertEquals([l.fonte, l.chave, l.destino], ["lembrete_pedido", "lembrete:a1", "deixar"]);
  assertEquals(referenciaDoAcompanhamento("a1", null), "acomp:a1:sem_mensagem");
});

// (16/10/2026) D11 e os dados que a manhã/o fechamento usam para escrever a linha do guardado.
Deno.test("acompanhamento (16/10): novo_fato só quando quem chama diz (D11); nome e mensagem nos dados", () => {
  const a = { id: "a1", phone_normalized: "351966776422", modo: "acompanhar" as const, contato: "Miguel" };
  const ultima = "2026-10-07T12:02:00Z";
  const velho = avisoDoAcompanhamento(a, ultima, 1, REGRAS_PADRAO, "t");
  assertEquals(velho.novo_fato, false, "sem o 6º argumento = como antes");
  assertEquals(velho.dados, { n: 1, contato: "Miguel", mensagem_em: "2026-10-07T12:02:00.000Z" });
  assertEquals(avisoDoAcompanhamento(a, ultima, 1, REGRAS_PADRAO, "t", true).novo_fato, true);
  const p = avisoDoAcompanhamento({ ...a, modo: "promessa", promessa: "Claro, te passo agora!", created_at: "2026-10-14T12:45:10Z" }, null, 1, REGRAS_PADRAO, "t");
  assertEquals(p.dados, { contato: "Miguel", promessa: "Claro, te passo agora!", mensagem_em: "2026-10-14T12:45:10.000Z" });
  assertEquals(p.novo_fato, undefined, "promessa não usa novo_fato");
});

Deno.test("NF-e rejeitada (16/10): um aviso por nota, acorda uma vez (chave nfe:<id>)", () => {
  const n = avisoDaNfe({ id: "nota-1", numero: 123, cliente: "MP MOTOR HOMES" }, "t");
  assertEquals([n.chave, n.assunto, n.destino, n.referencia], ["nfe:nota-1", "fiscal:nfe_rejeitada", "acorde", "nfe:nota-1"]);
  assertEquals(n.dados, { sinal: "nfe_rejeitada", nota_id: "nota-1", numero: "123", cliente: "MP MOTOR HOMES" });
});
